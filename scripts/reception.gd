class_name FootballReception
extends RefCounted

const ELEVEN_MAX_THROUGH_SPEED := 20.0

# A delivery is a teammate's intention, never ownership of the physical ball.
var pending: Array[Dictionary] = []
var flight_velocity := Vector3.ZERO
var assigned_count: int = 0
var cancelled_count: int = 0
var last_receiver: String = ""

func queue_delivery(player: FootballPlayer, kind: String, ball: FootballBall, receiver_id: String = "") -> void:
	if kind not in ["pass", "through", "lob", "roll", "throw"]:
		return
	pending.append({
		"passer": player, "kind": kind, "serial": ball.touch_serial,
		"receiver": receiver_id if not receiver_id.is_empty() else player.pending_receiver_id,
		"target_depth": player.pending_receiver_depth,
	})
	player.pending_receiver_id = ""
	player.pending_receiver_depth = 0.0

func reset(ball: FootballBall) -> void:
	pending.clear()
	ball.clear_pass("restart")
	flight_velocity = Vector3.ZERO
	last_receiver = ""

func update(game: Node3D, delta: float) -> void:
	var ball: FootballBall = game.ball
	if not pending.is_empty():
		var deliveries := pending.duplicate()
		pending.clear()
		for delivery: Dictionary in deliveries:
			var passer: FootballPlayer = delivery.passer
			if not is_instance_valid(passer) or int(delivery.serial) != ball.touch_serial or not ball.grip_holder_id.is_empty():
				continue
			var velocity := flat(ball.linear_velocity)
			if velocity.length() < 1.0:
				continue
			var receiver := choose_receiver(passer, game.players, ball.global_position, velocity, str(delivery.receiver), float(delivery.target_depth))
			if receiver == null:
				continue
			var distance := flat(receiver.global_position-ball.global_position).length()
			ball.begin_pass(passer.player_id, receiver.player_id, passer.team, interception_point(receiver, ball), clampf(distance/maxf(velocity.length()*.7,2.0)+1.0,.7,3.5))
			flight_velocity = velocity
			last_receiver = receiver.player_id
			assigned_count += 1
			game._record("receiver_assigned", receiver, {"passer":passer.player_id,"kind":delivery.kind,"serial":ball.touch_serial,"ball":game._vec(ball.global_position)})
	if not ball.pass_active:
		return
	var receiver: FootballPlayer = null
	for player: FootballPlayer in game.players:
		if player.player_id == ball.pass_receiver_id:
			receiver = player
			break
	var velocity := flat(ball.linear_velocity)
	var reason := ""
	if receiver == null or receiver.ragdoll != null:
		reason = "receiver_unavailable"
	elif not ball.grip_holder_id.is_empty():
		reason = "keeper_collected"
	elif (absf(ball.global_position.x) > (50.2 if game.eleven_a_side else 20.3) or absf(ball.global_position.z) > (32.2 if game.eleven_a_side else 12.3)) and not game.throw_entering_pitch():
		reason = "left_court"
	elif flight_velocity.length()>1.5 and velocity.length()>1.0 and velocity.normalized().dot(flight_velocity.normalized())<.55:
		reason = "deflected"
	elif flat(receiver.global_position-ball.global_position).length() > (28.0 if receiver.eleven_slot >= 0 else 18.0):
		reason = "unreachable"
	if not reason.is_empty():
		game._record("receiver_cancelled", receiver, {"reason":reason})
		ball.clear_pass(reason)
		cancelled_count += 1
		return
	ball.pass_target = interception_point(receiver, ball)
	flight_velocity = velocity

static func choose_receiver(passer: FootballPlayer, players: Array[FootballPlayer], origin: Vector3, velocity: Vector3, requested: String = "", target_depth: float = 0.0) -> FootballPlayer:
	var result: FootballPlayer = null
	var best := -INF
	var direction := flat(velocity).normalized()
	for player: FootballPlayer in players:
		if player == passer or player.team != passer.team or player.is_goalkeeper or player.ragdoll != null:
			continue
		var offset := flat(player.global_position-origin)
		var distance := offset.length()
		if distance < 1.0 or distance > (28.0 if passer.eleven_slot >= 0 else 18.0):
			continue
		var along := offset.dot(direction)
		var lateral := (offset-direction*along).length()
		if along < .3 or lateral > maxf(2.0,along*.55):
			continue
		var depth_cost := absf(along - target_depth) * 0.22 if target_depth > 0.0 else distance * 0.12
		var score := 8.0 - lateral - depth_cost + (3.0 if player.player_id == requested else 0.0)
		if score > best:
			best = score
			result = player
	return result

static func interception_point(receiver: FootballPlayer, ball: FootballBall) -> Vector3:
	var velocity := flat(ball.linear_velocity)
	var origin := ball.global_position
	var target := origin + velocity * 0.15
	if receiver.eleven_slot >= 0 and is_airborne_delivery(ball):
		var drop := ball.airborne_position_after(ball.time_to_descend_to(0.45))
		var heading := velocity.normalized()
		var lateral := heading.cross(Vector3.UP)
		var side := -1.0 if (receiver.global_position - drop).dot(lateral) < -0.03 else 1.0
		# Leave room between the flight line and the player's capsule.
		target = drop + heading * 0.35 + lateral * side * 0.60
	else:
		var best := INF
		for sample in range(1, 19):
			var time := float(sample) * 0.075
			var point := origin + velocity * ((1.0 - exp(-0.52 * time)) / 0.52)
			var needed := flat(point - receiver.global_position).length()
			var reach := receiver.pace * time * 0.82 + 0.55
			var cost := absf(needed - reach) + time * 0.12
			if needed <= reach and cost < best:
				best = cost
				target = point
	var x := 49.7 if receiver.eleven_slot >= 0 else 17.7
	var z := 31.7 if receiver.eleven_slot >= 0 else 11.5
	return Vector3(clampf(target.x, -x, x), 0, clampf(target.z, -z, z))

static func is_airborne_delivery(ball: FootballBall) -> bool:
	return ball.global_position.y > 0.45 or absf(ball.linear_velocity.y) > 1.0

static func flat(value: Vector3) -> Vector3:
	return Vector3(value.x,0,value.z)

static func through_speed(distance: float, runner_speed: float) -> float:
	return clampf(9.7 + distance * 0.36 + clampf(runner_speed, 0.0, 5.0) * 0.65, 11.5, ELEVEN_MAX_THROUGH_SPEED)
