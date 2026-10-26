extends SceneTree
## Calibration of the show's daylight (style/candy_light.gd, numbers in style/candy_look.gd) on the renderer this process runs on (Mobile by default, Compatibility with
## `--rendering-method gl_compatibility`). Offscreen only, never windowed, about 15 s:
##   lockf -k ~/.local/state/friends-slots/render.lock <Summer offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 --resolution 1280x720 \
##     --path demo -s "$PWD/tools/candy_light_check.gd" -- --out=<dir> [--prefix=light_]
## Measures and prints CANDY_LIGHT lines: (1) a white plane facing the sun with no ambient reads sun colour x energy (Lambert, no extra pi); (2) a grey ramp
## of scene-linear light follows the grade (0.18 -> #394, 0.5 -> 0.697, 1.0 -> 0.975 sRGB); (3) the lit and shadow anchors under the full rig: white tile, blue floor, orange floor and the
## shadow / lit luminance ratio (the albedo of a coloured floor is solved from the light a grey probe measures, so only the LIGHT is under test); (5) the sky's top and lowest colour.
## Writes `<out>/<prefix><renderer>_*.png`: the sky, the test scene (coloured boxes and a character-sized capsule on a white floor) from two sides. Exit code 1 when an anchor is off.
const CandyLook := preload("res://style/candy_look.gd")
const CandyLight := preload("res://style/candy_light.gd")

const WHITE_PLANE_TOLERANCE := 0.02          ## relative, on the linear value
const RAMP_TOLERANCE := 0.012                ## absolute, sRGB
const ANCHOR_TOLERANCE := 0.075             ## absolute per sRGB channel (about 13/255): the target anchors disagree with each other by about that much (white tile blue vs blue floor)
const LUMA_TARGET := 0.41
const LUMA_TOLERANCE := 0.05
const WHITE_LIT := Color("#fcf9fe")
const WHITE_SHADOW := Color("#c0abf7")
const BLUE_LIT := Color("#0094f5")
const BLUE_SHADOW := Color("#005cba")
const ORANGE_LIT := Color("#fbb052")
const ORANGE_SHADOW := Color("#bb672f")   ## the target shadow is redder and less blue than any single flat ambient gives (R is 0.07 off at best)
const SKY_TOP := Color("#30abf6")      ## the target median of the top of a frame
const SKY_LOW := Color("#2edde8")
const RAMP := [0.05, 0.1, 0.18, 0.25, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.5]
const BOX_HALF := 2.0
const BOX_HEIGHT := 10.0

var out := ""
var prefix := "light_"
var failures := 0
var _tag := ""
var _work: Node3D

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.trim_prefix("--out=")
		elif a.begins_with("--prefix="): prefix = a.trim_prefix("--prefix=")
	_tag = "compat" if RenderingServer.get_current_rendering_method() == "gl_compatibility" else "mobile"
	if out != "": DirAccess.make_dir_recursive_absolute(out)
	run.call_deferred()

func frames(count: int) -> void:
	for _i in count: await process_frame

func _clear() -> void:
	if _work != null: _work.queue_free()
	_work = Node3D.new()
	root.add_child(_work)

func _camera(position: Vector3, look_at: Vector3, fov := 60.0, ortho := 0.0, up := Vector3.UP) -> Camera3D:
	var camera := Camera3D.new()
	if ortho > 0.0:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = ortho
		camera.keep_aspect = Camera3D.KEEP_WIDTH
	else:
		camera.fov = fov
	camera.far = 600.0
	camera.current = true
	_work.add_child(camera)
	camera.look_at_from_position(position, look_at, up)
	return camera

func _plain(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.metallic_specular = 0.0
	return material

## The picture's colour (average of a 5 x 5 patch) at pixel (x, y).
func _pixel(image: Image, x: int, y: int) -> Color:
	var sum := Color(0, 0, 0, 0)
	for dy in range(-2, 3):
		for dx in range(-2, 3): sum += image.get_pixel(clampi(x + dx, 0, image.get_width() - 1), clampi(y + dy, 0, image.get_height() - 1))
	return Color(sum.r / 25.0, sum.g / 25.0, sum.b / 25.0)

func _hex(c: Color) -> String:
	return "#" + c.to_html(false).to_upper()

func _near(a: Color, b: Color, tolerance: float) -> bool:
	return absf(a.r - b.r) <= tolerance and absf(a.g - b.g) <= tolerance and absf(a.b - b.b) <= tolerance

func _luma(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b

func _verdict(name: String, ok: bool, detail: String) -> void:
	if not ok: failures += 1
	print("CANDY_LIGHT [%s] %s %s  %s" % [_tag, "ok  " if ok else "FAIL", name, detail])

func run() -> void:
	await _white_plane()
	await _ramp()
	await _floors()
	await _sky()
	await _scenes()
	print("CANDY_LIGHT [%s] %s (%d off)" % [_tag, "DONE ok" if failures == 0 else "DONE", failures])
	quit(1 if failures > 0 else 0)

# ------------------------------------------------------------------ (1) a white plane facing the sun

func _white_plane() -> void:
	_clear()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.reflected_light_source = 1 # no reflections
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	var holder := WorldEnvironment.new()
	holder.environment = env
	_work.add_child(holder)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#ffe9c4")
	sun.light_energy = 0.9
	sun.shadow_enabled = false
	_work.add_child(sun)
	var towards := CandyLook.towards(61.0, 229.0)
	sun.global_basis = Basis.looking_at(-towards, Vector3.UP)
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(20, 20)
	quad.mesh = mesh
	quad.material_override = _plain(Color.WHITE)
	_work.add_child(quad)
	quad.global_basis = Basis.looking_at(-towards, Vector3.UP) # a quad's front faces +Z: that is `towards`
	_camera(towards * 10.0, Vector3.ZERO, 40.0)
	await frames(4)
	var image := root.get_texture().get_image()
	var got := _pixel(image, image.get_width() / 2, image.get_height() / 2)
	var want := Color(0.9 * 1.0, 0.9 * 0.8148, 0.9 * 0.5521)
	var lin := got.srgb_to_linear()
	var ok := absf(lin.r / want.r - 1.0) < WHITE_PLANE_TOLERANCE and absf(lin.g / want.g - 1.0) < WHITE_PLANE_TOLERANCE and absf(lin.b / want.b - 1.0) < WHITE_PLANE_TOLERANCE
	_verdict("white plane", ok, "reads linear (%.3f %.3f %.3f), wanted energy x colour (%.3f %.3f %.3f)" % [lin.r, lin.g, lin.b, want.r, want.g, want.b])

# ------------------------------------------------------------------ (2) the grey ramp

func _ramp() -> void:
	_clear()
	var holder := WorldEnvironment.new()
	holder.environment = CandyLight.environment()
	_work.add_child(holder)
	var count := RAMP.size()
	for i in count:
		var quad := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(1, 4)
		quad.mesh = mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var v: float = RAMP[i]
		material.albedo_color = Color(v, v, v).linear_to_srgb()
		quad.material_override = material
		quad.position = Vector3(float(i) - float(count - 1) * 0.5, 0, 0)
		_work.add_child(quad)
	_camera(Vector3(0, 0, 10), Vector3.ZERO, 60.0, float(count))
	await frames(4)
	var image := root.get_texture().get_image()
	var worst := 0.0
	var line := ""
	for i in count:
		var px := int((float(i) + 0.5) / float(count) * float(image.get_width()))
		var got := _pixel(image, px, image.get_height() / 2)
		var v: float = RAMP[i]
		var want := CandyLook.screen_colour(Color(v, v, v))
		worst = maxf(worst, absf(got.g - want.g))
		line += " %.2f->%.3f(%.3f)" % [v, got.g, want.g]
	var anchors := CandyLook.screen_colour(Color(0.18, 0.18, 0.18)).g
	_verdict("grey ramp", worst <= RAMP_TOLERANCE, "scene-linear->sRGB measured(expected), worst %.4f:%s | grade anchors 0.18->%.3f (0.394) 0.5->%.3f (0.697) 1.0->%.3f (1.000: the shoulder is cut, see CandyLook.GRADE)" % [worst, line, anchors, CandyLook.screen_colour(Color(0.5, 0.5, 0.5)).g, CandyLook.screen_colour(Color(1, 1, 1)).g])

# ------------------------------------------------------------------ (3) lit and shadow anchors

## A floor of `albedo` under the full rig with a tall box on it: the screen colour of a lit and of a shadowed spot. Returns [lit, shadow].
func _floor(albedo: Color) -> Array:
	_clear()
	CandyLight.rig(_work, CandyLook.SUN_AZIMUTH)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	floor_mesh.mesh = plane
	floor_mesh.material_override = _plain(albedo)
	floor_mesh.material_override.roughness = 0.55
	_work.add_child(floor_mesh)
	var box := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(BOX_HALF * 2.0, BOX_HEIGHT, BOX_HALF * 2.0)
	box.mesh = box_mesh
	box.material_override = _plain(Color.WHITE)
	box.position = Vector3(0, BOX_HEIGHT * 0.5, 0)
	_work.add_child(box)
	var camera := _camera(Vector3(0, 40, 0), Vector3.ZERO, 60.0, 30.0, Vector3.FORWARD)
	await frames(5)
	var image := root.get_texture().get_image()
	var towards := CandyLook.towards(CandyLook.SUN_ELEVATION, CandyLook.SUN_AZIMUTH)
	var away := Vector3(-towards.x, 0, -towards.z).normalized()
	var lit_at := camera.unproject_position(-away * 8.0)
	var shadow_at := camera.unproject_position(away * 5.5)
	return [_pixel(image, int(lit_at.x), int(lit_at.y)), _pixel(image, int(shadow_at.x), int(shadow_at.y))]

func _floors() -> Dictionary:
	# the light itself: a mid grey probe (never clipped) gives the scene-linear light on an up-facing surface, lit and in shadow
	var grey := await _floor(Color(0.3, 0.3, 0.3).linear_to_srgb())
	var total_lit := CandyLook.scene_linear(grey[0] as Color)
	var total_shadow := CandyLook.scene_linear(grey[1] as Color)
	total_lit = Color(total_lit.r / 0.3, total_lit.g / 0.3, total_lit.b / 0.3)
	total_shadow = Color(total_shadow.r / 0.3, total_shadow.g / 0.3, total_shadow.b / 0.3)
	print("CANDY_LIGHT [%s] light on an up-facing surface, scene-linear: lit (%.3f %.3f %.3f)  shadow (%.3f %.3f %.3f)  (target: lit about (1.43 1.16 1.46), shadow about (0.57 0.46 0.97))" % [_tag, total_lit.r, total_lit.g, total_lit.b, total_shadow.r, total_shadow.g, total_shadow.b])
	var cases := {
		"white tile": [Color.WHITE, WHITE_LIT, WHITE_SHADOW],
		"blue floor": [_albedo_for(BLUE_LIT, total_lit), BLUE_LIT, BLUE_SHADOW],
		"orange floor": [_albedo_for(ORANGE_LIT, total_lit), ORANGE_LIT, ORANGE_SHADOW],
	}
	var ratios: Array = []
	for name: String in cases:
		var spec: Array = cases[name]
		var got := await _floor((spec[0] as Color).linear_to_srgb())
		var lit: Color = got[0]
		var shadow: Color = got[1]
		var ok := _near(lit, spec[1], ANCHOR_TOLERANCE) and _near(shadow, spec[2], ANCHOR_TOLERANCE)
		var ratio := _luma(shadow) / maxf(_luma(lit), 0.0001)
		ratios.append(ratio)
		_verdict(name, ok, "lit %s (want %s)  shadow %s (want %s)  luminance shadow/lit %.3f (albedo linear %.3f %.3f %.3f)" % [_hex(lit), _hex(spec[1]), _hex(shadow), _hex(spec[2]), ratio, (spec[0] as Color).r, (spec[0] as Color).g, (spec[0] as Color).b])
	var mean := 0.0
	for r: float in ratios: mean += r / float(ratios.size())
	_verdict("shadow / lit luminance", absf(mean - LUMA_TARGET) <= LUMA_TOLERANCE, "mean %.3f (target %.2f)" % [mean, LUMA_TARGET])
	return {"lit": total_lit, "shadow": total_shadow}

## The linear albedo that shows `screen` when lit by the scene-linear light `total`.
func _albedo_for(screen: Color, total: Color) -> Color:
	var want := CandyLook.scene_linear(screen)
	return Color(minf(want.r / maxf(total.r, 0.001), 1.0), minf(want.g / maxf(total.g, 0.001), 1.0), minf(want.b / maxf(total.b, 0.001), 1.0))

# ------------------------------------------------------------------ (5) the sky

func _sky() -> void:
	_clear()
	var holder := WorldEnvironment.new()
	holder.environment = CandyLight.environment()
	_work.add_child(holder)
	_work.add_child(CandyLight.sky_node(1.0))
	_camera(Vector3.ZERO, Vector3(0, -0.2126, -1), 60.0) # the show's standing view: pitched down 12.4 degrees, the frame holds the sky from the horizon (a third from the top) to 18 degrees
	await frames(4)
	var image := root.get_texture().get_image()
	var w := image.get_width()
	var h := image.get_height()
	var top := _pixel(image, w / 2, 4)
	var horizon_y := int(float(h) * (0.5 - tan(deg_to_rad(12.4)) / (2.0 * tan(deg_to_rad(30.0)))) * 1.0)
	var low := _pixel(image, w / 2, horizon_y + 10)
	var mid := _pixel(image, w / 2, horizon_y / 2)
	_verdict("sky", _near(top, SKY_TOP, 0.12) and _near(low, SKY_LOW, ANCHOR_TOLERANCE * 1.5), "top of a 12 degree pitched 60 degree frame %s (want about %s), a quarter down %s, at the horizon %s (want about %s)" % [_hex(top), _hex(SKY_TOP), _hex(mid), _hex(low), _hex(SKY_LOW)])
	if out != "": image.save_png("%s/%s%s_sky.png" % [out, prefix, _tag])
	# the same sky looking 25 degrees up, the middle of the frame holds the facets
	var camera := _camera(Vector3.ZERO, Vector3(0, 0.466, -1), 60.0)
	camera.current = true
	await frames(3)
	if out != "": root.get_texture().get_image().save_png("%s/%s%s_sky_up.png" % [out, prefix, _tag])

# ------------------------------------------------------------------ (4) the test scene

func _scenes() -> void:
	_clear()
	CandyLight.rig(_work, CandyLook.SUN_AZIMUTH)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	floor_mesh.mesh = plane
	var floor_material := _plain(Color.WHITE)
	floor_material.roughness = 0.55
	floor_mesh.material_override = floor_material
	_work.add_child(floor_mesh)
	var colours := [Color("#f4f0f4"), Color("#0066ff"), Color("#ff7100"), Color("#f40b6f"), Color("#8b187d")]
	for i in colours.size():
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(2.4, 2.4, 2.4)
		box.mesh = mesh
		var material := _plain(colours[i])
		material.roughness = 0.2
		material.metallic_specular = 0.5
		box.material_override = material
		box.position = Vector3(float(i) * 4.0 - 8.0, 1.2, 0)
		_work.add_child(box)
	var bean := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.5
	capsule.height = 1.9
	bean.mesh = capsule
	var bean_material := _plain(Color("#fa3774"))
	bean_material.roughness = 0.5
	bean_material.metallic_specular = 0.5
	bean.material_override = bean_material
	bean.position = Vector3(0, 0.95, 4.0)
	_work.add_child(bean)
	_camera(Vector3(-4, 7, 16), Vector3(0, 1.0, 0), 55.0)
	await frames(5)
	if out != "": root.get_texture().get_image().save_png("%s/%s%s_scene.png" % [out, prefix, _tag])
	_camera(Vector3(14, 6, -14), Vector3(0, 1.0, 0), 55.0)
	await frames(5)
	if out != "": root.get_texture().get_image().save_png("%s/%s%s_scene_back.png" % [out, prefix, _tag])
