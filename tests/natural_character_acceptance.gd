extends Node

# Presentation evidence through the same production controller/physics loop.
# Each athlete has one continuous locomotion scene and one dribbling scene;
# only those explicit setup boundaries reposition bodies or the ball.
const ATHLETES := 6
const MOTION_SECONDS := 5.0
const DRIBBLE_SECONDS := 2.5
const BASELINE_RUN := "run_1792009540985_5a381eeb9afa4682a049f761fcf7cedb"
var game: Node3D
var actor: FootballPlayer
var movement := Vector2.ZERO
var sprinting := false
var actions: Dictionary = {}
var stage := -1
var athlete_index := 0
var elapsed := 0.0
var total_elapsed := 0.0
var evidence_dir := ""
var checks: Dictionary = {}
var observations: Array[Dictionary] = []
var trace: Array[Dictionary] = []
var contacts: Array[Dictionary] = []
var screenshots: Array[String] = []
var motion_frames: Array[String] = []
var frame_metadata: Array[Dictionary] = []
var captured: Dictionary = {}
var phase_data: Dictionary = {}
var previous_positions: Dictionary = {}
var previous_stances: Dictionary = {}
var maximum_stance_slip := 0.0
var minimum_stance_height := 100.0
var maximum_stance_height := -100.0
var planted_samples := 0
var maximum_player_speed := 0.0
var finite := true
var continuous := true
var referee_start_clock := 0.0
var trace_remaining := 0.0
var frame_remaining := 0.0
var frame_index := 0
var finished := false

func begin(node: Node3D) -> void:
	game = node
	process_priority = 50
	evidence_dir = OS.get_environment("BASED_FOOTBALL_EVIDENCE")
	referee_start_clock = game.referee.clock
	for i in range(game.players.size()):
		var player: FootballPlayer = game.players[i]
		player.ai_rng.seed = 261014 + i
		player.dribble_contact.connect(_on_touch.bind(player))
	game.team_coordinator.rng.seed = 261014
	game.referee.rng.seed = 261014
	_next()
	print("NATURAL_CHARACTER_SESSION_STARTED: six athletes, production controller/referee/physics, continuous rendered movement")

func _dribble_scene() -> bool:
	return stage % 2 == 1

func _activity() -> String:
	if _dribble_scene():
		return "dribble_jog" if elapsed < .8 else "dribble_sprint" if elapsed < 1.9 else "dribble_turn"
	return "stand" if elapsed < .5 else "walk" if elapsed < 1.4 else "jog" if elapsed < 2.3 else "sprint" if elapsed < 3.4 else "turn" if elapsed < 4.4 else "stop"

func _view() -> String:
	var activity := _activity()
	return "profile" if activity in ["walk", "sprint"] else "front" if activity == "jog" else "angled"

func _next() -> void:
	stage += 1
	if stage >= ATHLETES * 2:
		_finish()
		return
	athlete_index = stage / 2
	elapsed = 0
	movement = Vector2.ZERO
	sprinting = false
	actions = {}
	captured.clear()
	previous_positions.clear()
	previous_stances.clear()
	phase_data = {"contacts": 0, "cycles": [], "cycle": {}, "minimum_speed": 100.0, "maximum_speed": 0.0, "activities": {}, "maximum_stance_slip": 0.0, "planted_samples": 0}
	game.reset_positions(0)
	game.goal_flow.active = false
	game.goal_flow.state = ""
	game.kickoff_remaining = 0
	game.phase = "playing"
	game.remaining = 600
	game.charging = false
	game.delivery_kind = ""
	game.team_coordinator.remaining = 0
	game.team_coordinator.chasers.clear()
	game.team_coordinator.roles.clear()
	game.team_coordinator.possession_team = -1
	game.referee.mark_state = ""
	game.referee.advantage.clear()
	game.referee.yellow.clear()
	game.referee.warnings.clear()
	actor = game.players[athlete_index]
	# Normal selection deliberately permits only the home team. Test setup
	# selects each opponent as the driver actor without modifying that UI rule.
	game.controlled = actor
	game.selected_index = athlete_index
	FootballAI.release_control(actor)
	var direction := 1.0 if actor.team == 0 else -1.0
	for i in range(game.players.size()):
		var player: FootballPlayer = game.players[i]
		player.reset_action()
		player.freeze = player != actor
		player.selected = player == actor
		player.global_position = Vector3(-direction * 13, .02, -9 + i * 3)
		player.linear_velocity = Vector3.ZERO
		player.angular_velocity = Vector3.ZERO
		player.intent = Vector3.ZERO
		player.sprint = false
		player.sent_off = false
		player.energy = 1
		player.emotion = ""
		player.aim = Vector3(direction, 0, 0)
		player.body_visual.rotation = Vector3(0, -direction * PI / 2, 0)
		player.body_visual.position = Vector3.ZERO
		player.kick_cooldown = 0
		player.touch_cooldown = 0
		player.incoming_pass_remaining = 0
		player.tactical_role = ""
		player.reaction_timer = 0
	actor.global_position = Vector3(-direction * 8, .02, 0)
	game.ball.freeze = not _dribble_scene()
	game.ball.global_position = actor.global_position + Vector3(direction * .55, .11, .12) if _dribble_scene() else Vector3(0, .11, 10)
	game.ball.linear_velocity = Vector3.ZERO
	game.ball.angular_velocity = Vector3.ZERO
	game.ball.last_touch_id = actor.player_id
	game.ball.last_touch_team = actor.team
	game.ball.control_block_remaining = 0
	game.ball.control_block_player_id = ""
	game.ball.control_candidate_id = ""
	game.previous_ball_position = game.ball.global_position
	game.referee.actor.global_position = Vector3(0, .02, 8)
	game.referee.actor.linear_velocity = Vector3.ZERO
	game.referee.actor.reset_action()
	for player in game.players:
		player.reset_physics_interpolation()
		previous_positions[player.player_id] = player.global_position
	game.ball.reset_physics_interpolation()
	game.hud.flash("%s / %s" % [actor.player_name, "TOUCH AHEAD" if _dribble_scene() else "NATURAL MOVEMENT"], 2)
	print("NATURAL_CHARACTER_PHASE: %s / %s" % [actor.player_id, "dribble" if _dribble_scene() else "locomotion"])

func decide(_delta: float) -> void:
	actions = {}
	movement = Vector2.ZERO
	sprinting = false
	if finished:
		return
	var direction := 1.0 if actor.team == 0 else -1.0
	match _activity():
		"walk":
			movement = Vector2(direction * .35, 0)
		"jog", "dribble_jog":
			movement = Vector2(direction, 0)
		"sprint", "dribble_sprint":
			movement = Vector2(direction, 0)
			sprinting = true
		"turn":
			movement = Vector2(direction * .2, -.8).normalized()
		"dribble_turn":
			movement = Vector2(direction, -.3).normalized()

func _physics_process(delta: float) -> void:
	if finished or game == null:
		return
	elapsed += delta
	total_elapsed += delta
	_observe(delta)
	if elapsed >= (DRIBBLE_SECONDS if _dribble_scene() else MOTION_SECONDS):
		_conclude()
		_next()

func _observe(delta: float) -> void:
	finite = finite and game.ball.global_position.is_finite() and game.ball.linear_velocity.is_finite()
	for player in game.players:
		finite = finite and player.global_position.is_finite() and player.linear_velocity.is_finite()
		maximum_player_speed = maxf(maximum_player_speed, player.linear_velocity.length())
		continuous = continuous and player.global_position.distance_to(previous_positions[player.player_id]) < .5
		previous_positions[player.player_id] = player.global_position
	var speed := Vector3(actor.linear_velocity.x, 0, actor.linear_velocity.z).length()
	phase_data.minimum_speed = minf(float(phase_data.minimum_speed), speed)
	phase_data.maximum_speed = maxf(float(phase_data.maximum_speed), speed)
	phase_data.activities[_activity()] = true
	var visual: FootballPlayerVisual = actor.visual_controller
	for i in range(2):
		var boot: Node3D = visual.left_boot if i == 0 else visual.right_boot
		var planted: bool = visual.planted_feet[i]
		var epoch: int = visual.stance_epochs[i]
		var key := str(i)
		var same_plant: bool = previous_stances.has(key) and previous_stances[key].planted and planted and previous_stances[key].epoch == epoch
		var start: Vector3 = previous_stances[key].start if same_plant else boot.global_position
		if planted:
			planted_samples += 1
			phase_data.planted_samples = int(phase_data.planted_samples) + 1
			var drift := ((boot.global_position - start) * Vector3(1, 0, 1)).length()
			maximum_stance_slip = maxf(maximum_stance_slip, drift)
			phase_data.maximum_stance_slip = maxf(float(phase_data.maximum_stance_slip), drift)
			minimum_stance_height = minf(minimum_stance_height, boot.global_position.y - actor.global_position.y)
			maximum_stance_height = maxf(maximum_stance_height, boot.global_position.y - actor.global_position.y)
		previous_stances[key] = {"epoch": epoch, "planted": planted, "start": start}
	if _dribble_scene() and not phase_data.cycle.is_empty():
		var cycle: Dictionary = phase_data.cycle
		var gap: float = ((game.ball.global_position - actor.global_position) * Vector3(1, 0, 1)).length()
		cycle.peak_gap = maxf(float(cycle.peak_gap), gap)
		if gap < float(cycle.peak_gap) - .1:
			cycle.caught_up = true
		cycle.free_samples = int(cycle.free_samples) + 1
		cycle.free_distance = maxf(float(cycle.free_distance), game.ball.global_position.distance_to(cycle.ball_start))
	trace_remaining -= delta
	if trace_remaining <= 0:
		trace_remaining = .05
		var pose: Dictionary = visual.pose_snapshot(actor)
		trace.append({"actor": actor.player_id, "team": actor.team, "scene": "dribble" if _dribble_scene() else "locomotion", "activity": _activity(), "view": _view(), "time": elapsed, "total_time": total_elapsed, "root": game._vec(actor.global_position), "velocity": game._vec(actor.linear_velocity), "ball": game._vec(game.ball.global_position), "ball_velocity": game._vec(game.ball.linear_velocity), "pose": pose, "feet": [game._vec(visual.left_boot.global_position), game._vec(visual.right_boot.global_position)], "stance_anchors": [game._vec(visual.stance_anchors[0]), game._vec(visual.stance_anchors[1])], "stance_epochs": visual.stance_epochs.duplicate(), "planted": visual.planted_mask(), "step_interval": visual.gait_step_interval, "stride_length": visual.gait_stride_length, "dribble_technique": actor.dribble_technique, "referee_clock": game.referee.clock})

func _on_touch(player: FootballPlayer) -> void:
	if finished or not _dribble_scene() or player != actor:
		return
	phase_data.contacts = int(phase_data.contacts) + 1
	var boot: Node3D = player.visual_controller.right_boot if player.dribble_right else player.visual_controller.left_boot
	contacts.append({"actor": player.player_id, "time": elapsed, "technique": player.dribble_technique, "ball": game._vec(game.ball.global_position), "boot": game._vec(boot.global_position), "boot_sweep_start": game._vec(player.last_dribble_boot)})
	var cycle: Dictionary = phase_data.cycle
	if not cycle.is_empty():
		cycle.end = elapsed
		phase_data.cycles.append(_serializable(cycle))
	var gap: float = ((game.ball.global_position - actor.global_position) * Vector3(1, 0, 1)).length()
	phase_data.cycle = {"start": elapsed, "end": elapsed, "peak_gap": gap, "caught_up": false, "free_samples": 0, "free_distance": 0.0, "ball_start": game.ball.global_position}

func _conclude() -> void:
	var prefix := actor.player_id + ("_dribble" if _dribble_scene() else "_locomotion")
	checks[prefix + "_support_sampled"] = int(phase_data.planted_samples) > 30
	checks[prefix + "_planted_slip_below_5_5_cm"] = float(phase_data.maximum_stance_slip) < .055
	if _dribble_scene():
		var catchups := 0
		for cycle in phase_data.cycles:
			if cycle.caught_up and cycle.free_samples >= 6 and cycle.free_distance > .35:
				catchups += 1
		checks[prefix + "_actual_foot_contacts"] = int(phase_data.contacts) >= 3
		checks[prefix + "_free_ball_travel_and_catchup"] = catchups >= 2
		phase_data["catchup_cycles"] = catchups
	else:
		checks[prefix + "_walk_jog_sprint_turn_stop_exercised"] = phase_data.activities.size() == 6 and float(phase_data.maximum_speed) > 5
		checks[prefix + "_physical_stop"] = Vector3(actor.linear_velocity.x, 0, actor.linear_velocity.z).length() < .7
	observations.append({"actor": actor.player_id, "team": actor.team, "scene": "dribble" if _dribble_scene() else "locomotion", "duration": elapsed, "data": _serializable(phase_data)})

func _serializable(value: Variant) -> Variant:
	if value is Vector3:
		return game._vec(value)
	if value is Dictionary:
		var dictionary: Dictionary = {}
		for key in value:
			dictionary[key] = _serializable(value[key])
		return dictionary
	if value is Array:
		var items: Array = []
		for item in value:
			items.append(_serializable(item))
		return items
	return value

func _process(delta: float) -> void:
	if finished or game == null:
		return
	var direction := 1.0 if actor.team == 0 else -1.0
	var focus := actor.global_position + Vector3.UP * .75
	var view := _view()
	var offset := Vector3(0, 1.0, 5.5) if view == "profile" else Vector3(direction * 5.5, .8, 0) if view == "front" else Vector3(direction * 3.5, 1.8, 4.5)
	game.camera.size = 3.6 if not _dribble_scene() else 4.6
	game.camera.position = focus + offset
	game.camera.look_at(focus)
	frame_remaining -= delta
	if frame_remaining > 0:
		return
	frame_remaining = .1
	var filename := "character_%04d.png" % frame_index
	frame_index += 1
	if get_viewport().get_texture().get_image().save_png(evidence_dir.path_join(filename)) == OK:
		screenshots.append(filename)
		motion_frames.append(filename)
		frame_metadata.append({"filename": filename, "actor": actor.player_id, "activity": _activity(), "view": view, "time": elapsed, "total_time": total_elapsed})
	var label := _activity() + "_" + view
	# Mid-action stills accompany the uncut frame sequence; capture once per view.
	var activity_started: float = .0 if _activity() == "stand" else .5 if _activity() == "walk" else 1.4 if _activity() == "jog" else 2.3 if _activity() == "sprint" else 3.4 if _activity() == "turn" else 4.4
	if _dribble_scene():
		activity_started = .0 if elapsed < .8 else .8 if elapsed < 1.9 else 1.9
	if not captured.has(label) and elapsed > activity_started + .25:
		captured[label] = true
		var still := "athlete_%d_%s.png" % [athlete_index, label]
		checks["capture_" + actor.player_id + "_" + label] = get_viewport().get_texture().get_image().save_png(evidence_dir.path_join(still)) == OK
		screenshots.append(still)

func _finish() -> void:
	finished = true
	set_physics_process(false)
	checks["production_match_physics_and_driver_active"] = game.is_physics_processing() and game.decision_driver == self
	checks["production_referee_active"] = game.referee.clock > referee_start_clock + 30
	checks["hardware_input_disabled"] = not game.is_processing_unhandled_input()
	checks["all_six_athletes_recorded"] = observations.size() == ATHLETES * 2
	checks["physics_finite_and_bounded"] = finite and maximum_player_speed < 20
	checks["body_continuity_without_teleport_during_scenes"] = continuous
	checks["planted_feet_grounded"] = minimum_stance_height > -.02 and maximum_stance_height < .18
	checks["continuous_rendered_frame_sequence"] = motion_frames.size() >= 300
	var report := {"pass": not checks.values().has(false), "checks": checks, "scope": "One six-athlete, two-team production-loop presentation sequence. Standing/walk/jog/sprint/turn/stop and touch-ahead running retain normal rigid-body/referee processing. Close front/profile/angled views and planted ankle/pose traces support human visual comparison; numerical checks do not establish natural appearance or controller feel.", "seconds": total_elapsed, "screenshots": screenshots, "motion_frames": motion_frames, "frame_metadata": frame_metadata, "observations": observations, "contacts": contacts, "metrics": {"maximum_stance_slip_within_one_plant": maximum_stance_slip, "minimum_planted_ankle_height": minimum_stance_height, "maximum_planted_ankle_height": maximum_stance_height, "planted_samples": planted_samples, "maximum_player_speed": maximum_player_speed}, "baseline_run": BASELINE_RUN, "baseline_execution_repeated": false, "hardware_input_injected": false, "subjective_visual_quality_verified": false, "subjective_feel_verified": false}
	var file := FileAccess.open(evidence_dir.path_join("scene-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	file = FileAccess.open(evidence_dir.path_join("character-trace.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(trace))
	file.close()
	print("NATURAL_CHARACTER_SESSION_RESULT: " + JSON.stringify({"pass": report.pass, "checks": checks, "seconds": total_elapsed}))
	get_tree().quit(0 if report.pass else 1)
