extends Node

const CASES := ["short","moving","through","lob","back"]
var game: Node3D
var actor: FootballPlayer
var receiver: FootballPlayer
var stage := -1
var elapsed := 0.0
var checks: Dictionary = {}
var screenshots: Array[String] = []
var starting_kicks := 0
var received := false
var apex := 0.0
var captured := false

func begin(node: Node3D) -> void:
	game=node
	game.hud.hide()
	actor=game.players[0]
	receiver=game.players[1]
	_next()

func _next() -> void:
	stage+=1
	if stage>=CASES.size():
		_finish()
		return
	elapsed=0
	received=false
	apex=0
	captured=false
	for i in range(6):
		var p: FootballPlayer=game.players[i]
		p.reset_action()
		p.freeze=p!=actor and p!=receiver
		p.global_position=Vector3(14,.02,-9+i*3)
		p.linear_velocity=Vector3.ZERO
		p.intent=Vector3.ZERO
		p.aim=Vector3.RIGHT
		p.kick_cooldown=0
		p.incoming_pass_remaining=0
	actor.global_position=Vector3(-4,.02,0)
	receiver.global_position=Vector3(1,.02,0)
	var direction:=Vector3.RIGHT
	if CASES[stage]=="back":
		receiver.global_position=Vector3(-9,.02,0)
		direction=Vector3.LEFT
	if CASES[stage]=="moving":
		receiver.linear_velocity=Vector3(0,0,2)
	actor.body_visual.rotation.y=-PI/2
	game._select(0)
	game.ball.freeze=false
	game.ball.global_position=actor.global_position+Vector3(.55,.11,.14)
	game.ball.linear_velocity=Vector3.ZERO
	game.ball.angular_velocity=Vector3.ZERO
	game.ball.last_touch_team=0
	game.ball.last_touch_id=actor.player_id
	game.ball.control_block_remaining=0
	starting_kicks=actor.completed_kicks
	game._release_delivery(direction,"square" if CASES[stage]=="lob" else "through" if CASES[stage]=="through" else "pass",.4,false)
	checks[CASES[stage]+"_receiver_selected"]=actor.planned_receiver_id==receiver.player_id
	game.camera.size=12
	game.camera.position=Vector3(-2,8,9)
	game.camera.look_at(Vector3(-2,.5,0))

func _physics_process(delta: float) -> void:
	if stage<0 or stage>=CASES.size():
		return
	elapsed+=delta
	FootballAI.decide(receiver,game.players,game.ball,delta)
	game._control_ball()
	received=received or game.ball.last_touch_id==receiver.player_id
	apex=maxf(apex,game.ball.global_position.y)
	if elapsed>.4 and not captured:
		captured=true
		_capture(CASES[stage]+"_flight")
	if elapsed>4.5:
		checks[CASES[stage]+"_physical_kick"]=actor.completed_kicks>starting_kicks
		if CASES[stage] in ["short","moving","back"]:
			checks[CASES[stage]+"_receiver_touched_ball"]=received
		if CASES[stage]=="lob":
			checks["lob_above_player_heads"]=apex>2.0
		_next()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var filename:=label+".png"
	checks["capture_"+label]=get_viewport().get_texture().get_image().save_png(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join(filename))==OK
	screenshots.append(filename)

func _finish() -> void:
	set_physics_process(false)
	var weak:=FootballPassing.delivery(actor,receiver,Vector3.RIGHT,"pass",0)
	var strong:=FootballPassing.delivery(actor,receiver,Vector3.RIGHT,"pass",1)
	checks["power_retains_under_over_hit_range"]=strong.strength>weak.strength*1.5
	var passed:=not checks.values().has(false)
	var report:={"pass":passed,"checks":checks,"screenshots":screenshots,"scope":"One physical short/moving/through/lob/back delivery sequence with receiving AI. Full match and controller hardware unverified."}
	var file:=FileAccess.open(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join("scene-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	get_tree().quit(0 if passed else 1)
