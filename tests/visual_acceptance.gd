extends Node

# Scene integrity checks reused by the single handling session.
func collect_checks(game: Node3D, headless: bool = true) -> Dictionary:
	await get_tree().process_frame
	await get_tree().process_frame
	var checks: Dictionary = {}
	checks["display_mode_matches_scenario"] = (DisplayServer.get_name() == "headless") == headless
	checks["hardware_input_disabled"] = not game.is_physics_processing() and not game.is_processing_unhandled_input()
	checks["isolated_career"] = game.squad.save_path == "user://acceptance_squad.json"
	checks["six_players_and_ball"] = game.players.size() == 6 and is_instance_valid(game.ball)
	checks["camera_preserved"] = game.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and is_equal_approx(game.camera.size, 43) and game.camera.position.is_equal_approx(Vector3(0, 34, 29))
	checks["physics_tick_rate_preserved"] = int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second")) == 120
	var player_shapes_ok := true
	var players_ready := true
	var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/squad.json"))
	for i in range(game.players.size()):
		var player: FootballPlayer = game.players[i]
		var collider := _collider(player)
		if collider == null or not collider.shape is CapsuleShape3D:
			player_shapes_ok = false
			continue
		var shape: CapsuleShape3D = collider.shape
		var entry: Dictionary = definition["players"][i % 3]
		player_shapes_ok = player_shapes_ok and is_equal_approx(shape.radius, 0.39) and is_equal_approx(shape.height, 1.65)
		player_shapes_ok = player_shapes_ok and collider.position.is_equal_approx(Vector3(0, 0.86, 0))
		player_shapes_ok = player_shapes_ok and is_equal_approx(player.mass, float(entry["mass"])) and is_equal_approx(player.pace, float(entry["pace"]))
		player_shapes_ok = player_shapes_ok and player.lock_rotation and player.continuous_cd and not player.can_sleep
		players_ready = players_ready and is_instance_valid(player.body_visual) and is_instance_valid(player.left_leg) and is_instance_valid(player.right_leg) and is_instance_valid(player.ring) and is_instance_valid(player.name_label)
	checks["player_bodies_preserved"] = player_shapes_ok
	checks["six_visuals_with_animation_parts"] = players_ready
	var ball_collider := _collider(game.ball)
	var ball_shape: SphereShape3D = ball_collider.shape if ball_collider != null else null
	checks["football_proportions_and_mass"] = ball_shape != null and is_equal_approx(ball_shape.radius, 0.11) and is_equal_approx(game.ball.mass, 0.43) and is_equal_approx(game.ball.physics_material_override.bounce, 0.48) and is_equal_approx(game.ball.physics_material_override.friction, 0.5)
	var buttons_ok := true
	for binding in [["pass", JOY_BUTTON_A], ["shoot", JOY_BUTTON_B], ["lob", JOY_BUTTON_X], ["through", JOY_BUTTON_Y], ["switch", JOY_BUTTON_LEFT_SHOULDER]]:
		var found := false
		for event in InputMap.action_get_events(binding[0]):
			if event is InputEventJoypadButton and event.button_index == binding[1]:
				found = true
		buttons_ok = buttons_ok and found
	checks["playstation_classic_face_buttons_and_switch"] = buttons_ok
	var triggers_ok := true
	for binding in [["sprint", JOY_AXIS_TRIGGER_RIGHT], ["jockey", JOY_AXIS_TRIGGER_LEFT]]:
		var found := false
		for event in InputMap.action_get_events(binding[0]):
			if event is InputEventJoypadMotion and event.axis == binding[1] and event.axis_value > 0:
				found = true
		triggers_ok = triggers_ok and found
	checks["playstation_classic_triggers"] = triggers_ok
	var expected: Array = [
		[Vector3(70, 0.5, 55), Vector3(0, -0.4, 0)],
		[Vector3(36, 0.25, 24), Vector3(0, -0.13, 0)]
	]
	for side in [-1.0, 1.0]:
		expected.append([Vector3(36.8, 1, 0.35), Vector3(0, 0.5, side * 12.18)])
		for lane in [-1.0, 1.0]:
			expected.append([Vector3(0.35, 1, 9.8), Vector3(side * 18.18, 0.5, lane * 7.25)])
		for z in [-2.3, 2.3]:
			expected.append([Vector3(0.18, 2.4, 0.18), Vector3(side * 18.1, 1.2, z)])
		expected.append([Vector3(0.18, 0.18, 4.78), Vector3(side * 18.1, 2.4, 0)])
		expected.append([Vector3(0.2, 2.4, 4.8), Vector3(side * 20.1, 1.2, 0)])
		for z in [-2.4, 2.4]:
			expected.append([Vector3(2.1, 2.4, 0.15), Vector3(side * 19.1, 1.2, z)])
	var static_count := 0
	var static_shapes_ok := true
	for child in game.get_children():
		if child is StaticBody3D:
			static_count += 1
			var collider := _collider(child)
			if collider == null or not collider.shape is BoxShape3D:
				static_shapes_ok = false
				continue
			var shape: BoxShape3D = collider.shape
			var found := -1
			for i in range(expected.size()):
				if shape.size.is_equal_approx(expected[i][0]) and child.position.is_equal_approx(expected[i][1]):
					found = i
					break
			if found < 0:
				static_shapes_ok = false
			else:
				expected.remove_at(found)
	checks["court_and_goal_collisions_preserved"] = static_shapes_ok and expected.is_empty() and static_count == 20
	var textures: Array[Texture2D] = [FootballArt.TURF, FootballArt.CONCRETE, FootballArt.NET, FootballArt.CONTACT_SHADOW, preload("res://assets/branding/based-football.png")]
	var assets_ok := true
	for texture in textures:
		assets_ok = assets_ok and texture != null and texture.get_width() > 0 and texture.get_height() > 0
	checks["surface_and_badge_assets_loaded"] = assets_ok
	var meshes: Array[Node] = game.find_children("*", "MeshInstance3D", true, false)
	var meshes_ok := not meshes.is_empty()
	for mesh in meshes:
		meshes_ok = meshes_ok and mesh.mesh != null and mesh.material_override != null
	checks["scene_meshes_have_materials"] = meshes_ok
	var fixture_score: Array[int] = [9, 9]
	game.hud.update_match(fixture_score, 180, game.players[2], 1)
	await get_tree().process_frame
	var screen := get_viewport().get_visible_rect()
	var panels: Array[Node] = get_tree().get_nodes_in_group("hud_panels")
	var hud_bounds_ok := panels.size() == 5
	var hud_contents_ok := true
	var hud_overlap_ok := true
	for i in range(panels.size()):
		var panel: Control = panels[i]
		hud_bounds_ok = hud_bounds_ok and screen.encloses(panel.get_global_rect())
		for j in range(i):
			hud_overlap_ok = hud_overlap_ok and not panel.get_global_rect().intersects(panels[j].get_global_rect())
		for child in panel.get_children():
			if child is Control:
				hud_contents_ok = hud_contents_ok and Rect2(Vector2.ZERO, panel.size).encloses(child.get_rect())
	checks["hud_panels_inside_viewport"] = hud_bounds_ok
	checks["hud_content_inside_panels"] = hud_contents_ok
	checks["hud_panels_do_not_overlap"] = hud_overlap_ok
	return checks

func _collider(body: Node) -> CollisionShape3D:
	for child in body.get_children():
		if child is CollisionShape3D:
			return child
	return null

func begin(game: Node3D) -> void:
	if "--coordination-check" in OS.get_cmdline_user_args():
		var fixture = load("res://tests/team_coordination_acceptance.gd").new()
		game.add_child(fixture)
		fixture.begin(game)
		return
	if "--passing-check" in OS.get_cmdline_user_args():
		var fixture = load("res://tests/passing_acceptance.gd").new()
		game.add_child(fixture)
		fixture.begin(game)
		return
	if "--referee-check" in OS.get_cmdline_user_args():
		var fixture = load("res://tests/referee_acceptance.gd").new()
		game.add_child(fixture)
		fixture.begin(game)
		return
	if "--celebration-check" in OS.get_cmdline_user_args():
		var fixture = load("res://tests/celebration_acceptance.gd").new()
		game.add_child(fixture)
		fixture.begin(game)
		return
	if "--realistic-player-check" in OS.get_cmdline_user_args():
		var fixture = load("res://tests/realistic_player_acceptance.gd").new()
		game.add_child(fixture)
		fixture.begin(game)
		return
	var checks := await collect_checks(game)
	var passed := true
	for value in checks.values():
		passed = passed and bool(value)
	var report := {"pass": passed, "checks": checks, "rendered_frames": 0, "hardware_input_injected": false, "visual_quality_verified": false}
	var destination := OS.get_environment("BASED_FOOTBALL_EVIDENCE")
	var file := FileAccess.open(destination.path_join("scene-report.json"), FileAccess.WRITE)
	if file == null:
		push_error("Could not write scene integrity report.")
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("VISUAL_SCENE_RESULT: " + JSON.stringify(report))
	get_tree().quit(0 if passed else 1)
