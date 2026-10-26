extends RefCounted
## Materials of the course surface (style/candy_surface.gdshader) made from a plain dictionary of its uniforms, so no look file builds a ShaderMaterial by hand. Colours may be a Color or
## a hex string; every other key is a uniform name of the shader (docs in its header). The three material families come with their roughness from style/candy_look.gd:
##   CandyMaterial.plastic("#c32258")                      hard plastic, 0.11
##   CandyMaterial.vinyl("#ffb308")                        inflatable, 0.45
##   CandyMaterial.tile("#13acd6")                         hexagon tile: 0.55, 30 % self light, the pink rim
##   CandyMaterial.make({"albedo": "#1aa8f4", "roughness": 0.3, "pattern": 1, "albedo2": "#ffffff", "pattern_period": 0.6})   anything else
## `extra` of the presets overrides or adds uniforms. Materials are shared: the same dictionary gives the same ShaderMaterial, so a level's surfaces cost one material per colour and pattern.
const SHADER := preload("res://style/candy_surface.gdshader")
const CandyLook := preload("res://style/candy_look.gd")
## NEAR DISSOLVE (style/near_dissolve.gdshaderinc): nothing of the look may hide the courier from the follow camera. `NEAR_TALL`: posts, beams, walls, signs, arches, bars: gone nearer than 4 m to
## the eye, whole from 7.5 m (the camera of the stage view hangs 5 to 7 m over its courier and the shoulder view's arm is 5.4 m: a piece that near is in its way). `NEAR_FLOOR`: floors and the
## surfaces under the courier's feet: the nearest floor on the screen of the stage view is 6.3 m from the eye even at its flattest pitch (the camera hangs 3.7 to 12 m over the feet), so only a floor that really comes up against the camera (a drop beside the start platform) thins out. `NEAR_FLOOR_LOW`: the lobby yard's deck, under the shoulder view (the eye 3.4 m over the feet, the deck at the bottom of the screen about 5 m away). The uniforms are merged into a
## surface's spec; a surface without them keeps `near_whole` 0 of candy_surface.gdshader: no dissolve (backdrop, podium).
const NEAR_TALL := {"near_gone": 4.0, "near_whole": 7.5}
const NEAR_FLOOR := {"near_gone": 4.0, "near_whole": 5.5}
const NEAR_FLOOR_LOW := {"near_gone": 3.0, "near_whole": 4.0}
const COLOUR_KEYS := ["albedo", "albedo2", "rim_color"]

static var _made := {}

static func make(spec: Dictionary) -> ShaderMaterial:
	var key := var_to_str(spec)
	if _made.has(key): return _made[key]
	var material := ShaderMaterial.new()
	material.shader = SHADER
	if spec.get("use_vertex_color", false) == true and RenderingServer.get_current_rendering_method() == "gl_compatibility": material.set_shader_parameter("vertex_color_srgb", false) # Compatibility hands COLOR over linear
	for name: String in spec:
		var value: Variant = spec[name]
		material.set_shader_parameter(name, Color(str(value)) if name in COLOUR_KEYS and not value is Color else value)
	_made[key] = material
	return material

static func plastic(colour: Variant, extra := {}) -> ShaderMaterial:
	return make(_merged({"albedo": colour, "roughness": CandyLook.ROUGH_PLASTIC}, extra))

static func vinyl(colour: Variant, extra := {}) -> ShaderMaterial:
	return make(_merged({"albedo": colour, "roughness": CandyLook.ROUGH_VINYL}, extra))

static func tile(colour: Variant, extra := {}) -> ShaderMaterial:
	return make(_merged({"albedo": colour, "roughness": CandyLook.ROUGH_TILE, "self_light": CandyLook.HEX_SELF_LIGHT, "rim_color": CandyLook.HEX_RIM_COLOR, "rim_power": CandyLook.HEX_RIM_POWER}, extra))

static func _merged(base: Dictionary, extra: Dictionary) -> Dictionary:
	var out := base.duplicate()
	out.merge(extra, true)
	return out

## Switches the near dissolve on for the StandardMaterial3D surfaces of every mesh under `root` (the level's or the lobby's decor: posters, banners, billboards, arches, signs, the hero prop: pieces
## that wear no candy shader): a pixel dither (BaseMaterial3D distance fade, decided per fragment) gone nearer than NEAR_TALL.near_gone m, whole from near_whole. A flat mesh (under 0.5 m high:
## a pad, a decal, a floor mark) takes the NEAR_FLOOR distances; a material that any tall mesh wears is tall. The candy shaders carry the dissolve in their own uniforms (see NEAR_TALL).
## Returns the number of materials switched.
static func dissolve_tree(root: Node) -> int:
	var tall := {}
	var flat := {}
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null: continue
		var is_flat := instance.get_aabb().size.y * instance.global_transform.basis.y.length() < 0.5
		var found: Array[Material] = [instance.material_override]
		for surface in instance.mesh.get_surface_count():
			found.append(instance.get_surface_override_material(surface))
			found.append(instance.mesh.surface_get_material(surface))
		for material: Material in found:
			if material is StandardMaterial3D:
				if is_flat: flat[material] = true
				else: tall[material] = true
	for material: StandardMaterial3D in tall: _fade(material, NEAR_TALL)
	for material: StandardMaterial3D in flat:
		if not tall.has(material): _fade(material, NEAR_FLOOR)
	return tall.size() + flat.size()

static func _fade(material: StandardMaterial3D, near: Dictionary) -> void:
	material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	material.distance_fade_min_distance = float(near.near_gone)
	material.distance_fade_max_distance = float(near.near_whole)
