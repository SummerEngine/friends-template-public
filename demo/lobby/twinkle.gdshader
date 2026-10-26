shader_type spatial;
// The lobby's string-light bulbs: their own colour, bright enough to glow, each bulb twinkling at its own pace (vertex alpha = its phase).
render_mode unshaded, cull_back, shadows_disabled;

uniform float brightness = 2.6;

void fragment() {
	float phase = COLOR.a * 6.2831;
	float pulse = 0.72 + 0.28 * sin(TIME * (1.3 + COLOR.a * 1.7) + phase * 3.0);
	ALBEDO = COLOR.rgb * pulse * brightness;
}
