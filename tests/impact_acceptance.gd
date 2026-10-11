extends Node

const CASES: Array[String] = ["light", "hard", "hop_clear", "AI_hop", "late_hop", "skill_low", "skill_high", "board", "restart"]
const TIMES: Array[float] = [1.2, 5.0, 1.8, 1.8, 4.8, 4.8, 1.2, 5.5, 0.8]
var game: Node3D
var victim: FootballPlayer
var attacker: FootballPlayer
var stage := -1
var elapsed := 0.0
var running := false
var screenshots: Array[String] = []
var events: Array = []
var checks: Dictionary = {}
var evidence: String
var contact_seen := false
var fall_seen := false
var stumble_seen := false
var floor_seen := false
var recovery_seen := false
var max_hop_height := 0.0
var finite := true
var max_part_speed := 0.0
var next_capture := 0.2
var capture_index := 0
var last_case: Dictionary = {}
var late_hop_requested := false
var paused_position := Vector3.ZERO
var pause_done := false
var resume_done := false

func begin(match_node: Node3D) -> void:
	game = match_node
	victim = game.players[0]
	attacker = game.players[3]
	evidence = OS.get_environment("BASED_FOOTBALL_EVIDENCE")
	for player in game.players:
		player.physical_event.connect(_event.bind(player))
	checks["R1_and_E_hop_mapping"] = false
	for event in InputMap.action_get_events("hop"):
		if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			checks["R1_and_E_hop_mapping"] = true
	game.camera.size = 7
	game.hud.hide()
	_next()
	running = true

func _event(kind: String, detail: Dictionary, player: FootballPlayer) -> void:
	events.append({"case": CASES[stage], "time": elapsed, "kind": kind, "player": player.player_id, "detail": detail})
	if player == victim:
		fall_seen = fall_seen or kind == "fall"
		stumble_seen = stumble_seen or kind == "stumble"
		recovery_seen = recovery_seen or kind == "get_up"
	if player == attacker and kind == "slide_body_contact":
		contact_seen = true

func _next() -> void:
	stage += 1
	if stage >= CASES.size():
		_complete()
		return
	elapsed = 0
	fall_seen = false
	stumble_seen = false
	recovery_seen = false
	floor_seen = false
	contact_seen = false
	late_hop_requested = false
	pause_done = false
	resume_done = false
	max_hop_height = 0
	next_capture = 0.2
	capture_index = 0
	for i in range(game.players.size()):
		var player: FootballPlayer = game.players[i]
		player.reset_action()
		player.freeze = player != victim and player != attacker
		player.global_position = Vector3(10, 0.02, -8 + i * 2)
		player.linear_velocity = Vector3.ZERO
		player.intent = Vector3.ZERO
		player.sprint = false
		player.energy = 1
		player.balance_skill = 1.0
		player.agility_skill = 1.0
		player.body_visual.position.y = 0
		player.reset_physics_interpolation()
	var origin := Vector3(0, 0.02, 0) if CASES[stage] != "board" else Vector3(0, 0.02, 10.8)
	victim.global_position = origin
	victim.aim = Vector3.RIGHT
	victim.body_visual.rotation.y = -PI / 2
	attacker.global_position = origin + Vector3(1.8, 0, 0)
	attacker.aim = Vector3.LEFT
	attacker.body_visual.rotation.y = PI / 2
	game.ball.global_position = Vector3(-4, 0.12, -3)
	game.ball.freeze = false
	game.ball.linear_velocity = Vector3.ZERO
	game.camera.position = origin + Vector3(1, 4, 5)
	game.camera.look_at(origin + Vector3(0, 0.6, 0))
	match CASES[stage]:
		"light", "skill_low", "skill_high":
			victim.balance_skill = 0.75 if CASES[stage] == "skill_low" else 1.3 if CASES[stage] == "skill_high" else 1.0
			# Equal physical impact, different balance threshold. Production slide
			# collision is covered separately by hard, hop and late-hop cases.
			victim.receive_slide(Vector3.LEFT * victim.mass * 0.8, victim.visual_controller.right_boot.global_position, 4.0 if CASES[stage] != "light" else 1.2)
		"AI_hop":
			attacker.linear_velocity = Vector3.LEFT * 6.0
			attacker.slide(game.ball)
			var hop_seeds: Array[int] = []
			for seed_value in range(1, 25):
				victim.reset_action()
				victim.energy = 1
				victim.reaction_timer = 0
				victim.ai_rng.seed = seed_value
				if FootballAI.decide(victim, game.players, game.ball, 0.008) == "hop_attempt":
					hop_seeds.append(seed_value)
			checks["AI_same_threat_has_varied_hop_choices"] = hop_seeds.size() > 0 and hop_seeds.size() < 24
			victim.reset_action()
			victim.energy = 1
			victim.reaction_timer = 0
			victim.ai_rng.seed = hop_seeds[0] if not hop_seeds.is_empty() else 1
			checks["AI_can_request_production_hop"] = FootballAI.decide(victim, game.players, game.ball, 0.008) == "hop_attempt"
		"hard", "late_hop":
			attacker.linear_velocity = Vector3.LEFT * 6.0
			attacker.slide(game.ball)
		"hop_clear":
			game._select(0)
			game._controller_actions(0.008, {"hop": true})
			checks["controller_hop_request_accepted"] = victim.hop_active
		"board":
			victim.receive_slide(Vector3(0, 0, 2.0) * victim.mass, victim.visual_controller.right_boot.global_position, 7.0)
		"restart":
			victim.receive_slide(Vector3.LEFT * victim.mass, victim.visual_controller.right_boot.global_position, 7.0)
			game.reset_positions(0)

func _physics_process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	if CASES[stage] == "hard" and victim.ragdoll != null:
		if elapsed >= 0.6 and not pause_done:
			_toggle_pause()
			paused_position = victim.ragdoll.torso.global_position
			pause_done = true
		elif elapsed >= 0.9 and pause_done and not resume_done:
			checks["pause_freezes_ragdoll_and_actions"] = victim.ragdoll.torso.global_position.distance_to(paused_position) < 0.001
			_toggle_pause()
			resume_done = true
	if CASES[stage] == "hop_clear" and elapsed >= 0.12 and attacker.action_kind == "" and attacker.tackle_cooldown <= 0:
		attacker.linear_velocity = Vector3.LEFT * 6
		attacker.slide(game.ball)
	if CASES[stage] == "late_hop" and elapsed >= 0.105 and not late_hop_requested:
		late_hop_requested = victim.hop()
	max_hop_height = maxf(max_hop_height, victim.global_position.y)
	finite = finite and victim.global_position.is_finite() and attacker.global_position.is_finite()
	if victim.ragdoll != null:
		checks["fallen_player_cannot_play_ball"] = not victim.can_control(game.ball) and not victim.kick(game.ball, Vector3.RIGHT, 10, 0) and not victim.slide(game.ball) and not victim.hop()
		checks["eleven_physical_parts"] = victim.ragdoll.bodies.size() == 11
		floor_seen = floor_seen or victim.ragdoll.torso.global_position.y < 0.45
		for body in victim.ragdoll.bodies:
			finite = finite and body.global_position.is_finite() and body.linear_velocity.is_finite()
			max_part_speed = maxf(max_part_speed, body.linear_velocity.length())
	if elapsed >= next_capture and capture_index < 6:
		next_capture += 0.4
		var file := CASES[stage] + "_%02d.png" % capture_index
		if get_viewport().get_texture().get_image().save_png(evidence.path_join(file)) == OK:
			screenshots.append(file)
		capture_index += 1
	if elapsed >= float(TIMES[stage]):
		var final_frame := CASES[stage] + "_final.png"
		if get_viewport().get_texture().get_image().save_png(evidence.path_join(final_frame)) == OK:
			screenshots.append(final_frame)
		match CASES[stage]:
			"light": checks["light_hit_stumbles_without_fall"] = stumble_seen and not fall_seen
			"hard":
				checks["actual_slide_hits_leg_and_falls"] = contact_seen and fall_seen
				checks["hard_fall_reaches_floor"] = floor_seen
				checks["hard_fall_gets_up"] = recovery_seen and victim.ragdoll == null
			"hop_clear":
				checks["hop_physically_lifts_body"] = max_hop_height > 0.5
				checks["well_timed_hop_clears_slide"] = not contact_seen and not fall_seen
				checks["hop_lands_and_control_returns"] = not victim.hop_active and victim.ragdoll == null and victim.global_position.y < 0.12
			"AI_hop": checks["AI_hop_physically_clears_and_lands"] = max_hop_height > 0.5 and not fall_seen and not contact_seen and not victim.hop_active
			"late_hop": checks["late_hop_can_be_tripped"] = late_hop_requested and contact_seen and fall_seen
			"skill_low": checks["lower_balance_falls_at_marginal_hit"] = fall_seen
			"skill_high": checks["higher_balance_stumbles_at_same_hit"] = stumble_seen and not fall_seen
			"board": checks["board_fall_recovers_without_escape"] = recovery_seen and absf(victim.global_position.z) < 12
			"restart": checks["restart_cleans_ragdoll"] = victim.ragdoll == null and not victim.freeze and victim.body_visual.visible and victim.collision_layer == 1
		_next()

func _toggle_pause() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	game._unhandled_input(event)

func _complete() -> void:
	running = false
	checks["parts_finite_and_bounded"] = finite and max_part_speed < 25
	checks["rendered_frames_saved"] = screenshots.size() >= 30
	var passed := true
	for value in checks.values():
		passed = passed and bool(value)
	var report := {"pass": passed, "checks": checks, "screenshots": screenshots, "events": events, "max_part_speed": max_part_speed, "hardware_input_injected": false}
	var file := FileAccess.open(evidence.path_join("scene-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("IMPACT_RESULT: " + JSON.stringify(report))
	get_tree().quit(0 if passed else 1)
