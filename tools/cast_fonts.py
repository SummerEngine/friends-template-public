#!/usr/bin/env python3
"""Japanese and Chinese letters for the cast: `python3 tools/cast_fonts.py`.

The game's fonts (Inter, Archivo) draw Latin letters only. When demo/cast/cast.json has Japanese or Chinese text (names,
titles, signs, words, the reveal line), this cuts exactly the letters the cast uses out of Noto Sans JP and Noto Sans SC
(SIL OFL 1.1, from github.com/google/fonts at the commit pinned below), bold (wght 800), and writes demo/cast/fonts/:
  fallback_1.ttf, fallback_2.ttf   the letters; the game hangs them behind its own fonts (TeamCast.use_fonts)
  fallback.txt                     every letter they draw (tools/cast_check.py accepts exactly these)
  noto-OFL.txt                     the fonts' licence
Text with kana takes the Japanese letter forms first, other text the Chinese (simplified) ones. A cast without such text
gets no demo/cast/fonts/. Run it after every change to the cast's text; tools/ship.py runs it first.
Needs fontTools (`pip install fonttools`) only when the cast has such text. The source fonts are downloaded once into
$FRIENDS_FONT_CACHE (default tools/.font-cache/, ignored by git) and checked against their SHA-256.
The last line is `cast_fonts: ok (<n> letters)` or `cast_fonts: FAILED: <why>`.
"""
import hashlib
import json
import os
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CAST_FILE = ROOT / "demo/cast/cast.json"
FONTS = "fonts"  # inside demo/cast/
OUTPUTS = ("fallback_1.ttf", "fallback_2.ttf", "fallback.txt", "noto-OFL.txt")
COMMIT = "47d54ca1ebb14fd864695f1d39dc734f39017c33"  # github.com/google/fonts, 2026-10-21
SOURCES = {
    "jp": ("ofl/notosansjp/NotoSansJP%5Bwght%5D.ttf", "c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f"),
    "sc": ("ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf", "a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"),
    "licence": ("ofl/notosansjp/OFL.txt", "1c05c68c34f9708415aada51f17e1b0092d2cea709bf4a94cd38114f9e73d7d9"),
}
WEIGHT = 800  # the game's display weight (Inter ExtraBold)
# Letters these fonts add: CJK punctuation, kana, ideographs (with extension A and compatibility forms), full-width forms.
RANGES = ((0x3000, 0x303F), (0x3040, 0x30FF), (0x31F0, 0x31FF), (0x3400, 0x4DBF), (0x4E00, 0x9FFF), (0xF900, 0xFAFF), (0xFF00, 0xFFEF))
KANA = ((0x3040, 0x30FF), (0x31F0, 0x31FF), (0xFF66, 0xFF9F))


def cjk(letter):
    """True for a letter the cast fonts can add (Japanese or Chinese)."""
    return any(low <= ord(letter) <= high for low, high in RANGES)


def kana(letter):
    return any(low <= ord(letter) <= high for low, high in KANA)


def letters(value):
    """Every letter of every text value in the cast (keys and numbers left out)."""
    if isinstance(value, str):
        yield from value
    elif isinstance(value, dict):
        for item in value.values():
            yield from letters(item)
    elif isinstance(value, list):
        for item in value:
            yield from letters(item)


def wanted(cast):
    """The cast's Japanese and Chinese letters, and the font order: Japanese forms first when the text has kana."""
    need = sorted({letter for letter in letters(cast) if cjk(letter)})
    order = ("jp", "sc") if any(kana(letter) for letter in need) else ("sc", "jp")
    return need, order


def source(key):
    """The cached source file, downloaded and checked on first use."""
    path_in_repo, sha = SOURCES[key]
    cache = Path(os.environ.get("FRIENDS_FONT_CACHE", ROOT / "tools/.font-cache"))
    cache.mkdir(parents=True, exist_ok=True)
    path = cache / f"{sha[:16]}-{Path(path_in_repo).name.replace('%5B', '[').replace('%5D', ']')}"
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != sha:
        url = f"https://raw.githubusercontent.com/google/fonts/{COMMIT}/{path_in_repo}"
        with urllib.request.urlopen(url, timeout=120) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != sha:
            raise RuntimeError(f"{url} does not match its pinned SHA-256")
        path.write_bytes(data)
    return path


def clear(folder):
    for name in OUTPUTS:
        (folder / name).unlink(missing_ok=True)
    if folder.is_dir() and not any(folder.iterdir()):
        folder.rmdir()


def build(cast_path=CAST_FILE):
    """Writes the cast fonts; returns (letters drawn, letters no font draws)."""
    cast = json.loads(cast_path.read_text(encoding="utf-8"))
    need, order = wanted(cast)
    folder = cast_path.parent / FONTS
    clear(folder)
    if not need:
        return [], []
    try:
        from fontTools import subset
        from fontTools.ttLib import TTFont
        from fontTools.varLib import instancer
    except ImportError:
        raise RuntimeError("the cast has Japanese or Chinese text; install fontTools first: pip install fonttools")
    folder.mkdir(exist_ok=True)
    left, drawn, count = set(need), set(), 0
    for key in order:
        font = TTFont(source(key))
        here = {letter for letter in left if ord(letter) in font.getBestCmap()}
        if not here:
            continue
        options = subset.Options()
        options.hinting = False
        options.layout_features = ["*"]
        cutter = subset.Subsetter(options)
        cutter.populate(unicodes=[ord(letter) for letter in here])
        cutter.subset(font)
        font = instancer.instantiateVariableFont(font, {"wght": WEIGHT})
        count += 1
        font.save(folder / f"fallback_{count}.ttf")
        drawn |= here
        left -= here
    (folder / "fallback.txt").write_text("".join(sorted(drawn)) + "\n", encoding="utf-8")
    (folder / "noto-OFL.txt").write_bytes(source("licence").read_bytes())
    return sorted(drawn), sorted(left)


def main():
    try:
        drawn, missing = build()
    except (OSError, ValueError, RuntimeError) as error:
        print(f"cast_fonts: FAILED: {error}")
        return 1
    if missing:
        print(f"cast_fonts: FAILED: no font draws {''.join(missing)!r}; change those letters")
        return 1
    print(f"cast_fonts: ok ({len(drawn)} letters)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
