extends Node

# One process: bounded physical shots, tactical fixtures, then normal live AI.
const CASES := ["finesse", "outside", "power", "chip", "lob", "high_lob", "side_pass", "back_pass", "side_lob", "side_shot", "support", "defend", "live"]
const TIMES := [1.2, 1.2, 1.1, 1.8, 2.0, 2.0, 1.1, 1.1, 2.0, 1.1, 0.8, 0.8, 30.0]
var game: Node3D
var actor: FootballPlayer
var stage := -1
var elapsed := 0.0
var running := false
var checks: Dictionary = {}
var screenshots: Array[String] = []
var measurements: Dictionary = {}
var origin := Vector3.ZERO
var kicks_start := 0
var captured := false
var second_capture := false
var bend_saved := false
var head_clearance := -INF
var kick_seen := false
var measured := false
var after_contact := -1.0
var movement := Vector2.ZERO
var sprinting := false
var actions: Dictionary = {}
var roles: Dictionary = {}
var finite := true
var max_speed := 0.0
var live_frame := 4.0

func begin(match_node: Node3D) -> void:
	game = match_node
	actor = game.players[0]
	game.hud.hide()
	var hop := false
	for event in InputMap.action_get_events("hop"):
		if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_RIGHT_STICK:
			hop = true
	checks["R3_hop_mapping"] = hop
	for i in range(game.players.size()):
		game.players[i].ai_rng.seed = 81011 + i
	_next()
	running = true

func _next() -> void:
	stage += 1
	if stage >= CASES.size():
		_finish()
		return
	elapsed = 0
	captured = false
	second_capture = false
	bend_saved = false
	head_clearance = -INF
	kick_seen = false
	measured = false
	after_contact = -1
	for i in range(game.players.size()):
		var player: FootballPlayer = game.players[i]
		player.reset_action()
		player.freeze = player != actor
		player.global_position = Vector3(-3, 0.02, 0) if player == actor else Vector3(12, 0.02, -9 + i * 3)
		player.linear_velocity = Vector3.ZERO
		player.angular_velocity = Vector3.ZERO
		player.intent = Vector3.ZERO
		player.jockey = false
		player.sprint = false
		player.energy = 1
		player.kick_cooldown = 0
		player.touch_cooldown = 0
		player.reaction_timer = 0
		player.aim = Vector3.RIGHT
		player.body_visual.rotation = Vector3(0, -PI / 2, 0)
		player.body_visual.position.y = 0
		player.reset_physics_interpolation()
	game.ball.freeze = false
	game.ball.global_position = actor.global_position + Vector3(0.61, 0.11, 0)
	game.ball.linear_velocity = Vector3.ZERO
	game.ball.angular_velocity = Vector3.ZERO
	game.ball.control_block_remaining = 0
	game.ball.last_touch_team = 0
	game.ball.last_touch_id = actor.player_id
	origin = game.ball.global_position
	kicks_start = actor.completed_kicks
	game._select(0)
	game.camera.size = 7
	game.camera.global_position = actor.global_position + Vector3(-1.2, 4.0, 5.2)
	game.camera.look_at(actor.global_position + Vector3(1, 0.8, 0))
	var label: String = CASES[stage]
	if label in ["finesse", "outside", "power", "chip"]:
		game._controller_actions(0, {"primary": true})
		game.charge = 1
		game._controller_actions(0, {"primary_release": true, "r1": label in ["finesse", "power"], "l1": label in ["chip", "power"], "l2": label == "outside"})
		checks[label + "_control_selects_kind"] = actor.kick_kind == label
	elif label in ["lob", "high_lob", "side_lob"]:
		if label == "side_lob":
			actor.intent = Vector3.FORWARD
		game._controller_actions(0, {"square": true, "l1": label == "high_lob"})
		game.players[3].global_position = origin + (Vector3.FORWARD if label == "side_lob" else Vector3.RIGHT) * 7
	elif label in ["side_pass", "back_pass", "side_shot"]:
		actor.intent = Vector3.FORWARD if label != "back_pass" else Vector3.LEFT
		if label == "side_shot":
			game._controller_actions(0, {"primary": true})
			game.charge = 0.5
			game._controller_actions(0, {"primary_release": true})
		else:
			game._controller_actions(0, {"pass": true})
	elif label in ["support", "defend"]:
		game.ball.freeze = true
		game.players[1].global_position = Vector3(-5, 0.02, -4)
		game.players[2].global_position = Vector3(-7, 0.02, 4)
		game.players[3].global_position = Vector3(-2, 0.02, 0)
		if label == "support":
			game.players[3].global_position = Vector3(6, 0.02, 0)
		else:
			game.ball.global_position = game.players[3].global_position + Vector3(0.6, 0.11, 0)
			game.ball.last_touch_team = 1
		for player in game.players:
			FootballAI.decide(player, game.players, game.ball, 0.3)
	elif label == "live":
		game.hud.show()
		game.camera.size = 43
		game.camera.global_position = Vector3(0, 34, 29)
		game.camera.look_at(Vector3.ZERO)
		for player in game.players:
			player.freeze = false
		game.reset_positions(1)
		game.kickoff_remaining = 0
		game.decision_driver = self
		game.set_physics_process(true)
		game.set_process(true)
		game.set_process_unhandled_input(false)
		game.action_log.clear()

func decide(_delta: float) -> void:
	# Local driver uses current state through the same AI and physical actions.
	FootballAI.decide(game.controlled, game.players, game.ball, _delta)
	movement = Vector2(game.controlled.intent.x, game.controlled.intent.z)
	sprinting = game.controlled.sprint
	actions = {}

func _physics_process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	var label: String = CASES[stage]
	finite = finite and game.ball.global_position.is_finite() and game.ball.linear_velocity.is_finite()
	for player in game.players:
		finite = finite and player.global_position.is_finite()
		max_speed = maxf(max_speed, player.linear_velocity.length())
		if label == "live" and player.team_role != "":
			roles[str(player.team) + "_" + player.team_role] = true
	if label == "live":
		if elapsed >= live_frame:
			live_frame += 4
			_capture("live_" + str(int(elapsed)))
	else:
		if actor.completed_kicks > kicks_start and not kick_seen:
			kick_seen = true
			after_contact = elapsed + delta
			_capture(label + "_contact")
		if after_contact > 0 and elapsed >= after_contact and not measured:
			measured = true
			measurements[label] = {"velocity": [game.ball.linear_velocity.x, game.ball.linear_velocity.y, game.ball.linear_velocity.z], "spin_y": game.ball.angular_velocity.y}
		if label in ["finesse", "outside"] and not bend_saved and game.ball.global_position.x > origin.x + 6:
			bend_saved = true
			measurements[label]["bend"] = game.ball.global_position.z - origin.z
		if label in ["lob", "high_lob", "side_lob"]:
			var axis: Vector3 = Vector3.FORWARD if label == "side_lob" else Vector3.RIGHT
			var along: float = (game.ball.global_position - origin).dot(axis)
			if absf(along - 7) < 0.35:
				head_clearance = maxf(head_clearance, game.ball.global_position.y - FootballBall.RADIUS - 1.8)
		if not captured and elapsed > 0.28:
			captured = true
			_capture(label + "_action")
		if not second_capture and elapsed > 0.8:
			second_capture = true
			_capture(label + "_flight")
	if elapsed >= TIMES[stage]:
		if label not in ["support", "defend", "live"]:
			checks[label + "_physical_contact"] = kick_seen
		if label in ["lob", "high_lob", "side_lob"]:
			checks[label + "_clears_head"] = head_clearance > 0.15
			measurements[label]["head_clearance"] = head_clearance
		if label in ["side_pass", "side_shot", "side_lob"]:
			checks[label + "_requested_direction"] = measurements.has(label) and measurements[label].velocity[2] < -2
		elif label == "back_pass":
			checks["back_pass_requested_direction"] = measurements.has(label) and measurements[label].velocity[0] < -2
		elif label == "support":
			checks["teammates_open_separate_lanes"] = game.players[1].team_role == "support" and game.players[2].team_role == "support" and game.players[1].team_target.distance_to(game.players[2].team_target) > 4
		elif label == "defend":
			checks["defenders_press_mark_and_cover"] = game.players[0].team_role == "press" and game.players[1].team_role == "mark" and game.players[2].team_role == "cover"
		_next()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var filename := label + ".png"
	checks["capture_" + label] = get_viewport().get_texture().get_image().save_png(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join(filename)) == OK
	screenshots.append(filename)

func _finish() -> void:
	running = false
	game.set_physics_process(false)
	checks["opposite_physical_curls"] = measurements.get("finesse", {}).get("bend", 0) < -0.02 and measurements.get("outside", {}).get("bend", 0) > 0.02
	checks["power_shot_faster_than_finesse"] = measurements.has("power") and measurements.has("finesse") and measurements.power.velocity[0] > measurements.finesse.velocity[0] + 3
	checks["live_both_teams_support_and_defend"] = roles.has("0_support") and roles.has("1_support") and roles.has("0_press") and roles.has("1_press")
	var passes := 0
	var shot_attempts := 0
	for event in game.action_log:
		if event.kind in ["pass", "lob"]:
			passes += 1
		if event.kind in ["shot", "power", "finesse", "outside", "chip"]:
			shot_attempts += 1
	checks["live_team_passes_and_shots"] = passes > 0 and shot_attempts > 0
	checks["finite_physics"] = finite and max_speed < 20
	var report := {"pass": not checks.values().has(false), "checks": checks, "screenshots": screenshots, "measurements": measurements, "roles": roles.keys(), "completed_passes": passes, "completed_shots": shot_attempts, "scores": game.scores, "events": game.action_log, "scope": "One finite kick/tactics sequence and 30 seconds of normal physical AI play. No hardware input or subjective feel claim."}
	var file := FileAccess.open(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join("scene-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	get_tree().quit(0 if report.pass else 1)
