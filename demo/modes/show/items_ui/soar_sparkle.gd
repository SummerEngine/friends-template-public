extends RefCounted
## Shared by the BOOST and SOAR looks: additive four-point sparkles (a camera-facing star drawn by a shader, tinted by the particle's colour) and the particles that emit them.
## Everything here is client-side decoration of an effect; nothing in it decides anything.

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * scale.x, INV_VIEW_MATRIX[1] * scale.y, INV_VIEW_MATRIX[2] * scale.z, MODEL_MATRIX[3]);
}
void fragment() {
	vec2 p = UV - 0.5;
	float d = pow(abs(p.x), 0.5) + pow(abs(p.y), 0.5);
	float star = 1.0 - smoothstep(0.08, 0.62, d);
	float core = exp(-dot(p, p) * 70.0);
	ALBEDO = COLOR.rgb * (star + core * 0.8) * 1.6;
	ALPHA = clamp(COLOR.a, 0.0, 1.0);
}
"""

static var _shader: Shader
static var _quad: QuadMesh
static var _material: ShaderMaterial

static func material() -> ShaderMaterial:
	if _material == null:
		_shader = Shader.new()
		_shader.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = _shader
	return _material

static func quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
		_quad.material = material()
	return _quad

## A sparkle emitter: `amount` stars over `lifetime` s, born inside a sphere of `radius` m, drifting at `speed` m/s (`up`: an extra upward drift), `size` m across, along the colour ramp `colors`
## (alpha fades them out). Not parented yet; `local_coords` is off, so what it emits stays where it was born.
static func emitter(amount: int, lifetime: float, radius: float, speed: Vector2, size: Vector2, colors: PackedColorArray, up := 0.0) -> CPUParticles3D:
	var parts := CPUParticles3D.new()
	parts.amount = amount
	parts.lifetime = lifetime
	parts.local_coords = false
	parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	parts.emission_sphere_radius = radius
	parts.direction = Vector3.UP
	parts.spread = 180.0
	parts.initial_velocity_min = speed.x
	parts.initial_velocity_max = speed.y
	parts.gravity = Vector3(0.0, up, 0.0)
	parts.scale_amount_min = size.x
	parts.scale_amount_max = size.y
	var ramp := Gradient.new()
	ramp.colors = colors
	var offsets := PackedFloat32Array()
	for index in colors.size(): offsets.append(float(index) / float(maxi(colors.size() - 1, 1)))
	ramp.offsets = offsets
	parts.color_ramp = ramp
	parts.mesh = quad()
	parts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return parts
