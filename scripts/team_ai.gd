class_name FootballAI
extends RefCounted

# Decisions use present positions/velocities, never score or future human input.
# This layer supplies intent; all teams share FootballPlayer's physical actions.
static func decide(player: FootballPlayer, players: Array[FootballPlayer], ball: FootballBall, delta: float) -> String:
	if player.is_goalkeeper:
		return ""
	if player.ragdoll != null or player.hop_active:
		return ""
	# An incoming pass remains a reception task until actual first contact.
	# Human selection bypasses this AI path in the normal match loop.
	if ball.pass_active and ball.pass_receiver_id == player.player_id:
		var target := FootballReception.interception_point(player,ball)
		var offset := target-player.global_position
		offset.y = 0
		var incoming := Vector3(ball.linear_velocity.x,0,ball.linear_velocity.z)
		var gap := Vector3(ball.global_position.x-player.global_position.x,0,ball.global_position.z-player.global_position.z).length()
		player.aim = (ball.global_position-player.global_position)*Vector3(1,0,1)
		player.aim = player.aim.normalized()
		var desired := offset.normalized()*minf(offset.length()*2.2,player.pace)
		if gap < 1.6:
			# Meet the lane, then move with the delivery rather than charging
			# head-on through it or turning to attack before the first touch.
			desired = (incoming*.35+offset*2.0).limit_length(player.pace*.65)
		player.sprint = gap > 2.4
		var base_speed := player.pace if player.sprint and player.energy > .05 else player.pace*.66
		player.intent = desired/maxf(base_speed,.1)
		if gap < 1.45:
			player.receive(ball)
		return "receiving"
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
	var teammate_chaser: FootballPlayer = null
	var opponent_carrier: FootballPlayer = null
	for other in players:
		if other.is_goalkeeper:
			continue
		if other.team != player.team:
			# Last touch alone is history, not an opponent in possession. A
			# loose ball must be collected rather than automatically tackled.
			if other.controlling_ball() or other.chasing_ball(ball):
				if opponent_carrier == null or other.global_position.distance_squared_to(ball.global_position) < opponent_carrier.global_position.distance_squared_to(ball.global_position):
					opponent_carrier = other
			continue
		var distance := other.global_position.distance_to(ball.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = other
		if other.controlling_ball():
			teammate_holder = other
		elif other.chasing_ball(ball):
			teammate_chaser = other
	# A genuine kick-ahead dribbler stays the attack reference during the
	# bounded chase. This only supplies intent; opponents may still win it.
	if teammate_holder != null:
		nearest = teammate_holder
	elif teammate_chaser != null:
		nearest = teammate_chaser
		teammate_holder = teammate_chaser
	# Keep the other two players available while the designated receiver meets
	# the flight. They can still intercept a loose ball after that intent ends.
	if ball.pass_active and ball.pass_team == player.team:
		for other in players:
			if other.player_id == ball.pass_receiver_id:
				nearest = other
				break
	if not ball.grip_holder_id.is_empty():
		for other in players:
			if other.player_id == ball.grip_holder_id and other.team == player.team:
				teammate_holder = other
				nearest = other
				break
	var target := ball.global_position
	if nearest != player:
		var lane := (-5.0 if player.shirt_number == 7 else 5.0) + player.ai_lane_offset
		if player.shirt_number == 4:
			lane = 0.0
		var support_x := ball.global_position.x + attack * (4.0 if teammate_holder != null else -5.0)
		if player.shirt_number == 4:
			support_x = ball.global_position.x - attack * 6.0
		target = Vector3(clampf(support_x, -13.0, 13.0), 0, clampf(ball.global_position.z * 0.35 + lane, -9, 9))
	else:
		# Follow the observed free-ball trajectory between real touches;
		# switching back to a behind-ball approach would abandon the run.
		var goal_direction := (goal - ball.global_position).normalized()
		if player.chasing_ball(ball):
			target = player.chase_target(ball)
		elif not player.controlling_ball():
			target = ball.global_position - goal_direction * 0.55
		else:
			target = goal
	var direction := target - player.global_position
	direction.y = 0.0
	var arrival_radius := 0.12 if nearest == player and not player.controlling_ball() else 0.65
	player.intent = direction.normalized() if direction.length() > arrival_radius else Vector3.ZERO
	player.aim = player.intent if player.intent.length_squared() > 0.1 else Vector3(attack, 0, 0)
	var chasing := nearest == player and player.chasing_ball(ball)
	var catch_up_run := chasing and direction.length() > 0.7 and Vector3(ball.linear_velocity.x, 0, ball.linear_velocity.z).length() > player.pace * 0.6
	player.sprint = nearest == player and (direction.length() > 4 or catch_up_run) and player.energy > 0.25 and confidence < 0.85
	# Defenders use the same finite contact windows and recovery as the controller.
	if ball.grip_holder_id.is_empty() and opponent_carrier != null and nearest == player:
		var separation := opponent_carrier.global_position - player.global_position
		separation.y = 0
		if separation.length() < 0.92 and absf(separation.normalized().dot(player.aim)) < 0.8:
			if confidence < 0.75 and player.shoulder(ball):
				return "shoulder"
		var ball_offset := ball.global_position - player.global_position
		ball_offset.y = 0
		if ball_offset.length() < 1.25 and separation.length() < 1.8:
			player.aim = ball_offset.normalized()
			if confidence < 0.8 and player.tackle(ball):
				return "tackle"
		elif ball_offset.length() < 2.6 and separation.length() < 2.8 and player.linear_velocity.length() > 3.5 and player.aim.dot(ball_offset.normalized()) > 0.85:
			if confidence < 0.35 + player.ai_style * 0.35 and player.slide(ball):
				return "slide"
	# A first-time pass or shot can be queued against an actually reachable
	# moving ball without first claiming a close-control state.
	if not ball.grip_holder_id.is_empty() or not player.predict_strike_reach(ball, 0.18):
		return ""
	var shot_direction := goal - player.global_position
	shot_direction.y = 0
	if absf(goal.x - player.global_position.x) < 10 and absf(player.global_position.z) < 6:
		player.aim = shot_direction.normalized()
		if confidence < 0.78 and player.kick(ball, player.aim.rotated(Vector3.UP, player.ai_rng.randf_range(-0.045, 0.045) / player.touch_skill), player.ai_rng.randf_range(16, 19), player.ai_rng.randf_range(1.0, 1.6), "shot"):
			return "shot"
	# A defender under pressure finds an advanced teammate, using the same kick.
	var pressured := false
	for opponent in players:
		if opponent.team != player.team and opponent.global_position.distance_to(player.global_position) < 2.1:
			pressured = true
	if pressured:
		var receiver: FootballPlayer = null
		var best := -INF
		for other in players:
			if other == player or other.team != player.team or other.is_goalkeeper:
				continue
			var advance := (other.global_position.x - player.global_position.x) * attack
			advance += player.ai_rng.randf_range(-1.5, 1.5)
			if advance > best:
				best = advance
				receiver = other
		if receiver != null and best > 0.5:
			var pass_direction := receiver.global_position - player.global_position
			pass_direction.y = 0
			player.pending_receiver_id = receiver.player_id
			if confidence < 0.85 and player.kick(ball, pass_direction.rotated(Vector3.UP, player.ai_rng.randf_range(-0.035, 0.035) / player.touch_skill), clampf(pass_direction.length() * player.ai_rng.randf_range(1.2, 1.4), 7, 14), 0.12, "pass"):
				return "pass"
			player.pending_receiver_id = ""
	return ""
