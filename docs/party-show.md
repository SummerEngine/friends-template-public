# THE SHOW (`show`): the party show

Three rounds of minigames and a crown, or any one of the eight polished rounds on its own from a lobby circle (the other eleven rounds are in the repo and hidden from the lobby: "The lineup" below). 2-10 players, on Mac and on phones, hosted multiplayer (on one machine: the two local players).
Everything a team can change is in `docs/swappables.md`; the cast fields are in `docs/slots.md`; the mode framework is `docs/modes.md`.

## Flow

Lobby circle `THE SHOW` (everybody stands on it, PLAY) -> round 1 RACE -> round 2 SURVIVAL (a stage round) -> round 3 FINAL (the finish: a second race, a different one) -> podium and crown -> results
page (Play Again, Main Menu) -> lobby. Or a round's own circle (everybody stands on it, PLAY, "Pick a round" below) -> that one round -> its results -> lobby.

Each round is a level-phase round on its own level (`round_mode = "level"`, shell play mode `show`: no painting, no balloon, contact and
grabs on). A round has a card (4 s: for 3 s the level's title with what to do in it and who qualifies, then the 1 and GO with the start gate shut), the play phase, and a result (4.5 s) before
the next round starts. The last round's result is the VICTORY banner (1.7 s) and the podium room lasts 9.6 s.

## The lineup (which rounds the lobby and THE SHOW offer)

`demo/modes/lineup/lineup.json` (read by `modes/lineup/lineup.gd`) is the one reversible list that decides which rounds are on offer. Nothing is deleted: every level file, every mode and every circle id (`r<file number>`) stays, a round that is not in the list only has no lobby circle and is not drawn by THE SHOW.
* `"lobby"`: the level file numbers whose rounds get a circle (`RoundList.entries()`) and may be drawn by THE SHOW (`Lineup.levels(kind)`, `Lineup.draw(round index)`). The list is `25..32`: SQUARE STACK A, HEX STACK A, SQUARE STACK B, HEX STACK B (stage rounds) and ROOFTOP RUN, FERRY CROSSING, SPINNER GARDEN, GATE RUSH (races). A missing or empty list offers every show level. To offer another round, add its file number: its circle, its place in the rows and THE SHOW's draw follow (the yard is cut to the rows, so it grows with them).
* `"playlist"`: the rounds of THE SHOW in order. `rules` is the kind a round is played by (`race`, `survival`, `final`), `levels` the kind of show level it draws from. The playlist is race (from the four races), survival (from the four stage rounds) and `final` rules on a second race level: the first across the goal wins the crown and the show ends in the VICTORY banner and the podium (CROWN CLIMB, the only `final` level, is hidden with the rest). A show never plays a level twice (the finish is drawn from the races that are left). A missing playlist is race, survival, final from their own levels.
`RoundList.entry(id)` still finds a hidden round (a tool or a test can pick it with `host.pick`), and `--show-level=<file number>` still forces any show level of the round's kind.

## All rounds and modes

The show's levels, by round kind. THE SHOW draws one level per round of the lineup's playlist (race, survival, final-on-a-race, in that order; the table shows every show level, "Lobby" marks the ones in the lineup's list) from the playlist round's **draw list** (every show level of the round's `levels` kind that is in the lobby list and does not carry `"draw": false`, `Lineup.draw`); a lobby circle plays one round (all levels of its title are its draw, and a level held back from THE SHOW's draw is still its circle's
own round). `--show-level=<file number>` (dev tools only, read by `DevEnv.user_args()`: the bots, `show_check`, `show_frames`) forces any show level of the round kind, drawn or not;
the draw is the seeded `host.rng`, so a show's rounds are the same on every machine and differ between shows.

| Circle | Kind | Level | Rule line (the card, the circle's board) | Alone | Lobby |
|---|---|---|---|---|---|
| `r14` CIRCUIT BREAKER | `race` | 14 | an obstacle course of crates, sliding walls, spinners and hammers; the first across the goal qualify | yes | hidden |
| `r17` POSTER RUSH | `race` | 17 or 20 (a hall of poster doors, one of the two is drawn) | run through the brand's logo poster (it tears), the problem posters are walls | yes | hidden |
| `r19` BOUNCE HOUSE | `race` | 19 | push pads fling you over gaps, bumpers and swinging cube heads | yes | hidden |
| `r23` ROLLING ROAD | `race` | 23 (27 balls) | dodge the crowd of rolling balls (big, middle and small, across, down the lanes, diagonal and ricocheting off the walls), the cannons and the sweepers on the bridge | yes | hidden |
| `r29` ROOFTOP RUN | `race` | 29 (long course over rooftops: belts, spinning bars, gate walls, stepping stones and launch pads) | `CROSS THE ROOFTOPS  ·  REACH THE TOWER`; the first across the goal at the tower qualify | yes | yes |
| `r30` FERRY CROSSING | `race` | 30 (long course with a ferry ride, doors that open and shut, belts and spinner discs) | `CHOOSE THE OPEN GATES  ·  REACH THE END`; the first across the goal qualify | yes | yes |
| `r31` SPINNER GARDEN | `race` | 31 (a short course of turning discs and turning bars, about 90 m: a drop into four turning discs, a hall with a turning bar, a hex room with low bumps, three small bars across the lane, two ramps topped by a bar, a big turning disc 13 m past the landing disc with three small turning discs a side to cross over, a narrow tiled walkway past a four-paddle wheel, then the finish deck) | `RIDE THE DISCS  ·  DODGE THE BARS`; the first across the goal qualify | yes | yes |
| `r32` GATE RUSH | `race` | 32 (a 30 m wide hall, 148 m: six gate rows of 3, 4, 4, 8, 5 and 3 doors that hang from a lintel and slide up on a schedule, a pink slime slope, a finish deck) | `DODGE THE DOORS  ·  SLIDE TO THE FINISH`; the first across the goal qualify | yes | yes |
| `r16` CROWN CLIMB | `final` | 16 | a climb to the crown; the first to the crown wins | yes | hidden |
| `r15` LAST TILE STANDING | `survival` | 15 (327 hexagons on three floors), `"draw": false`: only its own circle, THE SHOW draws the stage rounds below instead | hexagons you stand on shake and fall for good | yes | hidden |
| `r18` PICTURE MATCH | `survival` | 18 | stand on the shown picture, the others drop | yes | hidden |
| `r21` SPIN BARS | `survival` | 21 | jump the spinning bars as the floor goes in stages | yes | hidden |
| `r22` SHOVE RING | `survival` | 22 | the floor shrinks ring by ring: shove the rest off, stay on | yes | hidden |
| `r24` KEEP THE LOGO | `survival` | 24, `"play": "badge"` | grab somebody to take their logo; wear one when the timer ends | no: needs 2+ players | hidden |
| `r25` SQUARE STACK A | `survival` | 25 (stage round: four layers of square tiles, enclosure A) | `DON'T FALL  ·  BE ONE OF THE LAST STANDING` | yes | yes |
| `r26` HEX STACK A | `survival` | 26 (stage round: eight layers of flat-top hexagon tiles, enclosure A) | `DON'T FALL  ·  BE ONE OF THE LAST STANDING` | yes | yes |
| `r27` SQUARE STACK B | `survival` | 27 (stage round: the tiles of 25 inside enclosure B, our own design) | `DON'T FALL  ·  BE ONE OF THE LAST STANDING` | yes | yes |
| `r28` HEX STACK B | `survival` | 28 (stage round: the tiles of 26 inside enclosure B, our own design) | `DON'T FALL  ·  BE ONE OF THE LAST STANDING` | yes | yes |

The circle id is `r` and the file number of the title's first level (`modes/lineup/round_list.gd` builds the list from the level files alone: one entry per title among the show levels, races, then the final,
then the survival rounds, in file order (the lobby lists them races, survival, final); a show level the lineup lists shows up in the lobby with no code, the yard grows with the rows: `round_pick_check.gd` fails when a circle would stand outside it).

The race draw list of the lineup is the four files 29, 30, 31 and 32; THE SHOW draws one for its race and another for its finish, so each of ROOFTOP RUN, FERRY CROSSING, SPINNER GARDEN and GATE RUSH comes up in a show one time in two, and each is a circle of its own too. The survival draw list is the four stage rounds 25 to 28.

Modes (the cast's `mode`, `demo/modes/modes.json`; one game shows one mode, `AGENTS.md`): `show` (this game, the party show), and the template's `carry`, `who_said_it`, `friend_swap`,
`hot_potato`, `shove_off`, `balloon`. The five yard minigames are NOT lobby circles of the show, on purpose: they are first-person games in the lobby yard, authored for a yard with one
circle, and `game_run` fixes the camera (`shoulder_view`) and the dash (`dash_enabled`) from the cast's mode when the game is built, so run from the show's lobby they would play third
person with a dash they were never balanced for; and one game, one mode: a team that wants one of them sets `mode` in its cast. What the show shares with them: the level SHOVE RING is the idea of `shove_off`
(a floor that shrinks while everybody shoves), and KEEP THE LOGO is the idea of `hot_potato` (an item you must not be holding at the wrong moment) turned around into a thing you
want to hold when time runs out. `who_said_it` and `friend_swap` are quiz and look-swap games of the yard with no course to run, and `balloon` is a rule of the shell (3 or more players
keep the balloon up in a carry round) that the show does not use. `docs/modes.md` has the list with how to switch.

## Rounds can be renamed

A cast renames and re-skins rounds without code: `show.rounds.<round id>` (`title`, `rule`, `hint`, `label`, `model`; `docs/swappables.md` "Rounds as metaphors").
The round id is the circle id above (`r15` ...; POSTER RUSH, levels 17 and 20, is one round `r17`). `CourseSection.round_id(level)` gives it (computed from the level
files' own titles, so a rename never moves a round), and `CourseSection.level_title / level_rule / level_hint` apply the cast's text, so everything that shows a level's words follows: the round
card, the lobby circles (`round_list.gd` groups rounds by the file's own title, shows the cast's), the results headline of a round played alone, the hint under the goal on the round card, the server's level log.
The words on a hazard come from `TeamCast.round_labels(id)` and the model from `TeamCast.round_model(id)`: the plain tiles of `r15` (`style/step_tile_look.gd`), the spin bars of `r21`
(`style/hazard_looks.gd` `dress_spin_bars`), the posters of `r17` and the balls of `r23` (their rows). Collision, timing and rules never change; a model that does not load falls back to the default look.

## Pick a round (lobby circles)

The lobby yard (the same in the solo app and in multiplayer) shows nine circles in two staggered rows: THE SHOW and one circle per round of the lineup (eight, "The lineup" above). A front row of four round circles (the four races: ROOFTOP RUN, FERRY CROSSING, SPINNER GARDEN, GATE RUSH) and a rear row of five, THE SHOW's circle in the middle of the rear row (straight ahead of the spawn) with the stage rounds A (SQUARE STACK A, HEX STACK A) on its left and the stage rounds B (SQUARE STACK B, HEX STACK B) on its right. The rear circles stand in gaps of
the front row (pitch 3.3 m). The wardrobe's pink plate is the tenth, in the south-west corner. The rows are built from the round count for any lineup: the rear row has THE SHOW and a pair of rounds for every four rounds, the front row the rest (18 rounds: 10 and 8 + THE SHOW; an odd count puts a front circle in front of a rear one).
**The look is the race levels' block kit** (`lobby/lobby_kit.gd`; `docs/backdrop.md` "The lobby kit"), not the party look: the floor is ONE chamfered deck slab in the cast's P colour (blue without brand colours; no tiles, no grooves, no rim),
purple pillow walls (the S tone: the races' `navy` wall surface, vinyl; the collision is the yard's slab and four walls of 5.65 m, but only the north wall, the backdrop of the signs, is DRAWN that tall: the west, east and south walls are drawn as a 2.4 m cushion rim, `lobby_kit.gd WALL_SIDE_TOP`, under the shoulder camera's eye, so a side wall never fills the view), columns of pillow segments under the deck down to the lasers' plane, the skyline, balloons and painted sky of the daylight levels
around it (`levels/level_world.gd set_active_level` uses the daylight environment when no level is shown). Only the SHOW yard (`WalkInLobby.show_yard()`, more than one circle) looks like this and is clear of furniture: the minigame yards (one circle: hot potato, shove off, friend swap,
balloon, who said it) have the playground, props and the yard decor. The show yard has the wardrobe too (its ring in the south-west corner `WalkInLobby.wardrobe_center()`, the mirror board behind it on the west wall; its ring is a pink select plate with its own sign; it stands in a nook: a cream arch in a pink border on the wall behind the mirror and two pink cushion wings 1 m high either side of the ring, `WalkInLobby.nook_wings()`, collision in `lobby_space.gd props()`, drawn by `lobby_kit.gd _nook` and `wardrobe_booth.gd _alcove`), the cast's logo wall hangs on the east wall's back half
and the first poster on the north wall between the hero pylon and the first pier (`LobbyVisuals.show_slots()`, on the yard's own walls).
**The candy palette of a course** (`style/candy_course.gd`, used by the race levels 29-32 and the lobby yard): three hues, each in three flat tones (`main`, `light`, `deep`; without brand colours the authored default blue `#0A9CE4` floor with the light cyan `#3DD1F4`, purple `#B254F8`, amber `#FF8000`; with brand colours `main` is saturation 0.97 value 0.96 of the brand hue). Big pillow pieces (`BlockKit.pillow`) are cut into sections of at most 12 m and a tall one is banded in one or two big cushion tiers (S tone and its light tone; white and light blue for crates); floors carry a faint cyan additive rim for the lift at grazing angles; on Compatibility the kit's vertex colours skip the sRGB conversion (`vertex_color_srgb`, set by `CandyMaterial.make`), plus near white `#F8F4F3` and a dark `#473255`: P the floor, S the walls, frames, doors' stripes and columns, A the accents (warm decks, spinner discs, rails). Brand colours (`brand.colors`, `docs/swappables.md`) give their first three hues to P, S, A in the order `style/party_look.gd` `hues()` finds them (a brand with one colour gets a neighbour or a sky hue for S and A); a cast without brand colours gets the default blue `#1AA8F4`, purple `#AE4EE1` and amber `#EF860F`. The world around the course (sky, meadow, sea) and the props' hazard colours are not brand coloured, so the characters stay the most colourful thing on screen.
**Every circle is a select plate** (`lobby/pick_plate.gd`, NOT a bounce pad: flat, let into the floor): a cream rim round a flush face in one colour per kind (race mint, survival blue, final purple, THE SHOW gold, the wardrobe pink), a cream stud and an inlaid ring that lights while somebody stands on the plate
and pulses while its countdown runs (the face sinks 1-2 cm); the players' lamps (one per player, in the player's colour) are little domes on the rim's front arc. **Every sign is a connected crafted piece** (`lobby/lobby_sign.gd`, the show's UI style: Lilita One, a dark pill in a rounded band in the kind's colour with the
the title in white and the rule line in cream, up to two lines each; no thin legs): a front circle's plate stands on a tan corbel on one masonry pillar behind its circle, the rear row's plates stand side by side on ONE tan beam carried by four piers in the gaps between plates and by the pylon of THE SHOW,
whose sign is the GOAL sign's shield (`GoalSign.build_free`: yellow band, purple marquee border, the huge word) on a tall masonry pylon. **Every plate stands above the head of the player on its circle** (front plates 1.5 m up, rear 3.5 m, the shield's tip 4 m), the front plates are
narrower than the pitch (2.2 m) so the camera sees a player on a rear circle through the gap, and the rear plates stand above the front ones.
**Why the yard is 21.3 x 20.9 m.** The yard is cut to its rows (`WalkInLobby.interior_rect()`): the walls stand 0.9 m outside the outermost ring (and no closer than `MIN_HALF_WIDTH` 9.3 m, the room of the spawn seats and the wardrobe ring), the tile grid takes the next even number of tiles (`WalkInLobby.show_tiles_x()`: 14 tiles, half width 10.65 m), the north wall stands 1.6 m behind THE SHOW's pylon (`SHOW_NORTH` -10.9) and the south wall where the single-circle yards have it (10), so the spawn seats and their camera keep their room. The single-circle minigame yards are 34.6 x 24 m (`HALF_WIDTH` 17.3: walls and slab in `lobby_space.gd architecture()`). A third row would push the signs of the farthest row over the 5.65 m walls and away from
the spawn camera, and a smaller pitch would overlap the rings, so the two rows keep a geometry tested with up to nineteen circles. From a spawn seat the camera frame holds all nine signs; the sight lines to every sign are free from every circle and every seat.
`tools/party_look_check.gd` walks the sight lines (from a spawn seat and from every circle, the camera 5.3 m behind and 2.8 and 3.6 m up) to the title and the rule line of all 9 signs (`LobbySign.sight`: the plate and the masonry that can stand in a view), and to a player on each circle:
nothing and no player is in the way. `tools/lobby_frames.gd` renders the yard (`--only=spawn,yard,overhead,show,west,east,rear_a,pick,pad_close,corner_nw,corner_se,edge,north,phone_spawn`; the phone view needs `--resolution 844x390`), `tools/mesh_lint.sh --lobby` lints it.
Walk onto a circle, everybody stands on the SAME circle (walking across other circles on the way starts nothing), press PLAY (Enter, pad Y, the PLAY button on a phone) and the countdown starts; any change of the shared circle cancels it. In the solo app
you stand on a circle and press PLAY too. A round that needs other players (KEEP THE LOGO, hidden; a lineup that lists it shows its board) says `NEEDS 2+ PLAYERS` on its board in a show for one and PLAY does nothing on it.
How it is wired: `walk_in_lobby.gd` builds the circles (`shown_pads()`, ring radius 1.55 m, rows at z -1.8 and -5.8, pitch 3.3 m in both, the rear row one circle more than the front row, so each of the front circles stands in a gap of the rear row; every circle clear of the others and of the playground,
nobody spawns on one), each pad carries a `pick` (`show` or the round id); the match controller (online) and the local flow (one machine) keep the pick of the countdown (`round_pick`) and hand it to
the rules as `host.pick`; the rules (`modes/show/rules.gd`) then run `single` mode: one round of the pick's kind and levels; a round somebody won ends like the show's final (the VICTORY banner and the podium room, 1.7 s + 9.6 s, the round's `place` ranks the three pedestals), a round nobody won (a time out) `finished()` after its result (4.5 s); then the standard
results page (`<NAME> WINS` and the points of the round; in a show for one `<TITLE> CLEARED` with the time, or the title and `LASTED x S`) with Play Again and Main Menu. The state says it is
one round (`rounds: 1`): the chip and the card read `RACE` / `SURVIVAL`, with no `ROUND n`. Points and elimination work as in the show for the round's player count (so 4+ players: the round's
qualifiers go through, the rest are out of that one-round show, which then ends).

## Rules by player count (n = players in the show)

**2-3 players: POINTS.** Nobody is eliminated. Every round awards placement points: 1st gets m points, last gets 1 (m = field size); the
final scores like any round (there are no double points). The highest total wears the crown (the final's place breaks a tie). Race: everybody races, the round ends when all
are across or 30 s after the first finisher. Survival: the last one standing scores most. Final: the first to the crown ends it.

**4-10 players: ELIMINATION.**

* q1 = max(3, round(n * 0.65)) qualify from the race (the rest are out).
* q2 = max(2, ceil(q1 / 2)) survive the survival (the rest are out).
* The final is played by the q2 survivors; the first to the crown is the winner.

| n | Race: qualify (q1) | Out in race | Survival: survive (q2) | Out in survival | Final field |
|---|---|---|---|---|---|
| 2 | points: all | 0 | points: all | 0 | 2 (points) |
| 3 | points: all | 0 | points: all | 0 | 3 (points) |
| 4 | 3 | 1 | 2 | 1 | 2 |
| 5 | 3 | 2 | 2 | 1 | 2 |
| 6 | 4 | 2 | 2 | 2 | 2 |
| 7 | 5 | 2 | 3 | 2 | 3 |
| 8 | 5 | 3 | 3 | 2 | 3 |
| 9 | 6 | 3 | 3 | 3 | 3 |
| 10 | 7 | 3 | 4 | 3 | 4 |
| 11 | 7 | 4 | 4 | 3 | 4 |
| 12 | 8 | 4 | 4 | 4 | 4 |

(`round` is round-half-up: n = 10 gives 6.5 -> 7. In each round q is also capped at the field size minus one. The show seats 10 (`modes.json`); the rows for 11 and 12 are the rules' own numbers, which the tile stage rounds' 12 pads and `tools/stage_round_check.gd` use. In THE SHOW the survival field is the q1 players of the race, in a lobby circle of one round it is everybody; `need` is q2 of the show's n either way.)

Time caps: race 100 s (a race level may carry its own `cap`, docs/level-format.md: ROOFTOP RUN 240 s, FERRY CROSSING 300 s), survival 60 s (KEEP THE LOGO 45 s), final 90 s; a round ends at its cap (the standing so far decides). The deciding finish (or fall) ends a
round 1.5 s later. The scoreboard always shows the points.

Racers (race, final): a kill volume or a laser sends the racer back to its last checkpoint (the start before the first); the goal volume
qualifies it. Survival: a player whose feet reach the kill volume under the floor is out; a fall shows for 1.2 s, then the player is retired (hidden, no longer simulated; it stays where it fell and watches). **A tile stage round (r25-r28) eliminates on the ground, not on the fall**: falling through a hole onto the next layer is nothing, a player is out when it LANDS on the
ground floor under the last layer (feet within `STAGE_LAND` 0.3 m of the level's `stage.ground.y`) or leaves the slab sideways into the kill volume (which lies under the ground and never fires above it).
When the cap (`stage.cap`: 140 s square, 150 s hex) ends such a round with more players standing than `need`, the higher floor ranks first (it has fallen less far), then the lower slot; in a points show nobody is out.

**Stage rounds: frozen until GO, a solid ground to land on.** A tile round has no start gate, so from the spawn to GO (the whole card: the title and the digits 3, 2, 1) every player is held on its own start tiles (3 x 3 squares, a hexagon flower): no walk, no jump, no dash (the camera still turns). It is an authority rule, not a client courtesy: the authority holds every player (`rules.gd` `_freeze_start`, `ModeHost.hold` with a radius of `STAGE_HOLD` 0.25 m and a height band of `STAGE_RISE` 0.2 m) and drops any owner pose that leaves the spot, then puts the player back at its start (`_hold_start`), so a client that does not freeze its own courier (`GameRun.hold_start`, set by `modes/show/view.gd` while the card is up, honest clients only) still cannot move on any screen; GO (the play phase) releases everybody. The races keep their shut start gate for the card and are unchanged. Under the last layer lies the permanent ground floor (one layer gap, 14.3 m, under it; a solid floor in the layers' own tile look in ground colours, blue for squares, green for hexagons): landing on it is the elimination (the authority decides: feet within `STAGE_LAND` of its top = out, then the fall shows for 1.2 s and the player spectates). The gold lasers lie under the ground slab and show only round the outside of the arena. Check: `tools/modes/stage_flow_check.gd` (real owner couriers holding forward through the card, a cheating client, the unlock at GO, the fall to the ground, the elimination and the spectate view).

**Stage rounds, who starts where and how many survive.** The same `need` as every survival round: q2 = max(2, ceil(max(3, round(n * 0.65)) / 2)), so 12 players give 4 survivors (the last 4 of 12), 10 give 4,
8 give 3, 4 give 2; 2-3 players are the points show (need 1). The level file lists 12 start spots (`stage.starts`, the middle tiles of 12 groups on the start layer, 3 x 3 square tiles or a flower of 7 hexagons, a staggered block, the first group in its middle). 12 players stand on the 12 groups in the listed order; fewer take groups spread over the whole block
(`levels/stage_starts.gd`: the first is the group furthest from the block's middle, every next one the group furthest from the ones taken, so 2 players stand at opposite corners and 4 at the four corners; 1 alone: the middle group), the same on every machine; a respawn goes back to the player's own group. The unused groups exist too (all 12 are tiles to hop on). The show itself seats at most 10 (`modes.json`), the pads and the bot check go to 12.

**A survival round has no permanent safe ground.** The floor is the step tiles (level 15) or the `blink` tiles (level 18) and nothing else: no
ground ring, no start deck, no goal pad, and the arch, banner and billboard slots are looks without collision (their posts are drawn only where a
block is under them, so they hang in the sky). The kill volume reaches past the whole play area, so a player who leaves the tiles falls into it. A
player cannot stand anywhere off the tiles: it falls out (`tools/lift_ride_check.gd` puts a courier on such spots and watches the real
rules put it out). There are no static blocks at all (`"blocks": []`). `tools/level_lint.py` rejects any block in a
`"show": "survival"` level. The round's start spots (a ring of 1.75 m around the start, for 2 to 10 players) stand on tiles: PICTURE MATCH has
a 6 x 6 m `pm_start` blink pad just under the tiles' top, solid for 6 s of the level clock (it shakes from 5 s, 1 s after GO and before the
first drop at 10 s) that fills the gaps between the tiles at the start; before it, three or more players started over the gaps and fell.

## How long a round takes

Measured with the physics bots of `tools/modes/show_bot_check.gd` (real courier physics along each level's route; `--pace=<0.3..1>` is the
share of full speed the bots walk at, an average player is about 0.7 of a perfect route follower).
A person is slower than a bot on the course and faster on the floor.

| Round | Target | Measured |
|---|---|---|
| Race (`CIRCUIT BREAKER`, cap 100 s) | people 40-70 s | bots: 29-35 s at full pace (a lower bound), 31 s at 0.8 and 41 s at 0.7; the hammers and sweepers knock a bot back (the bonk, `docs/level-format.md`) and a person who falls at the sweepers, gaps or hammers goes back to the last checkpoint (+10-20 s) |
| Race (`POSTER RUSH` 17 / 20, cap 100 s) | people 40-70 s | bots (`--pick=r17 --show-level=17` or `=20`; they read the doors, predict the moving logo poster's opening, wait for it short of the wall and tear through, no bonks, no falls): 30-32 s at full pace, 34.6-35.7 s at 0.85, 41.5-41.9 s at 0.7 (2 players and `--solo`, both levels; the play phase is 39.2-39.5 s), 50.6-52.4 s at 0.55 |
| Race (`BOUNCE HOUSE`, cap 100 s) | people 40-70 s | bots: 29 s at full pace, 53 s at 0.7 and 56-58 s at 0.8 (a swinging cube head throws a bot off the slab now and then: back to the last checkpoint); a missed pad or a ball sends the player back to the last checkpoint |
| Survival (`LAST TILE STANDING`, cap 60 s) | 20-60 s with several players | the floor only falls where somebody stands, so the round ends when the walkers run out of floor: bots (2 players, one hexagon at a time to the nearest untouched one, never jumping, `fit` takes the outer ring away up to 3 players: 255 hexagons): 28 s at pace 0.7, 35 s at full pace, then both fall to the kill volume within a second of each other; a person who keeps to the logo tiles (2.5 s) and walks slowly lasts longer, a crowd shares all 327 hexagons and the round is over when they have used them up (not measured with 10: the bots are two); one bot alone (`--solo`, `fit` as for 2): 41 s at pace 0.7, down through all three floors, and at full pace it walks the whole 60 s cap (a perfect walker never wastes a tile; a person does); a lone player who walks slowly can outlast the 60 s cap |
| Survival (`PICTURE MATCH`, cap 60 s) | 20-55 s with several players | twelve windows that shrink from 5 s to 0.5 s (the first cue at level clock 5 s, the last window ends at 52.5 s), then the other pictures stay gone and the shown one falls at 54.5 s, so the round ends by a fall at 51 s of play at the latest. Bots that read the cues (2 players, `--pick=r18`, they walk to the nearest tile of the shown picture and stop): at full pace the first one is out in window 7 (1 s, 37.3 s of level clock), the round lasts 35.3 s; at pace 0.7 one is out in window 10 (0.5 s, 46.5 s), 44.5 s; a bot that ignores the cues is out at the first drop (6.5 s of play). The courier walks 5 m/s and two tiles are 0.25 m apart: a window of 0.5 s lets a player who stands next to a tile of the picture reach it and nobody who is a tile further. A model of that bot over eight start spots (throwaway script, not in the repo): 5 m/s with a 0.1 s lag is out in window 10, 3.5 m/s in window 10, 4 m/s with a 0.3 s reaction in window 9; not measured with people |
| Survival (`SPIN BARS`, cap 60 s) | 25-55 s with several players | the bars never stop, and the floor goes in stages: the pedestal (the start) goes at level clock 10 s = 6 s of play, the outer ring at 24 s (play 20), the middle ring at 38 s (play 34) and the core at 50 s (play 46), so a lone player is out by 48 s of play at the latest (cap 60 s); the two bars throw whoever they touch 7 m (probe: standing at 6 m, 8.5 m and 3 m from the middle, thrown 6.8-7.4 m off the edge; in the middle 3.3 m). Bots that look at the bars and jump them (2 players): 43.8 s at full pace, 37.6 s at 0.7 (both caught by the middle ring at 36 s); one bot alone (`--solo`): 43.8 s; a person who is hit once is usually thrown off the floor (not measured with people) |
| Survival (`SHOVE RING`, cap 60 s) | 40-56 s with several players | the floor shrinks in four steps: the outer ring drops at 14 s of play (level clock 18), the next at 28 s, the next at 42 s and the 8 m disc at 54 s (clock 58), each ring shaking for 2 s first, so nobody stands the 60 s cap; a courier on each ring falls into the kill volume 0.65-0.7 s after its drop (real physics, throwaway script). Bots (2 players, `--pace=0.7` and full pace alike): they shove nobody, stand 1 m from the middle of the floor that still stands and go down together with the disc, 54.7 s into play (round 56.2 s with the end grace); `--solo` the same; with ten players the 8 m disc after 42 s is the shoving contest (not measured with people), and whoever is still on the disc at 54 s falls with it |
| Race (`ROLLING ROAD`, cap 100 s) | people 40-70 s | 27 balls and 4 cannons (about 40 % of the road's 1 m slices hold a ball at any moment), bots (`show_bot_check.gd --pick=r23`, real physics; they never time a ball: the balls bonk them, the sweepers on the bridge push them off the edge back to the checkpoint before it): 0.7, two bots: bot 0 45.1 s, bot 1 52.2 s (one set back from the bridge), play phase 49.7 s; 0.7, `--solo`: 52.3 s (two set-backs from the bridge), play 49.8 s; full pace: 38.2 s and 38.4 s, play 36.0 s (one bot thrown off its route by a ball in the garage stretch, then the bridge). The balls throw the bots about (one was thrown sideways into a garage 12 m off the route); at 0.5 the bots do not get past the sweepers of the bridge in 100 s. Phases: a numbers-only model of a walking bot (a throwaway script) ranked 108 random draws (means 32 s to over 60 s, some never got through); the shipped phases are from the better third. If the bots take longer than 70 s, drop first the balls that roll at the player (`hop_2`, `lane_*`, `diag_*`, `zig_*`), then lengthen periods (not measured with people) |
| Survival (`KEEP THE LOGO`, cap 45 s) | 45 s, always to the cap | a fixed 45 s of play (the logos are the clock); two bots (one chases the other's logo and grabs, `--pick=r24`): 45.0 s; with people the round is a chase around the pillars: the dash costs a belly flop, so a chaser who dashes is easy to dodge (not measured with people) |
| Final (`CROWN CLIMB`, cap 90 s) | an average player in 60 s or less | bots: 37.5 s at full pace, 51-54 s at 0.8, 56-68 s at 0.7 (the three hammers on the summit deck knock a bot off now and then; their periods differ, 5.0 / 4.5 / 5.5 s, so a respawned walker never meets the same pattern twice: with a first hammer of 3.5 s, and again at 4.0 s, a bot's 3.6-4.0 s loop of walk, fall and respawn met it at the same phase every time and never got past) |

**Tile stage rounds (r25-r28).** Measured with `tools/stage_round_check.gd` (the bots below; real courier motion with the stage feel, real `PlayerContact`, the real `ShowRules` on a fake host, the level's real
tiles and colliders; the length is the play time to the deciding elimination plus the 1.5 s grace). Targets for 12 players: 103-116 s on the square levels, about 137 s on the hex levels (the measured pictures
of the same arenas). Two seeds, bots at pace 0.8 with a hop every 2 s on average:

| Level | 2 players | 4 | 8 | 10 | 12 | target for 12 |
|---|---|---|---|---|---|---|
| 25 square (1936 tiles, cap 140 s) | 91.6 / 126.2 s | 68.0 / 100.3 | 61.4 / 52.5 | 43.7 / 47.8 | 41.9 / 46.2 | 103-116 s |
| 27 square (enclosure B) | 127.3 / cap | 82.5 / 82.6 | 66.4 / 60.5 | 46.6 / 50.7 | 40.9 / 35.9 | 103-116 s |
| 26 hex (cap 150 s) | cap / cap | cap / cap | 116.2 / 116.0 | 84.7 / 92.6 | 74.2 / 87.6 | 137 s |
| 28 hex (enclosure B) | 63.0 / 26.8 | cap / cap | 102.0 / 96.6 | 86.8 / 91.8 | 86.3 / 85.4 | 137 s |

The 12-player rounds end 55-65 % short of the target on the square levels and 36-46 % short on the hex levels: 12 bots at 0.8 use 28-33 tiles a second (the measured picture: 18-25), 1150-1350 of the 1936 square tiles
and 2250-2600 of the hex ones, before the last 8 are out (at pace 0.65, 27 tiles a second: 45.9 s on level 25, 73.9 s on level 26; at 0.9: 43.9 s and 82.1 s). The arena was not shrunk to fit and nothing was
tuned to hit the targets (not measured with people). With 2-4 players on a hex level the bots hardly ever fall: the round runs to its cap (150 s) and the higher floor ranks first;
with 4 on a square level it ends at 68-100 s. Bots: one heading with a fan search over headings for the tiles not yet stepped on (far ones count too), a wide berth round other players, a jump over a hole, a random hop,
a little wander; `--pace` is their share of the run (a bot slower than 0.56 of it falls through the tile it has just stepped on: a tile goes 0.5 s after the step and is 3.5 m long), `--hops`, `--seed`, `--levels`, `--players`.
Every combination of levels 25-28 with 2, 4, 8, 10 and 12 bots asserts: the round ends by itself (the eliminations or the cap), lasts at least 15 s, `need` or fewer go through and none more stand at the end when the eliminations ended it, everybody who was put
out stood on the ground floor, no bot stands without headway for 2 s (0 in all 40 runs) or hangs in the air, no landing bounces (0), and the state fields stay within 240 B.

**The lengths depend on how people play.** A bot has one speed and one purpose: stay ahead of its vanishing tile and find fresh floor, so it never idles, looks about or runs in circles; a round's length is the time it takes the field to use up the floor, and that is set by how the people in it move. A bot slower than 0.56 of the run falls through its own tile, so below that a slower bot is a shorter round, not a longer one, and above it the length hardly moves with the pace on the square level (a few seconds around 42-48 s) and
rises with it on the hex level. Pace sweep, 12 and 10 bots, seed 1 (length in seconds; the target is 103-116 s on the square level and about 137 s on the hex one; 0.9 was run with 12 only):

| pace | 25 with 10 | 25 with 12 | 26 with 10 | 26 with 12 |
|---|---|---|---|---|
| 0.5 | 20.2 | 31.7 | 16.7 | 15.5 |
| 0.6 | 48.2 | 43.2 | 54.7 | 38.1 |
| 0.8 (the table above) | 43.7 | 41.9 | 84.7 | 74.2 |
| 0.9 (12 players only) | - | 43.9 | - | 82.1 |

None of them reaches the targets. What the bots cannot say is how long people take: the recorded rounds the targets come from are 12 people who run, hesitate, jump about and look around, which the bots do not, so no pace here stands for them. The rules and the arena were not changed to reach the targets.

The tile floor's times are the `delay` of each tile kind in the `tiles` section of `level_15.json` (`docs/level-format.md`, "Step tiles"); the climb's pace is set by the lifts (`lift_1`,
`lift_2`: a 6 s cycle with a 0.5 s pause) and the sliders (6 s). `PICTURE MATCH`'s timing is its `cues` and the `blink` schedules of
`level_18.json`, both written by `tools/picture_match_gen.py` (the windows, the pictures and the numbers are in its header; `--check` compares the file with it).

## Spectating, podium, crown

* **Out players spectate where they are.** Nobody is moved into a pen (levels have no `gallery`). An eliminated player's courier is *retired*
  (`ModeHost.retire` -> `GameRun.drop_slot`: the slot is inactive, which every machine already learns from the snapshot's `inactive` entry, one int on the wire): hidden,
  not simulated (an owner client stops stepping and publishing its courier, `GameRun.owner_step`, `client/main.gd` `_sync_owner`), no contact, nothing collides with it or
  targets it, and it stays where it fell. A fallen survival player is retired `FALL_SHOW` 1.2 s after its fall; a player eliminated at the end of a round
  (a race, a points-less survival) stays on the level it played and is listed as out when the next round begins (`ModeHost.begin_level(level, out)`: the slot is
  inactive for the whole round, so it takes no start pad). A racer who falls into a kill volume or a laser is NOT out: it goes back to its checkpoint.
  The camera of an out player (`spectate_slot`, set by `modes/show/view.gd` from the replicated `lead`: the furthest racer or a player still standing) follows that
  leader and the player's input is dropped; a player nobody leads (everybody out) has the view rest where its courier stays. The elimination effects (feed,
  plate, words, the SPECTATING note) apply as usual.
* **EXPERIMENT (switchable): GHOST PIGEON.** With `demo/modes/show/shared/pigeon/pigeon.json` on (the cast's `show.pigeon.off` turns it off), a player who is out of a tile round or has finished a race is not spectated: its retired courier is replaced by a
  pigeon it flies over the arena (WASD, up, down), with a COO (screen shake within 5 m) and a DROP (a white splat on a living player's screen for 1.5 s); it never pushes or hurts anybody. A race finisher is retired 1.2 s after the goal, the round ends
  as usual. The show state carries `pigeon` while it is on. `docs/pigeon.md`.
* **The victory sequence and the podium room.** The last round (the final of the show; a one-round show's round when somebody won it, not a time out) ends in `done` with the state flag `victory` for `VICTORY` 1.7 s (no result wall):
  `modes/show/shared/victory_flow.gd` (a CanvasLayer of the view, a pure function of the state: `t`, `top`, `crown`, `podium`) draws the winner's banner (`ShowBanner` kind `victory`, the cast's champion word, 40 % of the screen's width, 35 % down)
  for 1.45 s with a short burst of paper ribbons, then a beat of plain gameplay, then a hard cut (banner in to the cut 1.70 s). Then the podium phase (`ShowRules.PODIUM` 9.6 s):
  the top three stand on the pedestals of **the podium room** (`style/podium_room.gd`: `PodiumRoom.spots()` are the spots of the state's `podium` and of `host.podium`, whatever level the show ended on). The room is built in code on every client
  far from every course (`PodiumRoom.ORIGIN`, z 4000: nothing else renders there) with its own light rig and sky: while it is up the camera takes `PodiumRoom.environment()` and the course's directional lights are switched off (everything is put back
  when the phase ends). It is an open stage 19 m wide on a starry **night** (the room's colours are fixed, not the brand's): a dark violet dome (`_dome`: the inside of a 400 m sphere, `style/podium_sky.gdshader`, unshaded, one draw call, no particles; screen colours #3A1070 at the zenith to #5A3D8E at the horizon, slate to teal blue under it, star specks of one or two pixels in four pale colours made by the shader from a cell hash, nothing that moves), a stack of three inflatable amber tubes (0.46 m radius, pillow pinches, rounded corners, on posts, back and sides only: `_walls`, built with `CandyMesh.tube` and the course surface shader; the front stays open) standing on a pink zig-zag truss (1.25 m: two chords and a rounded triangle wave of 1.5 m period, one mesh with the ring), a glossy violet-blue tiled floor with lighter lines, low pink railings with orange-capped posts along the front and the sides, the hero prop in a small copy on each side; glossy cylindrical pedestals (`_pedestal`: stacks of rounded discs of radius `FRONT` 1.45 m, 0.5 m a disc, a navy groove between them, one mesh a pedestal with the course surface shader's vertex colours, roughness 0.18: 1st gold, 2nd pink, 3rd turquoise; the title's blocks are the same),
  1st in the middle 2.0 m high, 2nd on its left 1.5 m, 3rd on its right 1.0 m (the collision stays the boxes of 3.0 x 2.4 m); a purple vinyl cloth runner (roughness 0.45) down the front of each (it follows the disc's round front) with a pennant, a big number and a striped strip over the floor;
  behind them ONE big sunburst lightbox billboard for 1st (our own, not a TV: a purple body, an amber bezel, marquee bulbs chasing round the edge, amber and pink turning rays: `style/podium_rays.gdshader`) and two small dark violet screens for 2nd and 3rd (navy body, pink bezel, a faint fan: `wash` 0 in the shader)
  with huge extruded numbers 2 / 1 / 3 (Lilita One, `TextMesh`); a name plate stands on top of the side billboards, the champion banner (a spiky badge: the cast's champion word and the winner's name) over the middle one; two big yellow loudspeaker
  horns on posts at the two sides of the back wall pulse and fire confetti (a `MultiMesh`, a sprinkle on the night: 22 pieces a horn shot, 45 a rain, 16 a pop; paper and long ribbons in the show's colours and the brand's; every piece a closed-form function of its age, so the room is a pure function of `t` and every
  replica agrees). The room's collision (floor, pedestals, rails; layer 1) is the view's own, as every client-side geometry: the authority needs none (it takes the owners' poses, `_hold_podium` keeps them on their spots).
  The camera (`VictoryFlow.shot`): three hard cuts (0 s low and close under the middle screen backing off; 0.7 s the pedestals' close-up craning up; 1.4 s the wide frontal shot that settles in 0.8 s), then a slow push in on the winner;
  the fit follows the window's aspect (a phone's 844 x 390 and a narrow window get a wider dolly), the wide shot's lens is 44 degrees (42 at the end of the push), a landing shakes it a little. The winners drop in 3rd (1.7 s), 2nd (2.6 s), 1st (3.5 s): the real
  characters, stretched and squashed in about their feet (`VictoryFlow.drop_scale`, through the shell's `rig_scales`: `game/game_run.gd` applies it after each rig update, as the rig turns itself every update; a rig scaled to nothing is hidden),
  the billboard of the rank flashes, a round pop of confetti bursts over the winner and the horn on that side fires (the winner's fires both, with a rain from the ceiling), its name plate comes up; the champion banner pops in at 3.85 s
  (`TeamCast.show_word("champion")` and the winner's name); 0.4 s after landing each winner plays the cast's own emote (`players[i].emote`, else `dance` / `yes`); the crown comes down
  onto the winner at 3.9 s (`view.gd` `_crown`, `crown.glb` or the built-in one); a white glint sweeps the billboards from 2nd over 1st to 3rd at 5.0 s and the horns fire again; from 3.6 s the camera creeps in. The HUD is empty in the
  room (the results page follows at the end). `host.hold` / `hold_yaw` apply: for the whole podium phase (9.6 s) every client holds its own courier still facing +Z (`hold_yaw`: no steering, no dash, no grab, a jump in place stays) and the authority
  keeps every player on its spot (`rules.gd` `_hold_podium`: a pose more than 0.3 m from the spot on x/z, a fall or a grab puts the player back with `send_to`). Everybody else (4th place and below, the eliminated, spectators) is out for the phase
  (hidden, not simulated); they watch the same camera. The podium starts a new epoch on the final's level with its clock running (`ModeHost.begin_podium`): the top three are simulated again (an eliminated player with a podium
  spot comes back for it), everybody else stays out. With one player (the solo app) the player is the winner, in the middle on the top pedestal. Then the results page: `<NAME> TAKES THE CROWN` and the points (a one-round show:
  `<NAME> WINS`). The whole ending is about 11.3 s (1.7 s banner + 9.6 s room). The state carries `top` (the slots on the podium, best first) and `victory`.
  `tools/modes/show_check.gd` checks the hold (2 and 6 players, with scripted poses that walk away every tick: nobody is more than 0.5 m from its spot in the whole phase) and the room's wide shot framing; the pictures:
  `tools/modes/podium_frames.gd` (the room empty, with three winners, and the sequence as numbered frames).
* Players who leave online drop out of the show; the round goes on without them.

## Controls

| Device | Move | Jump | Dash | Grab | Look (orbit) | PLAY (lobby circle) |
|---|---|---|---|---|---|---|
| Keyboard | WASD | Space | Shift | F | mouse | Enter |
| Pad | left stick | A | B or right bumper | X | right stick | Y |
| Phone | stick | JUMP | DASH (over JUMP) | GRAB | drag on the right of the screen | the PLAY button over GRAB while everybody stands on the circle |

**ITEM** (races with item boxes, `docs/items.md`): keyboard **E** (two on one keyboard: **G** and **B**), pad **Y** or the left bumper, phone: the round ITEM button over GRAB (it wears the held item's icon; shown only in races that have item boxes).

**HOT EGGPLANT** (experiment, races with item boxes, `docs/items.md` "Hot eggplant"): now and then a giant eggplant is strapped to a runner's back (25 % slower, lower jumps); walk into someone or GRAB them and it jumps over to them, it pops after 20 s or at the finish line. No button of its own; `demo/modes/show/items/hot_eggplant.json` switches it.

Walking into someone shoves them; GRAB picks up a free player in front of you and GRAB again throws them. The key hint
(`WASD move · Space jumps · Shift dash · F grabs`) shows for the first 7 s of round 1 only, never on a phone (the buttons say it), never in a result and never in a tile stage round (no dash, no grab there);
an out player reads `SPECTATING  ·  <NAME>`.

**The camera is third person** (lobby and every round; `demo/modes/modes.json` `"camera": "third"` for `show`, every other mode keeps first person): over the right
shoulder, 5.4 m behind and a little above, the player's own character low on the left and the way ahead filling the screen, no first-person arms. The mouse, the right stick or a
drag orbits it (up to a slightly steeper look down, never along the floor); movement is relative to where the camera looks and the character turns to its own way. A wall never blocks it: the camera is
pulled in at the wall (shape cast against the level's camera blockers, `game/follow_camera.gd`), also when the wall is at the character's shoulder. Ctrl + wheel zooms.
On LAST TILE STANDING (three floors 4 m apart) the camera of a player on a lower floor would sit right under the next floor's slabs; the floors over the camera are not drawn
(client look only, `StepTiles.ghost_floors`, `docs/level-format.md` "Step tiles"): never the player's own floor or one below it, never a floor the camera is above, and the
players on a hidden floor stay in view.
**Smooth at any refresh rate, and no swing across the screen.** The couriers are moved by the 60 Hz physics tick, the screen is drawn once per rendered frame (60, 120, 144 Hz or whatever the display runs). Drawing the raw tick position made the courier step ahead of and
fall behind the camera (the camera eases towards it in the frame's own time step): on a 120 Hz screen every other frame has no tick, at 60 fps a frame now and then takes two ticks or none, and a courier running sideways smeared by a tick of its
speed (0.08 m at the 5 m/s run, 0.21 m at the 12.6 m/s of a tile round, 0.18 m at the dash). `game/visual_track.gd` keeps each courier's last two tick positions and `GameRun.visual_position(slot)` is the point `Engine.get_physics_interpolation_fraction()` of the way
between them (a teleport over 2 m, a respawn or a ride to the next level, is drawn at once; no ticks, as in a paused game, draws the last one). The rigs (`_update_rigs`), the dash trail and **every follow camera in the game** (the lobby, the shoulder view,
the race stage view, the tile stage rounds, the spectator view, split screen, the lab) take their point from it in the same `_process`, so courier and view agree in every frame; the simulation, the rules and the poses on the wire still read the physics position.
The owner's courier is never corrected by the authority (`network/owner_courier.gd`: no prediction, no replay), so it has no predicted-against-authoritative pose to swing between; the camera's lag does not restart on a tick (`reset_lag` runs on a new round, seat or view only).
Along the floor the shoulder view's focus follows the courier at 30/s like the stage view (`FollowCamera.LAG_SPEED_H`: 0.17 m at the run, 28 px; at 10/s the courier would stand 0.5 m ahead of the view's centre at the 5 m/s run and 0.5 m behind it once it turned back,
"ahead and then behind"); in height it follows at 10/s (a step or a landing does not pump the picture).
The check is `tools/strafe_jitter_probe.gd` (a scripted strafe of the solo show in a race, a tile round or the lobby: the courier's screen x per rendered frame, run headless `--fixed-fps 60|120` or offscreen in real time with any frame cap, vsync and an irregular frame pace). Peak to peak jitter of the courier's screen x at the full run, 1280 x 720
(double it on a retina screen): race (stage view) 120 fps 0.00 px, 144 fps 0.05; lobby 120 fps 0.00, 90 fps 0.14, 120 fps with an uneven frame pace 0.10; tile round 120 fps 0.86, 144 fps 0.87 (0.86 is the floor: the run's own speed
ripple, the same at 60 fps); at exactly 60 fps (one tick per frame) it is 0.
The tile stage rounds do not use this camera: they have the stage view and their own movement numbers (below, "The stage camera and feel"). The two long race courses (levels 29 and 30, level key `"camera": "stage"`) play in the stage view too and keep the ordinary walk, jump, buttons and HUD.

**Dash** (`"dash": true` for `show`; `courier/courier_motion.gd`): a quick lunge along the move input (the way the character faces when idle), 11 m/s (2.2 x the walk)
for 0.3 s, so about 3.3 m plus a little braking carry (5.7 m with the air time), with a slight lift that makes a low arc (the 'fly forward' move), and in the air the character dives
(pitched forward about 63 degrees, arms ahead). It can start on the ground or in the air, once per airtime (landing gives it back), cooldown 1.5 s from its start (shared by the ground dash and the air dash, shown by a thin bar low in the middle of the screen while it recharges, `game/dash_meter.gd`); a press just before the
cooldown ends still counts. A trail of puffs in the player's own colour follows anyone moving faster than a walk (`game/dash_trail.gd`), and the whoosh plays at the dasher. Two players on
one keyboard dash with C and comma (Shift is the second player's jump there).

**The dash costs a cooldown, nothing else.** There is no belly flop and no stun: the character lands from a dash (or from a dash in the air) and walks, steers and jumps on the next tick, and a dash that meets a wall
or an obstacle just ends there. The dash works in the air as a burst of air control (one per airtime, landing gives it back, the 1.5 s cooldown is shared with the ground dash): a player who is going to miss a jump presses
it with the stick towards the platform and gets about 3 m sideways and a little lift (`tools/move_strips.gd --mode=airdash`: a jump at the start deck, the dash to the left at the top, 8 m to the side by the landing
because the stick is held, no flop, walking on at once). The flop penalty (the slap, 1.15 s of lying and sliding with no steering, no jump and no new dash, a 1.8 s stun for a dash into a wall) is the mode option `dash_flop`
(modes.json, `Modes.dash_flop()`, `CourierMotion.set_dash_flop`; default off, off for the show, nothing else in the template turns it on): the code, the rig's belly pose and the pose wire's `flop` field serve it, a game
that wants the penalty back sets `"dash_flop": true` in its mode. It is still the player's own physics, like walking: the owner pose carries it to the authority and the other players
(`tools/core_shell_check.gd` dashes through the real owner path, reads the position and, with the option on, the `flop` back from the authority and its snapshot). Measured on a flat 30 m (`tools/dash_penalty_check.gd`, the real motion):
walking 6.17 s, a bot that presses dash every time the cooldown allows 4.22 s (0.68 of the walking time: the dash is a boost for gaps and the goal line and a spammer out-runs a walker, but only 3 dashes in 30 m), with the option on
7.22 s (17 % slower than walking) and a dash into a wall stunning 1.80 s. The cooldown is a real limit: 1.5 s between two dashes, however long the airtime (`tools/courier_check.gd`, `tools/dash_penalty_check.gd`).
Bots never dash (`tools/modes/show_bot_check.gd`); with `--bot-dash` a bot dashes on clear flat ground whenever it can.

## The stage camera and feel

The tile stage rounds (levels 25-28, `CourseSection.level_stage` / `GameRun.stage_round()`; the falling-floor arenas) play with their own camera and their own movement
numbers. Every other round keeps the shoulder view and the walk above, except that a level with `"camera": "stage"` (the race levels 29 and 30) takes the stage view alone (with the air follow: the picture follows a pad's throw): `GameRun._sync_stage_view`, `CourseSection.level_camera`; its movement is the ordinary one.

### Controls and camera

Same controls as above (move relative to the camera, jump, the mouse / right stick / drag orbits), **without the dash**: in a stage round the dash key and the touch dash button do nothing (the button is hidden, `game_run.gd`). The camera is the **stage view** (`game/follow_camera.gd`
`set_stage_view`, switched by `game/game_run.gd` per round): high and far over the arena, the courier a small figure at x 0.50 of the frame, **feet at 0.704 of the frame's height**, 12.2 % of the frame
tall (1.8 m, with a 3.5 m tile: about half a tile of screen is the courier's height). It starts behind the start heading; the look input is a free orbit (the whole circle, from -60 to -3 degrees of pitch for the view axis),
Ctrl + wheel zooms (arm 6-24 m, **12.1 m** by default, measured from the courier's feet). The courier's feet stay at that screen spot at every pitch, yaw and zoom (the camera stands `arm` from the feet at the
angle that puts the feet at 0.704, so the view centre is raised to fit), nothing blocks the camera (the cage has no collision), and the field of view is 65 degrees.

**Nothing of the look hides the courier (near dissolve).** The stage view ignores blockers, so every piece of the look dissolves where it comes up against the eye: gone nearer than **4 m** to the camera, whole from **7.5 m**, a pixel dither between (`style/near_dissolve.gdshaderinc`, decided per fragment on the true distance, opaque pass, no sorting; the shadow stays). It covers every piece that stands up or hangs over the course: the pillar kit's posts and columns, gantry beams, gate frames and gate walls, the start / goal signs and their gantries (`goal_sign.gdshader`), spin bars, hubs and cannons (`candy_prop.gdshader`), the surfaces of `race_surfaces.gd` and `block_kit.gd` (`CandyMaterial.NEAR_TALL`), and the posters, banners, billboards, arches and the hero prop (StandardMaterial3D distance fade, set once per level by `CandyMaterial.dissolve_tree`, `levels/level_world.gd`). Floors are the exception (`CandyMaterial.NEAR_FLOOR`: gone nearer than 4 m, whole from 5.5 m: the nearest floor on the stage view's screen is 6.3 m from the eye even at the flattest pitch, so only a floor the camera really comes up against thins out). The lobby's shoulder view has the same for the yard walls, the back panel and the signs (`lobby_visuals.gd`, `lobby/lobby_rings.gdshader`). A new tall piece must wear one of these materials; `tools/camera_clear_check.gd` flies the camera along every race route and over the lobby yard and lists every frame in which more than 20 % (and every frame in which more than 1 %) of the screen is covered by geometry within 4 m of the eye (header: the command).

* **Pitch** (the view axis, degrees down; the view ray to the feet is 14.6 degrees steeper, 27 standing and about 36 running): 12.4 at rest (`STAGE_PITCH_DEFAULT`), 12.4 + 8.6 = **21 at the full run** (`STAGE_RUN_PITCH`, eased in with tau 0.4 s and out with 0.6 s: 16.4 after a quarter second, 20.3 after one), and 3 degrees further (24 running) for a second after a landing a floor lower than the view (`STAGE_LAND_PITCH`, hold 1 s, in 0.15 s, out 0.5 s). The measured pictures: 12.4 standing, 13.9 / 16.0 / 20.8 running, 24.0 a second after a landing, 28 in a look-up swing (the player's own orbit input reaches it; the table with the frame numbers is above `STAGE_RUN_PITCH` in `follow_camera.gd`); the player's own orbit input is added on top.
  Courier on the render at pitch 14 / 21 / 24: 12.1 / 11.9 / 11.7 % of the frame height (the rig), feet at 71.1 / 71.4 / 71.4 %, x 49.9-50.0 %.
* **Level follow** is close to rigid (30 per second: the courier trails the picture by 0.4 m at the run). **Height** follows the floor under the courier, not its jumps: it is **frozen in the air** (a jump moves the
  courier up the frame and the picture not at all, rise < 0.02 m), and a fall trails by at most 4 m (`STAGE_AIR_TRAIL`, a quarter of the frame). After a landing on another layer the height re-centres with tau 0.11 s
  (`STAGE_LAG_V` 9 per second), no overshoot, no shake.
  **The race levels (29-32, `"camera": "stage"`) do not freeze the air**: `GameRun._sync_stage_view` asks for the **air follow** (`set_stage_view(true, true)`, `FollowCamera.stage_air_follow`; the tile rounds 25-28 keep the frozen air above). A rise past
  2 m over the view centre (`STAGE_AIR_RISE_DEAD`: a normal jump, apex 1.4 m, moves the picture by nothing) is followed with tau 0.15 s (`STAGE_AIR_RISE_TAU`, an exponential approach: no overshoot, never a hard clamp), a fall past 0.5 m under the
  centre (`STAGE_AIR_FALL_DEAD`) with tau 0.08 s (`STAGE_AIR_FALL_TAU`). A goal-tower throw (vy 20 m/s, apex 11.8 m, landing 8.5 m up) keeps the courier, feet to head, inside the middle 70 % of the frame's height the whole way (`tools/stage_feel_check.gd`,
  `camera_air_follow`); after the landing the usual floor follow (tau 0.11 s) brings it back to its spot.
* **Every floor over the viewed courier is hidden** (`_ghost_tiles` with the camera height at -INF): the camera is above the next layer as often as under it, and a slab above would
  hide the courier. The floors below stay.
* **Spectating** keeps your own orbit and only the followed courier changes (the leader, `lead`); an out player's courier is retired where it fell (see "Spectating, podium, crown"): with no leader the view rests there.
* **A phone held sideways** (viewport lower than 480 px) draws it 18 % closer (`SMALL_SCREEN_ARM` 0.82): the courier is 14.8 % of the frame instead of 12.2 %.
* **The start shot** (the render of a courier standing on its pad before GO, `tools/stage_frames.gd`) against the measured picture of the same moment: the courier 11.9-12.5 % of the frame's height in ours (12.2 % in the picture), x 49.9 % (49 %),
  feet at 70.4-71.1 % (70.4 %). Before the retune the follow camera put the feet at 71.0 % with the courier 12.2 % tall by formula, and the frame tool's hand camera put them at 56 %.

### Feel

`courier/courier_motion.gd` `STAGE_FEEL` (set by `set_stage` each tick from `stage_round()`; ice from `set_surface` still wins) is the stage movement in our metres
(a 3.5 m tile, a 1.8 m courier): 3.6 tiles/s = 7 body heights/s, an air time of about 0.54 s, an apex of about 0.9 tile, the jump carrying about two tiles at the run.

| | Stage rounds | Other rounds |
|---|---|---|
| Run | 12.6 m/s (3.6 tiles/s, 7 body heights/s) | 5 m/s |
| 95 % of the run | 0.23 s (acceleration 55 m/s^2) | about 0.3 s (15 m/s^2) |
| Stop (stick released) | 0.15 s, 0.84 m (braking 84 m/s^2, friction 18) | 0.25 s, 0.6 m (20 m/s^2) |
| Jump | 23.3 m/s up, gravity 86.4 m/s^2: apex 3.15 m by the formula (3.34 m measured on 60 Hz ticks, 0.9 tile), 0.54 s of air, about 6.8 m along at the run (two tiles) | 7 m/s up, gravity 17: apex 1.4 m |
| Air control | 0.5 | 0.75 |
| Dash | none: the key and the button do nothing | 11 m/s, cooldown 1.5 s, one air dash per airtime |
| Step up (one tile's lip, a raised pad) | 0.6 m | - |
| Seams between tiles | grounded on every tick, never slowed, floor height off by at most 0.002 m (square and hex, many angles) | - |

**Couriers collide.** In a stage round the couriers are solid for each other: a courier cannot walk through another, and a run, a dash or a head-on collision bumps. Network:
every machine moves only its own courier (the owner path, `network/owner_courier.gd`); other players' bodies are placed from their poses (replicas) and get the courier physics layer in stage
rounds (`game_run.gd` `_sync_courier_bodies`), and a courier's own motion adds that layer to its mask, so it is blocked by the replica it runs into on its own machine, with no new messages.
The bump is the shove path of `PlayerContact` (`stage` on): contact counts within 0.25 m of the capsules or 1.3 ticks of the closing speed (a dash covers 0.4 m a tick, so it never
tunnels), and the closing speed is exchanged like two equal masses with a restitution of 0.5: both get an impulse of 0.75 of it (at most 14 m/s), the one that was run into staggers 0.4 s.
The same symmetric formula runs on both machines, so it does not matter who has the lower slot. A dash into a courier is a tackle, not a bonk (no wall stun), and a bumped courier can
be knocked off the arena's edge. The authority simulates no couriers (its bodies have no shape), so it adds nothing to this.
Measured by `tools/stage_feel_check.gd` (the real motion, contact and camera classes on levels 25 and 26): blocked at 0.88 m, head-on closest 0.66 m (the capsules are 0.70 m), a replica
blocks at 0.70 m with no jitter, a dash hit throws 6.1 m, a run into a standing courier throws 4.7 m, a pile of five settles with no overlap and no jitter.

## Playing alone

`FRIENDS Show.app` (`tools/build_solo_show.py`, `res://show_solo.tscn`, `client/solo_entry.gd`) is the show for ONE player: no title page, the app
opens fullscreen in the lobby yard, one full third-person view, the keyboard and the first gamepad both drive the one courier (controls as in the
table above). Stand on THE SHOW's circle, press PLAY (Enter / pad Y), and the whole show plays (stand on a round's circle instead and that round plays alone; KEEP THE LOGO needs other players and says so): card, race,
survival, final, podium and crown, then the results page (Play Again goes back to the lobby; Main Menu starts the app over). With one player the
show is a points show where nobody is eliminated: the race and the final end at the finish, the survival round runs until the player falls or the
60 s cap (a fall flashes the cast's `eliminated` word, but nothing is out: the face wall shows the placing), the card's second line reads `AS FAST AS YOU CAN` (race and final) or `STAY ON THE FLOOR AS LONG AS YOU CAN` (survival) under the level's own goal line. Two players on one keyboard (WASD
and IJKL) is `FRIENDS Levels.app`. Check: `tools/modes/show_bot_check.gd --solo --shows=2` (one bot, two shows, Play Again between them).

## Tandem (experiment)

EXPERIMENT (switchable): a funny mechanic: **accidental hand-holding.** Two players who run towards or alongside each other, both moving (at least 1.5 m/s), within **1.2 m** for **1.5 s**
grab hands and FUSE into a tandem for **6 s**:

* **Movement.** The pair walks **1.6 times as fast** (the courier motion's `speed` mod, as BOOST has it). Each of the two steers by the **average** of both players' inputs (the world-space steering each player sends; `game/game_run.gd item_move`): both must agree to turn, one who lets go of the
  stick halves the other's steering, opposite inputs cancel. A pair drifting more than 1.5 m apart is pulled together (up to 0.8 of full steering at 3 m), more than 3.4 m apart for 0.6 s and the tandem comes apart.
* **Collisions.** The pair flings whoever it runs into the way a BOOST does (`item_power` 2.2 x the shove, the one hit feels it, the pair feels no kick back); two fused partners never shove each other (`PlayerContact.partners`).
* **Exit.** After 6 s the two spin apart (a spin of 0.7 s on both rigs) with a **fling**: 5.5 m/s outward from each other and 3 m/s up, thrown by the authority through the same cumulative kick every contact impulse rides on (`team.kicks`; the local game launches its own courier).
  An early end (a fall, a grab, a gap, one crosses the goal) is quiet and throws nobody.
* **Look.** Both characters reach for the joined hands (the carry pose with one grip at the hands' meeting point, 0.95 m over the feet, the other arm hangs loose: `game_run.gd rig_hold`), a heart rises from the hands now and then, a pop of hearts and sparks when they fuse, the show's banner (`boon`, lime) says **TANDEM!** on
  both screens with `WITH <NAME>` under it, the others read a line (`MAYA AND THEO ARE HOLDING HANDS`). Hearts and sparks are flat shapes made in code (`modes/show/tandem/tandem_fx.gd`, own materials; nothing of the world's look is touched).
* **Cooldown.** 10 s per pair after a tandem (the pair, not the players: either may fuse with somebody else). A new round forgets cooldowns.
* **Rounds.** Races (a racer on course in a race's play phase, `rules.gd tandem_ok`) and the lobby yard. Not in survival, the tile rounds, the final, the card or the results.
* **Bots** are players like any other: two bots running side by side fuse too (`tools/modes/show_bot_check.gd` runs bots through the real flow).
* **Alone** a **buddy** comes: after 2 s of running (2 m/s) a character (a rig of its own, an animal head) appears 2.5 s behind the player and retraces the player's own trail, so it is always on ground, catches up, runs 1 m beside it and, with both moving, takes its hand 1.5 s later; the pair walks 1.6 x as fast and the buddy steers by the player's own steering 0.45 s late (a sluggish partner: the pair turns wide);
  at the end the buddy is flung away and the player thrown, the buddy comes again after the cooldown. It never comes when there is company (`tandem_solo`), and leaves when the player stands still for 4 s. The same in the lobby yard, which is where to see it without a race.

**Switch.** `demo/modes/show/shared/tandem/tandem.json`: a top-level `on`, per-round switches (`rounds.race`, `rounds.lobby`), `solo_buddy`, the template's own neutral words (`name`, `banner`, `line` with `{a}` and `{b}`) and all numbers (`tuning`: `close`, `hold`, `duration`, `speed`, `shove`, `cooldown`, `min_speed`, `break_dist`, `fling`, `lift`, `spin`). On in this tree. `"on": false`, a round set to false, deleting the file or the cast's `show.tandem.off` turn it off completely.
**The cast** words it (`show.tandem`: `{off, name, banner, line}`, name up to 16, banner up to 30, line up to 48 with `{a}` and `{b}`; `docs/slots.md`); the team's jokes live there, the template's texts are neutral.

**Who does what.** The authority (`modes/show/shared/tandem/tandem.gd`, one object for the whole match, built by `network/match_controller.gd` and, on one machine, `client/local_level_flow.gd`; ticked every physics tick with the slots that may fuse: everybody who joined in the lobby, `rules.tandem_ok` in a race) decides who fuses, when, for how long and when it ends,
and throws the pair apart. It publishes `tandem` in the match state (`pairs` `[id, a, b, age, dur, ax, az, bx, bz]` with each player's world steering, `warm` `[a, b, share]`, `buddy` `[x, y, z, yaw, vx, vz, phase]`, `ev` `[seq, type, a, b]`, `seq`; a few hundred bytes, only while the experiment is on for the scope). Couriers move on their owners' machines, so the **owner's machine applies** the speed, the averaged
steering and the shove from the replicated pair (`modes/show/tandem/tandem_view.gd` puts them into `game_run.gd tandem`, `courier_mods`, `shove_power`, `item_move`); the view also draws the hands, the pop, the banner and the buddy. Nothing a view draws decides anything; no new network protocol.
**Checks:** `tools/modes/tandem_check.gd` (the rules on a stub shell: fuse, exit, cooldown, crowds, the ends, the buddy, the cast's words), `tools/modes/items_harness.gd -- --scenario=tandem --show-level=31` (a race: authority, two replicas, the banners, the owners' mods, the steering average, the shove, the fling) and `--scenario=tandem_lobby` (the lobby yard), and `tools/modes/tandem_solo_check.gd` (the real solo app: the buddy, the fuse, 1.6 x, the banner, the fling, the cooldown, then a race). Video takes (the offscreen binary, `--write-movie`, `--film`): `--scenario=tandem_film_lobby` and `--scenario=tandem_film --show-level=32` (the harness header in `tools/modes/items/tandem_film_*_scenario.gd`).

## Show state

`rules.state()` is published as `match.minigame`; the view (`modes/show/view.gd`) reads only this. All plain data, small.

```
phase   : "card" | "play" | "done" | "podium"          # of the current round
round   : 1..3
rounds  : int, rounds in this show (3, or 1 when a lobby circle of one round started it: the chip and the card then leave out `ROUND n`)
kind    : "race" | "survival" | "final"
play    : String, how a survival level is played besides its kind (the level file's `play`): "" the floor decides, "badge" KEEP THE LOGO
badge   : [slot...]                                     # KEEP THE LOGO: the slots wearing a logo now ([] in every other round)
t       : float, seconds into the phase
count   : float, seconds until the gate opens / GO (card phase; 0 once play), for the 1 and GO
left    : float, seconds left on the round's time cap, -1 none
level   : int, 0-based level index of this round
n       : int, players in the show
points_mode : bool                                      # n <= 3
need    : int, how many qualify / survive this round (points mode: all)
field   : [slot...]                                     # players in this round
status  : [int per slot]                                # 0 playing, 1 safe (qualified / survived), 2 out THIS round (eliminated), 3 spectator (out earlier), 4 crown winner
place   : [slot...]                                     # this round's ranking so far, best first (finished first, then by progress)
pts     : [int per slot]                                # show totals
lead    : int slot the spectators follow (-1 none)
crown   : int slot wearing the crown (-1 none; set in the podium phase)
podium  : [[x,y,z] x3] world positions of the podium room's pedestals (podium phase) else []
top     : [slot...]                                     # the slots on the podium, best first, at most 3 (in the victory banner's `done` and the podium phase) else []
victory : bool                                          # `done` of a round that ends in the podium room: the VICTORY banner (VICTORY 1.7 s), no result wall
card    : String                                        # the card's second line: who qualifies / how the round scores, e.g. "FIRST 4 ACROSS QUALIFY" (rules write it, view shows it under the level's own goal line, `rule` of the level file)
stage   : bool                                          # the round's level is a tile stage round (a `stage` section in its file, docs/level-format.md "Stage rounds"): its own card (title 1.2 s, then 3, 2, 1: `count` runs from 4.2), HUD and VICTORY
fell    : [slot...]                                     # survival: the slots that fell, in order (the kill feed and the eliminations count read it; always present, [] in the other rounds)
tiles, tiles1, tiles2 ... : PackedByteArray              # step tiles (levels with a `tiles` section): one byte per tile in file order, 0 standing, 1..254 the step clock in 0.25 s units, 255 never there (see "Step tiles"); the platform refuses a byte field over 256 B, so the bytes go out in pieces of at most 240 (`StepTiles.chunk_state` in the rules' `state()`, `StepTiles.join_state` in the view): `tiles` holds the first 240, `tiles1` the next, and so on (327 tiles: `tiles`, `tiles1`; at most 4 pieces = 960 tiles)
```

`slot` = index in the round's roster (view: `seats[slot]` = cast index, `cast_player(slot)`). The view turns a status change into the local
player's banner (`show.words.*` with the player's catchphrase under it; a points show shows the placement `1ST`, `2ND` ... after each
round instead) and into an event line for the others.

## What the screen shows

All in `modes/show/` and read from the state above (plus the level clock for the cue), nothing new on the network:

* **Round card** (4 s), one thing at a time, three lines for the first 3 s (`plates.gd`): the level's title (the cast's own round title when it names one, "Rounds can be renamed") on the accent; under it what to do in
  plain words, the level's own `rule` (or the cast's `show.rounds.<id>.rule`: `RUN THROUGH THE LOGO · PROBLEMS ARE WALLS`, `TILES VANISH UNDER YOU · KEEP MOVING`, `STAND ON THE SHOWN PICTURE`,
  `CLIMB TO THE CROWN`, ...; the round kind's default when neither has one); and smaller `ROUND n · KIND · who qualifies` (the state's `card`; one round from a lobby circle: `KIND · who qualifies`). Every line shrinks to the
  screen's width, so the longest fits a phone (844 x 390). Then the digit 1 and GO (the countdown, see "HUD look"); GO stays 1 s. The HUD is
  small and at the edges (`calm`, `docs/modes.md`): the round chip top centre, the timer, counters and feed top right, the scoreboard under them (a show for one
  has no scoreboard).
* **No objective text** (every round): nothing stays top left. The round card says the goal once (the level's `rule`, else the round kind's goal) and under it the level's `hint` (POSTER RUSH: `THE LOGO POSTER TEARS, THE REST ARE WALLS`), then the card is gone; there is no green dot and no persistent objective block (a stage round's pill at the top centre during the countdown is the only repeat).
* **Poster doors** (POSTER RUSH, `levels/poster_doors.gd`, look `style/poster_door_look.gd` and `style/slot_frames.gd`): the rule is PROBLEMS ARE WALLS, RUN THROUGH THE LOGO. A problem poster is a wall (a hidden block behind it) and
  looks it: the cast's obstacle picture and word big and readable on a plate in a hazard stripe, a red no-entry mark. The logo poster has no block and looks like the way out: the brand's logo (the team name without one), the win word
  (`show.rounds.r17.label`, a list cycles by row; else the show's "qualified" word), green chevrons and a check mark. A courier through the logo poster tears it (the board rips down to a scrap hanging
  crooked from one corner, the bare doorway frame shows (a green frame: the way through, visible from the start), paper pieces in the logo's colours fly the way it went, a soft rip; 1.4 s later the scrap rolls up into the top edge and a new poster rolls down out of it, nothing pops back), a
  courier that runs into a problem poster gets a short push back and a hop (3.6 m/s, the slap sound) while the board shudders (a thud for the others). The first row's logo poster is torn from the
  start: the idea shown once. In moving rows the posters and the opening are one rigid assembly on a `slide` hazard (`ride` on the slots): where they are is a function of the level clock (`PosterDoors.travel`), so the
  tear, the push, the observer and the look agree on every machine. Nothing is sent: every client reads the positions it already has (`LevelWorld.observe_doors`, called by the view for every player); the push-back is a pure function of the courier's feet in the owner's own simulation
  (`LevelWorld.door_push`, a `bonk` effect in `apply_effects`), the same for solo, 2 and 6 players. Bots read the doors (`show_bot_check.gd`): they predict where the opening will be when they arrive, hold two metres short and
  line up with it, and follow it through.
* **Live counter** (a dark pill during play): race `Through: x/N` (not in a points show), survival `Standing: x` and `N go through`, KEEP THE LOGO `Logos in play: N`.
* **KEEP THE LOGO** (`view.gd`, look `modes/show/badge_look.gd`, state `badge`): every wearer has a round enamel plate with the team's logo (the brand accent as its rim, no logo: just the plate) on its back and a bigger
  one that turns and bobs 2.4 m over its feet (a plate seen edge-on from the side is why there are two); a logo changing hands is an event line (`MAYA TOOK A LOGO`, `YOU TOOK A LOGO`, `YOUR LOGO WAS TAKEN`) and the plates fly from the one who lost it to the one who took it (0.35 s), the first wearers' plates drop onto them from 3.5 m, a plate nobody takes tumbles away under the arena; the winner's crown comes down onto the head from 5 m and falls away when the podium ends,
  and under it, while nothing else is on the line, the local player reads `YOU HAVE A LOGO  ·  KEEP IT` or `GRAB SOMEONE WITH A LOGO`. Client only: the plates are looks, the rules decide.
* **Step tiles** (`LAST TILE STANDING`, hexagons): `view.gd` joins the pieces `tiles`, `tiles1`, ... of the state (`StepTiles.join_state`) and hands the bytes to the level world, which poses every tile from the level clock and the byte: it shakes and turns red for the last part of its delay, falls and tumbles (gravity, no shrinking) and comes to rest 49 m under the arena after 2.4 s, so nothing pops out: it is gone from the game on every client, collision included, from the first moment of the fall (a late joiner gets the same pieces and sees the same floor at once). Each tile falling or shaking ticks the blink sounds.
* **Cue card** (`PICTURE MATCH`, `plates.gd`): the picture and label of the obstacle to stand on, with a countdown disc that turns red in
  the last second, from the level JSON's `cues` and the level clock.
* **Round result** (4.5 s), one moment at a time, never overlapping: the local player's banner first (1.8 s: the cast's word or the
  placing with the catchphrase; a show for one holds `CLEARED` + the seconds, `LASTED` + the seconds in the survival or `TIME'S UP` for
  3 s and has no wall), then the **face wall** (`face_wall.gd`) alone, centred (between the stick and the buttons on a phone): one cell per player in
  the round, the team photo (`team_wall` entry with the player's name, else the player's colour and initial), flipping to QUALIFIED +
  tick, ELIMINATED + cross, or the placing (`1ST` ...) in a points show and after the final; the name stays on the picture. The local player's own cell is a
  little larger with a white ring. Players out earlier are dimmed. The words are the cast's `show.words`. Without a banner the wall comes
  up at once.

### HUD look (`client/show_theme.gd`, `style/show_hud_kit.gd`, `modes/mode_hud.gd`)

Every HUD piece of every round (race, survival, final, stage rounds, the other minigames' generic HUD, the round card, the face wall, the name tags) draws with one look from `show_theme.gd`: dark pills with a thin light outline, slanted bold Lilita One words centred in the pill (`ShowTheme.pill_words`: even padding, no icon disc at either end), a plain white stopwatch glyph on the timer, gold rank badges. No pill carries a round icon disc: an icon that belongs to a pill (the item pill's item icon, the stopwatch) is drawn as a plain glyph straight on the dark pill. The pieces are in `show_hud_kit.gd` (static draw helpers, scaled by `Kit.k`: the screen's height over 720, never below 0.62, so a phone's pills stay readable); `mode_hud.gd` draws the whole generic HUD from one model with one control, `stage_hud.gd` and `plates.gd` use the same pieces, banners and countdown digits come from `show_banner.gd`.

* **Layout**: objective top left (green dot, white words with a dark edge); round chip top centre; right column top down: the timer pill (`M:SS` in chunky outlined digits with a plain white stopwatch glyph at its right end; the digits turn yellow and the glyph red in the last 10 s), the counter pills, the feed (cream name pills: a red X, or a gold rank badge + the name + the cast's word), the points board (a pill in the player's colour with a gold rank badge, players out dimmed). The yellow marker hangs over the local courier's head. On a phone (touch overlay up) the right column ends 120 px (at the screen's scale) short of the corner: the MENU button is there.
* **Model keys** (`modes/mode_view.gd` `hud()`): `counters` (strings, one dark pill each), `counter_age` (s since they changed: the first one swells), `feed` ([{name, tail, rank (>= 1 gold rank badge, 0 red X), age, left}]), `big_kind` (`victory`, `champion`, `qualified`, `eliminated`, `failure`, `timesup`, `title` = a banner; `digit` and `go` = the countdown; none = a big pill for the mode's own words), `big_age` (s since it came up: the pop), `marker` (the local courier's head on the screen). The show's view sets all of them (`view.gd` `hud()`); stage rounds keep their own model for `stage_hud.gd` (`quest`, `pill`, `elim_*`, `feed`, `digit`, `go`, `victory_age`, `failure`).
* **Round card** (`plates.gd`): the level's title as a `title` banner popping in, then the goal and the qualify line on dark pills.
* **Name tags** (`client/name_tags.gd`): white slanted words on a dark pill with the light outline, a gold ring badge at the end with the player's colour in its dot (an entry's `rank` turns it into a gold rank badge with the number); the own tag is hidden.
* **Preview**: `tools/modes/ui_frames.gd` renders the pieces with hand-made models over a race and a stage level (`--resolution 844x390 --touch` for a phone).

### Stage rounds: the flow (`stage_hud.gd`, `view.gd`, `rules.gd`)

A survival round on a level with a `stage` section (levels 25-28: SQUARE / HEX STACK A / B) has the flow of a tile-drop event, in our own words and look. Nothing of it changes another round.

* **Clock** (`rules.gd`): the card is `STAGE_CARD` = 4.2 s (the authority's phase clock: every machine reads `count` in the state): the round's title plate for the first `STAGE_TITLE` = 1.2 s (`plates.gd`), then the digits 3, 2, 1 one second
  apart (`count` 3 .. 0: the digit is `ceil(count)`), then `play` with GO for `GO_SHOW` = 1 s. Tiles are stepped only in `play`. A stage level has no start gate: a player who steps off the top layer during the card goes back to its start
  (`STAGE_DROP`). The round ends when `alive <= need` (`END_GRACE` 1.5 s later) or at `stage.cap` of the level file; then `done` lasts `STAGE_DONE` 2.3 s (the VICTORY banner) plus the usual `DONE` 4.5 s (the face wall); a lobby circle of one round ends after it.
* **Objective** (`StageHud.objective(need, players)`): `DON'T FALL!  BE ONE OF THE LAST N STANDING!` (N = `need`, 4 with 12 players); `DON'T FALL!  BE THE LAST ONE STANDING!` in a points show (2-3 players, need 1); alone `DON'T FALL!  STAY ON THE TILES AS LONG AS YOU CAN!`.
  Twice: as small text in two lines with a green dot at the top left for the card's digits and the whole play phase, and as a dark pill with up to three lines of slanted words centred in it at the top centre, only while the digits count and GO shows (`pill`: it comes up 10 % too big and goes in one cut).
* **Eliminations**: a dark pill at the top right, `Current eliminations: n/M` in white slanted words centred in it (on a phone it stands left of the MENU button) (M = players in the round - `need`: 8 with 12 players; n = the state's `fell` count, or the players out; it swells when n changes); under it, right-aligned, a cream pill with a red X and the player's name for every
  player who falls (`fell` order, the oldest on top and a new one under it, 2.9 s each then cut out, at most 4; it comes in at two thirds of its width, then 105 %, then 100 %: no slide). A show for one has no pill.
* **Controls on the screen**: no key hint line (the dash and grab keys are not part of a stage round: `TeamPlay.grabs_allowed()` is false, nothing is picked up, couriers bump), and on a phone the walk stick and one flat dark round button (the jump, `TouchControls.set_round_buttons`) bottom right: no GRAB, no DASH, no "Drag here to look around" (the look is still a drag on the right half).
* **Countdown**: the digits and GO come from `ShowBanner.countdown` (each popping in and settling; GO 1 s). The HUD's own digit, title chip, timer, scoreboard and hint line stay out of a stage round.
* **Eliminated players**: a player is out when it LANDS on the ground floor (the fall to a lower layer is nothing, and the kill volume under the ground never fires above it: the `fell` list, the pill and the failure banner all start at that landing). Its own banner is the `failure` banner with the cast's `show.words.eliminated`, fading in over 0.2 s, 1.4 s, no catchphrase (`failure` in the stage HUD's model); then the bottom note `SPECTATING  ·  NAME`; the camera follows `lead` (the state's first player still standing), the player's courier is retired where it landed 1.2 s after the fall (`FALL_SHOW`: hidden, not simulated, nothing collides with it). The round does not end for the one who is out and its camera does not sweep up: the eliminated watch the rest from where they fell. Everyone else's flow keeps running, so five out in the same second are five banners, pills and retired couriers.
* **Starts**: each player stands on a group of their own on the start layer (3 x 3 square tiles, a flower of 7 hexagons on the hex stacks), one gap (14.3 m) over the first full layer, facing the arena (start yaw 180); with fewer than 12 players the groups are spread (`levels/stage_starts.gd`, "Rules by player count"); the start layer is stepped like any layer (white, then gone), and a player who drops from it onto the first full layer is not out.
* **VICTORY**: at the round's end the survivors (status 1; in a points show the one still standing) get the `victory` banner (`ShowBanner.draw`), 2.3 s, instead of the QUALIFIED banner; the wall of faces follows for them (everybody else's wall comes up at once). A player who fell gets the `failure` banner with the cast's `show.words.eliminated` (fading in over 0.2 s, 1.4 s).
* **Own marker and name tags**: the yellow down-pointing triangle over the local courier's head (`model.marker`, the head's screen point from the camera) while it stands, in every round; the other couriers' name tags are the same size on the screen near and far in a stage round, never faded (`client/name_tags.gd`, `STAGE_TAG_PER_METRE`).
* **Sound** (`game_audio.gd`, `view.gd`; samples are the project's own, `audio/sfx/provenance.md`): a tile turning white plays the block crack (`timer_crack`, the atlas region of `sfx-atlas.wav`), a tile dropping the short break (`timer_broken`) on the voice of its own crack; one pool of
  8 voices, at most 3 starts per 100 ms per kind, gain `TILE_GAIN` 0.7 times a fall-off from the listener (full inside 7 m, nothing past 37 m: inaudible cues are skipped). The followed courier's landing on a lower layer is the existing `land` event (`land-1..3.ogg`,
  by fall speed and distance). An elimination plays `fall.ogg` (the `fall` event): the local player's own at full gain, another's scaled by its distance to the followed player (full inside 8 m, down to 12 % at 40 m). The digits play `countdown.ogg`, GO `go.ogg`, VICTORY `level-clear.ogg` (`room_clear`).
  Every other round's step tiles keep the block cues.
* **Checks**: `tools/modes/show_check.gd --only=E` (a stage round through the real flow with 4 players, then the same rules and views for 12 and for 3 players: digits one second apart, pills' data, feed limits, VICTORY, spectating, timings, the race card still 4 s).

### Banners and countdown digits (`style/show_banner.gd`)

Every banner and the countdown digit is drawn by one file, pure drawing (polygons with vertex colours and Lilita One letters, no textures; spiky outlines are cached per size): `ShowBanner.draw(ci, kind, words, age, centre, wide, alpha, line)` with the kinds `victory` (yellow-orange spiky badge, small crown), `champion` (gold, big jewelled crown, sparkles), `qualified` (mint, tick), `eliminated` (grey, cross, cracked, tilted), `failure` (grey, sagging pop), `timesup` (orange-red, stopwatch) and `title` (the wide ribbon with an optional smaller `line` under the round's name). Words are upper-cased and always fit (the lettering shrinks until the plate is at most `wide` px across; `height_of(kind, wide, has_line)` is its tallest). Timeline by `age`: pop-in 0 -> 1.25 x -> 0.92 x -> 1.0 by 0.35 s with a rotation wobble and the letters wobbling one after the other, a soft bob and a shine sweep while it holds `life(kind)` seconds, then it leaves by itself over `LEAVE` = 0.35 s (grows 20 % and fades): nothing is drawn after `total(kind)`, so a caller only keeps counting `age`. `ShowBanner.countdown(ci, word, age, centre, cap_px, go, alpha)` is the chunky cream digit with a mint edge and teal depth (pop 1.3 x -> 0.67 x -> 1.08 x -> 1.0, the stage HUD's timing; GO tilted). Frames: `tools/modes/banner_frames.gd` (offscreen, header has the command; one job per run: `strips`, `overview`, `countdown`, `pop`, `phone`).

## The look

**Nothing in the game vanishes into nowhere** (no pop-in and no pop-out in view): a `blink` block that is gone falls away and hangs out of reach, or falls out of sight when it is gone for the round, and climbs back; a step tile tumbles down and rests far below; a ball and a cannon ball come out of and go into a wall slot, a floor hole or a barrel (`style/shot_looks.gd`); a torn poster rolls up and a new one rolls down; the logo plates and the crown fly in and tumble away; SHOVE-OFF's dropped tile lies on the yard floor until it rises back. Lasers and fire jets switching on and off are effects with their emitters and grates always there, not objects. `tools/vanish_check.gd` runs the numbers on the real levels.

The lobby and the levels are not a grey test chamber: in the show mode the whole world is built from the cast's `brand.colors` and logo
(`docs/backdrop.md`, "The party look"): an open sky with a sea of soft clouds far below, candy islands, balloons and party hats around and
beyond the course, bunting and confetti, the course itself a candy track (checker floor, striped curbs and walls, pillow hop blocks, the
hazards in a candy red) standing on cones like a floating island. A brand colour that is dark, pale, grey or a single one still gets a
legible world; `tools/party_look_check.gd` checks 64 palettes. **Bunting hangs only high** (`style/bunting_rule.gd`, a pure function of the level data):
the line of pennants along the top of a tall wall must be at least 3 m over the highest walkable top within 4 m in front of that stretch of the
face (so even the lowest tip is over a player's head), not hidden behind a taller solid, not on a wall whose own top is walked on (a thick slab, a
plateau), not in the podium shot. Stair risers, low ledges and floor-level sides never wear any. `tools/party_look_check.gd` lists every run of
every show level (wall, face, pennants, line height, clearance) and fails when a built pennant hangs lower than the limit; the lobby's strings
hang 3.0 m up at the lowest. Floor decals (`floor_start`, `floor_finish`) lie 6 cm over the floor, clear
of the floor meshes' own lifts and the START and GOAL pads, so they never fight the floor from any camera angle.

**The GOAL sign and the finish rails** (`style/goal_sign.gd`, `style/finish_rails.gd`, `style/goal_sign.gdshader`; every look but the comic one, a level with an `arch_finish` slot, no
level file key needed). The finish arch is a big hanging shield with a V point over the finish deck: a thick amber glossy bevelled frame with a white inner edge, a purple border with a marquee of
bulbs (a chase, odd and even blinking, a breathing pulse in turn) and small rivets, a recess panel of saturated blue `#1064E1` with a faint pattern of lighter dots (candy look: flat tints, hard plastic roughness 0.11, no light of its own except the bulbs), the huge white extruded GOAL (Lilita One, amber sides) and under it the SUBTITLE in light amber, which is the level's own title (`CourseSection.level_title`: the cast's `show.rounds.<id>.title`, else the level file's; two lines when long), on both faces. It hangs from a beam on two
pylons beside it (on the deck when the deck is 19.2 m wide across the sign or more, else on columns from far below) and touches nothing but its four rods; no collision. Its width is 14 m
(a deck 19.2 m wide or more: the deck's width less 5.2 m, up to 18 m), its V tip hangs where the slot's bottom edge is (`p` y less half the size's height), its facing is the slot's yaw. The GOAL pad, the pole and the
flag stay; the GOAL word and the logo card over the pad are not drawn (the sign says it). The deck (static boxes whose top is the goal floor under the goal volume, plus wide floors
of the same top that touch them) gets railings: square pink posts with white globe lamps on top and two round white rails (see-through). The level's own thin rim walls on and near the deck keep
their collision but are drawn as these railings instead of as dark slabs (`level_world.gd` gives them an invisible `Rail` body); an open edge with no wall gets the same railings as a look only,
and none where another floor or the route meets it. A chequered line lies across the deck at the way in. Frames: `tools/race_view_frames.gd` with a views file (see its header).

## The levels

All carry `"modes": ["show"]`, `"pool": false`, `checkpoints` (races 5-6, final 6, survival none: a fall is out), a `kill` volume and
the show slots (`docs/swappables.md`: which slot ids each contains; obstacle boxes 1-5 in all of them).

| Level | Kind | Title | What is in it |
|---|---|---|---|
| 14 | race | `CIRCUIT BREAKER` | about 80 m course: crates, sliding walls, spinner bars, swinging hammers, blinking floors; start gate (shut for 4 s), goal at the end; arches at start and finish |
| 15 | survival | `LAST TILE STANDING` | three roughly circular floors of hexagonal step tiles (327 hexagons of 2.5 m across the flats: 127, 127 and 73, 4 m apart, the first 30 m across: 10 players on the 1.75 m start ring have room to run; with up to 3 players the outer ring is gone: 255) over the kill volume (64 x 64 m): a hexagon somebody stands on shakes and falls for good (plain 0.75 s, logo tiles 2.5 s, rival tiles wearing an obstacle picture 0.25 s); the players fall from floor to floor, the last floor drops into the kill volume; no ground around the floors (the arch, banners and billboards float just outside them) |
| 16 | final | `CROWN CLIMB` | steps, lifts, sliders, a spinner and hammers up to the crown floating over the hero prop (the company's own object, `docs/hero-prop.md`: a cake, a coin stack, or the built-in stepped stand) at the top; start gate; `podium` spots at the top, the hero prop again at half size on both sides. Six checkpoints (terrace, the platform after `lift_1`, the ramp top, the stair top, the platform after `lift_2`, the summit stairs); the volumes cover the whole landing, not a slice of it, and no kill volume comes within a jump of a lift or a platform (`tools/lift_ride_check.gd`, `tools/level_lint.py`) |
| 17 | race | `POSTER RUSH` | a hall of five rows of posters. PROBLEM posters (the cast's obstacle pictures, each with its word, on a yellow-and-ink hazard stripe with a red no-entry mark) are walls: a courier thuds and is pushed back. The brand's LOGO poster (the logo, a win word, green chevrons and a check mark) tears. The first row has four problem posters and one logo poster, already torn; later rows have more and narrower problem posters (six, then eleven, seven, thirteen), and in the third and fifth rows the whole row slides sideways on the level clock, so the logo poster's opening moves (7 s and 6 s, resting a moment at each end): time the run. Then a push pad over a 4 m gap to the goal |
| 18 | survival | `PICTURE MATCH` | a floor of 28 tiles (24 of 2.75 m, four of 1.25 m in the middle), each wearing one of the five obstacle pictures (8, 6, 5, 4 and 5 tiles; picture 5 is the four small tiles and one big one), on a start pad that falls at 6 s. Twelve cues in a fixed order (pictures 1 5 2 1 2 3 5 3 5 4 3 4, never the same twice; 1 and 2 touch every other picture, so they stop once the windows are under 1.5 s): the first shows from 5 s and gives 5 s, every next window is 0.75 x the one before (0.25 s grid, floor 0.5 s): 5, 3.75, 2.75, 2, 1.5, 1.25, 1, 0.75, 0.5, 0.5, 0.5, 0.5 s. At the end of a window every tile of the other pictures drops (and comes back 2 s later), the next cue shows 2.5 s after the drop. After the twelfth window the other pictures stay gone and the shown one falls 2 s later (54.5 s), the backstop under the 60 s cap. No START or GOAL pad is drawn, no ground under or around the tiles |
| 19 | race | `BOUNCE HOUSE` | about 145 m: four push pads fling the racers over gaps onto branded slabs, six swinging cube heads and a gauntlet of seven bumpers before the goal |
| 20 | race | `POSTER RUSH` | the same idea as 17, in a wider, taller hall: four rows (five, six, nine and eleven posters), the first row's logo poster torn at x = 3.25, the third and fourth rows slide (7.5 s and 6 s), other pictures, and two push-pad hops over an island to the goal |
| 21 | survival | `SPIN BARS` | a stepped round floor (three discs of 19, 13 and 7 m across, outer tier 0.5 m under the core) under two spinning bars through its middle: a 20 m bar (40 deg/s, 0.75 m high, obstacle 1 picture) and a 12 m bar (-65 deg/s the other way, 0.5 m high, obstacle 2 picture); a 5 m pedestal over the start ring holds the players off the bars for the card and the first 6 s of play, then it goes; the discs go one after the other (outer 24 s, middle 38 s, core 50 s of the level clock). `arena: true`, the arch, banners and billboards float beside the floor |
| 22 | survival | `SHOVE RING` | the template's shove-off floor as a show round: four concentric terraces (cylinders 23, 18, 13 and 8 m across, tops 0.25 m apart, rising towards the middle, the start ring stands on the 8 m disc) over the kill volume; contact is on, so players shove each other (walk into someone, GRAB lifts, GRAB again throws). The floor shrinks: the outer ring drops at 14 s of play, the next at 28 s, the next at 42 s, the disc at 54 s (level clock 18 / 32 / 46 / 58, each `blink` shakes 2 s first), so nobody stands the 60 s cap. Obstacle pictures on flat slabs standing 0.25 m up on the three outer rings (they fall with their ring), the logo decal on the disc, four decor boards, arch, banners and billboards floating round the floor. No static ground, so no `arena` flag |
| 23 | race | `ROLLING ROAD` | about 95 m of a 16 m wide road between 8 m walls, crowded with 27 rolling balls of three sizes (0.5, 1.0 and 1.75 m radius) on 11 different periods (3.5 to 8 s), 6 speeds (6 to 10 m/s) and their own phases, so no lane stays open (about 40 % of the road's 1 m slices hold a ball at any moment, and the gap is in a different place each time): one hop-size ball that ricochets off the right wall at the start, nine balls that roll out of the side garages (rows 5 m apart; four cross the whole road and go into the far garage, five stop in the road and sink into the floor), eight more crossing balls from slots in the road's own side walls (a hidden chamber block behind each wall; two cross the whole road, six stop in it), two balls rolling diagonally, three 3.5 m lanes of balls rolling down the road at you with two hop-size balls near them, and two balls zigzagging between the walls (every bend of a path is a bounce off a wall, the linter checks it); four cannons on the walls (mortars: a tube, a muzzle flash and smoke, a recoil) lobbing balls onto the road: each lands, bounces, rolls across to the far wall and goes into a round slot in it (a ball is in play 1.5 to 3.7 s of each 4 s shot); then an 8 m wide bridge over the kill volume with a spinning bar and two sweeping walls (jump the bar, time the walls). No ball pops in or out in view: every ball comes out of and goes into a wall slot (the garages' back walls and the side walls) or a hole in the floor (the lanes, the diagonals, the partial crossings) or its barrel (`docs/level-format.md`, `ball` and `cannon`). The balls are drawn in the world style's palette (night: the accent colours with a glow grid; party: stripes in three colours by size, always against the floor's contrast) and the big ones wear the round's labels (`round_labels("r23")`) or the cast's `round_r23.glb` (`demo/style/shot_looks.gd`). Start gate, five checkpoints (a fall off the bridge goes back to the one before it), goal volume, arches, banners, billboards, obstacle pictures on the garage back walls, the lane side boards, the bar and the sweepers |
| 24 | survival | `KEEP THE LOGO` | a walled 20 x 20 m arena (4 m walls wearing obstacle pictures, so a dash chain cannot leave it) with four pillar boxes (1 m, one hop high) and two low round bumps, a floor that stays: `"arena": true`, `"play": "badge"`, `"solo": false` (see "KEEP THE LOGO"); the kill volume under the floor only catches a courier that was thrown off it |
| 25 | survival | `SQUARE STACK A` | a tile stage round (`stage` section, `docs/level-format.md` "Stage rounds"): four layers of 22 x 22 square step tiles (3.5 m pitch, 1936 tiles, the layers 14.3 m apart: a fall of 0.59 s), a ground floor 57.2 m under the first full layer, a start layer of twelve groups of 3 x 3 tiles one gap over it in a staggered block, enclosure A, cap 140 s. A tile you step on goes 0.5 s later; a player who lands on the ground floor is out. Camera, feel and flow: "The stage camera and feel", "Stage rounds: the flow" |
| 26 | survival | `HEX STACK A` | the same with eight layers of flat-top hexagon tiles (4.06 m pitch, 14.3 m between layers, the ground 114.4 m down), the start layer of hexagon groups over it, cap 150 s |
| 27 | survival | `SQUARE STACK B` | the tiles of 25 inside enclosure B (our own design) |
| 28 | survival | `HEX STACK B` | the tiles of 26 inside enclosure B (our own design) |
| 29 | race | `ROOFTOP RUN` | a long course over rooftops, turning twice to stay inside the level box: belts (across the course 7 m/s, 1.4 x the walk: a straight run crosses, standing still is thrown off; the lane band back along the course 3.5 m/s), spinning bars, gate walls, stepping stones and launch pads to the tower at the end; start gate, 12 checkpoints; `"world": "daylight"` (the race world, `docs/level-format.md`) |
| 30 | race | `FERRY CROSSING` | a longer course with a ferry to ride (three 3 x 3 m blue chevron pads slide 4.5 m up and down beside each ferry rail's dock; no mover comes within 0.3 m of another or of a block, `tools/mover_clearance_check.py`), gate walls (a navy wall, a frame with two eyes and a blue chevron door per gate that slides up into the frame, a 4 s cycle) so the open one has to be picked, belts (the maze's seven rows run alternately left and right at 7 m/s, 1.4 x the walk; the lane strips back along the course 2.5 m/s) and spinner discs, turning three times; start gate, 8 checkpoints; `"world": "daylight"` |
| 31 | race | `SPINNER GARDEN` | about 100 m, 1 plan unit = 5.5 m (generator `tools/gen_level_31.py`): the start deck, a 4 m drop, a diamond of four turning discs (5 m, 60-75 deg/s, alternate directions; `spin` with `hit: false`, a cylinder part and a pointer bar that is a bumper (`bump`: it bounces whoever touches it 9 m/s away with a small pop): the disc carries whoever stands on it, `tools/disc_ride_check.gd`), a hall with a turning bar (axis along the course, 135 deg/s) behind side fences, a hex room with seven low bumps, three parallel small bars on a rod (120 deg/s), two warm ramps each topped by a bar, a still landing disc, a big turning disc (8.25 m, bumper bar) 13 m past it, further than any jump or dash jump reaches, so the way over is the three small turning discs (3.75 m, 75 deg/s) a side, and a narrow kit walkway (2.25 x 10.5 m, top -1.75: inset tiles in a rim) past a four-paddle wheel (-120 deg/s, lowest tip 0.75 m over it) to the finish deck (12 x 12 m, railed like level 29's); every spinner turns at a base rate scaled 0.69 (105 to 135 deg/s) except level 30's field of small discs under the big windmill (35); gate doors and frames are solid and never push (a closing door only nudges a courier out of its way); start gate, 3 checkpoints; `"world": "daylight"`, `"camera": "stage"` |

**EXPERIMENT (switchable): edge bumpers on levels 29-32.** Every stepping stone, landing deck and pad stone of the race levels 29-32 (and the edges of bigger decks that face a jump) carries rounded amber bumper cushions along its open edges: a landing in the clear middle (about 55% of the platform's width) is fine, a sloppy one near the edge is bounced off (8 m/s outward and 3.5 up); a jump that needs the air dash to land is allowed. It is a switch plus runtime decoration and hazards, no level file carries it: `demo/levels/edge_bumpers.json` (`"on": false`, per level or at the top, or deleting the file, turns it off). Rules and probes: `docs/level-format.md` "Edge bumpers (EXPERIMENT, race levels 29 to 32)", `tools/edge_bumper_probe.gd`, `tools/race_jump_probe.gd`.

## KEEP THE LOGO (`"play": "badge"`, level 24)

The show's tag round and the one survival round with a floor that stays (`"arena": true`: `level_lint` leaves out the rule that a survival level has no static ground, and `lift_ride_check` checks only the start ring on it).
At the round's start `need` players (the survival qualifier count, at least one and at most the field minus one: 1 of 2-3, 2 of 4-6, 2 of 7-9, 3-4 of 10) are dealt a logo on their back (random, from the
seeded rng, shown on the card). **GRAB somebody wearing a logo** (the same contact grab as everywhere in the show: F / X / the GRAB button) and the logo is yours, unless you
wear one already; a logo that has just been taken cannot be taken again for 1.5 s (`BADGE_IMMUNE`), so a thief gets away. The grabbed player is held (and can be thrown) as in any grab. A courier that
leaves the floor is put back on the start ring, logo and all, and is not out. At 45 s (`PLAY_CAPS`) the wearers go through (elimination: the rest are out; points mode: the one who wore a logo
longest scores most and the rest follow by their time) and the round is over. Rules: `_deal_badges`, `_tick_badge` (steal on the rising edge of `host.held_by(victim)`), `_take_badge`, the ranking in `_ranking`
(wearers by time held, then the rest). Alone it makes no sense (nobody to take from), so the level says `"solo": false`: a show for one never draws it and its circle says `NEEDS 2+ PLAYERS`.
Measured: `tools/modes/round_pick_check.gd` (the rules with scripted holders: deal, steal, immunity, hand-back after 1.5 s, respawn, wearers through, points), `show_check.gd` scenario D (six players through the real
online flow: a courier walks up to a wearer and presses GRAB, the real contact takes the logo, the views' plates move with it, the results come) and `show_bot_check.gd --pick=r24` (two physics bots, one chases and grabs).

## The manager (experiment)

EXPERIMENT (switchable): "Project manager". At the start of every race round (levels 29-32, also the final on a race) and every tile round (25-28) one random player of the field is named **THE MANAGER**: a banner when the play begins (`THE MANAGER`, who it is) and a little clipboard (a navy board, a cream sheet with four lines and a mint tick, a gold clip: `modes/show/manager/manager_marker.gd`, built in code) that turns and bobs over their head on every screen (a child of the rig's `head_anchor`). The manager keeps the role through the whole round, also when they have crossed the goal or fallen.
**The switch** is `demo/modes/show/shared/manager/manager.json` (the way `levels/edge_bumpers.json` switches the edge bumpers): `"on": false` there, or deleting the file, turns it off for every round. `rounds.race|final|survival.on` switches by round kind, `levels."<file number>".on` by level (a level entry wins); the cast can take it out of its own show with `show.manager.off: true` or single rules with `show.manager.rules[].off`. The file also has the timing, the neutral texts and the rules.
* **The prompt.** `first` (22-30 s) into the play, then every `every` (60-75 s, from one prompt to the next; when the event gate lets it, see "One interrupting event at a time" below) the manager is asked for a RULE: a **compact strip at the bottom edge of the screen** (small, translucent: three chips with the number, the rule's icon and name; a thin bar under it runs out with the prompt) instead of a panel in the middle; never two the same, never the one issued last. The prompt stays open `prompt` = **3 s**, then a random one of the three is issued (a bot after 1.2 s). **1 / 2 / 3** pick a card (the number keys travel as `test_seq`, the item lab's wire: `game_run.gd number_keys` lets them through while the prompt is open for this player), **E** (pad **Y**, the phone's ITEM button) picks a random one of the three, a **click or a tap** on a chip picks it (the chip sends the same number key). On one keyboard for two players the number keys are the first player's, the second one has **B** (random). A **bot** (`host.is_bot`, the checks' scripted players; the show has none in play) picks at random after 2 s, a manager who says nothing gets a random rule after `prompt` (9 s). While the prompt is open the manager's ITEM and number presses pick a rule and do nothing else (`items.gd _manager_asks`; for 0.6 s after the pick too: a typed key is two events and the second must not hand out a lab item). The others read `<name> IS PICKING A RULE` at the top.
* **The rules** (`manager.json` `order`, the wire's order; each lasts 10-15 s, a draw in the rule's own range or the cast's `tuning.duration`), for everybody else still racing or standing (not the manager, nobody who has crossed the goal or fallen), 0.9 s after it was issued so the banner lands first:

| id | name | what it does | where |
|---|---|---|---|
| `flip` | INVERTED | steering inverted | `mods.invert` (the item FLIP's own mod) |
| `moon` | MOON JUMP | gravity 0.28 times: floaty jumps and long falls | `mods.gravity` (`courier_motion.gd`) |
| `nojump` | NO JUMPING | the jump press is ignored | `mods.no_jump` |
| `giant` | EVERYONE GIANT | the rig is drawn 2.3 times as big about its feet | `rule_scales` (eased in over 0.45 s) |
| `tiny` | EVERYONE TINY | the rig is drawn 0.42 times as big | `rule_scales` |
| `ice` | SLIPPERY FLOOR | the ice's friction under the feet unless the ground has a feel of its own (slime, level ice) | `mods.ice` |
| `walk` | WALK ONLY | half the pace and no dash | `mods.speed` 0.5, `mods.no_dash` |
| `upside` | UPSIDE DOWN | the cameras of the victims turn over (roll 180 degrees at 5 rad/s), never the manager's: online each client turns its own; one machine with a view each (split screen) turns the victim's view only; one shared view on one machine turns over when a victim is on it | `follow.fx.roll` of the main camera and of each `split_follow` (`manager_roll` is our share of it) |

  Alone (a show for one player) nobody else is there: **you are the manager and the rule hits you**, 1.6 s after you issued it (the item lab's way of making a rule visible). With scripted bots in play the rule hits the bots.
* **The screens.** The rule's banner (a SMALL banner, 1.3-1.4 s on screen: `alert` red on the screens it hits, `item` blue elsewhere: `NO JUMPING!`, the line under it `<name>'S RULE`) and a pill at the bottom centre with the rule's icon, its name and the seconds left (red outline where it hits). The banners wait for the show's own banner (GO, a result) and make room for an item banner (`modes/show/manager/manager_view.gd`).
* **Who does what.** The authority (`modes/show/shared/manager/manager_rules.gd`, built by `modes/show/rules.gd`, ticked after the items in the play phase, also in tile rounds) owns the manager, the prompt, the choice and the clock and publishes `manager` in the show's state while the round is in its card or play phase (about 300 bytes): `{mgr, ph (0 idle, 1 prompt, 2 rule), t (prompt seconds left), ch (the three rule indexes), rule, dur, age (negative while the rule is still to start), seq (rules issued: a view tells each once), tg (the slots the rule applies to now), solo, round}`. A courier moves on its own machine, so each owner's machine applies the rule from the replicated state: `manager_view.gd` puts the mods of the targets in `game_run.gd rule_mods` (`slot_mods(slot)` merges them with the items' `item_mods` for the motion and the steering), the scales in `rule_scales` and the roll on the local camera; nothing the view draws decides anything.
* **Texts.** The template's are neutral and short (`THE MANAGER`, `NO JUMPING!`,  `manager.json` `texts` and `rules`). A cast changes them in `show.manager` (`docs/slots.md`, checked by `tools/cast_check.py`): `title` / `prompt` (up to 24), `line`, `you`, `waiting`, `made` (up to 48, `{manager}` is the name) and `rules[]` `{id, name (16), banner (30), line (48), off, tuning.duration (3-30 s)}`. The Summer cast (`summer-show-cast`) has MANAGER SAYS: ... lines.
* **Checks.** `tools/modes/manager_check.gd` (the rules on a host of the script's: the first prompt, three different rules, the 3 s AFK pick, the targets, the 60-75 s interval and the gate, the keys, a bot, a show for one, a tile round, the switches, the cast's words, the courier mods, the view on a stub shell), `tools/modes/items_harness.gd -- --scenario=manager --show-level=31` and `--pick=r25` (the authority, three racers and two replica clients: the banner and clipboard on both screens, every rule on both machines, the keys and a tap as `test_seq`), and `tools/modes/manager_flow_check.gd` (the real local flow with the real key path, alone and with two players).

### One interrupting event at a time (the event gate)

So that play is not broken up by quick-time events one after another, every event that breaks into play on its own clock asks ONE gate (`modes/show/shared/event_gate.gd`, owned by `modes/show/rules.gd` as `gate`, ticked every tick, reset with every round, authority side only: the clients only draw what the granted event puts in the state) and is granted only when **none is running and 15 s have passed since the last one ended**. A denied request is queued when its window can wait (the manager's prompt, the eggplant's handout and the clock's boost/soar ask again every tick; the gate keeps **one** waiting caller and forgets it when it stops asking) and skipped otherwise (a second caller that finds the queue taken: a clock caller asks again 7 s later, never a whole clock cycle later; a pigeon on its next press). An event that is never ended is called over by the gate after its announced length + 5 s.

| counts (asks the gate) | holds it from ... to ... |
|---|---|
| the manager (`manager_rules.gd`) | the prompt opens until the rule it issued ends (or the prompt closes unanswered) |
| the hot eggplant (`eggplant_rules.gd`) | the clock's handout until it pops (time, the goal, the carrier leaves); the passes in between are the same event |
| the clock's BOOST / SOAR ("new subscriber", "went viral": `items.gd _events_clock`) | the handout until the effect is gone |
| a pigeon's splat (`pigeon_rules.gd _try_drop`) | the DROP until its blob has landed and no splat is left on a screen; never queued: a pigeon that cannot drop now waits, and its DROP pill's bar shows the wait |

Not gated, on purpose: the **held items** of the boxes (a player's own deliberate choice, one at a time, a roll every box respawn: a press must always do what the player means), the **tandem** (two players who chose to hold hands), a pigeon's **COO** (a ping, no cover), the item lab's and the tools' forced events. The clocks are spaced to match: the manager about every 60-75 s (first 22-30 s), the eggplant about every 90 s (first about 40 s), the clock's boost/soar every 50-70 s (first 40-55 s); the banners of the experiments are small (`ShowBanner.small_wide`) and short (`item`/`alert`/`boon` kinds hold 1.3-1.4 s). Checks: `tools/modes/event_gate_check.gd` (the pure rules: events asked at t = 0, 5, 10 s, only the first runs, the next is granted 15 s after it ended; one waiting caller; the overrun) and `tools/modes/items_harness.gd -- --scenario=gate --show-level=31` (a real race, everything due at once for two minutes: never two at once, 15 s apart).

## Dash exploit audit (`tools/exploit_check.py`, `tools/exploit_probe.gd`)

The dash has no penalty (above), only the 1.5 s cooldown (`DASH_COOLDOWN`; the reaches below were measured with a 1.0 s cooldown, so they are upper bounds: a longer cooldown can only shorten them; `tools/exploit_check.py` models 1.5 s); the reaches below are those of the dash itself.

What the dash really reaches (the real courier, `courier_motion.gd`): a walking jump clears 4.4 m on the level and 1.5 m up. A jump plus one air dash clears 11.2 m, and the chain
ground dash, jump, air dash (the cooldown is 1 s from the start, the ground dash does not use the air dash) clears 15.9 m on the level (17.9 m 4 m down, 15.2 m 1 m up) and peaks at
2.93 m (3.00 m with a fine search of the timings). The model of the tool matches the real courier within 1 % (15.89 against 16.01 m). Rules of thumb for a level author:
a gap or pit a section depends on is at least 17 m wide, or something at least 0.5 m over the highest chain flight (apex + the height of the take-off spot, a rail or banner counts) stands
in the way; a wall, door or fence that must hold is at least 3.5 m over its floor; nothing you can reach by the walk-and-jump route or a pad is within 17 m of a spot that stands outside the course.
A touch breaks the painting on a `hit` block, so a `hit` block is a wall for every flight and never a floor (the ropes over the BOUNCE HOUSE pits, the billboard panels, the cap on the banner wall of level 16).

`python3 tools/exploit_check.py [--level N] [--emit-probe jobs.json]` audits levels 14-20 (about 2 minutes; ends with `EXPLOIT_CHECK ok=<bool>`): the surfaces reachable from the start by walk + jump
and by walk + jump + dash (pads, bumpers, lifts and slides included, pad flights simulated with steering and a dash on top), every connector the dash can do without (SKIP) and every
one it cannot (held), every reachable surface outside the play area (wall tops, beams, banners, hero-prop surroundings; the survival levels allow only tile and blink floors), the
barriers and their margin, the near-misses. Surfaces past the goal are not counted. `tools/exploit_probe.gd` plays the jobs on the real collision (`--jobs=<file>`; `--lobby` flies the yard's trampoline and dash against the walls).

| Where | What the dash could do there | What holds it |
|---|---|---|
| 19 BOUNCE HOUSE, the pits (5.6 to 8.5 m) | the dash chain could skip them from pad 1, 3, 4 (probe without the ropes: 10/40, 40/40, 30/39 strategies land) | a ring (rope fence, `hit`) across every pit at 4.5 / 5.5 / 6.5 / 5.5 m over the slab, 0.7 to 1.4 m under the pad flights and above the chain from the rails; probe 0/40, 0/39, 0/40, 0/40, farthest crossing 1.1 to 3.3 m short |
| 19, beams, pillars, banner board of the first gantry (9.4 and 11.8 m) | reachable by pad 2 + dash at a lower height | the first gantry stands as high as the others, its swing arm longer and ±30° |
| 19, the billboard panels (4 and 6 m) | reachable from pad 1 | `hit` |
| 16, the banner wall top (9 m) | reachable from the high lift with the dash | capped with a `hit` strip; the summit posts are only past the crown |
| 17 / 20, the poster doors | a 3.0 m door would hold by only 0.07 m over the chain | 3.5 m (+0.57 m), `poster_door_check` |
| 14 gap section (19 m between floors) | the real chain gets 16.0 m (3 m short) | the gap itself |
| the lobby yard (trampoline + dash) | over a 3.4 m wall 33 of 80 strategies fly out (feet up to 4.94 m) | walls 5.65 m: 0 of 80 |

Not modelled: tilted blocks, a bonk or bumper chain in the air, the movers' tops as take-off spots beyond their sampled poses; the probe skips mover jobs. Bots never dash, so `show_bot_check` does not exercise this; 
the pad flights themselves are checked on the real courier (`--pace=0.7` bots finish BOUNCE HOUSE in 56.6 s, `third_person_check` has no problem).

## How it is wired

* Round list and picks: `demo/modes/lineup/round_list.gd` (the circles' source), `network/walk_in_lobby.gd` (`shown_pads()`, `pad()`, `zone_at()`), `client/walk_in_markers.gd` (the boards), `network/match_controller.gd` and `client/local_level_flow.gd`
  (`round_pick` / `host.pick`, `_may_play` in the local flow for rounds that need other players), `modes/mode_host.gd` (`pick`).
* Rules: `demo/modes/show/rules.gd` (id `show`, `Modes.RULES`), shared by the authority and the local game; they decide from the players'
  positions only and start every round with `ModeHost.begin_level(level)` (the shell plays it in play mode `CourseSection.SHOW`).
  `CourseSection.show_levels(kind)` lists the 0-based levels whose `"show"` is `kind` (in file order); one is picked at random (`host.rng`) at each round
  (`--show-level=<file number>` overrides it in the dev tools).
* Host queries (`modes/mode_host.gd`): `zone`, `scorch`, `checkpoint_at`, `respawn`, `retire`, `progress`, `podium`, `level_clock`, and for step
  tiles `tile_start`, `tiles_under`, `apply_tiles`. Survival rules (`_step_tiles`) stamp the level clock onto every standing tile under an alive, unheld
  player (the authority sees the players' positions anyway) and `tiles` goes out in the state; every machine (authority, clients, the local
  game) applies the same bytes to its `LevelWorld` tiles (`levels/step_tiles.gd`; the hexagon grid maths is `levels/hex_grid.gd`: a courier is mapped to its hexagon cell by cube rounding), so the colliders agree. The look is `style/step_tile_look.gd`, client only.
* A respawn faces along the course: `level_world.gd` `_course_yaw` aims at the first path point at least `FACE_AHEAD` (4 m) of path past the nearest one, so a checkpoint that stands to the side of a winding hall (POSTER RUSH's second hall, level 20) looks along the way and not across it (an aim at the end of the nearest segment would point across the hall at level 20's checkpoints 1 and 4). `balloon_round_check` walks every level, the show's too, and checks all 46 checkpoints.
* View: `demo/modes/show/view.gd` (client; the card, 1, GO, the objective hint, banners, events, the spectator note, the crown, the poster doors' sounds), with
  `plates.gd` (round card, cue card), `stage_hud.gd` (a tile stage round's pills, digits and VICTORY, "Stage rounds: the flow") and `face_wall.gd` (the wall), the ending `demo/modes/show/shared/victory_flow.gd` (banner, camera, landings) and the room `demo/style/podium_room.gd`, the crown's look `demo/style/show_crown.gd`, the frames
  `demo/style/slot_frames.gd`, the hero prop's look `demo/style/hero_prop.gd`, the cast reads `demo/style/team_cast.gd` (`show_word`, `slot_picture`, `crown_model`, `hero_prop_model`, `obstacle`, `team_wall`).
* Level format: `docs/level-format.md` ("Show levels"); `python3 tools/level_lint.py demo/levels` checks `show`, `podium`, the gate, `cues`, `rule`, `hint` and the poster doors' blocks.
* Tile stage rounds (levels 25-28): `modes/show/rules.gd` (`STAGE_LAND`, `_ground_y` from `CourseSection.level_stage(level).ground.y`, the ranking at the cap), `levels/stage_starts.gd` (`pick(pads, count)`, used by `LevelWorld.team_start`), `game/follow_camera.gd` (the stage view),
  `courier/courier_motion.gd` (`STAGE_FEEL`), `game/game_run.gd` (`_stage_options`, no dash button). Checks: `tools/stage_feel_check.gd` (feel and camera numbers on the real classes), `tools/stage_round_check.gd` (bot rounds on levels 25-28 with 2, 4, 8, 10, 12 players, "How long a round takes"),
  `tools/stage_floors_check.gd`, `tools/lift_ride_check.gd` (the rules put out a courier on the spots off the tiles), `show_check.gd --only=E` (the flow), `show_bot_check.gd --pick=r25..r28`.
* Check: `tools/modes/show_check.gd` plays the whole show headless through the real online flow (points show with two players, elimination
  with six); the command is in its header. `tools/modes/show_bot_check.gd` runs two physics bots through a show (`--show-level=N` per round,
  `--pace`; a level with `cues` is played by a bot that reads them, `--dumb` makes bot 1 ignore them; on step tiles a bot walks to the nearest
  untouched hexagon and never jumps, so it leaves a trail and in the end walks off the edge). `tools/step_tiles_check.gd` is the number check of the tiles. `tools/modes/mode_framework_check.gd`
  and `mode_round_check.gd` cover the registry and the circle. `tools/modes/round_pick_check.gd` is the check of the round circles (list, geometry, one round per circle, no double points, KEEP THE LOGO's rules), `show_check.gd`'s scenarios C and D play a
  picked round and KEEP THE LOGO through the real flow, `show_bot_check.gd --pick=<id>` plays a circle in the local flow (`--solo --pick=r24` shows that a show for one refuses it). `tools/poster_door_check.gd` proves the poster doors of levels 17 and 20 with real courier physics (the problem poster's push-back, the logo poster's pass, the torn one, the observer's bursts, and the sliding rows: tear when the opening is there, thud when it is not, a courier standing in the opening when it sets off is met by the shutter's edge, pushed back in front of the row on its feet and never stuck in it, the observer's view at both clocks).

## Add a round or a level

A new level of an existing kind:

1. Write `demo/levels/level_NN.json` (next number, `docs/level-format.md`) with `"modes": ["show"]`, `"pool": false`, `"show": "race" | "survival" | "final"`,
   a `podium` of three spots on a `final`, `checkpoints` (at least 3 on
   a race, 2 on a final), a `kill` volume and a goal volume (the race's finish, the final's crown). Give it a `"rule"`: what to do in it in plain words (the card's middle line,
   upper case, at most 48 characters; players read it for 3 s), and a `"hint"` when the first seconds need one more sentence under GO.
2. A `race` or `final` gets a START GATE: a `blink` hazard `{"id": "gate", "slot": "gate", "on": 4.0, "off": 600, "warn": 1.0}` across the start (the rules'
   countdown matches it: GO at level clock 4.0). `"slot": "gate"` makes its two big faces wear the brand (logo, team name, accent: `docs/swappables.md`). A survival floor that falls under the players' feet is a `tiles` section ("Step tiles" in `docs/level-format.md`); a floor that falls at a set time is a `blink` hazard with `"on": T, "off": 600`.
3. Obstacle boxes: `"slot": "obstacle_1".."obstacle_5"` on blocks, hazard parts or a mover's `s` box; frames: `slots[]` with `arch_start`,
   `arch_finish`, `banner_1/2`, `billboard_1/2`, `floor_start`, `floor_finish`, `crown`, `hero_prop` (a stand and its three cylinders: `docs/hero-prop.md`). A box wearing a cast obstacle is trimmed in the brand accent (a plain light
   trim without one), never in a fixed colour.
4. Obstacles are obstacles: a moving `hit` hazard throws the courier it touches (`docs/level-format.md`, "The bonk"); a swing hangs from a gantry beam, lintel or wall; a
   push pad or bumper stands on a block (it is drawn as a pad or a ball on a base there). `level_lint` checks the last two, `tools/bonk_check.gd` the first.
5. Run `python3 tools/level_lint.py demo/levels`. Several levels of one kind: one is picked at random each show.


A new round that is a new level of an existing kind needs nothing else: it appears on a lobby circle of its own (title = circle) and in the draw of its kind. Level keys for the rest: `"solo": false`
keeps it out of a show for one (its circle says `NEEDS 2+ PLAYERS`), `"play": "badge"` is KEEP THE LOGO's way to play a survival level, `"arena": true` allows static ground in a survival level.

A new round KIND: a new entry in `KINDS` and `CAPS` in `rules.gd` (a new way to play inside a kind, like `play`, takes a tick function and a `PLAY_CAPS` entry), its tick function (`_tick_course` and `_tick_survival` are the
models: they move `status`, fill `across` or `fell` and call `_end_round`), a case in `_plan_round` (`need` and the card's qualify line; the goal line is the level's `rule`, or `KIND_GOALS` of `plates.gd`), a title in
the view (`KINDS` of `view.gd`), a value in `SHOW_KINDS` of `tools/level_lint.py` and at least one level of that kind. The number of rounds is
`KINDS.size()`. The rules never touch nodes; the view reads only the state above.
