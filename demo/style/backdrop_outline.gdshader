shader_type spatial;
// Ink line of a backdrop piece (next_pass of backdrop.gdshader): the body pushed out along its own direction from its centre, back faces
// only. Width is in screen pixels (about `line_px` at 1080 lines of height), so near and far pieces get the same thin line. The line takes
// on the haze with distance, like the piece itself.
render_mode cull_front, unshaded, fog_disabled, depth_draw_opaque;
#include "res://style/backdrop_motion.gdshaderinc"
uniform vec4 ink_color : source_color = vec4(0.106, 0.114, 0.227, 1.0);
uniform float line_px = 1.6;
varying float vdepth;

void vertex() {
	vec3 scale = max(vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz)), vec3(0.0001));
	float speed = INSTANCE_CUSTOM.w;
	if (abs(speed) > 0.001) {
		VERTEX += inverse(mat3(MODEL_MATRIX)) * drift_offset(MODEL_MATRIX[3].xyz, speed, TIME);
	}
	float depth = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	float width = depth * line_px * VIEWPORT_SIZE.y / 1080.0 * 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	VERTEX += normalize(VERTEX) * width / scale;
	vdepth = depth;
}

void fragment() {
	ALBEDO = mix(ink_color.rgb, haze_color(), haze_amount(vdepth) * 0.85);
}
