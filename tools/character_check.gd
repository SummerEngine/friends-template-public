extends SceneTree
## Dev check of the skinned character (demo/character/, not shipped). Headless is fine.
## Builds the rig, steps idle / walk / jump / carry / emotes, checks the size and facing of the body, the hand reach against the
## painting grips (like tools/courier_check.gd), every catalog item and 20 random looks, the mouth (talk level, shouts,
## emotes), every slider at -1, 0 and +1 (the body reshapes, the feet stay on the
## ground, the hands still reach the painting grips, hats follow a head's HatSocket) and that no engine error was logged.
## Without a body model it checks the fallback instead: the game keeps the courier rig and a character rig without a body
## stays harmless. With a body but no head model yet the game keeps the courier too; the rig is checked anyway (the parts
## that need a head or the stand-in face parts are skipped with a note).
## Example (from the worktree root):
##   python3 ~/.claude/skills/engine-runs-summer/engine_run.py --timeout 900 -- <Summer> --headless --path demo -s $PWD/tools/character_check.gd
## Prints CHARACTER_CHECK ok/FAIL lines, CHARACTER_NUM numbers and exits 1 on any failure.
const Rig := preload("res://character/character_rig.gd")
const Catalog := preload("res://character/catalog.gd")
const Look := preload("res://character/look.gd")
const Painting := preload("res://game/painting.gd")
const TeamCast := preload("res://style/team_cast.gd")
const DT := 1.0 / 60.0

## Counts engine errors and warnings while the check runs.
class Counter extends Logger:
	var errors: Array = []
	var warnings: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		var text := "%s (%s:%d %s)" % [rationale if rationale != "" else code, file, line, function]
		if error_type == ERROR_TYPE_WARNING: warnings.append(text)
		else: errors.append(text)
	func _log_message(_message: String, _error: bool) -> void:
		pass

var world: Node3D
var failures := 0
var counter := Counter.new()

func _initialize() -> void:
	OS.add_logger(counter)
	run.call_deferred()

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	if Catalog.body_path() == "":
		check_without_body()
	else:
		if not Rig.available(): print("CHARACTER_CHECK note: no head model yet, the game keeps the courier; checking the rig anyway")
		check_catalog()
		if failures == 0:
			check_body()
			check_motion()
			check_carry()
			check_emotes()
			check_looks()
			check_mouth()
			check_slap()
			check_art_hooks()
			check_style_hook()
			check_soft_materials()
			check_face_items()
			check_hair_eyes()
			check_pupils()
			check_team_shirt()
			check_chest_print()
			check_team_color()
			check_first_person()
			check_params()
			check_look_sync()
	expect("no engine errors", counter.errors.is_empty(), str(counter.errors.slice(0, 8)))
	expect("no engine warnings", counter.warnings.is_empty(), str(counter.warnings.slice(0, 8)))
	print("CHARACTER_CHECK done failures=", failures)
	OS.remove_logger(counter)
	quit(1 if failures > 0 else 0)

# ------------------------------------------------------------------ no body model: the courier stays
func check_without_body() -> void:
	print("CHARACTER_CHECK no body model (character/models/", Catalog.data().get("body", ""), "): checking the fallback")
	expect("rig reports no body", not Rig.available())
	var rig := make_rig(0)
	rig.global_position = Vector3.ZERO
	rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0})
	stand(rig, 10, {"yaw": 0.0, "carrying": true}, [Vector3(-0.25, 1.1, -0.45), Vector3(0.25, 1.1, -0.45)])
	rig.set_look(Look.defaults_for_seat(1))
	rig.play_emote("dance")
	rig.set_talk_level(1.0)
	rig.set_slot_tint(2)
	expect("rig without a body stays harmless", rig.skeleton() == null and rig.hands_center().is_finite())
	world.remove_child(rig)
	rig.free()
	# the body warning is expected here, nothing else
	var others := counter.warnings.filter(func(w: String) -> bool: return not w.contains("Character body model not found"))
	counter.warnings = others
	print("CHARACTER_CHECK courier fallback: game/game_run.gd builds res://courier/courier_rig.gd")

## The character has a head: one in the body (the stand-in) or the default head's model.
func has_head() -> bool:
	var head := Catalog.item(Catalog.default_item("head"))
	return bool(Rig._shared.get("has_head", false)) or Catalog.resolve(str(head.get("file", ""))) != ""

func expect(name: String, ok: bool, detail := "") -> void:
	if not ok: failures += 1
	print("CHARACTER_CHECK ", "ok  " if ok else "FAIL", " ", name, " ", detail)

func make_rig(seat := 0) -> Node3D:
	var rig: Node3D = Rig.new()
	world.add_child(rig)
	rig.setup(seat)
	return rig

func stand(rig: Node3D, frames: int, state := {}, grips := []) -> void:
	var s := {"velocity": Vector3.ZERO, "grounded": true, "yaw": rig.global_rotation.y, "carrying": false}
	s.merge(state, true)
	for i in frames: rig.update(DT, s, grips)

# ------------------------------------------------------------------ catalog
func check_catalog() -> void:
	expect("catalog slots", Catalog.slots() == ["head", "hat", "hair", "eyes", "brows", "nose", "outfit", "shirt", "hand"], str(Catalog.slots()))
	var wanted := ["body_girth", "torso_girth", "neck_girth", "neck_length", "arm_length", "leg_length", "hand_size", "foot_size", "head_size", "head_length",
		"head_width", "head_height", "eye_size", "eye_spacing", "nose_size", "mouth_width", "ear_size", "hat_size", "hat_height", "hat_width", "hat_tilt",
		"wobble", "bounce", "swagger"]
	expect("catalog params", Catalog.param_ids() == wanted, str(Catalog.param_ids()))
	expect("catalog colour slots", Catalog.color_slots() == ["skin", "shirt", "pants", "shoes"], str(Catalog.color_slots()))
	var website := ["#E5484D", "#F76B15", "#FFC53D", "#46A758", "#12A594", "#00A2C7", "#3E63DD", "#8E4EC6", "#D6409F", "#8D6E63", "#F2EFE9", "#2B2B2B"]
	var main := Catalog.palette("main")
	var same := main.size() >= 12
	for i in mini(12, main.size()): same = same and main[i].is_equal_approx(Color.html(website[i]))
	expect("first 12 main colours are the website palette", same)
	expect("body model resolves", Catalog.body_path() != "", Catalog.body_path())
	var missing: Array = []
	var count := 0
	for slot in Catalog.slots():
		for entry in Catalog.items(slot):
			count += 1
			if str(entry["mode"]) == "attach" and str(entry.get("bone", "")) == "": missing.append(str(entry["id"]) + " (no bone)")
			if str(entry.get("file", "")) != "" and Catalog.resolve(entry["file"]) == "": missing.append(entry["id"])
	if not Catalog.left_out().is_empty(): print("CHARACTER_CHECK note: left out until their files land: ", Catalog.left_out())
	print("CHARACTER_NUM catalog items=", count)
	expect("the customizer only gets items whose files are there", missing.is_empty(), str(missing))
	var all_count := 0
	for slot in Catalog.slots(): all_count += Catalog.all_items(slot).size()
	var award_count := 0
	for slot in Catalog.slots(): award_count += Catalog.awards(slot).size()
	expect("looks still index every catalog item (awards included)", all_count == count + award_count + Catalog.left_out().size(), "%d = %d + %d + %d" % [all_count, count, award_count, Catalog.left_out().size()])
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var round_trip := true
	for i in 30:
		var look: CharacterLook = Look.new().randomized(rng)
		round_trip = round_trip and Look.from_bytes(look.to_bytes()).equals(look) and Look.from_dict(look.to_dict()).equals(look)
	expect("look bytes and dict round trip", round_trip)
	# players start as animals: one head per seat in its own skin colour, the seat's colour on the shirt
	var order: Array = Catalog.data().get("seat_heads", [])
	if Catalog.items("head").size() == order.size():
		var heads := []
		var skins_ok := true
		for seat in order.size() + 2:
			var start := Look.defaults_for_seat(seat)
			heads.append(start.items["head"])
			skins_ok = skins_ok and int(start.colors["skin"]) == int(Catalog.item(start.items["head"]).get("skin", -1)) \
				and int(start.colors["shirt"]) == Catalog.nearest("shirt", preload("res://style/team_cast.gd").player_color(seat))
		expect("seats start as animals (frog, bear, bird, cat, fish, bean, cycling) in their own skin", heads.slice(0, order.size()) == order \
			and heads[order.size()] == order[0] and order[0] == "head_frog" and Catalog.default_item("head") == "head_frog" and skins_ok, str(heads))
	else: print("CHARACTER_CHECK note: not every head model is here, so the seat heads are not checked")
	# no people: a head that reads as a person is never offered, and a look that names one (a cast, bytes, a dict, a rig) wears the seat's animal
	var people_ok := not Catalog.people_heads().is_empty() and Catalog.is_people("head_human_2")
	for entry in Catalog.items("head"): people_ok = people_ok and not Catalog.is_people(str(entry["id"]))
	for id in Catalog.data().get("seat_heads", []): people_ok = people_ok and not Catalog.is_people(str(id))
	for id in Catalog.people_heads(): people_ok = people_ok and not Catalog.items("head").any(func(entry: Dictionary) -> bool: return str(entry["id"]) == str(id))
	expect("no people heads are offered or start a seat", people_ok, str(Catalog.people_heads()))
	TeamCast.override({"format": "team-cast-v2", "team": {"name": "NoPeople"}, "players": [
		{"name": "Ana", "look": {"head": "head_human"}}, {"name": "Bo", "look": {"head": "head_potato"}}, {"name": "Cy", "look": {"head": "head_human_old"}}]})
	var mapped := [Look.defaults_for_seat(0), Look.defaults_for_seat(1), Look.defaults_for_seat(2)]
	TeamCast.override({})
	var people_look := Look.defaults_for_seat(0)
	people_look.items["head"] = "head_potato"
	var from_bytes_look := Look.from_bytes(people_look.to_bytes(), 4)
	var from_dict_look := Look.from_dict(people_look.to_dict(), 3)
	var rig_look: CharacterLook = people_look.animal_only(2)
	expect("a cast, bytes or a dict naming a people head gets the seat's animal, the same one every time", mapped[0].items["head"] == Catalog.seat_head(0) \
		and mapped[1].items["head"] == Catalog.seat_head(1) and mapped[2].items["head"] == Catalog.seat_head(2) and mapped[0].items["head"] != mapped[1].items["head"] \
		and from_bytes_look.items["head"] == Catalog.seat_head(4) and from_dict_look.items["head"] == Catalog.seat_head(3) and rig_look.items["head"] == Catalog.seat_head(2) \
		and int(from_dict_look.colors["skin"]) == int(Catalog.item(Catalog.seat_head(3)).get("skin", -1)) and not Catalog.is_people(str(Look.from_bytes(from_bytes_look.to_bytes(), 4).items["head"])), \
		str([mapped[0].items["head"], mapped[1].items["head"], mapped[2].items["head"], from_bytes_look.items["head"], from_dict_look.items["head"]]))
	# the cast picks a seat's items (players[i].look); "" empties a slot; unknown ids, ids of another slot and "" heads keep the seat's own
	var heads_here := Catalog.items("head")
	var pick := str(heads_here[1]["id"]) if heads_here.size() >= 2 else ""
	var hats_here := Catalog.items_for("hat", pick)
	if pick != "" and not hats_here.is_empty():
		var hat := str(hats_here[-1]["id"])
		TeamCast.override({"format": "team-cast-v2", "team": {"name": "Looks"}, "players": [
			{"name": "Ida", "look": {"head": pick, "hat": hat, "hand": "", "eyes": "no_such_eyes", "face": "eyes_big"}},
			{"name": "Theo", "look": {"head": hat, "shirt": 7}},
			{"name": "Maja", "look": {"head": ""}}]})
		var picked := Look.defaults_for_seat(0)
		var wrong_slot := Look.defaults_for_seat(1)
		var empty_head := Look.defaults_for_seat(2)
		TeamCast.override({})
		var eyes := str(picked.items["eyes"])
		var picked_ok: bool = picked.items["head"] == pick and picked.items["hat"] == hat and picked.items["hand"] == "" \
			and (eyes == "" or (Catalog.item(eyes).get("slot") == "eyes" and Catalog.fits(Catalog.item(eyes), pick))) \
			and int(picked.colors["skin"]) == int(Catalog.item(pick).get("skin", picked.colors["skin"]))
		expect("the cast picks a seat's head, hat and an empty hand; bad ids and empty heads keep the seat's own", picked_ok \
			and wrong_slot.items["head"] == Catalog.seat_head(1) and empty_head.items["head"] == Catalog.seat_head(2), str([picked.to_dict(), wrong_slot.items, empty_head.items]))
	var with_params: CharacterLook = Look.new().randomized(rng)
	for id in Catalog.param_ids(): with_params.set_param(id, rng.randf_range(-1.0, 1.0))
	with_params.set_param("arm_length", -1.0)
	with_params.set_param("leg_length", 1.0)
	var bytes := with_params.to_bytes()
	expect("look bytes carry every param (int8) and round-trip", bytes.size() == Look.byte_size() and Look.from_bytes(bytes).equals(with_params) \
		and Look.from_bytes(bytes).param("arm_length") == -1.0 and Look.valid_bytes(bytes), "%d bytes" % bytes.size())
	var broken := bytes.duplicate()
	broken[broken.size() - 1] = 0x80
	var short := bytes.slice(0, bytes.size() - 1)
	var wrong_colour := bytes.duplicate()
	wrong_colour[2] = 200
	expect("bad look bytes refused", not Look.valid_bytes(broken) and not Look.valid_bytes(short) and not Look.valid_bytes(wrong_colour))
	var probe_seat := 7
	var cfg := ConfigFile.new()
	var had_file := cfg.load(Look.SAVE_PATH) == OK
	if had_file and cfg.has_section("seat_%d" % probe_seat): cfg.erase_section("seat_%d" % probe_seat)
	if had_file: cfg.save(Look.SAVE_PATH)
	var before_save := Look.has_saved(probe_seat)
	var saved: CharacterLook = Look.new().randomized(rng)
	saved.save(probe_seat)
	expect("save, has_saved, load_saved", not before_save and Look.has_saved(probe_seat) and Look.load_saved(probe_seat).equals(saved))
	cfg = ConfigFile.new()
	cfg.load(Look.SAVE_PATH)
	cfg.erase_section("seat_%d" % probe_seat)
	cfg.save(Look.SAVE_PATH)

# ------------------------------------------------------------------ body
func check_body() -> void:
	var times: Array = []
	var again: Array = []
	var rigs: Array = []
	for i in 4:
		var t0 := Time.get_ticks_usec()
		rigs.append(make_rig(i))
		times.append(snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1))
	for i in 4: # the same seats again: body, heads and items are loaded now
		var t0 := Time.get_ticks_usec()
		rigs.append(make_rig(i))
		again.append(snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1))
	print("CHARACTER_NUM rig build ms (first time each seat's head and items load): ", times, " again: ", again)
	expect("rig build under 25 ms once its models are loaded", again.all(func(t): return t < 25.0), str(again))
	var rig: Node3D = rigs[0]
	var sk: Skeleton3D = rig.skeleton()
	expect("48 bones", sk != null and sk.get_bone_count() == 48, str(sk.get_bone_count() if sk else -1))
	rig.global_position = Vector3.ZERO
	rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0})
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in rig.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree() or mesh.skin == null: continue
		var box := mesh.global_transform * mesh.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	print("CHARACTER_NUM body bounds (rest) min y=", snappedf(bounds.position.y, 0.001), " max y=", snappedf(bounds.end.y, 0.001))
	expect("feet on the origin", absf(bounds.position.y) < 0.03, str(bounds.position.y))
	if has_head(): expect("about 1.8 m tall with its head", absf(bounds.end.y - Rig.HEIGHT) < 0.25, str(bounds.end.y))
	else: print("CHARACTER_CHECK note: no head model, so no height check (body top ", snappedf(bounds.end.y, 0.01), " m)")
	var foot := sk.find_bone("ORG_foot_L")
	var toe := sk.get_bone_children(foot)[0]
	var foot_w := sk.global_transform * sk.get_bone_global_pose(foot).origin
	var toe_w := sk.global_transform * sk.get_bone_global_pose(toe).origin
	expect("faces -Z", toe_w.z < foot_w.z, "foot z=%.3f toe z=%.3f" % [foot_w.z, toe_w.z])
	expect("left foot on -X", foot_w.x < 0.0, str(foot_w.x))
	expect("anchor = position + offset", rig.anchor().is_equal_approx(rig.global_position + Rig.ANCHOR_OFFSET))
	for other in rigs.slice(1):
		world.remove_child(other)
		other.free()

# ------------------------------------------------------------------ walk, jump, replica
func check_motion() -> void:
	var rig := make_rig(1)
	var stats := {"steps": [0, 0], "jumped": 0, "landed": []}
	rig.footstep.connect(func(side): stats["steps"][side] += 1)
	rig.jumped.connect(func(): stats["jumped"] += 1)
	rig.landed.connect(func(speed): stats["landed"].append(snappedf(speed, 0.1)))
	rig.global_position = Vector3.ZERO
	rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0})
	stand(rig, 60, {"yaw": 0.0})
	expect("idle: no steps", stats["steps"] == [0, 0], str(stats["steps"]))
	var speed := 5.0
	var t1 := Time.get_ticks_usec()
	for tick in 300:
		rig.global_position += Vector3(0, 0, -speed * DT)
		rig.update(DT, {"velocity": Vector3(0, 0, -speed), "grounded": true, "yaw": 0.0, "carrying": false, "acceleration": Vector3.ZERO})
	var per_update := (Time.get_ticks_usec() - t1) / 300.0
	print("CHARACTER_NUM walk update us/frame=", snappedf(per_update, 0.1), " steps L/R=", stats["steps"])
	expect("footsteps alternate while walking", stats["steps"][0] > 6 and absi(stats["steps"][0] - stats["steps"][1]) <= 1, str(stats["steps"]))
	expect("update under 1 ms", per_update < 1000.0, str(per_update))
	# sideways while facing ahead (carry walk)
	var side_steps := [stats["steps"][0], stats["steps"][1]]
	for tick in 120:
		rig.global_position += Vector3(2.5 * DT, 0, 0)
		rig.update(DT, {"velocity": Vector3(2.5, 0, 0), "grounded": true, "yaw": 0.0, "carrying": false})
	expect("sidestep makes steps", stats["steps"][0] + stats["steps"][1] > side_steps[0] + side_steps[1] + 2, str(stats["steps"]))
	# jump
	rig.global_position = Vector3.ZERO
	rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0})
	stand(rig, 30, {"yaw": 0.0})
	var vy := 7.0
	for tick in 60:
		vy -= 17.0 * DT
		rig.global_position.y = maxf(rig.global_position.y + vy * DT, 0.0)
		var grounded := rig.global_position.y <= 0.0 and vy < 0.0
		rig.update(DT, {"velocity": Vector3(0, vy, 0), "grounded": grounded, "yaw": 0.0})
		if grounded: vy = 0.0
	expect("jumped / landed signals", stats["jumped"] == 1 and stats["landed"].size() == 1 and stats["landed"][0] > 5.0, str(stats))
	# replica: velocity from movement alone
	var replica := make_rig(0)
	replica.set_replica(true)
	replica.global_position = Vector3(5, 0, 0)
	var replica_steps := {"n": 0}
	replica.footstep.connect(func(_s): replica_steps["n"] += 1)
	for tick in 120:
		replica.global_position += Vector3(0, 0, -3.0 * DT)
		replica.update(DT, {"grounded": true, "yaw": 0.0})
	expect("replica animates from movement alone", replica_steps["n"] >= 3, str(replica_steps["n"]))
	world.remove_child(replica)
	replica.free()
	world.remove_child(rig)
	rig.free()

# ------------------------------------------------------------------ carry: hands on the painting grips
func check_carry() -> void:
	var rig := make_rig(0)
	rig.global_position = Vector3.ZERO
	rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0, "carrying": true})
	var grips := [Vector3(-0.25, 1.1, -0.45), Vector3(0.25, 1.1, -0.45)]
	stand(rig, 90, {"yaw": 0.0, "carrying": true}, grips)
	var miss0: float = rig.hand_world(0).distance_to(grips[0])
	var miss1: float = rig.hand_world(1).distance_to(grips[1])
	print("CHARACTER_NUM fixed grips reach error (m) L/R=", snappedf(miss0, 0.0001), "/", snappedf(miss1, 0.0001), " hands_center=", rig.hands_center())
	expect("hands reach the fixed grips", miss0 < 0.02 and miss1 < 0.02)
	# the painting's own grips for both carriers, at its height and roll limits
	var worst := 0.0
	var a := Vector3(-1.75, 0.0, 0.0)
	var b := Vector3(1.75, 0.0, 0.0)
	var partner := make_rig(1)
	var carriers := [rig, partner]
	var feet := [a, b]
	var yaws := [-PI * 0.5, PI * 0.5] # each faces the other
	for height in [-0.4, 0.0, 0.4]:
		for roll in [-0.6, 0.0, 0.6]:
			var pose := Painting.pose_for(a + Rig.ANCHOR_OFFSET, b + Rig.ANCHOR_OFFSET, roll, height)
			for slot in 2:
				var carrier: Node3D = carriers[slot]
				carrier.global_position = feet[slot]
				var slot_grips := Painting.grips_for(pose, slot)
				carrier.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": yaws[slot], "carrying": true})
				stand(carrier, 40, {"yaw": yaws[slot], "carrying": true, "look_at": feet[1 - slot]}, slot_grips)
				for side in 2: worst = maxf(worst, carrier.hand_world(side).distance_to(slot_grips[side]))
	print("CHARACTER_NUM painting grips worst reach error (m)=", snappedf(worst, 0.0001))
	expect("hands reach the painting grips (height +-0.4 m, roll +-0.6)", worst < 0.02, str(worst))
	# carrying while walking keeps the grips
	rig.global_position = a
	var walk_worst := 0.0
	var pose0 := Painting.pose_for(a + Rig.ANCHOR_OFFSET, b + Rig.ANCHOR_OFFSET, 0.0, 0.0)
	for tick in 120:
		var shift := Vector3(0, 0, -2.0 * DT)
		rig.global_position += shift
		pose0.origin += shift
		var walk_grips := Painting.grips_for(pose0, 0)
		rig.update(DT, {"velocity": Vector3(0, 0, -2.0), "grounded": true, "yaw": yaws[0], "carrying": true}, walk_grips)
		if tick > 30: for side in 2: walk_worst = maxf(walk_worst, rig.hand_world(side).distance_to(walk_grips[side]))
	print("CHARACTER_NUM carry walk worst reach error (m)=", snappedf(walk_worst, 0.0001))
	expect("hands stay on the grips while walking sideways", walk_worst < 0.02, str(walk_worst))
	# without grips the hands rest in front of the anchor
	rig.global_position = Vector3.ZERO
	rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0, "carrying": true})
	stand(rig, 30, {"yaw": 0.0, "carrying": true})
	var centre: Vector3 = rig.to_local(rig.hands_center())
	expect("hands in front without grips", centre.z < -0.3 and absf(centre.y - Rig.ANCHOR_OFFSET.y) < 0.05, str(centre))
	world.remove_child(partner)
	partner.free()
	world.remove_child(rig)
	rig.free()

# ------------------------------------------------------------------ emotes
func check_emotes() -> void:
	var rig := make_rig(0)
	rig.global_position = Vector3.ZERO
	rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0})
	stand(rig, 30, {"yaw": 0.0})
	var still := pose_points(rig)
	var played: Array = []
	var moved := {}
	for name in ["dance", "sit", "yes", "no", "point", "think", "cry"]:
		rig.play_emote(name)
		var most := 0.0
		for i in 40:
			stand(rig, 1, {"yaw": 0.0})
			var points := pose_points(rig)
			for k in points.size(): most = maxf(most, points[k].distance_to(still[k]))
		if rig.emote_playing() == name: played.append(name)
		moved[name] = snappedf(most, 0.01)
		stand(rig, 200, {"yaw": 0.0})
	print("CHARACTER_NUM emote movement (m, hands/head/feet) ", moved)
	expect("every emote plays", played.size() == 7, str(played))
	expect("every emote moves the body", moved.values().all(func(m): return m > 0.05), str(moved))
	rig.play_emote("dance")
	stand(rig, 10, {"yaw": 0.0})
	rig.update(DT, {"velocity": Vector3(0, 0, -3.0), "grounded": true, "yaw": 0.0})
	expect("moving ends an emote", rig.emote_playing() == "")
	# the cast's emote for the player (players[i].emote): after IDLE_EMOTE_AFTER s standing still, once per stop; not while moving
	TeamCast.override({"format": "team-cast-v2", "team": {"name": "Emotes"}, "players": [{"name": "Ida", "emote": "think"}, {"name": "Theo", "emote": "flex"}]})
	rig.idle_emotes = true
	stand(rig, 30, {"yaw": 0.0})
	rig.update(DT, {"velocity": Vector3(0, 0, -3.0), "grounded": true, "yaw": 0.0})
	stand(rig, int(Rig.IDLE_EMOTE_AFTER / DT) - 20, {"yaw": 0.0})
	var early: String = rig.emote_playing()
	stand(rig, 40, {"yaw": 0.0})
	var idle: String = rig.emote_playing()
	var unknown := make_rig(1)
	var unknown_emote: String = unknown.cast_emote()
	unknown.free()
	TeamCast.override({})
	expect("standing still plays the cast's emote for the player; unknown ids play nothing", early == "" and idle == "think" and unknown_emote == "", "%s %s %s" % [early, idle, unknown_emote])
	world.remove_child(rig)
	rig.free()

# ------------------------------------------------------------------ sliders
func bone_world(rig: Node3D, bone_name: String) -> Vector3:
	var sk: Skeleton3D = rig.skeleton()
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone_name)).origin

func look_with(params: Dictionary, base: CharacterLook = null) -> CharacterLook:
	var look: CharacterLook = (base if base != null else Look.defaults_for_seat(0)).duplicate_look()
	look.params.clear()
	for id in params: look.set_param(id, params[id])
	return look

## Worst hand error on the painting grips (both carriers, painting height -0.4/0/+0.4) for a look.
func grip_error(look: CharacterLook) -> float:
	var a := Vector3(-1.75, 0.0, 0.0)
	var b := Vector3(1.75, 0.0, 0.0)
	var feet := [a, b]
	var yaws := [-PI * 0.5, PI * 0.5]
	var worst := 0.0
	var carriers := [make_rig(0), make_rig(1)]
	for slot in 2:
		carriers[slot].set_look(look)
		carriers[slot].global_position = feet[slot]
	for height in [-0.4, 0.0, 0.4]:
		var pose := Painting.pose_for(a + Rig.ANCHOR_OFFSET, b + Rig.ANCHOR_OFFSET, 0.0, height)
		for slot in 2:
			var grips := Painting.grips_for(pose, slot)
			carriers[slot].snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": yaws[slot], "carrying": true})
			stand(carriers[slot], 30, {"yaw": yaws[slot], "carrying": true}, grips)
			for side in 2: worst = maxf(worst, carriers[slot].hand_world(side).distance_to(grips[side]))
	for rig in carriers:
		world.remove_child(rig)
		rig.free()
	return worst

func check_params() -> void:
	var rig := make_rig(0)
	rig.global_position = Vector3.ZERO
	expect("rig lists the param ids", rig.param_ids() == Catalog.param_ids())
	var base := Look.defaults_for_seat(0)
	base.items["hat"] = "hat_beanie"
	rig.set_look(base)
	rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0})
	stand(rig, 20, {"yaw": 0.0})
	var plain := {"head": bone_world(rig, "head"), "foot": bone_world(rig, "ORG_foot_L"), "hand": rig.hand_world(0), "hat": (rig.find_child("Item_hat", true, false) as Node3D).transform}
	var changed := {}
	var grounded_worst := 0.0
	for id in Catalog.param_ids():
		var moved := 0.0
		for value in [-1.0, 1.0]:
			rig.set_look(look_with({id: value}, base))
			rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0})
			stand(rig, 20, {"yaw": 0.0})
			for i in 30: rig.update(DT, {"velocity": Vector3(0, 0, -4.0), "grounded": true, "yaw": 0.0}) # a little walk too (fun sliders)
			stand(rig, 20, {"yaw": 0.0})
			grounded_worst = maxf(grounded_worst, absf(bone_world(rig, "ORG_foot_L").y - (plain["foot"] as Vector3).y))
			var hat := rig.find_child("Item_hat", true, false) as Node3D
			moved = maxf(moved, bone_world(rig, "head").distance_to(plain["head"]))
			moved = maxf(moved, rig.hand_world(0).distance_to(plain["hand"]))
			if hat != null: moved = maxf(moved, (hat.transform.basis.get_scale() - (plain["hat"] as Transform3D).basis.get_scale()).length() + absf(hat.transform.basis.get_euler().x - (plain["hat"] as Transform3D).basis.get_euler().x))
			for part in ["eyes", "nose", "ears", "mouth", "eyelids"]:
				var mesh := part_mesh(rig, part)
				if mesh != null and mesh.mesh != null: moved = maxf(moved, mesh.mesh.get_aabb().size.length() * 0.0 + (1.0 if not rig._base_mesh.values().has(mesh.mesh) and not rig._part_mesh.values().has(mesh.mesh) else 0.0))
		changed[id] = snappedf(moved, 0.001)
	print("CHARACTER_NUM slider effect at -1/+1 (m, or 1 = a reshaped face part) ", changed)
	var faces := has_head() or ["eyes", "nose", "ears", "mouth", "eyelids"].any(func(part: String) -> bool: return part_mesh(rig, part) != null)
	if not faces: print("CHARACTER_CHECK note: no head and no face parts, so the face sliders have nothing to reshape")
	var still: Array = changed.keys().filter(func(id: String) -> bool: return float(changed[id]) <= 0.0 and not id in ["wobble", "bounce", "swagger"] \
		and (faces or str(Catalog.param(id).get("group", "")) != "face"))
	expect("every shape slider changes the character", still.is_empty(), str(still))
	expect("feet stay on the ground with every slider", grounded_worst < 0.03, str(grounded_worst))
	# longer legs lift the head, a bigger head is higher at the top
	rig.set_look(look_with({"leg_length": 1.0}, base))
	stand(rig, 20, {"yaw": 0.0})
	var tall := bone_world(rig, "head").y
	rig.set_look(look_with({"leg_length": -1.0}, base))
	stand(rig, 20, {"yaw": 0.0})
	var short := bone_world(rig, "head").y
	expect("leg length raises and lowers the body", tall - short > 0.15, "%.3f vs %.3f" % [tall, short])
	# fun sliders: bounce bobs the walk, wobble jiggles the head after a landing
	for id in ["bounce", "swagger", "wobble"]:
		var amounts := {}
		for value in [-1.0, 1.0]:
			rig.set_look(look_with({id: value}, base))
			rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0})
			var most := 0.0
			var vy := 6.0
			for tick in 120:
				var state := {"velocity": Vector3(0, 0, -4.0), "grounded": true, "yaw": 0.0}
				if id == "wobble":
					vy -= 17.0 * DT
					state = {"velocity": Vector3(0, vy, 0), "grounded": tick > 40, "yaw": 0.0}
				rig.update(DT, state)
				var head_tilt: float = rig.skeleton().get_bone_pose_rotation(rig.skeleton().find_bone("head")).angle_to(Quaternion.IDENTITY)
				most = maxf(most, absf(rig._bob) + absf(rig._sway) + (head_tilt if id == "wobble" else 0.0))
			amounts[value] = most
		expect("%s: -1 calmer than +1" % id, float(amounts[1.0]) > float(amounts[-1.0]) + 0.005, str(amounts))
	# hats sit on a head's HatSocket when it has one
	rig._hat_socket = Transform3D(Basis(), Vector3(0.0, 1.5, 0.05))
	var socket_look := look_with({}, base)
	socket_look.items["hat"] = "hat_cap"
	rig.set_look(socket_look)
	rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0})
	stand(rig, 5, {"yaw": 0.0})
	var hat_node := rig.find_child("Item_hat", true, false) as Node3D
	var sk: Skeleton3D = rig.skeleton()
	var jaw := sk.find_bone("ORG_jaw_upper")
	var socket_world := sk.global_transform * (sk.get_bone_global_pose(jaw) * (sk.get_bone_global_rest(jaw).affine_inverse() * Vector3(0.0, 1.5, 0.05)))
	expect("hats sit on the head's HatSocket", hat_node != null and hat_node.global_position.distance_to(socket_world) < 0.02, str(hat_node.global_position if hat_node else Vector3.ZERO) + " vs " + str(socket_world))
	rig._hat_socket = null
	world.remove_child(rig)
	rig.free()
	# hands still reach the painting grips at the extremes
	var reach := {}
	for id in ["arm_length", "leg_length", "body_girth", "torso_girth", "hand_size", "neck_length", "head_size"]:
		for value in [-1.0, 1.0]: reach["%s %+d" % [id, int(value)]] = snappedf(grip_error(look_with({id: value}, base)), 0.0001)
	var all_low := {}
	var all_high := {}
	for id in Catalog.param_ids():
		all_low[id] = -1.0
		all_high[id] = 1.0
	reach["all -1"] = snappedf(grip_error(look_with(all_low, base)), 0.0001)
	reach["all +1"] = snappedf(grip_error(look_with(all_high, base)), 0.0001)
	print("CHARACTER_NUM grip error at slider extremes (m) ", reach)
	expect("hands reach the painting grips at every slider extreme", reach.values().all(func(e: float) -> bool: return e < 0.02), str(reach))

# ------------------------------------------------------------------ art hooks
## What the art models rely on, checked with small stand-ins built here: surfaces named after a colour slot take that
## colour, an outfit hides the body meshes it lists, a HatSocket under a bone attachment, the cap's "logo" panel, face
## sliders on the head's own surfaces.
func check_art_hooks() -> void:
	var rig := make_rig(0)
	rig.global_position = Vector3.ZERO
	rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0})
	# a skinned mesh with a surface named "pants" takes the pants colour
	var cloth := StandardMaterial3D.new()
	cloth.resource_name = "pants"
	var box := BoxMesh.new()
	box.material = cloth
	var patch := ArrayMesh.new()
	patch.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
	patch.surface_set_material(0, cloth)
	var patch_node := MeshInstance3D.new()
	patch_node.mesh = patch
	rig.skeleton().add_child(patch_node)
	var look: CharacterLook = rig.get_look()
	look.colors["pants"] = 3
	rig.set_look(look)
	var tinted := patch_node.get_surface_override_material(0)
	expect("a surface named pants takes the pants colour", colour_of(tinted).is_equal_approx(Catalog.color("pants", 3)))
	patch_node.queue_free()
	# an outfit hides the body meshes it lists while worn (a stand-in outfit added to the catalog for this check)
	var data := Catalog.data()
	var shirt_mesh := part_mesh(rig, "shirt")
	var outfit_file := "items/outfit_hoodie.glb" if Catalog.resolve("items/outfit_hoodie.glb") != "" else "items/brows_bold.glb" # any skinned model
	var stand_in := {"id": "outfit_check", "slot": "outfit", "name": "Check", "mode": "skinned", "file": outfit_file, "hides": [str(shirt_mesh.name) if shirt_mesh else ""], "default": false}
	data["items"].append(stand_in)
	Catalog._index()
	look = rig.get_look()
	look.items["outfit"] = "outfit_check"
	rig.set_look(look)
	var hidden_worn := shirt_mesh != null and not shirt_mesh.visible and rig.find_child("Item_outfit", true, false) != null
	look.items["outfit"] = "outfit_tee"
	rig.set_look(look)
	expect("an outfit hides the body meshes it lists, and they come back", hidden_worn and shirt_mesh.visible and rig.find_child("Item_outfit", true, false) == null)
	data["items"].erase(stand_in)
	Catalog._index()
	# a HatSocket parented to a bone (imported under a BoneAttachment3D) reads as that bone's rest pose times its own
	var model := Node3D.new()
	var bones: Skeleton3D = rig.skeleton().duplicate()
	model.add_child(bones)
	var on_bone := BoneAttachment3D.new()
	bones.add_child(on_bone)
	on_bone.bone_name = "ORG_jaw_upper"
	var socket := Node3D.new()
	socket.name = "HatSocket"
	socket.transform = Transform3D(Basis(), Vector3(0.0, 0.0, 0.2))
	on_bone.add_child(socket)
	var read: Variant = Rig._socket_transform(model)
	var expected := bones.get_bone_global_rest(bones.find_bone("ORG_jaw_upper")) * socket.transform
	expect("HatSocket under a bone attachment", read is Transform3D and (read as Transform3D).is_equal_approx(expected), str(read))
	model.free()
	# the cap's "logo" surface shows the team picture
	var panel := StandardMaterial3D.new()
	panel.resource_name = "logo"
	var cap_mesh := ArrayMesh.new()
	cap_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
	cap_mesh.surface_set_material(0, panel)
	var cap := MeshInstance3D.new()
	cap.mesh = cap_mesh
	var picture := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	Rig._show_logo(cap, picture)
	var shown := cap.get_surface_override_material(0)
	expect("the logo panel shows the team picture", texture_of(shown) == picture)
	cap.free()
	# face sliders reshape only the head's own "eyes" surface
	var head_mesh := ArrayMesh.new()
	for material_name in ["skin", "eyes"]:
		var material := StandardMaterial3D.new()
		material.resource_name = material_name
		var sphere := SphereMesh.new()
		var arrays := sphere.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in verts.size(): verts[i] = verts[i] * (1.0 if material_name == "skin" else 0.1) + (Vector3.ZERO if material_name == "skin" else Vector3(0.2, 1.2, 0.3))
		arrays[Mesh.ARRAY_VERTEX] = verts
		head_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		head_mesh.surface_set_material(head_mesh.get_surface_count() - 1, material)
	var reshaped: Mesh = Rig._deformed(head_mesh, [[Catalog.param("eye_size"), 1.0, ["eyes"]]])
	var skin_same: bool = reshaped.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == head_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var eye_grew: bool = reshaped.get_aabb().size.length() >= head_mesh.get_aabb().size.length() and (reshaped.surface_get_arrays(1)[Mesh.ARRAY_VERTEX] as PackedVector3Array)[0] != (head_mesh.surface_get_arrays(1)[Mesh.ARRAY_VERTEX] as PackedVector3Array)[0]
	expect("face sliders reshape the head's eyes surface only", skin_same and eye_grew)
	# a head model's own "eyes" surface shows the worn eye picture; a nose worn on its own hides the head's nose surface
	var head_node := part_mesh(rig, "head")
	var made_head := head_node == null
	if made_head: # a body without a head (heads are items): a stand-in head mesh worn as the head item
		head_node = MeshInstance3D.new()
		rig.skeleton().add_child(head_node)
		rig._extras["head"] = head_node
	var own_head := head_node.mesh
	var head_look: CharacterLook = rig.get_look()
	var with_nose := ArrayMesh.new()
	for material_name in ["skin", "eyes", "nose", "pupils", "ears"]:
		var material := StandardMaterial3D.new()
		material.resource_name = material_name
		with_nose.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
		with_nose.surface_set_material(with_nose.get_surface_count() - 1, material)
	head_node.mesh = with_nose
	rig._base_mesh["head"] = with_nose
	var eye_items := Catalog.items("eyes").filter(func(entry: Dictionary) -> bool: return str(entry.get("file", "")) != "")
	var eye_item: Dictionary = eye_items[0] if not eye_items.is_empty() else {}
	head_look.items["eyes"] = str(eye_item.get("id", ""))
	rig.set_look(head_look)
	var eye_shown := head_node.get_surface_override_material(1)
	var picture_ok := eye_item.is_empty() or (texture_of(eye_shown) == load(Catalog.resolve(str(eye_item["file"]))) \
		and head_node.get_surface_override_material(3) == Rig._hidden_material())
	if eye_item.is_empty(): print("CHARACTER_CHECK note: no eye picture in the tree, so the head eyes picture is not checked")
	rig._extras["nose"] = MeshInstance3D.new()
	rig._dress_head()
	var nose_hidden := head_node.get_surface_override_material(2) == Rig._hidden_material()
	(rig._extras["nose"] as Node).free()
	rig._extras.erase("nose")
	rig._dress_head()
	var nose_back := head_node.get_surface_override_material(2) != Rig._hidden_material()
	expect("head eyes show the eye picture; a worn nose hides the head's nose and it comes back", picture_ok and nose_hidden and nose_back, "%s %s %s" % [picture_ok, nose_hidden, nose_back])
	var ears := head_node.get_surface_override_material(4)
	expect("head ears take the skin colour", colour_of(ears).is_equal_approx(Catalog.color("skin", int(head_look.colors["skin"]))))
	head_node.mesh = own_head
	rig._base_mesh["head"] = own_head
	if made_head:
		rig._extras.erase("head")
		rig._base_mesh.erase("head")
		head_node.free()
	world.remove_child(rig)
	rig.free()

# ------------------------------------------------------------------ the team shirt
## The Team shirt is always offered and is every player's default: white, the player's colour on the sleeve ends and collar
## (the body's shirt carries the trim distances in its vertex colours), the cast logo on the chest and the team name under it
## in dark ink (two lines when it is long). demo/cast/shirt_print.png replaces logo and name (still white, still
## trimmed). Other prints keep the player's shirt colour and no trim. (Small pictures are written for the check and removed.)
func check_team_shirt() -> void:
	expect("the Team shirt is always offered and is the default shirt", Catalog.items("shirt").any(func(entry: Dictionary) -> bool: return entry["id"] == "shirt_team") \
		and Catalog.default_item("shirt") == "shirt_team")
	var shirt_mesh: Mesh = Rig._shared.get("shirt_mesh")
	var fields: PackedColorArray = shirt_mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] if shirt_mesh != null else PackedColorArray()
	var sleeve_ends := 0
	var collar := 0
	for field in fields:
		if field.r * Rig.TRIM_RANGE < Rig.TRIM_SLEEVE: sleeve_ends += 1
		if field.g * Rig.TRIM_RANGE < Rig.TRIM_COLLAR: collar += 1
	expect("the body's shirt carries the trim distances (sleeve ends, collar)", sleeve_ends > 0 and collar > 0 and fields.size() > sleeve_ends + collar, "%d points: %d at sleeve ends, %d at the collar" % [fields.size(), sleeve_ends, collar])
	var made := []
	var logo_path := "res://cast/check_logo.png"
	var picture := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	picture.fill(Color(0.9, 0.2, 0.3))
	picture.save_png(logo_path)
	made.append(logo_path)
	var cast: Dictionary = TeamCast.data().duplicate(true)
	if cast.is_empty(): cast = {"format": "team-cast-v2"}
	cast["team"] = {"name": "ACME", "tagline": "Four friends, one painting, never drop it"}
	cast["brand"] = {"logo": "check_logo.png"}
	TeamCast.override(cast)
	var print_path := "res://cast/shirt_print.png"
	var own_print := Catalog.cast_shirt() != ""
	if own_print: # the cast has its own picture: the built shirt is not checked
		print("CHARACTER_CHECK note: the cast has shirt_print, so the shirt built from logo and name is not checked")
	else:
		var built := shirt_on(6, "shirt_team")
		var logo_rect: Vector4 = built.get_shader_parameter("logo_rect")
		var motto_rect: Vector4 = built.get_shader_parameter("motto_rect")
		var ink: Color = built.get_shader_parameter("motto_ink")
		expect("the Team shirt is white, trimmed in the player's colour, with the logo above the team name in dark ink", \
			colour_of(built).is_equal_approx(Color.WHITE) and float(built.get_shader_parameter("trim")) == 1.0 \
			and (built.get_shader_parameter("trim_color") as Color).is_equal_approx(Catalog.color("shirt", 6)) \
			and built.get_shader_parameter("logo_tex") is Texture2D and built.get_shader_parameter("motto_tex") is Texture2D \
			and logo_rect.z > 0.0 and motto_rect.z > 0.0 and logo_rect.y + logo_rect.w <= motto_rect.y and ink.get_luminance() < 0.2, \
			"logo %s motto %s ink %s" % [logo_rect, motto_rect, ink])
		expect("the Team shirt's motto is the team name in capitals", Rig._motto() == "ACME", Rig._motto())
		var cut := Rig._motto_image("Six bakers · one oven · first to the crown")
		var split := Rig._unbound("· first to the crown")
		expect("a motto cut at a separator never starts or ends a line with it", split == "first to the crown" and Rig._unbound("Six bakers ·") == "Six bakers" and cut != null, split)
		var words := Rig._motto_image("Four friends, one painting, never drop it")
		var line := Rig.MOTTO_FONT.get_height(Rig.MOTTO_SIZE)
		var used := words.get_used_rect() if words != null else Rect2i()
		expect("a long motto is drawn in two lines of letters", words != null and used.size.x > words.get_width() * 0.6 and used.size.y > line * 1.3, "image %s used %s line %.0f" % [words.get_size() if words != null else Vector2i.ZERO, used, line])
		picture.save_png(print_path)
		made.append(print_path)
	var printed := shirt_on(6, "shirt_team")
	expect("the cast's shirt_print.png is printed on the white, trimmed Team shirt instead of logo and name", printed.get_shader_parameter("print_tex") is Texture2D \
		and colour_of(printed).is_equal_approx(Color.WHITE) and float(printed.get_shader_parameter("trim")) == 1.0 \
		and printed.get_shader_parameter("logo_tex") == null and printed.get_shader_parameter("motto_tex") == null)
	var stripes := shirt_on(6, "shirt_stripes")
	expect("other prints keep the player's shirt colour, without trim", stripes != null and colour_of(stripes).is_equal_approx(Catalog.color("shirt", 6)) \
		and stripes.get_shader_parameter("trim") in [null, 0.0])
	TeamCast.override({})
	for path in made: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## The shirt material of a fresh seat 0 character in shirt colour `color` wearing the shirt `id`.
func shirt_on(color: int, id: String) -> ShaderMaterial:
	var rig := make_rig(0)
	var look: CharacterLook = rig.get_look()
	look.items["shirt"] = id
	look.colors["shirt"] = color
	rig.set_look(look)
	var material := part_mesh(rig, "shirt").get_surface_override_material(0) as ShaderMaterial
	world.remove_child(rig)
	rig.free()
	return material

# ------------------------------------------------------------------ the chest print
## The team shirt's chest print (logo and motto) is the same for every seat: the same picture, place and size on the same
## shirt. On every outfit it is upright and not mirrored (seen from the front its right is the character's left, its top is
## up) and nothing of the outfit covers it (a hoodie's cords), or the outfit leaves it off (overalls' bib).
func check_chest_print() -> void:
	var logo_path := "res://cast/check_logo.png"
	var picture := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	picture.fill(Color(1.0, 0.4, 0.0))
	picture.save_png(logo_path)
	var cast: Dictionary = TeamCast.data().duplicate(true)
	if cast.is_empty(): cast = {"format": "team-cast-v2"}
	cast["team"] = {"name": "ACME", "tagline": "Make something people want"}
	cast["brand"] = {"logo": "check_logo.png"}
	TeamCast.override(cast)
	if Catalog.cast_shirt() != "":
		print("CHARACTER_CHECK note: the cast has shirt_print, so the chest print is not checked")
	else:
		var prints := []
		for seat in (Catalog.data().get("seat_heads", []) as Array).size():
			var rig := make_rig(seat)
			var shirt := part_mesh(rig, "shirt")
			var material := shirt.get_surface_override_material(0) as ShaderMaterial
			prints.append([shirt.mesh, material.get_shader_parameter("logo_tex"), material.get_shader_parameter("logo_rect"), material.get_shader_parameter("motto_rect"), material.get_shader_parameter("chest_move")])
			world.remove_child(rig)
			rig.free()
		expect("every seat's team shirt has the same chest print (picture, place, size)", prints.all(func(row: Array) -> bool: return str(row) == str(prints[0])) and prints[0][1] != null, str(prints[0]))
		var results := {}
		for entry in Catalog.items("outfit"):
			var rig := make_rig(0)
			var look: CharacterLook = rig.get_look()
			look.items["outfit"] = entry["id"]
			rig.set_look(look)
			var worn := rig.find_child("Item_outfit", true, false) as MeshInstance3D
			var shirt := worn if worn != null and Rig._surface_name(worn.mesh.surface_get_material(0)) == "shirt" else part_mesh(rig, "shirt")
			results[entry["id"]] = chest_print_on(shirt, worn, float((entry.get("chest", [0, 0, 1]) as Array)[2]) if entry.has("chest") else 1.0)
			world.remove_child(rig)
			rig.free()
		print("CHARACTER_NUM chest print per outfit (logo width m, upright, covered points) ", results)
		var tee: Dictionary = results.get("outfit_tee", {})
		expect("the chest print is upright and unmirrored on every outfit, never covered by the outfit, or left off", results.values().all(func(row: Dictionary) -> bool:
			return (row.get("off", false) and row.get("expected", false)) or (not row.get("off", false) and row["upright"] and row["covered"] == 0 and float(row["width"]) > 0.4 * float(tee.get("width", 1.0)))), str(results))
	TeamCast.override({})
	DirAccess.remove_absolute(ProjectSettings.globalize_path(logo_path))

## Where `shirt`'s chest print lands (rest pose, front only): the logo's width in body units, whether it is upright and
## unmirrored, and how many points of `outfit`'s other surfaces lie over the logo and motto. {"off": true} without a print.
func chest_print_on(shirt: MeshInstance3D, outfit: MeshInstance3D, scale: float) -> Dictionary:
	var surface := 0
	for i in shirt.mesh.get_surface_count():
		if Rig._surface_name(shirt.mesh.surface_get_material(i)) == "shirt": surface = i
	var material := shirt.get_surface_override_material(surface) as ShaderMaterial
	if material == null or material.get_shader_parameter("logo_tex") == null: return {"off": true, "expected": scale <= 0.0}
	var move: Vector3 = material.get_shader_parameter("chest_move") if material.get_shader_parameter("chest_move") != null else Vector3(0, 0, 1)
	var pivot: Vector2 = material.get_shader_parameter("chest_pivot")
	var logo_rect: Vector4 = material.get_shader_parameter("logo_rect")
	var motto_rect: Vector4 = material.get_shader_parameter("motto_rect")
	var inside := func(uv: Vector2, rect: Vector4) -> bool: return uv.x >= rect.x and uv.y >= rect.y and uv.x <= rect.x + rect.z and uv.y <= rect.y + rect.w
	var arrays := shirt.mesh.surface_get_arrays(surface)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var corners: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var logo_points := []
	var area := AABB()
	var first := true
	for i in range(0, corners.size() - 2, 3):
		for a in 5:
			for b in 5 - a:
				var w := Vector3(a, b, 4 - a - b) / 4.0
				var point := points[corners[i]] * w.x + points[corners[i + 1]] * w.y + points[corners[i + 2]] * w.z
				if point.z <= 0.0: continue
				var uv := uvs[corners[i]] * w.x + uvs[corners[i + 1]] * w.y + uvs[corners[i + 2]] * w.z
				var printed := (uv - pivot - Vector2(move.x, move.y)) / move.z + pivot
				var on_logo: bool = inside.call(printed, logo_rect)
				if on_logo: logo_points.append([point, printed])
				if on_logo or (motto_rect.z > 0.0 and inside.call(printed, motto_rect)):
					area = AABB(point, Vector3.ZERO) if first else area.expand(point)
					first = false
	if logo_points.is_empty(): return {"off": true, "expected": false}
	var mean_point := Vector3.ZERO
	var mean_uv := Vector2.ZERO
	for row in logo_points:
		mean_point += row[0]
		mean_uv += row[1]
	mean_point /= logo_points.size()
	mean_uv /= logo_points.size()
	var along_x := 0.0
	var along_y := 0.0
	var low := INF
	var high := -INF
	for row in logo_points:
		along_x += ((row[1] as Vector2).x - mean_uv.x) * ((row[0] as Vector3).x - mean_point.x)
		along_y += ((row[1] as Vector2).y - mean_uv.y) * ((row[0] as Vector3).y - mean_point.y)
		low = minf(low, (row[0] as Vector3).x)
		high = maxf(high, (row[0] as Vector3).x)
	var covered := 0
	if outfit != null and outfit.mesh != null:
		for i in outfit.mesh.get_surface_count():
			if Rig._surface_name(outfit.mesh.surface_get_material(i)) == "shirt": continue
			for point in (outfit.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				if point.x > area.position.x and point.x < area.end.x and point.y > area.position.y and point.y < area.end.y and point.z > area.position.z - 0.005: covered += 1
	return {"width": snappedf(high - low, 0.001), "upright": along_x > 0.0 and along_y < 0.0, "covered": covered}

# ------------------------------------------------------------------ team colour on items
## The cap's surfaces named "team_color" (crown, bill, button) take the cast's first brand colour (#FF6600 here: orange);
## without brand colours they take the player's shirt colour. Its other surfaces keep their own colours.
func check_team_color() -> void:
	var cast: Dictionary = TeamCast.data().duplicate(true)
	if cast.is_empty(): cast = {"format": "team-cast-v2"}
	var results := {}
	for colors in [["#FF6600"], []]:
		cast["brand"] = {"colors": colors}
		TeamCast.override(cast)
		var rig := make_rig(0)
		var look: CharacterLook = rig.get_look()
		look.items["hat"] = "hat_cap"
		rig.set_look(look)
		var team := []
		var other := []
		var hat := rig.find_child("Item_hat", true, false)
		for mesh: MeshInstance3D in (hat.find_children("*", "MeshInstance3D", true, false) if hat != null else []):
			for surface in mesh.mesh.get_surface_count():
				var shown := colour_of(mesh.get_surface_override_material(surface)).to_html(false)
				if Rig._surface_name(mesh.mesh.surface_get_material(surface)) == "team_color": team.append(shown)
				else: other.append(shown)
		results["brand" if not colors.is_empty() else "shirt " + Catalog.color("shirt", int(look.colors["shirt"])).to_html(false)] = [team, other]
		world.remove_child(rig)
		rig.free()
	TeamCast.override({})
	var shirt_key: String = results.keys()[1]
	var brand_team: Array = results["brand"][0]
	var shirt_team: Array = results[shirt_key][0]
	expect("with brand colour #FF6600 the cap is orange; without, it takes the shirt colour", not brand_team.is_empty() \
		and brand_team.all(func(c: String) -> bool: return c == "ff6600") and not shirt_team.is_empty() \
		and shirt_team.all(func(c: String) -> bool: return c == shirt_key.get_slice(" ", 1)) and not "ff6600" in results["brand"][1], str(results))

# ------------------------------------------------------------------ first person
## set_first_person: the own camera draws only the view arms (the body's arm and hand triangles and the hand item, on a
## skeleton of their own under the camera); other cameras keep the whole character. Idle: the right palm low-right in
## view, the hand about a fifth of the screen wide. Turns: the arms lag, then catch up. Carrying: the palms on the grips.
## Slap: the palm sweeps across the lower third, right to left, in about 0.2 s. The voice still opens the body's jaw.
## Off: the layers and the camera's mask come back.
func check_first_person() -> void:
	var rig := make_rig(0)
	var look: CharacterLook = rig.get_look()
	look.items["hand"] = "hand_hammer"
	rig.set_look(look)
	stand(rig, 2)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 80.0
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-12.0), 0.0, 0.0)), Vector3(0.0, 1.2, -0.18))
	var layers_before: int = (rig.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).layers
	rig.set_first_person(true, camera)
	stand(rig, 30)
	var body_bit := 1 << Rig.FP_BODY_FIRST_BIT
	var view_bit := 1 << Rig.FP_VIEW_FIRST_BIT
	var body_meshes := rig.find_children("*", "MeshInstance3D", true, false)
	var view_root := camera.find_child("FirstPersonArms0", false, false)
	var view_meshes := view_root.find_children("*", "MeshInstance3D", true, false) if view_root != null else []
	var triangles := func(meshes: Array) -> int:
		var count := 0
		for mesh: MeshInstance3D in meshes:
			if mesh.mesh is ArrayMesh and mesh.get_parent() is Skeleton3D:
				for surface in mesh.mesh.get_surface_count(): count += (mesh.mesh as ArrayMesh).surface_get_array_index_len(surface) / 3
		return count
	var arm_triangles: int = triangles.call(view_meshes)
	var held := view_meshes.any(func(mesh: Node) -> bool: return not (mesh.get_parent() is Skeleton3D))
	var other := Camera3D.new()
	var other_mask := other.cull_mask
	other.free()
	expect("first person: the own camera draws only the view arms (and the held item), other cameras the whole character", \
		body_meshes.all(func(mesh: MeshInstance3D) -> bool: return mesh.layers == body_bit) and camera.cull_mask & body_bit == 0 and camera.cull_mask & view_bit != 0 \
		and not view_meshes.is_empty() and view_meshes.all(func(mesh: MeshInstance3D) -> bool: return mesh.layers == view_bit and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF) \
		and arm_triangles > 0 and arm_triangles < int(triangles.call(body_meshes)) / 2 and held and other_mask & view_bit == 0 and other_mask & body_bit != 0, \
		"arm triangles %d of %d, %d view meshes" % [arm_triangles, triangles.call(body_meshes), view_meshes.size()])
	var palms: Array = rig.first_person_hands_world()
	var right := on_screen(camera, palms[1])
	var sk: Skeleton3D = (view_root.find_child("Skeleton", false, false) as Skeleton3D)
	var hand_bone := sk.find_bone("ORG_hand_R")
	var tip := sk.find_bone("ORG_finger_B_03_R")
	var hand_length := (sk.global_transform * sk.get_bone_global_pose(hand_bone).origin).distance_to(sk.global_transform * sk.get_bone_global_pose(tip).origin) if tip >= 0 else 0.0
	var screen_width := 2.0 * right.z * tan(deg_to_rad(camera.fov) * 0.5) * 16.0 / 9.0
	print("CHARACTER_NUM first person idle: right palm on screen (x, y -1..1) %s, hand %.2f of the screen width" % [Vector2(right.x, right.y), hand_length / screen_width])
	expect("first person idle: the right palm is in view, low right, the hand about a fifth of the screen wide", right.z > 0.15 and right.x > 0.15 and right.x < 0.95 \
		and right.y < -0.3 and right.y > -1.0 and hand_length / screen_width > 0.1 and hand_length / screen_width < 0.4, str(right))
	camera.rotate_y(deg_to_rad(30.0))
	stand(rig, 1)
	var lag := (view_root as Node3D).basis.get_rotation_quaternion().get_angle()
	stand(rig, 40)
	var caught := (view_root as Node3D).basis.get_rotation_quaternion().get_angle()
	camera.rotate_y(deg_to_rad(-30.0))
	stand(rig, 40)
	expect("first person: the arms lag a camera turn, then catch up", lag > 0.1 and caught < 0.02, "%.3f -> %.3f rad" % [lag, caught])
	var grips := [camera.global_transform * Vector3(-0.2, -0.3, -0.5), camera.global_transform * Vector3(0.2, -0.3, -0.5)]
	stand(rig, 45, {"carrying": true}, grips)
	palms = rig.first_person_hands_world()
	var miss := maxf((palms[0] as Vector3).distance_to(grips[0]), (palms[1] as Vector3).distance_to(grips[1]))
	expect("first person carrying: the palms hold the grips", miss < 0.03, "%.3f m" % miss)
	# the game's carry eye: 1.5 m high, 0.45 m behind the carrier; the grips 0.25 m ahead, 0.5 m apart, at 1.1 m
	var eye_before := camera.global_transform
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-12.0), 0.0, 0.0)), Vector3(0.0, 1.5, 0.45))
	grips = [Vector3(-0.25, 1.1, -0.25), Vector3(0.25, 1.1, -0.25)]
	stand(rig, 45, {"carrying": true}, grips)
	palms = rig.first_person_hands_world()
	miss = maxf((palms[0] as Vector3).distance_to(grips[0]), (palms[1] as Vector3).distance_to(grips[1]))
	var sleeves := [] # half way down the upper arm: the end of a tee's sleeve
	for side_name in ["L", "R"]:
		var shoulder := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("ORG_arm_" + side_name)).origin
		var elbow := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("ORG_forearm_" + side_name)).origin
		sleeves.append(on_screen(camera, shoulder.lerp(elbow, 0.5)))
	var hands_seen := [on_screen(camera, palms[0]), on_screen(camera, palms[1])]
	expect("first person carrying at the carry eye: palms on the grips in the lower half, the sleeves below the view", miss < 0.03 \
		and sleeves.all(func(point: Vector3) -> bool: return point.y < -1.0 or point.z < 0.0) and hands_seen.all(func(point: Vector3) -> bool: return point.y < 0.0 and point.y > -1.0), \
		"miss %.3f m, sleeve ends %s, palms %s" % [miss, sleeves, hands_seen])
	camera.global_transform = eye_before
	stand(rig, 30)
	rig.slap(1)
	var path := []
	for i in 18:
		stand(rig, 1)
		path.append(on_screen(camera, rig.first_person_hands_world()[1]))
	var start: Vector3 = path[1]
	var at_hit: Vector3 = path[11] # 0.2 s in
	var low := path.slice(0, 13).all(func(point: Vector3) -> bool: return point.y < -0.15)
	expect("first person slap: the palm sweeps across the lower third, right to left, in about 0.2 s", start.x > 0.3 and at_hit.x < -0.1 and low, "%s -> %s" % [start, at_hit])
	stand(rig, 30)
	var closed := jaw_turn(rig)
	rig.set_talk_level(1.0)
	stand(rig, 20)
	expect("first person: the voice still opens the body's jaw for the others", jaw_turn(rig) > closed + 0.05, "%.3f -> %.3f" % [closed, jaw_turn(rig)])
	rig.set_talk_level(0.0)
	rig.set_first_person(false)
	expect("first person off: the layers and the camera's mask come back", not rig.first_person() and camera.cull_mask & view_bit == 0 and camera.cull_mask & body_bit != 0 \
		and rig.find_children("*", "MeshInstance3D", true, false).all(func(mesh: MeshInstance3D) -> bool: return mesh.layers == layers_before) and view_root.is_queued_for_deletion())
	world.remove_child(rig)
	rig.free()
	camera.free()

## `point` seen from `camera`: x and y on the screen (-1..1, y up, 16:9) and z its distance in front.
func on_screen(camera: Camera3D, point: Vector3) -> Vector3:
	var local := camera.global_transform.affine_inverse() * point
	var half := tan(deg_to_rad(camera.fov) * 0.5)
	return Vector3(local.x / (-local.z * half * 16.0 / 9.0), local.y / (-local.z * half), -local.z)

# ------------------------------------------------------------------ face items on a head
## A worn nose hides only the head's own nose, a worn brow only its brows (with the first head that has nose and brow items).
func check_face_items() -> void:
	var head_id := ""
	var nose_items := []
	var brow_items := []
	for entry in Catalog.items("head"):
		nose_items = Catalog.items_for("nose", entry["id"]).filter(func(item: Dictionary) -> bool: return str(item.get("file", "")) != "")
		brow_items = Catalog.items_for("brows", entry["id"]).filter(func(item: Dictionary) -> bool: return str(item.get("file", "")) != "")
		if not nose_items.is_empty() and not brow_items.is_empty():
			head_id = entry["id"]
			break
	if head_id == "":
		print("CHARACTER_CHECK note: no head with nose and brow items in the catalog, so face items are not checked")
		return
	var rig := make_rig(0)
	var results := {}
	for pair in [[nose_items[0]["id"], "brows_classic"], ["nose_classic", brow_items[0]["id"]], [nose_items[0]["id"], brow_items[0]["id"]], ["nose_classic", "brows_classic"]]:
		var look: CharacterLook = rig.get_look()
		look.items["head"] = head_id
		look.items["nose"] = pair[0]
		look.items["brows"] = pair[1]
		rig.set_look(look)
		var head := rig.find_child("Item_head", true, false) as MeshInstance3D
		var hidden := []
		for surface in head.mesh.get_surface_count():
			if head.get_surface_override_material(surface) == Rig._hidden_material(): hidden.append(Rig._surface_name(head.mesh.surface_get_material(surface)))
		results["%s+%s" % pair] = hidden
	var expected := [["nose"], ["brows"], ["nose", "brows"], []]
	var got := results.values()
	var ok := true
	for i in 4: ok = ok and got[i].size() == expected[i].size() and expected[i].all(func(name: String) -> bool: return name in got[i])
	expect("a worn nose hides only the head's nose, a worn brow only its brows", ok, str(results))
	world.remove_child(rig)
	rig.free()

# ------------------------------------------------------------------ hair, hats and eyes
## Seen from the front, no hair item covers any of a head's eyes and no hat more than a sliver (the frog's eyes sit on top
## of its head): every head with every hair and hat that fits it, in the rest pose.
func check_hair_eyes() -> void:
	var rig := make_rig(0)
	var covered := {}
	var tested := 0
	for head in Catalog.items("head"):
		for slot in ["hair", "hat"]:
			for item in Catalog.items_for(slot, head["id"]):
				if str(item.get("file", "")) == "": continue
				var look: CharacterLook = rig.get_look()
				look.items["head"] = head["id"]
				look.items["hair"] = item["id"] if slot == "hair" else ""
				look.items["hat"] = item["id"] if slot == "hat" else ""
				rig.set_look(look)
				var share := eyes_covered(rig, rig.find_child("Item_" + slot, true, false))
				tested += 1
				if share > (0.0 if slot == "hair" else 0.02): covered["%s+%s" % [head["id"], item["id"]]] = snappedf(share, 0.001)
	expect("no hair covers a head's eyes from the front, no hat more than a sliver (%d pairs)" % tested, tested > 0 and covered.is_empty(), str(covered))
	world.remove_child(rig)
	rig.free()

## The share of the worn head's eyes (its "eyes" surface, front half) that `item` hides from the front, rest pose.
func eyes_covered(rig: Node3D, item: Node) -> float:
	var head := rig.find_child("Item_head", true, false) as MeshInstance3D
	if head == null or item == null: return 0.0
	var sk: Skeleton3D = rig.skeleton()
	var to_rig := rig.global_transform.affine_inverse()
	var eyes := PackedVector3Array()
	for surface in head.mesh.get_surface_count():
		if Rig._surface_name(head.mesh.surface_get_material(surface)) != "eyes": continue
		var arrays := head.mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var corners: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in range(0, corners.size() - 2, 3):
			for w in [Vector3(1, 1, 1) / 3.0, Vector3(4, 1, 1) / 6.0, Vector3(1, 4, 1) / 6.0, Vector3(1, 1, 4) / 6.0]:
				eyes.append(to_rig * (sk.global_transform * (points[corners[i]] * w.x + points[corners[i + 1]] * w.y + points[corners[i + 2]] * w.z)))
	if eyes.is_empty(): return 0.0
	var middle := 0.0
	for point in eyes: middle += point.z
	middle /= eyes.size()
	var front := Array(eyes).filter(func(point: Vector3) -> bool: return point.z < middle) # the character faces -Z
	var hidden := {}
	for mesh: MeshInstance3D in item.find_children("*", "MeshInstance3D", true, false) + ([item] if item is MeshInstance3D else []):
		var to_item := to_rig * sk.global_transform * rest_transform(mesh, sk)
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var corners: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(points.size()))
			for i in range(0, corners.size() - 2, 3):
				var a := to_item * points[corners[i]]
				var b := to_item * points[corners[i + 1]]
				var c := to_item * points[corners[i + 2]]
				for k in front.size():
					if hidden.has(k): continue
					var point: Vector3 = front[k]
					var area := (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
					if absf(area) < 1e-9: continue
					var u := ((b.x - point.x) * (c.y - point.y) - (c.x - point.x) * (b.y - point.y)) / area
					var v := ((c.x - point.x) * (a.y - point.y) - (a.x - point.x) * (c.y - point.y)) / area
					var t := 1.0 - u - v
					if u < 0.0 or v < 0.0 or t < 0.0: continue
					if a.z * u + b.z * v + c.z * t < point.z - 0.002: hidden[k] = true
	return float(hidden.size()) / front.size()

## `node`'s transform in its skeleton's rest pose (skeleton space): through BoneAttachment3D bones at their rest.
func rest_transform(node: Node, sk: Skeleton3D) -> Transform3D:
	var xf := Transform3D()
	var current := node
	while current != null and current != sk:
		if current is BoneAttachment3D: return sk.get_bone_global_rest(sk.find_bone((current as BoneAttachment3D).bone_name)) * xf
		if current is Node3D: xf = (current as Node3D).transform * xf
		current = current.get_parent()
	return xf

# ------------------------------------------------------------------ pupils
## Every seat's default look shows its head's pupils: a drawn "pupils" surface that stands out from the eyeball, or eyes
## painted in a picture of their own. An eye picture draws on every head's eyes (each eye's UVs span the picture) and
## hides the head's own pupils.
func check_pupils() -> void:
	var rig := make_rig(0)
	var blank := []
	var unmapped := []
	var pictures := []
	for seat in (Catalog.data().get("seat_heads", []) as Array).size():
		var look := CharacterLook.defaults_for_seat(seat)
		rig.set_look(look)
		var name := str(look.items.get("head", ""))
		var head := rig.find_child("Item_head", true, false) as MeshInstance3D
		var eyes := -1
		var pupils := -1
		for surface in head.mesh.get_surface_count():
			match Rig._surface_name(head.mesh.surface_get_material(surface)):
				"eyes": eyes = surface
				"pupils": pupils = surface
		if eyes < 0:
			blank.append(name + " (no eyes surface)")
			continue
		var eye_material := head.get_surface_override_material(eyes)
		if pupils >= 0:
			var pupil_material := head.get_surface_override_material(pupils)
			if pupil_material == Rig._hidden_material() or absf(colour_of(pupil_material).get_luminance() - colour_of(eye_material).get_luminance()) < 0.4: blank.append(name)
		elif texture_of(eye_material) == null: blank.append(name)
		var arrays := head.mesh.surface_get_arrays(eyes)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for side in [1.0, -1.0]:
			var span := Rect2()
			var first := true
			for i in uvs.size():
				if positions[i].x * side < 0.0: continue
				span = Rect2(uvs[i], Vector2.ZERO) if first else span.expand(uvs[i])
				first = false
			if first or span.size.x < 0.5 or span.size.y < 0.5: unmapped.append("%s %s" % [name, span])
		var picture_items := Catalog.items_for("eyes", name).filter(func(entry: Dictionary) -> bool: return str(entry.get("file", "")) != "")
		if picture_items.is_empty(): continue
		look.items["eyes"] = picture_items[0]["id"]
		rig.set_look(look)
		var own_texture: Texture2D = Rig._albedo(head.mesh.surface_get_material(eyes))[1]
		var worn := texture_of(head.get_surface_override_material(eyes))
		if worn == null or worn == own_texture or (pupils >= 0 and head.get_surface_override_material(pupils) != Rig._hidden_material()): pictures.append(name)
	expect("every seat's default look shows its head's pupils", blank.is_empty(), str(blank))
	expect("each eye of every head spans an eye picture's UVs", unmapped.is_empty(), str(unmapped))
	expect("an eye picture draws on every head's eyes and hides its pupils", pictures.is_empty(), str(pictures))
	world.remove_child(rig)
	rig.free()

# ------------------------------------------------------------------ bright toy materials
## Without the game look's materials every visible surface of a character (body, head, eyes, teeth, outfit, hat, hair, hand
## item) wears the rig's soft toy material (or the shirt shader) in its own colour: flat saturated colours, a little light
## of their own and a rim, never the darker imported material.
func check_soft_materials() -> void:
	var rig := make_rig(0)
	var look: CharacterLook = rig.get_look()
	look.items["hair"] = ""
	look.items["hand"] = "hand_hammer"
	rig.set_look(look)
	var plain: Array = []
	var whites: Array = []
	for mesh: MeshInstance3D in rig.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_surface_override_material(surface)
			var shader: Shader = (material as ShaderMaterial).shader if material is ShaderMaterial else null
			if shader == null or not (shader.resource_path.ends_with("character_soft.gdshader") or shader.resource_path.ends_with("shirt.gdshader") or material == Rig._hidden_material()):
				plain.append("%s#%d" % [mesh.name, surface])
			var own := mesh.mesh.surface_get_material(surface)
			if own != null and Rig._surface_name(own) in ["eyes", "teeth"]: whites.append(colour_of(material).v > 0.9)
	expect("every character surface wears the soft toy material", plain.is_empty(), str(plain))
	expect("eye whites and teeth stay white", not whites.is_empty() and whites.all(func(w: bool) -> bool: return w), str(whites))
	world.remove_child(rig)
	rig.free()

# ------------------------------------------------------------------ the game look's materials
## With FriendsStyle.character_material present (a stub here), every character part takes the look's material for its
## kind and colour; without it the rig's own materials come back.
func check_style_hook() -> void:
	var calls := {}
	Rig.style_hook = func(kind: String, color: Color, texture: Texture2D) -> Material:
		calls[kind] = int(calls.get(kind, 0)) + 1
		var material := StandardMaterial3D.new()
		material.resource_name = "styled_" + kind
		material.albedo_color = color
		material.albedo_texture = texture
		return material
	Rig._material_cache.clear()
	var rig := make_rig(0)
	var look: CharacterLook = rig.get_look()
	look.items["shirt"] = "" # a plain shirt (prints keep the rig's shirt shader)
	look.items["hat"] = "hat_cap"
	look.colors["pants"] = 5
	rig.set_look(look)
	var head := part_mesh(rig, "skin")
	var pants := part_mesh(rig, "pants")
	var shirt := part_mesh(rig, "shirt")
	var hat := rig.find_child("Item_hat", true, false)
	var hat_styled := hat != null and hat.find_children("*", "MeshInstance3D", true, false).any(func(m: MeshInstance3D) -> bool:
		var material := m.get_surface_override_material(0)
		return material != null and material.resource_name.begins_with("styled_hat"))
	var named := func(mesh: MeshInstance3D, kind: String) -> bool:
		var material := mesh.get_surface_override_material(0) if mesh != null else null
		return material != null and material.resource_name == "styled_" + kind
	var pants_colour := (pants.get_surface_override_material(0) as BaseMaterial3D).albedo_color if pants != null else Color.BLACK
	expect("the game look's materials are used when FriendsStyle has character_material", named.call(head, "skin") and named.call(pants, "pants") and named.call(shirt, "shirt") \
		and hat_styled and pants_colour.is_equal_approx(Catalog.color("pants", 5)) and (calls.has("eye") or part_mesh(rig, "eyes") == null), str(calls))
	Rig.style_hook = Callable()
	look.colors["pants"] = 6
	rig.set_look(look)
	var back := part_mesh(rig, "pants").get_surface_override_material(0)
	expect("without it the rig's own materials come back", back != null and not back.resource_name.begins_with("styled_"))
	world.remove_child(rig)
	rig.free()
	Rig._material_cache.clear()

# ------------------------------------------------------------------ slap
## Both hands: slap_hit fires once at SLAP_HIT_TIME with the hand's position, the hand is at its fastest there, the left
## swing mirrors the right one, the mouth opens, and the courier answers the same calls without doing anything.
func check_slap() -> void:
	var step := 1.0 / 120.0
	var paths := {}
	var mouths := {}
	for side in [-1, 1]:
		var rig := make_rig(0)
		rig.global_position = Vector3.ZERO
		rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0})
		stand(rig, 30, {"yaw": 0.0})
		var hits: Array = []
		var elapsed := {"t": 0.0}
		rig.slap_hit.connect(func(hit_side: int, at: Vector3) -> void: hits.append([hit_side, at, elapsed.t, rig.hand_world(0 if hit_side < 0 else 1)]))
		var hand := 0 if side < 0 else 1
		var previous: Vector3 = rig.hand_world(hand)
		var fastest := {"v": 0.0, "t": 0.0}
		var path: Array = []
		var mouth := 0.0
		rig.slap(side)
		for i in roundi(0.4 / step):
			elapsed.t = (i + 1) * step
			rig.update(step, {"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0})
			var at: Vector3 = rig.hand_world(hand)
			var speed := at.distance_to(previous) / step
			if speed > fastest.v: fastest = {"v": speed, "t": elapsed.t}
			previous = at
			path.append(at)
			mouth = maxf(mouth, rig.mouth_open())
		paths[side] = path
		mouths[side] = mouth
		print("CHARACTER_NUM slap side=", side, " length=", snappedf(rig.slap_length(), 0.001), " hit t=", snappedf(hits[0][2] if not hits.is_empty() else -1.0, 0.001), " at=", (hits[0][1] as Vector3).snapped(Vector3.ONE * 0.01) if not hits.is_empty() else Vector3.ZERO, " fastest t=", snappedf(fastest.t, 0.001), " v=", snappedf(fastest.v, 0.1), " mouth=", snappedf(mouth, 0.01))
		expect("slap %+d: one slap_hit with the side and the hand position, at SLAP_HIT_TIME" % side, hits.size() == 1 and int(hits[0][0]) == side and (hits[0][1] as Vector3).is_equal_approx(hits[0][3]) and absf(float(hits[0][2]) - Rig.SLAP_HIT_TIME) <= step + 0.0001, str(hits))
		expect("slap %+d: the hand is fastest at the hit (within a 60 Hz frame)" % side, absf(float(fastest.t) - Rig.SLAP_HIT_TIME) <= 1.0 / 60.0 + 0.0001 and float(fastest.v) > 8.0, str(fastest))
		expect("slap %+d: the hand swings out on its own side" % side, path.any(func(p: Vector3) -> bool: return signf(p.x) == signf(side) and absf(p.x) > 0.5) and path.all(func(p: Vector3) -> bool: return p.is_finite()))
		world.remove_child(rig)
		rig.free()
	# while the swing is fully on (after its 0.05 s fade-in, before its 0.1 s fade-out) the two hands are mirror images; in
	# the fades the idle under it shows, and that idle is not symmetric
	var mirror_error := 0.0
	var length := 0.208
	for i in mini(paths[-1].size(), paths[1].size()):
		var time := (i + 1) * step
		if time < 0.05 + 2.0 * step or time > length - 0.1 - step: continue
		var right: Vector3 = paths[1][i]
		mirror_error = maxf(mirror_error, (paths[-1][i] as Vector3).distance_to(Vector3(-right.x, right.y, right.z)))
	expect("the left slap mirrors the right one", mirror_error < 0.005, "%.4f m" % mirror_error)
	expect("the mouth opens on a slap", mouths[-1] > 0.3 and mouths[1] > 0.3, str(mouths))
	var courier: Node3D = load("res://courier/courier_rig.gd").new()
	world.add_child(courier)
	courier.setup(0)
	courier.slap(1)
	expect("the courier takes slap calls and does nothing", courier.slap_length() == 0.0 and "SLAP_HIT_TIME" in courier and courier.has_signal("slap_hit"))
	world.remove_child(courier)
	courier.free()

# ------------------------------------------------------------------ mouth
func jaw_turn(rig: Node3D) -> float:
	var sk: Skeleton3D = rig.skeleton()
	var jaw := sk.find_bone("ORG_jaw_lower")
	return sk.get_bone_pose_rotation(jaw).angle_to(sk.get_bone_rest(jaw).basis.get_rotation_quaternion())

func check_mouth() -> void:
	var rig := make_rig(0)
	rig.global_position = Vector3.ZERO
	rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0})
	stand(rig, 30, {"yaw": 0.0})
	var closed := jaw_turn(rig)
	var shut: float = rig.mouth_open()
	rig.set_talk_level(1.0)
	stand(rig, 10, {"yaw": 0.0})
	var open := jaw_turn(rig)
	print("CHARACTER_NUM jaw turn from rest (rad) closed=", snappedf(closed, 0.001), " talking=", snappedf(open, 0.001), " mouth=", snappedf(rig.mouth_open(), 0.01))
	expect("voice level opens the jaw", shut < 0.05 and rig.mouth_open() > 0.9 and absf(open - closed) > 0.25, "%.3f -> %.3f" % [closed, open])
	rig.set_talk_level(0.0)
	stand(rig, 30, {"yaw": 0.0})
	expect("mouth closes when the voice stops", rig.mouth_open() < 0.05, str(rig.mouth_open()))
	# a jump shouts, a long fall screams, a hard landing shouts
	var most := {"jump": 0.0, "fall": 0.0, "land": 0.0}
	var vy := 7.0
	var landed := false
	rig.global_position = Vector3(0, 0, 0)
	for tick in 150:
		vy -= 17.0 * DT
		var grounded := false
		if tick > 0: rig.global_position.y += vy * DT
		if tick > 120 and not landed:
			rig.global_position.y = 0.0
			grounded = true
			landed = true
		elif landed:
			grounded = true
			vy = 0.0
		rig.update(DT, {"velocity": Vector3(0, vy if not grounded else 0.0, 0) if tick > 0 else Vector3(0, 7.0, 0), "grounded": grounded, "yaw": 0.0})
		var phase := "jump" if tick < 12 else ("land" if landed else ("fall" if vy < -9.0 else ""))
		if phase != "": most[phase] = maxf(most[phase], rig.mouth_open())
	print("CHARACTER_NUM mouth peaks ", most)
	expect("jump shout, falling scream, hard landing shout", most["jump"] > 0.5 and most["fall"] > 0.4 and most["land"] > 0.5, str(most))
	stand(rig, 60, {"yaw": 0.0})
	rig.play_emote("dance")
	var dance := 0.0
	for i in 60:
		stand(rig, 1, {"yaw": 0.0})
		dance = maxf(dance, rig.mouth_open())
	expect("the dance emote sings", dance > 0.5, str(dance))
	world.remove_child(rig)
	rig.free()

## Fake client/main.gd for LookSync: joined, my_seat, slot_seats, match_info and simulation.
class FakeMain extends Node:
	var joined := false
	var my_seat := 0
	var slot_seats: Array = []
	var match_info := {}
	var simulation: FakeSimulation
	var sent: Array = []
	func _command(payload: Dictionary) -> Dictionary:
		sent.append(payload)
		return {"ok": true}

## Online looks on the client: other players are dressed from the match state, our own character is left to the wardrobe,
## a roster change re-dresses the slots, and a confirmed look is sent.
func check_look_sync() -> void:
	var LookSync := load("res://character/look_sync.gd")
	var fake := FakeMain.new()
	fake.simulation = FakeSimulation.new()
	var rigs := [make_rig(0), make_rig(1), make_rig(0)]
	fake.simulation.rigs = rigs
	root.add_child(fake)
	var sync: Node = LookSync.attach(fake)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var theirs: CharacterLook = Look.new().randomized(rng)
	var own_before: CharacterLook = rigs[0].get_look()
	fake.my_seat = 0
	fake.slot_seats = [0, 1, 2]
	fake.match_info = {"look_revs": [5, 6, 0], "looks": [Look.new().randomized(rng).to_bytes(), theirs.to_bytes(), PackedByteArray()]}
	sync.dress(fake.match_info)
	expect("look sync dresses the other players, not us", rigs[1].get_look().equals(theirs) and rigs[0].get_look().equals(own_before))
	# a new revision whose bytes have not arrived yet changes nothing; the next round moves seat 1 to slot 2
	fake.match_info = {"look_revs": [5, 7, 0]}
	sync.dress(fake.match_info)
	fake.slot_seats = [0, 2, 1]
	fake.match_info = {"look_revs": [5, 6, 0]}
	sync.dress(fake.match_info)
	expect("a roster change re-dresses the slots", rigs[2].get_look().equals(theirs) and rigs[1].get_look().equals(Look.defaults_for_seat(2)), str(rigs[1].get_look().to_dict()))
	# joining sends the saved look once, a confirmed look is sent on the next frame
	LookSync.commit(theirs)
	fake.joined = true
	sync._process(0.0)
	expect("a confirmed look is sent as hex", fake.sent.size() == 1 and str(fake.sent[0].get("c")) == "look" and str(fake.sent[0].get("v")).hex_decode() == theirs.to_bytes(), str(fake.sent))
	sync._process(0.0)
	expect("nothing more to send", fake.sent.size() == 1)
	fake.queue_free()
	for rig in rigs:
		world.remove_child(rig)
		rig.free()

## Fake simulation for LookSync: `rigs` and `selected`, like client/main.gd and game/game_run.gd.
class FakeSimulation extends RefCounted:
	var rigs: Array = []
	var selected := 0

## The colour a character material shows (the rig's soft material, the shirt shader or a standard material).
func colour_of(material: Material) -> Color:
	if material is BaseMaterial3D: return (material as BaseMaterial3D).albedo_color
	if material is ShaderMaterial:
		var value = (material as ShaderMaterial).get_shader_parameter("albedo")
		if value == null: value = (material as ShaderMaterial).get_shader_parameter("base_color")
		if value is Color: return value
	return Color(0, 0, 0, 0)

func texture_of(material: Material) -> Texture2D:
	if material is BaseMaterial3D: return (material as BaseMaterial3D).albedo_texture
	if material is ShaderMaterial: return (material as ShaderMaterial).get_shader_parameter("albedo_tex") as Texture2D
	return null

## The body mesh of a body_parts key (its first candidate name the body has), null without one.
func part_mesh(rig: Node3D, key: String) -> MeshInstance3D:
	for name in Catalog.body_part_names(key):
		var mesh := rig.find_child(str(name), true, false) as MeshInstance3D
		if mesh != null: return mesh
	return null

## Hands, head and feet in world space (to see a pose change).
func pose_points(rig: Node3D) -> Array:
	var sk: Skeleton3D = rig.skeleton()
	var points := [rig.hand_world(0), rig.hand_world(1)]
	for bone_name in ["head", "ORG_foot_L", "ORG_foot_R"]:
		points.append(sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone_name)).origin)
	return points

## World bounds of the visible meshes under `node`.
func bounds_of(node: Node) -> AABB:
	var box := AABB()
	var first := true
	var meshes := node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D: meshes.append(node)
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
		var part := mesh.global_transform * mesh.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box

# ------------------------------------------------------------------ looks
func check_looks() -> void:
	var rig := make_rig(0)
	rig.global_position = Vector3.ZERO
	rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0})
	var applied := {"n": 0}
	rig.look_applied.connect(func(): applied["n"] += 1)
	# the follow camera puts the body on its own render layers once; swaps must keep them
	for mesh: MeshInstance3D in rig.find_children("*", "MeshInstance3D", true, false): mesh.layers = 1 << 9
	var not_applied: Array = []
	for slot in Catalog.slots():
		var entries: Array = Catalog.items(slot).duplicate()
		entries.append({"id": ""})
		for entry in entries:
			var look: CharacterLook = rig.get_look()
			look.items[slot] = str(entry["id"])
			rig.set_look(look)
			stand(rig, 2, {"yaw": 0.0})
			if rig.get_look().items[slot] != str(entry["id"]): not_applied.append(entry["id"])
	expect("every item applies", not_applied.is_empty(), str(not_applied))
	# hats and hair sit on the head, hand items at the hand (standing, idle)
	var sk: Skeleton3D = rig.skeleton()
	var head := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("head")).origin
	var misplaced: Array = []
	var spots := {}
	for slot in ["hat", "hair", "hand"]:
		for entry in Catalog.items(slot):
			var look: CharacterLook = rig.get_look()
			for other in ["hat", "hair", "hand"]: look.items[other] = ""
			look.items[slot] = str(entry["id"])
			rig.set_look(look)
			stand(rig, 2, {"yaw": 0.0})
			var item := rig.find_child("Item_" + slot, true, false)
			if item == null:
				misplaced.append(str(entry["id"]) + " (no node)")
				continue
			var box := bounds_of(item)
			var centre := box.get_center()
			spots[entry["id"]] = [snappedf(centre.x, 0.01), snappedf(centre.y, 0.01), snappedf(centre.z, 0.01), snappedf(box.size.y, 0.01)]
			var ok := true
			if slot == "hand":
				ok = box.grow(0.15).has_point(rig.hand_world(0)) # the item is held: the hand is at (or in) it
			else:
				ok = Vector2(centre.x - head.x, centre.z - head.z).length() < 0.3 and centre.y > head.y + 0.15 and box.size.y < 1.2
			if not ok: misplaced.append(entry["id"])
	print("CHARACTER_NUM item spots [x, y, z, height] head=", head.snapped(Vector3.ONE * 0.01), " left hand=", rig.hand_world(0).snapped(Vector3.ONE * 0.01), " ", spots)
	expect("hats and hair on the head, hand items in the hand", misplaced.is_empty(), str(misplaced))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var t0 := Time.get_ticks_usec()
	for i in 20:
		var look: CharacterLook = Look.new().randomized(rng)
		rig.set_look(look)
		rig.update(DT, {"velocity": Vector3(0, 0, -2.0), "grounded": true, "yaw": 0.0, "carrying": i % 3 == 0})
		stand(rig, 3, {"yaw": 0.0})
		if not rig.get_look().equals(look): not_applied.append("random %d" % i)
	print("CHARACTER_NUM 20 random looks ms=", snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1))
	expect("20 random looks apply", not_applied.is_empty(), str(not_applied))
	var before: int = applied["n"]
	rig.set_look(rig.get_look())
	expect("same look again is a no-op", applied["n"] == before)
	var wrong_layers: Array = []
	for mesh: MeshInstance3D in rig.find_children("*", "MeshInstance3D", true, false):
		if mesh.layers != 1 << 9: wrong_layers.append(str(mesh.name))
	expect("item meshes keep the body's render layers", wrong_layers.is_empty(), str(wrong_layers))
	var shirt_look: CharacterLook = rig.get_look()
	var prints := Catalog.items("shirt").filter(func(entry: Dictionary) -> bool: return str(entry.get("file", "")) != "")
	if prints.is_empty(): print("CHARACTER_CHECK note: no shirt print in the tree, so prints are not checked")
	else:
		shirt_look.items["shirt"] = str(prints[0]["id"])
		rig.set_look(shirt_look)
		var shirt: MeshInstance3D = part_mesh(rig, "shirt")
		var shirt_material := shirt.get_surface_override_material(0) as ShaderMaterial if shirt != null else null
		expect("shirt print on the shirt", shirt_material != null and shirt_material.get_shader_parameter("print_tex") is Texture2D)
	var own_shirt: int = rig.get_look().colors["shirt"]
	rig.set_slot_tint(3)
	expect("set_slot_tint keeps a player's look", rig.get_look().colors["shirt"] == own_shirt)
	world.remove_child(rig)
	rig.free()
	var fresh := make_rig(1)
	fresh.set_slot_tint(3)
	expect("set_slot_tint colours a default look", fresh.get_look().colors["shirt"] == Catalog.nearest("shirt", preload("res://style/team_cast.gd").player_color(3)))
	world.remove_child(fresh)
	fresh.free()
