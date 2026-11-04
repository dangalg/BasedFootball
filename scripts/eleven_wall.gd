class_name ElevenWall
extends RefCounted

const MIN_DISTANCE := 9.15
const STAND_DISTANCE := 9.55
const SLOT_SPACING := 0.78

var members: Array[FootballPlayer] = []
var targets: Array[Vector3] = []
var spot: Vector3
var goalward: Vector3

func _init(ball_spot: Vector3, direction: Vector3, defenders: Array[FootballPlayer], manual_player: FootballPlayer) -> void:
	spot = ball_spot
	goalward = direction
	for slot in [-1, 0, 1]:
		var angle := float(slot) * SLOT_SPACING / STAND_DISTANCE
		var target := spot + goalward.rotated(Vector3.UP, angle) * STAND_DISTANCE
		var nearest: FootballPlayer = null
		var best := INF
		for defender in defenders:
			if defender == manual_player or defender in members or defender.ragdoll != null:
				continue
			var distance := defender.global_position.distance_squared_to(target)
			if distance < best:
				best = distance
				nearest = defender
		if nearest != null:
			members.append(nearest)
			targets.append(target)

func update_positions(defenders: Array[FootballPlayer], manual_player: FootballPlayer) -> bool:
	var ready := true
	for defender in defenders:
		if defender == manual_player:
			continue
		var slot := members.find(defender)
		var away := FootballReception.flat(defender.global_position - spot)
		var offset := Vector3.ZERO
		if slot >= 0:
			offset = FootballReception.flat(targets[slot] - defender.global_position)
			ready = ready and offset.length_squared() < 0.3 * 0.3 and away.length() >= MIN_DISTANCE
		elif away.length() < MIN_DISTANCE:
			var retreat := away.normalized() if away.length_squared() > 0.01 else goalward
			var target := spot + retreat * STAND_DISTANCE
			target.x = clampf(target.x, -49.6, 49.6)
			target.z = clampf(target.z, -31.6, 31.6)
			if FootballReception.flat(target - spot).length() < MIN_DISTANCE:
				target = spot + goalward * STAND_DISTANCE
			offset = FootballReception.flat(target - defender.global_position)
			ready = false
		defender.intent = (offset * 0.55).limit_length(1.0) if offset.length_squared() > 0.16 * 0.16 else Vector3.ZERO
		defender.sprint = false
		if slot >= 0:
			defender.aim = -away.normalized()
		elif defender.intent != Vector3.ZERO:
			defender.aim = defender.intent.normalized()
	return ready

func clear_attacking_players(attackers: Array[FootballPlayer], taker: FootballPlayer) -> bool:
	var center := spot + goalward * STAND_DISTANCE
	var lateral := goalward.cross(Vector3.UP)
	var ready := true
	for player in attackers:
		if player == taker:
			continue
		var offset := FootballReception.flat(player.global_position - center)
		var depth := offset.dot(goalward)
		if absf(depth) < 1.35 and absf(offset.dot(lateral)) < SLOT_SPACING + 1.25:
			player.intent = goalward * (0.55 if depth >= 0.0 else -0.55)
			ready = ready and absf(depth) >= 1.05
		else:
			player.intent = Vector3.ZERO
	return ready
