shader_type spatial;
// Collision look: the void under a level. One dark, flat colour (no fog, so it stays dark to the horizon).
render_mode unshaded, fog_disabled, cull_disabled;
uniform vec4 water_color : source_color = vec4(0.07, 0.13, 0.32, 1.0);

void fragment() {
	ALBEDO = water_color.rgb;
}
