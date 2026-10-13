class_name FootballRealisticAthlete
extends FootballSkinnedAthlete

# The exported rest has been fitted to these same physical contact anchors.
const MODEL = preload("res://assets/characters/squad/model.glb")
var bone_ids: Array[int] = []
var offsets: Array[Transform3D] = []

func build(player: Node3D, visual: FootballPlayerVisual) -> void:
	var root: Node3D = player.body_visual
	anchors = [root, visual.upper_body, visual.head_pivot, player.left_leg, visual.left_knee, visual.left_boot, player.right_leg, visual.right_knee, visual.right_boot, visual.left_arm, visual.left_elbow, visual.right_arm, visual.right_elbow]
	_hide_primitives(root)
	var model := MODEL.instantiate() as Node3D
	model.name = "RealisticAthlete"
	root.add_child(model)
	_collect(model)
	_style(player)
	var number := FootballArt.text(visual.upper_body, str(player.shirt_number), Vector3(0, 0.38, 0.145), 44, Color("f2eee4"))
	number.pixel_size = 0.0034
	number.outline_size = 0
	number.rotation.y = PI
	skeleton.name = "RealisticSkeleton"
	for mesh in meshes:
		mesh.skeleton = NodePath("")
		mesh.skeleton = mesh.get_path_to(skeleton)
	for i in range(anchors.size()):
		paths.append(root.get_path_to(anchors[i]))
		var index := skeleton.find_bone("A" + str(i))
		bone_ids.append(index)
		var rest: Transform3D = skeleton.global_transform * skeleton.get_bone_global_rest(index)
		offsets.append(anchors[i].global_transform.affine_inverse() * rest)
	sync()

func _style(player: Node3D) -> void:
	var variant := absi(str(player.player_id).hash()) % 3
	for mesh in meshes:
		for surface in range(mesh.mesh.get_surface_count()):
			var original := mesh.get_active_material(surface) as StandardMaterial3D
			if original == null:
				continue
			var material := original.duplicate() as StandardMaterial3D
			match original.resource_name:
				"TShirt": material.albedo_color = Color("3689cf") if player.team == 0 else Color("db7059")
				"FootballShorts": material.albedo_color = Color("203b55") if player.team == 0 else Color("51343d")
				"Skin": material.albedo_color = [Color("c89470"), Color("8f6248"), Color("d6ab88")][variant]
				"Hair", "Eyebrows": material.albedo_color = [Color("302925"), Color("493426"), Color("211e1c")][variant]
			mesh.set_surface_override_material(surface, material)

func _hide_primitives(node: Node) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D:
			child.hide()
		_hide_primitives(child)

func _collect(node: Node) -> void:
	if node is Skeleton3D:
		skeleton = node
	if node is MeshInstance3D:
		meshes.append(node)
		node.custom_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))
	for child in node.get_children():
		_collect(child)

func sync() -> void:
	if skeleton == null:
		return
	var poses: Dictionary = {}
	for i in range(bone_ids.size()):
		poses[bone_ids[i]] = skeleton.global_transform.affine_inverse() * anchors[i].global_transform * offsets[i]
	for index in bone_ids:
		var parent := skeleton.get_bone_parent(index)
		var pose: Transform3D = poses[index]
		if parent >= 0:
			pose = (poses[parent] as Transform3D).affine_inverse() * pose
		skeleton.set_bone_pose(index, pose)
	skeleton.force_update_all_bone_transforms()

func bind_clone(root: Node3D) -> FootballSkinnedAthlete:
	var copy := FootballRealisticAthlete.new()
	copy._collect(root.get_node("RealisticAthlete"))
	copy.bone_ids = bone_ids.duplicate()
	copy.offsets = offsets.duplicate()
	for path in paths:
		copy.anchors.append(root.get_node(path) as Node3D)
	for mesh in copy.meshes:
		mesh.skeleton = NodePath("")
		mesh.skeleton = mesh.get_path_to(copy.skeleton)
	return copy
