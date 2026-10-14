class_name FootballGoalFlow
extends RefCounted

# Dead-ball preparation uses normal physical actions. A phase owns one durable
# request; a contact or terminal miss changes it, not repeated scheduling calls.
var game: Node3D
var active := false
var state := ""
var elapsed := 0.0
var total_elapsed := 0.0
var receiving_team := 0
var restart_id := 0
var pending_action_id := 0
var pending_player_id := ""
var pending_purpose := ""
var pending_receiver_id := ""
var relay_passer_id := ""
var relay_received := false
var scorer: FootballPlayer
var runner: FootballPlayer
var retriever: FootballPlayer
var carrying := false
var targets: Dictionary = {}
var celebration_target := Vector3.ZERO
var restart_spot := Vector3.ZERO
var restart_kind := "kickoff"
var signalled := false
var ready_elapsed := 0.0
var retrieved := false
var kickoff_receiver: FootballPlayer
var return_receiver: FootballPlayer
var return_pass_pending := false
var return_passes := 0
var net_pull_planted := false
var net_pull_stance := Vector3.ZERO
var stance_phase := "direct"
var stance_side := 1.0

func begin_initial(match_node: Node3D, team: int) -> void:
	_start(match_node,team,"kickoff",Vector3.ZERO)
	_transition("settle" if _near_spot(.65) else "retrieve")

func begin(match_node: Node3D, scoring: int) -> void:
	_start(match_node,1-scoring,"kickoff",Vector3.ZERO)
	for player in game.players:
		if player.sent_off:
			continue
		if player.team==scoring and (scorer==null or player.player_id==game.ball.last_touch_id):
			scorer=player
	if scorer!=null:
		celebration_target=scorer.global_position
	for player in game.players:
		player.emotion="celebrate" if player.team==scoring else "sad"
		player.emotion_time=0
	game._record("celebration_start",scorer,{"team":scoring,"restart_id":restart_id})
	_transition("celebrating")

func begin_free_kick(match_node: Node3D, team: int, spot: Vector3) -> void:
	_start(match_node,team,"free kick",Vector3(clampf(spot.x,-16.5,16.5),0,clampf(spot.z,-10.5,10.5)))
	for player in game.players:
		if player.sent_off or player==runner:
			continue
		var destination: Vector3=player.global_position
		var slot: int=game.players.find(player)%3
		if player.team!=team:
			var goal:=Vector3(-18.0 if player.team==0 else 18.0,0,0)
			var toward_goal: Vector3=(goal-restart_spot).normalized()
			destination=restart_spot+toward_goal*(FootballRules.RESTART_DISTANCE+.3)+toward_goal.cross(Vector3.UP)*(slot-1)
			if goal.distance_to(restart_spot)<FootballRules.RESTART_DISTANCE:
				destination=goal+Vector3(0,0,(slot-1)*.7)
		else:
			var attack:=1.0 if team==0 else -1.0
			destination=restart_spot+Vector3(attack*(4 if slot%2==0 else -2),0,3 if slot%2==0 else -4)
			destination.x=clampf(destination.x,-17,17)
			destination.z=clampf(destination.z,-11,11)
		targets[player.player_id]=legal_target(destination,player)
	game.referee.start_marking(restart_spot,team)
	game.hud.flash("FREE KICK — GIVE SPACE",3)
	game._record("free_kick_awarded",runner,{"spot":game._vec(restart_spot),"restart_id":restart_id})
	_transition("settle" if _near_spot(.65) else "retrieve")

func _start(match_node: Node3D, team: int, kind: String, spot: Vector3) -> void:
	game=match_node
	FootballAI.clear_plans()
	restart_id+=1
	receiving_team=team
	restart_kind=kind
	restart_spot=spot
	active=true
	state=""
	elapsed=0
	total_elapsed=0
	scorer=null
	carrying=false
	retrieved=false
	relay_received=false
	return_passes=0
	return_receiver=null
	kickoff_receiver=null
	net_pull_planted=false
	signalled=false
	ready_elapsed=0
	_clear_pending()
	targets.clear()
	game.referee.begin_restart(restart_id)
	for i in range(game.players.size()):
		var player: FootballPlayer=game.players[i]
		var side: float=-1 if player.team==0 else 1
		var index:=i%3
		targets[player.player_id]=Vector3(side*[3.0,7.0,11.0][index],0,[-1.0,5.0,-4.0][index])
		player.buffered_remaining=0
		player.incoming_pass_remaining=0
		player.emotion=""
		_clear_ball_intent(player)
	runner=_nearest_returner()
	retriever=runner
	for player in game.players:
		if not player.sent_off:
			targets[player.player_id]=legal_target(targets[player.player_id],player)
	game.kickoff_remaining=0
	game.charging=false
	game.delivery_kind=""

func _nearest_returner() -> FootballPlayer:
	var chosen: FootballPlayer
	var best:=INF
	for player in game.players:
		if player.team!=receiving_team or player.sent_off or player==game.controlled or not player.upright_ready():
			continue
		var cost: float=player.global_position.distance_to(game.ball.global_position)
		cost-=1.2 if player.role=="Anchor" else 0
		if cost<best:
			best=cost
			chosen=player
	if chosen==null:
		for player in game.players:
			if player.team==receiving_team and not player.sent_off:
				chosen=player
				break
	return chosen

func _centre_receiver() -> FootballPlayer:
	var chosen: FootballPlayer
	var best:=INF
	for player in game.players:
		if player.team!=receiving_team or player==runner or player==game.controlled or player.sent_off or not player.upright_ready():
			continue
		var cost: float=player.global_position.distance_to(restart_spot)*.1-(3 if player.role=="Runner" else 0)
		if cost<best:
			best=cost
			chosen=player
	return chosen

func legal_target(preferred: Vector3, player: FootballPlayer) -> Vector3:
	if FootballRules.illegal_position(preferred,player.team,receiving_team,player==runner,restart_kind,restart_spot) == "":
		return preferred
	var best := INF
	var result := preferred
	for i in range(64):
		var candidate := restart_spot + Vector3(cos(i*TAU/64),0,sin(i*TAU/64)) * (FootballRules.RESTART_DISTANCE+.4)
		candidate.x = clampf(candidate.x,-17.8,17.8)
		candidate.z = clampf(candidate.z,-11,11)
		if FootballRules.illegal_position(candidate,player.team,receiving_team,false,restart_kind,restart_spot) != "":
			continue
		var distance := candidate.distance_squared_to(preferred)
		if distance < best:
			best = distance
			result = candidate
	return result

func position_reason(player: FootballPlayer) -> String:
	return FootballRules.illegal_position(player.global_position,player.team,receiving_team,player==runner,restart_kind,restart_spot)

func _transition(next_state: String) -> void:
	if state==next_state:
		return
	state=next_state
	elapsed=0
	stance_phase="direct"
	if state not in ["ready","kickoff_pending"]:
		signalled=false
		ready_elapsed=0
	game._record("restart_phase",runner,{"restart_id":restart_id,"state":state})

func _clear_ball_intent(player: FootballPlayer) -> void:
	player.retrieval_positioning=false
	player.retrieval_pull_direction=Vector3.ZERO
	player.restart_settle=false
	player.restart_touch_velocity=Vector3.ZERO

func _clear_pending() -> void:
	pending_action_id=0
	pending_player_id=""
	pending_purpose=""
	pending_receiver_id=""
	return_pass_pending=false

func _recover() -> void:
	_clear_pending()
	return_receiver=null
	kickoff_receiver=null
	net_pull_planted=false
	for player in game.players:
		player.incoming_pass_remaining=0
		_clear_ball_intent(player)
	runner=_nearest_returner()
	if runner==null:
		return
	_transition("settle" if _near_spot(.65) else "retrieve")

func _near_spot(radius: float) -> bool:
	return ((game.ball.global_position-restart_spot)*Vector3(1,0,1)).length()<radius

func _settled() -> bool:
	return _near_spot(.18) and game.ball.global_position.y<FootballBall.RADIUS+.055 and game.ball.linear_velocity.length()<.22

func tick(delta: float) -> void:
	if not active or runner==null:
		return
	elapsed+=delta
	total_elapsed+=delta
	if runner.sent_off:
		_recover()
		return
	if state=="celebrating" and elapsed>=3.5:
		for player in game.players:
			player.emotion=""
		game._record("return_to_positions",null,{"restart_id":restart_id})
		_transition("retrieve")
	# Formation slots guide AI only. Human movement remains normal and legal
	# areas, rather than these slots, determine readiness and referee decisions.
	for player in game.players:
		if player.sent_off or player==game.controlled:
			continue
		if player==runner and state!="celebrating":
			continue
		player.sprint=false
		player.jockey=false
		_clear_ball_intent(player)
		var destination: Vector3=targets[player.player_id]
		if state=="celebrating":
			destination=celebration_target+Vector3((game.players.find(player)%3-1)*1.5,0,1.7) if scorer!=null and player.team==scorer.team else player.global_position
		_walk(player,destination)
	if state=="celebrating":
		return
	if runner!=game.controlled:
		runner.emotion=""
		runner.sprint=false
		runner.jockey=false
		_clear_ball_intent(runner)
	# A displaced ball always gets a physical recovery route, even after the
	# taker had finished placing it. No phase sends it through a net wall.
	if state in ["settle","kickoff_prepare","ready"] and not _near_spot(1.2):
		_recover()
	if state=="retrieve":
		_retrieve()
	elif state=="relay_prepare":
		_relay_prepare()
	elif state in ["relay_pending","kickoff_pending"]:
		if runner!=game.controlled:
			runner.intent=Vector3.ZERO
		if state=="kickoff_pending" and not _near_spot(.32):
			_recover()
	elif state=="relay_flight":
		if game.ball.last_touch_id not in [relay_passer_id,runner.player_id,""]:
			_recover()
		elif elapsed>4.0:
			_recover()
		elif runner!=game.controlled:
			FootballAI._receive(runner,game.ball)
	elif state=="settle":
		_settle()
	elif state=="kickoff_prepare":
		_kickoff_prepare()
	elif state=="ready":
		_ready(delta)
	if active and state not in ["relay_pending","kickoff_pending"]:
		game._control_ball()

func _net_retrieval() -> bool:
	var route: Vector3=(restart_spot-game.ball.global_position)*Vector3(1,0,1)
	if route.length_squared()<.001 or absf((game.ball.global_position-route.normalized()*.6).x)<=19.45:
		net_pull_planted=false
		return false
	if runner==game.controlled:
		return true
	var reachable: Vector3=game.ball.global_position
	reachable.x=clampf(reachable.x,-19.55,19.55)
	reachable.z-=.56*signf(reachable.z if absf(reachable.z)>.05 else 1.0)
	if net_pull_planted:
		reachable=net_pull_stance
	var approach: Vector3=(reachable-runner.global_position)*Vector3(1,0,1)
	var gap: Vector3=(game.ball.global_position-runner.global_position)*Vector3(1,0,1)
	runner.retrieval_positioning=true
	runner.intent=approach.normalized()*minf(approach.length()*2,.5) if approach.length()>.04 else Vector3.ZERO
	runner.aim=gap.normalized()
	if approach.length()<.08 and runner.reach_ball(game.ball):
		if not net_pull_planted:
			net_pull_stance=runner.global_position
			net_pull_planted=true
		runner.retrieval_positioning=false
		runner.intent=Vector3.ZERO
		runner.retrieval_pull_direction=Vector3(-signf(game.ball.global_position.x),0,0)
	return true

func _retrieve() -> void:
	if _net_retrieval():
		return
	if _near_spot(.65):
		_transition("settle")
		return
	if restart_kind=="kickoff" and not relay_received and absf(game.ball.global_position.x)<17.6:
		return_receiver=_centre_receiver()
		if return_receiver!=null:
			targets[return_receiver.player_id]=restart_spot+Vector3(-.55 if receiving_team==0 else .55,0,0)
			_transition("relay_prepare")
			return
	_bring_to_spot()

func _bring_to_spot() -> void:
	if runner==game.controlled:
		return
	var offset: Vector3=(restart_spot-game.ball.global_position)*Vector3(1,0,1)
	var route:=offset.normalized()
	var gap: Vector3=(game.ball.global_position-runner.global_position)*Vector3(1,0,1)
	if gap.length()>.7 or gap.dot(route)<.12:
		_position_for_kick(route)
		return
	var speed:=clampf(offset.length()*1.4,.25,2.4)
	runner.intent=route*minf(speed/(runner.pace*.66),.65)
	runner.aim=gap.normalized()
	runner.restart_settle=true
	runner.restart_touch_velocity=route*speed

func _stop_near_ball() -> bool:
	if runner==game.controlled:
		return game.ball.linear_velocity.length()<.22
	var gap: Vector3=(game.ball.global_position-runner.global_position)*Vector3(1,0,1)
	if gap.length()>.68:
		var incoming: Vector3=game.ball.linear_velocity*Vector3(1,0,1)
		var route: Vector3=(restart_spot-game.ball.global_position)*Vector3(1,0,1)
		_position_for_kick(incoming.normalized() if incoming.length()>.3 else route.normalized())
		return false
	runner.intent=Vector3.ZERO
	runner.aim=gap.normalized()
	runner.restart_settle=true
	runner.restart_touch_velocity=Vector3.ZERO
	return game.ball.linear_velocity.length()<.22

func _position_for_kick(direction: Vector3) -> bool:
	if runner==game.controlled or direction.length_squared()<.01:
		return false
	var gap: Vector3=(game.ball.global_position-runner.global_position)*Vector3(1,0,1)
	var side:=direction.cross(Vector3.UP)
	if stance_phase=="direct" and gap.dot(direction)<.18 and gap.length()<1.3:
		stance_phase="around"
		stance_side=1.0 if (runner.global_position-game.ball.global_position).dot(side)>=0 else -1.0
	var destination: Vector3=game.ball.global_position-direction*.6
	if stance_phase=="around":
		destination=game.ball.global_position+side*stance_side*.95
		if ((destination-runner.global_position)*Vector3(1,0,1)).length()<.16:
			stance_phase="behind"
			destination=game.ball.global_position-direction*.6
	var approach: Vector3=(destination-runner.global_position)*Vector3(1,0,1)
	runner.retrieval_positioning=true
	runner.team_target=destination
	runner.intent=approach.normalized()*minf(approach.length()*1.8,.55) if approach.length()>.07 else Vector3.ZERO
	runner.aim=direction
	return approach.length()<.13 and gap.dot(direction)>.4 and absf(gap.dot(side))<.2 and runner.reach_ball(game.ball) and (runner.linear_velocity*Vector3(1,0,1)).length()<1

func _relay_prepare() -> void:
	if return_receiver==null or return_receiver.sent_off:
		_recover()
		return
	if _net_retrieval():
		_transition("retrieve")
		return
	if not _stop_near_ball():
		return
	var direction: Vector3=(return_receiver.global_position-game.ball.global_position)*Vector3(1,0,1)
	direction=direction.normalized()
	if not _position_for_kick(direction):
		return
	if return_receiver.global_position.distance_to(targets[return_receiver.player_id])>.35:
		return
	var delivery:=FootballPassing.delivery(runner,return_receiver,direction,"pass",.42,game.ball.global_position)
	runner.planned_receiver_id=return_receiver.player_id
	runner.planned_receive_point=delivery.point
	# notify_action('accepted') stores the immutable identity synchronously.
	if runner.kick(game.ball,delivery.direction,delivery.strength,.08,"pass",0,"restart_return"):
		_capture_pending(runner,"restart_return","relay_pending")

func _settle() -> void:
	if _net_retrieval():
		_transition("retrieve")
		return
	if _settled():
		_transition("kickoff_prepare")
		return
	if _near_spot(.18):
		_stop_near_ball()
	else:
		_bring_to_spot()

func _kickoff_prepare() -> void:
	if not _settled():
		_transition("settle")
		return
	kickoff_receiver=_restart_receiver()
	if kickoff_receiver==null:
		return
	var direction: Vector3=(kickoff_receiver.global_position-game.ball.global_position)*Vector3(1,0,1)
	if runner==game.controlled:
		if _players_ready() and game.referee.mark_state=="":
			_transition("ready")
		return
	if _position_for_kick(direction.normalized()) and _players_ready() and game.referee.mark_state=="":
		_transition("ready")

func _ready(delta: float) -> void:
	if not _settled():
		_transition("settle")
		return
	if not _players_ready() or game.referee.mark_state!="":
		signalled=false
		ready_elapsed=0
		return
	if not signalled:
		signalled=true
		game.sound.play_event("whistle")
		game.hud.flash("KICK TO RESTART",2)
		game._record("restart_signal",runner,{"restart_id":restart_id})
	ready_elapsed+=delta
	if runner==game.controlled:
		return
	if kickoff_receiver==null or kickoff_receiver.sent_off:
		_transition("kickoff_prepare")
		return
	var direction: Vector3=(kickoff_receiver.global_position-game.ball.global_position)*Vector3(1,0,1)
	if not _position_for_kick(direction.normalized()):
		_transition("kickoff_prepare")
		return
	if ready_elapsed>.6 and runner.upright_ready():
		var delivery:=FootballPassing.delivery(runner,kickoff_receiver,direction.normalized(),"pass",.4,game.ball.global_position)
		runner.planned_receiver_id=kickoff_receiver.player_id
		runner.planned_receive_point=delivery.point
		if runner.kick(game.ball,delivery.direction,delivery.strength,.08,"pass",0,"kickoff"):
			_capture_pending(runner,"kickoff","kickoff_pending")

func _capture_pending(player: FootballPlayer, purpose: String, phase: String) -> void:
	pending_action_id=player.accepted_action_id
	pending_player_id=player.player_id
	pending_purpose=purpose
	pending_receiver_id=player.accepted_receiver_id
	return_pass_pending=purpose=="restart_return"
	_transition(phase)

func notify_action(phase: String, player: FootballPlayer, detail: Dictionary) -> void:
	if not active:
		return
	if phase=="accepted" and player==runner:
		if detail.get("purpose","")=="restart_return" and state=="relay_prepare":
			_capture_pending(player,"restart_return","relay_pending")
		elif detail.get("purpose","")=="kickoff" and state=="ready" and signalled and _players_ready() and _settled():
			_capture_pending(player,"kickoff","kickoff_pending")
	if phase not in ["missed","cancelled"]:
		return
	if player.player_id==pending_player_id and int(detail.get("id",0))==pending_action_id:
		game._record("restart_action_failed",player,{"restart_id":restart_id,"phase":phase,"action_id":pending_action_id})
		_recover()

func notify_dribble(player: FootballPlayer) -> void:
	if not active:
		return
	if player==runner and not retrieved:
		retrieved=true
		game._record("ball_retrieved",player,{"restart_id":restart_id})
	if state=="relay_flight" and player==runner:
		relay_received=true
		game._record("restart_return_received",player,{"restart_id":restart_id,"from":relay_passer_id})
		_transition("settle")

func notify_kick(player: FootballPlayer) -> void:
	if not active:
		return
	var matches: bool=player.player_id==pending_player_id and player.accepted_action_id==pending_action_id and player.action_purpose==pending_purpose
	if matches and state=="relay_pending" and pending_purpose=="restart_return":
		var recipient: FootballPlayer
		for teammate in game.players:
			if teammate.player_id==pending_receiver_id and teammate.team==receiving_team and not teammate.sent_off:
				recipient=teammate
		if recipient==null:
			_recover()
			return
		return_passes+=1
		relay_passer_id=player.player_id
		targets[player.player_id]=legal_target(Vector3(-7 if receiving_team==0 else 7,0,4),player)
		_clear_ball_intent(player)
		game._record("restart_return_pass",player,{"restart_id":restart_id,"receiver":recipient.player_id,"action_id":pending_action_id})
		runner=recipient
		_clear_pending()
		_transition("relay_flight")
	elif matches and state=="kickoff_pending" and pending_purpose=="kickoff" and signalled and _players_ready() and _near_spot(.32):
		_finish()
	else:
		game._record("restart_retake",player,{"restart_id":restart_id,"state":state})
		_recover()

func _finish() -> void:
	_clear_pending()
	active=false
	_transition("live")
	carrying=false
	for player in game.players:
		player.emotion=""
		_clear_ball_intent(player)
	game.ball.last_touch_team=receiving_team
	game.ball.control_block_remaining=0
	game.sound.play_event("whistle")
	game.hud.flash("PLAY",1)
	game.team_coordinator.reset()
	game._record("natural_kickoff" if restart_kind=="kickoff" else "free_kick_ready",runner,{"restart_id":restart_id})

func _restart_receiver() -> FootballPlayer:
	var best:=-INF
	var chosen: FootballPlayer
	var own_direction:=1.0 if receiving_team==1 else -1.0
	for teammate in game.players:
		if teammate==runner or teammate.team!=receiving_team or teammate.sent_off or not teammate.upright_ready():
			continue
		if restart_kind=="kickoff" and teammate.global_position.x*own_direction<.3:
			continue
		var clearance:=_restart_lane_clearance(teammate)
		if clearance<.8:
			continue
		var score: float = minf(clearance,3)*2-teammate.global_position.distance_to(restart_spot)*.2
		# Prefer an AI recipient for the automatic sequence; a remaining human
		# teammate is still eligible after send-offs rather than deadlocking it.
		score-=1000 if teammate==game.controlled else 0
		if score>best:
			best=score
			chosen=teammate
	return chosen

func _restart_lane_clearance(target: FootballPlayer) -> float:
	var start: Vector3 = game.ball.global_position*Vector3(1,0,1)
	var end:=target.global_position*Vector3(1,0,1)
	var segment:=end-start
	var clearance:=20.0
	for player in game.players:
		if player==runner or player==target or player.sent_off:
			continue
		var point: Vector3 = player.global_position*Vector3(1,0,1)
		var along:=clampf((point-start).dot(segment)/maxf(segment.length_squared(),.001),0,1)
		if along>.03 and along<.97:
			clearance=minf(clearance,point.distance_to(start+segment*along))
	return clearance

func _walk(player: FootballPlayer, destination: Vector3) -> void:
	var offset := destination - player.global_position
	offset.y = 0
	player.intent = offset.normalized() * minf(offset.length() * 1.3, 1.0) if offset.length() > .3 else Vector3.ZERO
	if player.intent.length() > .1:
		player.aim = player.intent.normalized()
	# A loose ball over the boards is fetched by physically hopping them.
	if (absf(destination.z) > 12) != (absf(player.global_position.z) > 12) and absf(absf(player.global_position.z)-12.18) < 1.6 and player.hop():
		player.apply_central_impulse(Vector3.UP * player.mass * 1.5)

func _players_ready() -> bool:
	for player in game.players:
		if player.sent_off:
			continue
		if position_reason(player) != "":
			return false
	return true
