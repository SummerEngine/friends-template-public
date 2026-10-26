extends SceneTree
## The menu pet on the title, headless: it loads, stands with its feet on the drawing's platform (GROUND on the backdrop
## art), about half the title tall, right of the menu column (landscape and portrait), wears the characters' soft toy
## material with no ink line in the facility look (or the look's own character material), is happy on PLAY hover, sad on QUIT hover, idle elsewhere,
## follows keyboard focus too, cheers when PLAY is pressed (for CHEER_TIME on its own clock), is petted by a press-and-rub
## (hearts rise) and calms down after, turns its head toward the pointer, wears the cap with a logo texture, and nothing of
## the pet passes through the cap in any of the four moods (every clip sampled, the ear twitch on top), and hides with
## the title. Waits are on the pet's own clock, so the result does not depend on the frame rate. Without a pet model
## (demo/pet/models/pet.glb or the local stand-in in demo/pet/_ref/) it only checks that the title shows no pet.
## Prints MENU_PET_CHECK lines; the last one is `MENU_PET_CHECK ok=<bool>`.
##   /opt/homebrew/bin/python3 ~/.claude/skills/engine-runs-summer/engine_run.py --timeout 300 -- \
##     <Summer> --headless --fixed-fps 60 --path demo -s $PWD/tools/menu_pet_check.gd
const MainMenu := preload("res://client/main_menu.gd")
const MenuPet := preload("res://pet/menu_pet.gd")
const PetCap := preload("res://pet/pet_cap.gd")
const PetLook := preload("res://pet/pet_look.gd")
const PetMotion := preload("res://pet/pet_motion.gd")
const PetRig := preload("res://pet/pet_rig.gd")
const MenuBackdrop := preload("res://client/menu_backdrop.gd")
const MenuStyle := preload("res://client/menu_style.gd")
const TeamCast := preload("res://style/team_cast.gd")

var failures: Array[String] = []
var states: Array[String] = []
var plays := 0
var menu: Control
var pet: Control

func _initialize() -> void:
	run.call_deferred()

func expect(condition: bool, what: String) -> void:
	print("MENU_PET_CHECK ", "pass " if condition else "FAIL ", what)
	if not condition: failures.append(what)

func frames(count: int) -> void:
	for i in count: await process_frame

func center_of(control: Control) -> Vector2:
	return control.get_global_rect().get_center()

func move(at: Vector2, buttons := 0) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = Vector2(3, 0)
	event.button_mask = buttons
	root.push_input(event, true)

func click(at: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	root.push_input(event, true)

func read_asset(path: String) -> Resource:
	return ResourceLoader.load(path) if ResourceLoader.exists(path) else null

func pressed_play() -> void:
	plays += 1

func pressed_other() -> void:
	pass

func on_state(next: String) -> void:
	states.append(next)

func state_after(count: int) -> String:
	await frames(count)
	return pet.state

## Waits until the pet's own clock (its process delta, capped as the pet caps it) has run `time` seconds.
func pet_seconds(time: float) -> void:
	var clock := 0.0
	while clock < time:
		await process_frame
		clock += minf(pet.get_process_delta_time(), 0.1)

func run() -> void:
	root.size = Vector2i(1280, 720)
	MenuStyle.set_asset_reader(read_asset)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	# The title's characters are the cast's (style/menu_stage.gd); the dog is opt-in (MainMenu.pet_enabled), switched on here for its own checks.
	var plain := MainMenu.new()
	layer.add_child(plain)
	plain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	expect(plain.get_node_or_null("MenuPet") == null, "the title shows the cast, not the pet, by default")
	plain.queue_free()
	MainMenu.pet_enabled = true
	menu = MainMenu.new()
	menu.actions = {"Play": pressed_play, "Settings": pressed_other, "Quit": pressed_other}
	layer.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pet = menu.get_node_or_null("MenuPet")
	expect(pet != null, "the title has the pet")
	if pet == null:
		finish()
		return
	if not pet.has_model():
		# A clean checkout before our art lands: no pet, and nothing else changes on the title.
		await frames(10)
		expect(not pet.visible and not pet.is_processing() and not pet.is_processing_input(), "no model: the pet is hidden and idle")
		expect(pet.mouse_filter == Control.MOUSE_FILTER_IGNORE, "no model: the pet takes no clicks")
		print("MENU_PET_CHECK no pet model (demo/pet/models/pet.glb or the local stand-in): the rest is skipped")
		finish()
		return
	var deadline := Time.get_ticks_msec() + 60000
	while not pet.is_loaded() and pet.visible and Time.get_ticks_msec() < deadline: await process_frame
	expect(pet.is_loaded(), "the pet model loads")
	if not pet.is_loaded():
		finish()
		return
	pet.state_changed.connect(on_state)
	await frames(10)
	print("MENU_PET_CHECK title ", menu.size, " hit ", pet.hit_rect(), " clips ", pet.rig.clips)

	# Where it stands: on the drawing's platform, about half the title tall, right of the menu column, inside the title.
	var hit: Rect2 = pet.hit_rect()
	var stand: Rect2 = pet.stand_rect()
	var backdrop: Control = menu.get_node("MenuBackdrop")
	var ground: Vector2 = backdrop.art_point(MenuPet.GROUND)
	var feet := Vector2(stand.get_center().x, stand.end.y)
	print("MENU_PET_CHECK stand ", stand, " feet ", feet, " ground ", ground)
	expect(feet.distance_to(ground) < 2.0, "its feet stand on the drawing's platform")
	expect(stand.size.y >= menu.size.y * 0.45 and stand.size.y <= menu.size.y * 0.55, "it is about half the title tall")
	expect(hit.size.x > 40.0 and hit.size.y > 40.0, "the pet has a hit area")
	expect(hit.position.x >= menu.size.x * 0.46 and stand.position.x >= menu.size.x * 0.46 and Rect2(Vector2.ZERO, menu.size).encloses(stand) \
		and Rect2(Vector2.ZERO, menu.size).encloses(hit), "the pet stands in the free right half")
	# A cast with its own title art: the art comes from demo/cast/title_backdrop.* and the pet stands on title.pet_ground.
	await cast_title_art(backdrop)
	# The facility look (no character material of its own): every surface of the pet and its cap is the characters' soft
	# toy material, and nothing draws an ink line.
	var surfaces := 0
	var soft := 0
	var lined := 0
	for mesh_instance: MeshInstance3D in pet.rig.find_children("*", "MeshInstance3D", true, false):
		if mesh_instance == pet.rig.cap.panel: continue
		var looks: Array = [mesh_instance.material_override]
		if mesh_instance.material_override == null:
			looks = []
			for surface in mesh_instance.mesh.get_surface_count(): looks.append(mesh_instance.get_surface_override_material(surface))
		for look in looks:
			surfaces += 1
			if look is ShaderMaterial and (look as ShaderMaterial).shader == PetLook.SOFT: soft += 1
			if look is Material and (look as Material).next_pass != null: lined += 1
	print("MENU_PET_CHECK look surfaces ", surfaces, " soft ", soft, " lined ", lined, " game look ", PetLook.styled("pet", Color.WHITE) != null)
	if PetLook.styled("pet", Color.WHITE) == null:
		expect(surfaces > 11 and soft == surfaces, "the pet and its cap wear the characters' soft toy material")
		expect(lined == 0, "no ink line on the pet in the facility look")
	await style_hook_used()
	for clip: String in ["idle", "happy", "sad", "pet"]:
		expect(pet.rig.clips.get(clip, "") != "", "the model has a clip for " + clip)

	# The cap.
	var cap = pet.rig.cap
	expect(cap != null, "the pet wears a cap")
	if cap != null:
		var material := cap.panel.material_override as StandardMaterial3D
		var styled: bool = PetLook.styled("hat_logo", Color.WHITE, cap.logo) != null
		expect(styled or (material != null and material.albedo_texture != null), "the cap's front panel has a logo texture")
		expect(styled or cap.logo == material.albedo_texture, "the panel shows the cap's logo")
		var expected_color = PetCap.team_color()
		expect(cap.color == expected_color, "the cap is the team colour")
		print("MENU_PET_CHECK cap logo ", cap.logo.get_class(), " ", cap.logo.get_size(), " colour ", cap.color.to_html(false), " at ", cap.get_parent().get_parent().name)
	expect(PetCap._cast_call("team_name") is String, "cast functions are found by name")
	expect(PetCap._cast_call("no_such_function") == null, "a missing cast function is skipped")
	# A cast with brand colours: the cap takes the brand accent; without a logo it gets the name badge.
	TeamCast.override({"format": "team-cast-v2", "team": {"name": "ACME"}, "brand": {"colors": ["#1d1d1f", "#3a5bd9"]}})
	var branded = PetCap.new(0.5)
	root.add_child(branded)
	var accent = PetCap._cast_call("brand_accent")
	expect(accent is Color and accent.a > 0.0 and branded.color == accent, "a brand colour colours the cap")
	expect(branded.logo is ViewportTexture, "no logo: the cap gets the name badge")
	branded.free()
	TeamCast.override({})

	# Pointer: hover PLAY, QUIT, then empty sky.
	var play: Button = menu.action_button("Play")
	var quit_button: Button = menu.action_button("Quit")
	var settings: Button = menu.action_button("Settings")
	var empty := Vector2(menu.size.x * 0.98, menu.size.y * 0.03)
	move(center_of(play))
	expect(await state_after(4) == "happy", "hovering PLAY makes it happy")
	move(center_of(settings))
	expect(await state_after(4) == "happy", "hovering SETTINGS makes it happy")
	if quit_button != null:
		move(center_of(quit_button))
		expect(await state_after(4) == "sad", "hovering QUIT makes it sad")
	move(empty)
	expect(await state_after(4) == "idle", "away from the buttons it is idle")

	# Head: follows the pointer left and right.
	move(Vector2(menu.size.x * 0.05, menu.size.y * 0.5))
	await pet_seconds(1.0)
	var left: float = pet.rig.motion.yaw
	var turned_left: float = pet.rig.rotation.y
	move(Vector2(menu.size.x * 0.995, menu.size.y * 0.5))
	await pet_seconds(1.0)
	var right: float = pet.rig.motion.yaw
	var turned_right: float = pet.rig.rotation.y
	print("MENU_PET_CHECK body turn left ", turned_left, " right ", turned_right)
	expect(turned_right - turned_left > 0.2, "the pet turns toward the pointer")
	# The gaze turns the whole pet, never the head bone alone: the cap's mount is the head's pose as the clip has it.
	var skeleton: Skeleton3D = pet.rig.skeleton
	var mount: Node3D = pet.rig.cap.get_parent()
	expect(mount.transform.is_equal_approx(skeleton.get_bone_global_pose(skeleton.find_bone("head"))), "the cap stays on the head while the pet looks around")
	print("MENU_PET_CHECK yaw left ", left, " right ", right)
	expect(right - left > 0.3, "the gaze follows the pointer")

	# Keys: the focused button counts.
	var key := InputEventKey.new()
	key.keycode = KEY_DOWN
	key.pressed = true
	root.push_input(key, true)
	if quit_button != null:
		quit_button.grab_focus()
		expect(await state_after(4) == "sad", "focusing QUIT with keys makes it sad")
		# The engine refreshes the cursor with a motion of its own (device -2) when a cursor shape changes; handed to the pet
		# as the engine hands it in a window, it must not switch a key player to the pointer.
		var refresh := InputEventMouseMotion.new()
		refresh.device = MenuPet.ENGINE_MOTION
		refresh.position = Vector2(menu.size.x * 0.98, menu.size.y * 0.03)
		refresh.global_position = refresh.position
		pet.call("_input", refresh)
		expect(await state_after(4) == "sad", "the engine's cursor refresh does not take QUIT's sadness away")
		# A motion that does not move (the window opening under a resting cursor) is not the player picking up the mouse.
		var still := InputEventMouseMotion.new()
		still.position = refresh.position
		still.global_position = refresh.position
		pet.call("_input", still)
		expect(await state_after(4) == "sad", "a motion that does not move keeps key mode")
	settings.grab_focus()
	expect(await state_after(4) == "happy", "focusing SETTINGS with keys makes it happy")

	# Pressing PLAY: a short happy reaction even away from the button.
	move(empty)
	await frames(4)
	play.release_focus()
	expect(await state_after(4) == "idle", "idle before PLAY is pressed")
	play.button_down.emit()
	expect(await state_after(2) == "happy", "pressing PLAY cheers it")
	await pet_seconds(MenuPet.CHEER_TIME * 0.5)
	expect(pet.state == "happy", "the cheer lasts")
	await pet_seconds(MenuPet.CHEER_TIME * 0.5 + 0.15)
	expect(await state_after(2) == "idle", "the cheer is short")

	# Petting: press on the pet and rub.
	hit = pet.hit_rect()
	var middle := hit.get_center()
	click(middle, true)
	for step in 24:
		move(middle + Vector2(sin(step * 0.9) * hit.size.x * 0.25, cos(step * 0.7) * hit.size.y * 0.1), MOUSE_BUTTON_MASK_LEFT)
		await process_frame
	expect(pet.state == "pet", "rubbing the pet pets it")
	expect(pet.hearts.count() > 0, "hearts float up while petting")
	expect(pet.mouse_default_cursor_shape == Control.CURSOR_DRAG, "the hand grabs while rubbing")
	click(middle, false)
	# The rub fades from its top (0.6) below RUB_STOP in ln(0.6 / RUB_STOP) / RUB_DECAY seconds.
	await pet_seconds(log(0.6 / MenuPet.RUB_STOP) / MenuPet.RUB_DECAY + 0.15)
	expect(await state_after(2) == "idle", "it calms down after petting")
	expect(pet.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND, "hand cursor over the pet")
	expect(states.has("pet") and states.has("happy") and states.has("sad") and states.has("idle"), "all four states were played: " + str(states))

	# Sounds: headless runs stay silent through hover, petting and the cheer (the voice never got a stream).
	var voice: AudioStreamPlayer = pet.get_node("PetVoice")
	expect(not voice.playing and voice.stream == null, "the pet is silent headless")

	# Hidden with the title.
	menu.visible = false
	await frames(2)
	expect(not pet.is_visible_in_tree(), "the pet hides with the title")
	menu.visible = true
	await frames(2)
	expect(pet.is_visible_in_tree(), "the pet shows with the title")

	# Phone portrait: still right of the column, inside the screen.
	menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
	menu.size = Vector2(720, 1560)
	await frames(6)
	hit = pet.hit_rect()
	stand = pet.stand_rect()
	print("MENU_PET_CHECK portrait hit ", hit, " stand ", stand)
	expect(hit.position.x >= 720 * 0.46 and stand.position.x >= 720 * 0.46 and Rect2(0, 0, 720, 1560).encloses(stand) and hit.size.y > 80,
		"portrait: the pet stands right of the column")
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames(4)
	await cap_clear()
	finish()

## The cast's title art and pet spot: a picture named title_backdrop.png in the cast folder (here a folder of the check's
## own) is the title's art, scaled down past MenuBackdrop.CAST_MAX; title.pet_ground moves the pet's feet to that point of
## the art; a bad pet_ground keeps the template's spot.
func cast_title_art(backdrop: Control) -> void:
	var folder := "user://title_art_check/"
	DirAccess.make_dir_recursive_absolute(folder)
	var picture := Image.create(3000, 1600, false, Image.FORMAT_RGB8)
	picture.fill(Color("ff4000"))
	picture.save_png(folder + "title_backdrop.png")
	MenuBackdrop.cast_dir = folder
	var art := MenuBackdrop.new()
	expect(art._sky != null and art._sky.get_size() == Vector2(MenuBackdrop.CAST_MAX, 1092), "the cast's title_backdrop is the title art, at most %d px (%s)" % [MenuBackdrop.CAST_MAX, art._sky.get_size() if art._sky != null else "none"])
	art.free()
	MenuBackdrop.cast_dir = "user://no_such_folder/"
	art = MenuBackdrop.new()
	expect(art._sky == MenuStyle.backdrop_texture(), "without one the title keeps the template's art")
	art.free()
	MenuBackdrop.cast_dir = "res" + "://cast/"
	DirAccess.remove_absolute(folder + "title_backdrop.png")
	DirAccess.remove_absolute(folder)
	for spot: Array in [[0.75, 0.85], [1.4, 0.2]]:
		TeamCast.override({"format": "team-cast-v2", "team": {"name": "FRIENDS"}, "title": {"pet_ground": spot}})
		pet.call("_layout")
		await frames(2)
		var stand: Rect2 = pet.stand_rect()
		var want: Vector2 = backdrop.art_point(Vector2(spot[0], spot[1]) if spot[0] <= 1.0 else MenuPet.GROUND)
		var feet := Vector2(stand.get_center().x, stand.end.y)
		expect(feet.distance_to(want) < 2.0, "title.pet_ground %s: the feet stand on %s (at %s)" % [spot, want, feet])
	TeamCast.override({})
	pet.call("_layout")
	await frames(2)

## With the game look's FriendsStyle.character_material (a stand-in here), every part of the pet takes it: the body as
## "pet", the cap's parts as "hat", the logo as "hat_logo" with the logo texture.
func style_hook_used() -> void:
	var asked := {}
	var made := {}
	PetLook.style_hook = func(kind: String, color: Color, texture: Texture2D) -> Material:
		asked[kind] = int(asked.get(kind, 0)) + 1
		var look := StandardMaterial3D.new()
		look.albedo_color = color
		look.albedo_texture = texture
		look.resource_name = "style_" + kind
		made[look] = kind
		return look
	var styled := PetRig.new()
	root.add_child(styled)
	var ok: bool = styled.setup(load(str(pet.get("_model_path"))))
	var plain := 0
	for mesh_instance: MeshInstance3D in styled.find_children("*", "MeshInstance3D", true, false):
		var looks: Array = [mesh_instance.material_override]
		if mesh_instance.material_override == null:
			for surface in mesh_instance.mesh.get_surface_count(): looks.append(mesh_instance.get_surface_override_material(surface))
		for look in looks:
			if look != null and not made.has(look): plain += 1
	var logo_look: StandardMaterial3D = styled.cap.panel.material_override if ok and styled.cap != null else null
	print("MENU_PET_CHECK game look asked ", asked, " plain parts ", plain)
	expect(ok and plain == 0 and asked.get("pet", 0) > 0 and asked.get("hat", 0) >= 2 and asked.get("hat_logo", 0) == 1, "the game look's character_material dresses the pet and its cap")
	expect(logo_look != null and logo_look.albedo_texture == styled.cap.logo, "the game look gets the logo for the cap's front")
	styled.free()
	PetLook.style_hook = Callable()

## Nothing of the pet passes through the cap: every clip sampled every 0.15 s, plain and with both ears twitched (the
## motion's ear twitch at full angle), skinned on the CPU. A mesh edge that crosses the crown's dome, its wall or the brim
## is a visible clip; the head may go in under the rim (that is how a cap sits).
func cap_clear() -> void:
	var rig = pet.rig
	var cap: Node3D = rig.cap
	var skeleton: Skeleton3D = rig.skeleton
	var head := skeleton.find_bone("head")
	var mesh_instance: MeshInstance3D = null
	for each: MeshInstance3D in rig.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		if each.skin != null: mesh_instance = each
	if cap == null or head < 0 or mesh_instance == null:
		expect(false, "the cap check finds the cap, the head bone and the skinned mesh")
		return
	var shape: Node3D = cap.get_node("Shape")
	var brim: Node3D = shape.get_node("Brim")
	var brim_mesh := (brim as MeshInstance3D).mesh as CylinderMesh
	var ears := [skeleton.find_bone("ear_l"), skeleton.find_bone("ear_r")]
	print("MENU_PET_CHECK cap seat on the head ", cap.transform, " crown ", shape.scale)
	rig.motion.active = false
	rig.player.speed_scale = 0.0
	var edges := mesh_edges(mesh_instance.mesh)
	var crossings := {}
	var samples := 0
	for state: String in ["idle", "happy", "sad", "pet"]:
		var clip: String = rig.clips[state]
		var length: float = rig.player.get_animation(clip).length
		var time := 0.0
		while time <= length:
			for twitch in [false, true]:
				skeleton.reset_bone_poses()
				rig.player.play(clip)
				rig.player.seek(time, true)
				if twitch:
					for ear: int in ears:
						if ear >= 0: skeleton.set_bone_pose_rotation(ear, skeleton.get_bone_pose_rotation(ear) * Quaternion(Vector3.RIGHT, PetMotion.TWITCH_ANGLE))
				var to_shape := (skeleton.get_bone_global_pose(head) * cap.transform * shape.transform).affine_inverse()
				var points := skinned(mesh_instance, skeleton, to_shape)
				var hits := crown_crossings(points, edges, brim.transform, brim_mesh.top_radius)
				samples += 1
				if hits > 0: crossings["%s %.1f%s" % [state, time, " twitch" if twitch else ""]] = hits
			time += 0.15
	rig.player.speed_scale = 1.0
	rig.motion.active = true
	print("MENU_PET_CHECK cap samples ", samples, " crossings ", crossings)
	expect(samples > 100 and crossings.is_empty(), "nothing passes through the cap in any mood")

## Every vertex of the skinned mesh (all surfaces in a row) in `to_space`, for the skeleton's current pose.
func skinned(mesh_instance: MeshInstance3D, skeleton: Skeleton3D, to_space: Transform3D) -> PackedVector3Array:
	var skin := mesh_instance.skin
	var binds: Array[Transform3D] = []
	for bind in skin.get_bind_count():
		var bone := skin.get_bind_bone(bind)
		if bone < 0: bone = skeleton.find_bone(skin.get_bind_name(bind))
		binds.append(to_space * skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind))
	var points := PackedVector3Array()
	for surface in mesh_instance.mesh.get_surface_count():
		var arrays := mesh_instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / maxi(vertices.size(), 1)
		for index in vertices.size():
			var point := Vector3.ZERO
			for k in per:
				var weight := weights[index * per + k]
				if weight > 0.0: point += (binds[bones[index * per + k]] * vertices[index]) * weight
			points.append(point)
	return points

## The mesh's triangle edges as vertex index pairs (indices into all surfaces in a row).
func mesh_edges(mesh: Mesh) -> PackedInt32Array:
	var seen := {}
	var edges := PackedInt32Array()
	var offset := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for corner in indices.size():
			var a := offset + indices[corner]
			var b := offset + indices[corner - corner % 3 + (corner + 1) % 3]
			var key := mini(a, b) * 1000003 + maxi(a, b)
			if seen.has(key): continue
			seen[key] = true
			edges.append(a)
			edges.append(b)
		offset += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return edges

## Edges crossing the cap, in its shape's space (crown: the upper half of the unit sphere; brim: a disc of `brim_radius`
## in the plane of `brim_at`): into the dome from above the rim, through the wall below the rim's circle, or through the
## brim outside the crown.
func crown_crossings(points: PackedVector3Array, edges: PackedInt32Array, brim_at: Transform3D, brim_radius: float) -> int:
	var hits := 0
	var to_brim := brim_at.affine_inverse()
	for pair in range(0, edges.size(), 2):
		var a := points[edges[pair]]
		var b := points[edges[pair + 1]]
		# Far from the cap: skip.
		if a.length_squared() > 9.0 and b.length_squared() > 9.0: continue
		var a_in := a.y > 0.0 and a.length_squared() < 1.0
		var b_in := b.y > 0.0 and b.length_squared() < 1.0
		if a_in != b_in:
			var outside := b if a_in else a
			if outside.y > 0.0:
				hits += 1
				continue
			var t := a.y / (a.y - b.y)
			var rim := a.lerp(b, t)
			if Vector2(rim.x, rim.z).length_squared() > 1.0:
				hits += 1
				continue
		var brim_a := to_brim * a
		var brim_b := to_brim * b
		if (brim_a.y > 0.0) != (brim_b.y > 0.0):
			var on := brim_a.lerp(brim_b, brim_a.y / (brim_a.y - brim_b.y))
			var crossing := brim_at * on
			if Vector2(on.x, on.z).length_squared() < brim_radius * brim_radius and Vector2(crossing.x, crossing.z).length_squared() > 1.0:
				hits += 1
	return hits

func finish() -> void:
	MenuStyle.set_asset_reader(Callable())
	if menu != null: menu.free()
	await frames(2)
	print("MENU_PET_CHECK ok=", failures.is_empty(), " failures=", failures)
	quit(0 if failures.is_empty() else 1)
