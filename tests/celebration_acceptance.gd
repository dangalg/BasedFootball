extends Node

var game: Node3D
var elapsed := 0.0
var checks: Dictionary = {}
var screenshots: Array[String] = []
var previous: Dictionary = {}
var smooth_return := true
var next_capture := .6

func begin(match_node: Node3D) -> void:
	game = match_node
	game.camera.size = 41
	game.camera.position = Vector3(0,34,29)
	game.camera.look_at(Vector3.ZERO)
	for i in range(6):
		var player: FootballPlayer = game.players[i]
		player.freeze = false
		player.global_position = Vector3(8 + i * 1.5, .06, (i % 3 - 1) * 2.5)
		previous[player.player_id] = player.global_position
	game.ball.global_position = Vector3(18.5, .14, 0)
	game.ball.last_touch_id = game.players[0].player_id
	game.ball.last_touch_team = 0
	game.ball.freeze = false
	game._check_goal()
	checks["goal_recorded_once"] = game.scores[0] == 1
	checks["celebrations_and_sadness"] = game.players[0].emotion == "celebrate" and game.players[3].emotion == "sad"
	checks["goal_did_not_teleport_players"] = game.players[0].global_position.distance_to(previous[game.players[0].player_id]) < .01

func _physics_process(delta: float) -> void:
	if game == null:
		return
	elapsed += delta
	var actor: FootballPlayer = game.controlled
	if elapsed > 6:
		game.goal_flow._walk(actor, game.goal_flow.targets[actor.player_id])
	else:
		actor.intent = Vector3.ZERO
	if game.goal_flow.active:
		game.goal_flow.tick(delta)
	for player in game.players:
		smooth_return = smooth_return and player.global_position.distance_to(previous[player.player_id]) < .4
		previous[player.player_id] = player.global_position
	if elapsed >= next_capture:
		next_capture += 3
		_capture("goal_return_" + str(screenshots.size()))
	if not game.goal_flow.active or elapsed > 32:
		checks["continuous_player_return"] = smooth_return
		checks["natural_kickoff_completed"] = not game.goal_flow.active
		checks["ball_retrieved_visibly"] = game.action_log.any(func(e: Dictionary): return e.kind == "ball_retrieved")
		checks["everyone_walked_to_position"] = game.goal_flow._players_ready()
		checks["ball_at_centre"] = game.ball.global_position.distance_to(Vector3(0, FootballBall.RADIUS, 0)) < .45
		checks["no_duplicate_goal"] = game.scores[0] == 1
		set_physics_process(false)
		await _capture("kickoff_ready")
		var passed := not checks.values().has(false)
		var report := {"pass":passed,"checks":checks,"screenshots":screenshots,"elapsed":elapsed,"scope":"One physical goal, celebration and walk-back sequence. No hardware input."}
		var file := FileAccess.open(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join("scene-report.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
		get_tree().quit(0 if passed else 1)

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var filename := label + ".png"
	checks["capture_" + label] = get_viewport().get_texture().get_image().save_png(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join(filename)) == OK
	screenshots.append(filename)
