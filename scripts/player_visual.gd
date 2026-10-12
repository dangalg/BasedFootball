class_name FootballPlayerVisual
extends RefCounted

var left_knee: Node3D
var right_knee: Node3D
var left_arm: Node3D
var right_arm: Node3D
var left_elbow: Node3D
var right_elbow: Node3D
var upper_body: Node3D
var right_boot: Node3D
var left_boot: Node3D
var head_pivot: Node3D
var gait_blend := 0.0
var previous_velocity := Vector3.ZERO

func build(player: Node3D) -> void:
	player.body_visual = Node3D.new()
	player.body_visual.name = "AthleteVisual"
	player.add_child(player.body_visual)
	var model: Node3D = player.body_visual
	var jersey := FootballArt.material(Color("3689cf") if player.team == 0 else Color("db7059"))
	var shorts := FootballArt.material(Color("203b55") if player.team == 0 else Color("51343d"))
	var skin := FootballArt.material([Color("c89470"), Color("8f6248"), Color("d6ab88")][player.shirt_number % 3])
	var socks := FootballArt.material(Color("d5dfdc"))
	var boots := FootballArt.material(Color("17252c"), 0.5)
	var hair := FootballArt.material([Color("302925"), Color("493426"), Color("211e1c")][player.shirt_number % 3])
	FootballArt.contact_shadow(player, 1.4)
	FootballArt.tailored_mesh(model, [Vector3(0.88, 0.001, 0.001), Vector3(0.88, 0.16, 0.105), Vector3(1.01, 0.165, 0.115), Vector3(1.16, 0.19, 0.13), Vector3(1.33, 0.235, 0.14), Vector3(1.40, 0.25, 0.12), Vector3(1.45, 0.22, 0.10), Vector3(1.49, 0.075, 0.065), Vector3(1.49, 0.001, 0.001)], jersey)
	FootballArt.tailored_mesh(model, [Vector3(0.79, 0.001, 0.001), Vector3(0.79, 0.185, 0.12), Vector3(0.97, 0.18, 0.11), Vector3(0.97, 0.001, 0.001)], shorts)
	head_pivot = Node3D.new()
	head_pivot.name = "HeadPivot"
	model.add_child(head_pivot)
	head_pivot.position.y = 1.52
	FootballArt.cylinder(head_pivot, 0.048, 0.11, Vector3.ZERO, skin)
	FootballArt.circle(model, 0.06, Vector3(0, 1.49, 0), shorts, 0.012)
	var head := FootballArt.sphere(head_pivot, 0.13, Vector3(0, 0.16, 0), skin)
	head.scale = Vector3(0.88, 1.05, 0.94)
	var jaw := FootballArt.sphere(head_pivot, 0.091, Vector3(0, 0.105, -0.021), skin)
	jaw.scale = Vector3(0.92, 0.66, 0.92)
	var cap := FootballArt.sphere(head_pivot, 0.132, Vector3(0, 0.238, 0.014), hair)
	cap.scale = Vector3(0.89, 0.48, 0.94)
	if player.shirt_number % 3 == 0:
		cap.scale.y = 0.28
	elif player.shirt_number % 3 == 1:
		FootballArt.sphere(head_pivot, 0.066, Vector3(-0.037, 0.26, -0.04), hair).scale = Vector3(1.2, 0.55, 1)
	FootballArt.box(head_pivot, Vector3(0.035, 0.005, 0.008), Vector3(0, 0.105, -0.105), FootballArt.material(Color("855342")))
	FootballArt.sphere(head_pivot, 0.022, Vector3(0, 0.15, -0.121), skin).scale = Vector3(0.7, 1, 1)
	for side in [-1.0, 1.0]:
		FootballArt.sphere(head_pivot, 0.027, Vector3(side * 0.114, 0.15, 0), skin).scale = Vector3(0.6, 1, 0.8)
		FootballArt.sphere(head_pivot, 0.009, Vector3(side * 0.04, 0.186, -0.112), hair)
		FootballArt.box(head_pivot, Vector3(0.026, 0.005, 0.009), Vector3(side * 0.04, 0.203, -0.113), hair)
	upper_body = Node3D.new()
	upper_body.name = "TorsoPivot"
	upper_body.position.y = 0.88
	# A hip pivot lets the torso lean independently of the feet and pelvis.
	var upper_parts := model.get_children()
	model.add_child(upper_body)
	for part in upper_parts:
		var original_position: Vector3 = part.position
		part.reparent(upper_body, false)
		part.position = original_position - upper_body.position
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.name = "LeftArm" if side < 0 else "RightArm"
		upper_body.add_child(arm)
		arm.position = Vector3(side * 0.245, 0.52, 0)
		arm.rotation.z = side * 0.15
		FootballArt.capsule(arm, 0.065, 0.19, Vector3(0, -0.07, 0), jersey)
		FootballArt.tailored_mesh(arm, [Vector3(-0.28, 0.035, 0.036), Vector3(-0.23, 0.046, 0.045), Vector3(-0.13, 0.057, 0.055), Vector3(-0.04, 0.047, 0.05), Vector3(0, 0.001, 0.001)], skin)
		var elbow := Node3D.new()
		elbow.name = "LeftElbow" if side < 0 else "RightElbow"
		arm.add_child(elbow)
		elbow.position.y = -0.27
		FootballArt.tailored_mesh(elbow, [Vector3(-0.23, 0.027, 0.029), Vector3(-0.18, 0.033, 0.035), Vector3(-0.08, 0.044, 0.041), Vector3(0, 0.036, 0.036)], skin)
		FootballArt.sphere(elbow, 0.048, Vector3(0, -0.26, 0), skin).scale = Vector3(0.66, 1.1, 0.48)
		FootballArt.capsule(elbow, 0.013, 0.047, Vector3(-side * 0.029, -0.249, -0.008), skin).rotation.z = side * 0.45
		var leg := Node3D.new()
		leg.name = "LeftLeg" if side < 0 else "RightLeg"
		model.add_child(leg)
		leg.position = Vector3(side * 0.105, 0.88, 0)
		FootballArt.capsule(leg, 0.09, 0.24, Vector3(0, -0.06, 0), shorts)
		FootballArt.tailored_mesh(leg, [Vector3(-0.42, 0.045, 0.047), Vector3(-0.35, 0.055, 0.052), Vector3(-0.21, 0.08, 0.073), Vector3(-0.08, 0.085, 0.075), Vector3(0, 0.001, 0.001)], skin)
		var knee := Node3D.new()
		knee.name = "LeftKnee" if side < 0 else "RightKnee"
		leg.add_child(knee)
		knee.position.y = -0.41
		FootballArt.tailored_mesh(knee, [Vector3(-0.35, 0.033, 0.04), Vector3(-0.27, 0.039, 0.047), Vector3(-0.14, 0.062, 0.057), Vector3(-0.04, 0.052, 0.049), Vector3(0, 0.045, 0.047)], socks)
		FootballArt.cylinder(knee, 0.059, 0.03, Vector3(0, -0.06, 0), jersey)
		var boot := Node3D.new()
		boot.name = "Boot"
		knee.add_child(boot)
		boot.position = Vector3(0, -0.34, 0)
		FootballArt.sphere(boot, 0.10, Vector3(0, 0, -0.05), boots).scale = Vector3(0.62, 0.48, 1.3)
		FootballArt.box(boot, Vector3(0.12, 0.014, 0.24), Vector3(0, -0.045, -0.055), shorts)
		for lace in range(3):
			FootballArt.box(boot, Vector3(0.06, 0.006, 0.009), Vector3(0, 0.035, -0.045 - lace * 0.02), socks)
		if side < 0:
			player.left_leg = leg
			left_knee = knee
			left_arm = arm
			left_elbow = elbow
			left_boot = boot
		else:
			player.right_leg = leg
			right_knee = knee
			right_arm = arm
			right_elbow = elbow
			right_boot = boot
	var number := FootballArt.text(upper_body, str(player.shirt_number), Vector3(0, 0.40, 0.135), 44, Color("e6eee1"))
	number.pixel_size = 0.0045
	number.outline_size = 0
	number.rotation.y = PI
	FootballArt.box(upper_body, Vector3(0.09, 0.045, 0.014), Vector3(-0.115, 0.49, -0.123), socks)
	for side in [-1.0, 1.0]:
		FootballArt.box(upper_body, Vector3(0.018, 0.23, 0.012), Vector3(side * 0.156, 0.27, -0.105), shorts)
	player.ring = FootballArt.circle(player, 0.65, Vector3(0, 0.05, 0), FootballArt.marker(Color("e9c463")), 0.045)
	player.ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	player.name_label = FootballArt.text(player, player.player_name, Vector3(0, 2.07, 0), 22, Color("f4df99"))
	player.name_label.pixel_size = 0.009
	player.name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	player.name_label.no_depth_test = true

func animate(player: Node3D, delta: float) -> void:
	var previous_leg_rotation: Quaternion = player.right_leg.quaternion
	var previous_knee_rotation: Quaternion = right_knee.quaternion
	var velocity := Vector3(player.linear_velocity.x, 0, player.linear_velocity.z)
	var facing: Vector3 = player.action_direction if player.action_kind != "" else player.aim
	# Intent can reverse before momentum does. Face the actual running direction
	# rather than playing a forward run while travelling away from the face.
	if player.action_kind == "" and not player.jockey and velocity.length() > 0.65:
		facing = velocity.normalized()
	if player.action_kind == "kick":
		facing = Vector3(player.kick_target_offset.x, 0, player.kick_target_offset.z).normalized()
	if facing.length_squared() > 0.1:
		player.body_visual.rotation.y = lerp_angle(player.body_visual.rotation.y, atan2(-facing.x, -facing.z), 12.0 * delta)
	var local_velocity: Vector3 = player.body_visual.basis.inverse() * velocity
	var sliding: bool = player.action_kind == "slide"
	var standing: bool = player.action_kind == "standing"
	var shoulder: bool = player.action_kind == "shoulder"
	var kicking: bool = player.action_kind == "kick"
	var touching: bool = player.dribble_active
	var touch_weight := 0.0
	if touching:
		if player.dribble_elapsed <= player.dribble_contact_time:
			touch_weight = smoothstep(0, player.dribble_contact_time, player.dribble_elapsed)
		else:
			touch_weight = 1 - smoothstep(player.dribble_contact_time + 0.025, player.dribble_duration - 0.01, player.dribble_elapsed)
	var rising: bool = not sliding and player.body_visual.position.y < -0.25 and player.recovery_remaining > 0
	player.body_visual.rotation.x = 0
	player.body_visual.rotation.z = 0
	var lower := smoothstep(0, 0.10, player.action_elapsed) if sliding else 0.0
	var hip_offset := -0.55 * lower if sliding else -0.06 - absf(sin(player.step_phase)) * 0.018 * gait_blend
	if kicking:
		hip_offset = -0.22 * smoothstep(0, 0.06, player.action_elapsed)
	elif standing:
		hip_offset = -0.20 * sin(clampf(player.action_elapsed / player.action_duration, 0, 1) * PI)
	elif player.controlling_ball():
		hip_offset = -0.20
	elif rising:
		hip_offset = -0.55 * smoothstep(0, 0.65, player.recovery_remaining)
	player.body_visual.position.y = lerpf(player.body_visual.position.y, hip_offset, minf(1, delta * 12))
	var acceleration := (velocity - previous_velocity) / maxf(delta, 0.001)
	previous_velocity = velocity
	var local_acceleration: Vector3 = player.body_visual.basis.inverse() * acceleration
	upper_body.rotation.x = lerpf(upper_body.rotation.x, 0.85 if sliding or rising else local_velocity.z * 0.022 + clampf(local_acceleration.z * 0.008, -0.12, 0.12) - (0.18 if standing or kicking else 0.0), minf(1, 18 * delta))
	upper_body.rotation.z = lerpf(upper_body.rotation.z, -0.22 if shoulder else -local_velocity.x * 0.025, minf(1, 12 * delta))
	# Jockeying can intentionally backpedal while looking at the ball.
	var gait_direction := -1.0 if local_velocity.z > 0.1 else 1.0
	player.step_phase += velocity.length() * delta * 2.7 * gait_direction
	var stride := minf(velocity.length() * 0.085, 0.6)
	var left_swing := sin(player.step_phase) * stride
	var right_swing := -left_swing
	player.left_leg.rotation = Vector3(left_swing, 0, 0)
	player.right_leg.rotation = Vector3(right_swing, 0, 0)
	left_knee.rotation = Vector3(-maxf(0, -left_swing) * 1.1, 0, 0)
	right_knee.rotation = Vector3(-maxf(0, -right_swing) * 1.1, 0, 0)
	left_boot.rotation = Vector3.ZERO
	right_boot.rotation = Vector3.ZERO
	left_arm.rotation.x = -0.5 if sliding else -left_swing * 0.7
	right_arm.rotation.x = -0.5 if sliding else -right_swing * 0.7
	# The athlete faces local -Z. Positive X flexion bends the forearms forward;
	# a negative angle bent both elbows towards the back of the torso.
	left_elbow.rotation.x = 0.6 + stride * 0.3
	right_elbow.rotation.x = 0.6 + stride * 0.3
	# Stance travels opposite local motion at ground height; swing lifts the toe.
	# Both legs use the same IK and boot transforms as physical contact checks.
	gait_blend = move_toward(gait_blend, clampf(velocity.length() / 0.8, 0, 1), delta * 7)
	if not sliding and not standing and not kicking and not rising:
		_gait_foot(player, false, fposmod(player.step_phase / TAU, 1), local_velocity)
		_gait_foot(player, true, fposmod(player.step_phase / TAU + 0.5, 1), local_velocity)
	if kicking or standing or rising:
		_pose_foot(player, false, player.global_position + player.body_visual.basis * Vector3(-0.12, 0.075, 0.04))
	elif touching:
		_pose_foot(player, false, player.global_position + player.body_visual.basis * Vector3(-0.12, 0.075, 0.04), touch_weight)
	if rising:
		_pose_foot(player, true, player.global_position + player.body_visual.basis * Vector3(0.12, 0.075, -0.04))
	if sliding:
		var direction: Vector3 = player.action_direction
		var lateral := direction.cross(Vector3.UP)
		_pose_foot(player, true, player.global_position + direction * 0.72 + Vector3.UP * 0.085)
		_pose_foot(player, false, player.global_position + direction * 0.28 - lateral * 0.17 + Vector3.UP * 0.13)
	elif standing:
		var extension := sin(clampf(player.action_elapsed / 0.26, 0, 1) * PI)
		_pose_foot(player, true, player.global_position + player.action_direction * lerpf(0.12, 0.68, extension) + Vector3.UP * 0.095)
	elif player.action_kind == "kick":
		var contact: Vector3 = player.global_position + player.kick_target_offset
		var backswing: Vector3 = player.body_visual.to_global(Vector3(0.105, 0.18, 0.26))
		var target: Vector3
		if player.action_elapsed <= player.kick_contact_time:
			target = backswing.lerp(contact, smoothstep(0, player.kick_contact_time, player.action_elapsed))
		else:
			var follow := smoothstep(player.kick_contact_time, player.action_duration, player.action_elapsed)
			target = contact + player.action_direction * 0.22 * follow + Vector3.UP * 0.24 * follow
		_pose_foot(player, true, target)
	elif touching:
		var swing := smoothstep(0, player.dribble_contact_time, player.dribble_elapsed)
		var offset: Vector3 = player.dribble_start_foot_offset.lerp(player.dribble_target_offset, swing)
		if player.dribble_elapsed > player.dribble_contact_time:
			var follow := smoothstep(player.dribble_contact_time, player.dribble_duration, player.dribble_elapsed)
			offset += player.dribble_follow_direction * 0.12 * follow + Vector3.UP * sin(follow * PI) * 0.06
		_pose_foot(player, true, player.global_position + offset, touch_weight)
	if player.hop_active and player.hop_elapsed > 0.08:
		_pose_foot(player, false, player.global_position + player.body_visual.basis * Vector3(-0.12, 0.26, -0.12))
		_pose_foot(player, true, player.global_position + player.body_visual.basis * Vector3(0.12, 0.30, -0.18))
		left_arm.rotation.x = 0.45
		right_arm.rotation.x = 0.45
	if kicking:
		left_arm.rotation.x = -0.25
		right_arm.rotation.x = 0.35
		upper_body.rotation.y = sin(clampf(player.action_elapsed / player.action_duration, 0, 1) * PI) * -0.18
	else:
		upper_body.rotation.y = lerpf(upper_body.rotation.y, sin(player.step_phase) * stride * 0.09, minf(1, delta * 10))
	if player.stagger_remaining > 0:
		upper_body.rotation.z += sin(player.stagger_remaining * 14) * 0.12
	if player.getting_up:
		var rise := smoothstep(0, 0.85 / player.agility_skill, player.ragdoll.recovery_time)
		player.body_visual.position.y = lerpf(-0.5, 0, rise)
		upper_body.rotation.x = lerpf(-0.55, 0, rise)
		_pose_foot(player, false, player.global_position + player.body_visual.basis * Vector3(-0.14, 0.075, 0.10))
		_pose_foot(player, true, player.global_position + player.body_visual.basis * Vector3(0.14, 0.075, -0.15))
	if player.action_kind == "":
		# Bound joint angular velocity across re-planned touches and gait changes.
		# Kicks/challenges retain their contact poses; dribble contact checks observe
		# the smoothed boot, so smoothing cannot manufacture an invisible touch.
		player.right_leg.quaternion = _limit_rotation(previous_leg_rotation, player.right_leg.quaternion, delta * 18)
		right_knee.quaternion = _limit_rotation(previous_knee_rotation, right_knee.quaternion, delta * 18)

func _limit_rotation(previous: Quaternion, target: Quaternion, max_angle: float) -> Quaternion:
	var angle := previous.angle_to(target)
	return previous.slerp(target, minf(1, max_angle / maxf(angle, 0.00001)))

func _gait_foot(player: Node3D, right: bool, phase: float, local_velocity: Vector3) -> void:
	var travel := local_velocity.normalized() if local_velocity.length() > 0.05 else Vector3.FORWARD
	var reach := minf(local_velocity.length() * 0.075, 0.42) * gait_blend
	var along := lerpf(reach, -reach, phase / 0.6) if phase < 0.6 else lerpf(-reach, reach, smoothstep(0.6, 1, phase))
	var lift := 0.0 if phase < 0.6 else sin((phase - 0.6) / 0.4 * PI) * lerpf(0.07, 0.21, clampf(local_velocity.length() / 8, 0, 1)) * gait_blend
	var target := Vector3(0.105 if right else -0.105, 0.075 + lift, 0) + travel * along
	_pose_foot(player, right, player.global_position + player.body_visual.basis * target)

func _pose_foot(player: Node3D, right: bool, target_world: Vector3, weight: float = 1.0) -> void:
	# Two-bone leg pose. The contact checker uses this same animated boot.
	var leg: Node3D = player.right_leg if right else player.left_leg
	var knee: Node3D = right_knee if right else left_knee
	var boot: Node3D = right_boot if right else left_boot
	var target: Vector3 = player.body_visual.to_local(target_world)
	var offset: Vector3 = target - leg.position
	var distance := clampf(offset.length(), 0.12, 0.749)
	var direction: Vector3 = offset.normalized()
	var pole: Vector3 = Vector3.FORWARD - direction * Vector3.FORWARD.dot(direction)
	if pole.length_squared() < 0.001:
		pole = Vector3.UP - direction * Vector3.UP.dot(direction)
	var along := (0.41 * 0.41 + distance * distance - 0.34 * 0.34) / (2 * distance)
	var height := sqrt(maxf(0, 0.41 * 0.41 - along * along))
	var joint: Vector3 = direction * along + pole.normalized() * height
	var hip_rotation := Quaternion(Vector3.DOWN, joint.normalized())
	var lower: Vector3 = direction * distance - joint
	var knee_rotation := Quaternion(Vector3.DOWN, (Basis(hip_rotation).inverse() * lower).normalized())
	var boot_rotation := (Basis(hip_rotation) * Basis(knee_rotation)).inverse().get_rotation_quaternion()
	leg.quaternion = leg.quaternion.slerp(hip_rotation, weight)
	knee.quaternion = knee.quaternion.slerp(knee_rotation, weight)
	boot.quaternion = boot.quaternion.slerp(boot_rotation, weight)
