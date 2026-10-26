# Slots: how a team makes the game theirs (`team-cast-v2`, spec)

Everyone gets the same game. A team changes only **slots**: named places that take a word, a colour, a choice from a closed list or a
picture. A picture never goes on level geometry or on a character; it goes only into frames we place: signs, posters, prints and the
declared slots of a level (obstacle boxes that carry a slot id, banners, billboards, arches, floor decals, the crown),
so every team's game keeps the template's art style.

The cast is still one file, `demo/cast/cast.json`, plus files with fixed names next to it in `demo/cast/`. `format` becomes
`"team-cast-v2"`; a `team-cast-v1` file loads too. Every slot is optional and falls back on its own: a missing or bad slot never stops
the game (`tools/cast_check.py` reports it).

## Content rules: the game is public

1. **The team must be proud to share it.** Nothing embarrassing. Personal details stay vague ("someone always says ..."). Inside jokes
   appear only as hidden eggs (`eggs`), never in visible words (team name, tagline, words, sign labels, poster captions, catchphrases).
2. **The game shows what the team does, through play.** The product is the world or the goal: sign labels name things from that world,
   the print and posters show it. It never looks like an ad: no pitch, no prices, no links, no call to action anywhere in the game.
   The one exception is the results screen: one small watermark in its bottom right corner, "Made by the <team> team" with the team's link
   (`team.credit_link`) and "Make one for your team" (half see-through type, no button frame). `tools/cast_check.py` reports links, prices and call-to-action phrases in every text field.
3. **Private stays private.** Nothing in the template phones home, counts players or lists the game anywhere; there are no analytics
   and no links the game opens by itself. A game is only seen by others when its team uploads and shares it.

## The cast

```json
{
  "format": "team-cast-v2",
  "team":    {"name": "ACME", "tagline": "Four couriers · one city · don't drop it", "credit_link": "https://acme.example"},
  "brand":   {"logo": "logo.png", "colors": ["#ff6a13", "#1d1d1f"]},
  "world":   {"theme": "office", "style": "party"},
  "object":  {"kind": "landscape", "picture": "print.png", "fit": "contain"},
  "balloon": {"shape": "balloon", "picture": "balloon.png"},
  "obstacles": [
    {"label": "BROKEN LIFT", "picture": "obstacle_1.png"},
    {"label": "RUSH HOUR"}
  ],
  "posters": [{"picture": "poster_1.png"}],
  "eggs":    ["Someone always says it's a quick one"],
  "players": [{"name": "Maja", "color": "#22aa55", "catchphrase": "On my way!", "voice": "voice/member_1.ogg"}],
  "words":   {"delivered": "ON TIME!", "break": "DAMAGED!", "fall": "WHOOPS!"},
  "music":   "careful-step",
  "video":   {"intro": "video/intro.ogv", "win": "video/win.ogv"}
}
```

| Slot | Field | Files | Shows | Fallback |
|---|---|---|---|---|
| Team name | `team.name` (1-18 letters) | | short wordmark: lobby floor word, window title, pause screen, results credit line; the title screen when there is no `team.title` | `FRIENDS` |
| Title | `team.title` (up to 40, e.g. "ACME: DON'T DROP THE PARCEL") | | big on the title screen (wraps to two lines when that makes it bigger) and over the results headline | the team name |
| Tagline | `team.tagline` (up to 60) | | caption under the title, loading screen; template line |
| Credit | `team.credit_link` (one `https://` link, up to 100) | | only on the results screen, a watermark in the bottom right corner (small white type at 45 % alpha, no button frame, no hover box): "Made by the <team> team · <link>" (a click opens the link; the cursor turns to a hand over it) and "Make one for your team" above it | no line |
| Logo | `brand.logo` | `logo.png` | the carried painting (or glass) and the balloon when they have no own picture, the lobby wall, the goal sign, slot `logo_wall`, the chest of the Team shirt (never on billboards: the game is not an ad). A JPG or PNG with an opaque, near-uniform background (white, cream, any solid colour) is keyed out by `tools/cast_prep.py` (ship.py and the build tools run it; the original stays, the result is `demo/cast/prepared/logo.png`), so it sits on plates and shirts without a box | `logo_wall`: the team name in print lettering; elsewhere the template look |
| Team shirt | (the file alone, optional) | `shirt_print.png` | the wardrobe's "Team shirt" (every player's default) is built from the cast: a white shirt, the player's colour on the sleeve ends and collar, the logo on the chest (no box behind it: `tools/cast_prep.py` keys out an opaque background) and the team name in capitals under it (dark ink, two lines from 15 letters on; the tagline is too long for a chest). With this file the picture is printed on the white shirt instead of logo and name (alpha = coverage; the trim stays) | the shirt built from logo and name |
| Brand colours | `brand.colors` (1-3 `#rrggbb`) | | the accent (first colour with colour in it, clamped so it is never washed out or muddy): goal flag, logo wall panel, obstacle signs without own colour, a painted stripe along the level and lobby walls, the lobby flags and floor lettering, the tagline strip's shadow. The first colour also paints the team-colour parts of character items (surfaces named `team_color`, such as the cap) | template palette; team-colour item parts take the player's shirt colour |
| Brand walls | `brand.walls`: `auto`, `stripe`, `accent`, `full` | | how much of each room the first brand colour paints: `stripe` a painted stripe along the walls; `accent` also the end walls, pillars, door frames and the lobby's back wall; `full` every wall. `auto` is `accent` when the first brand colour is vivid (saturation at least 0.45, value at least 0.35, chroma at least 0.3; orange paints too), else `stripe`: a black, white, grey or dull brand keeps the facility's colours and shows on the stripe, signs, logo wall and posters. The white tile stays the base | `auto` |
| World | `world.theme`: `office`, `outdoor` | | the backdrop of the comic look (dev runs only); the game's facility look does not use it | `office` |
| World style | `world.style`: `party`, `night`, `auto` | | the look of the show's world (lobby and every level): `party` a bright candy world, `night` a dark sci-fi one (near-black glossy floors with thin glowing lines in the first brand colour, a dark sky with stars and a metal sun, floating platforms, monoliths, light blades, embers); `auto` is `night` when the first brand colour is near black (HSV value under 0.30), else `party`. Only the show has it; the HUD is the same in both (`docs/backdrop.md`) | `party` |
| Carried thing (2 players) | `object.kind` (`landscape`, `portrait`, `glass`), `object.picture`, `object.fit` | `print.png` | `landscape`, `portrait`: a framed painting showing the picture as `fit` says. `glass`: a large clear pane with the picture in the middle, always whole (`fit` is ignored): a picture with transparency is an etch, its alpha is the frost (white frost for a white etch, clear glass where it is transparent, about 2 x 1 m); an opaque picture (a logo on a solid background, a photo) is printed in its colours on a frosted 2:1 panel | `landscape`; the logo, else the built-in picture (`glass`: a frosted panel with a fragile-glass mark) |
| Floating thing (3+ players) | `balloon.shape` (`balloon`, `blimp`, `ball`), `balloon.picture` | `balloon.png` | the print on the floating thing | the logo |
| Obstacles 1-5 | `obstacles[i]`: `label` (up to 16), `picture`, `color` | `obstacle_1.png` .. `obstacle_5.png` | a sign board next to the hazard at level slot `obstacle_<i>`; in the show also the faces of the obstacle boxes with that slot id (board / plate colour: `color`, else the accent, else yellow) | label only; no label = no board and no box faces |
| Posters 1-3 | `posters[i]`: `picture`, `caption` (up to 24) | `poster_1.png` .. `poster_3.png` | framed posters at slots `poster_<i>` in levels and the lobby | the cast's other pictures (billboards, banners, obstacle pictures) in that order, in levels poster 1 the logo, else no poster; the lobby never repeats the logo (it is on the logo wall) |
| Easter eggs 1-5 | `eggs[i]` (up to 60, never a person's name) | | small hidden boards at slots `egg_<i>` | none |
| Players | `players[i]`: `name`, `color`, `look`, `emote`, `catchphrase`, `voice`, `title` (up to 16, e.g. "THE FIXER") | `voice/member_<n>.ogg` (n = i + 1) | name tags, colours, a speech bubble (and the clip) over that player on events: break, fall, goal (at the goal everyone with a catchphrase, one after the other); the title small under the name tag in the lobby and next to the player's row on the results | default seat |
| Mode | `mode`: `carry` (default), `who_said_it`, `friend_swap`, `hot_potato`, `shove_off`, `show` | | the one mode the game shows (AGENTS.md, `docs/modes.md`); a minigame's own slots are in `docs/modes/<id>.md`; `show` is the party show (`show.words`, banners, billboards, crown below) | `carry` |
| Run | `run`: `time_attack` or `endless` | | the one circle the lobby shows (a game shows one mode: AGENTS.md): `time_attack` 5 levels and a total time, `endless` random levels until the players leave | `time_attack` |
| Words | `words.delivered`, `break`, `fall`, `pop`, `zap`, `burnt` (up to 16) | | the big words over the game | template words |
| Show words | `show.words.qualified`, `eliminated`, `champion`, `go` (up to 16 letters each, shown in capitals) | | the show's big lines: a player is through, a player is out, the winner, the start of a round | `QUALIFIED!`, `ELIMINATED`, `CHAMPION!`, `GO!` |
| Item lab | `show.item_lab` (true / false) | | turns the item lab on: keys 1-7 hand out the items and events (`docs/items.md`) | off |
| Items | `show.items[]`: `{id, name, banner, line, off, voice, sfx, media, tuning}` per item or event id (`smash` `call` `flip` `glitch` `dance` `boost` `soar` `eggplant`): name up to 16, banner up to 30, line up to 48 (`{user}`, `{victim}`), and for `eggplant` also `pass` up to 48 and `pop` up to 30; texts may joke about prices (the item words are exempt from the price and "subscribe" patterns; links and calls to action are still refused) | `items/<file>.ogg` (voice, sfx: Ogg Vorbis mono, up to 4 s, 300 KB), `items/<file>.ogv` (call's footage) | the item words, sounds, voice slot and tuning of the race rounds' power-ups (`docs/items.md`) | the template's generic words and sounds, no voice |
| Tandem | `show.tandem`: `{off, name, banner, line}` (the TANDEM experiment): name up to 16, banner up to 30, line up to 48 (`{a}`, `{b}`); `off: true` switches it off | | the words of the hand-holding tandem of races and the lobby yard (`docs/party-show.md` "Tandem (experiment)") | the template's neutral words (TANDEM!) |
| Manager (experiment) | `show.manager`: `{off, title, line, you, prompt, waiting, made, rules[]}`; a rule `{id, name, banner, line, off, tuning}` per id (`flip` `moon` `nojump` `giant` `tiny` `ice` `walk` `upside`) | | THE MANAGER (`docs/party-show.md` "The manager (experiment)"): one player per round makes a rule for the others; `title` and `prompt` up to 24, `line` / `you` / `waiting` / `made` up to 48 (`{manager}` is their name), a rule's `name` up to 16, `banner` up to 30, `line` up to 48, `tuning.duration` 3-30 s; `off` takes the manager (or a rule) out of the show | the template's neutral texts |
| Rounds | `show.rounds.<round id>` with `title` (up to 24), `rule`, `hint` (up to 48), `label` (a text or up to 8 of up to 16), `model` (`"round_r21.glb"` / `"round_r23.glb"`): round ids `r14` `r15` `r16` `r17` (POSTER RUSH, both levels) `r18` `r19` `r21` `r22` `r23` `r24` `r25` `r26` `r27` `r28` (the four stage rounds); `label` only on `r15`, `r17`, `r21`, `r23`, `model` only on `r21`, `r23` | `round_r21.glb`, `round_r23.glb` (glTF binary) | the round's name and goal lines (round card, lobby circle, results headline, objective hint) and the words / model on its hazard: the plain tiles of LAST TILE STANDING, the spin bars, the rolling balls, the tearing posters (`docs/swappables.md`, "Rounds as metaphors") | the level file's own title, rule and hint; the hazard's default look |
| Reveal | `words.reveal` (up to 40, e.g. "Will you marry me?", "Happy birthday, Maya") | | the surprise of a gift or proposal game: shown big (in capitals) on the results in place of the delivered word, only when the run was delivered (a finished level run, or the carried thing arrived) | none: the delivered word |
| Goal sign | (the file alone, optional) | `goal_sign.png` (`.jpg` / `.webp`), found by its name | the picture on the card over the GOAL word at the end of each level | the logo, else no card |
| Music | `music`: an id `<id>` of `demo/audio/music/friends-<id>.ogg` (or `.wav`): `careful-step`, `lofi`, `electronic`, `hiphop`, `indie`, `funk`, `epic` | | the gameplay loop | `careful-step` |
| Video | `video.intro`, `video.win` | `video/intro.ogv`, `video/win.ogv` | intro over the title once per run (before the first level), win over the results of a delivered run; any key or tap skips | skipped |
| Title backdrop | `title.pet_ground`: `[x, y]`, 0 to 1 across the picture, the point where the title pet's feet stand (a platform or floor at the lower right) | `title_backdrop.png` (`.jpg` / `.webp`), found by its name | the title screen's art, cover-scaled behind the menu with the same slow sway; the menu column covers the left 46 %, so keep that side calm | the template's drawn backdrop (a light wall with a faint grid and a floor); `title.pet_ground` `[0.885, 0.848]` (the floor's front edge) |

Player look: `players[i].look` picks that seat's character items, catalog slot -> item id from
`demo/character/catalog.json`, for example `{"head": "head_bear", "hat": "hat_cap", "eyes": "eyes_big", "shirt": "shirt_stripes", "hand": "hand_mug"}`.
No people: the show shows animal and bean heads only. A look that names a people head (`people_heads` in the catalog: `head_human*`, `head_potato`) gets the seat's animal instead (catalog `seat_heads`, cycling by seat, so the same player always gets the same animal), whether it comes from the cast, a saved look or another client, and `tools/cast_check.py` prints a `WARNING:` line for it (not an error). Slots: `head` (the animal), `hat`, `hair`, `eyes`, `brows`, `nose`, `outfit`, `shirt`, `hand`. `""` means nothing in that slot
(not for `head`). A slot left out, or an item whose art is not in the build, keeps the seat's default (the seat's animal, catalog
defaults). The head brings its own skin colour; `color` goes on the shirt. Eyes that do not fit the head are swapped for ones
that do. A player's own saved look (the wardrobe) wins over the cast. The flat fields `hat`, `eyes`, `body` belong to the
courier look (`docs/courier-api.md`).

Player emote: `players[i].emote` is one of the character's emotes: `dance`, `sit`, `yes`, `no`, `point`, `think`, `cry`
(`demo/character/catalog.json` `emotes`). That player plays it at the goal (unless still carrying) and after 6 seconds standing
still in a game, once per stop; moving ends it. No emote: the player does neither.

## Japanese and Chinese text

The game's fonts draw Latin letters (with æøå and accents). For Japanese or Chinese text anywhere in the cast (team name,
title, names, catchphrases, signs, words, the reveal line), run `python3 tools/cast_fonts.py` after writing the cast
(`tools/ship.py` runs it first). It cuts exactly the letters the cast uses out of Noto Sans JP and Noto Sans SC (SIL OFL)
into `demo/cast/fonts/` (a few KB to a few hundred KB); the game draws every letter its own fonts lack with them. Text with
kana takes Japanese letter forms, other text Chinese (simplified) ones. It needs fontTools (`pip install fonttools`) and,
the first time, a download of the two source fonts. `tools/cast_check.py` names any letter no font draws (emoji, or text
changed after the last `cast_fonts.py` run). Limits count letters, and a Japanese or Chinese letter is about twice as wide, so
keep names short (up to 6).

## Picture files

| Slot | Size (px) | Aspect | Notes |
|---|---|---|---|
| `logo.png` | 1024 x 1024 | any, fitted `contain` | transparent PNG is best |
| `print.png` | 1024 x 512 | 2:1 (landscape) or 1:2 (portrait) | on a painting `fit` decides contain or cover; on the glass always whole: an RGBA PNG whose alpha is the etch (white on transparent), or an opaque picture on a frosted panel |
| `balloon.png` | 1024 x 1024 | 1:1 | wraps the front of the floating thing |
| `goal_sign.png` | 1024 x 512 | any, fitted on a white card | a short message or picture readable from far away; transparent PNG is best |
| `shirt_print.png` | 1024 x 1024 | 1:1 | RGBA, laid out on the shirt's UV: front panel x 0.06-0.57, y 0.52-0.99; back y 0.01-0.49; sleeves x 0.62-0.98; transparent where the shirt colour shows |
| `obstacle_<i>.png` | 1024 x 512 | 2:1 | the sign face (the label is lettered under it); in the show it covers each face of the obstacle boxes of that id, cropped to the face |
| `poster_<i>.png` | 768 x 1024 | 3:4 | |
| `title_backdrop.png` | 1536 x 1024 (at least 1280 x 720) | 3:2 (landscape) | the right side stays on screen on narrow screens; a JPEG keeps it under 4 MB |
| `banner_<i>.png` | 2048 x 512 | 4:1 | `i` = 1..2, the show's hung banners, covers the cloth |
| `billboard_<i>.png` | 1536 x 864 | 16:9 | `i` = 1..2, the show's billboards, covers the board |

PNG, JPEG or WebP, at least 256 px on the short side, under 4 MB. Bigger pictures are scaled down when the game loads them. The name is
fixed, the ending may be `.png`, `.jpg`/`.jpeg` or `.webp` (`logo.webp`). Sound and video: `voice/member_<n>.ogg` is Ogg Vorbis, up to 4 s
and 1 MB; `video/<kind>.ogv` is Ogg Theora, under 16 MB.

**House style for generated pictures** (the website uses this prompt for every slot picture so they match the game): *clean modern print
graphic, flat vector shapes with soft gradients and gentle shading, bold clear colours, crisp edges, no ink outlines, no halftone, plain light
background, no lettering unless the slot asks for it, no people, no human figures, no faces or hands of people, no characters or mascots (an object, a pattern or an animal is fine), no brands except the team's own logo.* Add the team's brand colours
to the prompt. The game shows them as real prints: signs with a rolled edge, posters behind glass in thin metal frames, the logo on a
painted panel, in a bright facility with white tiled walls and blue mats.

## The team pack (optional files)

summerengine.com makes a free pack per team; the brief hands it to the agent, who copies its files into `demo/cast/` as given. Every
file is optional and found by its fixed name; a missing one is skipped. `tools/cast_check.py` reports any other name in these folders.

**The show** (`mode: show`): banner and billboard pictures, an own hero prop and an own crown model, all optional (its lines are `show.words`, in the table
above):

| Slot | Files in `demo/cast/` | Shows | Limits |
|---|---|---|---|
| Banners | `banner_1.png`, `banner_2.png` (`.jpg` / `.webp` too) | the hung banners of the show's levels; plain bands above and below a strip are trimmed and the cloth hangs just as tall as the strip | 2048 x 512 (4:1), at least 256 px on the short side, under 4 MB |
| Billboards | `billboard_1.png`, `billboard_2.png` (`.jpg` / `.webp` too) | the framed boards beside the course | 1536 x 864 (16:9), at least 256 px on the short side, under 4 MB |
| Hero prop | `hero_prop.glb` (glTF binary) | the stand the crown floats over on the final's summit (and two half-size copies at the podium), instead of the built-in stepped stand in the brand colours: the object the team makes or sells, built with a Blender script from the brand colours and the logo (`docs/hero-prop.md`) | built 4.5 m across x 3.0 m tall, origin at the bottom centre, +Y up, front +Z, three tiers of radius 2.25 / 1.5 / 0.75 m (the collision; `tools/cast_check.py` reports a part wider than its tier), under 5 MB; any other file name is reported |
| Crown | `crown.glb` (glTF binary) | the crown over the hero prop and the winner, instead of the built-in gold crown | about 0.5 m wide, origin at its base centre, +Y up (it is scaled to the crown's height), under 5 MB; any other file name is reported |
| Round models | `round_r21.glb` (the spin bars), `round_r23.glb` (the balls); the file is named in `show.rounds.<id>.model` (glTF binary) | replaces the look of that round's hazard, fitted evenly inside its collision box; collision and gameplay never change | long axis +X, origin at the centre, +Y up (`docs/swappables.md`); under 5 MB; a file the cast does not name, or any other name, is reported |
| Item files | `items/<file>.ogg`, `items/<file>.ogv`; named in `show.items[]` (`voice`, `sfx`, `media`) | the items' hit sounds and voice lines; the call window's footage | Ogg Vorbis mono up to 4 s and 300 KB; Theora under 16 MB; a file of another type is reported |

| Slot | Files in `demo/cast/` | Plays / shows | Limits |
|---|---|---|---|
| Announcer | `announcer/<event>_<n>.ogg`, n = 1..4; event `start`, `near_drop`, `break`, `pop`, `zap`, `goal`, `perfect` | a random line of the event; the music ducks under it; one line at a time (an event during a line is dropped); every client decides from what it already sees, nothing extra goes over the network | Ogg Vorbis, mono, up to 4 s, up to 300 KB each |
| Player clips | `voice/member_<n>.ogg` and up to 3 variants `voice/member_<n>_<k>.ogg`, k = 1..3 (n = seat + 1, 1..8) | a random one with that player's catchphrase bubble (break, fall, goal) | the same as the announcer |
| Intro | `video/intro.ogv` (and `video.intro` in cast.json) | over the title, once per device the first time the game opens (a local flag; a new intro file plays once again); any key, click or tap skips it | Ogg Theora, under 16 MB |
| Team wall | `team_wall`: up to 10 `{"name", "picture"}`, `team/member_<n>.png` (n = entry + 1; `.jpg`/`.webp` too) | a board in the lobby yard (and at a level's `team_wall` slot): each photo in a rounded frame with the name under it; a person without a photo shows their cast colour (the player of the same name) | names up to 16; photos square, 512 x 512 px (256 to 1024), under 1 MB; each person's own photo, uploaded by themselves (opt-in) |

The events: `start` a level starts; `near_drop` the balloon falls within 1.3 m of the floor at more than 1.5 m/s, or the painting is
tilted past 90 % of its limit (at most once every 8 s, not in the first 2.5 s of a level or after a respawn); `break` the painting
breaks (a hit or a fall); `pop` the balloon pops; `zap` a laser zaps a player (when the game has lasers); `goal` a level is cleared;
`perfect` it was cleared without a break or a pop (falls back to `goal` when the pack has no `perfect` lines).

## Level slots (where the frames are)

Levels and the lobby place the frames; the cast only fills them. A level file may list `slots` (see `docs/level-format.md`):

```
"slots": [
  {"id": "obstacle_1", "p": [x, y, z], "yaw": 0, "size": [2.0, 1.0]},
  {"id": "poster_1",   "p": [x, y, z], "yaw": 90, "size": [1.5, 2.0]}
]
```

* `id`: `obstacle_1`..`obstacle_5`, `poster_1`..`poster_3`, `logo_wall`, `egg_1`..`egg_5`, `team_wall` (about 4 x 2.25 m). The show's levels
  (`mode: show`) also use `arch_start`, `arch_finish` (about 8 x 1.5 m), `banner_1`, `banner_2` (8 x 2 m), `billboard_1`, `billboard_2`
  (5 x 2.8 m), `floor_start`, `floor_finish` (a decal on the floor, its logo on a thin dark rim so keyed-out dark edges never show the pad; `floor_finish` is centred on the GOAL pad), `hero_prop` (a stand on the floor, `docs/hero-prop.md`; may repeat) and
  `crown` (where the crown floats).
* `p`: centre of the board face, level-local, 0.25 m grid. `yaw`: degrees, 0 = the face looks towards +Z (back at the start). `size`: width
  and height of the face in metres. A floor decal's `p` is on the floor and its `size` is width x depth (it lies 6 cm over the floor and over the START / GOAL pads, so it never fights them); the crown's `p` is the centre of
  the crown and its `size.y` its height; a hero prop's `p` is the bottom centre of its footprint and its `size` the footprint and the height.
* An `obstacle_<i>` board stands next to the hazard it names, readable from the path before the players reach it.
* An **obstacle box** is a block or hazard part that carries a slot id (`"slot": "obstacle_<i>"` in the level file, no board): its faces
  show the obstacle, the picture `obstacle_<i>.png` on every side and the top, else a plate in the obstacle's colour (else the accent) with
  the label lettered on the four sides. A moving box carries its faces; collision is unchanged. A box whose obstacle the cast does not
  list looks like a normal block.
  Its picture never merges with a floor: a face is neither coplanar with a floor's face nor cut by a floor, so an obstacle box rests on a floor or
  stands clear of it, and a decor board stands on a floor and does not sink into it (`docs/level-format.md` "Pictures and floors", checked by `tools/level_lint.py` on the show levels).
* An empty slot draws nothing (no empty frame), except: arches and banners show the team name, floor decals the logo (else the team name),
  the crown is always there (the built-in one, or `crown.glb`) and so is a hero prop (`hero_prop.glb`, else the built-in stand). A billboard needs a picture or the logo.
* A board whose face has a block right behind it (0.5 m or less) is as deep as the gap, so it sits on that wall; any other board stands
  on two posts down to the floor below it. Boards have no collision.
* Arches are a beam with two legs (the beam face carries the logo plate and the team name on the accent), banners hang between two thin
  posts (picture, else the team name on the accent), billboards are framed boards on posts (picture, else the logo on the accent).
* The lobby yard's frames are fixed in `demo/lobby_visuals.gd` (`SLOTS`): `logo_wall` and `poster_1` on the north wall, `poster_2` and
  `poster_3` on the side walls, `team_wall` on the east wall. They hang with their tops at 2.6 m at most; the bunting runs above. The logo
  is on the logo wall once: the easel takes the team's print, else the first of billboard_1/2, banner_1/2 or the obstacle pictures, each
  poster its own `posters[i]` or the next of those (a picture that is not a portrait gets a frame of its own shape); nothing left, no frame.
* Obstacle boxes show their picture whole and centred: the plain margins around the content are trimmed and the rest of the face takes the
  picture's own edge colour (a long wall repeats it in 2:1 cells); a picture whose edge is not plain is cropped to the face. The team wall's look (colours, frame, lettering) is one function,
  `SlotFrames.team_wall_style()`.

## What a team cannot change

The levels and their layout, the hazards and their timing, movement, physics, the camera, networking, the lobby, the menus and the build
files. `tools/cast_check.py` fails on any change outside `demo/cast/`.
