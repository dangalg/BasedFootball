extends Node

const CASES := ["tap_pass", "strong_pass", "through", "short_lob", "long_lob", "lob", "high_lob", "shot", "power", "finesse", "outside", "chip", "side_pass", "back_pass", "miss"]
var game: Node3D
var actor: FootballPlayer
var stage := -1
var elapsed := 0.0
var running := false
var checks: Dictionary = {}
var screenshots: Array[String] = []
var measurements: Dictionary = {}
var origin := Vector3.ZERO
var kicks := 0
var contact_seen := false
var measured := false
var bend_saved := false
var clearance := -INF
var apex := 0.0
var distance_at_one := 0.0
var captures := 0

func begin(match_node: Node3D) -> void:
	game = match_node
	actor = game.players[0]
	game.hud.hide()
	checks["distinct_contact_sound_profiles"] = game.sound.contact_streams.size() >= 9
	_next()
	running = true

func _next() -> void:
	stage += 1
	if stage >= CASES.size():
		_live()
		return
	for i in range(game.players.size()):
		var player: FootballPlayer = game.players[i]
		player.reset_action()
		player.freeze = player != actor
		player.global_position = Vector3(-3, 0.02, 0) if player == actor else Vector3(12, 0.02, -10 + i * 2)
		player.linear_velocity = Vector3.ZERO
		player.intent = Vector3.ZERO
		player.aim = Vector3.RIGHT
		player.sprint = false
		player.energy = 1
		player.kick_cooldown = 0
		player.touch_cooldown = 0
		player.body_visual.rotation = Vector3(0, -PI / 2, 0)
		player.body_visual.position.y = -0.06
	game._select(0)
	game.ball.freeze = false
	game.ball.global_position = actor.global_position + Vector3(0.55, 0.11, 0.14)
	game.ball.linear_velocity = Vector3.ZERO
	game.ball.angular_velocity = Vector3.ZERO
	game.ball.last_touch_team = 0
	game.ball.last_touch_id = actor.player_id
	game.ball.control_block_remaining = 0
	elapsed = 0
	captures = 0
	contact_seen = false
	measured = false
	bend_saved = false
	clearance = -INF
	apex = 0
	distance_at_one = 0
	origin = game.ball.global_position
	kicks = actor.completed_kicks
	var label: String = CASES[stage]
	if label in ["shot", "power", "finesse", "outside", "chip"]:
		game._controller_actions(0, {"primary": true})
		game.charge = 1
		game._controller_actions(0, {"primary_release": true, "l1": label in ["power", "chip"], "r1": label in ["power", "finesse"], "l2": label == "outside"})
		checks[label + "_modifier_selects_profile"] = actor.kick_kind == label
	else:
		var button := "square" if "lob" in label else "through" if label == "through" else "pass"
		if label in ["side_pass", "back_pass"]:
			actor.intent = Vector3.FORWARD if label == "side_pass" else Vector3.LEFT
		game._controller_actions(0, {button: true, "l1": label == "high_lob"})
		checks[label + "_waits_for_release"] = actor.action_kind == ""
		game.delivery_charge = 0.02 if label in ["tap_pass", "short_lob"] else 1 if label in ["strong_pass", "long_lob"] else 0.6
		game._controller_actions(0, {button + "_release": true})
		if label == "miss":
			game.ball.global_position += Vector3.FORWARD * 3
	if label in ["lob", "high_lob"]:
		game.players[3].global_position = origin + Vector3.RIGHT * 7
	game.camera.size = 6
	game.camera.global_position = actor.global_position + Vector3(-1.3, 3.2, 4.6)
	game.camera.look_at(actor.global_position + Vector3(0.4, 0.8, 0))

func _physics_process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	var label: String = CASES[stage]
	if actor.completed_kicks > kicks:
		if contact_seen and not measured:
			measurements[label] = {"launch_speed": game.ball.linear_velocity.length(), "horizontal_speed": Vector2(game.ball.linear_velocity.x, game.ball.linear_velocity.z).length(), "vx": game.ball.linear_velocity.x, "vz": game.ball.linear_velocity.z}
			measured = true
		contact_seen = true
	apex = maxf(apex, game.ball.global_position.y)
	var along: float = game.ball.global_position.x - origin.x
	if not bend_saved and label in ["finesse", "outside"] and along >= 6:
		bend_saved = true
		measurements[label]["bend_at_6m"] = game.ball.global_position.z - origin.z
	if label in ["lob", "high_lob"] and absf(along - 7) < 0.4:
		clearance = maxf(clearance, game.ball.global_position.y - FootballBall.RADIUS - 1.8)
	if elapsed >= 1 and distance_at_one == 0:
		distance_at_one = Vector2(game.ball.global_position.x - origin.x, game.ball.global_position.z - origin.z).length()
	if captures == 0 and elapsed >= 0.2:
		_capture(label + "_contact")
		captures = 1
	elif captures == 1 and elapsed >= 0.55:
		game.camera.size = 28
		game.camera.global_position = Vector3(6, 14, 17)
		game.camera.look_at(Vector3(6, 1, 0))
		captures = 2
	elif captures == 2 and elapsed >= 0.8:
		_capture(label + "_flight")
		captures = 3
	if elapsed >= (2.3 if "lob" in label or label == "chip" else 1.1):
		checks[label + "_physical_contact"] = not contact_seen if label == "miss" else contact_seen
		if measured:
			measurements[label]["apex"] = apex
			measurements[label]["distance_at_one"] = distance_at_one
		if label in ["lob", "high_lob"]:
			checks[label + "_clears_head"] = clearance > 0.15
		if label == "side_pass":
			checks["side_pass_follows_aim"] = measured and measurements[label].vz < -2
		elif label == "back_pass":
			checks["back_pass_follows_aim"] = measured and measurements[label].vx < -2
		_next()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var filename := label + ".png"
	checks["capture_" + label] = get_viewport().get_texture().get_image().save_png(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join(filename)) == OK
	screenshots.append(filename)

func _live() -> void:
	running = false
	checks["hold_strengthens_pass"] = measurements.get("strong_pass", {}).get("horizontal_speed", 0) > measurements.get("tap_pass", {}).get("horizontal_speed", 100) + 5
	checks["hold_extends_lob"] = measurements.get("long_lob", {}).get("distance_at_one", 0) > measurements.get("short_lob", {}).get("distance_at_one", 100) + 4
	checks["power_faster_than_normal"] = measurements.get("power", {}).get("launch_speed", 0) > measurements.get("shot", {}).get("launch_speed", 100) + 3
	checks["opposite_visible_curls"] = measurements.get("finesse", {}).get("bend_at_6m", 0) < -0.08 and measurements.get("outside", {}).get("bend_at_6m", 0) > 0.08
	checks["chip_lower_than_lob"] = measurements.get("chip", {}).get("apex", 100) < measurements.get("lob", {}).get("apex", 0) - 0.5
	for player in game.players:
		player.freeze = false
	game.hud.show()
	game.camera.size = 43
	game.set_physics_process(true)
	game.set_process(true)
	var driver: Node = load("res://tests/decision_acceptance.gd").new()
	driver.checkpoint = 2
	driver.fixture_checks = checks
	driver.fixture_frames = screenshots
	driver.fixture_observations = [measurements]
	game.decision_driver = driver
	game.add_child(driver)
	driver.begin(game)
