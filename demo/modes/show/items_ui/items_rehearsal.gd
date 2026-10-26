extends Node
## The items' dress rehearsal (docs/items.md "Hitch"). The first time a machine draws an effect's materials, particles, shaders, fonts and video it builds them on the spot: on a Mac whose Metal
## cache is cold that is a freeze of a quarter to two and a half seconds for the first SMASH, CALL, FORCED VIDEO, GLITCH, BOOST or SOAR of a run (a warm cache: 10 to 50 ms), and the second use
## of the same item costs one normal frame. So the round's card plays every item's look once, before anybody can use one.
## It is the real look code, not a copy: a second manager (items_view.gd with `rehearsal` on) is fed a made-up state, FRAMES frames long (every item's effect on two slots from its start to its
## end, the two flying shots, the three banner kinds, a line, the item pill, a box that pops), on a scratch rig. It lives in a SubViewport of its own (own World3D with its own camera, a sun and
## the round's environment; the same size, anti-aliasing and render settings as the window) so nothing of it can be seen, heard (its sounds are muted) or felt by the round: no mods, no camera
## sway, no HUD slot, no light on the course. Once per run: what is built stays built for as long as the process lives.
const Catalog := preload("res://modes/show/items/catalog.gd")
const ShowRules := preload("res://modes/show/items/items.gd")

const FRAMES := 52 ## frames the rehearsal runs for
const STEP := 0.14 ## s of the made-up clock per frame: the longest effect (FLIP, 7 s) is through in FRAMES
const FEET := Vector3(0.0, 0.0, 0.01) ## where the rehearsal's couriers stand (not the zero vector: that means "nobody there" to the looks)
const QUIET_DB := -80.0 ## the rehearsal's sounds
const SLOT_OTHER := 1 ## the made-up second slot's offset: the effects sit on the local player's slot (`mine`) and on this one's (a rival)

static var done := false ## once per run

var manager ## the real manager (items_view.gd)
var scratch ## the rehearsal manager
var _port: SubViewport
var _frame := 0
var _slots: Array = []
var _kinds: Array = [] ## [{id, kind, dur, a, b}]
var _events: Array = []
var _next_event := 1

## Starts the rehearsal for the set-up manager `real`; false when this machine draws nothing (headless) or already did it.
static func begin(real) -> bool:
	if done or DisplayServer.get_name() == "headless" or real.run == null: return false
	done = true
	var rehearsal = (load("res://modes/show/items_ui/items_rehearsal.gd") as GDScript).new()
	rehearsal.manager = real
	real.add_child(rehearsal)
	return true

func _ready() -> void:
	name = "ItemsRehearsal"
	var mine := maxi(int(manager.my_slot), 0)
	_slots = [mine, mine + SLOT_OTHER]
	var window: Viewport = manager.get_viewport()
	_port = SubViewport.new()
	_port.name = "Port"
	_port.size = Vector2i(window.get_visible_rect().size)
	_port.own_world_3d = true
	_port.world_3d = World3D.new()
	_port.world_3d.environment = window.world_3d.environment if window.world_3d != null else null
	_port.msaa_3d = window.msaa_3d
	_port.screen_space_aa = window.screen_space_aa
	_port.use_taa = window.use_taa
	_port.use_debanding = window.use_debanding
	_port.scaling_3d_mode = window.scaling_3d_mode
	_port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_port.gui_disable_input = true
	add_child(_port)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 3.0, 9.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.5, 0.0))
	_port.add_child(camera)
	camera.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60.0, 30.0, 0.0)
	sun.shadow_enabled = true
	_port.add_child(sun)
	scratch = (manager.get_script() as GDScript).new()
	scratch.rehearsal = true
	_port.add_child(scratch)
	scratch.setup(null, manager.run, mine, manager.seats)
	scratch._level = -1 # the made-up state says level -1: no boxes are built from a level
	var rig_script: GDScript = load("res://character/character_rig.gd")
	if not rig_script.call("available"): rig_script = load("res://courier/courier_rig.gd")
	var rig: Node3D = rig_script.new()
	rig.name = "RehearsalRig"
	_port.add_child(rig)
	rig.setup(mine)
	scratch.scratch_rig = rig
	scratch.add_rehearsal_box()
	for id: String in Catalog.KINDS:
		var look = scratch.look_of(id)
		if look == null or Catalog.off(id): continue
		var spec: Dictionary = look.rehearsal()
		_kinds.append({"id": id, "kind": Catalog.index(id), "dur": float(spec.dur), "a": float(spec.a), "b": float(spec.b)})

func _process(_delta: float) -> void:
	if manager == null or not is_instance_valid(manager):
		queue_free()
		return
	_frame += 1
	scratch.present({"level": -1, "items": _state(_frame)}, STEP)
	if _frame >= FRAMES:
		scratch.finish_rehearsal()
		queue_free()

## The made-up `items` state of frame `frame`: every effect from its start to its end on both slots, CALL's and FORCED VIDEO's shots in the air for a few frames, the box popping and growing back,
## the pill with an item (rolling, then landed), the banners (one of each kind: item, alert, boon) and a line.
func _state(frame: int) -> Dictionary:
	var clock := float(frame) * STEP
	var fx: Array = []
	var proj: Array = []
	for entry: Dictionary in _kinds:
		var kind := int(entry.kind)
		for index in _slots.size():
			if clock <= float(entry.dur):
				fx.append([9000 + kind * 10 + index, _slots[index], kind, float(entry.dur), minf(clock, float(entry.dur) - 0.01), float(entry.a), float(entry.b), -1])
		if (entry.id == "call" or entry.id == "dance") and frame >= 2 and frame < 14:
			var flown := float(frame - 2) * 0.4 # in from the left, ending at the other courier's chest (a hit)
			proj.append([9500 + kind, kind, -4.0 + flown, 1.0, 0.0, 6.0, 0.0, 0.0, _slots[1], float(frame - 2) * STEP])
	var banners := {"call": 4, "glitch": 8, "boost": 12}
	for entry: Dictionary in _kinds:
		if banners.has(entry.id) and frame == int(banners[entry.id]):
			_say(ShowRules.Event.HIT, int(entry.kind), -1, _slots[0])
		if entry.id == "call" and frame == 16: _say(ShowRules.Event.USE, int(entry.kind), _slots[1], _slots[0])
	var held := Catalog.index("call") if frame >= 24 and frame < 40 else -1
	var held_list: Array = []
	var spin_list: Array = []
	for slot in _slots[1] + 1:
		held_list.append(held if slot == _slots[0] else -1)
		spin_list.append(0.5 if slot == _slots[0] and frame < 30 else 0.0)
	return {"held": held_list, "spin": spin_list, "boxes": 0 if frame >= 8 and frame <= 20 else 1, "fx": fx, "proj": proj, "ev": _events.duplicate(true)}

func _say(type: int, kind: int, a: int, b: int) -> void:
	_events.append([_next_event, type, kind, a, b])
	_next_event += 1
