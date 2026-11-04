extends SceneTree

## Run in Movie Maker mode with --script res://tests/eleven_shot_setup_acceptance.gd
## and -- --report=<fresh absolute JSON path>.

const MatchInput := preload("res://scripts/match.gd")
const DEVICE := 0
const HOLD_SECONDS := 0.32
const FOLLOW_SECONDS := 0.62
const ROLL_DIRECTION := Vector3.RIGHT

class InputProbe extends Node:
	var tick: Callable

	func _physics_process(delta: float) -> void:
		tick.call(delta)


var _world: Node3D
var _camera: Camera3D
var _caption: Label
var _player: FootballPlayer
var _ball: FootballBall
var _adapter: MatchInput
var _phase := ""
var _samples: Array[Dictionary] = []
var _events: Array[Dictionary] = []
var _stick := Vector3.ZERO
var _circle := false


func _initialize() -> void:
	call_deferred("_run")


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
	var rolling := await _take_shot("Rolling shot", 3.15, false)
	var escape := await _take_shot("Escaping roll", 4.5, true)
	var settled := await _take_shot("Settled shot", 0.0, false)
	var checks := {
		"rolling_ball_and_body_keep_moving_during_charge": rolling["hold_ball_travel_m"] > 0.45 and rolling["hold_body_travel_m"] > 0.45,
		"rolling_approach_gathers_toward_ball": rolling["late_hold_velocity_to_stick_deg"] > 5.0 and rolling["late_hold_velocity_to_roll_deg"] < 6.0,
		"running_shot_contacts_while_moving": rolling["real_aimed_contact"] and rolling["contact_player_speed_mps"] > 1.0,
		"release_aim_differs_from_previous_facing": rolling["release_to_prior_facing_deg"] > 20.0,
		"escaping_ball_remains_free_and_shot_expires": escape["expired"] and escape["no_kick"] and escape["hold_ball_travel_m"] > 0.65 and escape["hold_body_projection_m"] > 0.28,
		"settled_shot_still_makes_contact": settled["real_aimed_contact"],
		"circle_edges_received_in_every_case": rolling["input_valid"] and escape["input_valid"] and settled["input_valid"],
		"finite_free_ball_and_visible_boots": rolling["observations_valid"] and escape["observations_valid"] and settled["observations_valid"],
	}
	var passed := not checks.values().has(false)
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not open shot setup report at %s" % report_path)
		quit(2)
		return
	file.store_string(JSON.stringify({
		"passed": passed, "checks": checks, "physics_hz": Engine.physics_ticks_per_second,
		"fixture_policy": "One fresh player and ball per case. One audited initial roll per moving case, with no subsequent fixture writes to ball physics. Joypad axes and Circle drive the match input adapter.",
		"cases": [rolling, escape, settled],
	}, "\t") + "\n")
	file.close()
	print("ELEVEN_SHOT_SETUP_ACCEPTANCE %s %s" % ["PASS" if passed else "FAIL", report_path])
	quit(0 if passed else 1)


func _take_shot(label: String, roll_speed: float, retreat: bool) -> Dictionary:
	_samples = []
	_events = []
	var fixture := Node3D.new()
	_world.add_child(fixture)
	_player = FootballPlayer.new()
	var squad := FootballSquad.new()
	squad.load_squad(true, true)
	squad.apply_to(_player, 0)
	_player.eleven_slot = 0
	_player.selected = true
	_player.aim = ROLL_DIRECTION
	_player.position.y = 0.05
	fixture.add_child(_player)
	_player.ai_rng.seed = 81100
	_player.physical_event.connect(_capture_event)
	_adapter = MatchInput.new()
	_adapter.eleven_a_side = true
	_adapter.controlled = _player
	_adapter.players.append(_player)
	if not InputMap.has_action("shoot"):
		_adapter._install_input()

	var hold_stick := Vector3.ZERO
	var release_stick := Vector3.ZERO
	var approach_stick := Vector3.ZERO
	if roll_speed > 0.0:
		# This 10-degree approach is below the ordinary chase steering threshold.
		# A lateral correction during the hold must come from shot preparation.
		hold_stick = ROLL_DIRECTION.rotated(Vector3.UP, deg_to_rad(10.0)) * 0.82
		release_stick = ROLL_DIRECTION.rotated(Vector3.UP, deg_to_rad(37.0)) * 0.82
		approach_stick = hold_stick
		if retreat:
			approach_stick = -ROLL_DIRECTION * 0.82
			hold_stick = approach_stick
			release_stick = approach_stick
	await _drive(label + " / approach", approach_stick, false, 0.64)

	_ball = FootballBall.new()
	_ball.position = _player.global_position + ROLL_DIRECTION * (0.64 if roll_speed > 0.0 else 0.53)
	_ball.position.y = FootballBall.RADIUS
	fixture.add_child(_ball)
	_adapter.ball = _ball
	if roll_speed > 0.0:
		_ball.touch(_player.team, _player.player_id, ROLL_DIRECTION * roll_speed * _ball.mass)
		_player._remember_free_ball(_ball, ROLL_DIRECTION)
	else:
		_ball.last_touch_team = _player.team
		_ball.last_touch_id = _player.player_id
		await _drive(label + " / settle", Vector3.ZERO, false, 0.35)

	var initial_body := _player.global_position
	var initial_ball := _ball.global_position
	var seed_serial := _ball.touch_serial
	await _drive(label + " / hold Circle", hold_stick, true, HOLD_SECONDS)
	var hold_body := FootballReception.flat(_player.global_position - initial_body)
	var hold_ball := FootballReception.flat(_ball.global_position - initial_ball)
	var held_velocity := FootballReception.flat(_player.linear_velocity)
	var held_facing := -_player.body_visual.global_basis.z
	var intended_aim := release_stick.normalized() if release_stick != Vector3.ZERO else ROLL_DIRECTION
	await _drive(label + " / release Circle", release_stick, false, FOLLOW_SECONDS)
	var result := _evaluate(intended_aim, seed_serial)
	result.merge({
		"case": label, "seed_speed_mps": roll_speed,
		"hold_stick": _vec(hold_stick), "release_stick": _vec(release_stick),
		"hold_body_travel_m": hold_body.length(), "hold_body_projection_m": hold_body.dot(hold_stick.normalized()),
		"hold_ball_travel_m": hold_ball.length(), "hold_end_velocity": _vec(held_velocity),
		"late_hold_velocity_to_stick_deg": _angle(held_velocity, hold_stick),
		"late_hold_velocity_to_roll_deg": _angle(held_velocity, ROLL_DIRECTION),
		"release_to_prior_facing_deg": _angle(intended_aim, held_facing),
		"match_actions": _adapter.action_log.duplicate(true), "events": _events,
		"impulse_audit": _ball.impulse_audit.duplicate(true), "samples": _samples,
	})
	_adapter.free()
	_adapter = null
	fixture.free()
	_player = null
	_ball = null
	return result


func _drive(phase: String, stick: Vector3, circle: bool, duration: float) -> void:
	_phase = phase
	_send_axis(JOY_AXIS_LEFT_X, stick.x)
	_send_axis(JOY_AXIS_LEFT_Y, stick.z)
	_stick = stick
	if circle != _circle:
		var event := InputEventJoypadButton.new()
		event.device = DEVICE
		event.button_index = JOY_BUTTON_B
		event.pressed = circle
		Input.parse_input_event(event)
		_circle = circle
	Input.flush_buffered_events()
	for _frame in range(ceili(duration * Engine.physics_ticks_per_second)):
		await physics_frame


func _send_axis(axis: int, value: float) -> void:
	var before := _stick.x if axis == JOY_AXIS_LEFT_X else _stick.z
	if is_equal_approx(value, before):
		return
	var event := InputEventJoypadMotion.new()
	event.device = DEVICE
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)


func _tick(delta: float) -> void:
	if _adapter == null:
		return
	_player.strike_setup_ball = null
	var movement := Input.get_vector("left", "right", "up", "down")
	_player.intent = Vector3(movement.x, 0, movement.y)
	if movement.length_squared() > 0.04:
		_player.aim = _player.intent.normalized()
	var pressed := Input.is_action_just_pressed("shoot")
	var released := Input.is_action_just_released("shoot")
	_update_camera()
	if _ball == null:
		return
	_adapter._controller_actions(delta, {"primary": pressed, "primary_release": released})
	_adapter._control_ball()
	var view := root.get_visible_rect().grow(-12.0)
	var framed := view.has_point(_camera.unproject_position(_ball.global_position))
	for boot: Node3D in [_player.visual_controller.left_boot, _player.visual_controller.right_boot]:
		framed = framed and view.has_point(_camera.unproject_position(boot.global_position))
	_samples.append({
		"frame": Engine.get_physics_frames(), "phase": _phase, "move_input": _vec(_player.intent),
		"circle_pressed": pressed, "circle_released": released, "charging": _adapter.charging,
		"buffer_s": _adapter.shot_buffer_remaining, "action": _player.action_kind,
		"setup_considers_ball": _player.strike_setup_ball == _ball,
		"player_position": _vec(_player.global_position), "player_velocity": _vec(_player.linear_velocity),
		"torso_position": _vec(_player.visual_controller.upper_body.global_position),
		"facing": _vec(-_player.body_visual.global_basis.z), "ball_position": _vec(_ball.global_position),
		"ball_velocity": _vec(_ball.linear_velocity), "serial": _ball.touch_serial,
		"free": _ball.grip_holder_id.is_empty() and not _ball.freeze, "framed": framed,
		"finite": _player.global_position.is_finite() and _ball.global_position.is_finite() and _ball.linear_velocity.is_finite(),
	})


func _capture_event(kind: String, detail: Dictionary) -> void:
	_events.append({"kind": kind, "detail": detail, "frame": Engine.get_physics_frames(), "player_speed_mps": FootballReception.flat(_player.linear_velocity).length()})


func _evaluate(aim: Vector3, seed_serial: int) -> Dictionary:
	var request_count := 0
	var queue_count := 0
	var expired := false
	var requested_aim := Vector3.ZERO
	for entry in _adapter.action_log:
		match entry["kind"]:
			"shot_requested":
				request_count += 1
				requested_aim = _vector(entry["direction"])
			"shot_queued":
				queue_count += 1
			"shot_buffer_expired":
				expired = true
	var contacts: Array[Dictionary] = []
	for entry in _events:
		if entry["kind"] == "kick_contact":
			contacts.append(entry)
	var actual_speed := 0.0
	var launch := Vector3.ZERO
	var valid_contact := false
	if contacts.size() == 1 and _ball.impulse_audit.size() > seed_serial:
		var contact := contacts[0]
		var detail: Dictionary = contact["detail"]
		var impulse: Dictionary = _ball.impulse_audit.back()
		actual_speed = contact["player_speed_mps"]
		for sample in _samples:
			if int(sample["frame"]) == int(contact["frame"]) + 2 and sample["serial"] == impulse["serial"]:
				launch = FootballReception.flat(_vector(sample["ball_velocity"]))
				break
		valid_contact = detail["kind"] == "shot" and detail["boot_gap"] <= FootballPlayer.STRIKE_BOOT_REACH
		valid_contact = valid_contact and impulse["serial"] == detail["touch_serial"] and impulse["player_id"] == _player.player_id
		valid_contact = valid_contact and impulse["physics_frame"] == contact["frame"]
		valid_contact = valid_contact and _vector(detail["aim_direction"]).dot(aim) > 0.999
	var pressed_edges := 0
	var released_edges := 0
	var observations_valid := not _samples.is_empty()
	for sample in _samples:
		pressed_edges += int(sample["circle_pressed"])
		released_edges += int(sample["circle_released"])
		observations_valid = observations_valid and sample["finite"] and sample["free"] and sample["framed"]
	return {
		"input_valid": pressed_edges == 1 and released_edges == 1 and request_count == 1 and requested_aim.dot(aim) > 0.999,
		"observations_valid": observations_valid,
		"contact_player_speed_mps": actual_speed, "launch_velocity": _vec(launch), "launch_aim_error_deg": _angle(launch, aim),
		"real_aimed_contact": valid_contact and queue_count == 1 and not expired and launch.length() > 8.0 and launch.normalized().dot(aim) > 0.98,
		"no_kick": queue_count == 0 and contacts.is_empty() and _ball.impulse_audit.size() == seed_serial,
		"expired": expired,
	}


func _build_world() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var turf := FootballArt.surface(Color("5c8869"), FootballArt.TURF, 22.0)
	FootballArt.solid(_world, Vector3(42.0, 0.5, 30.0), Vector3(0, -0.25, 0), turf)
	var marks := FootballArt.material(Color("789a80"))
	for x in range(-12, 17):
		FootballArt.box(_world, Vector3(0.012, 0.002, 24.0), Vector3(x, 0.001, 0.0), marks)
	for z in range(-10, 11):
		FootballArt.box(_world, Vector3(34.0, 0.002, 0.012), Vector3(0, 0.001, z), marks)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("233c47")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = 0.74
	_world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-56.0, -32.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	_world.add_child(sun)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_world.add_child(_camera)
	_camera.make_current()
	var overlay := CanvasLayer.new()
	root.add_child(overlay)
	_caption = Label.new()
	_caption.position = Vector2(24.0, 18.0)
	_caption.add_theme_font_size_override("font_size", 23)
	_caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	_caption.add_theme_constant_override("shadow_offset_y", 2)
	overlay.add_child(_caption)
	var probe := InputProbe.new()
	probe.tick = _tick
	probe.process_physics_priority = -100
	_world.add_child(probe)


func _update_camera() -> void:
	var target := _player.global_position + Vector3.UP * 0.84
	var size := 3.25
	if _ball != null:
		var separation := FootballReception.flat(_ball.global_position - _player.global_position)
		target += separation * 0.48
		size = maxf(size, 2.6 + separation.length())
	_camera.size = size
	_camera.position = target + Vector3(0.5, 2.3, 7.2)
	_camera.look_at(target)
	_caption.text = "%s   |   %.1f m/s" % [_phase, FootballReception.flat(_player.linear_velocity).length()]


func _vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])


func _angle(first: Vector3, second: Vector3) -> float:
	return rad_to_deg(FootballReception.flat(first).angle_to(FootballReception.flat(second)))
