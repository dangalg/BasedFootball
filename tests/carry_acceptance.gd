extends Node

var game: Node3D
var elapsed:=0.0
var carry_elapsed:=0.0
var samples:=0
var front:=0
var close:=0
var turned:=false
var captured: Dictionary={}
var screenshots: Array[String]=[]
var checks: Dictionary={}
var trace: Array[Dictionary]=[]
var trace_remaining:=0.0

func begin(node: Node3D) -> void:
	game=node
	game.hud.hide()
	game.reset_positions(1)
	game.goal_flow.begin_initial(game,1)
	for p in game.players:
		p.freeze=false
	game.ball.freeze=false
	var runner: FootballPlayer=game.goal_flow.runner
	runner.global_position=Vector3(-7,.02,4)
	runner.aim=Vector3.RIGHT
	runner.body_visual.rotation.y=-PI/2
	game.ball.global_position=Vector3(-6.4,.11,4)
	game.goal_flow.targets[runner.player_id]=Vector3(-2,.06,5)
	game.camera.size=7

func _physics_process(delta: float) -> void:
	elapsed+=delta
	var runner: FootballPlayer=game.goal_flow.runner
	game.goal_flow.tick(delta)
	if game.goal_flow.carrying and game.goal_flow.state=="returning":
		carry_elapsed+=delta
		if runner.global_position.x>-2.7 and not turned:
			game.goal_flow.targets[runner.player_id]=Vector3(.8,.06,0)
			turned=true
		if carry_elapsed>.7:
			samples+=1
			var relative: Vector3=game.ball.global_position-runner.global_position
			if relative.dot(-runner.body_visual.global_basis.z)>.15:
				front+=1
			if game.ball.global_position.distance_to(runner.visual_controller.carry_anchor())<.3:
				close+=1
	game.camera.position=runner.global_position+Vector3(4,3,5)
	game.camera.look_at(runner.global_position+Vector3.UP*.8)
	trace_remaining-=delta
	if trace_remaining<=0:
		trace_remaining=.1
		trace.append({"time":elapsed,"state":game.goal_flow.state,"ball":game._vec(game.ball.global_position),"hands":game._vec(runner.visual_controller.carry_anchor()),"runner":game._vec(runner.global_position)})
	for label in ["carry","turn","placing"]:
		var available: bool = carry_elapsed>1 if label=="carry" else turned if label=="turn" else game.goal_flow.state=="placing"
		if available and not captured.has(label):
			captured[label]=true
			await _capture(label)
	if game.goal_flow.state=="ready" or elapsed>18:
		set_physics_process(false)
		checks["retrieved_and_placed_physically"]=game.goal_flow.state=="ready"
		checks["turn_exercised"]=turned
		checks["sufficient_carry_samples"]=samples>60
		checks["ball_stays_in_front"]=float(front)/maxi(1,samples)>.9
		checks["ball_tracks_actual_hands"]=float(close)/maxi(1,samples)>.9
		checks["placed_ball_at_centre"]=game.ball.global_position.distance_to(Vector3(0,FootballBall.RADIUS,0))<.3
		await _capture("placed")
		var directory:=OS.get_environment("BASED_FOOTBALL_EVIDENCE")
		var report:={"pass":not checks.values().has(false),"checks":checks,"screenshots":screenshots,"samples":samples,"front_samples":front,"hand_samples":close,"scope":"One rendered physical pickup, moving front carry, direction change and lowering onto centre spot. Ends before kickoff."}
		var file:=FileAccess.open(directory.path_join("scene-report.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
		file=FileAccess.open(directory.path_join("carry-trace.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(trace))
		file.close()
		get_tree().quit(0 if report.pass else 1)

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var name:=label+".png"
	checks["capture_"+label]=get_viewport().get_texture().get_image().save_png(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join(name))==OK
	screenshots.append(name)
