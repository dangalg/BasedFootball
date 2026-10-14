extends Node

var game: Node3D
var stage:=-1
var elapsed:=0.0
var runner: FootballPlayer
var receiver: FootballPlayer
var checks: Dictionary={}
var screenshots: Array[String]=[]
var trace: Array[Dictionary]=[]
var next_trace:=0.0
var captured: Dictionary={}
var start_touches:=0
var kicked:=false
var backward:=false
var received:=false
var placed:=false
var initial_positions: Dictionary={}
var continuous:=true
var no_carry:=true
var launch_steps:=0

func begin(node: Node3D) -> void:
	game=node
	game.hud.hide()
	game.team_coordinator.rng.seed=14721
	_next()

func _next() -> void:
	stage+=1
	if stage==2:
		_finish()
		return
	elapsed=0
	kicked=false
	backward=false
	received=false
	placed=false
	launch_steps=0
	captured.clear()
	game.reset_positions(stage)
	game._select(0)
	game.goal_flow.begin_initial(game,stage)
	runner=game.goal_flow.runner
	for p in game.players:
		p.freeze=false
		p.ai_rng.seed=1250+game.players.find(p)
		p.tactical_role=""
		initial_positions[p.player_id]=p.global_position
	var side:=1.0 if stage==0 else -1.0
	runner.global_position=Vector3(side*7,.02,1)
	runner.body_visual.rotation.y=PI/2 if side>0 else -PI/2
	game.ball.freeze=false
	game.ball.global_position=Vector3(side*6.4,.11,1)
	initial_positions[runner.player_id]=runner.global_position
	start_touches=runner.completed_dribble_contacts
	game.camera.size=20
	game.camera.position=Vector3(0,12,14)
	game.camera.look_at(Vector3.ZERO)

func _physics_process(delta: float) -> void:
	var observed_stage:=stage
	elapsed+=delta
	if game.goal_flow.active:
		game.goal_flow.tick(delta)
		if game.goal_flow.state=="ready":
			placed=placed or game.ball.global_position.distance_to(Vector3(0,FootballBall.RADIUS,0))<.4
	else:
		if not kicked:
			kicked=true
			receiver=game.goal_flow.kickoff_receiver
		# apply_impulse is queued during the strike callback. Read the first
		# integrated launch, before later bounces or receiving foot contacts.
		launch_steps+=1
		if launch_steps==2:
			backward=game.ball.linear_velocity.x*(1 if stage==0 else -1)<-1
		game.team_coordinator.update(game.players,game.ball,game.controlled,delta)
		for p in game.players:
			if p!=game.controlled:
				FootballAI.decide(p,game.players,game.ball,delta)
		game._control_ball()
		if receiver!=null and game.ball.last_touch_id==receiver.player_id:
			received=true
	for p in game.players:
		continuous=continuous and p.global_position.distance_to(initial_positions[p.player_id])<.4
		initial_positions[p.player_id]=p.global_position
		no_carry=no_carry and p.emotion not in ["carry","place"]
	next_trace-=delta
	if next_trace<=0:
		next_trace=.1
		trace.append({"team":stage,"time":elapsed,"state":game.goal_flow.state,"ball":game._vec(game.ball.global_position),"velocity":game._vec(game.ball.linear_velocity),"runner":game._vec(runner.global_position),"dribble_contacts":runner.completed_dribble_contacts,"last_touch":game.ball.last_touch_id})
	for label in ["return","stop","kick","receive"]:
		var available: bool = elapsed>1 if label=="return" else placed if label=="stop" else kicked if label=="kick" else received
		if available and not captured.has(label):
			captured[label]=true
			await _capture("team_%d_%s" % [stage,label])
			if stage!=observed_stage:
				return
	if received or elapsed>22:
		checks["team_%d_foot_retrieval" % stage]=runner.completed_dribble_contacts-start_touches>=4
		checks["team_%d_ball_stopped_at_centre" % stage]=placed
		checks["team_%d_actual_backward_kick" % stage]=kicked and backward
		checks["team_%d_teammate_received" % stage]=received
		_next()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var filename:=label+".png"
	checks["capture_"+label]=get_viewport().get_texture().get_image().save_png(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join(filename))==OK
	screenshots.append(filename)

func _finish() -> void:
	set_physics_process(false)
	checks["continuous_player_movement"]=continuous
	checks["no_hand_carry"]=no_carry
	var report:={"pass":not checks.values().has(false),"checks":checks,"screenshots":screenshots,"scope":"One two-team physical retrieval, foot-controlled return, stop, backward kickoff and teammate reception sequence. Full coordinator/AI after kickoff, no hardware input."}
	var directory:=OS.get_environment("BASED_FOOTBALL_EVIDENCE")
	var file:=FileAccess.open(directory.path_join("scene-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	file=FileAccess.open(directory.path_join("restart-trace.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(trace))
	file.close()
	get_tree().quit(0 if report.pass else 1)
