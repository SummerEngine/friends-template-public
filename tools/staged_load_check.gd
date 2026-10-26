extends SceneTree
## Load check of a BUILT project (the staged hosted clone, not demo/): the level game loads through the real local shell
## (client/presentation_entry.gd, the code a client and the authority share), then prints one STAGED_LOAD_CHECK line with counts.
## Run headless, no frames; the pass criteria are in the engine log, grep it for SCRIPT ERROR / ERROR / Cannot open /
## Failed loading / not found (tools/staged_load_check.sh does exactly that):
##   Summer --headless --audio-driver Dummy --path analysis/staging/<label>/project --script tools/staged_load_check.gd
var sim: Node

func _initialize() -> void:
	go.call_deferred()

func go() -> void:
	sim = load("res://client/presentation_entry.gd").new()
	root.add_child(sim)
	current_scene = sim
	var started := Time.get_ticks_msec()
	while not sim.is_network_ready():
		await process_frame
		if Time.get_ticks_msec() > started + 240000:
			print("STAGED_LOAD_CHECK boot_timeout")
			quit(2)
			return
	for i in 60: await physics_frame
	# Enter the first and the last level (a level is an epoch at its start pad) and report where the couriers stand;
	# the course must name its levels and both must be playable (couriers on the ground, painting whole).
	var Course = load("res://course_section.gd")
	var level_report := []
	for level in [0, Course.level_count() - 1]:
		sim.set_course_plan(Course.plan(Course.default_course(), level))
		sim.configure_phase("level", [true, true])
		for i in 90: await physics_frame
		level_report.append({"level": level, "title": Course.level_title(level), "courier_x": snappedf(sim.actors[0].global_position.x, 0.1),
			"courier_y": snappedf(sim.actors[0].global_position.y, 0.01), "painting_broken": sim.painting.broken, "level_view": sim.level_world.active_level})
	print("STAGED_LOAD_CHECK_LEVELS ", JSON.stringify({"count": Course.level_count(), "entered": level_report}))
	var meshes := 0
	var null_meshes := 0
	var bodies := 0
	var shapes := 0
	for node: Node in sim.world.find_children("*", "", true, false):
		if node is MeshInstance3D:
			meshes += 1
			if node.mesh == null: null_meshes += 1
		elif node is CollisionObject3D:
			bodies += 1
		elif node is CollisionShape3D and node.shape != null:
			shapes += 1
	print("STAGED_LOAD_CHECK ", JSON.stringify({"levels": sim.level_world.level_count(), "mesh_instances": meshes, "null_meshes": null_meshes,
		"bodies": bodies, "shapes": shapes, "boot_ms": Time.get_ticks_msec() - started}))
	quit(0)
