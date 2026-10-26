shader_type spatial;
// The carried painting in the facility look (style/carry_item.gd): the frame and the canvas back in their palette colours
// (vertex colour, authored in sRGB), lacquered; vertices with COLOR.a < 0.5 are the canvas front, a matte print of the picture.
render_mode cull_back;
uniform sampler2D picture : source_color, filter_linear_mipmap;

void fragment() {
	if (COLOR.a < 0.5) {
		ALBEDO = texture(picture, UV).rgb;
		ROUGHNESS = 0.8;
	} else {
		ALBEDO = pow(COLOR.rgb, vec3(2.2));
		ROUGHNESS = 0.38;
	}
}
