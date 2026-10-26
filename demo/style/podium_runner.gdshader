shader_type spatial;
// The podium's cloth runner, one mesh: vinyl cloth (the candy look's vinyl, roughness 0.45), a cream hem along both edges (a distance from the edge, whatever the width), and thin lighter stripes across the runner part (COLOR.r = 1, every 0.16 m
// along it, uv.y). COLOR.g is half the cloth's width at that point in metres.
uniform vec4 red : source_color = vec4(0.38, 0.19, 0.69, 1.0);
uniform vec4 stripe : source_color = vec4(0.56, 0.30, 0.85, 1.0);
uniform vec4 edge : source_color = vec4(0.97, 0.96, 0.95, 1.0);

void fragment() {
	float s = step(0.62, fract(UV.y / 0.16)) * step(0.5, COLOR.r);
	vec3 col = mix(red.rgb, stripe.rgb, s);
	float side = min(UV.x, 1.0 - UV.x) * COLOR.g * 2.0;
	col = mix(col, edge.rgb, step(side, 0.06));
	ALBEDO = col;
	ROUGHNESS = 0.45;
}
