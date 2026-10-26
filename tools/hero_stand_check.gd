extends SceneTree
## Dev check of the hero props' stands in CROWN CLIMB (docs/hero-prop.md): a courier on the real level 16 collision walks into the summit stand
## and is stopped by the base tier (a step of 1 m is no 0.45 m step), then jumps up it tier by tier to the top; the same for a podium copy.
## Headless:
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 120 <Summer> --headless --audio-driver Dummy --path demo -s "$PWD/tools/hero_stand_check.gd"
## Prints HERO_STAND_CHECK lines and ok=<bool> last.
const LevelWorld := preload("res://levels/level_world.gd")
const Motion := preload("res://courier/courier_motion.gd")
const Hazards := preload("res://levels/hazards.gd")
const LEVEL := 15 ## 0-based: level_16.json
const DT := 1.0 / 60.0
var failures := 0
var world: Node3D
var origin := Vector3.ZERO

func _initialize() -> void:
	run.call_deferred()

func expect(condition: bool, label: String) -> void:
	if not condition: failures += 1
	print("HERO_STAND_CHECK ", "ok   " if condition else "FAIL ", label)

func run() -> void:
	world = LevelWorld.new()
	root.add_child(world)
	await world.build("authority")
	world.set_active_level(LEVEL)
	origin = world.level_origin(LEVEL)
	var data: Dictionary = world._levels[LEVEL].data
	var stands: Array = []
	for slot: Dictionary in data.slots:
		if slot.id == Hazards.HERO_SLOT: stands.append(slot)
	expect(not stands.is_empty(), "level 16 has hero_prop slots (%d)" % stands.size())
	for slot: Dictionary in stands: await climb(slot)
	print("HERO_STAND_CHECK ok=", failures == 0)
	quit(1 if failures > 0 else 0)

## Walks into the stand from the front (+Z), then climbs it: forward, a jump whenever it is stuck, until the courier stands on the top tier.
## A tier higher than a courier's step (0.45 m) stops the walk at the base tier; lower ones are stairs.
func climb(slot: Dictionary) -> void:
	var centre: Vector3 = slot.p
	var size: Vector2 = slot.size
	var tier_height := size.y / 3.0
	var label := "stand at %s" % [centre]
	var body := Motion.make_body("Courier")
	world.add_child(body)
	var motion := Motion.new()
	motion.setup(body)
	motion.reset(body, origin + centre + Vector3(0.0, 0.05, size.x * 0.5 + 2.5), 0.0)
	await settle(body, motion)
	expect(motion.grounded and absf(body.global_position.y - (origin.y + centre.y)) < 0.06, "%s: the courier stands on the floor beside it" % label)
	var top := origin.y + centre.y + size.y
	var highest := 0.0
	for chunk in 10: # walking in, no jump
		await drive(body, motion, {"move": Vector2(0.0, -1.0)}, 15)
		highest = maxf(highest, body.global_position.y - origin.y - centre.y)
	var stopped := body.global_position.z - (origin.z + centre.z)
	if tier_height > Motion.MAX_STEP + 0.1:
		var wanted := size.x * 0.5 + Motion.CAPSULE_RADIUS
		expect(absf(stopped - wanted) < 0.08 and highest < 0.06, "%s: walking in stops at the base tier (z %.2f from the middle, wanted %.2f)" % [label, stopped, wanted])
	else:
		expect(highest > size.y - 0.06, "%s: its low tiers are stairs a walk climbs (highest feet %.2f m up of %.2f)" % [label, highest, size.y])
		body.queue_free()
		return
	for chunk in 60: # forward, and a jump whenever it is stuck
		var before := body.global_position
		await drive(body, motion, {"move": Vector2(0.0, -1.0)}, 6)
		if motion.grounded and Vector2(body.global_position.x - before.x, body.global_position.z - before.z).length() < 0.02:
			await drive(body, motion, {"move": Vector2(0.0, -1.0), "jump": true}, 18)
		if motion.grounded and absf(body.global_position.y - top) < 0.06: break
	var reach := Vector2(body.global_position.x - (origin.x + centre.x), body.global_position.z - (origin.z + centre.z)).length()
	expect(motion.grounded and absf(body.global_position.y - top) < 0.06 and reach <= size.x / 6.0 + 0.2,
		"%s: jumped up to the top tier (feet y %.2f, wanted %.2f, %.2f m from the middle)" % [label, body.global_position.y - origin.y, top - origin.y, reach])
	body.queue_free()

func settle(body: CharacterBody3D, motion: RefCounted) -> void:
	await drive(body, motion, {}, 30)

func drive(body: CharacterBody3D, motion: RefCounted, input: Dictionary, count: int) -> void:
	for tick in count:
		await physics_frame
		motion.step(body, input, DT)
