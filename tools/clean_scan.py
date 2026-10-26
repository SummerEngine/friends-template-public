#!/usr/bin/env python3
"""Forbidden-string scan of a build and of the repository tree.

    tools/clean_scan.py --bundle build/<name>.summer.zip      # client.pck + server.pck + config inside the bundle
    tools/clean_scan.py --pck client.pck --pck server.pck
    tools/clean_scan.py --tree .                              # every tracked or untracked-but-not-ignored file of the checkout
    tools/clean_scan.py --bundle B --tree .                   # both; exit status 1 when anything matches

Matching is case-insensitive unless a pattern says otherwise. In a pack, script entries (compressed binary tokens) are decompressed first
(needs the `zstd` command), text and resource entries are scanned as bytes, and every entry path is scanned too. Binary media
(images, audio, fonts, compressed textures, meshes) are skipped: random bytes would only produce false hits.
Words are not listed in plain text: the scan lower-cases the text, splits it into letter/digit tokens and compares salted SHA-256
fingerprints of tokens, of runs of up to 4 tokens written together, and of token beginnings with the fingerprints below. A few generic
code-naming rules stay plain patterns, assembled from fragments so that this file does not match itself.
"""
import argparse
import hashlib
import re
import struct
import subprocess
import sys
import zipfile
from pathlib import Path


def _p(*parts, flags=re.I):
    return re.compile("".join(parts).encode(), flags)


# Plain patterns for generic code-naming conventions (case-sensitive). The rule ids are numbers on purpose.
PATTERNS = [
    ("rule 05", _p(r"/G", r"ame/(?=[A-Z])", flags=0)),
    ("rule 07", _p(r"(?<![A-Za-z])b", r"p[A-Z][a-z]", flags=0)),
    ("rule 08", _p(r"(?<![A-Za-z])M", r"M_[A-Za-z]", flags=0)),
    ("rule 26", _p(r"(?<![A-Za-z0-9])K", r"2_[A-Z]", flags=0)),
    ("rule 27", _p(r"(?<![a-z])sou", r"rce_(?!color|graph|file=\"res://)[a-z]")),
    ("rule 28", _p(r"(?<![A-Za-z])Sou", r"rce[A-Z][a-z]", flags=0)),
]

# Fingerprinted words: {length: {fingerprint: rule}}. JOINED matches a token or up to 4 consecutive tokens written together
# ("a_b_c", "a b c", "ABC" all give "abc"); PREFIX matches the beginning of one token.
SALT = b"friends-template clean scan v1\0"
MAX_JOIN = 4
JOIN_MIN = 3
BINARY_MIN = 4
JOINED = {
    3: {"52e3423ef0400c73": "rule 01", "58f7690b2ada2c62": "rule 10", "9a23482e0204cba5": "rule 10", "f4c2c3480acc1939": "rule 18"},
    4: {"1af5df275ba8639c": "rule 04"},
    5: {"ced409d6ec89aa6e": "rule 11"},
    6: {"759d3792b3aae645": "rule 24", "806381c2d4540481": "rule 21", "98a1a148dc1db87e": "rule 26", "b91c7ed49bac56b2": "rule 04", "d375c5ede212f847": "rule 09", "f269f7690a74c31a": "rule 25"},
    8: {"a582d0d94a559063": "rule 19"},
    9: {"7e9f3a8a539f7728": "rule 12", "f4d070e55c81a479": "rule 29"},
    10: {"c79c584e84521041": "rule 14", "f9390c7032b4157b": "rule 02"},
    12: {"1172d6e64955c440": "rule 03", "7668aa13dcea1184": "rule 15"},
    13: {"2de0890b3e889321": "rule 02", "30ed18d8fa5beebb": "rule 17", "af229699587b7f11": "rule 03"},
    14: {"b453149bcad03389": "rule 30", "d4cb7c5693cc9b07": "rule 30"},
    15: {"097db6872cfe8c95": "rule 30"},
    17: {"07a30ef339efcf98": "rule 16"},
}
PREFIX = {
    4: {"3af590672c721da4": "rule 13"},
    8: {"f5c2bd347ec8f27a": "rule 22"},
    9: {"11eb973e1fa12d7f": "rule 06", "3fdd29e51b71fd3c": "rule 20"},
    11: {"e4ab8002af64a475": "rule 23"},
}
TOKEN = re.compile(rb"[a-z0-9]+")
# Rules whose words are ordinary English: they find engine and asset naming in code and art, not what people write. The team's own
# text (cast.json: demo/cast/cast.json in the tree, cast/cast.json in a pack) may use them; every other rule still applies to it.
CAST_TEXT_OK = {"rule 06", "rule 09", "rule 11", "rule 21", "rule 23", "rule 24", "rule 25", "rule 26"}


def is_cast_text(name):
    return name.replace("\\", "/").removeprefix("res://").endswith("cast/cast.json")


def fingerprint(text):
    return hashlib.sha256(SALT + text).hexdigest()[:16]


def word_hits(data, binary=False):
    """(rule, start, end) of every fingerprinted word in `data` (bytes). Runs of tokens are joined only from tokens of at least
    JOIN_MIN letters, so noise such as "h*ff" never forms a word. In `binary` text (printable runs of compiled resource files) a single
    token must also be at least BINARY_MIN letters long: short words turn up in random bytes."""
    found = []
    tokens = [(m.start(), m.end(), m.group()) for m in TOKEN.finditer(data.lower())]
    longest = max(JOINED)
    for i, (start, end, token) in enumerate(tokens):
        for length, table in PREFIX.items():
            if len(token) >= length:
                rule = table.get(fingerprint(token[:length]))
                if rule:
                    found.append((rule, start, end))
        joined = b""
        for j in range(i, min(i + MAX_JOIN, len(tokens))):
            part = tokens[j][2]
            if j > i and (len(part) < JOIN_MIN or len(tokens[i][2]) < JOIN_MIN):
                break
            joined += part
            if len(joined) > longest:
                break
            if binary and j == i and len(joined) < BINARY_MIN:
                continue
            table = JOINED.get(len(joined))
            if table:
                rule = table.get(fingerprint(joined))
                if rule:
                    found.append((rule, start, tokens[j][1]))
    return found


# Entry types whose bytes are text or structured resources worth scanning.
TEXT_SUFFIXES = {".gd", ".gdc", ".tscn", ".scn", ".tres", ".res", ".json", ".cfg", ".godot", ".gdshader", ".gdshaderinc", ".shader", ".import",
                 ".remap", ".md", ".txt", ".uid", ".translation", ".csv", ".sh", ".py", ".mjs", ".gltf", ".command", ".plist", ".yml", ".yaml", ".toml", ""}
BINARY_SUFFIXES = {".gdc", ".scn", ".res", ".translation"}
SKIP_DIRS = {".git", ".godot", "__pycache__", ".summer", "node_modules"}
MAX_REPORT = 60


PRINTABLE = re.compile(rb"[\x20-\x7e\t\r\n]{5,}")


def scan_bytes(data, where, hits, strings_only=False, cast_text=False):
    """`strings_only`: binary container (tokens, resources): scan its printable runs, not the raw numbers. `cast_text`: the team's
    own text (cast.json), where the ordinary-English rules (CAST_TEXT_OK) do not apply."""
    if strings_only:
        data = b"\n".join(PRINTABLE.findall(data))
    found = [(label, m.start(), m.end()) for label, pattern in PATTERNS for m in [pattern.search(data)] if m]
    words = [hit for hit in word_hits(data, binary=strings_only) if not (cast_text and hit[0] in CAST_TEXT_OK)]
    seen = set()
    for label, start, end in found + words:
        if label in seen:
            continue
        seen.add(label)
        context = data[max(start - 24, 0):end + 24].decode("utf-8", "replace").replace("\n", " ")
        hits.append((where, label, context))


def scan_name(name, where, hits):
    scan_bytes(name.encode(), where + " [path]", hits)


def inflate_script(data):
    """Compressed binary tokens: 'GDSC', version u32, decompressed size u32 (0 = stored), then a zstd frame."""
    if data[:4] != b"GDSC" or len(data) < 12:
        return data
    size, = struct.unpack_from("<I", data, 8)
    if size == 0:
        return data[12:]
    result = subprocess.run(["zstd", "-dc"], input=data[12:], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return result.stdout if result.returncode == 0 else data


def pack_entries(data):
    if len(data) < 112 or data[:4] != b"GDPC":
        raise ValueError("not a Godot PCK")
    flags, = struct.unpack_from("<I", data, 20)
    if flags & 1:
        raise ValueError("encrypted PCK directory is unsupported")
    file_base, directory = struct.unpack_from("<QQ", data, 24)
    count, = struct.unpack_from("<I", data, directory)
    cursor = directory + 4
    entries = []
    for _ in range(count):
        length, = struct.unpack_from("<I", data, cursor)
        cursor += 4
        name = data[cursor:cursor + length].rstrip(b"\0").decode("utf-8", "replace")
        cursor += length
        offset, size = struct.unpack_from("<QQ", data, cursor)
        cursor += 36
        entries.append((name, file_base + offset, size))
    return entries


def scan_pack(data, where, hits):
    entries = pack_entries(data)
    for name, offset, size in entries:
        scan_name(name, f"{where}:{name}", hits)
        suffix = Path(name).suffix.lower()
        if suffix not in TEXT_SUFFIXES:
            continue
        body = data[offset:offset + size]
        if suffix == ".gdc":
            body = inflate_script(body)
        scan_bytes(body, f"{where}:{name}", hits, strings_only=suffix in BINARY_SUFFIXES, cast_text=is_cast_text(name))
    return len(entries)


def scan_bundle(path, hits):
    with zipfile.ZipFile(path) as archive:
        for name in archive.namelist():
            scan_name(name, f"{path.name}!{name}", hits)
            data = archive.read(name)
            if name.endswith(".pck"):
                count = scan_pack(data, f"{path.name}!{name}", hits)
                print(f"scanned {name}: {count} entries")
            else:
                scan_bytes(data, f"{path.name}!{name}", hits)


def tracked_files(root):
    result = subprocess.run(["git", "-C", str(root), "ls-files", "-co", "--exclude-standard", "-z"], stdout=subprocess.PIPE, check=True)
    return [p for p in result.stdout.decode().split("\0") if p]


def scan_tree(root, hits):
    count = 0
    for relative in tracked_files(root):
        path = root / relative
        if not path.is_file() or any(part in SKIP_DIRS for part in path.parts):
            continue
        scan_name(relative, relative, hits)
        if path.suffix.lower() in TEXT_SUFFIXES:
            scan_bytes(path.read_bytes(), relative, hits, cast_text=relative == "demo/cast/cast.json")
        count += 1
    print(f"scanned tree {root}: {count} files")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--bundle", type=Path, action="append", default=[], help="hosted bundle zip")
    parser.add_argument("--pck", type=Path, action="append", default=[], help="one pack file")
    parser.add_argument("--tree", type=Path, action="append", default=[], help="git checkout to scan (tracked and untracked, not ignored)")
    args = parser.parse_args()
    if not (args.bundle or args.pck or args.tree):
        parser.error("give --bundle, --pck or --tree")
    hits = []
    for bundle in args.bundle:
        scan_bundle(bundle, hits)
    for pack in args.pck:
        count = scan_pack(pack.read_bytes(), pack.name, hits)
        print(f"scanned {pack.name}: {count} entries")
    for tree in args.tree:
        scan_tree(tree.resolve(), hits)
    if hits:
        print(f"FORBIDDEN STRINGS: {len(hits)} hit(s)")
        for where, label, context in hits[:MAX_REPORT]:
            print(f"  {where}: {label}: ...{context}...")
        if len(hits) > MAX_REPORT:
            print(f"  ... {len(hits) - MAX_REPORT} more")
        return 1
    print("clean_scan: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
