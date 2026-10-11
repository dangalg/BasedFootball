extends Node

# One rendered, real-time match. Joypad events exercise the production InputMap.
# Initial kickoff is the normal match fixture; no scripted goals or ball warps.
var game: Node3D
var elapsed: float = 0.0
var next_pass: float = 8.0
var next_switch: float = 12.0
var next_tackle: float = 15.0
var shoot_release_at: float = -1.0
var shots_started: int = 0
var sprint_seconds: float = 0.0
var maximum_ball_speed: float = 0.0
var minimum_player_separation: float = INF
var frames_saved: Array[String] = []
var screenshots_at: Array[float] = [3.0, 24.0, 75.0, 140.0]
var screenshot_index: int = 0
var button_releases: Array[int] = []
var completion_started: bool = false
var time_limit: float = 215.0
var joy_events: int = 0
var evidence_dir: String = ""

func begin(match_node: Node3D) -> void:
	game = match_node
	evidence_dir = OS.get_environment("BASED_FOOTBALL_EVIDENCE")
	if evidence_dir.is_empty():
		evidence_dir = ProjectSettings.globalize_path("res://evidence")
	DirAccess.make_dir_recursive_absolute(evidence_dir)
	process_physics_priority = -100
	game.match_finished.connect(_completed, CONNECT_ONE_SHOT)
	print("ACCEPTANCE_STARTED: one 180-second rendered match; injected joypad events; isolated save")

func _physics_process(delta: float) -> void:
	if game == null or completion_started:
		return
	elapsed += delta
	if elapsed > time_limit:
		_finish({"pass": false, "reason": "Match did not complete within 215 simulation seconds."})
		return
	for button in button_releases:
		_button(button, false)
	button_releases.clear()
	maximum_ball_speed = maxf(maximum_ball_speed, game.ball.linear_velocity.length())
	for i in range(game.players.size()):
		for j in range(i + 1, game.players.size()):
			minimum_player_separation = minf(minimum_player_separation, game.players[i].global_position.distance_to(game.players[j].global_position))
	if screenshot_index < screenshots_at.size() and elapsed >= screenshots_at[screenshot_index]:
		_capture("match_%03d" % int(screenshots_at[screenshot_index]))
		screenshot_index += 1
	if game.phase != "playing" or game.kickoff_remaining > 0:
		return
	var player: FootballPlayer = game.controlled
	var difference: Vector3 = game.ball.global_position - player.global_position
	difference.y = 0
	var target: Vector3 = game.ball.global_position - Vector3(0.65, 0, 0)
	if player.reach_ball(game.ball, 1.25):
		target = Vector3(19, 0, 0)
	var direction: Vector3 = target - player.global_position
	direction.y = 0
	direction = direction.normalized() if direction.length() > 0.2 else Vector3.ZERO
	_axis(JOY_AXIS_LEFT_X, direction.x)
	_axis(JOY_AXIS_LEFT_Y, direction.z)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0 if difference.length() > 3 else 0.0)
	if difference.length() > 3:
		sprint_seconds += delta
	if elapsed >= next_switch:
		_button(JOY_BUTTON_LEFT_SHOULDER, true)
		button_releases.append(JOY_BUTTON_LEFT_SHOULDER)
		next_switch += 20
	if elapsed >= next_tackle and difference.length() < 2.0:
		_button(JOY_BUTTON_X, true)
		button_releases.append(JOY_BUTTON_X)
		next_tackle += 16
	if shoot_release_at > 0 and elapsed >= shoot_release_at:
		_button(JOY_BUTTON_B, false)
		shoot_release_at = -1
	elif shoot_release_at < 0 and player.reach_ball(game.ball) and player.kick_cooldown <= 0 and player.global_position.x > 4:
		_button(JOY_BUTTON_B, true)
		shoot_release_at = elapsed + 0.32
		shots_started += 1
	elif elapsed >= next_pass and player.reach_ball(game.ball) and player.kick_cooldown <= 0:
		_button(JOY_BUTTON_A, true)
		button_releases.append(JOY_BUTTON_A)
		next_pass += 22

func _axis(axis: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	joy_events += 1

func _button(button: int, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	joy_events += 1

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := evidence_dir.path_join("%s.png" % label)
	var result := get_viewport().get_texture().get_image().save_png(path)
	if result == OK:
		frames_saved.append(path)

func _completed() -> void:
	completion_started = true
	_axis(JOY_AXIS_LEFT_X, 0)
	_axis(JOY_AXIS_LEFT_Y, 0)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0)
	_button(JOY_BUTTON_B, false)
	await _capture("full_time")
	var counts := {}
	var ai_actions: int = 0
	var goal_crossings_valid := true
	for event in game.action_log:
		var kind: String = event["kind"]
		if str(event["player"]).begins_with("opponent_") and kind in ["shot", "pass", "touch"]:
			ai_actions += 1
		if event.get("source", "") == "controller":
			counts[kind] = int(counts.get(kind, 0)) + 1
		if kind == "goal":
			var pos: Array = event["ball"]
			goal_crossings_valid = goal_crossings_valid and absf(float(pos[0])) > 18.38 and absf(float(pos[2])) < 2.0 and float(pos[1]) < 2.1
	var save_exists := FileAccess.file_exists(game.squad.save_path)
	var saved = JSON.parse_string(FileAccess.get_file_as_string(game.squad.save_path)) if save_exists else null
	var progression_saved := saved is Dictionary and int(saved.get("matches", 0)) == 1
	if progression_saved:
		for entry in game.squad.entries:
			progression_saved = progression_saved and int(saved["xp"].get(entry["id"], 0)) > 0
	var previous_xp: int = int(game.squad.entries[0]["xp"])
	var final_score: Array = game.scores.duplicate()
	# Rematch through the normal controller confirm action, after full-time signal.
	_button(JOY_BUTTON_A, true)
	await get_tree().process_frame
	_button(JOY_BUTTON_A, false)
	await get_tree().process_frame
	var rematch_ok: bool = game.phase == "playing" and game.controlled.experience == previous_xp and previous_xp > 0
	var checks := {
		"match_completed": game.match_count == 1,
		"controller_switch": int(counts.get("switch", 0)) > 0,
		"successful_pass": int(counts.get("pass", 0)) > 0,
		"successful_shot": int(counts.get("shot", 0)) > 0,
		"tackle": int(counts.get("tackle", 0)) > 0,
		"sprint": sprint_seconds > 1,
		"physical_ball_moved": maximum_ball_speed > 8,
		"players_made_contact": minimum_player_separation < 0.88,
		"ai_played_ball": ai_actions > 0,
		"physical_goal": goal_crossings_valid and int(final_score[0]) + int(final_score[1]) > 0,
		"progression_saved": progression_saved and game.squad.last_error == "",
		"rematch_retains_progression": rematch_ok,
		"rendered_evidence": frames_saved.size() == 5
	}
	var passed := true
	for value in checks.values():
		passed = passed and bool(value)
	_finish({"pass": passed, "checks": checks, "controller_action_counts": counts, "final_score": final_score, "opponent_ball_actions": ai_actions, "max_ball_speed": maximum_ball_speed, "minimum_player_separation": minimum_player_separation, "sprint_seconds": sprint_seconds, "injected_joypad_events": joy_events, "rendered_frames": frames_saved, "simulation_seconds": elapsed, "hardware_controller_verified": false})

func _finish(report: Dictionary) -> void:
	completion_started = true
	var file := FileAccess.open(evidence_dir.path_join("acceptance.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	var events := FileAccess.open(evidence_dir.path_join("events.json"), FileAccess.WRITE)
	events.store_string(JSON.stringify(game.action_log, "\t"))
	events.close()
	print("ACCEPTANCE_RESULT: " + JSON.stringify(report))
	get_tree().quit(0 if report.get("pass", false) else 1)
