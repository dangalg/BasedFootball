extends Node

var game: Node3D
var stage := -1
var elapsed := 0.0
var checks: Dictionary = {}
var screenshots: Array[String] = []
var physical_touch_start := 0
var finite := true
var observed_defence_shape := false

func begin(node: Node3D) -> void:
	game=node
	game.hud.hide()
	game.camera.size=43
	game.camera.position=Vector3(0,34,29)
	game.camera.look_at(Vector3.ZERO)
	game.team_coordinator.rng.seed=48013
	_next()

func _next() -> void:
	stage+=1
	elapsed=0
	if stage>=4:
		_finish()
		return
	game.goal_flow.active=false
	game.team_coordinator.remaining=0
	for i in range(6):
		var p: FootballPlayer=game.players[i]
		p.reset_action()
		p.freeze=false
		p.sent_off=false
		p.show()
		p.global_position=Vector3(-5 if p.team==0 else 6,.02,(i%3-1)*4)
		p.linear_velocity=Vector3.ZERO
		p.intent=Vector3.ZERO
		p.aim=Vector3.RIGHT if p.team==0 else Vector3.LEFT
		p.incoming_pass_remaining=0
		p.kick_cooldown=0
		p.tactical_role=""
		p.ai_rng.seed=8000+i
	game._select(0)
	game.ball.freeze=false
	game.ball.linear_velocity=Vector3.ZERO
	game.ball.angular_velocity=Vector3.ZERO
	if stage==0:
		game.players[0].global_position=Vector3(-5,.02,0)
		game.players[1].global_position=Vector3(-8,.02,-1)
		game.players[2].global_position=Vector3(-8,.02,1)
		game.ball.global_position=Vector3(-4.45,.11,0)
		game.ball.last_touch_team=0
		game.ball.last_touch_id=game.players[0].player_id
	elif stage==1:
		game.players[3].global_position=Vector3(3,.02,0)
		game.ball.global_position=Vector3(2.45,.11,0)
		game.ball.last_touch_team=1
		game.ball.last_touch_id=game.players[3].player_id
	elif stage==2:
		game.players[1].global_position=Vector3(15,.02,9)
		game.ball.global_position=Vector3(17.85,.11,11.85)
		game.ball.last_touch_team=-1
		game.ball.last_touch_id=""
	else:
		game.reset_positions(1)
	physical_touch_start=game.ball.touches

func _physics_process(delta: float) -> void:
	if stage<0 or stage>=4:
		return
	elapsed+=delta
	game.team_coordinator.update(game.players,game.ball,game.controlled,delta)
	if stage==1:
		var roles: Array[String]=[]
		for p in game.players:
			if p.team==0:
				roles.append(p.tactical_role)
		observed_defence_shape=observed_defence_shape or roles.count("press")==1 and roles.has("cover") and roles.has("mark")
	if game.goal_flow.active:
		game.referee.tick(delta)
		game.goal_flow.tick(delta)
	else:
		for p in game.players:
			if p!=game.controlled or stage==3:
				FootballAI.decide(p,game.players,game.ball,delta)
		game._control_ball()
		if stage==3:
			game._check_goal()
	for p in game.players:
		finite=finite and p.global_position.is_finite()
	if elapsed>2 and not checks.has("stage_"+str(stage)):
		checks["stage_"+str(stage)]=true
		if stage==0:
			checks["attacking_options_spread_physically"]=game.players[1].global_position.distance_to(game.players[2].global_position)>3
			checks["support_targets_have_distinct_lanes"]=game.players[1].tactical_target.distance_to(game.players[2].tactical_target)>5
		if stage==1:
			checks["defence_has_one_press_cover_and_mark"]=observed_defence_shape
		await _capture("team_phase_"+str(stage))
	if elapsed>(20 if stage==3 else 7):
		if stage==2:
			checks["board_ball_contested_physically"]=game.ball.touches>physical_touch_start
		if stage==3:
			checks["live_match_produces_physical_touches"]=game.ball.touches-physical_touch_start>8
			checks["live_match_attempts_deliveries"]=game.action_log.any(func(e): return e.kind in ["pass","shot","finesse","power","lob"])
		_next()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var name:=label+".png"
	checks["capture_"+label]=get_viewport().get_texture().get_image().save_png(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join(name))==OK
	screenshots.append(name)

func _finish() -> void:
	set_physics_process(false)
	checks["finite_physical_positions"]=finite
	var passed:=not checks.values().has(false)
	var report:={"pass":passed,"checks":checks,"screenshots":screenshots,"scope":"One attack/defence/board physical sequence and twenty seconds of autonomous match decisions. No hardware input or win-balance claim."}
	var file:=FileAccess.open(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join("scene-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	get_tree().quit(0 if passed else 1)
