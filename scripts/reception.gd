class_name FootballReception
extends RefCounted

# A delivery is a teammate's intention, never ownership of the physical ball.
var pending: Array[Dictionary] = []
var flight_velocity := Vector3.ZERO
var assigned_count: int = 0
var cancelled_count: int = 0
var last_receiver: String = ""

func queue_delivery(player: FootballPlayer, kind: String, ball: FootballBall, receiver_id: String = "") -> void:
	if kind not in ["pass", "through", "lob", "roll", "throw"]:
		return
	pending.append({"passer":player,"kind":kind,"serial":ball.touch_serial,"receiver":receiver_id if not receiver_id.is_empty() else player.pending_receiver_id})
	player.pending_receiver_id = ""

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
			var receiver := choose_receiver(passer, game.players, ball.global_position, velocity, str(delivery.receiver))
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
	elif absf(ball.global_position.x)>20.3 or absf(ball.global_position.z)>12.3:
		reason = "left_court"
	elif flight_velocity.length()>1.5 and velocity.length()>1.0 and velocity.normalized().dot(flight_velocity.normalized())<.55:
		reason = "deflected"
	elif flat(receiver.global_position-ball.global_position).length()>18.0:
		reason = "unreachable"
	if not reason.is_empty():
		game._record("receiver_cancelled", receiver, {"reason":reason})
		ball.clear_pass(reason)
		cancelled_count += 1
		return
	ball.pass_target = interception_point(receiver, ball)
	flight_velocity = velocity

static func choose_receiver(passer: FootballPlayer, players: Array[FootballPlayer], origin: Vector3, velocity: Vector3, requested: String = "") -> FootballPlayer:
	var result: FootballPlayer = null
	var best := -INF
	var direction := flat(velocity).normalized()
	for player: FootballPlayer in players:
		if player == passer or player.team != passer.team or player.is_goalkeeper or player.ragdoll != null:
			continue
		var offset := flat(player.global_position-origin)
		var distance := offset.length()
		if distance < 1.0 or distance > 18.0:
			continue
		var along := offset.dot(direction)
		var lateral := (offset-direction*along).length()
		if along < .3 or lateral > maxf(2.0,along*.55):
			continue
		var score := 8.0-lateral-distance*.12+(3.0 if player.player_id==requested else 0.0)
		if score > best:
			best = score
			result = player
	return result

static func interception_point(receiver: FootballPlayer, ball: FootballBall) -> Vector3:
	var velocity := flat(ball.linear_velocity)
	var target := ball.global_position
	var best := INF
	for sample in range(1,19):
		var time := float(sample)*.075
		# Same approximate rolling deceleration as the free ball; observation is
		# refreshed each decision, so a bounce cannot reserve the old trajectory.
		var point := ball.global_position+velocity*((1.0-exp(-.52*time))/.52)
		var needed := flat(point-receiver.global_position).length()
		var reach := receiver.pace*time*.82+.55
		var cost := absf(needed-reach)+time*.12
		if needed <= reach and cost < best:
			best = cost
			target = point
	if best == INF:
		target = ball.global_position+velocity*.15
	return Vector3(clampf(target.x,-17.7,17.7),0,clampf(target.z,-11.5,11.5))

static func flat(value: Vector3) -> Vector3:
	return Vector3(value.x,0,value.z)
