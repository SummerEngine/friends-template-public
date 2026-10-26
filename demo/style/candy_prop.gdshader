shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://style/near_dissolve.gdshaderinc"
// NEAR DISSOLVE (style/near_dissolve.gdshaderinc): a spinner bar, a hub, a post or a cannon near the camera is see-through (gone nearer than `near_gone` m, whole from `near_whole` m; 0 = off).
uniform float near_gone = 4.0;
uniform float near_whole = 7.5;
// The surface of the race props in the candy look (style/lathe_mesh.gd: spinner, turntable, cannon): a flat authored tint from the vertex colour, glossy, lit by the engine's own
// Burley diffuse and GGX specular. No outline, no rim, no self light. The vertex colour's ALPHA says which family the vertex is (8 bit, so three levels):
//   1.0   hard plastic  (roughness 0.11): hubs, posts, collars, bases
//   0.5   vinyl         (roughness 0.45): inflatable-like bars, soft pieces
//   0.0   striped vinyl (roughness 0.30, glossier: a soft broad sheen on the bulges): vinyl with diagonal white stripes over the tint (UV.x runs round the part in whole stripe periods, UV.y along it in periods: the stripe is a 45 degree twist)
// The sheen of glossy vinyl and plastic is analytic (as in candy_surface.gdshader): a pale cyan sky reflection that grows towards the silhouette (fresnel), a small crisp glint where the
// reflection meets the sun (`sun_dir`): a ball, a bar or a post shows a soft broad sheen (with the engine's own specular) and a bright spot, the same on Mobile and Compatibility.
// Numbers per family: style/candy_look.gd (ROUGH_PLASTIC, ROUGH_VINYL).
uniform float rough_plastic : hint_range(0.0, 1.0) = 0.11;
uniform float rough_vinyl : hint_range(0.0, 1.0) = 0.45;
uniform float rough_striped : hint_range(0.0, 1.0) = 0.3;
uniform float glare : hint_range(0.0, 3.0) = 1.0;
uniform vec3 glare_color = vec3(0.12, 0.52, 0.70);
uniform vec3 sun_dir = vec3(-0.4207, 0.8746, 0.2429);   // world space, towards the sun
uniform vec3 sun_glare_color = vec3(1.0, 0.9, 0.7);
uniform vec3 stripe_color : source_color = vec3(0.94, 0.91, 0.90);

void fragment() {
	if (near_dissolved(VERTEX, FRAGCOORD.xy, near_gone, near_whole)) discard;
	float kind = COLOR.a;
	vec3 col = COLOR.rgb;
	float rough = kind > 0.9 ? rough_plastic : (kind < 0.2 ? rough_striped : rough_vinyl);
	if (kind < 0.2) {
		float t = UV.x + UV.y;
		float width = max(fwidth(t), 0.0001) * 1.2;
		float f = fract(t);
		float on = smoothstep(0.25 - width, 0.25 + width, f) * (1.0 - smoothstep(0.75 - width, 0.75 + width, f));
		col = mix(col, stripe_color, on);
	}
	ALBEDO = col;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	ROUGHNESS = rough;
	float gloss = smoothstep(0.75, 0.1, rough);
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 to_sun = mat3(VIEW_MATRIX) * normalize(sun_dir);
	float rs = max(dot(reflect(-VIEW, NORMAL), to_sun), 0.0);
	vec3 sheen = glare_color * pow(1.0 - nv, 3.0) + sun_glare_color * pow(rs, 100.0);
	EMISSION = sheen * gloss * glare;
}
