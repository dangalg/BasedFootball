class_name FootballKeeperVisual
extends FootballPlayerVisual

const GLOVE_RADIUS := 0.065
const ARM_TARGET_SPEED := 4.5

var left_hand: Node3D
var right_hand: Node3D
var left_hand_target := Vector3.ZERO
var right_hand_target := Vector3.ZERO
var previous_body_position := Vector3.ZERO
var hand_targets_initialized: bool = false

func build(player: Node3D) -> void:
	super.build(player)
	var old_color := Color("3689cf") if player.team == 0 else Color("db7059")
	var keeper_color := Color("e4bd49") if player.team == 0 else Color("73b99b")
	_recolor_kit(player.body_visual, old_color, keeper_color)
	var gloves := FootballArt.material(Color("ede9d9"), 0.9)
	var cuffs := FootballArt.material(Color("3a4849"))
	left_hand = _glove(left_elbow, "LeftKeeperPalm", gloves, cuffs)
	right_hand = _glove(right_elbow, "RightKeeperPalm", gloves, cuffs)

func _recolor_kit(node: Node, old_color: Color, keeper_color: Color) -> void:
	if node is MeshInstance3D:
		var surface := (node as MeshInstance3D).material_override as StandardMaterial3D
		if surface != null and surface.albedo_color.is_equal_approx(old_color):
			surface.albedo_color = keeper_color
	for child in node.get_children():
		_recolor_kit(child, old_color, keeper_color)

func _glove(elbow: Node3D, label: String, glove_material: Material, cuff_material: Material) -> Node3D:
	var palm := Node3D.new()
	palm.name = label
	palm.position = Vector3(0, -0.26, 0)
	elbow.add_child(palm)
	# Contact uses precisely this visible sphere, without an enlarged save volume.
	FootballArt.sphere(palm, GLOVE_RADIUS, Vector3.ZERO, glove_material)
	FootballArt.cylinder(elbow, 0.055, 0.065, Vector3(0, -0.205, 0), cuff_material)
	return palm

func animate(player: Node3D, delta: float) -> void:
	super.animate(player, delta)
	var keeper := player as FootballGoalkeeper
	if keeper == null or keeper.ragdoll != null or keeper.hop_active:
		return
	# The base animation has already solved the boot's world-space kick path.
	# Do not subsequently rotate its parent or replace its ordinary arm swing.
	if keeper.action_kind == "kick":
		_reset_hand_targets(keeper)
		return
	var facing := keeper.aim
	facing.y = 0
	if facing.length_squared() > 0.01:
		# A keeper shuffles while watching the ball instead of facing sideways.
		keeper.body_visual.rotation.y = lerp_angle(keeper.body_visual.rotation.y, atan2(-facing.x, -facing.z), minf(1.0, delta * 14.0))
	var forward := -keeper.body_visual.global_basis.z.normalized()
	var right := keeper.body_visual.global_basis.x.normalized()
	var center := keeper.global_position + Vector3.UP * 1.12 + forward * 0.28
	var separation := 0.23
	if keeper.keeper_state in ["holding", "releasing"]:
		center = keeper.grip_target
		separation = FootballBall.RADIUS + 0.04
	elif keeper.keeper_state in ["tracking", "lunge"]:
		center = keeper.save_hand_target
		separation = FootballBall.RADIUS + 0.04
	var body_displacement := keeper.global_position - previous_body_position
	if not hand_targets_initialized or body_displacement.length() > 1.0:
		# A dead-ball relocation clears contact history in reset_action. It must
		# not leave an arm chasing a world target on the old side of the pitch.
		_reset_hand_targets(keeper)
		body_displacement = Vector3.ZERO
	# Root movement transports the arms physically. Only the arms' additional
	# reach is rate limited, so a sprint does not strand their targets behind.
	left_hand_target += body_displacement
	right_hand_target += body_displacement
	left_hand_target = left_hand_target.move_toward(center - right * separation, ARM_TARGET_SPEED * delta)
	right_hand_target = right_hand_target.move_toward(center + right * separation, ARM_TARGET_SPEED * delta)
	previous_body_position = keeper.global_position
	_pose_hand(left_arm, left_elbow, left_hand_target, -right, forward)
	_pose_hand(right_arm, right_elbow, right_hand_target, right, forward)

func _reset_hand_targets(player: Node3D) -> void:
	left_hand_target = left_hand.global_position
	right_hand_target = right_hand.global_position
	previous_body_position = player.global_position
	hand_targets_initialized = true

func _pose_hand(arm: Node3D, elbow: Node3D, desired: Vector3, outward: Vector3, forward: Vector3) -> void:
	var shoulder := arm.global_position
	var difference := desired - shoulder
	var reach := clampf(difference.length(), 0.035, 0.522)
	var axis := difference.normalized() if difference.length_squared() > 0.00001 else Vector3.DOWN
	var endpoint := shoulder + axis * reach
	var upper := 0.27
	var lower := 0.26
	var along := (upper * upper + reach * reach - lower * lower) / (2.0 * reach)
	var height := sqrt(maxf(0.0, upper * upper - along * along))
	var pole := (outward * 0.65 + Vector3.DOWN * 0.6 - forward * 0.2)
	pole -= axis * pole.dot(axis)
	if pole.length_squared() < 0.00001:
		pole = axis.cross(Vector3.UP)
	if pole.length_squared() < 0.00001:
		pole = Vector3.RIGHT
	var elbow_world := shoulder + axis * along + pole.normalized() * height
	var local_upper: Vector3 = (arm.get_parent() as Node3D).to_local(elbow_world) - arm.position
	arm.quaternion = Quaternion(Vector3.DOWN, local_upper.normalized())
	var local_lower: Vector3 = arm.to_local(endpoint) - elbow.position
	elbow.quaternion = Quaternion(Vector3.DOWN, local_lower.normalized())

func hand_positions() -> Array[Vector3]:
	if left_hand == null or right_hand == null:
		return []
	return [left_hand.global_position, right_hand.global_position]
