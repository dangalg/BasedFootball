extends SceneTree

## --headless --script res://tests/eleven_run_acceptance.gd
## -- --eleven-acceptance --report=<fresh absolute JSON path>

const MATCH := preload("res://scenes/eleven_match.tscn")
const SAVE_PATH := "user://eleven_acceptance_squad.json"
const FORWARD := Vector3.RIGHT


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
	print("ELEVEN_RUN_ACCEPTANCE %s %s" % ["PASS" if report["passed"] else "FAIL", report_path])
	quit(0 if report["passed"] else 1)


func _exercise(game: Node3D) -> Dictionary:
	var carrier: FootballPlayer = game.controlled
	var runner: FootballPlayer = game.home_outfield[1]
	var ball: FootballBall = game.ball
	var hz := Engine.physics_ticks_per_second
	var delta := 1.0 / float(hz)
	for index in range(game.players.size()):
		var player: FootballPlayer = game.players[index]
		player.ai_rng.seed = 81100 + index
		if player.team == 1 and not player.is_goalkeeper:
			# Keep the first few metres of the pass lane clear at setup.
			player.global_position.x = maxf(24.0, player.global_position.x)
			player.reset_physics_interpolation()
	carrier.global_position = Vector3(0.0, 0.06, 0.0)
	carrier.aim = FORWARD
	carrier.reset_physics_interpolation()
	runner.global_position = Vector3(6.0, 0.06, 0.0)
	runner.aim = FORWARD
	runner.reset_physics_interpolation()
	ball.global_position = Vector3(0.53, FootballBall.RADIUS, 0.0)
	ball.reset_physics_interpolation()
	for _frame in range(ceili(0.23 * hz)):
		await physics_frame
	# A preceding touch supplies the live chase record. It is excluded from all pass checks.
	ball.touch(carrier.team, carrier.player_id, FORWARD * ball.mass * 0.025)
	carrier._remember_free_ball(ball, FORWARD)
	var seed_serial := ball.touch_serial
	var had_live_chase := carrier.chasing_ball(ball)
	var runner_start := runner.global_position
	var first_event: int = game.action_log.size()
	game.kickoff_remaining = 0.0
	game._controller_actions(delta, {"send_run": true})
	var called_target: Vector3 = runner.called_run_target
	var called_duration: float = runner.called_run_remaining
	for _frame in range(ceili(0.46 * hz)):
		await physics_frame
	var advance := (runner.global_position - runner_start).dot(FORWARD)
	var aim := runner.global_position - carrier.global_position
	aim.y = 0.0
	carrier.aim = aim.normalized()
	game._controller_actions(delta, {"through": true})
	var samples: Array[Dictionary] = []
	for _frame in range(ceili(0.65 * hz)):
		await physics_frame
		samples.append({
			"frame": Engine.get_physics_frames(), "touch_serial": ball.touch_serial,
			"ball_position": _vector(ball.global_position), "ball_velocity": _vector(ball.linear_velocity),
			"free": not ball.freeze and ball.grip_holder_id.is_empty(),
			"runner_position": _vector(runner.global_position), "receiver": ball.pass_receiver_id,
		})
	var events: Array = game.action_log.slice(first_event)
	var run_called := _event(events, "run_called", runner.player_id)
	var through_requested := _event(events, "run_through_requested", carrier.player_id)
	var contact := _event(events, "kick_contact", carrier.player_id)
	var serial := int(contact.get("touch_serial", -1))
	var receiver := _event(events, "receiver_assigned", runner.player_id)
	var pass_impulse: Dictionary = {}
	for entry in ball.impulse_audit:
		if entry["serial"] == serial and entry["player_id"] == carrier.player_id:
			pass_impulse = entry
			break
	var gap := float(contact.get("boot_gap", INF))
	var measured_speed := 0.0
	var free_flight := true
	for sample in samples:
		if sample["touch_serial"] != serial:
			continue
		var velocity := _read_vector(sample["ball_velocity"])
		free_flight = free_flight and sample["free"] and velocity.is_finite()
		measured_speed = maxf(measured_speed, velocity.dot(FORWARD))
	var checks := {
		"fixture_carrier_was_chasing": had_live_chase,
		"run_called_for_aimed_teammate": not run_called.is_empty() and called_duration > 0.0 and called_target.x > runner_start.x,
		"runner_advanced_before_pass": advance >= 0.50,
		"through_requested_for_runner": through_requested.get("receiver", "") == runner.player_id,
		"carrier_made_through_boot_contact": contact.get("detail_kind", "") == "through" and gap >= 0.0 and gap <= FootballPlayer.STRIKE_BOOT_REACH and serial > seed_serial and not pass_impulse.is_empty(),
		"runner_assigned_to_same_pass": receiver.get("serial", -1) == serial and receiver.get("passer", "") == carrier.player_id and serial > seed_serial,
		"observed_forward_free_ball": free_flight and measured_speed >= 4.0,
	}
	return {
		"passed": not checks.values().has(false), "checks": checks,
		"fixture": "Initial positioning and preceding chase touch only. Live 11v11 AI and controller actions drive the run and pass.",
		"carrier": carrier.player_id, "runner": runner.player_id, "seed_serial": seed_serial,
		"runner_start": _vector(runner_start), "called_target": _vector(called_target),
		"advance_before_pass_m": advance, "observed_pass_forward_speed_mps": measured_speed,
		"samples": samples, "match_action_log": events, "impulse_audit": ball.impulse_audit.duplicate(true),
	}


func _event(events: Array, kind: String, player_id: String) -> Dictionary:
	for event: Dictionary in events:
		if event.get("kind") == kind and event.get("player") == player_id:
			return event
	return {}


func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _read_vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
