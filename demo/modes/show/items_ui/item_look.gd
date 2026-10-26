extends RefCounted
## The client side of one show item or event (the rules side is item_rule.gd): its look, its sounds and what it does to the local player's machine. Extend this in `<id>_view.gd`.
## The manager (items_view.gd) tells it what the replicated state says and calls it every frame; nothing here decides anything that counts. Every effect and projectile of the item is
## handed in as a Dictionary the manager keeps for as long as it is in the state; the look may keep its own nodes in it (`node`, `nodes`) and frees them in `end_fx` / `end_shot`.
##
##   fx    {id, slot, kind, dur, age (s since this client first saw it, advanced by the frame), a, b, src, mine (it is on the local player's courier)}
##   shot  {id, kind, p (world, as the last state said, moved on between states), v, tgt, age, node}
## What a look may use of the manager (`m`): `m.run` (the shell: rigs, actors, camera `follow`, audio), `m.my_slot`, `m.rig(slot)`, `m.feet(slot)`, `m.name(slot)`, `m.world` (a Node3D to add nodes to),
## `m.post_layer` (a CanvasLayer under the HUD and the touch buttons: screen distortions go here), `m.over_layer` (over the game, under the round's HUD: letterbox, windows), `m.say(kind, words, line)`
## (a banner), `m.sfx(id, key, at, gain_db)` (a sound of this item: the cast's `sfx` for key "hit", else the template's file audio/items/<id>_<key>.ogg), `m.voice(id)` (the cast's clip, if any).
var m ## modes/show/items_ui/items_view.gd, null in an icon-only instance (the touch button and the HUD pill make one to draw the icon)
var id := ""

## The numbers of a made-up effect of this item for the dress rehearsal (items_rehearsal.gd): its length `dur` and the effect's `a` and `b` as the item's rules put them (fx above). A look whose
## effect has no `duration` tuning, or reads its `a` / `b`, overrides this.
func rehearsal() -> Dictionary:
	return {"dur": preload("res://modes/show/items/catalog.gd").tuning(id, "duration"), "a": 0.0, "b": 0.0}

func setup(manager, kind_id: String) -> void:
	m = manager
	id = kind_id

## The banner kind (client/show_banner.gd) of this item's big words: "item" (blue), "alert" (red), "boon" (gold).
func banner_kind() -> String:
	return "item"

## True for an item that is thrown and may miss (the dance): the line about it is told to the others when it hits, not when it is used (a miss tells none).
func tells_on_hit() -> bool:
	return false

## True for an item that tells its own banner, voice and sounds (the smash: the rush of air where the victim stands when the hand starts to fall, the banner, the voice and the slap when it lands, not when
## the events come): the manager then says and plays none of them for it, the look does (`m.say`, `m.voice`, `m.sfx`).
func announces_itself() -> bool:
	return false

## The icon of the item for the HUD pill and the touch button, light strokes on a dark ground with no disc of its own behind it, centred on `c` within radius `r`; `a` is the alpha.
func draw_icon(_ci: CanvasItem, _c: Vector2, _r: float, _a: float) -> void:
	pass

## An effect of this item came into the state (`fx.mine`: on the local courier); build what it needs.
func begin_fx(_fx: Dictionary) -> void:
	pass

## Every frame an effect is in the state.
func update_fx(_fx: Dictionary, _dt: float) -> void:
	pass

## The effect left the state (its time ran out, or the authority took it off): free everything built for it.
func end_fx(_fx: Dictionary) -> void:
	pass

## What an effect does to the courier of `fx.slot`, merged into game_run.gd item_mods for that slot: freeze, invert, speed, jump, dash, no_flop (courier_motion.gd mods). Called for
## every effect each frame; return {} for none. Only the owner's machine moves its courier, so the others' entries do no harm.
func mods(_fx: Dictionary) -> Dictionary:
	return {}

## What an effect does to the local camera (game/follow_camera.gd `fx`): add "roll" (radians), "fov" (degrees) and "zoom" / "point" / "range" into `camera`. Called for the local player's effects only.
func camera(_fx: Dictionary, _camera: Dictionary) -> void:
	pass

## A projectile of this item appeared / moved on / is gone.
func begin_shot(_shot: Dictionary) -> void:
	pass

func update_shot(_shot: Dictionary, _dt: float) -> void:
	pass

func end_shot(_shot: Dictionary) -> void:
	pass

## The local player's own game events: this look told about an event of its item (`type` items.gd Event), once: the default tells nothing (the manager says the banner and the line).
func on_event(_type: int, _a: int, _b: int) -> void:
	pass
