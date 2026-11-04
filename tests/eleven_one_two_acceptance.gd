extends SceneTree

## Movie Maker --script res://tests/eleven_one_two_acceptance.gd
## -- --eleven-acceptance --report=<fresh absolute JSON path>.

const MATCH := preload("res://scenes/eleven_match.tscn")
const FORWARD := Vector3.RIGHT

var _game: Node3D
var _runner: FootballPlayer
var _teammate: FootballPlayer
var _ball: FootballBall
var _camera: Camera3D
var _samples: Array[Dictionary] = []
var _inputs: Array[Dictionary] = []
var _touches: Array[Dictionary] = []
var _first_event := 0
var _stick := Vector3.ZERO
var _sprint := false
var _selected_throughout := true
var _run_origin := Vector3.ZERO


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var report_path := ""
	for argument in arguments:
		if argument.begins_with("--report="):
			report_path = argument.trim_prefix("--report=")
	if "--eleven-acceptance" not in arguments or not report_path.is_absolute_path() or FileAccess.file_exists(report_path):
		push_error("Use -- --eleven-acceptance --report=<fresh absolute JSON path>.")
		quit(2)
		return
	Input.use_accumulated_input = false
	_game = MATCH.instantiate() as Node3D
	root.add_child(_game)
	current_scene = _game
	if not _game.acceptance or _game.squad.save_path != "user://eleven_acceptance_squad.json" or _game.phase != "playing":
		push_error("Expected the isolated playing eleven-a-side scene.")
		quit(2)
		return
	await _exercise()
	var report := _evaluate()
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write one-two report.")
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("ELEVEN_ONE_TWO_ACCEPTANCE %s %s" % ["PASS" if report["passed"] else "FAIL", report_path])
	quit(0 if report["passed"] else 1)


func _exercise() -> void:
	_runner = _game.controlled
	_teammate = _game.home_outfield[1]
	_ball = _game.ball
	var start := Vector3(5.0, 0.05, 0.0)
	var outlet := Vector3(7.0, 0.05, 4.2)
	var direction := FootballReception.flat(outlet - start).normalized()
	for index in range(_game.players.size()):
		var player: FootballPlayer = _game.players[index]
		player.ai_rng.seed = 81100 + index
		if player == _runner or player == _teammate or player.is_goalkeeper:
			continue
		var lane := float(index % 7 - 3) * 8.0
		var depth := float(index % 3) * 3.0
		_place(player, Vector3(-10.0 - depth if player.team == 0 else 27.0 + depth, 0.05, lane), FORWARD * player.attack_sign())
	_place(_runner, start, direction)
	_place(_teammate, outlet, -direction)
	_ball.global_position = Vector3(start.x, FootballBall.RADIUS, start.z) + direction * 0.53
	_ball.last_touch_id = _runner.player_id
	_ball.last_touch_team = _runner.team
	_ball.reset_physics_interpolation()
	_ball.played.connect(_observe_touch)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_game.add_child(_camera)
	_camera.make_current()
	await _wait(0.32, "settled")

	_first_event = _game.action_log.size()
	_game.kickoff_remaining = 0.0
	_move(direction * 0.34)
	_button(JOY_BUTTON_LEFT_SHOULDER, true)
	await _wait(0.017, "hold L1")
	_button(JOY_BUTTON_A, true)
	await _wait(0.042, "L1 + Cross")
	_button(JOY_BUTTON_A, false)
	var hz := Engine.physics_ticks_per_second
	for _frame in range(ceili(0.48 * hz)):
		await physics_frame
		_sample("outbound strike")
		if not _event(_game.action_log, "one_two_started", _runner.player_id).is_empty():
			break
	_button(JOY_BUTTON_LEFT_SHOULDER, false)
	_run_origin = _runner.global_position
	_move(FORWARD * 0.93, true)
	for _frame in range(ceili(2.8 * hz)):
		await physics_frame
		_sample("forward run / return")
		if _ball.pass_active and _ball.pass_receiver_id == _runner.player_id:
			_follow_return()
		if not _event(_game.action_log, "receive_contact", _runner.player_id).is_empty():
			break
	_move(Vector3.ZERO)
	await _wait(0.34, "control after return")


func _place(player: FootballPlayer, position: Vector3, facing: Vector3) -> void:
	player.global_position = position
	player.aim = facing
	player.body_visual.rotation.y = atan2(-facing.x, -facing.z)
	player.reset_physics_interpolation()


func _wait(seconds: float, phase: String) -> void:
	for _frame in range(ceili(seconds * Engine.physics_ticks_per_second)):
		await physics_frame
		_sample(phase)


func _follow_return() -> void:
	var to_target := FootballReception.flat(_ball.pass_target - _runner.global_position)
	var to_ball := FootballReception.flat(_ball.global_position - _runner.global_position)
	if to_ball.length() < 1.6:
		var roll := FootballReception.flat(_ball.linear_velocity)
		var desired := (roll * 0.35 + to_target * 2.0).limit_length(_runner.pace * 0.64)
		_move(desired / maxf(1.0, _runner.pace * 0.66))
	else:
		var sprint := to_target.length() > 3.0
		_move(to_target.normalized() * clampf(to_target.length() * 0.60, 0.0, 0.94), sprint)


func _move(stick: Vector3, sprint := false) -> void:
	if not is_equal_approx(stick.x, _stick.x):
		_axis(JOY_AXIS_LEFT_X, stick.x)
	if not is_equal_approx(stick.z, _stick.z):
		_axis(JOY_AXIS_LEFT_Y, stick.z)
	if sprint != _sprint:
		_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0 if sprint else 0.0)
	_stick = stick
	_sprint = sprint
	Input.flush_buffered_events()


func _axis(axis: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)


func _button(button: int, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	_inputs.append({"frame": Engine.get_physics_frames(), "button": "Cross" if button == JOY_BUTTON_A else "L1", "pressed": pressed, "selected": _game.controlled.player_id})


func _observe_touch(team: int, actor: String, kind: String) -> void:
	var audit: Dictionary = _ball.impulse_audit.back()
	_touches.append({
		"frame": Engine.get_physics_frames(), "serial": _ball.touch_serial,
		"team": team, "actor": actor, "kind": kind, "selected": _game.controlled.player_id,
		"runner_position": _vec(_runner.global_position), "runner_velocity": _vec(_runner.linear_velocity),
		"ball_position": _vec(_ball.global_position), "impulse": audit["impulse"],
		"live": _game.phase == "playing" and _game.restart.is_empty() and _game.kickoff_remaining <= 0.0,
	})


func _sample(phase: String) -> void:
	var focus := (_runner.global_position + _teammate.global_position + _ball.global_position * 2.0) / 4.0 + Vector3.UP * 0.68
	var span := maxf(_runner.global_position.distance_to(_ball.global_position), _teammate.global_position.distance_to(_ball.global_position))
	_camera.size = clampf(3.8 + span * 0.70, 4.4, 10.0)
	_camera.position = focus + Vector3(1.8, 3.8, 8.0)
	_camera.look_at(focus)
	_selected_throughout = _selected_throughout and _game.controlled == _runner
	_samples.append({
		"frame": Engine.get_physics_frames(), "phase": phase, "selected": _game.controlled.player_id,
		"runner": _vec(_runner.global_position), "runner_velocity": _vec(_runner.linear_velocity), "stick": _vec(_stick),
		"teammate": _vec(_teammate.global_position), "ball": _vec(_ball.global_position),
		"serial": _ball.touch_serial, "assigned_receiver": _ball.pass_receiver_id, "pass_target": _vec(_ball.pass_target),
		"runner_control_reason": _runner.last_control_reason,
		"free": not _ball.freeze and _ball.grip_holder_id.is_empty() and _ball.global_position.is_finite(),
	})


func _evaluate() -> Dictionary:
	var events: Array = _game.action_log.slice(_first_event)
	var start := _event(events, "one_two_started", _runner.player_id)
	var outgoing_serial := int(start.get("touch_serial", -1))
	var outgoing := _event(events, "kick_contact", _runner.player_id, {"touch_serial": outgoing_serial})
	var first_receive := _event(events, "receive_contact", _teammate.player_id, {"incoming_touch_serial": outgoing_serial, "passer": _runner.player_id})
	var request := _event(events, "one_two_return_requested", _runner.player_id, {"receiver": _teammate.player_id, "incoming_touch_serial": outgoing_serial})
	var decision := _event(events, "ai_decision", _teammate.player_id, {"reason": "called_pass", "queued": true, "receiver_id": _runner.player_id})
	var assignment := _event(events, "receiver_assigned", _runner.player_id, {"passer": _teammate.player_id})
	var returning_serial := int(assignment.get("serial", -1))
	var returning := _event(events, "kick_contact", _teammate.player_id, {"touch_serial": returning_serial})
	var finish := _event(events, "receive_contact", _runner.player_id, {"incoming_touch_serial": returning_serial, "passer": _teammate.player_id})
	var finish_serial := int(finish.get("touch_serial", -1))
	var outgoing_touch := _touch(outgoing_serial, _runner.player_id)
	var teammate_touch := _touch(int(first_receive.get("touch_serial", -1)), _teammate.player_id)
	var return_touch := _touch(returning_serial, _teammate.player_id)
	var finish_touch := _touch(finish_serial, _runner.player_id)
	var uninterrupted := finish_serial > outgoing_serial
	for touch in _touches:
		if int(touch["serial"]) >= outgoing_serial and int(touch["serial"]) <= finish_serial:
			uninterrupted = uninterrupted and touch["team"] == _runner.team and touch["live"]
	var forward_at_return := _vector(return_touch["runner_velocity"]).dot(FORWARD) if not return_touch.is_empty() else 0.0
	var runner_progress := (_vector(finish_touch["runner_position"]) - _run_origin).dot(FORWARD) if not finish_touch.is_empty() else 0.0
	var free := true
	for sample in _samples:
		free = free and sample["free"]
	var checks := {
		"actual_l1_cross_keeps_the_same_selected_player": _inputs.size() == 4 and _selected_throughout and _event(events, "switch", "").is_empty(),
		"outbound_controller_pass_has_real_boot_contact": not start.is_empty() and outgoing.get("detail_kind", "") == "pass" and _boot_ok(outgoing, FootballPlayer.STRIKE_BOOT_REACH) and not outgoing_touch.is_empty(),
		"teammate_receives_outbound_and_return_is_requested": _boot_ok(first_receive, FootballPlayer.BOOT_TOUCH_REACH) and not teammate_touch.is_empty() and not request.is_empty(),
		"ai_returns_ball_into_the_selected_players_run": not decision.is_empty() and returning_serial > int(first_receive.get("touch_serial", -1)) and _boot_ok(returning, FootballPlayer.STRIKE_BOOT_REACH) and not return_touch.is_empty() and forward_at_return >= 1.0,
		"selected_runner_physically_receives_the_return": _boot_ok(finish, FootballPlayer.BOOT_TOUCH_REACH) and not finish_touch.is_empty() and finish_touch.get("selected", "") == _runner.player_id and runner_progress >= 2.0,
		"free_ball_and_no_opponent_touch_in_the_combination": free and uninterrupted,
	}
	return {
		"passed": not checks.values().has(false), "checks": checks,
		"runner": _runner.player_id, "teammate": _teammate.player_id,
		"runner_goalward_speed_at_return_mps": forward_at_return, "runner_progress_at_receive_m": runner_progress,
		"inputs": _inputs, "samples": _samples, "events": events, "touches": _touches,
	}


func _boot_ok(event: Dictionary, reach: float) -> bool:
	var gap := float(event.get("boot_gap", INF))
	return gap >= 0.0 and gap <= reach


func _event(events: Array, kind: String, actor: String, fields: Dictionary = {}) -> Dictionary:
	for event: Dictionary in events:
		if event["kind"] != kind or (not actor.is_empty() and event["player"] != actor):
			continue
		var matches := true
		for key in fields:
			matches = matches and event.get(key) == fields[key]
		if matches:
			return event
	return {}


func _touch(serial: int, actor: String) -> Dictionary:
	for touch in _touches:
		if touch["serial"] == serial and touch["actor"] == actor and touch["live"] and _vector(touch["impulse"]).length_squared() > 0.00001:
			return touch
	return {}


func _vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])
