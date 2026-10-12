extends Node

const CASES := ["turn", "stop", "sprint", "settle", "redirect", "first_time", "left_kick", "right_kick", "kick_miss"]
const TIMES := [1.6, 1.6, 1.6, 1.5, 1.5, 0.9, 0.8, 0.8, 0.8]
var game: Node3D
var actor: FootballPlayer
var athlete := 0
var stage := -1
var elapsed := 0.0
var running := false
var checks: Dictionary = {}
var screenshots: Array[String] = []
var observations: Array = []
var max_gap := 0.0
var contacts := 0
var kicks := 0
var captured := false
var cushioned := false
var stop_trace: Array = []
var stop_frame := 0

func begin(match_node: Node3D) -> void:
	game = match_node
	game.hud.hide()
	_next()
	running = true

func _next() -> void:
	stage += 1
	if stage >= CASES.size():
		stage = 0
		athlete += 1
	if athlete >= 2:
		_live()
		return
	actor = game.players[athlete]
	for i in range(game.players.size()):
		var player: FootballPlayer = game.players[i]
		player.reset_action()
		player.freeze = player != actor
		player.global_position = Vector3(-3, 0.02, 0) if player == actor else Vector3(12, 0.02, -9 + i * 3)
		player.linear_velocity = Vector3.ZERO
		player.intent = Vector3.ZERO
		player.sprint = false
		player.energy = 1
		player.kick_cooldown = 0
		player.touch_cooldown = 0
		player.aim = Vector3.RIGHT
		player.body_visual.rotation = Vector3(0, -PI / 2, 0)
		player.body_visual.position.y = -0.06
		player.reset_physics_interpolation()
	game.ball.freeze = false
	game.ball.global_position = actor.global_position + Vector3(0.55, 0.11, 0)
	game.ball.linear_velocity = Vector3.ZERO
	game.ball.angular_velocity = Vector3.ZERO
	game.ball.control_block_remaining = 0
	game.ball.last_touch_id = actor.player_id
	game.ball.last_touch_team = actor.team
	elapsed = 0
	max_gap = 0
	captured = false
	cushioned = false
	stop_frame = 0
	contacts = actor.completed_dribble_contacts
	kicks = actor.completed_kicks
	var label: String = CASES[stage]
	if label in ["turn", "stop", "sprint"]:
		actor.intent = Vector3.RIGHT * 0.6
		actor.sprint = label == "sprint"
	elif label in ["settle", "redirect"]:
		actor.incoming_pass_remaining = 2
		actor.incoming_pass_from = "fixture_passer"
		game.ball.last_touch_id = "fixture_passer"
		game.ball.global_position.x += 0.4
		game.ball.linear_velocity = Vector3.LEFT * 4
		actor.intent = Vector3.RIGHT * 0.3 if label == "redirect" else Vector3.ZERO
	elif label == "first_time":
		game.ball.global_position.x += 0.3
		game.ball.linear_velocity = Vector3.LEFT * 2
		actor.buffer_kick("pass", Vector3.RIGHT, 7.5, 0.12)
	else:
		game.ball.global_position += actor.body_visual.basis.x * (-0.22 if label == "left_kick" else 0.22)
		actor.kick(game.ball, Vector3.RIGHT, 12, 0.15, "pass")
		if label != "kick_miss":
			checks[actor.player_id + "_" + label + "_selects_foot"] = actor.kick_right == (label == "right_kick")
		else:
			game.ball.global_position += Vector3.FORWARD * 3
	game.camera.size = 5
	game.camera.global_position = actor.global_position + Vector3(-1.3, 3.2, 4.6)
	game.camera.look_at(actor.global_position + Vector3(0.3, 0.8, 0))

func _physics_process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	var label: String = CASES[stage]
	if label == "turn" and elapsed > 0.5:
		actor.intent = Vector3.FORWARD * 0.6
	elif label == "stop" and elapsed > 0.5:
		actor.intent = Vector3.ZERO
	actor.try_buffered_kick(game.ball)
	game._control_ball()
	var offset: Vector3 = game.ball.global_position - actor.global_position
	offset.y = 0
	max_gap = maxf(max_gap, offset.length())
	if label == "stop":
		var boot: Node3D = actor.visual_controller.right_boot if actor.dribble_right else actor.visual_controller.left_boot
		stop_trace.append({"actor": actor.player_id, "time": elapsed, "gap": offset.length(), "player_velocity": str(actor.linear_velocity), "ball_velocity": str(game.ball.linear_velocity), "boot": str(boot.global_position), "ball": str(game.ball.global_position), "eligible": actor.can_control(game.ball), "swing_time": actor.dribble_elapsed, "contact_time": actor.dribble_contact_time, "hit": actor.dribble_has_hit, "technique": actor.dribble_technique})
		if elapsed >= 0.55 + stop_frame * 0.3 and stop_frame < 4:
			_capture(actor.player_id + "_stop_phase_" + str(stop_frame))
			stop_frame += 1
	if actor.completed_dribble_contacts > contacts and game.ball.linear_velocity.length() < 3:
		cushioned = true
	if not captured and elapsed > 0.3:
		captured = true
		_capture(actor.player_id + "_" + label)
	if elapsed >= TIMES[stage]:
		var key := actor.player_id + "_" + label
		if label in ["turn", "stop", "sprint"]:
			checks[key + "_control_retained"] = max_gap < 1.2 and actor.completed_dribble_contacts > contacts
		elif label in ["settle", "redirect"]:
			checks[key + "_cushion_contact"] = cushioned
			if label == "redirect":
				checks[key + "_advances"] = actor.global_position.x > -2.6
		else:
			checks[key + "_physical_strike"] = actor.completed_kicks == kicks if label == "kick_miss" else actor.completed_kicks > kicks
		observations.append({"case": key, "max_gap": max_gap, "contacts": actor.completed_dribble_contacts - contacts, "kicks": actor.completed_kicks - kicks})
		_next()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var filename := label + ".png"
	checks["capture_" + label] = get_viewport().get_texture().get_image().save_png(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join(filename)) == OK
	screenshots.append(filename)

func _live() -> void:
	running = false
	for player in game.players:
		player.freeze = false
	game.hud.show()
	game.camera.size = 43
	game.camera.position = Vector3(0, 34, 29)
	game.camera.look_at(Vector3.ZERO)
	game.set_physics_process(true)
	game.set_process(true)
	var driver: Node = load("res://tests/decision_acceptance.gd").new()
	driver.checkpoint = 1
	driver.fixture_checks = checks
	driver.fixture_frames = screenshots
	driver.fixture_observations = observations
	driver.stop_trace = stop_trace
	game.decision_driver = driver
	game.add_child(driver)
	driver.begin(game)
