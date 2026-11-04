extends SceneTree

## Run in Movie Maker mode with --script res://tests/eleven_low_save_acceptance.gd
## and -- --report=<fresh absolute JSON path>.

const KEEPER_X := -48.6
const SHOT_X := -42.5
const ROLL_SPEED := 13.5
const CASE_SECONDS := 1.55
const GLOVE_REACH := FootballBall.RADIUS + FootballKeeperVisual.GLOVE_RADIUS
const CASES := [
	{"label": "Low roll to the keeper's left", "lane": -1.3, "expect_save": true},
	{"label": "Low roll to the keeper's right", "lane": 1.3, "expect_save": true},
	{"label": "Wide roll outside the post", "lane": 4.9, "expect_save": false},
]


class DrillActors extends Node3D:
	var phase := "playing"


class SampleProbe extends Node:
	var capture: Callable

	func _physics_process(_delta: float) -> void:
		capture.call()


var _world: Node3D
var _keeper: FootballGoalkeeper
var _ball: FootballBall
var _camera: Camera3D
var _caption: Label
var _players: Array[FootballPlayer] = []
var _events: Array[Dictionary] = []
var _samples: Array[Dictionary] = []
var _delta: float
var _launch_frame := -1
var _active := false


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
	var results: Array[Dictionary] = []
	var passed := true
	for spec: Dictionary in CASES:
		var result: Dictionary = await _run_case(spec)
		results.append(result)
		passed = passed and bool(result["passed"])
	var report := FileAccess.open(report_path, FileAccess.WRITE)
	if report == null:
		push_error("Could not write low-save report at %s" % report_path)
		quit(2)
		return
	report.store_string(JSON.stringify({
		"passed": passed, "physics_hz": Engine.physics_ticks_per_second,
		"glove_reach_m": GLOVE_REACH, "launch_speed_mps": ROLL_SPEED, "cases": results,
	}, "\t") + "\n")
	report.close()
	print("ELEVEN_LOW_SAVE_ACCEPTANCE %s %s" % ["PASS" if passed else "FAIL", report_path])
	quit(0 if passed else 1)


func _build_fixture() -> void:
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
	_camera.size = 11.0
	_camera.position = Vector3(-35.5, 7.0, -8.0)
	_world.add_child(_camera)
	_camera.look_at(Vector3(-46.4, 0.45, 0.55))
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
	probe.capture = _sample
	probe.process_physics_priority = 1000
	_world.add_child(probe)


func _run_case(spec: Dictionary) -> Dictionary:
	var actors := DrillActors.new()
	_world.add_child(actors)
	_keeper = FootballGoalkeeper.new()
	_keeper.full_pitch = true
	_keeper.eleven_slot = 10
	_keeper.player_id = "test_keeper"
	_keeper.player_name = "DAN"
	_keeper.position = Vector3(KEEPER_X, 0.05, 0.0)
	actors.add_child(_keeper)
	_keeper.ai_rng.seed = 81100
	_players = [_keeper]
	var lane := float(spec["lane"])
	_ball = FootballBall.new()
	_ball.position = Vector3(SHOT_X, FootballBall.RADIUS + 0.001, lane)
	_ball.set_collision_mask_value(ElevenPitch.NET_COLLISION_LAYER, true)
	actors.add_child(_ball)
	_keeper.physical_event.connect(_capture_event)
	_events = []
	_samples = []
	_caption.text = "%s  •  Ready" % spec["label"]
	await _drive(0.35)
	_launch_frame = Engine.get_physics_frames()
	_ball.angular_velocity = Vector3.UP.cross(Vector3.LEFT * ROLL_SPEED) / FootballBall.RADIUS
	_ball.touch(1, "fixture_roll", Vector3.LEFT * ROLL_SPEED * _ball.mass)
	_active = true
	_caption.text = "%s  •  Live ball" % spec["label"]
	await _drive(CASE_SECONDS)
	_active = false
	var result := _assess(spec)
	actors.queue_free()
	_keeper = null
	_ball = null
	_players.clear()
	await process_frame
	return result


func _drive(seconds: float) -> void:
	for tick in range(ceili(seconds / _delta)):
		await physics_frame
		_keeper.decide_keeper(_players, _ball, _delta)


func _sample() -> void:
	if not _active:
		return
	var hands := _keeper.hand_positions()
	var framed := _visible(_keeper.global_position + Vector3.UP) and _visible(_ball.global_position)
	for hand in hands:
		framed = framed and _visible(hand)
	_samples.append({
		"frame": Engine.get_physics_frames(), "ball": _vec(_ball.global_position),
		"velocity": _vec(_ball.linear_velocity), "keeper": _vec(_keeper.global_position),
		"hands": [_vec(hands[0]), _vec(hands[1])], "pose": _keeper.keeper_state,
		"framed": framed, "free": not _ball.freeze and _ball.grip_holder_id.is_empty(),
		"finite": _ball.global_position.is_finite() and _ball.linear_velocity.is_finite()
			and _keeper.global_position.is_finite() and hands[0].is_finite() and hands[1].is_finite(),
	})


func _visible(point: Vector3) -> bool:
	return not _camera.is_position_behind(point) and root.get_visible_rect().grow(-12).has_point(_camera.unproject_position(point))


func _capture_event(kind: String, detail: Dictionary) -> void:
	if not _active:
		return
	var frame := Engine.get_physics_frames()
	var ball_position := _ball.global_position
	var record := {"kind": kind, "frame": frame, "detail": detail}
	if kind in ["keeper_catch", "keeper_parry"]:
		var hands := _keeper.hand_positions()
		var nearest := INF
		for index in range(hands.size()):
			var before := _keeper.previous_hands[index] - _keeper.previous_ball_position
			var after := hands[index] - ball_position
			var motion := after - before
			var fraction := clampf(-before.dot(motion) / maxf(0.0000001, motion.length_squared()), 0.0, 1.0)
			nearest = minf(nearest, before.lerp(after, fraction).length())
		record.merge({
			"serial": _ball.touch_serial, "ball": _vec(ball_position),
			"keeper_inside": _keeper.area_contains(_keeper.global_position),
			"ball_inside": _keeper.area_contains(ball_position),
			"visible_glove_sweep_gap_m": nearest,
		})
		_caption.text = "Glove contact  •  Ball stays live"
	_events.append(record)


func _assess(spec: Dictionary) -> Dictionary:
	var crossed := false
	var framed := true
	var free := true
	var finite := true
	var min_before_height := INF
	var max_before_height := 0.0
	var away_speed := 0.0
	var saw_low_save := false
	var save: Dictionary = {}
	for event in _events:
		if event["kind"] in ["keeper_catch", "keeper_parry"]:
			save = event
			break
	var contact_frame := int(save.get("frame", -1))
	for sample in _samples:
		var ball: Array = sample["ball"]
		var velocity: Array = sample["velocity"]
		var frame := int(sample["frame"])
		crossed = crossed or float(ball[0]) <= -ElevenPitch.HALF_LENGTH - FootballBall.RADIUS
		if frame <= _launch_frame + ceili(1.0 / _delta):
			framed = framed and bool(sample["framed"])
		free = free and bool(sample["free"])
		finite = finite and bool(sample["finite"])
		if contact_frame < 0 or frame < contact_frame:
			saw_low_save = saw_low_save or sample["pose"] == "low_save"
			min_before_height = minf(min_before_height, float(ball[1]))
			max_before_height = maxf(max_before_height, float(ball[1]))
		elif frame >= contact_frame + 2 and frame <= contact_frame + 12:
			away_speed = maxf(away_speed, float(velocity[0]))
	var audited := false
	if not save.is_empty():
		for entry in _ball.impulse_audit:
			if (entry["serial"] == save["serial"] and entry["player_id"] == _keeper.player_id
					and entry["physics_frame"] == contact_frame and float(entry["impulse"][0]) > 0.01):
				audited = true
	var checks := {"free_ball": free, "finite_physics": finite, "action_in_frame": framed and not _samples.is_empty()}
	if bool(spec["expect_save"]):
		var detail: Dictionary = save.get("detail", {})
		var is_low_contact: bool = detail.get("pose") == "low_save" and float(detail.get("ball_height", INF)) < 0.23
		checks["ground_roll_before_contact"] = min_before_height > 0.08 and max_before_height <= 0.20
		checks["low_pose_before_contact"] = saw_low_save
		checks["physical_glove_parry"] = (save.get("kind") == "keeper_parry" and audited and is_low_contact
			and bool(save.get("keeper_inside", false)) and bool(save.get("ball_inside", false))
			and float(save.get("visible_glove_sweep_gap_m", INF)) <= GLOVE_REACH + 0.0001)
		checks["parry_redirects_away_from_goal"] = away_speed > 1.0 and not crossed
	else:
		checks["wide_ball_crosses_end_line"] = crossed
		checks["wide_ball_has_no_save_impulse"] = save.is_empty() and _ball.impulse_audit.size() == 1
	return {
		"label": spec["label"], "launch_frame": _launch_frame, "last_frame": Engine.get_physics_frames(),
		"passed": not checks.values().has(false), "checks": checks, "save": save,
		"max_precontact_ball_height_m": max_before_height, "max_outfield_speed_after_contact_mps": away_speed,
		"events": _events, "impulses": _ball.impulse_audit.duplicate(true), "samples": _samples,
	}


func _vec(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
