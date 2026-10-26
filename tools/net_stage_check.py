#!/usr/bin/env python3
"""Network test of whole stage rounds (levels 25-28): the engine's Local Play (one headless authority + N headless clients that join over loopback), the authority
starting the round by itself (bots walk onto the round's lobby circle and press PLAY, then run over the tiles), the real snapshots carrying the step state.

  python3 tools/net_stage_check.py [--levels 25,26,27,28] [--players 2] [--idle-after 20] [--idle-edge] [--seed 1] [--out /tmp/net_stage_check] [--timeout 280]
  python3 tools/net_stage_check.py --judge /tmp/net_stage_check/r25.log      # judge a log of an earlier run, start nothing

Every run is wrapped in `FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 <timeout> <Summer> --path demo --summer-local-play <players> --summer-local-play-headless
--summer-local-play-timeout <timeout-20> -- --autoplay --pick=r<level> --net-probe=<repo>/tools/net_stage_check.gd ...` (the probe, `tools/net_stage_check.gd`, prints the
NETSTAGE_* lines this script reads). Per level it asserts, for every client against the authority:
  * the round starts and finishes (authority and clients print the round's end) within a minute of the idle bots stopping (not at its cap: a player that hangs in the air would hold the
    round open; `--idle-edge` parks them on a tile's edge, where a courier's round feet rest), somebody falls (eliminations >= 1), the clients end with the authority's elimination count;
  * every byte field of the state is at most 240 B (the platform refuses more than 256 B), at the authority and as received;
  * the clients' gone bitmaps (the level world's is_gone, once a second) equal the authority's at the same level clock, allowing a lag of up to LAG_BACK s (the snapshot
    delay) and LAG_FWD s (clock slew); every tile the authority lost is lost at the client within TILE_LAG_MAX s of it (a tile the client never sees go before the round
    ends in its last second excepted);
  * no step-bytes hash of a client is one the authority never published (a drop skips hashes, nothing is ever invented);
  * a tile the client sees white goes within WHITE_MIN..WHITE_MAX s, as the authority's own tiles do; a tile never comes back (gone -> solid: 0 pop-backs; white -> solid: 0);
  * no error lines (SCRIPT ERROR, ERROR:, GW_*FAIL*, submit failures; engine exit leaks excepted).
Prints a table and `NET_STAGE ok=<bool>` last; exit status 1 on a failed check.
"""
import argparse
import json
import os
import re
import subprocess
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SUMMER = "/Applications/Summer Engine.app/Contents/MacOS/Summer"
MAX_FIELD = 240
LAG_BACK = 0.6      # s: a client's bitmap equals the authority's of this long ago at the most (snapshot delay + slew)
LAG_FWD = 0.15      # s: or of this far ahead (the client's clock a little ahead)
TILE_LAG_MAX = 0.6  # s: a tile gone at the authority is gone at the client at most this much later
TILE_LAG_MIN = -0.25  # s: and at most this much earlier
WHITE_MIN = 0.25    # s: a tile white at the client goes no sooner (a late snapshot shows it white late, the clock is the authority's)
WHITE_MAX = 0.62    # s: and no later: 0.5 s of weight + the step byte's 0.05 s unit + a tick
ERROR_LINE = re.compile(r"SCRIPT ERROR|\] ERROR:|GW_\w*(FAIL|REFUS)\w*|submit_failures=[1-9]|publish_failures=[1-9]|Parse Error")
ERROR_IGNORED = re.compile(r"leaked at exit|were leaked")
PAIR = re.compile(r"(\w+)=(\S*)")
LINE = re.compile(r"^\[([\w-]+)\] (NETSTAGE_\w+) (.*)$")


def fields(text):
    return {key: value for key, value in PAIR.findall(text)}


def number(value, default=0.0):
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def bitmap_set(hexed):
    data = bytes.fromhex(hexed) if hexed else b""
    return {i for i in range(len(data) * 8) if data[i >> 3] & (1 << (i & 7))}


class Process:
    """What one process (authority or a client) printed about one round."""

    def __init__(self, name):
        self.name = name
        self.round = None
        self.end = {}
        self.play = {}
        self.events = []       # (clock, kind, tile)
        self.samples = []      # dicts of NETSTAGE_S
        self.hashes = []       # (clock, hash)
        self.errors = []

    def gone_at(self):
        times = {}
        for clock, kind, tile, _unix in self.events:
            if kind == "gone" and tile not in times:
                times[tile] = clock
        return times

    def gone_unix(self):
        times = {}
        for _clock, kind, tile, unix in self.events:
            if kind == "gone" and tile not in times:
                times[tile] = unix
        return times


def parse(path):
    processes = {}
    errors = defaultdict(list)
    states = defaultdict(list)
    with open(path, errors="replace") as handle:
        for raw in handle:
            raw = raw.rstrip("\n")
            match = re.match(r"^\[([\w-]+)\] (.*)$", raw)
            who = match.group(1) if match else ""
            if ERROR_LINE.search(raw) and not ERROR_IGNORED.search(raw):
                errors[who or "?"].append(raw[:200])
            if "GW_AUTHORITY_STATE" in raw:
                states[who].append(fields(raw))
            line = LINE.match(raw)
            if not line:
                continue
            who, tag, rest = line.groups()
            values = fields(rest)
            process = processes.setdefault(who, Process(who))
            process.round = values.get("round", process.round)
            if tag == "NETSTAGE_END":
                process.end = values
            elif tag == "NETSTAGE_PLAY":
                process.play = values
            elif tag == "NETSTAGE_EV":
                process.events.append((number(values["clock"]), values["kind"], int(values["i"]), number(values.get("u"))))
            elif tag == "NETSTAGE_S":
                process.samples.append(values)
            elif tag == "NETSTAGE_H":
                process.hashes.append((number(values["clock"]), values["hash"], number(values.get("u"))))
    return processes, errors, states


def first_difference(auth_times, start, client_set, at):
    """The symmetric difference between the client's gone set and the authority's at level clock `at`."""
    auth_set = set(start) | {tile for tile, clock in auth_times.items() if clock <= at}
    return auth_set ^ client_set


def judge(path, label, idle_after=20.0):
    processes, errors, states = parse(path)
    result = {"label": label, "checks": [], "ok": True}

    def check(ok, text):
        result["checks"].append({"ok": bool(ok), "text": text})
        if not ok:
            result["ok"] = False
        print("NET_STAGE", "ok  " if ok else "FAIL", label, text)

    authority = processes.get("authority")
    clients = [process for name, process in sorted(processes.items()) if name != "authority"]
    check(authority is not None and bool(authority.end), "the authority ran a round to its end")
    check(len(clients) >= 2 and all(client.end for client in clients), "every client saw the round end (%d clients)" % len(clients))
    if authority is None or not authority.end:
        return result
    auth_times = authority.gone_at()
    start = bitmap_set(authority.play.get("bm", ""))
    summary = {"play_s": number(authority.end.get("play_s")), "gone": int(number(authority.end.get("gone"))), "start_gone": len(start), "elim": int(number(authority.end.get("elim"))),
               "tiles": int(number(authority.end.get("max_field", 0))), "clients": []}
    check(summary["elim"] >= 1, "somebody fell (eliminations %d)" % summary["elim"])
    check(summary["play_s"] < idle_after + 60.0, "the round ended by itself %.1f s after the idle bots stopped, not at its cap (%.1f s of play)" % (summary["play_s"] - idle_after, summary["play_s"]))
    check(authority.end.get("pops") == "0", "authority: no tile back from gone (pops %s)" % authority.end.get("pops"))
    check(number(authority.end.get("max_field")) <= MAX_FIELD, "authority: largest byte field of the state %s B <= %d" % (authority.end.get("max_field"), MAX_FIELD))
    a_min, a_max = number(authority.end.get("min")), number(authority.end.get("max"))
    check(WHITE_MIN <= a_min and a_max <= WHITE_MAX, "authority: white to gone %.3f..%.3f s (mean %s)" % (a_min, a_max, authority.end.get("mean")))
    auth_hashes = {}
    auth_hash_unix = {}
    for clock, value, unix in authority.hashes:
        auth_hashes.setdefault(value, clock)
        auth_hash_unix.setdefault(value, unix)
    auth_unix = authority.gone_unix()
    for client in clients:
        name = client.name
        row = {"name": name}
        gone = client.gone_at()
        end_clock = number(client.end.get("clock"))
        check(client.end.get("elim") == authority.end.get("elim"), "%s: eliminations %s = authority %s" % (name, client.end.get("elim"), authority.end.get("elim")))
        check(number(client.end.get("max_field")) <= MAX_FIELD, "%s: largest received byte field %s B <= %d" % (name, client.end.get("max_field"), MAX_FIELD))
        check(client.end.get("pops") == "0" and not [event for event in client.events if event[1] == "solid"], "%s: no tile came back from gone (pop-backs %s)" % (name, client.end.get("pops")))
        check(client.end.get("unwhite") == "0", "%s: no white tile went solid again (%s)" % (name, client.end.get("unwhite")))
        c_min, c_max = number(client.end.get("min")), number(client.end.get("max"))
        row["white_to_gone"] = [c_min, number(client.end.get("mean")), c_max]
        row["no_white"] = int(number(client.end.get("no_white")))
        check(WHITE_MIN <= c_min and c_max <= WHITE_MAX, "%s: white to gone %.3f..%.3f s (mean %s), %d tiles gone without being seen white" % (name, c_min, c_max, client.end.get("mean"), row["no_white"]))
        lags = []
        missing = []
        for tile, clock in auth_times.items():
            if tile in gone:
                lags.append((gone[tile] - clock, tile, clock))
            elif clock < end_clock - 1.0:
                missing.append((tile, clock))
        extra = [(tile, clock) for tile, clock in gone.items() if tile not in auth_times and clock < number(authority.end.get("clock")) - 1.0]
        row["tile_lag"] = [min(lag[0] for lag in lags), sum(lag[0] for lag in lags) / len(lags), max(lag[0] for lag in lags)] if lags else None
        check(not missing, "%s: every tile the authority lost is gone here (missing %d%s)" % (name, len(missing), (": tile %d at clock %.2f" % missing[0]) if missing else ""))
        check(not extra, "%s: no tile gone here that the authority kept (extra %d%s)" % (name, len(extra), (": tile %d at clock %.2f" % extra[0]) if extra else ""))
        worst = max(lags, key=lambda lag: abs(lag[0] - 0.05)) if lags else None
        check(lags and TILE_LAG_MIN <= min(lag[0] for lag in lags) and max(lag[0] for lag in lags) <= TILE_LAG_MAX,
              "%s: tile gone here %.3f..%.3f s after the authority (mean %.3f), worst tile %s at authority clock %s" %
              (name, row["tile_lag"][0] if lags else 0, row["tile_lag"][2] if lags else 0, row["tile_lag"][1] if lags else 0, worst[1] if worst else "-", ("%.2f" % worst[2]) if worst else "-"))
        # bitmaps once a second against the authority's at the same level clock, the lag window allowed
        bad = []
        compared = 0
        for sample in client.samples:
            clock = number(sample["clock"])
            client_set = bitmap_set(sample.get("bm", ""))
            compared += 1
            candidates = sorted({clock - LAG_BACK, clock + LAG_FWD} | {c for c in auth_times.values() if clock - LAG_BACK <= c <= clock + LAG_FWD})
            best = None
            for at in [clock] + candidates:
                diff = first_difference(auth_times, start, client_set, at)
                if best is None or len(diff) < len(best[1]):
                    best = (at, diff)
                if not diff:
                    break
            if best[1]:
                bad.append((clock, best[0], sorted(best[1])[:6]))
        row["bitmaps"] = [compared, len(bad)]
        check(compared > 0 and not bad, "%s: %d once-a-second gone bitmaps equal the authority's (%d differ%s)" %
              (name, compared, len(bad), (": first at client clock %.2f, tiles %s (authority gone at %s)" % (bad[0][0], bad[0][2], [auth_times.get(t) for t in bad[0][2]])) if bad else ""))
        unknown = [(clock, value) for clock, value, _unix in client.hashes if value not in auth_hashes]
        hash_lags = [clock - auth_hashes[value] for clock, value, _unix in client.hashes if value in auth_hashes]
        real_lags = sorted(unix - auth_hash_unix[value] for _clock, value, unix in client.hashes if value in auth_hash_unix)
        row["real_hash_lag_ms"] = [real_lags[0], real_lags[len(real_lags) // 2], real_lags[int(len(real_lags) * 0.95)], real_lags[-1]] if real_lags else None
        unix_gone = client.gone_unix()
        gone_real = sorted(unix_gone[tile] - auth_unix[tile] for tile in auth_unix if tile in unix_gone)
        row["real_gone_lag_ms"] = [gone_real[0], gone_real[len(gone_real) // 2], gone_real[int(len(gone_real) * 0.95)], gone_real[-1]] if gone_real else None
        row["hashes"] = [len(client.hashes), len(unknown), min(hash_lags) if hash_lags else None, max(hash_lags) if hash_lags else None]
        check(client.hashes and not unknown, "%s: %d step-state hashes, all published by the authority (%d invented%s), lag %s..%s s" %
              (name, len(client.hashes), len(unknown), (": first at clock %.2f" % unknown[0][0]) if unknown else "",
               "%.3f" % min(hash_lags) if hash_lags else "-", "%.3f" % max(hash_lags) if hash_lags else "-"))
        print("NET_STAGE   %s real delay (unix clock, ms) min/median/p95/max: state hash %s, tile gone %s" % (name, row["real_hash_lag_ms"], row["real_gone_lag_ms"]))
        summary["clients"].append(row)
    summary["errors"] = {who: lines for who, lines in errors.items()}
    check(not errors, "no error lines (%s)" % ("; ".join("%s: %d" % (who, len(lines)) for who, lines in errors.items()) if errors else "none"))
    for who, lines in errors.items():
        for line in lines[:3]:
            print("NET_STAGE   ", line)
    ticks = [number(state.get("physics_ms")) for state in states.get("authority", []) if state.get("physics_ms")]
    summary["authority_physics_ms"] = [min(ticks), max(ticks)] if ticks else None
    dropped = len(re.findall(r"AUTHORITY_TICKS_DROPPED", open(path, errors="replace").read()))
    summary["authority_ticks_dropped_warnings"] = dropped
    result["summary"] = summary
    return result


def run(level, args):
    os.makedirs(args.out, exist_ok=True)
    log = os.path.join(args.out, "r%d.log" % level)
    command = ["tools/engine_slot.sh", "timeout", "-k", "10", str(args.timeout), SUMMER, "--path", "demo", "--summer-local-play", str(args.players),
               "--summer-local-play-headless", "--summer-local-play-timeout", str(args.timeout - 20), "--", "--autoplay", "--pick=r%d" % level,
               "--net-probe=%s" % os.path.join(ROOT, "tools", "net_stage_check.gd"), "--idle-after=%s" % args.idle_after, "--probe-seed=%d" % args.seed] + (["--idle-edge"] if args.idle_edge else [])
    env = dict(os.environ, FRIENDS_PRIORITY="1")
    print("NET_STAGE run level=%d: %s > %s" % (level, " ".join(command), log), flush=True)
    with open(log, "w") as handle:
        subprocess.run(command, cwd=ROOT, env=env, stdout=handle, stderr=subprocess.STDOUT)
    return log


def table(results):
    print("\nNET_STAGE level  play_s  gone  elim  client: tile lag s (min/mean/max)  white->gone s (min/mean/max)  bitmaps bad/n  hashes n/invented/lag  fps(auth ms)")
    for result in results:
        summary = result.get("summary")
        if not summary:
            print("NET_STAGE %-6s FAILED (no round)" % result["label"])
            continue
        for row in summary["clients"]:
            lag = row["tile_lag"]
            hashes = row["hashes"]
            print("NET_STAGE %-6s %6.1f %5d %5d  %s  %s  %s  %d/%d  %d/%d/%s..%s  %s" % (
                result["label"], summary["play_s"], summary["gone"], summary["elim"], row["name"],
                "%.3f/%.3f/%.3f" % tuple(lag) if lag else "-", "%.3f/%.3f/%.3f" % tuple(row["white_to_gone"]), row["bitmaps"][1], row["bitmaps"][0],
                hashes[0], hashes[1], "%.2f" % hashes[2] if hashes[2] is not None else "-", "%.2f" % hashes[3] if hashes[3] is not None else "-",
                summary["authority_physics_ms"]))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--levels", default="25,26,27,28")
    parser.add_argument("--players", type=int, default=2)
    parser.add_argument("--idle-after", type=float, default=20.0)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--idle-edge", action="store_true", help="the idle bots rest on the edge of a tile next to a hole (the courier's round feet stand there; the round must still end)")
    parser.add_argument("--timeout", type=int, default=280)
    parser.add_argument("--out", default="/tmp/net_stage_check")
    parser.add_argument("--judge", help="judge this log (an earlier run), start nothing")
    args = parser.parse_args()
    results = []
    if args.judge:
        results.append(judge(args.judge, os.path.splitext(os.path.basename(args.judge))[0], args.idle_after))
    else:
        for level in [int(text) for text in args.levels.split(",")]:
            results.append(judge(run(level, args), "r%d" % level, args.idle_after))
    table(results)
    with open(os.path.join(args.out if not args.judge else os.path.dirname(args.judge), "net_stage_check.json"), "w") as handle:
        json.dump(results, handle, indent=1)
    ok = all(result["ok"] for result in results)
    print("NET_STAGE ok=%s" % str(ok).lower())
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
