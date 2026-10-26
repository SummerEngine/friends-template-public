#!/bin/bash
# Current checkout -> frozen hosted bundle (no upload, no release).
#   tools/stage_hosted_export.sh <label>      e.g. v0.6.0  -> build/friends-network-<label>.summer.zip
# Steps: APFS clone of demo/ (test lab removed) -> tools/prepare_network_build.py --execute (key the plain background out of the clone's cast
# pictures into cast/prepared/ (tools/cast_prep.py), prune to what the entry scenes reach,
# import, network scenes, domain graph, resource manifests, export presets, both analyzer profiles clean) ->
# tools/stage_build.py (export, input fence, bundle audit) -> tools/audit_staged_pack.py (pack membership from the generated graph) ->
# tools/clean_scan.py on the bundle and on the repository tree (any hit fails the run).
# Engine: SUMMER_BIN (default: the installed Summer app). Output: analysis/staging/<label>/ and build/.
# See docs/build-tooling.md.
set -euo pipefail
label=$1
engine=${SUMMER_BIN:-/Applications/Summer Engine.app/Contents/MacOS/Summer}
cd "$(dirname "$0")/.."
out=analysis/staging/$label
bundle=build/friends-network-$label.summer.zip
[ ! -e "$out" ] && [ ! -e "$bundle" ] || { echo "refusing to overwrite $out or $bundle" >&2; exit 2; }
mkdir -p "$out" build
cp -cR demo "$out/project"
# The offline test lab drives the simulation locally and is not part of any hosted build.
rm -rf "$out/project/lab"
# Local stand-in art (gitignored `_ref/` folders) never ships.
find "$out/project" -type d -name _ref -prune -exec rm -rf {} +
# Sidecar ids that are not committed come from earlier local runs; the clone must start from the committed state.
comm -23 <(find demo -name '*.uid' | sort) <(git ls-files 'demo/*.uid' | sort) | while read -r f; do rm -f "$out/project/${f#demo/}"; done
FRIENDS_PRIORITY=1 tools/engine_slot.sh python3 tools/prepare_network_build.py --project "$out/project" \
  --engine "$engine" --execute --receipt "$out/prep-receipt.json" --timeout 900 > "$out/prepare.log" 2>&1
FRIENDS_PRIORITY=1 tools/engine_slot.sh python3 tools/stage_build.py "$bundle" --export-project "$out/project" \
  --engine "$engine" --prune-unreferenced-code-uids --require-slim-authority \
  --receipt "$out/export-receipt.json" --snapshot "$out/input-snapshot.json" > "$out/export.log" 2>&1
python3 tools/audit_staged_pack.py "$bundle" --project "$out/project" --receipt "$out/pack-audit.json" > /dev/null
python3 tools/clean_scan.py --bundle "$bundle" --tree .
sha256sum "$bundle" 2>/dev/null || shasum -a 256 "$bundle"
