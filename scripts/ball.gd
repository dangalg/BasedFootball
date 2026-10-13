class_name FootballBall
extends RigidBody3D

const RADIUS := 0.11

static func loft_launch(distance: float, apex: float) -> Vector2:
	# Account for engine air damping at launch; flight is thereafter unconstrained.
	var drag := 0.22 + float(ProjectSettings.get_setting("physics/3d/default_linear_damp", 0.1))
	var low := 0.0
	var high := 18.0
	for step in range(16):
		var speed := (low + high) * 0.5
		var height := speed / drag - 9.8 / (drag * drag) * log(1 + drag * speed / 9.8)
		if height < apex - RADIUS:
			low = speed
		else:
			high = speed
	var lift := (low + high) * 0.5
	low = 0.1
	high = 5.0
	for step in range(18):
		var time := (low + high) * 0.5
		var height := (lift + 9.8 / drag) * (1 - exp(-drag * time)) / drag - 9.8 * time / drag
		if height > 0:
			low = time
		else:
			high = time
	var flight := (low + high) * 0.5
	return Vector2(distance * drag / (1 - exp(-drag * flight)), lift)

var last_touch_team: int = -1
var last_touch_id: String = ""
var touches: int = 0
var control_block_remaining: float = 0.0
var control_candidate_id: String = ""

func predict(time: float) -> Vector3:
	var airborne := global_position.y > RADIUS+.045 or linear_velocity.y > .5
	var drag := linear_damp+float(ProjectSettings.get_setting("physics/3d/default_linear_damp",.1))
	if not airborne:
		drag += .13/mass
	var position := global_position+linear_velocity*((1-exp(-drag*time))/drag)
	if airborne:
		position.y -= 9.8/drag*(time-(1-exp(-drag*time))/drag)
	position.y=maxf(RADIUS,position.y)
	return position

func _physics_process(delta: float) -> void:
	control_block_remaining = maxf(0, control_block_remaining - delta)

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
	last_touch_team = team
	last_touch_id = player_id
	touches += 1
	sleeping = false
	apply_impulse(impulse, offset)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Rolling resistance acts on every team equally; no possession attachment.
	if state.transform.origin.y < RADIUS + 0.045:
		var horizontal := Vector3(state.linear_velocity.x, 0, state.linear_velocity.z)
		state.apply_central_force(-horizontal * 0.13)
	# Explicit aerodynamic spin force, bounded for numerical stability.
	var magnus := state.angular_velocity.cross(state.linear_velocity) * 0.0018
	state.apply_central_force(magnus.limit_length(1.2))
