shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
// The faint triangle facets of the sky (style/candy_light.gd `sky_node`): a fullscreen quad at the far plane, added over the Environment's sky gradient wherever the sky shows (it is hidden behind
// everything nearer by the depth test). They need the CAMERA's direction, which an Environment sky shader does not know: the pattern is strongest in a cone round the camera's axis
// (cos^`cone_power`, the white edge lines of the triangles are in the same cone) and almost gone elsewhere, always LIGHTER (it is added to every channel: blue is already full, so red and green rise and the triangle reads light cyan). The triangles are a
// fixed grid over (azimuth, sin elevation), each with one of four tone levels from a hash (0, 1/3, 2/3, 1); the addition is `(0.03 + 0.37 m^2) gain`, 0.03 .. 0.4 like a `0.1 (1 + m) (1 - sin t + m)` span, but with the dark tones really dark: the facets are TONAL, edges at most a hairline.
// NO TIME and nothing that moves. Colours are scene-linear light: the grade of the picture is applied on top, like on the sky.
uniform float gain = 0.5;
uniform float cone_power = 6.0;
uniform vec2 cells = vec2(40.0, 20.0);          // columns over the azimuth turn, rows over sin(elevation) * 0.5 + 0.5
uniform float line_gain = 0.6;                // the white edge lines of the triangles (added over the fill, times the cone)
uniform float line_width = 0.03;              // in triangle widths
uniform float below_horizon = 0.12;             // the pattern fades in from the horizon up over this much of sin(elevation)

varying vec3 dir_view;

float hash12(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

void vertex() {
	vec4 p = INV_PROJECTION_MATRIX * vec4(VERTEX.xy, 1.0, 1.0);
	dir_view = p.xyz / p.w;
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);          // the far plane (reversed depth)
}

void fragment() {
	vec3 dir = normalize((INV_VIEW_MATRIX * vec4(normalize(dir_view), 0.0)).xyz);
	vec3 forward = -INV_VIEW_MATRIX[2].xyz;
	float cone = pow(clamp(dot(dir, forward), 0.0, 1.0), cone_power);
	vec2 p = vec2(atan(dir.z, dir.x) / TAU + 0.5, dir.y * 0.5 + 0.5) * cells;
	vec2 ab = vec2(p.x - 0.5 * p.y, p.y);
	vec2 id = floor(ab);
	vec2 fr = fract(ab);
	float m = floor(hash12(id + step(fr.x + fr.y, 1.0) * 17.0) * 4.0) / 3.0;   // four tones: 0, 1/3, 2/3, 1 (neighbouring triangles differ clearly)
	float up = smoothstep(0.0, below_horizon, dir.y);
	float d = min(min(fr.x, fr.y), abs(1.0 - fr.x - fr.y));
	float w = max(fwidth(d), 1e-4);
	float edge = 1.0 - smoothstep(line_width * 0.5, line_width * 0.5 + w * 1.5, d);
	ALBEDO = vec3(((0.03 + 0.37 * m * m) * gain + edge * line_gain) * cone * up);   // fill 0.03 .. 0.4 (tonal triangles), a hairline edge
}
