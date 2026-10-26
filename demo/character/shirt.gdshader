// The character's shirt: one colour, an optional all-over print (RGBA, alpha = coverage), an optional chest picture
// (the team logo) drawn into `logo_rect` and an optional motto (alpha = ink) in `motto_ink` drawn into `motto_rect` (uv x, y,
// width, height). With `trim` on, the sleeve ends and the collar are `trim_color`: the body's shirt carries how far each
// point is from them in its vertex colours (r: sleeve end, g: collar; alpha 0.5 marks them; meshes without them have white
// vertex colours and get no trim). An outfit moves and scales the chest print (print, logo, motto) by `chest_move` (uv shift
// x, y and scale around `chest_pivot`), so its own details (a hoodie's cords) do not cover it. Soft and matte, lit like
// character_soft.gdshader.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D print_tex : source_color, filter_linear_mipmap, hint_default_transparent;
uniform sampler2D logo_tex : source_color, filter_linear_mipmap, repeat_disable, hint_default_transparent;
uniform vec4 logo_rect = vec4(0.0, 0.0, 0.0, 0.0);
uniform sampler2D motto_tex : filter_linear_mipmap, repeat_disable, hint_default_transparent;
uniform vec4 motto_rect = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 motto_ink : source_color = vec4(0.11, 0.11, 0.16, 1.0);
uniform vec3 chest_move = vec3(0.0, 0.0, 1.0);
uniform vec2 chest_pivot = vec2(0.315, 0.75);
uniform float trim = 0.0;
uniform vec4 trim_color : source_color = vec4(1.0);
uniform float sleeve_band = 0.12;
uniform float collar_band = 0.2;
uniform float roughness_value = 0.85;
uniform float fill = 0.3;
uniform float rim = 0.35;

void fragment() {
	vec2 chest_uv = (UV - chest_pivot - chest_move.xy) / max(chest_move.z, 0.01) + chest_pivot;
	vec4 print_color = texture(print_tex, chest_uv);
	vec3 color = mix(base_color.rgb, print_color.rgb, print_color.a);
	if (trim > 0.0 && COLOR.a < 0.75) {
		float sleeve = 1.0 - smoothstep(sleeve_band - fwidth(COLOR.r), sleeve_band, COLOR.r);
		float collar = 1.0 - smoothstep(collar_band - fwidth(COLOR.g), collar_band, COLOR.g);
		color = mix(color, trim_color.rgb, max(sleeve, collar));
	}
	if (logo_rect.z > 0.0 && logo_rect.w > 0.0) {
		vec2 logo_uv = (chest_uv - logo_rect.xy) / logo_rect.zw;
		if (logo_uv.x >= 0.0 && logo_uv.x <= 1.0 && logo_uv.y >= 0.0 && logo_uv.y <= 1.0) {
			vec4 logo = texture(logo_tex, logo_uv);
			color = mix(color, logo.rgb, logo.a);
		}
	}
	if (motto_rect.z > 0.0 && motto_rect.w > 0.0) {
		vec2 motto_uv = (chest_uv - motto_rect.xy) / motto_rect.zw;
		if (motto_uv.x >= 0.0 && motto_uv.x <= 1.0 && motto_uv.y >= 0.0 && motto_uv.y <= 1.0) {
			color = mix(color, motto_ink.rgb, texture(motto_tex, motto_uv).a);
		}
	}
	ALBEDO = color;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	SPECULAR = 0.15;
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = color * (fill + rim * edge);
}
