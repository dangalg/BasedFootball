class_name FootballPlayer
extends RigidBody3D

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

func _ready() -> void:
	lock_rotation = true
	linear_damp = 0.1
	angular_damp = 1.0
	continuous_cd = true
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
	_build_visual()

func _build_visual() -> void:
	body_visual = Node3D.new()
	add_child(body_visual)
	var jersey := FootballArt.material(Color("309ff0") if team == 0 else Color("ff765e"))
	var dark := FootballArt.material(Color("182b43") if team == 0 else Color("572d38"))
	var skin := FootballArt.material(Color("d6a17a") if shirt_number != 4 else Color("92684f"))
	var white := FootballArt.material(Color("e8efe4"))
	FootballArt.box(body_visual, Vector3(0.66, 0.64, 0.38), Vector3(0, 1.13, 0), jersey)
	FootballArt.box(body_visual, Vector3(0.68, 0.07, 0.4), Vector3(0, 1.25, 0), white)
	FootballArt.box(body_visual, Vector3(0.57, 0.25, 0.36), Vector3(0, 0.72, 0), dark)
	FootballArt.sphere(body_visual, 0.26, Vector3(0, 1.72, 0), skin)
	FootballArt.sphere(body_visual, 0.07, Vector3(0, 1.73, -0.25), skin)
	FootballArt.box(body_visual, Vector3(0.4, 0.11, 0.36), Vector3(0, 1.93, 0.02), dark)
	for side in [-1.0, 1.0]:
		var arm := FootballArt.box(body_visual, Vector3(0.16, 0.53, 0.17), Vector3(side * 0.43, 1.05, 0), skin)
		arm.rotation.z = side * 0.15
		var leg := Node3D.new()
		body_visual.add_child(leg)
		leg.position = Vector3(side * 0.18, 0.68, 0)
		FootballArt.box(leg, Vector3(0.19, 0.41, 0.2), Vector3(0, -0.22, 0), white)
		FootballArt.box(leg, Vector3(0.23, 0.16, 0.39), Vector3(0, -0.53, -0.07), dark)
		if side < 0:
			left_leg = leg
		else:
			right_leg = leg
	var number := FootballArt.text(body_visual, str(shirt_number), Vector3(0, 1.1, 0.205), 40, Color.WHITE)
	number.rotation.y = PI
	ring = FootballArt.circle(self, 0.65, Vector3(0, 0.05, 0), FootballArt.material(Color("ffd65c")), 0.055)
	name_label = FootballArt.text(self, player_name, Vector3(0, 2.5, 0), 23, Color("ffdf7c"))
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true

func _physics_process(delta: float) -> void:
	kick_cooldown = maxf(0.0, kick_cooldown - delta)
	tackle_cooldown = maxf(0.0, tackle_cooldown - delta)
	touch_cooldown = maxf(0.0, touch_cooldown - delta)
	tackle_remaining = maxf(0.0, tackle_remaining - delta)
	active_seconds += delta
	if sprint and intent.length_squared() > 0.1:
		energy = maxf(0.0, energy - delta * 0.07 / stamina_trait)
	else:
		energy = minf(1.0, energy + delta * 0.05 * stamina_trait)
	ring.visible = selected
	name_label.visible = selected
	var velocity := Vector3(linear_velocity.x, 0, linear_velocity.z)
	var facing := aim if aim.length_squared() > 0.1 else velocity.normalized()
	if facing.length_squared() > 0.1:
		body_visual.rotation.y = lerp_angle(body_visual.rotation.y, atan2(-facing.x, -facing.z), 12.0 * delta)
	var local_velocity := body_visual.basis.inverse() * velocity
	body_visual.rotation.x = lerpf(body_visual.rotation.x, -local_velocity.z * 0.022 + (0.28 if tackle_remaining > 0 else 0.0), 9 * delta)
	body_visual.rotation.z = lerpf(body_visual.rotation.z, -local_velocity.x * 0.025, 9 * delta)
	step_phase += velocity.length() * delta * 2.6
	var stride := minf(velocity.length() * 0.065, 0.48)
	left_leg.rotation.x = sin(step_phase) * stride
	right_leg.rotation.x = -sin(step_phase) * stride - (0.65 if kick_cooldown > 0.22 else 0.0)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var speed := pace if sprint and energy > 0.05 else pace * 0.66
	var desired := intent.limit_length(1.0) * speed
	if tackle_remaining > 0.0:
		desired = aim * 7.3
	var horizontal := Vector3(state.linear_velocity.x, 0, state.linear_velocity.z)
	var acceleration := (desired - horizontal) * 7.5
	# The cap preserves collision response and prevents instant direction changes.
	state.apply_central_force(acceleration.limit_length(24.0) * mass)

func reach_ball(ball: FootballBall, distance: float = 1.15) -> bool:
	var difference := ball.global_position - global_position
	difference.y = 0
	return difference.length() < distance and ball.global_position.y < 1.15

func kick(ball: FootballBall, direction: Vector3, strength: float, lift: float) -> bool:
	if kick_cooldown > 0.0 or not reach_ball(ball):
		return false
	var target := direction.normalized() * strength + Vector3.UP * lift
	var impulse := (target - ball.linear_velocity) * ball.mass
	ball.touch(team, player_id, impulse, Vector3(0, -0.1, 0))
	kick_cooldown = 0.42
	touch_cooldown = 0.3
	match_touches += 1
	return true

func dribble(ball: FootballBall) -> bool:
	if touch_cooldown > 0.0 or kick_cooldown > 0.0 or intent.length_squared() < 0.05 or not reach_ball(ball, 1.08):
		return false
	var relative := ball.global_position - global_position
	relative.y = 0
	if relative.dot(intent.normalized()) < -0.25:
		return false
	var speed := pace + 1.4 if sprint and energy > 0.05 else pace * 0.69
	var touch_target := intent.normalized() * speed
	var impulse := (touch_target - Vector3(ball.linear_velocity.x, 0, ball.linear_velocity.z)) * ball.mass
	ball.touch(team, player_id, impulse.limit_length(2.6 * touch_skill))
	touch_cooldown = 0.24 if sprint else 0.16
	match_touches += 1
	return true

func tackle(ball: FootballBall) -> bool:
	if tackle_cooldown > 0.0:
		return false
	tackle_cooldown = 1.15
	tackle_remaining = 0.16
	apply_central_impulse(aim * mass * 1.5)
	if reach_ball(ball, 1.25):
		ball.touch(team, player_id, aim * 2.9)
		touch_cooldown = 0.35
		match_touches += 1
	return true
