extends SceneTree

## --headless --script res://tests/eleven_offside_acceptance.gd
## -- --eleven-acceptance --report=<fresh absolute JSON path>

const MATCH := preload("res://scenes/eleven_match.tscn")
const SAVE_PATH := "user://eleven_acceptance_squad.json"


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
	print("ELEVEN_OFFSIDE_ACCEPTANCE %s %s" % ["PASS" if report["passed"] else "FAIL", report_path])
	quit(0 if report["passed"] else 1)


func _exercise(game: Node3D) -> Dictionary:
	var passer: FootballPlayer = game.controlled
	var forward: FootballPlayer = game.home_outfield[1]
	var defender: FootballPlayer = game.away_outfield[0]
	var ball: FootballBall = game.ball
	var hz := Engine.physics_ticks_per_second
	for index in range(game.players.size()):
		var player: FootballPlayer = game.players[index]
		player.ai_rng.seed = 81100 + index
		if player.team == 1 and not player.is_goalkeeper:
			_place(player, Vector3(7.0 + float(player.eleven_slot) * 0.5, 0.06, player.eleven_home.z + 4.0))
	_place(defender, Vector3(15.0, 0.06, 4.0))
	_place(passer, Vector3(13.0, 0.06, 0.0))
	_place(forward, Vector3(17.0, 0.06, 0.58))
	ball.global_position = Vector3(13.53, FootballBall.RADIUS, 0.0)
	ball.reset_physics_interpolation()
	# Keep ordinary AI out of the lane during the two labelled fixture touches.
	for _frame in range(ceili(0.23 * hz)):
		await physics_frame
	var first_event: int = game.action_log.size()
	var pass_origin := ball.global_position
	var defender_line := defender.global_position.x
	var forward_depth := forward.global_position.x
	ball.touch(passer.team, passer.player_id, Vector3.RIGHT * ball.mass * 9.0)
	var pass_serial := ball.touch_serial
	var pass_frame := Engine.get_physics_frames()
	var reached_forward := false
	for _frame in range(ceili(0.90 * hz)):
		await physics_frame
		if ball.global_position.x >= forward_depth - 0.23:
			reached_forward = true
			break
	var before_involvement: Array = game.action_log.slice(first_event)
	var no_early_flag: bool = _event(before_involvement, "offside").is_empty() and game.restart.is_empty() and ball.touch_serial == pass_serial
	var involvement := ball.global_position
	var involvement_gap := FootballReception.flat(involvement - forward.global_position).length()
	var involvement_serial := -1
	if reached_forward and no_early_flag and involvement_gap <= 0.75:
		ball.touch(forward.team, forward.player_id, Vector3.RIGHT * ball.mass * 0.08)
		involvement_serial = ball.touch_serial
	game.kickoff_remaining = 0.0
	var restart_state: Dictionary = {}
	var clock_before_restart: float = game.remaining
	var resume := false
	for _frame in range(ceili(4.0 * hz)):
		await physics_frame
		if restart_state.is_empty() and game.restart.get("kind") == "indirect_free_kick":
			var taker: FootballPlayer = game.restart["taker"]
			restart_state = {"team": taker.team, "taker": taker.player_id, "spot": _vector(ball.global_position), "ball_frozen": ball.freeze}
		if not restart_state.is_empty() and game.restart.is_empty() and float(game.remaining) < clock_before_restart - 0.08:
			resume = true
			break
	var events: Array = game.action_log.slice(first_event)
	var flag := _event(events, "offside")
	var taken := _event(events, "restart_taken", "indirect_free_kick")
	var flag_spot := _read_vector(flag.get("spot", []))
	var free_kick_serial := int(taken.get("touch_serial", -1))
	var free_kick_impulse := false
	for entry in ball.impulse_audit:
		if entry["serial"] == free_kick_serial and entry["player_id"] == restart_state.get("taker") and entry["team"] == 1:
			free_kick_impulse = _read_vector(entry["impulse"]).length_squared() > 0.00001
			break
	var checks := {
		"attacker_beyond_ball_and_second_last_defender_at_pass": forward_depth > maxf(pass_origin.x, defender_line) and defender_line > 0.0,
		"no_flag_until_active_touch": no_early_flag and reached_forward and involvement_gap <= 0.75 and involvement_serial == pass_serial + 1,
		"offender_flagged_at_involvement": flag.get("player", "") == forward.player_id and flag.get("team", -1) == 0 and flag_spot.is_finite() and FootballReception.flat(flag_spot - involvement).length() <= 0.12,
		"away_awarded_indirect_free_kick": restart_state.get("team", -1) == 1 and restart_state.get("ball_frozen", false),
		"indirect_free_kick_contact_and_resume": resume and taken.get("team", -1) == 1 and free_kick_serial > involvement_serial and free_kick_impulse,
	}
	return {
		"passed": not checks.values().has(false), "checks": checks,
		"fixture": "Initial placements and two labelled impulses via FootballBall.touch. Ball rolls between touches. Production match owns the decision and restart.",
		"pass_origin": _vector(pass_origin), "pass_serial": pass_serial, "pass_frame": pass_frame,
		"defender_line_x": defender_line, "forward_x_at_pass": forward_depth,
		"involvement": _vector(involvement), "involvement_gap_m": involvement_gap, "involvement_serial": involvement_serial,
		"restart": restart_state, "match_action_log": events, "impulse_audit": ball.impulse_audit.duplicate(true),
	}


func _place(player: FootballPlayer, position: Vector3) -> void:
	player.global_position = position
	player.reset_physics_interpolation()


func _event(events: Array, kind: String, restart_kind: String = "") -> Dictionary:
	for event: Dictionary in events:
		if event.get("kind") == kind and (restart_kind.is_empty() or event.get("restart") == restart_kind):
			return event
	return {}


func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _read_vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2])) if value.size() == 3 else Vector3.INF
