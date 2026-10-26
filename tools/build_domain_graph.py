#!/usr/bin/env python3
"""Derive the hosted build's domain graph from the entry scenes.

The hosted analyzer wants `source-domains.json` (schema summer.source-domain-graph.v1): which project files are shared,
client-only or authority code, plus explicit edges for computed loads. This tool computes it instead of listing files by hand:

* entries come from `world.json` (client entry, component entries, network compositions) and the main scenes of `project.godot`
  (`run/main_scene` = local app = client side, `.summer_client` = client, `.summer_authority` = authority);
* `res://` tokens are followed transitively through scripts, scenes, resources, shaders (incl. includes), JSON and project.godot,
  the same token rule as the analyzer (it reads comments too);
* hard tokens (`"res://x"`) make the target part of the referencing role; soft tokens (`"res" + "://x"`, invisible to the
  analyzer on purpose) name payloads that are loaded at run time: data files they name from authority-side code are shared, everything
  else (textures, audio, scripts) is client-only;
* role rule: reachable from an authority entry = shared (files under `authority/` = authority); reachable only from client entries
  = client. A client-only payload directory (audio, menu art) named by a hard token from authority-side code is an error.
* payload directories (fonts, city kit, looks, level JSON; music, sound effects, menu art) are roots of their role as a whole;
* computed-load scripts get an explicit edge to the manifest of their role (`assets/shared_resources.json`, `assets/client_resources.json`);
* directory roots are collapsed wherever every code/data file below a directory has the same role (a row is limited to 128 paths).

CLI (a dry run unless --write, which only writes the ignored generated files of a dev checkout; staging uses prepare_clone and generate):
    tools/build_domain_graph.py --project demo [--report report.json]
"""
import argparse
from collections import deque
import json
import os
from pathlib import Path
import posixpath
import re

GRAPH_SCHEMA = "summer.source-domain-graph.v1"
GRAPH_FILE = "source-domains.json"
SHARED_MANIFEST = "assets/shared_resources.json"
CLIENT_MANIFEST = "assets/client_resources.json"
AUTHORITY_MANIFEST = "assets/authority_resources.json"
AUTHORITY_DIR = "authority"
MANIFESTS = {SHARED_MANIFEST: "shared", CLIENT_MANIFEST: "client", AUTHORITY_MANIFEST: "authority"}
# Files the analyzer or the exporter consume directly; never pruned, never part of the shared row.
METADATA = {"project.godot", "export_presets.cfg", "summer.build.json", "world.json", "runtime-manifest.json", GRAPH_FILE, *MANIFESTS}
ROW_LIMIT = 128
EDGE_LIMIT = 512
FILE_LIMIT = 4096  # analyzer: files per profile

# Payload directories: (directory, extensions or None for every file). Shared ones are part of the shared graph; the
# authority pack leaves out the visual ones (see server_excluded). Client ones never reach the authority.
SHARED_PAYLOADS = (("assets/fonts", None), ("assets/prop_kit", None), ("assets/looks", None),
                   ("levels", (".json",)), ("cast", None))  # cast: the team cast and its pictures (style/team_cast.gd)
CLIENT_PAYLOADS = (("audio/music", (".wav", ".ogg", ".png", ".jpg", ".json")),
                   ("audio/sfx", (".wav", ".ogg", ".png", ".jpg", ".json")),
                   ("client/menu_art", (".wav", ".ogg", ".png", ".jpg", ".json")))
KIT_DIR = "assets/prop_kit"
# Soft tokens from authority-side code to these are data both roles need; the rest is presentation (client).
DATA_EXTENSIONS = {".json", ".tres", ".res", ".cfg", ".csv", ".txt", ".bin", ".dat"}
# Never part of the authority pack: presentation payloads, whatever directory they sit in.
VISUAL_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".svg", ".glb", ".gltf", ".wav", ".ogg", ".ogv", ".mp3", ".exr", ".hdr", ".raw"}
SERVER_EXCLUDED_DIRS = ("assets/prop_kit/", "assets/looks/", "audio/")
PAYLOAD_LIST_EXTENSIONS = VISUAL_EXTENSIONS | {".json", ".ttf", ".otf"}
CODE_EXTENSIONS = {".gd", ".tscn", ".tres", ".gdshader", ".gdshaderinc", ".shader"}
# Analyzer text kinds (every `res://` token inside them must resolve) plus include files and binary resources, which carry paths too.
REFERENCING = {".gd", ".tscn", ".tres", ".gdshader", ".gdshaderinc", ".shader", ".json", ".res", ".scn"}
ANALYZER_TEXT = {".gd", ".cs", ".csproj", ".sln", ".tscn", ".scn", ".tres", ".res", ".gdshader", ".glsl", ".shader", ".json", ".toml", ".yaml", ".yml", ".import", ".uid"}
SKIP_DIRS = {".godot", ".git", ".summer", "__pycache__", "node_modules"}
STATIC_EXCLUDES = ("*_probe.gd", "build_scene.gd", "*.py", "*.md", "*.bak", "__pycache__/*", "lab/*")
CLIENT_INCLUDES = ("*.json", "assets/fonts/*-OFL.txt")
TOKEN = re.compile(r"res://[A-Za-z0-9/_\-.@]*")
TOKEN_BYTES = re.compile(rb"res://[A-Za-z0-9/_\-.@]*")
SOFT = re.compile(r"""["']res["']\s*\+\s*["']://([^"'\n]*)["']""")
PRELOAD = re.compile(r"""preload\(\s*["']res://([A-Za-z0-9/_\-.@]+)["']""")
EXT_RESOURCE = re.compile(r'^\[ext_resource [^\n]*?path="res://([^"]+)"', re.M)
SIDECARS = (".uid", ".import")


class GraphError(ValueError):
    """The project cannot produce an analyzer-clean graph; the message lists every cause."""


def is_sidecar(path):
    return path.endswith(SIDECARS)


def ext(path):
    return posixpath.splitext(path)[1].lower()


def under(path, prefix):
    return path == prefix or path.startswith(prefix.rstrip("/") + "/")


def index_project(project):
    files = set()
    for base, dirs, names in os.walk(project):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith(".")]
        for name in names:
            if name.startswith(".") or name.endswith((".tmp", ".bak")):
                continue
            files.add(Path(base, name).relative_to(project).as_posix())
    return files


def simplify(path):
    path = posixpath.normpath(path)
    return "" if path == "." else path


def tokens_of(path, data):
    """Hard `res://` tokens of one file, project relative, in the analyzer's character set."""
    if path.endswith(".import"):
        return []
    if path == "project.godot":
        data = b"\n".join(line for line in data.splitlines() if not re.match(rb"\s*run/main_scene", line))
    found = []
    for raw in TOKEN_BYTES.findall(data):
        token = raw[6:].decode()
        if token:
            found.append(simplify(token))
    return found


def soft_tokens(text):
    return [simplify(m) if m else "" for m in SOFT.findall(text)]


CLASS_NAME = re.compile(r"^class_name\s+(\w+)", re.M)
UID_TOKEN = re.compile(rb"uid://[a-z0-9]+")
UID_OWNER = re.compile(rb'^\s*uid="?(uid://[a-z0-9]+)', re.M)


def strip_comments(text):
    """GDScript text without `#` comments (quote-aware per line); class names inside comments are not references."""
    lines = []
    for line in text.splitlines():
        quote = None
        for index, char in enumerate(line):
            if quote:
                if char == quote and line[index - 1] != "\\":
                    quote = None
            elif char in "\"'":
                quote = char
            elif char == "#":
                line = line[:index]
                break
        lines.append(line)
    return "\n".join(lines)


def index_identities(project, files):
    """({class_name: file}, {uid: file}): what code can reference without writing a path."""
    classes, uids = {}, {}
    for path in sorted(files):
        suffix = ext(path)
        if suffix == ".gd":
            match = CLASS_NAME.search(strip_comments((project / path).read_text(errors="replace")))
            if match:
                classes[match.group(1)] = path
        if suffix == ".uid":
            found = UID_TOKEN.search((project / path).read_bytes())
            if found:
                uids[found.group().decode()] = path.rsplit(".", 1)[0]
        elif suffix == ".import":
            found = UID_OWNER.search((project / path).read_bytes())
            if found:
                uids[found.group(1).decode()] = path.rsplit(".", 1)[0]
        if suffix in (".tscn", ".tres"):
            head = (project / path).read_bytes().split(b"\n", 1)[0]
            found = re.search(rb'uid="(uid://[a-z0-9]+)"', head)
            if found:
                uids[found.group(1).decode()] = path
    return classes, uids


def has_computed_load(text, name):
    """Same scan as the analyzer: a global load()/preload() or ResourceLoader.load() whose first argument is not a literal."""
    def ident(ch):
        return ch.isascii() and (ch.isalnum() or ch == "_")
    offset = 0
    while True:
        at = text.find(name + "(", offset)
        if at < 0:
            return False
        skip = False
        if at > 0:
            before = text[at - 1]
            if ident(before):
                skip = True
            elif before == ".":
                receiver = at - 1
                while receiver > 0 and ident(text[receiver - 1]):
                    receiver -= 1
                skip = not (name == "load" and text[receiver:at - 1] == "ResourceLoader")
        if skip:
            offset = at + len(name) + 1
            continue
        cursor = at + len(name) + 1
        while cursor < len(text) and text[cursor] in " \t\n\r":
            cursor += 1
        if cursor >= len(text) or text[cursor] not in "\"'":
            return True
        offset = cursor + 1


def server_excluded(path, role):
    """True when the authority pack leaves the file out: client-role files and presentation payloads."""
    if role == "client":
        return True
    return ext(path) in VISUAL_EXTENSIONS or any(path.startswith(d) for d in SERVER_EXCLUDED_DIRS)


class Plan:
    def __init__(self, project, files):
        self.project = project
        self.files = files
        self.role = {}        # path -> shared | client | authority
        self.parent = {}      # path -> who named it first (diagnostics)
        self.errors = []
        self.notes = []
        self.computed = {}    # script path -> role, scripts whose load()/preload() argument is computed
        self.soft_dirs = {}   # directory named by a soft token -> role of the first referencing file
        self.unreached = set()
        self.preloads = []    # (authority-side file, target) of unconditional loads

    def chain(self, path):
        steps = [path]
        while steps[-1] in self.parent and self.parent[steps[-1]] and len(steps) < 12:
            steps.append(self.parent[steps[-1]])
        return " <- ".join(steps)

    def of_role(self, role):
        return sorted(p for p, r in self.role.items() if r == role)


def _data(plan, path):
    return (plan.project / path).read_bytes()


def _soft_targets(plan, token):
    """Files a soft token can name: a file, a directory, or a name prefix inside a directory (format strings stop at `%`)."""
    token = re.split(r"[%#]", token, maxsplit=1)[0]
    if not token:
        return []
    if token in plan.files:
        return [token]
    directory = token.rstrip("/")
    inside = [p for p in plan.files if p.startswith(directory + "/")]
    if not (token.endswith("/") or inside):
        parent, _, stem = token.rpartition("/")
        inside = [p for p in plan.files if posixpath.dirname(p) == parent and posixpath.basename(p).startswith(stem)]
    return sorted(p for p in inside if not is_sidecar(p))


def _seed_payloads(plan, table, role):
    for directory, extensions in table:
        for path in sorted(plan.files):
            if under(path, directory) and not is_sidecar(path) and (extensions is None or ext(path) in extensions):
                yield path, role, "payload " + directory


def _client_forced(path):
    return any(under(path, directory) for directory, _ in CLIENT_PAYLOADS)


def _entries(project):
    """(authority entries, client entries, shared seeds, runtime descriptors) from world.json and project.godot."""
    authority, client, shared = [], [], []
    world = json.loads((project / "world.json").read_text())
    strip = lambda value: value.removeprefix("res://")
    client.append(strip(world["client_entry_point"]))
    for component in world.get("components", []):
        authority.append(strip(component["entry_point"]))
    shared.extend(strip(v) for v in world.get("network_compositions", []))
    for line in (project / "project.godot").read_text().splitlines():
        match = re.match(r'run/main_scene(?:\.(\w+))?\s*=\s*"res://([^"]+)"', line)
        if match:
            (authority if match.group(1) == "summer_authority" else client).append(match.group(2))
    return sorted(set(authority)), sorted(set(client)), sorted(set(shared))


def build_plan(project, client_entries=()):
    """Compute roles, edges and diagnostics. Reads the project only."""
    project = Path(project).resolve(strict=True)
    plan = Plan(project, index_project(project))
    authority_entries, client_entries_world, shared_seeds = _entries(project)
    client_entries = sorted({*client_entries_world, *client_entries})
    for name in (*authority_entries, *client_entries, *shared_seeds):
        if name not in plan.files:
            plan.errors.append(f"entry file missing: {name}")

    def claim(path, role, parent):
        if path in plan.role or path not in plan.files:
            return False
        plan.role[path] = role
        plan.parent[path] = parent
        return True

    queue = deque()

    def enqueue(path, role, parent):
        if claim(path, role, parent):
            queue.append(path)

    classes, uids = index_identities(project, plan.files)
    class_pattern = re.compile(r"\b(?:" + "|".join(sorted(map(re.escape, classes), key=len, reverse=True)) + r")\b") if classes else None

    def indirect(path, data):
        """Files named without a path: global class names in code and `uid://` tokens."""
        found = set()
        if class_pattern is not None and ext(path) == ".gd":
            found.update(classes[name] for name in class_pattern.findall(strip_comments(data.decode("utf-8", "replace"))))
        for raw in UID_TOKEN.findall(data):
            if raw.decode() in uids:
                found.add(uids[raw.decode()])
        found.discard(path)
        return sorted(found)

    def targets_of(path, data):
        found = []
        for token in tokens_of(path, data):
            target = resolve_hard(path, token)
            if target is not None:
                found.append(target)
        found.extend(t for t in indirect(path, data) if t not in found)
        return found

    def resolve_hard(source, token):
        if not token:
            return None
        if token.startswith(".godot/"):
            plan.errors.append(f"{source}: names the import cache: res://{token}")
            return None
        if token in plan.files:
            return token
        kind = "directory" if any(p.startswith(token.rstrip("/") + "/") for p in plan.files) else "missing file"
        plan.errors.append(f"{source}: res://{token} is a {kind}; the analyzer cannot resolve it. A run-time prefix must be written \"res\" + \"://...\"")
        return None

    # --- authority side: everything an authority entry reaches is shared (authority/ itself is the authority row) ---
    for path in sorted(plan.files):
        if under(path, AUTHORITY_DIR) and not is_sidecar(path):
            enqueue(path, "authority", None)
    for name in authority_entries:
        enqueue(name, "authority" if under(name, AUTHORITY_DIR) else "shared", None)
    for name in shared_seeds:
        enqueue(name, "shared", "world.json")
    if "project.godot" in plan.files:
        for token in tokens_of("project.godot", _data(plan, "project.godot")):
            target = resolve_hard("project.godot", token)
            if target and not _client_forced(target) and target not in client_entries and target not in authority_entries:
                enqueue(target, "shared", "project.godot")
    for path, role, why in list(_seed_payloads(plan, SHARED_PAYLOADS, "shared")):
        enqueue(path, role, why)

    client_soft = []  # (file, parent) named by soft tokens from authority-side code
    while queue:
        path = queue.popleft()
        role = plan.role[path]
        if role == "client" or ext(path) not in REFERENCING:
            continue
        data = _data(plan, path)
        for target in targets_of(path, data):
            if _client_forced(target):
                plan.errors.append(f"{plan.chain(path)}: authority-side file names client-only payload res://{target}")
                continue
            enqueue(target, "authority" if under(target, AUTHORITY_DIR) else "shared", path)
        if ext(path) in (".gd", ".tscn", ".tres"):
            text = data.decode("utf-8", "replace")
            unconditional = PRELOAD.findall(text) if ext(path) == ".gd" else EXT_RESOURCE.findall(text)
            plan.preloads.extend((path, simplify(t)) for t in unconditional)
            for token in soft_tokens(text) if ext(path) == ".gd" else []:
                targets = _soft_targets(plan, token)
                if not targets:
                    plan.notes.append(f"{path}: \"res\" + \"://{token}\" names no file")
                kept_client = 0
                for target in targets:
                    if _client_forced(target):
                        client_soft.append((target, path))
                    elif any(under(target, d) for d, _ in SHARED_PAYLOADS) or ext(target) in DATA_EXTENSIONS:
                        enqueue(target, "shared", path)
                    else:
                        client_soft.append((target, path))
                        kept_client += 1
                if kept_client:
                    plan.notes.append(f"{path}: \"res\" + \"://{token}\" names {kept_client} presentation file(s), client-only (the authority pack leaves them out)")
    # --- client side ---
    for path, role, why in _seed_payloads(plan, CLIENT_PAYLOADS, "client"):
        enqueue(path, "client", why)
    for name in client_entries:
        enqueue(name, "client", None)
    for target, parent in client_soft:
        enqueue(target, "client", parent)
    while queue:
        path = queue.popleft()
        if plan.role[path] != "client" or ext(path) not in REFERENCING:
            continue
        data = _data(plan, path)
        for target in targets_of(path, data):
            if under(target, AUTHORITY_DIR):
                plan.errors.append(f"{plan.chain(path)}: client file reaches authority file res://{target}")
            else:
                enqueue(target, "client", path)
        if ext(path) == ".gd":
            for token in soft_tokens(data.decode("utf-8", "replace")):
                for target in _soft_targets(plan, token):
                    enqueue(target, "client", path)
    # --- sidecars follow their file ---
    for path in sorted(plan.files):
        if is_sidecar(path):
            base = path.rsplit(".", 1)[0]
            if base in plan.role:
                plan.role[path] = plan.role[base]
    # --- generated manifests and metadata take their own role ---
    for name, role in MANIFESTS.items():
        plan.role[name] = role
    if "runtime-manifest.json" in plan.files:
        plan.role["runtime-manifest.json"] = "authority"
    plan.unreached = {p for p in plan.files if p not in plan.role and p not in METADATA}
    # --- computed loads need an edge ---
    for path in sorted(plan.role):
        if path.endswith(".gd") and path in plan.files:
            text = _data(plan, path).decode("utf-8", "replace")
            if has_computed_load(text, "load") or has_computed_load(text, "preload"):
                plan.computed[path] = plan.role[path]
    # --- unconditional loads of what the authority pack leaves out ---
    for path, target in plan.preloads:
        if plan.role.get(path) in ("shared", "authority") and target in plan.role and server_excluded(target, plan.role[target]):
            plan.errors.append(f"{plan.chain(path)}: preloads res://{target}, which the authority pack leaves out (load it at run time instead)")
    if not plan.of_role("authority"):
        plan.errors.append("no authority entry: nothing is reachable from the authority scene")
    return plan


def payload_resources(plan, roles, authority_only=False):
    names = []
    for path, role in plan.role.items():
        if role in roles and not is_sidecar(path) and path in plan.files and ext(path) in PAYLOAD_LIST_EXTENSIONS and path not in METADATA:
            if not authority_only or not server_excluded(path, role):
                names.append("res://" + path)
    return sorted(names)


def edges(plan):
    result = []
    for path, role in sorted(plan.computed.items()):
        targets = {"shared": [SHARED_MANIFEST], "client": [CLIENT_MANIFEST, SHARED_MANIFEST],
                   "authority": [AUTHORITY_MANIFEST, SHARED_MANIFEST]}[role]
        result.extend({"from": path, "to": target} for target in targets if target != path)
    return result


def rows(plan):
    """Domain rows: a directory is one root where every code/data file below it has the same role, otherwise single files."""
    labels = {}    # directory -> roles of the files below it ("?" = unclaimed code or data, which keeps the directory open)
    direct = {}    # directory -> files directly in it that carry a role
    for path in plan.files:
        role = plan.role.get(path)
        if role is None:
            if path in METADATA or is_sidecar(path) or ext(path) not in {*ANALYZER_TEXT, ".gdshaderinc"}:
                continue
        directory = posixpath.dirname(path)
        parts = directory.split("/") if directory else []
        for depth in range(1, len(parts) + 1):
            labels.setdefault("/".join(parts[:depth]), set()).add(role or "?")
        if role is not None:
            direct.setdefault(directory, []).append(path)
    paths = {"shared": [], "client": [], "authority": []}

    def descend(directory):
        here = labels.get(directory, set())
        if directory and len(here) == 1 and "?" not in here:
            paths[next(iter(here))].append(directory)
            return
        for path in direct.get(directory, []):
            if path not in METADATA or path in MANIFESTS or path == "runtime-manifest.json":
                paths[plan.role[path]].append(path)
        for sub in sorted(d for d in labels if d and posixpath.dirname(d) == directory):
            descend(sub)

    descend("")
    return {role: sorted(set(values)) for role, values in paths.items()}


def _within(path, root):
    return path == root or path.startswith(root + "/")


def expand(project, graph):
    """{domain: set(files)} of a graph document: directory roots listed against the project."""
    project = Path(project)
    present = index_project(project)
    result = {}
    for row in graph["roots"]:
        owned = set()
        for root in row["paths"]:
            owned.update(p for p in present if _within(p, root))
        result[row["domain"]] = owned
    return result


def document(plan, edge_list=None):
    grouped = rows(plan)
    domains = [("shared", "shared"), ("client", "client"), ("authority", "authority_engine")]
    roots = [{"domain": name, "paths": grouped[role]} for role, name in domains if grouped[role]]
    return {"schema": GRAPH_SCHEMA, "roots": roots, "dependencies": edge_list if edge_list is not None else edges(plan)}


def atomic_json(path, value, indent=None):
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, separators=(",", ":") if indent is None else None, indent=indent) + "\n")
    os.replace(temporary, path)


def write_uids_from_imports(project):
    """The analyzer knows UID owners from `.uid` files only; importer metadata carries the same UID."""
    written = 0
    for path in project.rglob("*.import"):
        if any(part in SKIP_DIRS for part in path.relative_to(project).parts):
            continue
        match = re.search(r'^uid="(uid://[^"]+)"', path.read_text(), re.M)
        sidecar = path.with_suffix(".uid")
        if match and (not sidecar.exists() or sidecar.read_text().strip() != match.group(1)):
            sidecar.write_text(match.group(1) + "\n")
            written += 1
    return written


def counts(plan, graph):
    present = expand(plan.project, graph)
    shared, client, authority = (len(present.get(d, ())) for d in ("shared", "client", "authority_engine"))
    return {"shared": shared, "client": client, "authority": authority,
            "client_profile": shared + client, "authority_profile": shared + authority}


def check(plan, graph):
    problems = list(dict.fromkeys(plan.errors))
    for row in graph["roots"]:
        if len(row["paths"]) > ROW_LIMIT:
            problems.append(f"{row['domain']} row has {len(row['paths'])} paths (limit {ROW_LIMIT}); group files into directories")
    if len(graph["dependencies"]) > EDGE_LIMIT:
        problems.append(f"{len(graph['dependencies'])} dependency edges (limit {EDGE_LIMIT})")
    stats = counts(plan, graph)
    for profile in ("client_profile", "authority_profile"):
        if stats[profile] > FILE_LIMIT:
            problems.append(f"{profile} has {stats[profile]} files (analyzer limit {FILE_LIMIT})")
    if problems:
        raise GraphError("\n".join(problems))
    return stats


def generate(project, client_entries=(), clone=True):
    """Write manifests, the graph and (clone only) UID owners and export preset filters; returns the report.
    clone=False is for a dev checkout: nothing tracked is touched, only the ignored generated files."""
    project = Path(project).resolve(strict=True)
    uids = write_uids_from_imports(project) if clone else 0
    plan = build_plan(project, client_entries)
    for name in MANIFESTS:
        plan.files.add(name)
    atomic_json(project / SHARED_MANIFEST, {"resources": payload_resources(plan, {"shared"})})
    atomic_json(project / CLIENT_MANIFEST, {"resources": payload_resources(plan, {"client"})})
    atomic_json(project / AUTHORITY_MANIFEST, {"schema": "friends.authority-assets.v1",
                                              "resources": payload_resources(plan, {"shared", "authority"}, authority_only=True)})
    document_ = document(plan)
    stats = check(plan, document_)
    atomic_json(project / GRAPH_FILE, document_)
    if clone:
        apply_presets(project, plan)
    return {"roles": {role: len(plan.of_role(role)) for role in ("shared", "client", "authority")},
            "rows": {row["domain"]: len(row["paths"]) for row in document_["roots"]}, "edges": len(document_["dependencies"]),
            "files": stats, "computed_load_scripts": len(plan.computed), "uid_sidecars_written": uids,
            "notes": plan.notes, "unreached": sorted(plan.unreached)}


# ---- export presets ----

def _section(text, matcher):
    sections = list(re.finditer(r"(?ms)^\[preset\.(\d+)\]\n.*?(?=^\[preset\.\d+\.options\]|^\[preset\.\d+\]|\Z)", text))
    found = [m for m in sections if matcher(m.group())]
    if len(found) != 1:
        raise GraphError(f"expected exactly one matching export preset, found {len(found)}")
    return found[0]


def _set_filters(text, matcher, include, exclude):
    match = _section(text, matcher)
    block = match.group()
    quoted = lambda items: json.dumps(",".join(items))
    if include is not None:
        block = re.sub(r"^include_filter=.*$", lambda _: "include_filter=" + quoted(include), block, flags=re.M)
    block = re.sub(r"^exclude_filter=.*$", lambda _: "exclude_filter=" + quoted(exclude), block, flags=re.M)
    return text[:match.start()] + block + text[match.end():]


def role_patterns(plan, role):
    """Exclude patterns for every file of `role`: `dir/*` where a whole directory is that role, single files (and sidecars) elsewhere."""
    whole = {}
    for path in plan.files:
        directory = posixpath.dirname(path)
        parts = directory.split("/") if directory else []
        for depth in range(1, len(parts) + 1):
            key = "/".join(parts[:depth])
            whole[key] = whole.get(key, True) and plan.role.get(path) == role
    top = sorted(d for d, ok in whole.items() if ok and not (posixpath.dirname(d) and whole.get(posixpath.dirname(d))))
    patterns = [d + "/*" for d in top]
    for path in sorted(plan.files):
        if plan.role.get(path) == role and not any(under(path, d) for d in top):
            patterns.append(path)
    return patterns


def preset_filters(plan):
    """(client exclude, authority include, authority exclude) lists derived from the roles."""
    server_exclude = [*STATIC_EXCLUDES, *role_patterns(plan, "client"),
                      *(f"*{e}" for e in sorted(VISUAL_EXTENSIONS)), *(d + "*" for d in SERVER_EXCLUDED_DIRS),
                      SHARED_MANIFEST, CLIENT_MANIFEST]
    data_files = sorted(p for p, r in plan.role.items() if r in ("shared", "authority") and p in plan.files and ext(p) == ".json"
                        and not server_excluded(p, r) and p not in METADATA)
    grouped = {}
    for path in data_files:
        grouped.setdefault(posixpath.dirname(path), []).append(path)
    include = []
    for directory, members in sorted(grouped.items()):
        include.append(f"{directory}/*.json" if directory and len(members) > 1 else members[0])
    include.extend(["world.json", "runtime-manifest.json", GRAPH_FILE, AUTHORITY_MANIFEST])
    client_exclude = [*STATIC_EXCLUDES, AUTHORITY_DIR + "/*"]
    return client_exclude, list(dict.fromkeys(include)), list(dict.fromkeys(server_exclude))


def apply_presets(project, plan):
    presets = (project / "export_presets.cfg").read_text()
    server_name = json.loads((project / "summer.build.json").read_text())["server"]["exportPreset"]
    client_exclude, include, server_exclude = preset_filters(plan)
    presets = _set_filters(presets, lambda block: 'platform="summer.games"' in block, list(CLIENT_INCLUDES), client_exclude)
    presets = _set_filters(presets, lambda block: f'name="{server_name}"' in block, include, server_exclude)
    (project / "export_presets.cfg").write_text(presets)


# ---- clone preparation ----

def kit_models(plan):
    """Model stems of the city kit that shipped scripts and level data name (quoted names, name prefixes ending in `_`, suffix parts)."""
    stems = {posixpath.basename(p).split(".")[0] for p in plan.files if under(p, KIT_DIR) and ext(p) in (".gltf", ".glb")}
    used, suffixes, prefixes = set(), set(), set()
    quoted = re.compile(r"""["']((?:res://assets/prop_kit/)?[A-Za-z0-9_]+)(?:\.(?:gltf|glb))?["']""")
    for path, role in plan.role.items():
        if under(path, KIT_DIR) or path not in plan.files or ext(path) not in (".gd", ".json", ".tscn", ".tres"):
            continue
        for name in quoted.findall(plan.project.joinpath(path).read_text(errors="replace")):
            name = name.removeprefix("res://assets/prop_kit/")
            if name in stems:
                used.add(name)
            if name.endswith("_"):
                prefixes.add(name)
            if name.startswith("_"):
                suffixes.add(name)
    used.update(s for s in stems if any(s.startswith(p) for p in prefixes))
    used.update(s for s in stems if any(s == base + suffix for base in list(used) for suffix in suffixes))
    return used


def prune_kit(plan):
    kit = plan.project / KIT_DIR
    if not kit.is_dir():
        return 0
    used = kit_models(plan)
    removed = 0
    for path in sorted(kit.iterdir()):
        stem = path.name.split(".")[0]
        if path.suffix in (".gltf", ".glb", ".bin", ".import", ".uid") and stem not in used and not stem.startswith("citybits"):
            path.unlink()
            removed += 1
    return removed


def prune_unreached(plan):
    removed = 0
    for path in sorted(plan.unreached):
        if is_sidecar(path):
            continue
        target = plan.project / path
        for victim in (target, *(target.with_name(target.name + s) for s in SIDECARS)):
            if victim.exists():
                victim.unlink()
                removed += 1
    for path in sorted(plan.project.rglob("*"), key=lambda p: -len(p.parts)):  # empty directories
        if path.is_dir() and not any(path.iterdir()) and not any(part in SKIP_DIRS for part in path.parts):
            path.rmdir()
    return removed


def drop_orphan_sidecars(project):
    removed = 0
    for path in index_project(project):
        if is_sidecar(path) and not (project / path.rsplit(".", 1)[0]).exists():
            (project / path).unlink()
            removed += 1
    return removed


def prepare_clone(project, client_entries=(), prune=True):
    """Prune a disposable clone to what the entries reach, then write graph, manifests, presets. Returns the report."""
    project = Path(project).resolve(strict=True)
    pruned = {}
    if prune:
        first = build_plan(project, client_entries)
        pruned["kit_files"] = prune_kit(first)
        first = build_plan(project, client_entries)
        pruned["unreached_files"] = prune_unreached(first)
        pruned["unreached"] = sorted(first.unreached)
        pruned["orphan_sidecars"] = drop_orphan_sidecars(project)
    report = generate(project, client_entries)
    report["pruned"] = pruned
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--client-entry", action="append", default=[], help="extra client entry scene (project relative)")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--write", action="store_true",
                        help="write the graph and the resource manifests (ignored files) into --project; never presets or UID sidecars")
    args = parser.parse_args()
    try:
        if args.write:
            report = generate(args.project, args.client_entry, clone=False)
        else:
            plan = build_plan(args.project, args.client_entry)
            for name in MANIFESTS:
                plan.files.add(name)
            document_ = document(plan)
            stats = check(plan, document_)
            report = {"roles": {r: len(plan.of_role(r)) for r in ("shared", "client", "authority")},
                      "rows": {row["domain"]: len(row["paths"]) for row in document_["roots"]}, "edges": len(document_["dependencies"]),
                      "files": stats, "computed_load_scripts": len(plan.computed), "notes": plan.notes, "unreached": sorted(plan.unreached)}
    except GraphError as error:
        print(str(error))
        return 1
    text = json.dumps(report, indent=2)
    print(text)
    if args.report:
        args.report.write_text(text + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
