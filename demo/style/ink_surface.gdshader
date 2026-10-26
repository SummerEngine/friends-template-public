shader_type spatial;
// Ink: flat paper colours with screen-space halftone shadows.
// mode 0 plain block (flag pole and cloth), 3 character (courier body parts), 13 ground paint ring (drawn on a flat quad's UV).
// Outline is a separate next_pass. Mode 0 and 13 colours pass through the calm palette switch (calm_palette.gdshaderinc);
// characters and ink lines never do.
render_mode diffuse_lambert, specular_disabled;
#include "res://style/calm_palette.gdshaderinc"
uniform int mode = 0;
uniform vec4 base_color : source_color = vec4(0.17, 0.29, 1.0, 1.0);
uniform vec4 alt_color : source_color = vec4(1.0, 0.82, 0.25, 1.0);
uniform vec4 ink_color : source_color = vec4(0.106, 0.114, 0.227, 1.0);
uniform vec3 half_size = vec3(0.5);
uniform float dot_cell = 7.0;

void fragment() {
	vec3 col = base_color.rgb;
	if (mode == 0) {
		col = calm_color(base_color.rgb);
	} else if (mode == 13) {
		// Ground paint (flat quad, UV 0..1): a ring of alternating dashes between ink lines.
		vec2 p = UV * 2.0 - 1.0;
		float r = length(p);
		if (r > 0.98 || r < 0.78) discard;
		float dash = mod(floor((atan(p.y, p.x) / 6.2831853 + 0.5) * 24.0), 2.0);
		col = calm_color(dash < 0.5 ? base_color.rgb : alt_color.rgb);
		if (r > 0.94 || r < 0.82) col = ink_color.rgb;
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
}

void light() {
	float nl = clamp(dot(NORMAL, LIGHT) * ATTENUATION, 0.0, 1.0);
	float shadow = 1.0 - smoothstep(0.12, 0.62, nl);
	vec2 p = FRAGCOORD.xy / dot_cell;
	p = vec2(p.x * 0.7071 + p.y * 0.7071, -p.x * 0.7071 + p.y * 0.7071);
	vec2 g = fract(p) - 0.5;
	float r = length(g);
	float radius = sqrt(shadow) * 0.72;
	float aa = 0.12;
	float ink = 1.0 - smoothstep(radius - aa, radius + aa, r);
	ink *= step(0.02, shadow);
	DIFFUSE_LIGHT += mix(vec3(1.0), ink_color.rgb * 1.6, ink);
}
