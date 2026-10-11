class_name FootballPlayer
extends RigidBody3D

signal strike_contact(kind: String)
signal dribble_contact

const CONTROL_REACH := 0.95
const FOOT_DISTANCE := 0.61
const TOUCH_STRIDE_TIME := 0.13

var team: int = 0
var player_id: String = ""
var player_name: String = ""
var shirt_number: int = 7
var role: String = ""
var pace: float = 6.6
var touch_skill: float = 1.0
var stamina_trait: float = 1.0
var experience: int = 0
var energy: float = 1.0
var intent := Vector3.ZERO
var aim := Vector3.RIGHT
var sprint: bool = false
var selected: bool = false
var kick_cooldown: float = 0.0
var tackle_cooldown: float = 0.0
var touch_cooldown: float = 0.0
var reaction_timer: float = 0.0
var active_seconds: float = 0.0
var body_visual: Node3D
var left_leg: Node3D
var right_leg: Node3D
var ring: MeshInstance3D
var name_label: Label3D
var step_phase: float = 0.0
var tackle_remaining: float = 0.0
var match_touches: int = 0
var close_control_ball: FootballBall
var close_control_remaining: float = 0.0
var visual_controller := FootballPlayerVisual.new()
var body_collider: CollisionShape3D
var action_kind: String = ""
var action_direction := Vector3.RIGHT
var action_elapsed: float = 0.0
var action_duration: float = 0.0
var action_ball: FootballBall
var action_has_hit: bool = false
var recovery_remaining: float = 0.0
var stagger_remaining: float = 0.0
var challenge_contacts: int = 0
var control_stride_remaining: float = 0.0
var control_contact_offset := Vector3.ZERO
var jockey: bool = false
var shield_direction := Vector3.ZERO
var kick_strength: float = 0.0
var kick_lift: float = 0.0
var kick_kind: String = "pass"
var kick_target_offset := Vector3.ZERO
var kick_contact_time: float = 0.0
var last_boot_world := Vector3.ZERO
var completed_kicks: int = 0
var last_kick_contact_distance: float = 0.0
var dribble_active := false
var dribble_elapsed := 0.0
var dribble_duration := 0.22
var dribble_contact_time := 0.065
var dribble_has_hit := false
var dribble_ball: FootballBall
var dribble_target_offset := Vector3.ZERO
var dribble_start_foot_offset := Vector3.ZERO
var dribble_follow_direction := Vector3.RIGHT
var dribble_turn_side := 1.0
var completed_dribble_contacts := 0

func _ready() -> void:
	# Movement forces must remain responsive after a player stands still.
	can_sleep = false
	lock_rotation = true
	linear_damp = 0.1
	angular_damp = 1.0
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	var surface := PhysicsMaterial.new()
	surface.friction = 0.05
	surface.bounce = 0.02
	physics_material_override = surface
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.39
	shape.height = 1.65
	collider.shape = shape
	collider.position.y = 0.86
	add_child(collider)
	body_collider = collider
	_build_visual()

func _build_visual() -> void:
	visual_controller.build(self)

func _physics_process(delta: float) -> void:
	kick_cooldown = maxf(0.0, kick_cooldown - delta)
	tackle_cooldown = maxf(0.0, tackle_cooldown - delta)
	touch_cooldown = maxf(0.0, touch_cooldown - delta)
	tackle_remaining = maxf(0.0, tackle_remaining - delta)
	close_control_remaining = maxf(0.0, close_control_remaining - delta)
	recovery_remaining = maxf(0.0, recovery_remaining - delta)
	stagger_remaining = maxf(0.0, stagger_remaining - delta)
	control_stride_remaining = maxf(0.0, control_stride_remaining - delta)
	if action_kind != "":
		action_elapsed += delta
	if dribble_active:
		dribble_elapsed += delta
		if not dribble_has_hit and is_instance_valid(dribble_ball) and can_control(dribble_ball):
			# A foot can track a nearby moving ball during its approach. It does not
			# track or pull the ball after contact, or when the ball leaves reach.
			var time_to_contact := maxf(0, dribble_contact_time - dribble_elapsed)
			dribble_target_offset = dribble_ball.global_position - global_position + (dribble_ball.linear_velocity - linear_velocity) * time_to_contact
			dribble_target_offset.y = clampf(dribble_target_offset.y, 0.075, 0.28)
	active_seconds += delta
	if sprint and intent.length_squared() > 0.1:
		energy = maxf(0.0, energy - delta * 0.07 / stamina_trait)
	else:
		energy = minf(1.0, energy + delta * 0.05 * stamina_trait)
	ring.visible = selected
	name_label.visible = selected
	visual_controller.animate(self, delta)
	_update_dribble_contact()
	_update_challenge()

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var speed := pace if sprint and energy > 0.05 else pace * 0.66
	var horizontal := Vector3(state.linear_velocity.x, 0, state.linear_velocity.z)
	if stagger_remaining > 0.0:
		state.apply_central_force(-horizontal * mass * 1.5)
		return
	# Pace is unchanged. A touch temporarily shortens the stride; a released ball
	# immediately stops requiring those adjustments, for humans and AI alike.
	if controlling_ball():
		var stride_phase := control_stride_remaining / TOUCH_STRIDE_TIME
		speed *= 1.0 - (0.18 if sprint else 0.32) * sin(PI * stride_phase)
		speed *= _turn_speed_scale(close_control_ball, horizontal)
	if jockey:
		speed *= 0.65
	var desired := intent.limit_length(1.0) * speed
	if action_kind == "slide":
		desired = action_direction * lerpf(7.0, 2.5, clampf(action_elapsed / action_duration, 0, 1))
	elif action_kind == "kick":
		desired *= 0.35
	elif action_kind == "standing":
		desired = action_direction * 1.8
	elif action_kind == "shoulder":
		desired *= 0.65
	elif recovery_remaining > 0.0:
		desired *= 0.3
	var acceleration := (desired - horizontal) * 7.5
	# The cap preserves collision response and prevents instant direction changes.
	state.apply_central_force(acceleration.limit_length(24.0) * mass)

func controlling_ball() -> bool:
	return close_control_remaining > 0.0 and is_instance_valid(close_control_ball) and close_control_ball.last_touch_id == player_id and reach_ball(close_control_ball, CONTROL_REACH) and close_control_ball.control_block_remaining <= 0.0

func _turn_speed_scale(ball: FootballBall, velocity: Vector3) -> float:
	if intent.length_squared() < 0.01 or not reach_ball(ball, CONTROL_REACH) or ball.global_position.y > 0.4:
		return 1.0
	var ball_velocity := Vector3(ball.linear_velocity.x, 0, ball.linear_velocity.z)
	if (ball_velocity - velocity).length() > 5.5:
		return 1.0
	var direction := intent.normalized()
	var offset := ball.global_position - global_position
	offset.y = 0
	var angle := acos(clampf(offset.normalized().dot(direction), -1.0, 1.0))
	if velocity.length_squared() > 0.25:
		angle = maxf(angle, acos(clampf(velocity.normalized().dot(direction), -1.0, 1.0)))
	# Plant and brake before reversing around a ball still on the old side.
	# This is a movement adjustment during control, never a change to base pace.
	return lerpf(1.0, 0.0, smoothstep(0.45, 1.45, angle))

func reach_ball(ball: FootballBall, distance: float = CONTROL_REACH) -> bool:
	var difference := ball.global_position - global_position
	difference.y = 0
	return difference.length() < distance and ball.global_position.y < 0.75

func kick(ball: FootballBall, direction: Vector3, strength: float, lift: float, kind: String = "") -> bool:
	if kick_cooldown > 0.0 or action_kind != "" or recovery_remaining > 0.0 or stagger_remaining > 0.0 or not reach_ball(ball):
		return false
	# Queue a short wind-up. Only the visible boot's contact window can strike.
	action_kind = "kick"
	dribble_active = false
	action_direction = Vector3(direction.x, 0, direction.z).normalized()
	kick_kind = kind if kind != "" else ("shot" if strength >= 15.0 else "pass")
	kick_strength = strength
	kick_lift = lift
	kick_contact_time = 0.14 if kick_kind == "shot" else 0.10
	action_duration = 0.42 if kick_kind == "shot" else 0.32
	action_elapsed = 0
	action_ball = ball
	action_has_hit = false
	var relative_velocity := ball.linear_velocity - linear_velocity
	kick_target_offset = ball.global_position - global_position + relative_velocity * kick_contact_time
	kick_target_offset.y = clampf(kick_target_offset.y, 0.06, 0.55)
	var horizontal := Vector3(kick_target_offset.x, 0, kick_target_offset.z).limit_length(0.76)
	kick_target_offset.x = horizontal.x
	kick_target_offset.z = horizontal.z
	kick_cooldown = action_duration + 0.10
	close_control_remaining = 0.0
	control_stride_remaining = 0
	touch_cooldown = action_duration
	last_boot_world = visual_controller.right_boot.global_position
	return true

func can_control(ball: FootballBall) -> bool:
	if kick_cooldown > 0.0 or action_kind != "" or recovery_remaining > 0.0 or stagger_remaining > 0.0 or ball.control_block_remaining > 0.0 or not reach_ball(ball, CONTROL_REACH):
		return false
	if ball.global_position.y > 0.4:
		return false
	var relative_velocity := Vector3(ball.linear_velocity.x - linear_velocity.x, 0, ball.linear_velocity.z - linear_velocity.z)
	return relative_velocity.length() <= 6.2

func dribble(ball: FootballBall) -> bool:
	if touch_cooldown > 0.0 or not can_control(ball):
		return false
	var relative := ball.global_position - global_position
	relative.y = 0
	var player_velocity := Vector3(linear_velocity.x, 0, linear_velocity.z)
	var ball_velocity := Vector3(ball.linear_velocity.x, 0, ball.linear_velocity.z)
	var stick := minf(intent.length(), 1.0)
	var turning := stick > 0.05 and intent.normalized().dot(relative.normalized()) < 0.7
	var outward_speed := (ball_velocity - player_velocity).dot(relative.normalized())
	var needs_trap := turning or relative.length() + outward_speed * 0.10 > 0.78
	if dribble_active:
		if not dribble_has_hit or not needs_trap or dribble_elapsed < dribble_contact_time + 0.055:
			return false
	# A settled ball needs no recurring impulses or foot animation.
	if stick < 0.05 and player_velocity.length() < 0.12 and ball_velocity.length() < 0.12 and relative.length() > 0.45 and relative.length() < 0.75:
		return false
	dribble_active = true
	dribble_elapsed = 0
	dribble_duration = 0.16 if turning else (0.26 if sprint and energy > 0.05 else 0.22)
	dribble_contact_time = 0.05 if turning else 0.065
	dribble_has_hit = false
	dribble_ball = ball
	dribble_target_offset = ball.global_position - global_position + (ball.linear_velocity - linear_velocity) * dribble_contact_time
	dribble_start_foot_offset = visual_controller.right_boot.global_position - global_position
	dribble_target_offset.y = clampf(dribble_target_offset.y, 0.075, 0.28)
	dribble_follow_direction = intent.normalized() if stick > 0.05 else relative.normalized()
	close_control_ball = ball
	close_control_remaining = dribble_duration + 0.12
	last_boot_world = visual_controller.right_boot.global_position
	return false # Scheduling a swing is not a ball touch.

func _update_dribble_contact() -> void:
	if not dribble_active:
		return
	var boot_world: Vector3 = visual_controller.right_boot.global_position
	if action_kind != "" or not is_instance_valid(dribble_ball) or stagger_remaining > 0 or recovery_remaining > 0:
		dribble_active = false
		return
	if not dribble_has_hit and dribble_elapsed >= dribble_contact_time - 0.008 and dribble_elapsed <= dribble_contact_time + 0.055:
		if dribble_ball.control_candidate_id == player_id and can_control(dribble_ball) and _boot_distance(dribble_ball.global_position, last_boot_world, boot_world) < FootballBall.RADIUS + 0.12:
			var relative := dribble_ball.global_position - global_position
			relative.y = 0
			var velocity := Vector3(linear_velocity.x, 0, linear_velocity.z)
			var stick := minf(intent.length(), 1)
			var direction := intent.normalized() if stick > 0.05 else relative.normalized()
			if jockey and shield_direction.length_squared() > 0.1:
				direction = shield_direction
			var contact_direction := relative.normalized()
			var angle := contact_direction.signed_angle_to(direction, Vector3.UP)
			if absf(angle) > 2.8:
				angle = absf(angle) * dribble_turn_side
			elif absf(angle) > 0.25:
				dribble_turn_side = signf(angle)
			contact_direction = contact_direction.rotated(Vector3.UP, clampf(angle, -0.95, 0.95))
			var fast := sprint and energy > 0.05 and stick > 0.1
			var period := dribble_duration
			var speed := pace * (0.94 if fast else 0.66 * 0.80)
			var desired := intent.limit_length(1) * speed * _turn_speed_scale(dribble_ball, velocity)
			if jockey:
				desired *= 0.65
			# Predict the player's displacement through this free-flight interval.
			# One foot impulse supplies it; there is no force tether between contacts.
			var response := (1 - exp(-7.5 * period)) / (7.5 * period)
			var travel_velocity := desired + (velocity - desired) * response
			var next_offset := contact_direction * (0.68 if fast and absf(angle) < 0.7 else FOOT_DISTANCE)
			var target_velocity := (travel_velocity + (next_offset - relative) / period) * 1.045
			var ball_velocity := Vector3(dribble_ball.linear_velocity.x, 0, dribble_ball.linear_velocity.z)
			var impulse := (target_velocity - ball_velocity) * dribble_ball.mass
			dribble_ball.touch(team, player_id, impulse.limit_length(1.7 * touch_skill))
			dribble_has_hit = true
			dribble_follow_direction = target_velocity.normalized() if target_velocity.length() > 0.1 else contact_direction
			control_stride_remaining = TOUCH_STRIDE_TIME
			completed_dribble_contacts += 1
			match_touches += 1
			dribble_contact.emit()
	last_boot_world = boot_world
	if dribble_elapsed >= dribble_duration:
		dribble_active = false
		touch_cooldown = 0

func tackle(ball: FootballBall) -> bool:
	return _begin_challenge("standing", ball, 0.26, 0.85)

func slide(ball: FootballBall) -> bool:
	return _begin_challenge("slide", ball, 0.6, 1.6)

func shoulder(ball: FootballBall) -> bool:
	return _begin_challenge("shoulder", ball, 0.24, 0.9)

func _begin_challenge(kind: String, ball: FootballBall, duration: float, cooldown: float) -> bool:
	if tackle_cooldown > 0.0 or action_kind != "" or recovery_remaining > 0.0 or stagger_remaining > 0.0:
		return false
	action_kind = kind
	dribble_active = false
	action_direction = aim.normalized() if aim.length_squared() > 0.01 else Vector3.RIGHT
	action_elapsed = 0.0
	action_duration = duration
	action_ball = ball
	action_has_hit = false
	tackle_cooldown = cooldown
	close_control_remaining = 0.0
	control_stride_remaining = 0
	tackle_remaining = duration
	last_boot_world = visual_controller.right_boot.global_position
	if kind == "slide":
		body_collider.shape.height = 0.8
		body_collider.position.y = 0.43
		apply_central_impulse(action_direction * mass * 2.0)
	elif kind == "standing":
		apply_central_impulse(action_direction * mass * 0.4)
	return true

func _update_challenge() -> void:
	if action_kind == "":
		return
	var boot_world: Vector3 = visual_controller.right_boot.global_position
	if not action_has_hit and is_instance_valid(action_ball):
		if action_kind == "kick":
			if action_elapsed >= kick_contact_time - 0.015 and action_elapsed <= kick_contact_time + 0.045:
				var contact_distance := _boot_distance(action_ball.global_position, last_boot_world, boot_world)
				if contact_distance <= FootballBall.RADIUS + 0.095:
					var target := action_direction * kick_strength + Vector3.UP * kick_lift
					var incoming := action_ball.linear_velocity
					# Preserve part of incoming motion instead of replacing the trajectory.
					var impulse := (target - incoming * 0.85) * action_ball.mass
					action_ball.touch(team, player_id, impulse, Vector3(0, -FootballBall.RADIUS * 0.35, 0))
					action_ball.control_block_remaining = 0.3
					action_has_hit = true
					completed_kicks += 1
					last_kick_contact_distance = contact_distance
					match_touches += 1
					strike_contact.emit(kick_kind)
		elif action_kind == "shoulder":
			if action_elapsed >= 0.04:
				for other in get_colliding_bodies():
					if other is FootballPlayer and other.team != team:
						var offset: Vector3 = other.global_position - global_position
						offset.y = 0
						if offset.length() < 0.92 and absf(offset.normalized().dot(action_direction)) < 0.8:
							var impulse := offset.normalized() * minf(mass, other.mass) * 3.1
							other.apply_central_impulse(impulse)
							apply_central_impulse(-impulse)
							other.stagger_remaining = 0.3
							other.close_control_remaining = 0.0
							if other.reach_ball(action_ball):
								action_ball.control_block_remaining = 0.25
							action_has_hit = true
							challenge_contacts += 1
							break
		else:
			var active := action_elapsed >= (0.08 if action_kind == "slide" else 0.05) and action_elapsed <= (0.50 if action_kind == "slide" else 0.2)
			if active and _boot_distance(action_ball.global_position, last_boot_world, boot_world) <= FootballBall.RADIUS + 0.12:
				action_ball.touch(team, player_id, action_direction * (3.8 if action_kind == "slide" else 2.6))
				action_ball.control_block_remaining = 0.4 if action_kind == "slide" else 0.3
				action_has_hit = true
				challenge_contacts += 1
				match_touches += 1
	last_boot_world = boot_world
	if action_elapsed >= action_duration:
		recovery_remaining = 0.65 if action_kind == "slide" else (0.0 if action_kind == "kick" else 0.25)
		body_collider.shape.height = 1.65
		body_collider.position.y = 0.86
		action_kind = ""

func _boot_distance(point: Vector3, start: Vector3, end: Vector3) -> float:
	var segment := end - start
	var t := clampf((point - start).dot(segment) / maxf(segment.length_squared(), 0.000001), 0, 1)
	return point.distance_to(start + segment * t)

func reset_action() -> void:
	# Restarts reset action state as well as transforms, including a lowered slide.
	action_kind = ""
	action_elapsed = 0
	tackle_remaining = 0
	tackle_cooldown = 0
	recovery_remaining = 0
	stagger_remaining = 0
	close_control_remaining = 0
	control_stride_remaining = 0
	jockey = false
	shield_direction = Vector3.ZERO
	dribble_active = false
	dribble_elapsed = 0
	dribble_has_hit = false
	dribble_ball = null
	body_collider.shape.height = 1.65
	body_collider.position.y = 0.86
