extends Node

var game: Node3D
var checks: Dictionary = {}
var screenshots: Array[String] = []
var stepping := false
var mark_before_arrival := false
var largest_mark_step := 0
var previous_marks := 0

func begin(node: Node3D) -> void:
	game = node
	game.hud.hide()
	_run()

func _physics_process(delta: float) -> void:
	if not stepping:
		return
	game.referee.tick(delta)
	if game.goal_flow.active:
		game.goal_flow.tick(delta)
	var count: int = game.referee.boundary.get_child_count()
	if count > 0 and game.referee.mark_state == "walking":
		mark_before_arrival = true
	largest_mark_step = maxi(largest_mark_step,count-previous_marks)
	previous_marks = count

func _run() -> void:
	game.camera.size = 43
	game.camera.position = Vector3(0,34,29)
	game.camera.look_at(Vector3.ZERO)
	for player in game.players:
		player.freeze = false
	game.ball.freeze = false
	game.players[0].global_position = Vector3(-8,.02,7)
	game.goal_flow.begin_free_kick(game,0,Vector3.ZERO)
	checks["mark_does_not_appear_instantly"] = game.referee.boundary.get_child_count() == 0
	checks["attacker_can_stand_anywhere"] = game.goal_flow.position_reason(game.players[0]) == ""
	stepping = true
	await _capture("before_mark")
	var elapsed := 0.0
	var drawing_capture := false
	while game.goal_flow.active and elapsed < 25:
		await get_tree().create_timer(.2).timeout
		elapsed += .2
		if game.referee.mark_state == "drawing" and not drawing_capture:
			drawing_capture = true
			await _capture("drawing_distance")
	checks["referee_walks_before_drawing"] = not mark_before_arrival and game.action_log.any(func(e): return e.kind == "referee_draw_start")
	checks["line_drawn_progressively"] = largest_mark_step <= 1 and game.referee.boundary.get_child_count() > 10
	checks["referee_steps_away"] = game.referee.mark_state == "" and game.action_log.any(func(e): return e.kind == "referee_draw_complete")
	checks["retrieval_and_restart_complete"] = not game.goal_flow.active
	checks["restart_requires_actual_kick"] = game.action_log.any(func(e): return e.kind == "free_kick_ready") and game.goal_flow.runner.completed_kicks > 0
	checks["ball_released_physically"] = game.ball.linear_velocity.length() > 1
	checks["no_cards_for_legal_attacker"] = not game.referee.yellow.has(game.players[0].player_id)
	checks["distance_mark_is_9_15_m"] = true
	for segment in game.referee.boundary.get_children():
		checks["distance_mark_is_9_15_m"] = checks["distance_mark_is_9_15_m"] and absf(Vector2(segment.global_position.x,segment.global_position.z).length()-9.15)<.03
	checks["line_has_no_collision"] = game.referee.boundary.find_children("*","CollisionShape3D",true,false).is_empty()
	await _capture("wall_and_distance")
	stepping = false
	game.goal_flow.begin_initial(game,0)
	for player in game.players:
		player.freeze = true
		player.global_position = Vector3(-6,.02,6) if player.team == 0 else Vector3(12,.02,game.players.find(player)%3*2-2)
	game.goal_flow.runner.global_position = Vector3(-.8,.02,0)
	checks["kickoff_arbitrary_legal_locations"] = game.goal_flow._players_ready()
	game.players[0].global_position = Vector3(1,.02,8)
	checks["kickoff_wrong_half_detected"] = game.goal_flow.position_reason(game.players[0]) == "return to your half"
	game.players[0].global_position = Vector3(-8,.02,8)
	game.players[3].global_position = Vector3(4,.02,0)
	checks["kickoff_distance_detected"] = game.goal_flow.position_reason(game.players[3]) == "respect the 9.15 m distance"
	checks["goal_line_exception"] = FootballRules.illegal_position(Vector3(18,.02,0),1,0,false,"free kick",Vector3(16,0,0)) == ""
	checks["careless_is_not_automatic_card"] = FootballRules.contact_grade("push_contact",{"speed":8}) == "careless"
	checks["dangerous_studs_grade"] = FootballRules.contact_grade("slide_body_contact",{"speed":6,"studs_up":true}) == "excessive"
	for seen in [false,true]:
		game.goal_flow.active = false
		for i in range(6):
			var player: FootballPlayer = game.players[i]
			player.reset_action()
			player.global_position = Vector3(12,.02,-8+i*2)
			player.linear_velocity = Vector3.ZERO
			player.intent = Vector3.ZERO
			player.aim = Vector3.RIGHT
			player.body_visual.rotation.y = -PI/2
			player.freeze = i not in [0,3]
		game.players[0].global_position = Vector3(-1,.02,0)
		game.players[3].global_position = Vector3(-.15,.02,0)
		game.ball.freeze = true
		game.ball.global_position = Vector3(7,.11,0)
		game.referee.actor.freeze = true
		game.referee.actor.global_position = Vector3(-.5,.02,3.3)
		game.referee.actor.aim = Vector3.FORWARD if seen else Vector3.BACK
		game.referee.actor.body_visual.rotation.y = 0 if seen else PI
		await get_tree().physics_frame
		await get_tree().physics_frame
		game.referee.clock += 2
		game.players[0].push(game.ball)
		await get_tree().create_timer(.6).timeout
		checks["seen_push_warned" if seen else "unseen_push_unpunished"] = game.referee.warnings.has(game.players[0].player_id) if seen else not game.referee.warnings.has(game.players[0].player_id)
	await _capture("witnessed_contact")
	var passed := not checks.values().has(false)
	var report := {"pass":passed,"checks":checks,"screenshots":screenshots,"restart_seconds":elapsed,"scope":"One live restart/marking and witnessed/unseen push sequence, plus rule boundary checks. Full match and hardware controller unverified."}
	var file := FileAccess.open(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join("scene-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	get_tree().quit(0 if passed else 1)

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var filename := label+".png"
	checks["capture_"+label] = get_viewport().get_texture().get_image().save_png(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join(filename)) == OK
	screenshots.append(filename)
