# Friends template

**Starting prompt:** paste this into Claude Code, Codex or any coding agent:

```text
Clone this template game: https://github.com/SummerEngine/friends-template-public
Set up Summer Engine if it's not installed, get the project running, and ask me what kind of game I want to make with it.
```

A ready-made online party game for 2 to 10 players, built in [Summer Engine](https://www.summerengine.com). Race an obstacle course,
carry something fragile together, keep a balloon in the air, shove each other off the map. It is a whole game that already plays:
start from it and make it yours.

## Start here

**1. Get it running (5 minutes)**

1. Install Summer Engine 0.7.3 or newer: [summerengine.com/download](https://www.summerengine.com/download).
2. Clone this repo, then import and play it:

       S=<path to the Summer binary>       # macOS: /Applications/Summer.app/Contents/MacOS/Summer
       $S --headless --import --path demo  # first import, once
       $S --path demo                      # play: PLAY, then two players on one keyboard

3. Or open `demo/` in the Summer editor and press Play.

**2. Pick your game.** One setting, `"mode"` in `demo/cast/cast.json`, decides which game the lobby offers:

| Game | `mode` | Players | What it is |
|---|---|---|---|
| **The Show** (the default) | `show` | 2-10 | Three rounds: a race, a falling-floor survival and a climb to the crown. Four or more players are knocked out round by round; two or three play for points. `docs/party-show.md` |
| **Glass carry** | `carry` + `"object": {"kind": "glass"}` | 2 | Two players carry a pane of glass through obstacle levels. Touch the wrong thing and it shatters. (Leave `object` out for a framed painting instead.) |
| **Balloon** | `carry` | 3-10 | The same levels with three or more players: keep one big, slow balloon in the air from start to goal. Pops on any floor or hazard. |
| Minigames | `who_said_it`, `friend_swap`, `hot_potato`, `shove_off` | 2-10 | Short lobby games: run to whoever said the line, play as a friend and guess who is who, pass it before it pops, last one standing. `docs/modes/` |

Everything lives in the same project, so keep the game you like and delete the rest, or mix them.

**3. Change things.** Everything is open. A rough guide to how much work each kind of change is (and what it means for online play:
[`docs/multiplayer.md`](docs/multiplayer.md)):

| | What | Where to look |
|---|---|---|
| **Easy** | Names, colours, words, the logo, pictures on obstacles, banners and posters, music, which game the lobby offers | `demo/cast/cast.json` and the files next to it (every field: `docs/slots.md`; what the show lets you swap: `docs/swappables.md`). Try `cp -R samples/tidewheat/. demo/cast/` for a full example. |
| **Easy** | Levels: move blocks, add hazards, retime spinners | `demo/levels/level_NN.json` (format: `docs/level-format.md`), then `python3 tools/level_lint.py demo/levels` |
| **Medium** | New minigames, new show rounds and items, new hazard types | `demo/modes/<id>/` with `rules.gd` (what counts) and `view.gd` (what players see): `docs/modes.md`, `docs/items.md`, `demo/levels/hazards.gd` |
| **Medium** | The look: characters, world, menus and HUD | `demo/character/`, `demo/courier/`, `demo/style/`, `demo/client/` (`docs/courier-api.md`, `docs/backdrop.md`, `docs/comic-ui.md`) |
| **Bigger** | New shared physics objects, a different network model | `demo/network/`, `demo/authority/`, `demo/game/game_run.gd`. Very doable: the balloon and the lobby props are worked examples. The same code runs on each player and on the server, so plan which side owns what (`docs/multiplayer.md`, `docs/core-shell.md`). |
| **Bigger** | The build and hosting pipeline | `tools/stage_hosted_export.sh`, `tools/prepare_network_build.py` (`docs/build-tooling.md`); you rarely need to touch it |

**4. Publish it** on Summer Games: [summerengine.com/studio/upload](https://www.summerengine.com/studio/upload). Online multiplayer builds need your own game id: create the game in Summer Studio and put its id in `gameId` in
`demo/summer.build.json` (it ships as a placeholder). Making a game for the
[Friendslop jam](https://summer.games/jams/friendslop)? Upload with [this link](https://www.summerengine.com/studio/upload?event=friendslop) and it is entered automatically.

**Docs**
- Summer Engine docs: [docs.summerengine.com](https://docs.summerengine.com)
- Multiplayer: [make a multiplayer game](https://docs.summerengine.com/build/multiplayer), [parties](https://docs.summerengine.com/build/parties),
  [matchmaking](https://docs.summerengine.com/build/matchmaking); how it works in this project: [`docs/multiplayer.md`](docs/multiplayer.md)
- Publishing: [publish on Summer Games](https://docs.summerengine.com/publishing/summer-games)
- The Summer MCP, CLI and agent skills (including the `multiplayer-*` skills): [github.com/SummerEngine/summer](https://github.com/SummerEngine/summer)
- This project's own notes: `docs/` (start with `docs/modes.md` and `docs/multiplayer.md`)

---

## How the game works

PLAY -> the lobby yard (everybody stands on the circle, then somebody on it presses Enter or pad Y) -> the game the cast picked -> results -> lobby.

**The Show** (`"mode": "show"`, the template's cast): three rounds on their own levels (14 `CIRCUIT BREAKER` a race, 15 `LAST TILE STANDING`
floors of hexagons that fall under your feet, 16 `CROWN CLIMB` a climb), a crowned winner, the results. Rules, controls, state and how to add
a round or a level: `docs/party-show.md`. The hero prop under the crown and how to make one: `docs/hero-prop.md`.

**Carry and balloon** (`"mode": "carry"`): **TIME ATTACK** (5 random levels in a row, one clock) or **ENDLESS** (levels until you leave); the
cast's `run` picks which. The players in the round when it starts pick the play mode (`CourseSection.play_mode_for`):

- **Carry** (2 players): the two carry the painting (or the glass pane) to the goal.
- **Balloon** (3 to 10 players): the team walks the level and keeps the balloon up from the start pad to the goal. It drifts down slowly; touching
  it bumps it, a jump into it is a header. It pops on any floor, a hazard or block marked `hit`, a kill volume or falling out: POP!, and the team
  and the balloon restart at the last checkpoint it passed (else the start pad). A balloon round is a run of ROOMS: every balloon level in
  file order (ROOM 01, ROOM 02, ...); a room is cleared when the balloon floats through its exit door into the next. The results show the
  time and the pops. A player who falls out respawns alone.
- **Players touch players** everywhere: walking into someone shoves them. In the lobby yard and in balloon rounds GRAB (F; pad X; the GRAB button on a
  phone) picks up a free player in front of you, GRAB again throws them, JUMP five times wriggles free. GRAB next to the balloon with nobody in front to grab
  slaps it: a strong lift up and forward (one slap per 0.6 s). Carriers of the painting cannot grab or be grabbed.
- **Props in the lobby yard**: boxes, balls and traffic cones. GRAB with nobody in reach picks one up, GRAB again throws it; walk into one to
  kick it; a thrown prop or a grab knocks a prop out of someone's hands.

A round draws only levels whose file lists its mode (`"modes"`, default `["carry"]`, `docs/level-format.md`): `level_01`-`03` carry,
the rooms `level_04`-`13` balloon, `level_14`-`16` the show (`"pool": false`: only the show plays them).
Dev switch (editor binary and debug builds): the user arg `--balloon` or `FRIENDS_BALLOON=1` plays balloon mode with two players too (local play,
checks).

**Controls (two players on one keyboard).** Each player gets a view (left and right); one moves with WASD, turns with Q/E and grabs with F, the other moves with IJKL,
turns with U/O and grabs with N (`demo/game/game_input.gd` lists the rest). The camera is first person in every mode but the show (your own hands in view, 80 degree field of view, settings key `FieldOfView` 45 to 100; mouse or right stick to look; you
face where you look, carriers face the glass); the show plays in third person over the shoulder with a dash on Shift (`demo/modes/modes.json` `camera` and `dash`, `docs/party-show.md`);
`-- --third-person` (or `FRIENDS_CAMERA=third`) gives the view from behind and above in the other modes.
`$S --path demo -- --balloon` plays the balloon mode. The solo lab: `$S --path demo res://lab/main.tscn`.

## Layout

- `demo/`: the project (`--path demo`).
  - `cast/`: `cast.json` and its pictures: the team, words and look the game wears (`docs/slots.md`).
  - `game/`: the simulation shell (`game_run.gd`: local, authority and replica roles), follow camera, painting, shards, audio.
  - `courier/`, `character/`: the players: movement, the code-built skeleton and its animation, the outfits and heads.
  - `levels/`: `level_NN.json` (one file per level, spec in `docs/level-format.md`) and the runtime that builds them and runs their hazards.
  - `modes/`: the show and the minigames, one folder each (`docs/modes.md`).
  - `network/`, `authority/`: wire formats, match rules, the hosted authority.
  - `client/`: menus, HUD, online screens, touch controls. `style/`: the world look.
  - `audio/`, `assets/`: music and effects, fonts, paintings, menu art. Provenance in `docs/PROVENANCE.md`.
- `samples/`: two example casts (`acme`, couriers; `tidewheat`, a bakery). Both are invented.
- `tools/`: checks, staging, app builders (`docs/build-tooling.md`).
- `docs/`: notes on each module, the level format, the build.

## For engineers

**Where things live**
- Lobby and match flow: `demo/network/match_controller.gd` (authority side: lobby circles, countdown, level runs, results, replies to commands) and
  `demo/network/walk_in_lobby.gd` (the circles). The client side is `demo/client/main.gd` (join, menus, HUD, screens).
- Networking: `demo/network/game.gd` declares the streams (ids `gw.*`); wire formats are `owner_pose_wire.gd`, `input_wire.gd`,
  `snapshot_metadata_wire.gd`. The authority scene is `demo/authority/main.gd`; it runs the same simulation as a client but without rigs or a
  camera. Each client simulates its own courier and sends its pose; the authority checks it, derives the painting and publishes snapshots
  (`docs/core-shell.md`). `network/composition.tres` is regenerated by the staging tools.
- The simulation shell for all three roles (local, authority, replica): `demo/game/game_run.gd`; the balloon mode and players touching players in
  those roles: `demo/game/team_play.gd` around the pure simulations `demo/balloon/balloon_sim.gd` and `demo/players/player_contact.gd`.
- Levels: `demo/levels/` (`level_world.gd` builds a level from its file; `hazards.gd` holds the moving kinds; `level_run.gd` picks the order).

**A level file.** `demo/levels/level_NN.json`, level-local coordinates, spec in `docs/level-format.md` (blocks, hazards, kill and goal zones, a path
of waypoints). To add one: write the next number, run `python3 tools/level_lint.py demo/levels`, then the headless world check from
`docs/level-world-api.md`, and look at it in the solo lab (`demo/lab/`, `docs/solo-lab.md`; it lists every level). Time Attack and Endless draw only
from levels whose file does not say `"pool": false`: leave that line in while a level is unfinished and delete it (or set `true`) to put the
level in play. The pool is read by `CourseSection.pool_levels()`.

**The carried item.** `demo/game/painting.gd` is its pose, grips and break rule (the size constants are at the top); `painting_shards.gd` replays the
pieces from a seed; the geometry and the picture atlas come from `tools/build_painting_items.py` and `tools/make_painting_atlas.py` into
`demo/assets/paintings/`. A cast can pick `"object": {"kind": "glass"}` instead of the painting (the default): a clear pane with the team's
print etched in the middle (`demo/style/glass_pane.gdshader`) that shatters into angular shards. API: `docs/painting-api.md`.

**Build for Summer Games.** `SUMMER_BIN=$S tools/stage_hosted_export.sh <label>` writes `build/friends-network-<label>.summer.zip` and runs the
analyzers, the pack audit and `tools/clean_scan.py`; upload it with the Summer Games publish flow (`docs/build-tooling.md`). `python3 tools/ship.py`
runs the cast check, the clean scan, the in-engine check and a Web export in one go. Mac apps: `tools/build_levels_game.py`,
`tools/build_solo_levels.py`, `tools/build_solo_show.py` (the show for one player).

**Known limits**
- Sixteen levels: three carry levels (`level_01` warm-up, `level_02` timing, `level_03`), ten balloon rooms (`level_04`-`13`) and the three
  show levels (`level_14` race, `level_15` survival, `level_16` final), plus the show's extra race and stage levels (`docs/party-show.md`).
- Online play was checked by headless Local Play runs (clients and the authority walking onto each circle and entering a level), not
  at scale over the real network. Two players on one keyboard were tested by hand.
- A Web build plays two players on one keyboard; online play in the browser is not available yet.
- The build tools were written on macOS (`$SUMMER` defaults to `/Applications/Summer.app`); on Windows and Linux pass the engine path explicitly.

## License

Code and our own assets: MIT (`LICENSE`). Third-party pieces (fonts under OFL, CC0 music and textures) are listed with their terms
in `docs/PROVENANCE.md`.
