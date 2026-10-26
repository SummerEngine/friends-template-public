// NEAR DISSOLVE: nothing of the look may stand between the follow camera and the courier. A fragment nearer to the eye than `gone` metres is discarded, one beyond `whole` metres is
// kept, and in between a hash dither (a screen-space noise, opaque pass, no sorting) thins it out: a post, a beam, a wall or a sign the camera comes up against or looks through is
// see-through instead of hiding the courier. The distance is measured per fragment (the view-space position of the pixel, Euclidean), so a long beam that passes over the camera dissolves
// where it is near, not where its vertices are. `whole <= 0` switches it off (the surface keeps no dither at all).
// Use in a spatial shader's fragment(): `if (near_dissolved(VERTEX, FRAGCOORD.xy, near_gone, near_whole)) discard;` with the two uniforms declared by the shader.
// In a shadow pass VERTEX is the light's view space, far from the light's own eye: the pieces keep their shadows.
// Numbers: CandyMaterial.NEAR_TALL / NEAR_FLOOR (style/candy_material.gd). Checked by tools/camera_clear_check.gd.
bool near_dissolved(vec3 view_position, vec2 pixel, float gone, float whole) {
	if (whole <= 0.0) return false;
	float noise = fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
	return smoothstep(gone, whole, length(view_position)) < max(noise, 0.004);
}
