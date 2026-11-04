extends "res://tests/eleven_shot_setup_acceptance.gd"

## Movie Maker --script res://tests/eleven_ai_slide_selection_acceptance.gd
## -- --report=<fresh absolute JSON path>.

const SHIELD_DIRECTION := Vector3.RIGHT
const DEFENDER_SPEED := 5.0

var _fixture: Node3D
var _carrier: FootballPlayer
var _active := false
var _decisions: Array[Dictionary] = []
var _slide_touches: Array[Dictionary] = []
var _opening: Dictionary = {}


func _run() -> void:
	var report_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			report_path = argument.trim_prefix("--report=")
	if not report_path.is_absolute_path() or FileAccess.file_exists(report_path):
		push_error("Use -- --report=<fresh absolute JSON path>.")
		quit(2)
		return
	_build_world()
	var seed_value := _challenge_seed()
	var shielded := await _exercise(true, seed_value)
	var exposed := await _exercise(false, seed_value)
	var checks := {
		"both_cases_open_with_a_real_carrier_and_prior_slide_geometry": shielded["opening"]["prior_window"] and exposed["opening"]["prior_window"],
		"ball_reachable_by_slide_in_both_openings": shielded["opening"]["slide_reach_seconds"] >= 0.08 and shielded["opening"]["slide_reach_seconds"] <= 0.26 and exposed["opening"]["slide_reach_seconds"] >= 0.08 and exposed["opening"]["slide_reach_seconds"] <= 0.26,
		"inline_shield_keeps_defender_pressing_without_sliding": shielded["opening"]["carrier_blocks_lane"] and shielded["continued_pressure"] and not shielded["queued_slide"] and shielded["body_contacts"] == 0,
		"shielded_carrier_runs_on": shielded["carrier_progress_m"] >= 1.2 and not shielded["carrier_fell"],
		"exposed_roll_draws_ai_slide_and_real_ball_first_deflection": not exposed["opening"]["carrier_blocks_lane"] and exposed["queued_slide"] and exposed["ball_first"],
		"ball_remains_free_in_both_cases": shielded["free"] and exposed["free"],
	}
	var passed := not checks.values().has(false)
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write AI slide selection report.")
		quit(2)
		return
	file.store_string(JSON.stringify({
		"passed": passed, "checks": checks, "physics_hz": Engine.physics_ticks_per_second,
		"fixture": "Fresh bodies and one real starting roll per case. Same opening AI RNG seed. The live AI alone chooses every challenge, and the fixture never moves the ball or bodies after activation.",
		"ai_seed": seed_value, "shielded": shielded, "exposed": exposed,
	}, "\t") + "\n")
	file.close()
	print("ELEVEN_AI_SLIDE_SELECTION_ACCEPTANCE %s %s" % ["PASS" if passed else "FAIL", report_path])
	quit(0 if passed else 1)


func _exercise(shielded: bool, seed_value: int) -> Dictionary:
	_fixture = Node3D.new()
	_world.add_child(_fixture)
	_samples = []
	_events = []
	_decisions = []
	_slide_touches = []
	_opening = {}
	var squad := FootballSquad.new()
	squad.load_squad(true, true)
	_player = _create_player(squad, 1, 0, Vector3(0, 0.05, 0))
	_carrier = _create_player(squad, 0, 1, Vector3(0.91 if shielded else 2.10, 0.05, 0.0 if shielded else 0.90))
	_carrier.selected = true
	_player.physical_event.connect(_observe_actor_event.bind(_player.player_id))
	_carrier.physical_event.connect(_observe_actor_event.bind(_carrier.player_id))
	_ball = FootballBall.new()
	_ball.position = Vector3(1.57 if shielded else 1.66, FootballBall.RADIUS, 0.0)
	_fixture.add_child(_ball)
	_ball.played.connect(_observe_ball_touch)
	_adapter = MatchInput.new()
	_adapter.eleven_a_side = true
	_adapter.controlled = _carrier
	_adapter.players.assign([_player, _carrier])
	_adapter.ball = _ball
	var label := "Shielded carry" if shielded else "Exposed roll"
	await _drive(label + " / ready", Vector3.ZERO, false, 0.32)
	var carrier_start := _carrier.global_position
	_player.ai_rng.seed = seed_value
	_player.linear_velocity = SHIELD_DIRECTION * DEFENDER_SPEED
	_carrier.intent = SHIELD_DIRECTION * (0.87 if shielded else 0.30)
	_carrier.linear_velocity = SHIELD_DIRECTION * (3.3 if shielded else 0.8)
	_ball.touch(_carrier.team, _carrier.player_id, SHIELD_DIRECTION * _ball.mass * (3.3 if shielded else 0.62))
	_carrier._remember_free_ball(_ball, SHIELD_DIRECTION)
	_active = true
	await _drive(label + " / live AI", Vector3.ZERO, false, 0.80)
	_active = false
	var result := _evaluate_case(carrier_start)
	result.merge({"decisions": _decisions, "events": _events, "samples": _samples,
		"slide_touches": _slide_touches, "impulse_audit": _ball.impulse_audit.duplicate(true)})
	_adapter.free()
	_adapter = null
	_fixture.free()
	_player = null
	_carrier = null
	_ball = null
	return result


func _create_player(squad: FootballSquad, index: int, team: int, at: Vector3) -> FootballPlayer:
	var player := FootballPlayer.new()
	squad.apply_to(player, index)
	player.team = team
	player.eleven_slot = index
	player.aim = SHIELD_DIRECTION
	player.position = at
	_fixture.add_child(player)
	return player


func _challenge_seed() -> int:
	var rng := RandomNumberGenerator.new()
	for seed_value in range(81100, 81164):
		rng.seed = seed_value
		# The first AI decision draws a reaction period, a lane offset, then confidence.
		rng.randf()
		rng.randf()
		if rng.randf() < 0.30:
			return seed_value
	return 81100


func _tick(delta: float) -> void:
	if _adapter == null:
		return
	_update_camera()
	if not _active:
		return
	if _opening.is_empty():
		_opening = _observe_opening()
	var action := FootballAI.decide(_player, _adapter.players, _ball, delta, true)
	if not action.is_empty():
		_decisions.append({"frame": Engine.get_physics_frames(), "action": action})
	_adapter._control_ball()
	_samples.append({
		"frame": Engine.get_physics_frames(), "ball_position": _vec(_ball.global_position),
		"ball_velocity": _vec(_ball.linear_velocity), "serial": _ball.touch_serial,
		"defender": _vec(_player.global_position), "carrier": _vec(_carrier.global_position),
		"defender_intent": _vec(_player.intent), "defender_velocity": _vec(_player.linear_velocity),
		"defender_action": _player.action_kind, "carrier_fallen": _carrier.ragdoll != null,
		"free": not _ball.freeze and _ball.grip_holder_id.is_empty() and _ball.global_position.is_finite(),
	})


func _observe_opening() -> Dictionary:
	var lane := FootballReception.flat(_ball.global_position - _player.global_position)
	var toward_ball := lane.normalized()
	var to_carrier := FootballReception.flat(_carrier.global_position - _player.global_position)
	var carrier_depth := to_carrier.dot(toward_ball)
	var carrier_lateral := (to_carrier - toward_ball * carrier_depth).length()
	var speed := FootballReception.flat(_player.linear_velocity).length()
	var carrier_chasing := _carrier.chasing_ball(_ball)
	var closing := minf(speed + 2.0, 7.0) - FootballReception.flat(_ball.linear_velocity).dot(toward_ball)
	return {
		"carrier_chasing": carrier_chasing, "ball_gap_m": lane.length(), "carrier_gap_m": to_carrier.length(),
		"defender_speed_mps": speed, "carrier_lateral_m": carrier_lateral, "carrier_depth_m": carrier_depth,
		"slide_reach_seconds": (lane.length() - 0.66) / maxf(closing, 0.01),
		"carrier_blocks_lane": carrier_lateral <= 0.60 and carrier_depth > 0.0 and carrier_depth < lane.length(),
		"prior_window": carrier_chasing and _player.upright_ready() and lane.length() > 1.25 and lane.length() < 2.60 and to_carrier.length() < 2.80 and speed > 3.50 and _player.aim.dot(toward_ball) > 0.85,
	}


func _observe_actor_event(kind: String, detail: Dictionary, actor: String) -> void:
	if kind not in ["slide_body_contact", "standing_tackle_contact", "fall"]:
		return
	var fields := detail.duplicate()
	if fields.has("contact") and fields["contact"] is Vector3:
		fields["contact"] = _vec(fields["contact"])
	_events.append({"kind": kind, "detail": fields, "actor": actor, "frame": Engine.get_physics_frames()})


func _observe_ball_touch(_team: int, player_id: String, kind: String) -> void:
	if not _active or player_id != _player.player_id or kind != "deflection" or _player.action_kind != "slide":
		return
	var boot := _player.visual_controller.right_boot.global_position
	var gap := _player._boot_distance(_ball.global_position, _player.last_boot_world, boot)
	_slide_touches.append({
		"frame": Engine.get_physics_frames(), "serial": _ball.touch_serial,
		"slide_elapsed_s": _player.action_elapsed, "boot_gap_m": gap,
	})


func _evaluate_case(carrier_start: Vector3) -> Dictionary:
	var queued_slide := false
	for decision in _decisions:
		queued_slide = queued_slide or decision["action"] == "slide"
	var body_contacts := 0
	var first_body_frame := -1
	for event in _events:
		if event["actor"] == _player.player_id and event["kind"] == "slide_body_contact":
			if first_body_frame < 0:
				first_body_frame = int(event["frame"])
			body_contacts += 1
	var ball_first := false
	if _slide_touches.size() == 1:
		var contact := _slide_touches[0]
		for entry in _ball.impulse_audit:
			if entry["serial"] == contact["serial"] and entry["player_id"] == _player.player_id and entry["physics_frame"] == contact["frame"]:
				var body_first := first_body_frame >= 0 and first_body_frame < int(contact["frame"])
				for event in _events:
					if event["kind"] == "slide_body_contact" and event["actor"] == _player.player_id and event["frame"] == contact["frame"]:
						body_first = body_first or not event["detail"]["ball_first"]
				ball_first = not body_first and float(contact["boot_gap_m"]) <= FootballBall.RADIUS + 0.12 and _vector(entry["impulse"]).length() > 0.01
				break
	var pressing_samples := 0
	var fell := false
	var free := not _samples.is_empty()
	for sample in _samples:
		var to_ball := FootballReception.flat(_vector(sample["ball_position"]) - _vector(sample["defender"])).normalized()
		if _vector(sample["defender_intent"]).dot(to_ball) > 0.30 and _vector(sample["defender_velocity"]).dot(to_ball) > 1.0:
			pressing_samples += 1
		fell = fell or sample["carrier_fallen"]
		free = free and sample["free"]
	return {
		"opening": _opening, "queued_slide": queued_slide, "body_contacts": body_contacts,
		"ball_first": ball_first, "carrier_fell": fell, "free": free,
		"continued_pressure": pressing_samples >= 12, "pressing_samples": pressing_samples,
		"carrier_progress_m": (_carrier.global_position - carrier_start).dot(SHIELD_DIRECTION),
	}


func _update_camera() -> void:
	var center := (_player.global_position + _carrier.global_position + _ball.global_position) / 3.0 + Vector3.UP * 0.70
	var gap := FootballReception.flat(_ball.global_position - _player.global_position).length()
	_camera.size = maxf(3.7, 2.6 + gap * 0.7)
	_camera.position = center + Vector3(0.45, 2.65, 7.20)
	_camera.look_at(center)
	_caption.text = "%s   |   Defender %.1f m/s" % [_phase, FootballReception.flat(_player.linear_velocity).length()]
