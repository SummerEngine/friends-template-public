extends RefCounted
## A rainbow arch of the candy look (our own code): a half ellipse of five glossy tubes side by side, red, orange, yellow, green, blue from the outside in, springing from two
## feet and standing over the finish (style/goal_sign.gd gantry). Each tube is a round pipe (smooth normals), the five touch like the bands of an inflatable arch. Plain geometry
## into a style/block_mesh.gd group of vertex colours (the sign's "body" surface, which takes sRGB tints: flat, glossy). No collision, no light of its own.
const BANDS: Array[Color] = [Color("#ea3a3f"), Color("#f7862a"), Color("#ffd23a"), Color("#43c45c"), Color("#2f7df0")]
const TUBE := 0.21             ## m: the radius of one band's tube
const PITCH := 0.34            ## m: from one band's axis to the next, across the arch
const SIDES := 12              ## round of a tube
const STEPS := 40              ## segments along the half ellipse

## The width of the ribbon the five bands make across the arch (m).
static func ribbon() -> float:
	return PITCH * float(BANDS.size() - 1) + 2.0 * TUBE

## Adds the arch to `group` (a BlockMesh.Group): the half ellipse of half span `reach` and rise `rise` standing on `base_y` at x = `centre`, in the plane z = 0 (the face looks along z). The
## band k of BANDS is `k - 2` pitches inside the middle band's ellipse: the red one is the outside.
static func add(group: Variant, centre: float, base_y: float, reach: float, rise: float) -> void:
	var count := BANDS.size()
	for band in count:
		var shrink := (float(band) - float(count - 1) * 0.5) * PITCH   # + inside, - outside (band 0, red, is outside)
		var rx := reach - shrink
		var ry := rise - shrink
		var colour := BANDS[band]   # sRGB: the sign's body shader converts
		var rings: Array[Array] = []
		for step in STEPS + 1:
			var angle := PI * float(step) / STEPS
			var p := Vector3(centre + rx * cos(angle), base_y + ry * sin(angle), 0.0)
			var tangent := Vector3(-rx * sin(angle), ry * cos(angle), 0.0).normalized()
			var in_plane := Vector3(tangent.y, -tangent.x, 0.0)   # across the tube, in the arch's plane
			var ring: Array = []
			for k in SIDES + 1:
				var phi := TAU * float(k) / SIDES
				var n := in_plane * cos(phi) + Vector3.BACK * sin(phi)
				ring.append(group.add(p + n * TUBE, n, Vector2.ZERO, colour))
			rings.append(ring)
		for step in STEPS:
			var a: Array = rings[step]
			var b: Array = rings[step + 1]
			for k in SIDES:
				group.quad(a[k], a[k + 1], b[k + 1], b[k], group.n[a[k]] + group.n[a[k + 1]])
