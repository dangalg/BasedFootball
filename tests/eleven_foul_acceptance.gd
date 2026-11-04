extends SceneTree

## --headless --script res://tests/eleven_foul_acceptance.gd
## -- --eleven-acceptance --report=<fresh absolute JSON path>

const MATCH := preload("res://scenes/eleven_match.tscn")
const SAVE_PATH := "user://eleven_acceptance_squad.json"

var _slide_contact: Dictionary = {}


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
	if not game.acceptance or game.squad.save_path != SAVE_PATH or game.phase != "playing" or not is_instance_valid(game.referee):
		push_error("Expected the isolated eleven-a-side match and referee without the setup menu.")
		quit(2)
		return
	var midfield := await _exercise(game, false)
	game.queue_free()
	await process_frame
	game = MATCH.instantiate() as Node3D
	root.add_child(game)
	current_scene = game
	_slide_contact.clear()
	var penalty := await _exercise(game, true)
	var report := {"passed": midfield.passed and penalty.passed, "midfield": midfield, "penalty": penalty}
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
	print("ELEVEN_FOUL_ACCEPTANCE %s %s" % ["PASS" if report["passed"] else "FAIL", report_path])
	quit(0 if report["passed"] else 1)


func _exercise(game: Node3D, penalty: bool) -> Dictionary:
	var victim: FootballPlayer = game.controlled
	var attacker: FootballPlayer = game.away_outfield[0]
	var ball: FootballBall = game.ball
	var referee: ElevenReferee = game.referee
	var hz := Engine.physics_ticks_per_second
	for index in range(game.players.size()):
		var player: FootballPlayer = game.players[index]
		player.ai_rng.seed = 81100 + index
	var restart_kind := "penalty" if penalty else "direct_free_kick"
	var origin := Vector3(38.0 if penalty else 4.0, 0.02, 0.0)
	_place(victim, origin, Vector3.RIGHT)
	_place(attacker, origin + Vector3.RIGHT * 1.8, Vector3.LEFT)
	ball.global_position = origin + Vector3(-4.0, FootballBall.RADIUS - origin.y, -3.0)
	ball.reset_physics_interpolation()
	# Let the fixture settle without ordinary AI taking over the slide setup.
	for _frame in range(ceili(0.23 * hz)):
		await physics_frame
	referee.global_position = origin + Vector3(5.0, -origin.y, 4.0)
	referee.look_at(Vector3(origin.x, 0.0, origin.z), Vector3.UP)
	victim.body_visual.rotation.y = -PI / 2.0
	attacker.body_visual.rotation.y = PI / 2.0
	attacker.physical_event.connect(_capture_slide.bind(victim, ball, referee))
	var seed_serial := ball.touch_serial
	var first_event: int = game.action_log.size()
	game.kickoff_remaining = 0.0
	attacker.linear_velocity = Vector3.LEFT * 6.0
	var queued := attacker.slide(ball)
	for _frame in range(ceili(0.55 * hz)):
		await physics_frame
		if not _slide_contact.is_empty():
			break
	var restart_state: Dictionary = {}
	var clock_at_award := -1.0
	var resumed := false
	for _frame in range(ceili(5.4 * hz)):
		await physics_frame
		if restart_state.is_empty() and game.restart.get("kind") == restart_kind:
			var taker: FootballPlayer = game.restart["taker"]
			restart_state = {"team": taker.team, "taker": taker.player_id, "spot": _vector(ball.global_position), "ball_frozen": ball.freeze, "touch_serial": ball.touch_serial}
			if penalty:
				restart_state["keeper_x"] = game.keepers[1].global_position.x
			clock_at_award = game.remaining
		if not restart_state.is_empty() and game.restart.is_empty() and float(game.remaining) < clock_at_award - 0.08:
			resumed = true
			break
	var events: Array = game.action_log.slice(first_event)
	var foul := _event(events, "foul", attacker.player_id)
	var taker_id := str(restart_state.get("taker", ""))
	var taken := _event(events, "restart_taken", taker_id, restart_kind)
	var serial := int(taken.get("touch_serial", -1))
	var boot := _event(events, "kick_contact", taker_id, "", serial)
	var audited := false
	for entry in ball.impulse_audit:
		if entry["serial"] == serial and entry["player_id"] == taker_id and entry["team"] == victim.team:
			audited = _read_vector(entry["impulse"]).length_squared() > 0.00001
			break
	var contact_spot := _read_vector(_slide_contact.get("contact_spot", []))
	var flag_spot := _read_vector(foul.get("spot", []))
	var restart_spot := _read_vector(restart_state.get("spot", []))
	var expected_spot := Vector3(ElevenPitch.HALF_LENGTH - ElevenPitch.PENALTY_SPOT, FootballBall.RADIUS, 0.0) if penalty else flag_spot
	var at_correct_spot := contact_spot.is_finite() and flag_spot.is_finite() and restart_spot.is_finite() and FootballReception.flat(flag_spot - contact_spot).length() <= 0.35 and FootballReception.flat(restart_spot - expected_spot).length() <= 0.05
	var boot_gap := float(boot.get("boot_gap", INF))
	var checks := {
		"actual_slide_hit_victim": queued and _slide_contact.get("victim", "") == victim.player_id and float(_slide_contact.get("distance", INF)) <= 0.19,
		"referee_witnessed_ball_free_contact": _slide_contact.get("seen", false) and not _slide_contact.get("ball_first", true) and float(_slide_contact.get("ball_gap_m", 0.0)) >= 2.0 and _slide_contact.get("touch_serial", -1) == seed_serial,
		"foul_credited_to_correct_players": foul.get("player", "") == attacker.player_id and foul.get("victim", "") == victim.player_id and foul.get("restart", "") == restart_kind,
		"correct_team_and_spot_for_restart": at_correct_spot and restart_state.get("team", -1) == victim.team and restart_state.get("ball_frozen", false) and restart_state.get("touch_serial", -1) == seed_serial,
		"free_kick_boot_contact_and_play_resumed": resumed and taken.get("team", -1) == victim.team and serial > seed_serial and boot_gap >= 0.0 and boot_gap <= FootballPlayer.STRIKE_BOOT_REACH and audited,
	}
	if penalty:
		checks["penalty_keeper_on_goal_line"] = absf(float(restart_state.get("keeper_x", 0.0)) - ElevenPitch.HALF_LENGTH) <= 0.06
	return {
		"passed": not checks.values().has(false), "checks": checks,
		"fixture": "Initial placements, referee facing and attacker run-up only. The production slide sweep, foul decision and restart own the outcome.",
		"attacker": attacker.player_id, "victim": victim.player_id, "seed_serial": seed_serial,
		"slide_contact": _slide_contact.duplicate(true), "restart": restart_state,
		"match_action_log": events, "impulse_audit": ball.impulse_audit.duplicate(true),
	}


func _capture_slide(kind: String, detail: Dictionary, victim: FootballPlayer, ball: FootballBall, referee: ElevenReferee) -> void:
	if kind != "slide_body_contact" or detail.get("victim", "") != victim.player_id or not _slide_contact.is_empty():
		return
	var spot: Vector3 = detail.get("contact", Vector3.INF)
	_slide_contact = detail.duplicate(true)
	_slide_contact.erase("contact")
	_slide_contact["contact_spot"] = _vector(spot)
	_slide_contact["seen"] = referee.can_see_contact(spot)
	_slide_contact["referee_position"] = _vector(referee.global_position)
	_slide_contact["ball_gap_m"] = FootballReception.flat(ball.global_position - spot).length()
	_slide_contact["touch_serial"] = ball.touch_serial


func _place(player: FootballPlayer, position: Vector3, aim: Vector3) -> void:
	player.global_position = position
	player.aim = aim
	player.reset_physics_interpolation()


func _event(events: Array, kind: String, player_id: String, restart_kind: String = "", serial: int = -1) -> Dictionary:
	for event: Dictionary in events:
		if event.get("kind") == kind and event.get("player") == player_id and (restart_kind.is_empty() or event.get("restart") == restart_kind) and (serial < 0 or event.get("touch_serial", -1) == serial):
			return event
	return {}


func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _read_vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2])) if value.size() == 3 else Vector3.INF
