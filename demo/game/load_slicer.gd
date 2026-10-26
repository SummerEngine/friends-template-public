extends RefCounted
## Frame budget shared by every long build step of the level world: a step asks `due()` and, when its slice is used up,
## awaits `next()`, which hands the frame back to the loading page or the menu and starts a new slice.
## Background builds (behind the main menu) follow the frame time instead of a fixed budget so the menu keeps its frame rate.
const BACKGROUND_FRAME_MS := 20
const BACKGROUND_START_USEC := 3500
const BACKGROUND_FLOOR_USEC := 1200

var tree: SceneTree
var budget_usec := 9000
var foreground_budget_usec := 9000
var progress := Callable() ## (fraction 0..1 of the level build, label)
var frames := 0
var max_gap_ms := 0
var background := false: set = _set_background
var _from := 0
var _last_ms := 0
var _held: Array = []

func _set_background(value: bool) -> void:
	background = value
	budget_usec = BACKGROUND_START_USEC if value else foreground_budget_usec

func _init(owner_tree: SceneTree, progress_callback := Callable()) -> void:
	tree = owner_tree
	progress = progress_callback
	_from = Time.get_ticks_usec()
	_last_ms = Time.get_ticks_msec()

func due() -> bool:
	return Time.get_ticks_usec() - _from >= budget_usec

## Nodes that must not move while the level is still being drawn over several frames: processing is switched off until release().
func hold(node: Node) -> void:
	_held.append([node, node.is_processing(), node.is_physics_processing()])
	node.set_process(false)
	node.set_physics_process(false)

func release() -> void:
	for entry: Array in _held:
		if is_instance_valid(entry[0]):
			entry[0].set_process(entry[1])
			entry[0].set_physics_process(entry[2])
	_held.clear()

## Coroutine: hand the frame back (progress first), then start a new budget.
func next(part := -1.0, label := "") -> void:
	if progress.is_valid() and part >= 0.0: progress.call(part, label)
	await tree.process_frame
	var now := Time.get_ticks_msec()
	var gap := now - _last_ms
	max_gap_ms = maxi(max_gap_ms, gap)
	frames += 1
	if background:
		if gap > BACKGROUND_FRAME_MS: budget_usec = maxi(BACKGROUND_FLOOR_USEC, int(budget_usec * 0.7))
		elif gap <= BACKGROUND_FRAME_MS - 2: budget_usec = mini(foreground_budget_usec, budget_usec + 300)
	_last_ms = now
	_from = Time.get_ticks_usec()
