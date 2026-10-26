#!/usr/bin/env python3
"""Table of the worst frame per item and use from the csv tools/modes/items/hitch_scenario.gd writes (--measure=<csv>).

usage: items_hitch_report.py <csv> [<csv> ...]
Columns: item, #, window, worst frame ms (and the frame's process / physics / observe ms, the pipelines compiled in it), the median frame of the idle frames for scale.
"""
import csv
import statistics
import sys

for path in sys.argv[1:]:
    rows = list(csv.DictReader(open(path)))
    idle = [float(r["frame_ms"]) for r in rows if r["label"] == "idle"]
    median = statistics.median(idle) if idle else 0.0
    print(f"{path}: {len(rows)} frames, idle median {median:.1f} ms, idle worst {max(idle, default=0):.1f} ms")
    print(f"{'window':<14}{'worst ms':>9}{'2nd worst':>10}{'process':>9}{'physics':>9}{'observe':>9}{'new pipelines':>15}{'frames>2x med':>15}")
    groups = {}
    for index, row in enumerate(rows):
        groups.setdefault(row["label"], []).append((index, row))
    last_pipelines = 0
    for label, members in groups.items():
        if label in ("idle", "") or "/" not in label and label not in ("warm", "card"):
            continue
        times = sorted(((float(r["frame_ms"]), i, r) for i, r in members), key=lambda t: -t[0])
        worst, at, row = times[0]
        before = int(rows[members[0][0] - 1]["pipelines"]) if members[0][0] > 0 else 0
        after = int(members[-1][1]["pipelines"])
        second = times[1][0] if len(times) > 1 else 0.0
        slow = sum(1 for t in times if t[0] > 2 * median)
        print(f"{label:<14}{worst:9.1f}{second:10.1f}{float(row['process_ms']):9.1f}{float(row['physics_ms']):9.1f}{float(row['observe_ms']):9.1f}{after - before:15d}{slow:15d}")
