class_name FootballBall
extends RigidBody3D

var last_touch_team: int = -1
var last_touch_id: String = ""
var touches: int = 0

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
	shape.radius = 0.28
	collider.shape = shape
	add_child(collider)
	FootballArt.sphere(self, 0.28, Vector3.ZERO, FootballArt.material(Color("f5f1dd"), 0.65))
	var black := FootballArt.material(Color("172534"))
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
				var vertex := normal * 0.283
				if offset >= 0:
					var angle := float(i + offset) * TAU / 5.0
					vertex = (normal + (tangent * cos(angle) + bitangent * sin(angle)) * 0.32).normalized() * 0.284
				patch.surface_set_normal(normal)
				patch.surface_add_vertex(vertex)
		patch.surface_end()
		FootballArt.mesh(self, patch, black)

func touch(team: int, player_id: String, impulse: Vector3, offset: Vector3 = Vector3.ZERO) -> void:
	last_touch_team = team
	last_touch_id = player_id
	touches += 1
	sleeping = false
	apply_impulse(impulse, offset)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Rolling resistance acts on every team equally; no possession attachment.
	if state.transform.origin.y < 0.4:
		var horizontal := Vector3(state.linear_velocity.x, 0, state.linear_velocity.z)
		state.apply_central_force(-horizontal * 0.13)
	# Explicit aerodynamic spin force, bounded for numerical stability.
	var magnus := state.angular_velocity.cross(state.linear_velocity) * 0.0007
	state.apply_central_force(magnus.limit_length(0.25))
