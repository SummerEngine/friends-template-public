shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://style/near_dissolve.gdshaderinc"
// The course surface of the daylight look: flat authored colour, glossy, lit by the engine's own Burley diffuse and GGX specular (the same model the look is made of), plus
// the things the engine does not give: an additive rim, a self-light, a fake pillow bulge and a handful of flat decal patterns (stripes, chevrons, checker, dots, rings, guide lines).
// No texture, no outline, no ramp. Numbers per family: style/candy_look.gd.
//   hard plastic roughness 0.11 | inflatable 0.32-0.65 (0.45) | hexagon tile 0.55 + self_light 0.3 + rim #FF80FF p4 | felt 1.0
// COLOUR   `albedo` is the authored sRGB colour, `albedo2` the second colour of a pattern. `use_vertex_color`: the mesh's COLOR (written as sRGB, the way the block kit and the pillow
//          builders write it) multiplies the albedo; the colours are screen colours: do not bake light into them.
// PATTERN  `pattern` 0 none | 1 stripes (diagonal bars of `albedo2` over `albedo`) | 2 chevron (the same bars mirrored about the middle of a face: needs the box builder's edge data in UV2,
//          style/block_mesh.gd Batch.box `edge_data`: x = depth under the top edge, y = distance to the nearest upright edge) | 3 checker | 4 dots | 5 rings (UV = the unit disc of a cylinder cap:
//          concentric rings, `pattern_period` as a share of the radius) | 6 lines (guide lines `pattern_width` wide every `pattern_period` m on a top: along both axes) | 7 border (a band of `pattern_width` m
//          along the edge of a top, from UV2).
//          UV is metres along the face unless said otherwise (the mesh builders lay it out in level / body axes, so a pattern runs on across blocks that line up).
//          `pattern_duty` is the share of a period `albedo2` takes (stripes, dots: the dot's diameter share), `pattern_slope` the stripe slope (m of depth per m across; 1 = 45 degrees),
//          `pattern_angle` (degrees, pattern 1 only) turns the stripes about the face's normal.
// RIM      additive `rim_color * pow(1 - N.V, rim_power)`: ONLY on hexagon tiles; everything else leaves `rim_color` black.
// GLARE    the analytic sky probe: additive `glare_color * fresnel(N.V)` (a pale cyan, the horizon sky) so a grazing floor brightens to light cyan towards its far edge, plus a small crisp glint where
//          the view's reflection meets the sun (`sun_dir`, world space): the soft sheen and the glint of glossy plastic that a flat 0.11-roughness floor does not show under a sun this high.
//          A soft broad lobe (`patch_color`, pow 14) adds a glare patch on the floors; it ignores shadows, so it is kept weak. Scaled by the glossiness (1 at roughness 0.1, half at 0.4, nearly none for 0.55 tiles and felt). Plain scene-linear numbers, no texture, no probe: the same
//          picture on Mobile and Compatibility. `glare` 0 switches it off.
// CREASE   `crease` 1 darkens to navy (`crease_color`) where the normal's upward part is between 0.1 and 0.6 (steeper than a 45 degree chamfer, not yet a wall): the pinched seam of two mats,
//          a few pixels wide, so a floor has a few dark accents as seams.
// NEAR     `near_whole` > 0 dissolves the surface near the eye (style/near_dissolve.gdshaderinc): gone nearer than `near_gone` m, whole from `near_whole` m; 0 = off (the default: only the course and the lobby switch it on, CandyMaterial.NEAR_TALL / NEAR_FLOOR).
// BULGE    a fake pillow where the mesh has no real bevel: tilts the normal towards the edge of the face's UV rectangle (UV 0..1 per face; meshes with UV in metres use real chamfers instead).
uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 albedo2 : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform bool vertex_color_srgb = true;   // false on Compatibility, whose COLOR attribute arrives already linear (CandyMaterial.make sets it)
uniform float roughness : hint_range(0.0, 1.0) = 0.11;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform vec3 rim_color : source_color = vec3(0.0);
uniform float rim_power : hint_range(0.5, 8.0) = 4.0;
uniform float self_light : hint_range(0.0, 1.0) = 0.0;
uniform float glare : hint_range(0.0, 3.0) = 1.0;
uniform vec3 glare_color = vec3(0.06, 0.75, 0.90);   // linear: the horizon sky as the floor reflects it
uniform float glare_power : hint_range(0.5, 8.0) = 5.0;
uniform vec3 sun_dir = vec3(-0.4207, 0.8746, 0.2429); // world space, towards the sun (CandyLook.SUN_ELEVATION 61, SUN_AZIMUTH 300)
uniform vec3 sun_glare_color = vec3(0.9, 0.8, 0.6);
uniform vec3 patch_color = vec3(0.04, 0.30, 0.60);    // the broad glare patch where the view reflects towards the sun's side of the sky (a soft lobe, cyan white)
uniform float crease : hint_range(0.0, 1.0) = 0.0;   // 1: a pinched crease (a surface steeper than the 45 degree chamfers) goes dark navy: the contact seam of two mats
uniform vec3 crease_color : source_color = vec3(0.02, 0.02, 0.14);
uniform float bulge : hint_range(0.0, 1.0) = 0.0;
uniform float bulge_width : hint_range(0.01, 0.5) = 0.12;
uniform int pattern : hint_range(0, 7) = 0;
uniform float pattern_period = 1.0;
uniform float pattern_duty : hint_range(0.0, 1.0) = 0.5;
uniform float pattern_slope = 1.0;
uniform float pattern_angle = 0.0;
uniform float pattern_width = 0.2;
uniform float near_gone = 4.0;
uniform float near_whole = 0.0;
uniform float pattern_soft = 0.75;       // edge filtering in pixel footprints (1 = about one pixel)

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, vec3(lessThan(c, vec3(0.04045))));
}

// 1 on the inside of a periodic band: `phase` runs in periods, the band covers `duty` of each, filtered by the pixel footprint.
float band(float phase, float duty) {
	float w = fwidth(phase) * pattern_soft + 1e-4;
	float f = fract(phase);
	return smoothstep(0.0, w, f) * (1.0 - smoothstep(duty, duty + w, f));
}

float checker(vec2 q) {
	vec2 w = fwidth(q) + 1e-4;
	vec2 i = 2.0 * (abs(fract((q - 0.5 * w) * 0.5) - 0.5) - abs(fract((q + 0.5 * w) * 0.5) - 0.5)) / w;
	return 0.5 - 0.5 * i.x * i.y;
}

float within(float d, float width) {
	float w = fwidth(d) * pattern_soft + 1e-4;
	return 1.0 - smoothstep(width - w, width + w, d);
}

void fragment() {
	if (near_dissolved(VERTEX, FRAGCOORD.xy, near_gone, near_whole)) discard;
	vec3 tint = use_vertex_color ? (vertex_color_srgb ? srgb_to_linear(COLOR.rgb) : COLOR.rgb) : vec3(1.0);
	vec3 col = albedo.rgb * tint;
	if (pattern != 0) {
		float m = 0.0;
		float p = max(pattern_period, 1e-3);
		if (pattern == 1) {
			float a = radians(pattern_angle);
			vec2 q = vec2(cos(a) * UV.x - sin(a) * UV.y, sin(a) * UV.x + cos(a) * UV.y);
			m = band((q.x + pattern_slope * q.y) / p, pattern_duty);
		} else if (pattern == 2) {
			m = band((UV2.x * pattern_slope + UV2.y) / p, pattern_duty) * step(0.12, UV2.x) * step(0.1, UV2.y);
		} else if (pattern == 3) {
			m = checker(UV / p);
		} else if (pattern == 4) {
			vec2 c = fract(UV / p) - 0.5;
			vec2 w = fwidth(UV / p) * pattern_soft + 1e-4;
			float r = pattern_duty * 0.5;
			m = 1.0 - smoothstep(r - w.x, r + w.x, length(c));
		} else if (pattern == 5) {
			m = band(length(UV) / p, pattern_duty);
		} else if (pattern == 6) {
			float lx = abs(fract(UV.x / p + 0.5) - 0.5) * p;
			float ly = abs(fract(UV.y / p + 0.5) - 0.5) * p;
			m = max(within(lx, pattern_width * 0.5), within(ly, pattern_width * 0.5));
		} else if (pattern == 7) {
			m = within(min(UV2.x, UV2.y), pattern_width);
		}
		col = mix(col, albedo2.rgb * tint, m * albedo2.a);
	}
	if (crease > 0.0) {
		float ny = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
		float marked = use_vertex_color ? step(COLOR.a, 0.75) : 1.0; // a vertex colour with alpha under 0.75 marks a pinched seam: only there (never on an open edge's rounded shoulder) the crease darkens
		col = mix(col, crease_color, crease * marked * smoothstep(0.6, 0.35, ny) * smoothstep(0.08, 0.22, ny));
	}
	ALBEDO = col;
	METALLIC = 0.0;
	SPECULAR = specular;
	ROUGHNESS = roughness;
	if (bulge > 0.0) {
		vec2 c = UV - 0.5;
		vec2 e = smoothstep(0.5 - bulge_width, 0.5, abs(c)) * sign(c);
		NORMAL = normalize(NORMAL + bulge * (TANGENT * -e.x + BINORMAL * -e.y));
	}
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float gloss = smoothstep(0.75, 0.1, roughness);
	vec3 sheen = glare_color * pow(1.0 - nv, glare_power);
	vec3 to_sun = mat3(VIEW_MATRIX) * normalize(sun_dir);
	float rs = max(dot(reflect(-VIEW, NORMAL), to_sun), 0.0);
	sheen += sun_glare_color * pow(rs, 300.0) + patch_color * pow(rs, 14.0);
	EMISSION = col * self_light + rim_color * pow(1.0 - nv, rim_power) + sheen * gloss * glare;
}
