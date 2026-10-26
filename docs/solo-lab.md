# Solo levels lab

`demo/lab/` (entry `res://lab/main.tscn`): one courier alone, no painting, no second player, no lobby. Every level in difficulty order is a
stop. Offline only: `lab/*` is excluded from the hosted export (`tools/build_domain_graph.py` `STATIC_EXCLUDES`, `stage_hosted_export.sh`) and
is the entry of the standalone app `tools/build_solo_levels.py`.

The lab is a small simulation of its own built from the shell's modules (`LevelWorld`, `CourierMotion` / `CourierRig`, `FollowCamera`,
`GameInput`, `GameAudio`, `LoadSlicer`), the comic UI (`OnlineScreens` loading page, `LevelHud`, `ComicText`, `Ui`, `ComicSkin`). It does not
use `game/game_run.gd`: that role is built for two couriers, a painting and a break flow.

## Files

| file | job |
|---|---|
| `lab/main.tscn`, `lab/lab_main.gd` | boot (loading page, level world, courier, camera, audio), stops, epochs, tick, keys |
| `lab/lab_sheets.gd` | clock, help sheet (keys / keys + stop list), toast, typed number, pause sheet |
| `lab/lab_check.gd` | `--lab-levelscheck` (headless) |
| `lab/lab_shots.gd` | `--lab-shots=<dir>` frames (offscreen build) |

## Behaviour

* Stops: `"<N> <TITLE>"`, N = level number, TITLE = `LevelWorld.title(k)`; any level count (24 in the real data).
* Travelling to a stop starts that level as a new epoch: `set_active_level(k)`, clock 0, `reset_effects()`, the courier on the pad (middle of
  `start_pose(k)`), camera behind it. Only that level is in the tree.
* A kill volume or the void (`zone_at == "kill"`): back on the pad; with G on, back where the courier last stood (sampled every 12 ticks
  while grounded). Ice and launch pads work (`surface_at`, `effects_at`).
* The goal (`zone_at == "goal"`): LEVEL CLEARED card (`LevelHud`, run dict with `clearing`, `times`, `queue`, `next_title`) for
  `LevelRun.CLEARED_SECONDS` (2.6 s), then the next stop; after the last it wraps to 1. The level clock starts with the first move.

## Keys

| key | action |
|---|---|
| W A S D, mouse, Space | move, look, jump (pad: left stick, right stick, south button) |
| Esc / Start | pause sheet: RESUME, `< Level`, `Level >`, Respawn, Restart level, the stops as buttons |
| R | restart the level |
| `[` `]`, PgUp PgDn | previous / next stop (wraps) |
| digits, Enter | typed stop number (commits at once when no longer number fits, or after 0.7 s) |
| N | fly: Space up, C down, Shift fast (14 m/s, x3); no collision, no kill |
| G | no-death |
| H | help: keys, keys + stops, hidden |

## Command line (after `--`)

* `--lab-levelscheck`: stops are named in order; travel to each lands grounded on a floor at its pad with clock 0 and only that level drawn;
  the goal of stop 1 gives the cleared card (`Next: <title>`) then stop 2; the last stop wraps to 1; a fall returns to the pad; G returns to
  the last standing place; typed numbers and previous / next travel. Prints `GW_LEVELSCHECK` lines, exit 0 / 1.
* `--lab-shots=<dir>` with `--lab-poses=<json text or file>` and `--lab-hide-help`: PNG frames. Pose
  `{"name", "stop" (0-based), "ui": "none|help|stops|pause|cleared|loading", "yaw", "pitch", "wait" (ticks), "offset": [x, y, z]}`.

Headless:

    FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 240 <Summer 0.7.2> --headless --audio-driver Dummy --path demo res://lab/main.tscn -- --lab-levelscheck

Frames: the offscreen build, `--summer-offscreen --fixed-fps 60 --resolution 1280x720 ... res://lab/main.tscn -- --glass-style=ink --lab-shots=<dir>`.
