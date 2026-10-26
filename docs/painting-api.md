# Painting, shards, follow camera, game audio (`demo/game/`)

All four modules are ours. The authority builds no visuals:
`painting.gd` and `painting_shards.gd` are SHARED scripts and run on the authority (they preload `style/carry_item.gd`, which is in
the shared `style` directory, for the item data; the authority never builds meshes). `follow_camera.gd` and `game_audio.gd` are
client-only (`game_audio.gd` loads `client/settings.gd` for the music bus).

Hosted export: the domain graph is computed from the entry scenes (`tools/build_domain_graph.py`): shared `game/painting.gd`,
`game/painting_shards.gd`, `assets/paintings/painting_items.json` (also in the authority include filter); client `game/follow_camera.gd`,
`game/game_audio.gd`, `assets/paintings/painting_atlas.png`. `tools/painting_check.gd` is a dev check, never shipped.

Collision layers used: 8 = hit blocks and hazards (break the painting), 256 = camera blockers (follow camera), 1024 = painting blocker.

## `game/painting.gd` — `extends Node3D`

Painting local frame: x = along the carry axis (from anchor A towards anchor B), y = across, z = face normal (up at roll 0).
No physics body. Pose and break are computed, nothing is simulated.

    const SIZE := Vector3(3.25, 1.25, 0.05)         # along, across, thickness
    const BREAK_SIZE := Vector3(3.25, 1.25, 0.1)    # break box
    const BREAK_GRACE := 2.0   # s after reset without breaks
    const BREAK_LAYER := 8
    const BLOCKER_LAYER := 1024
    const GRIP_ALONG := 1.5    # hands on the short end bars (carriers 3.5 m apart: 0.25 m in front of each anchor)
    const GRIP_ACROSS := 0.25  # 0.5 m between the hands
    const GRIP_LIFT := 0.1     # above the plane (anchor = feet + 1.0 m)
    const ROLL_SPEED := 2.0943951   # rad/s (120 deg/s)
    const ROLL_LIMIT := 1.3962634   # rad (80 deg)
    const HEIGHT_SPEED := 2.25      # m/s
    const HEIGHT_LIMIT := 0.5       # m

    var role: String            # "authority" | "local" | "replica"
    var anchor_a: Vector3       # world; slot 0's anchor
    var anchor_b: Vector3       # world; slot 1's anchor
    var roll: float             # rad, painting turns around the axis a->b
    var height: float           # m, offset of the whole painting
    var broken: bool
    var hit_name: String        # name of the body that broke it, or the tag of break_with()
    var age: float              # s since reset(), advanced by step()

    func configure(new_role: String) -> void              # once, after add_child; builds the visual unless "authority"
    func step(dt: float) -> void                          # age += dt; pose from anchors/roll/height; break-box query after BREAK_GRACE
    func reset(a: Vector3, b: Vector3) -> void            # fresh: roll 0, height 0, age 0, intact, pose placed at once
    func break_with(tag: String, min_age := -1.0) -> void # kill volumes / grip loss; min_age -1 = BREAK_GRACE, 0 = immediately
    func roll_input(axis: float, dt: float) -> void       # axis -1..1, clamps to +-ROLL_LIMIT
    func height_input(axis: float, dt: float) -> void     # axis -1..1, clamps to +-HEIGHT_LIMIT
    func desired_transform() -> Transform3D
    func grip_points(slot: int) -> Array                  # [left_world, right_world] of the carrier in `slot` (0 = A end, 1 = B end)
    static func grips_for(pose: Transform3D, slot: int) -> Array
    static func pose_for(a: Vector3, b: Vector3, roll_angle: float, height_offset: float) -> Transform3D
    func set_intact_visible(on: bool) -> void             # hide the intact look when it breaks (shards take over)
    func set_carry_item() -> void                         # order handover: swap to CarryItem.active() with a small pop
    func make_blocker() -> AnimatableBody3D               # child, layer 1024, mask 0; an upright box along the carry axis (SIZE.x shortened by a capsule diameter, 4 m tall, 0.6 m wide); idempotent
    func set_blocker_enabled(on: bool) -> void

Notes:
* A replica (no authority) does not need `step` for the break: set `global_transform`, `broken`, `hit_name` from the snapshot and call
  `set_intact_visible(not broken)`. `step` also works there (it only reads the anchors).
* `step` after a break keeps the broken pose (it does not follow the anchors any more); `reset` starts over.
* Grips: both carriers face the painting; slot 0's left hand is on the +y side, slot 1's on the -y side. Anchor = the courier point
  the axis passes through (hip height between the hands). Roll turns the grips with the painting.
* The break rule is a shape query of `BREAK_SIZE` on layer 8 only (physics bodies; no Areas). Kill zones are the level world's
  geometric `zone_at` tests and call `break_with("kill")` (default grace) or `break_with("grip", 1.0)`.

## `game/painting_shards.gd` — `extends Node3D`

The break: the painting's own 30 pieces (frame bars and corners, torn canvas, glass shards; from `assets/paintings/painting_items.json`)
fly outward under gravity, bounce twice, settle flat and shrink away after ~18 s; torn canvas scraps and paint flecks
(`CarryItem.build_flecks`) fly with them. Every position and rotation is a pure function of (seed, age), so replicas replay the
burst from the state below. One burst at a time (a new burst replaces the old one).

    func configure(simulate: bool, authority: bool) -> void
        # simulate: draw the pieces on this peer (false = authority server: only the clock and the state)
        # authority: this peer owns the age clock and the state (local, authority); false = replica, age follows apply_state
    func burst(painting_transform: Transform3D, seed: int, floor_y := NAN) -> void
        # floor_y NaN: a ray from the painting downwards (layers 1 and 16), else 0.9 m below the painting
    func advance(dt: float) -> void       # also called from _process while `auto_advance` (default true)
    func reset() -> void                  # no burst
    func capture_state() -> Array         # [] or [seed, age, floor_y, qx, qy, qz, qw, px, py, pz, item_index]
    func apply_state(state: Array, weight: float) -> void
        # [] clears; a new seed starts that burst at the state's age; same seed re-syncs the age when it differs by > 0.25 s
    var active: bool
    var auto_advance := true
    var age: float

## `game/follow_camera.gd` — `extends RefCounted`, one instance per view

    const ARM_LENGTH := 8.0
    const ARM_MAX := 16.0                    # wheel zoom and framed views stop here
    const PITCH_DEFAULT := -45.0             # degrees, negative looks down: the view at a round or seat start (from behind and above)
    const PITCH_LOW := -75.0                 # the look input tilts it between these two: always top-down, never along the floor
    const PITCH_HIGH := -15.0
    const CAMERA_LAYER := 256               # physics layer of camera blockers (level world marks large static blocks)
    static func configure_projection(camera: Camera3D) -> void    # vertical fov 60, keep height, near 0.1
    func configure(camera: Camera3D) -> void                      # bind the view's camera (calls configure_projection)
    func update(dt: float, focus: Vector3, yaw: float, pitch: float, targets = null, options := {}) -> void
        # focus: the world point the camera orbits (courier chest); yaw/pitch: control rotation in rad
        # targets: Vector3 | PackedVector3Array | Array of points to keep in view (the partner, the painting)
        # options: {arm: float, mask: int, frame: bool (arm grows with the spread of the targets and frame_points, up to ARM_MAX),
        #           frame_points: points that only widen the frame (teammates), ahead: float (look-ahead along the yaw, default
        #           LOOK_AHEAD 2 m: the courier sits low in the picture, more of the way ahead shows)}
        #           shoulder: float (m the view centre moves to the courier's right), rise: float (m up); the shoulder view fills in SHOULDER)
    var shoulder_view := false                       # set_shoulder_view(on): the show's over-the-shoulder view (modes.json `camera: third`)
    func set_shoulder_view(on: bool) -> void
        # SHOULDER_ARM 5.4 m behind, the view centre 1.35 m over the courier's chest and 0.8 m to its right (the body stands low on the
        # left, the way ahead fills the screen), pitch SHOULDER_PITCH_LOW .. SHOULDER_PITCH_HIGH (-65 .. -3 deg, default -13); no targets
        # are kept in view; a camera blocker between the courier and the view centre pulls the centre in, and the arm is cast from there
        # as always, so a wall behind or at the shoulder never puts the camera behind it
    func look(yaw: float, pitch: float) -> Vector2   # applies queued look input: returns the new (yaw, pitch), wrapped / clamped
    func clamp_pitch(pitch: float) -> float          # first person FP_PITCH_LOW .. FP_PITCH_HIGH (-60 .. 35 deg), third PITCH_LOW .. PITCH_HIGH
    func default_pitch() -> float                    # first person FP_PITCH_DEFAULT (-12 deg), third PITCH_DEFAULT (radians)
    var first_person := true                         # the default view; set_first_person(on) switches and rebinds the own body
    func update_first_person(dt: float, feet: Vector3, yaw: float, pitch: float) -> void
        # the eye EYE_HEIGHT (1.6 m) over the feet and EYE_FORWARD (0.18 m) ahead along the yaw, fov FP_FOV (72); the own head
        # (meshes named head, eye, hair, hat, ...) is never drawn in its own view, the body, arms and hands are
    func queue_look(screen_delta: Vector2) -> void   # mouse, pixels
    func queue_touch_look(design_delta: Vector2) -> void
    func discard_look() -> void
    func reset_lag() -> void
    func apply_settings(values: Dictionary) -> void  # {XSensitivity, YSensitivity, InvertX, InvertY}
    func zoom(steps: float) -> void                  # wheel: arm_length +-0.7 m per step, 3.5 .. 16 m
    func own_body(rig: Node3D, slot: int) -> void    # this view's courier: hidden while the camera is closer than 0.9 m (back at 1.2 m)
    func clear_bodies() -> void
    var control_yaw: float                           # yaw used by the last update (movement is relative to it)
    var arm_length := ARM_LENGTH
    var sensitivity: Vector2, inverted: Vector2

## `game/game_audio.gd` — `extends Node`

Sound files: `audio/sfx/` (`mix.json` is the contract, `sfx-atlas.wav#start+frames` regions, `events` one-shots with variants,
`loops` hazard hums, `music` the title, yard and results tracks), `audio/music/`. Besides the calls below the node watches its run
(the parent) every frame on every client role and plays grabs, throws, escapes, slaps, shoves, respawns, zaps and burns, hazards
(fire, spikes, crushers, sweepers; laser, ball and lift loops), walk-in pads, the countdown and GO, level start, goal, the painting's
wobble near a hit block, the wardrobe, and switches the music per phase (title, yard, round: the cast's id, results: the end sting).

    const MUSIC_BUS := "GW_Music"
    const SFX_BUS := "GW_Effects"                              # every effect, the UI cues, the menu pet
    const VOICE_BUS := "GW_Voice"                          # announcer lines, catchphrase clips
    signal played(event: Dictionary)
    var playback_enabled := true
    func configure(listener: Node3D) -> void               # distance gain is measured to this node (the camera)
    func bind_courier(seat: int, rig: Node3D, local: bool) -> void
        # rig signals: footstep(side) -> step at the rig (all peers), jumped -> own jump sound (local seat only),
        # landed(speed) -> a landing take scaled by speed (speed > 3); steps take the surface under the feet (metal, ice, floor)
    func play_break(at: Vector3, age := 0.0) -> void       # CarryItem.break_sound_id(); skipped when `age` is past its length
    func play_jump() -> void
    func play_death() / play_push() / play_bounce() / play_easter() / play_checkpoint() -> void   # 2D
    func observe(counts: Dictionary, epoch: int) -> void
        # counts = {death, push, bounce, easter}: monotonic counters from the snapshot; the first call after a reset is a baseline
    func reset_baseline() -> void
    func blink_warn(id: int, at: Vector3) -> void          # long crack sound of a blinking block
    func blink_gone(id: int, at: Vector3) -> void          # stops the crack, plays the short break
    func stop_hazard(id: int) -> void
    static func load_mix() -> Dictionary
    static func break_entry(id: String) -> Dictionary
    static func load_wave(path: String) -> AudioStreamWAV  # whole file or atlas region
    static func attenuation(distance: float, radius := 0.32, falloff := 12.0) -> float
    static func break_gain(distance: float) -> float
    static func install_music(tree: SceneTree) -> AudioStreamPlayer   # one player on the root (title track first), idempotent
    static func music_stream(path: String, loop := true) -> AudioStream  # a PCM16 WAV or Ogg Vorbis music file
    static func music_probe(tree: SceneTree) -> Dictionary   # also "track": the path playing
    func play_event(id: String, at: Variant = null, gain_scale := 1.0, semitones := 0.0) -> bool   # mix.json "events"
    func play_pop() / play_slap(at) / play_grab(at) / play_throw(at) / play_escape(at) -> void
    func play_scorch(kind: String, at: Variant = null) -> void   # "zap" | "burn"
    func play_prop(event: Dictionary) -> void              # a yard prop event of players/prop_sim.gd: pick, throw, knock
    static func ensure_buses() -> void                     # GW_Music, GW_Effects, GW_Voice under Master
    static func event_entry(id: String) -> Dictionary
    static func event_stream(id: String) / ui_stream(cue) / pet_stream(cue) -> AudioStream   # a random variant
    static func stream_for(resource: String) -> AudioStream   # Ogg Vorbis, whole WAV or atlas region, cached
    static func music_path(context: String) -> String      # "menu" | "lobby" | "results" | "game" (the cast's music id)
    static func set_music(tree: SceneTree, context: String) -> void   # fades over to that track

## Carry item (`style/carry_item.gd`)

`CarryItem.active()` is always `landscape`, `portrait` or `glass` (default landscape, `TeamCast.object_kind()`); `set_active(name)`, `item()`, `break_sound_id()`
(`glass_break` for the pane, `break_painting` for a painting), `etched_picture()` / `pane_material()` (the pane, `style/glass_pane.gdshader`),
`build_intact()`, `build_flecks`, `animate_flecks`. The data is in `assets/paintings/` (`painting_items.json`, `painting_atlas.png`),
generated by `tools/build_painting_items.py` / `tools/make_painting_atlas.py`.
