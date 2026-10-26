shader_type spatial;
// One PBR surface of the facility look (style/surfaces.gd): a CC0 texture set (albedo, normal, roughness) on UVs in metres that the
// mesh builder lays out in world axes (style/block_mesh.gd), so tiles run on across neighbouring blocks. The texture gives the
// detail, `tint` the colour: albedo = tint * texture / its mean brightness (`detail` scales the variation). Vertex colour can tint
// it further (foam blocks of one material in several colours). Optional extras: seams every `seam_every` metres (floor mats,
// panels), diagonal safety stripes, a painted band at a height over the floor (the team's colour on the walls), and contact
// shadows from the level's height field (style/height_field.gd): a top darkens where the floor rises next to it, a side where it
// meets the floor. The party look (style/party_look.gd) adds candy patterns in a second colour (checker, vertical stripes, bands, dots,
// all filtered so they do not shimmer) and a soft rim light. The night look (style/night_look.gd) adds thin glowing lines (patterns 5 to 7: grid,
// lines along u, lines along v, in `tint2`, emissive, over a two-tone checker of `tint` and `tint3`) and `emit` (the surface's own colour glows).
// Works the same on the Compatibility renderer.
render_mode blend_mix, depth_draw_opaque, cull_disabled; // two-sided: a camera that slips into a block still sees a solid block

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tile = 1.0;              // metres per texture repeat
uniform float mean = 0.5;              // mean linear brightness of albedo_tex
uniform float detail = 1.0;            // 0 flat colour .. 1 the texture's own variation
uniform float macro = 0.12;            // large, slow variation (the texture again, 7.3 times larger) so repeats do not show
uniform float vertex_tint = 0.0;       // 1: COLOR.rgb multiplies the colour
uniform float normal_depth = 1.0;
uniform float roughness = 1.0;         // multiplies the roughness map
uniform float roughness_add = 0.0;
uniform float metallic = 0.0;
uniform float specular = 0.5;
uniform float seam_every = 0.0;        // metres between seams, 0 none
uniform float seam_width = 0.012;
uniform float seam_dark = 0.45;
uniform float stripes = 0.0;           // 1: diagonal safety stripes in stripe_color
uniform vec4 stripe_color : source_color = vec4(0.05, 0.05, 0.05, 1.0);
uniform float stripe_width = 0.25;
uniform sampler2D height_map : filter_linear, repeat_disable;
uniform vec4 height_rect = vec4(0.0);  // world x, z of the field's corner, 1 / its size in metres (z = 0: no contact shadows)
uniform float ao = 0.0;                // strength of the contact shadows
uniform vec4 band_color : source_color = vec4(0.0); // a painted band on the sides (the team's brand colour), alpha 0 for none
uniform vec2 band = vec2(1.0, 1.3);    // its bottom and top in metres above the floor in front of the side
uniform int pattern = 0;               // 0 none, 1 checker, 2 vertical stripes (along u), 3 horizontal bands (along v), 4 dots, 5 glowing grid, 6 glowing lines along v (vertical on a wall), 7 glowing lines along u
uniform vec4 tint2 : source_color = vec4(1.0); // the pattern's second colour (the glowing lines' colour in patterns 5 to 7)
uniform vec4 tint3 : source_color = vec4(0.0); // patterns 5 to 7: the second tone of the checker between the lines, alpha 0 for one tone
uniform float line_width = 0.03;           // patterns 5 to 7: width of a glowing line in metres
uniform float glow = 0.0;              // patterns 5 to 7: how strongly the lines shine (emission, above 1 they bloom)
uniform float emit = 0.0;              // share of the surface's own colour that shines (any pattern)
uniform float pattern_size = 1.0;      // metres per stripe / check / dot cell
uniform float rim = 0.0;               // soft rim light of the candy surfaces
uniform int debug_view = 0;           // 1: contact shadows only, 2: the height field (white = 10 m, red = empty)

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float field(vec2 xz) {
	return texture(height_map, (xz - height_rect.xy) * height_rect.zw).r;
}

// 1 = open, lower = occluded. Tops look 0.25, 0.6 and 1.2 m out in four directions for a rise; sides look at the floor in front of them
// (how far above it they are) and left and right of it (a wall beside: an inner corner).
float contact(vec3 p, vec3 n) {
	if (height_rect.z <= 0.0 || ao <= 0.0) return 1.0;
	float occ = 0.0;
	if (n.y > 0.6) {
		vec2 dirs[4] = vec2[4](vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0));
		for (int i = 0; i < 4; i++) {
			float near = clamp((field(p.xz + dirs[i] * 0.25) - p.y) / 0.25, 0.0, 1.0);
			float mid = clamp((field(p.xz + dirs[i] * 0.6) - p.y) / 0.6, 0.0, 1.0);
			float far = clamp((field(p.xz + dirs[i] * 1.2) - p.y) / 1.2, 0.0, 1.0);
			occ += max(near, max(mid * 0.6, far * 0.3));
		}
		occ *= 0.6;
	} else if (n.y > -0.6) {
		vec2 out_dir = normalize(n.xz + vec2(1e-5));
		vec2 side = vec2(-out_dir.y, out_dir.x);
		vec2 front = p.xz + out_dir * 0.35;
		float above = p.y - field(front);
		occ += above < -0.15 ? 0.0 : (1.0 - smoothstep(0.0, 1.0, max(above, 0.0))) * 0.75;
		occ += clamp((field(front + side * 0.35) - p.y) / 0.35, 0.0, 1.0) * 0.3;
		occ += clamp((field(front - side * 0.35) - p.y) / 0.35, 0.0, 1.0) * 0.3;
	} else {
		occ = 0.5;
	}
	return 1.0 - clamp(occ, 0.0, 1.0) * ao;
}

float checker(vec2 q) {
	vec2 w = fwidth(q) + 1e-4;
	vec2 i = 2.0 * (abs(fract((q - 0.5 * w) * 0.5) - 0.5) - abs(fract((q + 0.5 * w) * 0.5) - 0.5)) / w;
	return 0.5 - 0.5 * i.x * i.y;
}

// 0..1 mask of a candy pattern's second colour, filtered by the pixel footprint.
float pattern_mask(vec2 p) {
	vec2 q = p / pattern_size;
	if (pattern == 1) return checker(q);
	if (pattern == 2 || pattern == 3) {
		float x = pattern == 2 ? q.x : q.y;
		float w = fwidth(x) * 0.5 + 1e-4;
		float d = abs(fract(x * 0.5) - 0.5) - 0.25;      // distance to the edges, in half periods
		return smoothstep(-w, w, d);
	}
	if (pattern == 4) {
		vec2 f = fract(q) - 0.5;
		float w = fwidth(q.x) + 1e-4;
		return 1.0 - smoothstep(0.3 - w, 0.3 + w, length(f));
	}
	return 0.0;
}

// x: the line's core (1 on it, filtered), y: its halo, for the glowing patterns 5 to 7.
vec2 glow_line(vec2 p) {
	vec2 q = p / pattern_size;
	vec2 d = abs(fract(q + 0.5) - 0.5) * pattern_size;   // metres to the nearest line along u and v
	float m = pattern == 5 ? min(d.x, d.y) : (pattern == 6 ? d.x : d.y);
	float w = fwidth(m) * 0.75 + 1e-4;
	float core = 1.0 - smoothstep(line_width * 0.5 - w, line_width * 0.5 + w, m);
	float halo = 1.0 - smoothstep(0.0, line_width * 4.0 + w, m);
	return vec2(core, halo * halo);
}

void fragment() {
	vec2 uv = UV / tile;
	vec3 tex = texture(albedo_tex, uv).rgb;
	vec3 colour = pattern > 0 && pattern < 5 ? mix(tint.rgb, tint2.rgb, pattern_mask(UV)) : tint.rgb;
	if (pattern >= 5 && tint3.a > 0.0) colour = mix(tint.rgb, tint3.rgb, checker(UV / pattern_size));
	vec3 base = colour * mix(vec3(1.0), tex / max(mean, 0.01), detail);
	float slow = dot(texture(albedo_tex, UV / (tile * 7.3) + vec2(0.37, 0.61)).rgb, vec3(0.333)) / max(mean, 0.01);
	base *= mix(1.0, clamp(slow, 0.6, 1.4), macro);
	if (vertex_tint > 0.0) base *= mix(vec3(1.0), pow(COLOR.rgb, vec3(2.2)), vertex_tint); // vertex colours are sRGB
	float rough = texture(rough_tex, uv).r * roughness + roughness_add;
	if (stripes > 0.0) {
		float s = step(0.5, fract((UV.x + UV.y) / (stripe_width * 2.0)));
		base = mix(base, stripe_color.rgb, s * stripes);
	}
	if (band_color.a > 0.0 && height_rect.z > 0.0 && abs(world_nrm.y) < 0.6) {
		vec2 out_dir = normalize(world_nrm.xz + vec2(1e-5));
		float ground = field(world_pos.xz + out_dir * 0.35);
		float up = world_pos.y - ground;
		float w = fwidth(up);
		float paint = smoothstep(band.x - w, band.x + w, up) * (1.0 - smoothstep(band.y - w, band.y + w, up)) * step(-100.0, ground);
		base = mix(base, band_color.rgb * mix(1.0, dot(tex, vec3(0.333)) / max(mean, 0.01), 0.25), paint * band_color.a);
		rough = mix(rough, 0.45, paint);
	}
	if (seam_every > 0.0) {
		vec2 cell = abs(fract(UV / seam_every + 0.5) - 0.5) * seam_every;
		float d = min(cell.x, cell.y);
		float w = fwidth(d);
		float line = 1.0 - smoothstep(seam_width, seam_width + w * 1.5, d);
		base *= 1.0 - line * seam_dark;
		rough = mix(rough, 1.0, line * 0.5);
	}
	float shade = contact(world_pos, normalize(world_nrm));
	ALBEDO = base * shade;
	vec3 shine = base * shade * emit;
	if (pattern >= 5 && glow > 0.0) {
		vec2 l = glow_line(UV);
		shine += tint2.rgb * glow * (l.x + l.y * 0.12);
	}
	EMISSION = shine;
	if (debug_view == 1) ALBEDO = vec3(shade) * 0.8;
	if (debug_view == 2) {
		float h = field(world_pos.xz);
		ALBEDO = vec3(0.0);
		EMISSION = h < -100.0 ? vec3(1.0, 0.0, 0.0) : vec3(clamp(h / 10.0, 0.0, 1.0), clamp(h + 1.0, 0.0, 1.0) * 0.3, 0.2);
	}
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = metallic;
	SPECULAR = specular;
	RIM = rim;
	RIM_TINT = 0.6;
}
