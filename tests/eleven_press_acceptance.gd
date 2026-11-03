extends SceneTree

## --headless --script res://tests/eleven_press_acceptance.gd
## -- --eleven-acceptance --report=<fresh absolute JSON path>

const MATCH := preload("res://scenes/eleven_match.tscn")
const SAVE_PATH := "user://eleven_acceptance_squad.json"


class PressInput extends Node:
	var movement := Vector2(0.0, 0.16)
	var sprinting := false
	var actions := {"teammate_press": true}

	func decide(_delta: float) -> void:
		pass


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
	var game := MATCH.instantiate() as Node3D
	root.add_child(game)
	current_scene = game
	if not game.acceptance or game.squad.save_path != SAVE_PATH or game.phase != "playing":
		push_error("Expected the isolated eleven-a-side match without the setup menu.")
		quit(2)
		return
	var report := await _exercise(game)
	if FileAccess.file_exists(report_path):
		push_error("Report already exists at %s" % report_path)
		quit(2)
		return
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not open report at %s" % report_path)
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("ELEVEN_PRESS_ACCEPTANCE %s %s" % ["PASS" if report["passed"] else "FAIL", report_path])
	quit(0 if report["passed"] else 1)


func _exercise(game: Node3D) -> Dictionary:
	var human: FootballPlayer = game.controlled
	var presser: FootballPlayer = game.home_outfield[4]
	var cover: FootballPlayer = game.home_outfield[3]
	var carrier: FootballPlayer = game.away_outfield[0]
	var ball: FootballBall = game.ball
	var hz := Engine.physics_ticks_per_second
	for index in range(game.players.size()):
		var player: FootballPlayer = game.players[index]
		player.ai_rng.seed = 81100 + index
	_place(human, Vector3(-21.5, 0.06, -5.5), Vector3.RIGHT)
	_place(presser, Vector3(-24.0, 0.06, -8.0), Vector3.RIGHT)
	_place(cover, Vector3(-24.0, 0.06, -14.0), Vector3.RIGHT)
	_place(carrier, Vector3(-19.0, 0.06, -8.0), Vector3.LEFT)
	ball.global_position = Vector3(-19.53, FootballBall.RADIUS, -8.0)
	ball.reset_physics_interpolation()
	for _frame in range(ceili(0.23 * hz)):
		await physics_frame
	# Seed a live rolling ball and opponent chase. No fixture writes after this.
	ball.touch(carrier.team, carrier.player_id, Vector3.LEFT * ball.mass * 0.95)
	carrier._remember_free_ball(ball, Vector3.LEFT)
	var had_chase := carrier.chasing_ball(ball)
	var seed_serial := ball.touch_serial
	var ball_start := ball.global_position
	var human_start := human.global_position
	var press_start := presser.global_position
	var cover_start := cover.global_position
	var cover_direction := FootballReception.flat(ball_start - cover_start).normalized()
	var press_direction := FootballReception.flat(ball_start - press_start).normalized()
	var human_initial_gap := FootballReception.flat(ball_start - human_start).length()
	var press_initial_gap := FootballReception.flat(ball_start - press_start).length()
	var driver := PressInput.new()
	game.add_child(driver)
	game.decision_driver = driver
	var first_event: int = game.action_log.size()
	game.kickoff_remaining = 0.0
	var samples: Array[Dictionary] = []
	var nominates_expected := false
	var cover_max_advance := 0.0
	var human_max_drift := 0.0
	var human_max_depth_drift := 0.0
	for _frame in range(ceili(0.45 * hz)):
		await physics_frame
		var nominated: FootballPlayer = game.pressure_teammate
		nominates_expected = nominates_expected or nominated == presser
		cover_max_advance = maxf(cover_max_advance, (cover.global_position - cover_start).dot(cover_direction))
		human_max_drift = maxf(human_max_drift, FootballReception.flat(human.global_position - human_start).length())
		human_max_depth_drift = maxf(human_max_depth_drift, absf(human.global_position.x - human_start.x))
		samples.append({
			"frame": Engine.get_physics_frames(), "nominated": nominated.player_id if nominated != null else "",
			"human": _vector(human.global_position), "presser": _vector(presser.global_position),
			"cover": _vector(cover.global_position), "carrier": _vector(carrier.global_position),
			"ball": _vector(ball.global_position), "touch_serial": ball.touch_serial,
		})
	var press_advance := (presser.global_position - press_start).dot(press_direction)
	var press_gap := FootballReception.flat(ball.global_position - presser.global_position).length()
	var human_gap := FootballReception.flat(ball.global_position - human.global_position).length()
	var still_nominated: bool = game.pressure_teammate == presser
	var release_event_index: int = game.action_log.size()
	driver.actions["teammate_press"] = false
	await physics_frame
	await physics_frame
	var events: Array = game.action_log.slice(first_event)
	var release_events: Array = game.action_log.slice(release_event_index)
	var started := _event(events, "pressure_started", presser.player_id)
	var ended := _event(release_events, "pressure_ended", presser.player_id)
	var starts := 0
	for event: Dictionary in events:
		if event.get("kind") == "pressure_started":
			starts += 1
	var checks := {
		"away_had_live_chase": had_chase,
		"controlled_started_closer_than_presser": human_initial_gap < press_initial_gap,
		"nominated_one_expected_teammate": nominates_expected and starts == 1 and not started.is_empty(),
		"presser_closed_down": press_advance >= 0.85 and press_gap < human_gap,
		"human_held_lane": human_max_drift >= 0.06 and human_max_drift <= 0.65 and human_max_depth_drift <= 0.18,
		"other_defender_held_shape": cover_max_advance <= 0.55 and press_advance - cover_max_advance >= 0.65,
		"release_cleared_nomination": still_nominated and game.pressure_teammate == null and not ended.is_empty(),
	}
	return {
		"passed": not checks.values().has(false), "checks": checks,
		"fixture": "Initial positions and preceding away touch only. Production match applies held/released pressure input each physics tick.",
		"human": human.player_id, "presser": presser.player_id, "cover": cover.player_id, "carrier": carrier.player_id,
		"seed_serial": seed_serial, "presser_advance_m": press_advance, "cover_max_advance_m": cover_max_advance,
		"human_max_drift_m": human_max_drift, "human_max_depth_drift_m": human_max_depth_drift,
		"human_initial_gap_m": human_initial_gap, "presser_initial_gap_m": press_initial_gap,
		"human_gap_at_release_m": human_gap, "presser_gap_at_release_m": press_gap,
		"samples": samples, "match_action_log": events,
	}


func _place(player: FootballPlayer, position: Vector3, aim: Vector3) -> void:
	player.global_position = position
	player.aim = aim
	player.reset_physics_interpolation()


func _event(events: Array, kind: String, player_id: String) -> Dictionary:
	for event: Dictionary in events:
		if event.get("kind") == kind and event.get("player") == player_id:
			return event
	return {}


func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
