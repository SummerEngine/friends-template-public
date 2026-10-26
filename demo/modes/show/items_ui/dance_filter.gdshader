shader_type canvas_item;
// The DANCE's dumb filter (modes/show/items_ui/dance_view.gd): drawn over the vertical frame of the victim's screen only. A soft "beauty" glow (a few taps of the picture blended back as a bloom),
// saturation that pulses with the beat, a tint that swings between pink and cyan, a light leak across the top corner and a vignette at the frame's edge. `amount` is the fade in and out
// (0 = the picture untouched), `clock` the seconds since the effect began. The rect this is drawn on is the frame: UV runs 0..1 across it.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float clock = 0.0;

vec3 saturate_to(vec3 c, float k) {
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	return mix(vec3(l), c, k);
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 base = texture(screen_tex, SCREEN_UV).rgb;

	// the glow: eight taps round the pixel, only what is bright goes back in
	vec3 soft = base;
	float reach = 5.0;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.7853982 + 0.3;
		soft += texture(screen_tex, SCREEN_UV + vec2(cos(a), sin(a)) * px * reach * (1.0 + float(i % 2))).rgb;
	}
	soft /= 9.0;
	vec3 glow = max(soft - vec3(0.45), vec3(0.0)) * 1.1;
	vec3 c = mix(base, soft, 0.42) + glow;

	// the beat: saturation and tint pulse together, a second faster flicker rides on top
	float beat = 0.5 + 0.5 * sin(clock * 6.2832 * 2.1);
	float flick = 0.5 + 0.5 * sin(clock * 6.2832 * 5.3 + 1.3);
	c = saturate_to(c, 1.18 + 0.5 * beat);
	vec3 tint = mix(vec3(1.0, 0.62, 0.86), vec3(0.55, 0.9, 1.0), 0.5 + 0.5 * sin(clock * 3.1));
	c = mix(c, c * tint * 1.28, 0.2 + 0.12 * beat);
	c += vec3(0.05, 0.02, 0.06) * flick;

	// a light leak from the top corner
	float leak = smoothstep(0.75, 0.0, distance(UV, vec2(0.0, 0.0)));
	c += vec3(1.0, 0.55, 0.35) * leak * (0.16 + 0.1 * beat);

	// the vignette at the frame's edge
	vec2 e = abs(UV - 0.5) * 2.0;
	float edge = smoothstep(0.7, 1.25, max(e.x * 0.9, e.y));
	c *= 1.0 - 0.38 * edge;

	COLOR = vec4(mix(base, clamp(c, 0.0, 1.0), amount), 1.0);
}
