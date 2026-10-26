shader_type spatial;
// Backdrop pieces (style/backdrop.gd): flat three-tone shading, windows and poster stripes, atmospheric haze, ambient drift.
// One MultiMesh per body; per instance: COLOR = tone, INSTANCE_CUSTOM = (mode, seed, smooth, drift speed).
// mode 0 plain, 1 windows, 2 windows with lit ones, 3 poster (sunburst face on +z), 4 bird (wings flap).
// The ink outline is a separate next_pass (backdrop_outline.gdshader). Unshaded: no light, no shadow, one cheap fragment.
render_mode unshaded, fog_disabled, cull_back, depth_draw_opaque;
#include "res://style/backdrop_motion.gdshaderinc"
uniform vec3 light_dir = vec3(0.5, 0.75, 0.35);
uniform vec3 window_glass : source_color = vec3(0.30, 0.38, 0.55);
uniform vec3 window_lit : source_color = vec3(1.0, 0.82, 0.45);
uniform vec3 ink : source_color = vec3(0.106, 0.114, 0.227);
uniform float lit_share = 0.5;
uniform vec2 window_cell = vec2(3.4, 4.0);

varying vec3 vlocal;
varying vec3 vscale;
varying vec4 vdata;
varying vec3 vnormal;
varying float vdepth;

void vertex() {
	vlocal = VERTEX;
	vscale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	vdata = INSTANCE_CUSTOM;
	vnormal = normalize(mat3(MODEL_MATRIX) * (VERTEX / (vscale * vscale * vscale)));
	if (abs(INSTANCE_CUSTOM.w) > 0.001) {
		VERTEX += inverse(mat3(MODEL_MATRIX)) * drift_offset(MODEL_MATRIX[3].xyz, INSTANCE_CUSTOM.w, TIME);
	}
	if (INSTANCE_CUSTOM.x > 3.5) {
		VERTEX.y += sin(TIME * 7.0 + INSTANCE_CUSTOM.y * 40.0) * abs(VERTEX.x) * 0.55;
	}
	vdepth = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec3 col = COLOR.rgb;
	float mode = vdata.x;
	if (mode < 3.5) {
		vec3 nv = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
		if (dot(nv, VERTEX) > 0.0) {
			nv = -nv;
		}
		vec3 nw = vdata.z > 0.5 ? vnormal : normalize((INV_VIEW_MATRIX * vec4(nv, 0.0)).xyz);
		float ndl = dot(nw, normalize(light_dir));
		float tone = ndl > 0.45 ? 1.05 : (ndl > -0.05 ? 0.9 : 0.76);
		col *= tone;
		float px = 1.0 / max(vdepth * 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y), 0.0001);
		if (mode > 0.5 && mode < 2.5 && abs(nw.y) < 0.5) {
			vec3 a = abs(vlocal);
			float u = a.x > a.z ? vlocal.z * vscale.z : vlocal.x * vscale.x;
			float v = (vlocal.y + 0.5) * vscale.y;
			vec2 q = vec2(u, v) / window_cell;
			vec2 id = floor(q);
			vec2 f = fract(q);
			float pane = step(0.22, f.x) * step(f.x, 0.78) * step(0.28, f.y) * step(f.y, 0.72) * step(1.0, id.y);
			float fade = smoothstep(2.5, 6.0, window_cell.x * px);
			float lit = mode > 1.5 ? step(1.0 - lit_share, hash21(id + vdata.y * 57.0)) : 0.0;
			vec3 pane_col = mix(col * 0.72 + window_glass * 0.28, window_lit, lit);
			col = mix(col, pane_col, pane * fade);
		}
	} else if (mode < 4.5 && mode > 2.5) {
		vec3 nw = normalize((INV_VIEW_MATRIX * vec4(normalize(cross(dFdx(VERTEX), dFdy(VERTEX))), 0.0)).xyz);
		vec2 uv = vlocal.xy + 0.5;
		float ray = step(0.5, fract(atan(uv.y - 0.5, uv.x - 0.5) * (8.0 / 6.2831853)));
		float frame = step(min(min(uv.x, uv.y), min(1.0 - uv.x, 1.0 - uv.y)), 0.07);
		col = vlocal.z > 0.45 ? mix(col * mix(1.0, 0.8, ray), ink, frame) : col * 0.8;
	}
	col = calm_color(col);
	ALBEDO = mix(col, haze_color(), haze_amount(vdepth));
}
