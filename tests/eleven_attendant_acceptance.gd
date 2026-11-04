extends SceneTree

## --headless --script res://tests/eleven_attendant_acceptance.gd
## -- --eleven-acceptance --report=<fresh absolute JSON path>
## --attendant-movie adds lead-in and follow-through for capture.

const MATCH := preload("res://scenes/eleven_match.tscn")
const SAVE_PATH := "user://eleven_acceptance_squad.json"
const START := Vector3(12.0, FootballBall.RADIUS, 31.2)


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
	var report := await _exercise(game, "--attendant-movie" in arguments)
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
	print("ELEVEN_ATTENDANT_ACCEPTANCE %s %s" % ["PASS" if report["passed"] else "FAIL", report_path])
	quit(0 if report["passed"] else 1)


func _exercise(game: Node3D, movie: bool) -> Dictionary:
	var ball: FootballBall = game.ball
	var sender: FootballPlayer = game.controlled
	var hz := Engine.physics_ticks_per_second
	for index in range(game.players.size()):
		var player: FootballPlayer = game.players[index]
		player.ai_rng.seed = 81100 + index
	ball.global_position = START
	ball.reset_physics_interpolation()
	var settle_seconds := 0.50 if movie else 0.23
	for _frame in range(ceili(settle_seconds * hz)):
		await physics_frame
	var event_start: int = game.action_log.size()
	game.kickoff_remaining = 0.0
	# A labelled home touch rolls the ball out. The tester makes no further ball writes.
	ball.touch(sender.team, sender.player_id, Vector3(3.0, 0.0, 4.0) * ball.mass)
	var exit_serial := ball.touch_serial
	var last_live_point := ball.global_position
	var award: Dictionary = {}
	var attendant: ElevenAttendant
	var attendant_start := Vector3.ZERO
	var first_carry := Vector3.INF
	var carry_distance := 0.0
	var carry_samples := 0
	var entered_pitch := false
	var live_release := false
	var entry_frame := -1
	var samples: Array[Dictionary] = []
	for frame in range(ceili(12.0 * hz)):
		await physics_frame
		var physics_id := Engine.get_physics_frames()
		var stage: String = game.restart.get("attendant_stage", "")
		var point := ball.global_position
		if award.is_empty() and game.restart.get("kind") == "throw_in":
			attendant = game.restart.get("attendant")
			if attendant != null:
				attendant_start = attendant.global_position
			var taker: FootballPlayer = game.restart["taker"]
			award = {
				"frame": physics_id, "taker": taker.player_id, "team": taker.team, "ball": _vector(point),
				"previous_live_ball": _vector(last_live_point), "ball_frozen": ball.freeze,
				"stage": stage, "attendant_registered": attendant != null and attendant in game.attendants,
			}
		if award.is_empty() and not ball.freeze:
			last_live_point = point
		if stage == "carry" and ball.freeze:
			if not first_carry.is_finite():
				first_carry = point
			carry_samples += 1
			carry_distance = maxf(carry_distance, FootballReception.flat(point - first_carry).length())
		if ball.touch_serial == exit_serial + 1 and not award.is_empty() and ball.last_touch_id == award["taker"] and not ball.freeze and ball.grip_holder_id.is_empty() and ball.linear_velocity.z < -0.5:
			live_release = true
			if point.z < ElevenPitch.HALF_WIDTH - FootballBall.RADIUS:
				entered_pitch = true
				if entry_frame < 0:
					entry_frame = physics_id
		if frame % 6 == 0:
			samples.append({
				"frame": physics_id, "stage": stage, "position": _vector(point), "velocity": _vector(ball.linear_velocity),
				"frozen": ball.freeze, "touch_serial": ball.touch_serial, "receiver": ball.pass_receiver_id,
				"attendant": _vector(attendant.global_position) if attendant != null else [],
			})
		if entered_pitch and physics_id - entry_frame >= ceili((0.35 if movie else 0.12) * hz):
			break
	var events: Array = game.action_log.slice(event_start)
	var called := _event_index(events, "attendant_called")
	var pickup := _event_index(events, "attendant_pickup")
	var handoff := _event_index(events, "attendant_handoff")
	var release := _event_index(events, "restart_taken", {"restart": "throw_in", "team": 1})
	var taker_id := str(award.get("taker", ""))
	var receiver := _event_index(events, "receiver_assigned", {"passer": taker_id, "serial": exit_serial + 1, "team": 1})
	var ordered := called >= 0 and pickup > called and handoff > pickup and release > handoff
	var award_point := _read_vector(award.get("ball", []))
	var previous_live := _read_vector(award.get("previous_live_ball", []))
	var award_preserved := award_point.is_finite() and previous_live.is_finite() and award_point.z > ElevenPitch.HALF_WIDTH + FootballBall.RADIUS and award_point.y <= 0.25 and award_point.distance_to(previous_live) <= 0.20
	var valid_handoff: bool = ordered and events[handoff].get("player", "") == taker_id and float(events[handoff].get("hand_gap_m", INF)) <= 0.10
	var release_point := _read_vector(events[release].get("release_position", [])) if release >= 0 else Vector3.INF
	var thrower_point := _read_vector(events[release].get("thrower_position", [])) if release >= 0 else Vector3.INF
	var audited := false
	for entry in ball.impulse_audit:
		if entry["serial"] == exit_serial + 1 and entry["player_id"] == taker_id and entry["team"] == 1:
			var impulse := _read_vector(entry["impulse"])
			audited = impulse.is_finite() and impulse.z < 0.0 and impulse.y > 0.0
			break
	var checks := {
		"live_exit_awarded_away_throw_without_teleport": award_preserved and award.get("team", -1) == 1 and not award.get("ball_frozen", true) and award.get("stage", "") == "retrieve",
		"attendant_called_then_pickup_and_handoff": ordered and award.get("attendant_registered", false) and valid_handoff,
		"ball_travelled_while_carried": carry_samples >= 4 and carry_distance >= 0.25,
		"actual_throw_free_ball_and_pitch_entry": audited and live_release and entered_pitch and release >= 0 and events[release].get("touch_serial", -1) == exit_serial + 1,
		"thrower_stayed_at_touchline": thrower_point.z >= ElevenPitch.HALF_WIDTH + 0.3 and thrower_point.z <= ElevenPitch.HALF_WIDTH + 1.0 and absf(release_point.z - ElevenPitch.HALF_WIDTH) <= 1.15,
		"away_receiver_assigned_to_throw": receiver > release and release >= 0,
	}
	return {
		"passed": not checks.values().has(false), "checks": checks,
		"fixture": "Ball placed just inside the touchline and given one labelled home impulse. Production boundary, attendant and throw physics handle everything afterward.",
		"exit_serial": exit_serial, "award": award, "attendant_start": _vector(attendant_start),
		"carry_distance_m": carry_distance, "carry_ticks": carry_samples, "entry_frame": entry_frame,
		"samples": samples, "match_action_log": events, "impulse_audit": ball.impulse_audit.duplicate(true),
	}


func _event_index(events: Array, kind: String, fields: Dictionary = {}) -> int:
	for index in range(events.size()):
		var event: Dictionary = events[index]
		if event.get("kind") != kind:
			continue
		var matches := true
		for key in fields:
			matches = matches and event.get(key) == fields[key]
		if matches:
			return index
	return -1


func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _read_vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2])) if value.size() == 3 else Vector3.INF
