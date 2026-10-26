shader_type sky;
// The sky of every daylight scene (style/candy_light.gd `environment`, numbers in style/candy_look.gd): a gradient from a deep zenith to a cyan horizon, NO sun disc, no pattern (the faint
// triangle facets are a camera-aware quad, style/candy_sky_facets.gdshader). The radiance pass (`AT_CUBEMAP_PASS`, what glossy surfaces reflect) returns the same gradient times `reflect_gain`:
// the ambient light is a flat colour of the Environment, not this sky. NO TIME and nothing that moves: a sky that reads TIME makes the engine redraw its radiance map every frame, this one is made
// once (`Sky.process_mode` is set to quality in candy_light.gd). All colours are SCENE-LINEAR light (CandyLook.scene_linear of the screen colours) so the picture's grade lands on them.
uniform vec3 high_colour = vec3(0.0, 0.1, 1.0);             // from `high_at` degrees of elevation up to the zenith
uniform vec3 mid_colour = vec3(0.0, 0.3, 1.0);              // at `mid_at`
uniform vec3 low_colour = vec3(0.0, 0.5, 0.6);              // at the horizon and below
uniform float mid_at = 15.0;
uniform float high_at = 40.0;
uniform float reflect_gain = 1.5;                            // the radiance map (reflections) is the gradient times this

void sky() {
	float h = EYEDIR.y;
	float el = degrees(asin(clamp(h, -1.0, 1.0)));
	vec3 base = mix(low_colour, mid_colour, smoothstep(0.0, mid_at, el));
	base = mix(base, high_colour, smoothstep(mid_at, high_at, el));
	COLOR = AT_CUBEMAP_PASS ? base * reflect_gain : base;
}
