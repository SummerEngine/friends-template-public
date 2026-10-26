shader_type spatial;
render_mode cull_back;
// The tiles of a stage round (style/stage_tile_look.gd): glossy chamfered candy slabs; the code is shared with the fading variant in stage_tile.gdshaderinc.
#include "res://style/stage_tile.gdshaderinc"

void vertex() {
	TILE_VERTEX
}

void fragment() {
	NORMAL = tile_normal(NORMAL, VIEW_MATRIX);
	vec3 emission;
	float rough;
	tile_fragment(NORMAL, VIEW, (VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz, ALBEDO, emission, rough);
	EMISSION = emission;
	ROUGHNESS = rough;
	SPECULAR = tile_specular;
}
