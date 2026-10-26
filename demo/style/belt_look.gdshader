shader_type spatial;
// The deck of a conveyor belt (style/block_mesh.gd Batch.belt, style/real_look.gd) in the candy look: a saturated purple vinyl lane (#8E4CD9) between two amber hard-plastic rail strips (#EFAA2B, 0.2 m)
// with RAISED white chevrons on it (bevelled relief 7 cm proud, style/pillar_kit.gd chevron_mesh: a pale lilac bevel round a white face) that run along the belt the way it carries, at the belt's own speed.
// Flat tints, glossy, no light of their own: the chevrons read as direction by their white on the purple, and by their motion.
// The chevrons are real geometry that this vertex shader slides: every chevron vertex carries COLOR.g = 1 (COLOR.b = 1 on the face, 0 on the bevel), UV = (where the chevron's apex stands along the
// belt at TIME 0, how far behind the apex the vertex is) in metres from the belt's trailing end, UV2 = (the belt's length, the vertex's height over the deck). A chevron's apex runs at `speed` along
// `flow` and wraps from the leading end back to the trailing one (the wrap length is a whole number of PERIOD, long enough for a chevron to leave); a chevron grows out of the deck over its first
// SINK metres at the trailing end and sinks into it over its last SINK metres at the leading end, and what is still past either end is discarded. Deck vertices have COLOR.g = 0 and COLOR.r = 1 on the rails.
// One material per direction and speed (`speed` in m/s, `flow` the level-local unit direction). The scroll runs on the drawn frame's TIME and is only a picture: what carries a courier is
// courier_motion.gd. Works the same on the Compatibility renderer.
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform float speed = 3.0;                       // m/s: the chevrons run along `flow` at this speed
uniform vec2 flow = vec2(1.0, 0.0);              // level-local unit direction (x, z) the belt carries
uniform vec4 rubber : source_color = vec4(0.557, 0.298, 0.851, 1.0);
uniform vec4 rail_color : source_color = vec4(0.937, 0.667, 0.169, 1.0);
uniform vec4 chevron_color : source_color = vec4(0.973, 0.957, 0.953, 1.0);
uniform vec4 bevel_color : source_color = vec4(0.941, 0.882, 0.969, 1.0);
uniform float rough_plastic = 0.11;              // rails and chevrons: hard plastic (style/candy_look.gd ROUGH_PLASTIC)
uniform float rough_vinyl = 0.45;                // the lane: vinyl (ROUGH_VINYL)
const float PERIOD = 2.0;                        // metres from one chevron to the next (style/pillar_kit.gd BELT_PERIOD)
const float SPAN = 1.4;                          // the longest a chevron stands along the flow (BELT_SPAN)
const float SINK = 0.5;                          // metres over which a chevron grows out of the deck (and sinks into it) at the ends of the belt

varying float is_chevron;
varying float is_face;
varying float to_end;                            // metres to the nearer end of the belt along the flow (under 0 past it)

void vertex() {
	is_chevron = COLOR.g;
	is_face = COLOR.b;
	to_end = 1.0;
	if (COLOR.g > 0.5) {
		float belt_length = UV2.x;
		float wrap = ceil((belt_length + SPAN) / PERIOD) * PERIOD;
		float apex = mod(UV.x + speed * TIME, wrap);
		float along = apex + UV.y;
		VERTEX.xz += flow * (apex - UV.x);
		float grow = smoothstep(0.0, SINK, along) * smoothstep(0.0, SINK, belt_length - along);
		VERTEX.y -= (1.0 - grow) * UV2.y;
		to_end = min(along, belt_length - along);
	}
}

void fragment() {
	if (is_chevron > 0.5) {
		if (to_end < 0.0) discard;
		vec3 colour = mix(bevel_color.rgb, chevron_color.rgb, is_face);
		ALBEDO = colour;
		ROUGHNESS = rough_plastic;
		METALLIC = 0.0;
		SPECULAR = 0.5;
	} else {
		float rail = step(0.5, COLOR.r);
		ALBEDO = mix(rubber.rgb, rail_color.rgb, rail);
		ROUGHNESS = mix(rough_vinyl, rough_plastic, rail);
		METALLIC = 0.0;
		SPECULAR = 0.5;
	}
}
