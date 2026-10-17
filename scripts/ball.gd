class_name FootballBall
extends RigidBody3D

const RADIUS := 0.11

var last_touch_team: int = -1
var last_touch_id: String = ""
var touches: int = 0
var control_block_remaining: float = 0.0
var control_candidate_id: String = ""
var touch_serial: int = 0
var impulse_audit: Array[Dictionary] = []
var passer_block_id: String = ""
var passer_block_remaining: float = 0.0
var grip_holder_id: String = ""
var pass_active: bool = false
var pass_passer_id: String = ""
var pass_receiver_id: String = ""
var pass_team: int = -1
var pass_target := Vector3.ZERO
var pass_remaining: float = 0.0
var pass_end_reason: String = ""

func _physics_process(delta: float) -> void:
	control_block_remaining = maxf(0, control_block_remaining - delta)
	passer_block_remaining = maxf(0, passer_block_remaining - delta)
	if passer_block_remaining <= 0:
		passer_block_id = ""
	if pass_active:
		pass_remaining = maxf(0, pass_remaining - delta)
		if pass_remaining <= 0:
			clear_pass("expired")

func _ready() -> void:
	mass = 0.43
	continuous_cd = true
	linear_damp = 0.22
	angular_damp = 0.4
	contact_monitor = true
	max_contacts_reported = 8
	var surface := PhysicsMaterial.new()
	surface.friction = 0.5
	surface.bounce = 0.48
	physics_material_override = surface
	var collider := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = RADIUS
	collider.shape = shape
	add_child(collider)
	FootballArt.sphere(self, RADIUS, Vector3.ZERO, FootballArt.material(Color("e4e8da"), 0.65))
	var black := FootballArt.material(Color("101d29"), 0.8)
	black.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Twelve pentagonal patches rotate with the physical sphere.
	var phi := (1.0 + sqrt(5.0)) * 0.5
	var normals: Array[Vector3] = []
	for a in [-1.0, 1.0]:
		for b in [-1.0, 1.0]:
			normals.append(Vector3(0, a, b * phi).normalized())
			normals.append(Vector3(a, b * phi, 0).normalized())
			normals.append(Vector3(b * phi, 0, a).normalized())
	for normal in normals:
		var tangent := normal.cross(Vector3.UP).normalized()
		if tangent.length_squared() < 0.1:
			tangent = normal.cross(Vector3.RIGHT).normalized()
		var bitangent := normal.cross(tangent)
		var patch := ImmediateMesh.new()
		patch.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(5):
			for offset in [-1, 0, 1]:
				var vertex := normal * (RADIUS + 0.001)
				if offset >= 0:
					var angle := float(i + offset) * TAU / 5.0
					vertex = (normal + (tangent * cos(angle) + bitangent * sin(angle)) * 0.32).normalized() * (RADIUS + 0.0015)
				patch.surface_set_normal(vertex.normalized())
				patch.surface_add_vertex(vertex)
		patch.surface_end()
		FootballArt.mesh(self, patch, black)

func touch(team: int, player_id: String, impulse: Vector3, offset: Vector3 = Vector3.ZERO) -> void:
	if pass_active:
		clear_pass("receiver_touch" if player_id == pass_receiver_id else "intercepted")
	last_touch_team = team
	last_touch_id = player_id
	touches += 1
	touch_serial += 1
	# Observe the actual shared impulse application point; this log supplies no
	# possession, contacts, forces or corrections to the simulation.
	impulse_audit.append({"physics_frame":Engine.get_physics_frames(),"serial":touch_serial,"player_id":player_id,"team":team,"impulse":[impulse.x,impulse.y,impulse.z],"before_velocity":[linear_velocity.x,linear_velocity.y,linear_velocity.z]})
	if impulse_audit.size() > 2048:
		impulse_audit.pop_front()
	sleeping = false
	apply_impulse(impulse, offset)

func begin_pass(passer: String, receiver: String, team: int, target: Vector3, duration: float) -> void:
	pass_active = true
	pass_passer_id = passer
	pass_receiver_id = receiver
	pass_team = team
	pass_target = target
	pass_remaining = duration
	pass_end_reason = ""

func clear_pass(reason: String) -> void:
	pass_active = false
	pass_remaining = 0.0
	pass_end_reason = reason
	pass_receiver_id = ""
	pass_passer_id = ""
	pass_team = -1

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Rolling resistance acts on every team equally; no possession attachment.
	if state.transform.origin.y < RADIUS + 0.045:
		var horizontal := Vector3(state.linear_velocity.x, 0, state.linear_velocity.z)
		state.apply_central_force(-horizontal * 0.13)
	# Explicit aerodynamic spin force, bounded for numerical stability.
	var magnus := state.angular_velocity.cross(state.linear_velocity) * 0.0007
	state.apply_central_force(magnus.limit_length(0.25))
