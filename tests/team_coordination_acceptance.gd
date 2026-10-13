extends Node

# The selected human receives no movement/actions. Five production AI players.
var game: Node3D
var stage := -1
var elapsed := 0.0
var sample_remaining := 0.0
var checks: Dictionary = {}
var screenshots: Array[String] = []
var samples: Array[Dictionary] = []
var metrics: Array[Dictionary] = []
var metric: Dictionary
var streaks := [0.0,0.0]
var captured := 0
var touch_start := 0
var finite := true
var idle := true

func begin(node: Node3D) -> void:
	game=node
	game.hud.hide()
	game.camera.size=43
	game.camera.position=Vector3(0,34,29)
	game.camera.look_at(Vector3.ZERO)
	game.team_coordinator.rng.seed=48013
	_next()

func _next() -> void:
	if stage>=0:
		metrics.append(metric.duplicate())
	stage+=1
	elapsed=0
	sample_remaining=0
	captured=0
	streaks=[0.0,0.0]
	if stage>=4:
		_finish()
		return
	metric={"phase":stage,"samples":0,"crowded_team_samples":0,"all_ai_crowd_samples":0,"max_crowd_seconds":0.0,"separated_support_samples":0,"support_samples":0,"touches":0}
	game.goal_flow.active=false
	game.team_coordinator.remaining=0
	game.team_coordinator.possession_age=10
	game.team_coordinator.possession_team=-1
	game.team_coordinator.chasers.clear()
	game.team_coordinator.roles.clear()
	for i in range(6):
		var p: FootballPlayer=game.players[i]
		p.reset_action()
		p.freeze=false
		p.sent_off=false
		p.show()
		p.global_position=Vector3(-5 if p.team==0 else 6,.02,(i%3-1)*4)
		p.linear_velocity=Vector3.ZERO
		p.angular_velocity=Vector3.ZERO
		p.intent=Vector3.ZERO
		p.sprint=false
		p.aim=Vector3.RIGHT if p.team==0 else Vector3.LEFT
		p.incoming_pass_remaining=0
		p.kick_cooldown=0
		p.tactical_role=""
		p.reaction_timer=0
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
	touch_start=game.ball.touches

func _physics_process(delta: float) -> void:
	if stage<0 or stage>=4:
		return
	elapsed+=delta
	game.controlled.intent=Vector3.ZERO
	game.controlled.sprint=false
	game.team_coordinator.update(game.players,game.ball,game.controlled,delta)
	if game.goal_flow.active:
		game.referee.tick(delta)
		game.goal_flow.tick(delta)
	else:
		for p in game.players:
			if p!=game.controlled:
				FootballAI.decide(p,game.players,game.ball,delta)
		game._control_ball()
		game._check_goal()
	idle=idle and game.controlled.intent.length_squared()<.001
	for p in game.players:
		finite=finite and p.global_position.is_finite()
	sample_remaining-=delta
	if sample_remaining<=0:
		sample_remaining=.2
		_sample()
	if elapsed>3+captured*3 and captured<3:
		captured+=1
		await _capture("phase_%d_%d" % [stage,captured])
	if elapsed>(24 if stage==3 else 10):
		metric.touches=game.ball.touches-touch_start
		_next()

func _sample() -> void:
	var players: Array[Dictionary]=[]
	var near := [0,0]
	var ai_near := 0
	for p in game.players:
		var gap:=Vector2(p.global_position.x-game.ball.global_position.x,p.global_position.z-game.ball.global_position.z).length()
		if gap<3:
			near[p.team]+=1
			if p!=game.controlled:
				ai_near+=1
		players.append({"id":p.player_id,"team":p.team,"position":[p.global_position.x,p.global_position.y,p.global_position.z],"target":[p.team_target.x,p.team_target.z],"role":p.tactical_role,"chaser":p.tactical_chaser_id,"ball_gap":gap,"human":p==game.controlled})
	samples.append({"phase":stage,"time":elapsed,"dead_ball":game.goal_flow.active,"ball":[game.ball.global_position.x,game.ball.global_position.y,game.ball.global_position.z],"players":players})
	if elapsed<3 or game.goal_flow.active:
		streaks=[0.0,0.0]
		return
	metric.samples+=1
	for team in range(2):
		if near[team]==3:
			metric.crowded_team_samples+=1
			streaks[team]+=.2
			metric.max_crowd_seconds=maxf(metric.max_crowd_seconds,streaks[team])
		else:
			streaks[team]=0
	if ai_near>=4:
		metric.all_ai_crowd_samples+=1
	var supports: Array[FootballPlayer]=[]
	for p in game.players:
		if p.team==0 and p!=game.controlled and p.tactical_role in ["run","support"]:
			supports.append(p)
	if supports.size()==2:
		metric.support_samples+=1
		if supports[0].global_position.distance_to(supports[1].global_position)>4:
			metric.separated_support_samples+=1

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var name:=label+".png"
	checks["capture_"+label]=get_viewport().get_texture().get_image().save_png(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join(name))==OK
	screenshots.append(name)

func _finish() -> void:
	set_physics_process(false)
	checks["human_has_no_movement_decisions"]=idle
	checks["finite_physical_positions"]=finite
	var total:=0
	var crowded:=0
	var all_crowded:=0
	var support:=0
	var separated:=0
	for m in metrics:
		total+=m.samples
		crowded+=m.crowded_team_samples
		all_crowded+=m.all_ai_crowd_samples
		support+=m.support_samples
		separated+=m.separated_support_samples
		checks["phase_%d_no_sustained_team_pileup" % m.phase]=m.max_crowd_seconds<=1.2
	checks["sufficient_live_observation"]=total>=120
	checks["three_teammates_near_ball_under_10_percent"]=float(crowded)/maxi(1,total*2)<.1
	checks["four_ai_near_ball_under_15_percent"]=float(all_crowded)/maxi(1,total)<.15
	checks["attacking_support_physically_separated"]=support>=5 and float(separated)/maxi(1,support)>=.75
	checks["board_ball_contact"]=metrics[2].touches>0
	checks["idle_human_match_has_ball_contacts"]=metrics[3].touches>8
	var report:={"pass":not checks.values().has(false),"checks":checks,"metrics":metrics,"screenshots":screenshots,"scope":"One physical 54-second sequence: idle human possession, opposing possession, board ball, then 24 seconds of five normal AI players with human idle. Positions sampled every 0.2 seconds; first 3 seconds of each phase and dead balls excluded from crowding acceptance. No subjective fun claim."}
	var directory:=OS.get_environment("BASED_FOOTBALL_EVIDENCE")
	var trace:=FileAccess.open(directory.path_join("positions.json"),FileAccess.WRITE)
	trace.store_string(JSON.stringify(samples))
	trace.close()
	var file:=FileAccess.open(directory.path_join("scene-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	get_tree().quit(0 if report.pass else 1)
