// Exp2 fog of the daylight look, shared by the shaders of the background world and of anything that wants to fade into the haze:
//   ALBEDO = candy_fog(lit_colour, -VERTEX.z);      // in fragment(), VERTEX.z is the view-space depth (negative in front of the camera)
// Godot's built-in fog is exp(-d z), not exp(-(d z)^2), and would mis-fade the near layers: the shaders using this include use `render_mode unshaded, fog_disabled`.
// `fog_density` is 0.0005 at the full scale of the world; a world built at scale S uses 0.0005 / S (the fog looks the same: exp2 is scale covariant).
uniform vec3 fog_color : source_color = vec3(0.5137, 0.8667, 1.0);   // #83DDFF
uniform float fog_density = 0.0005;

vec3 candy_fog(vec3 colour, float view_depth) {
	float f = view_depth * fog_density;
	return mix(fog_color, colour, exp(-f * f));
}
