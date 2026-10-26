shader_type spatial;
// The menu pet's contact shadow on the title's floor: a soft round shade under the feet, darkest in the middle. Drawn on a
// unit quad lying on the ground.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 shade : source_color = vec4(0.11, 0.13, 0.18, 1.0);
uniform float strength = 0.32;

void fragment() {
	float from_middle = length(UV - 0.5) * 2.0;
	ALBEDO = shade.rgb;
	ALPHA = strength * (1.0 - smoothstep(0.25, 1.0, from_middle));
}
