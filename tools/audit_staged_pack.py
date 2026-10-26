#!/usr/bin/env python3
"""Offline membership audit of an exported hosted bundle (client.pck + server.pck).

Complements tools/stage_build.py (hashes, manifests, slim authority). The expected pack contents come from the generated domain
graph of the staged clone (tools/build_domain_graph.py), not from hand lists:

* shared code and data (that the authority pack does not leave out as presentation) is in BOTH packs;
* shared presentation payloads and everything of the client domain is in the client pack and NOT in the server pack;
* authority code is in the server pack and not in the client pack;
* no probes, no test lab; every .import/.remap target exists inside its own pack.
No engine, no network.
Usage: audit_staged_pack.py <bundle.zip> --project <staged-clone> [--receipt out.json]
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import zipfile

import build_domain_graph as graph
from stage_build import pack_entries, pack_has

# Types the exporter writes under their own name (or as a .remap/.import entry); raw side files (.bin of glTF, shader includes,
# licence texts) are not checked.
AUDITED = {".gd", ".tscn", ".tres", ".gdshader", ".json", ".ttf", ".otf", ".png", ".jpg", ".jpeg", ".webp", ".svg", ".glb", ".gltf", ".wav", ".ogg", ".mp3"}


def expectations(project):
    """(both, client_only, authority_only, shared_presentation): sets of project-relative logical files."""
    document = json.loads((project / graph.GRAPH_FILE).read_text())
    owned = graph.expand(project, document)
    logical = lambda domain: {f for f in owned.get(domain, set()) if not graph.is_sidecar(f) and graph.ext(f) in AUDITED}
    shared, client, authority = logical("shared"), logical("client"), logical("authority_engine")
    client_manifests = {graph.SHARED_MANIFEST, graph.CLIENT_MANIFEST}
    presentation = {f for f in shared if graph.server_excluded(f, "shared")} | (client_manifests & shared)
    both = shared - presentation
    authority_code = {f for f in authority if graph.ext(f) in graph.CODE_EXTENSIONS}
    return both, client - client_manifests, authority_code, presentation


def audit(bundle, project):
    both, client_only, authority_only, presentation = expectations(project)
    failures, report = [], {}
    with zipfile.ZipFile(bundle) as archive:
        meta = json.loads(archive.read("summer-bundle.json"))
        for role in ("client", "server"):
            data = archive.read(meta[role]["path"])
            entries = pack_entries(data)
            row = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), "entries": len(entries)}

            def have(names):
                return {name for name in names if pack_has(data, entries, name)}

            def report_set(label, names):
                if names:
                    failures.append(f"{role}: {label} ({len(names)}): {sorted(names)[:5]}")

            report_set("missing shared files", both - have(both))
            if role == "client":
                report_set("missing client files", client_only - have(client_only))
                report_set("missing shared presentation payloads", presentation - have(presentation))
                report_set("authority files present", have(authority_only))
            else:
                report_set("missing authority files", authority_only - have(authority_only))
                report_set("client-only files present", have(client_only))
                report_set("client presentation payloads present", have(presentation))
            probes = sorted(n for n in entries if re.search(r"_probe\.gd", n))
            report_set("probe scripts", probes)
            report_set("offline test lab must not ship", sorted(n for n in entries if n.startswith("lab/")))
            missing = []
            refs = 0
            for name, (offset, size) in entries.items():
                if name.endswith((".import", ".remap")):
                    text = data[offset:offset + size].decode(errors="ignore")
                    for target in re.findall(r'^path(?:\.[a-z0-9_]+)?="res://([^"]+)"', text, re.M):
                        refs += 1
                        if target not in entries:
                            missing.append(f"{name} -> {target}")
            report_set("unresolved import/remap targets", missing)
            row.update({"import_remap_refs": refs, "unresolved": len(missing),
                        "expected": {"both": len(both), "client_only": len(client_only), "authority_only": len(authority_only),
                                     "shared_presentation": len(presentation)}})
            report[role] = row
    return {"bundle": str(bundle), "ok": not failures, "failures": failures, "packs": report}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--project", type=Path, required=True, help="staged clone the bundle was exported from")
    parser.add_argument("--receipt", type=Path)
    args = parser.parse_args()
    result = audit(args.bundle, args.project.resolve())
    text = json.dumps(result, indent=2)
    if args.receipt:
        args.receipt.write_text(text + "\n")
    print(text)
    sys.exit(0 if result["ok"] else 1)
