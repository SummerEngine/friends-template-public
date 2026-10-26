extends "res://game/game_run.gd"
## Client bootstrap and the local Run entry. Hosted authority never loads it.
const MenuAssets = preload("res://client/menu_style.gd")
const LobbyDraw = preload("res://lobby_visuals.gd")
const LobbyEnvironment = preload("res://lobby_environment.gd")
const DevShots = preload("res://client/dev_shots.gd")

func _init() -> void:
	install()
	DevShots.attach(self) # dev builds only: -- --shots=<dir> saves a review shot of every screen (client/dev_shots.gd)

static func install() -> void:
	# Static readers survive scene changes, then release while their scripts are
	# still alive. Clearing per scene would break a surviving host's pause UI.
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and not tree.root.tree_exiting.is_connected(_release):
		tree.root.tree_exiting.connect(_release, CONNECT_ONE_SHOT)
	MenuAssets.set_asset_reader(func(path: String) -> Resource:
		return ResourceLoader.load(path) if ResourceLoader.exists(path) else null)
	# The level game on one machine (local co-op): shared code reaches the client flow through this tree meta, never by file name.
	if tree != null: tree.set_meta("gw_level_flow", load("res://client/local_level_flow.gd"))
	preload("res://lobby_space.gd").client_draw_factory = func() -> Dictionary:
		return {"visuals": LobbyDraw, "environment": LobbyEnvironment.new()}

static func _release() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.has_meta("gw_level_flow"): tree.remove_meta("gw_level_flow")
	MenuAssets.set_asset_reader(Callable())
	preload("res://lobby_space.gd").client_draw_factory = Callable()
