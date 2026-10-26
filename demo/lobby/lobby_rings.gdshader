shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;
#include "res://style/near_dissolve.gdshaderinc"
// The lobby yard's back panel (demo/lobby/lobby_kit.gd `_backdrop`): a warm yellow wall with concentric lighter rings round a point. Flat colour, no light, no
// shadow, no collision. The colours are SCENE-LINEAR light of the screen colours (CandyLook.scene_linear) so that the picture's grade lands on them. UV (0..1) of a quad of `size` metres.
uniform vec3 base : source_color = vec3(1.0, 0.76, 0.1);
uniform vec3 ring : source_color = vec3(1.0, 0.86, 0.3);
uniform vec2 size = vec2(20.0, 5.65);
uniform vec2 centre = vec2(0.5, 0.5);
uniform float period = 1.15;
uniform float width = 0.45;
uniform vec3 glow : source_color = vec3(1.0, 0.93, 0.55);
uniform float near_gone = 4.0;    // NEAR DISSOLVE (style/near_dissolve.gdshaderinc): the panel is see-through near the camera (gone nearer than this, whole from `near_whole` m)
uniform float near_whole = 7.5;

void fragment() {
	if (near_dissolved(VERTEX, FRAGCOORD.xy, near_gone, near_whole)) discard;
	vec2 p = (UV - centre) * size;
	float d = length(p) / period;
	float f = abs(fract(d) - 0.5) * 2.0; // 0 at the middle of a ring band, 1 between
	float m = (1.0 - smoothstep(width, width + 0.3, f)) * (1.0 - smoothstep(9.0, 16.0, d));
	vec3 col = mix(base, glow, 0.45 * exp(-d * 0.22)); // a warm glow round the centre
	ALBEDO = mix(col, ring, m);
}
