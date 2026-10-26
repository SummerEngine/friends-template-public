// Shared by the backdrop shaders (backdrop.gdshader, backdrop_outline.gdshader): slow ambient drift and the distance haze.
// Drift runs on the GPU: an instance whose INSTANCE_CUSTOM.w is a speed (m/s) slides along `drift_axis` and wraps after `wrap_length`
// metres, measured from `centre` (the world position of the backdrop's origin). Instances with speed 0 stand still.
#include "res://style/calm_palette.gdshaderinc"
uniform vec3 drift_axis = vec3(0.0, 0.0, -1.0);
uniform vec3 centre = vec3(0.0);
uniform float wrap_length = 1600.0;
uniform vec3 haze : source_color = vec3(0.92, 0.84, 0.66);
uniform float haze_k = 0.0013;
uniform float haze_cap = 0.94;

vec3 drift_offset(vec3 instance_world, float speed, float time) {
	if (abs(speed) < 0.001) {
		return vec3(0.0);
	}
	float rel = dot(instance_world - centre, drift_axis);
	float moved = mod(rel + speed * time + wrap_length * 0.5, wrap_length) - wrap_length * 0.5;
	return drift_axis * (moved - rel);
}

// How much of the haze colour (the sky at the horizon) covers a thing `d` metres from the camera.
float haze_amount(float d) {
	return haze_cap * (1.0 - exp(-d * haze_k));
}

// The horizon colour in the sky's own palette (calm or vivid), what everything fades into.
vec3 haze_color() {
	return calm_color(haze);
}
