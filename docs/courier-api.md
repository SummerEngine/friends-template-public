# Courier module (`demo/courier/`)

Own movement, own skeleton, own animation. No external model, clip or physics data.
All files are plain scripts, no `class_name`; use `preload("res://courier/<file>.gd")`.

| File | Class | Runs on |
|---|---|---|
| `courier_motion.gd` | `RefCounted` movement for one `CharacterBody3D` | owner client, local game, (authority never simulates) |
| `courier_rig.gd` | `Node3D`, the drawn courier (skeleton + meshes + animation) | clients only, never the authority |
| `courier_anchor.gd` | `RefCounted`, rigless stand-in | authority |

Shared constants live in `courier_motion.gd`: `CAPSULE_RADIUS 0.35`, `CAPSULE_HEIGHT 1.8`, tuning values (rounded designer values):
`WALK_SPEED 5`, `ACCEL 15`, `BRAKE 20`, `FRICTION 8`, `GRAVITY 17`, `JUMP_SPEED 7`, `COYOTE 0.25`, `JUMP_BUFFER 0.15`, `AIR_CONTROL 0.75`,
`FALL_BRAKE 15`, `MAX_FALL 40`, `FLOOR_MAX_ANGLE_DEG 55`, `MAX_STEP 0.45`, `PULL_DISTANCE 5`, `PULL_STRENGTH 0.8`, `TERMINAL`.

## courier_motion.gd

```gdscript
const Motion := preload("res://courier/courier_motion.gd")

static func make_body(body_name: String) -> CharacterBody3D
    # capsule r 0.35 / h 1.8, shape centre 0.9 above the body origin (origin = feet),
    # collision_layer 2, collision_mask 1 | 16, floor_max_angle 55 deg, snap 0.3, no engine platform carry.
func setup(body: CharacterBody3D) -> void           # applies the same settings to a body you built yourself; step() calls it once
func step(body: CharacterBody3D, input: Dictionary, dt: float) -> Dictionary
func capture(body: CharacterBody3D = null) -> Dictionary    # motion state (+ transform/velocity when body given); plain data, deterministic
func restore(d: Dictionary, body: CharacterBody3D) -> void  # puts motion state AND body transform/velocity back
func reset(body: CharacterBody3D, pos: Vector3, facing_yaw: float) -> void  # spawn / epoch reset: teleport + facing + all motion state cleared
func teleport(body: CharacterBody3D, pos: Vector3) -> void  # world position, velocity 0, clears launch/platform/coyote; keeps yaw
func launch(v: Vector3, override_xy: bool, override_z: bool) -> void  # queued, consumed by the next step (adds or replaces components)
func set_surface(d: Dictionary) -> void             # {} = normal ground (and no belt); {"ice": true} = slippery preset; or any of friction/braking/air_control; a non-empty one leaves the belt alone
func set_belt(v: Vector2) -> void                  # a conveyor belt under the feet: planar m/s (world x, z) the ground itself moves at; a grounded courier is carried at it (docs/level-format.md "Conveyor belts"); captured / restored
func set_stage(on: bool) -> void                    # a tile stage round: the walk, jump, air and dash use STAGE_FEEL (15 m/s run, 3.9 m jump) and the body is solid for other couriers (layer 2 in its mask); false restores both
func reset_clock() -> void                          # clears coyote/buffer (after checkpoint resets)
var grounded: bool            # read-only: standing on walkable ground after the last step
var acceleration: Vector3     # read-only: commanded world acceleration of the last step (direction * ACCEL, zero without input)
var yaw: float                # read-only: facing, radians (forward = -Z at yaw 0, atan2(-x, -z))
var floor_normal: Vector3     # read-only: Vector3.ZERO in the air
var platform: Node3D          # read-only: mover currently carrying the courier, or null
```

`input` keys (all optional): `move: Vector2` (world XZ, length <= 1), `jump: bool` (rising edge of this tick, one action),
`toward: Vector3` (partner world position; enables the pull), `partner_velocity: Vector3` (pull only applies while this courier is not faster than the partner; absent = pull),
`holding: bool` (faces `toward` while carrying instead of the move direction), `dash: bool` (a dash press of this tick: see below).

`step()` returns events of this tick: `{"jumped": bool, "landed": bool, "land_speed": float, "left_ground": bool, "stepped": bool, "started_moving": bool, "dashed": bool, "flopped": bool, "wall_stun": bool}`.

Dash (`dash` input, `DASH_*` constants): a press (kept `DASH_BUFFER` 0.12 s) starts a lunge when `dash_cooldown` is 0 and, in the air, none was used this
airtime (landing gives it back). It runs `DASH_TIME` 0.3 s along the move input (the facing without input) at `DASH_SPEED` 11 m/s (2.2 x the walk), faces that way,
ignores friction and takes off a little (`DASH_HOP` 1.8 m/s from the ground, `DASH_LIFT` 3.2 m/s in the air) with `DASH_GRAVITY` 0.25 of the gravity while it lasts: a low arc of
about 3.3 m plus the braking carry. `DASH_COOLDOWN` 1.5 s counts from its start and is shared by the ground dash and the air dash (so one dash per 1.5 s at most; the show's HUD
shows it, `game/dash_meter.gd`). The air dash is the courier's air control burst: one per airtime (landing gives it back), at any point of a jump or a fall, along the stick. A launch pad or
bumper ends it. `dash_left` and `dash_cooldown` are readable; it is the owner's own physics like walking, so the owner pose carries it (velocity 11 m/s, 0.2 m per 60 Hz pose, well inside the
authority's step limit). **A dash costs only the cooldown.** The flop penalty is the option `dash_flop` (`set_dash_flop(on)`, modes.json `dash_flop`, `Modes.dash_flop()`; off for every mode that
does not turn it on, and off for the show): with it on, the first time the courier is grounded again after a dash it flops on its belly for `FLOP_TIME` 1.15 s (`FLOP_GETUP` 0.3 s of it
getting up): `flop_left` > 0, move input, jump (and its buffer), a new dash (and its buffer) and the facing are ignored, the carried planar speed is cut to `FLOP_SPEED` 4 m/s and braked at
`FLOP_BRAKE` 10 m/s^2 (a 0.8 m belly slide; event `flopped`), and a dash that runs head-on into a wall or an obstacle (a vertical slide normal opposing the dash, `WALL_HEAD_ON` 0.7, the
dash speed collapsing) ends at once and stuns `WALL_STUN` 1.8 s with a push back of `WALL_PUSH` 2.5 m/s (event `wall_stun`; a glancing wall only slides). With the option off (the default)
neither happens: the dash that meets a wall just ends there and the courier keeps its control, no `flopped` or `wall_stun` event, `flop_left` stays 0. A launch (pad, bumper, bonk) and
`teleport`/`reset` end any flop; `capture`/`restore` carry `flop_left` and the pending flop. The owner pose carries `flop_left` as the int `flop` (1/100 s, `network/owner_pose_wire.gd`, version 2;
always 0 without the option); the rig lies down from `state.flop` (seconds left). The game switches the dash on per mode (modes.json `dash`, game_run.gd `dash_enabled`) and the penalty with
`dash_flop` (game_run.gd and `network/owner_courier.gd` hand it to the motion every step; `tools/dash_penalty_check.gd`): the shell keeps the press edges (`GameInput` `dashes`) and the phone's
DASH button taps Shift.

Behaviour: ground velocity turns towards the input and accelerates up to `WALK_SPEED * |move|` (min analog speed 0.2), brakes without input or when too fast,
friction value from the surface; air control `AIR_CONTROL` (doubled below 0.25 m/s); gravity, jump with coyote + buffer; walkable slope 55 deg; steps up to 0.45 m;
moving platforms (collision layer 16 `AnimatableBody3D`/any body whose transform moves) carry the courier by the transform delta of the mover under the feet, jumping off keeps the
mover velocity; pull towards the partner beyond 5 m.

## courier_rig.gd

```gdscript
extends Node3D
signal footstep(side: int)      # 0 = left foot, 1 = right foot, emitted at the moment the foot plants (grounded, moving)
signal jumped
signal landed(speed: float)     # downward speed (m/s, positive) at touchdown
const ANCHOR_OFFSET := Vector3(0.0, 1.0, 0.0)
const PALETTE: Array            # 8 team colours (Color); index = seat / palette index
func setup(seat: int, style_cfg: Dictionary = {}) -> void
    # style_cfg: hat "cap"|"hardhat"|"beanie"|"none" (default "cap"), mat Callable(kind: String, seat: int, tint: Color) -> Material (optional override)
func update(dt: float, state: Dictionary, grips: Array = []) -> void
    # state = {velocity: Vector3 (optional in replica mode: derived from the node's movement), grounded: bool, yaw: float, carrying: bool,
    #          paused: bool, speed01: float (optional), acceleration: Vector3 (optional), floor_normal: Vector3 (optional), look_at: Vector3 (optional partner point),
    #          flop: float (optional, seconds of dash flop left: the body lies on its belly, rises over the last 0.3 s)}
    # A fast airborne courier (over 7 m/s planar, not carrying) pitches forward about 63 degrees with its arms ahead (the dive).
    # grips = [] or [left_world, right_world] (hands reach these when carrying)
func set_replica(on: bool) -> void       # replica: velocity/acceleration are derived from the node's own movement when state has none
func set_slot_tint(palette_index: int) -> void   # shirt + cap colour (PALETTE[index])
func anchor() -> Vector3                 # global_position + ANCHOR_OFFSET (same constant the authority uses; independent of the pose)
func hands_center() -> Vector3           # real midpoint of the two drawn hands (world)
func hand_world(side: int) -> Vector3    # world position of the glove centre, 0 left, 1 right
func snap(state: Dictionary) -> void     # teleport the pose to `state` without animating (respawn, first frame)
func skeleton() -> Skeleton3D
static func warm_up() -> void            # builds the shared meshes once (call while loading)
```

The rig turns itself: it sets its own global rotation to the smoothed `state.yaw`; the caller only moves its global position to the body position (feet).
`anchor()` is `global_position + ANCHOR_OFFSET`, exactly what `courier_anchor.gd` computes from an owner pose, so replica and authority paintings agree.
Hands reach `grips`; without grips while carrying they rest 0.4 m in front of the anchor, 0.25 m apart (`hands_center()` shows the real point).
Painting grips should sit on the painting edge about 0.4 m in front of the anchor towards the partner, 0.5 m apart, to be reachable (arm reach from shoulder 0.57 m).

## courier_anchor.gd

```gdscript
extends RefCounted
const ANCHOR_OFFSET := Vector3(0.0, 1.0, 0.0)   # same value as the rig
func setup(body: CharacterBody3D) -> void
func set_pose(position: Vector3) -> bool        # owner pose position (feet); false and ignored when not finite
func set_anchor(anchor: Vector3) -> bool        # when the wire carries the anchor itself
func anchor() -> Vector3                        # last accepted anchor, else body position + ANCHOR_OFFSET
func clear() -> void
```

## Audio and presentation hooks

* `footstep(side)` fires when a foot plants (grounded, gait active); play the step sound at the rig position.
* `jumped` fires on the first airborne tick with upward speed (use `step()["jumped"]` for the owner's own jump sound if wanted earlier).
* `landed(speed)` fires at touchdown with the fall speed; scale a landing thud with it.
* `CourierMotion.step()` events `jumped / landed / land_speed / left_ground / stepped / started_moving` are the simulation-side equivalents (owner only).
* `look_at` (state, optional world point): the head and the upper body turn up to about 1 rad towards it while the feet keep the movement heading.
* `floor_normal` (state, optional): the feet settle on the slope; pass `CourierMotion.floor_normal` (it is zero in the air).

## Dev check

`tools/courier_check.gd` (`--mode=motion|rig|frames`, see its header). Frames go to
`/tmp/courier-frames/`.
