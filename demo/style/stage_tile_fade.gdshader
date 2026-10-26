shader_type spatial;
render_mode cull_back;
// A floor of the stage round that is fading out or in (style/stage_tile_look.gd: the floors over the followed courier are not drawn, and a floor comes and goes over about
// 0.2 s, not in one frame): the same surface as stage_tile.gdshader, drawn with a hash dither (alpha scissor against interleaved gradient noise: opaque pass, no sorting, nothing
// sees through to the draw order) so that `fade` 1 is whole and 0 is gone. A fragment near the eye also dissolves (a slab the camera sits in or passes is never cut by the near
// plane, it thins out instead).
#include "res://style/stage_tile.gdshaderinc"

uniform float fade = 1.0;             // 1 drawn, 0 gone
uniform float near_gone = 0.3;        // m from the eye: nearer than this a fragment is gone
uniform float near_whole = 3.0;       // m from the eye: from here on the near dissolve leaves a fragment whole

varying float eye;

void vertex() {
	TILE_VERTEX
	eye = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	NORMAL = tile_normal(NORMAL, VIEW_MATRIX);
	vec3 emission;
	float rough;
	tile_fragment(NORMAL, VIEW, (VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz, ALBEDO, emission, rough);
	EMISSION = emission;
	ROUGHNESS = rough;
	SPECULAR = tile_specular;
	float noise = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	float near = smoothstep(near_gone, near_whole, eye);
	ALPHA = fade * near;
	ALPHA_SCISSOR_THRESHOLD = max(noise, 0.004);
}
