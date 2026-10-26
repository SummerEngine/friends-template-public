extends RefCounted
## Collision look: what you see is what you collide with. Hands every call to the look in use: style/real_look.gd (the facility look of
## the game) or style/ink_look.gd (the comic look, dev runs only: style/surfaces.gd ink()). Same API for both; nothing here touches
## collision, hazards or the network.
const Surfaces := preload("res://style/surfaces.gd")
const Real := preload("res://style/real_look.gd")
const Ink := preload("res://style/ink_look.gd")
const SlotFrames := preload("res://style/slot_frames.gd")
const WATER_Y := -8.0

## Obstacle boxes (a box shape with the meta "slot", docs/slots.md) get the cast's faces on top of either look: SlotFrames.box_faces.
static func draw_level(level_root: Node3D, route: PackedVector3Array, slicer = null) -> int:
	var drawn := 0
	if Surfaces.ink(): drawn = await Ink.draw_level(level_root, route, slicer)
	else: drawn = await Real.draw_level(level_root, route, slicer)
	SlotFrames.box_faces(level_root.find_children("*", "CollisionShape3D", true, false))
	return drawn

static func draw_shapes(shapes: Array, hazard := false, painted: Array = []) -> int:
	var drawn := Ink.draw_shapes(shapes, hazard) if Surfaces.ink() else Real.draw_shapes(shapes, hazard, painted)
	SlotFrames.box_faces(shapes)
	return drawn

static func edges(world: Node3D) -> void:
	if Surfaces.ink(): Ink.edges(world)

static func void_plane(parent: Node3D) -> MeshInstance3D:
	return Ink.void_plane(parent) if Surfaces.ink() else Real.void_plane(parent)

## `goal` false: START only (a level whose goal is a hero prop, docs/hero-prop.md). `arch_under`: how high the underside of an arch over the goal is over the
## goal floor (SlotFrames.goal_arch_under), INF for none: the GOAL word and its logo card stay clear of it.
static func mark_level(level_root: Node3D, start: Vector3, goal_floor: Vector3, lateral: Vector3, goal := true, arch_under := INF, goal_word := true) -> void:
	if Surfaces.ink(): Ink.mark_level(level_root, start, goal_floor, lateral, goal, arch_under)
	else: Real.mark_level(level_root, start, goal_floor, lateral, goal, arch_under, goal_word)
