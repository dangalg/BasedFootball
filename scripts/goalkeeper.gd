class_name FootballGoalkeeper
extends FootballPlayer

const AREA_NEAR := 12.5
const AREA_FAR := 18.1
const AREA_HALF_WIDTH := 4.2
const CATCH_SPEED := 6.8
const GRIP_MAX_FORCE := 70.0
const GLOVE_RADIUS := FootballKeeperVisual.GLOVE_RADIUS

var held_ball: FootballBall
var keeper_state: String = "set"
var catch_count: int = 0
var parry_count: int = 0
var release_count: int = 0
var hand_contact_count: int = 0
var save_attempt_count: int = 0
var save_attempt_diagnostics: Dictionary = {}
var grip_target := Vector3.ZERO
var save_hand_target := Vector3.ZERO
var maximum_grip_error: float = 0.0
var watched_ball: FootballBall
var teammates: Array[FootballPlayer] = []
var keeper_reaction_remaining: float = 0.0
var hold_elapsed: float = 0.0
var release_elapsed: float = 0.0
var hand_cooldown: float = 0.0
var lunge_remaining: float = 0.0
var previous_hands: Array[Vector3] = []
var previous_ball_position := Vector3.ZERO
var previous_grip_center := Vector3.ZERO
var observed_ball: FootballBall
var release_receiver_id: String = ""
var release_direction := Vector3.ZERO
var release_kind: String = "throw"

func _init() -> void:
	is_goalkeeper = true
	role = "keeper"
	shirt_number = 1
	pace = 5.8
	visual_controller = FootballKeeperVisual.new()

func _ready() -> void:
	super._ready()
	# The outfield capsule is wider than the visible chest. This keeper-only
	# radius permits the visible palms to meet a ball ahead of the torso.
	(body_collider.shape as CapsuleShape3D).radius = 0.28
	previous_hands = hand_positions()
	grip_target = global_position + Vector3.UP * 1.12 + _field_direction() * 0.42
	save_hand_target = grip_target

func _field_direction() -> Vector3:
	return Vector3.RIGHT if team == 0 else Vector3.LEFT

func _own_side() -> float:
	return -1.0 if team == 0 else 1.0

func area_contains(point: Vector3) -> bool:
	var depth := point.x * _own_side()
	return depth >= AREA_NEAR and depth <= AREA_FAR and absf(point.z) <= AREA_HALF_WIDTH

func hand_positions() -> Array[Vector3]:
	return (visual_controller as FootballKeeperVisual).hand_positions()

func decide_keeper(all_players: Array[FootballPlayer], ball: FootballBall, delta: float) -> String:
	watched_ball = ball
	teammates = all_players
	if ragdoll != null or hop_active:
		intent = Vector3.ZERO
		return ""
	if is_instance_valid(held_ball):
		intent = Vector3.ZERO
		sprint = false
		return ""
	keeper_reaction_remaining -= delta
	if keeper_reaction_remaining > 0:
		return ""
	keeper_reaction_remaining = ai_rng.randf_range(0.12, 0.23) / agility_skill
	var side := _own_side()
	var forward := _field_direction()
	var facing := ball.global_position - global_position
	facing.y = 0
	aim = facing.normalized() if facing.length_squared() > 0.02 else forward
	jockey = false
	var target := Vector3(side * 16.6, 0, clampf(ball.global_position.z * 0.18, -1.5, 1.5))
	var toward_goal := ball.linear_velocity.x * side > 0.3
	var arrival := INF
	var threatens := false
	if toward_goal:
		arrival = (side * 18.0 - ball.global_position.x) / ball.linear_velocity.x
		if arrival > 0 and arrival < 1.5:
			var impact_z := ball.global_position.z + ball.linear_velocity.z * arrival
			var impact_y := ball.global_position.y + ball.linear_velocity.y * arrival - 4.9 * arrival * arrival
			threatens = absf(impact_z) < 3.0 and impact_y < 2.65
			if threatens:
				target.z = clampf(impact_z, -2.05, 2.05)
	var distance := global_position.distance_to(ball.global_position)
	if area_contains(ball.global_position) and distance < 3.2 and ball.grip_holder_id.is_empty():
		target = ball.global_position + ball.linear_velocity * minf(0.18, distance / 10.0) - forward * 0.45
	if not area_contains(global_position):
		target = Vector3(side * 16.5, 0, clampf(global_position.z, -2.2, 2.2))
	target.x = side * clampf(target.x * side, AREA_NEAR + 0.25, AREA_FAR - 0.45)
	target.z = clampf(target.z, -AREA_HALF_WIDTH + 0.3, AREA_HALF_WIDTH - 0.3)
	var offset := target - global_position
	offset.y = 0
	intent = offset.normalized() * clampf(offset.length() * 1.2, 0, 1) if offset.length() > 0.15 else Vector3.ZERO
	sprint = threatens and offset.length() > 0.8 and energy > 0.25
	save_hand_target = ball.global_position + ball.linear_velocity * 0.06
	var reachable_save := area_contains(global_position) and area_contains(ball.global_position) and distance < 2.2 and ball.global_position.y > 0.45 and ball.global_position.y < 2.15
	if hand_cooldown <= 0:
		keeper_state = "tracking" if reachable_save else "set"
	if reachable_save and threatens and arrival < 0.6 and absf(offset.z) > 0.6 and lunge_remaining <= 0 and hand_cooldown <= 0:
		var lunge := Vector3(0, 0, signf(offset.z))
		apply_central_impulse(lunge * mass * 1.15)
		lunge_remaining = 0.4
		keeper_state = "lunge"
		save_attempt_count += 1
		save_attempt_diagnostics = {"kind": "lunge", "arrival": arrival, "target": _vector(target)}
	if reachable_save and previous_hands.size() == 2:
		save_attempt_diagnostics["ball_speed"] = ball.linear_velocity.length()
	if can_control(ball):
		var receiver := _choose_outlet(all_players)
		var direction := forward
		if receiver != null:
			direction = receiver.global_position + receiver.linear_velocity * 0.2 - global_position
		direction.y = 0
		if kick(ball, direction, clampf(direction.length() * 1.3, 8, 12), 0.2, "pass"):
			pending_receiver_id = receiver.player_id if receiver != null else ""
			return "keeper_clear_attempt"
	return ""

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	hand_cooldown = maxf(0, hand_cooldown - delta)
	lunge_remaining = maxf(0, lunge_remaining - delta)
	if freeze:
		_update_hand_history()
		return
	if ragdoll != null or recovery_remaining > 0 or stagger_remaining > 0:
		_drop_grip("impact")
		_update_hand_history()
		return
	var parent_phase: Variant = get_parent().get("phase")
	if parent_phase is String and parent_phase == "finished":
		_drop_grip("full_time")
		_update_hand_history()
		return
	if is_instance_valid(held_ball):
		_update_grip(delta)
	else:
		held_ball = null
		_check_hand_contact()
	_update_hand_history()

func _update_hand_history() -> void:
	previous_hands = hand_positions()
	if is_instance_valid(watched_ball):
		previous_ball_position = watched_ball.global_position
		observed_ball = watched_ball

func _check_hand_contact() -> void:
	if not is_instance_valid(watched_ball) or hand_cooldown > 0 or action_kind != "" or hop_active:
		return
	var ball := watched_ball
	if not ball.grip_holder_id.is_empty() or not area_contains(global_position) or not area_contains(ball.global_position):
		return
	var hands := hand_positions()
	if hands.size() != 2:
		return
	if previous_hands.size() != 2 or observed_ball != ball:
		previous_hands = hands.duplicate()
		previous_ball_position = ball.global_position
	var radius := FootballBall.RADIUS + GLOVE_RADIUS
	var distance := INF
	var incoming := ball.linear_velocity - linear_velocity
	var approaching_contact := false
	for index in range(2):
		# Relative sweep accounts for a moving ball and moving visible glove.
		var from := previous_hands[index] - previous_ball_position
		var to := hands[index] - ball.global_position
		var motion := to - from
		var gap := _segment_distance_to_origin(from, to)
		# Classify approach at the start of the real relative sweep. Looking
		# only at the final positions incorrectly rejects a fast crossing ball.
		var approaches := from.dot(motion) < -0.0000001
		var resting_contact := motion.length_squared() < 0.0000001 and incoming.length() <= 0.6
		if gap <= radius and (approaches or resting_contact):
			distance = minf(distance, gap)
			approaching_contact = true
	if not approaching_contact:
		return
	var center := (hands[0] + hands[1]) * 0.5
	hand_contact_count += 1
	save_attempt_count += 1
	var both_hands := maxf(hands[0].distance_to(ball.global_position), hands[1].distance_to(ball.global_position))
	var can_catch := incoming.length() <= CATCH_SPEED and absf(incoming.y) <= 4.5 and both_hands <= radius + 0.025
	save_attempt_diagnostics = {"distance": distance, "both_hands_distance": both_hands, "relative_speed": incoming.length(), "inside_area": true, "hand_contact": true}
	if can_catch:
		held_ball = ball
		ball.touch(team, player_id, Vector3.ZERO)
		ball.grip_holder_id = player_id
		ball.control_candidate_id = ""
		grip_target = center
		previous_grip_center = center
		hold_elapsed = 0
		release_elapsed = 0
		keeper_state = "holding"
		intent = Vector3.ZERO
		sprint = false
		catch_count += 1
		physical_event.emit("keeper_catch", save_attempt_diagnostics.duplicate())
	else:
		var normal := (ball.global_position - center).normalized()
		if normal.dot(_field_direction()) < 0.3:
			normal = _field_direction()
		var outgoing := normal * clampf(incoming.length() * 0.7, 4.0, 11.0) + Vector3.UP * 1.5
		var impulse := ((outgoing - ball.linear_velocity) * ball.mass).limit_length(8.0)
		ball.touch(team, player_id, impulse)
		apply_central_impulse(-impulse)
		parry_count += 1
		hand_cooldown = 0.28
		keeper_state = "recover"
		physical_event.emit("keeper_parry", save_attempt_diagnostics.duplicate())

func _update_grip(delta: float) -> void:
	var ball := held_ball
	if ball.grip_holder_id != player_id or not area_contains(global_position) or not area_contains(ball.global_position):
		_drop_grip("area_or_owner")
		return
	hold_elapsed += delta
	var forward := -body_visual.global_basis.z.normalized()
	var carry := global_position + Vector3.UP * 1.12 + forward * 0.42
	if keeper_state == "releasing":
		release_elapsed += delta
		carry += forward * (minf(1, release_elapsed / 0.22) * 0.1)
		if release_elapsed >= 0.22:
			_release_ball()
			return
	grip_target = grip_target.move_toward(carry, delta * 1.7)
	var hands := hand_positions()
	if hands.size() != 2:
		_drop_grip("missing_hands")
		return
	var center := (hands[0] + hands[1]) * 0.5
	var error := center - ball.global_position
	maximum_grip_error = maxf(maximum_grip_error, error.length())
	var hand_velocity := (center - previous_grip_center) / maxf(delta, 0.001)
	previous_grip_center = center
	if hold_elapsed > 0.12 and (error.length() > 0.42 or (ball.linear_velocity - hand_velocity).length() > 10):
		_drop_grip("physical_spill")
		return
	var force := error * 210.0 + (hand_velocity - ball.linear_velocity) * 18.0 + Vector3.UP * ball.mass * 9.8
	force = force.limit_length(GRIP_MAX_FORCE)
	ball.apply_central_force(force)
	apply_central_force(-force)
	if keeper_state == "holding" and hold_elapsed >= 0.7:
		var receiver := _choose_outlet(teammates)
		release_receiver_id = receiver.player_id if receiver != null else ""
		release_direction = _field_direction()
		if receiver != null:
			release_direction = receiver.global_position + receiver.linear_velocity * 0.25 - ball.global_position
		release_direction.y = 0
		release_kind = "roll" if ball.global_position.y < 0.65 else "throw"
		keeper_state = "releasing"
		release_elapsed = 0

func _choose_outlet(all_players: Array[FootballPlayer]) -> FootballPlayer:
	var chosen: FootballPlayer
	var best := -INF
	for other in all_players:
		if other == self or other.team != team or other.is_goalkeeper or other.ragdoll != null:
			continue
		var distance := global_position.distance_to(other.global_position)
		if distance > 20:
			continue
		var space := 8.0
		for opponent in all_players:
			if opponent.team != team:
				space = minf(space, opponent.global_position.distance_to(other.global_position))
		var advance := (other.global_position - global_position).dot(_field_direction())
		var score := space * 1.4 + advance * 0.18 - distance * 0.15
		if score > best:
			best = score
			chosen = other
	return chosen

func _release_ball() -> void:
	if not is_instance_valid(held_ball):
		return
	var ball := held_ball
	var distance := release_direction.length()
	var direction := release_direction.normalized() if distance > 0.1 else _field_direction()
	var speed := clampf(distance * 0.95, 6.0, 12.0)
	var lift := 1.2 if release_kind == "roll" else 3.2
	var impulse := ((direction * speed + Vector3.UP * lift - ball.linear_velocity * 0.85) * ball.mass).limit_length(6.5)
	ball.grip_holder_id = ""
	held_ball = null
	ball.touch(team, player_id, impulse)
	release_count += 1
	hand_cooldown = 0.45
	keeper_state = "recover"
	physical_event.emit("keeper_release", {"receiver_id": release_receiver_id, "kind": release_kind, "impulse": _vector(impulse), "inside_area": area_contains(ball.global_position)})

func _drop_grip(reason: String) -> void:
	if is_instance_valid(held_ball):
		if held_ball.grip_holder_id == player_id:
			held_ball.grip_holder_id = ""
		physical_event.emit("keeper_drop", {"reason": reason})
	held_ball = null
	keeper_state = "set"
	hold_elapsed = 0
	release_elapsed = 0

func drop_ball(reason: String = "dead_ball") -> void:
	# Clear only the force-grip state. The free rigid ball keeps its transform
	# and current velocity when play ends or a restart is prepared.
	_drop_grip(reason)

func reset_action() -> void:
	_drop_grip("restart")
	super.reset_action()
	hand_cooldown = 0
	lunge_remaining = 0
	keeper_reaction_remaining = 0
	previous_hands.clear()
	observed_ball = null
	watched_ball = null
	intent = Vector3.ZERO
	grip_target = global_position + Vector3.UP * 1.12 + _field_direction() * 0.42
	save_hand_target = grip_target

func _segment_distance_to_origin(from: Vector3, to: Vector3) -> float:
	var segment := to - from
	var fraction := clampf(-from.dot(segment) / maxf(segment.length_squared(), 0.000001), 0, 1)
	return (from + segment * fraction).length()

func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
