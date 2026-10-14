class_name FootballAI
extends RefCounted

# Decisions use present positions/velocities, never score or future human input.
# This layer supplies intent; all teams share FootballPlayer's physical actions.
static var preparing_passes: Dictionary = {}

static func clear_plans() -> void:
	for plan in preparing_passes.values():
		if is_instance_valid(plan.player):
			plan.player.retrieval_positioning=false
			plan.player.restart_settle=false
			plan.player.restart_touch_velocity=Vector3.ZERO
	preparing_passes.clear()

static func preparation_for(player: FootballPlayer) -> Dictionary:
	return preparing_passes.get(player.get_instance_id(),{})

static func release_control(player: FootballPlayer) -> void:
	# A human taking over supplies their own movement and ball-control intent.
	# Keep any already accepted physical kick and its immutable metadata intact.
	_cancel_pass(player)

static func decide(player: FootballPlayer, players: Array[FootballPlayer], ball: FootballBall, delta: float) -> String:
	if player.sent_off or player.ragdoll != null or player.hop_active:
		_cancel_pass(player)
		return ""
	# An accepted action owns its metadata until physical contact or recovery.
	if player.action_kind!="" or player.recovery_remaining>0 or player.stagger_remaining>0:
		return ""
	if player.receive_hold_remaining>0:
		if ball.last_touch_id==player.player_id:
			_stabilize_ball(player,ball)
			return ""
		player.receive_hold_remaining=0
	if not preparing_passes.has(player.get_instance_id()):
		player.restart_settle=false
		player.restart_touch_velocity=Vector3.ZERO
	player.reaction_timer -= delta
	if player.reaction_timer > 0.0:
		return ""
	# Randomness is confined to choices, intent and timing, never hit outcomes.
	player.reaction_timer = player.ai_rng.randf_range(0.13, 0.27) / player.agility_skill
	player.ai_lane_offset = lerpf(player.ai_lane_offset, player.ai_rng.randf_range(-1.0, 1.0), 0.25)
	var confidence := player.ai_rng.randf()
	for attacker in players:
		if attacker == player or attacker.action_kind != "slide":
			continue
		var relative := attacker.global_position - player.global_position
		relative.y = 0
		var incoming := attacker.linear_velocity - player.linear_velocity
		var closing := incoming.dot(-relative.normalized())
		var time_to_hit := (relative.length() - 0.6) / maxf(closing, 0.01)
		if closing > 1.5 and time_to_hit > 0.06 and time_to_hit < player.ai_rng.randf_range(0.22, 0.40) and confidence < clampf(0.62 * player.agility_skill * player.energy, 0.25, 0.85):
			if player.hop():
				return "hop_attempt"
	var attack := 1.0 if player.team == 0 else -1.0
	var goal := Vector3(attack * 18.8, 0.28, 0)
	var nearest: FootballPlayer = null
	# Coordinator jobs have one owner; no second nearest-player election here.
	if player.tactical_role=="":
		player.intent=Vector3.ZERO
		return ""
	for teammate in players:
		if teammate.player_id==player.tactical_chaser_id:
			nearest=teammate
	player.team_role=player.tactical_role
	var target:=player.tactical_target
	var receiving:=player.incoming_pass_remaining>0 and ball.last_touch_id==player.incoming_pass_from
	if receiving:
		_cancel_pass(player)
		return _receive(player,ball)
	if preparing_passes.has(player.get_instance_id()):
		return _prepare_pass(player,ball)
	player.retrieval_positioning=false
	if nearest == player:
		target = pursuit_target(target)
	else:
		target.x = clampf(target.x, -16.5, 16.5)
		target.z = clampf(target.z, -10, 10)
	player.team_target = target
	var direction := target - player.global_position
	direction.y = 0.0
	var movement:=direction.normalized()*minf(direction.length()/1.2,1.0) if direction.length()>(.18 if nearest==player else .65) else Vector3.ZERO
	# Yield around teammates en route to a tactical position. The ball contender
	# keeps its contact approach; no positional correction or collision bypass.
	if nearest!=player:
		for teammate in players:
			if teammate==player or teammate.team!=player.team or teammate.sent_off:
				continue
			var separation:=player.global_position-teammate.global_position
			separation.y=0
			if separation.length()>.05 and separation.length()<1.6:
				movement+=separation.normalized()*(1.6-separation.length())*.7
	player.intent = movement.limit_length(1.0)
	player.aim = player.intent if player.intent.length_squared() > 0.1 else Vector3(attack, 0, 0)
	player.sprint = nearest == player and direction.length() > 4 and player.energy > 0.25 and confidence < 0.85
	# Defenders use the same finite contact windows and recovery as the controller.
	if ball.last_touch_team != player.team and ball.last_touch_team >= 0 and nearest == player:
		for opponent in players:
			if opponent.team == player.team:
				continue
			var separation := opponent.global_position - player.global_position
			separation.y = 0
			if separation.length() < 1.0 and opponent.reach_ball(ball) and player.upright_ready():
				if confidence < 0.08:
					player.aim = separation.normalized()
					if player.grab(ball):
						return "grab"
				elif confidence < 0.26:
					player.aim = separation.normalized()
					if player.push(ball):
						return "push"
			if separation.length() < 0.92 and absf(separation.normalized().dot(player.aim)) < 0.8:
				if confidence < 0.75 and player.shoulder(ball):
					return "shoulder"
		var ball_offset := ball.global_position - player.global_position
		ball_offset.y = 0
		if ball_offset.length() < 1.25:
			player.aim = ball_offset.normalized()
			if confidence < 0.8 and player.tackle(ball):
				return "tackle"
		elif ball_offset.length() < 2.6 and player.linear_velocity.length() > 3.5 and player.aim.dot(ball_offset.normalized()) > 0.85:
			if confidence < 0.35 + player.ai_style * 0.35 and player.slide(ball):
				return "slide"
	if nearest != player or not player.reach_ball(ball) or ball.last_touch_id!=player.player_id or player.receive_hold_remaining>0:
		return ""
	var inward := Vector3.ZERO
	if absf(ball.global_position.z) > 11.1:
		inward.z = -signf(ball.global_position.z)
	if absf(ball.global_position.x) > 17.1 and absf(ball.global_position.z) > 2.4:
		inward.x = -signf(ball.global_position.x)
	if inward.length_squared() > 0:
		var escape := (inward + Vector3(attack * 0.45, 0, 0)).normalized()
		if player.kick(ball, escape, 7.0, 0.14, "clear"):
			return "wall_clear"
	var shot_direction := goal - player.global_position
	shot_direction.y = 0
	if absf(goal.x - player.global_position.x) < 10 and absf(player.global_position.z) < 6:
		player.aim = shot_direction.normalized()
		var blocked := lane_clearance(player.global_position, goal, players, player.team) < 0.75
		var kind := "finesse" if blocked else "power" if confidence < 0.18 and absf(goal.x - player.global_position.x) > 6 else "shot"
		if confidence < 0.60 and player.kick(ball, player.aim.rotated(Vector3.UP, player.ai_rng.randf_range(-0.045, 0.045) / player.touch_skill), player.ai_rng.randf_range(22, 27) if kind == "power" else player.ai_rng.randf_range(16, 19), player.ai_rng.randf_range(1.0, 1.6), kind):
			return kind
	# Useful lanes can be sideways or backward. A return combination is an
	# option evaluated against defenders and space, never a forced outcome.
	var pressured := false
	for opponent in players:
		if opponent.team != player.team and opponent.global_position.distance_to(player.global_position) < 2.1:
			pressured = true
	var receiver: FootballPlayer
	var best := -INF
	for other in players:
		if other == player or other.team != player.team or not other.upright_ready():
			continue
		var clearance := lane_clearance(ball.global_position, other.global_position, players, player.team)
		var open := INF
		for opponent in players:
			if opponent.team != player.team:
				open = minf(open, opponent.global_position.distance_to(other.global_position))
		var advance := (other.global_position.x - player.global_position.x) * attack
		var score := minf(clearance,3)+minf(open,4)*(.7 if pressured else .45)+clampf(advance*.3,-1,2)-other.global_position.distance_to(player.global_position)*.1
		score-=maxf(0,1.2-clearance)*6
		if player.combination_remaining>0 and other.player_id==player.last_pass_from:
			score+=1.8 if clearance>1.1 else .3
		score += player.ai_rng.randf_range(-0.3, 0.3)
		if score > best:
			best = score
			receiver = other
	if receiver!=null and confidence<(.85 if pressured else .72 if player.combination_remaining>0 else .48) and best>1.1:
		var kind:="lob" if lane_clearance(ball.global_position,receiver.global_position,players,player.team)<.9 else "pass"
		preparing_passes[player.get_instance_id()]={"player":player,"receiver":receiver,"receive_point":receiver.global_position,"kind":kind,"power":player.ai_rng.randf_range(.38,.45),"phase":"stop","age":0.0}
		return _prepare_pass(player,ball)
	if pressured and player.global_position.x * attack < -9:
		var clear_direction := Vector3(attack, 0, -signf(player.global_position.z) * 0.45).normalized()
		if player.kick(ball, clear_direction, 15, 1.2, "clear"):
			return "clear"
	return ""

static func _cancel_pass(player: FootballPlayer) -> void:
	preparing_passes.erase(player.get_instance_id())
	player.retrieval_positioning=false
	player.restart_settle=false
	player.restart_touch_velocity=Vector3.ZERO

static func _stabilize_ball(player: FootballPlayer, ball: FootballBall) -> bool:
	var gap: Vector3=(ball.global_position-player.global_position)*Vector3(1,0,1)
	player.retrieval_positioning=false
	player.restart_settle=true
	player.restart_touch_velocity=Vector3.ZERO
	player.sprint=false
	player.aim=gap.normalized() if gap.length_squared()>.001 else player.aim
	# Continue to a reachable foot position rather than stopping at the edge
	# of the broad capsule-control radius. Only contact can stop the ball.
	player.intent=gap.normalized()*minf((gap.length()-.58)*1.8,.65) if gap.length()>.66 else Vector3.ZERO
	return gap.length()<.72 and ball.linear_velocity.length()<.22 and (player.linear_velocity*Vector3(1,0,1)).length()<.6

static func _receive(player: FootballPlayer, ball: FootballBall) -> String:
	var target:=receive_target(player,ball)
	var offset: Vector3=(target-player.global_position)*Vector3(1,0,1)
	var ball_offset: Vector3=(ball.global_position-player.global_position)*Vector3(1,0,1)
	player.team_target=target
	player.sprint=offset.length()>4 and player.energy>.25
	player.aim=ball_offset.normalized() if ball_offset.length_squared()>.001 else player.aim
	# Brake into the incoming trajectory. Only the swept receiving foot can
	# finish the reception; proximity cannot authorize the next shot or pass.
	if ball_offset.length()<1.05:
		player.sprint=false
		player.intent=offset.normalized()*minf(offset.length()*.65,.3) if ball_offset.length()>.7 else Vector3.ZERO
	else:
		player.intent=offset.normalized()*minf(offset.length()/1.2,1.0) if offset.length()>.12 else Vector3.ZERO
	return ""

static func receive_target(player: FootballPlayer, ball: FootballBall) -> Vector3:
	var travel: Vector3=ball.linear_velocity*Vector3(1,0,1)
	var target:=_intercept(player,ball)
	if player.incoming_pass_remaining>0 and player.incoming_receive_point.is_finite():
		var planned:=pursuit_target(player.incoming_receive_point)
		if ball.global_position.y>.65:
			target=planned
		elif player.global_position.distance_to(ball.global_position)>2.5:
			target=target.lerp(planned,.15)
	return pursuit_target(target+travel.normalized()*.45)

static func _prepare_pass(player: FootballPlayer, ball: FootballBall) -> String:
	var plan: Dictionary=preparing_passes.get(player.get_instance_id(),{})
	if plan.is_empty():
		return ""
	var recipient: FootballPlayer=plan.receiver
	plan.age+=player.reaction_timer
	if not is_instance_valid(recipient) or recipient.sent_off or not recipient.upright_ready() or ball.last_touch_id!=player.player_id or float(plan.age)>2.5 or (ball.global_position-player.global_position).length()>1.8:
		_cancel_pass(player)
		return ""
	var direction: Vector3=(recipient.global_position-ball.global_position)*Vector3(1,0,1)
	if direction.length()<1:
		_cancel_pass(player)
		return ""
	direction=direction.normalized()
	var gap: Vector3=(ball.global_position-player.global_position)*Vector3(1,0,1)
	# A sidestep cannot catch an outward-moving ball. First plant and trap it
	# through the ordinary foot sweep, then walk around the stationary ball.
	if plan.phase=="stop" or ball.linear_velocity.length()>.35:
		plan.phase="stop"
		if not _stabilize_ball(player,ball):
			return ""
		plan.phase="stance"
	player.restart_settle=false
	player.restart_touch_velocity=Vector3.ZERO
	var side:=direction.cross(Vector3.UP)
	if plan.phase=="stance" and gap.dot(direction)<.18 and gap.length()<1.3:
		plan.phase="around"
		plan.side=1.0 if (player.global_position-ball.global_position).dot(side)>=0 else -1.0
	var target:=ball.global_position-direction*.6
	if plan.phase=="around":
		target=ball.global_position+side*float(plan.side)*.95
		if ((target-player.global_position)*Vector3(1,0,1)).length()<.16:
			plan.phase="behind"
			target=ball.global_position-direction*.6
	var offset: Vector3=(target-player.global_position)*Vector3(1,0,1)
	player.retrieval_positioning=true
	player.team_target=target
	player.sprint=false
	player.aim=direction
	player.intent=offset.normalized()*minf(offset.length()*1.8,.55) if offset.length()>.07 else Vector3.ZERO
	if offset.length()>.13 or gap.dot(direction)<.4 or absf(gap.dot(side))>.2 or not player.reach_ball(ball) or (player.linear_velocity*Vector3(1,0,1)).length()>1.0:
		return ""
	var delivery:=FootballPassing.delivery(player,recipient,direction,plan.kind,float(plan.power),ball.global_position)
	player.planned_receiver_id=recipient.player_id
	player.planned_receive_point=delivery.point
	var scheduled: bool=player.loft(ball,delivery.direction,delivery.distance) if plan.kind=="lob" else player.kick(ball,delivery.direction,delivery.strength,.08,"pass")
	if scheduled:
		preparing_passes.erase(player.get_instance_id())
		player.retrieval_positioning=false
		player.restart_settle=false
		player.restart_touch_velocity=Vector3.ZERO
		return plan.kind
	return ""

static func pursuit_target(target: Vector3) -> Vector3:
	# Capsule centres can reach the boards; formation spacing has separate limits.
	return Vector3(clampf(target.x, -17.55, 17.55), target.y, clampf(target.z, -11.55, 11.55))

static func _intercept(player: FootballPlayer, ball: FootballBall) -> Vector3:
	var target := ball.global_position
	for step in range(1, 26):
		var time := step * 0.1
		var predicted := ball.predict(time)
		predicted.x = _rebound(predicted.x, 17.89)
		predicted.z = _rebound(predicted.z, 11.89)
		target = pursuit_target(predicted)
		var gap := Vector2(target.x - player.global_position.x, target.z - player.global_position.z).length()
		if predicted.y < 0.65 and gap <= player.pace * 0.66 * time + 0.55:
			break
	target.y = 0
	return target

static func _rebound(value: float, extent: float) -> float:
	var wrapped := fposmod(value + extent, extent * 4)
	return wrapped - extent if wrapped <= extent * 2 else extent * 3 - wrapped

static func lane_clearance(start: Vector3, end: Vector3, players: Array[FootballPlayer], team: int) -> float:
	var segment := end - start
	segment.y = 0
	var clearance := 20.0
	for opponent in players:
		if opponent.team == team:
			continue
		var offset := opponent.global_position - start
		offset.y = 0
		var along := offset.dot(segment) / maxf(segment.length_squared(), 0.001)
		if along > 0.08 and along < 0.95:
			clearance = minf(clearance, (offset - segment * along).length())
	return clearance

static func _support_position(player: FootballPlayer, holder: FootballPlayer, players: Array[FootballPlayer], attack: float) -> Vector3:
	var lane := -4.0 if player.shirt_number == 10 else 4.0
	if player.support_requested > 0:
		return holder.global_position + Vector3(-attack * 2.5, 0, lane * 0.65)
	if player.run_requested > 0:
		return holder.global_position + Vector3(attack * 7, 0, lane * 0.6)
	var advance := -3.0 if player.shirt_number == 4 else 4.5
	var best := -INF
	var target := holder.global_position + Vector3(attack * advance, 0, lane)
	for adjustment in [-2.0, 0.0, 2.0]:
		var candidate := holder.global_position + Vector3(attack * advance, 0, lane + adjustment + player.ai_lane_offset * 0.5)
		var score := minf(lane_clearance(holder.global_position, candidate, players, player.team), 4)
		for teammate in players:
			if teammate != player and teammate != holder and teammate.team == player.team:
				score -= maxf(0, 3 - candidate.distance_to(teammate.global_position))
		if score > best:
			best = score
			target = candidate
	return target
