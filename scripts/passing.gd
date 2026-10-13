class_name FootballPassing
extends RefCounted

const ROLL_DRAG := .62

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

static func delivery(passer: FootballPlayer, target: FootballPlayer, direction: Vector3, kind: String, power: float) -> Dictionary:
	var point := passer.global_position+direction*lerpf(4,22,power)
	var flight := .6
	if target!=null:
		point=target.global_position
		for iteration in range(3):
			var distance := point.distance_to(passer.global_position)
			var speed := 2.8+ROLL_DRAG*distance
			flight=clampf(log(speed/2.8)/ROLL_DRAG,.25,2)
			point=target.global_position+target.linear_velocity*flight
		if kind=="through":
			point+=Vector3(1 if passer.team==0 else -1,0,0)*lerpf(1.2,3.5,power)
	var offset := (point-passer.global_position)*Vector3(1,0,1)
	var scale := lerpf(.75,1.35,power)
	var strength := clampf((2.8+ROLL_DRAG*offset.length())*scale,4,23)
	return {"direction":offset.normalized(),"strength":strength,"distance":offset.length()*scale,"flight":flight,"point":point}
