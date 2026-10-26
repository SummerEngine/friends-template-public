shader_type spatial;
#include "res://style/near_dissolve.gdshaderinc"
// The three surfaces of the goal sign (style/goal_sign.gd), one shader, chosen by `kind`:
//   0  panel: the saturated blue recess behind the lettering with a faint pattern of lighter dots, laid out in the metres of the sign's own face (UV = x, y)
//   1  letters: the extruded GOAL word and its subtitle: `front` on the faces (normal along the word's z), `side` on the extrusion
//   3  paint: the vertex colour, glossy hard plastic (the frame and the gantry)
// Everything is flat authored colour on the engine's own PBR (a little light of its own: `self_light`; no outline), roughness 0.11 (style/candy_look.gd ROUGH_PLASTIC).
//   2  bulbs: the marquee of the sign's border. The vertex colour carries each bulb's place: r the chase phase (0, 1/2, 1), g its place along
//      the loop (0..1), b odd or even. Three phases run in turn: a light that chases round the loop, odd and even bulbs blinking, all of them breathing.
uniform int kind = 0;
uniform float near_gone = 4.0;     // NEAR DISSOLVE (style/near_dissolve.gdshaderinc): the sign, its posts and its gantry are see-through near the camera: gone nearer than this, whole from `near_whole` m
uniform float near_whole = 7.5;
uniform vec4 front : source_color = vec4(0.53, 0.94, 0.78, 1.0);
uniform vec4 side : source_color = vec4(0.18, 0.62, 0.52, 1.0);
uniform vec2 y_span = vec2(0.0, 1.0);          // letters: the word's lowest and highest y (a gradient between them)
uniform vec4 panel : source_color = vec4(0.063, 0.392, 0.882, 1.0);   // #1064E1
uniform vec4 dots : source_color = vec4(0.239, 0.82, 0.957, 1.0);     // #3DD1F4
uniform float dot_pitch = 0.9;                  // m between two dots
uniform float dot_radius = 0.11;                // m
uniform float dot_mix = 0.35;                   // how far a dot goes to its colour
uniform float rough_plastic = 0.11;
uniform float self_light = 0.28;               // share of its own albedo the sign adds as emission (a face turned from the sun keeps its colour, as the hexagon tiles do: style/candy_look.gd HEX_SELF_LIGHT)
uniform float chase_cycles = 14.0;

varying vec3 local_normal;
varying float local_y;
varying float lit;

void vertex() {
	local_normal = NORMAL;
	local_y = VERTEX.y;
	lit = 0.0;
	if (kind == 2) {
		float program = mod(TIME, 12.0);
		float run = fract(COLOR.g * chase_cycles - TIME * 1.15);
		float chase = smoothstep(0.0, 0.1, run) * (1.0 - smoothstep(0.28, 0.42, run));
		float blink = step(0.5, fract(TIME * 1.6 + COLOR.b * 0.5));
		float breathe = 0.5 + 0.5 * sin(TIME * 3.4);
		float a = 1.0 - smoothstep(6.5, 7.0, program);
		float b = smoothstep(6.5, 7.0, program) * (1.0 - smoothstep(9.5, 10.0, program));
		float c = smoothstep(9.5, 10.0, program);
		lit = clamp(chase * a + blink * b + breathe * c, 0.0, 1.0);
	}
}

void fragment() {
	if (near_dissolved(VERTEX, FRAGCOORD.xy, near_gone, near_whole)) discard;
	if (kind == 0) {
		vec2 p = UV / dot_pitch;
		p.x += mod(floor(p.y), 2.0) * 0.5;
		vec2 d = (fract(p) - 0.5) * dot_pitch;
		float edge = max(fwidth(length(d)), 0.002);
		float dot_mask = 1.0 - smoothstep(dot_radius - edge, dot_radius + edge, length(d));
		vec3 panel_colour = mix(panel.rgb, dots.rgb, dot_mask * dot_mix);
		ALBEDO = panel_colour;
		EMISSION = panel_colour * self_light;
		ROUGHNESS = rough_plastic;
	} else if (kind == 1) {
		float face = smoothstep(0.55, 0.85, abs(local_normal.z));
		float height = clamp((local_y - y_span.x) / max(y_span.y - y_span.x, 0.001), 0.0, 1.0);
		vec3 c = mix(side.rgb, front.rgb * (0.9 + 0.2 * height), face);
		ALBEDO = c;
		EMISSION = c * self_light;
		ROUGHNESS = rough_plastic;
		SPECULAR = 0.5;
	} else if (kind == 3) {
		vec3 paint = pow(COLOR.rgb, vec3(2.2)); // the vertex colours are the sRGB values the code wrote
		ALBEDO = paint;
		EMISSION = paint * self_light;
		ROUGHNESS = rough_plastic;
		METALLIC = 0.0;
		SPECULAR = 0.5;
	} else {
		vec3 dim = vec3(0.62, 0.42, 0.2);
		vec3 bright = vec3(1.0, 0.93, 0.7);
		ALBEDO = mix(dim, bright, lit);
		EMISSION = mix(dim * 0.35, bright * 3.0, lit);
		ROUGHNESS = 0.25;
	}
}
