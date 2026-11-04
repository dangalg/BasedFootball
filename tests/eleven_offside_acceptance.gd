extends SceneTree

## --headless --script res://tests/eleven_offside_acceptance.gd
## -- --eleven-acceptance --report=<fresh absolute JSON path>
## --referee-movie adds lead-in and post-signal observation for off-screen capture.

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
	if not is_instance_valid(game.referee):
		push_error("Expected the production eleven-a-side referee.")
		quit(2)
		return
	var report := await _exercise(game, "--referee-movie" in arguments)
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


func _exercise(game: Node3D, referee_movie: bool) -> Dictionary:
	var passer: FootballPlayer = game.controlled
	var forward: FootballPlayer = game.home_outfield[1]
	var defender: FootballPlayer = game.away_outfield[0]
	var ball: FootballBall = game.ball
	var referee: ElevenReferee = game.referee
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
	var referee_start := referee.global_position
	var tracking_direction := FootballReception.flat(ball.global_position - referee_start).normalized()
	# Keep ordinary AI out of the lane during the two labelled fixture touches.
	var settle_seconds := 0.50 if referee_movie else 0.23
	for _frame in range(ceili(settle_seconds * hz)):
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
	var referee_before_flag := referee.global_position
	var referee_progress := FootballReception.flat(referee_before_flag - referee_start).dot(tracking_direction)
	var involvement_gap := FootballReception.flat(involvement - forward.global_position).length()
	var involvement_serial := -1
	if reached_forward and no_early_flag and involvement_gap <= 0.75:
		ball.touch(forward.team, forward.player_id, Vector3.RIGHT * ball.mass * 0.08)
		involvement_serial = ball.touch_serial
	game.kickoff_remaining = 0.0
	var restart_state: Dictionary = {}
	var clock_before_restart: float = game.remaining
	var resume := false
	var indirect_signal := false
	var strike_signal := ""
	var strike_frame := -1
	var strike_serial := -1
	var subsequent_touch_frame := -1
	var play_signal_frame := -1
	var signal_fixture: Dictionary = {}
	for _frame in range(ceili(5.5 * hz)):
		await physics_frame
		var frame := Engine.get_physics_frames()
		if restart_state.is_empty() and game.restart.get("kind") == "indirect_free_kick":
			var taker: FootballPlayer = game.restart["taker"]
			restart_state = {"team": taker.team, "taker": taker.player_id, "spot": _vector(ball.global_position), "ball_frozen": ball.freeze}
		if game.restart.get("kind") == "indirect_free_kick" and referee.signal_kind == "indirect":
			indirect_signal = true
		if strike_frame < 0 and not restart_state.is_empty() and ball.touch_serial > involvement_serial and ball.last_touch_id == restart_state["taker"]:
			strike_frame = frame
			strike_serial = ball.touch_serial
			strike_signal = referee.signal_kind
		if not restart_state.is_empty() and game.restart.is_empty() and float(game.remaining) < clock_before_restart - 0.08:
			resume = true
		if strike_serial >= 0 and ball.touch_serial > strike_serial:
			if subsequent_touch_frame < 0:
				subsequent_touch_frame = frame
			if play_signal_frame < 0 and referee.signal_kind == "play":
				play_signal_frame = frame
		if resume and play_signal_frame >= 0 and (not referee_movie or frame - play_signal_frame >= ceili(0.35 * hz)):
			break
		if resume and strike_frame >= 0 and subsequent_touch_frame < 0 and signal_fixture.is_empty() and frame - strike_frame >= ceili(1.15 * hz):
			# If nobody has received it yet, supply one labelled additional touch.
			var next_player := _nearest_other_player(game.players, ball.global_position, str(restart_state["taker"]))
			if next_player != null:
				signal_fixture = {"frame": frame, "actor": next_player.player_id, "distance_m": next_player.global_position.distance_to(ball.global_position)}
				ball.touch(next_player.team, next_player.player_id, Vector3.RIGHT * ball.mass * 0.02)
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
		"referee_tracked_live_ball": referee_progress >= 0.08,
		"referee_signaled_indirect_through_strike": indirect_signal and strike_serial == free_kick_serial and strike_signal == "indirect",
		"referee_resumed_play_after_another_touch": subsequent_touch_frame > strike_frame and play_signal_frame >= subsequent_touch_frame,
	}
	return {
		"passed": not checks.values().has(false), "checks": checks,
		"fixture": "Initial placements and two labelled impulses via FootballBall.touch. Ball rolls between touches. Production match owns the decision and restart.",
		"pass_origin": _vector(pass_origin), "pass_serial": pass_serial, "pass_frame": pass_frame,
		"defender_line_x": defender_line, "forward_x_at_pass": forward_depth,
		"involvement": _vector(involvement), "involvement_gap_m": involvement_gap, "involvement_serial": involvement_serial,
		"restart": restart_state, "match_action_log": events, "impulse_audit": ball.impulse_audit.duplicate(true),
		"referee": {
			"movie_mode": referee_movie, "setup_position": _vector(referee_start), "position_before_flag": _vector(referee_before_flag),
			"tracking_progress_m": referee_progress, "strike_signal": strike_signal, "strike_frame": strike_frame,
			"subsequent_touch_frame": subsequent_touch_frame, "play_signal_frame": play_signal_frame, "labelled_followup_touch": signal_fixture,
		},
	}


func _nearest_other_player(players: Array, point: Vector3, excluded: String) -> FootballPlayer:
	var nearest: FootballPlayer = null
	var nearest_gap := INF
	for player: FootballPlayer in players:
		if player.player_id == excluded:
			continue
		var gap := player.global_position.distance_squared_to(point)
		if gap < nearest_gap:
			nearest = player
			nearest_gap = gap
	return nearest


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
