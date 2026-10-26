shader_type spatial;
// Inverted-hull outline for the carried item. The hull grows along the smooth normal that
// carry_item.gd stores in TANGENT, so flat-shaded corners stay closed.
render_mode cull_front, unshaded, depth_draw_opaque;
uniform vec4 ink_color : source_color = vec4(0.16, 0.09, 0.07, 1.0);
uniform float width = 0.012;

void vertex() {
	// the canvas (picture 0, torn edges 0.75) has no outline: the frame draws the ink, no seams between pieces
	if (COLOR.a >= 0.9) {
		float depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
		VERTEX += normalize(TANGENT) * width * clamp(depth * 0.15, 0.6, 3.0);
	}
}

void fragment() {
	ALBEDO = ink_color.rgb;
}
