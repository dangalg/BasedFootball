extends Node

# One rendered sequence using the production rigid bodies and dribble/tackle code.
# Direct intents isolate ball handling from hardware input; no Input events injected.
var game: Node3D
var carrier: FootballPlayer
var challenger: FootballPlayer
var stage: int = -1
var elapsed: float = 0.0
var finished: bool = false
var evidence_dir: String
var samples: Array[Dictionary] = []
var images: Array[String] = []
var checks := {}
var walk_distance_sum: float = 0.0
var walk_samples: int = 0
var close_control_max_distance: float = 0.0
var sprint_max_distance: float = 0.0
var stop_distance: float = INF
var stop_ball_speed: float = INF
var turn_positions: Array[Array] = []
var starting_position := Vector3.ZERO
var fixture_touch_count: int = 0
var tackle_max_distance: float = 0.0
var tackle_recorded: bool = false
var stage_start_position := Vector3.ZERO
var reverse_position: Array = []
var max_steady_gap: float = 0.0

const DURATIONS := [1.0, 1.65, 1.3, 1.3, 1.6, 1.5, 1.5, 1.5, 1.0, 0.65, 0.25]
const NAMES := ["settle", "full_stick_carry", "turn_left", "turn_right", "reverse_180", "stop", "sprint", "settle_for_challenge", "tackle", "out_of_reach", "airborne"]

func begin(match_node: Node3D) -> void:
	game = match_node
	game.set_physics_process(false)
	game.set_process(false)
	game.set_process_unhandled_input(false)
	process_physics_priority = -100
	carrier = game.players[0]
	challenger = game.players[3]
	for i in range(game.players.size()):
		var player: FootballPlayer = game.players[i]
		player.intent = Vector3.ZERO
		if player != carrier:
			player.freeze = true
			player.global_position = Vector3(12, 0.06, -9 + i * 3)
	game.camera.size = 25
	game.camera.position = Vector3(0, 23, 19)
	game.camera.look_at(Vector3.ZERO)
	evidence_dir = OS.get_environment("BASED_FOOTBALL_EVIDENCE")
	if evidence_dir.is_empty():
		evidence_dir = ProjectSettings.globalize_path("res://evidence")
	DirAccess.make_dir_recursive_absolute(evidence_dir)
	game.hud.status.text = "FULL-STICK TIGHT-TURN TEST  /  HARDWARE INPUT DISABLED"
	_fixture(Vector3(-8, 0.06, 4), Vector3(0.76, 0.3, 0))
	starting_position = carrier.global_position
	_next_stage()
	print("DRIBBLE_ACCEPTANCE_STARTED: one off-screen full-stick sequence; 90-degree turns and 180-degree reversal; production physics; no injected gamepad input")

func _fixture(player_position: Vector3, ball_offset: Vector3) -> void:
	carrier.global_position = player_position
	carrier.linear_velocity = Vector3.ZERO
	carrier.angular_velocity = Vector3.ZERO
	carrier.intent = Vector3.ZERO
	carrier.sprint = false
	carrier.aim = Vector3.RIGHT
	carrier.touch_cooldown = 0
	carrier.kick_cooldown = 0
	carrier.energy = 1
	carrier.close_control_remaining = 0
	carrier.reset_physics_interpolation()
	game.ball.global_position = player_position + ball_offset
	game.ball.linear_velocity = Vector3.ZERO
	game.ball.angular_velocity = Vector3.ZERO
	game.ball.last_touch_team = 0
	game.ball.reset_physics_interpolation()

func _physics_process(delta: float) -> void:
	if game == null or finished:
		return
	elapsed += delta
	if elapsed >= float(DURATIONS[stage]):
		_end_stage()
		_next_stage()
		if finished:
			return
	var direction := Vector3.ZERO
	if stage == 1 or stage == 3:
		direction = Vector3.RIGHT
	elif stage == 2:
		direction = Vector3.FORWARD
	elif stage == 4:
		direction = Vector3.LEFT
	elif stage == 6:
		direction = Vector3.RIGHT
	carrier.intent = direction
	carrier.sprint = stage == 6
	if direction.length_squared() > 0.01:
		carrier.aim = direction.normalized()
	carrier.dribble(game.ball)
	var offset: Vector3 = game.ball.global_position - carrier.global_position
	offset.y = 0
	var distance := offset.length()
	if stage >= 1 and stage <= 4:
		close_control_max_distance = maxf(close_control_max_distance, distance)
		walk_distance_sum += distance
		walk_samples += 1
	if stage == 1:
		max_steady_gap = maxf(max_steady_gap, distance)
	if stage == 6:
		sprint_max_distance = maxf(sprint_max_distance, distance)
	if stage == 8:
		tackle_max_distance = maxf(tackle_max_distance, distance)
	if Engine.get_physics_frames() % 12 == 0:
		samples.append({"stage": NAMES[stage], "time": snappedf(elapsed, 0.001), "gap": distance, "ball_speed": game.ball.linear_velocity.length(), "player_speed": Vector3(carrier.linear_velocity.x, 0, carrier.linear_velocity.z).length(), "stick": direction.length(), "player": _vector(carrier.global_position), "ball": _vector(game.ball.global_position)})

func _process(_delta: float) -> void:
	if game == null or finished:
		return
	game.hud.update_match(game.scores, game.remaining, carrier, 0)
	game.aim_line.position = carrier.global_position + carrier.aim * 1.5 + Vector3(0, 0.05, 0)
	game.aim_line.rotation.y = atan2(carrier.aim.x, carrier.aim.z)

func _next_stage() -> void:
	stage += 1
	elapsed = 0
	if stage >= DURATIONS.size():
		_complete()
		return
	game.hud.flash("DRIBBLE CHECK / " + str(NAMES[stage]).to_upper(), float(DURATIONS[stage]))
	stage_start_position = carrier.global_position
	if stage == 7:
		# Separate challenge fixture: settle a nearby ball, then tackle it away.
		_fixture(Vector3(0, 0.06, 0), Vector3(0.8, 0.3, 0))
	elif stage == 8:
		challenger.global_position = Vector3(game.ball.global_position.x, 0.06, game.ball.global_position.z + 0.85)
		challenger.freeze = false
		challenger.aim = Vector3.FORWARD
		challenger.intent = Vector3.ZERO
		challenger.tackle_cooldown = 0
		tackle_recorded = challenger.tackle(game.ball)
	elif stage == 9:
		challenger.freeze = true
		challenger.global_position = Vector3(12, 0.06, -9)
		_fixture(Vector3(0, 0.06, 0), Vector3(1.6, 0.3, 0))
		game.ball.linear_velocity = Vector3(3, 0, 0)
		fixture_touch_count = game.ball.touches
	elif stage == 10:
		_fixture(Vector3(0, 0.06, 0), Vector3(0.8, 1.5, 0))
		game.ball.linear_velocity = Vector3(0, 2, 0)
		fixture_touch_count = game.ball.touches

func _end_stage() -> void:
	var offset: Vector3 = game.ball.global_position - carrier.global_position
	offset.y = 0
	if stage == 1:
		checks["full_stick_carry_moves_player"] = carrier.global_position.x - starting_position.x > 5.0
	if stage in [1, 2, 3]:
		turn_positions.append(_vector(carrier.global_position))
		_capture(str(NAMES[stage]))
	if stage == 4:
		reverse_position = _vector(carrier.global_position)
		checks["reversal_moves_backwards"] = carrier.global_position.x < stage_start_position.x - 3.0
		checks["reversal_finishes_with_ball"] = carrier.reach_ball(game.ball)
		_capture("reverse_180")
	if stage == 5:
		stop_distance = offset.length()
		stop_ball_speed = Vector3(game.ball.linear_velocity.x, 0, game.ball.linear_velocity.z).length()
		checks["stop_within_kicking_reach"] = carrier.reach_ball(game.ball)
		checks["stop_settles_ball"] = stop_ball_speed < 0.35
		_capture("stop")
	if stage == 6:
		_capture("sprint")
	if stage == 8:
		checks["opponent_tackle_breaks_possession"] = tackle_recorded and tackle_max_distance > 1.3 and game.ball.last_touch_team == 1
		_capture("tackle")
	if stage == 9:
		checks["out_of_reach_ball_stays_free"] = game.ball.touches == fixture_touch_count and offset.length() > 2.3
	if stage == 10:
		checks["airborne_ball_stays_free"] = game.ball.touches == fixture_touch_count

func _capture(label: String) -> void:
	# Preserve the last rendered frame before the next fixture is installed.
	var path := evidence_dir.path_join("tight_turn_%s.png" % label)
	if get_viewport().get_texture().get_image().save_png(path) == OK:
		images.append(path)

func _complete() -> void:
	finished = true
	carrier.intent = Vector3.ZERO
	await RenderingServer.frame_post_draw
	var walk_average := walk_distance_sum / maxi(walk_samples, 1)
	checks["full_stick_turns_keep_ball_in_kicking_reach"] = close_control_max_distance < 1.15
	checks["left_turn_moves_upfield"] = float(turn_positions[1][2]) < float(turn_positions[0][2]) - 3.0
	checks["right_turn_moves_across_field"] = float(turn_positions[2][0]) > float(turn_positions[1][0]) + 3.0
	checks["sprint_touches_are_longer"] = sprint_max_distance > walk_average + 0.08
	checks["rendered_evidence"] = images.size() == 7
	var passed := true
	for value in checks.values():
		passed = passed and bool(value)
	var report := {"pass": passed, "checks": checks, "normal_stick_strength": 1.0, "close_control_max_gap": close_control_max_distance, "close_control_mean_gap": walk_average, "steady_carry_max_gap": max_steady_gap, "stop_gap": stop_distance, "stop_ball_speed": stop_ball_speed, "sprint_max_gap": sprint_max_distance, "tackle_max_gap": tackle_max_distance, "turn_positions": turn_positions, "reverse_position": reverse_position, "screenshots": images, "window_position": [DisplayServer.window_get_position().x, DisplayServer.window_get_position().y], "hardware_input_disabled": true, "gamepad_events_injected": false, "hardware_controller_feel_verified": false}
	var file := FileAccess.open(evidence_dir.path_join("tight-turn-acceptance.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	var trace := FileAccess.open(evidence_dir.path_join("tight-turn-trace.json"), FileAccess.WRITE)
	trace.store_string(JSON.stringify(samples, "\t"))
	trace.close()
	print("DRIBBLE_ACCEPTANCE_RESULT: " + JSON.stringify(report))
	get_tree().quit(0 if passed else 1)

func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
