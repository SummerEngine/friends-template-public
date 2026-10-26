extends SceneTree
## Writes the wardrobe's CROWN hat (demo/character/models/items/hat_crown.glb) from the show's built-in crown (style/show_crown.gd): the same mesh,
## seated and tipped as the podium crown sits on the winner's head (modes/show/view.gd CROWN_*), so the crown that comes down on the podium and the
## hat that is worn afterwards are the same picture. Code mesh, no scanned or generated model. Run again after changing the crown:
##   tools/engine_slot.sh timeout -k 10 120 <Summer> --headless --audio-driver Dummy --path demo -s "$PWD/tools/export_crown_hat.gd"
## then `<Summer> --headless --import --path demo` (the .import sidecar is not tracked).
const ShowCrown := preload("res://style/show_crown.gd")
const View := preload("res://modes/show/view.gd")
const OUT := "res://character/models/items/hat_crown.glb"

func _init() -> void:
	var crown: Node3D = ShowCrown.build(View.CROWN_HEIGHT)
	var root := Node3D.new()
	root.name = "hat_crown"
	var band := crown.get_node("Band") as MeshInstance3D
	crown.remove_child(band)
	band.position = Vector3(0.0, View.CROWN_SEAT, 0.0)
	band.rotation = View.CROWN_TILT
	band.mesh = band.mesh.duplicate()
	var names := ["crown_gold", "crown_gem"]
	for surface in band.mesh.get_surface_count():
		var material := (band.mesh.surface_get_material(surface) as Material).duplicate() as Material
		material.resource_name = names[mini(surface, names.size() - 1)]
		band.mesh.surface_set_material(surface, material)
	root.add_child(band)
	band.owner = root
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var failed := document.append_from_scene(root, state) != OK or document.write_to_filesystem(state, OUT) != OK
	print("CROWN_HAT ", "FAILED" if failed else "wrote " + OUT)
	quit(1 if failed else 0)
