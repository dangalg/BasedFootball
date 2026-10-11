class_name FootballPlayerRagdoll
extends Node3D

# A finite physical fall. Normal locomotion is handed back only after the body
# settles, then the same mesh blends into a crouched get-up pose.
var actor: FootballPlayer
var bodies: Array[RigidBody3D] = []
var pelvis: RigidBody3D
var torso: RigidBody3D
var clone: Node3D
var age := 0.0
var settled_time := 0.0
var recovering := false
var recovery_time := 0.0
var part_targets: Array = []
var original_layer: int
var original_mask: int
var finished := false
var recover_origin := Vector3.ZERO
var recover_target := Vector3.ZERO

func begin(player: FootballPlayer, impulse: Vector3, contact: Vector3) -> void:
	actor = player
	original_layer = actor.collision_layer
	original_mask = actor.collision_mask
	clone = actor.body_visual.duplicate() as Node3D
	add_child(clone)
	clone.global_transform = actor.body_visual.global_transform
	var visual: FootballPlayerVisual = actor.visual_controller
	var upper := _copy(visual.upper_body)
	var head := _copy(visual.head_pivot)
	var left_leg := _copy(actor.left_leg)
	var right_leg := _copy(actor.right_leg)
	var left_knee := _copy(visual.left_knee)
	var right_knee := _copy(visual.right_knee)
	var left_arm := _copy(visual.left_arm)
	var right_arm := _copy(visual.right_arm)
	var left_elbow := _copy(visual.left_elbow)
	var right_elbow := _copy(visual.right_elbow)
	pelvis = _body("Pelvis", actor.body_visual.global_transform.translated_local(Vector3(0, 0.87, 0)), 0.19, 0.25, actor.mass * 0.15)
	torso = _part("Torso", upper, Vector3(0, 0.32, 0), 0.19, 0.48, actor.mass * 0.335)
	var skull := _part("Head", head, Vector3(0, 0.16, 0), 0.125, 0.25, actor.mass * 0.07)
	_joint(pelvis, torso, upper.global_transform, Vector3(0.6, 0.4, 0.45))
	_joint(torso, skull, head.global_transform, Vector3(0.45, 0.6, 0.45))
	for parts in [[left_leg, left_knee, left_arm, left_elbow], [right_leg, right_knee, right_arm, right_elbow]]:
		var thigh := _part("Thigh", parts[0], Vector3(0, -0.205, 0), 0.075, 0.41, actor.mass * 0.10)
		var shin := _part("Shin", parts[1], Vector3(0, -0.17, 0), 0.057, 0.36, actor.mass * 0.065)
		var arm := _part("Arm", parts[2], Vector3(0, -0.135, 0), 0.053, 0.27, actor.mass * 0.0275)
		var forearm := _part("Forearm", parts[3], Vector3(0, -0.12, 0), 0.045, 0.25, actor.mass * 0.03)
		_joint(pelvis, thigh, parts[0].global_transform, Vector3(1.2, 0.45, 0.65))
		_joint(thigh, shin, parts[1].global_transform, Vector3(1.25, 0.05, 0.05), true)
		_joint(torso, arm, parts[2].global_transform, Vector3(1.3, 0.6, 1.1))
		_joint(arm, forearm, parts[3].global_transform, Vector3(1.35, 0.05, 0.05))
	# Internal limb intersections must not inject energy into the ragdoll.
	for body in bodies:
		for other in bodies:
			if body != other:
				body.add_collision_exception_with(other)
		body.linear_velocity = actor.linear_velocity
		body.reset_physics_interpolation()
	actor.body_visual.hide()
	actor.collision_layer = 0
	actor.collision_mask = 0
	actor.freeze = true
	# Spread the impact across trunk and struck lower leg. The differential
	# motion tips the jointed body without injecting excessive trunk torque.
	var struck: RigidBody3D = bodies[4] if bodies[4].global_position.distance_to(contact) < bodies[8].global_position.distance_to(contact) else bodies[8]
	pelvis.apply_central_impulse(impulse * 0.35)
	torso.apply_central_impulse(impulse * 0.35)
	struck.apply_central_impulse(impulse * 0.30)
	actor.physical_event.emit("fall", {"impulse": impulse.length()})

func _copy(original: Node3D) -> Node3D:
	return clone.get_node(actor.body_visual.get_path_to(original)) as Node3D

func _body(label: String, pose: Transform3D, radius: float, height: float, weight: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = label + str(bodies.size())
	body.mass = weight
	body.can_sleep = false
	body.continuous_cd = true
	body.linear_damp = 0.6
	body.angular_damp = 1.8
	body.collision_layer = 8
	body.collision_mask = 1 | 8
	var material := PhysicsMaterial.new()
	material.friction = 0.65
	material.bounce = 0
	body.physics_material_override = material
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(height, radius * 2)
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	body.global_transform = pose
	bodies.append(body)
	return body

func _part(label: String, mesh: Node3D, offset: Vector3, radius: float, height: float, weight: float) -> RigidBody3D:
	var body := _body(label, mesh.global_transform.translated_local(offset), radius, height, weight)
	mesh.reparent(body, true)
	part_targets.append({"mesh": mesh, "source": null})
	return body

func _joint(a: RigidBody3D, b: RigidBody3D, pose: Transform3D, limits: Vector3, knee: bool = false) -> void:
	var joint := Generic6DOFJoint3D.new()
	add_child(joint)
	joint.global_transform = pose
	joint.node_a = joint.get_path_to(a)
	joint.node_b = joint.get_path_to(b)
	joint.set("angular_limit_x/lower_angle", -limits.x if knee else -limits.x * 0.5)
	joint.set("angular_limit_x/upper_angle", 0.05 if knee else limits.x)
	joint.set("angular_limit_y/lower_angle", -limits.y)
	joint.set("angular_limit_y/upper_angle", limits.y)
	joint.set("angular_limit_z/lower_angle", -limits.z)
	joint.set("angular_limit_z/upper_angle", limits.z)

func _physics_process(delta: float) -> void:
	if finished:
		return
	age += delta
	if recovering:
		recovery_time += delta
		var blend := smoothstep(0, 0.85 / actor.agility_skill, recovery_time)
		actor.global_position = recover_origin.lerp(recover_target, blend)
		for target in part_targets:
			var mesh: Node3D = target.mesh
			var source: Node3D = target.source
			mesh.global_transform = target.start.interpolate_with(source.global_transform, blend)
		if blend >= 1:
			finish()
		return
	# Keep selection, camera and nearby-player logic at the physical body.
	actor.global_position = Vector3(pelvis.global_position.x, 0.02, pelvis.global_position.z)
	actor.reset_physics_interpolation()
	var speed := 0.0
	for body in bodies:
		speed = maxf(speed, body.linear_velocity.length())
	settled_time = settled_time + delta if speed < 1.1 else 0.0
	if age > 0.8 / actor.agility_skill and settled_time > 0.25:
		_start_recovery()

func _start_recovery() -> void:
	# Query clearance before restoring an upright capsule: never stand through
	# a board or another player. Continue lying down until space becomes available.
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = actor.body_collider.shape
	query.transform = Transform3D(Basis.IDENTITY, actor.global_position + Vector3(0, 0.89, 0))
	query.collision_mask = 1 | 8
	var excluded: Array[RID] = [actor.get_rid()]
	for body in bodies:
		excluded.append(body.get_rid())
	query.exclude = excluded
	var clear := false
	recover_origin = actor.global_position
	for offset in [Vector3.ZERO, Vector3.LEFT * 0.4, Vector3.RIGHT * 0.4, Vector3.FORWARD * 0.4, Vector3.BACK * 0.4, Vector3.LEFT * 0.7, Vector3.RIGHT * 0.7, Vector3.FORWARD * 0.7, Vector3.BACK * 0.7]:
		query.transform.origin = recover_origin + offset + Vector3(0, 0.89, 0)
		if get_world_3d().direct_space_state.intersect_shape(query, 8).is_empty():
			recover_target = recover_origin + offset
			clear = true
			break
	if not clear:
		return
	recovering = true
	actor.getting_up = true
	actor.body_visual.rotation.y = atan2(-actor.aim.x, -actor.aim.z)
	# Record corresponding original meshes before changing the clone hierarchy.
	var originals := [actor.visual_controller.upper_body, actor.visual_controller.head_pivot, actor.left_leg, actor.visual_controller.left_knee, actor.visual_controller.left_arm, actor.visual_controller.left_elbow, actor.right_leg, actor.visual_controller.right_knee, actor.visual_controller.right_arm, actor.visual_controller.right_elbow]
	for i in range(part_targets.size()):
		part_targets[i].source = originals[i]
		part_targets[i].start = part_targets[i].mesh.global_transform
	for body in bodies:
		body.freeze = true
		body.collision_layer = 0
		body.collision_mask = 0
	actor.recovery_remaining = 0.85 / actor.agility_skill

func finish(canceled: bool = false) -> void:
	if finished:
		return
	finished = true
	for body in bodies:
		body.collision_layer = 0
		body.collision_mask = 0
	actor.collision_layer = original_layer
	actor.collision_mask = original_mask
	actor.freeze = false
	actor.linear_velocity = Vector3.ZERO
	actor.body_visual.show()
	actor.getting_up = false
	actor.recovery_remaining = 0
	actor.ragdoll = null
	actor.physical_event.emit("fall_reset" if canceled else "get_up", {})
	queue_free()
