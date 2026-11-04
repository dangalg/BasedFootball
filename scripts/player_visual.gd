class_name FootballPlayerVisual
extends RefCounted

const CONTROL_HIP_OFFSET := -0.20
const HIP_RESPONSE := 12.0
const UPPER_ARM_LENGTH := 0.27
const HAND_LOCAL_CENTER := Vector3(0.0, -0.26, 0.0)
const GAIT_ANKLE_HEIGHT := 0.052
const GAIT_WALK_STEP_SECONDS := 0.27
const GAIT_RUN_STEP_SECONDS := 0.177
const KICK_FOLLOW_THROUGH_SECONDS := 0.075
const KICK_RECOVERY_STEP_SECONDS := 0.105

var left_knee: Node3D
var right_knee: Node3D
var left_arm: Node3D
var right_arm: Node3D
var left_elbow: Node3D
var right_elbow: Node3D
var upper_body: Node3D
var right_boot: Node3D
var left_boot: Node3D
const SOLE_LOCAL_CENTER := Vector3(0.0, -0.052, -0.055)
var _sole_planting := false
var _sole_plant_basis := Basis.IDENTITY
var _gait_active := false
var _gait_swing_foot := -1
var _gait_next_foot := 0
var _gait_progress := 0.0
var _gait_kick_step := false
var _gait_released_foot := -1
var _gait_release_start := 1.0
var _gait_swing_start := Vector3.ZERO
var _gait_swing_basis := Basis.IDENTITY
var _gait_last_root := Vector3.ZERO
var _gait_anchors: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _gait_bases: Array[Basis] = [Basis.IDENTITY, Basis.IDENTITY]
var _contact_support_foot := -1
var _contact_kicking := false
var _contact_last_elapsed := 0.0
var _contact_support_start := Vector3.ZERO
var _contact_support_start_basis := Basis.IDENTITY
var _contact_support_anchor := Vector3.ZERO
var _contact_support_basis := Basis.IDENTITY
var _contact_support_ready_at := 0.0
var _contact_support_released_at := -1.0
var _contact_support_planted := false
var _contact_last_root := Vector3.ZERO
var head_pivot: Node3D
var _celebration_start: Array[Quaternion] = []
var _tactical_marker: MeshInstance3D
var _tactical_kind := ""
static var _tactical_meshes: Dictionary = {}

func build(player: Node3D) -> void:
	player.body_visual = Node3D.new()
	player.body_visual.name = "AthleteVisual"
	player.add_child(player.body_visual)
	var model: Node3D = player.body_visual
	var jersey := FootballArt.material(Color("3689cf") if player.team == 0 else Color("db7059"))
	var shorts := FootballArt.material(Color("203b55") if player.team == 0 else Color("51343d"))
	var skin := FootballArt.material(Color("c89470") if player.shirt_number != 4 else Color("8f6248"))
	var socks := FootballArt.material(Color("d5dfdc"))
	var boots := FootballArt.material(Color("17252c"), 0.5)
	var hair := FootballArt.material(Color("302925"))
	FootballArt.contact_shadow(player, 1.4)
	FootballArt.tailored_mesh(model, [Vector3(0.88, 0.001, 0.001), Vector3(0.88, 0.17, 0.10), Vector3(1.01, 0.18, 0.11), Vector3(1.15, 0.185, 0.10), Vector3(1.33, 0.23, 0.13), Vector3(1.43, 0.245, 0.115), Vector3(1.49, 0.09, 0.07), Vector3(1.49, 0.001, 0.001)], jersey)
	FootballArt.tailored_mesh(model, [Vector3(0.79, 0.001, 0.001), Vector3(0.79, 0.185, 0.12), Vector3(0.97, 0.18, 0.11), Vector3(0.97, 0.001, 0.001)], shorts)
	head_pivot = Node3D.new()
	head_pivot.name = "HeadPivot"
	model.add_child(head_pivot)
	head_pivot.position.y = 1.52
	FootballArt.cylinder(head_pivot, 0.048, 0.11, Vector3.ZERO, skin)
	FootballArt.circle(model, 0.06, Vector3(0, 1.49, 0), shorts, 0.012)
	var head := FootballArt.sphere(head_pivot, 0.13, Vector3(0, 0.16, 0), skin)
	head.scale = Vector3(0.88, 1.05, 0.94)
	var cap := FootballArt.sphere(head_pivot, 0.132, Vector3(0, 0.238, 0.014), hair)
	cap.scale = Vector3(0.89, 0.48, 0.94)
	FootballArt.sphere(head_pivot, 0.022, Vector3(0, 0.15, -0.121), skin).scale = Vector3(0.7, 1, 1)
	for side in [-1.0, 1.0]:
		FootballArt.sphere(head_pivot, 0.027, Vector3(side * 0.114, 0.15, 0), skin).scale = Vector3(0.6, 1, 0.8)
		FootballArt.sphere(head_pivot, 0.009, Vector3(side * 0.04, 0.186, -0.112), hair)
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
		FootballArt.capsule(arm, 0.052, 0.28, Vector3(0, -0.14, 0), skin)
		var elbow := Node3D.new()
		elbow.name = "LeftElbow" if side < 0 else "RightElbow"
		arm.add_child(elbow)
		elbow.position.y = -UPPER_ARM_LENGTH
		FootballArt.capsule(elbow, 0.045, 0.25, Vector3(0, -0.12, 0), skin)
		FootballArt.sphere(elbow, 0.055, HAND_LOCAL_CENTER, skin).scale = Vector3(0.7, 1, 0.75)
		var leg := Node3D.new()
		leg.name = "LeftLeg" if side < 0 else "RightLeg"
		model.add_child(leg)
		leg.position = Vector3(side * 0.105, 0.88, 0)
		FootballArt.capsule(leg, 0.09, 0.24, Vector3(0, -0.06, 0), shorts)
		FootballArt.capsule(leg, 0.067, 0.39, Vector3(0, -0.21, 0), skin)
		var knee := Node3D.new()
		knee.name = "LeftKnee" if side < 0 else "RightKnee"
		leg.add_child(knee)
		knee.position.y = -0.41
		FootballArt.capsule(knee, 0.057, 0.37, Vector3(0, -0.17, 0), socks)
		FootballArt.cylinder(knee, 0.059, 0.03, Vector3(0, -0.06, 0), jersey)
		var boot := Node3D.new()
		boot.name = "Boot"
		knee.add_child(boot)
		boot.position = Vector3(0, -0.34, 0)
		FootballArt.sphere(boot, 0.10, Vector3(0, 0, -0.05), boots).scale = Vector3(0.62, 0.48, 1.3)
		FootballArt.box(boot, Vector3(0.12, 0.014, 0.24), Vector3(0, -0.045, -0.055), shorts)
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
	player.ring = FootballArt.circle(player, 0.65, Vector3(0, 0.05, 0), FootballArt.marker(Color("e9c463")), 0.045)
	player.ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	player.name_label = FootballArt.text(player, player.player_name, Vector3(0, 2.07, 0), 22, Color("f4df99"))
	player.name_label.pixel_size = 0.009
	player.name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	player.name_label.no_depth_test = true

func animate(player: Node3D, delta: float) -> void:
	if not _celebration_start.is_empty():
		_celebration_start.clear()
	var previous_leg_rotation: Quaternion = player.right_leg.quaternion
	var previous_knee_rotation: Quaternion = right_knee.quaternion
	var previous_left_leg_rotation: Quaternion = player.left_leg.quaternion
	var previous_left_knee_rotation: Quaternion = left_knee.quaternion
	var velocity := Vector3(player.linear_velocity.x, 0, player.linear_velocity.z)
	var kick_action: bool = player.action_kind == "kick"
	var since_impact: float = player.action_elapsed - player.kick_impact_time
	var kick_stepping: bool = kick_action and player.kick_impact_time >= 0.0 \
		and since_impact >= KICK_FOLLOW_THROUGH_SECONDS
	var kicking := kick_action and not kick_stepping
	var free_facing: bool = player.action_kind == "" or kick_stepping
	var facing: Vector3 = player.aim if free_facing else player.action_direction
	# Intent can reverse before momentum does. Face the actual running direction
	# rather than playing a forward run while travelling away from the face.
	if free_facing and not player.jockey and velocity.length() > 0.65:
		facing = velocity.normalized()
	if facing.length_squared() > 0.1:
		player.body_visual.rotation.y = lerp_angle(player.body_visual.rotation.y, atan2(-facing.x, -facing.z), 12.0 * delta)
	var local_velocity: Vector3 = player.body_visual.basis.inverse() * velocity
	var sliding: bool = player.action_kind == "slide"
	var standing: bool = player.action_kind == "standing"
	var shoulder: bool = player.action_kind == "shoulder"
	var touching: bool = player.dribble_active
	var sole_stopping: bool = touching and player.sole_stop_active and player.action_kind == "" and not player.hop_active
	var touch_weight := 0.0
	if touching:
		if not player.dribble_has_hit:
			touch_weight = smoothstep(0, player.dribble_contact_time, player.dribble_elapsed)
		else:
			touch_weight = 1 - smoothstep(player.dribble_follow_end - 0.075, player.dribble_follow_end, player.dribble_elapsed)
	var rising: bool = not sliding and player.body_visual.position.y < -0.25 and player.recovery_remaining > 0
	var upright_outfield: bool = player.eleven_slot >= 0 and not player.is_goalkeeper \
		and not rising and not player.hop_active and not player.getting_up and player.throw_in_phase < 0.0
	var grounded_gait: bool = upright_outfield and free_facing and not touching
	var coordinated_contact: bool = upright_outfield and (kicking or (player.action_kind == "" and touching and not sole_stopping))
	var strike_right: bool = player.kick_foot_right if kicking else player.dribble_foot_right
	var contact_elapsed: float = player.action_elapsed if kicking else player.dribble_elapsed
	var contact_time: float = player.kick_contact_time if kicking else player.dribble_contact_time
	if coordinated_contact:
		_prepare_contact_support(player, not strike_right, kicking, contact_elapsed, contact_time)
	elif not grounded_gait:
		_contact_support_foot = -1
		_contact_support_planted = false
	player.body_visual.rotation.x = 0
	player.body_visual.rotation.z = 0
	var lower := smoothstep(0, 0.10, player.action_elapsed) if sliding else 0.0
	var hip_offset := -0.55 * lower
	if kicking:
		hip_offset = -0.22 * smoothstep(0, 0.06, player.action_elapsed)
	elif standing:
		hip_offset = -0.20 * sin(clampf(player.action_elapsed / player.action_duration, 0, 1) * PI)
	elif touching:
		hip_offset = CONTROL_HIP_OFFSET * touch_weight
	elif rising:
		hip_offset = -0.55 * smoothstep(0, 0.65, player.recovery_remaining)
	elif grounded_gait:
		hip_offset = -lerpf(0.133, 0.186, smoothstep(0.15, 5.5, velocity.length()))
	player.body_visual.position.y = lerpf(player.body_visual.position.y, hip_offset, minf(1, delta * HIP_RESPONSE))
	# Jockeying can intentionally backpedal while looking at the ball.
	var gait_direction := -1.0 if local_velocity.z > 0.1 else 1.0
	if grounded_gait:
		_pose_grounded_gait(player, velocity, delta)
		_contact_support_foot = -1
		_contact_support_planted = false
	else:
		_gait_active = false
		player.step_phase += velocity.length() * delta * 2.7 * gait_direction
	var stride := minf(velocity.length() * 0.085, 0.6)
	var left_swing := sin(player.step_phase) * stride
	var right_swing := -left_swing
	if not grounded_gait:
		player.left_leg.rotation = Vector3(left_swing, 0, 0)
		player.right_leg.rotation = Vector3(right_swing, 0, 0)
		left_knee.rotation = Vector3(-maxf(0, -left_swing) * 1.1, 0, 0)
		right_knee.rotation = Vector3(-maxf(0, -right_swing) * 1.1, 0, 0)
		left_boot.rotation = Vector3.ZERO
		right_boot.rotation = Vector3.ZERO
	if grounded_gait or coordinated_contact:
		var weight := 0.0
		if coordinated_contact:
			var release: float = player.action_duration if kicking else player.dribble_follow_end
			weight = smoothstep(0.0, contact_time, contact_elapsed) * (1.0 - smoothstep(contact_time, release, contact_elapsed))
		_pose_outfield_balance(local_velocity, player.step_phase, strike_right, weight * (1.0 if kicking else 0.52), delta)
	else:
		upper_body.rotation.x = lerpf(upper_body.rotation.x, 0.85 if sliding or rising else local_velocity.z * 0.022 - (0.18 if standing or kicking else 0.0), minf(1, 18 * delta))
		upper_body.rotation.y = lerpf(upper_body.rotation.y, 0.0, minf(1, 12 * delta))
		upper_body.rotation.z = lerpf(upper_body.rotation.z, -0.22 if shoulder else -local_velocity.x * 0.025, minf(1, 12 * delta))
		left_arm.rotation = Vector3(-0.5 if sliding else -left_swing * 0.7, 0, -0.15)
		right_arm.rotation = Vector3(-0.5 if sliding else -right_swing * 0.7, 0, 0.15)
		left_elbow.rotation = Vector3(0.6 + stride * 0.3, 0, 0)
		right_elbow.rotation = Vector3(0.6 + stride * 0.3, 0, 0)
	if kicking and not coordinated_contact:
		var support_right: bool = not player.kick_foot_right
		_pose_foot(player, support_right, player.global_position + player.body_visual.basis * Vector3(0.12 if support_right else -0.12, 0.075, 0.04))
	elif standing or rising:
		_pose_foot(player, false, player.global_position + player.body_visual.basis * Vector3(-0.12, 0.075, 0.04))
	elif touching and not sole_stopping and not coordinated_contact:
		var support_right: bool = not player.dribble_foot_right
		_pose_foot(player, support_right, player.global_position + player.body_visual.basis * Vector3(0.12 if support_right else -0.12, 0.075, 0.04), touch_weight)
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
	elif kicking:
		var contact: Vector3 = player.global_position + player.kick_target_offset
		var start: Vector3 = player.global_position + player.kick_start_foot_offset
		var backswing: Vector3 = contact - player.action_direction * 0.22 + Vector3.UP * 0.12
		var target: Vector3
		if player.kick_impact_time >= 0.0:
			var follow := smoothstep(0.0, KICK_FOLLOW_THROUGH_SECONDS, since_impact)
			var extension := 1.0 if player.kick_kind == "shot" else 0.65
			target = contact + (player.action_direction * 0.19 + Vector3.UP * 0.16) * follow * extension
		elif player.action_elapsed <= player.kick_contact_time:
			var swing: float = player.action_elapsed / maxf(player.kick_contact_time, 0.00001)
			target = start.lerp(backswing, smoothstep(0, 0.35, swing)) if swing < 0.35 else backswing.lerp(contact, smoothstep(0.35, 1.0, swing))
		else:
			var follow := smoothstep(player.kick_contact_time, player.action_duration, player.action_elapsed)
			target = contact + player.action_direction * 0.22 * follow + Vector3.UP * 0.24 * follow
		_pose_foot(player, player.kick_foot_right, target)
	elif touching and not sole_stopping:
		var swing := smoothstep(0, player.dribble_contact_time, player.dribble_elapsed)
		var offset: Vector3 = player.dribble_start_foot_offset.lerp(player.dribble_target_offset, swing)
		if player.dribble_has_hit:
			var follow := smoothstep(player.dribble_follow_end - 0.075, player.dribble_follow_end, player.dribble_elapsed)
			offset += player.dribble_follow_direction * 0.12 * follow + Vector3.UP * sin(follow * PI) * 0.06
		_pose_foot(player, player.dribble_foot_right, player.global_position + offset, touch_weight)
	if player.hop_active and player.hop_elapsed > 0.08:
		_pose_foot(player, false, player.global_position + player.body_visual.basis * Vector3(-0.12, 0.26, -0.12))
		_pose_foot(player, true, player.global_position + player.body_visual.basis * Vector3(0.12, 0.30, -0.18))
		left_arm.rotation.x = 0.45
		right_arm.rotation.x = 0.45
	if player.stagger_remaining > 0:
		upper_body.rotation.z += sin(player.stagger_remaining * 14) * 0.12
	if player.getting_up:
		var rise := smoothstep(0, 0.85 / player.agility_skill, player.ragdoll.recovery_time)
		player.body_visual.position.y = lerpf(-0.5, 0, rise)
		upper_body.rotation.x = lerpf(-0.55, 0, rise)
		_pose_foot(player, false, player.global_position + player.body_visual.basis * Vector3(-0.14, 0.075, 0.10))
		_pose_foot(player, true, player.global_position + player.body_visual.basis * Vector3(0.14, 0.075, -0.15))
	if player.action_kind == "" and not grounded_gait:
		# Bound joint angular velocity across re-planned touches and gait changes.
		# Kicks/challenges retain their contact poses; dribble contact checks observe
		# the smoothed boot, so smoothing cannot manufacture an invisible touch.
		player.right_leg.quaternion = _limit_rotation(previous_leg_rotation, player.right_leg.quaternion, delta * 18)
		right_knee.quaternion = _limit_rotation(previous_knee_rotation, right_knee.quaternion, delta * 18)
		player.left_leg.quaternion = _limit_rotation(previous_left_leg_rotation, player.left_leg.quaternion, delta * 18)
		left_knee.quaternion = _limit_rotation(previous_left_knee_rotation, left_knee.quaternion, delta * 18)
	if sole_stopping:
		_pose_sole_stop(player, touch_weight)
	elif coordinated_contact:
		_pose_contact_support(player, velocity, contact_elapsed)
	_sole_planting = sole_stopping
	if player.throw_in_phase >= 0.0:
		_pose_throw_in(player, player.throw_in_phase)


func gait_plant_active(right: bool) -> bool:
	var foot := int(right)
	return _gait_active and _gait_swing_foot != foot and _gait_released_foot != foot


func contact_support_active(right: bool) -> bool:
	return _contact_support_planted and _contact_support_foot == int(right)


func _prepare_contact_support(player: Node3D, right: bool, kicking: bool, elapsed: float, contact_time: float) -> void:
	var foot := int(right)
	var new_contact := _contact_support_foot != foot or _contact_kicking != kicking or elapsed < _contact_last_elapsed
	_contact_last_elapsed = elapsed
	if not new_contact:
		return
	var boot := right_boot if right else left_boot
	var basis := _flat_body_basis(player)
	var displacement: Vector3 = player._predict_running_displacement(maxf(0.0, contact_time - elapsed), kicking)
	var stance: Vector3 = player.global_position + displacement + basis.x * (0.12 if right else -0.12)
	stance.y = GAIT_ANKLE_HEIGHT
	var previous_plant := gait_plant_active(right) or contact_support_active(right)
	var previous_anchor := _gait_anchors[foot] if gait_plant_active(right) else _contact_support_anchor
	var previous_basis := _gait_bases[foot] if gait_plant_active(right) else _contact_support_basis
	var keep_plant := previous_plant and stance.distance_squared_to(previous_anchor) <= 0.25 * 0.25
	_contact_support_foot = foot
	_contact_kicking = kicking
	_contact_support_start = boot.global_position
	_contact_support_start_basis = boot.global_basis.orthonormalized()
	_contact_support_anchor = previous_anchor if keep_plant else stance
	_contact_support_basis = previous_basis if keep_plant else basis
	_contact_support_ready_at = 0.0 if keep_plant else contact_time * 0.60
	_contact_support_released_at = -1.0


func _pose_contact_support(player: Node3D, velocity: Vector3, elapsed: float) -> void:
	var right := _contact_support_foot == 1
	var boot := right_boot if right else left_boot
	var hip: Node3D = player.right_leg if right else player.left_leg
	var plant_weight := smoothstep(0.0, _contact_support_ready_at, elapsed) if _contact_support_ready_at > 0.0 else 1.0
	var target := _contact_support_start.lerp(_contact_support_anchor, plant_weight)
	var boot_basis := _contact_support_start_basis.slerp(_contact_support_basis, plant_weight)
	# A plant only lasts while the support leg can reach it. The striking boot
	# still follows its original path and supplies the measured ball contact.
	if _contact_support_released_at < 0.0 and plant_weight >= 1.0 and hip.global_position.distance_to(target) > 0.743:
		_contact_support_released_at = elapsed
	_contact_support_planted = plant_weight >= 1.0 and _contact_support_released_at < 0.0
	if _contact_support_released_at >= 0.0:
		var facing := _flat_body_basis(player)
		var lift := smoothstep(0.0, 0.10, elapsed - _contact_support_released_at)
		var recovery: Vector3 = player.global_position + facing.x * (0.12 if right else -0.12) + velocity * 0.028
		recovery.y = GAIT_ANKLE_HEIGHT + 0.13
		target = _contact_support_anchor.lerp(recovery, lift)
		boot_basis = _contact_support_basis.slerp(facing * Basis(Vector3.RIGHT, -0.22), lift)
	_pose_foot(player, right, target)
	boot.global_basis = boot_basis
	_contact_last_root = player.global_position


func _pose_outfield_balance(velocity: Vector3, phase: float, strike_right: bool, strike_weight: float, delta: float) -> void:
	var run := clampf(velocity.length() / 6.3, 0.0, 1.0)
	var counter := sin(phase) * run * 0.72
	var strike_side := 1.0 if strike_right else -1.0
	var reaction := strike_side * strike_weight
	var weight := minf(1.0, delta * 19.0)
	upper_body.rotation.x = lerpf(upper_body.rotation.x, velocity.z * 0.033 - strike_weight * 0.16, weight)
	upper_body.rotation.y = lerpf(upper_body.rotation.y, -counter * 0.30 - reaction * 0.24, weight)
	upper_body.rotation.z = lerpf(upper_body.rotation.z, -velocity.x * 0.038 + reaction * 0.13, weight)
	left_arm.rotation = left_arm.rotation.lerp(Vector3(-counter + reaction * 0.46, 0, -0.14 - strike_weight * 0.33), weight)
	right_arm.rotation = right_arm.rotation.lerp(Vector3(counter - reaction * 0.46, 0, 0.14 + strike_weight * 0.33), weight)
	var bend := 0.62 + run * 0.56 - strike_weight * 0.20
	left_elbow.rotation.x = lerpf(left_elbow.rotation.x, bend - counter * 0.23, weight)
	right_elbow.rotation.x = lerpf(right_elbow.rotation.x, bend + counter * 0.23, weight)


func _pose_grounded_gait(player: Node3D, velocity: Vector3, delta: float) -> void:
	var root: Vector3 = player.global_position
	var facing := _flat_body_basis(player)
	var speed := velocity.length()
	var pace := smoothstep(0.7, 6.0, speed)
	var step_seconds := lerpf(GAIT_WALK_STEP_SECONDS, GAIT_RUN_STEP_SECONDS, pace)
	var feet: Array[Node3D] = [left_boot, right_boot]
	var homes: Array[Vector3] = []
	for foot in 2:
		var home := root + facing.x * (-0.115 if foot == 0 else 0.115)
		home.y = GAIT_ANKLE_HEIGHT
		homes.append(home)
	if not _gait_active or root.distance_squared_to(_gait_last_root) > 0.65 * 0.65:
		_gait_active = true
		_gait_swing_foot = -1
		_gait_released_foot = -1
		_gait_kick_step = false
		_gait_next_foot = 0 if feet[0].global_position.y >= feet[1].global_position.y else 1
		for foot in 2:
			var offset := feet[foot].global_position - homes[foot]
			offset.y = 0.0
			_gait_anchors[foot] = homes[foot] + offset.limit_length(0.22)
			_gait_bases[foot] = facing
		if _contact_support_foot >= 0 and root.distance_squared_to(_contact_last_root) < 0.65 * 0.65:
			var support := _contact_support_foot
			if _contact_support_planted and homes[support].distance_squared_to(_contact_support_anchor) < 0.36 * 0.36:
				_gait_anchors[support] = _contact_support_anchor
				_gait_bases[support] = _contact_support_basis
				_gait_next_foot = 1 - support
			if _contact_kicking and player.kick_impact_time >= 0.0:
				_gait_next_foot = 1 - support
				_gait_released_foot = _gait_next_foot
				_gait_kick_step = true
			elif feet[_gait_next_foot].global_position.y > GAIT_ANKLE_HEIGHT + 0.075:
				_gait_released_foot = _gait_next_foot
	_gait_last_root = root
	if _gait_swing_foot < 0:
		var next_foot := _gait_next_foot
		if _gait_released_foot >= 0:
			next_foot = _gait_released_foot
			_gait_swing_foot = next_foot
		elif speed <= 0.22:
			for foot in 2:
				if homes[foot].distance_squared_to(_gait_anchors[foot]) > 0.21 * 0.21 or facing.z.dot(_gait_bases[foot].z) < 0.82:
					next_foot = foot
					_gait_swing_foot = foot
					break
		else:
			_gait_swing_foot = next_foot
		if _gait_swing_foot >= 0:
			_gait_released_foot = -1
			_gait_release_start = 1.0
			_gait_progress = 0.0
			_gait_swing_start = feet[next_foot].global_position
			_gait_swing_start.y = maxf(_gait_swing_start.y, GAIT_ANKLE_HEIGHT)
			_gait_swing_basis = feet[next_foot].global_basis.orthonormalized()
	var swing_foot := _gait_swing_foot
	var swing_target := Vector3.ZERO
	var swing_basis := facing
	if swing_foot >= 0:
		var step_progress := delta / (KICK_RECOVERY_STEP_SECONDS if _gait_kick_step else step_seconds)
		_gait_progress = minf(1.0, _gait_progress + step_progress)
		# Land ahead of the hips so the next support step travels over the boot.
		var landing := homes[swing_foot] + (velocity * step_seconds * 0.49).limit_length(0.43)
		var blend := smoothstep(0.0, 1.0, _gait_progress)
		swing_target = _gait_swing_start.lerp(landing, blend)
		var swing_clearance := 0.025 if _gait_kick_step else lerpf(0.075, 0.20, pace)
		swing_target.y += sin(_gait_progress * PI) * swing_clearance
		swing_basis = _gait_swing_basis.slerp(facing, blend)
		player.step_phase = (float(swing_foot) + _gait_progress) * PI
		var support := 1 - swing_foot
		var support_gap := homes[support].distance_to(_gait_anchors[support])
		# Release the heel before the trailing leg exhausts its reach.
		var sprint_toe_off := speed > 4.8 and _gait_progress >= lerpf(0.93, 0.72, pace)
		if _gait_released_foot < 0 and (sprint_toe_off or support_gap > 0.405):
			_gait_released_foot = support
			_gait_release_start = maxf(0.0, _gait_progress - step_progress)
		if _gait_progress >= 1.0:
			_gait_kick_step = false
			_gait_anchors[swing_foot] = landing
			_gait_bases[swing_foot] = facing
			_gait_next_foot = 1 - swing_foot
			_gait_swing_foot = -1
	# Make a small knee bend when the standing leg approaches full extension.
	for foot in 2:
		if gait_plant_active(foot == 1):
			var hip: Node3D = player.right_leg if foot == 1 else player.left_leg
			var gap := hip.global_position - _gait_anchors[foot]
			var horizontal_squared := gap.x * gap.x + gap.z * gap.z
			var vertical_limit := sqrt(maxf(0.0, 0.747 * 0.747 - horizontal_squared))
			player.body_visual.position.y -= maxf(0.0, gap.y - vertical_limit)
	for foot in 2:
		# Keep both position and orientation of the sole fixed through a turn.
		var ankle := _gait_anchors[foot]
		var boot_basis := _gait_bases[foot]
		if _gait_swing_foot == foot:
			ankle = swing_target
			boot_basis = swing_basis
		elif _gait_released_foot == foot:
			var lift := smoothstep(_gait_release_start, 1.0, _gait_progress)
			ankle = ankle.lerp(homes[foot] - velocity.normalized() * 0.23, lift)
			ankle.y += 0.105 * lift
			boot_basis *= Basis(Vector3.RIGHT, -0.36 * lift)
		_pose_foot(player, foot == 1, ankle)
		feet[foot].global_basis = boot_basis


func set_tactical_marker(player: Node3D, marker: String) -> void:
	if marker == _tactical_kind:
		return
	_tactical_kind = marker
	if marker != "run" and marker != "receive":
		if _tactical_marker != null:
			_tactical_marker.hide()
		return
	if _tactical_marker == null:
		_tactical_marker = MeshInstance3D.new()
		_tactical_marker.name = "TacticalMarker"
		_tactical_marker.position.y = player.ring.position.y + 0.015
		_tactical_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		player.add_child(_tactical_marker)
	_tactical_marker.mesh = _tactical_mesh(marker)
	_tactical_marker.show()


static func _tactical_mesh(marker: String) -> ImmediateMesh:
	if _tactical_meshes.has(marker):
		return _tactical_meshes[marker] as ImmediateMesh
	var run := marker == "run"
	var material := FootballArt.marker(Color("8be8ff") if run else Color("d6f58c"))
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for side: float in [-1.0, 1.0]:
		if run:
			var tip := Vector2(side * 1.08, 0.0)
			_tactical_stroke(mesh, Vector2(side * 0.82, -0.36), tip)
			_tactical_stroke(mesh, tip, Vector2(side * 0.82, 0.36))
		else:
			for end: float in [-1.0, 1.0]:
				var corner := Vector2(side * 0.80, end * 0.80)
				_tactical_stroke(mesh, Vector2(side * 0.50, corner.y), corner)
				_tactical_stroke(mesh, corner, Vector2(corner.x, end * 0.50))
	mesh.surface_end()
	_tactical_meshes[marker] = mesh
	return mesh


static func _tactical_stroke(mesh: ImmediateMesh, start: Vector2, finish: Vector2) -> void:
	var along := (finish - start).normalized()
	var width := Vector2(-along.y, along.x) * 0.105
	for point: Vector2 in [start - width, start + width, finish + width, start - width, finish + width, finish - width]:
		mesh.surface_add_vertex(Vector3(point.x, 0.0, point.y))


func pose_celebration(_player: Node3D, elapsed: float) -> void:
	_gait_active = false
	# The match pauses the actor, so blend from the last on-pitch arm pose.
	if _celebration_start.is_empty() or elapsed <= 0.0:
		_celebration_start = [left_arm.quaternion, right_arm.quaternion, left_elbow.quaternion, right_elbow.quaternion]
	var left_raise := smoothstep(0.0, 0.40, elapsed) * (1.0 - smoothstep(0.86, 1.50, elapsed))
	var right_raise := smoothstep(0.08, 0.48, elapsed) * (1.0 - smoothstep(0.94, 1.58, elapsed))
	left_arm.quaternion = _celebration_start[0].slerp(Quaternion.from_euler(Vector3(2.22, 0.0, -0.64)), left_raise)
	right_arm.quaternion = _celebration_start[1].slerp(Quaternion.from_euler(Vector3(2.38, 0.0, 0.54)), right_raise)
	left_elbow.quaternion = _celebration_start[2].slerp(Quaternion.from_euler(Vector3(0.48, 0.0, 0.0)), left_raise)
	right_elbow.quaternion = _celebration_start[3].slerp(Quaternion.from_euler(Vector3(0.56, 0.0, 0.0)), right_raise)


func throw_in_hand_center(_player: Node3D) -> Vector3:
	var left_hand := left_elbow.to_global(HAND_LOCAL_CENTER)
	var right_hand := right_elbow.to_global(HAND_LOCAL_CENTER)
	return left_hand.lerp(right_hand, 0.5) + upper_body.global_basis.y * 0.045


func _pose_throw_in(player: Node3D, phase: float) -> void:
	# Move the hands around the crown before reaching forward for release.
	var cradle := Vector3(0.136, 0.39, -0.38)
	var high_front := Vector3(0.136, 1.02, -0.19)
	var behind_head := Vector3(0.136, 0.880, 0.260)
	var overhead := Vector3(0.136, 1.012, 0.000)
	var release := Vector3(0.136, 0.930, -0.265)
	var follow := Vector3(0.136, 0.700, -0.390)
	var hand: Vector3
	if phase < 0.16:
		hand = cradle.lerp(high_front, smoothstep(0.0, 0.16, phase))
	elif phase < 0.33:
		hand = high_front.lerp(behind_head, smoothstep(0.16, 0.33, phase))
	elif phase < 0.51:
		var swing := smoothstep(0.33, 0.51, phase)
		hand = behind_head.lerp(overhead, swing)
		hand.y += sin(swing * PI) * 0.047
	elif phase < 0.7:
		var swing := smoothstep(0.51, 0.7, phase)
		hand = overhead.lerp(release, swing)
		hand.y += sin(swing * PI) * 0.038
	else:
		hand = release.lerp(follow, smoothstep(0.7, 1.0, phase))
	_pose_throw_arm(left_arm, left_elbow, Vector3(-hand.x, hand.y, hand.z), -1.0)
	_pose_throw_arm(right_arm, right_elbow, hand, 1.0)
	player.body_visual.position.y = minf(player.body_visual.position.y, -0.10)
	var facing := _flat_body_basis(player)
	var position: Vector3 = player.global_position
	_pose_foot(player, false, position + facing * Vector3(-0.15, 0.052, 0.04))
	_pose_foot(player, true, position + facing * Vector3(0.15, 0.052, -0.04))


func _pose_throw_arm(arm: Node3D, elbow: Node3D, hand: Vector3, side: float) -> void:
	var to_hand := hand - arm.position
	var direction := to_hand.normalized()
	var forearm_length := -HAND_LOCAL_CENTER.y
	var reach := minf(to_hand.length(), UPPER_ARM_LENGTH + forearm_length - 0.001)
	var along := (UPPER_ARM_LENGTH ** 2 + reach ** 2 - forearm_length ** 2) / (2.0 * reach)
	var bend := sqrt(maxf(0.0, UPPER_ARM_LENGTH ** 2 - along ** 2))
	var outside := Vector3(side * 0.8, 0.0, 0.6)
	var pole := (outside - direction * outside.dot(direction)).normalized()
	var joint := direction * along + pole * bend
	arm.basis = _throw_arm_basis(joint)
	elbow.basis = arm.basis.inverse() * _throw_arm_basis(direction * reach - joint)


func _throw_arm_basis(segment: Vector3) -> Basis:
	var up := -segment.normalized()
	var right := (Vector3.RIGHT - up * up.x).normalized()
	return Basis(right, up, right.cross(up))


func sole_marker(_player: Node3D, right: bool) -> Vector3:
	var boot := right_boot if right else left_boot
	return boot.to_global(SOLE_LOCAL_CENTER)


func sole_target_offset(player: Node3D) -> Vector3:
	return _flat_body_basis(player) * SOLE_LOCAL_CENTER


func _flat_body_basis(player: Node3D) -> Basis:
	var forward: Vector3 = -player.body_visual.global_basis.z
	forward.y = 0.0
	return Basis.looking_at(forward, Vector3.UP)


func _pose_sole_stop(player: Node3D, touch_weight: float) -> void:
	var strike_right: bool = player.dribble_foot_right
	var flat_basis := _flat_body_basis(player)
	if not _sole_planting:
		_sole_plant_basis = flat_basis
	var elapsed: float = player.dribble_elapsed
	var contact_time: float = player.dribble_contact_time
	var weight := minf(touch_weight if player.dribble_has_hit else 1.0,
		smoothstep(0.0, minf(0.025, contact_time * 0.5), elapsed))
	var support_boot := left_boot if strike_right else right_boot
	var strike_boot := right_boot if strike_right else left_boot
	# Resolve the plant after gait smoothing so a settled support foot stays on its anchor.
	_pose_foot(player, not strike_right, player.sole_support_world, weight)
	support_boot.global_basis = support_boot.global_basis.slerp(_sole_plant_basis, weight)
	var swing := smoothstep(0.0, contact_time, elapsed)
	var offset: Vector3 = player.dribble_start_foot_offset.lerp(player.dribble_target_offset, swing)
	var lift := 0.115 * sin(PI * swing)
	if player.dribble_has_hit:
		lift = 0.08 * (1.0 - touch_weight)
	_pose_foot(player, strike_right, player.global_position + offset + Vector3.UP * lift, weight)
	strike_boot.global_basis = strike_boot.global_basis.slerp(flat_basis, weight)

func _limit_rotation(previous: Quaternion, target: Quaternion, max_angle: float) -> Quaternion:
	var angle := previous.angle_to(target)
	return previous.slerp(target, minf(1, max_angle / maxf(angle, 0.00001)))

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

func predicted_control_hip_shift(player: Node3D, delay: float, target_y: float = CONTROL_HIP_OFFSET) -> float:
	# Predict the same hip interpolation that an accepted swing will request.
	# The actual animated boot still has to meet the ball before any impulse.
	var current_y: float = player.body_visual.position.y
	var predicted_y := current_y
	var remaining := maxf(0, delay)
	var elapsed := 0.0
	var physics_step := 1.0 / float(Engine.physics_ticks_per_second)
	while remaining > 0.00001:
		var step := minf(physics_step, remaining)
		elapsed += step
		var weight := smoothstep(0, 0.06 if is_equal_approx(target_y, -0.22) else maxf(delay, 0.00001), elapsed)
		predicted_y = lerpf(predicted_y, target_y * weight, minf(1, step * HIP_RESPONSE))
		remaining -= step
	return predicted_y - current_y

func foot_reach_gap(player: Node3D, target_world: Vector3, right: bool = true, hip_shift: float = 0.0) -> float:
	# Use the same hip and limb length as the visible two-bone solver. This
	# reports unreachable distance; it never moves a foot or enlarges contact.
	var leg: Node3D = player.right_leg if right else player.left_leg
	var target: Vector3 = player.body_visual.to_local(target_world)
	var shift: Vector3 = player.body_visual.global_basis.inverse() * (Vector3.UP * hip_shift)
	return maxf(0, target.distance_to(leg.position + shift) - 0.749)
