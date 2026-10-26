extends RefCounted
## The four comic inks (navy, tomato, cobalt, yellow) on cream paper, and the few ink-shaded props that use them (goal pad rings, flags).
const Style := preload("res://style/friends_style.gd")
const SURFACE := "res://style/ink_surface.gdshader"

const INK := Color("#1b1d3a")
const TOMATO := Color("#ff5a36")
const COBALT := Color("#2c4bff")
const YELLOW := Color("#ffd23f")
const PAPER := Color("#f6ecd2")

## Painted ring for a flat quad on the ground (surface mode 13).
static func checkpoint_ring() -> Material:
	return Style.shader_material(SURFACE, {"mode": 13, "base_color": TOMATO, "alt_color": PAPER, "ink_color": INK})

## Flag: pole in ink, cloth in tomato or `cloth_color` (flat box shading, no stripes).
static func checkpoint_flag(cloth: bool, cloth_color := TOMATO) -> Material:
	var color := cloth_color if cloth else INK.lightened(0.1)
	var material := Style.shader_material(SURFACE, {"mode": 0, "base_color": color, "ink_color": INK, "half_size": Vector3.ONE * 10000.0})
	return Style.outlined(material, INK, 0.03, false, true)
