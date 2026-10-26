extends Node3D
## EXPERIMENT (switchable): the look of the edge bumpers (levels/edge_bumpers.gd). It draws EXACTLY the capsules the hitbox is: every cushion is a tube of the pill's radius
## between the ends of its axis, with a ball of that radius at each corner or end, so what a courier touches is what it sees (no band proud of the surface, no extra rim).
## Soft rounded amber inflatable cushions (vinyl, the candy look's rail orange) with a white stripe along their top, resting on the deck (a bumper is amber, a launch pad pink: they never read alike); a touch (`pulse`) squeezes the cushion that was hit for a moment and flashes the whole ring.
##   EdgeBumpers                 this node, a child of the level's root (level-local coordinates), one per level
##     Platform<n>               one per bumpered platform, one material of its own (the flash)
##       Pill<n>_<side>          a tube, placed at the middle of its axis (Y along the axis); squeezes
##       Ball<n>_<i>             a ball on every distinct end point
## Look only: collision, launch and every number stay with levels/edge_bumpers.gd and levels/level_world.gd. Client only.
const EdgeBumpers := preload("res://levels/edge_bumpers.gd")
const CandyLook := preload("res://style/candy_look.gd")
const BODY := CandyLook.RAIL_ORANGE
const STRIPE := CandyLook.PROP_WHITE
const SIDES := 24                     ## the round of a tube and a ball
const SQUEEZE := 0.28                 ## how thin the hit tube gets at the deepest (share of its radius)
const T_IN := 0.07                    ## s: it squeezes ...
const T_OUT := 0.38                   ## s: ... and springs back with an overshoot
const IGNORE := 0.1                   ## s: a second pulse this soon after the first is the same bump
const SHADER := "shader_type spatial;\nuniform vec4 body_color : source_color = vec4(0.937, 0.525, 0.059, 1.0);\nuniform vec4 stripe_color : source_color = vec4(0.973, 0.957, 0.953, 1.0);\n" + \
	"uniform float flash = 0.0;\nvarying vec3 up_amount;\n" + """
void vertex() { up_amount = vec3(normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y); }
void fragment() {
	float top = smoothstep(0.66, 0.74, up_amount.x);
	vec3 c = mix(body_color.rgb, stripe_color.rgb, top);
	c = mix(c, vec3(1.0, 0.97, 0.9), flash * 0.5);
	ALBEDO = c;
	EMISSION = c * flash * 0.6;
	ROUGHNESS = 0.45;
}
"""

static var _shader: Shader
static var _ball: SphereMesh

var _platforms: Array = []            ## per platform: {material: ShaderMaterial, tubes: [Node3D], rest: [Basis], age: float, side: int}
var _plan: Dictionary = {}

## The look of `plan` (levels/edge_bumpers.gd plan(): the platforms and their pills) under `level_root`; null when the level has no cushions.
static func build(level_root: Node3D, plan: Dictionary) -> Node3D:
	if (plan.pills as Array).is_empty(): return null
	var look = new()
	look.name = "EdgeBumpers"
	look._plan = plan
	level_root.add_child(look)
	look._draw()
	return look

func _draw() -> void:
	var pills: Array = _plan.pills
	for platform: Dictionary in _plan.platforms:
		var group := Node3D.new()
		group.name = "Platform%d" % int(platform.id)
		add_child(group)
		var material := ShaderMaterial.new()
		material.shader = _the_shader()
		material.set_shader_parameter("body_color", BODY)
		material.set_shader_parameter("stripe_color", STRIPE)
		var entry := {"material": material, "tubes": [], "rest": [], "age": 99.0, "side": -1}
		var points: Array = []
		for index: int in platform.pills:
			var pill: Dictionary = pills[index]
			var a: Vector3 = pill.a
			var b: Vector3 = pill.b
			var tube := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = float(pill.rad)
			mesh.bottom_radius = float(pill.rad)
			mesh.height = a.distance_to(b)
			mesh.radial_segments = SIDES
			mesh.rings = 1
			mesh.cap_top = false
			mesh.cap_bottom = false
			tube.mesh = mesh
			tube.material_override = material
			var turn := Basis(Quaternion(Vector3.UP, (b - a).normalized()))
			tube.transform = Transform3D(turn, (a + b) * 0.5)
			tube.name = "Pill%d_%d" % [int(platform.id), int(pill.side)]
			group.add_child(tube)
			(entry.tubes as Array).append(tube)
			(entry.rest as Array).append(turn)
			for end: Vector3 in [a, b]:
				if not end in points: points.append(end)
		if _ball == null:
			_ball = SphereMesh.new()
			_ball.radius = EdgeBumpers.RADIUS
			_ball.height = EdgeBumpers.RADIUS * 2.0
			_ball.radial_segments = SIDES
			_ball.rings = SIDES / 2
		for index in points.size():
			var ball := MeshInstance3D.new()
			ball.mesh = _ball
			ball.material_override = material
			ball.position = points[index]
			ball.name = "Ball%d_%d" % [int(platform.id), index]
			group.add_child(ball)
		_platforms.append(entry)

static func _the_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	return _shader

## A courier bumped cushion `pill` (an index into the plan's pills): its tube squeezes, the platform's ring flashes.
func pulse(pill: int) -> void:
	var platform := int((_plan.pills[pill] as Dictionary).platform)
	var entry: Dictionary = _platforms[platform]
	if float(entry.age) < IGNORE: return # the same bump told twice (by the simulation and by the look's own watch)
	entry.age = 0.0
	entry.side = int((_plan.pills[pill] as Dictionary).side)
	set_process(true)

func _ready() -> void:
	set_process(false)

func _process(delta: float) -> void:
	var live := false
	for entry: Dictionary in _platforms:
		if float(entry.age) > T_IN + T_OUT:
			continue
		entry.age = float(entry.age) + delta
		var age: float = entry.age
		var press := 0.0 # 0 at rest, 1 deepest, a little negative on the way back (the overshoot)
		if age < T_IN: press = age / T_IN
		elif age < T_IN + T_OUT:
			var u := (age - T_IN) / T_OUT
			press = exp(-4.0 * u) * cos(TAU * 1.1 * u) * (1.0 - u)
		else: press = 0.0
		(entry.material as ShaderMaterial).set_shader_parameter("flash", clampf(press, 0.0, 1.0))
		for index in (entry.tubes as Array).size():
			var tube: Node3D = entry.tubes[index]
			var squeezed: bool = index == int(entry.side) # the pills of a platform are in side order
			var thin := 1.0 - SQUEEZE * press if squeezed else 1.0
			tube.transform = Transform3D((entry.rest[index] as Basis) * Basis.from_scale(Vector3(thin, 1.0, thin)), tube.position)
		live = live or float(entry.age) <= T_IN + T_OUT
	if not live: set_process(false)
