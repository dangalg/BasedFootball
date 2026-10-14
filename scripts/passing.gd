class_name FootballPassing
extends RefCounted

const ROLL_DRAG := .62
const ARRIVAL_SPEED := 3.5

static func receiver(passer: FootballPlayer, direction: Vector3, players: Array[FootballPlayer]) -> FootballPlayer:
	var best := -INF
	var chosen: FootballPlayer
	for player in players:
		if player==passer or player.team!=passer.team or player.sent_off or not player.upright_ready():
			continue
		var offset := (player.global_position-passer.global_position)*Vector3(1,0,1)
		var alignment := direction.normalized().dot(offset.normalized())
		if offset.length()<1 or alignment<.866:
			continue
		var score := alignment*20-offset.length()*.12
		if score>best:
			best=score
			chosen=player
	return chosen

static func delivery(passer: FootballPlayer, target: FootballPlayer, direction: Vector3, kind: String, power: float, origin: Vector3 = Vector3.INF) -> Dictionary:
	# Calibrate from the ball rather than the capsule centre. Keep the optional
	# fallback for callers which only preview a delivery before a ball exists.
	var start := passer.global_position if not origin.is_finite() else origin
	start.y = 0
	var charge := clampf(power, 0, 1)
	var point := start+direction*lerpf(4,22,charge)
	var flight := .6
	if target!=null:
		var target_position := target.global_position*Vector3(1,0,1)
		var velocity := target.linear_velocity*Vector3(1,0,1)
		point=target_position
		if kind=="through":
			target_position+=Vector3(1 if passer.team==0 else -1,0,0)*lerpf(1.2,3.5,charge)
		for iteration in range(3):
			var distance := (point-start).length()
			var speed := ARRIVAL_SPEED+ROLL_DRAG*distance
			flight=clampf(log(speed/ARRIVAL_SPEED)/ROLL_DRAG,.2,2.6)
			# A lead is a reachable invitation, not a prediction that the player
			# maintains a sprint forever. The receiver still follows the live ball.
			point=target_position+(velocity*flight*.65).limit_length(3.0 if kind=="through" else 2.0)
		point.x=clampf(point.x,-17.25,17.25)
		point.z=clampf(point.z,-11.25,11.25)
	var offset := (point-start)*Vector3(1,0,1)
	var scale := lerpf(.75,1.35,charge)
	var strength := clampf((ARRIVAL_SPEED+ROLL_DRAG*offset.length())*scale,4,23)
	return {"direction":offset.normalized(),"strength":strength,"distance":offset.length()*scale,"flight":flight,"point":point}
