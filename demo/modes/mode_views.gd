extends RefCounted
## The minigames' views (modes/mode_view.gd), client only: client/main.gd and client/local_level_flow.gd build one when the
## mode's round starts. The shared list of modes is modes/modes.gd.
const VIEWS := {
	"who_said_it": preload("res://modes/who_said_it/view.gd"),
	"friend_swap": preload("res://modes/friend_swap/view.gd"),
	"hot_potato": preload("res://modes/hot_potato/view.gd"),
	"shove_off": preload("res://modes/shove_off/view.gd"),
	"show": preload("res://modes/show/view.gd"),
}

static func new_view(id: String) -> Node3D:
	return (VIEWS[id] as GDScript).new() if VIEWS.has(id) else null
