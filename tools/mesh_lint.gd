extends SceneTree
## Mesh lint: defects on the BUILT visual meshes of the stage levels (25-28 tile rounds, 29 and 30 races), headless. Builds the real LevelWorld as a client (the dummy renderer keeps
## the ArrayMesh data: `surface_get_arrays`), shows each level in turn and reads every visible MeshInstance3D / MultiMeshInstance3D under the world (level look, ceilings,
## hazard looks, goal arch and markers, tile floors, ground, arena cage, race / arena world) in the level's own coordinates (the level origin subtracted), at clock 0.
##   tools/mesh_lint.sh [--levels=25,26,27,28,29,30] [--out=build/mesh_lint.json] [--baseline=build/mesh_lint_base.json] [--budget=0] ...
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 600 <Summer> --headless --audio-driver Dummy --rendering-driver dummy --fixed-fps 60 --path demo \
##     -s $PWD/tools/mesh_lint.gd -- [--levels=25,26] [--out=file.json] [--baseline=file.json] [--budget=0] [--warn-budget=-1] [--selftest]
## `--path demo` of ANY worktree: the tool judges whatever look code the tree has. Prints MESHLINT lines and `MESHLINT ok=<bool>` last; exit 1 when over a budget.
## `--lobby [--dir=<small level directory, e.g. tools/level_testdata: a short world build>]`: lints the built lobby yard instead of levels, as the pseudo-level 99 (`MESHLINT level 99: ...`, JSON key "99"; tools/mesh_lint.sh --lobby).
## `--podium`: lints the victory podium room (style/podium_room.gd, built as the client builds it, no level world) as the pseudo-level 98 (JSON key "98"; tools/mesh_lint.sh --podium). The skyline is scope "world".
## The world is built as a client like tools/lobby_frames.gd does (LobbySpace room with the client look, LobbyEnvironment, the walk-in circles and signs of WalkInMarkers), positions are yard-local (WalkInLobby.ORIGIN
## subtracted). Meshes under a node named City / SkyThings / NearSky / LobbyWorld* are scope "world" (not examined for gaps and overlaps), every other one scope "level". Label3D nodes are not mesh instances and
## are ignored; a TextMesh MeshInstance3D is examined like any mesh.
##
## RULES (all lengths in metres, every one an argument):
##  Parts. A mesh's triangles are welded by position (`--weld`, 0.5 mm) and split into connected COMPONENTS: a rounded block of a merged level mesh, one tile of a MultiMesh, one
##  pillar are one component each. A component is the "part" of every rule below (reported as `Node#c<i> <size> @<level-local centre>`; a MultiMesh element as `Node[i]`).
##  C1 COPLANAR (z-fighting, class `zfight`, `zfight_back`, `zfight_self`, `decal`; counted against `--budget`, default 0):
##     two triangles whose front normals have |dot| > `--normal-dot` (0.9999) and lie in one plane (every vertex of each within `--eps` 2 mm of the other's plane) and whose
##     overlap, clipped in the plane, is > `--min-area` (1 cm^2), from DIFFERENT components (same component: only when they share no welded vertex).
##     Facing the same way: always a defect (`zfight`; `decal` when one of the two materials is blended, a deliberate overlay that can still flicker).
##     Facing opposite ways (`zfight_back`): two closed solids touching face to face hide each other's faces, so it is a defect only for an OPEN component (a quad, a
##     sheet, a glyph: some edge not shared by two triangles) drawn two-sided (cull_disabled): both are visible then. `same material` in a report line: both faces wear one
##     material instance (the overlap may not show, still wasted and fragile).
##     A finding is one pair of components (many triangle pairs, summed overlap area). Broad phase: triangles bucketed by plane (normal quantised 5 mm, distance 2 cm,
##     neighbour buckets for planes near a bucket edge), then a 2 m grid inside each bucket in the plane's own axes: 5528 tiles take seconds.
##  C2 GAPS (class `gap`, a warning; `--warn-budget`, default -1: not counted): two components' axis-aligned faces that look at each other, A's +axis face and B's -axis face
##     (or the other way round) with 0 < distance `--gap-min` (0.1 mm) .. `--gap-max` (5 cm), and their rectangles overlap in the other two axes by > 1 cm each: a hairline
##     between a panel and a pillar, a beam end and a post, a rim and its block. A face is the component's outermost flat axis-aligned face in that direction (within eps).
##     Two KIT parts (block-kit material) facing each other across a gap are the kit's own rim seam / groove (block_kit.gd SEAM, GROOVE): class `gap_seam`, intended,
##     listed in the JSON (`gap_seam`) and not counted. `gap_decal`: a part thinner than 2 cm (a pad marker, a decal) hovering over a surface so it never z-fights: intended.
##     `gap_lift`: a gap along y of at most `--lift-gap` (12 mm) between level-look parts (neither deco): the 3 mm steps of real_look.gd LIFT_STEP that keep equal tops from z-fighting
##     (a block and what stands on it are lifted by different ranks): intended trade-off of the look, listed, not counted. Every other pair is a real `gap`.
##     Elements of ONE MultiMesh are not compared with each other (a tile layer's grooves are the design; `--gaps-multimesh` includes them); movers (`Hazard_*`) are skipped
##     (`--gap-hazards`); only the scopes `--gap-scopes` (level, tiles, cage) are examined, every scope is a possible support.
##  C3 VERTICAL CONNECTIVITY (class `bottom_gap`, `bottom_free`, `floating`, warnings in the same budget as C2): a vertical-ish component (height >= `--tall` 1 m and >=
##     half its longest horizontal extent: a pillar, a leg, a post, a panel) must touch something at its bottom: another component whose footprint overlaps (> 1 cm^2) and
##     whose height range holds the bottom's height within `--eps` (a component thinner than 2 cm in plan is a sheet or a sign, not a support). No touch: `bottom_gap` when the nearest thing under it is within `--gap-max` (a hairline under a leg),
##     else `bottom_free` when its top touches something (it hangs: the air under it is reported) or `floating` when neither end touches.
##  C4 OVERLAPS (class `overlap_deco_kit`, `overlap_deco_block`, `overlap_deco_deco`, `overlap_kit_block`; `--overlap-budget`, default -1: reported, not counted): volumes that
##     interpenetrate. Parts are classified: KIT = a part of the block kit's material (chamfered slabs, pillow segments of the pillars: style/candy_surface.gdshader with use_vertex_color);
##     BLOCK = any other part of the merged level meshes, tile floors and ground; CAGE = every part (welded component) of the arena cage, each its own assembly; DECO = everything else (launch / ride pads, goal arch, banners, markers, gates
##     and their faces, hazard looks, spinner parts, turntables, relief arrows ...). A DECO part against any other part, a KIT part against a BLOCK part and a CAGE part against another CAGE part (a beam through a pillar, a clamp in a band, in one instance or between instances) are examined (KIT x KIT and
##     BLOCK x BLOCK are the kit's / the level's own overlapping construction: C1 covers their coplanar faces). Two DECO parts of one assembly never count against each other (the same
##     `Hazard_*` / `Slot_*` / `Launcher_*` / marker node, else the same parent node): a door in its frame, a spinner's bars and hub. Test: component boxes overlapping by more than
##     `--overlap-eps` (5 cm, the planting tolerance: a base sunk a few cm into the floor so it never z-fights is intended) on every axis, then exact triangle/triangle crossing (an edge of one through a face of the other) whose depth (the smaller of: the vertex distances from the other's face plane both ways, and the thinnest side of the boxes' common part) exceeds `--overlap-eps`; or one part's box inside the other's with its first vertex inside the other closed solid. Touching or sitting on
##     (contact within `--overlap-eps`) is the intended contact and passes. Report: per class and the two node paths (a group, the baseline's unit) and the 40 deepest single pairs.
##  C5 DOUBLE RIMS (class `double_rim`, `--rim-budget`): obsolete since the candy kit (style/block_kit.gd) has no rim, chamfered slabs only: the pass looks for rim-coloured thin bars of a floor tone (BlockKit.FLOORS "rim" colours) and finds none. Kept inert.
##  Budgets. Defect findings (C1) and warning findings (C2, C3) are counted per level. `--baseline=<json of an earlier --out>`: a finding group (class + the two node paths
##  without indices) only counts for what exceeds its count in the baseline, so a tree is judged on NEW defects. Exit 1 when C1 > --budget or (--warn-budget >= 0 and C2+C3 > it).
##  Limits (not defects of the tool's rules): movers are linted at one clock only (`--clock=<s>`); a vertex shader that moves geometry is not applied; normals that straddle a
##  5 mm quantisation edge within 0.1 mm are bucketed both ways, others of a bucket edge are not.
const LevelWorld := preload("res://levels/level_world.gd")
const BlockKit := preload("res://style/block_kit.gd")
const BlockMesh := preload("res://style/block_mesh.gd")
const LobbySpace := preload("res://lobby_space.gd")
const LobbyDraw := preload("res://lobby_visuals.gd")
const LobbyEnvironment := preload("res://lobby_environment.gd")
const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const WalkInMarkers := preload("res://client/walk_in_markers.gd")

const PodiumRoom := preload("res://style/podium_room.gd")
const PODIUM_LEVEL := 98       ## the pseudo-level number of the podium room in reports
const LOBBY_LEVEL := 99        ## the pseudo-level number of the lobby yard in reports

const CELL := 2.0              ## m, the grid inside a plane bucket
const D_STEP := 0.02           ## m, the plane-distance bucket
const N_STEP := 0.005          ## the normal bucket
const BIG_CELLS := 64          ## a triangle covering more cells than this is tested against its whole bucket instead
const GAP_CELL := 4.0
const GAP_BIG := 60.0          ## a component longer than this is a support only, tested by scan
const FLAG_ALPHA := 1
const FLAG_DOUBLE := 2
const FLAG_KIT := 4             ## the block kit's own material (style/candy_surface.gdshader with use_vertex_color): chamfered slabs, pillars
const OVERLAP_CELL := 4.0
const AXES := ["x", "y", "z"]
const RIM_TOL := 0.08           ## C5: how near (RGB distance, sRGB 0..1) a vertex colour is to a rim colour of the kit's palettes (and nearer than to any other palette colour) to count as rim
const DECK_CELL := 2.0          ## C5: the grid of up-facing triangles the deck test looks the far side of a rim up in

var opt := {
	"levels": [25, 26, 27, 28, 29, 30], "eps": 0.002, "normal_dot": 0.9999, "min_area": 1.0e-4, "weld": 0.0005, "gap_min": 0.0001, "gap_max": 0.05, "tall": 1.0,
	"budget": 0, "warn_budget": -1, "gaps_multimesh": false, "gap_hazards": false, "scopes": ["level", "tiles", "cage", "world"], "gap_scopes": ["level", "tiles", "cage"],
	"overlap_eps": 0.05, "lift_gap": 0.012, "overlap_budget": -1, "overlap_scopes": ["level", "tiles", "cage"], "clock": 0.0, "top": 10, "keep": 400, "out": "", "baseline": "", "selftest": false,
	"rim_budget": 0, "rim_width": 0.6, "rim_gap": 3.0, "lobby": false, "podium": false, "dir": ""}

## What WalkInMarkers.build asks the game for: the floor under a point (the yard is flat).
class FloorAt extends RefCounted:
	func floor_at(point: Vector3) -> Vector3: return point

## ---- data ----

class Entry extends RefCounted: ## one MeshInstance3D / MultiMeshInstance3D
	var path := ""
	var scope := "level"
	var multi := false
	var hazard := false

class MeshData extends RefCounted: ## a mesh in its own space, triangles only
	var mesh: Mesh
	var v := PackedVector3Array()   ## 3 per triangle
	var surf := PackedInt32Array()  ## per triangle: the surface
	var comp := PackedInt32Array()  ## per triangle: its component in this mesh
	var weld := PackedInt32Array()  ## 3 per triangle: welded vertex ids
	var col := PackedColorArray()   ## per triangle: the vertex colour of its first vertex (transparent black when the mesh has none)
	var open := PackedByteArray()   ## per component: 1 when some welded edge is not shared by exactly two triangles (a quad, a glyph, a sheet: not a closed solid)
	var comps := 0

class Scene extends RefCounted: ## the triangles and components of one level, in level-local space
	var entries: Array = []
	var meshes: Array = []                                ## per component: its MeshData's component count (name suffix)
	var c_entry := PackedInt32Array()
	var c_sub := PackedInt32Array()                       ## MultiMesh element, -1 for a MeshInstance3D
	var c_local := PackedInt32Array()
	var c_many := PackedByteArray()                       ## 1 when its mesh has more than one component
	var c_kind := PackedByteArray()                       ## 0 block, 1 kit, 2 deco, 3 cage (_kind)
	var c_kit := PackedByteArray()                        ## 1 when it is drawn with the block kit's material
	var c_rim := PackedByteArray()                        ## 1 when a kit part's up-facing triangle wears a rim colour (C5)
	var c_open := PackedByteArray()                       ## 1 when it is not a closed solid
	var c_min := PackedVector3Array()
	var c_max := PackedVector3Array()
	var c_face_p := PackedFloat64Array()                  ## 6 per component (axis * 2 + (0: + face, 1: - face)): the plane coordinate, NAN none
	var c_face_lo := PackedVector2Array()
	var c_face_hi := PackedVector2Array()
	var tv := PackedVector3Array()                        ## 3 per triangle
	var tn := PackedVector3Array()                        ## front normal (clockwise winding), ZERO for a degenerate triangle
	var tcomp := PackedInt32Array()
	var tflags := PackedByteArray()
	var tmat := PackedInt32Array()                        ## per triangle: its material (an id, -1 none)
	var tweld := PackedInt32Array()                       ## 3 per triangle, local to the component's mesh
	var triangles := 0

var mesh_cache := {}            ## Mesh instance id -> MeshData
var flag_cache := {}            ## Material instance id -> flags
var material_ids := {}          ## Material instance id -> small id
var material_refs: Array = []   ## keeps the materials alive while their ids are in use
var stats := {}                 ## counters of the last analyze
var multimesh_readable := false ## the renderer keeps MultiMesh transforms (the offscreen / windowed renderers do, the dummy one of --headless drops them)

func _initialize() -> void:
	var timer := create_timer(1500.0)
	timer.timeout.connect(func() -> void:
		print("MESHLINT FAILED timed out")
		print("MESHLINT ok=false")
		quit(1))
	run.call_deferred()

func parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"): continue
		var key := a.trim_prefix("--").get_slice("=", 0)
		var value := a.get_slice("=", 1) if a.contains("=") else ""
		match key:
			"levels":
				var list: Array = []
				for part in value.split(",", false): list.append(int(part))
				opt.levels = list
			"eps", "overlap-eps", "lift-gap", "normal-dot", "min-area", "weld", "gap-min", "gap-max", "tall", "clock", "rim-width", "rim-gap": opt[key.replace("-", "_")] = float(value)
			"budget", "warn-budget", "overlap-budget", "rim-budget", "top", "keep": opt[key.replace("-", "_")] = int(value)
			"scopes", "gap-scopes": opt[key.replace("-", "_")] = Array(value.split(",", false))
			"out", "baseline", "dir": opt[key] = value
			"gaps-multimesh": opt.gaps_multimesh = true
			"gap-hazards": opt.gap_hazards = true
			"lobby": opt.lobby = true
			"podium": opt.podium = true
			"selftest": opt.selftest = true
			_: print("MESHLINT unknown argument ", a)

## Whether a transform written to a MultiMesh can be read back (not with the dummy renderer).
func _probe_multimesh() -> bool:
	var probe := MultiMesh.new()
	probe.transform_format = MultiMesh.TRANSFORM_3D
	probe.mesh = BoxMesh.new()
	probe.instance_count = 1
	probe.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(1.0, 2.0, 3.0)))
	return probe.get_instance_transform(0).origin.is_equal_approx(Vector3(1.0, 2.0, 3.0))

func run() -> void:
	parse_args()
	multimesh_readable = _probe_multimesh()
	if not multimesh_readable: print("MESHLINT NOTE the dummy renderer drops MultiMesh transforms: tile floors, cage pillars / beams / signs, skyline and clouds are NOT linted (run tools/mesh_lint.sh without --headless: the offscreen renderer keeps them)")
	if opt.selftest:
		var failed := selftest()
		print("MESHLINT selftest ok=", failed == 0)
		quit(0 if failed == 0 else 1)
		return
	var began := Time.get_ticks_msec()
	var world: Node3D = LevelWorld.new()
	if str(opt.dir) != "": world.level_dir = str(opt.dir)
	var holder: Node3D = null
	if opt.podium:
		holder = Node3D.new()
		root.add_child(holder)
		var room: Node3D = PodiumRoom.new()
		holder.add_child(room)
		room.build()
	elif opt.lobby:
		holder = Node3D.new()
		root.add_child(holder)
		holder.add_child(world)
	else:
		root.add_child(world)
	if not opt.podium:
		await world.build("local")
		if opt.lobby: _build_lobby(holder, world)
	print("MESHLINT built %d levels in %d ms" % [0 if opt.podium else world.level_count(), Time.get_ticks_msec() - began])
	var baseline := {}
	if str(opt.baseline) != "":
		var text := FileAccess.get_file_as_string(str(opt.baseline))
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary: baseline = parsed
		else: print("MESHLINT cannot read the baseline ", opt.baseline)
	var report := {"tool": "mesh_lint", "version": 1, "options": opt.duplicate(), "levels": {}}
	var over_defects := 0
	var over_warnings := 0
	var over_overlaps := 0
	var over_rims := 0
	var numbers: Array = [PODIUM_LEVEL] if opt.podium else ([LOBBY_LEVEL] if opt.lobby else opt.levels)
	for number: int in numbers:
		var scene_root: Node = world
		var origin := WalkInLobby.ORIGIN
		if opt.podium:
			scene_root = holder
			origin = PodiumRoom.ORIGIN
		elif opt.lobby:
			scene_root = holder
		else:
			var k := number - 1
			if k < 0 or k >= world.level_count():
				print("MESHLINT level %d: not in the tree" % number)
				continue
			world.set_active_level(k)
			world.set_clock(float(opt.clock))
			origin = world.level_origin(k)
		await process_frame
		await process_frame
		var started := Time.get_ticks_msec()
		var result := analyze([scene_root], scene_root, origin)
		result.level = number
		result.seconds = float(Time.get_ticks_msec() - started) / 1000.0
		var base_level: Dictionary = (baseline.get("levels", {}) as Dictionary).get(str(number), {})
		var new_defects := _new_findings(result.coplanar, base_level.get("coplanar", {}), baseline.is_empty())
		result.new_overlaps = _new_findings(result.overlap, base_level.get("overlap", {}), baseline.is_empty())
		over_overlaps += int(result.new_overlaps)
		over_rims += int(result.double_rim.total)
		var new_warnings := _new_findings(result.gap, base_level.get("gap", {}), baseline.is_empty()) + _new_findings(result.vertical, base_level.get("vertical", {}), baseline.is_empty())
		result.new_defects = new_defects
		result.new_warnings = new_warnings
		over_defects += new_defects
		over_warnings += new_warnings
		(report.levels as Dictionary)[str(number)] = result
		print_level(result)
	var failed_defects: bool = over_defects > int(opt.budget)
	var failed_warnings: bool = int(opt.warn_budget) >= 0 and over_warnings > int(opt.warn_budget)
	print("MESHLINT total defects=%d (budget %d) warnings=%d (budget %s) in %d ms" % [over_defects, opt.budget, over_warnings, str(opt.warn_budget) if int(opt.warn_budget) >= 0 else "none", Time.get_ticks_msec() - began])
	if str(opt.out) != "":
		var file := FileAccess.open(str(opt.out), FileAccess.WRITE)
		if file == null: print("MESHLINT cannot write ", opt.out)
		else:
			file.store_string(JSON.stringify(report, "  "))
			file.close()
			print("MESHLINT wrote ", opt.out)
	var failed_overlaps: bool = int(opt.overlap_budget) >= 0 and over_overlaps > int(opt.overlap_budget)
	print("MESHLINT total overlaps=%d (budget %s)" % [over_overlaps, str(opt.overlap_budget) if int(opt.overlap_budget) >= 0 else "none"])
	var failed_rims: bool = over_rims > int(opt.rim_budget)
	print("MESHLINT total double_rim=%d (budget %d)" % [over_rims, opt.rim_budget])
	var ok := not failed_defects and not failed_warnings and not failed_overlaps and not failed_rims
	print("MESHLINT ok=", ok)
	quit(0 if ok else 1)

## The lobby yard of a client, as tools/lobby_frames.gd builds it: the room with the client look, the world around it, the circles' markers and signs.
func _build_lobby(holder: Node3D, world: Node3D) -> void:
	LobbySpace.client_draw_factory = func() -> Dictionary: return {"visuals": LobbyDraw, "environment": LobbyEnvironment.new()}
	LobbySpace.ensure(holder, "local")
	world.set_active_level(-1)
	LobbySpace.sync(holder, "local", true)
	var markers := WalkInMarkers.new()
	holder.add_child(markers)
	markers.build(FloorAt.new())
	markers.set_shown(true)

## What exceeds the baseline: per finding group the count over the baseline's (all of it without a baseline).
func _new_findings(section: Dictionary, base: Dictionary, no_baseline: bool) -> int:
	if no_baseline: return int(section.total)
	var known := {}
	for g: Dictionary in base.get("groups", []): known[str(g.key)] = int(g.findings)
	var fresh := 0
	for g: Dictionary in section.groups: fresh += maxi(0, int(g.findings) - int(known.get(str(g.key), 0)))
	return fresh

func print_level(result: Dictionary) -> void:
	print("MESHLINT level %d: %d triangles, %d components, scopes %s, %.1f s; coplanar %d (%d triangle pairs), gaps %d, vertical %d, overlaps %d; new defects %d, new warnings %d" % [result.level,
		result.triangles, result.components, str(result.scopes), result.seconds, result.coplanar.total, result.coplanar.pairs, result.gap.total, result.vertical.total, result.overlap.total, result.new_defects, result.new_warnings])
	if not (result.skipped_multimesh as Array).is_empty():
		var instances := 0
		for skipped: Dictionary in result.skipped_multimesh: instances += int(skipped.instances)
		print("MESHLINT   NOT LINTED: %d MultiMesh nodes (%d instances) the renderer cannot read back" % [result.skipped_multimesh.size(), instances])
	for section_name: String in ["coplanar", "gap", "vertical", "overlap", "double_rim"]:
		var section: Dictionary = result[section_name]
		var shown := 0
		for g: Dictionary in section.groups:
			if shown >= int(opt.top): break
			shown += 1
			var pair_text: String = str(g.a) if g.a == g.b else "%s  x  %s" % [g.a, g.b]
			var plane_text := ""
			if (g.plane as Array).size() == 4: plane_text = " plane n=(%.2f, %.2f, %.2f) d=%.3f" % [g.plane[0], g.plane[1], g.plane[2], g.plane[3]]
			print("MESHLINT   %s %s: %s  (%d findings, %s) near %s%s" % [section_name, g.cls, pair_text, g.findings, g.detail, _fmt(g.loc), plane_text])

func _fmt(p: Array) -> String:
	return "(%.2f, %.2f, %.2f)" % [p[0], p[1], p[2]]

## ---- collecting ----

## The lint of the visible meshes under `roots` (paths relative to `base`, positions relative to `origin`). Returns the report dictionary of one level.
func analyze(roots: Array, base: Node, origin: Vector3) -> Dictionary:
	var scene := Scene.new()
	var to_local := Transform3D(Basis.IDENTITY, -origin)
	stats = {"pairs_tested": 0, "skipped": []}
	for node: Node in roots: _collect(node, base, to_local, scene)
	var wanted: Array = opt.scopes
	var result := {"triangles": scene.triangles, "components": scene.c_entry.size(), "scopes": _scope_counts(scene), "skipped_multimesh": stats.skipped}
	result.coplanar = _coplanar(scene, wanted)
	scene.c_kind.resize(scene.c_entry.size())
	for c in scene.c_entry.size(): scene.c_kind[c] = _kind(scene, c)
	var gaps: Array = []
	var verticals: Array = []
	_gap_pass(scene, gaps, verticals)
	var seams: Array = []
	var real_gaps: Array = []
	for g: Dictionary in gaps: (real_gaps if str(g.cls) == "gap" else seams).append(g)
	result.gap = _section(scene, real_gaps)
	result.gap_seam = _section(scene, seams) # the intended gaps: gap_seam, gap_decal, gap_lift (the class of each group)
	var histogram := {}
	for g: Dictionary in real_gaps:
		var key := "%d mm" % roundi(float(g.extra) * 1000.0)
		histogram[key] = int(histogram.get(key, 0)) + 1
	result.gap_histogram = histogram
	result.vertical = _section(scene, verticals)
	var overlaps: Array = []
	_overlap_pass(scene, overlaps)
	result.overlap = _section(scene, overlaps)
	overlaps.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x.extra) > float(y.extra))
	var top_pairs: Array = []
	for f: Dictionary in overlaps.slice(0, 40):
		top_pairs.append({"cls": f.cls, "a": _comp_name(scene, int(f.ca)), "b": _comp_name(scene, int(f.cb)), "depth": snappedf(float(f.extra), 0.0001), "loc": _vec(f.loc), "hits": f.pairs})
	result.overlap.top_pairs = top_pairs
	var rims: Array = []
	_double_rim_pass(scene, rims)
	result.double_rim = _section(scene, rims)
	return result

func _scope_counts(scene: Scene) -> Dictionary:
	var counts := {}
	for c in scene.c_entry.size():
		var scope: String = (scene.entries[scene.c_entry[c]] as Entry).scope
		counts[scope] = int(counts.get(scope, 0)) + 1
	return counts

func _collect(node: Node, base: Node, to_local: Transform3D, scene: Scene) -> void:
	if node is Node3D and not (node as Node3D).visible: return
	if node.name == &"CollisionLookVoid": return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null and mi.is_visible_in_tree() and mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			var flags := PackedInt32Array()
			var mats := PackedInt32Array()
			for s in mi.mesh.get_surface_count():
				var material: Material = mi.material_override if mi.material_override != null else mi.get_active_material(s)
				flags.append(_material_flags(material))
				mats.append(_material_id(material))
			var entry := _entry(node, base, false)
			scene.entries.append(entry)
			_add_instance(scene, scene.entries.size() - 1, _mesh_data(mi.mesh), to_local * mi.global_transform, -1, flags, mats)
	elif node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		var mm := mmi.multimesh
		if mm != null and mm.mesh != null and mmi.is_visible_in_tree() and mm.transform_format == MultiMesh.TRANSFORM_3D and not multimesh_readable:
			(stats.skipped as Array).append({"path": _entry(node, base, true).path, "instances": mm.instance_count})
		elif mm != null and mm.mesh != null and mmi.is_visible_in_tree() and mm.transform_format == MultiMesh.TRANSFORM_3D:
			var flags := PackedInt32Array()
			var mats := PackedInt32Array()
			for s in mm.mesh.get_surface_count():
				var material: Material = mmi.material_override if mmi.material_override != null else mm.mesh.surface_get_material(s)
				flags.append(_material_flags(material))
				mats.append(_material_id(material))
			var entry := _entry(node, base, true)
			scene.entries.append(entry)
			var data := _mesh_data(mm.mesh)
			var shown := mm.instance_count if mm.visible_instance_count < 0 else mini(mm.visible_instance_count, mm.instance_count)
			var node_xf := to_local * mmi.global_transform
			for i in shown:
				var xf := node_xf * mm.get_instance_transform(i)
				if xf.basis.determinant() < 1.0e-6: continue # a gone tile is scaled to nothing
				_add_instance(scene, scene.entries.size() - 1, data, xf, i, flags, mats)
	for child in node.get_children(): _collect(child, base, to_local, scene)

func _entry(node: Node, base: Node, multi: bool) -> Entry:
	var entry := Entry.new()
	var raw := str(base.get_path_to(node))
	var rx := RegEx.new()
	rx.compile("@[A-Za-z0-9_]+@\\d+")
	entry.path = rx.sub(raw, "@", true)
	entry.multi = multi
	var parts := entry.path.split("/", false)
	entry.hazard = false
	for part in parts:
		if part.begins_with("Hazard_"): entry.hazard = true
	if "Cage" in parts: entry.scope = "cage"
	elif str(node.name).begins_with("StageFloor") or str(node.name).begins_with("StageGround"): entry.scope = "tiles"
	elif not parts.is_empty() and (parts[0].begins_with("ArenaWorld") or parts[0].begins_with("RaceWorld") or parts[0] == "NearSky" or "City" in parts or "SkyThings" in parts or "NearSky" in parts): entry.scope = "world"
	elif _in_lobby_world(parts) or "Skyline" in parts: entry.scope = "world"
	elif parts.size() >= 2 and (parts[1].begins_with("ArenaWorld") or parts[1].begins_with("RaceWorld")): entry.scope = "world"
	else: entry.scope = "level"
	return entry

func _in_lobby_world(parts: PackedStringArray) -> bool:
	for part in parts:
		if part.begins_with("LobbyWorld"): return true
	return false

func _material_id(mat: Material) -> int:
	if mat == null: return -1
	var id := mat.get_instance_id()
	if not material_ids.has(id):
		material_ids[id] = material_ids.size()
		material_refs.append(mat)
	return material_ids[id]

func _material_flags(mat: Material) -> int:
	if mat == null: return 0
	var id := mat.get_instance_id()
	if flag_cache.has(id): return int(flag_cache[id])
	var flags := 0
	if mat is BaseMaterial3D:
		var std := mat as BaseMaterial3D
		if std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: flags |= FLAG_ALPHA
		if std.cull_mode == BaseMaterial3D.CULL_DISABLED: flags |= FLAG_DOUBLE
	elif mat is ShaderMaterial:
		var shader := (mat as ShaderMaterial).shader
		if shader != null:
			var code := shader.code
			if code.contains("blend_add") or code.contains("blend_sub") or code.contains("blend_mul") or code.contains("premul_alpha"): flags |= FLAG_ALPHA
			var rx := RegEx.new()
			rx.compile("\\bALPHA\\s*=[^=]")
			if rx.search(code) != null: flags |= FLAG_ALPHA
			if code.contains("cull_disabled"): flags |= FLAG_DOUBLE
			if shader.resource_path.ends_with("candy_surface.gdshader") and (mat as ShaderMaterial).get_shader_parameter("use_vertex_color") == true: flags |= FLAG_KIT
	flag_cache[id] = flags
	return flags

func _mesh_data(mesh: Mesh) -> MeshData:
	var id := mesh.get_instance_id()
	if mesh_cache.has(id): return mesh_cache[id]
	var data := MeshData.new()
	data.mesh = mesh
	var weld_ids := {}
	var quantum := float(opt.weld)
	var parent := PackedInt32Array()
	for s in mesh.get_surface_count():
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES: continue # the built-in primitives are triangles
		var arrays := mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		if vertices.is_empty(): continue
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			indices.resize(vertices.size())
			for i in vertices.size(): indices[i] = i
		var vertex_weld := PackedInt32Array()
		vertex_weld.resize(vertices.size())
		for i in vertices.size():
			var p := vertices[i]
			var key := Vector3i(roundi(p.x / quantum), roundi(p.y / quantum), roundi(p.z / quantum))
			if not weld_ids.has(key):
				weld_ids[key] = parent.size()
				parent.append(parent.size())
			vertex_weld[i] = weld_ids[key]
		for t in indices.size() / 3:
			var ia := indices[3 * t]
			var ib := indices[3 * t + 1]
			var ic := indices[3 * t + 2]
			data.v.append(vertices[ia])
			data.v.append(vertices[ib])
			data.v.append(vertices[ic])
			data.surf.append(s)
			data.col.append(colors[ia] if colors.size() == vertices.size() else Color(0.0, 0.0, 0.0, 0.0))
			data.weld.append(vertex_weld[ia])
			data.weld.append(vertex_weld[ib])
			data.weld.append(vertex_weld[ic])
			_union(parent, vertex_weld[ia], vertex_weld[ib])
			_union(parent, vertex_weld[ia], vertex_weld[ic])
	var dense := {}
	data.comp.resize(data.surf.size())
	for t in data.surf.size():
		var r := _find(parent, data.weld[3 * t])
		if not dense.has(r): dense[r] = dense.size()
		data.comp[t] = dense[r]
	data.comps = dense.size()
	data.open.resize(data.comps)
	var edges := {}
	for t in data.surf.size():
		for e in 3:
			var wa := data.weld[3 * t + e]
			var wb := data.weld[3 * t + (e + 1) % 3]
			var key := (mini(wa, wb) << 32) | maxi(wa, wb)
			edges[key] = int(edges.get(key, 0)) + 1
	for t in data.surf.size():
		for e in 3:
			var wa := data.weld[3 * t + e]
			var wb := data.weld[3 * t + (e + 1) % 3]
			if int(edges[(mini(wa, wb) << 32) | maxi(wa, wb)]) != 2: data.open[data.comp[t]] = 1
	mesh_cache[id] = data
	return data

static func _find(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i

static func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb: parent[ra] = rb

## Adds the triangles of `data` placed by `xf` (level-local) to the scene: world triangles, normals, the components' boxes and their flat axis-aligned faces.
func _add_instance(scene: Scene, entry: int, data: MeshData, xf: Transform3D, sub: int, surface_flags: PackedInt32Array, surface_mats: PackedInt32Array) -> void:
	var count := data.surf.size()
	if count == 0: return
	var wv: PackedVector3Array = xf * data.v
	var comp_base := scene.c_entry.size()
	for c in data.comps:
		scene.c_entry.append(entry)
		scene.c_sub.append(sub)
		scene.c_local.append(c)
		scene.c_many.append(1 if data.comps > 1 else 0)
		scene.c_open.append(data.open[c])
		scene.c_kit.append(0)
		scene.c_rim.append(0)
		scene.c_min.append(Vector3(INF, INF, INF))
		scene.c_max.append(Vector3(-INF, -INF, -INF))
		for f in 6:
			scene.c_face_p.append(NAN)
			scene.c_face_lo.append(Vector2.ZERO)
			scene.c_face_hi.append(Vector2.ZERO)
	var normals := PackedVector3Array()
	normals.resize(count)
	var flags := PackedByteArray()
	flags.resize(count)
	var mats := PackedInt32Array()
	mats.resize(count)
	var tol := float(opt.eps)
	for t in count:
		var a := wv[3 * t]
		var b := wv[3 * t + 1]
		var c := wv[3 * t + 2]
		var ci := comp_base + data.comp[t]
		var cross := (b - a).cross(c - a)
		var length := cross.length()
		var nrm := Vector3.ZERO
		if length > 1.0e-9: nrm = -cross / length
		normals[t] = nrm
		flags[t] = surface_flags[data.surf[t]] if data.surf[t] < surface_flags.size() else 0
		if flags[t] & FLAG_KIT != 0:
			scene.c_kit[ci] = 1
			if nrm.y > 0.999 and _rim_like(data.col[t]): scene.c_rim[ci] = 1
		mats[t] = surface_mats[data.surf[t]] if data.surf[t] < surface_mats.size() else -1
		var lo: Vector3 = scene.c_min[ci]
		var hi: Vector3 = scene.c_max[ci]
		scene.c_min[ci] = lo.min(a.min(b.min(c)))
		scene.c_max[ci] = hi.max(a.max(b.max(c)))
		if length <= 1.0e-9: continue
		for axis in 3:
			if absf(nrm[axis]) < 0.9999: continue
			var positive := nrm[axis] > 0.0
			var slot := ci * 6 + axis * 2 + (0 if positive else 1)
			var p := (a[axis] + b[axis] + c[axis]) / 3.0
			var u := (axis + 1) % 3
			var w := (axis + 2) % 3
			var tri_lo := Vector2(minf(a[u], minf(b[u], c[u])), minf(a[w], minf(b[w], c[w])))
			var tri_hi := Vector2(maxf(a[u], maxf(b[u], c[u])), maxf(a[w], maxf(b[w], c[w])))
			var have := scene.c_face_p[slot]
			if is_nan(have) or (positive and p > have + tol) or (not positive and p < have - tol):
				scene.c_face_p[slot] = p
				scene.c_face_lo[slot] = tri_lo
				scene.c_face_hi[slot] = tri_hi
			elif absf(p - have) <= tol:
				scene.c_face_lo[slot] = scene.c_face_lo[slot].min(tri_lo)
				scene.c_face_hi[slot] = scene.c_face_hi[slot].max(tri_hi)
			break
	scene.tv.append_array(wv)
	scene.tn.append_array(normals)
	scene.tflags.append_array(flags)
	scene.tmat.append_array(mats)
	scene.tweld.append_array(data.weld)
	for t in count: scene.tcomp.append(comp_base + data.comp[t])
	scene.triangles += count

## ---- C1: coplanar ----

func _coplanar(scene: Scene, wanted: Array) -> Dictionary:
	var eps: float = opt.eps
	var margin := eps + 1.0e-4
	var buckets := {}
	for t in scene.triangles:
		var nrm: Vector3 = scene.tn[t]
		if nrm == Vector3.ZERO: continue
		var entry: Entry = scene.entries[scene.c_entry[scene.tcomp[t]]]
		if not (entry.scope in wanted): continue
		var sign := 1.0
		for axis in 3:
			if absf(nrm[axis]) > 1.0e-3:
				if nrm[axis] < 0.0: sign = -1.0
				break
		var cn := nrm * sign
		var d := cn.dot(scene.tv[3 * t])
		var qd := floori(d / D_STEP)
		var frac := d - qd * D_STEP
		var ds: Array = [qd]
		if frac < margin: ds.append(qd - 1)
		if D_STEP - frac < margin: ds.append(qd + 1)
		var xs := _normal_options(cn.x)
		var ys := _normal_options(cn.y)
		var zs := _normal_options(cn.z)
		for qx: int in xs:
			for qy: int in ys:
				for qz: int in zs:
					for qdd: int in ds:
						var key := ((qx + 256) << 46) | ((qy + 256) << 37) | ((qz + 256) << 28) | ((qdd + 134217728) & 0xFFFFFFF)
						if buckets.has(key): (buckets[key] as Array).append(t)
						else: buckets[key] = [t]
	var findings := {}
	var seen := {}
	for key in buckets:
		var ids: Array = buckets[key]
		if ids.size() > 1: _scan_bucket(scene, ids, findings, seen)
	var raw: Array = []
	var pair_total := 0
	for f in findings.values():
		var finding: Dictionary = f
		pair_total += int(finding.pairs)
		finding.loc = (finding.pos as Vector3) / maxf(float(finding.area), 1.0e-9)
		raw.append(finding)
	var section := _section(scene, raw)
	section.pairs = pair_total
	return section

func _normal_options(c: float) -> Array:
	var q := c / N_STEP
	var r := roundi(q)
	var options: Array = [r]
	var edge := absf(q - (r + 0.5)) # distance to the upper edge, in buckets
	var edge_low := absf(q - (r - 0.5))
	var near := 1.0e-4 / N_STEP
	if edge < near: options.append(r + 1)
	elif edge_low < near: options.append(r - 1)
	return options

func _scan_bucket(scene: Scene, ids: Array, findings: Dictionary, seen: Dictionary) -> void:
	var n0: Vector3 = scene.tn[ids[0]]
	var axis := 0
	if absf(n0.y) > absf(n0[axis]): axis = 1
	if absf(n0.z) > absf(n0[axis]): axis = 2
	var u := (axis + 1) % 3
	var w := (axis + 2) % 3
	var size := ids.size()
	var mins := PackedVector2Array()
	var maxs := PackedVector2Array()
	mins.resize(size)
	maxs.resize(size)
	var grid := {}
	var big: Array = []
	for i in size:
		var t: int = ids[i]
		var a := scene.tv[3 * t]
		var b := scene.tv[3 * t + 1]
		var c := scene.tv[3 * t + 2]
		var lo := Vector2(minf(a[u], minf(b[u], c[u])), minf(a[w], minf(b[w], c[w])))
		var hi := Vector2(maxf(a[u], maxf(b[u], c[u])), maxf(a[w], maxf(b[w], c[w])))
		mins[i] = lo
		maxs[i] = hi
		var x0 := floori(lo.x / CELL)
		var x1 := floori(hi.x / CELL)
		var y0 := floori(lo.y / CELL)
		var y1 := floori(hi.y / CELL)
		if (x1 - x0 + 1) * (y1 - y0 + 1) > BIG_CELLS:
			big.append(i)
			continue
		for cx in range(x0, x1 + 1):
			for cy in range(y0, y1 + 1):
				var cell := Vector2i(cx, cy)
				if grid.has(cell): (grid[cell] as Array).append(i)
				else: grid[cell] = [i]
	for cell: Vector2i in grid:
		var list: Array = grid[cell]
		for ai in list.size():
			var i: int = list[ai]
			for bi in range(ai + 1, list.size()):
				var j: int = list[bi]
				var lo := Vector2(maxf(mins[i].x, mins[j].x), maxf(mins[i].y, mins[j].y))
				if floori(lo.x / CELL) != cell.x or floori(lo.y / CELL) != cell.y: continue # tested in the cell that holds the overlap's corner
				if lo.x >= minf(maxs[i].x, maxs[j].x) or lo.y >= minf(maxs[i].y, maxs[j].y): continue
				_pair(scene, ids[i], ids[j], findings, seen)
	for bi in big.size():
		var i: int = big[bi]
		for j in size:
			if j == i or (j in big and j < i): continue
			if mins[i].x >= maxs[j].x or mins[j].x >= maxs[i].x or mins[i].y >= maxs[j].y or mins[j].y >= maxs[i].y: continue
			_pair(scene, ids[i], ids[j], findings, seen)

func _pair(scene: Scene, a: int, b: int, findings: Dictionary, seen: Dictionary) -> void:
	var pair_key := (a * scene.triangles + b) if a < b else (b * scene.triangles + a)
	if seen.has(pair_key): return
	stats.pairs_tested += 1
	var na := scene.tn[a]
	var nb := scene.tn[b]
	var dot := na.dot(nb)
	if absf(dot) < float(opt.normal_dot): return
	var eps: float = opt.eps
	var pa := scene.tv[3 * a]
	var pb := scene.tv[3 * b]
	for k in 3:
		if absf(na.dot(scene.tv[3 * b + k] - pa)) > eps: return
		if absf(nb.dot(scene.tv[3 * a + k] - pb)) > eps: return
	var ca := scene.tcomp[a]
	var cb := scene.tcomp[b]
	if ca == cb:
		for i in 3:
			for j in 3:
				if scene.tweld[3 * a + i] == scene.tweld[3 * b + j]: return # adjacent in the same mesh
	var area := _overlap_area(scene, a, b, na)
	if area < float(opt.min_area): return
	var fa := int(scene.tflags[a])
	var fb := int(scene.tflags[b])
	var cls := "zfight"
	if dot > 0.0:
		if (fa | fb) & FLAG_ALPHA != 0: cls = "decal"
		elif ca == cb: cls = "zfight_self"
	else:
		# back to back: two closed solids touching face to face hide each other's face; only open sheets drawn two-sided show both
		if (fa | fb) & FLAG_DOUBLE == 0 or (scene.c_open[ca] == 0 and scene.c_open[cb] == 0): return
		cls = "zfight_back"
	seen[pair_key] = true
	var low := mini(ca, cb)
	var high := maxi(ca, cb)
	var key := "%d|%d|%s" % [low, high, cls]
	var centre := (scene.tv[3 * a] + scene.tv[3 * a + 1] + scene.tv[3 * a + 2]) / 3.0
	if not findings.has(key):
		findings[key] = {"same": true, "cls": cls, "ca": low, "cb": high, "pairs": 0, "area": 0.0, "pos": Vector3.ZERO, "plane": [snappedf(na.x, 0.0001), snappedf(na.y, 0.0001), snappedf(na.z, 0.0001), snappedf(na.dot(pa), 0.0001)]}
	var finding: Dictionary = findings[key]
	finding.pairs = int(finding.pairs) + 1
	if scene.tmat[a] < 0 or scene.tmat[a] != scene.tmat[b]: finding.same = false
	finding.area = float(finding.area) + area
	finding.pos = (finding.pos as Vector3) + centre * area

func _overlap_area(scene: Scene, a: int, b: int, normal: Vector3) -> float:
	var axis := 0
	if absf(normal.y) > absf(normal[axis]): axis = 1
	if absf(normal.z) > absf(normal[axis]): axis = 2
	var u := (axis + 1) % 3
	var w := (axis + 2) % 3
	var poly: Array[Vector2] = []
	for k in 3:
		var p := scene.tv[3 * a + k]
		poly.append(Vector2(p[u], p[w]))
	var clip: Array[Vector2] = []
	for k in 3:
		var p := scene.tv[3 * b + k]
		clip.append(Vector2(p[u], p[w]))
	if (clip[1] - clip[0]).cross(clip[2] - clip[0]) < 0.0:
		var swap := clip[1]
		clip[1] = clip[2]
		clip[2] = swap
	for e in 3:
		if poly.is_empty(): return 0.0
		var c0 := clip[e]
		var c1 := clip[(e + 1) % 3]
		var edge := c1 - c0
		var out: Array[Vector2] = []
		var previous := poly[poly.size() - 1]
		var previous_side := edge.cross(previous - c0)
		for current in poly:
			var side := edge.cross(current - c0)
			if side >= 0.0:
				if previous_side < 0.0: out.append(previous + (current - previous) * (previous_side / (previous_side - side)))
				out.append(current)
			elif previous_side >= 0.0:
				out.append(previous + (current - previous) * (previous_side / (previous_side - side)))
			previous = current
			previous_side = side
		poly = out
	var twice := 0.0
	for i in poly.size(): twice += poly[i].cross(poly[(i + 1) % poly.size()])
	return absf(twice) * 0.5 / maxf(absf(normal[axis]), 1.0e-6)

## ---- C2 and C3: gaps and vertical connectivity ----

func _gap_pass(scene: Scene, gaps: Array, verticals: Array) -> void:
	var count := scene.c_entry.size()
	var gap_max: float = opt.gap_max
	var gap_min: float = opt.gap_min
	var examined: Array = []
	var gap_scopes: Array = opt.gap_scopes
	for c in count:
		var entry: Entry = scene.entries[scene.c_entry[c]]
		if not (entry.scope in gap_scopes): continue
		if entry.hazard and not opt.gap_hazards: continue
		if (scene.c_min[c] as Vector3).x == INF: continue
		examined.append(c)
	# C2: a grid on the boxes grown by the largest gap; a pair is tested in the cell that holds the corner of its boxes' intersection
	var grid := {}
	var long_ones: Array = []
	for c: int in examined:
		var lo: Vector3 = scene.c_min[c] - Vector3.ONE * gap_max
		var hi: Vector3 = scene.c_max[c] + Vector3.ONE * gap_max
		var size := hi - lo
		if maxf(size.x, maxf(size.y, size.z)) > GAP_BIG:
			long_ones.append(c)
			continue
		for cx in range(floori(lo.x / GAP_CELL), floori(hi.x / GAP_CELL) + 1):
			for cy in range(floori(lo.y / GAP_CELL), floori(hi.y / GAP_CELL) + 1):
				for cz in range(floori(lo.z / GAP_CELL), floori(hi.z / GAP_CELL) + 1):
					var cell := Vector3i(cx, cy, cz)
					if grid.has(cell): (grid[cell] as Array).append(c)
					else: grid[cell] = [c]
	var found := {}
	for cell: Vector3i in grid:
		var list: Array = grid[cell]
		for ai in list.size():
			for bi in range(ai + 1, list.size()):
				var a: int = list[ai]
				var b: int = list[bi]
				var corner := (scene.c_min[a] as Vector3).max(scene.c_min[b]) - Vector3.ONE * gap_max
				if Vector3i(floori(corner.x / GAP_CELL), floori(corner.y / GAP_CELL), floori(corner.z / GAP_CELL)) != cell: continue
				_gap_pair(scene, a, b, gap_min, gap_max, found)
	for a: int in long_ones:
		for b: int in examined:
			if b == a or (b in long_ones and b < a): continue
			_gap_pair(scene, a, b, gap_min, gap_max, found)
	gaps.append_array(found.values())
	# C3: vertical-ish components, every component is a possible support
	var tall: float = opt.tall
	var eps: float = opt.eps
	for c: int in examined:
		var lo: Vector3 = scene.c_min[c]
		var hi: Vector3 = scene.c_max[c]
		var height := hi.y - lo.y
		if height < tall or height < 0.5 * maxf(hi.x - lo.x, hi.z - lo.z) or minf(hi.x - lo.x, hi.z - lo.z) < 0.02: continue # a flat sign or a sheet is not a support
		var bottom_touch := false
		var top_touch := false
		var below := INF
		for s in count:
			if s == c: continue
			var slo: Vector3 = scene.c_min[s]
			var shi: Vector3 = scene.c_max[s]
			if slo.x == INF: continue
			var ox := minf(hi.x, shi.x) - maxf(lo.x, slo.x)
			var oz := minf(hi.z, shi.z) - maxf(lo.z, slo.z)
			if ox <= 0.0 or oz <= 0.0 or ox * oz < 1.0e-4: continue
			if slo.y - eps <= lo.y and lo.y <= shi.y + eps: bottom_touch = true
			elif shi.y < lo.y - eps: below = minf(below, lo.y - shi.y)
			if slo.y - eps <= hi.y and hi.y <= shi.y + eps: top_touch = true
		if bottom_touch: continue
		var cls := "bottom_gap" if below <= gap_max else ("bottom_free" if top_touch else "floating")
		verticals.append({"cls": cls, "ca": c, "cb": c, "pairs": 1, "area": 0.0, "loc": Vector3((lo.x + hi.x) * 0.5, lo.y, (lo.z + hi.z) * 0.5), "extra": below})

func _gap_pair(scene: Scene, a: int, b: int, gap_min: float, gap_max: float, found: Dictionary) -> void:
	var ea: Entry = scene.entries[scene.c_entry[a]]
	if scene.c_entry[a] == scene.c_entry[b] and ea.multi and ea.scope != "cage" and not opt.gaps_multimesh: return # a tile layer's grooves are the design; the cage's parts are compared
	for axis in 3:
		for side in 2:
			var slot_a := a * 6 + axis * 2 + side
			var slot_b := b * 6 + axis * 2 + (1 - side)
			var pa: float = scene.c_face_p[slot_a]
			var pb: float = scene.c_face_p[slot_b]
			if is_nan(pa) or is_nan(pb): continue
			var distance := (pb - pa) if side == 0 else (pa - pb)
			if distance < gap_min or distance > gap_max: continue
			var lo := (scene.c_face_lo[slot_a] as Vector2).max(scene.c_face_lo[slot_b])
			var hi := (scene.c_face_hi[slot_a] as Vector2).min(scene.c_face_hi[slot_b])
			if hi.x - lo.x < 0.01 or hi.y - lo.y < 0.01: continue
			var u := (axis + 1) % 3
			var w := (axis + 2) % 3
			var loc := Vector3.ZERO
			loc[axis] = (pa + pb) * 0.5
			loc[u] = (lo.x + hi.x) * 0.5
			loc[w] = (lo.y + hi.y) * 0.5
			var key := "%d|%d|%d" % [mini(a, b), maxi(a, b), axis]
			if found.has(key) and float((found[key] as Dictionary).extra) <= distance: continue
			var gap_class := "gap"
			if scene.c_kind[a] == 1 and scene.c_kind[b] == 1: gap_class = "gap_seam"
			elif minf(minf(scene.c_max[a].x - scene.c_min[a].x, scene.c_max[a].y - scene.c_min[a].y), scene.c_max[a].z - scene.c_min[a].z) < 0.02 or minf(minf(scene.c_max[b].x - scene.c_min[b].x, scene.c_max[b].y - scene.c_min[b].y), scene.c_max[b].z - scene.c_min[b].z) < 0.02: gap_class = "gap_decal"
			elif axis == 1 and distance <= float(opt.lift_gap) and scene.c_kind[a] != 2 and scene.c_kind[b] != 2: gap_class = "gap_lift"
			found[key] = {"cls": gap_class, "ca": mini(a, b), "cb": maxi(a, b), "pairs": 1, "area": (hi.x - lo.x) * (hi.y - lo.y), "loc": loc, "extra": distance, "axis": axis}

## ---- C4: overlaps ----

## 0 = BLOCK, 1 = KIT, 2 = DECO, 3 = CAGE (every part of the arena cage is its own assembly)
func _kind(scene: Scene, c: int) -> int:
	var entry: Entry = scene.entries[scene.c_entry[c]]
	if scene.c_kit[c] == 1: return 1
	var parts := entry.path.split("/", false)
	var leaf: String = parts[parts.size() - 1]
	if entry.scope == "cage": return 3
	if entry.scope == "tiles": return 0
	if leaf in ["LevelLook", "LevelCeilings"] and parts.size() <= 2: return 0
	return 2

## The assembly a part belongs to: parts of one assembly may touch and cross.
func _assembly(entry: Entry) -> String:
	var parts := entry.path.split("/", false)
	for i in parts.size():
		var seg: String = parts[i]
		if i > 0 and (seg.begins_with("Hazard_") or seg.begins_with("Slot_") or seg.begins_with("Launcher_") or seg.begins_with("CollisionLookMarkers") or seg.begins_with("CollisionLookPad")): return "/".join(parts.slice(0, i + 1))
	return "/".join(parts.slice(0, parts.size() - 1))

func _overlap_pass(scene: Scene, out: Array) -> void:
	var eps: float = opt.overlap_eps
	var count := scene.c_entry.size()
	var scopes: Array = opt.overlap_scopes
	var kinds := PackedByteArray()
	kinds.resize(count)
	var cands: Array = []
	var assembly: Array = []
	assembly.resize(count)
	var by_entry := {}
	for c in count:
		var entry: Entry = scene.entries[scene.c_entry[c]]
		if not (entry.scope in scopes) or (scene.c_min[c] as Vector3).x == INF: continue
		kinds[c] = _kind(scene, c)
		var ei := scene.c_entry[c]
		if not by_entry.has(ei): by_entry[ei] = _assembly(entry)
		assembly[c] = by_entry[ei]
		cands.append(c)
	var tris := {} # component -> its triangles, built for the parts that reach a pair test
	var grid := {}
	var long_ones: Array = []
	for c: int in cands:
		var lo: Vector3 = scene.c_min[c]
		var hi: Vector3 = scene.c_max[c]
		if maxf(hi.x - lo.x, maxf(hi.y - lo.y, hi.z - lo.z)) > GAP_BIG:
			long_ones.append(c)
			continue
		for cx in range(floori(lo.x / OVERLAP_CELL), floori(hi.x / OVERLAP_CELL) + 1):
			for cy in range(floori(lo.y / OVERLAP_CELL), floori(hi.y / OVERLAP_CELL) + 1):
				for cz in range(floori(lo.z / OVERLAP_CELL), floori(hi.z / OVERLAP_CELL) + 1):
					var cell := Vector3i(cx, cy, cz)
					if grid.has(cell): (grid[cell] as Array).append(c)
					else: grid[cell] = [c]
	var pairs := {}
	for cell: Vector3i in grid:
		var list: Array = grid[cell]
		for ai in list.size():
			for bi in range(ai + 1, list.size()):
				var a: int = list[ai]
				var b: int = list[bi]
				var corner := (scene.c_min[a] as Vector3).max(scene.c_min[b])
				if Vector3i(floori(corner.x / OVERLAP_CELL), floori(corner.y / OVERLAP_CELL), floori(corner.z / OVERLAP_CELL)) != cell: continue
				pairs[a * count + b if a < b else b * count + a] = true
	for a: int in long_ones:
		for b: int in cands:
			if b != a and not (b in long_ones and b < a): pairs[a * count + b if a < b else b * count + a] = true
	for key in pairs:
		var a: int = key / count
		var b: int = key % count
		var ka := kinds[a]
		var kb := kinds[b]
		var cls := ""
		if ka == 3 and kb == 3: cls = "overlap_cage"
		elif ka == 3 or kb == 3: continue # a cage part against the level: not this rule
		elif ka == 2 and kb == 2: cls = "overlap_deco_deco"
		elif ka == 2 or kb == 2: cls = "overlap_deco_kit" if (ka == 1 or kb == 1) else "overlap_deco_block"
		elif ka != kb: cls = "overlap_kit_block"
		else: continue
		if ka == 2 and kb == 2 and assembly[a] == assembly[b]: continue
		if scene.c_entry[a] == scene.c_entry[b] and (scene.entries[scene.c_entry[a]] as Entry).multi and ka != 3: continue # a tile floor's neighbours; the cage's instances are compared
		var lo := (scene.c_min[a] as Vector3).max(scene.c_min[b])
		var hi := (scene.c_max[a] as Vector3).min(scene.c_max[b])
		if hi.x - lo.x <= eps or hi.y - lo.y <= eps or hi.z - lo.z <= eps: continue # the common box is thinner than the planting tolerance on some axis: sitting on / touching
		var hit := _cross(scene, a, b, lo, hi, eps, tris)
		if hit.is_empty(): continue
		out.append({"cls": cls, "ca": mini(a, b), "cb": maxi(a, b), "pairs": hit.hits, "area": hit.depth, "loc": hit.at, "extra": hit.depth})

func _comp_tris(scene: Scene, c: int, tris: Dictionary) -> Array:
	if tris.is_empty():
		for t in scene.triangles:
			var ci := scene.tcomp[t]
			if not tris.has(ci): tris[ci] = []
			(tris[ci] as Array).append(t)
	return tris.get(c, [])

## Exact crossing test of two parts inside the box lo..hi: {hits, depth, at} or {}.
func _cross(scene: Scene, a: int, b: int, lo: Vector3, hi: Vector3, eps: float, tris: Dictionary) -> Dictionary:
	var la: Array = []
	var lb: Array = []
	for t: int in _comp_tris(scene, a, tris):
		if _tri_in_box(scene, t, lo, hi, eps): la.append(t)
	for t: int in _comp_tris(scene, b, tris):
		if _tri_in_box(scene, t, lo, hi, eps): lb.append(t)
	var hits := 0
	var depth := 0.0
	var at := Vector3.ZERO
	var box_depth := minf(hi.x - lo.x, minf(hi.y - lo.y, hi.z - lo.z)) # the thinnest side of the boxes' common part: how far one part can reach into the other along an axis
	for ta: int in la:
		var na: Vector3 = scene.tn[ta]
		if na == Vector3.ZERO: continue
		var a0: Vector3 = scene.tv[3 * ta]
		var a1: Vector3 = scene.tv[3 * ta + 1]
		var a2: Vector3 = scene.tv[3 * ta + 2]
		for tb: int in lb:
			var nb: Vector3 = scene.tn[tb]
			if nb == Vector3.ZERO or absf(na.dot(nb)) > 0.99999: continue
			var b0: Vector3 = scene.tv[3 * tb]
			var b1: Vector3 = scene.tv[3 * tb + 1]
			var b2: Vector3 = scene.tv[3 * tb + 2]
			var point := _tri_cross(a0, a1, a2, na, b0, b1, b2, nb)
			if point.is_empty(): continue
			var da := maxf(maxf(absf(nb.dot(a0 - b0)), absf(nb.dot(a1 - b0))), absf(nb.dot(a2 - b0)))
			var db := maxf(maxf(absf(na.dot(b0 - a0)), absf(na.dot(b1 - a0))), absf(na.dot(b2 - a0)))
			var d := minf(minf(da, db), box_depth)
			if d <= eps: continue
			hits += 1
			if d > depth:
				depth = d
				at = point[0]
	if hits > 0: return {"hits": hits, "depth": depth, "at": at}
	# one part wholly inside the other (no surface crosses): its first vertex inside a closed solid
	for pair in [[a, b], [b, a]]:
		var inner: int = pair[0]
		var outer: int = pair[1]
		if scene.c_open[outer] == 1: continue
		var ilo: Vector3 = scene.c_min[inner]
		var ihi: Vector3 = scene.c_max[inner]
		var olo: Vector3 = scene.c_min[outer]
		var ohi: Vector3 = scene.c_max[outer]
		if ilo.x < olo.x or ilo.y < olo.y or ilo.z < olo.z or ihi.x > ohi.x or ihi.y > ohi.y or ihi.z > ohi.z: continue
		var first: Array = _comp_tris(scene, inner, tris)
		if first.is_empty(): continue
		var probe: Vector3 = scene.tv[3 * int(first[0])]
		var crossings := 0
		for t: int in _comp_tris(scene, outer, tris):
			if _ray_hits(scene, probe, t): crossings += 1
		if crossings % 2 == 1: return {"hits": 1, "depth": minf(ihi.x - ilo.x, minf(ihi.y - ilo.y, ihi.z - ilo.z)), "at": (ilo + ihi) * 0.5}
	return {}

func _tri_in_box(scene: Scene, t: int, lo: Vector3, hi: Vector3, eps: float) -> bool:
	var p0: Vector3 = scene.tv[3 * t]
	var p1: Vector3 = scene.tv[3 * t + 1]
	var p2: Vector3 = scene.tv[3 * t + 2]
	var tlo := p0.min(p1.min(p2))
	var thi := p0.max(p1.max(p2))
	return tlo.x <= hi.x + eps and tlo.y <= hi.y + eps and tlo.z <= hi.z + eps and thi.x >= lo.x - eps and thi.y >= lo.y - eps and thi.z >= lo.z - eps

## One crossing test of a ray cast from `origin` along +x with triangle t (inside test by crossing count).
func _ray_hits(scene: Scene, origin: Vector3, t: int) -> bool:
	var p0: Vector3 = scene.tv[3 * t]
	var p1: Vector3 = scene.tv[3 * t + 1]
	var p2: Vector3 = scene.tv[3 * t + 2]
	var hit: Variant = Geometry3D.ray_intersects_triangle(origin + Vector3(1.0e-4, 2.0e-4, 3.0e-4), Vector3.RIGHT, p0, p1, p2)
	return hit != null

## A proper crossing of triangle A (a0 a1 a2, normal na) and B: [point] or [] (touching and coplanar pairs do not count).
func _tri_cross(a0: Vector3, a1: Vector3, a2: Vector3, na: Vector3, b0: Vector3, b1: Vector3, b2: Vector3, nb: Vector3) -> Array:
	var pa: Array[Vector3] = [a0, a1, a2]
	var pb: Array[Vector3] = [b0, b1, b2]
	for e in 3:
		var hit: Variant = _edge_tri(pa[e], pa[(e + 1) % 3], b0, b1, b2, nb)
		if hit != null: return [hit]
	for e in 3:
		var hit: Variant = _edge_tri(pb[e], pb[(e + 1) % 3], a0, a1, a2, na)
		if hit != null: return [hit]
	return []

func _edge_tri(p: Vector3, q: Vector3, t0: Vector3, t1: Vector3, t2: Vector3, n: Vector3) -> Variant:
	var d0 := n.dot(p - t0)
	var d1 := n.dot(q - t0)
	if (d0 > 0.0 and d1 > 0.0) or (d0 < 0.0 and d1 < 0.0) or d0 == d1: return null
	var x := p + (q - p) * (d0 / (d0 - d1))
	var e0 := (t1 - t0).cross(x - t0).dot(n)
	var e1 := (t2 - t1).cross(x - t1).dot(n)
	var e2 := (t0 - t2).cross(x - t2).dot(n)
	if (e0 >= 0.0 and e1 >= 0.0 and e2 >= 0.0) or (e0 <= 0.0 and e1 <= 0.0 and e2 <= 0.0): return x
	return null

## ---- C5: double rims ----

var _rim_colours: Array = []     ## the rim colours of the kit's floor palettes
var _other_colours: Array = []   ## every other colour of them (tiles, grooves, sides, substructures)
var _rim_like_cache := {}

## Whether the vertex colour `c` (sRGB) is a kit rim colour: within RIM_TOL of one and nearer to it than to any other palette colour.
func _rim_like(c: Color) -> bool:
	if c.a <= 0.0: return false
	var packed := c.to_rgba32()
	if _rim_like_cache.has(packed): return bool(_rim_like_cache[packed])
	if _rim_colours.is_empty():
		for tone: String in BlockKit.FLOORS:
			var palette: Dictionary = BlockKit.FLOORS[tone]
			for key: String in palette: (_rim_colours if key == "rim" else _other_colours).append(Color(str(palette[key])))
	var near := INF
	for rim: Color in _rim_colours: near = minf(near, _rgb_distance(c, rim))
	var like := near <= RIM_TOL
	if like:
		for other: Color in _other_colours:
			if _rgb_distance(c, other) <= near:
				like = false
				break
	_rim_like_cache[packed] = like
	return like

static func _rgb_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()

## The double rims of a level (rules at the top of this file, C5): findings {cls: "double_rim", ca, cb: a part of each run, loc, extra: the distance between the two lines}.
func _double_rim_pass(scene: Scene, out: Array) -> void:
	var strips: Array = [] # a rim part that is a thin bar: {c, a: the axis it runs along (0 x, 2 z), lo, hi: its extent along it, at: its middle across, w: its width, y: its top}
	var max_width := float(opt.rim_width)
	for c in scene.c_entry.size():
		if scene.c_rim[c] == 0 or (scene.entries[scene.c_entry[c]] as Entry).hazard: continue
		var lo: Vector3 = scene.c_min[c]
		var hi: Vector3 = scene.c_max[c]
		var sx := hi.x - lo.x
		var sz := hi.z - lo.z
		if minf(sx, sz) > max_width or maxf(sx, sz) < minf(sx, sz) * 1.2: continue
		var a := 0 if sx >= sz else 2
		var b := 2 - a
		strips.append({"c": c, "a": a, "lo": lo[a], "hi": hi[a], "at": (lo[b] + hi[b]) * 0.5, "w": hi[b] - lo[b], "y": hi.y})
	strips.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return int(p.a) < int(q.a) if int(p.a) != int(q.a) else float(p.at) < float(q.at))
	var runs: Array = [] # strips of one line laid end to end: {c, a, lo, hi, at, w, y}
	var i := 0
	while i < strips.size():
		var first: Dictionary = strips[i]
		var cluster: Array = []
		while i < strips.size() and int(strips[i].a) == int(first.a) and float(strips[i].at) <= float(first.at) + 0.06:
			cluster.append(strips[i])
			i += 1
		cluster.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p.lo) < float(q.lo))
		var line: Array = []
		for s: Dictionary in cluster:
			var joined := false
			for r: Dictionary in line:
				if absf(float(r.y) - float(s.y)) <= 0.1 and float(s.lo) <= float(r.hi) + 0.05:
					r.hi = maxf(float(r.hi), float(s.hi))
					r.w = maxf(float(r.w), float(s.w))
					joined = true
					break
			if not joined: line.append(s.duplicate())
		runs.append_array(line)
	stats.rim_runs = runs.size()
	if runs.size() < 2: return
	var deck := _deck_grid(scene)
	var gap := float(opt.rim_gap)
	for p in runs.size():
		var ra: Dictionary = runs[p]
		for q in range(p + 1, runs.size()):
			var rb: Dictionary = runs[q]
			if int(rb.a) != int(ra.a) or float(rb.at) - float(ra.at) > gap: break
			var apart := float(rb.at) - float(ra.at)
			if apart < 0.12 or absf(float(ra.y) - float(rb.y)) > 0.15: continue
			var from := maxf(float(ra.lo), float(rb.lo))
			var to := minf(float(ra.hi), float(rb.hi))
			if to - from < 0.9: continue
			var top := maxf(float(ra.y), float(rb.y))
			var middle_across := (float(ra.at) + float(rb.at)) * 0.5
			if not _deck_line(scene, deck, int(ra.a), middle_across, from, to, top): continue # air between the two lines: two platforms with a gap, each its own edge
			var inner := _deck_beyond(scene, deck, ra, -1.0, from, to, top) or _deck_beyond(scene, deck, rb, 1.0, from, to, top)
			if not inner: continue
			var b := 2 - int(ra.a)
			var middle := Vector3.ZERO
			middle[int(ra.a)] = (from + to) * 0.5
			middle[b] = (float(ra.at) + float(rb.at)) * 0.5
			middle.y = top
			out.append({"cls": "double_rim", "ca": int(ra.c), "cb": int(rb.c), "pairs": 1, "area": 0.0, "loc": middle, "extra": apart, "same": false})

## The up-facing tops of the level (not movers' parts, not the world): triangle ids by DECK_CELL cell in x, z.
func _deck_grid(scene: Scene) -> Dictionary:
	var grid := {}
	var wanted: Array = opt.overlap_scopes
	for t in scene.tn.size():
		if scene.tn[t].y < 0.99: continue
		var entry: Entry = scene.entries[scene.c_entry[scene.tcomp[t]]]
		if entry.hazard or not entry.scope in wanted: continue
		var a: Vector3 = scene.tv[3 * t]
		var b: Vector3 = scene.tv[3 * t + 1]
		var c: Vector3 = scene.tv[3 * t + 2]
		var x0 := floori(minf(a.x, minf(b.x, c.x)) / DECK_CELL)
		var x1 := floori(maxf(a.x, maxf(b.x, c.x)) / DECK_CELL)
		var z0 := floori(minf(a.z, minf(b.z, c.z)) / DECK_CELL)
		var z1 := floori(maxf(a.z, maxf(b.z, c.z)) / DECK_CELL)
		for x in range(x0, x1 + 1):
			for z in range(z0, z1 + 1):
				var key := Vector2i(x, z)
				if not grid.has(key): grid[key] = []
				(grid[key] as Array).append(t)
	return grid

## Whether deck lies beyond the rim run `run` (on its side away from the other run: `side` -1 when the other run is on its +across side, +1 when on its -across side): `_deck_line` 0.2 m past its outer edge.
func _deck_beyond(scene: Scene, grid: Dictionary, run: Dictionary, side: float, from: float, to: float, top: float) -> bool:
	return _deck_line(scene, grid, int(run.a), float(run.at) + side * (float(run.w) * 0.5 + 0.2), from, to, top)

## Whether half of the samples along the line `across` (every 0.5 m over [from, to] of the axis `a`) stand on a top of the level within 0.3 m under `top`.
func _deck_line(scene: Scene, grid: Dictionary, a: int, across: float, from: float, to: float, top: float) -> bool:
	var b := 2 - a
	var count := maxi(1, floori((to - from - 0.5) / 0.5) + 1)
	var on := 0
	for k in count:
		var along := (from + to) * 0.5 if count == 1 else from + 0.25 + (to - from - 0.5) * float(k) / float(count - 1)
		var point := Vector3.ZERO
		point[a] = along
		point[b] = across
		if _on_deck(scene, grid, point.x, point.z, top): on += 1
	return on * 2 >= count

func _on_deck(scene: Scene, grid: Dictionary, x: float, z: float, top: float) -> bool:
	var key := Vector2i(floori(x / DECK_CELL), floori(z / DECK_CELL))
	if not grid.has(key): return false
	for t: int in grid[key]:
		var a: Vector3 = scene.tv[3 * t]
		var b: Vector3 = scene.tv[3 * t + 1]
		var c: Vector3 = scene.tv[3 * t + 2]
		var y := (a.y + b.y + c.y) / 3.0
		if y > top + 0.08 or y < top - 0.3: continue
		var d1 := (x - b.x) * (a.z - b.z) - (a.x - b.x) * (z - b.z)
		var d2 := (x - c.x) * (b.z - c.z) - (b.x - c.x) * (z - c.z)
		var d3 := (x - a.x) * (c.z - a.z) - (c.x - a.x) * (z - a.z)
		if not ((d1 < 0.0 or d2 < 0.0 or d3 < 0.0) and (d1 > 0.0 or d2 > 0.0 or d3 > 0.0)): return true
	return false

## ---- findings to a report section ----

func _comp_name(scene: Scene, c: int) -> String:
	var entry: Entry = scene.entries[scene.c_entry[c]]
	var lo: Vector3 = scene.c_min[c]
	var hi: Vector3 = scene.c_max[c]
	var name_text := entry.path
	if scene.c_sub[c] >= 0: name_text += "[%d]" % scene.c_sub[c]
	if scene.c_many[c] == 1: name_text += "#c%d" % scene.c_local[c]
	var centre := (lo + hi) * 0.5
	return "%s %.2fx%.2fx%.2f @(%.2f, %.2f, %.2f)" % [name_text, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, centre.x, centre.y, centre.z]

func _group_name(scene: Scene, c: int) -> String:
	return (scene.entries[scene.c_entry[c]] as Entry).path

## Findings (dictionaries with cls, ca, cb, pairs, area, loc, extra) -> {total, groups: by class and the two node paths, top: the biggest findings}.
func _section(scene: Scene, findings: Array) -> Dictionary:
	var groups := {}
	for f in findings:
		var finding: Dictionary = f
		var pa := _group_name(scene, int(finding.ca))
		var pb := _group_name(scene, int(finding.cb))
		var key := "%s|%s|%s" % [finding.cls, pa, pb] if pa <= pb else "%s|%s|%s" % [finding.cls, pb, pa]
		if not groups.has(key):
			groups[key] = {"key": key, "cls": finding.cls, "a": _comp_name(scene, int(finding.ca)), "b": _comp_name(scene, int(finding.cb)), "findings": 0, "pairs": 0, "area": 0.0, "loc": _vec(finding.loc), "best": -1.0, "extra": INF, "detail": "", "plane": finding.get("plane", []), "same": true}
		var g: Dictionary = groups[key]
		if not bool(finding.get("same", false)): g.same = false
		g.findings = int(g.findings) + 1
		g.pairs = int(g.pairs) + int(finding.pairs)
		g.area = float(g.area) + float(finding.area)
		var is_overlap := str(finding.cls).begins_with("overlap")
		if is_overlap: g.depth = maxf(float(g.get("depth", 0.0)), float(finding.extra))
		else: g.extra = minf(float(g.extra), float(finding.extra)) if finding.has("extra") else g.extra
		var rank: float = float(finding.extra) if is_overlap else (float(finding.area) if not str(finding.cls) in ["gap", "gap_seam", "gap_decal", "gap_lift", "bottom_gap", "bottom_free", "floating"] else 1.0 / (0.001 + float(finding.get("extra", 0.0))))
		if rank > float(g.best):
			g.best = rank
			g.loc = _vec(finding.loc)
			g.plane = finding.get("plane", [])
			g.a = _comp_name(scene, int(finding.ca))
			g.b = _comp_name(scene, int(finding.cb))
	var list: Array = groups.values()
	for g: Dictionary in list:
		match str(g.cls):
			"overlap_deco_kit", "overlap_deco_block", "overlap_deco_deco", "overlap_kit_block", "overlap_cage": g.detail = "%d crossings, deepest %.1f cm" % [g.pairs, float(g.depth) * 100.0]
			"gap", "gap_seam", "gap_decal", "gap_lift": g.detail = "smallest gap %.1f mm, overlap %.3f m2" % [float(g.extra) * 1000.0, g.area]
			"double_rim": g.detail = "%d rim line pairs, nearest %.2f m apart" % [g.findings, float(g.extra)]
			"bottom_gap", "bottom_free", "floating": g.detail = "%s under it" % (_air(float(g.extra)) if float(g.extra) < INF else "nothing")
			_: g.detail = "%d triangle pairs, %.3f m2%s" % [g.pairs, g.area, ", same material" if g.same else ""]
		g.erase("best")
		if float(g.extra) == INF: g.extra = -1.0
	list.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if str(x.cls) != str(y.cls): return str(x.cls) < str(y.cls)
		if str(x.cls).begins_with("overlap"): return float(x.get("depth", 0.0)) > float(y.get("depth", 0.0))
		if float(x.area) != float(y.area) and str(x.cls) != "gap": return float(x.area) > float(y.area)
		return int(x.findings) > int(y.findings))
	var kept := list.slice(0, int(opt.keep))
	return {"total": findings.size(), "pairs": 0, "groups": kept, "group_count": list.size()}

func _air(metres: float) -> String:
	return "%.1f mm of air" % (metres * 1000.0) if metres < 0.1 else "%.2f m of air" % metres

func _vec(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]

## ---- self-test: synthetic meshes, known defects and clean stacks ----

var _failures := 0

func expect(ok: bool, text: String) -> void:
	if not ok: _failures += 1
	print("MESHLINT selftest ", "ok   " if ok else "FAIL ", text)

func _box(parent: Node3D, label: String, position: Vector3, size: Vector3, double_sided := false, alpha := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	if double_sided: mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alpha: mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = position
	return mi

func _quad(parent: Node3D, label: String, position: Vector3, size: Vector2, up := true, double_sided := false) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	if double_sided: mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = position
	mi.rotation_degrees = Vector3(-90.0 if up else 90.0, 0.0, 0.0) # a QuadMesh faces +z: turned to face up (or down)
	return mi

func _lint(label: String) -> Dictionary:
	var holder: Node3D = root.get_node("LintHolder")
	var result := analyze([holder], holder, Vector3.ZERO)
	print("MESHLINT selftest   %s: coplanar %d, gaps %d, vertical %d" % [label, result.coplanar.total, result.gap.total, result.vertical.total])
	return result

func _fresh() -> Node3D:
	var old := root.get_node_or_null("LintHolder")
	if old != null:
		root.remove_child(old)
		old.free()
	var holder := Node3D.new()
	holder.name = "LintHolder"
	root.add_child(holder)
	return holder

func _classes(section: Dictionary) -> Array:
	var out: Array = []
	for g: Dictionary in section.groups: out.append(str(g.cls))
	return out

## The expectations; returns the number of failures.
func selftest() -> int:
	_failures = 0
	mesh_cache.clear()
	flag_cache.clear()
	opt.scopes = ["level", "tiles", "cage", "world"]
	opt.gap_scopes = ["level", "tiles", "cage"]
	opt.keep = 100000
	var holder := _fresh()
	# 1. two coplanar quads facing up, overlapping: z-fight
	_quad(holder, "QuadA", Vector3.ZERO, Vector2(2, 2))
	_quad(holder, "QuadB", Vector3(0.5, 0.0, 0.0), Vector2(2, 2))
	var r := _lint("two coplanar quads")
	expect(r.coplanar.total == 1 and _classes(r.coplanar) == ["zfight"], "two coplanar up-facing quads: one zfight finding (%s)" % str(_classes(r.coplanar)))
	expect(r.coplanar.groups.size() == 1 and absf(float(r.coplanar.groups[0].area) - 3.0) < 0.01, "their overlap is 1.5 x 2 = 3 m2 (%s)" % str(r.coplanar.groups[0].area if r.coplanar.groups.size() > 0 else -1))
	# 2. the same quads 1 mm apart (inside eps) fail, 5 mm apart (outside) pass, touching rims (no area) pass
	holder = _fresh()
	_quad(holder, "QuadA", Vector3.ZERO, Vector2(2, 2))
	_quad(holder, "QuadB", Vector3(0.0, 0.001, 0.0), Vector2(2, 2))
	expect(_lint("1 mm apart").coplanar.total == 1, "quads 1 mm apart z-fight")
	holder = _fresh()
	_quad(holder, "QuadA", Vector3.ZERO, Vector2(2, 2))
	_quad(holder, "QuadB", Vector3(0.0, 0.005, 0.0), Vector2(2, 2))
	expect(_lint("5 mm apart").coplanar.total == 0, "quads 5 mm apart pass")
	holder = _fresh()
	_quad(holder, "QuadA", Vector3.ZERO, Vector2(2, 2))
	_quad(holder, "QuadB", Vector3(2.0, 0.0, 0.0), Vector2(2, 2))
	expect(_lint("side by side").coplanar.total == 0, "coplanar quads that only share an edge pass")
	# 3. opposite facing: one-sided pass (each hidden by its block), a two-sided one fails
	holder = _fresh()
	_quad(holder, "Up", Vector3.ZERO, Vector2(2, 2), true)
	_quad(holder, "Down", Vector3.ZERO, Vector2(2, 2), false)
	expect(_lint("back to back, one-sided").coplanar.total == 0, "back to back one-sided quads pass")
	holder = _fresh()
	_quad(holder, "Up", Vector3.ZERO, Vector2(2, 2), true, true)
	_quad(holder, "Down", Vector3.ZERO, Vector2(2, 2), false)
	r = _lint("back to back, two-sided")
	expect(_classes(r.coplanar) == ["zfight_back"], "back to back with a two-sided material: zfight_back (%s)" % str(_classes(r.coplanar)))
	# 4. a blended overlay is a decal
	holder = _fresh()
	_box(holder, "Block", Vector3(0.0, -0.5, 0.0), Vector3(2, 1, 2))
	var overlay := _quad(holder, "Overlay", Vector3.ZERO, Vector2(1, 1))
	(overlay.material_override as BaseMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	expect(_classes(_lint("decal").coplanar) == ["decal"], "an alpha quad on a block's top is a decal")
	# 5. a clean stack: floor slab, a block on it, a second block on that, flush sides: no coplanar findings, no gaps, every pillar held
	holder = _fresh()
	_box(holder, "Floor", Vector3(0.0, -0.1, 0.0), Vector3(6, 0.2, 6))
	_box(holder, "LowerBlock", Vector3(0.0, 0.5, 0.0), Vector3(1, 1, 1))
	_box(holder, "UpperBlock", Vector3(0.0, 1.5, 0.0), Vector3(1, 1, 1))
	r = _lint("clean stack")
	expect(r.coplanar.total == 0 and r.gap.total == 0 and r.vertical.total == 0, "a flush stack is clean (coplanar %d, gaps %d, vertical %d)" % [r.coplanar.total, r.gap.total, r.vertical.total])
	# 5b. the same stack drawn two-sided: closed solids touching face to face still hide each other's faces
	holder = _fresh()
	_box(holder, "Floor", Vector3(0.0, -0.1, 0.0), Vector3(6, 0.2, 6), true)
	_box(holder, "LowerBlock", Vector3(0.0, 0.5, 0.0), Vector3(1, 1, 1), true)
	_box(holder, "UpperBlock", Vector3(0.0, 1.5, 0.0), Vector3(1, 1, 1), true)
	expect(_lint("clean stack, two-sided").coplanar.total == 0, "a flush stack of two-sided closed blocks is clean")
	# 5c. coplanar blocks that overlap (an upper block pushed into the first): the shared top faces z-fight, and one material instance is reported as such
	holder = _fresh()
	var shared := StandardMaterial3D.new()
	var left := _box(holder, "Left", Vector3(0.0, 0.5, 0.0), Vector3(2, 1, 2))
	var right := _box(holder, "Right", Vector3(1.0, 0.5, 0.0), Vector3(2, 1, 2))
	left.material_override = shared
	right.material_override = shared
	r = _lint("overlapping blocks")
	expect(r.coplanar.total == 1 and str(r.coplanar.groups[0].detail).ends_with("same material") and absf(float(r.coplanar.groups[0].area) - 6.0) < 0.01, "two blocks overlapping by half share their top, bottom and both sides (2 + 2 + 1 + 1 m2): one finding, same material (%s)" % str(r.coplanar.groups[0].detail if r.coplanar.groups.size() > 0 else ""))
	# 6. the same stack with the upper block lifted 1 cm: a hairline gap on y
	holder = _fresh()
	_box(holder, "Floor", Vector3(0.0, -0.1, 0.0), Vector3(6, 0.2, 6))
	_box(holder, "LowerBlock", Vector3(0.0, 0.5, 0.0), Vector3(1, 1, 1))
	_box(holder, "UpperBlock", Vector3(0.0, 1.51, 0.0), Vector3(1, 1, 1))
	r = _lint("hairline above")
	expect(r.gap.total == 1 and _classes(r.gap) == ["gap"] and absf(float(r.gap.groups[0].extra) - 0.01) < 0.0005, "a 1 cm gap in a stack is found (%d, %s)" % [r.gap.total, str(r.gap.groups[0].extra if r.gap.groups.size() > 0 else -1)])
	expect(_classes(r.vertical) == ["bottom_gap"], "the block lifted 1 cm: bottom_gap (%s)" % str(_classes(r.vertical)))
	# 7. a panel and a pillar side by side 2 cm apart (gap on x), then 20 cm apart (too far to be a hairline), then touching
	for gap_case in [[0.02, 1], [0.2, 0], [0.0, 0]]:
		holder = _fresh()
		_box(holder, "Floor", Vector3(0.0, -0.1, 0.0), Vector3(8, 0.2, 8))
		_box(holder, "Pillar", Vector3(0.0, 1.5, 0.0), Vector3(0.4, 3, 0.4))
		_box(holder, "Panel", Vector3(0.2 + float(gap_case[0]) + 1.0, 1.5, 0.0), Vector3(2, 3, 0.1))
		r = _lint("panel at %s" % str(gap_case[0]))
		expect(r.gap.total == int(gap_case[1]) and r.vertical.total == 0, "panel %.0f cm from a pillar: %d gap(s), no loose end (%d, vertical %d)" % [float(gap_case[0]) * 100.0, int(gap_case[1]), r.gap.total, r.vertical.total])
	# 8. a pillar in the air
	holder = _fresh()
	_box(holder, "Floor", Vector3(0.0, -0.1, 0.0), Vector3(6, 0.2, 6))
	_box(holder, "Pillar", Vector3(0.0, 4.0, 0.0), Vector3(0.4, 3, 0.4))
	r = _lint("floating pillar")
	expect(_classes(r.vertical) == ["floating"], "a pillar touching nothing is floating (%s)" % str(_classes(r.vertical)))
	# 8b. a pillar hanging from a ceiling slab with 0.5 m of air under it: bottom_free, with the air
	holder = _fresh()
	_box(holder, "Floor", Vector3(0.0, -0.1, 0.0), Vector3(6, 0.2, 6))
	_box(holder, "Ceiling", Vector3(0.0, 3.1, 0.0), Vector3(6, 0.2, 6))
	_box(holder, "Hanger", Vector3(0.0, 1.75, 0.0), Vector3(0.4, 2.5, 0.4))
	r = _lint("hanging pillar")
	expect(_classes(r.vertical) == ["bottom_free"] and absf(float(r.vertical.groups[0].extra) - 0.5) < 0.01, "a pillar hanging from a slab is bottom_free with 0.5 m of air (%s)" % str(r.vertical.groups[0].extra if r.vertical.groups.size() > 0 else -1))
	# 9. a MultiMesh: overlapping elements z-fight, spaced elements (the grooves of a layer) neither z-fight nor count as gaps
	multimesh_readable = _probe_multimesh()
	holder = _fresh()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	var tile := BoxMesh.new()
	tile.size = Vector3(1, 0.2, 1)
	multi.mesh = tile
	multi.instance_count = 3
	multi.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.0)))
	multi.set_instance_transform(1, Transform3D(Basis.IDENTITY, Vector3(0.5, 0.0, 0.0)))
	multi.set_instance_transform(2, Transform3D(Basis.IDENTITY, Vector3(1.52, 0.0, 0.0))) # 2 cm groove to element 1's far side
	var node := MultiMeshInstance3D.new()
	node.name = "StageFloor0"
	node.multimesh = multi
	holder.add_child(node)
	r = _lint("multimesh")
	if multimesh_readable:
		expect(r.coplanar.total == 1 and r.coplanar.groups[0].cls == "zfight" and r.coplanar.groups[0].pairs > 0, "overlapping MultiMesh elements z-fight (%d)" % r.coplanar.total)
		expect(r.gap.total == 0, "elements of one MultiMesh are not compared for gaps (%d)" % r.gap.total)
	else:
		expect(r.coplanar.total == 0 and r.skipped_multimesh.size() == 1, "dummy renderer: the MultiMesh is reported as not linted instead of read as garbage (%d skipped)" % r.skipped_multimesh.size())
		print("MESHLINT selftest skip the MultiMesh cases: this renderer drops MultiMesh transforms (run without --headless)")
	# 10. the grid against the brute force on random axis-aligned quads on a few planes (the broad phase loses nothing)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	holder = _fresh()
	var quads: Array = []
	for i in 160:
		var p := Vector3(rng.randf_range(-6.0, 6.0), float(rng.randi_range(0, 2)) * 0.5 + (0.0015 if rng.randf() < 0.3 else 0.0), rng.randf_range(-6.0, 6.0))
		var s := Vector2(rng.randf_range(0.4, 3.0), rng.randf_range(0.4, 3.0))
		quads.append([p, s])
		_quad(holder, "Q%d" % i, p, s)
	var brute := _brute_pairs(quads)
	r = _lint("random quads")
	var found := 0
	for g: Dictionary in r.coplanar.groups: found += int(g.findings)
	expect(r.coplanar.total == brute and found == brute, "grid broad phase: %d findings, brute force over the quads %d" % [r.coplanar.total, brute])
	# 11. C4 overlaps: a pad sunk into a block, sitting on it, sunk less than eps, buried; the parts of one assembly; a kit part against a block
	for case in [["pad sunk 8 cm", 0.47, "overlap_deco_block"], ["pad sitting on the top", 0.5 + 0.05, ""], ["pad sunk 5 mm", 0.545, ""], ["pad planted 3 cm", 0.52, ""], ["pad buried", 0.0, "overlap_deco_block"]]:
		holder = _fresh()
		var level := Node3D.new()
		level.name = "Level01"
		holder.add_child(level)
		_box(level, "LevelLook", Vector3(0.0, 0.0, 0.0), Vector3(4, 1, 4))
		_box(level, "LaunchPad", Vector3(0.0, float(case[1]) + 0.0, 0.0), Vector3(1, 0.1, 1) if float(case[1]) > 0.0 else Vector3(0.5, 0.1, 0.5))
		r = _lint(str(case[0]))
		var want: Array = [] if str(case[2]) == "" else [str(case[2])]
		expect(_classes(r.overlap) == want, "%s: %s (%s)" % [case[0], str(want), str(_classes(r.overlap))])
	holder = _fresh()
	var level2 := Node3D.new()
	level2.name = "Level01"
	holder.add_child(level2)
	var spinner := Node3D.new()
	spinner.name = "Hazard_spin_1"
	level2.add_child(spinner)
	_box(spinner, "BarA", Vector3.ZERO, Vector3(4, 0.5, 0.5))
	_box(spinner, "BarB", Vector3.ZERO, Vector3(0.5, 0.5, 4))
	expect(_lint("spinner bars").overlap.total == 0, "the two bars of one spinner cross: one assembly, no finding")
	_box(level2, "Banner", Vector3(1.5, 0.0, 0.0), Vector3(1, 1, 1))
	expect(_classes(_lint("a stranger in the bars").overlap) == ["overlap_deco_deco"], "a deco part crossing the spinner's bar is found")
	# 12. gap classes: a 3 mm lift step between level-look parts and a thin pad marker over a block are intended, a 3 mm gap under a deco part is not
	holder = _fresh()
	var level3 := Node3D.new()
	level3.name = "Level01"
	holder.add_child(level3)
	_box(level3, "LevelLook", Vector3(0.0, 0.0, 0.0), Vector3(4, 1, 4))
	_box(level3, "LevelCeilings", Vector3(0.0, 1.003, 0.0), Vector3(2, 1, 2))
	r = _lint("lift step")
	expect(r.gap.total == 0 and _classes(r.gap_seam) == ["gap_lift"], "a 3 mm step between level-look parts is gap_lift, not a gap (%s, %s)" % [r.gap.total, str(_classes(r.gap_seam))])
	holder = _fresh()
	var level4 := Node3D.new()
	level4.name = "Level01"
	holder.add_child(level4)
	_box(level4, "LevelLook", Vector3(0.0, 0.0, 0.0), Vector3(4, 1, 4))
	_box(level4, "CollisionLookPad", Vector3(0.0, 0.507, 0.0), Vector3(2, 0.01, 2))
	r = _lint("decal over a block")
	expect(r.gap.total == 0 and _classes(r.gap_seam) == ["gap_decal"], "a 1 cm thick marker 2 mm over a block is gap_decal (%s, %s)" % [r.gap.total, str(_classes(r.gap_seam))])
	holder = _fresh()
	var level5 := Node3D.new()
	level5.name = "Level01"
	holder.add_child(level5)
	_box(level5, "LevelLook", Vector3(0.0, 0.0, 0.0), Vector3(4, 1, 4))
	_box(level5, "Statue", Vector3(0.0, 1.003, 0.0), Vector3(1, 1, 1))
	r = _lint("deco over a block")
	expect(_classes(r.gap) == ["gap"], "a 3 mm gap under a deco part stays a gap (%s)" % str(_classes(r.gap)))
	# the candy kit's floor slabs: one deck, and two decks meeting at one height, are clean
	holder = _fresh()
	_kit_floors(holder, [[Vector3(0.0, -1.0, 0.0), Vector3(12.0, 2.0, 8.0)]])
	r = _lint("one kit deck")
	expect(r.coplanar.total == 0 and r.gap.total == 0 and r.double_rim.total == 0, "one kit deck (a chamfered slab): no coplanar face, no gap (%d, %d)" % [r.coplanar.total, r.gap.total])
	holder = _fresh()
	_kit_floors(holder, [[Vector3(-6.0, -1.0, 0.0), Vector3(12.0, 2.0, 8.0)], [Vector3(6.0, -2.0, 0.0), Vector3(12.0, 2.0, 8.0)]])
	r = _lint("a step down")
	expect(r.coplanar.total == 0 and r.double_rim.total == 0, "a deck and a lower one beside it: no coplanar face (%d)" % r.coplanar.total)
	var old := root.get_node_or_null("LintHolder")
	if old != null:
		root.remove_child(old)
		old.free()
	return _failures

## Kit floor blocks ([[centre, size], ...], palette teal, no neighbours known) as one kit-material mesh under `parent`.
func _kit_floors(parent: Node3D, blocks: Array) -> void:
	var batch := BlockMesh.Batch.new()
	for block: Array in blocks:
		var xf := Transform3D(Basis.IDENTITY, block[0])
		BlockKit.floor_block(batch, xf, block[1], "teal", null, [[], [], [], []])
	var mesh := ArrayMesh.new()
	for key: String in batch.groups:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, (batch.groups[key] as BlockMesh.Group).arrays())
		mesh.surface_set_material(mesh.get_surface_count() - 1, BlockKit.material())
	var mi := MeshInstance3D.new()
	mi.name = "KitFloors"
	mi.mesh = mesh
	parent.add_child(mi)

## Pairs of the synthetic quads that overlap in plan (> min_area) and sit within eps in height, counted per pair of quads (what the lint reports as findings).
func _brute_pairs(quads: Array) -> int:
	var n := 0
	for i in quads.size():
		for j in range(i + 1, quads.size()):
			var a: Array = quads[i]
			var b: Array = quads[j]
			var pa: Vector3 = a[0]
			var pb: Vector3 = b[0]
			if absf(pa.y - pb.y) > float(opt.eps): continue
			var sa: Vector2 = a[1]
			var sb: Vector2 = b[1]
			var ox := minf(pa.x + sa.x * 0.5, pb.x + sb.x * 0.5) - maxf(pa.x - sa.x * 0.5, pb.x - sb.x * 0.5)
			var oz := minf(pa.z + sa.y * 0.5, pb.z + sb.y * 0.5) - maxf(pa.z - sa.y * 0.5, pb.z - sb.y * 0.5)
			if ox > 0.0 and oz > 0.0 and ox * oz >= float(opt.min_area): n += 1
	return n
