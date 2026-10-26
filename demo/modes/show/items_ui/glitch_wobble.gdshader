shader_type canvas_item;
// GLITCH's full-screen trip (modes/show/items_ui/glitch_view.gd): the whole picture heaves and melts like a bad dream. Big slow swells warp both axes and the picture breathes in and out
// about its centre, a droop sags it, the red / green / blue channels split far apart (more towards the edges), the colours drift round the hue wheel and over-saturate, a second ghost of the
// picture floats beside the first (double vision) and a violet vignette closes in. `amount` is the envelope times the item's sway (0 = the picture untouched, 1 = the full trip). It stays
// readable: the warp is a smooth function of the screen (no tearing, no random flashes), so the course ahead can still be made out. The hue and the ghost grow with the envelope too.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float amount : hint_range(0.0, 2.0) = 0.0;
uniform float clock = 0.0; // seconds since the effect began

// rotates the hue of `c` by `angle` radians (a rotation of the colour about the grey axis)
vec3 hue_turn(vec3 c, float angle) {
	float s = sin(angle);
	float k = cos(angle);
	vec3 axis = vec3(0.57735);
	return c * k + cross(axis, c) * s + axis * dot(axis, c) * (1.0 - k);
}

vec2 heave(vec2 uv, float clock_s, float asp, float push) {
	vec2 warp;
	warp.x = sin(uv.y * 3.3 + clock_s * 1.1) * 0.085 + sin(uv.y * 7.4 - clock_s * 1.6 + 1.3) * 0.026;
	warp.y = sin(uv.x * 2.7 + clock_s * 0.9 + 0.8) * 0.100 + sin(uv.x * 5.6 - clock_s * 1.3) * 0.028;
	warp.x *= asp;
	float droop = (0.5 + 0.5 * sin(uv.x * 3.2 + clock_s * 0.55)) * smoothstep(0.05, 1.0, uv.y) * 0.10;
	return warp * push + vec2(0.0, -droop * push);
}

void fragment() {
	float k = amount;
	float asp = SCREEN_PIXEL_SIZE.x / SCREEN_PIXEL_SIZE.y; // height / width: a displacement of d screen-heights sideways is d * asp in uv
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float swell = 0.5 + 0.5 * sin(clock * 0.75 - 0.6); // 0..1, a slow breath of about 8 s
	float push = k * (0.7 + 0.6 * swell);

	// the picture breathes in and out about its centre, more across than up
	float stretch = 1.0 - k * (0.07 + 0.07 * sin(clock * 1.1)) - 0.03 * k;
	vec2 grown = c * vec2(stretch * (1.0 - 0.05 * k * sin(clock * 0.9 + 1.0)), stretch * (1.0 + 0.05 * k * sin(clock * 0.9 + 1.0)));
	vec2 at = vec2(0.5) + grown + heave(uv, clock, asp, push);

	// the channel split: far apart, growing with the distance from the centre and breathing with the swell
	vec2 split = c * (0.022 + 0.020 * swell) * k + vec2(0.006 * asp, 0.002) * k;
	float r = texture(screen_tex, at + split).r;
	float g = texture(screen_tex, at).g;
	float b = texture(screen_tex, at - split).b;
	vec3 col = vec3(r, g, b);

	// double vision: a second, drifting copy of the picture floats beside the first
	vec2 drift = vec2(sin(clock * 0.7) * 0.045 * asp, cos(clock * 0.53) * 0.032) * k;
	vec3 ghost = texture(screen_tex, at + drift + split * 1.6).rgb;
	col = mix(col, max(col, ghost * 0.9), clamp(0.30 * k, 0.0, 0.42));

	// the colours drift round the hue wheel, over-saturated
	float hue = k * (clock * 0.85 + 0.9 * sin(clock * 1.3));
	col = hue_turn(col, hue);
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(grey), col, 1.0 + 0.55 * clamp(k, 0.0, 1.0));

	// the vignette, a touch violet at the rim, pulsing
	float v = smoothstep(0.28, 0.95, length(c * vec2(1.0, 1.15)));
	col = mix(col, col * vec3(0.55, 0.4, 0.8), clamp(v * (0.55 + 0.15 * sin(clock * 2.1)) * k, 0.0, 0.7));
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
