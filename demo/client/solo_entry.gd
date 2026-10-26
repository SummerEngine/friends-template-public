extends "res://client/presentation_entry.gd"
## The local game for ONE player (res://show_solo.tscn, the standalone `FRIENDS Show` app): no partner, no title page. The app boots
## into the lobby yard; the one player stands on the circle and presses PLAY, and the cast's mode (the show, docs/party-show.md)
## runs for them alone: a points show, nobody is eliminated. The keyboard and the first gamepad both drive the one courier,
## in one full-screen first-person view (game/game_run.gd `local_players`, client/local_presentation.gd, client/local_level_flow.gd).

func _init() -> void:
	super() # the client bootstrap (presentation_entry.gd `_init`)
	local_players = 1
