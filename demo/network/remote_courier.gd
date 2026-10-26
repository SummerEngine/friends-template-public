extends RefCounted
## The other player's courier on a replica client, drawn from the poses the authority relays: arrival-clock mapping, a short
## back time, interpolation inside the bracket and bounded extrapolation past the newest pose. Only a pose of the current
## epoch is accepted; the epoch is set explicitly by the owner of this object.
const Wire = preload("res://network/owner_pose_wire.gd")
const BACK_TIME := 0.05 ## seconds behind the newest pose; owners send at 60 Hz
const OFFSET_SAMPLES := 60
const MAX_STATES := 120
const MAX_EXTRAPOLATION := 0.1 ## seconds of velocity extrapolation past the newest pose before holding
const FOLLOW := 0.85 ## share of the way from the displayed pose to the target taken per sample
var back_time := BACK_TIME ## widened by the client when the authority thins the relay
var epoch := -1
var states: Array[Dictionary] = [] # descending timestamp
var offsets: Array[float] = []
var mean_offset := 0.0
var latest_seq := 0
var last_arrival := -1.0
var metrics := {"received":0,"rejected":0,"samples":0,"underruns":0,"extrapolated":0,"held":0}

func reset(reset_epoch: int) -> bool:
	if reset_epoch<1 or reset_epoch<epoch: return false
	if reset_epoch==epoch: return true # Repeated shared snapshots cannot flush.
	epoch=reset_epoch
	states.clear()
	offsets.clear()
	mean_offset=0.0
	latest_seq=0
	last_arrival=-1.0
	metrics={"received":0,"rejected":0,"samples":0,"underruns":0,"extrapolated":0,"held":0}
	return true

func receive(frame: Dictionary, arrival_real_seconds: float) -> bool:
	if epoch<1 or not Wire.valid(frame) or frame.reset_epoch!=epoch or not is_finite(arrival_real_seconds) or arrival_real_seconds<0.0 or arrival_real_seconds<last_arrival:
		metrics.rejected+=1
		return false
	if frame.seq<=latest_seq-MAX_STATES:
		metrics.rejected+=1
		return false
	for state: Dictionary in states:
		if state.seq==frame.seq:
			metrics.rejected+=1
			return false
	# The clock offset is sampled from every pose that is newer than the newest one held.
	if states.size()<=1 or frame.time>float(states[0].time):
		offsets.append(float(frame.time)-arrival_real_seconds)
		if offsets.size()>OFFSET_SAMPLES: offsets.pop_front()
		var total := 0.0
		for offset: float in offsets: total+=offset
		mean_offset=total/float(offsets.size())
	var index := 0
	while index<states.size() and float(states[index].time)>float(frame.time): index+=1
	states.insert(index,frame.duplicate(true))
	if states.size()>MAX_STATES: states.pop_back()
	latest_seq=maxi(latest_seq,frame.seq)
	last_arrival=arrival_real_seconds
	metrics.received+=1
	return true

## The pose to display now, or {} while there is not enough history. `current` = {transform} of the displayed courier.
func sample(local_real_seconds: float, current: Dictionary) -> Dictionary:
	if epoch<1 or states.size()<2 or offsets.is_empty() or not is_finite(local_real_seconds) or local_real_seconds<last_arrival or not Wire.rigid_unit(current.get("transform")):
		metrics.underruns+=1
		return {}
	var target := local_real_seconds+mean_offset-back_time
	if target<float(states[-1].time):
		metrics.underruns+=1
		return {} # Startup before the oldest pose is never guessed.
	var newest: Dictionary=states[0]
	var older: Dictionary=newest
	var newer: Dictionary=newest
	var target_position: Vector3
	var target_rotation: Quaternion
	var weight := 0.0
	var newest_transform: Transform3D=newest.transform
	if target>=float(newest.time):
		var ahead := minf(target-float(newest.time),MAX_EXTRAPOLATION)
		if target-float(newest.time)>MAX_EXTRAPOLATION: metrics.held+=1
		else: metrics.extrapolated+=1
		target_position=newest_transform.origin+Vector3(newest.velocity.x,0.0,newest.velocity.z)*ahead
		target_rotation=newest_transform.basis.get_rotation_quaternion()
	else:
		var older_index := 0
		while older_index<states.size()-1 and target<float(states[older_index].time): older_index+=1
		older=states[older_index]
		newer=states[maxi(older_index-1,0)]
		var gap := float(newer.time)-float(older.time)
		weight = 1.0 if gap<=0.0 else clampf((target-float(older.time))/gap,0.0,1.0)
		var older_transform: Transform3D=older.transform
		var newer_transform: Transform3D=newer.transform
		target_position=older_transform.origin.lerp(newer_transform.origin,weight)
		target_rotation=older_transform.basis.get_rotation_quaternion().slerp(newer_transform.basis.get_rotation_quaternion(),weight)
	var displayed: Transform3D=current.transform
	var position := displayed.origin.lerp(target_position,FOLLOW)
	var rotation := displayed.basis.get_rotation_quaternion().slerp(target_rotation,FOLLOW)
	var result := older.duplicate(true)
	result.time=target
	result.transform=Transform3D(Basis(rotation),position)
	result.velocity=older.velocity.lerp(newer.velocity,weight)
	result.anchor=older.anchor.lerp(newer.anchor,weight)
	metrics.samples+=1
	return result
