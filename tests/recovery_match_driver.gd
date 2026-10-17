extends Node

## Test-only controller for ONE ordinary 180-second historical match. Decisions
## read current visible state and use the existing controller dictionary/helper.
## No RNG reseeding, body/ball writes, clock edits or renderer readbacks.

const PALETTE := [Color("24d3c8"), Color("ff9d3c"), Color("d346d1"), Color("a8e043")]
const MAX_WALL_SECONDS := 300.0
const MAX_ACTION_SECONDS := 240.0
var game: Node3D
var session := ""
var token := ""
var identities: Array = []
var movement := Vector2.ZERO
var sprinting := false
var actions: Dictionary = {}
var scene_ready := false
var started := false
var finished := false
var start_us := 0
var finish_us := 0
var initialized_us := 0
var physics_frames := 0
var finish_frame := 0
var think_remaining := 0.0
var switch_remaining := 0.0
var next_action_at := 0.0
var shot_release_at := -1.0
var stop_until := 0.0
var stop_requested := false
var decisions := 0
var pass_requests := 0
var shot_requests := 0
var switches := 0
var sprint_seconds := 0.0
var moving_seconds := 0.0
var turns := 0
var stops := 0
var controlled_passes := 0
var controlled_shots := 0
var controlled_touches := 0
var ai_strikes := 0
var ai_touches := 0
var opponent_contacts := 0
var final_exit_code := 1
var finite := true
var max_speed := 0.0
var previous_speed := 0.0
var stop_hold := 0.0
var stop_counted := true
var heading_checkpoints: Dictionary = {}
var previous_controlled_id := ""
var fps_samples: Array[float] = []
var telemetry: FileAccess
var event_file: FileAccess
var sample_clock := 0.0
var marker: ColorRect
var identity_cells: Array[ColorRect] = []
var frame_cells: Array[ColorRect] = []
var status: Label
var bad_start_reported := false

func configure(match_node: Node3D, directory: String, request: Dictionary) -> void:
	game = match_node
	session = directory
	token = str(request.capture_token)
	identities = request.identity_phases
	initialized_us = Time.get_ticks_usec()
	process_physics_priority = -100

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	marker = _rect(layer, Vector2(1120,22), Vector2(100,28), PALETTE[0])
	for index in range(12):
		identity_cells.append(_rect(layer, Vector2(1120+index*8,58), Vector2(8,12), PALETTE[int(identities[index])]))
		frame_cells.append(_rect(layer, Vector2(1120+index*8,82), Vector2(8,12), PALETTE[0]))
	status = Label.new()
	status.position = Vector2(20, 740)
	status.add_theme_font_size_override("font_size", 14)
	status.add_theme_color_override("font_color", Color.WHITE)
	status.text = "RECOVERED 2d5d7ad / recording preflight / ordinary initial fixture held"
	layer.add_child(status)
	telemetry = FileAccess.open(session.path_join("telemetry.jsonl"), FileAccess.WRITE)
	event_file = FileAccess.open(session.path_join("events.jsonl"), FileAccess.WRITE)

func _rect(parent: Node, position: Vector2, size: Vector2, color: Color) -> ColorRect:
	var result := ColorRect.new()
	result.position = position
	result.size = size
	result.color = color
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

func bind_match() -> void:
	game.match_finished.connect(_match_finished, CONNECT_ONE_SHOT)
	for player in game.players:
		player.strike_contact.connect(_strike.bind(player))
		player.dribble_contact.connect(_touch.bind(player))
		player.physical_event.connect(_physical.bind(player))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if telemetry == null or event_file == null:
		_infrastructure_failure("Could not create evidence streams.")
		return
	scene_ready = true
	_write("ready.json", {"scene":"recovery_full_match", "game_ready":true, "capture_token":token,
		"identity_phases":identities, "hwnd":str(DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)),
		"viewport":[1280,800], "marker_rect":[1120,22,100,28], "identity_rect":[1120,58,96,12], "frame_rect":[1120,82,96,12],
		"physics_hz":Engine.physics_ticks_per_second, "planned_match_clock_seconds":180, "max_wall_seconds":MAX_WALL_SECONDS,
		"executable_path":OS.get_executable_path(), "pack_path":OS.get_executable_path().get_base_dir().path_join("BasedFootball.pck"), "career_save":game.squad.save_path,
		"user_data_dir":OS.get_user_data_dir(), "custom_user_dir":ProjectSettings.get_setting("application/config/custom_user_dir_name", ""),
		"source_paths":["scripts","scenes","data","assets","project.godot","tests/recovery_runner.gd","tests/recovery_match_driver.gd"],
		"fixture":"unchanged production initial kickoff; no tester resets or injected outcomes"})
	print("RECOVERY_MATCH_READY ", token)

func _process(delta: float) -> void:
	var seconds := float(Time.get_ticks_usec() - (start_us if started else initialized_us)) / 1000000.0
	marker.color = PALETTE[int(seconds*2.0)%4]
	frame_cells[0].color = PALETTE[2 if finished else 1 if started else 0]
	var count := finish_frame if finished else physics_frames
	for index in range(11):
		frame_cells[index+1].color = PALETTE[(count>>(index*2))&3]
	if started and not finished:
		fps_samples.append(1.0 / maxf(delta, .000001))
		status.text = "RECOVERED 2d5d7ad / normal match / pass %d / shot %d / touches %d / %d FPS" % [controlled_passes, controlled_shots, controlled_touches, Engine.get_frames_per_second()]

func _physics_process(delta: float) -> void:
	if finished:
		var held := float(Time.get_ticks_usec()-finish_us)/1000000.0
		if held >= 1.2 and (_token_flag("allowexit.flag") or held >= 20.0):
			get_tree().quit(final_exit_code)
		return
	if not scene_ready:
		return
	if not started:
		if _token_flag("start.flag"):
			started = true
			start_us = Time.get_ticks_usec()
			_write("started.json", {"capture_token":token, "system_time_unix":Time.get_unix_time_from_system(), "physics_frame":Engine.get_physics_frames(), "match_remaining":game.remaining, "phase":game.phase})
			_event("match_started", {"initial_match_remaining":game.remaining,"production_kickoff_remaining":game.kickoff_remaining,"isolated_save":game.squad.save_path})
			get_tree().paused = false
		elif FileAccess.file_exists(session.path_join("start.flag")) and not bad_start_reported:
			bad_start_reported = true
			_write("infrastructure-error.json", {"reason":"start.flag token does not match capture request", "behavior_started":false})
		elif float(Time.get_ticks_usec()-initialized_us)/1000000.0 > 180.0:
			_infrastructure_failure("Recording preflight timed out; match never started.")
		return
	physics_frames += 1
	_monitor(delta)
	sample_clock += delta
	if sample_clock >= .1:
		sample_clock -= .1
		call_deferred("_sample")
	if _wall() > MAX_WALL_SECONDS or float(physics_frames)/Engine.physics_ticks_per_second > MAX_ACTION_SECONDS:
		_finish(false, "Full-time did not occur before the declared safety limit.")

func _token_flag(name: String) -> bool:
	var path := session.path_join(name)
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed is Dictionary and str(parsed.get("capture_token", "")) == token

func decide(delta: float) -> void:
	actions = {}
	if not started or finished:
		movement = Vector2.ZERO
		sprinting = false
		return
	switch_remaining = maxf(0.0, switch_remaining-delta)
	var seconds := float(physics_frames)/Engine.physics_ticks_per_second
	if shot_release_at >= 0.0 and seconds >= shot_release_at:
		actions["primary_release"] = true
		shot_release_at = -1.0
	think_remaining -= delta
	if think_remaining > 0.0:
		return
	think_remaining = .12
	decisions += 1
	var actor: FootballPlayer = game.controlled
	var ball: FootballBall = game.ball
	var nearest: FootballPlayer = actor
	for teammate: FootballPlayer in game.players:
		if teammate.team == 0 and teammate.ragdoll == null and teammate.global_position.distance_to(ball.global_position) < nearest.global_position.distance_to(ball.global_position):
			nearest = teammate
	if nearest != actor and switch_remaining <= 0.0 and not game.charging and (actor.ragdoll != null or actor.global_position.distance_to(ball.global_position) > 2.4):
		game._switch_player(_flat(nearest.global_position-actor.global_position).normalized())
		actor = game.controlled
		switches += 1
		switch_remaining = .8
	var offset := _flat(ball.global_position-actor.global_position)
	var goal := _flat(Vector3(18.8,0,0)-actor.global_position)
	var desired := _flat(ball.global_position+ball.linear_velocity*.12-actor.global_position).normalized()
	sprinting = offset.length() > 2.0
	if seconds < stop_until:
		movement = Vector2.ZERO
		sprinting = false
		return
	if game.charging:
		movement = Vector2.ZERO
		sprinting = false
		return
	if game._attacking_contact():
		desired = goal.normalized()
		var danger := INF
		for opponent: FootballPlayer in game.players:
			if opponent.team != actor.team:
				danger = minf(danger, _flat(opponent.global_position-actor.global_position).length())
		sprinting = danger > 2.3 and goal.length() > 7.0
		if not stop_requested and controlled_touches > 0 and seconds > 5.0:
			stop_requested = true
			stop_until = seconds+.45
			movement = Vector2.ZERO
			sprinting = false
			_event("stop_input", {"seconds":.45})
			return
		if actor.kick_cooldown <= 0.0 and actor.action_kind.is_empty() and seconds >= next_action_at:
			var receiver := _receiver(actor)
			if receiver != null and (controlled_passes == 0 or (danger < 1.5 and goal.length() > 9.0)):
				desired = _flat(receiver.global_position-actor.global_position).normalized()
				actions["pass"] = true
				pass_requests += 1
				next_action_at = seconds+2.3
				_event("pass_request", {"player":actor.player_id,"direction":_vec(desired),"recipient_observed":receiver.player_id})
			elif goal.length() < 14.0 or (controlled_shots == 0 and seconds > 35.0):
				desired = goal.normalized()
				actions["primary"] = true
				shot_release_at = seconds+.32
				shot_requests += 1
				next_action_at = seconds+2.3
				_event("shot_request", {"player":actor.player_id,"direction":_vec(desired),"charge_seconds":.32})
	else:
		if ball.last_touch_team == 1 and offset.length() < .95 and actor.tackle_cooldown <= 0.0 and seconds >= next_action_at:
			actions["primary"] = true
			next_action_at = seconds+.8
	movement = Vector2(desired.x, desired.z)

func _receiver(actor: FootballPlayer) -> FootballPlayer:
	var best: FootballPlayer
	var best_score := -INF
	for teammate: FootballPlayer in game.players:
		if teammate == actor or teammate.team != actor.team or teammate.ragdoll != null:
			continue
		var offset := _flat(teammate.global_position-actor.global_position)
		if offset.length() < 2.0:
			continue
		var clearance := 20.0
		for opponent: FootballPlayer in game.players:
			if opponent.team != actor.team:
				clearance = minf(clearance, _flat(opponent.global_position-teammate.global_position).length())
		var score := clearance + clampf(offset.x, -5.0, 5.0)*.2-offset.length()*.08
		if score > best_score:
			best_score = score
			best = teammate
	return best

func _monitor(delta: float) -> void:
	for player: FootballPlayer in game.players:
		finite = finite and player.global_position.is_finite() and player.linear_velocity.is_finite()
	finite = finite and game.ball.global_position.is_finite() and game.ball.linear_velocity.is_finite()
	var actor: FootballPlayer = game.controlled
	var velocity := _flat(actor.linear_velocity)
	var speed := velocity.length()
	max_speed = maxf(max_speed, speed)
	if speed > .5:
		moving_seconds += delta
	if sprinting and speed > 4.5:
		sprint_seconds += delta
	if actor.player_id != previous_controlled_id:
		previous_speed = speed
		stop_hold = 0.0
		stop_counted = true
		previous_controlled_id = actor.player_id
	if speed > .8:
		stop_counted = false
		stop_hold = 0.0
		var direction := velocity.normalized()
		if not heading_checkpoints.has(actor.player_id):
			heading_checkpoints[actor.player_id] = direction
		elif direction.dot(heading_checkpoints[actor.player_id]) < .5:
			turns += 1
			heading_checkpoints[actor.player_id] = direction
	elif speed < .12 and not stop_counted:
		stop_hold += delta
		if stop_hold > .15:
			stops += 1
			stop_counted = true
	previous_speed = speed

func _sample() -> void:
	if finished or telemetry == null:
		return
	var roster: Array[Dictionary] = []
	for player: FootballPlayer in game.players:
		roster.append({"id":player.player_id,"team":player.team,"position":_vec(player.global_position),"velocity":_vec(player.linear_velocity),"action":player.action_kind,"ragdoll":player.ragdoll!=null,"selected":player==game.controlled})
	telemetry.store_line(JSON.stringify({"physics_frames":physics_frames,"engine_physics_frame":Engine.get_physics_frames(),"sim_seconds":float(physics_frames)/Engine.physics_ticks_per_second,"wall_seconds":_wall(),"remaining":game.remaining,"phase":game.phase,"kickoff_remaining":game.kickoff_remaining,"score":game.scores,"controlled":game.controlled.player_id,"players":roster,"ball":{"position":_vec(game.ball.global_position),"velocity":_vec(game.ball.linear_velocity),"last_touch_id":game.ball.last_touch_id,"last_touch_team":game.ball.last_touch_team},"input":{"movement":[movement.x,movement.y],"sprint":sprinting,"actions":actions},"contacts":{"pass":controlled_passes,"shot":controlled_shots,"touch":controlled_touches,"ai_strikes":ai_strikes,"ai_touches":ai_touches},"fps":Engine.get_frames_per_second()}))
	telemetry.flush()

func _strike(kind: String, player: FootballPlayer) -> void:
	var controlled: bool = player == game.controlled
	if player.team == 1:
		opponent_contacts += 1
	if controlled:
		if kind == "pass": controlled_passes += 1
		if kind == "shot": controlled_shots += 1
	else:
		ai_strikes += 1
	_event("strike_contact", {"kind":kind,"player":player.player_id,"team":player.team,"controlled_at_contact":controlled,"distance":player.last_kick_contact_distance,"ball":_vec(game.ball.global_position)})

func _touch(player: FootballPlayer) -> void:
	if player.team == 1:
		opponent_contacts += 1
	if player == game.controlled:
		controlled_touches += 1
	else:
		ai_touches += 1
	_event("dribble_contact", {"player":player.player_id,"team":player.team,"controlled_at_contact":player==game.controlled,"ball":_vec(game.ball.global_position)})

func _physical(kind: String, detail: Dictionary, player: FootballPlayer) -> void:
	_event(kind, detail.merged({"player":player.player_id,"team":player.team}))

func _event(kind: String, detail: Dictionary) -> void:
	if event_file != null:
		event_file.store_line(JSON.stringify({"kind":kind,"physics_frames":physics_frames,"engine_physics_frame":Engine.get_physics_frames(),"sim_seconds":float(physics_frames)/Engine.physics_ticks_per_second,"wall_seconds":_wall(),"detail":detail}))
		event_file.flush()

func _match_finished() -> void:
	_finish(true, "production match_finished signal")

func _finish(full_time: bool, reason: String) -> void:
	if finished:
		return
	finished = true
	finish_us = Time.get_ticks_usec()
	finish_frame = physics_frames
	movement = Vector2.ZERO
	sprinting = false
	actions = {}
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(game.squad.save_path)) if FileAccess.file_exists(game.squad.save_path) else null
	var progression_ok: bool = saved is Dictionary and int(saved.get("matches",0)) == 1
	if progression_ok:
		for entry: Dictionary in game.squad.entries:
			progression_ok = progression_ok and int(saved.get("xp",{}).get(str(entry.id),0)) > 0
	var sorted_fps := fps_samples.duplicate()
	sorted_fps.sort()
	var median_fps: float = sorted_fps[sorted_fps.size()/2] if not sorted_fps.is_empty() else 0.0
	var checks := {"normal_full_time":full_time and game.phase=="finished" and game.remaining<=0.0 and game.match_count==1,"controller_pass_contact":controlled_passes>0,"controller_shot_contact":controlled_shots>0,"physical_dribble_contacts":controlled_touches>0,"movement_exercised":moving_seconds>5.0,"physical_sprint_exercised":sprint_seconds>1.0,"actual_turn_exercised":turns>0,"actual_stop_exercised":stops>0,"finite_physics":finite,"AI_played_ball":ai_strikes+ai_touches>0,"opponents_played_ball":opponent_contacts>0,"isolated_progression_saved":progression_ok and game.squad.last_error.is_empty()}
	var passed := true
	for value: bool in checks.values(): passed = passed and value
	final_exit_code = 0 if passed else 1
	_event("verification_finished", {"match_full_time":full_time,"reason":reason,"checks":checks})
	if telemetry != null: telemetry.close()
	if event_file != null: event_file.close()
	telemetry = null
	event_file = null
	_write("events.json", {"production_action_log":game.action_log,"controller_decisions":decisions,"pass_requests":pass_requests,"shot_requests":shot_requests})
	_write("result.json", {"schema":"recovered-football-full-match/v1","capture_token":token,"pass":passed,"match_full_time":full_time,"physics_frames":finish_frame,"sim_seconds":float(finish_frame)/Engine.physics_ticks_per_second,"wall_seconds":float(finish_us-start_us)/1000000.0,"final_phase":game.phase,"remaining":game.remaining,"score":game.scores,"match_count":game.match_count,"checks":checks,"controlled_passes":controlled_passes,"controlled_shots":controlled_shots,"controlled_touches":controlled_touches,"ai_strikes":ai_strikes,"ai_touches":ai_touches,"opponent_contacts":opponent_contacts,"movement_seconds":moving_seconds,"physical_sprint_seconds":sprint_seconds,"max_controlled_speed":max_speed,"actual_turns":turns,"actual_stops":stops,"switches":switches,"median_fps":median_fps,"reason":reason,"career_save":game.squad.save_path,"user_data_dir":OS.get_user_data_dir(),"custom_user_dir":ProjectSettings.get_setting("application/config/custom_user_dir_name", ""),"saved_career":saved,"hardware_controller_verified":false,"subjective_fun_verified":false,"tester_fixture_resets":0,"limitations":["Test-only current-state driver uses the historical controller interface, not physical gamepad input.","Production goals and out-of-court rules retain their original centre resets.","Contact and completion checks cannot establish subjective fun or realistic animation.","Required actions not exercised fail coverage; no forced outcomes or retries."]})
	_write("finished.json", {"capture_token":token,"match_full_time":full_time,"physics_frames":finish_frame,"sim_seconds":float(finish_frame)/Engine.physics_ticks_per_second,"wall_seconds":float(finish_us-start_us)/1000000.0,"pass":passed})
	status.text = "RECOVERY VERIFICATION FINISHED / full-time %s / pass %d / shot %d / result %s" % [str(full_time),controlled_passes,controlled_shots,"PASS" if passed else "FAIL"]
	print("RECOVERY_MATCH_FINISHED ",JSON.stringify(checks))

func _infrastructure_failure(reason: String) -> void:
	_write("infrastructure-error.json", {"reason":reason,"behavior_started":started,"capture_token":token})
	get_tree().quit(2)

func _write(name: String, data: Dictionary) -> void:
	var output := FileAccess.open(session.path_join(name), FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(data,"\t"))

func _wall() -> float:
	return float(Time.get_ticks_usec()-start_us)/1000000.0 if started else 0.0

func _flat(value: Vector3) -> Vector3:
	return value*Vector3(1,0,1)

func _vec(value: Vector3) -> Array[float]:
	return [value.x,value.y,value.z]
