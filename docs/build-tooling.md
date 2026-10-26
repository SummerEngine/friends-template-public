# Build tooling

Everything lives in `tools/`; outputs go to `build/` and `analysis/` (both ignored). Engine for every run: the installed Summer app
(`/Applications/Summer Engine.app/Contents/MacOS/Summer`, or `$SUMMER`), headless (`--headless --audio-driver Dummy`), optionally under the shared
slot (`FRIENDS_PRIORITY=1 tools/engine_slot.sh ...`).
A harmless `ERROR: TLS handshake error` at engine shutdown is ignored by the scripts.

| File | Purpose |
|---|---|
| `ship.py` | one command from a finished cast to a playable Web build: fonts, cast prep, cast check, clean scan, in-engine cast check, Web export, link; last line `SHIP ok=... link=...` |
| `cast_prep.py`, `cast_prep.gd` | keys the plain background out of the cast's logo, balloon and goal sign pictures into `cast/prepared/` (below); `python3 tools/cast_prep.py [--cast DIR] [--also a.png,b.jpg]` |
| `stage_hosted_export.sh <label>` | demo/ → hosted bundle `build/friends-network-<label>.summer.zip`, evidence in `analysis/staging/<label>/` |
| `prepare_network_build.py` | clone preparation: prune, import, network scenes, domain graph, presets, analyzers (never exports) |
| `build_domain_graph.py` | derives `source-domains.json`, the resource manifests and the preset filters from the entry scenes |
| `stage_build.py` | export of the prepared clone, input fence, bundle audit |
| `audit_staged_pack.py` | pack membership of client.pck and server.pck from the generated graph |
| `prune_unreferenced_graph_uids.py` | drops unreferenced code UID sidecars of the clone |
| `prepare_audio_imports.py` | keeps music and effect WAV imports lossless |
| `build_network.gd`, `check_network_build.gd` | regenerate `client/main.tscn`, `authority/main.tscn`, `network/composition.tres`; compile both entries and run the analyzer for both profiles |
| `build_levels_game.py`, `build_solo_levels.py`, `build_solo_show.py` (`app_build.py`) | standalone Mac apps |
| `clean_scan.py` | forbidden-string scan of a bundle, packs and the repository tree |
| `staged_load_check.gd`, `levels_flow_check.gd` | headless checks of a staged clone / the level game |
| `cast_models/hero_prop_*.py`, `hero_common.py`, `preview_glb.py` | Blender (`--background` only) scripts that build the sample hero props (`samples/*/hero_prop.glb`, `docs/hero-prop.md`) from brand colours and a logo, and a quick PNG preview of any .glb |
| `hero_stand_check.gd` | headless: a courier walks into and jumps up the hero prop stands of level 16 on the real collision |
| `lift_ride_check.gd` | headless, real courier physics and the REAL `ShowRules` (`_tick_course` / `_tick_survival` on a `ModeHost` without a shell, `tools/modes/fake_host.gd`): for every rising `lift` of the show levels (files 14-20) a courier rides it from its bottom with the level clock, then walks, dashes, jumps and early-jumps onto the landing the route goes to; it must be carried up, never sent back by the rules (no kill volume, no scorch) and end on static floor at the landing (respawn depends on the courier's position only: the follow camera never enters it). Also: every checkpoint's respawn spots (1 to 8 players) stand on static floor, outside kill volumes and clear of every platform that carries riders (a knocking hammer or sweeper over a spot is only reported); and on the survival levels, a ray scan at 15 s and 40 s finds no static ground, the start ring (2 to 10 players) stands on tiles at clock 0, and a courier on the spots with no ground under them (`FORMER_GROUND`) falls and is put out by the rules. `LIFT_RIDE` lines, `LIFT_RIDE ok=<bool>` last, exit 1 on failure; `-- --level=16 --variant=jump --trace` narrow it down |
| `bonk_check.gd` | headless physics check that every moving `hit` hazard kind throws a courier (a standing one and a walking one, `tools/level_testdata/bonk/level_01.json`); `--legacy` runs the launches only, with no bonk impulse, for comparison; `--trace=<lane>` prints one lane; gate doors are not `hit` and never bonk (`gate_check.gd` stands under and runs into them), a turning disc's `bump` bar is a bumper bounce (`disc_ride_check.gd`, level 31) |
| `spinner_pass_check.gd` | headless, real courier physics on the real `LevelWorld`: every cluster of hit `spin` hazards (windmills, wheels, spinner discs, bars) of levels 29-32 whose sweep touches the route must be passable by waiting and walking (a steady walk through from a window of start times of 0.6 s or more, or the careful walker that waits on safe floor from 90 % of its starts) and still fling a careless run (30 % of steady starts); `--levels=`, `--only=<ids>`, `--quick`, `--trace`; see `docs/level-format.md` (passable flings) |
| `belt_check.gd` | headless physics check of the conveyor belt (`"m": "belt"`, `tools/level_testdata/belt/level_01.json`): a courier standing on a 3 m/s belt is carried at it (x and z), walking with / against it nets walk +- belt, stepping off the end or jumping keeps the velocity, opposite belts side by side, a belt over ice, `surface_at` reach, capture / restore; `--trace=<case>` prints one case. Command in its header |
| `belt_cross_probe.gd` + `belt_jobs.py` | the belts of the race levels (29-32) on the real level collision with the real courier: `python3 tools/belt_jobs.py /tmp/belts.json` lists every belt of the level files (a belt across the course = cross, one that runs along it = lane; the course direction is the nearest `path` segment snapped to an axis), the probe plays them: a straight run across from every start offset 1 m apart (at three jump timings for the maze's steps; passes with 4 neighbouring starts), a lane run from its start (at most 15 s), a standing courier carried off a cross belt within 2 s, and the look's chevron speed equal to the block's `belt`. Command in its header; `--no-require` prints only |
| `edge_bumper_probe.gd` | headless, real courier physics on the real `LevelWorld`: the EDGE BUMPERS experiment (`demo/levels/edge_bumpers.json`, `docs/level-format.md` "Edge bumpers"), per level of the switch: the plan (candidates, share, cushions), a courier dropped on the clear middle of every bumpered platform from up to three clean headings and straight down lands and brakes without a bump, straight drops at the 4 corners of the clear middle are safe, a sloppy landing dropped on each cushion's inner flank is thrown off (or at the next stone's wall) by it; information only: the share of those bounced couriers an air dash back puts on the deck again; platforms a spinner bar sweeps are reported, not counted; `--look` checks every drawn tube and ball is exactly a hitbox; `--levels=29,30`, `--trace`. Prints `EDGE_BUMPER RESULT ok=<bool>` last. Command in its header. `race_jump_probe.gd` re-aims jumps from and onto bumpered platforms (shifted lane, middle to middle) and, for a jump no run lands, tries the air dash: it passes as `NEEDS THE AIR DASH` and is counted in `dash=` |
| `edge_bumper_frames.gd` | offscreen binary only (never windowed): pictures of the edge bumpers experiment on the real level world, courier physics and rig, one shot name per run (`--only=` approach, close, overhead, strip_centre or strip_edge; `--level=`, `--pick=<block>`, `--focus=x,z --span=<m>`); the strips are a courier dropped on the middle of a bumpered platform (lands, stays) and just inside its near cushion (bumped, thrown off), a frame every 5 ticks; `overhead` also writes a .json with the screen box of every bumpered platform and the screen line of every cushion. Command in its header |
| `camera_clear_check.gd` | offscreen binary only (never windowed): the camera clearance sweep. For every sample pose of the game's own camera (race levels 29-32: the stage view behind a courier on the route, three lateral offsets x three orbit yaws x standing / running pitch; the lobby yard: the shoulder view over a grid of spots, four yaws, arm pulled in at the walls) it renders the real scene with the far plane pulled in against a magenta background and counts the share of the screen covered by geometry NOT dissolved within 4 m of the eye (true distance, rings of equal ray length) and by depth under 8 m; fails (exit 1) when any frame covers more than `--limit` (0.20), lists every frame over `--note` (0.01), saves the worst frames with their 4 m cut (`--shots=`), `--why` names the meshes within 4 m and their material, `--filter=` re-renders one pose. Command in its header; docs/party-show.md "The stage camera and feel" |
| `third_person_check.gd` | headless: the show's shoulder camera (`modes.json` `camera: third`) at every metre of every show level's route, looking along it and 50 degrees to each side, on the real collision: no camera inside a wall, the courier in view, no wall in the camera's face (a view turned into a wall at the shoulder is pulled in by the clipped camera and is not counted); `show_frames.gd --tour=<n>` shoots the same view |
| `exploit_check.py`, `exploit_probe.gd` | the dash exploit audit of levels 14-20 (`docs/party-show.md` "Dash exploit audit"): `python3 tools/exploit_check.py [--level N] [--emit-probe /tmp/jobs.json]` (stdlib only, a Python port of `courier_motion.gd` checked against the engine to 1 %; prints `EXPLOIT_CHECK ok=<bool>` last) finds sequence breaks, out-of-play standing spots and weak barriers; the probe plays its jobs with the real courier: `FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 600 <Summer> --headless --audio-driver Dummy --rendering-driver dummy --fixed-fps 60 --path demo -s $PWD/tools/exploit_probe.gd -- --jobs=/tmp/jobs.json [--out=r.json] [--level=N] [--job=N]` (`--lobby`: the yard) |
| `party_look_check.gd`, `party_perf.gd` | the party look: palette and backdrop rules over 64 palettes (headless) / draw calls, primitives and ms per frame in the party or facility look (offscreen) |
| `lobby_frames.gd` | offscreen frames of the show's lobby yard without the show's world (a small level dir, the yard, the circles' plates and signs, one shoulder camera): `tools/engine_slot.sh timeout -k 10 600 <Summer> --summer-offscreen --path demo -s $PWD/tools/lobby_frames.gd -- --dir=$PWD/tools/level_testdata --shots=<out dir> --only=spawn,yard,overhead,show,west,east,rear_a,pick,pad_close,corner_nw,corner_se,edge,north,phone_spawn [--prefix=] [--count=]` (`phone_spawn` with `--resolution 844x390`; under the render lock) |
| `modes/stage_flow_check.gd` | a tile stage round through the real online flow with real owner couriers on three replicas: everybody holds forward through the card and nobody leaves the start tiles (an honest client, and a cheating one the authority drops and puts back), input unlocks at GO, a standing player falls to the ground floor, is out on landing and spectates; `--stage=0..3`, `--shots=<dir>` (offscreen binary) writes the victim's frames of the fall |
| `stage_levels_gen.py`, `stage_tiles_check.gd`, `stage_floors_check.gd` | the four tile stage levels (25-28: `python3 tools/stage_levels_gen.py [--check]` writes them) / their tiles, ground, instant exit, wire state and cost (headless) / the one-way floors with the real courier motion: standing, walking under an intact floor, jumping up through it, holes, the ground, a sinking tile (headless); `party_perf.gd --levels=25,26,27,28` renders them (`docs/level-format.md` "Stage rounds") |
| `mesh_lint.sh`, `mesh_lint.gd`, `mesh_lint_report.py`, `test_mesh_lint.py` | defects of the BUILT visual meshes of the stage levels (25-32), per level in level coordinates: coplanar faces (z-fighting, budget default 0), hairline gaps between parts and loose pillar / leg ends (warnings), decorative / hazard visuals crossing kit parts or each other (C4 overlaps, reported; `--overlap-budget=N` to fail, double rims (C5 `double_rim`: two parallel kit rim lines on one coplanar top, a beige line inside a deck or a rim on both sides of a joint; budget default 0, `--rim-budget=N`)); rules in the header of `mesh_lint.gd`. `tools/mesh_lint.sh [--headless] [--levels=25,...,30] [--out=f.json] [--baseline=f.json] [--budget=N] [--warn-budget=N] [--md=report.md] [--tree=DIR]` (exit 1 over a budget; a baseline counts only NEW findings): the default is the offscreen renderer (no window, under the render lock), which keeps MultiMesh data so tile floors, arena cage and skyline are linted too; `--headless` (dummy renderer, about 6 s) drops MultiMesh transforms, lists those nodes as NOT LINTED and lints the rest; `--selftest` runs synthetic known-bad and clean meshes; `--lobby [--dir=tools/level_testdata]` lints the built lobby yard (the client look, world around it, walk-in circles and signs, built like `lobby_frames.gd`; yard-local positions; City / SkyThings / NearSky / `LobbyWorld*` meshes are scope "world", Label3D is not a mesh and ignored) as the pseudo-level 99 in ONE engine process, same budgets and exit code (`--lobby --headless --dir=tools/level_testdata --overlap-budget=0 --budget=0 --warn-budget=0`); `mesh_lint_report.py` renders the JSON as Markdown / diffs two runs |
| `net_stage_check.py`, `net_stage_check.gd`, `stage_net_sim_check.gd`, `stage_hang_check.gd` | the network test of whole stage rounds: `python3 tools/net_stage_check.py [--levels 25,26,27,28] [--players 2] [--idle-after 20]` runs the engine's Local Play (`--summer-local-play N --summer-local-play-headless`: the authority from `world.json` and N headless clients over loopback) under `engine_slot.sh`; the clients' dev run walks onto the round's circle (`-- --autoplay --pick=r25`), presses PLAY and runs over the tiles (the probe `net_stage_check.gd` is loaded from `--net-probe=<path>` by `DevEnv.attach_probe`, editor binary only), the script judges the `NETSTAGE_*` lines: gone bitmaps and step-state hashes of the clients against the authority's at the same level clock, a stepped tile white then gone after 0.5 s, no tile back from gone, every state byte field <= 240 B, no error lines, the round ends by itself (`--idle-edge` parks the idle bots on a tile's edge; `--judge <log>` re-reads a log); prints `NET_STAGE ok=<bool>` last / the same rounds in one process over a simulated link: `FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 900 <Summer> --headless --audio-driver Dummy --rendering-driver dummy --fixed-fps 60 --path demo -s $PWD/tools/stage_net_sim_check.gd [-- --levels=25,26,27,28 --players=2,6 --latency=0.1 --jitter=0.03 --drop=0.05 --spike]` (the real rules and a replica `LevelWorld` fed only through the published state, a late joiner, two rounds in a row; prints `STAGE_NET_SIM ok=<bool>` last) / `stage_hang_check.gd`: a courier resting on a tile's edge (up to 0.29 m past it) counts as standing on the tile (`StepTiles.STAGE_REACH_XZ`) and falls through when it goes, square and hex stack (headless) |
| `engine_slot.sh` | machine-wide engine slots |
| `test_*.py` | unit tests: `python3 -m unittest discover -s tools -p 'test_*.py'` |

## Staging a hosted build

    SUMMER_BIN=<0.7.2 binary> tools/stage_hosted_export.sh <label>      # e.g. v0.6.0

Refuses to overwrite `analysis/staging/<label>` or the bundle. Steps:

1. `cp -cR demo` (APFS clone) into `analysis/staging/<label>/project`; `lab/` is removed (offline lab, never hosted).
2. `prepare_network_build.py --execute`: prune the clone (below), lossless audio imports, import, `build_network.gd`, graph and presets,
   import, UID pruning, final graph, `check_network_build.gd` (client and authority profile, 0 diagnostics required).
3. `stage_build.py`: hash all inputs, `--export-release summer.games`, remove exporter-made unreferenced code UIDs, audit the bundle
   (manifests, both packs present, Android pin, no visual payload in the server pack, input fence unchanged), receipts under the label.
4. `audit_staged_pack.py`: shared code and data in both packs; client files and presentation payloads only in the client pack; authority
   files only in the server pack; no probes, no test lab; every `.import`/`.remap` target inside its own pack.
5. `clean_scan.py --bundle <zip> --tree .`: any hit fails the run (the bundle stays for inspection).

`demo/client/main.tscn`, `demo/authority/main.tscn` and `demo/network/composition.tres` are generated by `build_network.gd` but kept in git:
the clone needs them before the first import. After changing `network/game.gd` run the script once on demo and commit.

## How the domain graph is derived

`build_domain_graph.py` follows `res://` references from the entries (client entry of `world.json`, component entries, network
compositions, the main scenes of `project.godot`) through scripts, scenes, resources, shaders (incl. includes), JSON and global
class names / `uid://` tokens (comments are ignored for class names, not for paths: the analyzer reads them).

* **Roles.** Reachable from an authority entry: shared (`authority/` itself is the authority row). Reachable only from client
  entries: client. A client file reaching `authority/` is an error.
* **Hard tokens** `"res://x"` must name an existing file. A directory, a missing file or a trailing `.` fails the generator with the
  referencing chain (the analyzer would report the same minutes later).
* **Soft tokens** `"res" + "://x"` are for payloads loaded at run time; the analyzer cannot see them. A file, a directory or a name prefix
  (`"res" + "://levels/level_"`, `%` formats cut at the `%`) is accepted. From authority-side code, data files (json, tres, cfg, txt,
  bin, dat) and everything in shared payload directories are shared; textures, audio and scripts are client-only. The report lists
  those as notes: check that nothing the authority needs is a note.
* **Payload directories** (whole directory = one role): shared `assets/fonts`, `assets/prop_kit`, `assets/looks`, `levels/*.json`;
  client `audio/music`, `audio/sfx`, `client/menu_art`. The authority pack leaves out client files, `audio/`, city kit, look textures and
  every png/jpg/svg/glb/gltf/wav/ogg/mp3/exr/hdr; a hard `preload` or scene dependency on such a file from authority-side code is an error.
* **Computed loads** (the analyzer's own rule: `load`/`preload`/`ResourceLoader.load` whose first argument is not a literal) get an edge to
  `assets/shared_resources.json` (client scripts also to `assets/client_resources.json`; authority files to `assets/authority_resources.json`).
* **Rows.** A directory becomes one root when every code/data file below it has the same role; otherwise its files are listed one by one.
  A row may hold 128 paths: keep roles in separate directories and the project root nearly empty. File counts of both profiles (limit
  4096) are checked too. The shared row is close to its 128, so the authority-side files of the show experiments (pigeon, manager and tandem rules, catalogs, switches), `victory_flow.gd` and `shared/event_gate.gd` (the show's one event gate) live together in `demo/modes/show/shared/` (one row path: a file inside the directory row adds no row path): put a new authority-side file of the show there, not next to its view. `demo/style/` is one row path only while EVERY file in it is reached from an authority entry: a file that only the client reaches (the lobby's ring shader is such a file) must live in a client directory (`demo/lobby/`), or the style directory splits into about 200 listed files and the shared row goes far over 128.
* **Clone pruning** (`prepare_clone`, disposable clones only): files no entry reaches (probes, dead scripts, docs, unused data) are deleted;
  city-kit models stay when a shipped script or level file names them (quoted stem, a prefix ending in `_`, or a `_suffix` part).
* **Presets.** The `summer.games` preset gets `*.json,assets/fonts/*-OFL.txt` plus `authority/*` excluded; the authority preset (named by
  `summer.build.json` → `server.exportPreset`) gets an include list of its JSON data and an exclude list of every client-role file (as
  `dir/*` where a whole directory is client-only), the visual extensions and visual directories, and the client manifests.

Dry run on a checkout (prints rows, file counts, notes, unreached files; writes nothing):

    python3 tools/build_domain_graph.py --project demo [--report r.json]

`--write` also writes `demo/source-domains.json` and the three manifests (ignored files) for a dev session; staging does that in its clone.

Rules for runtime code that follow: shared code never names client files or client payload directories with a hard token (hand them
over at run time); presentation payloads are loaded through `"res" + "://..."`; authority-side `preload`s name only code and data;
role-specific code sits in its own directory.

## Standalone Mac apps

    FRIENDS_PRIORITY=1 tools/engine_slot.sh python3 tools/build_levels_game.py --output build/levels-<new name>
    FRIENDS_PRIORITY=1 tools/engine_slot.sh python3 tools/build_solo_levels.py --output build/solo-<new name>
    FRIENDS_PRIORITY=1 tools/engine_slot.sh python3 tools/build_solo_show.py --output build/solo-show-<new name>

`FRIENDS Levels.app` (`res://main.tscn`, two players on one keyboard), `FRIENDS Solo Levels.app` (`res://lab/main.tscn`) and
`FRIENDS Show.app` (`res://show_solo.tscn`: THE SHOW for ONE player, wearing the `samples/tidewheat` cast; `--cast <dir>` wears another, and
demo/cast/ is never touched; no title, straight into the lobby yard; it opens fullscreen like every exported desktop build, see
`docs/party-show.md` "Playing alone"). They
refuse an existing output directory and never touch demo/: freeze (APFS clone) → prune to what the entry reaches → import → `--export-pack`
→ every client-visible file of the graph must be in the pack, no probes, no `authority/` → app from the installed engine's player template (the engine and the player binary are pinned by SHA-256 in `app_build.py`) →
ad-hoc signature → `--headless` boot of the exported app for 240 frames (any `SCRIPT ERROR`/`ERROR` line fails). The receipt is
`<output>/receipt.json`. Executables are `FRIENDSLevels`, `FRIENDSSoloLevels` and `FRIENDSShow`, bundle ids `com.summerengine.friends.levels` / `.sololevels` / `.show`.

## Cast prep

Creators upload JPG or PNG logos with an opaque white or solid-colour background; drawn as they are, the background shows as a square. `tools/cast_prep.py`
(engine part: `tools/cast_prep.gd`, plain `Image` code, no dependency on the project) makes a transparent copy and leaves the original alone:

    python3 tools/cast_prep.py                          # demo/cast
    python3 tools/cast_prep.py --cast <cast dir> --also mascot.png,badge.jpg

* **Which pictures:** `brand.logo` and `balloon.picture` of `cast.json`, a `goal_sign.png|.jpg|.jpeg|.webp` in the cast folder, plus `--also` (file names
  in the cast folder). Obstacle pictures, posters, banners, billboards, team photos, `shirt_print.*` and `object.picture` are never prepared.
* **When it runs:** `ship.py` runs it on `demo/cast` (step `prep`, after `fonts`, before `cast`). The build tools run it on their disposable copy,
  never on `demo/cast` or `samples/*` in place: `prepare_network_build.py --execute` (so `stage_hosted_export.sh`) on the clone's `cast/`, and
  `app_build.py` (levels, solo levels, `build_solo_show.py` with or without `--cast`) on the project clone's `cast/` after the cast is copied in. Both run
  it before the import, so the exported pack holds `cast/prepared/*`.
* **Files it writes:** `<cast dir>/prepared/<source stem>.png` for every picture it keyed, and `<cast dir>/prepared/manifest.json`:
  `{"format": "cast-prep-v1", "files": {"<source file name>": {"sha256", "result", "background", "size"}}}`. `sha256` is of the source bytes;
  `result` is `keyed` (a prepared PNG exists; `background` is `#rrggbb` and `size` is `[w, h]`), `transparent` (the picture already has a transparent
  border), `busy` (the border is not one flat colour: a photo or scene) or `empty` (keying would leave under 2% opaque pixels). Only `keyed` has a PNG.
  Same input bytes give the same output bytes; a rerun overwrites, deletes prepared files whose source is gone or no longer keyed, and removes an
  empty `prepared/` folder. `tools/cast_check.py` accepts `demo/cast/prepared/` only as the manifest plus the PNGs it names as keyed, fails when a source changed
  since the run (`run it again`) and when a prepared PNG is not a valid PNG under 4 MB.
* **How:** the border ring's median is the background colour; the tolerance is `clamp(2.5 x the 75th percentile of the ring's distances, 14, 36)`; a 4-connected flood fill
  from the ring marks the background; pixels within 4 px of it get a soft alpha (the share of the nearby picture colour they hold, un-mixed from the background,
  smoothstepped); transparent pixels next to the picture keep the picture's colour so bilinear sampling shows no light halo; the result is cropped to the picture plus
  a 4% margin when that removes more than 3% of the area. A 1024 x 1024 picture takes about two seconds. The full algorithm is the header of `cast_prep.gd`.
* **Limits:** only a background that is one flat colour along the whole border is keyed (a gradient, a photo or a scene is `busy` and left alone). Regions of the
  background colour the fill cannot reach (a white eye inside a mascot) stay opaque on purpose. A picture whose own colours are close to the background
  (within the tolerance) loses those edge pixels' softness but is not eaten. The engine runs on an empty throw-away project, so nothing outside the cast folder is written.

## Scanning

    python3 tools/clean_scan.py --bundle build/<bundle>.summer.zip --tree .
    python3 tools/clean_scan.py --pck client.pck --pck server.pck

Scans packs (scripts decompressed, entry names included) and every tracked or untracked-but-not-ignored file; exit 1 on any hit.
Engine-defined names stay legal: the shader hint, the world key naming the graph file, and the importer key in `.import` files.

## Pitfalls met

* The analyzer reads comments and JSON: any `res://` token must resolve (see above). Write run-time prefixes as `"res" + "://x"`.
* `load(CONST)` of a shader or font in shared code is a computed load; use a literal `preload` (or let the generator add the edge).
* Every file below a directory root counts toward the 4096 ceiling, `.uid` and `.import` sidecars included.
* The exporter writes `.uid` sidecars for scripts; `stage_build.py --prune-unreferenced-code-uids` removes the unreferenced ones and the input
  fence must show no other change. `.import` UIDs are copied to `.uid` owners by the generator.
* `build_network.gd` needs an imported project (the pipeline imports first); run on a never-imported clone it fails compiling the entry scripts.
* Never add a `qos` block to `demo/summer.build.json`.
