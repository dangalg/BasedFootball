class_name FootballSkinnedAthlete
extends RefCounted

# Original runtime mesh: connected limb rings with blended elbow/knee weights.
# Existing pose anchors drive real Skeleton3D bones and remain contact sources.
var skeleton: Skeleton3D
var anchors: Array[Node3D] = []
var paths: Array[NodePath] = []
var meshes: Array[MeshInstance3D] = []
var blended_vertices := 0
const PARENTS := [-1, 0, 1, 0, 3, 4, 0, 6, 7, 1, 9, 1, 11]

func build(player: Node3D, visual: FootballPlayerVisual) -> void:
	var root: Node3D = player.body_visual
	anchors = [root, visual.upper_body, visual.head_pivot, player.left_leg, visual.left_knee, visual.left_boot, player.right_leg, visual.right_knee, visual.right_boot, visual.left_arm, visual.left_elbow, visual.right_arm, visual.right_elbow]
	skeleton = Skeleton3D.new()
	skeleton.name = "AthleteSkeleton"
	root.add_child(skeleton)
	var skin := Skin.new()
	for i in range(anchors.size()):
		paths.append(root.get_path_to(anchors[i]))
		skeleton.add_bone("AthleteRoot" if i == 0 else str(anchors[i].name) + str(i))
		skeleton.set_bone_parent(i, PARENTS[i])
		var world_rest: Transform3D = root.global_transform.affine_inverse() * anchors[i].global_transform
		var local_rest: Transform3D = world_rest if PARENTS[i] < 0 else anchors[PARENTS[i]].global_transform.affine_inverse() * anchors[i].global_transform
		skeleton.set_bone_rest(i, local_rest)
		skeleton.set_bone_pose(i, local_rest)
		skin.add_bind(i, world_rest.affine_inverse())
	# Copy head, boots and kit geometry into weighted surfaces. Replace separate
	# limb primitives with continuous tubes so bends deform rather than separate.
	_copy_details(root, root, skin)
	for pair in [[3, 4, 0.41, 0.34, true], [6, 7, 0.41, 0.34, true], [9, 10, 0.27, 0.25, false], [11, 12, 0.27, 0.25, false]]:
		_limb(root, skin, pair[0], pair[1], pair[2], pair[3], pair[4], player.team)
	sync()

func _copy_details(node: Node3D, root: Node3D, skin: Skin) -> void:
	for child in node.get_children():
		if child is Skeleton3D:
			continue
		if child is MeshInstance3D:
			var owner_bone := 1
			var parent: Node = child.get_parent()
			while parent != root:
				var found := anchors.find(parent)
				if found >= 0:
					owner_bone = found
					break
				parent = parent.get_parent()
			var limb := owner_bone in [3, 4, 6, 7, 9, 10, 11, 12]
			# Keep hands/thumbs, but replace sleeves, thigh, shin and forearm pieces.
			var hand: bool = owner_bone in [10, 12] and child.position.y < -0.23
			if not limb or hand:
				var mesh := ArrayMesh.new()
				for surface in range(child.mesh.get_surface_count()):
					var arrays: Array = child.mesh.surface_get_arrays(surface)
					var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
					var transform: Transform3D = root.global_transform.affine_inverse() * child.global_transform
					var normal_basis: Basis = transform.basis.inverse().transposed()
					var bones := PackedInt32Array()
					var weights := PackedFloat32Array()
					for v in range(vertices.size()):
						vertices[v] = transform * vertices[v]
						if not normals.is_empty():
							normals[v] = (normal_basis * normals[v]).normalized()
						bones.append_array(PackedInt32Array([owner_bone, 0, 0, 0]))
						weights.append_array(PackedFloat32Array([1, 0, 0, 0]))
					arrays[Mesh.ARRAY_VERTEX] = vertices
					arrays[Mesh.ARRAY_NORMAL] = normals
					arrays[Mesh.ARRAY_BONES] = bones
					arrays[Mesh.ARRAY_WEIGHTS] = weights
					# Tangents from the old scaled primitives are not used by these materials.
					arrays[Mesh.ARRAY_TANGENT] = null
					mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
					mesh.surface_set_material(surface, child.material_override)
				var instance := _attach(root, mesh, skin)
				instance.set_meta("source_bone", owner_bone)
			child.hide()
		elif child is Node3D:
			_copy_details(child, root, skin)

func _limb(root: Node3D, skin: Skin, upper: int, lower: int, length_a: float, length_b: float, leg: bool, team: int) -> void:
	var transform: Transform3D = root.global_transform.affine_inverse() * anchors[upper].global_transform
	var colors := [Color("3689cf") if team == 0 else Color("db7059"), Color("c89470"), Color("d5dfdc")]
	var mesh := ArrayMesh.new()
	var total := length_a + length_b
	var rings := 18
	var sides := 20
	# Adjacent material surfaces share identical positions/weights at their seams.
	for material_index in range(3 if leg else 2):
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		for row in range(rings):
			var y0 := float(row) / rings * total
			var middle := (float(row) + 0.5) / rings * total
			var region := 0 if middle < (0.13 if leg else 0.14) else (2 if leg and middle >= length_a else 1)
			if region != material_index:
				continue
			for side in range(sides):
				for corner in [[row, side], [row + 1, side], [row + 1, side + 1], [row, side], [row + 1, side + 1], [row, side + 1]]:
					var distance := float(corner[0]) / rings * total
					var angle := float(corner[1]) / sides * TAU
					var radius := _radius(distance, length_a, total, leg)
					vertices.append(transform * Vector3(cos(angle) * radius, -distance, sin(angle) * radius * 0.91))
					normals.append((transform.basis * Vector3(cos(angle), 0, sin(angle) / 0.91)).normalized())
					var blend := smoothstep(length_a - 0.065, length_a + 0.065, distance)
					bones.append_array(PackedInt32Array([upper, lower, 0, 0]))
					weights.append_array(PackedFloat32Array([1 - blend, blend, 0, 0]))
					if blend > 0 and blend < 1:
						blended_vertices += 1
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, FootballArt.material(colors[material_index]))
	_attach(root, mesh, skin)

func _radius(distance: float, joint: float, total: float, leg: bool) -> float:
	if distance < joint:
		return lerpf(0.085 if leg else 0.062, 0.047 if leg else 0.037, smoothstep(0.06, joint, distance))
	var phase := (distance - joint) / (total - joint)
	return lerpf(0.047 if leg else 0.037, 0.033 if leg else 0.027, phase) + sin(phase * PI) * (0.014 if leg else 0.006)

func _attach(root: Node3D, mesh: ArrayMesh, skin: Skin) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = "SkinnedSurface" + str(meshes.size())
	root.add_child(instance)
	instance.mesh = mesh
	instance.skin = skin
	instance.skeleton = instance.get_path_to(skeleton)
	instance.custom_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))
	meshes.append(instance)
	return instance

func sync() -> void:
	if skeleton == null:
		return
	for i in range(anchors.size()):
		var pose: Transform3D = skeleton.global_transform.affine_inverse() * anchors[i].global_transform
		if PARENTS[i] >= 0:
			pose = anchors[PARENTS[i]].global_transform.affine_inverse() * anchors[i].global_transform
		skeleton.set_bone_pose(i, pose)
	skeleton.force_update_all_bone_transforms()

func bind_clone(root: Node3D) -> FootballSkinnedAthlete:
	var copy := FootballSkinnedAthlete.new()
	copy.skeleton = root.get_node("AthleteSkeleton") as Skeleton3D
	for path in paths:
		copy.anchors.append(root.get_node(path) as Node3D)
	for child in root.get_children():
		if child is MeshInstance3D and str(child.name).begins_with("SkinnedSurface"):
			copy.meshes.append(child)
			# Explicitly register the duplicated mesh against the clone skeleton.
			child.skeleton = NodePath("")
			child.skeleton = child.get_path_to(copy.skeleton)
	return copy
