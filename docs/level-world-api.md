# LevelWorld API (`demo/levels/`)

Plain scripts, no `class_name`: `preload("res://levels/level_world.gd")`. File format: `docs/level-format.md`.

| File | Content |
|---|---|
| `level_world.gd` | `Node3D`, all levels, clock, queries |
| `level_data.gd` | `RefCounted` static: file probing, JSON -> typed data |
| `hazards.gd` | `RefCounted` static: hazard kinds as pure functions of the clock, block geometry tests |
| `level_environment.gd` | `RefCounted` static: ink sky, ambient, fog, sun for client roles |
| `style/backdrop.gd` | client: the world around and far below each level (`docs/backdrop.md`: the open-air party look in the show mode, else the facility room, the comic world in dev runs); built on first `set_active_level`, hides the flat void plane |
| `style/collision_look.gd` | client look: `draw_level`, `mark_level`, `void_plane`, `edges`, `draw_shapes` (lobby) |

## level_world.gd

```gdscript
extends Node3D
signal level_changed(level: int)                 # 0-based, -1 = none
signal blink_warned(index: int, position: Vector3) ; signal blink_vanished(index: int, position: Vector3)
const SPACING := 300.0                           # level k (0-based) sits at x = k * 300
var role: String ; var level_dir := "res://levels" ; var clock: float ; var active_level := -1

func build(role: String, slicer = null)          # COROUTINE; call after add_child. "authority": bodies only. Any other role also builds
                                                 #   WorldEnvironment + LevelSun (children of this node's PARENT), the void plane, the ink pass, the drawn look
func level_count() -> int                        # files present (level_01.json .. up to the first missing number)
func set_active_level(k: int)                    # only that level is in the tree (drawn + simulated); -1 = nothing of any level (lobby)
func set_clock(t) / advance(dt) / correct_clock(authority_t) / sync_clock(authority_t, dt)
func start_pose(k) -> {a: Vector3, b: Vector3, yaw: float}   # world, feet; yaw RADIANS (courier convention, 0 faces -Z)
func goal_volume(k) -> {p: Vector3 centre, size: Vector3, yaw: float (rad), floor: Vector3}
func zone_at(k, feet: Vector3) -> "goal" | "kill" | ""
func effects_at(k, who: int, feet: Vector3) -> {} | {v: Vector3, override_xy: bool, override_z: bool, id: int, kind: "push"|"bumper"}
func apply_effects(k, who: int, body: CharacterBody3D, motion: CourierMotion) -> {}  # ice + ONE launch (push/bumper, else a bonk, else a bump bar, else a solid poster door's push-back), fed to motion; kind "push"|"bumper"|"bonk"
func bonk_at(k, who: int, body: CharacterBody3D, platform: Node = null) -> {} | {v, override_xy, override_z, id, kind: "bonk"}   # a moving `hit` hazard touching the courier throws it
func bump_at(k, who: int, body: CharacterBody3D) -> {} | {v, override_xy, override_z, id, kind: "bumper", hazard: "bar", at}   # a courier touching a `bump` bar of a turning floor (docs/level-format.md "spin"): bounced away from the bar's plane; part of apply_effects after a bonk
func door_nudge(k, body: CharacterBody3D)   # a gate door (solid `lift`, no `hit`, tone door) closing on the courier moves it out of its volume, horizontally, at most 0.25 m a tick, no velocity, no effect returned; part of apply_effects
func door_push(k, who: int, feet: Vector3) -> {} | {v, override_xy, override_z, id, kind: "bonk", hazard: "door", at}   # a courier first pressing on a solid poster door's block (docs/level-format.md "Poster doors"); part of apply_effects; a door that rides a slide hazard is where the level clock puts it (`PosterDoors.travel(door, clock)`), doors farther than 4 m are skipped
func observe_doors(k, who: int, feet: Vector3)   # every rendered frame, every courier (the show view): signals door_burst / door_bonk and the drawn look's tear and shudder (moving doors: the travel at each sample's clock); client only
func surface_at(k, feet: Vector3) -> {} | {"ice": true, "belt": Vector2}   # either key or both (a belt over an ice block); belt = level-local planar m/s
func floor_y(k, feet: Vector3) -> float          # highest static surface under feet (probe starts 3 m above feet), NAN if none (movers not counted)
func route(k) -> PackedVector3Array              # path waypoints, world
func title(k) / blurb(k) -> String ; level_origin(k) -> Vector3 ; level_at(world_x) -> int ; reset_effects()
func show_kind(k) -> String                      # "race" | "survival" | "final" | "" (not a show level)
func podium_spots(k) -> Array                    # Vector3 per place (1st, 2nd, 3rd), world feet; [] when the level lists none
func route_progress(k, feet: Vector3) -> float   # metres along the densified route to the point nearest feet (0 at the start)
func route_length(k) -> float                    # total length of the densified route in metres
func checkpoint_spot(k, index: int) -> Vector3   # floor under checkpoint `index` (world), like team_start's spot; the start spot when out of range
func item_boxes(k) -> PackedVector3Array          # world feet spots of the level's item boxes (the `item_boxes` rows unrolled, docs/level-format.md "Item boxes"); [] for none
func tile_count(k) -> int                        # step tiles of the level (docs/level-format.md "Step tiles"); 0 when it has none
func tile_start(k, players: int) -> PackedByteArray   # a round's start state: a byte per tile, 0 standing, 255 never there (the level's `fit`)
func set_tile_steps(k, steps: PackedByteArray, quiet := false)   # the state of every tile (a byte each: 1..254 = stood on at clock byte * 0.25 s); a wrong size is ignored; quiet = no sounds, no signals
func tile_gone(k, index: int) -> bool            # is that tile gone (no collision, no look) at the world's clock
func tiles_under(k, feet: Vector3) -> Array      # indices of the standing tiles under a courier's feet (world), [] when none
func ghost_tiles(k, camera_y: float, feet_y: float) -> void   # client look: the floors over a camera at that height are not drawn (StepTiles.ghost_floors); INF draws all
signal tile_warned(index, position) / tile_vanished(index, position)   # a tile starts to shake / is gone
signal door_burst(index, position, heading) / door_bonk(index, position, who)   # a courier went through an open poster door / pressed on a solid one (index = the slot's place in the level's `slots`)
```

* `k` is always the 0-based level index. All positions are world positions; `feet` = the courier body origin (CharacterBody3D origin = feet).
  Zone and launch tests use the courier centre (feet + 0.9 m).
* **Clock**. The authority and a local run call `advance(dt)` once per physics tick (BEFORE the couriers step, so carried couriers follow the movers) and
  `set_clock(0)` at the start of a level epoch. A replica also calls `advance(dt)` every tick and `correct_clock(snapshot.hazard_t)` for each new
  snapshot: the gap is worked off at 4 per second, a gap above 0.5 s is jumped. `sync_clock(t, dt)` does both in one call for a replica that
  has no snapshot cadence of its own (do not combine it with `advance`). `clock` is what goes into the snapshot as `hazard_t`.
* **Kill / goal**: `zone_at` for each courier each tick. Kill: painting breaks, the courier respawns at `start_pose`. Goal: the shell decides
  who must be inside (either courier with an intact painting is the plan).
* **Launch pads**: `effects_at(k, seat, feet)` once per tick of the owner's simulation. It answers only on the tick the courier ENTERS a pad volume or its
  capsule first touches a bumper's drawn ball (band included, `_bumper_touched`; per seat memory), `{}` otherwise. Feed `v`, `override_xy`, `override_z` into
  `CourierMotion.launch(v, override_xy, override_z)`. `set_active_level` and `reset_effects()` clear the memory.
* **Bonk**: `apply_effects(k, seat, body, motion)` is the one call per tick of the owner's simulation (it does ice, pads and bumpers through `effects_at`, then
  `bonk_at`: a physics query of the courier's capsule against the `hit` movers, thrown the way the hazard point moves, from the level clock alone, so every
  machine computes the same throw; the mover the courier stands on is `motion.platform` and never bonks it). See docs/level-format.md "The bonk".
* **Ice and belts**: `surface_at(k, feet)` -> `CourierMotion.set_surface({"ice": true} or {})` and `set_belt(result.belt)` every tick inside `apply_effects` ({} = normal ground). Blocks with
  `"m": "belt"` have shape meta `"belt"` (a `Vector2`, level-local m/s) for the look (docs/level-format.md "Conveyor belts").
* Layers: movers `AnimatableBody3D` on 16 (+8 `hit`); static blocks `StaticBody3D` on 1 (+8 `hit`), and static blocks whose longest side is >= 1.5 m
  also on 256 (the follow camera's pull-in layer); launch volumes have no collision. Bodies of a hidden level are not in the tree. The authority builds no meshes.
* **Sound events** (clients): `blink_warned(index, world_pos)` when a blink block starts to shiver, `blink_vanished(index, world_pos)` when it stops being solid and starts to fall away (`index` =
  the hazard's index in its level; not emitted for jumps: build, set_clock, set_active_level). Pads: `effects_at(...)` carries `kind` "push" | "bumper" so the shell
  can raise the push / bounce counter. Death and goal come from `zone_at`.
* Hosted build: the level files `levels/level_NN.json` must be exported as non-resource files; `level_count()` probes `res://levels/level_NN.json`.
* **Show queries**: `show_kind`, `podium_spots`, `route_progress`, `route_length`, `checkpoint_spot` (all world coordinates, `k` 0-based) answer
  for the party show (`docs/level-format.md` "Show levels"). `route_progress` projects onto the nearest segment of `LevelData.densify(path)` (a point every 2 m),
  so it is the course's distance, not the straight line. Collision shapes of blocks and hazard parts that carry a `slot` (obstacle boxes) have shape meta
  `"slot"` (String, `obstacle_1`..`obstacle_5`), like the metas `ice` and `hazard`, so the look can find them.

## collision_look.gd (client)

`draw_level(level_root, route_world, slicer)` (coroutine; level_root in the tree): draws every `CollisionShape3D` below it from its own shape: all static
shapes of a level merge into one mesh with rounded edges and the facility surfaces (`style/real_look.gd`, `style/surfaces.gd`; bodies with meta `hazard` as
movers, shapes with meta `ice` in the ice surface, contact shadows from the level's height field); `mark_level(level_root, start, goal_floor, lateral, goal := true, arch_under := INF)`
(`arch_under`: the height of an arch's beam underside over the goal floor, `SlotFrames.goal_arch_under`; the GOAL word and logo card keep clear of it);
`void_plane(parent)`; `edges(world)` (only the comic look draws an ink pass); `draw_shapes(shapes, hazard)` (the lobby yard). The comic look
(`style/ink_look.gd`) is reachable in dev runs with `--look=comic`.

## Lobby (client + authority)

`lobby_space.gd`: `LobbySpace.ensure(world: Node3D, role: String) -> Node3D` (builds the yard under `world` once), `LobbySpace.sync(world, role, in_lobby: bool)` (switches the
yard on/off). `role == "authority"` builds bodies only. The slab and the walls are also on the camera layer (256), so the follow camera stops on the yard floor.
The yard is lit like the levels; only the comic look (dev runs) has `lobby_environment.gd` swap the world's `WorldEnvironment` sky while the lobby is on
(it finds the `WorldEnvironment` / `DirectionalLight3D` children of `world` that LevelWorld added). `client/friends_title_camera.gd`: `configure(camera, a, b, ahead)`.

## course_section.gd

Keeps `ADVENTURE`, `CHALLENGE`, `COURSES`, `CARRY`, `BALLOON`, `SHOW`, `valid()`, `default_course()`, `orders()` (the two lobby circles: TIME ATTACK / ENDLESS), `has_levels()`, `level_count()`,
`level_title(k)`, `plan(course, level, play_mode)` -> `{course, level, time_limit, hazards, play_mode}` (`play_mode` may be `"show"`; the level index passes through),
`show_levels(kind) -> Array` (0-based levels whose `show` is `kind`, in file order; they carry `"pool": false`, so `pool_levels(mode)` never offers them to Time Attack, Endless or a balloon run).
Level data comes from `LevelData` (the same files as LevelWorld; `show`, `podium` are parsed there, a block's `slot` by `Hazards.block`).
