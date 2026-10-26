extends SceneTree
## Clone preparation: compile both entries and require both source profiles clean.
func same_value(a: Variant, b: Variant, depth := 0) -> bool:
	if depth > 64 or typeof(a) != typeof(b): return false
	if a is Resource:
		if a == null or b == null: return a == b
		if a.get_class() != b.get_class(): return false
		for property: Dictionary in a.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE and str(property.name) != "resource_path":
				if not same_value(a.get(property.name), b.get(property.name), depth + 1): return false
		return true
	if a is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not same_value(a[i], b[i], depth + 1): return false
		return true
	if a is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not same_value(a[key], b[key], depth + 1): return false
		return true
	return a == b

func _init() -> void:
	var failures: Array[String] = []
	var contract: Script = load("res://network/game.gd")
	var saved: Resource = load("res://network/composition.tres")
	var declaration: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://summer.build.json"))
	var version := ""
	if contract == null or not contract.can_instantiate():
		failures.append("Game contract does not compile")
	elif saved == null or not saved is SummerNetworkComposition:
		failures.append("Saved composition is missing/invalid")
	elif not declaration is Dictionary:
		failures.append("Build declaration is invalid")
	else:
		version = str(declaration.get("runtime", {}).get("protocolVersion", ""))
		var generated: Resource = contract.composition()
		if version.is_empty() or saved.network_version != version or generated.network_version != version:
			failures.append("Build, saved and code composition versions differ")
		if not same_value(saved, generated):
			failures.append("Saved composition storage fields differ from current Game.composition()")
	for role: String in ["client", "authority"]:
		var script: Script = load("res://%s/main.gd" % role)
		if script == null or not script.can_instantiate():
			failures.append(role + " entry does not compile")
		var scene: PackedScene = load("res://%s/main.tscn" % role)
		if scene == null:
			failures.append(role + " scene is missing")
	var profiles: Array = []
	var analyzer := SummerWorldCompositionAnalyzer.new()
	for profile: int in [SummerWorldCompositionAnalyzer.PROFILE_CLIENT, SummerWorldCompositionAnalyzer.PROFILE_AUTHORITY_ENGINE]:
		var analysis := analyzer.analyze_project(ProjectSettings.globalize_path("res://"), "world.json", profile)
		var diagnostics: Array = []
		for diagnostic in analysis.diagnostics:
			diagnostics.append({"code": str(diagnostic.code), "path": str(diagnostic.path), "message": str(diagnostic.message), "dependency_path": str(diagnostic.dependency_path)})
		profiles.append({"profile": profile, "ok": analysis.ok, "diagnostics": diagnostics})
		if not analysis.ok or not diagnostics.is_empty():
			failures.append("Source profile " + str(profile) + " has diagnostics")
	var passed := failures.is_empty()
	print("GW_BUILD_CHECK ", JSON.stringify({"passed": passed, "protocol": version, "profiles": profiles, "failures": failures}))
	quit(0 if passed else 1)
