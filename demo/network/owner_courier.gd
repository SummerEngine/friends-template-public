extends RefCounted
## The owner's own courier on a replica client: it is seeded from the authority's baseline, stepped at 60 Hz by CourierMotion
## and captured as the owner pose the authority validates. The caller authenticates lifetime and baseline; this helper grants no
## network permissions. There is no history or replay: the authority never corrects an owner, it only starts a new epoch.
const Modes := preload("res://modes/modes.gd")
const STEP := 1.0 / 60.0
const LIFETIME_FIELDS := ["world_id","session_id","entity_id","lifetime_revision"]
const ANCHOR_OFFSET := Vector3(0.0, 1.0, 0.0)
var run
var actor: CharacterBody3D
var motion
var seat := -1
var dash_flop := Modes.dash_flop() ## the mode's dash penalty (modes.json `dash_flop`), handed to the motion every step
var lifetime := {}
var reset_epoch := -1
var observed_epoch := -1
var configured := false
var active := false
var shared_playing := false
var waiting_for_partner := false
var holding := true
var jump_pending := 0
var dash_pending := 0
var local_tick := 0
var frozen := false ## a stage round's card (game_run.gd hold_start): no steering, no jump, no dash until GO; set by the shell before each step
var still := false ## the show's podium (game_run.gd hold_yaw): no steering and no dash, a jump in place stays; set by the shell before each step
var last_events := {}
var metrics := {"steps":0,"seeds":0,"duplicate_resets":0,"ignored_echoes":0,"rejected_lifetimes":0,"rejected_epochs":0}
var _previous_layers := 0
var _previous_mask := 0

static func _valid_lifetime(value: Dictionary) -> bool:
	return value.get("world_id") is String and not value.world_id.is_empty() and value.get("session_id") is String and not value.session_id.is_empty() and value.get("entity_id") is int and value.entity_id>0 and value.get("lifetime_revision") is int and value.lifetime_revision>0

## `baseline`: {position: Vector3, yaw: float}.
static func _valid_baseline(value: Dictionary) -> bool:
	return value.get("position") is Vector3 and value.position.is_finite() and (value.get("yaw") is float or value.get("yaw") is int) and is_finite(float(value.yaw))

func _same_lifetime(value: Dictionary) -> bool:
	if not _valid_lifetime(value): return false
	for key: String in LIFETIME_FIELDS:
		if value[key]!=lifetime.get(key): return false
	return true

func _refresh_active() -> void:
	active=configured and reset_epoch==observed_epoch and shared_playing and not waiting_for_partner
	if not active:
		jump_pending=0
		dash_pending=0

func configure(simulation, slot: int, identity: Dictionary, epoch: int, baseline: Dictionary) -> bool:
	if configured or simulation==null or simulation.network_role!="replica": return false
	if slot < 0 or slot >= simulation.carrier_count or simulation.actors.size()!=simulation.carrier_count or simulation.motions.size()!=simulation.carrier_count: return false
	if not _valid_lifetime(identity) or epoch<0 or not _valid_baseline(baseline): return false
	run=simulation
	seat=slot
	actor=run.actors[seat]
	motion=run.motions[seat]
	lifetime=identity.duplicate(true)
	_previous_layers=actor.collision_layer
	_previous_mask=actor.collision_mask
	# Only the owner's own courier collides with the world: the other one is drawn from its relayed poses.
	actor.collision_layer=2
	actor.collision_mask=1|16|run.BLOCKER_LAYER
	configured=true
	return reset_from_authority(identity,epoch,baseline)

func reset_from_authority(identity: Dictionary, epoch: int, baseline: Dictionary) -> bool:
	if not configured or not _same_lifetime(identity):
		metrics.rejected_lifetimes+=1
		return false
	if epoch<reset_epoch or epoch<observed_epoch:
		metrics.rejected_epochs+=1
		return false
	if not _valid_baseline(baseline): return false
	if epoch==reset_epoch:
		metrics.duplicate_resets+=1
		return true # Same epoch cannot reseed, even if another baseline is supplied.
	motion.reset(actor,baseline.position,float(baseline.yaw))
	reset_epoch=epoch
	observed_epoch=epoch
	holding=true
	jump_pending=0
	dash_pending=0
	local_tick=0
	last_events={}
	metrics.seeds+=1
	_refresh_active()
	return true

func observe_shared(identity: Dictionary, state: Dictionary) -> bool:
	if not configured or not _same_lifetime(identity):
		metrics.rejected_lifetimes+=1
		return false
	if not state.get("resets") is int or state.resets<observed_epoch:
		metrics.rejected_epochs+=1
		return false
	if not state.get("playing") is bool or not state.get("waiting_for_partner") is bool: return false
	if not state.get("holding") is Array or state.holding.size()<=seat: return false
	for value: Variant in state.holding:
		if not value is bool: return false
	observed_epoch=state.resets
	shared_playing=state.playing
	waiting_for_partner=state.waiting_for_partner
	holding=state.holding[seat]
	_refresh_active() # A new epoch pauses until the explicit trusted baseline arrives.
	return true

## Never inspects or applies echoed transform/velocity/timers: an echo is not a reset and cannot move the courier.
func observe_owner_echo(identity: Dictionary, epoch: int, _pose: Dictionary) -> bool:
	if not configured or not _same_lifetime(identity):
		metrics.rejected_lifetimes+=1
		return false
	if epoch!=reset_epoch or epoch!=observed_epoch:
		metrics.rejected_epochs+=1
		return false
	metrics.ignored_echoes+=1
	return true

func jump_edge() -> void:
	if configured and active and not frozen: jump_pending=mini(jump_pending+1,8)

## One DASH press (courier_motion.gd DASH_*): taken by the next step; a press the cooldown refuses is simply spent.
func dash_edge() -> void:
	if configured and active and not still and not frozen: dash_pending=mini(dash_pending+1,2)

## `command`: {move: Vector2 or [x, z]}; `enabled` false = a menu covers the game (neutral input, gravity and braking still run).
func physics_step(command: Dictionary, enabled: bool, delta: float) -> bool:
	if not configured or not active or not is_finite(delta) or absf(delta-STEP)>.00001: return false
	var move: Variant=command.get("move",Vector2.ZERO)
	if move is Array and move.size()==2: move=Vector2(float(move[0]),float(move[1]))
	if not move is Vector2 or not move.is_finite(): return false
	if not enabled:
		move=Vector2.ZERO
		jump_pending=0
		dash_pending=0
	elif still:
		move=Vector2.ZERO
		dash_pending=0
	if frozen and enabled:
		move=Vector2.ZERO
		jump_pending=0
		dash_pending=0
	var jump: bool = enabled and jump_pending>0
	if jump: jump_pending-=1
	var dash: bool = enabled and dash_pending>0
	if dash: dash_pending-=1
	var partner: CharacterBody3D=run.partner_actor(seat)
	motion.set_stage(run.stage_round()) # a stage round: its feel, the couriers solid for each other and the one-way floors (the same as a local game's)
	motion.set_floors(run.stage_floors())
	motion.set_dash_flop(dash_flop)
	last_events=motion.step(actor,{"move":move,"jump":jump,"dash":dash,"toward":partner.global_position,"partner_velocity":partner.velocity,"holding":holding and run.round_mode!="lobby"},delta)
	local_tick+=1
	metrics.steps+=1
	return true

## The owner pose of this tick (the caller adds version, seq, time and floor_normal).
func capture_pose() -> Dictionary:
	if not configured: return {}
	return {"transform":actor.transform,"velocity":actor.velocity,"grounded":motion.grounded,"yaw":motion.yaw,"acceleration":motion.acceleration,"reset_epoch":reset_epoch,"local_tick":local_tick,"anchor":actor.global_position+ANCHOR_OFFSET,"flop":clampi(ceili(motion.flop_left*100.0),0,255)}

func dispose() -> void:
	if is_instance_valid(actor):
		actor.collision_layer=_previous_layers
		actor.collision_mask=_previous_mask
	configured=false
	active=false
	shared_playing=false
	waiting_for_partner=false
	holding=true
	jump_pending=0
	dash_pending=0
	local_tick=0
	lifetime={}
	reset_epoch=-1
	observed_epoch=-1
	run=null
	actor=null
	motion=null
