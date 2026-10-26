#!/bin/bash
# The look loop's cost: frame time, draw calls and triangles of a tile round, a race level and the lobby on the Mobile and the Compatibility renderers, one command.
#   tools/look_perf.sh <worktree> [mobile|compat|both] [outfile]
# <worktree>  the checkout to measure (its demo/ is the project; its tools/party_perf.gd is used when it has one, else this checkout's).
# renderer    both (default), mobile (Forward Mobile) or compat (gl_compatibility, the phone build).
# outfile     the table is also written there (default: only printed).
# What is measured (tools/party_perf.gd, offscreen, 1280x720, the whole pipeline per frame on this machine's GPU, median of five 120-frame rounds): level 26 (hexagon round: start view,
# wide view, wide view with every second tile gone), level 29 (race: player view, wide view) and the lobby player view. Run before/after a restyle for the before/after report.
# Env: LEVELS (comma list of level file numbers, default 26,29), ITEMSLAB (the offscreen binary, required), RENDER_LOCK, PERF_TIMEOUT (s per renderer, default 280).
# The runs take the machine-wide render lock (ONE render at a time) and hold it only while they run.
set -u
if [ $# -lt 1 ]; then sed -n '2,10p' "$0"; exit 2; fi
OWN="$(cd "$(dirname "$0")/.." && pwd)"
WT="$(cd "$1" && pwd)"
WHICH="${2:-both}"
OUTFILE="${3:-}"
BIN="${ITEMSLAB:-}"
LOCK="${RENDER_LOCK:-$HOME/.local/state/friends-slots/render.lock}"
LIMIT="${PERF_TIMEOUT:-280}"
LEVELS="${LEVELS:-26,29}"
[ -x "$BIN" ] || { echo "look_perf: no offscreen binary at $BIN"; exit 2; }
[ -d "$WT/demo" ] || { echo "look_perf: $WT has no demo/"; exit 2; }
SCRIPT="$WT/tools/party_perf.gd"; [ -f "$SCRIPT" ] || SCRIPT="$OWN/tools/party_perf.gd"
mkdir -p "$(dirname "$LOCK")"
case "$WHICH" in both) LIST="mobile compat" ;; mobile|compat) LIST="$WHICH" ;; *) echo "look_perf: renderer must be mobile, compat or both"; exit 2 ;; esac
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
STATUS=0
for r in $LIST; do
  ARGS=()
  if [ "$r" = compat ]; then ARGS=(--rendering-method gl_compatibility --rendering-driver opengl3); fi
  lockf -k "$LOCK" timeout -k 10 "$LIMIT" "$BIN" --summer-offscreen --audio-driver Dummy --fixed-fps 60 --resolution 1280x720 ${ARGS[@]+"${ARGS[@]}"} \
    --path "$WT/demo" -s "$SCRIPT" -- --levels="$LEVELS" --lobby > "$TMP/$r.log" 2>&1
  code=$?
  [ $code -eq 0 ] || { echo "look_perf: $r exited with $code"; STATUS=1; }
  grep -h "SCRIPT ERROR\|SHADER ERROR\|Parse Error" "$TMP/$r.log" | sort | uniq -c | sort -rn | head -10
done
TABLE="$(python3 - "$TMP" $LIST <<'E'
import re, sys
tmp, renderers = sys.argv[1], sys.argv[2:]
rows = {}
order = []
built = {}
for r in renderers:
    for line in open("%s/%s.log" % (tmp, r), errors="replace"):
        m = re.match(r"PARTY_PERF (.+?) ([\d.]+) ms per frame \((\d+) fps\) at .*?draws=(\d+) objects=(\d+) primitives=(\d+)", line)
        if m:
            label = m.group(1)
            if label not in rows:
                rows[label] = {}
                order.append(label)
            rows[label][r] = m.groups()[1:]
        m = re.match(r"PARTY_PERF built (\d+) levels in (\d+) ms", line)
        if m:
            built[r] = m.group(2)
head = "%-48s" % "view"
for r in renderers:
    head += " | %-34s" % (r + ": ms (fps)  draws  triangles")
print(head)
print("-" * len(head))
for label in order:
    line = "%-48s" % label
    for r in renderers:
        v = rows[label].get(r)
        line += " | %-34s" % ("%6s (%4s) %6s %10s" % (v[0], v[1], v[2], v[4]) if v else "-")
    print(line)
print("world build (all levels): " + ", ".join("%s %s ms" % (r, built.get(r, "?")) for r in renderers))
E
)"
echo "$TABLE"
[ -n "$OUTFILE" ] && echo "$TABLE" > "$OUTFILE"
exit $STATUS
