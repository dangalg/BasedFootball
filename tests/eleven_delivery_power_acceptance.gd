extends "res://tests/eleven_shot_setup_acceptance.gd"

## Movie Maker, --script res://tests/eleven_delivery_power_acceptance.gd
## -- --report=<fresh absolute JSON path>.

const TAP_SECONDS := 0.045
const FULL_SECONDS := 0.66
const TRAVEL_SAMPLE_SECONDS := 0.18
const FIRST_DESCENT_RECEIVE_SECONDS := 0.25

var _fixture: Node3D
var _receiver: FootballPlayer
var _defender: FootballPlayer
var _delivery_camera_focus := Vector3.ZERO
var _receiver_body_contacts: Array[Dictionary] = []


func _run() -> void:
	var report_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			report_path = argument.trim_prefix("--report=")
	if not report_path.is_absolute_path() or FileAccess.file_exists(report_path):
		push_error("Use -- --report=<fresh absolute JSON path>.")
		quit(2)
		return
	Input.use_accumulated_input = false
	_build_world()
	FootballArt.solid(_world, Vector3(28.0, 0.5, 30.0), Vector3(35, -0.25, 0), FootballArt.material(Color("5c8869")))
	var pass_tap := await _exercise("Cross tap", JOY_BUTTON_A, TAP_SECONDS, 5.0)
	var pass_hold := await _exercise("Cross held", JOY_BUTTON_A, FULL_SECONDS, 9.0)
	var lob_tap := await _exercise("Square tap", JOY_BUTTON_X, TAP_SECONDS, 9.0)
	var lob_hold := await _exercise("Square held / clear the defender", JOY_BUTTON_X, FULL_SECONDS, 17.5, true)
	var call := await _exercise("Cross off the ball", JOY_BUTTON_A, 0.31, 7.0, false, "call")
	var slide := await _exercise("Square defending", JOY_BUTTON_X, 0.31, 7.0, false, "slide")
	var checks := {
		"cross_tap_and_hold_strike_on_release": pass_tap["real_delivery"] and pass_hold["real_delivery"],
		"held_cross_launches_faster_and_travels_farther": _more_power(pass_tap, pass_hold),
		"square_tap_and_hold_strike_on_release": lob_tap["real_delivery"] and lob_hold["real_delivery"],
		"held_square_launches_faster_farther_and_higher": _more_power(lob_tap, lob_hold) and float(lob_hold["peak_ball_y_m"]) > float(lob_tap["peak_ball_y_m"]) + 0.65,
		"held_lob_physically_clears_standing_defender": float(lob_hold["standing_clearance_m"]) > 0.15,
		"teammates_physically_receive_held_pass_and_lob": pass_hold["physical_reception"] and lob_hold["physical_reception"],
		"held_lob_received_on_first_playable_descent": lob_hold["physical_reception"] and lob_hold["first_descent_receive"],
		"off_ball_cross_calls_once_on_press": call["input_valid"] and call["immediate_call"] and call["no_delivery"],
		"defensive_square_slides_on_press": slide["input_valid"] and slide["immediate_slide"] and slide["no_delivery"],
		"all_cases_observe_free_ball": pass_tap["free"] and pass_hold["free"] and lob_tap["free"] and lob_hold["free"] and call["free"] and slide["free"],
	}
	var passed := not checks.values().has(false)
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write delivery power report.")
		quit(2)
		return
	file.store_string(JSON.stringify({
		"passed": passed, "checks": checks, "physics_hz": Engine.physics_ticks_per_second,
		"fixture": "Fresh actors and settled balls for each case. Actual mapped controller edges, normal strike planner and receiver AI. No fixture ball writes after placement.",
		"cases": [pass_tap, pass_hold, lob_tap, lob_hold, call, slide],
	}, "\t") + "\n")
	file.close()
	print("ELEVEN_DELIVERY_POWER_ACCEPTANCE %s %s" % ["PASS" if passed else "FAIL", report_path])
	quit(0 if passed else 1)


func _exercise(label: String, button: int, hold_seconds: float, receiver_x: float, with_defender := false, mode := "delivery") -> Dictionary:
	_fixture = Node3D.new()
	_world.add_child(_fixture)
	_samples = []
	_events = []
	_receiver_body_contacts = []
	var squad := FootballSquad.new()
	squad.load_squad(true, true)
	_player = _create_player(squad, 0, 0.0)
	_player.selected = true
	_delivery_camera_focus = _player.global_position + Vector3.UP * 0.84
	_camera.size = 3.4
	_receiver = _create_player(squad, 1, receiver_x, 1 if mode == "slide" else 0)
	_defender = _create_player(squad, 2, 7.2, 1) if with_defender else null
	_ball = FootballBall.new()
	_ball.position = Vector3(0.53 if mode == "delivery" else receiver_x + 0.53, FootballBall.RADIUS, 0.0)
	_ball.last_touch_team = 1 if mode == "slide" else 0
	_ball.last_touch_id = _player.player_id if mode == "delivery" else _receiver.player_id
	_fixture.add_child(_ball)
	_ball.body_entered.connect(_observe_ball_body_contact)
	_adapter = MatchInput.new()
	_adapter.eleven_a_side = true
	_adapter.controlled = _player
	_adapter.players.assign([_player, _receiver])
	_adapter.ball = _ball
	if with_defender:
		_adapter.players.append(_defender)
	if not InputMap.has_action("pass"):
		_adapter._install_input()
	_adapter.sound = FootballSound.new()
	_fixture.add_child(_adapter.sound)
	_adapter.hud = FootballHUD.new()
	_adapter.hud.visible = false
	_fixture.add_child(_adapter.hud)
	_player.strike_contact.connect(_adapter._on_strike_contact.bind(_player))
	_player.physical_event.connect(_capture_event)
	_receiver.physical_event.connect(_capture_event)
	await _drive(label + " / ready", Vector3.ZERO, false, 0.33)
	_set_button(button, true)
	await _drive(label + " / held", Vector3.ZERO, false, hold_seconds)
	_set_button(button, false)
	await _drive(label + " / released", Vector3.ZERO, false, 2.05 if mode == "delivery" else 0.20)
	var result := _measure_delivery("pass" if button == JOY_BUTTON_A else "lob")
	result.merge({"case": label, "held_seconds": hold_seconds, "samples": _samples, "events": _events,
		"action_log": _adapter.action_log.duplicate(true), "impulse_audit": _ball.impulse_audit.duplicate(true),
		"receiver_body_contacts": _receiver_body_contacts})
	_adapter.free()
	_adapter = null
	_fixture.free()
	_player = null
	_ball = null
	_receiver = null
	_defender = null
	return result


func _create_player(squad: FootballSquad, index: int, x: float, team := 0) -> FootballPlayer:
	var player := FootballPlayer.new()
	squad.apply_to(player, index)
	player.team = team
	player.eleven_slot = index
	player.aim = ROLL_DIRECTION if team == 0 else -ROLL_DIRECTION
	player.position = Vector3(x, 0.05, 0.0)
	_fixture.add_child(player)
	player.ai_rng.seed = 81100 + index
	return player


func _set_button(button: int, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = DEVICE
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _observe_ball_body_contact(body: Node) -> void:
	if body != _receiver:
		return
	_receiver_body_contacts.append({
		"frame": Engine.get_physics_frames(), "serial": _ball.touch_serial,
		"receiver": _receiver.player_id, "ball": _vec(_ball.global_position),
		"velocity": _vec(_ball.linear_velocity), "receiver_position": _vec(_receiver.global_position),
	})


func _tick(delta: float) -> void:
	if _adapter == null:
		return
	_player.strike_setup_ball = null
	var actions := {
		"pass": Input.is_action_just_pressed("pass"), "pass_release": Input.is_action_just_released("pass"),
		"square": Input.is_action_just_pressed("lob"), "square_release": Input.is_action_just_released("lob"),
	}
	_adapter.reception.update(_adapter, delta)
	var events_before := _adapter.action_log.size()
	_adapter._controller_actions(delta, actions, true)
	if _ball.pass_active and _ball.pass_receiver_id == _receiver.player_id:
		FootballAI.decide(_receiver, _adapter.players, _ball, delta, true)
	else:
		_receiver.intent = Vector3.ZERO
	_adapter._control_ball()
	_update_camera()
	var pressed: bool = actions["pass"] or actions["square"]
	var released: bool = actions["pass_release"] or actions["square_release"]
	_samples.append({
		"frame": Engine.get_physics_frames(), "phase": _phase,
		"press": pressed, "release": released, "call_on_press": pressed and _adapter.action_log.size() > events_before and _adapter.pass_call_remaining > 0.0,
		"slide_on_press": pressed and _player.action_kind == "slide", "serial": _ball.touch_serial,
		"ball": _vec(_ball.global_position), "velocity": _vec(_ball.linear_velocity),
		"receiver": _vec(_receiver.global_position), "assigned_receiver": _ball.pass_receiver_id,
		"receiver_facing": _vec(-_receiver.body_visual.global_basis.z),
		"receiver_left_boot": _vec(_receiver.visual_controller.left_boot.global_position),
		"receiver_right_boot": _vec(_receiver.visual_controller.right_boot.global_position),
		"receiving_active": _receiver.receiving_active, "predicted_reach_gap_m": _receiver.last_control_reach_gap,
		"pass_target": _vec(_ball.pass_target), "receiver_control_reason": _receiver.last_control_reason,
		"free": _ball.grip_holder_id.is_empty() and not _ball.freeze and _ball.global_position.is_finite() and _ball.linear_velocity.is_finite(),
	})


func _update_camera() -> void:
	var target := _player.global_position + Vector3.UP * 0.84
	var subject := _ball.global_position
	if _ball.touch_serial > 0 and _ball.global_position.x > 2.4:
		target = _ball.global_position
		target.y = maxf(0.84, target.y * 0.68)
		subject = _receiver.global_position
		if _defender != null and _ball.global_position.x <= _defender.global_position.x + 1.6:
			subject = _defender.global_position
	var span := FootballReception.flat(subject - target).limit_length(6.0)
	target += span * 0.44
	var blend := 1.0 - exp(-16.0 / Engine.physics_ticks_per_second)
	_delivery_camera_focus = _delivery_camera_focus.lerp(target, blend)
	_camera.size = lerpf(_camera.size, maxf(3.4, 2.8 + span.length() * 0.90), blend)
	_camera.position = _delivery_camera_focus + Vector3(0.5, 2.30, 7.20)
	_camera.look_at(_delivery_camera_focus)
	_caption.text = "%s   |   Ball %.1f m/s" % [_phase, _ball.linear_velocity.length()]


func _measure_delivery(kind: String) -> Dictionary:
	var contact: Dictionary = {}
	var receive: Dictionary = {}
	var receive_frame := -1
	var launch_count := 0
	for event in _events:
		if event["kind"] == "kick_contact":
			launch_count += 1
			contact = event
		elif event["kind"] == "receive_contact" and event["detail"]["receiver"] == _receiver.player_id:
			receive = event["detail"]
			receive_frame = int(event["frame"])
	var detail: Dictionary = contact.get("detail", {})
	var serial := int(detail.get("touch_serial", -1))
	var contact_frame := int(contact.get("frame", -1))
	var launch_origin := Vector3.ZERO
	var travel_point := Vector3.ZERO
	var launch_speed := 0.0
	var apex := 0.0
	var clearance := -1.0
	var press_count := 0
	var release_count := 0
	var release_frame := -1
	var call_on_press := false
	var slide_on_press := false
	var free := true
	var receiver_travel := 0.0
	var playable_descent_frame := -1
	var first_reachable_frame := -1
	var receiver_start := _vector(_samples[0]["receiver"])
	var travel_ticks := roundi(TRAVEL_SAMPLE_SECONDS * Engine.physics_ticks_per_second)
	for sample in _samples:
		press_count += int(sample["press"])
		release_count += int(sample["release"])
		if sample["release"]:
			release_frame = int(sample["frame"])
		call_on_press = call_on_press or sample["call_on_press"]
		slide_on_press = slide_on_press or sample["slide_on_press"]
		free = free and sample["free"]
		var frame := int(sample["frame"])
		if frame == receive_frame:
			receiver_travel = FootballReception.flat(_vector(sample["receiver"]) - receiver_start).length()
		if frame == contact_frame:
			launch_origin = _vector(sample["ball"])
		if int(sample["serial"]) != serial:
			continue
		var position := _vector(sample["ball"])
		var velocity := _vector(sample["velocity"])
		if frame == contact_frame + 2:
			launch_speed = FootballReception.flat(velocity).length()
		if frame == contact_frame + travel_ticks:
			travel_point = position
		apex = maxf(apex, position.y)
		if playable_descent_frame < 0 and apex > 1.0 and position.y <= 0.55 and velocity.y < 0.0:
			playable_descent_frame = frame
		if first_reachable_frame < 0 and sample["assigned_receiver"] == _receiver.player_id and position.y <= 0.55 and FootballReception.flat(position - _vector(sample["receiver"])).length() < FootballPlayer.RECEIVE_PREPARE_REACH:
			first_reachable_frame = frame
		if _defender != null and absf(position.x - _defender.global_position.x) <= 0.10:
			var head_top := _defender.visual_controller.head_pivot.global_position.y + 0.31
			clearance = maxf(clearance, position.y - FootballBall.RADIUS - head_top)
	var input_valid := press_count == 1 and release_count == 1
	var call_count := 0
	for action in _adapter.action_log:
		call_count += int(action["kind"] == "pass_called")
	var distance := (travel_point - launch_origin).dot(ROLL_DIRECTION) if travel_point != Vector3.ZERO else 0.0
	var first_descent_delay: Variant = null
	var first_descent_receive := false
	if playable_descent_frame >= 0 and receive_frame >= 0:
		var frame_delta := receive_frame - playable_descent_frame
		var delay := float(frame_delta) / Engine.physics_ticks_per_second
		first_descent_delay = delay
		first_descent_receive = frame_delta >= -2 and delay <= FIRST_DESCENT_RECEIVE_SECONDS
	return {
		"input_valid": input_valid, "release_frame": release_frame, "free": free,
		"launch_speed_mps": launch_speed, "travel_at_018_s_m": distance, "peak_ball_y_m": apex, "standing_clearance_m": clearance,
		"real_delivery": input_valid and launch_count == 1 and contact_frame > release_frame and detail.get("kind", "") == kind and float(detail.get("boot_gap", INF)) <= FootballPlayer.STRIKE_BOOT_REACH and _audited(serial, _player.player_id) and launch_speed > 5.0 and distance > 0.5,
		"physical_reception": receiver_travel > 0.35 and int(receive.get("incoming_touch_serial", -1)) == serial and float(receive.get("boot_gap", INF)) <= FootballPlayer.BOOT_TOUCH_REACH and _audited(int(receive.get("touch_serial", -1)), _receiver.player_id),
		"playable_descent_frame": playable_descent_frame, "first_reachable_frame": first_reachable_frame, "receive_frame": receive_frame,
		"receive_after_playable_descent_s": first_descent_delay, "first_descent_receive": first_descent_receive,
		"receiver_final_displacement_m": FootballReception.flat(_vector(_samples.back()["receiver"]) - receiver_start).length(),
		"receiver_travel_m": receiver_travel, "immediate_call": call_on_press and call_count == 1,
		"immediate_slide": slide_on_press, "no_delivery": launch_count == 0 and _ball.impulse_audit.is_empty(),
	}


func _audited(serial: int, actor_id: String) -> bool:
	for impulse in _ball.impulse_audit:
		if impulse["serial"] == serial and impulse["player_id"] == actor_id and _vector(impulse["impulse"]).length_squared() > 0.00001:
			return true
	return false


func _more_power(tap: Dictionary, hold: Dictionary) -> bool:
	return float(hold["launch_speed_mps"]) > float(tap["launch_speed_mps"]) + 2.0 and float(hold["travel_at_018_s_m"]) > float(tap["travel_at_018_s_m"]) + 0.25
