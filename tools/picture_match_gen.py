#!/usr/bin/env python3
"""Writes PICTURE MATCH's schedule (demo/levels/level_18.json): `cues` and the `blink` hazards of its tiles.

The tile layout is read from the level itself (every distinct `parts` entry of the hazards that are not the start pad), so the file is its own
source: change a tile there, run this, and the cues and the blink schedules follow. `--check` exits 1 when the file differs from what this would write.

The schedule (docs/party-show.md "Survival"): the first cue shows from 5 s and gives 5 s; every next window is 0.75 x the one before it (on the
0.25 s grid) down to a 0.5 s floor, so late cues are too short to cross a floor tile unless the player already stands next to the right one. At
the end of a window every tile that does not wear the shown picture drops, and comes back RETURN s later; the next cue shows GAP s after the drop.
The pictures follow PICTURE_ORDER (fixed, never twice in a row, every picture twice or more; 1 and 2 touch every other picture, so they only
come while the windows are 1.5 s or longer; the short windows rotate 3, 5 and 4, whose tiles are a gap apart).
After the last window the other pictures stay gone and the shown one's tiles fall RETURN s later, so the round is over by 55 s whatever the
players do. Nothing is random: a cue is `{t, until, slot}` in the file and the view and the tiles read the same numbers.

    python3 tools/picture_match_gen.py [--check] [demo/levels/level_18.json]
"""
import json
import sys
from pathlib import Path

LEVEL = Path(__file__).resolve().parent.parent / "demo" / "levels" / "level_18.json"
FIRST_CUE = 5.0        # level clock s of the first cue
FIRST_WINDOW = 5.0     # s the first cue gives
FACTOR = 0.75          # each window is this share of the one before
FLOOR = 0.5            # s: the shortest window
GRID = 0.25            # the level grid for times
GAP = 2.5              # s from a drop to the next cue
RETURN = 2.0           # s a dropped tile stays gone (the floor is whole again GAP - RETURN s before the next cue)
WARN = 1.0             # blink shake s before a drop, cut to leave 0.5 s of the window unshaken (a shake would show which tiles fall)
PICTURE_ORDER = [1, 5, 2, 1, 2, 3, 5, 3, 5, 4, 3, 4]
PHASE = 60.0           # blink schedule offset: a tile that appears at S has on = its stay, off = S + PHASE - on (first cycle again after the cap)
START_ID = "pm_start"


def snap(value):
    return round(value / GRID) * GRID


def windows():
    """[(t, until, picture)] for the whole round."""
    out, t = [], FIRST_CUE
    for index, picture in enumerate(PICTURE_ORDER):
        length = max(FLOOR, snap(FIRST_WINDOW * FACTOR ** index))
        out.append((t, t + length, picture))
        t += length + GAP
    return out


def segments(picture, wins):
    """The stretches [(start, end, warn)] a picture's tiles stand: whole at 0, gone from every drop (the windows of the other pictures) for
    RETURN s, and after the last window gone for good (the shown picture RETURN s later, with the full shake)."""
    stands, start = [], 0.0
    for index, (t, until, shown) in enumerate(wins):
        last = index == len(wins) - 1
        if shown == picture and not last:
            continue
        if shown == picture:
            stands.append((start, until + RETURN, WARN))
            break
        stands.append((start, until, snap(min(WARN, max(0.0, until - t - 0.5)))))
        if last:
            break
        start = until + RETURN
    return stands


def tiles_of(hazards):
    layout = {}
    for hazard in hazards:
        if hazard.get("id") == START_ID:
            continue
        for part in hazard.get("parts", []):
            layout[(int(part["slot"].rsplit("_", 1)[1]), tuple(part["p"]), tuple(part["s"]))] = part
    return layout, next(h for h in hazards if h.get("id") != START_ID)["p"]


def build(level):
    hazards = level["hazards"]
    layout, pivot = tiles_of(hazards)
    wins = windows()
    pictures = sorted({picture for picture, _, _ in layout})
    # (start, end, warn) -> the parts of every picture that stands exactly then: one hazard per distinct stretch
    groups = {}
    for picture in pictures:
        parts = [dict(part) for (shown, _, _), part in sorted(layout.items()) if shown == picture]
        for stand in segments(picture, wins):
            groups.setdefault(stand, []).extend(parts)
    out = [h for h in hazards if h.get("id") == START_ID]
    for number, ((start, end, warn), parts) in enumerate(sorted(groups.items())):
        blink = {"k": "blink", "id": f"pm_{number + 1}", "p": pivot, "on": end - start}
        if start > 0:
            blink["off"] = start + PHASE - blink["on"]
            blink["phase"] = PHASE
        else:
            blink["off"] = 600.0
        blink.update({"warn": warn, "hit": False, "parts": parts})
        out.append(blink)
    level = dict(level)
    level["hazards"] = out
    level["cues"] = [{"t": t, "until": until, "slot": f"obstacle_{picture}"} for t, until, picture in wins]
    return level


def dump(level):
    """The file's style: one line per hazard, block and cue, the rest inline."""
    lines = ["{"]
    keys = list(level)
    for number, key in enumerate(keys):
        value = level[key]
        tail = "," if number < len(keys) - 1 else ""
        if key in ("kill", "blocks", "hazards", "cues", "slots") and not value:
            lines.append(f' "{key}": []{tail}')
        elif key in ("kill", "blocks", "hazards", "cues", "slots"):
            lines.append(f' "{key}": [')
            lines.append(",\n".join("  " + json.dumps(item) for item in value))
            lines.append(f" ]{tail}")
        else:
            lines.append(f" {json.dumps(key)}: {json.dumps(value)}{tail}")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main(argv):
    check = "--check" in argv
    paths = [Path(a) for a in argv if not a.startswith("--")] or [LEVEL]
    text = paths[0].read_text()
    result = dump(build(json.loads(text)))
    if check:
        return 0 if result == text else 1
    paths[0].write_text(result)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
