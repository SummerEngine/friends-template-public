extends Node3D
## The menu pet's body: the model in the game's look (pet_look.gd), its clips crossfaded by state, the motion on top
## (pet_motion.gd) and the team cap (pet_cap.gd).
##   rig.setup(scene) -> bool    # false when the scene has no skeleton
##   rig.play("happy")           # idle | happy | sad | pet, 0.2 s crossfade
const PetMotion := preload("res://pet/pet_motion.gd")
const PetCap := preload("res://pet/pet_cap.gd")
const PetLook := preload("res://pet/pet_look.gd")

## State -> clip names to try, first found wins.
const CLIPS := {"idle": ["menu_idle", "idle"], "happy": ["menu_happy", "happy"], "sad": ["menu_sad", "sad"], "pet": ["menu_pet", "pet"]}
const BLEND := 0.2

var skeleton: Skeleton3D
var player: AnimationPlayer
var motion: PetMotion
var cap: Node3D
var state := ""
## The clip each state plays ("" when the model has none for it).
var clips := {}

func _init() -> void:
	name = "PetRig"

func setup(scene: PackedScene) -> bool:
	var model := scene.instantiate() as Node3D
	if model == null: return false
	model.name = "Model"
	add_child(model)
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty(): return false
	skeleton = skeletons[0]
	var players := model.find_children("*", "AnimationPlayer", true, false)
	player = players[0] if not players.is_empty() else null
	for wanted: String in CLIPS:
		clips[wanted] = ""
		if player == null: continue
		for clip: String in CLIPS[wanted]:
			if player.has_animation(clip):
				clips[wanted] = clip
				player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
				break
	PetLook.dress(model)
	motion = PetMotion.new()
	skeleton.add_child(motion)
	cap = PetCap.wear(skeleton)
	play("idle")
	return true

func play(next: String) -> void:
	if next == state: return
	state = next
	var clip: String = clips.get(next, "")
	if clip == "": clip = clips.get("idle", "")
	if clip != "" and player != null: player.play(clip, BLEND)

## The model's bounds in this node's space (the cap included).
func bounds() -> AABB:
	var result := AABB()
	var first := true
	for item: VisualInstance3D in find_children("*", "VisualInstance3D", true, false):
		if not item is GeometryInstance3D: continue
		var box := (global_transform.affine_inverse() * item.global_transform) * item.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result
