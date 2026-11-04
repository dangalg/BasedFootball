extends SceneTree

## Movie Maker fixture. Pass -- --report=<fresh absolute JSON path>.

const MatchInput := preload("res://scripts/match.gd")
const PLAYER_X := -43.0
const ROLL_SPEED := 4.8
const TACKLE_GAP := 0.98
const TACKLE_LANE := 0.15

class SampleProbe extends Node:
	var sample: Callable

	func _physics_process(_delta: float) -> void:
		sample.call()

var _world: Node3D
var _camera: Camera3D
var _caption: Label
var _player: FootballPlayer
var _ball: FootballBall
var _adapter: MatchInput
var _delta: float
var _events: Array[Dictionary] = []
var _touches: Array[Dictionary] = []
var _samples: Array[Dictionary] = []
var _previous: Dictionary = {}


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
	_delta = 1.0 / float(Engine.physics_ticks_per_second)
	_build_view()
	var left := await _tackle_case(-1.0, false)
	var right := await _tackle_case(1.0, true)
	var shot := await _shot_case()
	var passed: bool = left["passed"] and right["passed"] and shot["passed"]
	var report := FileAccess.open(report_path, FileAccess.WRITE)
	if report == null:
		push_error("Could not write tackle report at %s" % report_path)
		quit(2)
		return
	report.store_string(JSON.stringify({
		"passed": passed, "physics_hz": Engine.physics_ticks_per_second,
		"fixture": "Isolated 11v11 actors, production match controller handler and physical ball. A declared roll launches each tackle case. An audited zero-impulse touch stages the change of last-touch team.",
		"cases": [left, right, shot],
	}, "\t") + "\n")
	report.close()
	print("ELEVEN_TACKLE_ACCEPTANCE %s %s" % ["PASS" if passed else "FAIL", report_path])
	quit(0 if passed else 1)


func _build_view() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	ElevenPitch.build(_world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("233c47")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = 0.72
	_world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -35, 0)
	sun.light_energy = 1.24
	sun.shadow_enabled = true
	_world.add_child(sun)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 8.0
	_camera.position = Vector3(PLAYER_X + 5.5, 5.8, -8.0)
	_world.add_child(_camera)
	_camera.look_at(Vector3(PLAYER_X + 0.6, 0.45, 0))
	_camera.make_current()
	var overlay := CanvasLayer.new()
	root.add_child(overlay)
	_caption = Label.new()
	_caption.position = Vector2(24, 18)
	_caption.add_theme_font_size_override("font_size", 25)
	_caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	_caption.add_theme_constant_override("shadow_offset_y", 2)
	overlay.add_child(_caption)
	var probe := SampleProbe.new()
	probe.sample = _capture_sample
	probe.process_physics_priority = 1000
	_world.add_child(probe)


func _spawn_case(ball_offset: Vector3) -> Node3D:
	_events = []
	_touches = []
	_samples = []
	_previous = {}
	var actors := Node3D.new()
	_world.add_child(actors)
	_player = FootballPlayer.new()
	var squad := FootballSquad.new()
	squad.load_squad(true, true)
	squad.apply_to(_player, 0)
	_player.eleven_slot = 0
	_player.selected = true
	_player.aim = Vector3.RIGHT
	_player.position = Vector3(PLAYER_X, 0.05, 0.0)
	actors.add_child(_player)
	_ball = FootballBall.new()
	_ball.position = Vector3(PLAYER_X, FootballBall.RADIUS + 0.001, 0.0) + ball_offset
	_ball.set_collision_mask_value(ElevenPitch.NET_COLLISION_LAYER, true)
	actors.add_child(_ball)
	_player.physical_event.connect(_capture_event)
	_ball.played.connect(_capture_touch)
	_adapter = MatchInput.new()
	_adapter.eleven_a_side = true
	_adapter.controlled = _player
	_adapter.players.append(_player)
	_adapter.ball = _ball
	return actors


func _tackle_case(side: float, home_before_press: bool) -> Dictionary:
	var actors := _spawn_case(Vector3(TACKLE_GAP, 0.0, side * TACKLE_LANE))
	var label := "Left-foot lane" if side < 0.0 else "Right-foot lane"
	_caption.text = "%s  •  Rolling challenge" % label
	await _step(0.55)
	var roll := Vector3.LEFT * ROLL_SPEED
	_ball.angular_velocity = Vector3.UP.cross(roll) / FootballBall.RADIUS
	_ball.touch(1, "fixture_roll", roll * _ball.mass)
	if home_before_press:
		_ball.touch(0, "fixture_home_touch", Vector3.ZERO)
	_player.jockey = true
	var press_team := _ball.last_touch_team
	var press_frame := Engine.get_physics_frames()
	_adapter._controller_actions(_delta, {"primary": true})
	var action_at_press := _player.action_kind
	var charged_at_press := _adapter.charging
	_caption.text = "%s  •  L2 + Circle" % label
	await physics_frame
	if not home_before_press:
		_ball.touch(0, "fixture_home_touch", Vector3.ZERO)
	var release_team := _ball.last_touch_team
	_player.jockey = false
	_adapter._controller_actions(_delta, {"primary_release": true})
	await _step(0.85, true)
	var contact := _contact("standing_tackle_contact")
	var audit := _audited_touch(contact, "deflection")
	var detail: Dictionary = contact.get("detail", {})
	var normal := _read_vector(detail.get("normal"))
	var incoming := _read_vector(detail.get("incoming_velocity"))
	var impulse := _read_vector(audit.get("impulse"))
	var outgoing := _post_contact_velocity(contact)
	var expected_foot := "left" if side < 0.0 else "right"
	var tackles := _logged("circle_tackle")
	var checks := {
		"l2_circle_queues_standing_tackle": action_at_press == "standing" and tackles.size() == 1 and bool(tackles[0].get("queued", false)),
		"home_touch_does_not_turn_release_into_shot": press_team == (0 if home_before_press else 1) and release_team == 0 and not charged_at_press
			and _logged("shot_requested").is_empty() and _logged("shot_queued").is_empty() and _contact("kick_contact").is_empty(),
		"one_visible_boot_deflection": not audit.is_empty() and detail.get("foot") == expected_foot and bool(contact.get("framed", false))
			and float(detail.get("gap", INF)) <= FootballPlayer.STANDING_TACKLE_REACH + 0.0001
			and float(contact.get("observed_sweep_gap_m", INF)) <= FootballPlayer.STANDING_TACKLE_REACH + 0.012,
		"impulse_follows_contact_normal": normal.is_normalized() and impulse.length_squared() > 0.0001 and impulse.normalized().dot(normal) > 0.97,
		"physical_roll_redirected": incoming.x < -0.5 and outgoing.is_finite() and outgoing.x >= incoming.x - 0.12
			and (outgoing.x > incoming.x + 0.30 or absf(outgoing.z - incoming.z) > 0.30),
	}
	var result := _case_report(label, press_frame, checks, contact, outgoing)
	result["press_last_touch_team"] = press_team
	result["release_last_touch_team"] = release_team
	await _clear_case(actors)
	return result


func _shot_case() -> Dictionary:
	var actors := _spawn_case(Vector3.RIGHT * 0.53)
	var label := "Ordinary Circle shot"
	_caption.text = "%s  •  Ready" % label
	await _step(0.55)
	var press_frame := Engine.get_physics_frames()
	_adapter._controller_actions(_delta, {"primary": true})
	var armed := _adapter.charging
	_caption.text = "%s  •  Charging" % label
	await _step(0.40, true)
	_adapter._controller_actions(_delta, {"primary_release": true})
	await _step(0.70, true)
	var contact := _contact("kick_contact")
	var audit := _audited_touch(contact, "play")
	var detail: Dictionary = contact.get("detail", {})
	var outgoing := _post_contact_velocity(contact)
	var checks := {
		"ordinary_circle_shot_armed_and_queued": armed and _logged("shot_requested").size() == 1
			and _logged("shot_queued").size() == 1 and _logged("circle_tackle").is_empty(),
		"one_normal_kick_contact": not audit.is_empty() and detail.get("kind") == "shot" and detail.get("style") == ""
			and float(detail.get("boot_gap", INF)) <= FootballPlayer.STRIKE_BOOT_REACH and bool(contact.get("framed", false)),
		"ball_launches_upfield": _read_vector(audit.get("impulse")).x > 0.0 and outgoing.is_finite() and outgoing.x > 8.0,
	}
	var result := _case_report(label, press_frame, checks, contact, outgoing)
	await _clear_case(actors)
	return result


func _step(seconds: float, drive_controller := false) -> void:
	for _tick in range(ceili(seconds / _delta)):
		await physics_frame
		if drive_controller:
			_adapter._controller_actions(_delta, {})


func _capture_sample() -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_ball):
		return
	var visual := _player.visual_controller
	_previous = {
		"frame": Engine.get_physics_frames(), "ball": _vector(_ball.global_position),
		"velocity": _vector(_ball.linear_velocity), "player": _vector(_player.global_position),
		"left": _vector(visual.tackle_marker(false)), "right": _vector(visual.tackle_marker(true)),
		"action": _player.action_kind, "serial": _ball.touch_serial,
		"free": not _ball.freeze and _ball.grip_holder_id.is_empty(),
	}
	_samples.append(_previous)


func _capture_event(kind: String, detail: Dictionary) -> void:
	var event := {"kind": kind, "detail": detail, "frame": Engine.get_physics_frames(), "ball": _vector(_ball.global_position)}
	if kind in ["standing_tackle_contact", "kick_contact"]:
		var right: bool = detail.get("foot") == "right"
		var boot := _player.visual_controller.tackle_marker(right)
		event["framed"] = _visible(boot) and _visible(_ball.global_position)
		if kind == "standing_tackle_contact" and not _previous.is_empty():
			var from := _read_vector(_previous["ball"]) - _read_vector(_previous[detail["foot"]])
			var to := _ball.global_position - boot
			var movement := to - from
			var fraction := clampf(-from.dot(movement) / maxf(movement.length_squared(), 0.000001), 0.0, 1.0)
			event["observed_sweep_gap_m"] = from.lerp(to, fraction).length()
		_caption.text = "Standing tackle  •  Ball stays live" if kind == "standing_tackle_contact" else "Ordinary Circle shot  •  Boot contact"
	_events.append(event)


func _capture_touch(team: int, player_id: String, kind: String) -> void:
	_touches.append({"serial": _ball.touch_serial, "team": team, "player_id": player_id, "kind": kind})


func _contact(kind: String) -> Dictionary:
	var contact: Dictionary = {}
	for event in _events:
		if event["kind"] == kind:
			if not contact.is_empty():
				return {}
			contact = event
	return contact


func _audited_touch(contact: Dictionary, kind: String) -> Dictionary:
	if contact.is_empty():
		return {}
	var detail: Dictionary = contact["detail"]
	var serial: int = detail.get("touch_serial", -1)
	var actor_touches := _touches.filter(func(touch: Dictionary) -> bool: return touch["player_id"] == _player.player_id)
	if actor_touches.size() != 1 or actor_touches[0]["serial"] != serial or actor_touches[0]["kind"] != kind:
		return {}
	for entry in _ball.impulse_audit:
		if entry["serial"] == serial and entry["player_id"] == _player.player_id and entry["physics_frame"] == contact["frame"]:
			return entry
	return {}


func _post_contact_velocity(contact: Dictionary) -> Vector3:
	var frame := int(contact.get("frame", -1000)) + 3
	for sample in _samples:
		if sample["frame"] == frame:
			return _read_vector(sample["velocity"])
	return Vector3.INF


func _case_report(label: String, press_frame: int, checks: Dictionary, contact: Dictionary, outgoing: Vector3) -> Dictionary:
	checks["ball_remains_free"] = not _samples.is_empty() and _samples.all(func(sample: Dictionary) -> bool: return bool(sample["free"]))
	return {
		"label": label, "press_frame": press_frame, "last_frame": Engine.get_physics_frames(),
		"passed": not checks.values().has(false), "checks": checks, "contact": contact,
		"outgoing_velocity_mps": _vector(outgoing) if outgoing.is_finite() else null,
		"match_actions": _adapter.action_log.duplicate(true), "events": _events,
		"impulse_audit": _ball.impulse_audit.duplicate(true), "touches": _touches, "samples": _samples,
	}


func _logged(kind: String) -> Array[Dictionary]:
	return _adapter.action_log.filter(func(event: Dictionary) -> bool: return event["kind"] == kind)


func _visible(point: Vector3) -> bool:
	return not _camera.is_position_behind(point) and root.get_visible_rect().grow(-12.0).has_point(_camera.unproject_position(point))


func _clear_case(actors: Node3D) -> void:
	_adapter.free()
	_player = null
	_ball = null
	actors.queue_free()
	await process_frame


func _read_vector(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
