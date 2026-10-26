shader_type spatial;
// Collision look: the START / GOAL pad, a flat disc in the accent colour (green / gold) with a darker rim and a pale ring.
render_mode unshaded, fog_disabled, cull_disabled;
uniform vec4 pad_color : source_color = vec4(0.13, 0.7, 0.37, 1.0);
uniform float radius = 2.7;
varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	float r = length(lpos.xz) / radius;
	vec3 col = pad_color.rgb;
	col = mix(col, col * 0.55, smoothstep(0.86, 0.9, r));
	col = mix(col, mix(col, vec3(1.0), 0.65), (1.0 - smoothstep(0.03, 0.05, abs(r - 0.7))));
	ALBEDO = col;
}
