# Swappables: everything the party show lets a team change

The brief for an agent that fills THE SHOW (`"mode": "show"`) without reading code. Every swappable is
listed with where it shows, its type, its size, the exact cast key or file and what the game does without it. The show's flow and rules are in `docs/party-show.md`, the field formats in `docs/slots.md`.

Everything lives in `demo/cast/`: `cast.json` plus files with fixed names next to it (the ending may be `.png`, `.jpg` or `.webp`;
pictures at least 256 px on the short side, under 4 MB). Rounds: R1 RACE = level 14 `CIRCUIT BREAKER`, 17 or 20 `POSTER RUSH`, 19
`BOUNCE HOUSE` or 23 `ROLLING ROAD`; R2 SURVIVAL = level 15 `LAST TILE STANDING`, 18 `PICTURE MATCH`, 21 `SPIN BARS`, 22 `SHOVE RING` or 24 `KEEP THE LOGO` (not in a show for
one); R3 FINAL = level 16 `CROWN CLIMB` (one level per round is drawn per show; each round is also a lobby circle of its own, `docs/party-show.md`). The lobby and THE SHOW offer only the rounds of the lineup (`demo/modes/lineup/lineup.json`, "The lineup" in `docs/party-show.md`): levels 25-32, the four stage rounds and the four races, with the finish played on a second race; the others stay in the repo, hidden. The rounds' names, goal lines and hazard looks are swappable too: `show.rounds.<round id>` (below, "Rounds as metaphors").

## Every swappable

| id | Where it shows | Type | Size | Cast key / file to drop | Fallback when absent | Seen in |
|---|---|---|---|---|---|---|
| `team_name` | R1, R2, R3: the beam of the start arch (R1 also the finish arch), banners and floor decals that have no picture; lobby floor word, window title, results | text | 1-18 letters | `team.name` (required) | `FRIENDS` | [01](show-frames/01-r1-gate-acme.jpg) [02](show-frames/02-r1-gate-tidewheat.jpg) [09](show-frames/09-lobby-tidewheat.jpg) |
| `team_title` | title screen, over the results headline | text | up to 40 letters | `team.title` | the team name | title screen and results (not in the frames) |
| `team_tagline` | caption under the title, loading screen | text | up to 60 letters | `team.tagline` | template line | [09](show-frames/09-lobby-tidewheat.jpg) |
| `logo` | R1, R2, R3: logo plate on the arch beams; R2 (level 15) the LOGO TILES that last longer (a cream plate with the logo on it); R2 (level 24, KEEP THE LOGO) the round plates the logo wearers carry on their backs and over their heads; the floor decals at the start (R1 also finish); the small plate on the front of the built-in crown; billboards without picture; lobby logo wall | image | 1024 x 1024, transparent PNG is best, fitted whole; a JPG/PNG on a white or solid background is keyed out by `tools/cast_prep.py` (no box on shirts, plates or tiles) | `brand.logo` = `"logo.png"`, file `logo.png` | arches show the team name only; floor decals the team name lettering; the crown has no plate; a billboard with neither picture nor logo is not drawn; logo wall shows the team name | [01](show-frames/01-r1-gate-acme.jpg) [02](show-frames/02-r1-gate-tidewheat.jpg) [07](show-frames/07-r3-crown-acme.jpg) [09](show-frames/09-lobby-tidewheat.jpg) |
| `brand_colors` | R1, R2, R3: the normal tiles of level 15 (hexagons in three tones: the first colour with colour in it, a second one and a paler first), the three hues of the falling-tile rounds 25-28 (the stage tiles of `style/stage_tile_look.gd` keep the candy tile palette's three colour roles and their saturation and value, and take the hue of the brand's role for each: the blue and cyan floors and their pads the first hue (P), the hexagon rounds' amber lower floors the third (A), the square rounds' start pads (mid blue) and deep blue mats the first (P), the purple floors the second (S); the chevron walls round the arena are S; the template's own colours give blue/cyan, orange and magenta), the accent colour of arch beams, banner and billboard fallbacks, obstacle plates without an own colour, the crown's gems; painted stripe along the walls and lobby; the menus' primary colour (PLAY, the chosen tab, the progress bar, the logo's extrusion) (the page backdrops stay yellow, violet behind a yellow or orange brand colour: `style/menu_kit.gd`); in the show mode also the palette of the whole world (track, curb and wall stripes, hop blocks, sky, islands, bunting, confetti: `style/party_look.gd`, `docs/backdrop.md`) | colour | 1-3 `#rrggbb`, the first with colour in it is the accent | `brand.colors` | template palette | [01](show-frames/01-r1-gate-acme.jpg) [02](show-frames/02-r1-gate-tidewheat.jpg) [05](show-frames/05-r2-tiles-acme.jpg) [06](show-frames/06-r2-tiles-tidewheat.jpg) |
| `world_style` | the whole show world: lobby yard and every level, R1, R2, R3 (floors, walls, hop blocks, movers, the sky, the world around the course, bunting, confetti, the boards' lettering, the tiles of level 15, the lobby's signboards) | choice | `party`, `night`, `auto` | `world.style` (no file) | `party`: a bright candy world in the brand colours (docs/backdrop.md "The party look"). `night`: a dark sci-fi world in the same palette roles (docs/backdrop.md "The night look"): near-black glossy floors and walls with thin glowing lines in the first brand colour, dark obstacles with accent trim, a dark sky with stars and a metal sun, floating hexagon platforms, monoliths and light rings, light blades along the walls, embers; players, hop blocks and hazards stay far lighter than the floor and picture faces stay lit. `auto`: `night` when the first brand colour is near black (HSV value under 0.30), else `party`. Pick `night` for a dark logo or brand, a tech, sci-fi, game or night-time product, or a `team.style` that reads that way | `party` (a missing, empty or unknown value) | frames of the Summer cast and a navy-and-cyan one: `tools/modes/show_frames.gd` (not in `show-frames/`) |
| `obstacle_1` | R1 static crates (level 14), R2 the rival tiles of LAST TILE STANDING (level 15), R3 sliding blocks (level 16); on every face of those boxes | image + text + colour | 1024 x 512 (2:1), label up to 16 letters | `obstacles[0]`: `label` (REQUIRED), `picture` = `"obstacle_1.png"`, `color`; file `obstacle_1.png` | no entry or no label: the boxes look like normal blocks; no picture: a plate in `color` (else the accent, else yellow) with the label lettered on the four sides | [05](show-frames/05-r2-tiles-acme.jpg) [06](show-frames/06-r2-tiles-tidewheat.jpg) |
| `obstacle_2` | R1 sliding walls (14), R2 rival tiles (15), R3 spinner (16) | image + text + colour | as `obstacle_1` | `obstacles[1]`, `obstacle_2.png` | as `obstacle_1` | [03](show-frames/03-r1-obstacles-acme.jpg) [04](show-frames/04-r1-obstacles-tidewheat.jpg) |
| `obstacle_3` | R1 spinner bars (14), R2 rival tiles (15), R3 swinging hammers (16) | image + text + colour | as `obstacle_1` | `obstacles[2]`, `obstacle_3.png` | as `obstacle_1` | [03](show-frames/03-r1-obstacles-acme.jpg) [04](show-frames/04-r1-obstacles-tidewheat.jpg) [05](show-frames/05-r2-tiles-acme.jpg) [06](show-frames/06-r2-tiles-tidewheat.jpg) |
| `obstacle_4` | R1 swinging hammers (14), R2 rival tiles (15), R3 lifting platforms (16) | image + text + colour | as `obstacle_1` | `obstacles[3]`, `obstacle_4.png` | as `obstacle_1` | level 16 lifts (not in the frames) |
| `obstacle_5` | R1 static crates (14), R2 rival tiles (15), R3 static boxes (16) | image + text + colour | as `obstacle_1` | `obstacles[4]`, `obstacle_5.png` | as `obstacle_1` | [06](show-frames/06-r2-tiles-tidewheat.jpg) |
| `tile_plain` | R2 (level 15): the normal step hexagons, three tones that fall 0.75 s after somebody stands on one. The falling-tile rounds 25-28 wear their own tile palette in the brand's hues (see `brand_colors`: the hexagon pads and the square rounds' pads and mats P, the amber floors A, the purple floors S) | colour | in the show the party palette's hop-block tones (saturated tones of the brand's colours and two more hues that go with them); outside it the first colour with colour in it of `brand_colors`, the second colour (else a paler first) and a paler first | `brand.colors` (no file of its own) | template palette | [05](show-frames/05-r2-tiles-acme.jpg) [06](show-frames/06-r2-tiles-tidewheat.jpg) [33](show-frames/33-tiles-layers-acme.jpg) [34](show-frames/34-tiles-layers-tidewheat.jpg) |
| `tile_logo` | R2 (level 15): the LOGO hexagons, a cream plate with the logo in an accent rim; they stand 2.5 s after the step (the plain ones 0.75 s) | image (the logo) | the logo, fitted | `logo` (no file of its own) | concentric hexagons in the accent colour | [05](show-frames/05-r2-tiles-acme.jpg) [06](show-frames/06-r2-tiles-tidewheat.jpg) [35](show-frames/35-tiles-trail-acme.jpg) [36](show-frames/36-tiles-trail-tidewheat.jpg) |
| `tile_rival` | R2 (level 15): the RIVAL hexagons, the obstacle's picture (cropped by the hexagon) in a red rim; they go 0.25 s after the step, nearly at once: avoid them | image | the picture of `obstacle_1`..`obstacle_5` (one kind per obstacle) | `obstacles[i]`, `obstacle_<i+1>.png` | hazard stripes in the obstacle's colour (plain stripes when the cast has no such obstacle) | [05](show-frames/05-r2-tiles-acme.jpg) [06](show-frames/06-r2-tiles-tidewheat.jpg) [37](show-frames/37-tiles-fall-acme.jpg) [38](show-frames/38-tiles-fall-tidewheat.jpg) |
| `banner_1` | the survival and final levels only: R2 (level 15, one side of the arena), R3 (level 16, over the first steps of the climb). The race levels (R1) carry no banners and no billboards: their brand is the START gate and the floor decals | image | 2048 x 512 (4:1), covers the cloth | `banner_1.png` | the team name on the accent colour | [05](show-frames/05-r2-tiles-acme.jpg) [06](show-frames/06-r2-tiles-tidewheat.jpg) |
| `banner_2` | R2 (15, the other side of the arena); not in R1 or R3 | image | 2048 x 512 (4:1) | `banner_2.png` | the team name on the accent colour | [05](show-frames/05-r2-tiles-acme.jpg) [06](show-frames/06-r2-tiles-tidewheat.jpg) |
| `billboard_1` | R2 (15, beside the arena), R3 (16, on the climb); not in the race levels | image | 1536 x 864 (16:9), covers the board | `billboard_1.png` | the logo on the accent colour; none without a logo | [05](show-frames/05-r2-tiles-acme.jpg) [06](show-frames/06-r2-tiles-tidewheat.jpg) [07](show-frames/07-r3-crown-acme.jpg) [08](show-frames/08-r3-crown-tidewheat.jpg) |
| `billboard_2` | R2 (15), R3 (16, at the top, behind the podium); not in the race levels | image | 1536 x 864 (16:9) | `billboard_2.png` | the logo on the accent colour; none without a logo | [05](show-frames/05-r2-tiles-acme.jpg) [06](show-frames/06-r2-tiles-tidewheat.jpg) [15](show-frames/15-podium-tidewheat.jpg) [16](show-frames/16-podium-acme.jpg) |
| `start_gate` | R1 and R3: the wall that holds the racers behind the start line for the 2-1 (it drops at GO); its two big faces, about 17 x 4 m | image (the logo) + text + colour | the logo, the team name, the accent | `logo`, `team_name`, `brand_colors` above (no file of its own) | the team name on the accent, no logo plate | [01](show-frames/01-r1-gate-acme.jpg) [02](show-frames/02-r1-gate-tidewheat.jpg) |
| `arch_start` | R1, R2, R3: the START gate over the start (levels 14-32): ONE rounded gantry across the whole start platform in the GOAL sign's design family (style/start_gate.gd): two purple plastic legs standing inside the platform's rim (or against a side wall), a bevelled amber band between them with the marquee bulbs, and ONE brand plate in the band's recess on both faces: the logo on its round plate, the extruded START word and the team name under it. A level whose start has no floor under both ends (the survival rounds hang in the air) keeps the older pillar arch with the plate between its columns (style/goal_arch.gd); the comic look the flat arch | image (the logo) + text | the logo, the team name | `logo` and `team_name` above (no file of its own) | the team name under START, no logo plate | [01](show-frames/01-r1-gate-acme.jpg) [02](show-frames/02-r1-gate-tidewheat.jpg) |
| `arch_finish` | R1 only: the finish (levels 14, 17, 19, 20, 23, 29-32): in every look but the comic one a hanging GOAL sign over the finish deck (style/goal_sign.gd: white GOAL, the round's title in light amber under it, no logo, no team name); the comic look has an arch instead: the GOAL word hangs under its beam and no logo card floats over it (the arch wears the logo) | image (the logo) + text | as `arch_start` | `logo` and `team_name` | as `arch_start` | [04](show-frames/04-r1-obstacles-tidewheat.jpg) |
| `floor_start` | R1, R3: a decal on the floor at the start line (not R2: a survival level has no ground to lay it on) | image (the logo) | the logo, fitted | `logo` (no file of its own) | the team name lettering | [01](show-frames/01-r1-gate-acme.jpg) [02](show-frames/02-r1-gate-tidewheat.jpg) |
| `floor_finish` | R1 only: a decal on the floor, centred on the GOAL pad under the finish arch (levels 14, 17, 19, 20, 23; 5 x 5 m, the logo cut to its visible content and centred) | image (the logo) | the logo, fitted | `logo` | the team name lettering | R1 finish (not in the frames) |
| `crown` (slot) | R3 (level 16): the crown floating over the hero prop at the top of the climb (1.5 m tall, 0.25 m over its top) | 3D model | about 0.5 m wide, origin at its base centre, +Y up, scaled to the crown's height, under 5 MB | `crown.glb` (glTF binary) | the built-in crown: a chunky gold ring with five rounded points with ball tips and three gems in gold bezels in the accent (no logo plate) | [07](show-frames/07-r3-crown-acme.jpg) [08](show-frames/08-r3-crown-tidewheat.jpg) |
| `hero_prop` (slot) | R3 (level 16): the company's own object as the stand the crown floats over, a big three-tier stand at the top of the climb that players walk up to and jump up (it is the goal's mark: no GOAL pad, word, flag or logo card there); two half-size copies flank the podium | 3D model, procedural (Blender script, never AI-generated) | built at 4.5 m across the floor x 3.0 m tall, origin at the bottom centre, +Y up, front +Z, top flat at 3.0 m; three tiers of radius 2.25 / 1.5 / 0.75 m, 1 m each, the collision; fitted into the slot's box; under 5 MB (`docs/hero-prop.md`) | `hero_prop.glb` (glTF binary); built by `tools/cast_models/hero_prop_*.py --colors <brand colours> --logo <logo>` | a stepped stand in `brand_colors` (bottom to top) with the logo on a plaque at the front | [46](show-frames/46-hero-cake-tidewheat.jpg) [47](show-frames/47-hero-coins-acme.jpg) [48](show-frames/48-hero-climb-tidewheat.jpg) [49](show-frames/49-hero-climb-acme.jpg) [50](show-frames/50-hero-fallback-tidewheat.jpg) [51](show-frames/51-hero-fallback-acme.jpg) |
| `hero_prop_podium` | the podium after the final (level 16): the same model at half size on both sides of the three steps (stairs a courier walks up) | 3D model | as `hero_prop` | `hero_prop.glb` | the built-in stand at half size | [15](show-frames/15-podium-tidewheat.jpg) [16](show-frames/16-podium-acme.jpg) |
| `crown_winner` | the podium after the final (level 16): the winner's crown, worn on their head (it comes down onto it at 3.9 s, slightly tilted, riding the head bone through every clip). Once it has landed it is the winner's HAT (catalog item `hat_crown`, `award: crown`, `demo/character/models/items/hat_crown.glb` made from the built-in crown by `tools/export_crown_hat.gd`): saved, sent to the other players like any wardrobe pick, and in the wardrobe's Hat tab for the players who won it, where None or another hat takes it off and the Crown tile puts it back. The hat is always the built-in crown; a cast `crown.glb` only changes the podium crown | 3D model | as `crown` | `crown.glb` | the built-in crown | [15](show-frames/15-podium-tidewheat.jpg) [16](show-frames/16-podium-acme.jpg) |
| `player_name` | name tags, the scoreboard, event lines ("MAJA QUALIFIED!"), results ("<NAME> TAKES THE CROWN") | text | up to 12 letters | `players[i].name` (required) | `PLAYER n` | [11](show-frames/11-phone-race-844x390.jpg) [12](show-frames/12-banner-qualified-6p.jpg) [13](show-frames/13-banner-eliminated-6p.jpg) [14](show-frames/14-spectator.jpg) |
| `player_color` | the player's shirt and their row on the scoreboard | colour | `#rrggbb`, clearly different between players | `players[i].color` | default seat colour | [09](show-frames/09-lobby-tidewheat.jpg) [11](show-frames/11-phone-race-844x390.jpg) [12](show-frames/12-banner-qualified-6p.jpg) [14](show-frames/14-spectator.jpg) |
| `player_title` | the small title under the name tag in the lobby and next to the player's row on the results | text | up to 16 letters | `players[i].title` | none | lobby name tags and results (not in the frames) |
| `catchphrase` | R1, R2, R3: under the big banner when the local player is QUALIFIED / ELIMINATED / CHAMPION; in a points show (2-3 players) under the placement banner (1ST, 2ND ...) | text | up to 60 letters, case kept, fine for strangers | `players[i].catchphrase` | no line under the banner | [12](show-frames/12-banner-qualified-6p.jpg) [13](show-frames/13-banner-eliminated-6p.jpg) |
| `word_qualified` | R1, R2: the big banner when a player is through (not shown in the final) | text | up to 16 letters, shown in capitals | `show.words.qualified` | `QUALIFIED!` | [12](show-frames/12-banner-qualified-6p.jpg) |
| `word_eliminated` | R1, R2: the big banner when a player is out | text | up to 16 letters | `show.words.eliminated` | `ELIMINATED` | [13](show-frames/13-banner-eliminated-6p.jpg) |
| `word_champion` | R3 podium: the big banner for the winner of the show | text | up to 16 letters | `show.words.champion` | `CHAMPION!` | results page (not in the frames) |
| `word_go` | R1, R2, R3: the big word when a round starts (after the 1) | text | up to 16 letters | `show.words.go` | `GO!` | the 1 and GO card (frames 58, 59) |
| `round_title` | the round's name: the round card (big, on the accent), the round's lobby circle board, the results headline of a round played alone, the server's level log; every level of the round (POSTER RUSH levels 17 and 20 are one round) | text | up to 24 letters, shown in capitals | `show.rounds.<round id>.title` (round ids `r14` `r15` `r16` `r17` `r18` `r19` `r21` `r22` `r23` `r24` `r25` `r26` `r27` `r28`) | the level file's own title (`LAST TILE STANDING` ...) | the round card and the lobby boards (not in the frames) |
| `round_rule` | the goal line under the title on the round card, the subtitle of the round's lobby circle | text | up to 48 letters, capitals; say in plain words what to do | `show.rounds.<round id>.rule` | the level file's own rule line (`TILES VANISH UNDER YOU  ·  KEEP MOVING`) | the round card (not in the frames) |
| `round_hint` | the line under the goal on the round card | text | up to 48 letters, capitals | `show.rounds.<round id>.hint` | the level file's own hint (none for most rounds) | in play (not in the frames) |
| `round_label` | R2 `r15`: the plain hexagons wear the words in turn (cream card, big ink word; logo and rival tiles stay as they are); R1 `r17` the word under the logo on the tearing posters; R2 `r21` printed along both long faces of the spin bars; R1 `r23` printed on the balls | text, one or a list | one text or a list of up to 8, each up to 16 letters, capitals; short and readable from the camera | `show.rounds.<r15, r17, r21 or r23>.label` | `r15`: the plain tiles; `r17`: `show.words.qualified`; `r21`: the obstacle's own sign; `r23`: the balls as they are | `r15` / `r21` / `r23` / `r17` in play (not in the frames) |
| `round_model` | R2 `r21`: replaces the look of both spin bars; R1 `r23`: replaces the look of the balls. Collision and gameplay never change | 3D model, procedural (Blender script, never AI-generated) | a glb under 5 MB, authored at its real-world axes (long axis +X, origin at the centre, +Y up), fitted evenly inside the hazard's collision box (see "Rounds as metaphors") | `show.rounds.r21.model` = `"round_r21.glb"` (file `round_r21.glb`); `show.rounds.r23.model` = `"round_r23.glb"` | the default look of the hazard | in play (not in the frames) |
| `item_text` | races with item boxes (levels 29-32, `docs/items.md`): the item pill's name, the big banner on the victim's screen, the line the others read ("{user} ... {victim}") | text x 3 per item | name up to 16, banner up to 30, line up to 48; `{user}` and `{victim}` are filled in; capitals | `show.items[].name`, `.banner`, `.line` (ids `smash` `call` `flip` `glitch` `dance` `boost` `soar` `eggplant`; the eggplant also has `.pass` and `.pop`) | the template's generic words (`demo/modes/show/items/items.json`) | the item pill and the banner (not in the frames) |
| `item_sfx` | the item's hit sound on the victim's machine | audio | Ogg Vorbis mono, up to 4 s and 300 KB | `show.items[].sfx` = `"items/<file>.ogg"` (file in `demo/cast/items/`) | the template's own generated sound (`demo/audio/items/`) | audio |
| `item_voice` | a spoken line when the item hits, played with the banner (empty: no voice) | audio | as `item_sfx` | `show.items[].voice` = `"items/<file>.ogg"` | none: banner and sound only | audio |
| `item_call_media` | the 5-minute call's footage inside the video-call window | video | Ogg Theora `.ogv` under 16 MB, silent, 16:9 | `show.items[]` with `id` `call`: `media` = `"items/<file>.ogv"` | a generic animated placeholder drawn in code | in play |
| `item_tuning` / `item_off` | durations and strengths of an item; taking an item out of the show | numbers / flag | inside the ranges of `items.json` | `show.items[].tuning`, `.off` | the template's numbers; every item is on | in play |
| `pigeon_text` / `pigeon_tuning` / `pigeon_off` | GHOST PIGEON (`docs/pigeon.md`): the banner of a player who became a pigeon, the coo bubble, the splat word, the two lines ("{user} ...", "{user} ... {victim}"); its speeds, cooldowns and ranges; the switch | text x 5 / numbers / flag | banner up to 30, coo 16, splat 16, lines 48; numbers inside the ranges of `pigeon.json` | `show.pigeon`: `{banner, coo, splat, line, drop_line, tuning, off}` | the template's neutral texts and numbers; the experiment is on | in play |
| `music` | the gameplay loop during the rounds | audio (existing loops) | an id of `demo/audio/music/friends-<id>.ogg`: `careful-step`, `lofi`, `electronic`, `hiphop`, `indie`, `funk`, `epic` | `music` | `careful-step` | audio |
| `credit_link` | results screen only: a small half see-through watermark in the bottom right corner, "Made by the <team> team" and the link (a click opens it) | text (one `https://` link) | up to 100 letters | `team.credit_link` | no line | results screen (not in the frames) |
| `posters` | not in the show's levels (levels 14-16 carry no `poster_<i>` slot); lobby and the other modes only | image + text | 768 x 1024 | `posters[i]`, `poster_<i>.png` | the lobby: the next of billboard_1/2, banner_1/2, obstacle pictures (the logo is on the logo wall); other modes: poster 1 the logo, else none | [09](show-frames/09-lobby-tidewheat.jpg) |
| `team_wall` | lobby: the photo board in the yard; after each show round: the face wall (a player's cell shows the photo of the entry with their name in capitals) | image + text | 512 x 512, square, under 1 MB | `team_wall[]`, `team/member_<n>.png` | the person's colour and initial; no board without entries | lobby photo board, the wall [32](show-frames/32-wall-points-acme-844x390.jpg) |

Not swappable: the round kinds (RACE, SURVIVAL, FINAL), the card lines ("FIRST 4 ACROSS QUALIFY"), the levels, hazards, rules and
camera, the controls, the podium, the placement banners (1ST, 2ND ...). The rounds' names, goal lines and hazard looks are swappable (next section).

## What each level contains

| Level | Round | Title | Slot ids it places | Obstacle boxes (and what they are) |
|---|---|---|---|---|
| 14 | R1 RACE | `CIRCUIT BREAKER` | start gate (`gate`), `arch_start`, `arch_finish`, `floor_start`, `floor_finish` | 1 crates (static), 2 sliding walls, 3 spinner bars, 4 swinging hammers, 5 crates (static) |
| 15 | R2 SURVIVAL | `LAST TILE STANDING` | `arch_start`, `banner_1`, `banner_2`, `billboard_1`, `billboard_2` (all hanging in the air: no ground under them) | 1-5: the rival tiles of the step floors (hexagons wearing the obstacle's picture in a red rim, they fall almost at once: 0.25 s); the normal tiles wear `brand_colors` (and, with `show.rounds.r15.label`, a cream card with one of the labels in turn), the logo tiles (2.5 s) the `logo` |
| 16 | R3 FINAL | `CROWN CLIMB` | start gate (`gate`), `arch_start`, `banner_1`, `billboard_1`, `billboard_2`, `floor_start`, `hero_prop` (the summit stand and two podium copies), `crown` | 1 sliding blocks, 2 spinner, 3 swinging hammers, 4 lifting platforms, 5 static boxes |
| 17 | R1 RACE | `POSTER RUSH` | start gate (`gate`), `arch_start`, `arch_finish`, `floor_start`, `floor_finish` | 1-5: the PROBLEM posters (walls), each with its picture, label and colour on a hazard-striped plate, five rows (the third and fifth slide); the logo poster is a separate look (the brand's logo, the win word `show.rounds.r17.label`, else `show.words.qualified`), the one that tears |
| 18 | R2 SURVIVAL | `PICTURE MATCH` | `arch_start`, `banner_1`, `banner_2`, `billboard_1`, `billboard_2` | 1-5: the floor tiles (8, 6, 5, 4 and 2 tiles per picture); the cue card shows the picture and label of the one to stand on |
| 19 | R1 RACE | `BOUNCE HOUSE` | start gate (`gate`), `arch_start`, `arch_finish`, `floor_start`, `floor_finish` | 1-5: the plates of the launch pads, the landing slabs, the swinging cubes (hammer heads) and the bumpers |
| 20 | R1 RACE | `POSTER RUSH` | as 17 | 1-5: the problem posters, four rows (the third and fourth slide); `obstacle_1`'s slot is the logo poster's board |
| 21 | R2 SURVIVAL | `SPIN BARS` | `arch_start`, `banner_1`, `banner_2`, `billboard_1`, `billboard_2` (hanging in the air: no ground under them) | 1: the slow 20 m bar; 2: the fast 12 m bar (with `show.rounds.r21.label` both wear a plate with the label on their two long faces instead of the obstacle's sign; with `show.rounds.r21.model` the model replaces their look) |
| 22 | R2 SURVIVAL | `SHOVE RING` | `arch_start`, `banner_1`, `banner_2`, `billboard_1`, `billboard_2` (hanging in the air: no ground under them), `floor_start` (the logo decal on the middle disc), four decor boards | 1-5: flat slabs on the three outer rings of the round floor (they drop with their ring: 14, 28 and 42 s of play); 1-4 again as decor boards round the floor |
| 23 | R1 RACE | `ROLLING ROAD` | start gate (`gate`), `arch_start`, `arch_finish`, `floor_start`, `floor_finish` | 1-5: the back walls of the ball garages, the side boards along the lanes, the spinning bar (3) and the two sweeping walls (4, 5) of the bridge. The 27 balls have no picture: they wear the round's `label` words (the big ones) or its `model` (`show.rounds.r23`, below), else the palette stripes |
| 24 | R2 SURVIVAL | `KEEP THE LOGO` | `arch_start`, `banner_1`, `banner_2`, `billboard_1`, `billboard_2`, `floor_start` (the logo decal in the arena's middle); the arena walls wear 1-4 | 1-4: the four walls; 5, 2, 3, 4: the four pillar boxes (the logo plates the wearers carry are the `logo`) |

| Slot id | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `arch_start` | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes |
| `arch_finish` | yes | | | yes | | yes | yes |  |  | yes |  |
| `banner_1` |  | yes | yes |  | yes |  |  | yes | yes |  | yes |
| `banner_2` |  | yes | |  | yes |  |  | yes | yes |  | yes |
| `billboard_1` |  | yes | yes |  | yes |  |  | yes | yes |  | yes |
| `billboard_2` |  | yes | yes |  | yes |  |  | yes | yes |  | yes |
| `floor_start` | yes | | yes | yes | | yes | yes |  | yes | yes | yes |
| `floor_finish` | yes | | | yes | | yes | yes |  |  | yes |  |
| `hero_prop` (may repeat) | | | yes (3: the summit, two at the podium) | | | | |  |  |  |  |
| `crown` | | | yes | | | | |  |  |  |  |
| `obstacle_1` .. `obstacle_5` | all five | all five | all five | all five | all five | all five | all five | 1 and 2 | all five | all five | all five |

`docs/show-frames/` holds rendered frames of the two sample casts (index: `docs/show-frames/README.md`: brand against brand per round, the
phone, the banners, the podium); the "Seen in" column links the frames where each swappable can be found.

The crown the winner wears is built by the view in the podium phase on level 16 and parented to the character's head anchor (`character_rig.gd head_anchor`), so it appears whichever slot set the level has. The hero prop is
placed by the level (`docs/hero-prop.md`).

## Rounds as metaphors

A team's own words make the show theirs: the cast renames and re-skins a round without code. `show.rounds.<round id>` in `cast.json` holds, per
round, any of `title`, `rule`, `hint`, `label` and `model`. Nothing here touches collision or gameplay: the same tiles fall, the same bars
turn at the same speed, the same balls roll. A round without an entry plays as the level file says.

```json
"show": {"words": {...}, "rounds": {
  "r15": {"title": "DON'T DROWN IN PRS", "rule": "TILES VANISH UNDER YOU · KEEP MOVING", "label": ["#1234", "LGTM", "WIP"]},
  "r21": {"title": "KEY ROTATION", "model": "round_r21.glb"},
  "r23": {"title": "MERGE CONFLICTS", "label": "CONFLICT"},
  "r17": {"title": "BREAK THROUGH", "label": "SHIP IT"}}}
```

A round id is `r<file number of the round's first level>` (the same ids as the lobby circles): POSTER RUSH is levels 17 and 20 and is one round, `r17`
(there is no `r20`). Which key each round takes, and where it shows:

| Round id | Round (levels) | Keys it takes | `label` shows as | `model` replaces |
|---|---|---|---|---|
| `r14` | CIRCUIT BREAKER (14) | `title` `rule` `hint` | | |
| `r15` | LAST TILE STANDING (15) | `title` `rule` `hint` `label` | the plain hexagons wear the labels in turn (dealt in shuffled rounds): a cream card with the word big in ink, the tile's colour kept around it; the logo tiles and the rival picture tiles stay as they are | |
| `r16` | CROWN CLIMB (16) | `title` `rule` `hint` | | |
| `r17` | POSTER RUSH (17, 20) | `title` `rule` `hint` `label` | the word under the logo on the tearing posters (default `show.words.qualified`) | |
| `r18` | PICTURE MATCH (18) | `title` `rule` `hint` | | |
| `r19` | BOUNCE HOUSE (19) | `title` `rule` `hint` | | |
| `r21` | SPIN BARS (21) | `title` `rule` `hint` `label` `model` | printed on a plate along both long faces of each bar (one text on both bars; with a list, bar 1 wears the first, bar 2 the second) | both bars: `round_r21.glb` |
| `r22` | SHOVE RING (22) | `title` `rule` `hint` | | |
| `r23` | ROLLING ROAD (23) | `title` `rule` `hint` `label` `model` | printed on the balls (the labels go round, ball by ball) | the balls: `round_r23.glb` |
| `r24` | KEEP THE LOGO (24) | `title` `rule` `hint` | | |
| `r25` | SQUARE STACK A (25) | `title` `rule` `hint` | | |
| `r26` | HEX STACK A (26) | `title` `rule` `hint` | | |
| `r27` | SQUARE STACK B (27) | `title` `rule` `hint` | | |
| `r28` | HEX STACK B (28) | `title` `rule` `hint` | | |
| `r29` | ROOFTOP RUN (29) | `title` `rule` `hint` | | |
| `r30` | FERRY CROSSING (30) | `title` `rule` `hint` | | |
| `r31` | SPINNER GARDEN (31) | `title` `rule` `hint` | | |
| `r32` | GATE RUSH (32) | `title` `rule` `hint` | | |

* `title` (up to 24 letters, shown in capitals) replaces the level's title everywhere it shows: the round card, the lobby circle's board, the
  headline of a round played alone, the server's level log. `rule` and `hint` (up to 48 letters, capitals) replace the goal line under the title
  on the round card (and on the lobby circle's board) and the hint under the goal on the round card. An empty or missing key keeps the level file's own text.
* `label` is one text or a list of up to 8, each up to 16 letters, capitals. Only `r15`, `r17`, `r21` and `r23` take it (see the table). Short words
  read from the third-person camera; a long word shrinks to fit. With a `model` on the same round, `r21` prints no label (the model is the look).
* `model` is the file name `round_r21.glb` / `round_r23.glb`, exactly, in `demo/cast/`: a glTF binary under 5 MB, made with a script in Blender (never
  AI-generated). A file the cast does not name, or a name the round does not take, is an error in `tools/cast_check.py`; a model that does not load at
  runtime falls back to the default look.
* Everything is checked by `python3 tools/cast_check.py`: an unknown round id, a key the round does not take, too long a text, more than 8 labels, a
  wrong file name, a missing or too big glb.

**The model convention** (same spirit as the hero prop, `docs/hero-prop.md`; the game fits, you author at real size):

| What | Rule |
|---|---|
| Axes | real-world axes: the LONG axis along **+X**, origin at the **centre** of the thing, **+Y up**, front +Z. A spin bar is long along X; a ball is round, any axis |
| Fit | scaled UNIFORMLY (never stretched) so it lies inside the hazard's collision box, centred on the hazard's pivot. `r21`: the bar's box (the slow bar 20 x 1.0 x 0.5 m, the fast bar 12 x 1.0 x 0.5 m): the scale makes its length match the box length, and a model whose height or depth would stick out is shrunk until it fits. `r23`: a ball: the scale makes its largest dimension the ball's diameter, centred, and it spins with the ball's roll |
| Spin | a spin-bar model is a child of the bar, so it turns with it about the pivot; a ball model rolls with the ball |
| Collision | never changes: the hazard still hurts and bonks by its own box or sphere. Make the model fill that box (a bar as long as the box) so what you see is what hurts |
| Size | under 5 MB; a few thousand triangles, one or two materials (phones draw it) |

**Writing a good metaphor**: never about a person or a named colleague, short, titles up
to 24 letters; the title must still say what to do or be a clear metaphor, and the `rule` line says the goal in plain words. A round that
would become unreadable under a joke keeps its own title.

## How an agent fills it

1. `demo/cast/cast.json` first: `"mode": "show"`, team name and colours, `players[]` (name, a clearly different colour, catchphrase, title),
   `obstacles[0..4]` (label required, a short thing, up to 16 letters), `show.words` in the team's manner, `music`.
2. Then the pictures at their sizes: `logo.png` (1024 x 1024), `obstacle_1..5.png` (1024 x 512), `banner_1/2.png` (2048 x 512),
   `billboard_1/2.png` (1536 x 864). House style from `docs/slots.md`: clean printed graphics, flat vector shapes, soft shading, no
   lettering, no people, no human figures, no characters, no brands but the team's own logo.
3. Optional last: `hero_prop.glb`, the object the team makes or sells as the stand under the crown (a layered cake for a bakery, a stack of
   coins for a payments or parcels company): `docs/hero-prop.md` has the box, the anchor and the stepped silhouette it keeps to, and the
   scripts that build one from the brand colours and the logo in one command (`tools/cast_models/`). Then `crown.glb`. Neither is AI-generated: each is
   made with a script in Blender (the crown a small mesh, about 0.5 m wide, origin at the base centre, +Y up) or left out.
4. Rounds as metaphors (optional, the cast's own words): `show.rounds.<round id>` per round:
   `title`, `rule`, `hint`, `label`, and a `round_r21.glb` / `round_r23.glb` made in Blender.
5. Content rules: `AGENTS.md` and `docs/slots.md` (public game: proud to share, no pitch, prices or links, inside jokes only as eggs).
6. Check: `python3 tools/cast_check.py`, then `python3 tools/ship.py` until it prints `SHIP ok=true`.

A missing swappable never breaks the game, it falls back. Try the samples: `cp -R samples/tidewheat/. demo/cast/` (every swappable
filled, own crown, a cake as the hero prop) and `samples/acme` (a coin stack as the hero prop; no banners, billboards or crown: the fallbacks).
