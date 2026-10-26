extends RefCounted
## Explicit local test opt-in. Uses the same input stream and matchmaking as
## people; never supplies identity, tickets, transforms or authority commands.
const DevEnv := preload("res://dev_env.gd")
const CONFIG := "user://gw-private-qa.json"
var enabled := false
var test_id := ""
var steps: Array = []
var clock := 0.0
var next_report := 0.0
var next_capture := 0
var capture_times := [1.0,3.0,6.0,10.0,15.0,22.0]
var capture_pending := false
var camera_applied := false
var pitch_degrees := -30.0
var scenario := "steps"
var next_boot_report := 0.0
var next_boot_capture := 0
var boot_capture_times := [2.0,10.0,20.0,40.0,80.0,120.0]
var boot_started_ms := Time.get_ticks_msec()
var join_events: Array[Dictionary] = []
var latest_join_progress := {}

func _init() -> void:
	if not DevEnv.is_dev() or not FileAccess.file_exists(CONFIG): return
	var file := FileAccess.open(CONFIG,FileAccess.READ)
	if file == null or file.get_length()>8192: return
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not value is Dictionary or value.get("schema",0)!=1 or value.get("enabled",false)!=true: return
	if not value.get("test_id") is String or not value.get("steps") is Array: return
	test_id = str(value.test_id)
	if test_id.length()<1 or test_id.length()>64 or test_id!=test_id.validate_filename(): return
	if value.steps.size()>64: return
	scenario = str(value.get("scenario","steps"))
	if scenario != "steps": return
	var previous := -1.0
	for step: Variant in value.steps:
		if not step is Dictionary or not step.get("move") is Array or step.move.size()!=2: return
		var after := float(step.get("after_s",-1))
		if not is_finite(after) or after<0 or after>180 or after<=previous: return
		for axis: Variant in step.move:
			if not (axis is float or axis is int) or not is_finite(float(axis)) or absf(float(axis))>1: return
		previous = after
		steps.append({"after_s":after,"move":[float(step.move[0]),float(step.move[1])]})
	pitch_degrees = clampf(float(value.get("camera_pitch_degrees",-30)),-89.9,89.9)
	if not is_finite(pitch_degrees): return
	# One launch only. A later human launch must start in the ordinary menu.
	if DirAccess.rename_absolute(CONFIG,"user://gw-private-qa-consumed-%s.json" % test_id)!=OK: return
	enabled = true
	print("GW_PRIVATE_QA_ENABLED test=",test_id," inputs_only=true")

func next_input(snapshot: Dictionary, delta: float, seat := -1, echo_seconds := 0.0) -> Dictionary:
	if bool(snapshot.get("playing",false)) and not bool(snapshot.get("waiting_for_partner",false)):
		clock += delta
	var move := [0.0,0.0]
	for step: Dictionary in steps:
		if clock>=float(step.after_s): move = step.move
	if clock>180 or bool(snapshot.get("broken",false)) or bool(snapshot.get("won",false)): move = [0.0,0.0]
	var facing := 0.0
	var players: Array = snapshot.get("players",[])
	if seat>=0 and seat<players.size(): facing = float(players[seat].get("movement",{}).get("yaw",0.0))
	if Vector2(move[0],move[1]).length_squared()>0: facing = atan2(-move[0],-move[1])
	return {"move":move,"jump":false,"height":0.0,"roll":0.0,"restart":false,"facing":facing}

static func _v(vector: Vector3) -> Array:
	return [vector.x,vector.y,vector.z]

func note_join(event: String, safe_fields: Dictionary = {}) -> void:
	if not enabled: return
	if event=="progress":
		latest_join_progress=safe_fields.duplicate(true)
		if not join_events.is_empty() and join_events[-1].event=="progress":
			var previous: Dictionary=join_events[-1]
			if previous.get("stage")==safe_fields.get("stage") and previous.get("attempt")==safe_fields.get("attempt") and previous.get("region")==safe_fields.get("region") and previous.get("resumed")==safe_fields.get("resumed"): return
	var row := safe_fields.duplicate(true)
	row.event=event
	row.at_unix_ms=int(Time.get_unix_time_from_system()*1000)
	row.boot_elapsed_s=(Time.get_ticks_msec()-boot_started_ms)*.001
	join_events.append(row)
	if join_events.size()>32: join_events.pop_front()

func observe_connection(client: Node) -> void:
	if not enabled: return
	var elapsed := (Time.get_ticks_msec()-boot_started_ms)*.001
	if elapsed>=next_boot_report:
		next_boot_report=elapsed+1.0
		# No host context or credential objects are serialized: only the game's UI
		# and ordinary lifecycle flags, including failures before World admission.
		var status := str(client.message.text).left(512) if client.message!=null else ""
		var ready: bool = client.simulation!=null and client.simulation.is_network_ready()
		var report := {"test_id":test_id,"boot_elapsed_s":elapsed,"process_frame":Engine.get_process_frames(),"summer_ready":client.summer_ready,"simulation_ready":ready,"searching":client.searching,"joined":client.joined,"seat":client.my_seat,"world_id":client.last_world_id,"snapshot_count":client.snapshot_count,"status":status}
		report.join_events=join_events.duplicate(true)
		report.join_progress=latest_join_progress.duplicate(true)
		_write_json("user://gw-private-qa-boot.json",report)
	if next_boot_capture<boot_capture_times.size() and elapsed>=boot_capture_times[next_boot_capture] and not capture_pending and DisplayServer.get_name()!="headless":
		capture_pending=true
		_capture.call_deferred(client,200+next_boot_capture)
		next_boot_capture+=1

func observe(client: Node) -> void:
	if not enabled: return
	if not camera_applied and client.connected_seconds>1.0:
		client.simulation.pitch = deg_to_rad(pitch_degrees)
		camera_applied = true
	if clock>=next_report:
		next_report = clock+0.5
		_write_report(client)
	if next_capture<capture_times.size() and clock>=capture_times[next_capture] and not capture_pending and DisplayServer.get_name()!="headless":
		capture_pending = true
		_capture.call_deferred(client,next_capture)
		next_capture += 1

func _write_report(client: Node) -> void:
	var state: Dictionary = client.latest_snapshot
	var server_positions := []
	for player: Dictionary in state.get("players",[]): server_positions.append(_v(player.position))
	var replica_positions := []
	for actor: Node3D in client.simulation.actors: replica_positions.append(_v(actor.position))
	var report := {"test_id":test_id,"elapsed_s":clock,"seat":client.my_seat,"world_id":client.last_world_id,"server_tick":state.get("tick",-1),"process_frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames(),"snapshot_count":client.snapshot_count,"server_positions":server_positions,"replica_positions":replica_positions,"pane_position":_v(client.simulation.painting.global_position),"broken":state.get("broken",false),"resets":state.get("resets",-1),"input_echo_ms":client.input_echo_msec,"fps":Engine.get_frames_per_second(),"own_input":client.current_input.get("move",[0,0])}
	report.scenario = scenario
	report.input_sequences = state.get("input_sequences",[])
	_write_json("user://gw-private-qa-state.json",report)
	print("GW_PRIVATE_QA_STATE ",JSON.stringify(report))

func _write_json(path: String, report: Dictionary) -> void:
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report)); file.close()
		DirAccess.rename_absolute(path+".tmp",path)

func _capture(client: Node, index: int) -> void:
	await RenderingServer.frame_post_draw
	if not is_instance_valid(client): return
	var path := "user://gw-private-qa-%s-%02d.png" % [test_id,index]
	var error := client.get_viewport().get_texture().get_image().save_png(path)
	print("GW_PRIVATE_QA_CAPTURE test=",test_id," index=",index," frame=",Engine.get_process_frames()," error=",error)
	capture_pending = false
