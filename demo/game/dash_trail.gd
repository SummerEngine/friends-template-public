extends Node3D
## The dash's puffs (client only, game_run.gd): a trail of soft round puffs in the player's cast colour behind any courier that moves faster
## than a walk. Nothing is sent: every client reads the speeds it already draws (the owner's own physics, the replicas' smoothed poses), so
## a dash seen from another client looks like the owner's. One CPUParticles3D per seat, world space, a few meshes (phones: no GPU particles).
const TeamCast := preload("res://style/team_cast.gd")
const FAST := 7.5 ## m/s of planar speed that leaves puffs (the walk is 5, the dash 11)
const CHEST := Vector3(0.0, 0.85, 0.0)

var _trails := {} ## seat -> CPUParticles3D

## Call once per rendered frame for every courier: its feet, velocity and whether it is drawn.
func follow(seat: int, shown: bool, feet: Vector3, velocity: Vector3) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	var trail: CPUParticles3D = _trails.get(seat)
	if trail == null:
		if not shown or speed < FAST: return
		trail = _build(seat)
	trail.global_position = feet + CHEST
	trail.emitting = shown and speed >= FAST

func _build(seat: int) -> CPUParticles3D:
	var color := TeamCast.player_color(seat).lerp(Color.WHITE, 0.3)
	var mesh := SphereMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.44
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	mesh.material = material
	var fade := Gradient.new()
	fade.set_color(0, Color(color, 0.95))
	fade.set_color(1, Color(color, 0.0))
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.1))
	var trail := CPUParticles3D.new()
	trail.name = "DashTrail%d" % seat
	trail.mesh = mesh
	trail.amount = 22
	trail.lifetime = 0.45
	trail.local_coords = false
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	trail.emission_sphere_radius = 0.2
	trail.gravity = Vector3.ZERO
	trail.direction = Vector3.UP
	trail.spread = 180.0
	trail.initial_velocity_min = 0.2
	trail.initial_velocity_max = 0.9
	trail.color_ramp = fade
	trail.scale_amount_curve = shrink
	trail.emitting = false
	add_child(trail)
	_trails[seat] = trail
	return trail
