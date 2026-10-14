extends Node

const CASES:=["walk","jog","sprint","turn_stop","dribble","right_slide","left_slide","miss_slide","impact"]
var game: Node3D
var actor: FootballPlayer
var stage:=-1
var elapsed:=0.0
var captured:=0
var checks: Dictionary={}
var screenshots: Array[String]=[]
var trace: Array[Dictionary]=[]
var trace_remaining:=0.0
var minimum_boot:=10.0
var maximum_roll:=0.0
var minimum_hand:=10.0
var start_contacts:=0
var start_challenges:=0
var recovered:=false
var interrupted:=false
var impact_observed:=false

func begin(node: Node3D) -> void:
	game=node
	game.hud.hide()
	_next()

func _next() -> void:
	stage+=1
	if stage==CASES.size():
		_finish()
		return
	elapsed=0
	captured=0
	minimum_boot=10
	maximum_roll=0
	minimum_hand=10
	recovered=false
	interrupted=false
	impact_observed=false
	actor=game.players[stage%6]
	for i in range(game.players.size()):
		var p: FootballPlayer=game.players[i]
		p.reset_action()
		p.freeze=p!=actor
		p.global_position=Vector3(-3,.02,0) if p==actor else Vector3(12,.02,-8+i*3)
		p.linear_velocity=Vector3.ZERO
		p.angular_velocity=Vector3.ZERO
		p.intent=Vector3.ZERO
		p.aim=Vector3.RIGHT
		p.body_visual.rotation=Vector3(0,-PI/2,0)
		p.body_visual.position=Vector3.ZERO
		p.sprint=false
		p.kick_cooldown=0
		p.tackle_cooldown=0
		p.recovery_remaining=0
	game.goal_flow.active=false
	game.ball.freeze=false
	game.ball.global_position=actor.global_position+Vector3(.58,.11,.14)
	game.ball.linear_velocity=Vector3.ZERO
	game.ball.angular_velocity=Vector3.ZERO
	game.ball.control_block_remaining=0
	game.ball.last_touch_id=actor.player_id
	game.ball.last_touch_team=actor.team
	start_contacts=actor.completed_dribble_contacts
	start_challenges=actor.challenge_contacts
	if CASES[stage].contains("slide") or CASES[stage]=="impact":
		actor.linear_velocity=Vector3.RIGHT*5
		game.ball.global_position=actor.global_position+Vector3(1.0,.11,.12 if CASES[stage]=="left_slide" else -.12)
		if CASES[stage]=="miss_slide":
			game.ball.global_position.z=4
		checks[CASES[stage]+"_started"]=actor.slide(game.ball)
		if CASES[stage]=="right_slide":
			checks["right_leg_selected"]=actor.slide_right
		if CASES[stage]=="left_slide":
			checks["left_leg_selected"]=not actor.slide_right
	game.camera.size=5.5

func _physics_process(delta: float) -> void:
	var observed_stage:=stage
	elapsed+=delta
	var label: String=CASES[stage]
	if label=="walk":
		actor.intent=Vector3.RIGHT*.35
	elif label=="jog":
		actor.intent=Vector3.RIGHT
	elif label=="sprint":
		actor.intent=Vector3.RIGHT
		actor.sprint=true
	elif label=="turn_stop":
		actor.intent=Vector3.RIGHT if elapsed<.7 else Vector3.FORWARD if elapsed<1.3 else Vector3.ZERO
	elif label=="dribble":
		actor.intent=Vector3.RIGHT*.65 if elapsed<1.1 else Vector3(1,0,.5).normalized()*.5
		game._control_ball()
	elif label=="impact" and elapsed>.22 and not interrupted:
		interrupted=true
		actor.receive_slide(Vector3.LEFT*actor.mass*5,actor.global_position+Vector3.UP*.3,6)
	impact_observed=impact_observed or interrupted and actor.ragdoll!=null and actor.action_kind!="slide"
	if actor.ragdoll==null:
		for boot in [actor.visual_controller.left_boot,actor.visual_controller.right_boot]:
			minimum_boot=minf(minimum_boot,boot.global_position.y)
		maximum_roll=maxf(maximum_roll,absf(actor.body_visual.rotation.z))
		if actor.slide_recovery:
			var hand: Vector3 = actor._hand(not actor.slide_right)
			minimum_hand=minf(minimum_hand,hand.y)
		recovered=recovered or elapsed>1.5 and actor.action_kind=="" and not actor.slide_recovery and absf(actor.body_visual.rotation.z)<.1 and actor.body_visual.position.y>-.15
	trace_remaining-=delta
	if trace_remaining<=0:
		trace_remaining=.05
		trace.append({"case":label,"time":elapsed,"root":game._vec(actor.global_position),"hip_offset":game._vec(actor.body_visual.position),"roll":actor.body_visual.rotation.z,"action":actor.action_kind,"recovery":actor.recovery_remaining,"right":actor.slide_right,"ball":game._vec(game.ball.global_position),"ragdoll":actor.ragdoll!=null,"contacts":actor.challenge_contacts,"boots":[game._vec(actor.visual_controller.left_boot.global_position),game._vec(actor.visual_controller.right_boot.global_position)],"hand":game._vec(actor._hand(not actor.slide_right))})
	game.camera.position=actor.global_position+Vector3(3,2.2,4)
	game.camera.look_at(actor.global_position+Vector3.UP*.65)
	var capture_time: float=.18+captured*.3 if label.contains("slide") else .3+captured*.6
	if elapsed>capture_time and captured<5:
		captured+=1
		await _capture("%s_%d" % [label,captured])
		if observed_stage!=stage:
			return
	if elapsed>2.5:
		checks[label+"_feet_above_ground"]=minimum_boot>.015
		if label.contains("slide"):
			checks[label+"_side_roll_visible"]=maximum_roll>.8
			checks[label+"_hand_planted_in_recovery"]=minimum_hand<.18
			checks[label+"_returned_to_standing"]=recovered
			if label=="miss_slide":
				checks["miss_did_not_touch_ball"]=actor.challenge_contacts==start_challenges
			else:
				checks[label+"_physical_ball_contact"]=actor.challenge_contacts>start_challenges
		if label=="dribble":
			checks["dribble_has_physical_foot_contacts"]=actor.completed_dribble_contacts-start_contacts>=3
		if label=="impact":
			checks["impact_interrupted_slide"]=impact_observed
		_next()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var filename:=label+".png"
	checks["capture_"+label]=get_viewport().get_texture().get_image().save_png(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join(filename))==OK
	screenshots.append(filename)

func _finish() -> void:
	set_physics_process(false)
	var directory:=OS.get_environment("BASED_FOOTBALL_EVIDENCE")
	var report:={"pass":not checks.values().has(false),"checks":checks,"screenshots":screenshots,"scope":"One rendered walk/jog/sprint/turn/stop/dribble/two-sided slide/miss/impact sequence across six athletes. Actual hand, boot and hip trace; visual style still requires user evaluation."}
	var file:=FileAccess.open(directory.path_join("scene-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	file=FileAccess.open(directory.path_join("motion-trace.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(trace))
	file.close()
	get_tree().quit(0 if report.pass else 1)
