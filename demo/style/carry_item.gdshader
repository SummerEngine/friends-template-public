shader_type spatial;
// Carried painting: flat vertex colours (frame, canvas back), three light bands, no specular. Vertices with
// COLOR.a < 0.5 are the canvas front: they show the picture (carry_paintings.png), self-lit so it reads in shade.
// The ink outline is the next_pass (carry_item_outline.gdshader). Pure look.
render_mode cull_back, diffuse_lambert;
uniform sampler2D picture : source_color, filter_linear;
uniform float lift : hint_range(0.0, 1.0) = 0.12; // self-light so the shaded side still reads
uniform float picture_lift : hint_range(0.0, 1.0) = 0.55;
uniform float strength = 1.0;

void fragment() {
	if (COLOR.a < 0.5) {
		ALBEDO = texture(picture, UV).rgb;
		EMISSION = ALBEDO * picture_lift;
	} else {
		ALBEDO = pow(COLOR.rgb, vec3(2.2)); // palette is authored in sRGB
		EMISSION = ALBEDO * lift;
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float nl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float band = 0.45 * smoothstep(0.12, 0.16, nl) + 0.55 * smoothstep(0.55, 0.6, nl);
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * band * strength / PI;
}
