extends Node

const CASES := ["slide_ball", "slide_miss", "slide_fall", "slide_glance", "slide_hop", "push", "push_miss", "grab_release", "grab_break", "grab_miss"]
const TIMES := [1.5, 1.5, 1.4, 1.4, 1.4, 0.9, 0.9, 0.9, 0.9, 0.9]
var game: Node3D
var actor: FootballPlayer
var victim: FootballPlayer
var stage := -1
var elapsed := 0.0
var running := false
var checks: Dictionary = {}
var screenshots: Array[String] = []
var observations: Array = []
var challenges_start := 0
var log_start := 0
var origin := Vector3.ZERO
var fallen := false
var stumbled := false
var acquired := false
var released := false
var tension := false
var reacted := false
var captured := false
var finite := true
var slide_lateral := 0.0

func begin(match_node: Node3D) -> void:
	game = match_node
	game.hud.hide()
	actor = game.players[0]
	victim = game.players[3]
	_next()
	running = true

func _next() -> void:
	stage += 1
	if stage >= CASES.size():
		_finish()
		return
	elapsed = 0
	fallen = false
	stumbled = false
	acquired = false
	released = false
	tension = false
	reacted = false
	captured = false
	slide_lateral = 0
	for i in range(game.players.size()):
		var player: FootballPlayer = game.players[i]
		player.reset_action()
		player.freeze = player != actor and player != victim
		player.global_position = Vector3(12, 0.02, -8 + i * 2)
		player.linear_velocity = Vector3.ZERO
		player.angular_velocity = Vector3.ZERO
		player.intent = Vector3.ZERO
		player.aim = Vector3.RIGHT
		player.sprint = false
		player.jockey = false
		player.energy = 1
		player.body_visual.rotation = Vector3(0, -PI / 2, 0)
		player.body_visual.position.y = -0.06
		player.reset_physics_interpolation()
	actor.global_position = Vector3(-3, 0.02, 0)
	victim.global_position = Vector3(8, 0.02, 3)
	game.ball.freeze = false
	game.ball.global_position = Vector3(8, 0.11, -8)
	game.ball.linear_velocity = Vector3.ZERO
	game.ball.angular_velocity = Vector3.ZERO
	game.ball.last_touch_team = 1
	game.ball.last_touch_id = victim.player_id
	game.ball.control_block_remaining = 0
	game._select(0)
	challenges_start = actor.challenge_contacts
	log_start = game.action_log.size()
	origin = actor.global_position
	var label: String = CASES[stage]
	if label.begins_with("slide"):
		actor.linear_velocity = Vector3.RIGHT * (0 if label == "slide_glance" else 6)
		if label == "slide_ball":
			game.ball.global_position = actor.global_position + Vector3(1.1, 0.11, 0)
		elif label in ["slide_fall", "slide_glance", "slide_hop"]:
			victim.global_position = actor.global_position + Vector3(1.0 if label == "slide_glance" else 2.0, 0, 0)
			if label == "slide_hop":
				victim.hop()
		actor.slide(game.ball)
	else:
		if not label.ends_with("miss"):
			victim.global_position = actor.global_position + Vector3(0.85, 0, 0)
		game._controller_actions(0, {"primary": true, "l2": label.begins_with("grab")})
		checks[label + "_contextual_control"] = actor.action_kind == ("grab" if label.begins_with("grab") else "standing" if label == "push_miss" else "push")
		if label == "push_miss":
			actor.reset_action()
			actor.push(game.ball)
	game.camera.size = 5.0
	game.camera.global_position = actor.global_position + Vector3(-1.3, 3.2, 4.6)
	game.camera.look_at(actor.global_position + Vector3(0.5, 0.8, 0))

func _physics_process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	var label: String = CASES[stage]
	if label == "slide_miss" and elapsed > 0.10:
		actor.intent = Vector3.FORWARD
	if actor.action_kind == "slide":
		slide_lateral = maxf(slide_lateral, absf(actor.global_position.z - origin.z))
	if label.begins_with("grab"):
		actor.grab_held = elapsed < 0.42 if label == "grab_release" else true
		if actor.grab_target != null:
			acquired = true
			if elapsed > 0.24:
				victim.intent = Vector3.RIGHT * 0.3
		if acquired and actor.grab_target == null:
			released = true
		if label == "grab_break" and elapsed > 0.4 and actor.grab_target != null:
			victim.linear_velocity = Vector3.RIGHT * 4.5
		tension = tension or actor.last_grab_force.length() > 0.1
	fallen = fallen or victim.ragdoll != null
	stumbled = stumbled or victim.stagger_remaining > 0
	reacted = reacted or (victim.linear_velocity.x > 0.1 and actor.linear_velocity.x < -0.1)
	finite = finite and actor.global_position.is_finite() and victim.global_position.is_finite() and actor.last_grab_force.is_finite()
	if not captured and elapsed >= 0.25:
		captured = true
		_capture(label)
	if elapsed >= TIMES[stage]:
		var body_contacts := 0
		for i in range(log_start, game.action_log.size()):
			if game.action_log[i].kind == "slide_body_contact":
				body_contacts += 1
		match label:
			"slide_ball":
				checks["slide_strikes_ball"] = actor.challenge_contacts > challenges_start
				checks["slide_recovers"] = actor.action_kind == "" and actor.recovery_remaining <= 0 and actor.body_visual.position.y > -0.2
			"slide_miss":
				checks["miss_commits_without_steering"] = actor.global_position.x - origin.x > 1 and slide_lateral < 0.12
				checks["miss_has_no_remote_contact"] = actor.challenge_contacts == challenges_start and body_contacts == 0
			"slide_fall": checks["hard_slide_causes_physical_fall"] = fallen and body_contacts > 0
			"slide_glance": checks["slow_contact_stumbles_without_fall"] = stumbled and not fallen and body_contacts > 0
			"slide_hop": checks["timed_hop_clears_tackling_boot"] = not fallen and body_contacts == 0
			"push": checks["push_contacts_and_reacts_both_bodies"] = actor.challenge_contacts > challenges_start and reacted
			"push_miss": checks["distant_shove_has_no_contact"] = actor.challenge_contacts == challenges_start
			"grab_release":
				checks["grab_has_contact_and_tension"] = acquired and tension
				checks["grab_releases_on_button"] = released and actor.grab_target == null
			"grab_break": checks["movement_breaks_grab"] = acquired and released and actor.grab_target == null
			"grab_miss": checks["grab_has_no_remote_attachment"] = not acquired and actor.challenge_contacts == challenges_start
		observations.append({"case": label, "body_contacts": body_contacts, "fall": fallen, "stumble": stumbled, "grab_acquired": acquired, "grab_released": released, "tension": tension})
		_next()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var filename := label + ".png"
	checks["capture_" + label] = get_viewport().get_texture().get_image().save_png(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join(filename)) == OK
	screenshots.append(filename)

func _finish() -> void:
	running = false
	checks["finite_physics"] = finite
	var report := {"pass": not checks.values().has(false), "checks": checks, "screenshots": screenshots, "observations": observations, "scope": "Finite clean/missed slide, hard/glancing contact, hop clearance, shove reaction and grab contact/release/break. No hardware input or subjective-fun claim."}
	var file := FileAccess.open(OS.get_environment("BASED_FOOTBALL_EVIDENCE").path_join("scene-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	get_tree().quit(0 if report.pass else 1)
