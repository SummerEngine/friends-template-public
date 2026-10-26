// Calm palette (Settings > Display > Palette, `--glass-palette=calm`): one global switch,
// `glass_calm` (0 = the full vivid inks, 1 = calm), declared at runtime by
// FriendsStyle.ensure_globals() before any shader that includes this file is loaded.
// Scenery colours go through calm_color(); hazards, characters and ink lines never do, so
// danger keeps its clear accent while the world around it settles down.
global uniform float glass_calm;

// Lower saturation, a little less contrast, one warm cast over everything: the hues stay
// distinguishable but stop competing with each other. Works on linear colours.
vec3 calm_color(vec3 c) {
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	vec3 g = mix(vec3(l), c, 0.34);
	g = mix(g, vec3(0.62, 0.58, 0.50), 0.12);
	g *= vec3(1.01, 1.0, 0.97);
	return mix(c, g, clamp(glass_calm, 0.0, 1.0));
}
