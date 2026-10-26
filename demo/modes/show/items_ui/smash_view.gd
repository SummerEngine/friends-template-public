extends "res://modes/show/items_ui/item_look.gd"
## SMASH on a client (docs/items.md): a white-gloved hand comes down on the racer in the lead. The effect `a` s of warning (the shadow on the floor grows, the hand
## drops out of the sky over the victim, follows it, cocks back and locks, then slams with an ease-in), `b` s of the character lying flat under the palm, and what is left of its length springing
## back. The hand, its shadow, the dust and the sounds exist on every client; what changes the victim is `mods` (freeze while pinned, `scale`: the squash about the feet, from the same clock on
## every machine), which only the victim's own machine acts on for its courier. The hand model is tools/item_models/hand_glove.py's (demo/modes/show/items_ui/hand.glb).
const ShowTheme := preload("res://client/show_theme.gd")
const BoxLook := preload("res://modes/show/items_ui/box_look.gd")
const Catalog := preload("res://modes/show/items/catalog.gd")

const HAND := "res://modes/show/items_ui/hand.glb"
const HEIGHT := 1.8 ## m, a standing character (character/character_rig.gd HEIGHT)
const START_H := 15.0 ## m over the floor where the hand waits (out of the top of the frame) while the shadow comes alone
const HOVER_H := 6.2 ## m where it hangs while it follows the victim (the show's camera frames about 8 m over the character)
const COCK_H := 7.2 ## m it rises to before the slam
const HAND_SCALE := 2.0 ## the model is 2.9 m from wrist to fingertip and 1.8 m across the palm: at this size the palm (3.6 m) covers the victim whole, the hand is about 6 m long
const PRE := 0.5 ## s of the warning in which only the shadow grows (the hand is still out of the frame)
const COCK := 0.2 ## s of the cocking back
const SLAM := 0.18 ## s of the slam (an ease-in)
const HOLD := 0.55 ## s the hand has gone and the flat character lies there alone, frozen, before it springs back
const LIFT := 0.4 ## s the hand takes to rise away (it fades as it goes)
const LIFT_H := 18.0 ## m the hand rises to when it lets go
const SWELL := 0.15 ## the sideways swell of the flat character
const DUST := 30
const LOOK_UP := 0.7 ## how far the victim's camera moves towards the point over the character while the hand comes
const LOOK_DOWN := 0.85 ## and while the flat character lies there alone (close to it, from above)
const BLOB_MAX := 3.4 ## m, radius of the shadow disc when the hand lands
const STARS := 5
const FOOT := [Vector2(-0.8, 0.5), Vector2(0.0, 0.5), Vector2(0.8, 0.5), Vector2(-0.8, -0.1), Vector2(0.0, -0.1), Vector2(0.8, -0.1), Vector2(-0.8, -0.65), Vector2(0.0, -0.65), Vector2(0.8, -0.65),
	Vector2(-0.55, -1.4), Vector2(-0.2, -1.8), Vector2(0.2, -1.7), Vector2(0.55, -1.3), Vector2(-0.2, -2.3), Vector2(-1.3, -0.45)] ## spots (x, z in the hand model's metres) under the palm, the fingers and the thumb where the hand's rest height is probed

static var _hand_scene: PackedScene
static var _blob: Texture2D
static var _ring: Texture2D
static var _cracks: Texture2D
static var _star: ArrayMesh

class Flash extends Control:
	var amount := 0.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
	func _draw() -> void:
		if amount > 0.01: draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(1.0, 1.0, 1.0, amount))

func banner_kind() -> String:
	return "alert"

## warn, pin and the spring back (smash_rules.gd SPRING): the effect's length and its `a` and `b`.
func rehearsal() -> Dictionary:
	var warn := Catalog.tuning(id, "warn")
	var pin := Catalog.tuning(id, "pin")
	return {"dur": warn + pin + 0.45, "a": warn, "b": pin}

func announces_itself() -> bool:
	return true

## An open hand seen from above, palm down, four fingers and the thumb on a short cuff with the accent band.
func draw_icon(ci: CanvasItem, c: Vector2, r: float, a: float) -> void:
	var col := Color(0.93, 0.97, 1.0, a)
	var edge := Color(0.02, 0.07, 0.25, a)
	var palm := c + Vector2(0.0, r * 0.14)
	var reach := [0.5, 0.64, 0.58, 0.44]
	var root := [-0.27, -0.09, 0.09, 0.27]
	var width := r * 0.17
	for k in 4:
		var base := palm + Vector2(r * float(root[k]), -r * 0.12)
		var tip := base + Vector2(r * (float(root[k]) * 0.34), -r * float(reach[k]))
		ci.draw_line(base, tip, edge, width + r * 0.07, true)
		ci.draw_circle(tip, width * 0.5 + r * 0.035, edge)
	ci.draw_circle(palm, r * 0.37 + r * 0.035, edge)
	var thumb_a := palm + Vector2(-r * 0.3, r * 0.08)
	var thumb_b := palm + Vector2(-r * 0.62, -r * 0.14)
	ci.draw_line(thumb_a, thumb_b, edge, width + r * 0.09, true)
	ci.draw_circle(thumb_b, width * 0.5 + r * 0.045, edge)
	for k in 4:
		var base := palm + Vector2(r * float(root[k]), -r * 0.12)
		var tip := base + Vector2(r * (float(root[k]) * 0.34), -r * float(reach[k]))
		ci.draw_line(base, tip, col, width, true)
		ci.draw_circle(tip, width * 0.5, col)
	ci.draw_circle(palm, r * 0.37, col)
	ci.draw_line(thumb_a, thumb_b, col, width + r * 0.02, true)
	ci.draw_circle(thumb_b, (width + r * 0.02) * 0.5, col)
	var cuff := Rect2(c + Vector2(-r * 0.3, r * 0.44), Vector2(r * 0.6, r * 0.26))
	ci.draw_rect(cuff, edge)
	ci.draw_rect(Rect2(cuff.position + Vector2(0.0, r * 0.02), Vector2(cuff.size.x, r * 0.07)), Color(ShowTheme.BLUE, a))

# ------------------------------------------------------------------ the clock of the effect

static func spring_of(fx: Dictionary) -> float:
	return maxf(float(fx.dur) - float(fx.a) - float(fx.b), 0.1)

## The lengths of the warning's parts for a `warn` s warning: [shadow alone, the hand's descent, the cocking back, the slam] (they shrink together for a short warning and add up to `warn`).
static func phases(warn: float) -> PackedFloat32Array:
	var pre := minf(PRE, warn * 0.35)
	var cock := minf(COCK, warn * 0.2)
	var slam := minf(SLAM, warn * 0.25)
	return PackedFloat32Array([pre, warn - pre - cock - slam, cock, slam])

## Metres between the floor and the hand's underside at `t` s into the effect; `rest` is where it stops (on whatever surface it lands on: smash_view.gd `_rest`).
static func hand_height(t: float, warn: float, pin: float, rest: float) -> float:
	var part := phases(warn)
	var descend_at := part[0]
	var cock_at := descend_at + part[1]
	if t < descend_at: return START_H
	if t < cock_at: return lerpf(START_H, HOVER_H, 1.0 - pow(1.0 - (t - descend_at) / part[1], 3.0))
	if t < cock_at + part[2]: return lerpf(HOVER_H, COCK_H, sin((t - cock_at) / part[2] * PI * 0.5))
	if t < warn: return lerpf(COCK_H, rest, pow((t - cock_at - part[2]) / part[3], 2.2))
	var let_go := warn + pin - HOLD
	if t < let_go: return rest
	var u := clampf((t - let_go) / LIFT, 0.0, 1.0)
	return lerpf(rest, LIFT_H, u * u)

## The squash of the character: (x, y, z) scale about the feet.
static func squash_scale(t: float, warn: float, pin: float, spring: float, squash: float, press: float) -> Vector3:
	var y := 1.0
	var swell := 0.0
	if t < warn:
		var h := hand_height(t, warn, pin, press)
		if h < HEIGHT: y = clampf((h - 0.02) / HEIGHT, squash, 1.0) # the palm comes down on it
	elif t < warn + pin:
		y = squash
		var since := t - warn
		swell = 0.5 * exp(-since * 11.0) * sin(since * 42.0) # the slap rings through it
	else:
		var sec := t - warn - pin
		var s := clampf(sec / spring, 0.0, 1.0)
		y = 1.0 + (squash - 1.0) * exp(-3.0 * s) * cos(TAU * 1.4 * s) * (1.0 - s) # up with an overshoot, a couple of damped bounces
	var wide := 1.0 + SWELL * (1.0 - y) / maxf(1.0 - squash, 0.01) + SWELL * swell
	return Vector3(wide, y, wide)

# ------------------------------------------------------------------ built once

static func _gradient_texture(colors: PackedColorArray, offsets: PackedFloat32Array) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = colors
	gradient.offsets = offsets
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	return texture

static func blob_texture() -> Texture2D:
	if _blob == null:
		_blob = _gradient_texture(PackedColorArray([Color(0, 0, 0, 0.92), Color(0, 0, 0, 0.85), Color(0, 0, 0, 0.0)]), PackedFloat32Array([0.0, 0.5, 1.0]))
	return _blob

static func ring_texture() -> Texture2D:
	if _ring == null:
		_ring = _gradient_texture(PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)]), PackedFloat32Array([0.0, 0.66, 0.9, 1.0]))
	return _ring

## Jagged cracks running out of the middle of the floor under the palm, ink on clear.
static func crack_texture() -> Texture2D:
	if _cracks != null: return _cracks
	var size := 256
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 24102026
	var ink := Color(0.04, 0.04, 0.07, 0.9)
	var centre := Vector2(size, size) * 0.5
	var rays := 11
	for k in rays:
		var angle := TAU * (float(k) + rng.randf_range(-0.25, 0.25)) / rays
		var p := centre + Vector2.from_angle(angle) * 16.0
		var reach := rng.randf_range(70.0, 122.0)
		var walked := 16.0
		var thick := 3.0
		while walked < reach:
			var step := rng.randf_range(10.0, 17.0)
			angle += rng.randf_range(-0.34, 0.34)
			var q := p + Vector2.from_angle(angle) * step
			_line(image, p, q, ink, thick)
			if rng.randf() < 0.35 and walked < reach * 0.75: # a twig
				var twig := angle + (0.7 if rng.randf() < 0.5 else -0.7)
				_line(image, q, q + Vector2.from_angle(twig) * rng.randf_range(10.0, 24.0), ink, maxf(thick - 1.0, 1.0))
			p = q
			walked += step
			thick = maxf(thick - 0.35, 1.0)
	_cracks = ImageTexture.create_from_image(image)
	return _cracks

static func _line(image: Image, from: Vector2, to: Vector2, color: Color, thick: float) -> void:
	var steps := int(from.distance_to(to)) + 1
	var radius := thick * 0.5
	for i in steps + 1:
		var p := from.lerp(to, float(i) / steps)
		for dy in range(-ceili(radius), ceili(radius) + 1):
			for dx in range(-ceili(radius), ceili(radius) + 1):
				if Vector2(dx, dy).length() > radius + 0.2: continue
				var x := int(p.x) + dx
				var y := int(p.y) + dy
				if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height(): image.set_pixel(x, y, color)

static func hand_scene() -> PackedScene:
	if _hand_scene == null and ResourceLoader.exists(HAND): _hand_scene = load(HAND)
	return _hand_scene

## A flat five-pointed star facing +Z (the stars over the flat character are billboards of it), 1 m across.
static func star_mesh() -> ArrayMesh:
	if _star != null: return _star
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.BACK)
	for k in 10:
		var a := Vector2.from_angle(-PI * 0.5 + TAU * float(k) / 10.0) * (0.5 if k % 2 == 0 else 0.21)
		var b := Vector2.from_angle(-PI * 0.5 + TAU * float(k + 1) / 10.0) * (0.5 if (k + 1) % 2 == 0 else 0.21)
		tool.add_vertex(Vector3.ZERO)
		tool.add_vertex(Vector3(a.x, -a.y, 0.0))
		tool.add_vertex(Vector3(b.x, -b.y, 0.0))
	_star = tool.commit()
	return _star

func _flat(texture: Texture2D, tint := Color.WHITE) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	mesh.orientation = PlaneMesh.FACE_Y
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = texture
	material.albedo_color = tint
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

func _tint(node: MeshInstance3D, alpha: float) -> void:
	(node.material_override as StandardMaterial3D).albedo_color.a = alpha

# ------------------------------------------------------------------ the effect

func begin_fx(fx: Dictionary) -> void:
	if m == null: return
	var slot := int(fx.slot)
	var feet: Vector3 = m.feet(slot)
	fx["pos"] = feet
	fx["hit"] = float(fx.age) >= float(fx.a) # first heard after the slap: no slap again
	fx["back"] = float(fx.age) >= float(fx.a) + float(fx.b)
	fx["puffs"] = []
	fx["rest"] = Catalog.tuning(id, "squash") * HEIGHT + 0.03
	var root := Node3D.new()
	root.name = "SmashFx"
	m.add_child(root)
	root.global_position = feet
	fx["root"] = root
	var shadow := _flat(blob_texture())
	root.add_child(shadow)
	shadow.position.y = 0.025
	fx["shadow"] = shadow
	var cracks := _flat(crack_texture())
	root.add_child(cracks)
	cracks.position.y = 0.032
	cracks.visible = bool(fx.hit)
	fx["cracks"] = cracks
	var wave := _flat(ring_texture())
	root.add_child(wave)
	wave.position.y = 0.04
	wave.visible = false
	fx["wave"] = wave
	var scene := hand_scene()
	if scene != null:
		var hand := scene.instantiate() as Node3D
		m.add_child(hand)
		var accent := BoxLook.accent()
		var materials: Array = []
		for body: Node in hand.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := body as MeshInstance3D
			var own: Material = mesh_node.mesh.surface_get_material(0)
			var copy := (own.duplicate() if own != null else StandardMaterial3D.new()) as StandardMaterial3D
			if str(mesh_node.name).begins_with("Band"): copy.albedo_color = accent
			elif str(mesh_node.name).begins_with("Hand"):
				copy.emission_enabled = true # a white glove stays white from underneath too (the camera mostly sees it from below)
				copy.emission = Color(0.8, 0.84, 0.95)
				copy.emission_energy_multiplier = 0.5
			mesh_node.set_surface_override_material(0, copy)
			mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			materials.append(copy)
		fx["hand"] = hand
		fx["materials"] = materials
		hand.global_position = feet + Vector3(0.0, START_H, 0.0)
	if bool(fx.mine):
		var flash := Flash.new()
		m.over_layer.add_child(flash)
		fx["flash"] = flash
	if not bool(fx.hit): # the rush of air comes down with the hand: heard where it lands (in the victim's own ears for the victim and for who threw it)
		if bool(fx.mine) or int(fx.src) == m.my_slot: m.sfx(id, "use")
		else: m.sfx(id, "use", feet, -2.0)

func update_fx(fx: Dictionary, dt: float) -> void:
	var root: Node3D = fx.get("root")
	if m == null or root == null: return
	var slot := int(fx.slot)
	var t := float(fx.age)
	var warn := float(fx.a)
	var pin := float(fx.b)
	var spring := spring_of(fx)
	var squash := Catalog.tuning(id, "squash")
	var press := squash * HEIGHT + 0.03
	var part := phases(warn)
	var cock_at: float = part[0] + part[1]
	var let_go := warn + pin - HOLD
	var feet: Vector3 = m.feet(slot)
	# where the hand is over the floor: it follows the victim, slower once it is cocked back, and holds the spot for the slam
	var rate := 6.0 if t < cock_at else (3.0 if t < warn else 14.0)
	var pos: Vector3 = fx.pos
	pos = Vector3(lerpf(pos.x, feet.x, 1.0 - exp(-rate * dt)), feet.y, lerpf(pos.z, feet.z, 1.0 - exp(-rate * dt)))
	fx.pos = pos
	root.global_position = pos
	var lift := clampf((t - let_go) / LIFT, 0.0, 1.0) # the hand rising away
	var settle := clampf((t - warn - pin) / spring, 0.0, 1.0) # the spring back
	var hand: Node3D = fx.get("hand")
	var h := START_H
	if hand != null:
		# the heading: the fingers point across the view (to the right, a little at the lens): a hand seen from below reads best along the screen, not foreshortened
		var camera_now: Camera3D = m.get_viewport().get_camera_3d()
		var toward := Vector3.ZERO
		if camera_now != null: toward = pos - camera_now.global_position
		toward.y = 0.0
		var want := 0.0
		if toward.length() > 0.5:
			var ahead := toward.normalized()
			var across := Vector3(-ahead.z, 0.0, ahead.x) * cos(0.3) - ahead * sin(0.3)
			want = atan2(-across.x, -across.z)
		if not fx.has("yaw"): fx["yaw"] = want
		if t < warn - part[3]: fx.yaw = lerp_angle(float(fx.yaw), want, 1.0 - exp(-4.0 * dt))
		# where it comes to rest: on the highest surface under the palm and fingers (a spinner's bar sweeping through lifts it), never into it
		if t >= cock_at - 0.1 and t < let_go:
			var wanted := press
			var top := _surface(pos, float(fx.yaw), feet.y)
			if not is_nan(top): wanted = maxf(press, top - feet.y + 0.02)
			var rest: float = fx.rest
			fx.rest = wanted if wanted > rest else lerpf(rest, wanted, 1.0 - exp(-10.0 * dt))
		h = hand_height(t, warn, pin, float(fx.rest))
		var cock := 0.0
		if t < cock_at: cock = 0.24 + 0.05 * sin(t * 3.4)
		elif t < warn: cock = lerpf(0.24, 0.5, sin(minf((t - cock_at) / part[2], 1.0) * PI * 0.5)) * (1.0 - pow(clampf((t - cock_at - part[2]) / part[3], 0.0, 1.0), 1.4)) # the fingers rise as it cocks back, flat for the slap
		var swing := 0.55 * pow(1.0 - clampf((t - part[0]) / part[1], 0.0, 1.0), 2.0) # it drops in tipping from the side
		var shake := Vector3.ZERO
		if t >= warn and t < let_go:
			var since := t - warn
			shake = Vector3(sin(since * 83.0), 0.0, cos(since * 71.0)) * 0.035 * exp(-since * 9.0) # the palm rings on the floor
		hand.global_position = Vector3(pos.x, pos.y + h, pos.z) + shake
		hand.global_basis = Basis(Vector3.UP, float(fx.yaw)) * Basis(Vector3.RIGHT, cock) * Basis(Vector3.BACK, swing) * Basis.from_scale(Vector3.ONE * HAND_SCALE)
		var alpha := 1.0 - smoothstep(0.1, 0.8, lift)
		for material: StandardMaterial3D in fx.materials:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 0.999 else BaseMaterial3D.TRANSPARENCY_DISABLED
			material.albedo_color.a = alpha
	# the shadow: from the first moment it grows and darkens; the hand arrives into it, and it lets go as the hand lifts
	var shadow: MeshInstance3D = fx.shadow
	var closeness := clampf(t / maxf(warn, 0.1), 0.0, 1.0)
	var blob := lerpf(1.1, BLOB_MAX, pow(closeness, 0.7))
	shadow.scale = Vector3(blob * 2.0, 1.0, blob * 2.0)
	_tint(shadow, lerpf(0.6, 1.0, pow(closeness, 0.7)) * (1.0 - lift))
	if t >= warn - 0.25 and t < warn: # the lock: the disc beats once as it stops following
		shadow.scale *= 1.0 + 0.05 * sin((t - warn + 0.25) / 0.25 * PI * 4.0)
	# the slap
	if not bool(fx.hit) and t >= warn:
		fx.hit = true
		_impact(fx, pos)
	if bool(fx.hit): _after_impact(fx, t - warn, settle, dt)
	_stars(fx, t, let_go, warn + pin)
	if not bool(fx.back) and t >= warn + pin:
		fx.back = true
		if bool(fx.mine): m.sfx(id, "back")
		else: m.sfx(id, "back", pos + Vector3(0.0, 0.5, 0.0), -3.0)
	var flash: Flash = fx.get("flash")
	if flash != null:
		flash.amount = 0.55 * exp(-maxf(t - warn, 0.0) * 14.0) if t >= warn else 0.0
		flash.queue_redraw()

## Metres over the floor of the highest surface under the hand's palm and fingers (a ray down from over the hazards at each spot of FOOT; the couriers' bodies are not surfaces), NAN for none.
func _surface(pos: Vector3, yaw: float, floor_y: float) -> float:
	var space := (m as Node3D).get_world_3d().direct_space_state
	var turn := Basis(Vector3.UP, yaw)
	var top := NAN
	for spot: Vector2 in FOOT:
		var at := pos + turn * Vector3(spot.x, 0.0, spot.y) * HAND_SCALE
		var found := _ray_down(space, Vector3(at.x, floor_y + 3.2, at.z), floor_y - 0.6)
		if is_nan(found) or found - floor_y > 2.4: continue
		top = found if is_nan(top) else maxf(top, found)
	return top

func _ray_down(space: PhysicsDirectSpaceState3D, from: Vector3, floor_y: float) -> float:
	var skip: Array[RID] = []
	for _try in 4:
		var query := PhysicsRayQueryParameters3D.create(from, Vector3(from.x, floor_y, from.z))
		query.exclude = skip
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if hit.is_empty(): return NAN
		if hit.collider is CharacterBody3D:
			skip.append(hit.rid)
			continue
		return (hit.position as Vector3).y
	return NAN

## Little stars circling over the flat character while the hand has gone and it lies there alone (a pancake the camera can find), from `from` to `to` s.
func _stars(fx: Dictionary, t: float, from: float, to: float) -> void:
	var ring: Node3D = fx.get("stars")
	if ring == null:
		if t < from: return
		ring = Node3D.new()
		ring.name = "Stars"
		(fx.root as Node3D).add_child(ring)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = Color(1.0, 0.84, 0.22, 1.0)
		fx["star_material"] = material
		for k in STARS:
			var star := MeshInstance3D.new()
			star.mesh = star_mesh()
			star.material_override = material
			star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ring.add_child(star)
		fx["stars"] = ring
	var alpha := clampf((t - from) / 0.15, 0.0, 1.0) * (1.0 - clampf((t - to) / 0.12, 0.0, 1.0))
	ring.visible = alpha > 0.01
	(fx.star_material as StandardMaterial3D).albedo_color.a = alpha
	var spin := t * 4.2
	for k in ring.get_child_count():
		var around := spin + TAU * float(k) / STARS
		var star := ring.get_child(k) as Node3D
		star.position = Vector3(cos(around) * 0.8, 1.15 + 0.12 * sin(spin * 1.7 + float(k)), sin(around) * 0.8)
		star.scale = Vector3.ONE * (0.38 + 0.06 * sin(spin * 3.0 + float(k) * 2.0)) * (0.6 + 0.4 * alpha)
		star.rotation.z = spin * 0.8 + float(k)

## The palm lands: the slap, a ring of dust, a shock ring and the cracks.
func _impact(fx: Dictionary, pos: Vector3) -> void:
	if bool(fx.mine):
		m.say(banner_kind(), Catalog.text(id, "banner")) # the big words bang in as the palm lands (they would hide the hand coming down)
		m.voice(id)
		m.sfx(id, "hit")
	else: m.sfx(id, "hit", pos + Vector3(0.0, 0.5, 0.0), -1.0)
	var root: Node3D = fx.root
	var rng := RandomNumberGenerator.new()
	rng.seed = int(fx.id) * 7919 + 13
	var puffs: Array = fx.puffs
	for k in DUST:
		var body := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		sphere.radial_segments = 8
		sphere.rings = 4
		body.mesh = sphere
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.9, 0.87, 0.8, 0.8)
		body.material_override = material
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(body)
		var angle := TAU * (float(k) + rng.randf_range(-0.4, 0.4)) / DUST
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		body.position = dir * rng.randf_range(0.8, 1.15) * HAND_SCALE + Vector3(0.0, 0.2, 0.0)
		puffs.append({"node": body, "v": dir * rng.randf_range(3.6, 6.6) + Vector3(0.0, rng.randf_range(0.9, 2.2), 0.0), "size": rng.randf_range(1.0, 1.7), "life": rng.randf_range(0.75, 1.2), "age": 0.0, "material": material})
	(fx.cracks as Node3D).visible = true
	(fx.wave as Node3D).visible = true

func _after_impact(fx: Dictionary, since: float, settle: float, dt: float) -> void:
	var cracks: MeshInstance3D = fx.cracks
	cracks.scale = Vector3(9.0, 1.0, 9.0) * (0.82 + 0.18 * minf(since / 0.08, 1.0))
	cracks.rotation.y = float(int(fx.id) % 7) * 0.9
	_tint(cracks, (1.0 - smoothstep(0.0, 1.0, settle)) * 0.85) # the cracks stay until the character springs back
	var wave: MeshInstance3D = fx.wave
	var w := clampf(since / 0.42, 0.0, 1.0)
	wave.visible = w < 1.0
	wave.scale = Vector3.ONE * lerpf(3.0, 14.0, 1.0 - pow(1.0 - w, 2.5))
	_tint(wave, 0.75 * (1.0 - w))
	var keep: Array = []
	for puff: Dictionary in fx.puffs:
		puff.age = float(puff.age) + dt
		var life := float(puff.life)
		if float(puff.age) >= life:
			(puff.node as Node).queue_free()
			continue
		var u := float(puff.age) / life
		var node: Node3D = puff.node
		puff.v = (puff.v as Vector3) * exp(-3.2 * dt) + Vector3(0.0, 0.6, 0.0) * dt
		node.position += (puff.v as Vector3) * dt
		node.scale = Vector3.ONE * float(puff.size) * (0.5 + 1.7 * (1.0 - pow(1.0 - u, 2.0)))
		(puff.material as StandardMaterial3D).albedo_color.a = 0.8 * (1.0 - u) * (1.0 - u)
		keep.append(puff)
	fx.puffs = keep

func end_fx(fx: Dictionary) -> void:
	for key in ["root", "hand", "flash"]:
		var node: Node = fx.get(key)
		if node != null and is_instance_valid(node): node.queue_free()
		fx.erase(key)

# ------------------------------------------------------------------ what it does to the victim

func mods(fx: Dictionary) -> Dictionary:
	var t := float(fx.age)
	var warn := float(fx.a)
	var pin := float(fx.b)
	var squash := Catalog.tuning(id, "squash")
	var out := {"scale": squash_scale(t, warn, pin, spring_of(fx), squash, squash * HEIGHT + 0.03)}
	if t >= warn and t < warn + pin: out["freeze"] = true
	return out

## The victim's camera: it looks up at the hand as the shadow closes (a slow arc in towards a point over the character), a hard punch, a roll shake and a jolt on the slap, then it climbs
## over the flat character (a low camera cannot see a pancake) while it lies there alone, and lets go as it springs back.
func camera(fx: Dictionary, camera_fx: Dictionary) -> void:
	var t := float(fx.age)
	var warn := float(fx.a)
	var pin := float(fx.b)
	var let_go := warn + pin - HOLD
	var since := t - warn
	var push := 4.0 * smoothstep(warn - 0.9, warn, t)
	if since >= 0.0: push = (4.0 + 7.0 * minf(since / 0.04, 1.0)) * exp(-since * 6.5)
	camera_fx["fov"] = float(camera_fx.get("fov", 0.0)) - push
	if since >= 0.0: camera_fx["roll"] = float(camera_fx.get("roll", 0.0)) + 0.09 * sin(since * 50.0) * exp(-since * 7.0) * (1.0 if int(fx.id) % 2 == 0 else -1.0)
	var zoom := LOOK_UP * smoothstep(0.0, 0.8, t)
	var low := 0.0 # how much of the way the point has come down to the floor
	var range_m := 9.0
	if since >= 0.0:
		low = smoothstep(0.0, 0.3, since)
		zoom = lerpf(zoom, 0.2, smoothstep(0.0, 0.3, since)) + 0.22 * exp(-since * 9.0) # the jolt
	var closer := smoothstep(0.0, 0.3, t - let_go) # how much of the way the camera has come over the flat character
	if t > let_go:
		zoom = lerpf(zoom, LOOK_DOWN, closer)
		range_m = lerpf(9.0, 3.8, closer)
	if t > warn + pin: zoom = lerpf(LOOK_DOWN, 0.0, smoothstep(0.0, 0.4, t - warn - pin))
	if zoom <= 0.001 or m == null: return
	var point: Vector3 = (m.feet(int(fx.slot)) as Vector3) + Vector3(0.0, lerpf(4.0, 0.5, low), 0.0)
	var seen: Camera3D = m.get_viewport().get_camera_3d()
	if seen == null: return
	var off := seen.global_position - point
	var start := atan2(off.z, off.x) # the arc keeps the side the camera is on (it only comes closer and higher), so the heading is its own angle round the point
	camera_fx["around"] = atan2(-cos(start), -sin(start))
	camera_fx["rise"] = lerpf(1.0 + 3.5 * low, 3.6, closer) # the point drops to the floor on the slap: the camera keeps its height, then settles a little lower for the hold
	camera_fx["zoom"] = zoom
	camera_fx["point"] = point
	camera_fx["range"] = range_m
