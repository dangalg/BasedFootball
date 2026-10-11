class_name FootballArt
extends RefCounted

static func material(color: Color, roughness: float = 0.8) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat

static func mesh(parent: Node3D, shape: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.material_override = mat
	node.position = pos
	parent.add_child(node)
	return node

static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return mesh(parent, shape, mat, pos)

static func sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = radius
	shape.height = radius * 2.0
	shape.radial_segments = 16
	shape.rings = 8
	return mesh(parent, shape, mat, pos)

static func cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 16
	return mesh(parent, shape, mat, pos)

static func solid(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	parent.add_child(body)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	box(body, size, Vector3.ZERO, mat)
	return body

static func line(parent: Node3D, a: Vector3, b: Vector3, width: float, mat: Material) -> void:
	var node := box(parent, Vector3(width, 0.018, a.distance_to(b)), (a + b) * 0.5, mat)
	node.rotation.y = atan2(b.x - a.x, b.z - a.z)

static func circle(parent: Node3D, radius: float, pos: Vector3, mat: Material, thickness: float = 0.05) -> MeshInstance3D:
	var shape := TorusMesh.new()
	shape.inner_radius = radius - thickness
	shape.outer_radius = radius + thickness
	shape.rings = 48
	shape.ring_segments = 8
	return mesh(parent, shape, mat, pos)

static func text(parent: Node3D, value: String, pos: Vector3, size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.font_size = size
	label.pixel_size = 0.013
	label.modulate = color
	label.outline_size = 4
	label.position = pos
	parent.add_child(label)
	return label
