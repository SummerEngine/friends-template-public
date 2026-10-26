extends RefCounted
## The menu pet in the game's look. When the look has FriendsStyle.character_material(kind, color, texture) for a part
## (demo/style/friends_style.gd; the comic look of dev runs has one), the part takes it: kinds "pet" (the model), "hat"
## (the cap's cloth) and "hat_logo" (its front print). Without one (the facility look), the characters' own soft toy
## material (character/character_soft.gdshader), like the players: flat saturated colours, soft light, no ink line.
##   PetLook.dress(model)                  # every surface of the pet model, keeping its colours and albedo textures
##   PetLook.material(color)               # one cap part
##   PetLook.styled(kind, color, texture)  # the game look's material, null without one
const SOFT := preload("res://character/character_soft.gdshader")
const STYLE := "res://style/friends_style.gd"
const STYLE_HOOK := "character_material"
## Checks only: stands in for FriendsStyle.character_material.
static var style_hook := Callable()
static var _found: Variant = null ## Callable of FriendsStyle.character_material, or false without one

static func dress(model: Node) -> void:
	for mesh_instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh_instance.mesh == null: continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.get_active_material(surface)
			var color := Color.WHITE
			var picture: Texture2D = null
			if source is BaseMaterial3D:
				color = (source as BaseMaterial3D).albedo_color
				picture = (source as BaseMaterial3D).albedo_texture
			var look := styled("pet", color, picture)
			mesh_instance.set_surface_override_material(surface, look if look != null else soft(color, picture))

## A cap part in `color`: the game look's "hat", else the soft toy material.
static func material(color: Color) -> Material:
	var look := styled("hat", color)
	return look if look != null else soft(color)

## The characters' own soft toy material in `color` (and `picture`).
static func soft(color: Color, picture: Texture2D = null) -> ShaderMaterial:
	var look := ShaderMaterial.new()
	look.shader = SOFT
	look.set_shader_parameter("albedo", color)
	if picture != null: look.set_shader_parameter("albedo_tex", picture)
	return look

## The game look's material for a part (FriendsStyle.character_material), or null when the look has none.
static func styled(kind: String, color: Color, texture: Texture2D = null) -> Material:
	var hook := style_hook
	if not hook.is_valid():
		if _found == null:
			_found = false
			var style: Script = load(STYLE) if ResourceLoader.exists(STYLE) else null
			for method: Dictionary in (style.get_script_method_list() if style != null else []):
				if str(method.get("name", "")) == STYLE_HOOK: _found = Callable(style, STYLE_HOOK)
		if _found is Callable: hook = _found
	if not hook.is_valid(): return null
	return hook.call(kind, color, texture) as Material
