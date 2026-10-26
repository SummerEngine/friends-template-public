extends SceneTree
## Summer --headless --path demo --script ../tools/build_network.gd.

func _init() -> void:
	var contract: Script = load("res://network/game.gd")
	if contract == null or not contract.can_instantiate():
		push_error("Network contract does not compile")
		quit(1)
		return
	var composition: Resource = contract.composition()
	if ResourceSaver.save(composition, "res://network/composition.tres") != OK:
		quit(1)
		return
	for role: String in ["client", "authority"]:
		var script_path := "res://%s/main.gd" % role
		var script: Script = load(script_path)
		if script == null or not script.can_instantiate():
			push_error("Entry script does not compile: " + script_path)
			quit(1)
			return
		var node: Node = ClassDB.instantiate(script.get_instance_base_type())
		node.name = "FriendsClient" if role == "client" else "FriendsAuthority"
		node.set_script(script)
		var scene := PackedScene.new()
		var error := scene.pack(node)
		if error == OK:
			error = ResourceSaver.save(scene, "res://%s/main.tscn" % role)
		node.free()
		if error != OK:
			push_error("Cannot save " + role + " entry: " + str(error))
			quit(1)
			return
	print("GW_NETWORK_GENERATED client authority composition")
	quit()
