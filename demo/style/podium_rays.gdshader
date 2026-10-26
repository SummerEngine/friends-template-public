shader_type spatial;
render_mode unshaded, cull_disabled;
// The podium screens' glass: a sunburst of rays turning about a point, in two colours, a soft vignette and a gloss band. `time_s` is the podium's own clock
// (the room is a pure function of it); `dim` darkens the screen before its winner has landed, `flash` is the white pop at the landing, `wash` how far the colours are pastelled towards white.
uniform vec4 ray_a : source_color = vec4(0.97, 0.78, 0.07, 1.0);
uniform vec4 ray_b : source_color = vec4(0.29, 0.78, 0.93, 1.0);
uniform float rays = 12.0;
uniform float spin = 0.05;
uniform float aspect = 1.3;
uniform float time_s = 0.0;
uniform float dim = 0.0;
uniform float flash = 0.0;
uniform float wash = 0.32;
uniform vec2 centre = vec2(0.5, 0.42);

void fragment() {
	vec2 p = (UV - centre) * vec2(aspect, 1.0);
	float a = atan(p.y, p.x) / TAU + time_s * spin;
	float f = fract(a * rays);
	float edge = 0.02 + length(p) * 0.012;
	float m = smoothstep(0.5 - edge, 0.5 + edge, f) * (1.0 - smoothstep(1.0 - edge, 1.0, f));
	vec3 col = mix(ray_b.rgb, ray_a.rgb, m);
	col = mix(col, vec3(1.0), wash); // calm: the rays are pastel, not signal colours
	col = mix(col, vec3(1.0), (1.0 - smoothstep(0.0, 0.7, length(p))) * 0.18 * (wash / 0.32));
	vec2 q = UV - vec2(0.5);
	col *= 1.0 - 0.18 * smoothstep(0.25, 0.75, length(q * vec2(1.0, 1.25)));
	col += vec3(smoothstep(0.05, 0.0, abs((UV.x * 0.75 + (1.0 - UV.y) * 0.45) - 0.42)) * 0.16);
	col = mix(col, col * vec3(0.45, 0.5, 0.65), dim);
	col = mix(col, vec3(1.0, 0.92, 0.98), clamp(flash, 0.0, 1.0) * 0.55);
	ALBEDO = col;
}
