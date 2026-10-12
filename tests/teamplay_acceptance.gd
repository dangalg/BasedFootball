extends Node

# One finite physical sequence, followed by autonomous team play.
const CASES := ["side_wall", "corner", "end_wall", "switch", "pass", "lob", "miss", "pressure", "live"]
const TIMES := [4.0, 4.0, 4.0, 0.1, 4.0, 4.5, 0.8, 1.2, 12.0]
var game: Node3D
var stage := -1
var elapsed := 0.0
var running := false
var checks: Dictionary = {}
var screenshots: Array[String] = []
var measurements: Array = []
var actor: FootballPlayer
var receiver: FootballPlayer
var ball_start := Vector3.ZERO
var receiver_start := Vector3.ZERO
var contacts_start := 0
var kicks_start := 0
var receiver_contacts_start := 0
var assigned := false
var receiving_seen := false
var advanced := false
var first_frame := false
var last_frame := false
var finite := true

func begin(match_node: Node3D) -> void:
	game = match_node
	game.hud.hide()
	for i in range(game.players.size()):
		game.players[i].ai_rng.seed = 900 + i
	_next()
	running = true

func _next() -> void:
	stage += 1
	if stage >= CASES.size():
		_finish()
		return
	elapsed = 0
	assigned = false
	receiving_seen = false
	advanced = false
	first_frame = false
	last_frame = false
	actor = game.players[0]
	receiver = game.players[1]
	for i in range(game.players.size()):
		var player: FootballPlayer = game.players[i]
		player.reset_action()
		player.freeze = player != actor
		player.global_position = Vector3(-3, 0.02, 0) if player == actor else Vector3(10, 0.02, -8 + i * 2)
		player.linear_velocity = Vector3.ZERO
		player.angular_velocity = Vector3.ZERO
		player.intent = Vector3.ZERO
		player.sprint = false
		player.energy = 1
		player.kick_cooldown = 0
		player.touch_cooldown = 0
		player.reaction_timer = 0
		player.team_role = ""
		player.aim = Vector3.RIGHT
		player.body_visual.rotation = Vector3(0, -PI / 2, 0)
		player.reset_physics_interpolation()
	game.ball.freeze = false
	game.ball.global_position = actor.global_position + Vector3(0.61, 0.11, 0)
	game.ball.linear_velocity = Vector3.ZERO
	game.ball.angular_velocity = Vector3.ZERO
	game.ball.control_block_remaining = 0
	game.ball.last_touch_team = -1
	game.ball.last_touch_id = ""
	game._select(0)
	match CASES[stage]:
		"side_wall":
			actor.global_position = Vector3(-3, 0.02, 10.3)
			game.ball.global_position = Vector3(-3, 0.11, 11.88)
		"corner":
			actor.global_position = Vector3(16.4, 0.02, 10.5)
			game.ball.global_position = Vector3(17.88, 0.11, 11.88)
		"end_wall":
			actor.global_position = Vector3(-16.4, 0.02, -5)
			game.ball.global_position = Vector3(-17.88, 0.11, -5)
		"switch":
			game.players[3].global_position = Vector3.ZERO
			game.ball.global_position = Vector3(0.5, 0.11, 0)
			game.ball.last_touch_team = 1
			receiver.global_position = Vector3(1, 0.02, 0)
			game.players[2].global_position = Vector3(-5, 0.02, 0.2)
			game._switch_player()
			checks["L1_prefers_goal_side_defender_over_nearer_player"] = game.controlled == game.players[2]
			game._select(0)
			game._switch_player(Vector3.RIGHT)
			checks["right_stick_retains_directional_choice"] = game.controlled == receiver
		"pass", "lob":
			receiver.freeze = false
			receiver.global_position = Vector3(1, 0.02, 0.5) if CASES[stage] == "pass" else Vector3(5, 0.02, 1.5)
			game.ball.last_touch_team = 0
			game.ball.last_touch_id = actor.player_id
			actor.aim = (receiver.global_position - actor.global_position).normalized()
			game._controller_actions(0, {"pass": CASES[stage] == "pass", "square": CASES[stage] == "lob"})
		"miss":
			game.ball.last_touch_team = 0
			game.ball.last_touch_id = actor.player_id
			game._controller_actions(0, {"pass": true})
			game.ball.global_position += Vector3.FORWARD * 3
		"pressure":
			actor.global_position = Vector3(-13, 0.02, 0)
			game.ball.global_position = actor.global_position + Vector3(0.61, 0.11, 0)
			game.ball.last_touch_team = 0
			game.players[3].global_position = actor.global_position + Vector3(1.6, 0, 0.3)
		"live":
			game.reset_positions(0)
			game.kickoff_remaining = 0
			for player in game.players:
				player.freeze = false
	ball_start = game.ball.global_position
	receiver_start = receiver.global_position
	contacts_start = actor.completed_kicks + actor.completed_dribble_contacts
	kicks_start = actor.completed_kicks
	receiver_contacts_start = receiver.completed_dribble_contacts + receiver.completed_kicks
	game.camera.size = 10 if CASES[stage] != "live" else 43
	game.camera.global_position = actor.global_position + Vector3(0, 7, 8) if CASES[stage] != "live" else Vector3(0, 34, 29)
	game.camera.look_at(actor.global_position if CASES[stage] != "live" else Vector3.ZERO)

func _physics_process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	var label: String = CASES[stage]
	if label in ["side_wall", "corner", "end_wall", "pressure"]:
		FootballAI.decide(actor, game.players, game.ball, delta)
	elif label in ["pass", "lob"]:
		FootballAI.decide(receiver, game.players, game.ball, delta)
		assigned = assigned or receiver.incoming_pass_remaining > 0
		receiving_seen = receiving_seen or receiver.team_role == "receive"
		advanced = advanced or (game.ball.last_touch_id == receiver.player_id and (receiver.intent.x > 0.2 or receiver.action_kind == "kick"))
	elif label == "live":
		for player in game.players:
			FootballAI.decide(player, game.players, game.ball, delta)
	game._control_ball()
	finite = finite and game.ball.global_position.is_finite()
	for player in game.players:
		finite = finite and player.global_position.is_finite()
	if not first_frame and elapsed > 0.4:
		first_frame = true
		_capture(label + "_start")
	if not last_frame and elapsed > TIMES[stage] - 0.1:
		last_frame = true
		_capture(label + "_end")
	if elapsed >= TIMES[stage]:
		if label in ["side_wall", "corner", "end_wall"]:
			checks[label + "_physical_recovery"] = actor.completed_kicks + actor.completed_dribble_contacts > contacts_start and game.ball.global_position.distance_to(ball_start) > 0.4
		elif label in ["pass", "lob"]:
			checks[label + "_assigned_after_contact"] = assigned and actor.completed_kicks > kicks_start
			checks[label + "_receiver_moves_to_intercept"] = receiving_seen and receiver.global_position.distance_to(receiver_start) > 0.3
			checks[label + "_receiver_physically_collects"] = receiver.completed_dribble_contacts + receiver.completed_kicks > receiver_contacts_start
			checks[label + "_receiver_advances_or_plays_ball"] = advanced
		elif label == "miss":
			checks["miss_creates_no_receiver_assignment"] = actor.completed_kicks == kicks_start and receiver.incoming_pass_remaining == 0
		elif label == "pressure":
			checks["pressure_prompts_pass_or_clear"] = actor.completed_kicks > kicks_start
		elif label == "live":
			checks["autonomous_teams_make_physical_kicks"] = game.action_log.any(func(event: Dictionary): return event.get("kind", "") in ["pass", "shot", "lob", "clear", "finesse"])
		measurements.append({"case": label, "ball": str(game.ball.global_position), "receiver": str(receiver.global_position), "actor_kicks": actor.completed_kicks - kicks_start})
		_next()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var filename := label + ".png"
	checks["capture_" + label] = get_viewport().get_texture().get_image().save_png(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join(filename)) == OK
	screenshots.append(filename)

func _finish() -> void:
	running = false
	checks["finite_physics"] = finite
	var report := {"pass": not checks.values().has(false), "checks": checks, "screenshots": screenshots, "measurements": measurements, "scope": "Bounded wall recovery, switching and physical receiving plus autonomous team play. Hardware controls and fun remain human evaluation."}
	var file := FileAccess.open(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join("scene-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	get_tree().quit(0 if report.pass else 1)
