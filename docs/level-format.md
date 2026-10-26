# Level file format `level-1` (spec, stable)

One file per level: `demo/levels/level_NN.json`, NN = 01, 02, ... (two digits, contiguous, difficulty order). The loader (`levels/level_world.gd`) probes
`res://levels/level_01.json`, `level_02.json`, ... until one is missing; the count is the number of files. `tools/level_lint.py` checks this spec.

Units: metres, degrees, seconds. Every level is authored in **level-local space**: origin = centre of the start pad at ground height, the course
runs towards -Z (it may turn). LevelWorld puts level k at world x = (k-1) * 300.

## The hand-placement grid (rounding rule)

Everything is placed the way a person places boxes in an editor, so all numbers sit on a grid (the linter rejects off-grid values):

| quantity | grid | note |
|---|---|---|
| positions, sizes, diameters, distances, paths | 0.25 m | sizes at least 0.25 |
| angles `r`, `a0`, `a1`, `rate` | 5 deg (rate: deg/s) | |
| times (`period`, `pause`, `on`, `off`, `warn`, `up`, `phase`, `life`) | 0.25 s | |
| speeds, launch components (`v`, `speed`, `kick`, `up`) | 0.5 m/s | |
| radii (`rad`) | 0.25 m | |

A file may leave the grid only for a documented reason in its top-level `note` string (the linter then prints a warning instead of an error).

## File

```
{
  "format": "level-1",
  "number": 7,                       // equals NN of the file name
  "title": "SLAM ALLEY",             // upper case, at most 24 characters, shown by the HUD
  "blurb": "Two walls, one gap.",    // one short line (optional, default "")
  "rule": "RUN THROUGH THE LOGO  ·  PROBLEMS ARE WALLS",  // show levels, optional: what to do, in plain words, the middle line of the round card (see "Show levels")
  "hint": "THE LOGO POSTER TEARS, THE REST ARE WALLS",   // show levels, optional: the hint under the goal on the round card
  "pool": true,                     // optional, default true; false keeps the level out of Time Attack and Endless (the solo lab still lists it)
  "note": "",                        // free text, optional
  "start": {"p": [0, 0, 0], "yaw": 0},
  "goal":  {"p": [x, y, z], "s": [8, 4, 5], "yaw": 0},
  "path":  [[x, y, z], ...],
  "void_y": -10,                     // optional; below this level-local height counts as "kill" (default -10)
  "kill":  [{"p": [x, y, z], "s": [w, h, d], "yaw": 0}],
  "blocks": [ block, ... ],
  "hazards": [ hazard, ... ],
  "modes": ["carry", "balloon"],     // optional, default ["carry"]: which round modes may use this level ("show": the party show)
  "checkpoints": [{"p": [x, y, z], "s": [w, h, d], "yaw": 0}],   // optional, balloon and show modes
  "slots": [{"id": "obstacle_1", "p": [x, y, z], "yaw": 0, "size": [w, h]}],   // optional, docs/slots.md
  "show": "race",                    // show levels: which round it serves, "race" | "survival" | "final"
  "podium": [[x, y, z], [x, y, z], [x, y, z]],  // the final (required), optional elsewhere: feet spots of 1st, 2nd, 3rd
  "cues": [{"t": 5.0, "until": 10.0, "slot": "obstacle_2"}],  // survival show levels, optional: the picture to stand on, see "Show levels"
  "camera": "stage",                 // optional, show levels: the round is played in the stage view (high and far, free orbit) like the tile stage rounds
  "cap": 240,                        // optional, race show levels: the round's own time cap in seconds (60-600); absent = the round kind's cap (race 100 s)
  "world": "daylight",               // optional, show levels: bright daylight and an open-air world without a cage (see "Show levels"); absent = the cast's own world
  "item_boxes": [{"p": [x, y, z], "n": 3, "step": 1.8, "yaw": 0}],   // optional, race show levels: rows of item boxes the show's items come from, see "Item boxes"
  "tiles": {...}                     // optional: floors of step tiles that fall once stood on, see "Step tiles"
}
```

* **start**: both couriers spawn at `p` +- 1.75 m along the level's local right axis (`yaw` rotated), facing `yaw`. `yaw` = degrees about +Y,
  0 faces -Z (positive turns left, towards -X). `p` must be `[0, 0, 0]`; the start pad is drawn there (green disc). The first block under it
  must be ground (checked by the linter).
* **goal**: a box volume, `p` = its CENTRE, `s` = size [w, h, d], `yaw`. Touching it with the intact painting clears the level. Gold disc and sign are
  drawn on the floor under the box centre (`goal.p.y - goal.s.y / 2`).
* **path**: waypoints along the way, about every 4 to 6 m, from the start pad to the goal (first point near `[0,0,0]`, last inside the goal).
  Used for the look (what is far from the path fades into the dark background, a block's role: ground / hop / wall from its height above the
  path beside it), for the camera hint and by the linter (reachability). Heights are the walking surface.
* **kill**: death volumes (water, void, slime). Any courier inside one: the painting breaks, that courier respawns at the start. `void_y`:
  a courier lower than this (level-local y) counts as inside a kill volume too, so under-floor gaps cannot swallow anyone. Give kill
  volumes where a thing is seen (a pool), `void_y` is the safety net.
  **A kill volume stays clear of every floor a courier can stand on or jump from** (a show level; the linter checks the top of every upright
  block and of every rising lift or slide, at both ends of its travel): a courier's centre is 0.9 m over its feet and a jump reaches 1.5 m more,
  so no volume may reach within 2.4 m over a floor. A volume that touches the lift's top or the platform after it throws the player back to the
  last checkpoint (CROWN CLIMB's `lift_1` did, through a catch volume over the final climb).
* **Moving platforms never overlap anything** (the daylight race levels 29-32; `tools/mover_clearance_check.py`, also run by `tools/level_lint.py` on a `world: daylight` race level, tests
  `tools/test_mover_clearance.py`): at NO time may a `slide` / `lift` come within 0.3 m of another `slide` / `lift`, of a `spin` / `swing` part (a hub, a mast, a bar at any pose), of a `blink`
  block at its solid place or of any static block (floors, walls, pillars, rails, gate frames, belts). The check sweeps every mover over a full period (the least common multiple of the two periods
  for a pair; 0.05 s steps, 0.01 s where two come within 1 m) with the motion formulas of `levels/hazards.gd` (`cycle`: `phase`, `period`, `pause`, `hold`, `ease`), measures the Euclidean gap of the
  parts' boxes (a cylinder as its box, turned as the level turns it) and prints every hit as `level, both names, clock, gap`. Two exemptions, both by construction: a wall that stands on a floor
  (a mover with `hit`: a crate sliding along the court, a door shutting onto its sill) is in contact with the top it stands on and keeps that contact, and a gate door (every part `tone door`)
  touches the `arch` frame and the `navy` wall it is set in. `tools/mover_pose_check.gd` proves the checker's poses equal `Hazards.pose` on levels 29-32. To fix a hit shorten the run, move the
  phase (two movers running along one line need `run < spacing - length - 0.3`), or put them on separate lanes; a ferry keeps 0.5 m of air at both ends of its run.
* A level's content stays within +-150 m of its origin on X and Z and between -40 and +80 m in y (levels are 300 m apart).

## Modes, checkpoints and slots

* **modes**: `carry` (2 players carry the painting), `balloon` (3 to 10 players keep the floating thing in the air) and `show` (the party show, see
  "Show levels" below). Time Attack and Endless
  draw a round's levels only from levels that list the round's mode. Default `["carry"]`. A balloon round plays its levels as ROOMS: every
  `balloon` level in file order (ROOM 01, ROOM 02, ...), one clock, the pops counted (`levels/level_run.gd`). The room number is painted on
  the first wall straight ahead of the start pad (found 7 m up) as a worn stencil, as high up it as it fits (`style/room_number.gd`): the
  follow camera sits behind each player's courier, so a tall wall shows the number over it. The rooms are indoor halls 15 m high with a
  skylit ceiling.
* **checkpoints** (balloon and show modes): box volumes like `goal`, in path order. When the floating thing passes through one, it becomes the restart
  point: after a pop the floating thing and the team restart there (the team on a ring of 1.75 m around the floor under the box centre, the
  balloon 2.6 m above that point; at the start the same ring around the start pad). Each size at least 2 m.
  In a show race or final the racer who falls restarts at the highest checkpoint it has touched (the start before the first), so a level needs
  a checkpoint after every major section (CROWN CLIMB: six), and each volume must cover the whole landing of the section before it (every
  place a player can walk, jump or dash onto), not a slice across the path: the respawn spot is the middle of the volume's floor, so keep the
  middle away from hazards. `tools/lift_ride_check.gd` checks that the respawn spots stand on static floor, outside kill volumes and clear of every
  platform that carries riders (lift, slide, spinner without `hit`); a hammer or sweeper that knocks back over a spot is only reported.
* **slots**: the frames a team's cast fills (signs, posters, logo wall, hidden boards, the team wall); ids, sizes and rules in `docs/slots.md`.
  Ids: `obstacle_1`..`obstacle_5`, `poster_1`..`poster_3`, `logo_wall`, `egg_1`..`egg_5`, `team_wall` (the team's photo board, about 4 x 2.25 m),
  and for show levels `arch_start`, `arch_finish`, `banner_1`, `banner_2`, `billboard_1`, `billboard_2`, `floor_start`, `floor_finish`, `crown`,
  `hero_prop` (below).
  `p` is the centre of the board face, `yaw` 0 faces +Z (back towards the start), `size` is [width, height] of the face. Unknown ids are
  errors; an id may not repeat, except `obstacle_1`..`obstacle_5` on a show level (decor boards, below) and `hero_prop`. At most 64 slots.

## Show levels (the party show)

A level that lists `"show"` in `modes` is played by the party show (`demo/modes/show/`), never by Time Attack, Endless or a balloon run:
it carries `"pool": false` and `"show": "race" | "survival" | "final"` (the round it serves; `CourseSection.show_levels(kind)` lists them).

* **No spectator pen**: a level has no `gallery` (the linter rejects the key). Eliminated players are not moved anywhere: their courier stays where it is, hidden and
  not simulated, and their camera follows the leader (docs/party-show.md "Spectating, podium, crown").
* **podium** `[[x,y,z] x 3]` (required on `final`, 0.25 m grid): the feet spots of 1st, 2nd and 3rd place on the level. The show's ending does not stand on them: the podium phase happens in the podium room
  (`style/podium_room.gd`, far from every course, docs/party-show.md "The victory sequence and the podium room"), whose own pedestals are the state's `podium` spots; the level's list is still required and linted, and
  `style/bunting_rule.gd` keeps pennants out of the 10 m around it, so a level may be tested with it.
  Everybody else is out of the picture for the phase (their couriers are retired, hidden and not simulated).
* **Start gate**: race and final levels hold the racers behind a `blink` hazard with `"id": "gate"`, `"on": 4.0`, `"off": 600`, `"warn": 1.0`
  (solid for the card and countdown, then gone for the round) and `"slot": "gate"` (its two big faces wear the arch's look: the logo, the team
  name and the accent colour of the cast; a wide thin box about 17 x 4 x 0.5 m). The linter warns when it is missing (a blink `on` of at least 3).
  A `blink` may have `on` up to 120 and `off` up to 600 (a tile that falls for good at a given time: `"on": T, "off": 600`); a tile that falls when somebody has stood on it is a step tile ("Step tiles").
* Show levels use `checkpoints` (racers respawn at the last one they passed), the same `void_y` / `kill` volumes and the same limits (600 blocks,
  80 hazards, +-150 m) as every other level; the race's goal is the finish, the final's goal is the crown's volume.
* **`camera`** `"stage"` (optional, show levels only; the linter rejects any other value): the round is played in the stage view of the tile stage rounds (`game/follow_camera.gd` `set_stage_view`: the courier a small figure, 12.1 m from the camera, a free orbit; `game_run.gd` `_sync_stage_view`, `CourseSection.level_camera`). Movement, buttons and HUD stay those of an ordinary round (the stage feel and rules belong to a `stage` section). Unlike the tile rounds, the picture follows a pad's throw up and down (`stage_air_follow`, docs/party-show.md 'The stage camera and feel'). Levels 29 and 30 use it.
* **`cap`** seconds, 60-600 (optional, race show levels only; the linter rejects anything else): the round ends at this many seconds of play instead of the race cap of 100 s (`modes/show/rules.gd` `CAPS`), and the round timer counts down from it. A course of two to three minutes (levels 29 and 30: 240 and 300 s) needs it; `CourseSection.level_cap` reads it.
* **`world`** `"daylight"` (optional, show levels only; the linter rejects any other value or a non-show level): the level gets the stage rounds' bright daylight (`style/candy_light.gd`) and an open-air world
  of its own (`style/race_world.gd`): a skyline of flat blue box skyscrapers under the candy sky (`style/candy_sky.gdshader`), balloons and a blimp, and a little below the platforms the LASERS (`style/laser_floor.gd`: one big beam and four small ones, repeating, with an orange glow where they meet a pillar; the city goes on below them), with no enclosure around the course.
  The world is built around the rectangle that bounds every block, every mover's travel, the path and the goal, plus 6 m, so nothing of the skyline ever stands in the course's footprint; the laser plane
  lies at `void_y` less a courier's centre height (0.9 m): a courier dies exactly when its feet touch the lasers (`tools/laser_plane.py` sets `void_y` of levels 29 and 30 from the lowest block, 6 to 14 m under the lowest floor, and no `kill` volume is needed). Levels 25-28 (the `stage` rounds) have their own world and ignore it. The level's blocks wear the daylight palette
  too (teal floors, navy walls, per-block `tone`, "Blocks" below), and spin hazards, `slide` / `lift` platforms without `hit` and push pads are drawn in it (`style/race_surfaces.gd`, `style/race_hazard_looks.gd`, `docs/backdrop.md` "The race world").
* **`slot`** `"obstacle_1"`..`"obstacle_5"` (and `"gate"` on the start gate hazard) on a box block, on a hazard part (`parts[]` entry) or on a mover's shortcut `s` box: an OBSTACLE BOX. Its
  faces show that cast slot (picture, else a plate in the slot's colour with its label); a cast without that obstacle leaves it a normal block.
  Collision is unchanged. Not on `wedge`; on a `cyl` only the value `hero_prop` (a stand tier, below); a hazard with `parts` carries `slot` on the parts.
* **Pictures and floors** (show levels, `tools/level_lint.py` `lint_picture_floors`, `lint_floor_tops`): a picture face never merges with a floor. A FLOOR is a static box that is not `hit`, stands
  upright (a turn of 90 degrees about y is fine) and is at least 1 m across both ways, or at least 0.5 m across and no taller than 1.75 m (a deck's rim); a tall wall, a post, a cylinder and a wedge are not floors.
  Every picture face (the four sides and the top of an obstacle box; a mover's box at every pose of its travel, quarter steps of a slide or lift, the whole arc of a swing, quarter turns of a spin) must be neither
  **coplanar** with a floor's face of the same direction (within 5 cm, overlapping it: picture and floor fight over the pixels) nor **cut** by a floor (a floor's volume covers part of the face and
  not all of it: the picture runs into the floor). A face buried whole (a pier whose end butts the deck's end) is never seen and passes. So an obstacle box rests ON a floor (its bottom at the floor's top: a
  0.25 m plate becomes a 0.5 m one on the 0.25 m grid) or stands clear of it; a pier next to a deck matches the deck's width or butts it with nothing sticking out; a ledge beside a pier covers the pier's
  whole side or none of it; a deck's rim stands on the deck, not 0.125 m into its side. A decor board in `slots[]` (any id except the decals `floor_start`, `floor_finish`, the crown and a hero prop) may not
  sink into a floor either (a board stands on it). Two floors whose tops are in one plane may not overlap (their tops only touch: a dashed z-fight line along the overlap otherwise). Both checks run on the show levels (14-24) only.
* Extra `slots[]` ids for show levels (placed like the others, once each): `arch_start`, `arch_finish` (a logo arch over the course, face about
  [8, 1.5]), `banner_1`, `banner_2` (hung banners [8, 2]), `billboard_1`, `billboard_2` (boards on posts [5, 2.8]), `floor_start`, `floor_finish`
  (a decal on the floor: `p` on the floor surface, size [width, depth]; the logo is cut to its visible content first, so it lies centred on `p`; `floor_finish` lies on the GOAL pad: its `p` is the goal's
  x / z, the linter errors on a centre more than 0.25 m off, size [5, 5] keeps the logo inside the pad), `crown` (`p` = where the crown floats), `hero_prop` (below).
  **`arch_finish` is the GOAL sign** in every look but the comic one (`style/goal_sign.gd`, docs/party-show.md "The look"): a hanging shield over the finish deck, sized by the deck under the goal volume;
  the slot's `p` gives its place along the course and the height of the V's tip (`p` y less half the size's height), its yaw the facing (the sign reads from both sides), its size nothing. The subtitle is the
  level's title. No other key is read; thin rim walls on or next to the deck are drawn as railings (`style/finish_rails.gd`), their collision is unchanged. In the comic look an arch is drawn.
  With an arch within 12 m of the goal (the comic look's, or a level without the sign) the GOAL word hangs under its beam and the floating logo card is left out when the arch already wears the same logo
  (`style/slot_frames.gd goal_marks`: neither ever reaches the arch).
* **Hero props** (`hero_prop`, `docs/hero-prop.md`): `p` = the bottom centre of the footprint (on the floor), `size` = [footprint, height]. It shows the
  cast's `hero_prop.glb` fitted into that box, else a stepped stand in the brand colours. Its collision is three cylinder blocks you place
  yourself, tagged `"slot": "hero_prop"` (no look is drawn for them, the slot draws the prop): tier i is `footprint x [1, 2/3, 1/3][i]` across
  and `height / 3` tall, centred over `p`, one on top of the other (`{"k": "cyl", "p": [x, y + height / 3 * (i + 0.5), z], "d": ..., "h": height / 3,
  "slot": "hero_prop"}`; every number on the 0.25 m grid). The linter checks every slot has its three and every tagged cylinder belongs to a slot.
  A level with a hero prop draws no GOAL pad, word, flag or logo card (the prop is the goal's mark), and the crown has no pedestal of its own.
  Tiers 1 m tall need a jump, 0.5 m tiers are stairs. The path must end outside the stand but inside the goal volume.
* **Decor boards**: `obstacle_1`..`obstacle_5` may also stand in `slots[]`, as often as the level needs (the 64-slot limit applies): a thin
  board (0.12 m deep) wearing that obstacle's picture, label and colour, `p` = its centre, `size` = [width, height]. It has no collision.
  POSTER RUSH builds its doors from them: rows of boards across the hall, bottom on the floor, wall to wall. A PROBLEM poster (`solid` door) is a wall: it has a hidden block
  0.25 m behind its board (the same width, as tall as the board, so no dash goes over it) and wears the cast's obstacle (picture, word, colour) on a plate inside a yellow and ink
  hazard stripe with a red no-entry mark. The brand's LOGO poster (`open` or `torn` door) is the one that tears: no block, a light board in a green edge with the logo (the team name
  without one), the win word (round r17's `label`, else the show's "qualified" word) and green chevrons and a check mark (`style/slot_frames.gd`, "poster doors"). Which board is which
  depends on the door kind only: whatever obstacle id a logo poster carries (use `obstacle_1`), it wears the logo. Each board of a door row carries `"door": "open" | "solid" | "torn"`
  (below): the level world and the look then know which is which.
* **Poster doors** (`"door"` on an obstacle slot facing along an axis, `levels/poster_doors.gd`): `solid` (a problem poster) has a static box block as wide as the board whose front face is
  0.125 m behind the board's plane (centre 0.25 m behind, 0.25 m deep, from the floor to at least 2 m up), `open` and `torn` (the logo poster) have no block in their opening and are at
  least 1.75 m wide (a courier is 0.7 m across); `torn` is an open door that starts out torn (the idea shown once: the first row of POSTER RUSH has the only one). The linter checks all of it.
  A row is the doors of one plane. Every row has a logo poster; the row nearest the start has exactly one among at least four problem posters; the posters seal the hall between its walls (the
  wall blocks, at least 4 m tall) except slits narrower than 0.6 m and the logo poster's opening, at every pose of the row. What the doors do is a pure function of a courier's feet in
  the door's own frame (and the level clock for a door that moves), so every machine agrees without a message: a courier whose centre goes through the plane inside the opening (width and height) bursts an open door
  (`LevelWorld.observe_doors` -> signal `door_burst`, the look tears the board and throws paper; a jump of more than 2.5 m between two frames is a respawn, not a run); a courier whose capsule
  first presses on a solid door's block gets `LevelWorld.door_push`'s one launch (3.6 m/s away from the board and a 2.2 m/s hop, a `bonk` effect with `hazard` "door", so the slap
  sound plays) and the board shudders (`door_bonk`); a new touch counts after it has left the block by 0.15 m. Doors farther than 4 m (along the board's normal) from a courier are not asked.
  `tools/poster_door_check.gd` proves it with real courier physics.
* **Moving poster rows** (`"ride": "<id>"` on a door slot, the id of a `slide` hazard): the whole row is ONE rigid assembly on that slide: the hazard's `parts` are the hidden blocks of the
  problem posters (each part at the hazard's `p` plus its own `p` is where the static block would stand, 0.125 m behind its board) and the logo poster is the gap between them, with no
  collision; every door of the row carries the same `ride` and `p` = its place at the slide's rest pose (the cycle's start: `to` * 0). The door is where the level clock puts it:
  `PosterDoors.travel(door, clock)` is the slide's travel (`Hazards.pose`, a pure function of the clock, `phase` included), `crossed` and `touching` use the door's travel at the moment of each sample, the
  look (`PosterDoorLook.follow`) moves board and bare doorway with it. Rules for the slide: `hit` false (the posters never knock a courier back: a problem poster only stands in the way),
  no `r`, `to` along the row (across the board, level), `period` at most 10 s with a `pause` so the opening rests, and the assembly wider than the hall
  so its ends hide in the walls: the cells beyond the walls stand in a housing, two static boxes (s.y at least 4, 0.75 deep, centred 0.25 m behind the plane, from the wall's outer face outwards) that are
  not floors (`span` under 1 m). The opening travels inside the hall at every pose and the posters seal the rest (lint: eight poses of the travel), so the way is never closed for good: the opening
  is back where it was within the period.
* **rule** and **hint** (show levels, optional, upper case, at most 48 characters): `rule` is the round card's middle line, what to do in this level in plain words
  (the round kind's default when it is missing: `RACE TO THE GOAL`, `STAY ON THE FLOOR TO THE END`, `CLIMB TO THE CROWN`); `hint` is shown for the first 6 s of play under GO. Both are read
  by the view from the file (`CourseSection.level_rule` / `level_hint`), nothing is replicated. The cast may replace a show level's `title`, `rule` and `hint` for its round (`show.rounds.<round id>`,
  `docs/swappables.md` "Rounds as metaphors"): `CourseSection.level_title / level_rule / level_hint` apply it, `CourseSection.round_id(level)` gives the round id ("r" + the file number of the first
  show level with the same title and kind, so both POSTER RUSH levels are `r17`) from the files' own titles, and the lobby groups rounds by the file's title, never the cast's.
* **cues** (survival levels only, at most 12): what the view's cue card shows. Each `{"t": <s>, "until": <s>, "slot": "obstacle_N"}` shows
  that obstacle's picture and label (the cast's) from level clock `t` to `until`, with a countdown; 0.25 s grid, `0 <= t < until`, in order
  and not overlapping. PICTURE MATCH puts the tiles of that picture on `blink` hazards and drops the others at `until`; the cue is only read
  by the view (`modes/show/plates.gd`), the level clock does the rest. The cues are not a formula the game computes: the file lists them (`level_18.json`
  has twelve, the limit), so the view and the tiles read the same numbers and the schedule is the same on every machine. The windows get shorter
  down the list (5 s from clock 5 s, x0.75 each, floor 0.5 s: 5, 3.75, 2.75, 2, 1.5, 1.25, 1, 0.75, 0.5 ...), each cue shows 2.5 s after the drop
  before it, and the hazards' `on`/`off`/`phase` (a tile that stands from S to E is a blink with `on` E-S, `phase` 60 and `off` S+60-(E-S)) are
  derived from them by `tools/picture_match_gen.py`, which rewrites `cues` and the tile hazards of the file (`--check`: the file is what it
  would write; `tools/test_picture_match_gen.py`). A `warn` shake that would start before a short window's cue is cut so it never shows which tiles
  fall (`warn` = window - 0.5 s, at most 1 s). A survival level draws no START or GOAL pad (its floor falls away).
* **A survival level has no permanent ground** (the linter enforces it): its floor is `tiles` or `blink` hazards, and it has no `blocks`
  at all (`"blocks": []`; the linter takes an empty list on a survival show level only). A ring of ground around the floor, a start deck or a goal pad is a safe zone the round never
  takes away. The `kill` volume must reach well past the floor (a 60 m square under it), the start ring
  (`start` +- 1.75 m for 2 to 10 players) must stand on tiles at level clock 0 (a `blink` pad under the tiles that falls when the first picture
  shows covers the gaps: PICTURE MATCH's `pm_start`), and the goal volume is never read (it needs no floor). `slots` (arch, banners, billboards)
  have no collision; their posts are drawn only over a block, so on a survival level they hang in the air. `tools/lift_ride_check.gd` proves it
  with real physics: 15 s and 40 s into the round a vertical ray over the whole play area finds only tiles and moving bodies, and a courier put on
  spots with no ground under them (`FORMER_GROUND`) falls and is put out by the real rules.
* **`"arena": true`** (survival levels only): the level may have static ground blocks (a platform that stays up), so the no-permanent-ground rule above is off for it; the round must
  still end every player, by hazards that throw them off (spinning bars, pushers) and by a floor that goes in stages (`blink` hazards with `on` T and `off` 600), so that nobody can stand there for the 60 s
  cap. SPIN BARS (`level_21.json`) builds its floor from three stacked `blink` discs (a disc may lie under a smaller one: the larger falls first and leaves a stepped rim) and a `blink`
  pedestal over the start ring whose top is above the floor: the start check (`level_lint.py`) looks under a pedestal that stands on the floor (bottom at y 0 or above) for the ground top at y 0, and the
  players spawn on its top (`team_start` stands them on the highest floor within 1.5 m); the hazards of an arena start moving at level clock 0, the card and countdown included (the level clock runs from
  the card, play starts at about 4 s), so a bar that sweeps the start ring must not be reachable from the pedestal (a bar lower than the pedestal passes under the players' feet).
* **`"play": "badge"`** (survival show levels only): the round is KEEP THE LOGO, not "last ones standing": the rules deal logos, a grab takes one, the wearers at the cap go through (`docs/party-show.md`, "KEEP THE LOGO"); it
  goes with `"arena": true` (the floor stays). Only `"badge"` exists (`PLAYS` in `tools/level_lint.py`).
* **`"solo": false`** (show levels only, default true): the level needs other players: a show for one never draws it and its lobby circle says `NEEDS 2+ PLAYERS` and refuses PLAY.

## Blocks (static)

```
{"k": "box",   "p": [x,y,z], "s": [w,h,d], "r": [rx,ry,rz], "m": "ground", "hit": false, "slot": "obstacle_1"}
{"k": "box",   "p": [x,y,z], "s": [w,h,d], "r": [0,90,0],   "m": "belt", "belt": [vx, vz]}          (a conveyor belt, below)
{"k": "cyl",   "p": [x,y,z], "d": 2.0, "h": 1.0,            "r": [rx,ry,rz]}
{"k": "wedge", "p": [x,y,z], "s": [w,h,d], "r": [rx,ry,rz]}
```
Any block of a `"world": "daylight"` level may add `"tone": "teal" | "warm" | "navy" | "frame" | "door" | "crate" | "eye" | "court" | "disc" | "hub" | "arch"` (see "`tone`" below).

* `p` = centre of the shape's bounding box. `r` = Euler degrees, Godot YXZ order, default `[0,0,0]`.
* `box`: `s` = [width x, height y, depth z]. `cyl`: upright cylinder, diameter `d`, height `h`. `wedge`: a box cut along its diagonal: ramp surface
  rises towards +Z (low edge at -Z, bottom; high edge at +Z with a vertical face), `s` as the box; turn it with `r` (to climb towards -Z: `r = [0,180,0]`).
* `m`: `"ground"` (default), `"ice"` (courier friction drops, see `surface_at`) or `"belt"` (a conveyor belt, "Conveyor belts" below).
* `hit`: default false. `true`: touching the block with the painting breaks it (a wall at hand height, a fence). Couriers collide with every block normally. A `hit` block is never a floor (nobody can stand on it): use it for ropes, panels and caps that must stop a dash (`docs/party-show.md` "Dash exploit audit"); bars spaced less than 1.8 m (a courier's height) block a flight and the camera still sees through them.
* Static blocks are collision layer 1 (layer 8 as well for `hit`). Maximum 600 blocks, 80 hazards per level (`MAX_BLOCKS`, `MAX_HAZARDS` in `tools/level_lint.py`; nothing in the engine counts them).
* Ground should be a few large boxes, not tiles. Two ground boxes whose top faces share an edge keep that edge square (no chamfer between them), so they read as one floor.
* Look roles are derived: a block whose top is less than 0.75 m above the path beside it is ground, up to 1.75 m a hop block, above that a wall;
  hazards are always drawn red/orange; ice gets the ground look with a pale blue tone; a belt is a floor wherever it stands (never a hop block or a wall).
* **`tone`** (optional, boxes, cylinders and wedges of a `"world": "daylight"` level only; the linter rejects any other value, or a level without the world; on a hazard part only for the parts of a `slide` / `lift`: a sliding or sinking wall panel or door wears the surface of its `tone` and keeps the moving look, no grey ride pad): the surface the block wears
  in the candy look (`style/race_surfaces.gd`: flat authored colours from the cast's course scheme `style/candy_course.gd`, glossy, one shared material per colour and pattern). Without it a block is dressed by its role: floors (ground and hop blocks) `teal`, walls `navy`; ice keeps its own look and
  a belt's sides are `teal`. Every cycling door (a tall thin box of a `blink` hazard that carries no picture) wears `door` by itself. P, S, A are the cast's first three brand hues, or blue, purple and amber without brand colours.
  | `tone` | look | for |
  |---|---|---|
  | `teal` | the P floor tone, vinyl 0.45; a floor block is one PILLOW slab: its open top edges are inflated into a rounded shoulder of up to 0.45 m (smooth normals, only going down and in: the top stays exactly in the collision plane), a big floor is a quilt of ~5 m mats whose seams are soft pinched creases | floors, courts, stepping stones (the floor default) |
  | `warm` | the A accent floor (amber), the same slab | long accent decks |
  | `navy` | the S pillow wall: a box rounded by up to 0.95 of half its thickness (0.34 m at most), vinyl; any navy box is a pillow | walls (the wall default), blocks between and around gates |
  | `frame` | S, hard plastic 0.11, door-sized rounding 0.09 m (a slim tall one is a column of pillow segments; a long beam, over the route or not, is an inflated tube of touching sections of about 2.6 m: the rounded ends are the pinches) | door frames, gate piers |
  | `door` | a door slab: white hard plastic with S diagonal stripes mirrored about the middle (a chevron, `candy_surface` pattern 2) on both big faces, plain S on the two narrow ones | door slabs (a box about 0.5 m thin; also the part of a gate wall's `lift` door); the START gate's door (slot `gate`) is DRAWN only 1.7 m high from its foot, as a rounded cushion barrier (its collision stays the whole door), so the course behind it is in view |
  | `crate` | white vinyl | crates set into a wall |
  | `eye` | for a cylinder: both flat ends are a white disc with a dark pupil (the cap's own unit-disc UV, `BlockMesh.Batch.lathe` `unit_caps`), the rim S plastic | the two small eyes on a gate frame |
  | `arch` | not drawn by the block kit: the collision of a gate frame (piers, beam, and the core over the opening). `style/gate_look.gd` draws ONE rounded-arch frame for every core, or one shared slab with a window per core for cores of one row whose openings are 1.0 m apart | `tools/gate_piece.py` only |
  | `court` | the light P tone, vinyl; a walkable court is a kit slab | the floors of courts |
  | `disc` | for a cylinder: the top is amber with white concentric rings, deep amber sides | spinner discs |
  | `hub` | S hard plastic on every face | the hub of a spinner disc |
  | `slime` | glossy pink (the world's slime colour), roughness 0.05 | the slime slope of level 32 |
  | `finish` | a white / dark chequered top (1 m squares), white sides | the finish strip |
  The colours are the authored colours: the light rig of `style/candy_light.gd` decides what the player sees.

**Gate walls** (`tools/gate_piece.py` `gate_wall(...)`, used by `gen_level_29/30`): ONE navy panel wall block per stretch between the doorways, a crafted frame (tone `arch`
collision, drawn by `style/gate_look.gd` as a single purple rounded arch with an amber lip; frames that touch in one row (openings 1.0 m apart) are drawn as ONE slab with a window per doorway and a shared flat mullion between them, only the ends of the row and its top corners are rounded, no seam, no slit) with two small `eye` discs on top, and a blue chevron door (`tone door`) per doorway. A
door is a `lift` without `hit` whose rest pose is OPEN (up in the top half of the frame, in front of the `arch` core) and whose negative `rise` (-h) brings it down to shut, so it never
goes under the floor; `period` 4 s, `pause` 1.25 s (open and shut rests, 0.75 s of travel each way). See the module docstring for the geometry and the call.

**Narrow safe decks** (levels 29, 30): a deck with nothing on it is a walkway with void on both sides, not a hall. Level 30: court 1 and court 2 are 8 m necks (`NECK` 4 m a side; their gate walls span exactly the neck, the two doors stay at +-1.5) that turn into 12 m corner walks (court 1: x -4..20, z -134..-121.5, the dock of the first ferry crossing; court 2: x 92.75..105, z -134..-116, the start of the second crossing), court 2 keeps a 17 m x 5.5 m apron where the three landing pillars (17 m together) open onto it; the turn deck after the maze is 8.5 m (u -3.25..5.25, the route on its left and the pad's tile cell on the right), the long deck is an 8 m walkway with an 8 m arm that turns west (z 81.5..89.5, the width of the checker deck it jumps to) and the long checker deck is 8 m. Level 29: the plain teal deck before the tower-base cluster is 10 m (the pedestal throws land 3 m either side of the middle, 2 m inside the edges). Kept wide on purpose: every start and finish deck, the decks that carry launch pads and their landings (pad margin 1.5 m), the 18 m gate deck, corridor and first stone of level 29 (the cross belt before them carries a courier 7 m sideways, they catch the drift), level 30's court 3 (crates slide across it, five-door walls), the apron and the platform between the landing pillars and the belts (they are as wide as the pillars), every deck under a spinner, and level 32's 30 m hall (its gate rows of 3 to 8 doors span it); level 31 has none.

### Conveyor belts (`"m": "belt"`)

A static `box` with `"m": "belt"` and `"belt": [vx, vz]` carries every courier that stands on it. `belt` is the velocity of the belt's surface in level-local m/s
(a level is not turned, so its x and z axes are the world's): the 0.5 m/s grid, a length of 0.5 to 8 m/s (`[0, -3]` runs 3 m/s towards -Z). Two belts side by side may run opposite ways;
a belt may stand on an `ice` block (ice friction and the carry both apply).

* **Rules** (`tools/level_lint.py lint_belt`): `belt` is required with `m: belt` and forbidden without it; the block is an upright `box` (`r` only turns it about y by 0, 90, 180 or 270),
  not `hit`, and not a hazard part. It counts as a floor for every floor rule (start and path support, kill-volume clearance, pictures never merge with a floor, coplanar tops).
* **Physics** (`levels/level_world.gd surface_at` / `apply_effects`, `courier/courier_motion.gd set_belt`): the same test as ice (a ray from 0.4 m over the feet down; the feet are within 0.4 m of the
  belt's top), over the belt's footprint made 0.35 m longer at its downstream end (`Hazards.BELT_RIM`: a courier at rest on the rim hangs there on its round foot and would perch for ever; it is carried off and falls).
  While the courier was grounded at the start of the tick, its planar velocity is taken RELATIVE to the belt for the ground rules (turn, accelerate, brake, friction, the belly slide of a
  flop) and the belt's velocity is added back. A courier standing still on a 3 m/s belt is carried at 3 m/s (it takes the speed up with the ground brake, about 0.15 s, when it steps on); walking with the
  belt adds the walk (5 + 3 = 8 m/s), walking against it at 5 m/s against a 3 m/s belt nets 2 m/s the walker's way. A jump or a walk off the edge keeps the velocity the courier had, and the
  air rules take it from there (an air brake of 15 m/s^2 with no input, as for any other speed). The dash is its own velocity and ignores the belt. A pure function of the feet and the level: nothing
  is sent, the owner's tick, a bot's and a replica's owner tick all go through `apply_effects` (`game_run.gd _apply_level_effects`) and agree. `CourierMotion.set_surface({})` also puts the belt away;
  the belt rides in `capture` / `restore` (`belt`).
* **Look** (`style/real_look.gd`, `style/block_mesh.gd Batch.belt`, `style/belt_look.gdshader`; the party and the night look both draw it, the comic look draws a plain floor): a near-black rubber
  lane between two yellow rail strips (0.2 m) along the sides the belt runs along, with bright green chevrons (period 1.0 m) that run the way `belt` points at the belt's own speed
  (a scrolling shader: the picture only, the clock is the frame's `TIME`). One material per direction and speed: all belts of one velocity are one draw call (a surface of the level mesh).
* **Belts in the race levels** (29, 30; `tools/gen_level_29.py` / `gen_level_30.py`): a belt ACROSS the course (`BELT`, 7 m/s = 1.4 x the courier's walk of 5 m/s) throws a courier that stands still off within
  about 1.5 s, so it is crossed by a straight run (and the maze's steps by a jump); a belt that runs BACK along the course (`BELT_LANE`: 3.5 m/s in 29, 2.5 m/s in 30) stays under the walk,
  because a faster treadmill could not be run up at all (net speed = 5 - `BELT_LANE`). The chevrons scroll at the length of the block's own `belt` vector (`style/real_look.gd` `_belt_material`, one value:
  the level file), so the picture and the carry always agree. `python3 tools/belt_jobs.py /tmp/belts.json` + `tools/belt_cross_probe.gd` prove it with the real courier (see docs/build-tooling.md).
* **Check**: `tools/belt_check.gd` (a courier on a 3 m/s belt, walking with and against it, stepping off, the opposite belt next to it; `tools/level_testdata/belt/level_01.json`).

## Hazards

Every hazard is a **pure function of the level clock `t`** (seconds since the level epoch, the same number on every peer, no physics, no random).
`phase` (seconds, default 0) shifts the hazard: it runs at local time `tau = t + phase`.

Common fields: `k`, optional `id` (unique string within the level), `p` pivot / rest position (level-local), `r` base rotation (like blocks),
`phase`, `hit` (default per kind below). A hazard with a body has `parts`: a list of blocks (`k` box/cyl/wedge, `p` and `r` relative to the hazard
pivot, no `m`/`hit` keys, optional `slot`) or the shortcut `"s": [w,h,d]` (one box centred on the pivot, optional `"slot"` on the hazard). All movers are `AnimatableBody3D` on layer 16 (couriers
stand on and are carried by them), plus layer 8 when `hit`. Launch hazards and kill volumes have no collision.

**The bonk.** A mover with `hit` (swing, spin, slide, lift, ball, cannon; a `hit: false` platform only carries) throws every courier it touches the way it
moves, so an obstacle is an obstacle and not a wall you lean on. A courier touching a hazard point that moves faster than 0.75 m/s, and that closes in on it
by at least 0.5 m/s along the contact normal (a wall sliding past the courier's face does not throw it, its end does), gets, once per 0.4 s: horizontal velocity `8.5 + 1.0 * speed` m/s (at most 15) along the hazard point's own horizontal velocity
(a hammer head, the tip of a spinning bar, a sweeper wall), and 6 m/s up. A hazard that moves mostly up or down (a stamping lift) throws the courier away from
the hazard's centre (x 1.25 power, half the up speed when it comes down). The mover a courier stands on never bonks it (riders are carried). The hazard point's
velocity is its pose a probe either side of the clock, so each machine computes the same throw from the level clock alone (`level_world.gd bonk_at`,
`apply_effects`; the constants `BONK_*` there). Push pads and bumpers win over a bonk on the tick both would fire. `tools/bonk_check.gd` proves it: a scripted
courier standing in, and one walking into, each hazard kind (`tools/level_testdata/bonk/level_01.json`) is thrown at least 3 m (a bumper 1.5 m, its throw is mostly up).

**The fling (race levels).** In a `world: daylight` level a bonk by a `spin` hazard (spinner, wheel, windmill) is a fling: horizontal launch speed `8.5 + 1.0 * speed` clamped to 12..16 m/s
(`FLING_MIN` / `FLING_MAX`), 6 m/s up (`FLING_UP`), along the bar head's tangent; a throw within 0.7 (|cos|, `FLING_ALONG`) of the course's own direction at the courier (a wheel across a
walkway sweeps along it) is turned to the side of the course the courier stands on, so a hit sends it over the edge. No level key: every hit `spin` of a daylight level; levels 1-24 and the
stage rounds keep the plain bonk. `tools/bonk_check.gd` (`check_race_flings`) stands a courier in the sweep of every such hazard of levels 29-32 and demands the launch and, except where the level's own
solids catch it (the `CAUGHT` list: gantry posts, hall walls, the next disc of a field), a fall under `void_y` within 9 s.

**Passable flings (race levels).** The fling stays, so a sweep a courier cannot get through would be a wall: every cluster of hit `spin` hazards whose in-plane sweep touches the route
(clusters merge when their reach is under 8 m apart along the route) has to be crossable by waiting and then walking, or it is reported. Windmills, wheels and the bars of discs keep the
base rates scaled for our courier (150 x 0.69): 105 deg/s for the windmills, wheels and route discs of levels 29 and 30 (120 for the second set of discs), 120 to 135 for the bars of
level 31 and -120 for its four-paddle wheel. The ONE slow cluster is the field of six small spinner discs under level 30's big windmill (`DISC_B`, 35 deg/s: two rows with a stone between
them). Where a bigger sweep at the full rate leaves no window, the check says so (`SPIN_PASS FAIL`, the steady and careful strings per cluster) and the
rate is NOT cut for it. At these rates it fails (steady starts through of 60, widest window against the 0.6 s needed, careful starts of 24): level 29 `disc_a` 0, 0.0 s, 0;
`spin_x1` 12, 0.4 s, 0; `spin_x2` 16, 0.4 s, 0; `spin_x3` 20, 0.4 s, 0; `disc_r1_2` 0, 0.0 s, 0; `wheel` 20, 0.4 s, 0; level 30 `disc_a1` 0, 0.0 s, 0; `wind_a1` 0, 0.0 s, 0; `wind_b1` 0,
0.0 s, 0; `wind_big` with `disc_b2` 3, 0.4 s, 0; level 31 `wheel` (the four-paddle cross at -120) 0, 0.0 s, 0. Passing: 29 `disc_c`, `disc_r3_2`, `disc_r4_c`; 30 `disc_b5`; 31 `wind_1` and
`wind_s2, wind_3, wind_4` (the careful walker 24 of 24). The bars, sizes and masts GateSpin made stay.
Where a sweep crosses a path the arms reach the whole width of the platform or walkway, the lowest tip 0.5 m over the deck, the hub hangs over the path from a frame (posts and a lintel
`dome_offset` m before the arms' plane, so the frame never touches the sweep; generators: `windmill_frame` in `tools/gen_level_30.py`, `carrier` and `mast` in `gen_level_29.py`).
`tools/spinner_pass_check.gd` (`--levels=29,30,31,32 --only=<hazard ids> --quick --trace`) walks a real courier through each cluster from every start of the 24 s cycle: the steady walker
(never waits) must get through from a run of start times at least 0.6 s wide, or the careful walker (looks 1.2 s ahead, waits on safe floor) from 90 % of its starts, and at least 30 % of the
steady starts must be flung (a careless run usually is). It prints `SPIN_PASS ok|FAIL ...` per cluster and `SPIN_PASS ok=<bool>`, exit status 1 on a failure.

### The shared motion curve `cycle(tau, period, pause, ease) -> f in [0,1]`

One round trip lasts `period`. At each end it dwells for `pause` (default 0); the rest is split into the way there and the way back. `f` = 0 at the
start (tau = 0, and for `pause` seconds), rises to 1, dwells, returns. `ease`: `"sine"` (default, smooth), `"linear"`. Requires `period > 2 * pause`.

### `slide`: platform / wall sliding between two points
`p` start A, `to` [dx,dy,dz] offset to B (level axes), `period`, `pause`, `ease`, `parts`/`s`. Position `p + to * f`. Default `hit` false
(a platform you ride); set `"hit": true` for a sweeping wall (it then bonks couriers sideways, see above).

### `lift`: vertical slide with long dwells
Like `slide` with `to = [0, rise, 0]`: fields `rise` (m), `period`, `pause` (default 1), `ease`. Default `hit` false.
`hold` (optional, default = `pause`): the dwell at the far end of the way (`pause` at the rest pose, `hold` at the other); `period` must exceed `pause + hold`. A **gate door** (`tools/gate_piece.py`, all of levels 29-32, `hit: false`: a door is solid, it stops a courier that walks into it and never throws anybody; one that comes down on a courier only moves it out of its volume, see **Gate doors** below) is a `lift` with a part of tone `door` whose rest pose is OPEN (up in the frame) and a negative `rise` that brings it down; `pause` is its open dwell, `hold` its shut dwell, `phase` when it starts to open.

**Gate doors never push.** A gate door (`lift`, `hit: false`, a part of tone `door`; also the start gate, a `blink` with slot `gate`, `hit: false`) is solid collision like any wall and never a bonk:
no impulse, no bonk event, no sound. A courier that walks into a shut door stops against it. A courier that stands in the way of a door coming down is moved out of the door's volume by
`LevelWorld.door_nudge` (called from `apply_effects` every tick): the shortest of the four horizontal ways out of the door's box (grown by the courier's radius, read `DOOR_LEAD` = 2 ticks ahead
of the clock so the courier is clear before the door body arrives), at most `DOOR_NUDGE_STEP` = 0.25 m a tick, only along a way that is free (`test_move`), never down into the floor and
no velocity: a courier in the middle of a 0.5 m deep door moves 0.6 m (its radius 0.35 + half the depth 0.25), one at the face moves what it overlaps. `tools/gate_check.gd` proves it on level 32
(stand under a closing door, half in it, run into a shut, rising and closing door: no bonk effect, no launch above 1 m/s, never under the floor, moved at most 0.7 m) and that no door or
start gate of levels 29-32 has `hit`.

### Slime slopes (`"m": "slime"`)
A `wedge` block (not `hit`, turned about y by 0/90/180/270 only, at most 20 degrees) with `"m": "slime"` and `"tone": "slime"` is a slippery slope: its downhill is the wedge's low edge, every courier on it is pushed that way (6 m/s^2, ground speed at most 11, airborne at most 15, low friction, a jump adds 2 m/s along the slope: `courier/courier_motion.gd` SLIME). A pure function of the feet and the clock like ice and belts; `tools/gate_check.gd` slides, hops and steers on level 32's.


### `spin`: constant rotation (rotating platform, barrier, disc)
`axis` "x" | "y" | "z" (hazard-local, default "y"), `rate` deg/s (signed, 5 deg/s grid, -180..180: a bar that turns every 2.5 s is 144), `parts`/`s`. Angle `rate * tau` about `axis`, applied after `r`.
Default `hit` true (barriers), set false for a platform you stand on.
**A turning floor** is a `spin` with `hit: false`, axis `y` and a `cyl` part (a disc) at the pivot: a courier on it is carried round the axis by the mover's transform delta like on any other mover (level 31's discs; `tools/disc_ride_check.gd` rides each one: the courier covers the disc's own angle within 12 degrees and a walk-on is carried). A disc has no visible turn by itself, so give it an off-centre part (a flat pointer bar of at most 0.25 m above the top: a step the courier takes in stride).
**A bumper bar:** a box part of a turning floor with `"bump": true` bounces whoever touches it, like a bumper: `kick` m/s (default 9, hazard key, `Hazards.BAR_KICK`) horizontally away from the bar's plane (along
its width, the side the courier is on; from on top of the bar the side it is nearer to) and `up` m/s (default 4, `BAR_UP`), `kind` "bumper" (the bumper sound and `override` launch of `apply_effects`), once per `BONK_COOLDOWN`.
The touch is geometric (the courier's axis and radius against the bar's box at the clock's pose: `LevelWorld.bump_at`); the look draws such a bar as a mesh of its own (`RaceLook/Bar<part>`) that
squashes for a moment on a hit (`TurntableLook.pulse`). Level 31 gives the pointer of every disc of 4.5 m or more (the diamond's four and the big disc) this; the small discs keep a plain bar.

### `swing`: pendulum, hammer, gate that turns
`axis` (default "x"), `a0`, `a1` (degrees, the two end angles), `period`, `pause`, `ease`. Angle `a0 + (a1 - a0) * cycle(...)` about `axis` at the pivot `p`;
`parts` hang from the pivot (a hammer: arm box with centre `[0,-2,0]`, head box at the end). Default `hit` true. The pivot hangs from something: lint requires a
solid block (a gantry beam, a lintel, a wall) through it, within 0.25 m. Keep the swing inside the lane (a hammer that only reaches the lane at its slow turnaround is no obstacle).
A gate that flips 180 deg: `a0 = 0, a1 = 180, pause = 2`.

### `blink`: platform that falls away and returns on a schedule
`on` s solid, `off` s gone, `warn` s (default 1): the last `warn` seconds of `on` the block shakes (visual only, still solid), `parts`/`s`.
Cycle length `on + off`; solid while `tau mod (on+off) < on`. Collision (layers 16/8) is disabled while gone. Default `hit` true. Limits: `on` 0.5..120, `off` 1..600
(a block needs `levels/hazards.gd` BLINK_MIN_OFF, 0.9 s, to fall out of reach and come back; the linter rejects a shorter `off`).
Trigger-on-touch tiles from a hand-placed level become periodic: pick `on`/`off` so neighbours form a rhythm.
**Nothing vanishes into nowhere.** A block that is gone is never hidden: from the moment it stops being solid it falls straight down (an accelerating fall: its own
height plus 2 m in 0.4 s, much faster than a courier falls, so nobody is left standing in it) and hangs there, drawn, out of reach; in its last 0.5 s of `off` it climbs
back and arrives exactly when it is solid again. A block whose `off` is 20 s or more is gone for the round (a floor that goes in stages, the start gate, a picture's
tiles): it keeps falling to 60 m under its place, far out of sight, and climbs back in its last 2 s of `off` (a swoosh seen only over its last metres: the tiles of a picture that stands from S to E come up into place just before S). A gate or pad standing on a floor sinks into it. So a level needs
room under every blink block: the open air (the backdrop's world far below) or a floor that hides the fall, never a solid thing the block would fall through in view.
The fall decides only where the block is while it is not solid: `on` / `off` / `warn` / `phase`, the collision window and the sounds are the schedule's, the same on every peer.
Checks: `tools/blink_drop.py` (the arithmetic, `tools/test_blink_drop.py`) and `tools/vanish_check.gd` (every blink of every level in the engine: stands while solid, collides exactly
while solid, never hidden, hangs at least its thickness + 2 m under its place while gone, no jump between two frames, back at its place when solid again).

### `spikes`: spikes in the floor
`p` = position when fully up, `rise` (default 2.5): how far below `p` it hides, `period` (0 = always up, static), `up` s fully up per period, `warn` s (default 0.5):
the spikes peek out 0.25 m before rising, `parts`/`s`. One period: hidden, `warn`, rises in 0.5 s, up for `up`, sinks in 0.5 s (`period >= warn + up + 1`).
Always `hit` true: touching them with the painting breaks it; couriers are not hurt, they are only blocked by the solid.

### `push`: launcher pad (volume, no collision)
`g` "box" (`s`) or "cyl" (`d`,`h`), `p`, `r`, `v` [vx,vy,vz] launch velocity in m/s (world axes), `ride` optional: the `id` of a hazard the volume rides on (then `p`,`r`
are relative to that hazard's pivot). On entering the volume a courier's velocity becomes `v` (override xz and y). The volume itself is invisible: it is drawn as a
flat pad on the block under it (the brand accent with chevrons running the way of the throw), so the volume's underside must be within 1 m over a block top (lint error otherwise;
a `ride` launcher is exempt, its pad is drawn on the hazard it rides). Every component of `v` is at most 36 m/s (lint error otherwise). A pad throws the courier to a target on the course:
the generators design it with `tools/pad_design.py` (`design_pad`: the real flight of `jump_reach.pad_flight`, the stick held along the throw; landing at least 1.5 m inside the target, at least 1 m over its near
edge) and `tools/race_jump_probe.gd` flies every pad (`pads` of `--emit-jumps`). A pad whose small stone exists only to hold it (a 3 x 3 tile stone of 4.5 m; the pad stands in its middle and its volume is
about as wide as the tile grid, `d` = the grid's side less 0.2 m) is drawn over the whole stone: one big round pad on the tile grid minus the rim, the corner strips and the button scaled up
(`style/pad_look.gd cell_side`, `tools/kit_grid.py full_cell`, `tools/pad_cell_check.gd`); a pad on a bigger platform keeps its 2 x 2 cell. Far throws (up to 36 m/s, up to 38 m along the ground, apex 9 m over the pad) are
level 29's four pedestal pads: `hop_start_l/r` throw over the lane band, disc A and the first cross belt onto the dark deck (35 m), `hop_entry_l/r` over the three disc rows onto the plain teal deck (38 m).

### `bumper`: bounce ball (volume, no collision)
`rad` sphere radius, `p`, `kick` (default 7.5 m/s horizontal, added), `up` (default 15 m/s, vertical, replaces), `ride` optional (see push). What is drawn is what bumps: the
courier is thrown the moment its body (the capsule, 0.35 m round its 0.55 m half-segment, `level_world.gd _bumper_touched`) touches the ball's outer surface, the band round it included
(`rad` + `Hazards.BUMPER_BAND` 0.1 m, the look's `ring.outer_radius`), so no part of a courier is ever inside the ball it sees. The throw is away from the centre: direction
`d = normalize(courier centre - ball centre)`; velocity `xz += d.xz * kick`, `y = max(d.y, 0.5) * up`. Drawn as a ball with a band on a base disc and a
post standing on the block under it (same lint rule as push). `tools/bonk_check.gd` (lane `bumper_walk`) walks a courier at one and fails if it is thrown more than 0.2 m inside the drawn ball.

### `ball`: rolling ball on a schedule
`path` [[x,y,z], ...] ball CENTRE points (2 or more), `speed` m/s, `rad`, `period` (whole cycle, >= path length / speed), `phase`. The ball starts at path[0] at
tau mod period = 0, rolls at constant speed, vanishes at the end until the next period. Always `hit` true, collision layers 16 + 8, couriers are shoved.
**It never pops in or out in view.** Both ends of the path are housed, found from the level's blocks (`levels/hazards.gd` `ball_ports`, drawn by `style/shot_looks.gd`):
an end within 0.3 m of a wall (centre distance - `rad`) is a **wall slot**: the ball is drawn rolling on through a round slot in the wall face (a dark disc with a rim in the
brand accent) until it is fully inside, and comes out of the slot the same way; an end over a floor is a **floor hole**: the ball comes up out of a dark slot in the floor while it
speeds up and sinks into one while it slows down (0.5 s each); the drawn extra is harmless (`Pose.lead`: no collision, hit volume and timing are exactly the path's). The period holds
the path plus those lead times (wall slot: (distance to the wall + `rad` + 0.1 m) / `speed`; floor hole 0.5 s). The linter (`tools/shot_plan.py`) rejects an end with neither
wall nor floor and a period that is too short.
**A ball rolls where it can, and the linter checks it** (`lint_ball_path`): (1) the centre is sampled every 0.25 m along the path and never sinks more than 0.05 m into a block
(`rad` clear of every wall, post, floor; a block that holds an end of the path, a ball that starts inside a thick wall, is its housing and is skipped); (2) every bend of more
than 5 degrees is a **bounce**: a wall face straight ahead of the bend, the centre `rad` (+-0.3 m) from it, and the way out within 6 degrees of the mirror image of the way in
(so a zigzag path reads as a ball ricocheting between the walls: put the vertex at x = wall face -+ `rad`, and the next vertex on the mirrored line); (3) an end in a wall slot meets
the wall square on (within 10 degrees), because the slot is drawn flat on the wall face: a diagonal path ends in a floor hole instead (the end at least `rad` + 0.3 m from every wall
along its heading). A ball that houses itself in a side wall that is thin sits in front of a "chamber": a solid block right behind that wall (no gap), so the rest of the ball's lead,
after it has passed through the slot, is hidden inside solid; the path itself starts at the road side face of the wall minus `rad`, so the slot decal is on the wall the player sees.

**The look** (`style/shot_looks.gd`, party and night looks only; other looks keep the collision look). The ball is a lathe sphere of the world style's palette, not red: night
uses the accent role's main and pale colours (glow grid), party the palette roles `a` / `p` / `x` (stripes) darkened or lightened against both floor colours of the world
(`tools/party_look_check.gd` checks at least 2.0 : 1 for the body and 1.4 : 1 for the stripes in every palette, 3.0 : 1 in the night looks). Size picks the role: radius 1.4 and up
role `a`, 0.7 and up role `p` (cannon balls included), smaller role `x`, so three sizes read as three kinds. In ROLLING ROAD (round `r23`) the big balls carry the cast's
`round_labels("r23")` words, four flat labels on a ball (the roll axis and up), cycling by ball index; `round_model("r23")`, when the cast has one, replaces every sphere (fitted to
the ball's diameter, turning with the roll, no labels). The ball's orientation follows its path: a bounce turns the roll axis with the heading (`Hazards._ball_roll`), so the
look never jumps at a bend.

### `cannon`: fires a ball that lands, bounces, rolls on and goes into a wall
`p` muzzle, `v` launch velocity [vx,vy,vz] m/s, `rad` ball radius, `period`, `life` s the shot may last (default 3, at most `period`), `phase`, `parts` for fixed extra geometry
(static, layer 1, placed relative to `p` with `r`; the barrel itself is drawn for you, see below, so a level does not add one). The ball flies `p + v * s + [0, -0.5 * 17 * s^2, 0]`
with `s = tau mod period` until it lands on the floor under it, bounces (it keeps 0.5 of its fall speed and 0.85 of its flat speed; a bounce under 2.5 m/s is a roll), rolls on
across the floor until a wall swallows it (the same wall slot as a rolling ball's) or the floor ends under it (it falls 14 m). The whole path is a pure function of the clock built
from the level's blocks once (`hazards.gd` `shot_plan`, mirrored by `tools/shot_plan.py`), so every peer sees the same, and the ball hurts for all of it (`hit` shows until the
wall touches it); the last metres inside the wall are harmless. `life` and `period` must hold the whole path (the linter says how long it takes, shoot faster across the road when it
is too long). The ball starts inside its barrel: a metal tube drawn along `v` with the ball one radius inside its muzzle, a dark muzzle disc with the brand rim, a post to the
block under its breech when one is within 3 m, a muzzle flash (0.16 s), a puff of smoke (0.9 s) and a recoil of the barrel (0.3 m, 0.2 s to 0.7 s after the shot).
Always `hit` true, couriers are shoved.

### `laser`: a beam that zaps (no collision)
`p` start of the beam, `to` [dx,dy,dz] the beam to its other end (0.5 to 40 m; turned by `r` and by a spin). Optional schedule: `on` s
dangerous, `off` s gone, `warn` s (default 0.5, at most `off`): the last `warn` seconds of `off` a thin beam flickers, still harmless; without
`on`/`off` it is always on. Optional motion: `move` [dx,dy,dz] with `period`, `pause`, `ease` (the beam slides like `slide`: `p + move * f`),
and/or `rate` deg/s about `axis` ("x" | "y" | "z", default "y") through `p` (a turning beam). Couriers walk through it. Touching it pops the
balloon, breaks the painting and zaps the courier: in a balloon round that player alone respawns at the last checkpoint (else the start) with
the comic word "ZAP!" (cast word `zap`); in a carry round the painting breaks and everybody restarts, as for a kill volume. Always `hit`.
Drawn as an emissive red beam in a faint glow (the glow is the hit radius, 0.1 m) between two metal emitter housings (they stay while it is off).

### `fire`: a flame jet on a schedule (no collision)
`g` "box" (`s`) or "cyl" (`d`, `h`), `p` centre of the jet volume, `r` (the jet points along the volume's own +y), the same schedule as `laser`
(`on`, `off`, `warn` default 1 s: smoke puffs over the grate while it warns). While on it pops the balloon, breaks the painting and burns a
courier inside it ("BURNT!", cast word `burnt`; the same respawn as a zap). Always `hit`. Drawn as a dark metal grate with flame cards
(a noise-driven shader, turned to the camera) and smoke cards while it warns.

### `"look": "spikes"`: spike crushers
On a `slide`, `lift`, `swing` or `spin` with `parts` (or `s`): brushed-metal spikes on every face of its box parts (around a cyl part). It is then
always `hit`, and the spike tips (0.2 m past the parts) pop the balloon and break the painting; couriers are bonked and carried like by any mover.

Lasers and fire jets are on collision layers 8 and 32 while on (couriers do not collide with them; `zone_at` does not report them, the shell
asks `scorch_at`); spike tips are a layer-8-only shell around the parts. Their looks are all in `demo/style/hazard_looks.gd`.
`tools/level_testdata/level_04.json` shows every variant.

### Triggered movers
There are no hazards that react to a courier: a platform that only moves while someone stands on it is written as a periodic
`slide` / `lift` / `blink` with dwell times long enough to board, and one-shot gates become `swing` with `pause`. The one trigger is
the step tiles below (a level section of their own, not a hazard).

## Edge bumpers (EXPERIMENT, race levels 29 to 32)

An experiment (switchable): the jump-target platforms of the race levels have rounded amber bumper cushions along their open edges, so landing in the middle is fine and a sloppy
landing near the edge is thrown off into the void, on all of them. It is built at load time from a
show-level switch and the blocks, with NO key in any level file (the linter rejects an `edge_bumpers` key there): `demo/levels/edge_bumpers.json` next to the level files.

```
{"format": "edge-bumpers-1", "experiment": "...", "on": true,
 "levels": {"29": {"on": true, "share": 1.0, "seed": 29}, "30": {...}}}
```

**Switching it off (reversible, nothing else changes):** `"on": false` at the top (every level), `"on": false` in one level's row, or delete the file. A level that is not listed has none. `share`
is the share of the candidate platforms (above 0, at most 1.0 = all of them), `seed` feeds the hash that ranks them when it is below 1 (`levels/edge_bumpers.gd hash_of`): same file, same blocks,
same picks for every player.

**Which platforms (`EdgeBumpers.plan`, run by `LevelData.load_level` into `level.edge_bumpers`):** every plain upright floor box (or round floor up to 12 m across) at least 3 m on both sides
(a narrower strip has no room for a clear middle) that is not the start deck, the goal, a belt, a hit/slot block, a pillar / frame / wall tone, a deck under a gate (a lift, slide, blink or
swing with a part 2 m tall or more) or something that covers most of it; movers (discs, ferry pads, sliding platforms) carry no cushions. Which edges: on a platform up to 12 m across every
side that is open (no block touches it, no post stands in its band), on a bigger deck only the stretch of an open edge that faces a jump (another platform or a mover's carrier within 8 m
across the gap, 1.5 m wider each side). Left bare where something is in the way: the respawn ring of a checkpoint (`team_start` puts 1 to 8 couriers on a 1.75 m ring round the zone's middle,
so nobody is put back inside a bumper: a checkpoint's own landing, such as L31's round platform, stays bare), an item box, a pad / bumper / fire jet / spike field / laser, the rod of a hit
spinner turning over the deck (its bar's bonk, not a cushion, throws whoever stands there: `tools/bonk_check.gd`) and any stretch shorter than 1 m. There is no hazard clearance and no breather rule. Platforms a level edit adds are picked up on the next load.

**Cushions:** horizontal capsules (0.25 m radius, 0.5 m thick: knee height) along those edges, their axis inset so the clear middle is about 55% of the side (50 to 66%; a round floor: a ring of
16 capsules). The hitbox is the capsule and what is drawn (`style/edge_bumper_look.gd`: a tube and a ball at each end) is exactly that capsule; the courier body touches it at 0.6 m from the axis
(`EdgeBumpers.touched`, exact capsule against capsule). Touching one throws the courier away from the edge at 8 m/s horizontal and 3.5 m/s up (`EdgeBumpers.launch`, via the launcher table
of `level_world.gd`, kind `cushion`): pop, squash pulse of the touched cushion, the `bump` sound (`game_run.gd _apply_level_effects`).

**Probes:** `tools/edge_bumper_probe.gd` (a courier dropped on the clear middle from clean headings and straight down lands safely and is never bumped, straight drops at the clear middle's corners
are safe 4/4, a sloppy landing dropped on each cushion's inner flank is bumped and ends off the platform; the air dash back is counted for information; `--look` also checks the drawing against
the hitbox). `tools/race_jump_probe.gd` re-aims a jump from or onto a bumpered platform (the generator's lane runs along rims; a courier may also steer in the air towards the target's middle) and,
for a jump that no run lands, tries the air dash (pressed 6 to 30 ticks after the jump, forward or braking): such a jump passes and is reported `NEEDS THE AIR DASH` (the show's dash costs only its
cooldown, `dash_flop` is off: courier_motion.gd). A launch pad's flight is also flown steering to the middle of its target and, failing that, with the air dash.

## Item boxes (race show levels)

A race show level may list `"item_boxes"`: rows of boxes a racer takes an item from (docs/items.md). Only `"show": "race"` has them (the linter rejects the key elsewhere); no key, no items in that round.

```
"item_boxes": [{"p": [x, y, z], "n": 3, "step": 1.8, "yaw": 0}]
```

* **`p`** the middle of the row, ON the floor (level-local feet), **`n`** boxes 1-4, **`step`** m between two boxes (1.2-3.0, default 1.8), **`yaw`** degrees (default 0): the row runs along the level's right axis turned by `yaw`, so
  0 is a row across a course that runs towards -Z, 90 across one that runs towards -X. Levels are placed at an origin and the boxes follow it. `levels/level_data.gd item_boxes()` parses it, `level_world.item_boxes(k)` returns the single boxes' world spots.
* **The box** (`modes/show/items_ui/box_look.gd`): a rounded 1 m cube on a 0.24 m pedestal of radius 0.74 m, not solid. A racer without an item that walks through one (within 1.15 m horizontally, feet within -0.6 .. +2.0 m of the spot's height) takes a roll; the box bursts and is back after 8 s.
* **Where** (the design; `tools/item_boxes_gen.py` proposes spots and checks the rows): two or three rows spread along the route (rough progress 25 %, 55 %, 80 %; the first 18 m and the last 15 m stay free), each row ACROSS the way, centred on it, so a runner on the route takes one
  and the field splits across the row; on a flat stretch where the runner has a moment to look (after a landing or a flat run: 4 m after a jump's or a launch pad's landing, 2 m before a take-off), where a hazard is not about to hit and where the level has the room. A course with little static floor
  (level 31) may keep its two rows near each other.
* **The linter** (`level_lint.py lint_item_boxes`, errors name the row and box): at most 5 rows and 12 boxes; each row `{p, n, step, yaw}` with the ranges above; every box inside +-150 m / y -40..80; the floor under it (`floor_below`, a static block only: never a mover, a lift, a spinner,
  a blink tile or a door, which are hazards) within 0.05 m of `p.y` for the row's middle and 0.15 m for each box; the pedestal's foot (its radius and 0.2 m more, 25 samples) on one flat floor within 0.06 m (a ramp of a few degrees at most), plain `ground` (not belt, ice or slime, not a `hit` block);
  no solid block within 0.1 m of the cube; 2.5 m clear of every hazard's swept volume (a spinner or swing: a sphere about its pivot round its parts; a slide or lift: its parts at every metre of its travel; a blink, push pad or bumper: its volume; a ball, laser or cannon: its path, reach or range) and of every kill volume.
* **A level generator keeps its rows**: `tools/gen_level_29.py` .. `32` call `item_boxes_gen.rows_for(NUMBER, data)`, the rows live in `ROWS` of `tools/item_boxes_gen.py` (`--check` tests them against the lint and the route rules, `--propose N` lists free runs of the route).
  `tools/modes/items_harness.gd -- --scenario=boxes --show-level=N` walks a scripted runner through every row, checks the floor under every box, that a taken box leaves the state and is back 8 s later, and prints the level's rows, boxes and route length.
* A box inside a checkpoint's volume is fine (a racer respawned there stands in it and may take it, at most once per 8 s per box).

## Step tiles

A level may carry floors of HEXAGONS (or squares: `"grid": "square"`, see "Stage rounds") that fall for good once somebody has stood on them (the party show's LAST TILE STANDING, `level_15.json`).
A tile is not a hazard (hazards are pure functions of the level clock; there are at most 80 of them): it has one byte of state, written by
the show's rules, and the tile is a pure function of that byte and the level clock, so every machine, a late joiner included, agrees.

```
"tiles": {
  "pitch": 2.5,                       // metres across the flats of a hexagon (= between two neighbours' middles); pointy-top, rows run along X
  "thick": 0.5,                       // tile thickness (the top face is at the floor's y)
  "kinds": {                          // one character each
    "n": {"delay": 0.75, "look": "plain"},                        // candy hexagons in three tones (the party palette in the show)
    "L": {"delay": 2.5,  "look": "logo"},                         // a cream plate with the cast's logo: lasts longer
    "1": {"delay": 0.25, "look": "obstacle", "slot": "obstacle_1"} // a rival tile: the obstacle's picture and colour, red rim
  },
  "floors": [                         // 1 to 4, at least 3 m apart (the players fall from one to the next)
    {"y": 0.0, "origin": [0.0, 0.0], "rows": ["  n n  ", " n L n ", "  n n  "]}   // seven hexagons around an L; every tile has column + row even
  ],
  "fit": [{"players": 3, "radius": 5.0}]  // optional: with this many players or fewer the tiles whose middle is further than `radius` m from the level's middle start gone
}
```

* **rows** draw the floor as it looks, one character per HALF a tile's width: a kind character is a tile, a neighbour in the same row is 2 columns on,
  the next row's neighbours sit 1 column to either side (rows are `pitch * 0.866` m apart, from -Z to +Z; columns from -X to +X), so a tile's column
  plus its row is always even (the linter says where it is not). A space or `.` is a hole. The middle of the text is `origin`; keep the text symmetric
  around the cell you want at the floor's centre (a round floor is easiest generated: the cells within a radius of a centre cell). A second floor
  may use another `origin` (half a tile over) so that the holes of the floor above land on the middle of tiles below. The cells are axial hexagon
  coordinates (column = 2q + r, row = r): the standing-on-a-tile test cube-rounds the courier's position to its cell and the six around it
  (`levels/hex_grid.gd`), it never scans the tiles.
* **delay**: seconds from the first step (rounded up to 0.25 s of level clock) until the tile is gone; the tile shakes and turns red over its last
  part. On the 0.25 grid, 0.25 to 10.
* **look**: `plain` (three tones so that no two neighbours match; the rim is a
  darker tone; in the show the party look's hop-block tones of `brand_colors`, `style/party_look.gd`, else the first colour, the second and a paler first), `logo` (the cast's `logo` picture on cream, else concentric hexagons of the accent), `obstacle` (`slot` `obstacle_1`..`obstacle_5`: that
  picture covers the hexagon and the hexagon crops it, else hazard stripes in its colour; the rim is red). Every tile is a hexagonal prism with a
  flat rim and a small bevel. The look is client only; the collision (a convex hexagonal prism, the same for every kind) is the same everywhere.
* At most 960 tiles in all (the state is one byte per tile: 0 standing, 1..254 the step clock in 0.25 s units, 255 never there). The platform
  refuses a byte field over 256 B, so the show publishes the bytes in pieces of at most 240 (`StepTiles.chunk_state`: the state keys `tiles`, `tiles1`,
  `tiles2`, ... up to four; `StepTiles.join_state` puts them back, the view does it); the rules keep one array. `level_15.json` has 327: three
  roughly circular floors (127, 127 and 73 hexagons, two pieces). A tile can be stood on only
  while the show's play phase runs; a courier whose feet are within 0.1 m of a hexagon's edge and between 0.3 m below and 0.12 m above its top stands
  on it (on an edge on two tiles, on a corner on three), a jump clears it.
* A gone tile has no collision on any machine (a ray, a courier and the camera pull-in all pass it) and no look. A `kill` volume under the
  lowest floor ends the fall (the show's rules send a faller out when its feet reach it; give the level one, `void_y` is only the safety net).
* The linter checks the kinds (one character, delay on the 0.25 grid, a look, an obstacle's slot), equal-length rows, the hexagon grid (column + row
  even), floors at least 3 m apart, at most 4 floors and 960 tiles, the `fit` list, and counts each hexagon as the widest solid box inside it for
  the start and path checks.
* The level world builds the bodies on every role (`StaticBody3D`, solid layer 1, meta `fx`, one shared `ConvexPolygonShape3D`) and, on a client, the look
  (`style/step_tile_look.gd`: one multi-mesh per kind). API: `tile_count(k)`, `tile_start(k, players)`, `set_tile_steps(k, steps, quiet)`,
  `tile_gone(k, index)`, `tiles_under(k, feet)`; signals `tile_warned`, `tile_vanished`. The show's rules do the stepping (`modes/show/rules.gd`).
* **Floors over the camera are not drawn** (client look only; nothing authoritative, the colliders and the steps are untouched). The shoulder camera stands about 3.6 m over
  the player's feet, so on a lower floor the next floor (4 m up, its slab 0.5 m thick) would hang over the camera and cover the top of the picture.
  `StepTiles.ghost_floors(tiles, camera_y, feet_y)` (pure, level-local heights) lists the floors that are not drawn: a floor whose top is more than `GHOST_ABOVE` (1 m) over the
  followed player's feet AND the camera is below its top + `GHOST_MARGIN` (0.3 m). The floor the player stands on, every floor below it, and every floor the camera is above
  (a steep look down) are always drawn; players on a hidden floor are characters and stay visible. The look scales the hidden tiles' multi-mesh instances to nothing (no extra
  draw call, only the tiles of a floor that changed are touched, a tile that shakes, falls or goes meanwhile is drawn right when its floor comes back).
  `game_run.gd` `_ghost_tiles` calls `level_world.ghost_tiles(k, camera_y, feet_y)` each frame (the followed player is the spectated one while spectating; first person and
  the podium shot pass INF: every floor drawn); `StepTiles.ghosted` holds the floors hidden now, on every role. LAST TILE STANDING: floors at y 0, -4 and -8; a player on 0 sees
  all, on -4 the floor 0 is hidden (until the camera is above it), on -8 floors 0 and -4.
* Checks: `python3 tools/level_lint.py demo/levels`, `tools/step_tiles_check.gd` (numbers: the grid, edges and corners, colliders, the byte
  states) and `show_check.gd --show-level=15` (a tile under a standing player is gone for the authority, the clients and a late joiner); `tools/vanish_check.gd` (nothing vanishes into
  nowhere: every blink falls away and returns, a gone tile rests far below and is never scaled, the torn poster is whole again by rolling, no frame-to-frame jump).

## Stage rounds (the falling-tile rounds, `level_25.json` .. `level_28.json`)

A level with a `stage` section is a tile stage round: a survival level (`show: survival`) whose whole floor is `tiles` of `"style": "stage"` with `"wrap": true`,
stacked in several one-way floors, with a permanent ground far under the last one. `level_25`/`level_27` are a square stack (22 x 22 tiles of 3.5 m, 4 full floors 14.3 m apart),
`level_26`/`level_28` a flat-top hexagon stack (29 columns, 691 tiles a floor, pitch 4.06 m, 8 full floors 14.3 m apart). One more floor, the **start layer**, lies one gap (14.3 m) over the first full floor and is `floors[0]` of the file: 12 groups, one per seat: 3 x 3 square tiles (108 tiles), or on the hexagon stacks a flower of 7 hexagons, a centre and its six neighbours (84 tiles), ordinary stepped tiles (a groups' tile warns and goes like any other), no permanent start platform. A player usually drops to the first full floor within a second, or stays up a little by hopping to the tiles of other groups (a group is a tile's gap from the next: a jump). Level-local y 0 is the top of the first FULL floor (the origin, `start` and the lint's start check stand on it); the start layer is at y +14.3, the starts there. The gap is the one a fall of 0.59 s needs with the stage gravity (86.4 m/s2, leaving a vanished tile at rest, speed cap 40 m/s), within the 0.5-0.65 s a fall between two layers should last. A and B (25/26 against 27/28) differ only in
`stage.enclosure` and the title. `tools/stage_levels_gen.py` writes the four files (`--check`: they are what it would write); edit the generator, not the files.

```
"stage": {
  "enclosure": "a",                    // "a" | "b": the cage around the arena (style/arena_world.gd); the only difference between A and B
  "cap": 140,                          // the round's own time cap in s (0: the show's default), at most 150 (the level clock a wrapped step byte covers)
  "starts": [[-1.75, 14.3, -8.75], ...],// 1 to 12 level-local spots, each the TOP of the middle tile of a start group (on the start layer) at least 3 pitches from the others; players are seated in this order
                                       // (the first is the middle of the block of groups), the Nth player of a smaller round uses the first N, more players wrap round
  "ground": {"y": -57.2, "thick": 2.0, "centre": [0, 0], "size": [92.3, 92.3], "tone": "#55659f"}
}
```

* **tiles** for a stage level: `"grid": "square"` (rows and columns of one character per tile, `pitch` apart) or `"grid": "hex"` with `"orient": "flat"` (flat-top
  hexagons: a text row is a column along X, a text column a half step along Z; `"pointy"`, the default, is level_15's); `"style": "stage"`, `"wrap": true`. A kind may
  carry `"raise"` (metres, 0 to 2: the tile's top stands that far over the floor's y) and `"tone"` (a fixed colour, no tone patches); the stage rounds use neither.
  A floor's `y` is the top of its tiles. The one kind of a stage round is `n`. The start layer's groups: squares 3 x 3 tiles in the 3 x 4 staggered block (a tile's gap between groups, left and behind), hexagons a flower of 7 (a centre, the cells above and below it and the two above and below on each neighbouring column), the 3 rows x 4 block on a hexagonal lattice: four columns between the groups of a row, the middle row two columns over and three pitches down from the rows beside it, so every group has its neighbours the same 3.46 pitches away and one hexagon's gap between groups.
* **Floors are one-way** (`courier/courier_motion.gd` `set_floors`, `levels/step_tiles.gd`): the level world builds ONE `StaticBody3D` per floor with a shape owner per tile
  (`tile_bodies` holds the floor bodies, a few instead of thousands of nodes), on its own collision layer `TILE_LAYER_BASE << floor` (`TILE_LAYER_BASE` 2048: bit 12 is
  the first floor; layers 1024 and 512 are the painting blocker and the lobby yard). A courier's mask holds the floors whose top is at or under its feet (2 cm of reach),
  and keeps a floor until its feet are 0.6 m under it (a fall through a hole in the floor above takes it onto the next one
  without ever touching the slab beside the hole). So it walks freely on a lower floor under an intact upper one, jumps UP through the floor over it and lands on it when
  its jump reaches (neither stack: 14.3 m is far more than a jump of 3.15 m, so nobody climbs back; the floors keep the mask so a jump from under a floor never wedges), and a replica body is posed, never pushed. `LevelWorld.tile_floors(k)` lists the floors' world tops
  for `Motion.set_floors` (the owner, the local courier and the replica owner call it every tick through `game_run.gd` `stage_floors()`). A stage level's tiles are not on layer 1 (only the ground is): a ray that has to find a tile uses the mask `StepTiles.TILE_LAYERS_ALL`, the game's own ground rays (the lobby, the balloon rounds, footsteps) never need one.
  `STAGE_FEEL.max_step` (0.6 m) lets a courier climb onto a raised tile (a `raise` kind) from the floor without losing speed. 9 floors fit the 9 collision layer bits of the hexagon stack (start layer + 8).
* **Look** (`style/stage_tile_look.gd`, `style/stage_tile.gdshader`, one multi-mesh and one draw call per floor): glossy chamfered slabs of the candy look (`docs/backdrop.md` "The stage look"): a flat top, a 0.25 m
  chamfer (half the 0.5 m thickness) all round it that makes a V groove between two neighbours, engine PBR at roughness 0.55 (square 0.3), a faint sheen band on the top. A floor wears ONE colour
  family (`CandyLook.TILE_FAMILIES`, picked by the hue of its `tone`: blue `#1aa8f4`, cyan `#59e4e4`, amber `#ffad00`, magenta `#b02da2`); the start pads' tiles take one of the family's three shades by hash, the floors under them a single colour. A hexagon adds 30 % of its colour as own light and a pink rim on its chamfers, a square tile a cool dark rim and 15 % own light. The square rounds have amber pads over blue and magenta layers, the hexagon rounds cyan pads over magenta, amber and blue layers (the stack 5 floors / 9), the ground lime `#a1e531`; the warning is the tile's own colour lifted 75 % towards white (pale lemon, pale cyan). **Floors fade**: a floor the view hides (see "Floors over the camera") fades out, and fades back in, over `StageLook.FADE_TIME` (0.2 s) instead of vanishing in one frame:
  `LevelWorld.ghost_tiles(k, camera_y, feet_y, dt)` with the frame's time (`game_run.gd` passes it; the default INF is instant, for a fixed shot or a check). A floor in between wears its
  own dither material (`style/stage_tile_fade.gdshader`, alpha scissor against interleaved gradient noise, the opaque pass: no sorting; fragments near the eye thin out too, so a slab the
  camera sits in is never cut by the near plane); a whole floor wears the plain material and a gone one is not visible.
* **The exit is instant** (`StepTiles.STAGE_FALL` is 0): a stepped tile turns cream and sinks by 0.4 of a slab thickness (`StageTileLook.SINK_SHARE`) at once IN THE LOOK ONLY: its collider keeps its height, so a runner
  stays level on every fresh tile (no bob, no landing per tile) and the sinking tile sits under its feet; when its `delay` is over (`n` 0.5 s) the tile is gone in
  that frame, collision and look both; nothing falls and nothing shrinks on screen. A gone tile's collider shape is disabled (not removed) and its look instance is scaled to nothing where it sat.
* **Ground**: a solid box (`StepTiles.ground` body, layer 1, drawn by the stage look as a slab) under the last full floor, one floor gap (14.3 m) under it, covering every tile and reaching under the whole enclosure (the cage's ring plus 1.5 m: the walls stand on it);
  `ground.y` is its top, level-local: the height at which the show's rules eliminate a player that lands on it. It is drawn as a solid floor in `ground.tone` (a slab with the layers' tiles laid on it, `StageGroundLook` / `StageGroundTiles`); the gold lasers lie under its bottom and show only outside the arena. The `kill` volumes and `void_y` lie under its underside, so nothing kills
  before the ground. The linter checks all of that.
* **Clock**: a replica's level clock never runs backwards (`LevelWorld.advance`), and in a stage round a correction that would run it back by less than `STAGE_REWIND_HOLD` (5 s: a burst of old snapshots after a stall) is waited out, never jumped, so a tile that has gone does not come back; a larger step back (a new round) still jumps.
* **State**: the byte field is packed (`StepTiles.pack_state`: a bitmap of the gone tiles and a short list of the live ones, pieces of 240 B, up to 7680 tiles; the stage
  levels have 1936 and 5528). The bitmap holds the gone tiles, the list at most 320 stepped tiles that are not gone yet (the 12 runners keep about 50 live): a literal "every tile
  stepped at once" does not fit and never happens in a round.
* **Cost** (`tools/stage_tiles_check.gd` prints it, 5528 tiles): build 0.4 s, `set_steps` with every tile stepped 0.4 s, a pose of every warned tile at most 1.7 ms, one new step among
  settled tiles 0.04 ms, a pose with everything asleep 0 ms. Render (`tools/party_perf.gd --levels=25,26,27,28`, offscreen, 1280x720): 25 to 43 objects and 0.6 to 1.0 ms a frame on Mobile,
  84 to 124 draws and 1.8 to 2.2 ms on Compatibility (level 14 for comparison: 216 draws, 2.7 ms).
* The linter (`tools/level_lint.py`): `stage` keys `{enclosure, cap, starts, ground}`; stage floors at least 1.0 m (and 2 tile thicknesses) apart (other levels: 3 m), floor y and
  `void_y` down to -160 (other levels -40); tiles of a stage level need no hand-placement grid (`free_grid`); a raised tile does not count as ground for the start check;
  the start check uses x = 0 only; `starts` on tile tops; `ground` as above.
* Checks: `tools/stage_tiles_check.gd` (counts, tones, one body per floor, seams, pads and starts, ground and kill, the instant exit, the look's modes, the wire state, the cost),
  `tools/stage_floors_check.gd` (the one-way floors with the real motion: standing, walking under an intact floor, jumping up through it, holes, the ground, a sinking tile, running
  off a sunk tile), `tools/lift_ride_check.gd` (levels 14 to 28: a survival level keeps no permanent ground but a stage round's own), `tools/stage_feel_check.gd`.

## Runtime contract summary (see `docs/level-world-api.md`)
`zone_at(k, pos)`: `"goal"` inside the goal box, `"kill"` inside a kill volume or below `void_y`, else `""`. `launch`/`surface` effects come from `effects_at`.
`scorch_at(k, feet)`: `"zap"` when a courier at `feet` touches a laser that is on, `"burn"` inside a fire jet that is on, else `""`.
`item_boxes(k)`: the world feet spots of the level's item boxes (the rows of `item_boxes` unrolled, the level's origin added), `[]` for none; the show's items read them (docs/items.md).
