class_name FootballAI
extends RefCounted

const MIN_PASS_DISTANCE := 2.0
const MAX_PASS_DISTANCE := 15.5
const PASS_LANE_CLEARANCE := 0.85
const RETURN_MEMORY_SECONDS := 3.0
const PASS_ADVANTAGE_MARGIN := 0.30

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
	var options := evaluate_options(player, players, ball)
	var best_pass: Dictionary = options["pass"]
	# Small variation can break a close choice, but cannot make a blocked lane
	# eligible or manufacture a better-positioned receiver.
	var pass_value := -1000.0
	if bool(options["can_pass"]) and not best_pass.is_empty():
		for candidate: Dictionary in options["candidates"]:
			if not bool(candidate["eligible"]) or float(candidate["score"]) < float(options["pass_score"]) - 0.32:
				continue
			var value := float(candidate["score"]) + player.ai_rng.randf_range(-0.16, 0.16)
			if value > pass_value:
				pass_value = value
				best_pass = candidate
	var carry_value := float(options["dribble_score"]) + player.ai_rng.randf_range(-0.10, 0.10)
	var shot_value := float(options["shot_score"]) + player.ai_rng.randf_range(-0.12, 0.12)
	var wants_pass := pass_value > carry_value + PASS_ADVANTAGE_MARGIN and pass_value > shot_value + 0.10
	if wants_pass and confidence < (0.96 if bool(options["pressured"]) else 0.88):
		var destination := _point(best_pass["target"])
		var pass_direction := _flat(destination - ball.global_position).normalized()
		var kind := str(best_pass["kind"])
		var strength := clampf(float(best_pass["speed"]) * player.ai_rng.randf_range(0.97, 1.03), 7.0, 14.0)
		var actual_direction := pass_direction.rotated(Vector3.UP, player.ai_rng.randf_range(-0.035, 0.035) / maxf(player.touch_skill, 0.1))
		if player.kick(ball, actual_direction, strength, 0.14 if kind == "through" else 0.12, kind):
			# A failed queue must not erase an action's existing receiver intent.
			player.pending_receiver_id = str(best_pass["receiver_id"])
			_emit_decision(player, options, kind, best_pass, "better_open_teammate", true)
			return "pass"
	if shot_value > carry_value - 0.25 and shot_value >= pass_value - 0.10 and confidence < 0.82:
		var shot_direction := _point(options["shot_direction"])
		player.aim = shot_direction
		if player.kick(ball, shot_direction.rotated(Vector3.UP, player.ai_rng.randf_range(-0.045, 0.045) / maxf(player.touch_skill, 0.1)), player.ai_rng.randf_range(16, 19), player.ai_rng.randf_range(1.0, 1.6), "shot"):
			player.pending_receiver_id = ""
			_emit_decision(player, options, "shot", {"target": options["shot_target"]}, "clear_shot", true)
			return "shot"
	var reason := "carry_has_more_value"
	if not bool(options["can_pass"]):
		reason = "settling_or_delivery_cooldown" if float(options["settle_remaining"]) > 0 or float(options["delivery_cooldown_remaining"]) > 0 else "no_safe_pass"
	elif wants_pass:
		reason = "brief_decision_variation"
	_emit_decision(player, options, "carry", {}, reason)
	return ""

# Shared production/diagnostic evaluation. All results are observations of
# current positions, velocities and actual-contact history; there is no input
# prediction, possession grant, successful-pass roll or selected-player bonus.
static func evaluate_options(player: FootballPlayer, players: Array[FootballPlayer], ball: FootballBall) -> Dictionary:
	var attack := 1.0 if player.team == 0 else -1.0
	var origin := ball.global_position
	var goal := Vector3(attack * 18.8, FootballBall.RADIUS, 0)
	var carrier_space := _space_at(player.global_position, players, player.team)
	var forward := _flat(goal - origin).normalized()
	var forward_space := _space_at(origin + forward * 2.0, players, player.team, 0.25)
	var carry_score := 2.2 + minf(carrier_space, 4.0) * 0.45 + minf(forward_space, 4.0) * 0.35
	var receive_age := _seconds_since(player.last_received_frame)
	var delivery_age := _seconds_since(player.last_delivery_frame)
	var settle_remaining := maxf(0, 0.18 + player.ai_style * 0.14 - receive_age)
	var cooldown_remaining := maxf(0, 1.0 + player.ai_style * 0.2 - delivery_age)
	var candidates: Array[Dictionary] = []
	var best_pass: Dictionary = {}
	var best_score := -1000.0
	for receiver: FootballPlayer in players:
		if receiver == player or receiver.team != player.team or receiver.is_goalkeeper:
			continue
		var distance := _flat(receiver.global_position - origin).length()
		var velocity := _flat(receiver.linear_velocity).limit_length(receiver.pace)
		var to_feet := receiver.global_position + velocity * clampf(distance / 12.0 * 0.18, 0.06, 0.15)
		var feet_option := _pass_option(player, receiver, players, origin, to_feet, "pass", distance, 0.0, carrier_space, receive_age)
		candidates.append(feet_option)
		if bool(feet_option["eligible"]) and float(feet_option["score"]) > best_score:
			best_pass = feet_option
			best_score = float(feet_option["score"])
		# A through ball follows an observed forward run, never an anticipated
		# future stick direction. A feet pass remains an alternative to that run.
		if velocity.length() > 1.3 and velocity.x * attack > 0.8:
			var lead_seconds := clampf(distance / 11.0, 0.28, 0.60)
			var lead := (velocity * lead_seconds).limit_length(2.8)
			var run_option := _pass_option(player, receiver, players, origin, receiver.global_position + lead, "through", distance, lead_seconds, carrier_space, receive_age)
			candidates.append(run_option)
			if bool(run_option["eligible"]) and float(run_option["score"]) > best_score:
				best_pass = run_option
				best_score = float(run_option["score"])
	var shot_score := -1000.0
	var shot_clearance := 0.0
	var shot_direction := forward
	var best_shot_target := goal
	var depth := absf(goal.x - origin.x)
	if depth < 10.0 and absf(origin.z) < 6.0:
		for goal_z: float in [-1.35, 0.0, 1.35]:
			var shot_target := Vector3(goal.x, FootballBall.RADIUS, goal_z)
			var clearance := _lane_clearance(origin, shot_target, 18.0, players, player.team)
			if clearance < 0.40:
				continue
			var value := 3.6 + (10.0 - depth) * 0.30 + minf(clearance, 2.0) * 0.60 - absf(origin.z - goal_z) * 0.08
			if depth < 5.0 and clearance > 0.65:
				value += 0.50
			if value > shot_score:
				shot_score = value
				shot_clearance = clearance
				shot_direction = _flat(shot_target - origin).normalized()
				best_shot_target = shot_target
	var strike_reachable := player.predict_strike_reach(ball, 0.18)
	return {"candidates": candidates, "pass": best_pass, "pass_score": best_score,
		"dribble_score": carry_score, "shot_score": shot_score, "shot_direction": _vector(shot_direction), "shot_target": _vector(best_shot_target), "shot_clearance": shot_clearance,
		"carrier_space": carrier_space, "forward_space": forward_space, "pressured": carrier_space < 2.1,
		"settle_remaining": settle_remaining, "delivery_cooldown_remaining": cooldown_remaining, "recent_receive_age": receive_age,
		"strike_reachable": strike_reachable, "can_pass": not best_pass.is_empty() and settle_remaining <= 0 and cooldown_remaining <= 0 and strike_reachable and player.kick_cooldown <= 0}

static func _pass_option(passer: FootballPlayer, receiver: FootballPlayer, players: Array[FootballPlayer], origin: Vector3, target: Vector3, kind: String, receiver_distance: float, lead_seconds: float, carrier_space: float, receive_age: float) -> Dictionary:
	var attack := 1.0 if passer.team == 0 else -1.0
	var distance := _flat(target - origin).length()
	var speed := clampf(distance * 1.3, 7.0, 14.0)
	var lane := _lane_clearance(origin, target, speed, players, passer.team)
	var target_space := _space_at(target, players, passer.team, minf(lead_seconds, 0.60))
	var recent_passer := receiver.player_id == passer.last_received_from and receive_age <= RETURN_MEMORY_SECONDS
	var run_speed := _flat(receiver.linear_velocity).length()
	var pressure_relief := clampf(target_space - carrier_space, -2.0, 3.0)
	var advance := (target.x - origin.x) * attack
	var score := 1.6 + minf(target_space, 5.0) * 0.50 + minf(lane, 2.5) * 0.50 + pressure_relief * 0.45
	score += clampf(advance * 0.08, -0.50, 0.90) - distance * 0.045
	if run_speed > 1.0:
		score += 0.20
	if kind == "through":
		score += 0.35
	if recent_passer:
		# A previous passer is an option, not a return obligation. Space and
		# lane eligibility below take precedence over this small, fading bonus.
		score += 0.60 * (1.0 - receive_age / RETURN_MEMORY_SECONDS)
	var reason := "open_option"
	if receiver.ragdoll != null or receiver.hop_active or receiver.recovery_remaining > 0 or receiver.stagger_remaining > 0:
		reason = "receiver_unavailable"
	elif receiver_distance < MIN_PASS_DISTANCE or distance < MIN_PASS_DISTANCE or distance > MAX_PASS_DISTANCE:
		reason = "distance"
	elif absf(target.x) > 17.5 or absf(target.z) > 11.3:
		reason = "target_outside_pitch"
	elif lane < PASS_LANE_CLEARANCE:
		reason = "blocked_lane"
	elif target_space < (1.10 if kind == "through" else 1.0):
		reason = "receiver_marked"
	return {"receiver_id": receiver.player_id, "selected": receiver.selected, "kind": kind, "target": _vector(target),
		"eligible": reason == "open_option", "reason": reason, "score": score, "lane_clearance": lane, "receiver_space": target_space,
		"pressure_relief": pressure_relief, "advance": advance, "distance": distance, "speed": speed, "lead_seconds": lead_seconds, "recent_passer": recent_passer}

static func _space_at(point: Vector3, players: Array[FootballPlayer], team: int, future_seconds: float = 0.0) -> float:
	var space := 8.0
	for opponent: FootballPlayer in players:
		if opponent.team == team:
			continue
		var observed := opponent.global_position + _flat(opponent.linear_velocity).limit_length(opponent.pace) * future_seconds
		space = minf(space, _flat(point - observed).length())
	return space

static func _lane_clearance(origin: Vector3, target: Vector3, speed: float, players: Array[FootballPlayer], team: int) -> float:
	var path := _flat(target - origin)
	var distance := path.length()
	if distance < 0.01:
		return 0.0
	var direction := path / distance
	var clearance := 8.0
	for opponent: FootballPlayer in players:
		if opponent.team == team:
			continue
		var along := _flat(opponent.global_position - origin).dot(direction)
		var arrival := clampf(along / maxf(speed, 1.0), 0.0, 0.85)
		var observed := opponent.global_position + _flat(opponent.linear_velocity).limit_length(opponent.pace) * arrival
		# Consider both the current lane and observed movement into it. Players
		# behind the ball or beyond the receiver do not block an unrelated lane.
		for point: Vector3 in [opponent.global_position, observed]:
			var projection := _flat(point - origin).dot(direction)
			if projection < 0.25 or projection > distance + 0.4:
				continue
			var closest := origin + direction * clampf(projection, 0.0, distance)
			clearance = minf(clearance, _flat(point - closest).length())
	return clearance

static func _seconds_since(frame: int) -> float:
	if frame < 0:
		return 999.0
	return maxf(0, float(Engine.get_physics_frames() - frame) / maxf(float(Engine.physics_ticks_per_second), 1.0))

static func _emit_decision(player: FootballPlayer, options: Dictionary, action: String, candidate: Dictionary, reason: String, queued: bool = false) -> void:
	var frame := Engine.get_physics_frames()
	var previous_frame := int(player.get_meta("football_ai_decision_frame", -100000))
	if not queued and frame - previous_frame < Engine.physics_ticks_per_second:
		return
	player.set_meta("football_ai_decision_frame", frame)
	player.physical_event.emit("ai_decision", {"action": action, "kind": action if action != "carry" else "", "queued": queued, "reason": reason,
		"receiver_id": str(candidate.get("receiver_id", "")), "target": candidate.get("target", []), "candidate": candidate,
		"candidates": options["candidates"], "pass_score": options["pass_score"], "dribble_score": options["dribble_score"], "shot_score": options["shot_score"],
		"shot_direction": options["shot_direction"], "shot_clearance": options["shot_clearance"], "pressured": options["pressured"],
		"settle_remaining": options["settle_remaining"], "delivery_cooldown_remaining": options["delivery_cooldown_remaining"], "recent_receive_age": options["recent_receive_age"]})

static func _flat(value: Vector3) -> Vector3:
	return Vector3(value.x, 0, value.z)

static func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

static func _point(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
