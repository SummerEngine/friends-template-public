shader_type spatial;
// The thin glass in front of a carried painting (and its 30-piece shards): a faint blue tint and two hard white
// glare streaks like the comic pane. UV = (along the picture, down the picture), set by tools/build_carry_items.py.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;
uniform vec4 tint : source_color = vec4(0.72, 0.9, 1.0, 1.0);
uniform float tint_alpha : hint_range(0.0, 1.0) = 0.07;
uniform float streak_alpha : hint_range(0.0, 1.0) = 0.28;

void fragment() {
	float d = UV.x - UV.y * 0.55;
	float streak = step(abs(d - 0.34), 0.035) + step(abs(d - 0.5), 0.016);
	ALBEDO = mix(tint.rgb, vec3(1.0), min(streak, 1.0));
	ALPHA = tint_alpha + streak_alpha * min(streak, 1.0);
}
