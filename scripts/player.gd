class_name FootballPlayer
extends RigidBody3D

signal strike_contact(kind: String)
signal dribble_contact
signal physical_event(kind: String, detail: Dictionary)

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
var kick_power := 0.0
var kick_start_boot := Vector3.ZERO
var kick_plant_world := Vector3.ZERO
var kick_plant_start := Vector3.ZERO
var kick_target_world := Vector3.ZERO
var kick_run_velocity := Vector3.ZERO
var kick_committed := false
var shot_preparation := 0.0
var strike_delta := 1.0 / 120.0
var last_strike_speed := 0.0
var last_strike_quality := 0.0
var kick_curve := 0.0
var team_role := ""
var team_target := Vector3.ZERO
var run_requested := 0.0
var support_requested := 0.0
var incoming_pass_from := ""
var incoming_pass_remaining := 0.0
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
var dribble_right := true
var last_dribble_right := false
var dribble_technique := "push"
var left_dribble_contacts := 0
var right_dribble_contacts := 0
var last_dribble_boot := Vector3.ZERO
var balance_skill := 1.0
var agility_skill := 1.0
var hop_active := false
var hop_elapsed := 0.0
var hop_cooldown := 0.0
var hop_launched := false
var hop_landing_remaining := 0.0
var hop_landing_impact := 0.0
var hop_previous_vertical := 0.0
var ragdoll: FootballPlayerRagdoll
var getting_up := false
var slide_victims: Array[int] = []
var slide_entry_speed := 0.0
var grab_target: FootballPlayer
var grab_held := false
var grab_right := true
var grab_rest_length := 0.0
var last_grab_force := Vector3.ZERO
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
	incoming_pass_remaining = maxf(0, incoming_pass_remaining - delta)
	hop_landing_remaining = maxf(0, hop_landing_remaining - delta)
	run_requested = maxf(0, run_requested - delta)
	support_requested = maxf(0, support_requested - delta)
	strike_delta = delta
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
			hop_landing_remaining = 0.24
			hop_landing_impact = clampf(absf(hop_previous_vertical) / 4, 0.3, 1)
			physical_event.emit("land", {})
		hop_previous_vertical = linear_velocity.y
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
		if action_kind == "kick" and not action_has_hit:
			_update_kick_target()
	if dribble_active:
		dribble_elapsed += delta
		if not dribble_has_hit and is_instance_valid(dribble_ball) and can_control(dribble_ball):
			# A foot can track a nearby moving ball during its approach. It does not
			# track or pull the ball after contact, or when the ball leaves reach.
			var time_to_contact := maxf(0, dribble_contact_time - dribble_elapsed)
			dribble_target_offset = dribble_ball.global_position - global_position + (dribble_ball.linear_velocity - linear_velocity) * time_to_contact
			dribble_target_offset.y = clampf(dribble_target_offset.y, 0.075, 0.28)
			if dribble_technique == "trap":
				dribble_target_offset.y += 0.05
	active_seconds += delta
	if sprint and intent.length_squared() > 0.1:
		energy = maxf(0.0, energy - delta * 0.07 / stamina_trait)
	else:
		energy = minf(1.0, energy + delta * 0.05 * stamina_trait)
	ring.visible = selected
	name_label.visible = selected
	visual_controller.animate(self, delta)
	_update_dribble_contact()
	_update_body_challenge(delta)
	_update_challenge()

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if ragdoll != null:
		return
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
		# A committed slide loses speed through ground friction, never steering
		# or accelerating back up after hitting a body or the boards.
		state.apply_central_force(-horizontal.normalized() * mass * 5.5 if horizontal.length() > 0.12 else -horizontal * mass / state.step)
		return
	elif action_kind == "kick":
		if not action_has_hit and action_elapsed <= kick_contact_time:
			# Keep the run-up through the strike. Braking at button release made
			# the free ball outrun the planted leg, especially during a sprint.
			desired = kick_run_velocity
			if is_instance_valid(action_ball):
				var gap := action_ball.global_position - global_position
				gap.y = 0
				if gap.length() > 0.62:
					desired += gap.normalized() * minf((gap.length() - 0.62) * 5, 2)
		else:
			desired *= 0.35
	elif action_kind == "standing":
		desired = action_direction * 1.8
	elif action_kind in ["shoulder", "push", "grab"]:
		desired *= 0.65
	elif recovery_remaining > 0.0:
		desired *= 0.3
	var acceleration := (desired - horizontal) * 7.5
	# The cap preserves collision response and prevents instant direction changes.
	state.apply_central_force(acceleration.limit_length(24.0) * mass * (0.2 if hop_launched and hop_active else 1.0))

func hop() -> bool:
	if not upright_ready() or hop_cooldown > 0 or global_position.y > 0.12 or absf(linear_velocity.y) > 0.6:
		return false
	hop_active = true
	visual_controller.begin_hop(self)
	hop_launched = false
	hop_elapsed = 0
	hop_previous_vertical = 0
	hop_cooldown = 1.15 / agility_skill
	dribble_active = false
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
	if instability > resistance:
		_release_grab("fall")
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
	if ragdoll != null or hop_active:
		return false
	var difference := ball.global_position - global_position
	difference.y = 0
	return difference.length() < distance and ball.global_position.y < 0.75

func kick(ball: FootballBall, direction: Vector3, strength: float, lift: float, kind: String = "", curve: float = 0) -> bool:
	if not upright_ready():
		return false
	if kick_cooldown > 0.0 or action_kind != "" or recovery_remaining > 0.0 or stagger_remaining > 0.0 or not reach_ball(ball):
		return false
	# Queue a short wind-up. Only the visible boot's contact window can strike.
	action_kind = "kick"
	dribble_active = false
	action_direction = Vector3(direction.x, 0, direction.z).normalized()
	kick_kind = kind if kind != "" else ("shot" if strength >= 15.0 else "pass")
	kick_strength = strength
	kick_lift = lift
	kick_curve = curve
	if kick_kind == "finesse":
		kick_curve = 1 if curve == 0 else curve
	elif kick_kind == "outside":
		kick_curve = -1 if curve == 0 else curve
	kick_power = clampf((strength - 12) / 11, 0, 1)
	kick_contact_time = lerpf(0.17, 0.22, kick_power) if kick_kind == "shot" else 0.10
	if kick_kind in ["finesse", "outside", "chip"]:
		kick_contact_time = 0.18
	elif kick_kind == "power":
		kick_contact_time = lerpf(0.28, 0.35, kick_power)
	action_duration = kick_contact_time + 0.36 if kick_kind == "shot" else 0.32
	if kick_kind in ["finesse", "outside", "power", "chip"]:
		action_duration = kick_contact_time + 0.36
	kick_start_boot = visual_controller.right_boot.global_position
	kick_plant_start = visual_controller.left_boot.global_position
	kick_plant_world = global_position - action_direction.cross(Vector3.UP) * 0.12 + action_direction * 0.08 + Vector3.UP * 0.075
	kick_run_velocity = Vector3(linear_velocity.x, 0, linear_velocity.z)
	kick_committed = false
	shot_preparation = 0
	action_elapsed = 0
	action_ball = ball
	action_has_hit = false
	_update_kick_target()
	kick_cooldown = action_duration + 0.10
	close_control_remaining = 0.0
	control_stride_remaining = 0
	touch_cooldown = action_duration
	last_boot_world = visual_controller.right_boot.global_position
	return true

func loft(ball: FootballBall, direction: Vector3, distance: float, high: bool = false, kind: String = "lob") -> bool:
	# Solve a launch arc once; gravity/drag/collisions own the rest of its flight.
	var apex := 4.0 if high else 3.0
	var rise := sqrt(2 * 9.8 * (apex - FootballBall.RADIUS))
	var flight := 2 * rise / 9.8
	return kick(ball, direction, clampf(distance / flight * 1.15, 5, 18), rise, kind)

func _update_kick_target() -> void:
	if not is_instance_valid(action_ball):
		return
	if not kick_committed:
		var time_left := maxf(0, kick_contact_time - action_elapsed)
		var velocity := action_ball.linear_velocity
		# Re-plan only the preparation from current visible physics state. The
		# final swing commits; collisions after commitment can still cause misses.
		kick_target_world = action_ball.global_position + velocity * time_left
		if action_ball.global_position.y > FootballBall.RADIUS + 0.045:
			kick_target_world.y -= 0.5 * 9.8 * time_left * time_left
		kick_target_world.y = maxf(FootballBall.RADIUS, kick_target_world.y)
		kick_plant_world = kick_target_world - action_direction * 0.48 - action_direction.cross(Vector3.UP) * 0.12
		kick_plant_world.y = global_position.y + 0.075
		kick_committed = action_elapsed >= kick_contact_time * 0.62
	# Keep a committed WORLD target fixed when the player's physical root moves.
	kick_target_offset = kick_target_world - global_position

func can_control(ball: FootballBall) -> bool:
	if kick_cooldown > 0.0 or action_kind != "" or recovery_remaining > 0.0 or stagger_remaining > 0.0 or ball.control_block_remaining > 0.0 or not reach_ball(ball, CONTROL_REACH):
		return false
	if ball.global_position.y > 0.4:
		return false
	var relative_velocity := Vector3(ball.linear_velocity.x - linear_velocity.x, 0, ball.linear_velocity.z - linear_velocity.z)
	# Receiving allows a faster cushioning contact, still through the swept boot.
	return relative_velocity.length() <= (12.0 if incoming_pass_remaining > 0 else 6.2)

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
	var local_ball: Vector3 = body_visual.basis.inverse() * relative
	if absf(local_ball.x) > 0.09:
		dribble_right = local_ball.x > 0
	else:
		var left_distance := visual_controller.left_boot.global_position.distance_to(ball.global_position)
		var right_distance := visual_controller.right_boot.global_position.distance_to(ball.global_position)
		dribble_right = right_distance < left_distance - 0.08 if absf(left_distance - right_distance) > 0.08 else not last_dribble_right
	var local_aim: Vector3 = body_visual.basis.inverse() * intent
	dribble_technique = "trap" if stick < 0.05 else "inside" if turning and local_aim.x * (1 if dribble_right else -1) < 0 else "outside" if turning else "push"
	dribble_elapsed = 0
	dribble_duration = 0.16 if turning else (0.26 if sprint and energy > 0.05 else 0.22)
	dribble_contact_time = 0.05 if turning else 0.065
	dribble_has_hit = false
	dribble_ball = ball
	dribble_target_offset = ball.global_position - global_position + (ball.linear_velocity - linear_velocity) * dribble_contact_time
	var boot: Node3D = visual_controller.right_boot if dribble_right else visual_controller.left_boot
	dribble_start_foot_offset = boot.global_position - global_position
	dribble_target_offset.y = clampf(dribble_target_offset.y, 0.075, 0.28)
	if dribble_technique == "trap":
		dribble_target_offset.y += 0.05
	dribble_follow_direction = intent.normalized() if stick > 0.05 else relative.normalized()
	close_control_ball = ball
	close_control_remaining = dribble_duration + 0.12
	last_dribble_boot = boot.global_position
	return false # Scheduling a swing is not a ball touch.

func _update_dribble_contact() -> void:
	if not dribble_active:
		return
	var boot_world: Vector3 = visual_controller.right_boot.global_position if dribble_right else visual_controller.left_boot.global_position
	if action_kind != "" or not is_instance_valid(dribble_ball) or stagger_remaining > 0 or recovery_remaining > 0:
		dribble_active = false
		return
	if not dribble_has_hit and dribble_elapsed >= dribble_contact_time - 0.008 and dribble_elapsed <= dribble_contact_time + 0.055:
		if dribble_ball.control_candidate_id == player_id and can_control(dribble_ball) and _boot_distance(dribble_ball.global_position, last_dribble_boot, boot_world) < FootballBall.RADIUS + 0.12:
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
			last_dribble_right = dribble_right
			if dribble_right:
				right_dribble_contacts += 1
			else:
				left_dribble_contacts += 1
			match_touches += 1
			dribble_contact.emit()
	last_dribble_boot = boot_world
	if dribble_elapsed >= dribble_duration:
		dribble_active = false
		touch_cooldown = 0

func tackle(ball: FootballBall) -> bool:
	return _begin_challenge("standing", ball, 0.26, 0.85)

func slide(ball: FootballBall) -> bool:
	return _begin_challenge("slide", ball, 0.68, 1.6)

func shoulder(ball: FootballBall) -> bool:
	return _begin_challenge("shoulder", ball, 0.24, 0.9)

func push(ball: FootballBall) -> bool:
	return _begin_challenge("push", ball, 0.34, 1.0)

func grab(ball: FootballBall) -> bool:
	if energy < 0.15 or not _begin_challenge("grab", ball, 0.72, 1.4):
		return false
	grab_target = null
	grab_held = true
	last_grab_force = Vector3.ZERO
	return true

func _hand(right: bool) -> Vector3:
	var elbow: Node3D = visual_controller.right_elbow if right else visual_controller.left_elbow
	return elbow.to_global(Vector3(0, -0.26, 0))

func _body_contact() -> FootballPlayer:
	for node in get_parent().get_children():
		if not node is FootballPlayer or node == self or node.team == team or node.ragdoll != null or node.hop_active:
			continue
		var offset: Vector3 = node.global_position - global_position
		offset.y = 0
		if offset.length() > 1.1 or offset.normalized().dot(action_direction) < 0.35:
			continue
		var chest: Vector3 = node.global_position + Vector3.UP * 1.12
		for right in [false, true]:
			if _hand(right).distance_to(chest) <= 0.44:
				grab_right = right
				return node
	return null

func _release_grab(reason: String) -> void:
	if is_instance_valid(grab_target):
		physical_event.emit("grab_release", {"victim": grab_target.player_id, "reason": reason})
	grab_target = null
	grab_held = false

func _update_body_challenge(delta: float) -> void:
	if action_kind not in ["push", "grab"]:
		if is_instance_valid(grab_target):
			_release_grab("interrupted")
		return
	if action_kind == "grab" and not grab_held:
		_release_grab("button_release")
		action_elapsed = action_duration
		return
	if not action_has_hit and action_elapsed >= 0.10 and action_elapsed <= 0.28:
		var other := _body_contact()
		if other != null:
			action_has_hit = true
			challenge_contacts += 1
			if action_kind == "push":
				var direction := other.global_position - global_position
				direction.y = 0
				var effective_mass := mass * other.mass / (mass + other.mass)
				var speed := 2.8 * lerpf(0.75, 1.0, energy) + maxf(0, (linear_velocity - other.linear_velocity).dot(direction.normalized())) * 0.3
				var impulse := direction.normalized() * effective_mass * speed
				other.receive_slide(impulse, _hand(grab_right), speed)
				apply_central_impulse(-impulse)
				energy = maxf(0, energy - 0.04)
				physical_event.emit("push_contact", {"victim": other.player_id, "speed": speed})
			else:
				grab_target = other
				grab_rest_length = _hand(grab_right).distance_to(other.global_position + Vector3.UP * 1.12)
				physical_event.emit("grab_contact", {"victim": other.player_id})
	if action_kind != "grab" or not is_instance_valid(grab_target):
		return
	var separation := grab_target.global_position - global_position
	separation.y = 0
	var relative := grab_target.linear_velocity - linear_velocity
	var break_speed := 3.0 * grab_target.balance_skill * lerpf(0.7, 1.0, energy)
	if separation.length() > 1.12 or relative.length() > break_speed or grab_target.ragdoll != null or grab_target.hop_active or energy < 0.08 or action_elapsed >= action_duration:
		_release_grab("physical_break" if action_elapsed < action_duration else "duration")
		return
	var gap := grab_target.global_position + Vector3.UP * 1.12 - _hand(grab_right)
	var direction := gap.normalized()
	var effective_mass := mass * grab_target.mass / (mass + grab_target.mass)
	var tension := maxf(0, (gap.length() - grab_rest_length) * 28 + relative.dot(direction) * 2)
	var force := direction * minf(effective_mass * tension, minf(mass, grab_target.mass) * 9)
	last_grab_force = force
	grab_target.apply_central_force(-force)
	apply_central_force(force)
	energy = maxf(0, energy - delta * 0.18 / stamina_trait)

func _begin_challenge(kind: String, ball: FootballBall, duration: float, cooldown: float) -> bool:
	if not upright_ready():
		return false
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
	slide_victims.clear()
	last_boot_world = visual_controller.right_boot.global_position
	if kind == "slide":
		visual_controller.begin_slide(self)
		body_collider.shape.height = 0.8
		body_collider.position.y = 0.43
		slide_entry_speed = clampf(Vector3(linear_velocity.x, 0, linear_velocity.z).dot(action_direction) + 2.0, 2.0, 8.5)
		var launch := action_direction * slide_entry_speed - Vector3(linear_velocity.x, 0, linear_velocity.z)
		apply_central_impulse(launch * mass)
	elif kind == "standing":
		apply_central_impulse(action_direction * mass * 0.4)
	return true

func _update_challenge() -> void:
	if action_kind == "":
		return
	var boot_world: Vector3 = visual_controller.right_boot.global_position
	if action_kind == "slide" and action_elapsed >= 0.08 and action_elapsed <= 0.50:
		_slide_player_contacts(boot_world)
	if not action_has_hit and is_instance_valid(action_ball):
		if action_kind == "kick":
			if action_elapsed >= kick_contact_time - 0.015 and action_elapsed <= kick_contact_time + 0.045:
				var contact_distance := _boot_distance(action_ball.global_position, last_boot_world, boot_world)
				if contact_distance <= FootballBall.RADIUS + 0.095:
					var target := action_direction * kick_strength + Vector3.UP * kick_lift
					last_strike_speed = maxf(0, ((boot_world - last_boot_world) / maxf(strike_delta, 0.001) - linear_velocity).dot(action_direction))
					last_strike_quality = 1.0
					if kick_kind in ["shot", "finesse", "outside", "power", "chip"]:
						# Swing speed and how centrally the swept boot meets the ball
						# affect the strike. No impulse without the visible boot contact.
						last_strike_quality = lerpf(1.0, 0.78, clampf(contact_distance / (FootballBall.RADIUS + 0.095), 0, 1))
						var transfer := clampf(last_strike_speed / 15.0, 0.75, 1.12) * last_strike_quality
						target *= transfer
					var incoming := action_ball.linear_velocity
					# Preserve part of incoming motion instead of replacing the trajectory.
					var impulse := (target - incoming * 0.85) * action_ball.mass
					var contact_offset := Vector3(0, -FootballBall.RADIUS * clampf(kick_lift / 7, 0.04, 0.35), 0)
					action_ball.touch(team, player_id, impulse, contact_offset)
					if absf(kick_curve) > 0:
						# Signed vertical angular momentum creates opposite physical curls.
						var inertia := 0.4 * action_ball.mass * FootballBall.RADIUS * FootballBall.RADIUS
						action_ball.apply_torque_impulse(Vector3.UP * inertia * 48 * clampf(kick_curve, -1, 1))
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
		elif action_kind in ["slide", "standing"]:
			var active := action_elapsed >= (0.08 if action_kind == "slide" else 0.05) and action_elapsed <= (0.50 if action_kind == "slide" else 0.2)
			if active and _boot_distance(action_ball.global_position, last_boot_world, boot_world) <= FootballBall.RADIUS + 0.12:
				action_ball.touch(team, player_id, action_direction * (3.8 if action_kind == "slide" else 2.6))
				action_ball.control_block_remaining = 0.4 if action_kind == "slide" else 0.3
				action_has_hit = true
				challenge_contacts += 1
				match_touches += 1
	last_boot_world = boot_world
	if action_elapsed >= action_duration:
		if action_kind == "grab":
			_release_grab("duration")
		recovery_remaining = 0.65 if action_kind == "slide" else (0.0 if action_kind == "kick" else 0.25)
		body_collider.shape.height = 1.65
		body_collider.position.y = 0.86
		action_kind = ""

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
	_release_grab("restart")
	incoming_pass_from = ""
	incoming_pass_remaining = 0
	hop_landing_remaining = 0
	shot_preparation = 0
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
	body_collider.shape.height = 1.65
	body_collider.position.y = 0.86
