extends SceneTree
## Frames of the title and the results stage (style/menu_stage.gd) as the menu shows them: the whole window is the stage (no menu column drawn over it).
## Offscreen binary only, never windowed (ONE render at a time machine-wide):
##   <Summer offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 --resolution 1280x720 \
##     --path demo -s "$PWD/tools/menu_stage_frames.gd" -- --shots=<dir> [--prefix=menu_] [--only=title,results]
## Prints MENU_FRAMES lines with the build time of the candy world seen in the tree and the path of every picture.
const MenuStage := preload("res://style/menu_stage.gd")

var shots := ""
var prefix := "menu_"
var only: PackedStringArray = ["title", "results"]

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="): shots = argument.trim_prefix("--shots=")
		if argument.begins_with("--prefix="): prefix = argument.trim_prefix("--prefix=")
		if argument.begins_with("--only="): only = argument.trim_prefix("--only=").split(",")
	create_timer(90.0).timeout.connect(func() -> void:
		print("MENU_FRAMES FAIL timed out")
		quit(1))
	run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(shots)
	for kind in only:
		var stage := MenuStage.new(kind)
		get_root().add_child(stage)
		if kind == "results": stage.set_ranking([0, 1, 2])
		for i in 90: await process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/%s%s.png" % [shots, prefix, kind]
		get_root().get_texture().get_image().save_png(path)
		print("MENU_FRAMES ", kind, " ", path)
		stage.queue_free()
		await process_frame
	quit(0)
