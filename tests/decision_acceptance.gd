extends Node

const SECONDS := 30.0
var game: Node3D
var movement := Vector2.ZERO
var sprinting := false
var actions: Dictionary = {}
var elapsed := 0.0
var think_remaining := 0.0
var switch_remaining := 0.0
var shot_release_remaining := 0.0
var decision_count := 0
var switches := 0
var sprint_seconds := 0.0
var choices: Dictionary = {}
var trace: Array = []
var screenshots: Array[String] = []
var evidence_dir: String
var next_frame := 4.0
var physics_finite := true
var max_speed := 0.0
var running_samples := [0, 0]
var backwards_samples := [0, 0]

func begin(match_node: Node3D) -> void:
	game = match_node
	evidence_dir = OS.get_environment("BASED_FOOTBALL_EVIDENCE")
	# Start with the opposing kickoff so a home-dominated opening cannot leave
	# their possession path unexercised. Subsequent play follows normal rules.
	game.reset_positions(1)
	game.hud.flash("DECISION PLAYTEST / LIVE OPPONENT AI", 3)
	print("DECISION_SESSION_STARTED: current-state decisions through production controller actions; normal match and AI active")

func decide(delta: float) -> void:
	actions = {}
	think_remaining -= delta
	switch_remaining = maxf(0, switch_remaining - delta)
	if shot_release_remaining > 0:
		shot_release_remaining -= delta
		if shot_release_remaining <= 0:
			actions["primary_release"] = true
	if think_remaining > 0:
		return
	think_remaining = 0.16
	decision_count += 1
	var actor: FootballPlayer = game.controlled
	var ball: FootballBall = game.ball
	var nearest: FootballPlayer = actor
	for teammate in game.players:
		if teammate.team == 0 and teammate.global_position.distance_to(ball.global_position) < nearest.global_position.distance_to(ball.global_position):
			nearest = teammate
	if nearest != actor and actor.global_position.distance_to(ball.global_position) > 2 and switch_remaining <= 0 and not game.charging:
		game._switch_player(nearest.global_position - actor.global_position)
		actor = game.controlled
		switches += 1
		switch_remaining = 0.6
	var offset: Vector3 = ball.global_position - actor.global_position
	offset.y = 0
	var goal_direction := Vector3(18.8, 0, 0) - actor.global_position
	goal_direction.y = 0
	var desired := offset.normalized()
	var choice := "recover"
	sprinting = offset.length() > 2.0
	if game._attacking_contact():
		choice = "carry"
		desired = goal_direction.normalized()
		var nearest_opponent := INF
		for opponent in game.players:
			if opponent.team == actor.team:
				continue
			var danger: Vector3 = opponent.global_position - actor.global_position
			danger.y = 0
			nearest_opponent = minf(nearest_opponent, danger.length())
			if danger.length() < 3 and danger.normalized().dot(desired) > 0.7:
				desired = (desired + Vector3(0, 0, -signf(danger.z + 0.001)) * 0.7).normalized()
		sprinting = nearest_opponent > 2.3 and actor.linear_velocity.length() > 2
		if goal_direction.length() < 10 and absf(actor.global_position.z) < 7 and actor.kick_cooldown <= 0 and not game.charging:
			choice = "shoot"
			actor.aim = goal_direction.normalized()
			desired = actor.aim
			actions["primary"] = true
			shot_release_remaining = 0.38
		elif nearest_opponent < 1.8 and actor.kick_cooldown <= 0:
			var receiver: FootballPlayer = null
			for teammate in game.players:
				if teammate.team == actor.team and teammate != actor and teammate.global_position.x > actor.global_position.x + 1.5:
					receiver = teammate
			if receiver != null:
				choice = "pass"
				desired = (receiver.global_position - actor.global_position).normalized()
				actor.aim = Vector3(desired.x, 0, desired.z).normalized()
				actions["pass"] = true
	elif ball.last_touch_team == 1:
		choice = "intercept"
		desired = (offset + Vector3(ball.linear_velocity.x, 0, ball.linear_velocity.z) * 0.12).normalized()
		if offset.length() < 1 and actor.tackle_cooldown <= 0:
			choice = "tackle"
			actor.aim = offset.normalized()
			actions["primary"] = true
		elif offset.length() < 2.4 and actor.linear_velocity.length() > 3.5 and actor.aim.dot(offset.normalized()) > 0.85 and actor.tackle_cooldown <= 0:
			choice = "slide"
			actions["square"] = true
	movement = Vector2(desired.x, desired.z)
	choices[choice] = int(choices.get(choice, 0)) + 1
	trace.append({"seconds": snappedf(elapsed, 0.01), "choice": choice, "actor": actor.player_id, "gap": offset.length(), "sprint": sprinting, "ball_team": ball.last_touch_team})

func _physics_process(delta: float) -> void:
	if game == null:
		return
	elapsed += delta
	if sprinting:
		sprint_seconds += delta
	for player in game.players:
		physics_finite = physics_finite and player.global_position.is_finite() and player.linear_velocity.is_finite()
		max_speed = maxf(max_speed, player.linear_velocity.length())
		var horizontal: Vector3 = Vector3(player.linear_velocity.x, 0, player.linear_velocity.z)
		if player.action_kind == "" and not player.jockey and horizontal.length() > 1.0:
			running_samples[player.team] += 1
			if (-player.body_visual.global_basis.z).dot(horizontal.normalized()) < 0:
				backwards_samples[player.team] += 1
	physics_finite = physics_finite and game.ball.global_position.is_finite() and game.ball.linear_velocity.is_finite()
	if elapsed >= next_frame:
		next_frame += 4
		var filename := "decision_%02d.png" % screenshots.size()
		if get_viewport().get_texture().get_image().save_png(evidence_dir.path_join(filename)) == OK:
			screenshots.append(filename)
	if elapsed >= SECONDS:
		_finish()

func _finish() -> void:
	set_physics_process(false)
	var touches := [0, 0]
	var kicks := 0
	var ai_actions := 0
	for event in game.action_log:
		if event["kind"] == "touch":
			touches[int(event["team"])] += 1
		if event["kind"] in ["shot", "pass", "lob", "through"]:
			kicks += 1
		if event.get("source", "") == "ai":
			ai_actions += 1
	var checks := {
		"normal_match_physics_and_ai_active": game.is_physics_processing() and ai_actions > 0,
		"hardware_input_disabled": not game.is_processing_unhandled_input() and game.decision_driver == self,
		"isolated_career": game.squad.save_path == "user://acceptance_squad.json",
		"reactive_decisions_and_player_switching": decision_count > 100 and switches > 0 and choices.size() >= 3,
		"both_teams_make_physical_touches": touches[0] > 3 and touches[1] > 3,
		"contact_timed_kicks_in_live_match": kicks > 0,
		"sprinting_exercised": sprint_seconds > 2,
		"physics_stays_finite_and_bounded": physics_finite and max_speed < 20,
		"both_teams_face_running_motion": running_samples[0] > 100 and running_samples[1] > 100 and float(backwards_samples[0]) / running_samples[0] < 0.03 and float(backwards_samples[1]) / running_samples[1] < 0.03,
		"live_match_frames_saved": screenshots.size() >= 7
	}
	var passed := true
	for value in checks.values():
		passed = passed and bool(value)
	var report := {"pass": passed, "checks": checks, "seconds": elapsed, "decisions": decision_count, "choices": choices, "switches": switches, "team_dribble_contacts": touches, "completed_kicks": kicks, "ai_actions": ai_actions, "sprint_seconds": sprint_seconds, "max_player_speed": max_speed, "scores": game.scores, "screenshots": screenshots, "trace": trace, "events": game.action_log, "hardware_input_injected": false, "subjective_feel_verified": false}
	var file := FileAccess.open(evidence_dir.path_join("scene-report.json"), FileAccess.WRITE)
	report["running_samples"] = running_samples
	report["backwards_running_samples"] = backwards_samples
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("DECISION_SESSION_RESULT: " + JSON.stringify(report))
	get_tree().quit(0 if passed else 1)
