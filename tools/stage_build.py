#!/usr/bin/env python3
"""Export and audit a hosted bundle from a prepared clone. Never authenticates, uploads or releases."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import zipfile
from datetime import datetime, timezone

import build_domain_graph as graph

# The Summer Games Android app refuses a pack exported by a newer patch than its embedded engine
# ("This game needs a newer version of Summer"): same MAJOR.MINOR, exporter patch <= app patch.
# 0.7.3 is the Android template pin of summer-platform 73d613755 (2026-10-17); a phone that still
# runs an older staging app needs FRIENDS_ANDROID_APP_SUMMER=0.7.2 and the 0.7.2 exporter.
ANDROID_APP_SUMMER = os.environ.get("FRIENDS_ANDROID_APP_SUMMER", "0.7.3")
IMPORTED_VISUAL = re.compile(r"\.godot/imported/.*\.(?:png|jpe?g|webp|svg|glb|gltf|wav|ogg|mp3|exr|hdr)-")


def android_accepts(exporter, app=ANDROID_APP_SUMMER):
    try:
        e, a = [tuple(int(x) for x in v.split(".")) for v in (exporter, app)]
    except (AttributeError, ValueError):
        return False
    return len(e) == len(a) == 3 and e[:2] == a[:2] and e[2] <= a[2]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def pack_entries(data):
    """Read the unencrypted Godot PCK v4 directory used by Summer 0.7.x."""
    if len(data) < 112 or data[:4] != b"GDPC":
        raise ValueError("not a standalone Godot PCK")
    version, = struct.unpack_from("<I", data, 4)
    if version != 4:
        raise ValueError(f"PCK version {version} is unsupported by this audit")
    flags, = struct.unpack_from("<I", data, 20)
    if flags & 1:
        raise ValueError("encrypted PCK directory is unsupported")
    file_base, directory = struct.unpack_from("<QQ", data, 24)
    count, = struct.unpack_from("<I", data, directory)
    cursor = directory + 4
    entries = {}
    for _ in range(count):
        length, = struct.unpack_from("<I", data, cursor)
        cursor += 4
        if length > len(data) - cursor:
            raise ValueError("invalid PCK path length")
        name = data[cursor:cursor + length].rstrip(b"\0").decode("utf-8")
        cursor += length
        offset, size = struct.unpack_from("<QQ", data, cursor)
        cursor += 36  # offset, size, MD5, flags
        if file_base + offset + size > len(data):
            raise ValueError(f"PCK entry exceeds file: {name}")
        entries[name.removeprefix("res://")] = (file_base + offset, size)
    return entries


def is_authority_visual_payload(path):
    """Presentation payloads the authority pack must not carry (sources and their imported cache entries)."""
    normalized = path.lower()
    return (graph.ext(normalized) in graph.VISUAL_EXTENSIONS
            or any(normalized.startswith(d) for d in graph.SERVER_EXCLUDED_DIRS)
            or IMPORTED_VISUAL.search(normalized) is not None)


def pack_has(pack_data, entries, resource):
    """The resource itself, its `.remap`, or an `.import` whose imported targets are all inside the pack."""
    normalized = resource.removeprefix("res://")
    paths = set(entries)
    if normalized in paths or normalized + "c" in paths or normalized + ".remap" in paths:
        return True
    imported = normalized + ".import"
    if imported not in entries:
        return False
    start, size = entries[imported]
    remaps = re.findall(r'^path(?:\.[^=\s]+)?="res://([^"]+)"', pack_data[start:start + size].decode("utf-8"), re.MULTILINE)
    return bool(remaps) and all(path in paths for path in remaps)


def audit(bundle, required, require_slim_authority=False):
    failures = []
    with zipfile.ZipFile(bundle) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            failures.append("duplicate ZIP entry")
        metadata = json.loads(archive.read("summer-bundle.json"))
        declaration = json.loads(archive.read("config/summer.build.json"))
        world = json.loads(archive.read("config/world.json"))
        if metadata.get("schema") != "summer.bundle.v1":
            failures.append("unexpected bundle schema")
        if declaration.get("executionMode") != "hosted":
            failures.append("executionMode must be hosted")
        declared = set(declaration.get("targetPlatforms", []))
        exported = set(metadata.get("client", {}).get("targetPlatforms", []))
        if declared != exported or not exported:
            failures.append("declared/exported client platform mismatch")
        if "android" in exported and not android_accepts(metadata.get("export", {}).get("summerVersion")):
            failures.append("Android app embeds Summer %s: it rejects a pack exported by %s" % (ANDROID_APP_SUMMER, metadata.get("export", {}).get("summerVersion")))
        for entry in metadata.get("files", []):
            content = archive.read(entry["path"])
            if len(content) != entry["size"] or "sha256:" + digest(content) != entry["sha256"]:
                failures.append("bundle integrity mismatch: " + entry["path"])
        packs = {}
        for role in ("client", "server"):
            target = metadata.get(role, {})
            if not target.get("path"):
                failures.append("missing " + role + " pack")
                continue
            pack_data = archive.read(target["path"])
            entries = pack_entries(pack_data)
            paths = set(entries)
            packs[role] = {"entries": len(paths), "mainScene": target.get("mainScene")}
            for resource in required:
                if not pack_has(pack_data, entries, resource):
                    failures.append(f"{role} pack missing required resource: {resource}")
            manifests = [graph.AUTHORITY_MANIFEST] if role == "server" else [graph.SHARED_MANIFEST, graph.CLIENT_MANIFEST]
            if role == "server" and graph.AUTHORITY_MANIFEST not in entries and require_slim_authority:
                failures.append("server pack missing precise authority runtime manifest")
            declared_assets = 0
            for manifest in manifests:
                if manifest in entries:
                    start, size = entries[manifest]
                    resources = json.loads(pack_data[start:start + size])["resources"]
                    declared_assets += len(resources)
                    packs[role][manifest] = digest(pack_data[start:start + size])
                    for resource in resources:
                        if not pack_has(pack_data, entries, resource):
                            failures.append(f"{role} pack missing manifest resource: {resource}")
            packs[role]["declaredRuntimeAssets"] = declared_assets
            if role == "server":
                for manifest in (graph.SHARED_MANIFEST, graph.CLIENT_MANIFEST):
                    if manifest in entries:
                        failures.append(f"server pack includes client resource manifest {manifest}")
                visual = sorted(path for path in paths if is_authority_visual_payload(path))
                packs[role]["unexpectedVisualAssets"] = visual
                if visual:
                    failures.append(f"server pack contains {len(visual)} excluded visual payloads")
        result = {"bundle": str(bundle.resolve()), "bytes": bundle.stat().st_size,
                  "sha256": digest(bundle.read_bytes()), "export": metadata.get("export"),
                  "platforms": sorted(exported), "composition": metadata.get("compositionPath"),
                  "worldDefinition": world.get("definition_id"), "packs": packs,
                  "failures": failures, "ok": not failures,
                  "limits": "Offline integrity/resource coverage only; no runtime, allocation or human gameplay proof."}
    return result


def project_snapshot(project):
    """Content hash of every file of the clone outside the import cache."""
    project = project.resolve()
    return {path: digest((project / path).read_bytes()) for path in sorted(graph.index_project(project))}


def role_snapshots(project, snapshot):
    """Shipped input fence per role: the files of the domains a role's profile composes (from the generated graph)."""
    document = json.loads((project / graph.GRAPH_FILE).read_text())
    owned = graph.expand(project, document)
    result = {}
    for role, domains in (("client", ("shared", "client")), ("server", ("shared", "authority_engine"))):
        names = set().union(*(owned.get(domain, set()) for domain in domains))
        inputs = {name: value for name, value in snapshot.items() if name in names or name in graph.METADATA}
        result[role] = {"inputFiles": inputs,
                        "inputSHA256": digest(json.dumps(inputs, sort_keys=True, separators=(",", ":")).encode())}
    return result


def utc_now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--export-project", type=Path, required=True,
                        help="Prepared disposable clone (tools/prepare_network_build.py --execute) to export; no network publication")
    parser.add_argument("--prune-unreferenced-code-uids", action="store_true",
                        help="Record and remove exporter-generated unreferenced code UID sidecars in the clone")
    parser.add_argument("--require-slim-authority", action="store_true", help="Reject an authority pack with client visual payload or no precise runtime manifest")
    parser.add_argument("--engine", type=Path, default=Path("/Applications/Summer Engine.app/Contents/MacOS/Summer"))
    parser.add_argument("--require-resource", action="append", default=[],
                        help="Require a resource in BOTH client and authority packs (repeatable)")
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--snapshot", type=Path, help="Save exact input hashes and reject changes during export")
    args = parser.parse_args()
    project = args.export_project.resolve()
    args.bundle.parent.mkdir(parents=True, exist_ok=True)
    snapshot_before = project_snapshot(project)
    roles_before = role_snapshots(project, snapshot_before)
    export_started = utc_now()
    subprocess.run([str(args.engine), "--headless", "--audio-driver", "Dummy", "--path", str(project),
                    "--export-release", "summer.games", str(args.bundle.resolve())], check=True)
    generated_code_uids = None
    if args.prune_unreferenced_code_uids:
        from prune_unreferenced_graph_uids import prune
        raw_after = project_snapshot(project)
        generated_code_uids = prune(project)
        generated_code_uids["raw_fence_changes_before_pruning"] = sorted(
            name for name in snapshot_before.keys() | raw_after.keys() if snapshot_before.get(name) != raw_after.get(name))
    try:
        result = audit(args.bundle, args.require_resource, args.require_slim_authority)
    except (OSError, KeyError, ValueError, zipfile.BadZipFile, struct.error) as error:
        result = {"ok": False, "failures": [str(error)]}
    after = project_snapshot(project)
    changed = sorted(path for path in snapshot_before.keys() | after.keys() if snapshot_before.get(path) != after.get(path))
    if args.snapshot:
        record = {"exportStartedUTC": export_started, "exportCompletedUTC": utc_now(),
                  "inputFiles": snapshot_before, "inputChanges": changed, "roles": roles_before,
                  "bundle": str(args.bundle.resolve()), "bundleSHA256": result.get("sha256")}
        if generated_code_uids is not None:
            record["exporterGeneratedUnreferencedCodeUIDs"] = generated_code_uids
        args.snapshot.parent.mkdir(parents=True, exist_ok=True)
        args.snapshot.write_text(json.dumps(record, indent=2) + "\n")
        result["snapshot"] = {"path": str(args.snapshot.resolve()), "inputs": len(snapshot_before),
                              "unchanged": not changed, "startedUTC": export_started, "completedUTC": record["exportCompletedUTC"]}
    if changed:
        result.setdefault("failures", []).append("Export inputs changed: " + ", ".join(changed[:30]))
        result["ok"] = False
    output = json.dumps(result, indent=2)
    print(output)
    if args.receipt:
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        args.receipt.write_text(output + "\n")
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
