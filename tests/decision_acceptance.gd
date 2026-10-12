extends Node

const SECONDS := 30.0
var checkpoint := 0
var fixture_checks: Dictionary = {}
var fixture_frames: Array[String] = []
var fixture_observations: Array = []
var stop_trace: Array = []
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
var ai_intervals: Dictionary = {}
var previous_ai_timers: Dictionary = {}
var possession: Dictionary = {}
var episodes: Array = []
var control_samples: Array = []
var recent_contacts: Dictionary = {}
var sample_remaining := 0.0
var missing_since := -1.0
var missing_snapshot: Dictionary = {}
var last_frame: Image
var before_loss_frame: Image
var missed_windows := 0
var window_seen := false
var previous_swing_elapsed := 0.0

func begin(match_node: Node3D) -> void:
	game = match_node
	for i in range(game.players.size()):
		game.players[i].ai_rng.seed = 81011 + i
		game.players[i].ai_style = game.players[i].ai_rng.randf_range(0.25, 0.75)
		game.players[i].dribble_contact.connect(_observe_touch.bind(game.players[i]))
		game.players[i].strike_contact.connect(_observe_strike.bind(game.players[i]))
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
	_track_possession(delta)
	if sprinting:
		sprint_seconds += delta
	for player in game.players:
		if player != game.controlled:
			var previous: float = previous_ai_timers.get(player.player_id, 0.0)
			if player.reaction_timer > previous + 0.01:
				ai_intervals[snappedf(player.reaction_timer, 0.005)] = true
			previous_ai_timers[player.player_id] = player.reaction_timer
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
	_end_possession("test_end", {})
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
		"AI_reaction_timing_varies": ai_intervals.size() > 5,
		"physics_stays_finite_and_bounded": physics_finite and max_speed < 20,
		"both_teams_face_running_motion": running_samples[0] > 100 and running_samples[1] > 100 and float(backwards_samples[0]) / running_samples[0] < 0.03 and float(backwards_samples[1]) / running_samples[1] < 0.03,
		"live_match_frames_saved": screenshots.size() >= 7
	}
	if checkpoint == 1:
		# Offensive AI quality belongs to checkpoint three; record its touch
		# count here without making it the acceptance gate for handling.
		checks.erase("both_teams_make_physical_touches")
	checks.merge(fixture_checks)
	screenshots.append_array(fixture_frames)
	checks["possession_diagnostic_sampled"] = control_samples.size() > 300
	checks["physical_possession_observed"] = episodes.size() > 0
	var passed := true
	for value in checks.values():
		passed = passed and bool(value)
	var report := {"pass": passed, "checks": checks, "seconds": elapsed, "decisions": decision_count, "choices": choices, "switches": switches, "team_dribble_contacts": touches, "completed_kicks": kicks, "ai_actions": ai_actions, "sprint_seconds": sprint_seconds, "max_player_speed": max_speed, "scores": game.scores, "screenshots": screenshots, "trace": trace, "events": game.action_log, "hardware_input_injected": false, "subjective_feel_verified": false}
	var file := FileAccess.open(evidence_dir.path_join("scene-report.json"), FileAccess.WRITE)
	report["running_samples"] = running_samples
	report["backwards_running_samples"] = backwards_samples
	report["AI_reaction_intervals"] = ai_intervals.keys()
	report["AI_seed_base"] = 81011
	report["possession_episodes"] = episodes
	report["checkpoint"] = checkpoint
	report["fixture_observations"] = fixture_observations
	report["stop_trace"] = stop_trace
	report["control_samples"] = control_samples
	report["missed_dribble_contact_windows"] = missed_windows
	report["diagnostic_definition"] = "Episodes begin with an actual dribble contact within 0.95 m, or a recent such contact when selected. Escape means gap above 1.2 m for 0.15 s. Actual kicks, teammate handoffs, selection changes and restarts are excluded from losses. Opponent proximity is context, not proof of a challenge."
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("DECISION_SESSION_RESULT: " + JSON.stringify(report))
	get_tree().quit(0 if passed else 1)

func _observe_touch(player: FootballPlayer) -> void:
	recent_contacts[player.player_id] = elapsed
	if player == game.controlled and possession.is_empty():
		_start_possession(player)

func _observe_strike(kind: String, player: FootballPlayer) -> void:
	recent_contacts.erase(player.player_id)
	if not possession.is_empty() and possession.actor == player.player_id:
		_end_possession("intentional_" + kind, _snapshot(player))

func _start_possession(player: FootballPlayer) -> void:
	possession = {"actor": player.player_id, "start": elapsed, "start_contacts": player.completed_dribble_contacts, "sprint_seconds": 0.0, "turn_samples": 0, "max_gap": 0.0}
	missing_since = -1
	missing_snapshot = {}
	before_loss_frame = null

func _snapshot(player: FootballPlayer) -> Dictionary:
	var offset: Vector3 = game.ball.global_position - player.global_position
	offset.y = 0
	var velocity := Vector3(player.linear_velocity.x, 0, player.linear_velocity.z)
	var relative := Vector3(game.ball.linear_velocity.x, 0, game.ball.linear_velocity.z) - velocity
	var opponent_gap := INF
	var colliding: Array[String] = []
	for other in game.players:
		if other.team != player.team:
			opponent_gap = minf(opponent_gap, other.global_position.distance_to(player.global_position))
	for body in player.get_colliding_bodies():
		if body is FootballPlayer and body.team != player.team:
			colliding.append(body.player_id)
	var boot: Node3D = player.visual_controller.right_boot if player.dribble_right else player.visual_controller.left_boot
	return {"seconds": elapsed, "actor": player.player_id, "gap": offset.length(), "relative_speed": relative.length(), "outward_speed": relative.dot(offset.normalized()), "player_speed": velocity.length(), "ball_speed": game.ball.linear_velocity.length(), "ball_height": game.ball.global_position.y, "player_position": str(player.global_position), "ball_position": str(game.ball.global_position), "sprint": sprinting, "intent": str(player.intent), "turn_angle": acos(clampf(player.intent.normalized().dot(offset.normalized()), -1, 1)), "nearest_opponent": opponent_gap, "opponent_collisions": colliding, "ball_owner": game.ball.last_touch_id, "eligible": player.can_control(game.ball), "candidate": game.ball.control_candidate_id, "swing_active": player.dribble_active, "swing_elapsed": player.dribble_elapsed, "swing_hit": player.dribble_has_hit, "swing_contact_time": player.dribble_contact_time, "boot_gap": boot.global_position.distance_to(game.ball.global_position), "technique": player.dribble_technique, "action": player.action_kind, "kick_cooldown": player.kick_cooldown, "control_block": game.ball.control_block_remaining}

func _track_possession(delta: float) -> void:
	var player: FootballPlayer = game.controlled
	var snapshot := _snapshot(player)
	if player.dribble_elapsed < previous_swing_elapsed or not player.dribble_active:
		window_seen = false
	if player.dribble_active and not player.dribble_has_hit and not window_seen and player.dribble_elapsed > player.dribble_contact_time + 0.055:
		missed_windows += 1
		window_seen = true
	previous_swing_elapsed = player.dribble_elapsed
	sample_remaining -= delta
	if sample_remaining <= 0:
		sample_remaining = 0.05
		control_samples.append(snapshot)
		# Retain only one recent raster; save it if an escape starts.
		last_frame = get_viewport().get_texture().get_image()
	if possession.is_empty():
		if game.ball.last_touch_id == player.player_id and snapshot.gap <= FootballPlayer.CONTROL_REACH and elapsed - float(recent_contacts.get(player.player_id, -10)) < 0.3:
			_start_possession(player)
		return
	if possession.actor != player.player_id:
		_end_possession("selection_change", snapshot)
		return
	if game.kickoff_remaining > 0:
		_end_possession("restart", snapshot)
		return
	possession.max_gap = maxf(possession.max_gap, snapshot.gap)
	if sprinting:
		possession.sprint_seconds += delta
	if snapshot.turn_angle > 0.7:
		possession.turn_samples += 1
	if game.ball.last_touch_id != player.player_id:
		_end_possession("opponent_touch" if game.ball.last_touch_team != player.team else "teammate_handoff", snapshot)
	elif snapshot.gap > 1.2:
		if missing_since < 0:
			missing_since = elapsed
			missing_snapshot = snapshot
			before_loss_frame = last_frame
		if elapsed - missing_since >= 0.15:
			_end_possession("ball_escape", snapshot)
	else:
		missing_since = -1

func _end_possession(reason: String, snapshot: Dictionary) -> void:
	if possession.is_empty():
		return
	possession["end"] = elapsed
	possession["duration"] = elapsed - possession.start
	possession["reason"] = reason
	possession["loss_start"] = missing_snapshot
	possession["end_state"] = snapshot
	if reason in ["ball_escape", "opponent_touch"]:
		var stem := "loss_%02d" % episodes.size()
		if before_loss_frame != null:
			var before_name := stem + "_before.png"
			if before_loss_frame.save_png(evidence_dir.path_join(before_name)) == OK:
				screenshots.append(before_name)
		var after_name := stem + "_after.png"
		if get_viewport().get_texture().get_image().save_png(evidence_dir.path_join(after_name)) == OK:
			screenshots.append(after_name)
	episodes.append(possession)
	possession = {}
	missing_since = -1
	missing_snapshot = {}
	before_loss_frame = null
