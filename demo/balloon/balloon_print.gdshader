shader_type spatial;
// The team's print on the floating thing (balloon/balloon_look.gd): a round sticker that turns to face each camera and sits `lift`
// metres towards it from the body's centre, so from every view it reads as printed on the front. Unshaded, cut out at the circle.
render_mode unshaded, cull_disabled, shadows_disabled;
uniform sampler2D print_texture : source_color, filter_linear_mipmap;
uniform float lift = 0.6;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX.z += lift;
}

void fragment() {
	vec4 tint = texture(print_texture, UV);
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
