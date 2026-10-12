extends Node

# One bounded sequence, no hardware input, isolated career data and no retries.
const CASES := ["models", "blue_run", "orange_sprint", "turn", "dribble", "kick", "slide", "hop", "fall"]
const DURATIONS := [0.8, 1.6, 1.6, 1.6, 1.8, 1.2, 1.5, 1.8, 5.5]
var game: Node3D
var actor: FootballPlayer
var stage := -1
var elapsed := 0.0
var running := false
var screenshots: Array[String] = []
var checks: Dictionary = {}
var capture_index := 0
var next_capture := 0.15
var fall_seen := false
var recovery_seen := false
var max_lift := 0.0
var planted_samples := 0
var finite := true
var kick_start := 0
var touch_start := 0

func begin(match_node: Node3D) -> void:
	game = match_node
	game.hud.hide()
	for player in game.players:
		player.physical_event.connect(_event)
	_capture("match_camera")
	await RenderingServer.frame_post_draw
	_next()
	running = true

func _event(kind: String, _detail: Dictionary) -> void:
	fall_seen = fall_seen or kind == "fall"
	recovery_seen = recovery_seen or kind == "get_up"

func _next() -> void:
	stage += 1
	if stage >= CASES.size():
		_finish()
		return
	elapsed = 0
	capture_index = 0
	next_capture = 0.15
	max_lift = 0
	planted_samples = 0
	actor = game.players[3] if CASES[stage] == "orange_sprint" else game.players[0]
	for i in range(game.players.size()):
		var player: FootballPlayer = game.players[i]
		player.reset_action()
		player.freeze = player != actor
		player.global_position = Vector3(-3, 0.02, 0) if player == actor else Vector3(9, 0.02, -9 + i * 3)
		player.linear_velocity = Vector3.ZERO
		player.angular_velocity = Vector3.ZERO
		player.intent = Vector3.ZERO
		player.sprint = false
		player.energy = 1
		player.touch_cooldown = 0
		player.kick_cooldown = 0
		player.hop_cooldown = 0
		player.body_visual.position.y = 0
		player.aim = Vector3.RIGHT
		player.body_visual.rotation = Vector3(0, -PI / 2, 0)
		player.reset_physics_interpolation()
	game.ball.freeze = true
	game.ball.global_position = actor.global_position + Vector3(0.56, 0.10, 0)
	game.ball.linear_velocity = Vector3.ZERO
	game.ball.angular_velocity = Vector3.ZERO
	game.camera.size = 5.8
	game.camera.global_position = actor.global_position + Vector3(-1.2, 3.2, 4.2)
	game.camera.look_at(actor.global_position + Vector3(0, 0.95, 0))
	kick_start = actor.completed_kicks
	touch_start = actor.completed_dribble_contacts
	match CASES[stage]:
		"models":
			game.players[3].global_position = actor.global_position + Vector3(1.3, 0, 0)
			game.players[3].aim = Vector3.LEFT
			game.players[3].body_visual.rotation.y = PI / 2
		"blue_run", "turn": actor.intent = Vector3.RIGHT
		"orange_sprint":
			actor.intent = Vector3.RIGHT
			actor.sprint = true
		"dribble":
			game.ball.freeze = false
			actor.intent = Vector3.RIGHT * 0.6
		"kick":
			game.ball.freeze = false
			checks["kick_requested"] = actor.kick(game.ball, Vector3.RIGHT, 13, 1, "shot")
		"slide": checks["slide_requested"] = actor.slide(game.ball)
		"hop": checks["hop_requested"] = actor.hop()
		"fall": actor.receive_slide(Vector3(220, 0, 0), actor.global_position + Vector3(0, 0.1, 0), 10)

func _physics_process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	if CASES[stage] == "turn" and elapsed > 0.7:
		actor.intent = Vector3.FORWARD
	if CASES[stage] == "dribble":
		game._control_ball()
	for player in game.players:
		finite = finite and player.global_position.is_finite() and player.visual_controller.right_boot.global_position.is_finite()
	var left: Vector3 = actor.visual_controller.left_boot.global_position
	var right: Vector3 = actor.visual_controller.right_boot.global_position
	max_lift = maxf(max_lift, maxf(left.y, right.y))
	if minf(left.y, right.y) < 0.13 and minf(left.y, right.y) > -0.03:
		planted_samples += 1
	game.camera.global_position = actor.global_position + Vector3(-1.2, 3.2, 4.2)
	game.camera.look_at(actor.global_position + Vector3(0, 0.95, 0))
	if elapsed >= next_capture and capture_index < 4:
		next_capture += DURATIONS[stage] / 4
		capture_index += 1
		_capture(CASES[stage] + "_" + str(capture_index))
	if elapsed >= DURATIONS[stage]:
		match CASES[stage]:
			"blue_run", "orange_sprint":
				checks[CASES[stage] + "_planted_steps"] = planted_samples > 10
				checks[CASES[stage] + "_swing_clearance"] = max_lift > 0.15
			"dribble": checks["visible_boot_dribble_contact"] = actor.completed_dribble_contacts > touch_start
			"kick": checks["visible_boot_kick_contact"] = actor.completed_kicks > kick_start
			"hop": checks["hop_landed"] = not actor.hop_active
			"fall":
				checks["physical_fall"] = fall_seen
				checks["recovered_model"] = recovery_seen and actor.body_visual.visible and actor.ragdoll == null
		_next()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var filename := label + ".png"
	var result := get_viewport().get_texture().get_image().save_png(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join(filename))
	checks["capture_" + label] = result == OK
	screenshots.append(filename)

func _finish() -> void:
	running = false
	checks["finite_transforms"] = finite
	var passed := not checks.values().has(false)
	var report := {"pass": passed, "checks": checks, "screenshots": screenshots, "scope": "One athlete model and animation sequence; artistic quality requires inspection of saved frames. No hardware controller or full-match regression."}
	var file := FileAccess.open(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join("scene-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	get_tree().quit(0 if passed else 1)
