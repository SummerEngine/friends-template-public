extends Node3D
## The player character: the catalog's skinned body model with clip animations and a look (colours and items from
## demo/character/catalog.json). Same public API as the courier rig (docs/courier-api.md) plus set_look / get_look / play_emote /
## param_ids.
## Rig space: origin at the feet, +Y up, forward is -Z, the character's left side is -X. The node turns itself to the smoothed
## `state.yaw`; the caller only places its global position.
##
## The body sits in a pivot that puts its feet on the origin, turns it to face -Z and scales it to HEIGHT. The animation is an
## AnimationTree built in code and advanced by update(): idle, walk with a direction blend (forward, back, sidestep) scaled by
## speed, jump and fall, a carry layer on the arms (two-hand hold poses picked by grip height), full-body emotes and on top a
## mouth layer on the jaw: the player's voice (set_talk_level), a shout on jumps and hard landings, a scream in long falls and
## the emote's own mouth. After the clips update() adds the procedural part: the look's sliders (catalog "params": bone
## scales, the loose bones of the body following what they sit on, longer legs and necks lifting the body), lean, landing
## squash, wobble, bounce and swagger, the head turning towards `look_at` and the hands reaching the painting grips. The face
## sliders reshape the face part meshes and the hat sliders the hat when the look is set.
## First person (set_first_person): the own camera draws only the character's arms and hands, posed for the view.

signal footstep(side: int)
signal jumped
signal landed(speed: float)
signal look_applied
signal slap_hit(side: int, hand_world: Vector3) ## at the slap's fastest point (SLAP_HIT_TIME after slap()), side -1 left, +1 right

const ANCHOR_OFFSET := Vector3(0.0, 1.0, 0.0)
const TeamCast := preload("res://style/team_cast.gd") ## seat colours and the team picture (demo/cast/)
const Catalog := preload("res://character/catalog.gd")
const Look := preload("res://character/look.gd")
const SHIRT_SHADER := preload("res://character/shirt.gdshader")
const SOFT_SHADER := preload("res://character/character_soft.gdshader") ## the characters' own material: bright toy colours under any light
const Style := preload("res://style/friends_style.gd") ## the game's look: character_material(kind, color, texture) when it has one

const HEIGHT := 1.8 ## metres, top of the head (like the courier, so the anchor, capsule and camera stay right)
const WALK_CLIP_SPEED := 3.0 ## ground speed (m/s) at which the walk clip plays at its own pace
const HOLD_FORWARD := 0.40 ## carrying without grips: hands 0.4 m in front of the anchor, 0.25 m to each side
const HOLD_SIDE := 0.25
const REACH_SLACK := 0.999
## Style names of the courier's setup() -> hat items.
const HAT_STYLES := {"cap": "hat_cap", "hardhat": "hat_cap", "beanie": "hat_beanie", "none": ""}
## Bones of the body skeleton the rig drives (left, right).
const BONE_HEAD := "head"
const BONE_JAW := "ORG_jaw_lower"
const BONE_ARM := ["ORG_arm_L", "ORG_arm_R"]
const BONE_FOREARM := ["ORG_forearm_L", "ORG_forearm_R"]
const BONE_HAND := ["ORG_hand_L", "ORG_hand_R"]
const HEAD_BONE := "ORG_jaw_upper" ## the bone hats ride on (the head model's own)
const BONE_FINGER := ["ORG_finger_B_01_L", "ORG_finger_B_01_R"]
const BONE_FOOT := ["ORG_foot_L", "ORG_foot_R"]
## Hand items: the direction of a held handle relative to the hand bone (left hand; the right hand mirrors it). The item's
## origin (its grip) sits at the palm centre, the item runs along its +Y.
const HAND_GRIP := Basis(Vector3(-0.0134, 0.0779, 0.9969), Vector3(-0.5739, 0.8158, -0.0714), Vector3(-0.8188, -0.5731, 0.0338))
## The chest print area of the shirt texture (uv), where the team picture goes; with a motto (the team's name) the logo moves up and
## the motto goes under it (one or two lines), without a logo the motto sits on the chest.
const LOGO_RECT := Rect2(0.19, 0.64, 0.25, 0.25)
const LOGO_OVER_MOTTO := Rect2(0.2, 0.605, 0.23, 0.2)
const MOTTO_RECT := Rect2(0.18, 0.82, 0.27, 0.07)
const MOTTO_ALONE := Rect2(0.165, 0.68, 0.3, 0.14)
const CHEST_PIVOT := Vector2(0.315, 0.7525) ## the chest print's centre (uv): an outfit's catalog "chest" moves and scales the print around it
const MOTTO_FONT := preload("res://assets/fonts/Inter.ttf") ## the game's type
const MOTTO_INK := Color("#1c1c28") ## dark ink: readable on the white team shirt
const MOTTO_SIZE := 64 ## px the motto picture is drawn at
const MOTTO_WEIGHT := 700 ## the font's weight axis: bold, readable from the game camera
const MOTTO_SPLIT := 14 ## a motto longer than this many characters goes on two lines (a team name rarely does)
const SEPARATORS := ["·", "•", "|", "/", "-", "–", "—", ",", ";", ":"] ## a line never starts or ends with one of these (the cut leaves them off)
## The team shirt's trim (body units, the body model's own size): the sleeve ends and the collar in the player's colour.
const TRIM_SLEEVE := 0.03 ## from the sleeve's end along the arm
const TRIM_COLLAR := 0.05 ## below the shirt's top
const TRIM_RANGE := 0.25 ## the distances the shirt's vertex colours carry (0..1 = 0..TRIM_RANGE)
const BROW_SHADE := 0.45 ## brows: the skin colour darkened by this much
const STEP_DOWN := 0.015 ## foot plant: within this height (body units) of the rest height; re-armed above STEP_UP
const STEP_UP := 0.04
const EMOTE_FADE_IN := 0.15
const EMOTE_FADE_OUT := 0.25
const IDLE_EMOTE_AFTER := 6.0 ## seconds standing still before idle_emotes plays the cast's emote for this player
const JUMP_SHOUT := 0.85 ## mouth opening of the short shout on a jump; it closes over SHOUT_SECONDS
const SHOUT_SECONDS := 0.35
const HARD_LANDING := 7.0 ## m/s downward at touchdown: a landing this hard shouts too
const SCREAM_FALL_SPEED := 6.0 ## m/s downward: falling faster opens the mouth
const MOUTH_EXTRA := 0.14 ## rad: the jaw opens this much further than the open-mouth clip at full voice (cartoon)
const HAT_SOCKET := "HatSocket" ## node of a head model where hats sit
## Head surfaces (material names) the face sliders reshape when the face part is not a mesh of its own.
const HEAD_SURFACES := {"eyes": ["eyes", "pupils"], "eyelids": ["eyelids"], "brows": ["brows"], "nose": ["nose", "beak"], "mouth": ["mouth", "teeth", "tongue"], "ears": ["ears", "ear_inner"]}
## Head surfaces (material names) that take a colour slot's colour besides the surfaces named after the slot.
const SURFACE_COLORS := {"ears": "skin"}
const PUPIL_COLOR := Color("#17171C") ## pupils that come without a colour of their own on a light eyeball
const SLAP_SPEED := 1.6 ## the arm-swing clip (catalog clips "slap", a right-arm throw; the left arm plays it mirrored) runs this much faster
const SLAP_HIT_TIME := 0.1 ## s from slap() to the hand's fastest point (the hit)
const SLAP_SHOUT := 0.6 ## mouth opening on a slap (it closes over SHOUT_SECONDS)
const WOBBLE_STIFF := 90.0 ## head jiggle spring (rad/s^2 per rad) ...
const WOBBLE_DAMP := 7.0 ## ... its damping ...
const WOBBLE_KICK := 0.012 ## ... and how hard acceleration (m/s^2) and landings push it, at wobble 0
const WOBBLE_MAX := 0.35 ## rad: the most the head jiggles
const BOUNCE_HEIGHT := 0.015 ## m: extra bob of a walking step at bounce 0
const SWAGGER_ROLL := 0.025 ## rad: side sway of a walking step at swagger 0
const FP_BODY_FIRST_BIT := 18 ## first person: the character's meshes on render layer bit 18 + seat % 2, which its own camera culls ...
const FP_VIEW_FIRST_BIT := 20 ## ... and its view arms on bit 20 + seat % 2, which only its own camera draws (not in a camera's default mask)
## The dash's belly flop and dive (game/game_run.gd feeds `state.flop`, seconds left of courier_motion.gd's flop): the whole body tips forward about the hips.
const GETUP := 0.3 ## s at the end of the flop spent getting up (courier_motion.gd FLOP_GETUP)
const LIE_IN := 0.1 ## s to go down on the belly
const HIPS_Y := 0.95 ## m: the tipping point
const LIE_HEIGHT := 0.2 ## m: the body axis over the floor when lying flat
const LIE_CENTER := 0.08 ## m: the hips ahead of the capsule centre while lying (the legs reach further back than the head forward)
const DIVE_SPEED := 7.0 ## m/s of planar speed in the air that pitches the courier forward
const DIVE_PITCH := 1.1 ## rad (63 degrees)
const ARMS_AHEAD := 2.85 ## rad: the arms swing forward over the head while lying or diving

# shared by every rig of the same body (built once: warm_up)
static var _shared: Dictionary = {}
static var _item_cache: Dictionary = {}
static var _material_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {} ## face part meshes reshaped by sliders
static var _arm_mesh_cache: Dictionary = {} ## body mesh -> its arm and hand triangles (first person), null for none
## Checks only: stands in for FriendsStyle.character_material (kind, color, texture) -> Material. Clear _material_cache after.
static var style_hook := Callable()
static var _style_found: Variant = null ## Callable of FriendsStyle.character_material, or false without one

var seat := 0
var tint_index := 0
## A player in a game (game/game_run.gd): the cast's emote for this player (cast_emote) plays after IDLE_EMOTE_AFTER s standing
## still, once per stop. Off for previews and checks.
var idle_emotes := false
var _still := 0.0
var _idle_emoted := false
var _look: CharacterLook
var _own_look := false ## a player's look came through set_look (or setup's "look"): set_slot_tint leaves its colours alone
var _look_over: CharacterLook ## set_look_over: drawn in place of the player's look while set
var _look_kept: CharacterLook ## the player's look while an override is drawn
var _applied: Dictionary = {} ## slot -> item id applied to the meshes
var _built := false
var _replica := false
var _fresh := true
var _pivot: Node3D
var _body: Node3D
var _skeleton: Skeleton3D
var _tree: AnimationTree
var _meshes: Dictionary = {} ## mesh name -> MeshInstance3D of the body
var _parts: Dictionary = {} ## body part name (catalog body_parts) -> MeshInstance3D
var _part_mesh: Dictionary = {} ## slot -> the body's own mesh of that slot
var _eye_material: Material
var _extras: Dictionary = {} ## slot -> node added for an item (attach model holder or skinned mesh)
var _attachments: Dictionary = {} ## bone name -> BoneAttachment3D
var _head_anchor: Node3D ## see head_anchor()
var _layer_ref: MeshInstance3D
var _base_mesh: Dictionary = {} ## face part slot -> its mesh before the face sliders
var _eye_file := ""
var _hidden_by: Dictionary = {} ## slot -> body mesh names its item hides
var _hat_socket: Variant = null ## Transform3D of the worn head's HatSocket (body space), null for none
var _bone_scales: Dictionary = {} ## bone -> pose scale factor (bone axes) from the look's sliders
var _body_lift := 0.0 ## body units: longer legs lift everything but the feet
var _head_lift := 0.0 ## body units: a longer neck lifts the head
var _fun := {"wobble": 1.0, "bounce": 1.0, "swagger": 1.0}
var _wobble := Vector2.ZERO
var _wobble_v := Vector2.ZERO
var _walk_phase := 0.0
var _bob := 0.0
var _sway := 0.0
var _bone := {} ## role -> bone index

# animation state
var _yaw := 0.0
var _air := 0.0
var _carry := 0.0
var _lie := 0.0 ## 0..1: how far the courier is down on its belly (eases in over LIE_IN s, then follows `state.flop` out)
var _getup := 0.0 ## 1 while the flop still lies flat, falling to 0 over the last GETUP s
var _dive := 0.0 ## 0..1: the superman pitch of a fast airborne courier
var _grounded := true
var _speed := 0.0
var _walk_dir := Vector2(0.0, 1.0)
var _lean := 0.0
var _roll := 0.0
var _acc_fwd := 0.0
var _acc_side := 0.0
var _reach_lean := 0.0
var _squash := 0.0
var _squash_v := 0.0
var _vy_prev := 0.0
var _fall_peak := 0.0
var _last_pos := Vector3.ZERO
var _last_vel := Vector3.ZERO
var _foot_armed := [true, true]
var _talk := 0.0
var _talk_target := 0.0
var _shout := 0.0
var _slap_side := 0 ## -1 / +1 while a slap plays, 0 otherwise
var _slap_time := 0.0
var _emote := ""
var _emote_mouth: Array = [0.0, 0.0, 0.0] ## open, swing, hz of the emote playing (kept while it fades out)
var _emote_time := 0.0
var _emote_length := 0.0
var _emote_loop := false
var _emote_weight := 0.0
var _hold_height := 0.0
var _fp := false ## first person on (set_first_person)
var _fp_camera: Camera3D
var _fp_root: Node3D ## under the camera: the view arms, turned by the lag and moved by the bob
var _fp_skeleton: Skeleton3D ## the view arms' own copy of the body skeleton
var _fp_source: Skeleton3D ## the body skeleton the view arms were made from
var _fp_item: Node3D ## the hand item's copy in the view hand
var _fp_item_side := -1
var _fp_lagged := Basis() ## the camera orientation the view arms follow, lagging behind turns
var _fp_time := 0.0
var _fp_layers := -1 ## the character's render layers before first person (-1: not taken yet)

# ---------------------------------------------------------------- setup
## style_cfg: hat "cap" | "hardhat" | "beanie" | "none" (courier styles), look: CharacterLook or a look dictionary.
func setup(seat_index: int, style_cfg: Dictionary = {}) -> void:
	seat = seat_index
	tint_index = seat_index
	if _pivot != null:
		remove_child(_pivot)
		_pivot.queue_free()
		_pivot = null
	_meshes.clear()
	_parts.clear()
	_part_mesh.clear()
	_base_mesh.clear()
	_hat_socket = null
	_extras.clear()
	_attachments.clear()
	_head_anchor = null
	_applied.clear()
	_built = false
	_build()
	var look: CharacterLook
	var given = style_cfg.get("look")
	if given is CharacterLook: look = given
	elif given is Dictionary: look = Look.from_dict(given)
	else:
		look = Look.defaults_for_seat(seat)
		if style_cfg.has("hat"): look.items["hat"] = HAT_STYLES.get(str(style_cfg["hat"]), look.items.get("hat", ""))
	_look = null
	_own_look = given != null
	_show_look(look)
	_fresh = true

func set_replica(on: bool) -> void:
	_replica = on

## Shirt colour of the seat `palette_index` (the cast's player colour, nearest palette entry). Once set_look() has given the
## rig a player's look, that look keeps its own colours and only the index is stored.
func set_slot_tint(palette_index: int) -> void:
	tint_index = palette_index
	if _own_look: return
	var look := get_look()
	look.colors["shirt"] = Catalog.nearest("shirt", TeamCast.player_color(palette_index))
	_show_look(look)

## True when the catalog's body model is there (our art or a local stand-in). game/game_run.gd keeps the courier rig otherwise.
static func available() -> bool:
	if Catalog.body_path() == "": return false
	var shared := _shared_body()
	if not bool(shared.get("ok", false)): return false
	if bool(shared.get("has_head", false)): return true
	# a body without a head (heads are items) needs one head model (any; the default head when it is there), else the game keeps the courier
	var head := Catalog.item(Catalog.default_item("head"))
	return str(head.get("file", "")) != "" and Catalog.resolve(str(head["file"])) != ""

## The slider ids a look can set (CharacterLook.params), in catalog order.
func param_ids() -> Array:
	return Catalog.param_ids()

## Loads the body, its animation tree and the catalog once (call while loading).
static func warm_up() -> void:
	_shared_body()

func skeleton() -> Skeleton3D:
	return _skeleton

func anchor() -> Vector3:
	return global_position + ANCHOR_OFFSET

## World position of the palm centre, 0 left, 1 right.
func hand_world(side: int) -> Vector3:
	if not _built: return anchor() + global_basis * Vector3((-1.0 if side == 0 else 1.0) * HOLD_SIDE, 0.0, -HOLD_FORWARD)
	var hand := _skeleton.get_bone_global_pose(_bone["hand"][side])
	return _skeleton.global_transform * (hand * (_shared["palm"][side] as Vector3))

func hands_center() -> Vector3:
	return (hand_world(0) + hand_world(1)) * 0.5

# ---------------------------------------------------------------- shared body data
static func _shared_body() -> Dictionary:
	if not _shared.is_empty(): return _shared
	_shared["ok"] = false
	var path := Catalog.body_path()
	if path == "":
		push_warning("Character body model not found: character/models/" + str(Catalog.data().get("body", "")))
		return _shared
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("Character body model is not a scene: " + path)
		return _shared
	var probe: Node3D = scene.instantiate()
	var skeletons := probe.find_children("*", "Skeleton3D", true, false)
	var players := probe.find_children("*", "AnimationPlayer", true, false)
	if skeletons.is_empty() or players.is_empty():
		push_warning("Character body model needs a skeleton and its clips: " + path)
		probe.free()
		return _shared
	var sk: Skeleton3D = skeletons[0]
	var library: AnimationLibrary = (players[0] as AnimationPlayer).get_animation_library("")
	# size and facing from the rest pose: feet on the origin, HEIGHT tall, facing -Z
	var hidden := Catalog.body_part_names("hidden")
	var head_names := Catalog.body_part_names("head")
	var has_head := false
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in probe.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or str(mesh.name) in hidden: continue
		has_head = has_head or str(mesh.name) in head_names
		var box := _relative(mesh, probe) * mesh.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	# the character is HEIGHT tall with its head: a head in the body is measured with it; heads that are items are measured
	# with the default head's model (else the body is catalog body_height units tall)
	var units := bounds.size.y
	if not has_head:
		var top := _default_head_top()
		units = top - bounds.position.y if top > bounds.end.y else float(Catalog.data().get("body_height", bounds.size.y))
	var scale := HEIGHT / maxf(units, 0.01)
	var foot := sk.find_bone(BONE_FOOT[0])
	var faces_plus_z := true
	if foot >= 0 and not sk.get_bone_children(foot).is_empty():
		var toe := sk.get_bone_global_rest(sk.get_bone_children(foot)[0]).origin
		faces_plus_z = toe.z > sk.get_bone_global_rest(foot).origin.z
	var turn := Basis(Vector3.UP, PI) if faces_plus_z else Basis()
	_shared["pivot_basis"] = turn * Basis.from_scale(Vector3.ONE * scale)
	_shared["pivot_origin"] = Vector3(0.0, -bounds.position.y * scale, 0.0)
	_shared["scale"] = scale
	_shared["has_head"] = has_head
	# hands: palm centre in hand space, arm lengths, the side each arm is on (body space)
	var palm: Array = []
	var lengths: Array = []
	var side_sign: Array = []
	for side in 2:
		var arm := sk.find_bone(BONE_ARM[side])
		var fore := sk.find_bone(BONE_FOREARM[side])
		var hand := sk.find_bone(BONE_HAND[side])
		var finger := sk.find_bone(BONE_FINGER[side])
		var hand_rest := sk.get_bone_global_rest(hand)
		var palm_point := hand_rest.origin + hand_rest.basis.y.normalized() * 0.08
		if finger >= 0: palm_point = (hand_rest.origin + sk.get_bone_global_rest(finger).origin) * 0.5
		palm.append(hand_rest.affine_inverse() * palm_point)
		var shoulder := sk.get_bone_global_rest(arm).origin
		var elbow := sk.get_bone_global_rest(fore).origin
		lengths.append([shoulder.distance_to(elbow), elbow.distance_to(hand_rest.origin)])
		side_sign.append(signf(hand_rest.origin.x))
	_shared["palm"] = palm
	_shared["lengths"] = lengths
	_shared["side_sign"] = side_sign
	var rest_feet: Array = []
	for side in 2: rest_feet.append(sk.get_bone_global_rest(sk.find_bone(BONE_FOOT[side])).origin.y)
	_shared["foot_rest_y"] = rest_feet
	# the jaw's opening axis (bone space), from the closed and open mouth poses
	_shared["jaw_axis"] = Vector3.ZERO
	var jaw_path := NodePath("%s:%s" % [probe.get_path_to(sk), BONE_JAW])
	var open_clip := library.get_animation(_clip(library, "mouth_open"))
	var closed_clip := library.get_animation(_clip(library, "mouth_closed"))
	if open_clip != null and closed_clip != null:
		var open_track := open_clip.find_track(jaw_path, Animation.TYPE_ROTATION_3D)
		var closed_track := closed_clip.find_track(jaw_path, Animation.TYPE_ROTATION_3D)
		if open_track >= 0 and closed_track >= 0:
			var opening := closed_clip.rotation_track_interpolate(closed_track, 0.0).inverse() * open_clip.rotation_track_interpolate(open_track, 0.0)
			if opening.get_angle() > 0.01: _shared["jaw_axis"] = opening.get_axis()
	_shared["params"] = _prepare_params(sk, library, probe.get_path_to(sk))
	for name in Catalog.body_part_names("shirt"):
		var shirt := probe.find_child(name, true, false) as MeshInstance3D
		if shirt != null and shirt.mesh is ArrayMesh:
			_shared["shirt_mesh"] = _trim_mesh(shirt.mesh, _relative(shirt, probe), sk, _relative(sk, probe))
			break
	var walk_clip := library.get_animation(_clip(library, "walk"))
	_shared["walk_length"] = maxf(walk_clip.length if walk_clip != null else 0.667, 0.1)
	_shared["scene"] = scene
	_shared["library"] = library
	_shared["moves"] = _slap_library(sk, probe.get_path_to(sk), library)
	_shared["tree"] = _build_tree(sk, probe.get_path_to(sk), library)
	_shared["ok"] = true
	probe.free()
	return _shared

## The top of the default head's model (its rest space is the body's), 0 without one.
static func _default_head_top() -> float:
	var head := Catalog.item(Catalog.default_item("head"))
	var path := Catalog.resolve(str(head.get("file", "")))
	var scene := load(path) as PackedScene if path != "" else null
	if scene == null: return 0.0
	var model := scene.instantiate()
	var top := 0.0
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh != null: top = maxf(top, (_relative(mesh, model) * mesh.mesh.get_aabb()).end.y)
	model.free()
	return top

## The sliders' bones in this skeleton: per param [bone, axis mask in bone space], the follow pairs, the channels to put back
## to rest every frame (no clip writes them), the root bone and the rest leg length.
static func _prepare_params(sk: Skeleton3D, library: AnimationLibrary, skeleton_path: NodePath) -> Dictionary:
	var animated := {} ## bone -> {"P": true, "R": true, "S": true}
	for clip_name in library.get_animation_list():
		var clip := library.get_animation(clip_name)
		for track in clip.get_track_count():
			var path := str(clip.track_get_path(track))
			if path.get_slice(":", 0) != str(skeleton_path): continue
			var kind: String = {Animation.TYPE_POSITION_3D: "P", Animation.TYPE_ROTATION_3D: "R", Animation.TYPE_SCALE_3D: "S"}.get(clip.track_get_type(track), "")
			var bone := sk.find_bone(path.get_slice(":", 1))
			if kind == "" or bone < 0: continue
			if not animated.has(bone): animated[bone] = {}
			animated[bone][kind] = true
	var bones := {}
	var touched := {} ## bone -> channels this rig writes ("P" position, "S" scale)
	for entry in Catalog.params():
		var list: Array = []
		for bone_name in entry.get("bones", []):
			var bone := sk.find_bone(str(bone_name))
			if bone < 0: continue
			list.append([bone, _axis_mask(sk, bone, str(entry.get("axes", "xyz")))])
			touched[bone] = str(touched.get(bone, "")) + "S"
		bones[str(entry.get("id", ""))] = list
	var follow: Array = []
	for pair in Catalog.data().get("bone_follow", []):
		var bone := sk.find_bone(str(pair[0]))
		var anchor := sk.find_bone(str(pair[1]))
		if bone < 0 or anchor < 0: continue
		follow.append([bone, anchor])
		touched[bone] = str(touched.get(bone, "")) + "P"
	var head := sk.find_bone(BONE_HEAD)
	if head >= 0: touched[head] = str(touched.get(head, "")) + "P"
	var root := 0
	while root < sk.get_bone_count() - 1 and sk.get_bone_parent(root) >= 0: root += 1
	touched[root] = str(touched.get(root, "")) + "P"
	var reset := {"P": [], "S": []}
	for bone: int in touched:
		for kind in ["P", "S"]:
			if str(touched[bone]).contains(kind) and not (animated.get(bone, {}) as Dictionary).has(kind) and not bone in reset[kind]: reset[kind].append(bone)
	var leg := sk.find_bone("ORG_leg_L")
	var foot := sk.find_bone(BONE_FOOT[0])
	var leg_length := sk.get_bone_global_rest(leg).origin.y - sk.get_bone_global_rest(foot).origin.y if leg >= 0 and foot >= 0 else 0.4
	return {"bones": bones, "follow": follow, "reset": reset, "root": root, "leg_length": leg_length}

## Which of the bone's own axes point along the body axes in `axes` ("x" sideways, "y" up, "z" forward), as a 0/1 mask.
static func _axis_mask(sk: Skeleton3D, bone: int, axes: String) -> Vector3:
	var basis := sk.get_bone_global_rest(bone).basis
	var mask := Vector3.ZERO
	for letter in axes:
		var body_axis: Vector3 = {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK}.get(letter, Vector3.ZERO)
		if body_axis == Vector3.ZERO: continue
		var best := 0
		var best_dot := -1.0
		for i in 3:
			var d := absf(basis[i].normalized().dot(body_axis))
			if d > best_dot:
				best_dot = d
				best = i
		mask[best] = 1.0
	return mask

## The slap clips: the catalog's "slap" clip (a right-arm swing) as slap_right and its mirror image on the left arm as
## slap_left. Both are sampled the same way (60 fps, the right arm's global poses; the left ones mirrored across the body's
## middle), so the two swings are exact mirror images. Library "moves".
static func _slap_library(sk: Skeleton3D, skeleton_path: NodePath, library: AnimationLibrary) -> AnimationLibrary:
	var moves := AnimationLibrary.new()
	var source := library.get_animation(_clip(library, "slap"))
	if source == null: return moves
	var right := Animation.new()
	right.length = source.length
	var left := Animation.new()
	left.length = source.length
	var tracks := {} ## bone -> {"P", "R", "S"} track indices of the source
	for track in source.get_track_count():
		var path := str(source.track_get_path(track))
		var bone := sk.find_bone(path.get_slice(":", 1))
		if path.get_slice(":", 0) != str(skeleton_path) or bone < 0: continue
		if not tracks.has(bone): tracks[bone] = {}
		match source.track_get_type(track):
			Animation.TYPE_POSITION_3D: tracks[bone]["P"] = track
			Animation.TYPE_ROTATION_3D: tracks[bone]["R"] = track
			Animation.TYPE_SCALE_3D: tracks[bone]["S"] = track
	var pairs := {} ## right-arm (and middle) bone -> its left (or same) bone
	for bone in sk.get_bone_count():
		var bone_name := sk.get_bone_name(bone)
		if bone_name in ["spine_FK", "chest_FK"]: pairs[bone] = bone
		elif bone_name.ends_with("_R") and ["arm", "hand", "finger", "thumb", "shoulder"].any(func(part: String) -> bool: return bone_name.containsn(part)):
			var other := sk.find_bone(bone_name.trim_suffix("_R") + "_L")
			if other >= 0: pairs[bone] = other
	var left_tracks := {} ## left (or middle) bone -> its tracks in slap_left
	var right_tracks := {} ## right (or middle) bone -> its tracks in slap_right
	for bone: int in pairs:
		for side in [[left, pairs[bone], left_tracks], [right, bone, right_tracks]]:
			var clip: Animation = side[0]
			var path := NodePath("%s:%s" % [skeleton_path, sk.get_bone_name(side[1])])
			var list := [clip.add_track(Animation.TYPE_POSITION_3D), clip.add_track(Animation.TYPE_ROTATION_3D), clip.add_track(Animation.TYPE_SCALE_3D)]
			for track: int in list: clip.track_set_path(track, path)
			side[2][side[1]] = list
	var flip := Basis.from_scale(Vector3(-1.0, 1.0, 1.0))
	var steps := maxi(ceili(source.length * 60.0), 1)
	for step in steps + 1:
		var time := source.length * step / float(steps)
		var globals := {}
		for bone in sk.get_bone_count(): _clip_global(sk, source, tracks, bone, time, globals)
		var mirrored := {} ## target bone -> its mirrored global pose
		for bone: int in pairs:
			var g: Transform3D = globals[bone]
			mirrored[pairs[bone]] = Transform3D(flip * g.basis * flip, flip * g.origin)
		for target: int in left_tracks:
			var parent := sk.get_bone_parent(target)
			var parent_global: Transform3D = mirrored.get(parent, globals.get(parent, Transform3D())) if parent >= 0 else Transform3D()
			var local: Transform3D = parent_global.affine_inverse() * (mirrored[target] as Transform3D)
			_insert_pose(left, left_tracks[target], time, local)
		for bone: int in right_tracks:
			var parent := sk.get_bone_parent(bone)
			var parent_global: Transform3D = globals.get(parent, Transform3D()) if parent >= 0 else Transform3D()
			_insert_pose(right, right_tracks[bone], time, parent_global.affine_inverse() * (globals[bone] as Transform3D))
	moves.add_animation("slap_right", right)
	moves.add_animation("slap_left", left)
	return moves

static func _insert_pose(clip: Animation, tracks: Array, time: float, local: Transform3D) -> void:
	clip.position_track_insert_key(tracks[0], time, local.origin)
	clip.rotation_track_insert_key(tracks[1], time, local.basis.get_rotation_quaternion())
	clip.scale_track_insert_key(tracks[2], time, local.basis.get_scale())

## A bone's global pose at `time` of `clip` (rest for channels the clip leaves out).
static func _clip_global(sk: Skeleton3D, clip: Animation, tracks: Dictionary, bone: int, time: float, globals: Dictionary) -> Transform3D:
	if globals.has(bone): return globals[bone]
	var rest := sk.get_bone_rest(bone)
	var channels: Dictionary = tracks.get(bone, {})
	var origin := clip.position_track_interpolate(channels["P"], time) if channels.has("P") else rest.origin
	var rotation := clip.rotation_track_interpolate(channels["R"], time) if channels.has("R") else rest.basis.get_rotation_quaternion()
	var scale := clip.scale_track_interpolate(channels["S"], time) if channels.has("S") else rest.basis.get_scale()
	var local := Transform3D(Basis(rotation).scaled_local(scale), origin)
	var parent := sk.get_bone_parent(bone)
	var global := _clip_global(sk, clip, tracks, parent, time, globals) * local if parent >= 0 else local
	globals[bone] = global
	return global

## Transform of `node` relative to `root` (works outside the scene tree).
## `mesh` (the body's shirt, `to_root` its transform) with the team shirt's trim distances in its vertex colours: r how far a
## point is from its sleeve's end along the arm (shoulder to hand, rest pose), g how far below the shirt's top it is, both
## in 0..1 of TRIM_RANGE, alpha 0.5 (shirt.gdshader). The sleeves are the shirt's loose parts beside the part with the top;
## a shirt in one piece gets the collar only.
static func _trim_mesh(mesh: ArrayMesh, to_root: Transform3D, sk: Skeleton3D, skeleton_to_root: Transform3D) -> ArrayMesh:
	var arms := [] # [shoulder, direction to the hand] per side, rest pose
	for side in 2:
		var shoulder := skeleton_to_root * sk.get_bone_global_rest(sk.find_bone(BONE_ARM[side])).origin
		arms.append([shoulder, (skeleton_to_root * sk.get_bone_global_rest(sk.find_bone(BONE_HAND[side])).origin - shoulder).normalized()])
	var copy := ArrayMesh.new()
	copy.resource_name = mesh.resource_name
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var corners: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(points.size()))
		var spots := PackedVector3Array()
		var part := [] # loose parts: points at the same spot are one, joined along the triangles (a union-find)
		var of := PackedInt32Array() # point -> its spot in `part`
		var at := {}
		for i in points.size():
			spots.append(to_root * points[i])
			var spot := Vector3i((spots[i] * 10000.0).round())
			if not at.has(spot):
				at[spot] = part.size()
				part.append(part.size())
			of.append(at[spot])
		for i in range(0, corners.size() - 2, 3):
			for k in 2: part[_part_root(part, of[corners[i + k]])] = _part_root(part, of[corners[i + k + 1]])
		var top := 0
		for i in points.size():
			if spots[i].y > spots[top].y: top = i
		var torso := _part_root(part, of[top])
		var along := PackedFloat32Array()
		var ends := {}
		for i in points.size():
			var arm: Array = arms[0] if signf(spots[i].x) == signf((arms[0][1] as Vector3).x) else arms[1]
			along.append((spots[i] - (arm[0] as Vector3)).dot(arm[1]))
			var root := _part_root(part, of[i])
			if root != torso: ends[root] = maxf(ends.get(root, -INF), along[i])
		var colors := PackedColorArray()
		for i in points.size():
			var root := _part_root(part, of[i])
			var sleeve: float = (ends[root] - along[i]) / TRIM_RANGE if root != torso else 1.0
			var collar := (spots[top].y - spots[i].y) / TRIM_RANGE if root == torso else 1.0
			colors.append(Color(clampf(sleeve, 0.0, 1.0), clampf(collar, 0.0, 1.0), 1.0, 0.5))
		arrays[Mesh.ARRAY_COLOR] = colors
		copy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		copy.surface_set_material(surface, mesh.surface_get_material(surface))
		copy.surface_set_name(surface, mesh.surface_get_name(surface))
	return copy

## The loose part `index` belongs to (union-find root in `part`).
static func _part_root(part: Array, index: int) -> int:
	while part[index] != index: index = part[index]
	return index

static func _relative(node: Node, root: Node) -> Transform3D:
	var xf := Transform3D()
	var n := node
	while n != null and n != root:
		if n is Node3D: xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf

# ---------------------------------------------------------------- animation tree
static func _clip(library: AnimationLibrary, role: String, fallback := "idle") -> String:
	var name := Catalog.clip(role)
	if name != "" and library.has_animation(name): return name
	if fallback != "" and fallback != role: return _clip(library, fallback, "")
	var names := library.get_animation_list()
	return str(names[0]) if not names.is_empty() else ""

static func _animation(library: AnimationLibrary, role: String, backward := false) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = _clip(library, role)
	if backward: node.play_mode = AnimationNodeAnimation.PLAY_MODE_BACKWARD
	return node

static func _filtered(paths: Array) -> AnimationNodeBlend2:
	var blend := AnimationNodeBlend2.new()
	blend.filter_enabled = true
	for path: NodePath in paths: blend.set_filter_path(path, true)
	return blend

static func _build_tree(sk: Skeleton3D, skeleton_path: NodePath, library: AnimationLibrary) -> AnimationNodeBlendTree:
	for role in ["idle", "walk", "sidestep", "fall"]:
		var looped := library.get_animation(_clip(library, role))
		if looped != null: looped.loop_mode = Animation.LOOP_LINEAR
	var emotes: Dictionary = Catalog.emotes()
	for name: String in emotes:
		var clip := library.get_animation(_clip(library, name))
		if clip != null and bool((emotes[name] as Dictionary).get("loop", false)): clip.loop_mode = Animation.LOOP_LINEAR
	var arm_paths: Array = []
	var jaw_paths: Array = []
	for bone in sk.get_bone_count():
		var bone_name := sk.get_bone_name(bone)
		var path := NodePath("%s:%s" % [skeleton_path, bone_name])
		for part in ["arm", "hand", "finger", "thumb", "shoulder"]:
			if bone_name.containsn(part):
				arm_paths.append(path)
				break
		if bone_name.containsn("jaw"): jaw_paths.append(path)
	var tree := AnimationNodeBlendTree.new()
	tree.add_node("idle", _animation(library, "idle"))
	var walk_dir := AnimationNodeBlendSpace2D.new()
	walk_dir.add_blend_point(_animation(library, "walk"), Vector2(0.0, 1.0), -1, "forward")
	walk_dir.add_blend_point(_animation(library, "walk", true), Vector2(0.0, -1.0), -1, "back")
	walk_dir.add_blend_point(_animation(library, "sidestep"), Vector2(1.0, 0.0), -1, "right")
	walk_dir.add_blend_point(_animation(library, "sidestep"), Vector2(-1.0, 0.0), -1, "left")
	tree.add_node("walk_dir", walk_dir)
	tree.add_node("walk_scale", AnimationNodeTimeScale.new())
	tree.connect_node("walk_scale", 0, "walk_dir")
	tree.add_node("move", AnimationNodeBlend2.new())
	tree.connect_node("move", 0, "idle")
	tree.connect_node("move", 1, "walk_scale")
	tree.add_node("jump", _animation(library, "jump"))
	tree.add_node("jump_seek", AnimationNodeTimeSeek.new())
	tree.connect_node("jump_seek", 0, "jump")
	tree.add_node("fall", _animation(library, "fall"))
	tree.add_node("air_pick", AnimationNodeBlend2.new())
	tree.connect_node("air_pick", 0, "jump_seek")
	tree.connect_node("air_pick", 1, "fall")
	tree.add_node("air", AnimationNodeBlend2.new())
	tree.connect_node("air", 0, "move")
	tree.connect_node("air", 1, "air_pick")
	var hold := AnimationNodeBlendSpace1D.new()
	hold.add_blend_point(_animation(library, "carry_down"), -1.0, -1, "low")
	hold.add_blend_point(_animation(library, "carry"), 0.0, -1, "level")
	hold.add_blend_point(_animation(library, "carry_up"), 1.0, -1, "high")
	tree.add_node("hold", hold)
	tree.add_node("carry", _filtered(arm_paths))
	tree.connect_node("carry", 0, "air")
	tree.connect_node("carry", 1, "hold")
	var pick := AnimationNodeTransition.new()
	pick.xfade_time = 0.0
	var index := 0
	for name: String in emotes:
		pick.add_input(name)
		pick.set_input_reset(index, true)
		tree.add_node("emote_" + name, _animation(library, name))
		index += 1
	tree.add_node("emote_pick", pick)
	index = 0
	for name: String in emotes:
		tree.connect_node("emote_pick", index, "emote_" + name)
		index += 1
	tree.add_node("emote_seek", AnimationNodeTimeSeek.new())
	tree.connect_node("emote_seek", 0, "emote_pick")
	tree.add_node("emote", AnimationNodeBlend2.new())
	tree.connect_node("emote", 0, "carry")
	tree.connect_node("emote", 1, "emote_seek")
	tree.add_node("mouth", _animation(library, "mouth_open"))
	var slap_bones := {-1: [], 1: []} ## each arm with its fingers and shoulder, plus the spine and chest that twist with it
	for bone in sk.get_bone_count():
		var bone_name := sk.get_bone_name(bone)
		var path := NodePath("%s:%s" % [skeleton_path, bone_name])
		if bone_name in ["spine_FK", "chest_FK"]:
			slap_bones[-1].append(path)
			slap_bones[1].append(path)
		elif path in arm_paths:
			slap_bones[-1 if bone_name.ends_with("_L") else 1].append(path)
	var under := "emote"
	for side in [-1, 1]:
		var name := "slap_left" if side < 0 else "slap_right"
		var clip := AnimationNodeAnimation.new()
		clip.animation = "moves/" + name
		tree.add_node(name + "_clip", clip)
		var faster := AnimationNodeTimeScale.new()
		tree.add_node(name + "_speed", faster)
		tree.connect_node(name + "_speed", 0, name + "_clip")
		var shot := AnimationNodeOneShot.new()
		shot.fadein_time = 0.05
		shot.fadeout_time = 0.1
		shot.filter_enabled = true
		for path: NodePath in slap_bones[side]: shot.set_filter_path(path, true)
		tree.add_node(name, shot)
		tree.connect_node(name, 0, under)
		tree.connect_node(name, 1, name + "_speed")
		under = name
	tree.add_node("talk", _filtered(jaw_paths))
	tree.connect_node("talk", 0, under)
	tree.connect_node("talk", 1, "mouth")
	tree.connect_node("output", 0, "talk")
	return tree

# ---------------------------------------------------------------- build
func _build() -> void:
	var shared := _shared_body()
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	if not bool(shared.get("ok", false)): return
	_body = (shared["scene"] as PackedScene).instantiate()
	_body.name = "Body"
	for player: AnimationPlayer in _body.find_children("*", "AnimationPlayer", true, false):
		player.get_parent().remove_child(player)
		player.free()
	_pivot.add_child(_body)
	_skeleton = _body.find_children("*", "Skeleton3D", true, false)[0]
	_bone = {"head": _skeleton.find_bone(BONE_HEAD), "jaw": _skeleton.find_bone(BONE_JAW), "arm": [], "forearm": [], "hand": [], "foot": []}
	for side in 2:
		_bone["arm"].append(_skeleton.find_bone(BONE_ARM[side]))
		_bone["forearm"].append(_skeleton.find_bone(BONE_FOREARM[side]))
		_bone["hand"].append(_skeleton.find_bone(BONE_HAND[side]))
		_bone["foot"].append(_skeleton.find_bone(BONE_FOOT[side]))
	var meshes := _meshes
	meshes.clear()
	for mesh: MeshInstance3D in _skeleton.find_children("*", "MeshInstance3D", true, false): meshes[str(mesh.name)] = mesh
	var parts := Catalog.body_parts()
	for key: String in parts:
		if key in ["skin", "brow_tone", "hidden"]: continue
		for name in Catalog.body_part_names(key):
			if meshes.has(name):
				_parts[key] = meshes[name]
				break
	for name in Catalog.body_part_names("hidden"):
		if meshes.has(name): (meshes[name] as MeshInstance3D).visible = false
	if _parts.has("shirt") and shared.has("shirt_mesh"): (_parts["shirt"] as MeshInstance3D).mesh = shared["shirt_mesh"]
	for key: String in _parts: _part_mesh[key] = (_parts[key] as MeshInstance3D).mesh
	if _parts.has("eyes"): _eye_material = (_parts["eyes"] as MeshInstance3D).get_active_material(0)
	_layer_ref = null
	for name in Catalog.body_part_names("skin"):
		if meshes.has(name) and _layer_ref == null: _layer_ref = meshes[name]
	if _layer_ref == null and not meshes.is_empty(): _layer_ref = meshes.values()[0]
	for mesh: MeshInstance3D in meshes.values(): mesh.extra_cull_margin = 0.5
	_tree = AnimationTree.new()
	_tree.name = "Animation"
	_tree.add_animation_library("", shared["library"])
	_tree.add_animation_library("moves", shared["moves"])
	_tree.tree_root = shared["tree"]
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_body.add_child(_tree)
	_tree.root_node = _tree.get_path_to(_body)
	_tree.active = true
	_built = true
	_fresh = true
	_place_pivot()
	_tree.advance(0.0)

func _place_pivot() -> void:
	var shared := _shared
	var amounts := _flop_amounts()
	var upright := 1.0 - amounts.y
	var lean := Basis(Vector3.RIGHT, -(_lean + _reach_lean * _carry) * upright) * Basis(Vector3.BACK, (-_roll - _sway) * upright)
	var squash := Basis.from_scale(Vector3(1.0 + _squash * 0.5, 1.0 - _squash, 1.0 + _squash * 0.5) * (1.0 - amounts.x) + Vector3.ONE * amounts.x)
	_pivot.transform = _tilt_transform(amounts.z, amounts.x) * Transform3D(lean * squash * (shared["pivot_basis"] as Basis), lean * (shared["pivot_origin"] as Vector3) + Vector3.UP * _bob)

## (lying amount: 1 flat, easing to 0 as the courier gets up, body held straight: lying or diving, tilt in rad)
func _flop_amounts() -> Vector3:
	var lie := _lie * smoothstep(0.0, 1.0, _getup)
	return Vector3(lie, maxf(lie, _dive), maxf(_dive * DIVE_PITCH, lie * PI * 0.5))

## The body tipped forward by `tilt` rad about the hips: a dive in the air, 90 degrees flat for the belly flop. Flat on the floor (`lie` 1) the
## body axis is LIE_HEIGHT over the ground and centred on the capsule; while rising the toes stay on the floor.
func _tilt_transform(tilt: float, lie: float) -> Transform3D:
	if tilt < 0.0001: return Transform3D.IDENTITY
	var turned := Basis(Vector3.RIGHT, -tilt)
	var down := clampf(lie * 4.0, 0.0, 1.0)
	var pivot := Vector3(0.0, lerpf(HIPS_Y, HIPS_Y * cos(tilt) + LIE_HEIGHT * sin(tilt), down), -LIE_CENTER * sin(tilt) * down)
	return Transform3D(turned, pivot - turned * Vector3(0.0, HIPS_Y, 0.0))

# ---------------------------------------------------------------- look
func get_look() -> CharacterLook:
	if _look_over != null and _look_kept != null: return _look_kept.duplicate_look() # the player's own look, kept under an override
	return _look.duplicate_look() if _look != null else Look.defaults_for_seat(seat)

## Applies colours and items at once. Cheap when nothing changed (safe every frame of a preview).
func set_look(look: CharacterLook) -> void:
	if look == null: return
	_own_look = true
	_show_look(look)

## Draws `over` instead of the player's look until it is called with null (the show's FORCED VIDEO: a plain look for three seconds). While an override stands, set_look / set_slot_tint
## still keep the player's look underneath, and null puts exactly that one back.
func set_look_over(over: CharacterLook) -> void:
	var under := get_look()
	_look_over = over
	_look_kept = under if over != null else null
	_show_look(over if over != null else under)

func _show_look(given: CharacterLook) -> void:
	if given == null: return
	if _look_over != null and given != _look_over:
		_look_kept = given
		given = _look_over
	var look := given.animal_only(seat) # no people: a people head is this seat's animal
	if _look != null and _look.equals(look) and not _applied.is_empty(): return
	_look = look.duplicate_look()
	if not _built:
		look_applied.emit()
		return
	var shown := _look.fitted()
	var head_changed: bool = _applied.get("head", null) != str(shown.items.get("head", ""))
	for slot in Catalog.slots():
		var id := str(shown.items.get(slot, ""))
		if _applied.get(slot, null) == id and not (slot in ["hat", "hair"] and head_changed): continue
		_apply_item(slot, id)
		_applied[slot] = id
	_apply_params(shown)
	_apply_colors()
	if _fp_skeleton != null: _fp_dress()
	look_applied.emit()

func _apply_item(slot: String, id: String) -> void:
	var entry := Catalog.item(id)
	for name in _hidden_by.get(slot, []):
		if _meshes.has(name): (_meshes[name] as MeshInstance3D).visible = true
	_hidden_by[slot] = entry.get("hides", []) if id != "" else []
	for name in _hidden_by[slot]:
		if _meshes.has(name): (_meshes[name] as MeshInstance3D).visible = false
	if _extras.has(slot):
		var old: Node = _extras[slot]
		old.get_parent().remove_child(old)
		old.queue_free()
		_extras.erase(slot)
	var mode := str(entry.get("mode", ""))
	var file := str(entry.get("file", ""))
	var part: MeshInstance3D = _parts.get(slot)
	if slot == "head": _hat_socket = _item(file).get("socket") if file != "" else null
	match slot:
		"eyes":
			_eye_file = file # drawn by _apply_colors (after the face sliders)
			return
		"shirt":
			return # the shirt is drawn by _apply_colors (colour, print, team picture)
	if part != null: # a body part: the body's own, an item mesh, or nothing
		part.visible = id != "" or slot == "head" # no head item (none has its model yet): the body's own head
		if id == "": return
		var mesh: Mesh = _part_mesh.get(slot)
		if mode == "skinned" and file != "":
			var res := _item(file)
			if res.has("mesh"): mesh = res["mesh"]
		part.mesh = mesh
		_base_mesh[slot] = mesh
		return
	if id == "" or file == "": return
	var res := _item(file)
	var node: Node3D
	if mode == "skinned" and res.has("mesh"):
		var skinned := MeshInstance3D.new()
		skinned.mesh = res["mesh"]
		var own_skin: Skin = res.get("skin")
		skinned.skin = own_skin if own_skin != null else (_layer_ref.skin if _layer_ref != null else null)
		_skeleton.add_child(skinned)
		skinned.skeleton = skinned.get_path_to(_skeleton)
		skinned.extra_cull_margin = 0.5
		node = skinned
	elif res.has("scene"):
		node = _attach(entry, res["scene"])
	if node == null: return
	if node is MeshInstance3D: _base_mesh[slot] = (node as MeshInstance3D).mesh
	node.name = "Item_" + slot
	_extras[slot] = node
	var layers := _layer_ref.layers if _layer_ref != null else 1
	if node is MeshInstance3D: (node as MeshInstance3D).layers = layers
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false): mesh.layers = layers

## The BoneAttachment3D that carries things on `bone_name` (made on first use).
func _attachment(bone_name: String) -> BoneAttachment3D:
	if not _attachments.has(bone_name):
		var attachment := BoneAttachment3D.new()
		attachment.name = "On_" + bone_name
		_skeleton.add_child(attachment)
		attachment.bone_name = bone_name
		_attachments[bone_name] = attachment
	return _attachments[bone_name]

## A node on the head bone at the top of the head (the worn head's hat socket, else the hat fallback lift), upright in body space: what a crown is parented to (modes/show/view.gd). It follows
## the head through every clip and the body's scale. Made on first use, null for a rig without the head bone.
func head_anchor() -> Node3D:
	if _head_anchor != null and is_instance_valid(_head_anchor): return _head_anchor
	var bone := _skeleton.find_bone(HEAD_BONE) if _skeleton != null else -1
	if bone < 0: return null
	var rest := _skeleton.get_bone_global_rest(bone)
	var holder := Node3D.new()
	holder.name = "HeadAnchor"
	if _hat_socket is Transform3D:
		holder.transform = rest.affine_inverse() * (_hat_socket as Transform3D)
	else:
		var upright := rest.basis.orthonormalized().inverse()
		var lift: Array = Catalog.data().get("hat_fallback", [0.0, 0.0, 0.0])
		holder.transform = Transform3D(upright, upright * Vector3(float(lift[0]), float(lift[1]), float(lift[2])))
	_attachment(HEAD_BONE).add_child(holder)
	_head_anchor = holder
	return holder

## An item model on its bone: hats and hair upright at the head bone, hand items in the hand's grip.
func _attach(entry: Dictionary, scene: PackedScene) -> Node3D:
	var bone_name := str(entry.get("bone", "ORG_jaw_upper"))
	var bone := _skeleton.find_bone(bone_name)
	if bone < 0:
		push_warning("Character item %s: no bone %s" % [entry.get("id", ""), bone_name])
		return null
	var attachment := _attachment(bone_name)
	var holder := Node3D.new()
	var rest := _skeleton.get_bone_global_rest(bone)
	if bone_name in BONE_HAND:
		var side := 0 if bone_name == BONE_HAND[0] else 1
		var grip := Transform3D(HAND_GRIP, (_shared["palm"] as Array)[0])
		holder.transform = grip if side == 0 else Transform3D(_mirrored(Transform3D(HAND_GRIP, Vector3.ZERO)).basis, (_shared["palm"] as Array)[1])
	elif str(entry.get("slot", "")) in ["hat", "hair"] and _hat_socket is Transform3D:
		holder.transform = rest.affine_inverse() * (_hat_socket as Transform3D) # the worn head's socket, carried by the head bone
		var place: Array = Catalog.item(str(_applied.get("head", ""))).get("hair_place", []) if str(entry.get("slot", "")) == "hair" else []
		if place.size() >= 4: # this head's hair fit: moved [x, y, z] in the socket's space and scaled
			holder.transform *= Transform3D(Basis.from_scale(Vector3.ONE * float(place[3])), Vector3(float(place[0]), float(place[1]), float(place[2])))
	else:
		var upright := rest.basis.orthonormalized().inverse()
		var lift: Array = Catalog.data().get("hat_fallback", [0.0, 0.0, 0.0]) if str(entry.get("slot", "")) in ["hat", "hair"] else [0.0, 0.0, 0.0]
		holder.transform = Transform3D(upright, upright * Vector3(float(lift[0]), float(lift[1]), float(lift[2])))
	holder.set_meta("base", holder.transform)
	if bool(entry.get("upright", false)): holder.set_meta("upright", true)
	var model: Node3D = scene.instantiate()
	for player: AnimationPlayer in model.find_children("*", "AnimationPlayer", true, false):
		player.get_parent().remove_child(player)
		player.free()
	var offset: Array = entry.get("offset", [0.0, 0.0, 0.0])
	var turn: Array = entry.get("rotate", [0.0, float(entry.get("yaw", 0.0)), 0.0])
	var tilt := Basis.from_euler(Vector3(deg_to_rad(float(turn[0])), deg_to_rad(float(turn[1])), deg_to_rad(float(turn[2]))))
	model.transform = Transform3D(tilt, Vector3(float(offset[0]), float(offset[1]), float(offset[2])))
	var slot := str(entry.get("slot", ""))
	_style_model(model, slot if slot in ["hat", "hair"] else "accent")
	_show_logo(model, _team_picture())
	holder.add_child(model)
	attachment.add_child(holder)
	return holder

## The HatSocket of a head model in its skeleton's rest space, null without one. Under a BoneAttachment3D (a node parented to
## a bone) it is that bone's rest pose times the node's own transform; anywhere else its transform relative to the skeleton.
static func _socket_transform(model: Node) -> Variant:
	var socket := model.find_child(HAT_SOCKET, true, false) as Node3D
	if socket == null: return null
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	var sk: Skeleton3D = skeletons[0] if not skeletons.is_empty() else null
	var attachment := socket.get_parent() as BoneAttachment3D
	if sk != null and attachment != null:
		var bone := sk.find_bone(attachment.bone_name)
		if bone < 0: bone = attachment.bone_idx
		if bone >= 0 and bone < sk.get_bone_count(): return sk.get_bone_global_rest(bone) * socket.transform
	var space: Node = sk if sk != null else model
	return _relative(space, model).affine_inverse() * _relative(socket, model)

## Puts `picture` on every surface of `model` whose material is named "logo" (the cap's front panel); none: as modelled.
static func _show_logo(model: Node, picture: Texture2D) -> void:
	if picture == null: return
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D: meshes.append(model)
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null: continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface)
			if _surface_name(material) != "logo": continue
			var styled := _style_material("hat_logo", Color.WHITE, picture)
			if styled != null:
				mesh.set_surface_override_material(surface, styled)
				continue
			mesh.set_surface_override_material(surface, _soft(material, Color.WHITE, picture))

static func _mirrored(xf: Transform3D) -> Transform3D:
	var flip := Basis.from_scale(Vector3(-1.0, 1.0, 1.0))
	return Transform3D(flip * xf.basis * flip, flip * xf.origin)

## Loads an item file once: a texture, or a scene with its first mesh (skinned items).
static func _item(path: String) -> Dictionary:
	if _item_cache.has(path): return _item_cache[path]
	var res := {}
	var resolved := Catalog.resolve(path)
	var loaded: Resource = load(resolved) if resolved != "" else null
	if loaded is Texture2D:
		res["texture"] = loaded
	elif loaded is PackedScene:
		res["scene"] = loaded
		var probe: Node = (loaded as PackedScene).instantiate()
		var meshes := probe.find_children("*", "MeshInstance3D", true, false)
		if probe is MeshInstance3D: meshes.push_front(probe)
		if not meshes.is_empty():
			res["mesh"] = (meshes[0] as MeshInstance3D).mesh
			res["skin"] = (meshes[0] as MeshInstance3D).skin
		var socket: Variant = _socket_transform(probe)
		if socket != null: res["socket"] = socket
		probe.free()
	elif loaded != null:
		push_warning("Character item file is not a scene or picture: " + resolved)
	# a file that is not there yet keeps the body's own part (our art lands later)
	_item_cache[path] = res
	return res

func _eye_override(file: String) -> Material:
	if _eye_material == null: return null
	var res := _item(file) if file != "" else {}
	var styled := _style_material("eye", Color.WHITE, res.get("texture", _albedo(_eye_material)[1]))
	if styled != null: return styled
	return _soft(_eye_material, null, res.get("texture"))

# ---------------------------------------------------------------- sliders
## The look's slider values: bone scales and lifts for the pose, the face part meshes, the hat, the fun motions.
func _apply_params(look: CharacterLook) -> void:
	var prepared: Dictionary = _shared["params"]
	_bone_scales.clear()
	_body_lift = 0.0
	_head_lift = 0.0
	var face := {} ## face part slot -> [[param entry, value], ...]
	var hat := {"scale": Vector3.ONE, "tilt": 0.0}
	for entry in Catalog.params():
		var id := str(entry.get("id", ""))
		var value := look.param(id)
		var factor := Catalog.param_factor(entry, value)
		var special := str(entry.get("special", ""))
		if special in _fun:
			_fun[special] = factor
			continue
		if value == 0.0: continue
		for bone_axes in prepared["bones"].get(id, []):
			var mask: Vector3 = bone_axes[1]
			var scale: Vector3 = _bone_scales.get(bone_axes[0], Vector3.ONE)
			_bone_scales[bone_axes[0]] = scale * (Vector3.ONE + mask * (factor - 1.0))
		match str(entry.get("lift", "")):
			"body": _body_lift += (factor - 1.0) * float(prepared["leg_length"])
			"head": _head_lift += (factor - 1.0) * float(entry.get("lift_by", 0.05))
		for part in entry.get("parts", []):
			if not face.has(part): face[part] = []
			face[part].append([entry, value])
		if str(entry.get("target", "")) == "hat":
			if special == "tilt": hat["tilt"] = factor
			else: hat["scale"] *= Vector3.ONE + _letters(str(entry.get("axes", "xyz"))) * (factor - 1.0)
	# face parts that are meshes of the body are reshaped whole; the others are surfaces of the head (named like the part)
	var head_ops: Array = []
	for slot in ["eyes", "eyelids", "brows", "nose", "mouth", "ears"]:
		var part: MeshInstance3D = _parts.get(slot)
		var ops: Array = face.get(slot, [])
		if part == null:
			for op in ops: head_ops.append([op[0], op[1], HEAD_SURFACES.get(slot, [slot])])
			var worn := _extras.get(slot) as MeshInstance3D # a face item of its own on the head (brows, nose)
			var worn_base: Mesh = _base_mesh.get(slot)
			if worn != null and worn_base != null:
				var shown_worn := worn_base if ops.is_empty() else _deformed(worn_base, ops)
				if worn.mesh != shown_worn: worn.mesh = shown_worn
			continue
		var base: Mesh = _base_mesh.get(slot, _part_mesh.get(slot))
		var mesh := base if ops.is_empty() or base == null else _deformed(base, ops)
		if part.mesh != mesh: part.mesh = mesh
	var head := _parts.get("head", _extras.get("head")) as MeshInstance3D
	var head_base: Mesh = _base_mesh.get("head", _part_mesh.get("head"))
	if head != null and head_base != null:
		var shown_head := head_base if head_ops.is_empty() else _deformed(head_base, head_ops)
		if head.mesh != shown_head: head.mesh = shown_head
	var hat_node := _extras.get("hat") as Node3D
	if hat_node != null and hat_node.has_meta("base"):
		hat_node.transform = (hat_node.get_meta("base") as Transform3D) * Transform3D(Basis(Vector3.RIGHT, hat["tilt"]) * Basis.from_scale(hat["scale"]), Vector3.ZERO)

## "xz" -> (1, 0, 1).
static func _letters(axes: String) -> Vector3:
	return Vector3(1.0 if axes.contains("x") else 0.0, 1.0 if axes.contains("y") else 0.0, 1.0 if axes.contains("z") else 0.0)

## A face part mesh reshaped by face sliders, cached: "scale" grows it around its centre (each side's own centre with
## `split`), "spread" moves each side outwards. An op [entry, value, surfaces] with surface names only reshapes those
## surfaces (by material name) of a bigger mesh, the head. The skin weights stay, so the part still follows the skeleton.
static func _deformed(base: Mesh, ops: Array) -> Mesh:
	var key := "%d" % base.get_instance_id()
	for op in ops: key += "|%s=%d" % [op[0].get("id", ""), roundi(float(op[1]) * 127.0)]
	if _mesh_cache.has(key): return _mesh_cache[key]
	var names: Array = []
	for surface in base.get_surface_count():
		var material := base.surface_get_material(surface)
		names.append(_surface_name(material))
	var centres: Array = [] ## per op: all, left (x >= 0), right (x < 0) of the surfaces it reshapes
	for op in ops:
		var sums := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
		var counts := [0, 0, 0]
		for surface in base.get_surface_count():
			if not _reshapes(op, names[surface]): continue
			for v: Vector3 in base.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var side := 1 if v.x >= 0.0 else 2
				sums[0] += v
				sums[side] += v
				counts[0] += 1
				counts[side] += 1
		for i in 3: sums[i] /= maxf(counts[i], 1.0)
		centres.append(sums)
	var out := ArrayMesh.new()
	for surface in base.get_surface_count():
		var arrays := base.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in verts.size():
			var v := verts[i]
			var side := 1 if v.x >= 0.0 else 2
			var stretch := Vector3.ONE
			for index in ops.size():
				var op: Array = ops[index]
				if not _reshapes(op, names[surface]): continue
				var entry: Dictionary = op[0]
				var factor := Catalog.param_factor(entry, float(op[1]))
				if str(entry.get("deform", "")) == "spread":
					v.x += factor if side == 1 else -factor
					continue
				var axes := _letters(str(entry.get("axes", "xyz")))
				var scale := Vector3.ONE + axes * (factor - 1.0)
				var centre: Vector3 = centres[index][side] if bool(entry.get("split", false)) else centres[index][0]
				v = centre + (v - centre) * scale
				stretch *= scale
			verts[i] = v
			if i < normals.size(): normals[i] = (normals[i] / stretch).normalized()
		arrays[Mesh.ARRAY_VERTEX] = verts
		if normals.size() == verts.size(): arrays[Mesh.ARRAY_NORMAL] = normals
		var bones = arrays[Mesh.ARRAY_BONES]
		var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if bones != null and bones.size() == verts.size() * 8 else 0
		var primitive := (base as ArrayMesh).surface_get_primitive_type(surface) if base is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
		out.add_surface_from_arrays(primitive, arrays, [], {}, flags)
		out.surface_set_material(surface, base.surface_get_material(surface))
	_mesh_cache[key] = out
	return out

static func _reshapes(op: Array, surface_name: String) -> bool:
	return op.size() < 3 or (op[2] as Array).is_empty() or surface_name in op[2]

## Every frame after the clips: channels no clip writes back to rest, the sliders' bone scales, the loose bones moved with
## what they sit on, then the lifts of longer legs (the root up, the feet stay) and a longer neck (the head up).
func _pose_params() -> void:
	var prepared: Dictionary = _shared["params"]
	var sk := _skeleton
	for bone: int in prepared["reset"]["P"]: sk.set_bone_pose_position(bone, sk.get_bone_rest(bone).origin)
	for bone: int in prepared["reset"]["S"]: sk.set_bone_pose_scale(bone, sk.get_bone_rest(bone).basis.get_scale())
	if _bone_scales.is_empty() and _body_lift == 0.0 and _head_lift == 0.0: return
	var before := {}
	for pair in prepared["follow"]:
		for bone: int in pair:
			if not before.has(bone): before[bone] = sk.get_bone_global_pose(bone)
	for bone: int in _bone_scales: sk.set_bone_pose_scale(bone, sk.get_bone_pose_scale(bone) * (_bone_scales[bone] as Vector3))
	for pair in prepared["follow"]:
		var anchor_then: Transform3D = before[pair[1]]
		var origin := sk.get_bone_global_pose(pair[1]) * (anchor_then.affine_inverse() * (before[pair[0]] as Transform3D).origin)
		_set_bone_global(pair[0], Transform3D(sk.get_bone_global_pose(pair[0]).basis, origin))
	if _head_lift != 0.0 and _bone["head"] >= 0:
		var head := sk.get_bone_global_pose(_bone["head"])
		_set_bone_global(_bone["head"], Transform3D(head.basis, head.origin + Vector3.UP * _head_lift))
	if _body_lift != 0.0:
		var root: int = prepared["root"]
		sk.set_bone_pose_position(root, sk.get_bone_pose_position(root) + Vector3.UP * _body_lift)

# ---------------------------------------------------------------- colours
func _apply_colors() -> void:
	var eyes: MeshInstance3D = _parts.get("eyes")
	if eyes != null: eyes.set_surface_override_material(0, _eye_override(_eye_file))
	var skin := Catalog.color("skin", int(_look.colors.get("skin", 0)))
	for name in Catalog.body_part_names("skin"):
		_tint_part(_meshes.get(name), skin)
	for name in Catalog.body_part_names("brow_tone"):
		_tint_part(_meshes.get(name), skin.darkened(BROW_SHADE))
	_tint_part(_parts.get("pants"), Catalog.color("pants", int(_look.colors.get("pants", 0))), "pants")
	_tint_part(_parts.get("shoes"), Catalog.color("shoes", int(_look.colors.get("shoes", 0))), "shoes")
	var shirt: MeshInstance3D = _parts.get("shirt")
	var shirt_material := _shirt_material(Catalog.color("shirt", int(_look.colors.get("shirt", 0))), str(_look.items.get("shirt", "")), str(_look.items.get("outfit", "")))
	if shirt != null: shirt.set_surface_override_material(0, shirt_material)
	# every surface named after a colour slot, on the body, the head and skinned items (not the brows: they keep their shade);
	# surfaces named "team_color" on any item (the cap's crown, bill and button) take the team's first brand colour, else the
	# shirt colour; the other surfaces take the game look's eye or accent material, except the body parts coloured above
	var brand := TeamCast.brand_colors()
	var team: Color = brand[0] if not brand.is_empty() else Catalog.color("shirt", int(_look.colors.get("shirt", 0)))
	var item_kinds := {} # hat and hair meshes take the game look's hat or hair material, other items its accent material
	for kind in ["hat", "hair"]:
		if _extras.has(kind):
			for mesh in (_extras[kind] as Node).find_children("*", "MeshInstance3D", true, false): item_kinds[mesh] = kind
	var brows := Catalog.body_part_names("brow_tone")
	var coloured := {}
	for key in ["eyes", "pants", "shoes", "shirt"]:
		if _parts.has(key): coloured[_parts[key]] = true
	for name in Catalog.body_part_names("skin"):
		if _meshes.has(name): coloured[_meshes[name]] = true
	for mesh: MeshInstance3D in _skeleton.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or str(mesh.name) in brows: continue
		for surface in mesh.mesh.get_surface_count():
			if surface == 0 and coloured.has(mesh): continue
			var material := mesh.mesh.surface_get_material(surface)
			var slot := _surface_name(material)
			slot = SURFACE_COLORS.get(slot, slot)
			if slot == "shirt": mesh.set_surface_override_material(surface, shirt_material)
			elif slot == "team_color": mesh.set_surface_override_material(surface, _colored(material, item_kinds.get(mesh, "accent"), team))
			elif slot in Catalog.color_slots(): mesh.set_surface_override_material(surface, _colored(material, slot, Catalog.color(slot, int(_look.colors.get(slot, 0)))))
			elif material != null and mesh.get_parent() == _skeleton: # the rest of the body, head and outfits: eyes and accents
				var shown := _albedo(material)
				var styled := _style_material("eye" if slot == "eyes" else "accent", shown[0], shown[1])
				mesh.set_surface_override_material(surface, styled if styled != null else _soft(material))
	_dress_head()

## The worn head's own face surfaces: "eyes" shows the worn eye picture (else its own, or the game look's eye material) and
## its "pupils" hide while a picture is worn (the picture has its own); a face item worn on its own (brows, nose) hides the
## head's surface of that slot.
func _dress_head() -> void:
	var head := _parts.get("head", _extras.get("head")) as MeshInstance3D
	if head == null or head.mesh == null: return
	var picture: Texture2D = _item(_eye_file).get("texture") if _eye_file != "" else null
	var eyes: Material = null
	for surface in head.mesh.get_surface_count():
		if _surface_name(head.mesh.surface_get_material(surface)) == "eyes": eyes = head.mesh.surface_get_material(surface)
	if eyes == null: picture = null # no surface to draw the picture on: the head keeps its own pupils
	for surface in head.mesh.get_surface_count():
		var material := head.mesh.surface_get_material(surface)
		var surface_name := _surface_name(material)
		var covered := false
		var face_slot := ""
		for slot in ["brows", "nose"]:
			if surface_name in HEAD_SURFACES.get(slot, []):
				face_slot = slot
				covered = covered or _extras.has(slot)
		if covered or (surface_name == "pupils" and picture != null): head.set_surface_override_material(surface, _hidden_material()) # an eye picture draws its own pupil
		elif surface_name == "pupils": head.set_surface_override_material(surface, _pupils(material, eyes))
		elif surface_name == "eyes": head.set_surface_override_material(surface, _eye_picture(material, picture) if picture != null else _own(material, "eye"))
		elif face_slot != "": head.set_surface_override_material(surface, _own(material, "accent"))

## `base` (a head's "eyes" material) showing `picture`: the game look's eye material when it has one.
static func _eye_picture(base: Material, picture: Texture2D) -> Material:
	var styled := _style_material("eye", Color.WHITE, picture)
	if styled != null: return styled
	return _soft(base, Color.WHITE, picture)

## A head's "pupils" in their own colours; pupils without a colour of their own (white, no texture) on a light eyeball
## would not show, so they draw in PUPIL_COLOR (white pupils on a dark eyeball are its shine and stay).
static func _pupils(material: Material, eyes: Material) -> Material:
	var shown := _albedo(material)
	if shown[1] != null or (shown[0] as Color).get_luminance() < 0.9 or eyes == null or (_albedo(eyes)[0] as Color).get_luminance() < 0.5: return _own(material, "eye")
	var styled := _style_material("eye", PUPIL_COLOR)
	return styled if styled != null else _soft(material, PUPIL_COLOR)

## A surface's material in its own colours: the game look's `kind` material, else the soft toy material.
static func _own(material: Material, kind: String) -> Material:
	var shown := _albedo(material)
	var styled := _style_material(kind, shown[0], shown[1])
	return styled if styled != null else (_soft(material) if material != null else null)

## A material that draws nothing (a head surface covered by a face item).
static func _hidden_material() -> Material:
	if not _material_cache.has("hidden"):
		var shader := Shader.new()
		shader.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled;\nvoid fragment() { discard; }\n"
		var material := ShaderMaterial.new()
		material.shader = shader
		_material_cache["hidden"] = material
	return _material_cache["hidden"]

## Surface 0 of `part` in `color`: its current mesh's own material (body or item) with the colour multiplied in.
func _tint_part(part: MeshInstance3D, color: Color, kind := "skin") -> void:
	if part == null or part.mesh == null: return
	var base := part.mesh.surface_get_material(0)
	if base == null: return
	part.set_surface_override_material(0, _colored(base, kind, color))

## The game look's material for a part of the character (FriendsStyle.character_material, kinds skin, shirt, pants,
## shoes, accent, eye, hat, hat_logo, hair), cached per kind, colour and texture; null when the look has none.
static func _style_material(kind: String, color: Color, texture: Texture2D = null) -> Material:
	var hook := style_hook
	if not hook.is_valid():
		if _style_found == null:
			_style_found = false
			for method in (Style as Script).get_script_method_list():
				if str(method.get("name", "")) == "character_material": _style_found = Callable(Style, "character_material")
		if _style_found is Callable: hook = _style_found
	if not hook.is_valid(): return null
	var key := "style|%s|%s|%d" % [kind, color.to_html(), texture.get_instance_id() if texture != null else 0]
	if not _material_cache.has(key): _material_cache[key] = hook.call(kind, color, texture)
	return _material_cache[key]

## A surface's name for the rules above: its material's name without a modelling tool's ".001" copy suffix.
static func _surface_name(material: Material) -> String:
	return material.resource_name.get_slice(".", 0) if material != null else ""

## The colour and texture a material shows (for the game look's materials).
static func _albedo(material: Material) -> Array:
	if material is BaseMaterial3D: return [(material as BaseMaterial3D).albedo_color, (material as BaseMaterial3D).albedo_texture]
	return [Color.WHITE, null]

## `base` in `color` for the colour slot `kind`: the game look's material when it has one, else `base` with the colour
## multiplied in (cached per material and colour).
static func _colored(base: Material, kind: String, color: Color) -> Material:
	var styled := _style_material(kind, color, _albedo(base)[1])
	return styled if styled != null else _tinted(base, color)

## Every surface of an item model in the game look's material of `kind` (hats, hair, hand items); the cap's logo panel too.
## (Surfaces named "team_color" are coloured by _apply_colors.)
static func _style_model(model: Node, kind: String) -> void:
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D: meshes.append(model)
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null: continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface)
			var shown := _albedo(material)
			var logo := _surface_name(material) == "logo" # the picture goes on in _show_logo
			var styled := _style_material("hat_logo" if logo else kind, shown[0], shown[1])
			if material != null: mesh.set_surface_override_material(surface, styled if styled != null else _soft(material))

## `base` with `color` as its albedo colour (cached per material and colour).
static func _tinted(base: Material, color: Color) -> Material:
	return _soft(base, color)

## The characters' own material for a surface: `base`'s colour (or `color`), texture (or `texture`), vertex colours and
## roughness in the soft toy shader (character_soft.gdshader; catalog "material" tunes fill and rim). Cached.
static func _soft(base: Material, color: Variant = null, texture: Variant = null) -> Material:
	var shown := _albedo(base)
	var albedo: Color = color if color is Color else shown[0]
	var picture: Texture2D = texture if texture is Texture2D else shown[1]
	var key := "soft|%d|%s|%d" % [base.get_instance_id() if base != null else 0, albedo.to_html(), picture.get_instance_id() if picture != null else 0]
	if not _material_cache.has(key):
		var soft := ShaderMaterial.new()
		soft.shader = SOFT_SHADER
		soft.set_shader_parameter("albedo", albedo)
		if picture != null: soft.set_shader_parameter("albedo_tex", picture)
		if base is BaseMaterial3D:
			soft.set_shader_parameter("use_vertex_color", (base as BaseMaterial3D).vertex_color_use_as_albedo)
			soft.set_shader_parameter("roughness_value", maxf((base as BaseMaterial3D).roughness, 0.7))
		var tune: Dictionary = Catalog.data().get("material", {})
		for name in ["fill", "rim"]:
			if tune.has(name): soft.set_shader_parameter(name, float(tune[name]))
		_material_cache[key] = soft
	return _material_cache[key]

## The shirt in `color` with the item `id`'s print, under the outfit `outfit`. The team shirt (print "team") is white with the
## sleeve ends and collar in `color`, the team logo on the chest and the team's motto under it; the cast's shirt_print.png,
## when there is one, is printed instead of logo and motto. The outfit's catalog "chest" [x, y, scale] moves and scales that
## chest print (scale 0: the outfit covers the chest, no print). Other prints go over `color`.
func _shirt_material(color: Color, id: String, outfit := "") -> Material:
	var entry := Catalog.item(id)
	var team := str(entry.get("print", "")) == "team"
	var file := str(entry.get("file", ""))
	if file == "" and not team:
		var styled := _style_material("shirt", color)
		if styled != null: return styled
	var chest: Array = Catalog.item(outfit).get("chest", [0.0, 0.0, 1.0])
	var move := Vector3(float(chest[0]), float(chest[1]), float(chest[2])) if chest.size() >= 3 else Vector3(0.0, 0.0, 1.0)
	var shown := team and move.z > 0.0
	var own := Catalog.cast_shirt_picture() if shown else null
	var logo := _team_picture() if shown and own == null else null
	var motto := _motto_picture(_motto()) if shown and own == null else null
	var key := "shirt|%s|%s|%s|%d|%d|%d" % [color.to_html(), id, move if shown else Vector3.ZERO, own.get_instance_id() if own != null else 0, logo.get_instance_id() if logo != null else 0, motto.get_instance_id() if motto != null else 0]
	if _material_cache.has(key): return _material_cache[key]
	var material := ShaderMaterial.new()
	material.shader = SHIRT_SHADER
	material.set_shader_parameter("base_color", Color.WHITE if team else color)
	var tune: Dictionary = Catalog.data().get("material", {})
	for name in ["fill", "rim"]:
		if tune.has(name): material.set_shader_parameter(name, float(tune[name]))
	if file != "": material.set_shader_parameter("print_tex", _item(file).get("texture"))
	if team:
		material.set_shader_parameter("trim", 1.0)
		material.set_shader_parameter("trim_color", color)
		material.set_shader_parameter("sleeve_band", TRIM_SLEEVE / TRIM_RANGE)
		material.set_shader_parameter("collar_band", TRIM_COLLAR / TRIM_RANGE)
		material.set_shader_parameter("chest_pivot", CHEST_PIVOT)
		if shown: material.set_shader_parameter("chest_move", move)
		if own != null: material.set_shader_parameter("print_tex", own)
		if logo != null:
			material.set_shader_parameter("logo_tex", logo)
			material.set_shader_parameter("logo_rect", _contain(LOGO_OVER_MOTTO if motto != null else LOGO_RECT, logo.get_size()))
		if motto != null:
			material.set_shader_parameter("motto_tex", motto)
			material.set_shader_parameter("motto_rect", _contain(MOTTO_RECT if logo != null else MOTTO_ALONE, motto.get_size()))
			material.set_shader_parameter("motto_ink", MOTTO_INK)
	_material_cache[key] = material
	return material

## The motto of the team shirt: the team's name in capitals (the tagline is a whole sentence, too long to print legibly on a chest),
## "" when the cast has none.
static func _motto() -> String:
	var team = TeamCast.data().get("team", {})
	var line = team.get("name", "") if team is Dictionary else ""
	return line.strip_edges().to_upper() if line is String else ""

## `text` as a picture for the shirt (cached): white letters whose alpha is the ink, null for no text.
static func _motto_picture(text: String) -> Texture2D:
	if text == "": return null
	var key := "motto|" + text
	if not _material_cache.has(key):
		var image := _motto_image(text)
		_material_cache[key] = ImageTexture.create_from_image(image) if image != null else null
	return _material_cache[key]

## `text` in MOTTO_FONT at MOTTO_SIZE px, centred, on one line or, past MOTTO_SPLIT characters, on two (split at the space
## nearest the middle): white letters, alpha = ink. Drawn from the font's own glyph pictures, so it needs no renderer.
static func _motto_image(text: String) -> Image:
	var lines: Array[String] = [text]
	if text.length() > MOTTO_SPLIT and text.contains(" "):
		var cut := -1
		for i in text.length():
			if text[i] == " " and (cut < 0 or absi(i - text.length() / 2) < absi(cut - text.length() / 2)): cut = i
		lines = [_unbound(text.substr(0, cut)), _unbound(text.substr(cut + 1))]
	var font := _motto_font()
	var size := Vector2i(MOTTO_SIZE, 0)
	var widths: Array[float] = []
	for line in lines:
		var width := 0.0
		for letter in line: width += font.get_glyph_advance(0, MOTTO_SIZE, _glyph(font, letter)).x
		widths.append(width)
	var pad := 8
	var line_height := font.get_height(MOTTO_SIZE)
	var image := Image.create_empty(int(ceilf(widths.max())) + pad * 2, int(ceilf(line_height * lines.size())) + pad * 2, false, Image.FORMAT_RGBA8)
	for row in lines.size():
		var pen := Vector2(pad + (image.get_width() - pad * 2 - widths[row]) * 0.5, pad + font.get_ascent(MOTTO_SIZE) + line_height * row)
		for letter in lines[row]:
			var glyph := _glyph(font, letter)
			var sheet := font.get_glyph_texture_idx(0, size, glyph)
			if sheet >= 0:
				var area := Rect2i(font.get_glyph_uv_rect(0, size, glyph))
				var picture := font.get_texture_image(0, size, sheet).get_region(area)
				picture.convert(Image.FORMAT_RGBA8)
				image.blend_rect(picture, Rect2i(Vector2i.ZERO, area.size), Vector2i((pen + font.get_glyph_offset(0, size, glyph)).round()))
			pen.x += font.get_glyph_advance(0, MOTTO_SIZE, glyph).x
	return image

## `line` without spaces and without separators (" · ", "-") at either end: a line of the motto never starts or ends with one.
static func _unbound(line: String) -> String:
	var words := line.strip_edges().split(" ", false)
	while words.size() > 1 and words[0] in SEPARATORS: words.remove_at(0)
	while words.size() > 1 and words[words.size() - 1] in SEPARATORS: words.remove_at(words.size() - 1)
	return " ".join(words)

## MOTTO_FONT at MOTTO_WEIGHT: a copy of it, so the UI's own use of the font stays as it is.
static func _motto_font() -> FontFile:
	if not _material_cache.has("motto_font"):
		var font: FontFile = MOTTO_FONT.duplicate()
		font.set_variation_coordinates(0, {TextServerManager.get_primary_interface().name_to_tag("weight"): MOTTO_WEIGHT})
		_material_cache["motto_font"] = font
	return _material_cache["motto_font"]

## The glyph of `letter` in `font` at MOTTO_SIZE, drawn into the font's glyph pictures.
static func _glyph(font: FontFile, letter: String) -> int:
	var glyph := font.get_glyph_index(MOTTO_SIZE, letter.unicode_at(0), 0)
	font.render_glyph(0, Vector2i(MOTTO_SIZE, 0), glyph)
	return glyph

## The team logo, else the painting's picture, else null.
static func _team_picture() -> Texture2D:
	var logo := TeamCast.logo()
	return logo if logo != null else TeamCast.picture()

## `area` shrunk to the aspect of `size`, centred (the whole picture is shown).
static func _contain(area: Rect2, size: Vector2) -> Vector4:
	var aspect := size.x / maxf(size.y, 1.0)
	var rect := area
	if aspect >= area.size.x / area.size.y: rect.size.y = area.size.x / aspect
	else: rect.size.x = area.size.y * aspect
	rect.position += (area.size - rect.size) * 0.5
	return Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y)

# ---------------------------------------------------------------- emotes and voice
## dance, sit, yes, no, point, think, cry. Plays while standing; moving, jumping or carrying ends it.
func play_emote(emote_name: String) -> void:
	var emotes := Catalog.emotes()
	if not emotes.has(emote_name):
		push_warning("Unknown emote: " + emote_name)
		return
	if not _built or _carry > 0.5: return
	var settings: Dictionary = emotes[emote_name]
	var clip := (_shared["library"] as AnimationLibrary).get_animation(_clip(_shared["library"], emote_name))
	_emote = emote_name
	_emote_time = 0.0
	_emote_loop = bool(settings.get("loop", false))
	_emote_length = float(settings.get("seconds", clip.length if clip != null else 1.0))
	if _emote_loop and not settings.has("seconds"): _emote_length = INF
	var mouth = settings.get("mouth", [0.0, 0.0, 0.0])
	_emote_mouth = mouth if mouth is Array and (mouth as Array).size() == 3 else [0.0, 0.0, 0.0]
	_tree.set("parameters/emote_pick/transition_request", emote_name)
	_tree.set("parameters/emote_seek/seek_request", 0.0)

## An arm-swing slap with the left (-1) or right (+1) hand. slap_hit fires SLAP_HIT_TIME later with the hand's position;
## hand_world() follows the swing. While carrying, the hands stay on the grips. Ends an emote.
func slap(side: int) -> void:
	if not _built or side == 0: return
	_slap_side = -1 if side < 0 else 1
	_slap_time = 0.0
	_emote = ""
	_shout = maxf(_shout, SLAP_SHOUT)
	var name := "slap_left" if _slap_side < 0 else "slap_right"
	_tree.set("parameters/%s_speed/scale" % name, SLAP_SPEED)
	_tree.set("parameters/%s/request" % name, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

## Seconds a slap takes.
func slap_length() -> float:
	if not _built: return 0.0
	var clip := (_shared["moves"] as AnimationLibrary).get_animation("slap_right")
	return clip.length / SLAP_SPEED if clip != null else 0.0

func emote_playing() -> String:
	return _emote

## Ends the emote playing (it fades out); a looping one (the dance) does not end by itself while the character stands.
func stop_emote() -> void:
	_emote = ""

## The cast's emote for this player (players[i].emote, one of Catalog.emotes(); i = tint_index, the cast seat), "" for none.
func cast_emote() -> String:
	var emote := str(TeamCast.player(tint_index).get("emote", ""))
	return emote if Catalog.emotes().has(emote) else ""

## Plays the cast's emote for this player now (the goal, a long stop); nothing without one or while carrying.
func play_cast_emote() -> void:
	var emote := cast_emote()
	if emote != "": play_emote(emote)

## Sets how far the mouth opens on its own, 0..1 (the shouts, the scream and the emote's mouth come on top).
func set_talk_level(level: float) -> void:
	_talk_target = clampf(level, 0.0, 1.0)

## How open the mouth is right now, 0..1.
func mouth_open() -> float:
	return _talk

# ---------------------------------------------------------------- animation
func snap(state: Dictionary) -> void:
	_fresh = true
	_last_pos = global_position
	update(0.0, state, [])

func update(dt: float, state: Dictionary, grips: Array = []) -> void:
	dt = clampf(dt, 0.0, 0.1)
	var paused := bool(state.get("paused", false))
	var pos := global_position
	var vel: Vector3
	if state.has("velocity") and state["velocity"] is Vector3:
		vel = state["velocity"]
	elif dt > 0.0 and not _fresh:
		vel = (pos - _last_pos) / dt
	else:
		vel = Vector3.ZERO
	_last_pos = pos
	var grounded := bool(state.get("grounded", true))
	var carrying := bool(state.get("carrying", false))
	var flop := maxf(float(state.get("flop", 0.0)), 0.0)
	var target_yaw := float(state.get("yaw", _yaw))
	if _fresh:
		_yaw = target_yaw
		_grounded = grounded
		_vy_prev = vel.y
		_last_vel = vel
		_air = 0.0 if grounded else 1.0
		_carry = 1.0 if carrying else 0.0
		_speed = Vector2(vel.x, vel.z).length()
		_squash = 0.0
		_squash_v = 0.0
		_lie = 1.0 if flop > 0.0 else 0.0
		_getup = clampf(flop / GETUP, 0.0, 1.0)
		_dive = 0.0
		_fresh = false
	var turn := angle_difference(_yaw, target_yaw)
	if not paused: _yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-16.0 * dt))
	global_basis = Basis(Vector3.UP, _yaw)
	if not _built: return
	if paused:
		_tree.advance(0.0)
		_post_pose(state, grips)
		if _fp: _fp_update(0.0, grips)
		return
	var inv := Basis(Vector3.UP, _yaw).inverse()
	var speed := Vector2(vel.x, vel.z).length()
	_speed = lerpf(_speed, speed, 1.0 - exp(-20.0 * dt))
	# airborne transitions and events
	if _grounded and not grounded and vel.y > 1.5:
		_squash_v -= 1.2
		_tree.set("parameters/jump_seek/seek_request", 0.0)
		_shout = maxf(_shout, JUMP_SHOUT)
		jumped.emit()
	if not _grounded and grounded:
		var impact := maxf(_fall_peak, -_vy_prev)
		_fall_peak = 0.0
		_squash_v += clampf(impact, 0.0, 14.0) * 0.35
		if impact > HARD_LANDING: _shout = maxf(_shout, clampf(impact / 14.0, 0.5, 1.0))
		_wobble_v.x += clampf(impact, 0.0, 14.0) * WOBBLE_KICK * 4.0
		landed.emit(impact)
	if not grounded: _fall_peak = maxf(_fall_peak, -vel.y)
	_grounded = grounded
	_vy_prev = vel.y
	_air = move_toward(_air, 0.0 if grounded else 1.0, dt * (12.0 if grounded else 9.0))
	_carry = move_toward(_carry, 1.0 if carrying else 0.0, dt * 6.0)
	_lie = move_toward(_lie, 1.0 if flop > 0.0 else 0.0, dt / LIE_IN)
	_getup = clampf(flop / GETUP, 0.0, 1.0)
	var diving := not grounded and flop <= 0.0 and _carry < 0.5 and Vector2(vel.x, vel.z).length() > DIVE_SPEED
	_dive = move_toward(_dive, 1.0 if diving else 0.0, dt * (9.0 if diving else 6.0))
	# lean from acceleration and turning (the whole body tips around the feet)
	var accel: Vector3
	if state.has("acceleration") and state["acceleration"] is Vector3:
		accel = state["acceleration"]
	elif dt > 0.0:
		accel = (vel - _last_vel) / dt
	else:
		accel = Vector3.ZERO
	_last_vel = vel
	if accel.length() < 0.5 and speed > 0.3 and grounded:
		accel = -vel.normalized() * 12.0 * minf(speed / 2.0, 1.0)
	var local_acc := inv * accel
	_acc_fwd = lerpf(_acc_fwd, clampf(-local_acc.z, -20.0, 20.0), 1.0 - exp(-10.0 * dt))
	_acc_side = lerpf(_acc_side, clampf(local_acc.x, -20.0, 20.0), 1.0 - exp(-10.0 * dt))
	var turn_rate := clampf(turn / maxf(dt, 0.001), -6.0, 6.0) if dt > 0.0 else 0.0
	var speed01 := clampf(_speed / 5.0, 0.0, 1.2)
	var lean_target := (speed01 * 0.08 + _acc_fwd * 0.004) * (1.0 - 0.6 * _carry) * (1.0 - _air * 0.5)
	_lean = lerpf(_lean, lean_target, 1.0 - exp(-9.0 * dt))
	_roll = lerpf(_roll, clampf(_acc_side * 0.003 - turn_rate * speed01 * 0.025, -0.2, 0.2), 1.0 - exp(-9.0 * dt))
	_squash_v += (-300.0 * _squash - 16.0 * _squash_v) * dt
	_squash = clampf(_squash + _squash_v * dt, -0.08, 0.18)
	# emotes end when the player moves
	if _emote != "":
		_emote_time += dt
		if speed > 0.6 or not grounded or carrying or _emote_time >= _emote_length: _emote = ""
	if idle_emotes:
		if speed > 0.6 or not grounded or carrying:
			_still = 0.0
			_idle_emoted = false
		elif not _idle_emoted:
			_still += dt
			if _still >= IDLE_EMOTE_AFTER:
				_idle_emoted = true
				play_cast_emote()
	_emote_weight = move_toward(_emote_weight, 1.0 if _emote != "" else 0.0, dt / (EMOTE_FADE_IN if _emote != "" else EMOTE_FADE_OUT))
	# mouth: voice, shouts, a scream while falling fast, the emote's own mouth; opens fast, closes a little slower
	_shout = move_toward(_shout, 0.0, dt / SHOUT_SECONDS)
	var scream := clampf((-vel.y - SCREAM_FALL_SPEED) / 8.0, 0.0, 0.8) if not grounded else 0.0
	var emote_mouth := clampf(float(_emote_mouth[0]) + float(_emote_mouth[1]) * sin(TAU * float(_emote_mouth[2]) * _emote_time), 0.0, 1.0) * _emote_weight
	var mouth := maxf(maxf(_talk_target, _shout), maxf(scream, emote_mouth))
	_talk = lerpf(_talk, mouth, 1.0 - exp(-(30.0 if mouth > _talk else 14.0) * dt))
	# clip blend
	var local_vel := inv * vel
	var heading := Vector2(local_vel.x, -local_vel.z)
	if heading.length() > 0.2: _walk_dir = _walk_dir.lerp(heading.normalized(), 1.0 - exp(-10.0 * dt))
	var gait := smoothstep(0.15, 1.0, _speed) * (1.0 - _lie)
	# fun sliders: a bob and a sway on every step, a head jiggle pushed by acceleration and landings
	var walk_scale := clampf(_speed / WALK_CLIP_SPEED, 0.5, 2.2)
	_walk_phase = fposmod(_walk_phase + dt * walk_scale / float(_shared["walk_length"]), 1.0) if gait > 0.01 else 0.0
	_bob = float(_fun["bounce"]) * BOUNCE_HEIGHT * absf(sin(TAU * _walk_phase)) * gait
	_sway = float(_fun["swagger"]) * SWAGGER_ROLL * sin(TAU * _walk_phase) * gait
	var kick := Vector2(_acc_fwd, _acc_side) * WOBBLE_KICK
	_wobble_v += (-WOBBLE_STIFF * _wobble - WOBBLE_DAMP * _wobble_v) * dt + kick * dt * 10.0
	_wobble = (_wobble + _wobble_v * dt).limit_length(0.5)
	_tree.set("parameters/walk_dir/blend_position", _walk_dir)
	_tree.set("parameters/walk_scale/scale", walk_scale)
	_tree.set("parameters/move/blend_amount", gait)
	_tree.set("parameters/air_pick/blend_amount", clampf((1.0 - vel.y) / 4.0, 0.0, 1.0))
	_tree.set("parameters/air/blend_amount", _air)
	_tree.set("parameters/hold/blend_position", _hold_height)
	_tree.set("parameters/carry/blend_amount", _carry)
	_tree.set("parameters/talk/blend_amount", _talk)
	_tree.set("parameters/emote/blend_amount", _emote_weight)
	_tree.advance(dt)
	_post_pose(state, grips)
	if grounded and gait > 0.35 and _emote == "": _footsteps()
	if _slap_side != 0:
		var before := _slap_time
		_slap_time += dt
		if before < SLAP_HIT_TIME and _slap_time >= SLAP_HIT_TIME: slap_hit.emit(_slap_side, hand_world(0 if _slap_side < 0 else 1))
		if _slap_time >= slap_length(): _slap_side = 0
	if _fp: _fp_update(dt, grips)

## Footsteps from the clip itself: a foot plants when it comes down to its rest height.
func _footsteps() -> void:
	var rest: Array = _shared["foot_rest_y"]
	for side in 2:
		var y := _skeleton.get_bone_global_pose(_bone["foot"][side]).origin.y
		if _foot_armed[side] and y < float(rest[side]) + STEP_DOWN:
			_foot_armed[side] = false
			footstep.emit(side)
		elif y > float(rest[side]) + STEP_UP:
			_foot_armed[side] = true

## After the clips: pivot lean and squash, the head towards `look_at`, the hands to the grips while carrying.
func _post_pose(state: Dictionary, grips: Array) -> void:
	_place_pivot()
	_pose_params()
	var sk := _skeleton
	var amounts := _flop_amounts()
	var strait: float = amounts.y
	if strait > 0.001: # arms stretched ahead of the head (a little hop of the hands while getting up), the head up to look ahead
		var hop := sin(PI * smoothstep(0.0, 1.0, _getup)) * 0.6 * _lie
		for side in 2:
			_turn_bone(_bone["arm"][side], Quaternion(Vector3.RIGHT, (ARMS_AHEAD - hop) * strait))
		if _bone["head"] >= 0: _turn_bone(_bone["head"], Quaternion(Vector3.RIGHT, amounts.z * 0.55))
	var carry := _carry * (1.0 - strait)
	var to_body := sk.global_transform.affine_inverse()
	var wobble := (_wobble * float(_fun["wobble"])).limit_length(WOBBLE_MAX)
	if _bone["head"] >= 0 and wobble.length_squared() > 0.000001:
		_turn_bone(_bone["head"], Quaternion(Vector3.RIGHT, wobble.x) * Quaternion(Vector3.BACK, -wobble.y))
	if state.has("look_at") and state["look_at"] is Vector3 and is_inside_tree() and _bone["head"] >= 0:
		var to_target: Vector3 = to_local(state["look_at"])
		if Vector2(to_target.x, to_target.z).length_squared() > 0.01:
			var look_yaw := clampf(atan2(-to_target.x, -to_target.z), -1.0, 1.0) * (1.0 - _emote_weight)
			_turn_bone(_bone["head"], Quaternion(Vector3.UP, look_yaw * 0.6))
	var jaw_axis: Vector3 = _shared["jaw_axis"]
	if _talk > 0.001 and _bone["jaw"] >= 0 and jaw_axis != Vector3.ZERO:
		sk.set_bone_pose_rotation(_bone["jaw"], sk.get_bone_pose_rotation(_bone["jaw"]) * Quaternion(jaw_axis, _talk * MOUTH_EXTRA))
	var hand_items := _extras.get("hand") as Node3D
	if hand_items != null:
		hand_items.visible = _carry < 0.3
		if hand_items.has_meta("upright"): # a balloon: its string rises straight up from the hand, whatever the hand does
			hand_items.global_basis = Basis(Vector3.UP, global_rotation.y).scaled(hand_items.global_basis.get_scale())
	if carry <= 0.001: return
	var lengths: Array = _shared["lengths"]
	var palm: Array = _shared["palm"]
	var sides: Array = _shared["side_sign"]
	var reach_sum := 0.0
	var height_sum := 0.0
	for side in 2:
		var target_world: Vector3
		if grips.size() == 2 and grips[side] is Vector3: target_world = grips[side]
		else: target_world = to_global(Vector3((-1.0 if side == 0 else 1.0) * HOLD_SIDE, ANCHOR_OFFSET.y, -HOLD_FORWARD))
		var target := to_body * target_world
		var arm := sk.get_bone_global_pose(_bone["arm"][side])
		var fore := sk.get_bone_global_pose(_bone["forearm"][side])
		var hand := sk.get_bone_global_pose(_bone["hand"][side])
		var stretch: float = (_bone_scales.get(_bone["arm"][side], Vector3.ONE) as Vector3)[_arm_axis(side)]
		var upper_len: float = float(lengths[side][0]) * stretch
		var lower_len: float = float(lengths[side][1]) * stretch
		var shoulder := arm.origin
		var pole := Vector3(float(sides[side]) * 0.7, -1.0, -0.35)
		var fore_basis := fore.basis
		var hand_basis := hand.basis
		var wrist := target - hand_basis * (palm[side] as Vector3)
		var chain := {}
		for refine in 3:
			var reach := (upper_len + lower_len) * REACH_SLACK
			var start := shoulder
			if wrist.distance_to(shoulder) > reach: start = wrist + (shoulder - wrist).normalized() * reach # out of reach: the arm follows the hand
			chain = _two_bone(start, wrist, upper_len, lower_len, pole)
			chain["start"] = start
			var turn_fore := Quaternion(fore.basis.y.normalized(), chain["lower"])
			fore_basis = Basis(turn_fore) * fore.basis
			hand_basis = Basis(turn_fore) * hand.basis
			wrist = target - hand_basis * (palm[side] as Vector3)
		var upper_basis := Basis(Quaternion(arm.basis.y.normalized(), chain["upper"])) * arm.basis
		var elbow: Vector3 = chain["start"] + (chain["upper"] as Vector3) * upper_len
		_set_bone_global(_bone["arm"][side], arm.interpolate_with(Transform3D(upper_basis, chain["start"]), carry))
		_set_bone_global(_bone["forearm"][side], fore.interpolate_with(Transform3D(fore_basis, elbow), carry))
		_set_bone_global(_bone["hand"][side], hand.interpolate_with(Transform3D(hand_basis, wrist), carry))
		reach_sum += shoulder.distance_to(wrist) / (upper_len + lower_len)
		height_sum += (target.y - shoulder.y) / maxf(upper_len + lower_len, 0.01)
	# far grips tip the body forward; the hold pose follows the grip height
	_reach_lean = lerpf(_reach_lean, clampf((reach_sum * 0.5 - 0.85) * 0.8, 0.0, 0.25), 0.15)
	_hold_height = lerpf(_hold_height, clampf(height_sum * 0.5 * 1.5, -1.0, 1.0), 0.2)

## The arm bone's own axis that runs along the arm (slider scales on it lengthen the reach).
func _arm_axis(side: int) -> int:
	return _along_axis(_bone["arm"][side], _bone["forearm"][side])

## The axis of `bone` (0 x, 1 y, 2 z) that points the most towards the bone `toward` in the rest pose.
func _along_axis(bone: int, toward: int) -> int:
	var basis := _skeleton.get_bone_global_rest(bone).basis
	var along := (_skeleton.get_bone_global_rest(toward).origin - _skeleton.get_bone_global_rest(bone).origin).normalized()
	var best := 1
	for i in 3:
		if absf(basis[i].normalized().dot(along)) > absf(basis[best].normalized().dot(along)): best = i
	return best

## Turns a bone by `q` (body space) about its own origin.
func _turn_bone(bone: int, q: Quaternion) -> void:
	var global := _skeleton.get_bone_global_pose(bone)
	_set_bone_global(bone, Transform3D(Basis(q) * global.basis, global.origin))

## Sets a bone's pose from a body-space transform.
func _set_bone_global(bone: int, xf: Transform3D) -> void:
	var parent := _skeleton.get_bone_parent(bone)
	var local := xf if parent < 0 else _skeleton.get_bone_global_pose(parent).affine_inverse() * xf
	_skeleton.set_bone_pose_position(bone, local.origin)
	_skeleton.set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())

## Two-bone chain from `root` to `target`; the middle joint bends towards `pole`.
## Returns the directions of the two bones (unit vectors, root -> mid, mid -> end).
static func _two_bone(root: Vector3, target: Vector3, a: float, b: float, pole: Vector3) -> Dictionary:
	var d := target - root
	var dist := clampf(d.length(), absf(a - b) + 0.001, (a + b) * 0.9999)
	var dir := d.normalized() if d.length() > 0.0001 else Vector3.DOWN
	var x := (a * a - b * b + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(a * a - x * x, 0.0))
	var side := pole - dir * pole.dot(dir)
	side = side.normalized() if side.length() > 0.0001 else Vector3.BACK
	var mid := root + dir * x + side * h
	var end := root + dir * dist
	return {"upper": (mid - root).normalized(), "lower": (end - mid).normalized()}

# ---------------------------------------------------------------- first person
## First person on or off for this character's own `camera` (the viewport's camera when null). On: that camera stops drawing
## the character (its meshes go to render layer bit FP_BODY_FIRST_BIT + seat % 2, which the camera culls) and draws its view
## arms instead (bit FP_VIEW_FIRST_BIT + seat % 2, added to that camera only): the arm and hand meshes and the hand item on a
## skeleton of their own under the camera, posed in front of it by catalog "first_person" (idle, a held item, reaching in the
## air, the carry grips, the slap), lagging camera turns a little and bobbing with the steps. Other cameras keep the whole
## character with its normal animation and its mouth. Off: the character's layers and the camera's mask come back.
func set_first_person(on: bool, camera: Camera3D = null) -> void:
	if on and camera == null and is_inside_tree(): camera = get_viewport().get_camera_3d()
	on = on and camera != null
	if on == _fp and camera == _fp_camera: return
	if _fp: _fp_off()
	_fp = on
	_fp_camera = camera if on else null
	if on and _built: _fp_build()

func first_person() -> bool:
	return _fp

## World positions of the view arms' palms [left, right] while first person is on (the body's hands otherwise).
func first_person_hands_world() -> Array:
	if _fp_skeleton == null or not _fp_skeleton.is_inside_tree(): return [hand_world(0), hand_world(1)]
	var palms := []
	for side in 2:
		var hand := _fp_skeleton.get_bone_global_pose(_bone["hand"][side])
		palms.append(_fp_skeleton.global_transform * (hand * (_shared["palm"][side] as Vector3)))
	return palms

func _exit_tree() -> void:
	if _fp_root != null and is_instance_valid(_fp_root): _fp_root.queue_free()
	_fp_root = null
	_fp_skeleton = null

## The view arms: a copy of the body skeleton under the camera, the body's arm and hand meshes on it.
func _fp_build() -> void:
	if _fp_root != null and is_instance_valid(_fp_root): _fp_root.queue_free()
	_fp_source = _skeleton
	_fp_root = Node3D.new()
	_fp_root.name = "FirstPersonArms%d" % seat
	_fp_camera.add_child(_fp_root)
	_fp_skeleton = Skeleton3D.new()
	_fp_skeleton.name = "Skeleton"
	for bone in _skeleton.get_bone_count(): _fp_skeleton.add_bone(_skeleton.get_bone_name(bone))
	for bone in _skeleton.get_bone_count():
		_fp_skeleton.set_bone_parent(bone, _skeleton.get_bone_parent(bone))
		_fp_skeleton.set_bone_rest(bone, _skeleton.get_bone_rest(bone))
	_fp_root.add_child(_fp_skeleton)
	_fp_lagged = _fp_camera.global_basis.orthonormalized()
	_fp_dress()

## The view arms' meshes and hand item for the current look; the character's own meshes leave the camera's layers.
func _fp_dress() -> void:
	for child in _fp_skeleton.get_children():
		_fp_skeleton.remove_child(child)
		child.queue_free()
	var view_bit := 1 << (FP_VIEW_FIRST_BIT + seat % 2)
	for source in _skeleton.get_children():
		if not (source is MeshInstance3D) or not (source as MeshInstance3D).visible or (source as MeshInstance3D).mesh == null: continue
		var arms := _arm_mesh((source as MeshInstance3D).mesh, (source as MeshInstance3D).skin, _skeleton)
		if arms == null: continue
		var view := MeshInstance3D.new()
		view.mesh = arms
		view.skin = (source as MeshInstance3D).skin
		_fp_skeleton.add_child(view)
		view.skeleton = NodePath("..")
		var surfaces: PackedInt32Array = arms.get_meta("surfaces")
		for surface in surfaces.size(): view.set_surface_override_material(surface, (source as MeshInstance3D).get_active_material(surfaces[surface]))
	_fp_item = null
	_fp_item_side = -1
	var held := _extras.get("hand") as Node3D
	var on_bone := held.get_parent() as BoneAttachment3D if held != null else null
	if on_bone != null:
		var attachment := BoneAttachment3D.new()
		_fp_skeleton.add_child(attachment)
		attachment.bone_name = on_bone.bone_name
		_fp_item = held.duplicate() as Node3D
		attachment.add_child(_fp_item)
		_fp_item_side = BONE_HAND.find(on_bone.bone_name)
	for mesh: MeshInstance3D in _fp_skeleton.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = view_bit
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.extra_cull_margin = 1.0
	var body_bit := 1 << (FP_BODY_FIRST_BIT + seat % 2)
	if _fp_layers < 0 and _layer_ref != null: _fp_layers = _layer_ref.layers
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false): mesh.layers = body_bit
	_fp_camera.cull_mask = (_fp_camera.cull_mask & ~body_bit) | view_bit

## First person off: the view arms go, the character's meshes and the camera's mask come back.
func _fp_off() -> void:
	if _fp_root != null and is_instance_valid(_fp_root): _fp_root.queue_free()
	_fp_root = null
	_fp_skeleton = null
	_fp_item = null
	if _fp_layers >= 0:
		for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false): mesh.layers = _fp_layers
	_fp_layers = -1
	if is_instance_valid(_fp_camera):
		_fp_camera.cull_mask = (_fp_camera.cull_mask & ~(1 << (FP_VIEW_FIRST_BIT + seat % 2))) | (1 << (FP_BODY_FIRST_BIT + seat % 2))
	_fp_camera = null

## The view arms' pose for this frame (after the body's): the body's bones, then each arm reaching its target in front of the
## camera (catalog "first_person"; camera space as [right, up, forward] metres).
func _fp_update(dt: float, grips: Array) -> void:
	if not is_instance_valid(_fp_camera) or not _fp_camera.is_inside_tree():
		_fp_off()
		_fp = false
		return
	if _fp_skeleton == null or _fp_source != _skeleton: _fp_build()
	var data: Dictionary = Catalog.data().get("first_person", {})
	var sk := _fp_skeleton
	for bone in _skeleton.get_bone_count():
		sk.set_bone_pose_position(bone, _skeleton.get_bone_pose_position(bone))
		sk.set_bone_pose_rotation(bone, _skeleton.get_bone_pose_rotation(bone))
		sk.set_bone_pose_scale(bone, _skeleton.get_bone_pose_scale(bone))
	# the arms follow camera turns a little late and bob with the steps
	var view := _fp_camera.global_basis.orthonormalized()
	_fp_lagged = _fp_lagged.slerp(view, 1.0 - exp(-float(data.get("lag", 14.0)) * dt)).orthonormalized() if dt > 0.0 else view
	_fp_time += dt
	var bob: Array = data.get("bob", [0.0, 0.0])
	var step := sin(TAU * _walk_phase) * smoothstep(0.15, 1.0, _speed)
	_fp_root.transform = Transform3D(view.inverse() * _fp_lagged, Vector3(step * float(bob[0]), -absf(step) * float(bob[1]), 0.0))
	# the skeleton: its shoulders at "shoulders", facing the view, "scale" times the body's size (the carry's own scale while carrying)
	var carry: Dictionary = data.get("carry", {})
	var basis := (_shared["pivot_basis"] as Basis) * Basis.from_scale(Vector3.ONE * lerpf(float(data.get("scale", 1.0)), float(carry.get("scale", data.get("scale", 1.0))), _carry))
	var shoulders := (sk.get_bone_global_rest(_bone["arm"][0]).origin + sk.get_bone_global_rest(_bone["arm"][1]).origin) * 0.5
	sk.transform = Transform3D(basis, _fp_point(data.get("shoulders")) - basis * shoulders)
	var to_skeleton := sk.transform.affine_inverse()
	var sway: Array = data.get("sway", [0.0, 1.0])
	for side in 2:
		var key := "left" if side == 0 else "right"
		var pose: Dictionary = (data.get("held" if side == _fp_item_side and _carry < 0.3 else "idle", {}) as Dictionary).get(key, {})
		var air: Dictionary = (data.get("air", {}) as Dictionary).get(key, pose)
		var hand := _fp_point(pose.get("hand")).lerp(_fp_point(air.get("hand")), _air)
		hand += Vector3(sin(_fp_time * float(sway[1]) + side), cos(_fp_time * float(sway[1]) * 0.8 + side), 0.0) * float(sway[0])
		var elbow := _fp_point(pose.get("elbow")).lerp(_fp_point(air.get("elbow")), _air)
		var turn := _fp_turn(pose.get("turn"))
		if _slap_side != 0 and side == (0 if _slap_side < 0 else 1):
			var slap: Dictionary = data.get("slap", {})
			var seconds := maxf(float(slap.get("seconds", 0.2)), 0.01)
			var mirror := Vector3(-1.0 if side == 0 else 1.0, 1.0, 1.0)
			var sweep := _fp_point(slap.get("from")).lerp(_fp_point(slap.get("to")), smoothstep(0.0, 1.0, _slap_time / seconds)) * mirror
			var weight := 1.0 - clampf((_slap_time - seconds) / maxf(slap_length() - seconds, 0.05), 0.0, 1.0)
			hand = hand.lerp(sweep, weight)
		var target := to_skeleton * hand
		var start := sk.get_bone_global_pose(_bone["arm"][side]).origin
		if _carry > 0.001: # the palms on the grips, the arms coming up from below the view ("from"), not from the eye
			var held: Dictionary = carry.get(key, {})
			var grip: Vector3 = sk.global_transform.affine_inverse() * grips[side] if grips.size() == 2 and grips[side] is Vector3 \
				else to_skeleton * _fp_point(held.get("hand"))
			target = target.lerp(grip, _carry)
			if held.has("from"): start = start.lerp(to_skeleton * _fp_point(held["from"]), _carry)
			if held.has("elbow"): elbow = elbow.lerp(_fp_point(held["elbow"]), _carry)
			if held.has("turn"): turn = turn.lerp(_fp_turn(held["turn"]), _carry)
		var stretch := lerpf(1.0, float(carry.get("stretch", 1.0)), _carry)
		_fp_reach(side, start, target, to_skeleton * elbow, to_skeleton.basis * Basis.from_euler(turn) * sk.transform.basis, float(data.get("hand_scale", 1.0)), stretch)
	if _fp_item != null: _fp_item.visible = _carry < 0.3

## The view arm of `side` reaching from `start` (its shoulder; out of reach the arm slides along the line to the hand) with
## its palm to `target` (view skeleton space), the elbow bending towards `elbow`, the hand turned by `turn` at the wrist
## (from carrying on along the forearm) and scaled by `hand_scale`, the arm and forearm `stretch` times their length (so a
## slim arm still reaches from below the view).
func _fp_reach(side: int, start: Vector3, target: Vector3, elbow: Vector3, turn: Basis, hand_scale: float, stretch := 1.0) -> void:
	var sk := _fp_skeleton
	var hand_bone: int = _bone["hand"][side]
	sk.set_bone_pose_scale(hand_bone, sk.get_bone_pose_scale(hand_bone) * hand_scale)
	var lengths: Array = _shared["lengths"]
	var spans := []
	for pair in [[_bone["arm"][side], _bone["forearm"][side], 0], [_bone["forearm"][side], hand_bone, 1]]:
		var size := sk.get_bone_pose_scale(pair[0])
		var axis := _along_axis(pair[0], pair[1])
		size[axis] *= stretch
		sk.set_bone_pose_scale(pair[0], size)
		spans.append(float(lengths[side][pair[2]]) * size[axis])
	var arm := sk.get_bone_global_pose(_bone["arm"][side])
	var fore := sk.get_bone_global_pose(_bone["forearm"][side])
	var hand := sk.get_bone_global_pose(hand_bone)
	var upper_len: float = spans[0]
	var lower_len: float = spans[1]
	var palm: Vector3 = _shared["palm"][side]
	var shoulder := start
	var hand_basis := hand.basis
	var fore_basis := fore.basis
	var wrist := target - hand_basis * palm
	var chain := {}
	for refine in 3:
		var begin := shoulder
		if wrist.distance_to(shoulder) > (upper_len + lower_len) * REACH_SLACK: begin = wrist + (shoulder - wrist).normalized() * (upper_len + lower_len) * REACH_SLACK
		chain = _two_bone(begin, wrist, upper_len, lower_len, elbow - begin)
		chain["start"] = begin
		var turn_fore := Quaternion(fore.basis.y.normalized(), chain["lower"])
		fore_basis = Basis(turn_fore) * fore.basis
		hand_basis = turn * Basis(turn_fore) * hand.basis
		wrist = target - hand_basis * palm
	var elbow_at: Vector3 = chain["start"] + (chain["upper"] as Vector3) * upper_len
	_fp_set_bone_global(_bone["arm"][side], Transform3D(Basis(Quaternion(arm.basis.y.normalized(), chain["upper"])) * arm.basis, chain["start"]))
	_fp_set_bone_global(_bone["forearm"][side], Transform3D(fore_basis, elbow_at))
	_fp_set_bone_global(hand_bone, Transform3D(hand_basis, wrist))

func _fp_set_bone_global(bone: int, xf: Transform3D) -> void:
	var parent := _fp_skeleton.get_bone_parent(bone)
	var local := xf if parent < 0 else _fp_skeleton.get_bone_global_pose(parent).affine_inverse() * xf
	_fp_skeleton.set_bone_pose_position(bone, local.origin)
	_fp_skeleton.set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())

## A catalog first-person point [right, up, forward] (metres from the camera) in camera space (forward is -Z).
static func _fp_point(value) -> Vector3:
	if not (value is Array) or (value as Array).size() < 3: return Vector3.ZERO
	return Vector3(float(value[0]), float(value[1]), -float(value[2]))

## A catalog first-person hand turn [x, y, z] (degrees about the camera's axes) as euler radians.
static func _fp_turn(value) -> Vector3:
	if not (value is Array) or (value as Array).size() < 3: return Vector3.ZERO
	return Vector3(deg_to_rad(float(value[0])), deg_to_rad(float(value[1])), deg_to_rad(float(value[2])))

## `mesh` cut down to its arm and hand triangles (every corner weighted at least half to an arm, forearm or hand bone or a
## bone under them), null when it has none. Cached per mesh; meta "surfaces" lists the source surface of each surface.
static func _arm_mesh(mesh: Mesh, skin: Skin, sk: Skeleton3D) -> ArrayMesh:
	var key := mesh.get_instance_id()
	if _arm_mesh_cache.has(key): return _arm_mesh_cache[key]
	var arm_bones := {}
	var stack := []
	for side in 2:
		for name in [BONE_ARM[side], BONE_FOREARM[side], BONE_HAND[side]]:
			if sk.find_bone(name) >= 0: stack.append(sk.find_bone(name))
	while not stack.is_empty():
		var bone: int = stack.pop_back()
		arm_bones[bone] = true
		stack.append_array(Array(sk.get_bone_children(bone)))
	var on_arm := {} # skin bind -> true for the arm bones
	for bind in (skin.get_bind_count() if skin != null else sk.get_bone_count()):
		var bone := bind
		if skin != null: bone = sk.find_bone(skin.get_bind_name(bind)) if skin.get_bind_name(bind) != "" else skin.get_bind_bone(bind)
		if arm_bones.has(bone): on_arm[bind] = true
	var copy: ArrayMesh = null
	var from := PackedInt32Array()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null: continue
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var per := bones.size() / maxi(count, 1)
		var arm_point := PackedByteArray()
		arm_point.resize(count)
		for point in count:
			var share := 0.0
			for k in per:
				if on_arm.has(bones[point * per + k]): share += weights[point * per + k]
			arm_point[point] = 1 if share >= 0.5 else 0
		var corners: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(count))
		var kept := PackedInt32Array()
		for i in range(0, corners.size() - 2, 3):
			if arm_point[corners[i]] == 1 and arm_point[corners[i + 1]] == 1 and arm_point[corners[i + 2]] == 1:
				kept.append_array([corners[i], corners[i + 1], corners[i + 2]])
		if kept.is_empty(): continue
		arrays[Mesh.ARRAY_INDEX] = kept
		if copy == null: copy = ArrayMesh.new()
		copy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		copy.surface_set_material(copy.get_surface_count() - 1, mesh.surface_get_material(surface))
		from.append(surface)
	if copy != null: copy.set_meta("surfaces", from)
	_arm_mesh_cache[key] = copy
	return copy
