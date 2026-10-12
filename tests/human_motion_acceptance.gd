extends Node

const CASES := ["walk", "sprint", "turn", "stop", "slide", "hop", "dribble", "kick", "dribble_left", "dribble_right", "dribble_turn", "dribble_stop", "escape"]
const TIMES := [0.8, 1.0, 1.0, 0.8, 1.5, 1.6, 1.3, 0.9, 0.7, 0.7, 1.5, 1.4, 0.3]
var game: Node3D
var actor: FootballPlayer
var player_index := 0
var stage := -1
var elapsed := 0.0
var running := false
var checks: Dictionary = {}
var screenshots: Array[String] = []
var traces: Array = []
var styles: Dictionary = {}
var ai_states: Array = []
var pace_values: Array = []
var sample_times: Array[float] = []
var sample_index := 0
var min_foot := INF
var max_joint_step := 0.0
var previous_leg := Quaternion.IDENTITY
var previous_knee := Quaternion.IDENTITY
var max_height := 0.0
var crouch_seen := false
var slide_low_seen := false
var tuck_seen := false
var extend_seen := false
var landing_seen := false
var touches_start := 0
var kicks_start := 0
var challenges_start := 0
var finite := true
var left_start := 0
var right_start := 0
var max_gap := 0.0

func begin(match_node: Node3D) -> void:
	game = match_node
	game.hud.hide()
	for player in game.players:
		ai_states.append(player.ai_rng.state)
		pace_values.append(player.pace)
	_next()
	running = true

func _next() -> void:
	stage += 1
	if stage >= CASES.size():
		stage = 0
		player_index += 1
	if player_index >= game.players.size():
		_finish()
		return
	actor = game.players[player_index]
	for i in range(game.players.size()):
		var player: FootballPlayer = game.players[i]
		player.reset_action()
		player.freeze = player != actor
		player.global_position = Vector3(-3, 0.02, 0) if player == actor else Vector3(13, 0.02, -10 + i * 3)
		player.linear_velocity = Vector3.ZERO
		player.angular_velocity = Vector3.ZERO
		player.intent = Vector3.ZERO
		player.sprint = false
		player.jockey = false
		player.energy = 1
		player.touch_cooldown = 0
		player.kick_cooldown = 0
		player.aim = Vector3.RIGHT
		player.body_visual.rotation = Vector3(0, -PI / 2, 0)
		player.body_visual.position.y = 0
		player.reset_physics_interpolation()
	game.ball.freeze = true
	game.ball.global_position = actor.global_position + Vector3(0.61, 0.11, 0)
	game.ball.linear_velocity = Vector3.ZERO
	game.ball.angular_velocity = Vector3.ZERO
	game.ball.control_block_remaining = 0
	game.ball.last_touch_id = actor.player_id
	game.ball.last_touch_team = actor.team
	if CASES[stage] in ["walk", "sprint", "turn", "stop"]:
		# A parked frozen rigid ball must not obstruct a locomotion fixture.
		game.ball.global_position = Vector3(12, 0.11, 11)
	elapsed = 0
	sample_index = 0
	sample_times = [0.18, 0.48]
	if CASES[stage] == "slide":
		sample_times = [0.05, 0.22, 0.48, 0.78, 1.25]
	elif CASES[stage] == "hop":
		sample_times = [0.05, 0.18, 0.42, 0.68, 0.90, 1.20]
	min_foot = INF
	max_joint_step = 0
	max_height = 0
	crouch_seen = false
	slide_low_seen = false
	tuck_seen = false
	extend_seen = false
	landing_seen = false
	touches_start = actor.completed_dribble_contacts
	left_start = actor.left_dribble_contacts
	right_start = actor.right_dribble_contacts
	max_gap = 0
	kicks_start = actor.completed_kicks
	challenges_start = actor.challenge_contacts
	previous_leg = actor.right_leg.quaternion
	previous_knee = actor.visual_controller.right_knee.quaternion
	var style: FootballPlayerVisual = actor.visual_controller
	styles[actor.player_id] = {"cadence": style.cadence_style, "arms": style.arm_style, "posture": style.posture_style}
	match CASES[stage]:
		"walk", "turn": actor.intent = Vector3.RIGHT
		"sprint":
			actor.intent = Vector3.RIGHT
			actor.sprint = true
		"stop": actor.linear_velocity = Vector3.RIGHT * 4
		"slide":
			game.ball.freeze = false
			game.ball.global_position = actor.global_position + Vector3(0.85, 0.11, 0)
			actor.slide(game.ball)
		"hop": actor.hop()
		"dribble":
			game.ball.freeze = false
			actor.intent = Vector3.RIGHT * 0.6
		"kick":
			game.ball.freeze = false
			actor.kick(game.ball, Vector3.RIGHT, 18, 1.5, "shot")
		"dribble_left", "dribble_right", "dribble_turn", "dribble_stop", "escape":
			game.ball.freeze = false
			actor.intent = Vector3.RIGHT * 0.6
			if CASES[stage] in ["dribble_left", "dribble_right"]:
				game.ball.global_position = actor.global_position + Vector3(0.55, 0.11, 0) + actor.body_visual.basis.x * (-0.22 if CASES[stage] == "dribble_left" else 0.22)
			elif CASES[stage] == "escape":
				game.ball.global_position += Vector3.RIGHT * 2
	game.camera.size = 4.5
	_follow_camera()

func _follow_camera() -> void:
	game.camera.global_position = actor.global_position + Vector3(-1.3, 2.7, 4.0)
	game.camera.look_at(actor.global_position + Vector3(0.25, 0.8, 0))

func _physics_process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	if CASES[stage] == "turn" and elapsed > 0.45:
		actor.intent = Vector3.FORWARD
	if CASES[stage] == "dribble_turn" and elapsed > 0.5:
		actor.intent = Vector3.FORWARD * 0.6
	elif CASES[stage] == "dribble_stop" and elapsed > 0.5:
		actor.intent = Vector3.ZERO
	if "dribble" in CASES[stage] or CASES[stage] == "escape":
		game._control_ball()
		var gap: Vector3 = game.ball.global_position - actor.global_position
		gap.y = 0
		max_gap = maxf(max_gap, gap.length())
	var left: Vector3 = actor.visual_controller.left_boot.global_position
	var right: Vector3 = actor.visual_controller.right_boot.global_position
	finite = finite and left.is_finite() and right.is_finite() and actor.global_position.is_finite()
	if elapsed > 0.15:
		min_foot = minf(min_foot, minf(left.y, right.y))
		if actor.action_kind == "":
			max_joint_step = maxf(max_joint_step, maxf(previous_leg.angle_to(actor.right_leg.quaternion), previous_knee.angle_to(actor.visual_controller.right_knee.quaternion)))
	previous_leg = actor.right_leg.quaternion
	previous_knee = actor.visual_controller.right_knee.quaternion
	max_height = maxf(max_height, actor.global_position.y)
	crouch_seen = crouch_seen or (actor.hop_active and not actor.hop_launched and actor.body_visual.position.y < -0.08)
	slide_low_seen = slide_low_seen or (actor.action_kind == "slide" and actor.body_visual.position.y < -0.45)
	if actor.hop_active and actor.hop_launched:
		var boot_height: float = right.y - actor.global_position.y
		tuck_seen = tuck_seen or (actor.linear_velocity.y > 1 and boot_height > 0.22)
		extend_seen = extend_seen or (actor.linear_velocity.y < -1 and boot_height < 0.18)
	landing_seen = landing_seen or actor.hop_landing_remaining > 0
	_follow_camera()
	if sample_index < sample_times.size() and elapsed >= sample_times[sample_index]:
		_capture(actor.player_id + "_" + CASES[stage] + "_" + str(sample_index))
		sample_index += 1
	if elapsed >= TIMES[stage]:
		var key: String = actor.player_id + "_" + CASES[stage]
		checks[key + "_feet_above_ground"] = min_foot > 0.015
		if CASES[stage] in ["walk", "sprint", "turn", "stop", "hop", "dribble", "dribble_left", "dribble_right", "dribble_turn", "dribble_stop"]:
			checks[key + "_bounded_joint_changes"] = max_joint_step < 0.20
		if CASES[stage] == "slide":
			checks[key + "_descends_and_recovers"] = slide_low_seen and actor.body_visual.position.y > -0.15 and actor.recovery_remaining <= 0
			checks[key + "_physical_ball_contact"] = actor.challenge_contacts > challenges_start
		elif CASES[stage] == "hop":
			checks[key + "_preparation"] = crouch_seen
			checks[key + "_flight_phases"] = max_height > 0.4 and tuck_seen and extend_seen
			checks[key + "_landing"] = landing_seen and not actor.hop_active
		elif "dribble" in CASES[stage]:
			checks[key + "_physical_ball_contact"] = actor.completed_dribble_contacts > touches_start
			if CASES[stage] == "dribble_left":
				checks[key + "_selected_left_boot_contact"] = actor.left_dribble_contacts > left_start
			elif CASES[stage] == "dribble_right":
				checks[key + "_selected_right_boot_contact"] = actor.right_dribble_contacts > right_start
			elif CASES[stage] in ["dribble_turn", "dribble_stop"]:
				checks[key + "_control_retained"] = max_gap < 1.2
		elif CASES[stage] == "escape":
			checks[key + "_no_remote_touch"] = actor.completed_dribble_contacts == touches_start
		elif CASES[stage] == "kick":
			checks[key + "_physical_ball_contact"] = actor.completed_kicks > kicks_start
		traces.append({"player": actor.player_id, "case": CASES[stage], "minimum_boot_height": min_foot, "max_joint_step": max_joint_step, "jump_height": max_height, "max_control_gap": max_gap, "left_contacts": actor.left_dribble_contacts - left_start, "right_contacts": actor.right_dribble_contacts - right_start})
		_next()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var filename := label + ".png"
	checks["capture_" + label] = get_viewport().get_texture().get_image().save_png(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join(filename)) == OK
	screenshots.append(filename)

func _finish() -> void:
	running = false
	var distinct: Dictionary = {}
	var cosmetic_only := true
	for i in range(game.players.size()):
		var player: FootballPlayer = game.players[i]
		distinct[player.visual_controller.cadence_style] = true
		cosmetic_only = cosmetic_only and player.ai_rng.state == ai_states[i] and player.pace == pace_values[i]
	checks["six_distinct_movement_styles"] = distinct.size() == 6
	checks["AI_random_state_and_pace_preserved"] = cosmetic_only
	checks["finite_transforms"] = finite
	var report := {"pass": not checks.values().has(false), "checks": checks, "screenshots": screenshots, "styles": styles, "foot_contact_totals": _foot_totals(), "traces": traces, "scope": "One finite sequence for all six athletes. Ground, joint, action-phase and physical-contact evidence; visual quality requires frame inspection. No controller or full-match claim."}
	var file := FileAccess.open(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join("scene-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	get_tree().quit(0 if report.pass else 1)

func _foot_totals() -> Dictionary:
	var counts: Dictionary = {}
	for player in game.players:
		counts[player.player_id] = {"left": player.left_dribble_contacts, "right": player.right_dribble_contacts}
	return counts
