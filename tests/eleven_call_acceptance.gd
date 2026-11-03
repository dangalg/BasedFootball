extends SceneTree

## --headless --script res://tests/eleven_call_acceptance.gd
## -- --eleven-acceptance --report=<fresh absolute JSON path>

const MATCH := preload("res://scenes/eleven_match.tscn")
const SAVE_PATH := "user://eleven_acceptance_squad.json"
const FORWARD := Vector3.RIGHT


class RunInput extends Node:
	var movement := Vector2.RIGHT
	var sprinting := false
	var actions: Dictionary = {}

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
	print("ELEVEN_CALL_ACCEPTANCE %s %s" % ["PASS" if report["passed"] else "FAIL", report_path])
	quit(0 if report["passed"] else 1)


func _exercise(game: Node3D) -> Dictionary:
	var caller: FootballPlayer = game.controlled
	var passer: FootballPlayer = game.home_outfield[5]
	var ball: FootballBall = game.ball
	var hz := Engine.physics_ticks_per_second
	for index in range(game.players.size()):
		var player: FootballPlayer = game.players[index]
		player.ai_rng.seed = 81100 + index
		if player.team == 1 and not player.is_goalkeeper:
			player.global_position.x = maxf(25.0, player.global_position.x)
			player.reset_physics_interpolation()
	caller.global_position = Vector3(8.0, 0.06, 0.0)
	passer.global_position = Vector3(0.0, 0.06, 0.0)
	caller.aim = FORWARD
	passer.aim = FORWARD
	caller.reset_physics_interpolation()
	passer.reset_physics_interpolation()
	ball.global_position = Vector3(0.53, FootballBall.RADIUS, 0.0)
	ball.reset_physics_interpolation()
	for _frame in range(ceili(0.23 * hz)):
		await physics_frame
	var driver := RunInput.new()
	game.add_child(driver)
	game.decision_driver = driver
	# Initial run momentum and preceding touch only. Subsequent motion is live.
	caller.linear_velocity = FORWARD * 2.5
	ball.touch(passer.team, passer.player_id, FORWARD * ball.mass * 0.025)
	passer._remember_free_ball(ball, FORWARD)
	var seed_serial := ball.touch_serial
	var caller_start := caller.global_position
	var previous_position := caller_start
	var max_tick_step := 0.0
	var had_chase := passer.chasing_ball(ball)
	var caller_out_of_reach: bool = not game._attacking_contact()
	var first_event: int = game.action_log.size()
	game.kickoff_remaining = 0.0
	game._controller_actions(1.0 / float(hz), {"pass": true})
	var queued_seconds: float = game.pass_call_remaining
	var samples: Array[Dictionary] = []
	for _frame in range(ceili(1.25 * hz)):
		await physics_frame
		var position := caller.global_position
		max_tick_step = maxf(max_tick_step, position.distance_to(previous_position))
		previous_position = position
		samples.append({
			"frame": Engine.get_physics_frames(), "caller_position": _vector(position),
			"call_remaining": game.pass_call_remaining, "touch_serial": ball.touch_serial,
			"ball_position": _vector(ball.global_position), "ball_velocity": _vector(ball.linear_velocity),
			"free": not ball.freeze and ball.grip_holder_id.is_empty(), "receiver": ball.pass_receiver_id,
		})
	var events: Array = game.action_log.slice(first_event)
	var call := _event(events, "pass_called", caller.player_id)
	var decision := _event(events, "ai_decision", passer.player_id, {"reason": "called_pass", "queued": true, "receiver_id": caller.player_id})
	var contact := _event(events, "kick_contact", passer.player_id)
	var serial := int(contact.get("touch_serial", -1))
	var receiver := _event(events, "receiver_assigned", caller.player_id, {"passer": passer.player_id, "serial": serial})
	var audited := false
	for entry in ball.impulse_audit:
		if entry["serial"] == serial and entry["player_id"] == passer.player_id:
			audited = _read_vector(entry["impulse"]).length_squared() > 0.00001
			break
	var speed := 0.0
	var free_flight := true
	var cleared_on_strike := false
	for sample in samples:
		if sample["touch_serial"] != serial:
			continue
		var velocity := _read_vector(sample["ball_velocity"])
		free_flight = free_flight and sample["free"] and velocity.is_finite()
		speed = maxf(speed, velocity.dot(FORWARD))
		cleared_on_strike = cleared_on_strike or float(sample["call_remaining"]) <= 0.0
	var advance := (caller.global_position - caller_start).dot(FORWARD)
	var gap := float(contact.get("boot_gap", INF))
	var checks := {
		"fixture_passer_chasing_and_caller_out_of_reach": had_chase and caller_out_of_reach,
		"cross_queued_call_for_controlled_player": not call.is_empty() and queued_seconds > 0.0,
		"ai_queued_called_pass": not decision.is_empty(),
		"ai_boot_contact": contact.get("detail_kind", "") in ["pass", "through"] and gap >= 0.0 and gap <= FootballPlayer.STRIKE_BOOT_REACH and serial > seed_serial and audited,
		"caller_assigned_to_same_pass": not receiver.is_empty() and serial > seed_serial,
		"call_cleared_on_strike": cleared_on_strike,
		"caller_kept_running": advance >= 2.0 and max_tick_step <= 9.0 / float(hz),
		"observed_forward_free_ball": free_flight and speed >= 4.0,
	}
	return {
		"passed": not checks.values().has(false), "checks": checks,
		"fixture": "Initial positions, caller momentum and preceding AI touch only. Live 11v11 AI and the production Cross handler drive the pass.",
		"caller": caller.player_id, "passer": passer.player_id, "seed_serial": seed_serial,
		"advance_m": advance, "max_tick_step_m": max_tick_step, "observed_pass_forward_speed_mps": speed,
		"samples": samples, "match_action_log": events, "impulse_audit": ball.impulse_audit.duplicate(true),
	}


func _event(events: Array, kind: String, player_id: String, fields: Dictionary = {}) -> Dictionary:
	for event: Dictionary in events:
		if event.get("kind") != kind or event.get("player") != player_id:
			continue
		var matches := true
		for key in fields:
			matches = matches and event.get(key) == fields[key]
		if matches:
			return event
	return {}


func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _read_vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
