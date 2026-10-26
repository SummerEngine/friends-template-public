// The characters' own material (when the game look has none): the flat saturated toy colours of the art proofs under any
// scene light. Soft wrapped diffuse, almost no specular, a little light of its own (`fill`) so faces and eye whites never
// sink into shade, and a soft rim (`rim`) so the silhouette reads against the ground. Colours are sRGB like the art.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, hint_default_white;
uniform bool use_vertex_color = false;
uniform float roughness_value = 0.85;
uniform float fill = 0.3;
uniform float rim = 0.35;

void fragment() {
	vec3 color = albedo.rgb * texture(albedo_tex, UV).rgb;
	if (use_vertex_color) color *= COLOR.rgb;
	ALBEDO = color;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	SPECULAR = 0.15;
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = color * (fill + rim * edge);
}
