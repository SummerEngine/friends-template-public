# Show frames: the proof that the cast personalises the show

Rendered with the offscreen engine build on a project clone, from the two sample casts: `samples/acme` (orange, no banners, billboards or
crown of its own: the fallbacks) and `samples/tidewheat` (teal and violet, every picture, six players, its own `crown.glb`). Same game, same
levels, same code: only `demo/cast/` differs. 1024 px wide JPEG (phone frames 844 x 390, the sheets 1600 px):
third-person camera, the Shift dash, the calm HUD, hexagon floors, the hero prop, knock-back hazards, the party look.

How they were made (all dev tools, offscreen binary only, one render at a time):

| Frames | Tool |
|---|---|
| 01-09 (free camera, no HUD) | `tools/modes/show_frames.gd -- --shots=<dir> --prefix=<brand>-` |
| 10-11 (phone, touch layout, two local players in split view) | `tools/modes/show_bot_check.gd -- --frames=<dir> --size=844x390 --touch --stop=6` |
| 12-16 (the real online flow, the player's own camera and HUD) | `tools/modes/show_check.gd -- --shots=<dir> --only=A\|B --cast=real [--show-level=<file number> ...]` |
| 17-27 (free camera: levels 17-20, couriers posed on the spot) | `show_frames.gd` shots `p17_burst_bonk`, `p20_doors`, `b19_pads`, `b19_gauntlet`, `m18_grid`, `m18_drop`, `m18_finale` (list `SHOTS` in the script) |
| 33-38 (free camera: the step hexagons, stepped on the spot) | `show_frames.gd` shots `t15_layers`, `t15_trail`, `t15_fall` (the tile steps of a shot are the 7th element of its `SHOTS` entry; `t15_arena` is 05/06) |
| 39-40 (the real flow on a phone, 12 s into the survival round) | `show_check.gd -- --only=A --cast=real --show-level=15 --touch` at `--resolution 844x390` (shot `A_5_survival`) |
| 28-32 (the real flow: the round card, the cue card, the face wall) | `show_check.gd` as above (`--show-level=17 --show-level=18` for 28-29; 30 and 32 at `--resolution 844x390`) |

| 52-53 (the show's shoulder camera in every show level) | `show_frames.gd -- --shots=<dir> --tour=3` (the real `FollowCamera` with the player's character at three spots of each show level's route; `--tourlevel=<file number>` for one level, `--tp=<name>:<level 0-based>:<feet x,y,z>:<yaw degrees>` for any spot); the sheet is shots `tp14_2` .. `tp20_2` and `tp16_3` |
| 54-55 (a hammer bonk, in the air) | `show_bot_check.gd -- --solo --show-level=14 --frames=<dir> --bonk-shot --bonk-z=-55` (the bot's first throw past the hammers; the frame is 0.15 s into it, from the player's own camera) |
| 56-57 (the dash) | `show_bot_check.gd -- --solo --show-level=14 --frames=<dir> --dash-at=3` (the bot presses DASH, the frame is 0.12 s later) |
| 58-59 (the calm HUD in order: card, 2, GO + key hint, banner, face wall) | `show_check.gd -- --shots=<dir> --only=A --cast=real` (shots `A_1_card_race`, `A_2_count`, `A_2b_go`, `A_2c_hint`, `A_4_race_done`, `A_4b_wall_points`) |
| party-look-*.jpg (the party look, three palettes) | nine of the shots above per palette, sheets of `show_frames.gd` shots `r1_midrace`, `r1_obstacles`, `r3_climb`, `b19_flight`, `b19_gauntlet`, `t15_arena`, `p17_doors`, `m18_drop`, `t15_layers`; the third palette is the tidewheat sample with `brand.colors` `#2fb85a`, `#ff5fa8` and the name MINTO (not committed) |

Copy a sample into the clone's `demo/cast/` first (`cp -R samples/tidewheat/. demo/cast/`). Each run is under 30 s.

## Brand A (acme) against brand B (tidewheat), per round

| Round | Acme | Tidewheat | What to look at |
|---|---|---|---|
| R1 RACE, the start gate (shut for the 2-1) and the arch over it | ![](01-r1-gate-acme.jpg) | ![](02-r1-gate-tidewheat.jpg) | the gate wears the logo, the team name and the accent colour (slot `gate`: `logo`, `team_name`, `brand_colors`); the arch beam, the floor decal under the players, the player shirts |
| R1 RACE, the obstacle boxes | ![](03-r1-obstacles-acme.jpg) | ![](04-r1-obstacles-tidewheat.jpg) | `obstacle_2` (sliding walls) and `obstacle_3` (spinner bars): the picture repeats along a long wall instead of stretching; the sign, banner and goal arch beyond |
| R2 SURVIVAL, LAST TILE STANDING at the start | ![](05-r2-tiles-acme.jpg) | ![](06-r2-tiles-tidewheat.jpg) | three couriers on the three logo hexagons at the middle of the top floor (`logo`), the hexagons in three tones of the brand colours (`brand_colors`), the five rival hexagons wearing `obstacle_1..5` (the hexagon crops the picture, red rim), the two floors below, `arch_start`, `banner_1/2`, `billboard_1/2` |
| R3 FINAL, the summit: the crown over the hero prop | ![](07-r3-crown-acme.jpg) | ![](08-r3-crown-tidewheat.jpg) | acme: the built-in gold crown with the logo plate over its coin stack (`hero_prop.glb`); tidewheat: its own `crown.glb` over its cake; the two half-size copies of the prop by the podium behind, `billboard_2`, no GOAL pad or logo card (frames 46-51: the prop close up) |

## The lobby and the phone

| Frame | |
|---|---|
| ![](09-lobby-tidewheat.jpg) | 09: the lobby circle THE SHOW with its signboard (tagline `team.tagline`), the logo wall, the players' lamps in their colours (`players[i].color`) |
| ![](10-phone-lobby-844x390.jpg) | 10: a phone (844 x 390) on the circle: the touch layout with WALK, JUMP, GRAB and the PLAY button, "TAP PLAY TO START". Two local players share the screen in this harness; a real phone is one full view |
| ![](11-phone-race-844x390.jpg) | 11: the same phone in the race: the round, the timer, the scoreboard rows in the players' colours (`players[i].name`, `color`), the obstacle pictures |

## Banners, spectating, podium (six players: elimination)

| Frame | |
|---|---|
| ![](12-banner-qualified-6p.jpg) | 12: QUALIFIED in the cast's word (`show.words.qualified` = FRESH BAKED!) with the player's catchphrase under it; the six names on the scoreboard in their colours |
| ![](13-banner-eliminated-6p.jpg) | 13: ELIMINATED in the cast's word (STALE) with that player's catchphrase; the player stays where it fell and spectates the leader |
| ![](14-spectator.jpg) | 14: the spectator view in round 2: the eliminated players grey on the board, `SPECTATING  ·  BRAM`, the camera follows the leader |
| ![](15-podium-tidewheat.jpg) | 15: the podium with the custom `crown.glb` over the winner, `billboard_2` behind it, and the hero prop (the cake) at half size on both sides |
| ![](16-podium-acme.jpg) | 16: the same podium with the built-in crown (acme has no `crown.glb`), the logo billboard behind it and acme's coin stack on both sides |

## The rounds of levels 17-20

| Frame | |
|---|---|
| ![](17-poster-bonk-acme.jpg) ![](18-poster-bonk-tidewheat.jpg) | 17, 18: POSTER RUSH (level 17), both brands: five doors in a row, each wearing an obstacle picture and label. The courier on the left stands IN an open door (the board is a decor board: there is nothing to stop it), the one on the right is pressed against a solid door (a hidden block 0.25 m behind the board). Nothing tells the two apart from the front |
| ![](19-poster20-doors-tidewheat.jpg) | 19: the second POSTER RUSH hall (level 20): wider doors, other picture order |
| ![](20-bounce-pads-acme.jpg) ![](21-bounce-pads-tidewheat.jpg) | 20, 21: BOUNCE HOUSE: the first push pad (orange), a landing slab wearing `obstacle_2`'s picture (tidewheat: the cream picture tinted by the obstacle's colour), the first swinging cubes and the banner over the hall |
| ![](22-bounce-gauntlet-acme.jpg) ![](23-bounce-gauntlet-tidewheat.jpg) | 22, 23: BOUNCE HOUSE's last stretch: seven bumpers between a swinging cube head and the goal arch |
| ![](24-match-grid-acme.jpg) ![](25-match-grid-tidewheat.jpg) | 24, 25: PICTURE MATCH at 7 s (the first cue is on): 25 tiles, five pictures. The four small tiles at the top are the finale's crumbling quarters. The START pad is not drawn on a survival level |
| ![](26-match-drop-tidewheat.jpg) | 26: 1 s after the drop: only the eight tiles of the cued picture are left (RUNAWAY DOUGH); the rest of the floor comes back 2.5 s after the drop |
| ![](27-match-finale-tidewheat.jpg) | 27: clock 52 s: the last tiles are crumbling, three of the four quarters are left |
| ![](28-card-title-acme.jpg) | 28: the round card: the level's title on the accent (the cast's `brand_colors`) with the rule line under it, then the 2-1 and GO small and high up (frames 58, 59) |
| ![](29-match-cue-tidewheat.jpg) ![](30-phone-match-cue-844x390.jpg) | 29, 30: the cue card of PICTURE MATCH (the obstacle's picture and label, 3 s to go) on a laptop and on a phone, with the live counter `STANDING 4 · 2 GO THROUGH` in the chip |
| ![](31-wall-race-tidewheat.jpg) ![](32-wall-points-acme-844x390.jpg) | 31, 32: the face wall after a race, six players (tick and the cast's QUALIFIED word, cross and STALE; no photos in tidewheat, so the player's colour and initial) and, on a phone in a points show, the team photos with the placings |

## LAST TILE STANDING (level 15)

| Frame | |
|---|---|
| ![](33-tiles-layers-acme.jpg) ![](34-tiles-layers-tidewheat.jpg) | 33, 34: three floors of hexagons over the kill volume (clock 14 s): the middle of the top floor and of the second are already gone, the runners' trails are holes, one hexagon (pink) is shaking, a courier stands on the second floor |
| ![](35-tiles-trail-acme.jpg) ![](36-tiles-trail-tidewheat.jpg) | 35, 36: two runners' footsteps on the top floor: the hexagons behind them are gone for good (you see the floor below through the hole), the hexagon just stepped on shakes and goes pink, logo hexagons (the logo on a cream plate) outlast the plain ones |
| ![](37-tiles-fall-acme.jpg) ![](38-tiles-fall-tidewheat.jpg) | 37, 38: a courier falling through the hole to the next floor, a hexagon tumbling away, the underside of the top floor above (the bevel and the sides of the prisms) |
| ![](39-phone-tiles-tidewheat-844x390.jpg) ![](40-phone-tiles-acme-844x390.jpg) | 39, 40: the same round on a phone (844 x 390, 12 s in): the first-person view with the walker's trail missing ahead, a logo tile and a rival tile wearing a picture |

## The hero prop (the stand under the crown, level 16, `docs/hero-prop.md`)

Made from each brand's colours and logo by a Blender script (`tools/cast_models/hero_prop_cake.py`, `hero_prop_coin_stack.py`; `--background` only, nothing
AI-generated), 1024 px wide. `show_frames.gd` with custom shots on the project clone: `46`-`47` and `50`-`51` `--shot=approach:15:12,31.8,-33.5:12,32.6,-42:0`,
`48`-`49` `--shot=climb:15:7.5,32.4,-35:12,32.0,-41.5:0:12,31.0,-40.0;12.9,32.0,-41.1;12,30,-37.2` (couriers posed on the tiers).

| Frame | |
|---|---|
| ![](46-hero-cake-tidewheat.jpg) ![](47-hero-coins-acme.jpg) | 46, 47: the summit from the path at a player's eye height: tidewheat's three-tier cake (brand colours bottom to top, icing and pearls, the logo on a plaque) and acme's stack of three coins (reeded edges, gold rims, the logo on a plaque), the crown floating over each; nothing marks the goal but the prop itself |
| ![](48-hero-climb-tidewheat.jpg) ![](49-hero-climb-acme.jpg) | 48, 49: players on the tiers (1 m steps: a jump each; walking in is blocked at the foot), the two small copies by the podium behind |
| ![](50-hero-fallback-tidewheat.jpg) ![](51-hero-fallback-acme.jpg) | 50, 51: without a `hero_prop.glb` the game builds the stepped stand in `brand.colors` (bottom to top) with a cream rim on each tier and the logo on a plaque |

## The party look (levels 14-20 and the lobby)

One sheet per palette, each with four rows: the facility look (a white-tile hall, grey ceiling, concrete and a blue
floor) from a wide view and from player height, then the party look (`docs/backdrop.md`, "The party look") from the same two cameras. Columns:
levels 14 to 20. `samples/acme` (orange), `samples/tidewheat` (teal and violet) and a made-up green and pink cast (a temporary copy of acme with
`brand.colors` `#2fb85a`, `#ff5fa8`): nothing but `brand.colors` differs between the three. Made with `tools/modes/show_frames.gd` custom shots
(`--shot=<name>:<level>:<eye>:<look at>:<clock>[:<couriers>]`, `--look=facility` for the facility look).

| Palette | |
|---|---|
| ![](party-look-acme.jpg) | acme |
| ![](party-look-tidewheat.jpg) | tidewheat |
| ![](party-look-greenpink.jpg) | green and pink |

Characters wear their own looks (`docs/slots.md`, `players[i].look`); the cast colour is the trim of the shirt (collar and cuffs, visible
on the characters in 14 and 15), the lamps on the lobby sign and the scoreboard rows.

## Logos without boxes, the lobby wall, the shirt, banners (`tools/cast_prep.py`, `demo/lobby_visuals.gd`)

| Frame | |
|---|---|
| ![](41-lobby-wall-acme.jpg) ![](42-lobby-wall-tidewheat.jpg) | 41, 42: the lobby's north wall (`show_frames.gd` view `lobby_wall_n`): the logo once on the logo wall (no box behind it: a logo with an opaque background is keyed out by the cast prep), the easel and the poster with other pictures of the cast (acme: its print and `posters[]`; tidewheat: `billboard_1/2`, in frames of their own shape), the bunting above the frames, one frame each |
| ![](43-shirt-acme.jpg) ![](44-shirt-tidewheat.jpg) | 43, 44: the Team shirt (view `shirt`): the logo on the chest and the team name in capitals under it |
| ![](45-banner-strip-tidewheat.jpg) | 45: R3's `banner_1` (a strip with plain bands above and below in the file): the bands are trimmed and the cloth hangs just as tall as the strip (view `r3_banner`) |

Frames 01-06 and 09 show the keyed logo (no beige square on the gate plate, the arch, the tiles and the lobby wall); the
obstacle boxes of 03/04 show their picture whole.
Other brand close-ups in `show_frames.gd`: `t15_logotile`, `t15_rivals` (LAST TILE STANDING), `r3_crown_plate` (the plate on the built-in crown), `r3_cakebox` (an obstacle box).

## Third person, the bonk, the dash, the calm HUD

| Frame | |
|---|---|
| ![](52-third-person-acme.jpg) ![](53-third-person-tidewheat.jpg) | 52, 53: the show's camera over the shoulder in every show level, at the middle of each route: CIRCUIT BREAKER, LAST TILE STANDING (on the hexagons), CROWN CLIMB (twice: the first stairs and the summit), POSTER RUSH, PICTURE MATCH, BOUNCE HOUSE, the second POSTER RUSH hall. The player's own character stays in view; in the narrow halls the arm is pulled in by the wall (`tools/third_person_check.gd` checks 2500 spots of the routes for a camera inside a wall) |
| ![](54-hammer-bonk-acme.jpg) ![](55-hammer-bonk-tidewheat.jpg) | 54, 55: a hammer of CIRCUIT BREAKER has just thrown the courier: in the air and sideways, 15 m/s, dust where the head hit (the hammer pivots hang from a gantry, the heads are plain with a thin accent trim, never red edges) |
| ![](56-dash-acme.jpg) ![](57-dash-tidewheat.jpg) | 56, 57: Shift (pad B / right bumper / the DASH button on a phone) at 11 m/s for 0.3 s with a puff trail in the player's colour; the hint bar says `Shift dash` for the first 7 s of round 1 |
| ![](58-hud-sequence-acme.jpg) ![](59-hud-sequence-tidewheat.jpg) | 58, 59: the calm HUD in order (left to right, top to bottom): the card (the level's title and the rule line), the 2, GO with the key hint, the banner (the placing and the catchphrase), the face wall alone with the player's own cell ringed. One thing at a time |
| ![](party-look-acme.jpg) ![](party-look-tidewheat.jpg) ![](party-look-greenpink.jpg) | the party look in three palettes (acme, tidewheat, a made-up green and pink): a saturated track against a sky of its own colour, white clouds, bright candy hexagons and obstacles that stand out; no white haze (`docs/backdrop.md`) |

## Survival starts, the lift, bunting, the podium, the poster cards

Rendered offscreen on project clones with the real flow or `show_frames.gd` shots (`s60_match_start`, `s61_tiles_start`, `s62_lift_section`, the `p17_*` poster shots, `--tp`
for the shoulder view, `show_check.gd -- --only=A|B --cast=real` for the podium); acme and tidewheat, same code.

| Frame | |
|---|---|
| ![](60-survival-start-acme.jpg) ![](60-survival-start-tidewheat.jpg) | 60: PICTURE MATCH at the start: no start deck and no goal pad; everybody stands on the tiles (the pad under the start ring is a blink that falls at 6 s) |
| ![](61-survival-start-tiles-acme.jpg) ![](61-survival-start-tiles-tidewheat.jpg) | 61: LAST TILE STANDING at the start: no ring of ground around the hexagons |
| ![](62-lift-section-acme.jpg) ![](62-lift-section-tidewheat.jpg) | 62: CROWN CLIMB, a courier riding `lift_1` to the top and one walking on to the landing: the kill volume stays clear of the lift |
| ![](63-survival-third-person-acme.jpg) ![](63-survival-third-person-tidewheat.jpg) | 63: the player's own camera at the PICTURE MATCH start |
| ![](64-stairs-acme.jpg) ![](64-stairs-tidewheat.jpg) | 64: the CROWN CLIMB stairs: no pennants on risers or ledges |
| ![](65-bunting-high-acme.jpg) ![](65-bunting-high-tidewheat.jpg) | 65: the lobby and a poster hall: the bunting stays on the high edges |
| ![](66-podium-solo-acme.jpg) ![](66-podium-solo-tidewheat.jpg) | 66: the podium for one player (the solo app): the winner on top, facing the camera, centred, locked on the spot |
| ![](67-podium-2p-acme.jpg) ![](67-podium-2p-tidewheat.jpg) | 67: the podium for two players (also 15 and 16) |
| ![](68-podium-6p-acme.jpg) ![](68-podium-6p-tidewheat.jpg) | 68: the podium for six players: the top three on the spots, the others spectate the same camera |
| ![](70-poster-card-acme.jpg) ![](70-poster-card-tidewheat.jpg) | 70: the POSTER RUSH card: the title, the goal line `TEAR THROUGH THE POSTERS · SOME ARE WALLS`, the round chip |
| ![](71-poster-hint-acme.jpg) ![](71-poster-hint-tidewheat.jpg) | 71: the first seconds of play: `RUN THROUGH THE POSTERS THAT TEAR` under the GO |
| ![](72-poster-burst-acme.jpg) ![](72-poster-burst-tidewheat.jpg) | 72: a courier tearing through an open poster: paper in the poster colours, the bare doorway frame |
| ![](73-poster-bonk-acme.jpg) ![](73-poster-bonk-tidewheat.jpg) | 73 (also 17 and 18): a solid poster: the courier is pushed back, the board wobbles; the tutorial row's torn poster stands open on the left |
| ![](74-card-final-acme.jpg) ![](74-card-survival-tidewheat.jpg) ![](75-poster-torn-acme.jpg) ![](76-card-phone-acme.jpg) ![](77-card-solo-acme.jpg) | 74-77: the final's and the survival's card lines, the torn tutorial poster, a card on a phone (844 x 390) and in the solo app |
| ![](80-bounce-pit-before-tidewheat.jpg) ![](81-bounce-pit-ropes-tidewheat.jpg) | 80, 81: BOUNCE HOUSE's pit without and with the rope fence that stops a dash chain from skipping the pad (`docs/party-show.md`, "Dash exploit audit") |

The round card (title, goal line and a small chip for three seconds, then the digit 1 and GO) is in 70 and 74-77; the card in frames 28, 58
and 59 does not match it.

## The dash flop option, the hex map, SPIN BARS, SHOVE RING, ROLLING ROAD, KEEP THE LOGO, a circle per round

Rendered offscreen on project clones (acme and tidewheat, same code). Tools: 90-91 `show_bot_check.gd -- --solo --show-level=14 --dash-at=3 --flop-shots` (the shoulder camera over a free side view);
92-93 and 97 `show_frames.gd` shots `t15_big`, `t15_bigplay`, `t15_phone`, `s*` of levels 21-23; 94-96 `show_frames.gd` shots `sb_*`, the SHOVE RING shots and `show_bot_check.gd --frames`;
100-101, 107-108 `show_frames.gd -- --only=lobby` (`lobby_rounds_low`, `lobby_rounds`, `lobby_cam_spawn`, `lobby_cam_show`); 109 `show_frames.gd` shot `t15_arena`; 102-103 and 110 `show_bot_check.gd -- --solo [--pick=r21] --size=844x390 --touch --frames=<dir> --stop=1` (`lobby_ready`, `card_survival`); 104-106 `show_check.gd -- --only=D --cast=real --shots=<dir>`
(the real online flow with six players: the card, a round under way, the moment a real GRAB took a logo).

| Frame | |
|---|---|
| ![](90-dash-flop-acme.jpg) ![](90-dash-flop-tidewheat.jpg) | 90: the belly flop after a dash (the `dash_flop` option): flat on the belly, head up, arms ahead, 0.2 m over the floor, sliding (shoulder camera above, a free side view below) |
| ![](91-dash-getup-acme.jpg) ![](91-dash-getup-tidewheat.jpg) | 91: the get-up (the last 0.3 s): leaning forward and rising, toes still on the floor |
| ![](92-hex-big-acme.jpg) ![](92-hex-big-tidewheat.jpg) | 92: LAST TILE STANDING, 327 hexagons on three floors (127, 127, 73), ten couriers on the start ring |
| ![](93-hex-play-acme.jpg) ![](93-hex-play-tidewheat.jpg) ![](93-hex-phone-tidewheat.jpg) | 93: a round under way on the big floors (six runners leave trails of fallen tiles, two couriers fall), and the same on a phone (844 x 390) |
| ![](94-spin-bars-acme.jpg) ![](94-spin-bars-tidewheat.jpg) | 94: SPIN BARS from above: the stepped round floor, the two bars wearing obstacle pictures, six couriers on it |
| ![](95-spin-bars-bonk-acme.jpg) ![](95-spin-bars-bonk-tidewheat.jpg) ![](95-spin-bars-card-tidewheat.jpg) ![](95-spin-bars-phone-tidewheat.jpg) | 95: a courier thrown by a bar (posed in the air), the round card, the card on a phone |
| ![](96-shove-ring-acme.jpg) ![](96-shove-ring-tidewheat.jpg) ![](96-shove-ring-shrunk-acme.jpg) ![](96-shove-ring-shrunk-tidewheat.jpg) | 96: SHOVE RING with all four terraces, and after the outer ring dropped |
| ![](97-rolling-road-acme.jpg) ![](97-rolling-road-tidewheat.jpg) ![](97-rolling-road-cannons-tidewheat.jpg) ![](97-rolling-road-garages-tidewheat.jpg) ![](97-rolling-road-phone-tidewheat.jpg) | 97: ROLLING ROAD: balls rolling at the runner, the cannons, the side garages, a phone frame |
| ![](100-lobby-rounds-acme.jpg) ![](100-lobby-rounds-tidewheat.jpg) | 100: the lobby with a circle per round (a lineup longer than the eight rounds of `lineup.json`), from a low free camera: a front row of six round circles and a rear row of five in the gaps, THE SHOW's circle in the middle of the rear row with the highest board; every board over the head of the player on its circle, the banners in the brand's colours |
| ![](101-lobby-rows-acme.jpg) ![](101-lobby-rows-tidewheat.jpg) | 101: the same from the yard's middle (where the players come in) |
| ![](107-lobby-spawn-acme.jpg) ![](107-lobby-spawn-tidewheat.jpg) | 107: the lobby as the shoulder camera sees it from the spawn seats (`show_frames.gd` view `lobby_cam_spawn`: 5.3 m behind, 3.4 m up, pitched down 13 degrees): all eleven boards read, no lamp, string or player over a rule line (a confetti flake in the air can pass in front: it falls) |
| ![](108-lobby-on-circle-acme.jpg) ![](108-lobby-on-circle-tidewheat.jpg) | 108: standing on THE SHOW's circle (`lobby_cam_show`): the player seen between two front boards, THE SHOW's board high above it |
| ![](109-hex-brand-acme.jpg) ![](109-hex-brand-tidewheat.jpg) | 109: LAST TILE STANDING's hexagons in three tones of the first brand colour (acme: amber and orange, tidewheat: teal), not the hop-block tones of other hues |
| ![](102-lobby-pick-phone-tidewheat.jpg) ![](103-pick-card-phone-tidewheat.jpg) ![](110-lobby-phone-tidewheat.jpg) | 102: a phone (844 x 390), standing on SPIN BARS (a rear circle): `SPIN BARS: TAP PLAY TO START`, the PLAY button, its board above the player, KEEP THE LOGO's board reading `NEEDS 2+ PLAYERS` in a show for one; 103: the card of that one round (no `ROUND n`); 110: the same standing on THE SHOW's circle |
| ![](104-keep-logo-card-acme.jpg) ![](104-keep-logo-card-tidewheat.jpg) | 104: KEEP THE LOGO's card (six players: 2 logos): the plates already turn over two heads |
| ![](105-keep-logo-play-acme.jpg) ![](105-keep-logo-play-tidewheat.jpg) | 105: play: the plates over the wearers' heads and on their backs, the hint under the timer |
| ![](106-keep-logo-steal-acme.jpg) ![](106-keep-logo-steal-tidewheat.jpg) | 106: a real GRAB took a logo (`YOU TOOK A LOGO`, the grabbed courier is lifted); the plate has moved |
| ![](111-cannon-shot-tidewheat.jpg) | 111: a ROLLING ROAD cannon ball after the shot: it leaves a mortar tube with a flash and a puff, arcs, lands, bounces and rolls on to a slot in the far wall (it never vanishes where it touches the floor) |
| ![](112-blink-platform-dropped-tidewheat.jpg) | 112: a blinking platform of CIRCUIT BREAKER while it is gone: it has dropped out of reach and hangs below the deck (nothing vanishes; it climbs back and is solid again on time) |
| ![](113-picture-match-tiles-falling-tidewheat.jpg) | 113: PICTURE MATCH after a cue: the tiles that do not match tumble away under the floor |
