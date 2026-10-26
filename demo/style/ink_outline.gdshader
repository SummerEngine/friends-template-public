shader_type spatial;
// Ink: inverted-hull outline. boxy = true extrudes box proxies towards
// their corners (keeps corners closed); false extrudes along normals.
// world_units = true keeps the width in world metres on scaled nodes (a box stretched far
// along one axis would otherwise get a metre-thick outline along that axis).
render_mode cull_front, unshaded, depth_draw_opaque;
uniform vec4 ink_color : source_color = vec4(0.106, 0.114, 0.227, 1.0);
uniform float width = 0.035;
uniform bool boxy = true;
uniform bool world_units = false;

void vertex() {
	vec3 dir = boxy ? sign(VERTEX) : normalize(NORMAL);
	float depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
	float scale = clamp(depth * 0.075, 0.5, 5.0);
	vec3 axes = vec3(1.0);
	if (world_units) {
		axes = max(vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz)), vec3(0.0001));
	}
	VERTEX += dir * width * scale / axes;
}

void fragment() {
	ALBEDO = ink_color.rgb;
}
