extends Node

# One finite session. Direct intents and production button-context snapshots never
# read or inject hardware input. No automatic retries or parameter tuning.
const NAMES := ["carry", "left_turn", "right_turn", "reverse", "stop", "standing", "standing_miss", "slide", "slide_miss", "shoulder", "shoulder_miss", "airborne", "out_of_reach", "sprint", "free_run", "carry_speed", "free_sprint", "carry_sprint", "pass", "shot", "lob", "kick_miss", "weak_shot", "through", "fast_turn", "sprint_stop", "shoulder_free"]
const DURATIONS := [1.4, 1.1, 1.1, 1.4, 1.3, 0.9, 0.7, 1.4, 1.3, 0.95, 0.65, 0.25, 0.4, 0.8, 1.6, 1.6, 2.5, 2.5, 1.1, 1.1, 1.5, 0.6, 1.1, 1.1, 2.2, 1.5, 0.95]
var game: Node3D
var carrier: FootballPlayer
var defender: FootballPlayer
var checks: Dictionary = {}
var evidence_dir: String
var screenshots: Array[String] = []
var stage: int = -1
var elapsed: float = 0
var running := false
var max_gap: float = 0
var stop_gap: float = 0
var stop_speed: float = 0
var challenge_gaps: Dictionary = {}
var turn_positions: Array = []
var touch_start: int = 0
var max_tick_touches: int = 0
var previous_touches: int = 0
var recovery_seen := false
var slide_lowering_seen := false
var frame_saved := false
var samples: Array = []
var distances: Dictionary = {}
var heights: Dictionary = {}
var stage_origin := Vector3.ZERO
var ball_origin := Vector3.ZERO
var kick_started := false
var no_early_contact := true
var strike_seen := false
var slide_contact_seen := false
var moving_carrier_seen := false
var kick_contact_seconds: Dictionary = {}
var max_sprint_gap := 0.0
var max_fast_turn_gap := 0.0
var max_leg_step := 0.0
var previous_leg := Quaternion.IDENTITY
var previous_knee := Quaternion.IDENTITY
var animation_frames := 0
var shoulder_stagger_seen := false
var free_intervals := 0
var dribble_contact_total := 0

func begin(match_node: Node3D) -> void:
	game = match_node
	carrier = game.players[0]
	defender = game.players[3]
	evidence_dir = OS.get_environment("BASED_FOOTBALL_EVIDENCE")
	var inspector: Node = load("res://tests/visual_acceptance.gd").new()
	add_child(inspector)
	checks = await inspector.collect_checks(game, false)
	inspector.queue_free()
	var fixture_score: Array[int] = [0, 0]
	game.hud.update_match(fixture_score, 180, carrier, 0)
	game.hud.status.text = "LOCAL VERIFICATION / HARDWARE INPUT DISABLED"
	game.hud.banner.text = ""
	await RenderingServer.frame_post_draw
	_capture("courtyard")
	game.camera.size = 5.8
	game.camera.position = Vector3(-1.2, 3.2, 4.2)
	game.camera.look_at(Vector3(-0.8, 0.95, 0))
	game.hud.hide()
	await RenderingServer.frame_post_draw
	_capture("athletes")
	game.hud.show()
	_fixture(Vector3(-7, 0.06, 4))
	running = true
	_next_stage()
	print("HANDLING_SESSION_STARTED: one production-physics sequence; no hardware input")

func _fixture(position: Vector3) -> void:
	for i in range(game.players.size()):
		var player: FootballPlayer = game.players[i]
		player.reset_action()
		player.intent = Vector3.ZERO
		player.sprint = false
		player.kick_cooldown = 0
		player.touch_cooldown = 0
		player.energy = 1
		player.challenge_contacts = 0
		player.completed_kicks = 0
		player.completed_dribble_contacts = 0
		player.action_has_hit = false
		player.linear_velocity = Vector3.ZERO
		player.angular_velocity = Vector3.ZERO
		player.freeze = player != carrier
		player.global_position = position if player == carrier else Vector3(13, 0.06, -10 + i * 3)
		player.reset_physics_interpolation()
	carrier.aim = Vector3.RIGHT
	game._select(0)
	game.ball.freeze = false
	game.ball.global_position = position + Vector3(0.61, 0.10, 0)
	game.ball.linear_velocity = Vector3.ZERO
	game.ball.angular_velocity = Vector3.ZERO
	game.ball.last_touch_id = carrier.player_id
	game.ball.last_touch_team = carrier.team
	game.ball.control_block_remaining = 0
	game.ball.control_candidate_id = ""
	game.ball.reset_physics_interpolation()
	touch_start = game.ball.touches
	previous_touches = game.ball.touches

func _place_defender(position: Vector3, direction: Vector3) -> void:
	defender.freeze = false
	defender.global_position = position
	defender.aim = direction
	defender.reset_physics_interpolation()

func _next_stage() -> void:
	stage += 1
	elapsed = 0
	frame_saved = false
	recovery_seen = false
	no_early_contact = true
	strike_seen = false
	kick_started = false
	if stage >= NAMES.size():
		running = false
		_complete()
		return
	game.camera.size = 25
	game.camera.position = Vector3(0, 23, 19)
	game.camera.look_at(Vector3.ZERO)
	game.hud.flash("CHECK / " + NAMES[stage].to_upper(), DURATIONS[stage])
	if stage == 4:
		var nearby: FootballPlayer = game.players[1]
		nearby.global_position = game.ball.global_position + Vector3(0, -0.10, 0.85)
		checks["nearby_second_player_eligible"] = nearby.can_control(game.ball)
	elif stage >= 5 and stage != 25:
		_fixture(Vector3(0, 0.06, 0))
		if stage in [16, 17]:
			_fixture(Vector3(-7, 0.06, 0))
		match NAMES[stage]:
			"standing":
				_place_defender(Vector3(0.61, 0.06, 0.70), Vector3.FORWARD)
				game.controlled = defender
				game._controller_actions(0, {"primary": true})
				checks["circle_defends_with_standing_tackle"] = defender.action_kind == "standing" and not game.charging
			"standing_miss", "slide_miss":
				carrier.freeze = true
				carrier.global_position = Vector3(-8, 0.06, 0)
				game.ball.global_position = Vector3(4, 0.13, 0)
				_place_defender(Vector3(0, 0.06, 0), Vector3.FORWARD)
				if stage == 6:
					defender.tackle(game.ball)
				else:
					defender.slide(game.ball)
			"slide":
				carrier.linear_velocity = Vector3.RIGHT * 2.8
				game.ball.linear_velocity = Vector3.RIGHT * 2.8
				_place_defender(Vector3(0.61, 0.06, 1.65), Vector3(0.4, 0, -1).normalized())
				game.controlled = defender
				game._controller_actions(0, {"square": true})
				checks["square_defends_with_slide"] = defender.action_kind == "slide"
				game.camera.size = 5.8
				game.camera.position = Vector3(1, 3.2, 4.2)
				game.camera.look_at(Vector3(0.8, 0.6, 0))
			"shoulder":
				_place_defender(Vector3(0.86, 0.06, 0), Vector3.FORWARD)
				defender.intent = Vector3.LEFT
				game.controlled = defender
				game._controller_actions(0, {"primary": true})
				checks["circle_uses_side_contact_shoulder"] = defender.action_kind == "shoulder"
			"shoulder_miss":
				_place_defender(Vector3(4, 0.06, 0), Vector3.FORWARD)
				defender.shoulder(game.ball)
			"airborne":
				game.ball.global_position = Vector3(0.61, 1.5, 0)
				game.ball.linear_velocity = Vector3.UP * 2
			"out_of_reach":
				game.ball.global_position = Vector3(1.6, 0.13, 0)
				game.ball.linear_velocity = Vector3.RIGHT * 3
			"free_run", "free_sprint":
				game.ball.global_position = Vector3(9, 0.13, 0)
			"fast_turn":
				carrier.linear_velocity = Vector3.RIGHT * 6
				game.ball.linear_velocity = Vector3.RIGHT * 6
			"shoulder_free":
				game.ball.global_position = Vector3(0, 0.13, -0.61)
				_place_defender(Vector3(0.86, 0.06, 0), Vector3.FORWARD)
				defender.intent = Vector3.LEFT
				defender.shoulder(game.ball)
		if stage >= 18 and stage <= 23:
			game.camera.size = 6.5
			game.camera.position = Vector3(1, 3.2, 4.2)
			game.camera.look_at(Vector3(1, 0.6, 0))
	stage_origin = carrier.global_position
	ball_origin = game.ball.global_position
	previous_leg = carrier.right_leg.quaternion
	previous_knee = carrier.visual_controller.right_knee.quaternion

func _physics_process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	carrier.intent = Vector3.ZERO
	if stage in [0, 2, 7, 13, 14, 15, 16, 17]:
		carrier.intent = Vector3.RIGHT
	elif stage == 1:
		carrier.intent = Vector3.FORWARD
	elif stage == 3:
		carrier.intent = Vector3.LEFT
	elif stage == 24:
		carrier.intent = Vector3.FORWARD
	carrier.sprint = stage in [13, 16, 17, 24]
	if carrier.intent.length_squared() > 0.01:
		carrier.aim = carrier.intent.normalized()
	if stage not in [6, 8, 9, 10, 14, 16, 26] and (stage < 18 or stage in [24, 25]):
		game._control_ball()
	if stage >= 18 and stage <= 23:
		_check_kick_stage()
	var offset: Vector3 = game.ball.global_position - carrier.global_position
	offset.y = 0
	var gap := offset.length()
	if stage <= 4:
		max_gap = maxf(max_gap, gap)
		max_tick_touches = maxi(max_tick_touches, game.ball.touches - previous_touches)
	if stage in [13, 17]:
		max_sprint_gap = maxf(max_sprint_gap, gap)
	if stage == 24:
		max_fast_turn_gap = maxf(max_fast_turn_gap, gap)
	if stage <= 4 or stage in [15, 17, 24, 25]:
		if elapsed > 0.12:
			max_leg_step = maxf(max_leg_step, maxf(previous_leg.angle_to(carrier.right_leg.quaternion), previous_knee.angle_to(carrier.visual_controller.right_knee.quaternion)))
		if game.ball.touches == previous_touches:
			free_intervals += 1
		else:
			dribble_contact_total += game.ball.touches - previous_touches
	previous_leg = carrier.right_leg.quaternion
	previous_knee = carrier.visual_controller.right_knee.quaternion
	previous_touches = game.ball.touches
	if stage in [9, 26]:
		shoulder_stagger_seen = shoulder_stagger_seen or carrier.stagger_remaining > 0
		challenge_gaps[NAMES[stage]] = maxf(float(challenge_gaps.get(NAMES[stage], 0)), gap)
	if stage in [15, 17] and elapsed >= 0.5 and elapsed <= 1.16:
		var index := int((elapsed - 0.5) / 0.055)
		var label := ("dribble_" if stage == 15 else "sprint_") + "%02d" % index
		if not screenshots.has(label + ".png"):
			game.camera.size = 6.5
			game.camera.position = carrier.global_position + Vector3(1, 3.2, 4.2)
			game.camera.look_at(carrier.global_position + Vector3(0.5, 0.6, 0))
			_capture(label)
			animation_frames += 1
	if stage in [5, 7, 9, 13]:
		challenge_gaps[NAMES[stage]] = maxf(float(challenge_gaps.get(NAMES[stage], 0)), gap)
	if stage in [5, 7] and defender.recovery_remaining > 0:
		recovery_seen = recovery_seen or (not defender.can_control(game.ball) and not defender.kick(game.ball, Vector3.RIGHT, 10, 0.12) and not defender.tackle(game.ball))
	if stage == 7:
		if defender.action_kind == "slide":
			slide_lowering_seen = slide_lowering_seen or is_equal_approx(defender.body_collider.shape.height, 0.8)
		moving_carrier_seen = moving_carrier_seen or Vector3(carrier.linear_velocity.x, 0, carrier.linear_velocity.z).length() > 1.5
		slide_contact_seen = slide_contact_seen or (defender.challenge_contacts == 1 and game.ball.last_touch_id == defender.player_id and game.ball.control_block_remaining > 0)
	if stage in [5, 7, 9] and not frame_saved and elapsed >= (0.22 if stage == 7 else 0.15):
		_capture(NAMES[stage])
		frame_saved = true
	if Engine.get_physics_frames() % 12 == 0:
		samples.append({"stage": NAMES[stage], "seconds": snappedf(elapsed, 0.001), "gap": gap, "ball_speed": game.ball.linear_velocity.length(), "ball_height": game.ball.global_position.y, "carrier_speed": carrier.linear_velocity.length(), "defender_action": defender.action_kind, "defender_contacts": defender.challenge_contacts, "kick_action": carrier.action_kind, "kick_elapsed": carrier.action_elapsed, "completed_kicks": carrier.completed_kicks, "dribble_active": carrier.dribble_active, "dribble_phase": carrier.dribble_elapsed, "dribble_hit": carrier.dribble_has_hit, "dribble_contacts": carrier.completed_dribble_contacts})
	if elapsed >= float(DURATIONS[stage]):
		_end_stage(gap)
		_next_stage()

func _check_kick_stage() -> void:
	if elapsed >= 0.12 and not kick_started:
		kick_started = true
		touch_start = game.ball.touches
		match NAMES[stage]:
			"pass": game._controller_actions(0, {"pass": true})
			"shot":
				game._controller_actions(0.65, {"primary": true})
				game._controller_actions(0, {"primary_release": true})
			"lob": game._controller_actions(0, {"square": true})
			"kick_miss":
				carrier.kick(game.ball, Vector3.RIGHT, 18, 2, "shot")
				game.ball.global_position = Vector3(3, 0.13, 0)
			"weak_shot": carrier.kick(game.ball, Vector3.RIGHT, 12, 0.7, "shot")
			"through": game._controller_actions(0, {"through": true})
		checks[NAMES[stage] + "_queues_animation"] = carrier.action_kind == "kick"
	if kick_started and carrier.action_kind == "kick" and carrier.action_elapsed < carrier.kick_contact_time - 0.02:
		no_early_contact = no_early_contact and game.ball.touches == touch_start
	if carrier.completed_kicks > 0 and not strike_seen:
		strike_seen = true
		kick_contact_seconds[NAMES[stage]] = carrier.action_elapsed
		checks[NAMES[stage] + "_contact_matches_boot"] = carrier.last_kick_contact_distance <= FootballBall.RADIUS + 0.095
	heights[NAMES[stage]] = maxf(float(heights.get(NAMES[stage], 0)), game.ball.global_position.y)
	if stage in [18, 20] and elapsed >= 0.50 and not frame_saved:
		_capture(NAMES[stage] + "_flight")
		frame_saved = true
	if stage == 19:
		if elapsed >= 0.18 and not screenshots.has("kick_backswing.png"):
			_capture("kick_backswing")
		if strike_seen and not screenshots.has("kick_contact.png"):
			_capture("kick_contact")
		if elapsed >= 0.36 and not screenshots.has("kick_followthrough.png"):
			_capture("kick_followthrough")

func _end_stage(gap: float) -> void:
	if stage <= 3:
		turn_positions.append([carrier.global_position.x, carrier.global_position.z])
	match NAMES[stage]:
		"reverse": _capture("turns")
		"stop":
			stop_gap = gap
			stop_speed = Vector3(game.ball.linear_velocity.x, 0, game.ball.linear_velocity.z).length()
			checks["stop_keeps_ball_in_reach"] = gap < FootballPlayer.CONTROL_REACH
			checks["stop_settles_ball"] = stop_speed < 0.35
			_capture("stop")
		"standing":
			checks["standing_contact_dislodges_ball"] = defender.challenge_contacts == 1 and float(challenge_gaps.get("standing", 0)) > FootballPlayer.CONTROL_REACH
			checks["standing_recovery_blocks_actions"] = recovery_seen
		"standing_miss":
			checks["missed_standing_has_no_remote_effect"] = defender.challenge_contacts == 0 and game.ball.touches == touch_start
		"slide":
			checks["slide_contacts_moving_carrier_ball"] = slide_contact_seen and moving_carrier_seen
			checks["slide_contact_dislodges_ball"] = defender.challenge_contacts == 1 and float(challenge_gaps.get("slide", 0)) > FootballPlayer.CONTROL_REACH
			checks["slide_recovery_blocks_actions"] = recovery_seen
			checks["slide_lowers_then_restores_body"] = slide_lowering_seen and is_equal_approx(defender.body_collider.shape.height, 1.65) and is_equal_approx(defender.body_collider.position.y, 0.86)
		"slide_miss":
			checks["missed_slide_has_no_remote_effect"] = defender.challenge_contacts == 0 and game.ball.touches == touch_start
		"shoulder":
			checks["shoulder_contact_staggers_carrier"] = defender.challenge_contacts == 1 and shoulder_stagger_seen
			checks["shoulder_uses_body_contact_without_ball_impulse"] = game.ball.touches == touch_start
		"shoulder_miss":
			checks["missed_shoulder_has_no_remote_effect"] = defender.challenge_contacts == 0 and game.ball.touches == touch_start and gap < FootballPlayer.CONTROL_REACH
		"airborne", "out_of_reach":
			checks[NAMES[stage] + "_ball_remains_free"] = game.ball.touches == touch_start
		"sprint": checks["ordinary_sprint_stays_recoverable"] = gap < FootballPlayer.CONTROL_REACH
		"carry_sprint": checks["sustained_sprint_keeps_touching"] = carrier.completed_dribble_contacts >= 6 and gap < FootballPlayer.CONTROL_REACH
		"fast_turn": checks["fast_turn_recovers_control"] = gap < FootballPlayer.CONTROL_REACH
		"sprint_stop":
			checks["sprint_stop_keeps_ball"] = gap < FootballPlayer.CONTROL_REACH
			checks["sprint_stop_settles_ball"] = Vector3(game.ball.linear_velocity.x, 0, game.ball.linear_velocity.z).length() < 0.35
		"shoulder_free":
			checks["suitable_shoulder_can_free_ball"] = defender.challenge_contacts == 1 and float(challenge_gaps.get("shoulder_free", 0)) > FootballPlayer.CONTROL_REACH and game.ball.touches == touch_start
	if stage in [14, 15, 16, 17]:
		distances[NAMES[stage]] = carrier.global_position.distance_to(stage_origin)
	elif stage >= 18 and stage <= 23:
		distances[NAMES[stage]] = Vector2(game.ball.global_position.x - ball_origin.x, game.ball.global_position.z - ball_origin.z).length()
		checks[NAMES[stage] + "_waits_for_contact_window"] = no_early_contact
		if stage == 21:
			checks["missed_kick_has_no_remote_impulse"] = carrier.completed_kicks == 0 and game.ball.touches == touch_start
		else:
			checks[NAMES[stage] + "_one_physical_strike"] = carrier.completed_kicks == 1 and game.ball.touches == touch_start + 1

func _capture(label: String) -> void:
	var filename := label + ".png"
	if get_viewport().get_texture().get_image().save_png(evidence_dir.path_join(filename)) == OK:
		screenshots.append(filename)

func _complete() -> void:
	carrier.intent = Vector3.ZERO
	checks["turns_keep_ball_in_kicking_reach"] = max_gap < FootballPlayer.CONTROL_REACH
	checks["carrying_moves_player"] = float(turn_positions[0][0]) > -4
	checks["left_turn_changes_direction"] = float(turn_positions[1][1]) < float(turn_positions[0][1]) - 1.0
	checks["right_turn_changes_direction"] = float(turn_positions[2][0]) > float(turn_positions[1][0]) + 1.0
	checks["reversal_changes_direction"] = float(turn_positions[3][0]) < float(turn_positions[2][0]) - 1.3
	checks["one_control_touch_per_tick"] = max_tick_touches <= 1
	checks["rendered_action_and_animation_frames_saved"] = screenshots.size() >= 34 and animation_frames >= 22
	checks["dribble_legs_blend_without_pose_snaps"] = max_leg_step < 0.35
	checks["ball_is_free_between_timed_contacts"] = dribble_contact_total > 5 and free_intervals > dribble_contact_total * 8
	checks["sprint_ball_remains_recoverable"] = max_sprint_gap < 1.15
	checks["fast_turn_ball_remains_recoverable"] = max_fast_turn_gap < 1.15
	checks["control_touches_cost_ground_without_changing_pace"] = float(distances["carry_speed"]) > 1 and float(distances["carry_speed"]) < float(distances["free_run"]) * 0.95
	checks["sprint_touches_cost_ground"] = float(distances["carry_sprint"]) < float(distances["free_sprint"])
	checks["ground_pass_stays_low"] = float(heights["pass"]) < 0.35 and float(distances["pass"]) > 3
	checks["shot_has_physical_flight"] = float(heights["shot"]) > 0.25 and float(distances["shot"]) > float(distances["pass"])
	checks["lofted_pass_flies_higher"] = float(heights["lob"]) > float(heights["shot"]) + 0.25
	checks["higher_power_shot_travels_further"] = float(distances["shot"]) > float(distances["weak_shot"])
	var passed := true
	for value in checks.values():
		passed = passed and bool(value)
	var report := {"pass": passed, "checks": checks, "normal_stick_strength": 1, "max_control_gap": max_gap, "max_sprint_gap": max_sprint_gap, "max_fast_turn_gap": max_fast_turn_gap, "max_leg_step_radians": max_leg_step, "free_physics_ticks": free_intervals, "dribble_contacts": dribble_contact_total, "stop_gap": stop_gap, "stop_ball_speed": stop_speed, "challenge_gaps": challenge_gaps, "turn_positions": turn_positions, "distances": distances, "flight_heights": heights, "kick_contact_seconds": kick_contact_seconds, "screenshots": screenshots, "hardware_input_injected": false, "subjective_feel_verified": false, "trace": samples}
	var file := FileAccess.open(evidence_dir.path_join("scene-report.json"), FileAccess.WRITE)
	if file == null:
		push_error("Could not write handling report.")
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("HANDLING_SESSION_RESULT: " + JSON.stringify(report))
	get_tree().quit(0 if passed else 1)
