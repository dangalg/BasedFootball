extends Node

# One bounded sequence, no hardware input, isolated career data and no retries.
var CASES := ["models", "blue_run", "orange_sprint", "turn", "dribble", "weak_shot", "strong_shot", "moving_shot", "missed_shot", "slide", "hop", "fall"]
var DURATIONS := [0.8, 1.6, 1.6, 1.6, 1.8, 1.2, 1.2, 1.2, 1.2, 1.5, 1.8, 5.5]
var game: Node3D
var actor: FootballPlayer
var stage := -1
var elapsed := 0.0
var running := false
var screenshots: Array[String] = []
var checks: Dictionary = {}
var capture_index := 0
var next_capture := 0.15
var fall_seen := false
var recovery_seen := false
var max_lift := 0.0
var planted_samples := 0
var finite := true
var kick_start := 0
var touch_start := 0
var shot_speeds: Dictionary = {}
var shot_traces: Array = []
var contact_seen := false
var no_early_impulse := true
var max_follow_lift := 0.0
var skin_pose_valid := true
var shot_trials := 0
var shot_hits := 0
var matrix: Dictionary = {}
var matrix_displaced := false
var sample_after := -1.0
var max_boot_error := 0.0
var boot_errors: Array = []

func begin(match_node: Node3D) -> void:
	game = match_node
	game.hud.hide()
	# Six reachable attempts per movement class: two powers and three offsets.
	for movement in ["standing", "walking", "sprinting", "turning"]:
		for power in [0, 1]:
			for gap in [0.45, 0.61, 0.75]:
				var label: String = "shot_matrix_" + movement + "_" + str(power) + "_" + str(int(gap * 100))
				CASES.append(label)
				DURATIONS.append(0.8)
				matrix[label] = {"movement": movement, "power": power, "gap": gap, "miss": false}
	for movement in ["standing", "walking", "sprinting", "turning"]:
		var label: String = "shot_deflected_" + movement
		CASES.append(label)
		DURATIONS.append(0.8)
		matrix[label] = {"movement": movement, "power": 1, "gap": 0.61, "miss": true}
	checks["first_athlete_is_skinned"] = game.players[0].visual_controller.skinned != null
	var skin: FootballSkinnedAthlete = game.players[0].visual_controller.skinned
	checks["blended_joint_vertices"] = skin.blended_vertices > 100
	checks["skeleton_has_13_bones"] = skin.skeleton.get_bone_count() == 13
	for mesh in skin.meshes:
		for surface in range(mesh.mesh.get_surface_count()):
			var weights: PackedFloat32Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_WEIGHTS]
			for index in range(0, weights.size(), 4):
				skin_pose_valid = skin_pose_valid and absf(weights[index] + weights[index + 1] + weights[index + 2] + weights[index + 3] - 1) < 0.001
	for player in game.players:
		player.physical_event.connect(_event)
	_capture("match_camera")
	await RenderingServer.frame_post_draw
	_next()
	running = true

func _event(kind: String, _detail: Dictionary) -> void:
	fall_seen = fall_seen or kind == "fall"
	recovery_seen = recovery_seen or kind == "get_up"

func _next() -> void:
	stage += 1
	if stage >= CASES.size():
		_finish()
		return
	elapsed = 0
	capture_index = 0
	next_capture = 0.15
	max_lift = 0
	contact_seen = false
	no_early_impulse = true
	max_follow_lift = 0
	matrix_displaced = false
	sample_after = -1
	planted_samples = 0
	actor = game.players[3] if CASES[stage] == "orange_sprint" else game.players[0]
	for i in range(game.players.size()):
		var player: FootballPlayer = game.players[i]
		player.reset_action()
		player.freeze = player != actor
		player.global_position = Vector3(-3, 0.02, 0) if player == actor else Vector3(9, 0.02, -9 + i * 3)
		player.linear_velocity = Vector3.ZERO
		player.angular_velocity = Vector3.ZERO
		player.intent = Vector3.ZERO
		player.sprint = false
		player.energy = 1
		player.touch_cooldown = 0
		player.kick_cooldown = 0
		player.hop_cooldown = 0
		player.body_visual.position.y = 0
		player.aim = Vector3.RIGHT
		player.body_visual.rotation = Vector3(0, -PI / 2, 0)
		player.reset_physics_interpolation()
	game.ball.control_block_remaining = 0
	game.ball.freeze = true
	game.ball.global_position = actor.global_position + Vector3(0.56, 0.10, 0)
	game.ball.linear_velocity = Vector3.ZERO
	game.ball.angular_velocity = Vector3.ZERO
	game.camera.size = 5.8
	game.camera.global_position = actor.global_position + Vector3(-1.2, 3.2, 4.2)
	game.camera.look_at(actor.global_position + Vector3(0, 0.95, 0))
	kick_start = actor.completed_kicks
	touch_start = actor.completed_dribble_contacts
	match CASES[stage]:
		"models":
			game.players[3].global_position = actor.global_position + Vector3(1.3, 0, 0)
			game.players[3].aim = Vector3.LEFT
			game.players[3].body_visual.rotation.y = PI / 2
		"blue_run", "turn": actor.intent = Vector3.RIGHT
		"orange_sprint":
			actor.intent = Vector3.RIGHT
			actor.sprint = true
		"dribble":
			game.ball.freeze = false
			actor.intent = Vector3.RIGHT * 0.6
		"weak_shot", "strong_shot", "moving_shot", "missed_shot":
			game.ball.freeze = false
			game.ball.control_block_remaining = 0
			var strong: bool = CASES[stage] != "weak_shot"
			if CASES[stage] == "moving_shot":
				actor.linear_velocity = Vector3.RIGHT * 3
				actor.intent = Vector3.RIGHT
				game.ball.linear_velocity = Vector3.RIGHT * 3
			checks[CASES[stage] + "_requested"] = actor.kick(game.ball, Vector3.RIGHT, 23 if strong else 12, 3.2 if strong else 0.7, "shot")
			if CASES[stage] == "missed_shot":
				game.ball.global_position += Vector3.FORWARD * 2
		"slide": checks["slide_requested"] = actor.slide(game.ball)
		"hop": checks["hop_requested"] = actor.hop()
		"fall": actor.receive_slide(Vector3(220, 0, 0), actor.global_position + Vector3(0, 0.1, 0), 10)
	if matrix.has(CASES[stage]):
		var spec: Dictionary = matrix[CASES[stage]]
		var speed: float = 0 if spec.movement == "standing" else 6.9 if spec.movement == "sprinting" else 3
		actor.linear_velocity = Vector3.RIGHT * speed
		actor.intent = Vector3.FORWARD if spec.movement == "turning" else Vector3.RIGHT if speed > 0 else Vector3.ZERO
		actor.sprint = spec.movement == "sprinting"
		game.ball.global_position = actor.global_position + Vector3(float(spec.gap), 0.11, 0)
		game.ball.freeze = false
		game.ball.linear_velocity = Vector3.RIGHT * speed
		var direction: Vector3 = Vector3.FORWARD if spec.movement == "turning" else Vector3.RIGHT
		checks[CASES[stage] + "_requested"] = actor.kick(game.ball, direction, 23 if spec.power else 12, 3.2 if spec.power else 0.7, "shot")

func _physics_process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	if CASES[stage] == "turn" and elapsed > 0.7:
		actor.intent = Vector3.FORWARD
	if CASES[stage] == "dribble":
		game._control_ball()
	if matrix.has(CASES[stage]) and matrix[CASES[stage]].miss and not matrix_displaced and elapsed >= actor.kick_contact_time * 0.66:
		matrix_displaced = true
		game.ball.apply_central_impulse(Vector3.FORWARD * game.ball.mass * 14)
	if "shot" in CASES[stage]:
		if actor.action_kind == "kick" and actor.action_elapsed < actor.kick_contact_time - 0.015:
			no_early_impulse = no_early_impulse and actor.completed_kicks == kick_start
		if actor.completed_kicks > kick_start and not contact_seen:
			contact_seen = true
			sample_after = elapsed + delta
			_capture(CASES[stage] + "_contact")
		if sample_after >= 0 and elapsed >= sample_after:
			shot_speeds[CASES[stage]] = game.ball.linear_velocity.length()
			shot_traces.append({"case": CASES[stage], "time": elapsed, "contact_distance": actor.last_kick_contact_distance, "swing_speed": actor.last_strike_speed, "quality": actor.last_strike_quality, "ball_speed": game.ball.linear_velocity.length(), "ball_spin": game.ball.angular_velocity.length()})
			sample_after = -1
		if elapsed > actor.kick_contact_time:
			max_follow_lift = maxf(max_follow_lift, actor.visual_controller.right_boot.global_position.y)
	for player in game.players:
		finite = finite and player.global_position.is_finite() and player.visual_controller.right_boot.global_position.is_finite()
	var left: Vector3 = actor.visual_controller.left_boot.global_position
	var right: Vector3 = actor.visual_controller.right_boot.global_position
	max_lift = maxf(max_lift, maxf(left.y, right.y))
	if minf(left.y, right.y) < 0.13 and minf(left.y, right.y) > -0.03:
		planted_samples += 1
	game.camera.global_position = actor.global_position + Vector3(-1.2, 3.2, 4.2)
	game.camera.look_at(actor.global_position + Vector3(0, 0.95, 0))
	if elapsed >= next_capture and capture_index < 4:
		next_capture += DURATIONS[stage] / 4
		capture_index += 1
		_capture(CASES[stage] + "_" + str(capture_index))
	if elapsed >= DURATIONS[stage]:
		match CASES[stage]:
			"blue_run", "orange_sprint":
				checks[CASES[stage] + "_planted_steps"] = planted_samples > 10
				checks[CASES[stage] + "_swing_clearance"] = max_lift > 0.15
			"dribble": checks["visible_boot_dribble_contact"] = actor.completed_dribble_contacts > touch_start
			"weak_shot", "strong_shot", "moving_shot", "missed_shot":
				checks[CASES[stage] + "_no_early_impulse"] = no_early_impulse
				checks[CASES[stage] + "_contact_or_miss"] = actor.completed_kicks == kick_start if CASES[stage] == "missed_shot" else actor.completed_kicks > kick_start
				if CASES[stage] != "missed_shot":
					checks[CASES[stage] + "_follow_through"] = max_follow_lift > 0.22
			"hop": checks["hop_landed"] = not actor.hop_active
			"fall":
				checks["physical_fall"] = fall_seen
				checks["recovered_model"] = recovery_seen and actor.body_visual.visible and actor.ragdoll == null
		if matrix.has(CASES[stage]):
			if matrix[CASES[stage]].miss:
				checks[CASES[stage] + "_misses"] = actor.completed_kicks == kick_start
			else:
				shot_trials += 1
				if actor.completed_kicks > kick_start:
					shot_hits += 1
		_next()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	# Compare the baked boot and its anchor from this completed render frame.
	var skin: FootballSkinnedAthlete = actor.visual_controller.skinned if actor != null else game.players[0].visual_controller.skinned
	if skin != null and (actor == null or actor.ragdoll == null or actor.getting_up):
		for mesh in skin.meshes:
			if mesh.get_meta("source_bone", -1) != 8:
				continue
			var baked := mesh.bake_mesh_from_current_skeleton_pose()
			var points: PackedVector3Array = baked.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var raw: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var error := 0.0
			for index in range(points.size()):
				var actual: Vector3 = mesh.global_transform * points[index]
				var expected: Vector3 = skin.anchors[8].global_transform * mesh.skin.get_bind_pose(8) * raw[index]
				error = maxf(error, actual.distance_to(expected))
			max_boot_error = maxf(max_boot_error, error)
			boot_errors.append({"frame": label, "max_vertex_error": error})
	var filename := label + ".png"
	var result := get_viewport().get_texture().get_image().save_png(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join(filename))
	checks["capture_" + label] = result == OK
	screenshots.append(filename)

func _finish() -> void:
	running = false
	checks["finite_transforms"] = finite
	checks["normalized_skin_weights"] = skin_pose_valid
	checks["rendered_boot_matches_contact_anchor"] = max_boot_error < 0.03
	checks["reachable_shot_success_at_least_95_percent"] = shot_trials == 24 and float(shot_hits) / shot_trials >= 0.95
	checks["charged_shot_more_powerful"] = shot_speeds.get("strong_shot", 0) > shot_speeds.get("weak_shot", 0) + 3
	var passed := not checks.values().has(false)
	var report := {"pass": passed, "checks": checks, "screenshots": screenshots, "shot_traces": shot_traces, "shot_hits": shot_hits, "shot_trials": shot_trials, "boot_errors": boot_errors, "max_boot_error": max_boot_error, "scope": "One skinned athlete and shot sequence, including actual boot pose, shot variants, misses and physical ragdoll handoff. No hardware controller or full-match regression."}
	var file := FileAccess.open(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join("scene-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	get_tree().quit(0 if passed else 1)
