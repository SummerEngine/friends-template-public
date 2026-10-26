# Modes

One game shows exactly one mode (AGENTS.md "One game, one mode"). The cast's `mode` picks it; every mode stays in the repo.

| `mode` | Players | What it is | Slots |
|---|---|---|---|
| `show` | 2-10 | THE SHOW: a party show of three level rounds (race, survival, final), elimination from 4 players and points for 2-3, a crown for the winner; or any one of the eight polished rounds from its own lobby circle | `docs/party-show.md`, `docs/swappables.md` |
| `carry` (default in code) | 2-10 | Two players carry the painting through the levels; three to ten keep the balloon up (`run` picks TIME ATTACK or ENDLESS) | `docs/slots.md` |
| `who_said_it` | 2-10 | A catchphrase shows; everyone runs to whoever says it | `docs/modes/who_said_it.md` |
| `friend_swap` | 3-10 online (2 on one machine) | Everyone plays as someone else; then everyone guesses who is who | `docs/modes/friend_swap.md` |
| `hot_potato` | 2-10 | Pass the team's thing on; whoever holds it when it pops loses a life | `docs/modes/hot_potato.md` |
| `shove_off` | 2-10 | Shove each other off a shrinking floor; last one standing wins | `docs/modes/shove_off.md` |

The list, titles and player limits are `demo/modes/modes.json` (the lobby circle shows the title and subtitle; `tools/cast_check.py`
reads the ids). Two optional keys per mode set how it plays: `"camera": "third"` plays over the shoulder (the own body in view, no first-person
arms, the look input orbits: `Modes.camera()`, `FollowCamera.set_shoulder_view`; every other mode keeps first person) and `"dash": true` gives
every player a dash (`Modes.dash()`; `docs/party-show.md` "Controls") and `"dash_flop": true` would put the flop penalty on it (a belly flop after the dash and a stun for a dash into a wall,
`Modes.dash_flop()`, default off: the dash costs only its cooldown). Only `show` sets them. A minigame needs at least `min` players online; on one machine it plays with the two local players.

`show` is the template's own game (its cast says `"mode": "show"`); a cast without `mode` still means `carry`. Its rounds are not yard
minigames but level rounds on the show levels (`"show": "race" | "survival" | "final"` in the level file): level rounds: see
`docs/party-show.md`, which lists all rounds (the lineup decides which are on offer) and the modes and says why the yard minigames below are not circles of the show. It uses this framework: rules `demo/modes/show/rules.gd`, view `demo/modes/show/view.gd`, check `tools/modes/show_check.gd`.

## How a minigame runs

Every mode but `carry` and `show` is a minigame in the lobby yard (the show uses the lobby circle, then plays its rounds on levels). The flow is the game's own: the lobby shows one circle with the mode's title,
everybody stands on it, PLAY, the countdown, the round, the results page (Play Again, Main Menu), the lobby again.

During the round the shell (`game/game_run.gd`) stays in its yard phase: players walk, jump, shove, grab and throw each other and the
loose props as they do in the lobby. The mode adds its rules and its look:

| File | Side | Job |
|---|---|---|
| `demo/modes/<id>/rules.gd` | shared (the authority and the local game) | extends `modes/mode_rules.gd`: everything that counts (rounds, scores, who is out, the end), from the host's clock, the players' positions and action buttons |
| `demo/modes/<id>/view.gd` | client | extends `modes/mode_view.gd`: what players see (pads, signs, tiles, effects) and what the HUD says; reads only the rules' `state()` |
| `docs/modes/<id>.md` | | the mode's slots: which cast fields it reads and how |
| `tools/modes/<id>_check.gd` | | the mode's headless check |

Locked core: `modes/modes.gd`, `modes/mode_rules.gd`, `mode_host.gd`, `mode_view.gd`, `mode_hud.gd`, `mode_views.gd`, the shell, the
network. A new mode adds its folder, an entry in `modes.json`, its rules in `Modes.RULES` and its view in `ModeViews.VIEWS`.

Online: `network/match_controller.gd` builds a `ModeHost` and the rules at the round start (`_begin_minigame`), ticks them at 60 Hz,
publishes `state()` as `match.minigame` (with `match.minigame_id`) 20 times a second, and ends the round when `finished()`; the results
page shows `results().headline` and `.sub`, and a table with one row per player: `rank` (1-based, best first; from `results().order`, the slots
best first, when the rules give one, else from `scores`, a tie sharing its rank: `Modes.ranks`) and `points` (the player's score), which the page
counts up and sets on the stage's podium. `client/main.gd` builds the view and the mode HUD when the round starts and frees them
after. On one machine `client/local_level_flow.gd` does both jobs.

## Rules (`modes/mode_rules.gd`)

`start(host)`, `tick(dt)` (1/60 s), `state() -> Dictionary`, `finished() -> bool`, `results() -> {headline, sub, scores, winners}` (and optionally `order`, the slots best first),
`drop(slot)` (a player left online). Helpers: `score_line(scores)`, `best(scores)`, `time` (seconds since the start).

Keep `state()` small and plain (ints, floats, bools, strings, arrays, dictionaries; a few KB): it is all a view gets. Anything random
comes from `host.rng` (seeded per round). Rules never touch nodes, never draw and never read client files.

## Host (`modes/mode_host.gd`)

| Member | |
|---|---|
| `count`, `seats`, `seat(slot)` | players in the round; slot -> cast index (what that character looks like and is called) |
| `player(slot)`, `name(slot)` | the cast member a slot plays (`TeamCast.player`: name, color, catchphrase, title, look, emote) |
| `active(slot)` | false once that player left (online) |
| `position(slot)` | the character's feet, world space |
| `action(slot)` | the mode's button held: either lift key (Z / X on one keyboard; the lift buttons on a pad). Act on the press edge |
| `held_by(slot)` | who holds this player (a grab), -1 for none |
| `props()` | the yard's loose props (`players/prop_sim.gd`: `positions`, `velocities`, `held_by` per prop, `reset()`) |
| `send_to(slot, at, yaw)` | moves a player (released if held); the owner is told through the snapshot |
| `hold(slot, at, radius)`, `strays(slot)`, `release_holds()` | keeps a player on a spot (a podium): the authority drops that player's poses further than `radius` (x/z) from `at` and counts them; `strays` returns and clears the count, so the rules re-`send_to` the player. `release_holds()` ends it (a new round resets all holds). The view sets `hold_yaw` on the shell so the owner's own courier stands still and faces that yaw |
| `yard_center()`, `yard_rect()`, `floor_y()`, `spot(slot)` | the yard (`network/walk_in_lobby.gd`, `lobby_space.gd`) |
| `rng` | the round's random numbers |
| `pick` | the lobby circle the round was started from (`""` for the cast's own circle: the mode's whole game). Only the show reads it: `"show"` is the whole show, a round id (`r21`) one round (`modes/lineup/round_list.gd`) |

Players move on their own machines (the authority only checks their poses), so a rule never steers a character; it moves one only with
`send_to`. Geometry a view adds (tiles, pads) collides with the players' own couriers on their machines; the rules decide from positions
(a player whose feet are below the floor fell off), never from that geometry.

## View (`modes/mode_view.gd`) and HUD (`modes/mode_hud.gd`)

`build()` once, `present(state, dt)` every frame, `hud(state) -> {title, big, line, timer, scores, out, note, tint, calm}` (`tint: true` paints each scoreboard row in the player's cast colour; `calm: true` is the small layout for a mode with a lot of play to see: title, timer and board at 0.8, the big word at 0.7 and high up, off the centre of the view). Set `hide_name_tags = true` to hide the game's own name tags while the view is up (it draws its own). Helpers: `run` (the shell:
`world`, `actors`, `rigs`, `camera`), `seats`, `my_slot`, `cast_player(slot)`, `rig(slot)` (`play_emote`, `set_look`, ...), `feet(slot)`.
Touch: the lobby's PLAY is a big button over the phone's GRAB while everybody stands on one circle (it taps Enter, the keyboard's PLAY, and the prompt in the lobby
reads "Tap PLAY to start", "Press Enter to start" or "Press Y to start" for the device used last: `client/match_presenter.gd` `input_kind`, `play_prompt`). A mode's `note`
names buttons, not keys, when `touching()` is true.
The HUD draws the model on the game's flat chips: the title top centre, the big word in the middle (`calm`: high up) with a line under it, the timer top
right, the scoreboard down the right (players in `out` greyed), the note at the bottom.

Look: the game's facility look and clean type (Inter); flat, no shadows or glows that are not the game's own; the team's words and
pictures from the cast. Use what the template has: the characters and their looks, shove / grab / throw, the props, the carried thing
(`style/carry_item.gd`), the balloon look, emotes, music and the cast's words. Summer networking only: nothing but the match state.

## Checks

Each mode has `tools/modes/<id>_check.gd`: it plays whole rounds of the rules with scripted players through `tools/modes/fake_host.gd`
(positions and buttons set by the script) and checks the scores, the end and the results, then builds the view under a stub shell and
calls `present` and `hud` on the states it saw. Headless:

    /opt/homebrew/bin/python3 ~/.claude/skills/engine-runs-summer/engine_run.py --timeout 900 -- "$SUMMER" --headless --audio-driver Dummy --rendering-driver dummy --path demo -s "$PWD/tools/modes/<id>_check.gd"

It prints `MODE_CHECK <id> ok=<bool>` last. `tools/modes/mode_framework_check.gd` checks the registry, the cast field, the lobby
circle and that every mode's rules and view load.
`tools/modes/mode_round_check.gd` plays every minigame through the real online flow (the authority's match controller with four
scripted players and a replica drawing the view): the circle, PLAY, the round, the snapshots, End run, the results, Play Again; and that
friend_swap does not start with two players.
