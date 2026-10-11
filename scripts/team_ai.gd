class_name FootballAI
extends RefCounted

# Decisions use present positions/velocities, never score or future human input.
# This layer supplies intent; all teams share FootballPlayer's physical actions.
static func decide(player: FootballPlayer, players: Array[FootballPlayer], ball: FootballBall, delta: float) -> String:
	player.reaction_timer -= delta
	if player.reaction_timer > 0.0:
		return ""
	player.reaction_timer = 0.16
	var attack := 1.0 if player.team == 0 else -1.0
	var goal := Vector3(attack * 18.8, 0.28, 0)
	var nearest: FootballPlayer = null
	var nearest_distance := INF
	var teammate_holder: FootballPlayer = null
	for other in players:
		if other.team != player.team:
			continue
		var distance := other.global_position.distance_to(ball.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = other
		if other.reach_ball(ball, 1.4):
			teammate_holder = other
	var target := ball.global_position
	if nearest != player:
		var lane := -5.0 if player.shirt_number == 7 else 5.0
		if player.shirt_number == 4:
			lane = 0.0
		var support_x := ball.global_position.x + attack * (4.0 if teammate_holder != null else -5.0)
		if player.shirt_number == 4:
			support_x = ball.global_position.x - attack * 6.0
		target = Vector3(clampf(support_x, -13.0, 13.0), 0, clampf(ball.global_position.z * 0.35 + lane, -9, 9))
	else:
		# Approach from behind the ball to carry it towards the opposing goal.
		var goal_direction := (goal - ball.global_position).normalized()
		if player.global_position.distance_to(ball.global_position) > 1.5:
			target = ball.global_position - goal_direction * 0.65
		else:
			target = goal
	var direction := target - player.global_position
	direction.y = 0.0
	player.intent = direction.normalized() if direction.length() > 0.65 else Vector3.ZERO
	player.aim = player.intent if player.intent.length_squared() > 0.1 else Vector3(attack, 0, 0)
	player.sprint = nearest == player and direction.length() > 4 and player.energy > 0.25
	# Defenders use the same finite contact windows and recovery as the controller.
	if ball.last_touch_team != player.team and ball.last_touch_team >= 0 and nearest == player:
		for opponent in players:
			if opponent.team == player.team:
				continue
			var separation := opponent.global_position - player.global_position
			separation.y = 0
			if separation.length() < 0.92 and absf(separation.normalized().dot(player.aim)) < 0.8:
				if player.shoulder(ball):
					return "shoulder"
		var ball_offset := ball.global_position - player.global_position
		ball_offset.y = 0
		if ball_offset.length() < 1.25:
			player.aim = ball_offset.normalized()
			if player.tackle(ball):
				return "tackle"
		elif ball_offset.length() < 2.6 and player.linear_velocity.length() > 3.5 and player.aim.dot(ball_offset.normalized()) > 0.85:
			if player.slide(ball):
				return "slide"
	if not player.reach_ball(ball):
		return ""
	var shot_direction := goal - player.global_position
	shot_direction.y = 0
	if absf(goal.x - player.global_position.x) < 10 and absf(player.global_position.z) < 6:
		player.aim = shot_direction.normalized()
		if player.kick(ball, player.aim, 17.0, 1.2, "shot"):
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
			if other == player or other.team != player.team:
				continue
			var advance := (other.global_position.x - player.global_position.x) * attack
			if advance > best:
				best = advance
				receiver = other
		if receiver != null and best > 0.5:
			var pass_direction := receiver.global_position - player.global_position
			pass_direction.y = 0
			if player.kick(ball, pass_direction, clampf(pass_direction.length() * 1.3, 7, 14), 0.12, "pass"):
				return "pass"
	return ""
