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
	_kit_details(player,visual)
	var number := FootballArt.text(visual.upper_body, str(player.shirt_number), Vector3(0, 0.38, 0.145), 44, Color("f2eee4"))
	number.pixel_size = 0.0034
	number.outline_size = 0
	number.rotation.y = PI
	if player.team < 0:
		number.hide()
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
				"TShirt":
					material.albedo_color = Color("307fb8") if player.team == 0 else Color("c76b53")
					material.roughness=.86
					material.metallic_specular=.22
				"FootballShorts":
					material.albedo_color = Color("263b4e") if player.team == 0 else Color("49353b")
					material.roughness=.9
					material.metallic_specular=.18
				"FootballSocks":
					material.albedo_color=Color("dfddd1")
					material.roughness=.94
					material.metallic_specular=.12
				"Skin":
					material.albedo_color = [Color("bd8b6c"), Color("95694e"), Color("d3a98b")][variant]
					material.roughness=.68
					material.metallic_specular=.3
				"Hair", "Eyebrows":
					material.albedo_color = [Color("302925"), Color("493426"), Color("211e1c")][variant]
					material.roughness=.82
					material.metallic_specular=.2
				"Iris":
					material.albedo_color=[Color("6c5941"),Color("3d6058"),Color("48596a")][variant]
					material.roughness=.26
				"EyeSclera":
					material.albedo_color=Color("d8d7ce")
					material.roughness=.22
				"Shoes":
					material.albedo_color=[Color("292b2b"),Color("352d29"),Color("26272a")][variant]
					material.roughness=.38
					material.metallic_specular=.42
			if player.team < 0 and original.resource_name in ["TShirt","FootballShorts","FootballSocks"]:
				material.albedo_color = Color("242830")
			mesh.set_surface_override_material(surface, material)

func _kit_details(player: Node3D, visual: FootballPlayerVisual) -> void:
	if player.team<0:
		return
	# Original, unbranded cloth trim follows the same torso/arm anchors as skin.
	var trim:=FootballArt.material(Color("e0dccb"),.9)
	var ink:=FootballArt.material(Color("24333b"),.86)
	for arm in [visual.left_arm,visual.right_arm]:
		FootballArt.cylinder(arm,.068,.012,Vector3(0,-.175,0),trim)
	var badge:=FootballArt.sphere(visual.upper_body,.026,Vector3(-.105,.425,-.146),trim)
	badge.scale=Vector3(.85,1,.10)
	FootballArt.box(visual.upper_body,Vector3(.008,.025,.003),Vector3(-.105,.425,-.151),ink)
	for boot in [visual.left_boot,visual.right_boot]:
		for lace in range(3):
			FootballArt.box(boot,Vector3(.057,.005,.009),Vector3(0,.037,-.038-lace*.018),trim)

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
