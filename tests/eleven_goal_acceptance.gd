extends SceneTree

## --headless --script res://tests/eleven_goal_acceptance.gd
## -- --eleven-acceptance --report=<fresh absolute JSON path>

const MATCH := preload("res://scenes/eleven_match.tscn")
const SAVE_PATH := "user://eleven_acceptance_squad.json"


class ShotInput extends Node:
	var movement := Vector2.ZERO
	var sprinting := false
	var actions: Dictionary = {}
	var tick := 0
	var release_tick := 0

	func decide(_delta: float) -> void:
		actions.clear()
		if tick == 0:
			actions["primary"] = true
		elif tick == release_tick:
			actions["primary_release"] = true
		tick += 1


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
	print("ELEVEN_GOAL_ACCEPTANCE %s %s" % ["PASS" if report["passed"] else "FAIL", report_path])
	quit(0 if report["passed"] else 1)


func _exercise(game: Node3D) -> Dictionary:
	game._set_ends_swapped(true)
	game.remaining = game.match_duration * 0.5 - 1.0
	game.reset_positions(0)
	var shooter: FootballPlayer = game.controlled
	var ball: FootballBall = game.ball
	var away_keeper: FootballPlayer = game.keepers[1]
	var hz := Engine.physics_ticks_per_second
	for index in range(game.players.size()):
		var player: FootballPlayer = game.players[index]
		player.ai_rng.seed = 81100 + index
	shooter.global_position = Vector3(-46.0, 0.06, 0.0)
	shooter.aim = Vector3.LEFT
	shooter.reset_physics_interpolation()
	away_keeper.global_position.z = 12.0
	away_keeper.reset_physics_interpolation()
	ball.global_position = Vector3(-46.53, FootballBall.RADIUS, 0.0)
	ball.reset_physics_interpolation()
	for _frame in range(ceili(0.50 * hz)):
		await physics_frame
	var seed_serial := ball.touch_serial
	var first_event: int = game.action_log.size()
	var driver := ShotInput.new()
	driver.release_tick = ceili(0.18 * hz)
	game.add_child(driver)
	game.decision_driver = driver
	game.kickoff_remaining = 0.0
	var celebration_frames := 0
	var celebration_clock := -1.0
	var frozen_clock := true
	var ball_in_net := true
	var one_home_goal_on_board := true
	var kickoff_resume := false
	var samples: Array[Dictionary] = []
	for frame in range(ceili(8.0 * hz)):
		await physics_frame
		if game.phase == "goal_celebration":
			celebration_frames += 1
			if celebration_clock < 0.0:
				celebration_clock = game.remaining
			frozen_clock = frozen_clock and is_equal_approx(float(game.remaining), celebration_clock)
			ball_in_net = ball_in_net and not ball.freeze and _inside_left_net(ball.global_position)
			one_home_goal_on_board = one_home_goal_on_board and game.scores == [1, 0]
		if frame % 4 == 0:
			samples.append({
				"frame": Engine.get_physics_frames(), "phase": game.phase, "remaining": game.remaining,
				"position": _vector(ball.global_position), "velocity": _vector(ball.linear_velocity),
				"touch_serial": ball.touch_serial, "ball_frozen": ball.freeze,
			})
		if celebration_clock >= 0.0 and game.phase == "playing" and game.kickoff_remaining <= 0.0 and not is_instance_valid(game.kickoff_taker) and float(game.remaining) < celebration_clock - 0.35:
			kickoff_resume = true
			break
	var events: Array = game.action_log.slice(first_event)
	var goal := _event(events, "goal")
	var shot := _event(events, "kick_contact", shooter.player_id)
	var serial := int(shot.get("touch_serial", -1))
	var audit := ball.impulse_audit.duplicate(true)
	var kickoff := _event(events, "kickoff_taken")
	var celebration_end := _event(events, "goal_celebration_finished", shooter.player_id)
	var kickoff_serial := int(kickoff.get("touch_serial", -1))
	var seconds := float(celebration_frames) / float(hz)
	var gap := float(shot.get("boot_gap", INF))
	var checks := {
		"physical_shot_toward_left_goal": shooter.attack_sign() < 0.0 and shot.get("detail_kind") == "shot" and serial > seed_serial and gap >= 0.0 and gap <= FootballPlayer.STRIKE_BOOT_REACH and _left_impulse(audit, serial, shooter.player_id),
		"home_goal_credited_once_to_shooter": goal.get("team", -1) == 0 and goal.get("player", "") == shooter.player_id and not goal.get("own_goal", true) and _count(events, "goal") == 1 and one_home_goal_on_board and game.scores == [1, 0],
		"celebration_holds_clock_and_ball_in_net": absf(seconds - 1.6) <= 0.04 and frozen_clock and ball_in_net and _count(events, "goal_celebration_finished") == 1 and celebration_end.get("team", -1) == 0,
		"away_kickoff_physically_resumed_play": kickoff_resume and kickoff.get("team", -1) == 1 and kickoff_serial > serial and _left_impulse(audit, kickoff_serial, str(kickoff.get("player", ""))),
	}
	return {
		"passed": not checks.values().has(false), "checks": checks,
		"fixture": "Second-half placement only. Production shot input, physics, scoring, celebration and restart own the ball thereafter.",
		"shooter": shooter.player_id, "score": game.scores, "celebration_seconds": seconds,
		"celebration_clock": celebration_clock, "remaining": game.remaining, "physics_hz": hz,
		"samples": samples, "match_action_log": events, "impulse_audit": audit,
	}


func _inside_left_net(point: Vector3) -> bool:
	return point.is_finite() and -point.x >= ElevenPitch.HALF_LENGTH + FootballBall.RADIUS - 0.002 and -point.x <= ElevenPitch.HALF_LENGTH + ElevenPitch.GOAL_DEPTH + FootballBall.RADIUS and absf(point.z) <= ElevenPitch.GOAL_HALF_WIDTH and point.y <= ElevenPitch.CROSSBAR_HEIGHT


func _left_impulse(audit: Array, serial: int, actor: String) -> bool:
	for entry: Dictionary in audit:
		if entry["serial"] == serial and entry["player_id"] == actor:
			return float(entry["impulse"][0]) < 0.0
	return false


func _event(events: Array, kind: String, player_id: String = "") -> Dictionary:
	for event: Dictionary in events:
		if event.get("kind") == kind and (player_id.is_empty() or event.get("player") == player_id):
			return event
	return {}


func _count(events: Array, kind: String) -> int:
	var count := 0
	for event: Dictionary in events:
		if event.get("kind") == kind:
			count += 1
	return count


func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
