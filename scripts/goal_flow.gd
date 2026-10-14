class_name FootballGoalFlow
extends RefCounted

# A goal is a dead ball, not a teleport. Players return under normal locomotion;
# one receiving teammate retrieves the ball through physical foot touches.
var game: Node3D
var active := false
var state := ""
var elapsed := 0.0
var total_elapsed := 0.0
var receiving_team := 0
var scorer: FootballPlayer
var runner: FootballPlayer
var carrying := false
var targets: Dictionary = {}
var celebration_target := Vector3.ZERO
var restart_spot := Vector3.ZERO
var restart_kind := "kickoff"
var signalled := false
var ready_elapsed := 0.0
var retrieved := false
var kickoff_receiver: FootballPlayer

func begin_initial(match_node: Node3D, team: int) -> void:
	begin(match_node,1-team)
	state = "returning"
	for player in game.players:
		player.emotion = ""

func begin(match_node: Node3D, scoring: int) -> void:
	game = match_node
	game.referee.return_delay.clear()
	game.referee.last_distance.clear()
	active = true
	state = "celebrating"
	elapsed = 0
	total_elapsed = 0
	receiving_team = 1 - scoring
	restart_spot = Vector3.ZERO
	restart_kind = "kickoff"
	carrying = false
	retrieved=false
	kickoff_receiver=null
	signalled = false
	ready_elapsed = 0
	scorer = null
	runner = null
	for player in game.players:
		if player.sent_off:
			continue
		if player.player_id == game.ball.last_touch_id:
			scorer = player
		if player.team == receiving_team and player != game.controlled and runner == null:
			runner = player
	if scorer == null or scorer.team != scoring:
		for player in game.players:
			if player.team == scoring and not player.sent_off:
				scorer = player
				break
	if runner == null:
		runner = game.controlled
	celebration_target = scorer.global_position
	for i in range(game.players.size()):
		var player: FootballPlayer = game.players[i]
		var side := -1.0 if player.team == 0 else 1.0
		var index := i % 3
		targets[player.player_id] = Vector3(side * [3.0, 7.0, 11.0][index], .06, [-1.0,5.0,-4.0][index])
		player.buffered_remaining = 0
		player.dribble_active = false
		player.emotion = "celebrate" if player.team == scoring else "sad"
		player.emotion_time = 0
	targets[runner.player_id] = Vector3(-.8 if receiving_team == 0 else .8, .06, 0)
	for player in game.players:
		if player != runner:
			targets[player.player_id] = legal_target(targets[player.player_id],player)
	game.kickoff_remaining = 0
	game.charging = false
	game.delivery_kind = ""
	game._record("celebration_start", scorer, {"team":scoring})

func begin_free_kick(match_node: Node3D, team: int, spot: Vector3) -> void:
	game = match_node
	game.referee.return_delay.clear()
	game.referee.last_distance.clear()
	active = true
	state = "returning"
	elapsed = 0
	total_elapsed = 0
	receiving_team = team
	restart_kind = "free kick"
	restart_spot = Vector3(clampf(spot.x,-16.5,16.5),0,clampf(spot.z,-10.5,10.5))
	carrying = false
	retrieved=false
	kickoff_receiver=null
	signalled = false
	ready_elapsed = 0
	runner = null
	var best := INF
	for player in game.players:
		if not player.sent_off and player.team == team and player != game.controlled:
			var distance: float = player.global_position.distance_to(game.ball.global_position)
			if distance < best:
				best = distance
				runner = player
	if runner == null:
		runner = game.controlled if game.controlled.team == team else game.players.filter(func(p: FootballPlayer): return p.team == team and not p.sent_off)[0]
	for player in game.players:
		var destination: Vector3 = player.global_position
		if player.team != team:
			var goal := Vector3(-18.0 if player.team == 0 else 18.0,0,0)
			var toward_goal := (goal-restart_spot).normalized()
			var lateral := toward_goal.cross(Vector3.UP)
			var slot: int = game.players.find(player) % 3
			destination = restart_spot + toward_goal * (FootballRules.RESTART_DISTANCE+.3) + lateral * (slot-1) * 1.0
			if goal.distance_to(restart_spot) < FootballRules.RESTART_DISTANCE:
				destination = goal + Vector3(0,0,(slot-1)*.7)
		else:
			var attack := 1.0 if team == 0 else -1.0
			var slot: int = game.players.find(player) % 3
			destination = restart_spot + Vector3(attack * (4 if slot % 2 == 0 else -2),0,3 if slot % 2 == 0 else -4)
			destination.x = clampf(destination.x,-17,17)
			destination.z = clampf(destination.z,-11,11)
		destination = legal_target(destination,player)
		targets[player.player_id] = destination
		player.emotion = ""
	targets[runner.player_id] = restart_spot + Vector3(-.8 if team == 0 else .8,.06,0)
	game.charging = false
	game.delivery_kind = ""
	game.hud.flash("FREE KICK — GIVE SPACE",3)
	game._record("free_kick_awarded",runner,{"spot":game._vec(restart_spot)})
	game.referee.start_marking(restart_spot,team)

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

func tick(delta: float) -> void:
	if runner.sent_off:
		for player in game.players:
			if player.team == receiving_team and not player.sent_off:
				runner = player
				if player != game.controlled:
					break
		carrying = false
		state = "returning"
		signalled = false
		targets[runner.player_id] = restart_spot + Vector3(-.8 if receiving_team == 0 else .8,.06,0)
	elapsed += delta
	total_elapsed += delta
	if state == "celebrating" and elapsed >= 3.5:
		state = "returning"
		elapsed = 0
		for player in game.players:
			player.emotion = ""
		game.hud.flash("WALK BACK FOR KICKOFF", 3)
		game._record("return_to_positions", null)
	for player in game.players:
		if player.sent_off:
			continue
		if player == game.controlled:
			if player.intent.length() > .15:
				player.emotion = ""
			continue
		player.sprint = state == "returning" and player == runner
		player.jockey = false
		var destination: Vector3 = targets[player.player_id]
		if state == "celebrating":
			destination = celebration_target + Vector3((game.players.find(player) % 3 - 1) * 1.5, 0, 1.7) if player.team == scorer.team else player.global_position
		if player==runner and state in ["returning","placing"]:
			_return_ball()
		else:
			_walk(player, destination)
	if state == "ready":
		if not _players_ready():
			signalled = false
			ready_elapsed = 0
			return
		if not signalled:
			signalled = true
			game.sound.play_event("whistle")
		ready_elapsed += delta
		if runner != game.controlled and ready_elapsed > .6 and runner.upright_ready():
			kickoff_receiver=_restart_receiver()
			if kickoff_receiver!=null:
				var direction: Vector3 = (kickoff_receiver.global_position-game.ball.global_position)*Vector3(1,0,1)
				var delivery:=FootballPassing.delivery(runner,kickoff_receiver,direction.normalized(),"pass",.4)
				runner.planned_receiver_id=kickoff_receiver.player_id
				runner.planned_receive_point=delivery.point
				runner.aim=delivery.direction
				runner.kick(game.ball,delivery.direction,delivery.strength,.08,"pass")
		return
	if state not in ["returning", "placing"]:
		return
	if not retrieved and runner.reach_ball(game.ball):
		retrieved=true
		game._record("ball_retrieved", runner)
	game._control_ball()
	if state=="returning" and game.ball.global_position.distance_to(restart_spot+Vector3.UP*FootballBall.RADIUS)<.65:
		state="placing"
		elapsed=0
	var clear_stance: bool = kickoff_receiver!=null and (game.ball.global_position-runner.global_position).dot((kickoff_receiver.global_position-game.ball.global_position).normalized())>.32 and runner.reach_ball(game.ball)
	if _players_ready() and state == "placing" and clear_stance and game.referee.mark_state == "" and game.ball.global_position.distance_to(restart_spot + Vector3.UP * FootballBall.RADIUS) < .4 and game.ball.linear_velocity.length() < .25:
		state = "ready"
		carrying = false
		runner.emotion=""
		signalled = true
		game.sound.play_event("whistle")
		game.hud.flash("KICK TO RESTART",2)

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

func _return_ball() -> void:
	runner.emotion=""
	runner.sprint=false
	var offset: Vector3 = (restart_spot-game.ball.global_position)*Vector3(1,0,1)
	var distance:=offset.length()
	var route:=offset.normalized()
	var gap: Vector3 = (game.ball.global_position-runner.global_position)*Vector3(1,0,1)
	if state=="placing":
		# Cushion at the spot before repositioning beside it for a clear exit.
		if game.ball.linear_velocity.length()>.25 or distance>.4:
			runner.intent=route*minf(distance*.6,.35) if distance>.4 else Vector3.ZERO
			runner.aim=gap.normalized()
		else:
			kickoff_receiver=_restart_receiver()
			var outgoing: Vector3 = (kickoff_receiver.global_position-restart_spot).normalized() if kickoff_receiver!=null else Vector3(-1 if receiving_team==0 else 1,0,0)
			targets[runner.player_id]=game.ball.global_position-outgoing*.55
			var approach: Vector3 = (targets[runner.player_id]-runner.global_position)*Vector3(1,0,1)
			runner.intent=approach.normalized()*minf(approach.length()*1.6,.5) if approach.length()>.08 else Vector3.ZERO
			runner.aim=outgoing
		return
	if gap.length()>.85 or gap.dot(route)<.12:
		# Approach from behind the ball; go around it rather than kicking it
		# through the capsule when returning in the opposite direction.
		var behind: Vector3 = game.ball.global_position-route*.6
		if gap.dot(route)<.12 and gap.length()<1.5:
			behind+=route.cross(Vector3.UP)*.65
		_walk(runner,behind)
	else:
		runner.intent=route*clampf(distance*.22,.15,.65)
		runner.aim=route

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

func notify_kick(player: FootballPlayer) -> void:
	if not active:
		return
	if state == "ready" and player == runner and signalled and _players_ready():
		_finish()
	else:
		game._record("restart_retake",player)
		state = "returning"
		carrying = false
		signalled = false

func _finish() -> void:
	active = false
	state = ""
	carrying = false
	for player in game.players:
		player.emotion = ""
	game.ball.last_touch_team = receiving_team
	# Preserve the real kicker so the receiver assignment survives kickoff.
	game.ball.control_block_remaining = 0
	game.sound.play_event("whistle")
	game.hud.flash("PLAY", 1)
	game._record("natural_kickoff" if restart_kind == "kickoff" else "free_kick_ready", runner)
