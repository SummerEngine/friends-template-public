shader_type spatial;
// The carried glass pane (style/carry_item.gd, item "glass") and its shards: clear glass with a faint blue-green body, a
// fresnel sheen with a soft sky reflection, a teal band along the pane's border and on the cut edges of the shards, two
// glare streaks and, in the middle, the team's print: an alpha etch (alpha = frost, clear glass where it is transparent) or an
// opaque print on a frosted panel (a fragile-glass mark without a picture).
// No screen texture and no refraction: it draws the same on the mobile and the gl_compatibility renderers.
// UV = (along the pane, down the pane) over the visible pane (tools/build_painting_items.py); COLOR.a < 0.75 marks the cut
// edges of a shard.
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

uniform sampler2D picture : source_color, filter_linear_mipmap, repeat_disable;
uniform bool has_picture = false;
uniform bool alpha_etch = false; // the picture's alpha is the frost: no panel
uniform vec2 pane_size = vec2(2.94, 1.2); // metres: along, across
uniform vec2 panel_size = vec2(1.44, 0.72); // the print's area in the middle, 2:1 (carry_item.gd PANEL, ETCH_PANEL)
uniform vec3 body : source_color = vec3(0.6, 0.88, 0.84);
uniform vec3 edge : source_color = vec3(0.12, 0.55, 0.52);
uniform vec3 frost : source_color = vec3(0.93, 0.97, 0.97);
uniform float body_alpha : hint_range(0.0, 1.0) = 0.16;
uniform float edge_alpha : hint_range(0.0, 1.0) = 0.8;
uniform float edge_width = 0.07; // metres
uniform float frost_alpha : hint_range(0.0, 1.0) = 0.6;
uniform float etch_alpha : hint_range(0.0, 1.0) = 0.85;

float segment(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	return length(p - a - ab * clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0));
}

// The fragile-glass mark (a cracked goblet), 1 inside. p: y up, the mark about 1.4 tall around the origin.
float glass_mark(vec2 p) {
	float bowl = step(length(p - vec2(0.0, 0.28)), 0.42) * step(p.y, 0.6);
	float stem = step(abs(p.x), 0.05) * step(-0.62, p.y) * step(p.y, 0.0);
	float foot = step(abs(p.x), 0.3) * step(-0.72, p.y) * step(p.y, -0.6);
	float crack = min(min(segment(p, vec2(-0.1, 0.62), vec2(0.07, 0.42)), segment(p, vec2(0.07, 0.42), vec2(-0.06, 0.26))),
		segment(p, vec2(-0.06, 0.26), vec2(0.05, 0.1)));
	return max(max(bowl * step(0.035, crack), stem), foot);
}

void fragment() {
	vec2 m = UV * pane_size;
	float edge_d = min(min(m.x, pane_size.x - m.x), min(m.y, pane_size.y - m.y));
	float band = max(1.0 - smoothstep(0.0, edge_width, edge_d), step(COLOR.a, 0.75));
	float bevel = (1.0 - smoothstep(0.0, 0.012, abs(edge_d - edge_width))) * (1.0 - step(COLOR.a, 0.75));
	float d = m.x - m.y * 1.2;
	float glare = 0.7 * (1.0 - smoothstep(0.0, 0.07, abs(d - 0.55))) + (1.0 - smoothstep(0.0, 0.025, abs(d - 0.78)))
		+ 0.5 * (1.0 - smoothstep(0.0, 0.05, abs(d - 2.25)));
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 reflected = (INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).xyz;
	vec3 sky = mix(vec3(0.7, 0.8, 0.84), vec3(1.0), smoothstep(-0.2, 0.7, reflected.y));

	vec3 color = mix(body, edge, band);
	float alpha = mix(body_alpha, edge_alpha, band);
	float rough = 0.05;
	// the print in the middle: an alpha etch on clear glass, else a frosted panel with an etched rule
	vec2 q = (m - (pane_size - panel_size) * 0.5) / panel_size;
	vec2 inner = min(q, 1.0 - q) * panel_size;
	if (min(inner.x, inner.y) > 0.0 && COLOR.a > 0.75 && has_picture && alpha_etch) {
		vec4 art = texture(picture, q);
		color = mix(color, mix(art.rgb, frost, 0.12), art.a);
		alpha = mix(alpha, etch_alpha, art.a);
		rough = mix(rough, 0.6, art.a);
	} else if (min(inner.x, inner.y) > 0.0 && COLOR.a > 0.75) {
		color = frost;
		alpha = frost_alpha;
		rough = 0.6;
		float rule = 1.0 - smoothstep(0.0, 0.008, abs(min(inner.x, inner.y) - 0.03));
		vec4 art = vec4(edge, glass_mark(vec2((q.x - 0.5) * panel_size.x / panel_size.y, 0.5 - q.y) * 2.2));
		if (has_picture) {
			art = texture(picture, q);
			art.rgb = mix(art.rgb, frost, 0.12); // printed into the frost
		}
		color = mix(color, art.rgb, art.a * 0.92);
		alpha = mix(alpha, 0.94, art.a);
		color = mix(color, edge, rule);
		alpha = max(alpha, rule * 0.8);
	}
	color = mix(color, vec3(1.0), clamp(glare + bevel, 0.0, 1.0) * 0.8);
	alpha = clamp(alpha + 0.28 * glare + 0.4 * bevel + 0.55 * fresnel, 0.0, 0.96);
	ALBEDO = color;
	ALPHA = alpha;
	ROUGHNESS = rough;
	SPECULAR = 0.6;
	EMISSION = color * 0.12 + sky * fresnel * 0.5;
}
