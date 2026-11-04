extends SceneTree

## Run in Movie Maker mode with --script res://tests/eleven_stride_acceptance.gd
## and -- --report=<fresh absolute JSON path>.

const MatchInput := preload("res://scripts/match.gd")
const TURN := Vector3(0.422618, 0.0, 0.906308)
const MAX_PLANT_DRIFT := 0.03
const MAX_SOLE_HEIGHT := 0.035
const MIN_PLANT_TICKS := 4

class PoseProbe extends Node:
	var sample: Callable

	func _physics_process(_delta: float) -> void:
		sample.call()


var _world: Node3D
var _player: FootballPlayer
var _ball: FootballBall
var _camera: Camera3D
var _caption: Label
var _adapter: MatchInput
var _delta: float
var _phase: Dictionary
var _phases: Dictionary = {}
var _active_plants: Array[Dictionary] = [{}, {}]
var _plants: Array[Dictionary] = []
var _events: Array[Dictionary] = []
var _samples: Array[Dictionary] = []
var _ball_start: Vector3
var _peak_ball_y := 0.0
var _peak_ball_speed := 0.0
var _finite := true
var _free_ball := true
var _framed := true


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
	_build_fixture()
	await _drive("Ready", Vector3.ZERO, false, 0.55)
	await _drive("Walk", Vector3.RIGHT * 0.32, false, 2.80)
	await _drive("Jog", Vector3.RIGHT * 0.80, false, 2.10)
	await _drive("Sprint", Vector3.RIGHT, true, 2.10)
	await _drive("Sprint turn", TURN, true, 1.25)
	await _drive("Stop", Vector3.ZERO, false, 1.15)
	# Place one settled ball for the contact check after the uninterrupted gait sequence.
	_ball_start = _player.global_position + TURN * 0.53
	_ball_start.y = FootballBall.RADIUS
	_ball = FootballBall.new()
	_ball.position = _ball_start
	_world.add_child(_ball)
	_adapter.ball = _ball
	await _drive("Ball settles", Vector3.ZERO, false, 0.45)
	await _drive("Charge shot", Vector3.ZERO, false, 0.30, {"primary": true})
	await _drive("Kick", Vector3.ZERO, false, 0.60, {"primary_release": true})
	_adapter.free()
	var checks := _check_result()
	var passed := not checks.values().has(false)
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write stride report at %s" % report_path)
		quit(2)
		return
	file.store_string(JSON.stringify({
		"passed": passed,
		"checks": checks,
		"physics_hz": Engine.physics_ticks_per_second,
		"actor": _player.player_id,
		"plant_drift_limit_m": MAX_PLANT_DRIFT,
		"sole_height_limit_m": MAX_SOLE_HEIGHT,
		"phases": _phases,
		"plants": _plants,
		"events": _events,
		"ball_start": _vector(_ball_start),
		"peak_ball_y_m": _peak_ball_y,
		"peak_ball_speed_mps": _peak_ball_speed,
		"impulse_audit": _ball.impulse_audit,
		"samples": _samples,
	}, "\t") + "\n")
	file.close()
	print("ELEVEN_STRIDE_ACCEPTANCE %s %s" % ["PASS" if passed else "FAIL", report_path])
	quit(0 if passed else 1)


func _build_fixture() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var turf := FootballArt.surface(Color("5c8869"), FootballArt.TURF, 22.0)
	FootballArt.solid(_world, Vector3(85.0, 0.5, 55.0), Vector3(0, -0.25, 0), turf)
	var marks := FootballArt.material(Color("789a80"))
	for x in range(-20, 28):
		FootballArt.box(_world, Vector3(0.012, 0.002, 31.0), Vector3(x, 0.001, 3.0), marks)
	for z in range(-12, 19):
		FootballArt.box(_world, Vector3(47.0, 0.002, 0.012), Vector3(3.5, 0.001, z), marks)
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
	_player = FootballPlayer.new()
	var squad := FootballSquad.new()
	squad.load_squad(true, true)
	squad.apply_to(_player, 0)
	_player.eleven_slot = 0
	_player.selected = true
	_player.aim = Vector3.RIGHT
	_player.position = Vector3(-13.0, 0.05, 0.0)
	_world.add_child(_player)
	_player.ai_rng.seed = 81100
	_player.physical_event.connect(_capture_event)
	_adapter = MatchInput.new()
	_adapter.eleven_a_side = true
	_adapter.controlled = _player
	_adapter.players.append(_player)
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
	var probe := PoseProbe.new()
	probe.sample = _sample_pose
	probe.process_physics_priority = 1000
	_world.add_child(probe)


func _drive(label: String, movement: Vector3, sprint: bool, seconds: float, actions: Dictionary = {}) -> void:
	_phase = {
		"label": label, "start_frame": Engine.get_physics_frames(),
		"start_time_s": Engine.get_physics_frames() * _delta,
		"start_player": _vector(_player.global_position),
		"input": _vector(movement), "sprint": sprint, "samples": 0,
		"left_swing_samples": 0, "right_swing_samples": 0,
		"both_soles_grounded_samples": 0, "peak_speed_mps": 0.0,
	}
	_phases[label] = _phase
	_player.intent = movement
	_player.sprint = sprint
	if movement != Vector3.ZERO:
		_player.aim = movement.normalized()
	var ticks := ceili(seconds / _delta)
	for tick in range(ticks):
		if is_instance_valid(_ball):
			_adapter._controller_actions(_delta, actions if tick == 0 else {})
		await physics_frame
	for side in range(2):
		_finish_plant(side)
	_phase["end_time_s"] = Engine.get_physics_frames() * _delta
	_phase["end_player"] = _vector(_player.global_position)
	_phase["end_velocity"] = _vector(FootballReception.flat(_player.linear_velocity))
	_phase["end_speed_mps"] = FootballReception.flat(_player.linear_velocity).length()


func _sample_pose() -> void:
	if _phase.is_empty():
		return
	var velocity := FootballReception.flat(_player.linear_velocity)
	_phase["samples"] += 1
	_phase["peak_speed_mps"] = maxf(float(_phase["peak_speed_mps"]), velocity.length())
	var sample := {
		"frame": Engine.get_physics_frames(), "phase": _phase["label"],
		"player": _vector(_player.global_position), "velocity": _vector(velocity),
	}
	var grounded := true
	for side in range(2):
		var right := side == 1
		var name := "right" if right else "left"
		var boot := _player.visual_controller.right_boot if right else _player.visual_controller.left_boot
		var sole := FootballPlayerVisual.SOLE_LOCAL_CENTER
		var points: Array[Vector3] = [
			boot.to_global(sole), boot.to_global(sole + Vector3.FORWARD * 0.105),
			boot.to_global(sole + Vector3.BACK * 0.105),
		]
		var planted := _player.visual_controller.gait_plant_active(right)
		_update_plant(side, points, planted)
		var all_points_near_ground := true
		for point in points:
			_finite = _finite and point.is_finite()
			all_points_near_ground = all_points_near_ground and absf(point.y) <= MAX_SOLE_HEIGHT
		grounded = grounded and all_points_near_ground
		if not planted and points[0].y > MAX_SOLE_HEIGHT:
			_phase[name + "_swing_samples"] += 1
		sample[name] = {"planted": planted, "sole": _vector(points[0]), "toe": _vector(points[1]), "heel": _vector(points[2])}
	if grounded:
		_phase["both_soles_grounded_samples"] += 1
	_finite = _finite and _player.global_position.is_finite() and velocity.is_finite()
	if is_instance_valid(_ball):
		_finite = _finite and _ball.global_position.is_finite() and _ball.linear_velocity.is_finite()
		_free_ball = _free_ball and not _ball.freeze and _ball.grip_holder_id.is_empty()
		_peak_ball_y = maxf(_peak_ball_y, _ball.global_position.y)
		_peak_ball_speed = maxf(_peak_ball_speed, FootballReception.flat(_ball.linear_velocity).length())
		sample["ball"] = _vector(_ball.global_position)
		sample["ball_velocity"] = _vector(_ball.linear_velocity)
		sample["touch_serial"] = _ball.touch_serial
	_samples.append(sample)
	_follow_action(velocity.length())


func _update_plant(side: int, points: Array[Vector3], planted: bool) -> void:
	if not planted:
		_finish_plant(side)
		return
	if _active_plants[side].is_empty():
		_active_plants[side] = {
			"side": "right" if side == 1 else "left", "phase": _phase["label"],
			"first_frame": Engine.get_physics_frames(), "anchors": points,
			"samples": 0, "max_drift_m": 0.0, "max_abs_height_m": 0.0,
		}
	var plant := _active_plants[side]
	var anchors: Array[Vector3] = plant["anchors"]
	for point in range(points.size()):
		var drift := FootballReception.flat(points[point] - anchors[point]).length()
		plant["max_drift_m"] = maxf(float(plant["max_drift_m"]), drift)
		plant["max_abs_height_m"] = maxf(float(plant["max_abs_height_m"]), absf(points[point].y))
	plant["samples"] += 1
	plant["last_frame"] = Engine.get_physics_frames()


func _finish_plant(side: int) -> void:
	var plant := _active_plants[side]
	if not plant.is_empty():
		plant.erase("anchors")
		_plants.append(plant)
		_active_plants[side] = {}


func _follow_action(speed: float) -> void:
	var look_at_point := _player.global_position + Vector3.UP * 0.84
	var size := 3.25
	if is_instance_valid(_ball):
		var separation := FootballReception.flat(_ball.global_position - _player.global_position)
		look_at_point += separation * 0.46
		size = maxf(size, 2.0 + separation.length() * 0.90)
	_camera.size = size
	_camera.position = look_at_point + Vector3(1.25, 2.30, 7.20)
	_camera.look_at(look_at_point)
	_caption.text = "%s   |   %.1f m/s" % [_phase["label"], speed]
	if is_instance_valid(_ball):
		var frame := root.get_visible_rect().grow(-16.0)
		_framed = _framed and frame.has_point(_camera.unproject_position(_ball.global_position))
		_framed = _framed and frame.has_point(_camera.unproject_position(_player.visual_controller.left_boot.global_position))
		_framed = _framed and frame.has_point(_camera.unproject_position(_player.visual_controller.right_boot.global_position))


func _check_result() -> Dictionary:
	var walk := float(_phases["Walk"]["end_speed_mps"])
	var jog := float(_phases["Jog"]["end_speed_mps"])
	var sprint := float(_phases["Sprint"]["end_speed_mps"])
	var turn_velocity := _read_vector(_phases["Sprint turn"]["end_velocity"])
	var checks := {
		"walk_jog_sprint_separate_speeds": walk > 0.65 and walk < 2.25 and jog > walk + 0.85 and sprint > jog + 1.15,
		"turn_follows_input": turn_velocity.length() > 2.8 and turn_velocity.normalized().dot(TURN) >= 0.90,
		"stop_settles_on_both_feet": float(_phases["Stop"]["end_speed_mps"]) <= 0.20 and int(_phases["Stop"]["both_soles_grounded_samples"]) >= 18,
		"finite_player_pose_and_ball": _finite,
		"ball_free_after_placement": _free_ball,
		"ball_and_feet_framed": _framed,
		"kick_makes_one_real_boot_contact": _check_kick(),
		"ball_flies_forward_after_kick": _peak_ball_y > FootballBall.RADIUS + 0.035 and _peak_ball_speed > 5.0 and (_ball.global_position - _ball_start).dot(TURN) > 1.0,
	}
	var within_drift := true
	var within_height := true
	for plant in _plants:
		within_drift = within_drift and float(plant["max_drift_m"]) <= MAX_PLANT_DRIFT
		within_height = within_height and float(plant["max_abs_height_m"]) <= MAX_SOLE_HEIGHT
	checks["actual_planted_sole_toe_heel_hold"] = within_drift
	checks["actual_planted_sole_toe_heel_grounded"] = within_height
	for label in ["Walk", "Jog", "Sprint"]:
		var order: Array[Dictionary] = []
		var first_frame := int(_phases[label]["start_frame"]) + ceili(0.25 / _delta)
		for plant in _plants:
			if plant["phase"] == label and int(plant["samples"]) >= MIN_PLANT_TICKS and int(plant["first_frame"]) >= first_frame:
				order.append(plant)
		order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["first_frame"]) < int(b["first_frame"]))
		var sides: Array[String] = []
		var changes := 0
		for plant in order:
			var side: String = plant["side"]
			if not sides.is_empty() and sides.back() != side:
				changes += 1
			sides.append(side)
		_phases[label]["plant_order"] = sides
		var swing_on_both := int(_phases[label]["left_swing_samples"]) >= 4 and int(_phases[label]["right_swing_samples"]) >= 4
		checks[label.to_lower() + "_alternating_plants_and_flight"] = sides.size() >= 3 and changes >= ceili(float(sides.size() - 1) * 0.70) and swing_on_both
	return checks


func _check_kick() -> bool:
	if _ball.impulse_audit.size() != 1:
		return false
	var audit := _ball.impulse_audit[0]
	if audit["player_id"] != _player.player_id or _read_vector(audit["impulse"]).dot(TURN) <= 0.1:
		return false
	for event in _events:
		if event["kind"] == "kick_contact":
			var detail: Dictionary = event["detail"]
			var gap := float(detail.get("boot_gap", INF))
			if detail.get("touch_serial", -1) == audit["serial"] and gap >= 0.0 and gap <= FootballPlayer.STRIKE_BOOT_REACH:
				return true
	return false


func _capture_event(kind: String, detail: Dictionary) -> void:
	_events.append({"kind": kind, "phase": _phase["label"], "frame": Engine.get_physics_frames(), "detail": detail.duplicate(true)})


func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _read_vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
