extends Node

# One bounded acceptance run. The driver injects controller input, while the
# production match, coordinator, referee and player physics keep processing.
# Positions/velocities are assigned only at explicit scenario boundaries.
const CASES := ["action_contact", "action_miss", "walk", "jog", "sprint", "turn_stop", "dribble_jog", "dribble_sprint", "dribble_turn_stop", "contested", "pass_stationary", "pass_moving", "pass_backward", "pass_return", "goal_blue", "goal_orange"]
const LIMITS := [1.2, 1.2, 1.8, 1.8, 1.8, 2.6, 3.0, 3.0, 3.4, 4.0, 4.5, 4.5, 4.5, 6.0, 40.0, 40.0]
var game: Node3D
var movement := Vector2.ZERO
var sprinting := false
var actions: Dictionary = {}
var stage := -1
var elapsed := 0.0
var total_elapsed := 0.0
var evidence_dir := ""
var actor: FootballPlayer
var receiver: FootballPlayer
var contender: FootballPlayer
var checks: Dictionary = {}
var observations: Array[Dictionary] = []
var trace: Array[Dictionary] = []
var contact_events: Array[Dictionary] = []
var action_events: Array[Dictionary] = []
var screenshots: Array[String] = []
var motion_frames: Array[String] = []
var phase_data: Dictionary = {}
var previous_positions: Dictionary = {}
var previous_stances: Dictionary = {}
var trace_remaining := 0.0
var frame_remaining := 0.0
var frame_index := 0
var phase_captures: Dictionary = {}
var finite := true
var continuous := true
var maximum_player_speed := 0.0
var maximum_ball_speed := 0.0
var maximum_stance_slip := 0.0
var planted_samples := 0
var planted_height_min := 100.0
var planted_height_max := -100.0
var referee_start_clock := 0.0
var starting_log := 0
var finished := false

func begin(node: Node3D) -> void:
	game = node
	process_priority = 50
	evidence_dir = OS.get_environment("BASED_FOOTBALL_EVIDENCE")
	referee_start_clock = game.referee.clock
	for i in range(game.players.size()):
		var player: FootballPlayer = game.players[i]
		player.ai_rng.seed = 251014 + i
		player.dribble_contact.connect(_on_touch.bind(player))
		player.strike_contact.connect(_on_strike.bind(player))
		player.action_event.connect(_on_action.bind(player))
	game.team_coordinator.rng.seed = 251014
	game.referee.rng.seed = 251014
	_next()
	print("FOUNDATION_SESSION_STARTED: scripted input; production match, referee, AI and physics active; one bounded sequence")

func _label() -> String:
	return CASES[stage] if stage >= 0 and stage < CASES.size() else "finished"

func _next() -> void:
	stage += 1
	if stage >= CASES.size():
		_finish()
		return
	elapsed = 0
	movement = Vector2.ZERO
	sprinting = false
	actions = {}
	phase_data = {"contacts": {}, "kicks": {}, "touch_cycles": [], "cycle": {}, "requested": false, "repeat_checked": false, "received": false, "return_received": false, "relay": false, "goal": false, "settled": false, "signal": false, "kickoff": false, "kickoff_received": false}
	phase_captures = {}
	previous_positions.clear()
	previous_stances.clear()
	starting_log = game.action_log.size()
	game.reset_positions(0)
	game.goal_flow.active = false
	game.goal_flow.state = ""
	game.goal_flow.signalled = false
	game.kickoff_remaining = 0
	game.remaining = 600
	game.phase = "playing"
	game.charging = false
	game.delivery_kind = ""
	game.team_coordinator.remaining = 0
	game.team_coordinator.chasers.clear()
	game.team_coordinator.roles.clear()
	game.team_coordinator.possession_team = -1
	game.referee.yellow.clear()
	game.referee.warnings.clear()
	game.referee.return_delay.clear()
	game.referee.last_distance.clear()
	game.referee.mark_state = ""
	game.referee.advantage.clear()
	game._select(0)
	actor = game.controlled
	receiver = game.players[1]
	contender = game.players[3]
	for i in range(game.players.size()):
		var player: FootballPlayer = game.players[i]
		player.reset_action()
		player.freeze = player != actor
		player.global_position = Vector3(13, .02, -9 + i * 3)
		player.linear_velocity = Vector3.ZERO
		player.angular_velocity = Vector3.ZERO
		player.intent = Vector3.ZERO
		player.aim = Vector3.RIGHT
		player.body_visual.rotation = Vector3(0, -PI / 2, 0)
		player.body_visual.position = Vector3.ZERO
		player.sprint = false
		player.sent_off = false
		player.emotion = ""
		player.energy = 1
		player.kick_cooldown = 0
		player.tackle_cooldown = 0
		player.touch_cooldown = 0
		player.incoming_pass_remaining = 0
		player.tactical_role = ""
		player.reaction_timer = 0
	actor.global_position = Vector3(-10, .02, 0)
	game.ball.freeze = false
	game.ball.global_position = actor.global_position + Vector3(.55, .11, .12)
	game.ball.linear_velocity = Vector3.ZERO
	game.ball.angular_velocity = Vector3.ZERO
	game.ball.last_touch_id = actor.player_id
	game.ball.last_touch_team = actor.team
	game.ball.control_block_remaining = 0
	game.ball.control_candidate_id = ""
	var label := _label()
	if label in ["walk", "jog", "sprint", "turn_stop"]:
		game.ball.freeze = true
		game.ball.global_position = Vector3(0, .11, 10)
	if label == "action_miss":
		game.ball.linear_velocity = Vector3(0, 0, 14)
	if label == "contested":
		contender.freeze = false
		contender.global_position = actor.global_position + Vector3(1.9, 0, .1)
		contender.linear_velocity = Vector3.LEFT * 1.5
		contender.aim = Vector3.LEFT
		contender.body_visual.rotation.y = PI / 2
		phase_data["contender_challenges"] = contender.challenge_contacts
	if label.begins_with("pass_"):
		actor.global_position = Vector3(-5, .02, 0)
		game.ball.global_position = actor.global_position + Vector3(.55, .11, .12)
		receiver.freeze = false
		receiver.global_position = Vector3(1, .02, 0)
		if label == "pass_backward":
			receiver.global_position = Vector3(-11, .02, 0)
		if label == "pass_moving":
			receiver.linear_velocity = Vector3(0, 0, 1.6)
		actor.aim = ((receiver.global_position - game.ball.global_position) * Vector3(1, 0, 1)).normalized()
		phase_data["initial_receiver_position"] = receiver.global_position
	if label.begins_with("goal_"):
		_setup_goal(0 if label == "goal_blue" else 1)
	game.previous_ball_position = game.ball.global_position
	for player in game.players:
		player.reset_physics_interpolation()
		previous_positions[player.player_id] = player.global_position
	game.ball.reset_physics_interpolation()
	game.hud.flash("FOUNDATION / " + label.to_upper(), 2)
	print("FOUNDATION_PHASE: " + label)

func _setup_goal(receiving_team: int) -> void:
	var side := -1.0 if receiving_team == 0 else 1.0
	for i in range(game.players.size()):
		var player: FootballPlayer = game.players[i]
		player.freeze = false
		var team_side := -1.0 if player.team == 0 else 1.0
		player.global_position = Vector3(team_side * (8 + (i % 3) * 3), .02, [-7.0, 3.0, -4.0][i % 3])
	actor.global_position = Vector3(-8, .02, -7)
	game.scores[0] = 0
	game.scores[1] = 0
	game.ball.global_position = Vector3(side * 17.0, .11, 1.4)
	game.ball.linear_velocity = Vector3(side * 8, 0, 0)
	game.ball.last_touch_team = 1 - receiving_team
	game.ball.last_touch_id = game.players[3 if receiving_team == 0 else 0].player_id
	phase_data["receiving_team"] = receiving_team
	phase_data["kickoff_receiver_id"] = ""
	phase_data["return_recipient_id"] = ""

func decide(_delta: float) -> void:
	actions = {}
	movement = Vector2.ZERO
	sprinting = false
	if finished:
		return
	var label := _label()
	if label.begins_with("action_"):
		if not phase_data.requested:
			phase_data.requested = true
			actor.planned_receiver_id = receiver.player_id
			actor.planned_receive_point = receiver.global_position
			var accepted := actor.kick(game.ball, Vector3.RIGHT, 8, .08, "pass")
			checks[label + "_request_accepted"] = accepted
			phase_data["action_id"] = actor.accepted_action_id
			phase_data["accepted_receiver"] = actor.accepted_receiver_id
			phase_data["accepted_point"] = actor.accepted_receive_point
			phase_data["accepted_direction"] = actor.action_direction
		elif not phase_data.repeat_checked and actor.action_kind == "kick":
			phase_data.repeat_checked = true
			var rejected := not actor.kick(game.ball, Vector3.LEFT, 23, 4, "shot")
			checks[label + "_repeat_rejected_without_mutation"] = rejected and actor.accepted_action_id == phase_data.action_id and actor.accepted_receiver_id == phase_data.accepted_receiver and actor.accepted_receive_point == phase_data.accepted_point and actor.action_direction == phase_data.accepted_direction
	elif label == "walk":
		movement = Vector2(.35, 0)
	elif label == "jog":
		movement = Vector2.RIGHT
	elif label == "sprint":
		movement = Vector2.RIGHT
		sprinting = true
	elif label == "turn_stop":
		movement = Vector2.RIGHT if elapsed < .9 else Vector2(0, -.8) if elapsed < 1.7 else Vector2.ZERO
	elif label == "dribble_jog":
		movement = Vector2.RIGHT
	elif label == "dribble_sprint":
		movement = Vector2.RIGHT
		sprinting = true
	elif label == "dribble_turn_stop":
		movement = Vector2.RIGHT if elapsed < 1 else Vector2(.4, -.8).normalized() if elapsed < 2.2 else Vector2.ZERO
	elif label == "contested":
		movement = Vector2(.65, 0)
	elif label.begins_with("pass_"):
		if elapsed < .14:
			actions["pass"] = not phase_data.requested
			actions["pass_held"] = true
			phase_data.requested = true
		elif not phase_data.get("released", false):
			actions["pass_release"] = true
			phase_data["released"] = true

func _physics_process(delta: float) -> void:
	if finished or game == null:
		return
	elapsed += delta
	total_elapsed += delta
	_observe_physics(delta)
	_observe_goal()
	if elapsed >= float(LIMITS[stage]) or _label().begins_with("goal_") and phase_data.kickoff_received:
		_conclude_phase()
		_next()

func _observe_physics(delta: float) -> void:
	finite = finite and game.ball.global_position.is_finite() and game.ball.linear_velocity.is_finite()
	maximum_ball_speed = maxf(maximum_ball_speed, game.ball.linear_velocity.length())
	for player in game.players:
		finite = finite and player.global_position.is_finite() and player.linear_velocity.is_finite()
		maximum_player_speed = maxf(maximum_player_speed, player.linear_velocity.length())
		continuous = continuous and player.global_position.distance_to(previous_positions[player.player_id]) < .5
		previous_positions[player.player_id] = player.global_position
	var label := _label()
	if label in ["walk", "jog", "sprint", "turn_stop", "dribble_jog", "dribble_sprint", "dribble_turn_stop"]:
		_observe_stances()
	if label.begins_with("dribble_"):
		var cycle: Dictionary = phase_data.cycle
		if not cycle.is_empty():
			var gap: float = ((game.ball.global_position - actor.global_position) * Vector3(1, 0, 1)).length()
			cycle["peak_gap"] = maxf(float(cycle.peak_gap), gap)
			if gap < float(cycle.peak_gap) - .1:
				cycle["caught_up"] = true
			cycle["free_samples"] = int(cycle.free_samples) + 1
			cycle["free_distance"] = maxf(float(cycle.free_distance), game.ball.global_position.distance_to(cycle.ball_start))
	trace_remaining -= delta
	if trace_remaining <= 0:
		trace_remaining = .05
		trace.append(_snapshot())

func _observe_stances() -> void:
	var visual: FootballPlayerVisual = actor.visual_controller
	for i in range(2):
		var boot: Node3D = visual.left_boot if i == 0 else visual.right_boot
		var planted: bool = visual.planted_feet[i]
		var epoch: int = visual.stance_epochs[i]
		var key := actor.player_id + str(i)
		if planted:
			planted_samples += 1
			planted_height_min = minf(planted_height_min, boot.global_position.y - actor.global_position.y)
			planted_height_max = maxf(planted_height_max, boot.global_position.y - actor.global_position.y)
			if previous_stances.has(key) and previous_stances[key].epoch == epoch and previous_stances[key].planted:
				var drift: Vector3 = (boot.global_position - previous_stances[key].plant_start) * Vector3(1, 0, 1)
				maximum_stance_slip = maxf(maximum_stance_slip, drift.length())
		var plant_start: Vector3 = previous_stances[key].plant_start if previous_stances.has(key) and previous_stances[key].epoch == epoch and previous_stances[key].planted and planted else boot.global_position
		previous_stances[key] = {"epoch": epoch, "planted": planted, "plant_start": plant_start}

func _on_touch(player: FootballPlayer) -> void:
	if finished:
		return
	phase_data.contacts[player.player_id] = int(phase_data.contacts.get(player.player_id, 0)) + 1
	contact_events.append({"phase": _label(), "time": elapsed, "actor": player.player_id, "kind": "dribble", "technique": player.dribble_technique, "ball": game._vec(game.ball.global_position), "gap": player.global_position.distance_to(game.ball.global_position)})
	if _label().begins_with("pass_") and player == receiver:
		if not phase_data.received:
			# Latch the first physical receiving contact. Later running touches
			# occur after the reception hold expires and are separate actions.
			phase_data.received = true
			phase_data["receive_time"] = elapsed
			phase_data["receive_hold_observed"] = player.receive_hold_remaining > 0
			phase_data["receive_hold_at_contact"] = player.receive_hold_remaining
			phase_data["first_receive_technique"] = player.dribble_technique
			phase_data["first_receive_from"] = player.last_pass_from
			_capture_once("received")
	if _label() == "pass_return" and player == actor and phase_data.received:
		phase_data.return_received = true
	if _label().begins_with("dribble_") and player == actor:
		var old: Dictionary = phase_data.cycle
		if not old.is_empty():
			old["end"] = elapsed
			phase_data.touch_cycles.append(old.duplicate())
		var gap: float = ((game.ball.global_position - actor.global_position) * Vector3(1, 0, 1)).length()
		phase_data.cycle = {"start": elapsed, "end": elapsed, "peak_gap": gap, "contact_gap": gap, "caught_up": false, "free_samples": 0, "free_distance": 0.0, "ball_start": game.ball.global_position}
	if _label().begins_with("goal_"):
		if player.player_id == phase_data.get("return_recipient_id", ""):
			phase_data["relay_received"] = true
		if phase_data.kickoff and player.player_id == phase_data.kickoff_receiver_id:
			phase_data.kickoff_received = true
			_capture_once("kickoff_received")

func _on_strike(kind: String, player: FootballPlayer) -> void:
	if finished:
		return
	phase_data.kicks[player.player_id] = int(phase_data.kicks.get(player.player_id, 0)) + 1
	contact_events.append({"phase": _label(), "time": elapsed, "actor": player.player_id, "kind": kind, "id": player.accepted_action_id, "receiver": player.accepted_receiver_id, "purpose": player.action_purpose, "direction": game._vec(player.action_direction)})
	if _label().begins_with("pass_") and player == receiver and not phase_data.received:
		phase_data["kicked_before_reception"] = true
	if _label().begins_with("goal_"):
		if player.action_purpose == "restart_return":
			phase_data.relay = true
			phase_data.return_recipient_id = player.accepted_receiver_id
			_capture_once("return_pass")
		elif player.action_purpose == "kickoff":
			phase_data.kickoff = true
			phase_data.kickoff_receiver_id = player.accepted_receiver_id
			phase_data["kickoff_contact_time"] = elapsed
			var attack := 1.0 if int(phase_data.receiving_team) == 0 else -1.0
			phase_data["backward_direction"] = player.action_direction.x * attack < -.25
			_capture_once("kickoff")

func _on_action(phase: String, detail: Dictionary, player: FootballPlayer) -> void:
	if finished:
		return
	var event := detail.duplicate(true)
	event["phase"] = phase
	event["case"] = _label()
	event["time"] = elapsed
	event["actor"] = player.player_id
	action_events.append(event)
	if _label().begins_with("action_") and int(detail.get("id", -1)) == int(phase_data.get("action_id", -2)):
		phase_data["outcome_" + phase] = true
	if _label().begins_with("pass_") and player == receiver and phase == "accepted":
		phase_data["receiver_accepted_after_contact"] = phase_data.received

func _observe_goal() -> void:
	if not _label().begins_with("goal_"):
		return
	var team: int = phase_data.receiving_team
	if game.scores[1 - team] == 1 and not phase_data.goal:
		phase_data.goal = true
		_capture_once("goal")
	if game.goal_flow.active:
		phase_data.relay = phase_data.relay or game.goal_flow.return_passes > 0
		if game.goal_flow.state == "ready":
			phase_data.settled = phase_data.settled or game.ball.global_position.distance_to(Vector3(0, FootballBall.RADIUS, 0)) < .4 and game.ball.linear_velocity.length() < .25
			phase_data.signal = phase_data.signal or game.goal_flow.signalled
			_capture_once("settled_signal")
		if absf(game.ball.global_position.x) < 17.5 and phase_data.goal:
			_capture_once("net_exit")
	if phase_data.kickoff and not phase_data.get("launch_velocity_observed", false) and elapsed > float(phase_data.kickoff_contact_time) and game.ball.linear_velocity.length() > 1:
		phase_data["launch_velocity_observed"] = true
		phase_data["launch_velocity"] = game.ball.linear_velocity
		phase_data["backward_launch"] = game.ball.linear_velocity.x * (1 if team == 0 else -1) < -1
	# Read the first contact log, rather than inferring a kickoff from last-touch.
	for i in range(starting_log, game.action_log.size()):
		var event: Dictionary = game.action_log[i]
		if event.kind == "restart_retake":
			phase_data["retake"] = true

func _conclude_phase() -> void:
	var label := _label()
	_capture_once("end")
	if label == "action_contact":
		checks[label + "_actual_contact"] = phase_data.get("outcome_contact", false)
		checks[label + "_completed"] = phase_data.get("outcome_completed", false)
	elif label == "action_miss":
		checks[label + "_miss_has_no_contact"] = not phase_data.get("outcome_contact", false) and phase_data.get("outcome_missed", false)
	elif label in ["walk", "jog", "sprint", "turn_stop"]:
		checks[label + "_physical_movement"] = actor.global_position.x > -9
		if label == "turn_stop":
			checks["turn_stop_physically_brakes"] = Vector3(actor.linear_velocity.x, 0, actor.linear_velocity.z).length() < .6
	elif label.begins_with("dribble_"):
		var contacts: int = phase_data.contacts.get(actor.player_id, 0)
		checks[label + "_actual_foot_contacts"] = contacts >= 3
		var catchups := 0
		for cycle in phase_data.touch_cycles:
			if cycle.caught_up and cycle.free_samples >= 6 and cycle.free_distance > .35:
				catchups += 1
		if label != "dribble_turn_stop":
			checks[label + "_free_travel_and_catchup"] = catchups >= 2
		else:
			checks[label + "_ball_stopped_in_reach"] = game.ball.linear_velocity.length() < .8 and actor.global_position.distance_to(game.ball.global_position) < 1.3
		phase_data["catchup_cycles"] = catchups
	elif label == "contested":
		var touched_first: bool = phase_data.contacts.get(actor.player_id, 0) > 0
		var opponent_contact: bool = phase_data.contacts.get(contender.player_id, 0) > 0 or contender.challenge_contacts > int(phase_data.contender_challenges) and game.ball.last_touch_id == contender.player_id
		checks["contested_physical_possession_can_be_lost"] = touched_first and opponent_contact
	elif label.begins_with("pass_"):
		checks[label + "_actual_pass_contact"] = phase_data.kicks.get(actor.player_id, 0) > 0
		checks[label + "_intended_receiver_physical_first_touch"] = phase_data.received
		checks[label + "_cushion_before_next_action"] = phase_data.get("receive_hold_observed", false) and not phase_data.get("kicked_before_reception", false)
		if label == "pass_moving":
			checks["moving_receiver_meets_delivery"] = receiver.global_position.distance_to(phase_data.initial_receiver_position) > .5 and phase_data.received
		if label == "pass_return":
			checks["return_combination_actual_receive_pass_receive"] = phase_data.return_received and phase_data.kicks.get(receiver.player_id, 0) > 0
	elif label.begins_with("goal_"):
		var team: int = phase_data.receiving_team
		checks[label + "_goal_counted_exactly_once"] = phase_data.goal and game.scores[1 - team] == 1
		checks[label + "_physical_team_return"] = phase_data.relay and phase_data.get("relay_received", false)
		checks[label + "_centre_settled_and_signalled"] = phase_data.settled and phase_data.signal
		checks[label + "_actual_backward_kickoff"] = phase_data.kickoff and phase_data.get("backward_direction", false) and phase_data.get("backward_launch", false)
		checks[label + "_live_teammate_reception"] = phase_data.kickoff_received and not game.goal_flow.active
		checks[label + "_no_false_retake"] = not phase_data.get("retake", false)
	observations.append({"case": label, "duration": elapsed, "data": _serializable(phase_data)})

func _serializable(value: Variant) -> Variant:
	if value is Vector3:
		return game._vec(value)
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[key] = _serializable(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_serializable(item))
		return result
	return value

func _snapshot() -> Dictionary:
	var players: Array[Dictionary] = []
	for player in game.players:
		players.append({"id": player.player_id, "position": game._vec(player.global_position), "velocity": game._vec(player.linear_velocity), "intent": game._vec(player.intent), "role": player.tactical_role, "action_id": player.accepted_action_id, "action": player.action_kind, "purpose": player.action_purpose, "receiver": player.accepted_receiver_id, "receiving": player.incoming_pass_remaining, "receive_hold": player.receive_hold_remaining, "dribble": player.dribble_technique, "feet": [game._vec(player.visual_controller.left_boot.global_position), game._vec(player.visual_controller.right_boot.global_position)], "planted": player.visual_controller.planted_mask(), "stance_epochs": player.visual_controller.stance_epochs.duplicate()})
	return {"case": _label(), "time": elapsed, "total_time": total_elapsed, "ball": game._vec(game.ball.global_position), "velocity": game._vec(game.ball.linear_velocity), "last_touch": game.ball.last_touch_id, "restart": game.goal_flow.state if game.goal_flow.active else "live", "referee_clock": game.referee.clock, "players": players}

func _process(delta: float) -> void:
	if finished or game == null:
		return
	var label := _label()
	if label.begins_with("goal_"):
		game.camera.size = 46
		game.camera.position = Vector3(0, 34, 29)
		game.camera.look_at(Vector3.ZERO)
	else:
		var focus := actor.global_position + Vector3.UP * .5
		game.camera.size = 6.5 if label in ["walk", "jog", "sprint", "turn_stop"] or label.begins_with("dribble_") else 17
		game.camera.position = focus + Vector3(3, 3, 5)
		game.camera.look_at(focus)
	if label in ["walk", "jog", "sprint", "turn_stop"] or label.begins_with("dribble_"):
		frame_remaining -= delta
		if frame_remaining <= 0:
			frame_remaining = .1
			var filename := "motion_%04d.png" % frame_index
			frame_index += 1
			if get_viewport().get_texture().get_image().save_png(evidence_dir.path_join(filename)) == OK:
				screenshots.append(filename)
				motion_frames.append(filename)

func _capture_once(label: String) -> void:
	if phase_captures.has(label):
		return
	phase_captures[label] = true
	var filename := _label() + "_" + label + ".png"
	checks["capture_" + _label() + "_" + label] = get_viewport().get_texture().get_image().save_png(evidence_dir.path_join(filename)) == OK
	screenshots.append(filename)

func _finish() -> void:
	finished = true
	set_physics_process(false)
	checks["production_match_physics_active"] = game.is_physics_processing() and game.decision_driver == self
	checks["production_referee_active"] = game.referee.clock > referee_start_clock + 20
	checks["hardware_input_disabled"] = not game.is_processing_unhandled_input()
	checks["physics_finite_and_bounded"] = finite and maximum_player_speed < 20 and maximum_ball_speed < 40
	checks["no_player_teleport_during_sequences"] = continuous
	checks["planted_stance_sampled"] = planted_samples > 120
	checks["planted_feet_do_not_slide"] = maximum_stance_slip < .055
	checks["planted_feet_stay_grounded"] = planted_height_min > -.02 and planted_height_max < .18
	checks["continuous_motion_frames_saved"] = motion_frames.size() > 100
	var report := {"pass": not checks.values().has(false), "checks": checks, "scope": "One bounded normal-match sequence: immutable physical action contact/miss, planted walk/jog/sprint/turn/stop, free touch-ahead catch-up dribbling and contested loss, full-AI pass/reception/return, mirrored live goals through physical team return, settlement, signal and backward kickoff. Setups only between scenarios; normal referee, AI and match ordering remain active. Visual quality and controller feel require human evaluation.", "seconds": total_elapsed, "screenshots": screenshots, "motion_frames": motion_frames, "observations": observations, "contact_events": contact_events, "action_events": action_events, "events": game.action_log, "metrics": {"planted_samples": planted_samples, "maximum_stance_slip_within_one_plant": maximum_stance_slip, "minimum_planted_ankle_height": planted_height_min, "maximum_planted_ankle_height": planted_height_max, "maximum_player_speed": maximum_player_speed, "maximum_ball_speed": maximum_ball_speed}, "hardware_input_injected": false, "subjective_feel_verified": false}
	var file := FileAccess.open(evidence_dir.path_join("scene-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	file = FileAccess.open(evidence_dir.path_join("foundation-trace.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(trace))
	file.close()
	print("FOUNDATION_SESSION_RESULT: " + JSON.stringify({"pass": report.pass, "checks": checks, "seconds": total_elapsed}))
	get_tree().quit(0 if report.pass else 1)
