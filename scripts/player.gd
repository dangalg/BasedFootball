class_name FootballPlayer
extends RigidBody3D

signal strike_contact(kind: String)
signal dribble_contact
signal physical_event(kind: String, detail: Dictionary)

const CONTROL_REACH := 0.95
const FOOT_DISTANCE := 0.61
const TOUCH_STRIDE_TIME := 0.13
const BOOT_TOUCH_REACH := FootballBall.RADIUS + 0.12
const RECEIVE_PREPARE_REACH := 1.45
const CHASE_MAX_DISTANCE := 3.0
const CHASE_MEMORY_SECONDS := 1.6
const MAX_KICK_IMPULSE := 18.0

var team: int = 0
var player_id: String = ""
var player_name: String = ""
var shirt_number: int = 7
var role: String = ""
var is_goalkeeper: bool = false
var pending_receiver_id: String = ""
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
var jockey: bool = false
var shield_direction := Vector3.ZERO
var kick_strength: float = 0.0
var kick_lift: float = 0.0
var kick_kind: String = "pass"
var kick_target_offset := Vector3.ZERO
var kick_contact_time: float = 0.0
var kick_foot_right: bool = true
var kick_start_foot_offset := Vector3.ZERO
var last_kick_ball_world := Vector3.ZERO
var last_kick_boot_gap: float = -1.0
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
var dribble_foot_right: bool = true
var preferred_touch_foot_right: bool = true
var dribble_trap: bool = false
var dribble_phase: String = "idle"
var dribble_follow_end: float = 0.0
var chase_ball: FootballBall
var chase_remaining: float = 0.0
var chase_touch_serial: int = -1
var chase_peak_gap: float = 0.0
var chase_contact_gap: float = 0.0
var chase_direction := Vector3.RIGHT
var stop_stride_remaining: float = 0.0
var stop_stride_direction := Vector3.ZERO
var stop_stride_speed: float = 0.0
var stop_stride_start := Vector3.ZERO
var previous_intent_magnitude: float = 0.0
var completed_dribble_contacts := 0
var receiving_active: bool = false
var receiving_ball: FootballBall
var completed_receive_contacts: int = 0
var last_receive_contact_frame: int = -1000
var dribble_is_receive: bool = false
var last_dribble_ball_world := Vector3.ZERO
var last_control_reason: String = "idle"
var last_control_boot_gap: float = -1.0
var last_control_reach_gap: float = -1.0
var last_control_contact_interval: float = 0.0
var last_control_contact_frame: int = -1
var control_attempts: int = 0
var control_misses: int = 0
var control_reach_rejections: int = 0
var control_brake_predictions: int = 0
var balance_skill := 1.0
var agility_skill := 1.0
var hop_active := false
var hop_elapsed := 0.0
var hop_cooldown := 0.0
var hop_launched := false
var ragdoll: FootballPlayerRagdoll
var getting_up := false
var slide_victims: Array[int] = []
var ai_rng := RandomNumberGenerator.new()
var ai_lane_offset := 0.0
var ai_style := 0.5

func _ready() -> void:
	ai_rng.randomize()
	ai_style = ai_rng.randf_range(0.25, 0.75)
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
	hop_cooldown = maxf(0, hop_cooldown - delta)
	if ragdoll != null:
		ring.visible = selected
		name_label.visible = selected
		if getting_up:
			visual_controller.animate(self, delta)
		return
	if hop_active:
		hop_elapsed += delta
		if not hop_launched and hop_elapsed >= 0.08:
			hop_launched = true
			apply_central_impulse(Vector3.UP * mass * (3.9 + (agility_skill - 1) * 0.5))
		if hop_launched and hop_elapsed > 0.28 and global_position.y < 0.10 and linear_velocity.y <= 0:
			hop_active = false
			physical_event.emit("land", {})
	kick_cooldown = maxf(0.0, kick_cooldown - delta)
	tackle_cooldown = maxf(0.0, tackle_cooldown - delta)
	touch_cooldown = maxf(0.0, touch_cooldown - delta)
	tackle_remaining = maxf(0.0, tackle_remaining - delta)
	close_control_remaining = maxf(0.0, close_control_remaining - delta)
	recovery_remaining = maxf(0.0, recovery_remaining - delta)
	stagger_remaining = maxf(0.0, stagger_remaining - delta)
	control_stride_remaining = maxf(0.0, control_stride_remaining - delta)
	chase_remaining = maxf(0.0, chase_remaining - delta)
	stop_stride_remaining = maxf(0.0, stop_stride_remaining - delta)
	var stick_magnitude := intent.length()
	if stick_magnitude > 0.05:
		stop_stride_remaining = 0
	elif previous_intent_magnitude > 0.05 and is_instance_valid(chase_ball) and chasing_ball(chase_ball) and _flat(chase_ball.global_position - global_position).length() <= 1.35:
		# Finish at most a short catch-up stride on release. There is no remote
		# ball trap, and any new direction immediately takes back movement.
		var momentum := _flat(linear_velocity)
		if momentum.length() > 1.0:
			stop_stride_remaining = 0.40
			stop_stride_direction = momentum.normalized()
			stop_stride_speed = momentum.length()
			stop_stride_start = global_position
	if _flat(global_position - stop_stride_start).length() > 2.8:
		stop_stride_remaining = 0
	previous_intent_magnitude = stick_magnitude
	if is_instance_valid(chase_ball) and chasing_ball(chase_ball):
		chase_peak_gap = maxf(chase_peak_gap, _flat(chase_ball.global_position - global_position).length())
	elif dribble_phase == "free_chase":
		dribble_phase = "idle"
	if action_kind != "":
		action_elapsed += delta
	if action_kind == "kick" and not action_has_hit and is_instance_valid(action_ball):
		kick_target_offset = _predicted_contact_offset(action_ball, maxf(0, kick_contact_time - action_elapsed))
		kick_target_offset.y = clampf(kick_target_offset.y, 0.06, 0.55)
	if dribble_active:
		dribble_elapsed += delta
		var tracking_allowed: bool = _can_receive(dribble_ball) if dribble_is_receive else (is_instance_valid(dribble_ball) and can_control(dribble_ball))
		if not dribble_has_hit and tracking_allowed:
			# A foot can track a nearby moving ball during its approach. It does not
			# track or pull the ball after contact, or when the ball leaves reach.
			var time_to_contact := maxf(0, dribble_contact_time - dribble_elapsed)
			dribble_target_offset = _predicted_contact_offset(dribble_ball, time_to_contact)
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
	if ragdoll != null:
		return
	var horizontal := Vector3(state.linear_velocity.x, 0, state.linear_velocity.z)
	if stagger_remaining > 0.0:
		state.apply_central_force(-horizontal * mass * 1.5)
		return
	# Pace is unchanged. A touch temporarily shortens the stride; a released ball
	# immediately stops requiring those adjustments, for humans and AI alike.
	var desired := _running_target_velocity(control_stride_remaining)
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
	var acceleration := _running_acceleration(horizontal, desired)
	# The cap preserves collision response and prevents instant direction changes.
	state.apply_central_force(acceleration * mass * (0.2 if hop_launched and hop_active else 1.0))

func _running_target_velocity(stride_remaining: float, future_time: float = 0.0) -> Vector3:
	# Free chase uses normal running. Only an actual touch shortens a stride;
	# a short release stride can finish before the next physical stop contact.
	var speed := pace if sprint and energy > 0.05 else pace * 0.66
	if stride_remaining > 0:
		var stride_phase := clampf(stride_remaining / TOUCH_STRIDE_TIME, 0, 1)
		speed *= 1.0 - (0.18 if sprint else 0.32) * sin(PI * stride_phase)
	if jockey:
		speed *= 0.65
	if intent.length_squared() < 0.0025 and stop_stride_remaining > future_time and is_instance_valid(chase_ball) and chasing_ball(chase_ball):
		return stop_stride_direction * stop_stride_speed
	return intent.limit_length(1.0) * speed

func _running_acceleration(velocity: Vector3, desired: Vector3) -> Vector3:
	return ((desired - velocity) * 7.5).limit_length(24.0)

func _predict_running_displacement(duration: float) -> Vector3:
	# This is a prediction only. Collisions still determine the actual trajectory.
	var velocity := Vector3(linear_velocity.x, 0, linear_velocity.z)
	var displacement := Vector3.ZERO
	var stride_remaining := control_stride_remaining
	var elapsed := 0.0
	var damping := linear_damp
	if linear_damp_mode == RigidBody3D.DAMP_MODE_COMBINE:
		damping += float(ProjectSettings.get_setting("physics/3d/default_linear_damp", 0.1))
	while elapsed < duration - 0.00001:
		var step := minf(1.0 / float(Engine.physics_ticks_per_second), duration - elapsed)
		var desired := _running_target_velocity(stride_remaining, elapsed)
		if action_kind == "kick":
			desired *= 0.35
		velocity += _running_acceleration(velocity, desired) * step
		velocity *= maxf(0, 1.0 - damping * step)
		displacement += velocity * step
		stride_remaining = maxf(0, stride_remaining - step)
		elapsed += step
	return displacement

func _predicted_contact_offset(ball: FootballBall, delay: float) -> Vector3:
	var displacement := _predict_running_displacement(delay)
	var predicted_ball: Vector3 = ball.global_position + ball.linear_velocity * delay
	return predicted_ball - global_position - displacement

func _predicted_foot_gap(ball: FootballBall, delay: float, right: bool = true, hip_target: float = FootballPlayerVisual.CONTROL_HIP_OFFSET) -> float:
	var offset := _predicted_contact_offset(ball, delay)
	offset.y = clampf(offset.y, 0.06, 0.55) if is_equal_approx(hip_target, -0.22) else clampf(offset.y, 0.075, 0.28)
	var hip_shift := visual_controller.predicted_control_hip_shift(self, delay, hip_target)
	return visual_controller.foot_reach_gap(self, global_position + offset, right, hip_shift)

func _flat(value: Vector3) -> Vector3:
	return Vector3(value.x, 0, value.z)

func _boot(right: bool) -> Node3D:
	return visual_controller.right_boot if right else visual_controller.left_boot

func _choose_touch_foot(ball: FootballBall, delay: float, hip_target: float = FootballPlayerVisual.CONTROL_HIP_OFFSET) -> bool:
	var left_gap := _predicted_foot_gap(ball, delay, false, hip_target)
	var right_gap := _predicted_foot_gap(ball, delay, true, hip_target)
	if absf(left_gap - right_gap) > 0.045:
		return right_gap < left_gap
	var local_ball: Vector3 = body_visual.to_local(ball.global_position)
	if absf(local_ball.x) > 0.14:
		return local_ball.x > 0
	# Prefer the other foot after a real touch, with the current forward stride
	# resolving a first collection. The chosen foot stays fixed for this swing.
	if completed_dribble_contacts == 0 and absf(sin(step_phase)) > 0.35:
		return sin(step_phase) < 0
	return preferred_touch_foot_right

func chasing_ball(ball: FootballBall) -> bool:
	return is_instance_valid(ball) and ball == chase_ball and chase_remaining > 0 and ball.touch_serial == chase_touch_serial and ball.last_touch_id == player_id and ball.grip_holder_id.is_empty() and ragdoll == null and not hop_active and action_kind == "" and recovery_remaining <= 0 and stagger_remaining <= 0 and _flat(ball.global_position - global_position).length() <= CHASE_MAX_DISTANCE

func chase_target(ball: FootballBall) -> Vector3:
	if not is_instance_valid(ball):
		return global_position
	var velocity := _flat(ball.linear_velocity)
	var gap := _flat(ball.global_position - global_position).length()
	var horizon := clampf(gap / maxf(pace, 1.0), 0.06, 0.30)
	var travel := velocity * ((1.0 - exp(-0.62 * horizon)) / 0.62)
	var forward := velocity.normalized() if velocity.length() > 0.3 else chase_direction
	return ball.global_position + travel - forward * 0.50

func predict_strike_reach(ball: FootballBall, horizon: float = 0.18) -> bool:
	if not is_instance_valid(ball) or not upright_ready() or not ball.grip_holder_id.is_empty():
		return false
	for sample in range(5):
		var delay := maxf(0, horizon) * float(sample) / 4.0
		var right := _choose_touch_foot(ball, delay, -0.22)
		if ball.global_position.y + ball.linear_velocity.y * delay < 0.65 and _predicted_foot_gap(ball, delay, right, -0.22) <= FootballBall.RADIUS + 0.095:
			return true
	return false

func hop() -> bool:
	if not upright_ready() or hop_cooldown > 0 or global_position.y > 0.12 or absf(linear_velocity.y) > 0.6:
		return false
	hop_active = true
	hop_launched = false
	hop_elapsed = 0
	hop_cooldown = 1.15 / agility_skill
	dribble_active = false
	receiving_active = false
	close_control_remaining = 0
	energy = maxf(0, energy - 0.025)
	physical_event.emit("hop", {})
	return true

func upright_ready() -> bool:
	return ragdoll == null and not hop_active and action_kind == "" and recovery_remaining <= 0 and stagger_remaining <= 0

func receive_slide(impulse: Vector3, contact: Vector3, relative_speed: float) -> void:
	if ragdoll != null:
		return
	var horizontal := Vector3(linear_velocity.x, 0, linear_velocity.z)
	var lateral := absf(impulse.normalized().dot(body_visual.global_basis.x))
	var instability := relative_speed * (0.8 + lateral * 0.35) + horizontal.length() * 0.16
	var resistance := 4.0 * balance_skill * lerpf(0.8, 1.0, energy) * (1.12 if jockey else 1.0)
	close_control_remaining = 0
	dribble_active = false
	receiving_active = false
	if instability > resistance:
		action_kind = ""
		hop_active = false
		hop_launched = false
		body_collider.shape.height = 1.65
		body_collider.position.y = 0.86
		ragdoll = FootballPlayerRagdoll.new()
		get_parent().add_child(ragdoll)
		ragdoll.begin(self, impulse, contact)
	else:
		apply_impulse(impulse, contact - global_position)
		stagger_remaining = clampf(instability / resistance * 0.5, 0.10, 0.5)
		physical_event.emit("stumble", {"impact_speed": relative_speed})

func controlling_ball() -> bool:
	if ragdoll != null or hop_active:
		return false
	return close_control_remaining > 0.0 and is_instance_valid(close_control_ball) and close_control_ball.grip_holder_id == "" and close_control_ball.last_touch_id == player_id and reach_ball(close_control_ball, CONTROL_REACH) and close_control_ball.control_block_remaining <= 0.0

func reach_ball(ball: FootballBall, distance: float = CONTROL_REACH) -> bool:
	if ragdoll != null or hop_active:
		return false
	var difference := ball.global_position - global_position
	difference.y = 0
	return difference.length() < distance and ball.global_position.y < 0.75

func kick(ball: FootballBall, direction: Vector3, strength: float, lift: float, kind: String = "") -> bool:
	if not upright_ready():
		return false
	if not is_instance_valid(ball) or kick_cooldown > 0 or not ball.grip_holder_id.is_empty() or _flat(direction).length_squared() < 0.0001:
		return false
	# A loose or incoming ball can be struck. This queues a physical swing,
	# including a possible air miss; ownership and dribble speed are irrelevant.
	action_kind = "kick"
	dribble_active = false
	receiving_active = false
	chase_remaining = 0
	stop_stride_remaining = 0
	dribble_phase = "idle"
	action_direction = Vector3(direction.x, 0, direction.z).normalized()
	kick_kind = kind if kind != "" else ("shot" if strength >= 15.0 else "pass")
	kick_strength = strength
	kick_lift = lift
	kick_contact_time = 0.14 if kick_kind == "shot" else 0.10
	action_duration = 0.42 if kick_kind == "shot" else 0.32
	action_elapsed = 0
	action_ball = ball
	action_has_hit = false
	kick_foot_right = _choose_touch_foot(ball, kick_contact_time, -0.22)
	kick_start_foot_offset = _boot(kick_foot_right).global_position - global_position
	kick_target_offset = _predicted_contact_offset(ball, kick_contact_time)
	kick_target_offset.y = clampf(kick_target_offset.y, 0.06, 0.55)
	kick_cooldown = action_duration + 0.10
	close_control_remaining = 0.0
	control_stride_remaining = 0
	touch_cooldown = action_duration
	last_boot_world = _boot(kick_foot_right).global_position
	last_kick_ball_world = ball.global_position
	last_kick_boot_gap = -1
	return true

func can_control(ball: FootballBall) -> bool:
	if ball.grip_holder_id != "" or (ball.passer_block_id == player_id and ball.passer_block_remaining > 0):
		return false
	if kick_cooldown > 0.0 or action_kind != "" or recovery_remaining > 0.0 or stagger_remaining > 0.0 or ball.control_block_remaining > 0.0 or not reach_ball(ball, CONTROL_REACH):
		return false
	if ball.global_position.y > 0.4:
		return false
	var relative_velocity := Vector3(ball.linear_velocity.x - linear_velocity.x, 0, ball.linear_velocity.z - linear_velocity.z)
	return relative_velocity.length() <= 6.2

func dribble(ball: FootballBall) -> bool:
	if receiving_active or (ball.pass_active and ball.pass_receiver_id == player_id):
		return false
	if dribble_active or touch_cooldown > 0.0 or not can_control(ball):
		return false
	var relative := ball.global_position - global_position
	relative.y = 0
	var player_velocity := Vector3(linear_velocity.x, 0, linear_velocity.z)
	var ball_velocity := Vector3(ball.linear_velocity.x, 0, ball.linear_velocity.z)
	var stick := minf(intent.length(), 1.0)
	var requested := intent.normalized() if stick > 0.05 else Vector3.ZERO
	var turning := stick > 0.05 and chasing_ball(ball) and requested.dot(chase_direction) < 0.75
	var stopping := stick < 0.05
	if chasing_ball(ball) and not turning and not stopping:
		var closing_speed := (ball_velocity - player_velocity).dot(relative.normalized())
		var caught_up := relative.length() < 0.52 or (closing_speed < -0.12 and relative.length() <= chase_peak_gap - 0.12)
		if not caught_up:
			last_control_reason = "free_chase"
			return false
	# A settled ball needs no recurring impulses or foot animation.
	if ball.last_touch_id == player_id and stick < 0.05 and player_velocity.length() < 0.12 and ball_velocity.length() < 0.12 and relative.length() > 0.45 and relative.length() < 0.75:
		return false
	var contact_delay := 0.055 if turning or stopping else 0.075
	var foot_right := _choose_touch_foot(ball, contact_delay)
	var predicted_gap := _predicted_foot_gap(ball, contact_delay, foot_right)
	last_control_reach_gap = predicted_gap
	if predicted_gap > BOOT_TOUCH_REACH:
		last_control_reason = "predicted_foot_out_of_reach"
		control_reach_rejections += 1
		return false
	dribble_active = true
	dribble_is_receive = false
	dribble_foot_right = foot_right
	dribble_trap = turning or stopping
	dribble_phase = "prepare"
	dribble_elapsed = 0
	dribble_duration = contact_delay + 0.10
	dribble_follow_end = dribble_duration
	dribble_contact_time = contact_delay
	dribble_has_hit = false
	dribble_ball = ball
	dribble_target_offset = _predicted_contact_offset(ball, dribble_contact_time)
	dribble_start_foot_offset = _boot(dribble_foot_right).global_position - global_position
	dribble_target_offset.y = clampf(dribble_target_offset.y, 0.075, 0.28)
	dribble_follow_direction = intent.normalized() if stick > 0.05 else relative.normalized()
	close_control_ball = ball
	close_control_remaining = 0
	last_boot_world = _boot(dribble_foot_right).global_position
	last_dribble_ball_world = ball.global_position
	last_control_boot_gap = -1
	last_control_reason = "swing_scheduled"
	control_attempts += 1
	return false # Scheduling a swing is not a ball touch.

func _can_receive(ball: FootballBall) -> bool:
	if not is_instance_valid(ball) or not upright_ready() or kick_cooldown > 0 or touch_cooldown > 0:
		return false
	if ball.grip_holder_id != "" or ball.control_block_remaining > 0:
		return false
	if ball.passer_block_id == player_id and ball.passer_block_remaining > 0:
		return false
	if not ball.pass_active or ball.pass_receiver_id != player_id or ball.pass_team != team:
		return false
	if not reach_ball(ball, RECEIVE_PREPARE_REACH) or ball.global_position.y > 0.55:
		return false
	var relative_velocity := ball.linear_velocity - linear_velocity
	return Vector3(relative_velocity.x, 0, relative_velocity.z).length() <= 18.0

func receive(ball: FootballBall) -> bool:
	# A request is not a successful reception. The contact callback below is.
	if is_instance_valid(ball) and ball == receiving_ball and ball.last_touch_id == player_id and Engine.get_physics_frames() - last_receive_contact_frame <= 18:
		return true
	if receiving_active and receiving_ball == ball:
		return false
	if not _can_receive(ball):
		return false
	var relative := ball.global_position - global_position
	relative.y = 0
	var relative_velocity := ball.linear_velocity - linear_velocity
	var closing := maxf(0, -relative_velocity.dot(relative.normalized()))
	var delay := clampf((relative.length() - FOOT_DISTANCE) / maxf(closing, 1.0), 0.035, 0.12)
	var foot_right := _choose_touch_foot(ball, delay)
	var predicted_gap := _predicted_foot_gap(ball, delay, foot_right)
	last_control_reach_gap = predicted_gap
	if predicted_gap > BOOT_TOUCH_REACH:
		last_control_reason = "receive_foot_out_of_reach"
		control_reach_rejections += 1
		return false
	receiving_active = true
	receiving_ball = ball
	dribble_is_receive = true
	dribble_active = true
	dribble_foot_right = foot_right
	dribble_trap = true
	dribble_phase = "prepare"
	dribble_elapsed = 0
	dribble_contact_time = delay
	dribble_duration = delay + 0.16
	dribble_follow_end = dribble_duration
	dribble_has_hit = false
	dribble_ball = ball
	dribble_target_offset = _predicted_contact_offset(ball, delay)
	dribble_target_offset.y = clampf(dribble_target_offset.y, 0.075, 0.28)
	dribble_start_foot_offset = _boot(dribble_foot_right).global_position - global_position
	dribble_follow_direction = relative.normalized()
	last_boot_world = _boot(dribble_foot_right).global_position
	last_dribble_ball_world = ball.global_position
	last_control_boot_gap = -1
	last_control_reason = "receive_scheduled"
	control_attempts += 1
	return false

func _update_dribble_contact() -> void:
	if not dribble_active:
		return
	var boot_world: Vector3 = _boot(dribble_foot_right).global_position
	if action_kind != "" or not is_instance_valid(dribble_ball) or stagger_remaining > 0 or recovery_remaining > 0:
		dribble_active = false
		receiving_active = false
		last_control_reason = "swing_interrupted"
		dribble_phase = "idle"
		return
	if not dribble_has_hit and dribble_elapsed >= dribble_contact_time - 0.008 and dribble_elapsed <= dribble_contact_time + 0.055:
		var contact_gap := _moving_boot_distance(last_dribble_ball_world, dribble_ball.global_position, last_boot_world, boot_world)
		last_control_boot_gap = contact_gap if last_control_boot_gap < 0 else minf(last_control_boot_gap, contact_gap)
		var eligible := _can_receive(dribble_ball) if dribble_is_receive else can_control(dribble_ball)
		var assigned_receive := dribble_is_receive and eligible
		if (dribble_ball.control_candidate_id == player_id or assigned_receive) and eligible and contact_gap < BOOT_TOUCH_REACH:
			if dribble_is_receive:
				_cushion_receive(contact_gap)
			else:
				_apply_dribble_touch(contact_gap)
		elif not eligible:
			last_control_reason = "receive_no_longer_eligible" if dribble_is_receive else "control_no_longer_eligible"
		elif dribble_ball.control_candidate_id != player_id and not assigned_receive:
			last_control_reason = "another_control_candidate"
		else:
			last_control_reason = "boot_not_at_ball"
	last_boot_world = boot_world
	last_dribble_ball_world = dribble_ball.global_position
	if (not dribble_has_hit and dribble_elapsed >= dribble_duration) or (dribble_has_hit and dribble_elapsed >= dribble_follow_end):
		if not dribble_has_hit:
			control_misses += 1
			physical_event.emit("control_miss", {"receive": dribble_is_receive, "reason": last_control_reason, "minimum_boot_gap": last_control_boot_gap, "predicted_reach_gap": last_control_reach_gap})
		dribble_active = false
		receiving_active = false
		dribble_phase = "free_chase" if chasing_ball(dribble_ball) else "idle"

func _apply_dribble_touch(contact_gap: float) -> void:
	var velocity := Vector3(linear_velocity.x, 0, linear_velocity.z)
	var stick := minf(intent.length(), 1)
	var direction := intent.normalized() if stick > 0.05 else Vector3.ZERO
	if jockey and shield_direction.length_squared() > 0.1:
		direction = shield_direction
	dribble_trap = dribble_trap or stick <= 0.05 or (chasing_ball(dribble_ball) and direction.dot(chase_direction) < 0.75)
	var fast := sprint and energy > 0.05 and stick > 0.1
	var incoming := dribble_ball.linear_velocity
	var incoming_flat := _flat(incoming)
	var target_velocity := Vector3.ZERO
	if stick > 0.05:
		var base_speed := pace if fast else pace * 0.66
		var lead_speed := (1.8 if fast else 1.3) * stick
		var forward_speed := maxf(0, velocity.dot(direction))
		var push_speed := minf(base_speed * stick + lead_speed, maxf(0.9 * stick, forward_speed) + lead_speed)
		if dribble_trap:
			# A turn is a first touch into the new direction, not a full-speed
			# reversal. The finite impulse may leave incoming momentum to chase.
			push_speed = minf(push_speed, 1.2 + stick)
		target_velocity = direction * push_speed
	var impulse := ((target_velocity - incoming_flat) * dribble_ball.mass).limit_length(1.7 * touch_skill)
	dribble_ball.touch(team, player_id, impulse)
	preferred_touch_foot_right = not dribble_foot_right
	dribble_follow_direction = direction if direction.length_squared() > 0.01 else (-incoming_flat).normalized()
	var free_seconds := 0.20 if fast else 0.16
	touch_cooldown = free_seconds
	if stick > 0.05:
		_remember_free_ball(dribble_ball, direction)
	else:
		chase_remaining = 0
		stop_stride_remaining = 0
	if dribble_trap:
		control_brake_predictions += 1
	close_control_ball = dribble_ball
	close_control_remaining = TOUCH_STRIDE_TIME
	_finish_control_contact(contact_gap, "dribble_contact")
	physical_event.emit("dribble_touch", {"foot": "right" if dribble_foot_right else "left", "direction": _vector(direction), "impulse": _vector(impulse), "ball_velocity_before": _vector(incoming), "predicted_velocity_after": _vector(incoming + impulse / dribble_ball.mass), "player_velocity": _vector(velocity), "touch_serial": dribble_ball.touch_serial, "phase": dribble_phase, "kind": "trap" if dribble_trap else "push", "trap": dribble_trap, "contact_gap": contact_gap, "minimum_free_chase_seconds": free_seconds})

func _remember_free_ball(ball: FootballBall, direction: Vector3) -> void:
	chase_ball = ball
	chase_remaining = CHASE_MEMORY_SECONDS
	chase_touch_serial = ball.touch_serial
	chase_contact_gap = _flat(ball.global_position - global_position).length()
	chase_peak_gap = chase_contact_gap
	chase_direction = direction

func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func _cushion_receive(contact_gap: float) -> void:
	var incoming := dribble_ball.linear_velocity
	var velocity := Vector3(linear_velocity.x, 0, linear_velocity.z)
	var direction := intent.normalized() if intent.length_squared() > 0.01 else (dribble_ball.global_position - global_position).normalized()
	direction.y = 0
	direction = direction.normalized()
	var target := velocity + direction * 0.65
	target.y = incoming.y * 0.35
	var impulse := ((target - incoming) * dribble_ball.mass).limit_length(4.5 * touch_skill)
	# Snapshot the flight identity before touch() ends that flight.
	var passer := dribble_ball.pass_passer_id
	var receiver := dribble_ball.pass_receiver_id
	var incoming_serial := dribble_ball.touch_serial
	dribble_ball.touch(team, player_id, impulse)
	apply_central_impulse(-impulse)
	receiving_active = false
	completed_receive_contacts += 1
	last_receive_contact_frame = Engine.get_physics_frames()
	close_control_ball = dribble_ball
	close_control_remaining = TOUCH_STRIDE_TIME
	dribble_follow_direction = direction
	preferred_touch_foot_right = not dribble_foot_right
	touch_cooldown = 0.12
	_remember_free_ball(dribble_ball, direction)
	_finish_control_contact(contact_gap, "receive_contact")
	physical_event.emit("receive_contact", {"passer": passer, "receiver": receiver, "foot": "right" if dribble_foot_right else "left", "incoming_touch_serial": incoming_serial, "touch_serial": dribble_ball.touch_serial, "boot_gap": contact_gap, "incoming_speed": incoming.length(), "incoming_velocity": _vector(incoming), "applied_impulse": _vector(impulse), "touch_skill": touch_skill})

func _finish_control_contact(contact_gap: float, reason: String) -> void:
	dribble_has_hit = true
	dribble_phase = "follow_through"
	dribble_follow_end = dribble_elapsed + 0.075
	dribble_target_offset = dribble_ball.global_position - global_position
	control_stride_remaining = TOUCH_STRIDE_TIME
	completed_dribble_contacts += 1
	match_touches += 1
	last_control_boot_gap = contact_gap
	last_control_reason = reason
	var frame := Engine.get_physics_frames()
	if last_control_contact_frame >= 0:
		last_control_contact_interval = float(frame - last_control_contact_frame) / float(Engine.physics_ticks_per_second)
	last_control_contact_frame = frame
	dribble_contact.emit()

func _moving_boot_distance(ball_start: Vector3, ball_end: Vector3, boot_start: Vector3, boot_end: Vector3) -> float:
	# Closest approach of the two actual movements during this physics tick.
	# Keeping the original contact radius avoids turning reception into a magnet.
	return _boot_distance(Vector3.ZERO, boot_start - ball_start, boot_end - ball_end)

func tackle(ball: FootballBall) -> bool:
	return _begin_challenge("standing", ball, 0.26, 0.85)

func slide(ball: FootballBall) -> bool:
	return _begin_challenge("slide", ball, 0.6, 1.6)

func shoulder(ball: FootballBall) -> bool:
	return _begin_challenge("shoulder", ball, 0.24, 0.9)

func _begin_challenge(kind: String, ball: FootballBall, duration: float, cooldown: float) -> bool:
	if not upright_ready():
		return false
	if tackle_cooldown > 0.0 or action_kind != "" or recovery_remaining > 0.0 or stagger_remaining > 0.0:
		return false
	action_kind = kind
	dribble_active = false
	receiving_active = false
	action_direction = aim.normalized() if aim.length_squared() > 0.01 else Vector3.RIGHT
	action_elapsed = 0.0
	action_duration = duration
	action_ball = ball
	action_has_hit = false
	tackle_cooldown = cooldown
	close_control_remaining = 0.0
	control_stride_remaining = 0
	tackle_remaining = duration
	slide_victims.clear()
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
	var boot_world: Vector3 = _boot(kick_foot_right).global_position if action_kind == "kick" else visual_controller.right_boot.global_position
	if action_kind == "slide" and action_elapsed >= 0.08 and action_elapsed <= 0.50:
		_slide_player_contacts(boot_world)
	if not action_has_hit and is_instance_valid(action_ball) and action_ball.grip_holder_id.is_empty():
		if action_kind == "kick":
			if action_elapsed >= kick_contact_time - 0.015 and action_elapsed <= kick_contact_time + 0.045:
				var contact_distance := _moving_boot_distance(last_kick_ball_world, action_ball.global_position, last_boot_world, boot_world)
				last_kick_boot_gap = contact_distance if last_kick_boot_gap < 0 else minf(last_kick_boot_gap, contact_distance)
				if contact_distance <= FootballBall.RADIUS + 0.095:
					var target := action_direction * kick_strength + Vector3.UP * kick_lift
					var incoming := action_ball.linear_velocity
					# Preserve part of incoming motion instead of replacing the trajectory.
					var impulse := ((target - incoming * 0.85) * action_ball.mass).limit_length(MAX_KICK_IMPULSE)
					action_ball.touch(team, player_id, impulse, Vector3(0, -FootballBall.RADIUS * 0.35, 0))
					if kick_kind in ["pass", "through", "lob"]:
						action_ball.passer_block_id = player_id
						action_ball.passer_block_remaining = 0.3
					else:
						action_ball.control_block_remaining = 0.3
					action_has_hit = true
					completed_kicks += 1
					last_kick_contact_distance = contact_distance
					kick_target_offset = action_ball.global_position - global_position
					match_touches += 1
					strike_contact.emit(kick_kind)
					physical_event.emit("kick_contact", {"foot": "right" if kick_foot_right else "left", "aim_direction": _vector(action_direction), "boot_gap": contact_distance, "incoming_velocity": _vector(incoming), "impulse": _vector(impulse), "predicted_velocity_after": _vector(incoming + impulse / action_ball.mass), "power": kick_strength, "kind": kick_kind, "touch_serial": action_ball.touch_serial})
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
	if action_kind == "kick" and is_instance_valid(action_ball):
		last_kick_ball_world = action_ball.global_position
	if action_elapsed >= action_duration:
		if action_kind == "kick" and not action_has_hit:
			physical_event.emit("kick_miss", {"foot": "right" if kick_foot_right else "left", "aim_direction": _vector(action_direction), "minimum_boot_gap": last_kick_boot_gap, "kind": kick_kind})
		recovery_remaining = 0.65 if action_kind == "slide" else (0.0 if action_kind == "kick" else 0.25)
		body_collider.shape.height = 1.65
		body_collider.position.y = 0.86
		action_kind = ""
		pending_receiver_id = ""

func _boot_distance(point: Vector3, start: Vector3, end: Vector3) -> float:
	var segment := end - start
	var t := clampf((point - start).dot(segment) / maxf(segment.length_squared(), 0.000001), 0, 1)
	return point.distance_to(start + segment * t)

func _slide_player_contacts(boot: Vector3) -> void:
	for node in get_parent().get_children():
		if not node is FootballPlayer or node == self or node.ragdoll != null or node.get_instance_id() in slide_victims:
			continue
		var other: FootballPlayer = node
		var closest := INF
		var contact := Vector3.ZERO
		for foot in [other.visual_controller.left_boot, other.visual_controller.right_boot]:
			for height in [0.0, 0.10, 0.20, 0.30]:
				var point: Vector3 = foot.global_position + Vector3.UP * height
				var distance := _boot_distance(point, last_boot_world, boot)
				if distance < closest:
					closest = distance
					contact = point
		if closest > 0.19:
			continue
		var separation := other.global_position - global_position
		separation.y = 0
		var direction := separation.normalized() if separation.length() > 0.01 else action_direction
		var relative := linear_velocity - other.linear_velocity
		var closing := maxf(0, relative.dot(direction))
		if closing < 0.4:
			continue
		slide_victims.append(other.get_instance_id())
		var effective_mass := mass * other.mass / (mass + other.mass)
		var impulse := direction * closing * effective_mass * 0.65
		other.receive_slide(impulse, contact, closing)
		apply_central_impulse(-impulse)
		physical_event.emit("slide_body_contact", {"victim": other.player_id, "speed": closing, "distance": closest})

func reset_action() -> void:
	if ragdoll != null:
		ragdoll.finish(true)
	getting_up = false
	hop_active = false
	hop_launched = false
	hop_elapsed = 0
	hop_cooldown = 0
	slide_victims.clear()
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
	receiving_active = false
	receiving_ball = null
	dribble_is_receive = false
	last_receive_contact_frame = -1000
	pending_receiver_id = ""
	last_control_reason = "reset"
	last_control_boot_gap = -1
	last_control_reach_gap = -1
	last_control_contact_frame = -1
	dribble_phase = "idle"
	dribble_trap = false
	chase_ball = null
	chase_remaining = 0
	chase_touch_serial = -1
	chase_peak_gap = 0
	chase_contact_gap = 0
	stop_stride_remaining = 0
	previous_intent_magnitude = 0
	body_collider.shape.height = 1.65
	body_collider.position.y = 0.86
