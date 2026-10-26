extends Node3D
## The base of one minigame's view (docs/modes.md). Client only: what players see of a mode, built under the shell's world
## by client/main.gd (online) and client/local_level_flow.gd (one machine) when the mode's round starts, freed when it ends.
## It reads only the mode's replicated state (its rules' state(), match.minigame) and the shell (`run`: game/game_run.gd,
## replica or local role: world, actors, rigs, camera). It never decides anything that counts.
##
## A mode's view.gd extends this file and overrides build, present and hud. Geometry a view adds to the world (pads, tiles)
## collides with the players' own couriers on their machines; the authority never sees it, so the rules must not depend on it.

var run ## game/game_run.gd (replica or local role)
var seats: Array = [] ## slot -> cast index, as the rules' host has them
var my_slot := -1 ## the local player's slot (local play: 0)
var hide_name_tags := false ## true: the game's own name tags hide while this view is up (the view draws its own)

## Called once, right after the view is added to the shell's world.
func setup(shell, round_seats: Array, local_slot: int) -> void:
	run = shell
	seats = round_seats.duplicate()
	my_slot = local_slot
	build()

## True while the local player plays by touch (the overlay is up): a note then names buttons, not keys.
func touching() -> bool:
	var pad: Variant = run.get("touch") if run != null else null
	return pad != null and is_instance_valid(pad) and bool(pad.is_active())

## Build what the mode needs in the world (props, pads, statues, tiles).
func build() -> void:
	pass

## Every rendered frame with the newest state.
func present(_state: Dictionary, _dt: float) -> void:
	pass

## What the mode HUD (modes/mode_hud.gd) shows this frame: any of
## {"title": String (top chip), "big": String (centre, large), "line": String (under it), "timer": float (s, top right, -1 none),
##  "scores": Array (per slot, ints; [] hides the board), "out": Array (slots out of the round), "note": String (bottom),
##  "tint": bool (board rows in the players' colours), "calm": bool (the small layout: pills at 0.9, the banner smaller and high up),
##  and for the show's look (docs/party-show.md "HUD look"): "counters": Array of String (one dark pill each), "counter_age": float,
##  "feed": Array of {name, tail, rank, age, left}, "big_kind": String (a banner kind, "digit", "go" or "" for a big pill), "big_age": float, "marker": Vector2 (the own head on the screen)}.
func hud(_state: Dictionary) -> Dictionary:
	return {}

# ------------------------------------------------------------------ helpers for every mode

## The cast member a slot plays (TeamCast.player).
func cast_player(slot: int) -> Dictionary:
	return preload("res://style/team_cast.gd").player(int(seats[slot]) if slot >= 0 and slot < seats.size() else slot)

## The slot's character rig (character/character_rig.gd or the courier rig), null when there is none.
func rig(slot: int) -> Node3D:
	if run == null or slot < 0 or slot >= run.rigs.size(): return null
	var found: Variant = run.rigs[slot]
	return found if found != null and is_instance_valid(found) else null

## The slot's character position (feet), world space.
func feet(slot: int) -> Vector3:
	return run.actors[slot].global_position if run != null and slot >= 0 and slot < run.actors.size() else Vector3.ZERO
