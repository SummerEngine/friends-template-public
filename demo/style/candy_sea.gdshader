shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
// The candy world's sea (style/candy_world.gd): the pink slime, glossy. One flat quad over the lake's window; where the slime ends is read from the SHORE FIELD (shore_tex: signed metres to
// the waterline, negative on the slime), baked on the CPU from the terrain's own height function, so the shore, the foam line and the rings are smooth analytic curves at any distance (no
// vertex mask, nothing steps). Concentric ripple rings run out from every shore and island, the deeper trough colour shows in broad patches, the sky is mirrored at a grazing angle (fresnel) and
// the sun draws a glossy streak across the ripples. Cheap: three texture taps, a few noise lookups, no depth texture, no transparency; it works the same on the Compatibility renderer.
// Hand-lit and fogged like the rest (candy_fog.gdshaderinc). The only motion is the slow outward drift of the rings.
#include "res://style/candy_fog.gdshaderinc"

uniform sampler2D shore_tex : filter_linear, repeat_disable;
uniform vec2 shore_origin;                                   // diorama units (x, z) of the window's corner
uniform vec2 shore_size;
uniform vec3 base : source_color = vec3(0.98, 0.62, 0.8);   // #FA9FCC
uniform vec3 light : source_color = vec3(1.0, 0.71, 0.855); // #FFB6DA
uniform vec3 deep : source_color = vec3(0.86, 0.35, 0.60);  // #DB5A9A
uniform vec3 foam : source_color = vec3(1.0);
uniform vec3 crest_col : source_color = vec3(1.0, 0.88, 0.94);   // the near-white pink of a ripple crest
uniform vec3 sun_dir = vec3(0.30, 0.876, 0.38);
uniform vec3 sky_tint : source_color = vec3(1.0, 0.93, 0.97);
uniform vec2 course_half = vec2(0.0);        // the course's rectangle (half sizes) and radius, in the window's units: ripples run out from it over the open slime
uniform float course_r = 0.0;
uniform float world_scale = 1.0;
uniform float foam_width = 1.1;               // m (full-size world) on each side of the waterline
uniform float ring_wave = 24.0;               // m between two ripple rings at the full-size world
uniform float ring_speed = 0.35;              // m/s the rings drift outward
uniform float glint = 2.6;

varying vec2 local;   // the diorama's x / z of the fragment (the window's units)
varying vec3 wpos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float field(vec2 p, float t) {
	return vnoise(p * 0.012 + vec2(t * 0.02, t * 0.013)) * 0.6 + vnoise(p * 0.03 + vec2(-t * 0.03, t * 0.02) + 7.0) * 0.4;
}
float shore_at(vec2 q) {
	vec2 hs = texture(shore_tex, (q - shore_origin) / shore_size).rg;   // height over the slime and its slope: the distance is made after the bilinear filter
	return clamp(hs.r / max(hs.g, 0.02), -96.0, 96.0);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local = VERTEX.xz;
}

void fragment() {
	float d = shore_at(local);
	if (d > 0.0) discard;                       // land: the terrain's shader draws the lime (and the other half of the foam line)
	float out_m = -d;                           // metres out from the shore onto the slime
	float aa = fwidth(d);                       // metres per pixel: lines never get thinner than a pixel
	float t = TIME;

	// ripple rings, from the shore and from the course, the nearer of the two (they meet in a soft crease): a little wobbled so no ring is a perfect circle, drifting out, spaced wider
	// the farther out (the same number of pixels apart in the distance); strongest near, a faint set far, none where they would be thinner than 3 px
	float cd = length(max(abs(local) - course_half, 0.0)) - course_r;
	float dist = min(out_m, max(cd, 0.0));
	float wob = (field(local, 0.0) - 0.5) * 10.0;
	float warped = 160.0 * log(1.0 + (dist + wob) / 160.0);
	float phase = warped / ring_wave - t * ring_speed / ring_wave;
	float ring = sin(phase * TAU);
	float fade = (0.45 + 0.55 * exp(-dist / 200.0)) * (1.0 - smoothstep(0.1, 0.32, aa / ring_wave * (1.0 + dist / 160.0)));
	float soft = clamp(aa / ring_wave * 6.0, 0.0, 0.25);               // wider where the field is steep on screen (far away): the stairs of its texels melt
	float band = smoothstep(0.68 - soft, 0.97 + soft * 0.5, ring) * fade;                     // a narrow bright band on every crest

	vec3 c = mix(light, base, smoothstep(1.0, 14.0, out_m));              // lighter pink in the shallows by the shore
	float f = field(local * 1.0 + 30.0, t);
	c = mix(c, deep, smoothstep(0.40, 0.68, f) * 0.65);                   // broad deeper patches: the troughs
	c = mix(c, light, smoothstep(0.50, 0.20, f) * 0.3);
	c = mix(c, deep, smoothstep(-0.1 + soft, -0.85, ring) * fade * 0.85);        // a darker trough between two crests
	c = mix(c, crest_col, band * 0.95);
	// loose round ripples over the open slime (iso-lines of a smooth noise: rings round its blobs, soft and pale, not the white contour lines of the meadow); thinner than 3 px they fade
	float rv = field(local * 0.55 + 70.0, t * 0.5) * 7.0;
	float rw = fwidth(rv);
	float rip = smoothstep(0.7, 0.95, abs(sin(rv * PI))) * (1.0 - smoothstep(0.2, 0.6, rw));
	c = mix(c, crest_col, rip * 0.55);

	// the slope of the rings (analytic: the height is a sine of the field's distance) tilts the normal; a mirror of the sky at a grazing angle and a streak of a sun that stands in front of the
	// eye (over the horizon where the camera looks: a physical sun is behind the shots most of the time, and a glossy slime must show its sheen in every one)
	vec2 e = vec2(4.0, 0.0);
	vec2 grad = vec2(shore_at(local + e.xy) - d, shore_at(local + e.yx) - d) / e.x;   // d(distance)/d(x, z)
	float slope = cos(phase * TAU) * TAU / ring_wave * 0.5 * fade;                       // ring height amplitude 0.5 m
	vec3 nrm = normalize(vec3(-slope * grad.x, 1.0, -slope * grad.y));
	vec3 view_w = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 refl = reflect(-view_w, nrm);
	float fres = 0.04 + 0.96 * pow(1.0 - clamp(dot(nrm, view_w), 0.0, 1.0), 4.0);
	c = mix(c, sky_tint, clamp(fres * 0.4, 0.0, 0.2));
	vec2 ahead = normalize(-INV_VIEW_MATRIX[2].xz + vec2(0.0001));
	vec3 lamp = normalize(vec3(ahead.x * 0.9, 0.42, ahead.y * 0.9));
	float lamp_r = max(dot(refl, lamp), 0.0);
	float sun_r = max(dot(refl, sun_dir), 0.0);
	c += vec3(1.0, 0.97, 0.93) * (pow(lamp_r, 150.0) * 0.06 + pow(lamp_r, 700.0) * 1.6 + pow(sun_r, 700.0) * glint + pow(sun_r, 60.0) * 0.08) * (0.35 + 0.65 * fade);

	// foam: a crisp thin white line at the waterline (the terrain's shader draws its other half), and a fainter broken ring a few metres out
	float fw = max(foam_width, aa * 2.0);
	float line = 1.0 - smoothstep(fw - aa * 1.6, fw + aa * 1.6, out_m);
	float ring2_d = out_m - 5.5 - (field(local * 1.3, 5.0) - 0.5) * 5.0;
	float ring2 = (1.0 - smoothstep(max(0.3, aa), max(0.3, aa) + aa * 1.6 + 0.2, abs(ring2_d))) * smoothstep(0.4, 0.62, field(local * 0.8 + 40.0, 0.0)) * 0.75;
	c = mix(c, foam, max(line, ring2));
	ALBEDO = candy_fog(c, -VERTEX.z);
}
