shader_type spatial;
// Collision look: ink lines on every silhouette and crease of everything drawn, one full-screen pass over the depth buffer.
//  * outline: 1 / depth is an affine function of the screen position on any flat surface, however steeply it is seen, so its second
//    difference is zero inside a face and jumps at a depth step;
//  * crease: the surface normals rebuilt from the depth on either side of the pixel (forward and backward differences) differ.
// That needs no normal buffer, so it also runs on the Compatibility renderer. Lines are about 2 px wide at 1080 lines of height,
// and fade out far away (where distant ground only flickers).
render_mode unshaded, fog_disabled, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec4 ink_color : source_color = vec4(0.106, 0.114, 0.227, 1.0);
uniform float line_pixels = 2.0;     // offset of the neighbours, in pixels per 1080 lines of height
uniform float outline_step = 0.03;   // relative second difference of 1 / depth that starts an outline (full at twice that)
uniform float crease_step = 0.07;    // 1 - cos(angle between the two normals) that starts a crease (full at 2.5 times that)
uniform float fade_near = 50.0;
uniform float fade_far = 170.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

vec3 view_position(vec2 uv, mat4 inv_projection) {
	float d = texture(depth_tex, uv).x;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 ndc = vec4(uv * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
#else
	vec4 ndc = vec4(uv * 2.0 - 1.0, d, 1.0);
#endif
	vec4 v = inv_projection * ndc;
	vec3 p = v.xyz / v.w;
	p.z = min(p.z, -0.05);
	return p;
}

void fragment() {
	vec2 px = line_pixels * max(1.0, floor(VIEWPORT_SIZE.y / 1080.0 + 0.5)) / VIEWPORT_SIZE;
	vec3 c = view_position(SCREEN_UV, INV_PROJECTION_MATRIX);
	vec3 l = view_position(SCREEN_UV - vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	vec3 r = view_position(SCREEN_UV + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	vec3 u = view_position(SCREEN_UV - vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	vec3 d = view_position(SCREEN_UV + vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float ic = -1.0 / c.z;
	float bend = max(abs(-1.0 / l.z - 1.0 / r.z - 2.0 * ic), abs(-1.0 / u.z - 1.0 / d.z - 2.0 * ic)) / ic;
	float outline = smoothstep(outline_step, outline_step * 2.0, bend);
	vec3 n_after = normalize(cross(r - c, d - c) + vec3(1.0e-12));
	vec3 n_before = normalize(cross(c - l, c - u) + vec3(1.0e-12));
	float crease = smoothstep(crease_step, crease_step * 2.5, 1.0 - dot(n_after, n_before));
	ALBEDO = ink_color.rgb;
	ALPHA = max(outline, crease) * (1.0 - smoothstep(fade_near, fade_far, -c.z));
}
