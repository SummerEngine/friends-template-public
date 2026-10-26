#!/bin/bash
# Mesh lint of the built stage levels: z-fighting (coplanar faces), hairline gaps, loose supports and overlaps of decorative visuals (tools/mesh_lint.gd, rules in its header).
#   tools/mesh_lint.sh [--headless] [--selftest] [--tree=DIR] [--md=FILE] [mesh_lint.gd arguments, e.g. --levels=25,26 --budget=0 --baseline=FILE --out=FILE --overlap-budget=0]
#   tools/mesh_lint.sh --podium [--headless] [--out=f.json] [--md=f.md] [--overlap-budget=0]   # the victory podium room (pseudo-level 98)
#   tools/mesh_lint.sh --lobby [--dir=tools/level_testdata] [--headless] [--out=f.json] [--md=f.md] [--budget=0 --warn-budget=0 --overlap-budget=0]   # the built lobby yard (pseudo-level 99), ONE engine process
# Default: the offscreen renderer (a Summer build with --summer-offscreen, no window) under the machine-wide render lock: it keeps MultiMesh transforms, so the tile
# floors, the arena cage (pillars, beams, signs) and the skyline are linted too. `--headless` runs the dummy renderer (no GPU, no lock, about 10 s per level): it drops
# MultiMesh transforms, those nodes are listed as NOT LINTED and everything else (level look, ceilings, hazards, goal arch, markers, ground) is linted.
# One engine process per level (a big level plus the ones before it does not fit one process); the JSON of the levels is merged into --out.
#   --tree=DIR   lint the project of another checkout (DIR/demo), the tool itself is always this file's
#   --md=FILE    write the Markdown report of the run (tools/mesh_lint_report.py) from the JSON (`--out`, default build/mesh_lint.json)
#   --selftest   the synthetic known-bad / clean meshes (no level is built)
# Environment: SUMMER (engine binary, default the installed app; the offscreen build is needed without --headless), MESH_LINT_TIMEOUT (seconds per level, default 900),
# FRIENDS_PRIORITY=1 (take the reserved engine slot). Exit code: 1 over a budget, 2 for a usage problem.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
tree=$root
summer=${SUMMER:-/Applications/Summer Engine.app/Contents/MacOS/Summer}
mode=offscreen
md=""
out=""
levels="25,26,27,28,29,30"
lobby=0
podium=0
selftest=0
args=()
for a in "$@"; do
  case "$a" in
    --headless) mode=headless ;;
    --tree=*) tree=$(cd "${a#--tree=}" && pwd) ;;
    --md=*) md=${a#--md=} ;;
    --out=*) out=${a#--out=} ;;
    --levels=*) levels=${a#--levels=} ;;
    --lobby) lobby=1; args+=("$a") ;;
    --podium) podium=1; args+=("$a") ;;
    --selftest) selftest=1; args+=("$a") ;;
    *) args+=("$a") ;;
  esac
done
if [ "$podium" = 1 ]; then levels=98; fi # the podium room is one pseudo-level
if [ "$lobby" = 1 ]; then levels=99; fi # the lobby yard is one pseudo-level in one engine process
if [ ! -x "$summer" ]; then echo "mesh_lint.sh: no engine at $summer (set SUMMER)" >&2; exit 2; fi
if [ -n "$md" ] && [ -z "$out" ]; then out="$tree/build/mesh_lint.json"; fi
if [ -n "$out" ]; then mkdir -p "$(dirname "$out")"; fi
timeout_s=${MESH_LINT_TIMEOUT:-900}
work=$(mktemp -d -t mesh_lint)
trap 'rm -rf "$work"' EXIT
status=0
run_engine() { # run_engine <log> <mesh_lint.gd arguments...>
  local log=$1
  shift
  if [ "$mode" = headless ]; then
    "$root/tools/engine_slot.sh" timeout -k 10 "$timeout_s" "$summer" --headless --audio-driver Dummy --rendering-driver dummy --fixed-fps 60 --path "$tree/demo" \
      -s "$root/tools/mesh_lint.gd" -- "$@" > "$log" 2>&1
  else
    local lock=${XDG_STATE_HOME:-$HOME/.local/state}/friends-slots/render.lock
    mkdir -p "$(dirname "$lock")"
    lockf -k "$lock" "$root/tools/engine_slot.sh" timeout -k 10 "$timeout_s" "$summer" --summer-offscreen --audio-driver Dummy --fixed-fps 60 --resolution 320x180 --path "$tree/demo" \
      -s "$root/tools/mesh_lint.gd" -- "$@" > "$log" 2>&1
  fi
}
show() { grep -v '^\[SE\]\|TLS handshake error\|^Welcome to Summer\|^$' "$1"; }
if [ "$selftest" = 1 ]; then
  run_engine "$work/log" ${args[@]+"${args[@]}"}
  status=$?
  show "$work/log"
  exit $status
fi
parts=()
for level in ${levels//,/ }; do
  run_engine "$work/log$level" --levels="$level" --out="$work/level$level.json" ${args[@]+"${args[@]}"}
  code=$?
  show "$work/log$level"
  if [ ! -f "$work/level$level.json" ]; then echo "MESHLINT level $level: no result (engine exit $code)"; status=1; continue; fi
  [ "$code" -gt "$status" ] && status=$code
  parts+=("$work/level$level.json")
done
if [ ${#parts[@]} -gt 0 ] && [ -n "$out" ]; then python3 "$root/tools/mesh_lint_report.py" --merge "$out" "${parts[@]}" || status=1; fi
if [ -n "$md" ] && [ -f "$out" ]; then python3 "$root/tools/mesh_lint_report.py" "$out" --md "$md" || status=$?; fi
exit $status
