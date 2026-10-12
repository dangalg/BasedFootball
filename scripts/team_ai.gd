class_name FootballAI
extends RefCounted

# Decisions use present positions/velocities, never score or future human input.
# This layer supplies intent; all teams share FootballPlayer's physical actions.
static func decide(player: FootballPlayer, players: Array[FootballPlayer], ball: FootballBall, delta: float) -> String:
	if player.ragdoll != null or player.hop_active:
		return ""
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
	var nearest_distance := INF
	var teammate_holder: FootballPlayer = null
	for other in players:
		if other.team != player.team or not other.upright_ready():
			continue
		var distance := other.global_position.distance_to(ball.global_position)
		# Small continuity preference prevents two teammates exchanging pursuit.
		if other.team_role in ["press", "receive"]:
			distance -= 0.4
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = other
		if other.reach_ball(ball, 0.9):
			teammate_holder = other
	var opponent_holder: FootballPlayer = null
	var opponent_distance := INF
	for other in players:
		if other.team != player.team and other.upright_ready():
			var distance := other.global_position.distance_to(ball.global_position)
			if distance < opponent_distance:
				opponent_distance = distance
				opponent_holder = other
	var own_possession: bool = teammate_holder != null and nearest_distance <= opponent_distance and ball.global_position.y < 0.5
	var receiver: FootballPlayer = null
	for teammate in players:
		if teammate.team == player.team and teammate.incoming_pass_remaining > 0:
			if not teammate.upright_ready() or ball.last_touch_id != teammate.incoming_pass_from:
				teammate.incoming_pass_remaining = 0
			else:
				receiver = teammate
	if receiver != null:
		nearest = receiver
		own_possession = true
		if teammate_holder == null:
			teammate_holder = receiver
	var target := ball.global_position
	if receiver == player:
		player.team_role = "receive"
		target = _intercept(player, ball)
	elif nearest == player:
		player.team_role = "carry" if own_possession else "press"
		var goal_direction := (goal - ball.global_position).normalized()
		target = goal if own_possession else ball.global_position - goal_direction * 0.65 + ball.linear_velocity * 0.12
	elif own_possession:
		player.team_role = "support"
		target = _support_position(player, teammate_holder, players, attack)
	else:
		var own_goal := Vector3(-attack * 17.5, 0, 0)
		if player.shirt_number == 4:
			player.team_role = "cover"
			target = own_goal.lerp(ball.global_position, 0.28)
		else:
			player.team_role = "mark"
			var threat: FootballPlayer = null
			var danger := INF
			for other in players:
				if other.team != player.team and other != opponent_holder:
					var distance := other.global_position.distance_to(own_goal)
					if distance < danger:
						threat = other
						danger = distance
			target = threat.global_position.lerp(ball.global_position, 0.22) if threat != null else own_goal.lerp(ball.global_position, 0.5)
			target += (own_goal - target).normalized() * 0.8
	if nearest == player:
		target = pursuit_target(target)
	else:
		target.x = clampf(target.x, -16.5, 16.5)
		target.z = clampf(target.z, -10, 10)
	player.team_target = target
	var direction := target - player.global_position
	direction.y = 0.0
	player.intent = direction.normalized() if direction.length() > (0.18 if nearest == player else 0.65) else Vector3.ZERO
	player.aim = player.intent if player.intent.length_squared() > 0.1 else Vector3(attack, 0, 0)
	player.sprint = nearest == player and direction.length() > 4 and player.energy > 0.25 and confidence < 0.85
	# Defenders use the same finite contact windows and recovery as the controller.
	if ball.last_touch_team != player.team and ball.last_touch_team >= 0 and nearest == player:
		for opponent in players:
			if opponent.team == player.team:
				continue
			var separation := opponent.global_position - player.global_position
			separation.y = 0
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
	if nearest != player or not player.reach_ball(ball):
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
	# A defender under pressure finds an advanced teammate, using the same kick.
	var pressured := false
	for opponent in players:
		if opponent.team != player.team and opponent.global_position.distance_to(player.global_position) < 2.1:
			pressured = true
	receiver = null
	var best := -INF
	for other in players:
		if other == player or other.team != player.team or not other.upright_ready():
			continue
		var clearance := lane_clearance(player.global_position, other.global_position, players, player.team)
		var open := INF
		for opponent in players:
			if opponent.team != player.team:
				open = minf(open, opponent.global_position.distance_to(other.global_position))
		var advance := (other.global_position.x - player.global_position.x) * attack
		var score := minf(clearance, 3) + minf(open, 4) * 0.45 + advance * 0.18 - other.global_position.distance_to(player.global_position) * 0.08
		score += player.ai_rng.randf_range(-0.3, 0.3)
		if score > best:
			best = score
			receiver = other
	if receiver != null and confidence < (0.85 if pressured else 0.38) and best > 1.1:
		var pass_direction := receiver.global_position + receiver.linear_velocity * 0.35 - player.global_position
		pass_direction.y = 0
		pass_direction = pass_direction.rotated(Vector3.UP, player.ai_rng.randf_range(-0.035, 0.035) / player.touch_skill)
		if lane_clearance(player.global_position, receiver.global_position, players, player.team) < 0.9:
			if player.loft(ball, pass_direction.normalized(), pass_direction.length()):
				return "lob"
		elif player.kick(ball, pass_direction.normalized(), clampf(pass_direction.length() * 1.3, 7, 14), 0.12, "pass"):
			return "pass"
	if pressured and player.global_position.x * attack < -9:
		var clear_direction := Vector3(attack, 0, -signf(player.global_position.z) * 0.45).normalized()
		if player.kick(ball, clear_direction, 15, 1.2, "clear"):
			return "clear"
	return ""

static func pursuit_target(target: Vector3) -> Vector3:
	# Capsule centres can reach the boards; formation spacing has separate limits.
	return Vector3(clampf(target.x, -17.55, 17.55), target.y, clampf(target.z, -11.55, 11.55))

static func _intercept(player: FootballPlayer, ball: FootballBall) -> Vector3:
	var target := ball.global_position
	for step in range(1, 26):
		var time := step * 0.1
		var predicted := ball.global_position + ball.linear_velocity * time
		if ball.global_position.y > 0.2 or ball.linear_velocity.y > 1:
			predicted.y -= 4.9 * time * time
		else:
			predicted.y = FootballBall.RADIUS
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
