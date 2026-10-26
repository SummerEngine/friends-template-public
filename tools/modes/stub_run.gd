extends Node
## A stand-in for the shell (game/game_run.gd) that a mode's view needs in a check: a world with a camera, one body per slot and,
## when asked, the real character rigs (character/character_rig.gd) on them. Add it to the tree, then call make(count, rigs).
const Rig := preload("res://character/character_rig.gd")

var world: Node3D
var camera: Camera3D
var actors: Array = []
var rigs: Array = []
var carrier_count := 0
var network_role := "replica"
# the shell's per-slot item effects the show's views write each frame (game/game_run.gd): plain tables here, nothing reads them in a check
var item_mods := {}
var item_power := {}
var rig_lag := {}
var rig_scales := {}
var rule_mods := {} # the manager's rules (modes/show/manager/manager_view.gd)
var rule_scales := {}
var number_keys := false
var item_slot := {"kind": -1, "roll": 0.0}

func make(count: int, with_rigs := false) -> void:
	carrier_count = count
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	camera = Camera3D.new()
	world.add_child(camera)
	for slot in count:
		var body := CharacterBody3D.new()
		body.name = "Courier%d" % (slot + 1)
		world.add_child(body)
		actors.append(body)
		var rig: Node3D = null
		if with_rigs and Rig.available():
			rig = Rig.new()
			world.add_child(rig)
			rig.setup(slot)
		rigs.append(rig)

func is_slot_active(slot: int) -> bool:
	return slot >= 0 and slot < carrier_count
