extends RefCounted
## The lobby yard's light. The facility look keeps the levels' own light (nothing to do here). The comic look (dev runs) swaps in a
## phase-scoped comic sky (style/ink_sky.gdshader), paper-cream ambient and two directional lights; every property it changes is
## restored in rounds.
const SKY = preload("res://style/ink_sky.gdshader")
const SAVED := ["background_mode", "sky", "fog_enabled", "ambient_light_source", "ambient_light_color", "ambient_light_energy", "tonemap_mode"]
var _environment: Environment
var _saved := {}
var _level_suns: Array[DirectionalLight3D] = []
var _sun_visibility: Array[bool] = []
var _lights: Array[DirectionalLight3D] = []
var _active := false
var _sky: Sky

func build(world: Node3D, parent: Node3D) -> void:
	if not preload("res://style/surfaces.gd").ink(): return # the facility look lights the yard like the levels (levels/level_environment.gd)
	for child: Node in world.get_children():
		if child is WorldEnvironment: _environment=child.environment
		if child is DirectionalLight3D:
			_level_suns.append(child)
			_sun_visibility.append(child.visible)
	if _environment == null: return
	var mat:=ShaderMaterial.new();mat.shader=SKY
	_sky=Sky.new();_sky.sky_material=mat
	for spec in [[Vector3(-.5,.67,.55),Color("fffaf0"),1.1,true],[Vector3(.55,.45,-.70),Color("dce6ee"),.35,false]]:
		var light:=DirectionalLight3D.new()
		light.name="DepotSun" if spec[3] else "DepotFill"
		light.light_color=spec[1];light.light_energy=spec[2];light.shadow_enabled=spec[3]
		parent.add_child(light)
		if bool(spec[3]):
			preload("res://style/friends_style.gd").apply_quality(light)
			light.shadow_blur=1.0
		light.global_basis=Basis.looking_at(-(spec[0] as Vector3).normalized(),Vector3.UP)
		light.visible=false
		_lights.append(light)

func set_active(on: bool) -> void:
	if _environment==null or on==_active:return
	_active=on
	if on:
		for key: String in SAVED: _saved[key]=_environment.get(key)
		_environment.background_mode=Environment.BG_SKY;_environment.sky=_sky
		_environment.fog_enabled=false # the level fog cannot wash the paper sky
		_environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
		_environment.ambient_light_color=Color("fff4dc");_environment.ambient_light_energy=.8
		_environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
		for i in _level_suns.size():
			_sun_visibility[i]=_level_suns[i].visible
			_level_suns[i].visible=false
	else:
		for key: String in _saved: _environment.set(key,_saved[key])
		for i in _level_suns.size(): _level_suns[i].visible=_sun_visibility[i]
	for light: DirectionalLight3D in _lights:light.visible=on
