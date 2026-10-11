class_name FootballArt
extends RefCounted

const TURF: Texture2D = preload("res://assets/court/turf.png")
const CONCRETE: Texture2D = preload("res://assets/court/concrete.png")
const NET: Texture2D = preload("res://assets/court/net.png")
const CONTACT_SHADOW: Texture2D = preload("res://assets/court/contact-shadow.png")

static func material(color: Color, roughness: float = 0.8) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat

static func surface(color: Color, texture: Texture2D, tiling: float) -> StandardMaterial3D:
	var mat := material(color)
	mat.albedo_texture = texture
	mat.uv1_scale = Vector3(tiling, tiling, 1)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return mat

static func marker(color: Color) -> StandardMaterial3D:
	var mat := material(color)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

static func capsule(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var shape := CapsuleMesh.new()
	shape.radius = radius
	shape.height = height
	shape.radial_segments = 12
	shape.rings = 4
	return mesh(parent, shape, mat, pos)

static func tailored_mesh(parent: Node3D, profile: Array, mat: Material) -> MeshInstance3D:
	# Elliptical cross-sections give clothing a waist, shoulders and tapered edges.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(0)
	for row in range(profile.size() - 1):
		for segment in range(16):
			for corner in [[row, segment], [row + 1, segment], [row + 1, segment + 1], [row, segment], [row + 1, segment + 1], [row, segment + 1]]:
				var section: Vector3 = profile[corner[0]]
				var angle := float(corner[1]) * TAU / 16.0
				surface.add_vertex(Vector3(cos(angle) * section.y, section.x, sin(angle) * section.z))
	surface.generate_normals()
	surface.index()
	var node := mesh(parent, surface.commit(), mat)
	return node

static func contact_shadow(parent: Node3D, diameter: float) -> MeshInstance3D:
	var mat := marker(Color.WHITE)
	mat.albedo_texture = CONTACT_SHADOW
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shape := QuadMesh.new()
	shape.size = Vector2(diameter, diameter)
	var node := mesh(parent, shape, mat, Vector3(0, 0.035, 0))
	node.rotation.x = -PI * 0.5
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

static func net(parent: Node3D, dimensions: Vector2, pos: Vector3, rotation_y: float) -> MeshInstance3D:
	var mat := surface(Color("b4c6bd"), NET, 1)
	mat.uv1_scale = Vector3(dimensions.x * 0.8, dimensions.y * 0.8, 1)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shape := QuadMesh.new()
	shape.size = dimensions
	var node := mesh(parent, shape, mat, pos)
	node.rotation.y = rotation_y
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

static func hide_solid_mesh(body: StaticBody3D) -> void:
	# A cosmetic replacement must never change the rebound geometry.
	for child in body.get_children():
		if child is MeshInstance3D:
			child.hide()

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
