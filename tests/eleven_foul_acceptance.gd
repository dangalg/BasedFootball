extends SceneTree

## --headless --script res://tests/eleven_foul_acceptance.gd
## -- --eleven-acceptance --report=<fresh absolute JSON path>
## --discipline-acceptance checks two midfield cautions and rematch restoration.
## --foul-recovery-acceptance records the midfield fall, get-up and restart.

const MATCH := preload("res://scenes/eleven_match.tscn")
const SAVE_PATH := "user://eleven_acceptance_squad.json"

var _slide_contact: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var report_path := ""
	for argument in arguments:
		if argument.begins_with("--report="):
			report_path = argument.trim_prefix("--report=")
	if "--eleven-acceptance" not in arguments or not report_path.is_absolute_path() or FileAccess.file_exists(report_path):
		push_error("Use -- --eleven-acceptance --report=<fresh absolute JSON path>.")
		quit(2)
		return
	var game := MATCH.instantiate() as Node3D
	root.add_child(game)
	current_scene = game
	if not game.acceptance or game.squad.save_path != SAVE_PATH or game.phase != "playing" or not is_instance_valid(game.referee):
		push_error("Expected the isolated eleven-a-side match and referee without the setup menu.")
		quit(2)
		return
	var report: Dictionary
	if "--foul-recovery-acceptance" in arguments:
		report = await _exercise(game, false, true)
	elif "--discipline-acceptance" in arguments:
		report = await _exercise_discipline(game)
	else:
		var midfield := await _exercise(game, false)
		game.queue_free()
		await process_frame
		game = MATCH.instantiate() as Node3D
		root.add_child(game)
		current_scene = game
		var penalty := await _exercise(game, true)
		report = {"passed": midfield.passed and penalty.passed, "midfield": midfield, "penalty": penalty}
	if FileAccess.file_exists(report_path):
		push_error("Report already exists at %s" % report_path)
		quit(2)
		return
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not open report at %s" % report_path)
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("ELEVEN_FOUL_ACCEPTANCE %s %s" % ["PASS" if report["passed"] else "FAIL", report_path])
	quit(0 if report["passed"] else 1)


func _exercise_discipline(game: Node3D) -> Dictionary:
	var offender: FootballPlayer = game.away_outfield[0]
	var original_roster := _player_ids(game.players)
	var original_away := _player_ids(game.away_outfield)
	var expected_roster := original_roster.duplicate()
	var expected_away := original_away.duplicate()
	expected_roster.erase(offender.player_id)
	expected_away.erase(offender.player_id)
	var first := await _exercise(game, false)
	var first_yellow: bool = _card_receipts(first["match_action_log"], offender.player_id) == ["yellow/reckless_slide"] and first["restart"].get("card_color", "") == "yellow" and offender.yellow_cards == 1 and offender in game.players and not offender in game.sent_off_players
	var second: Dictionary = {}
	if first_yellow:
		# Reposition for the same kind of contact without clearing match discipline.
		game.reset_positions(0)
		second = await _exercise(game, false)
	var second_events: Array = second.get("match_action_log", [])
	var dismissed: bool = offender.sent_off and offender in game.sent_off_players and not offender in game.players and not offender in game.away_outfield
	var removed_from_simulation := offender.collision_layer == 0 and offender.collision_mask == 0 and offender.freeze and not offender.visible and not offender.is_physics_processing()
	var no_replacement := _player_ids(game.players) == expected_roster and _player_ids(game.away_outfield) == expected_away
	var selection_valid: bool = game.controlled != offender and game.controlled in game.home_outfield and game.controlled.selected
	var sent_off := _event(second_events, "sent_off", offender.player_id)
	var second_yellow: bool = _card_receipts(second_events, offender.player_id) == ["yellow/reckless_slide", "red/second_yellow"] and second.get("restart", {}).get("card_color", "") == "red" and offender.yellow_cards == 2 and sent_off.get("reason", "") == "second_yellow"
	var dismissal_state := {
		"roster": _player_ids(game.players), "away_outfield": _player_ids(game.away_outfield),
		"yellow_cards": offender.yellow_cards, "collision_layer": offender.collision_layer,
		"collision_mask": offender.collision_mask, "physics_processing": offender.is_physics_processing(),
		"sent_off": offender.sent_off, "visible": offender.visible, "frozen": offender.freeze,
	}
	game.rematch()
	await physics_frame
	var rematch_roster := _player_ids(game.players)
	var rematch_away := _player_ids(game.away_outfield)
	var restored: bool = rematch_roster == original_roster and rematch_away == original_away and game.sent_off_players.is_empty() and offender in game.players and offender.yellow_cards == 0 and not offender.sent_off and offender.visible and not offender.freeze and offender.collision_layer == 1 and offender.collision_mask == 1 and offender.is_physics_processing()
	var checks := {
		"first_physical_foul_and_restart": first["passed"],
		"first_yellow_did_not_remove_player": first_yellow,
		"second_physical_foul_and_restart": second.get("passed", false),
		"second_yellow_led_to_red": second_yellow,
		"offender_removed_without_replacement": dismissed and no_replacement and removed_from_simulation,
		"active_selection_valid": selection_valid,
		"rematch_restored_squad_and_reset_discipline": restored,
	}
	return {
		"passed": not checks.values().has(false), "checks": checks, "offender": offender.player_id,
		"first_foul": first, "second_foul": second, "dismissal_state": dismissal_state,
		"rematch_roster": rematch_roster, "rematch_away_outfield": rematch_away,
	}


func _exercise(game: Node3D, penalty: bool, record_recovery := false) -> Dictionary:
	_slide_contact.clear()
	var victim: FootballPlayer = game.controlled
	var attacker: FootballPlayer = game.away_outfield[0]
	var ball: FootballBall = game.ball
	var referee: ElevenReferee = game.referee
	var hz := Engine.physics_ticks_per_second
	for index in range(game.players.size()):
		var player: FootballPlayer = game.players[index]
		player.ai_rng.seed = 81100 + index
	var restart_kind := "penalty" if penalty else "direct_free_kick"
	var origin := Vector3(38.0 if penalty else 4.0, 0.02, 0.0)
	_place(victim, origin, Vector3.RIGHT)
	_place(attacker, origin + Vector3.RIGHT * 1.8, Vector3.LEFT)
	ball.global_position = origin + Vector3(-4.0, FootballBall.RADIUS - origin.y, -3.0)
	ball.reset_physics_interpolation()
	var camera: Camera3D
	if record_recovery:
		camera = Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		game.add_child(camera)
		camera.make_current()
		_frame_recovery(camera, victim.global_position, attacker.global_position)
	# Let the fixture settle without ordinary AI taking over the slide setup.
	for _frame in range(ceili(0.23 * hz)):
		await physics_frame
	referee.global_position = origin + Vector3(5.0, -origin.y, 4.0)
	referee.look_at(Vector3(origin.x, 0.0, origin.z), Vector3.UP)
	victim.body_visual.rotation.y = -PI / 2.0
	attacker.body_visual.rotation.y = PI / 2.0
	var capture := _capture_slide.bind(victim, ball, referee)
	attacker.physical_event.connect(capture)
	var seed_serial := ball.touch_serial
	var first_event: int = game.action_log.size()
	game.kickoff_remaining = 0.0
	attacker.linear_velocity = Vector3.LEFT * 6.0
	var queued := attacker.slide(ball)
	for _frame in range(ceili(0.55 * hz)):
		await physics_frame
		if record_recovery:
			_frame_recovery(camera, victim.global_position, attacker.global_position)
		if not _slide_contact.is_empty():
			break
	var restart_state: Dictionary = {}
	var clock_at_award := -1.0
	var resumed := false
	var recovery_samples: Array[Dictionary] = []
	var tail_frames := 0
	for _frame in range(ceili((8.0 if record_recovery else 5.4) * hz)):
		await physics_frame
		if restart_state.is_empty() and game.restart.get("kind") == restart_kind:
			var taker: FootballPlayer = game.restart["taker"]
			restart_state = {"team": taker.team, "taker": taker.player_id, "spot": _vector(ball.global_position), "ball_frozen": ball.freeze, "touch_serial": ball.touch_serial, "card_color": referee.card_color}
			if penalty:
				restart_state["keeper_x"] = game.keepers[1].global_position.x
			clock_at_award = game.remaining
		if not restart_state.is_empty() and game.restart.is_empty() and float(game.remaining) < clock_at_award - 0.08:
			resumed = true
			if not record_recovery:
				break
		if record_recovery:
			var secondary := ball.global_position if not game.restart.is_empty() else victim.global_position
			if restart_state.is_empty():
				secondary = attacker.global_position
			_frame_recovery(camera, victim.global_position, secondary)
			if not restart_state.is_empty():
				recovery_samples.append(_sample_recovery(victim))
				if resumed and victim.ragdoll == null:
					tail_frames += 1
					if tail_frames >= ceili(0.42 * hz):
						break
	attacker.physical_event.disconnect(capture)
	var events: Array = game.action_log.slice(first_event)
	var foul := _event(events, "foul", attacker.player_id)
	var taker_id := str(restart_state.get("taker", ""))
	var taken := _event(events, "restart_taken", taker_id, restart_kind)
	var serial := int(taken.get("touch_serial", -1))
	var boot := _event(events, "kick_contact", taker_id, "", serial)
	var audited := false
	for entry in ball.impulse_audit:
		if entry["serial"] == serial and entry["player_id"] == taker_id and entry["team"] == victim.team:
			audited = _read_vector(entry["impulse"]).length_squared() > 0.00001
			break
	var contact_spot := _read_vector(_slide_contact.get("contact_spot", []))
	var flag_spot := _read_vector(foul.get("spot", []))
	var restart_spot := _read_vector(restart_state.get("spot", []))
	var expected_spot := Vector3(ElevenPitch.HALF_LENGTH - ElevenPitch.PENALTY_SPOT, FootballBall.RADIUS, 0.0) if penalty else flag_spot
	var at_correct_spot := contact_spot.is_finite() and flag_spot.is_finite() and restart_spot.is_finite() and FootballReception.flat(flag_spot - contact_spot).length() <= 0.35 and FootballReception.flat(restart_spot - expected_spot).length() <= 0.05
	var boot_gap := float(boot.get("boot_gap", INF))
	var checks := {
		"actual_slide_hit_victim": queued and _slide_contact.get("victim", "") == victim.player_id and float(_slide_contact.get("distance", INF)) <= 0.19,
		"referee_witnessed_ball_free_contact": _slide_contact.get("seen", false) and not _slide_contact.get("ball_first", true) and float(_slide_contact.get("ball_gap_m", 0.0)) >= 2.0 and _slide_contact.get("touch_serial", -1) == seed_serial,
		"foul_credited_to_correct_players": foul.get("player", "") == attacker.player_id and foul.get("victim", "") == victim.player_id and foul.get("restart", "") == restart_kind,
		"correct_team_and_spot_for_restart": at_correct_spot and restart_state.get("team", -1) == victim.team and restart_state.get("ball_frozen", false) and restart_state.get("touch_serial", -1) == seed_serial,
		"free_kick_boot_contact_and_play_resumed": resumed and taken.get("team", -1) == victim.team and serial > seed_serial and boot_gap >= 0.0 and boot_gap <= FootballPlayer.STRIKE_BOOT_REACH and audited,
	}
	if penalty:
		checks["penalty_keeper_on_goal_line"] = absf(float(restart_state.get("keeper_x", 0.0)) - ElevenPitch.HALF_LENGTH) <= 0.06
	if record_recovery:
		checks.merge(_check_recovery(recovery_samples, events, victim.player_id, hz))
	return {
		"passed": not checks.values().has(false), "checks": checks,
		"fixture": "Initial placements, referee facing and attacker run-up only. The production slide sweep, foul decision and restart own the outcome.",
		"attacker": attacker.player_id, "victim": victim.player_id, "seed_serial": seed_serial,
		"slide_contact": _slide_contact.duplicate(true), "restart": restart_state,
		"match_action_log": events, "impulse_audit": ball.impulse_audit.duplicate(true),
		"recovery_samples": recovery_samples,
	}


func _frame_recovery(camera: Camera3D, player_position: Vector3, secondary_position: Vector3) -> void:
	var separation := FootballReception.flat(secondary_position - player_position).limit_length(5.0)
	var focus := player_position + separation * 0.42 + Vector3.UP * 0.74
	camera.size = 4.2 + separation.length() * 0.65
	camera.position = focus + Vector3(1.5, 3.4, 8.0)
	camera.look_at(focus)


func _sample_recovery(victim: FootballPlayer) -> Dictionary:
	var ragdoll := victim.ragdoll
	var sample := {
		"frame": Engine.get_physics_frames(),
		"ragdoll": ragdoll.get_instance_id() if ragdoll != null else 0,
		"getting_up": victim.getting_up,
		"original_visible": victim.body_visual.visible,
		"collision_layer": victim.collision_layer, "collision_mask": victim.collision_mask,
		"capsule_frozen": victim.freeze,
	}
	if ragdoll != null:
		sample["torso_height_m"] = ragdoll.torso.global_position.y
		sample["torso_up_dot"] = absf(ragdoll.torso.global_basis.y.dot(Vector3.UP))
		sample["torso_dynamic"] = not ragdoll.torso.freeze
	return sample


func _check_recovery(samples: Array[Dictionary], events: Array, victim_id: String, hz: int) -> Dictionary:
	var ragdoll_id := int(_slide_contact.get("ragdoll", 0))
	var same_fall_at_whistle := not samples.is_empty() and ragdoll_id != 0 and int(samples[0]["ragdoll"]) == ragdoll_id
	var live_frames := 0
	var rise_frames := 0
	var grounded := false
	var restored := false
	for sample in samples:
		if int(sample["ragdoll"]) == ragdoll_id and ragdoll_id != 0:
			if sample.get("torso_dynamic", false) and not sample["original_visible"]:
				live_frames += 1
				grounded = grounded or (float(sample["torso_height_m"]) < 0.48 and float(sample["torso_up_dot"]) < 0.60)
			rise_frames += int(sample["getting_up"])
		elif rise_frames > 0 and int(sample["ragdoll"]) == 0:
			restored = restored or (sample["original_visible"] and not sample["capsule_frozen"] and int(sample["collision_layer"]) == 1 and int(sample["collision_mask"]) == 1)
	return {
		"same_dynamic_ragdoll_after_whistle": same_fall_at_whistle and live_frames >= ceili(0.20 * hz),
		"physical_fall_reached_turf": grounded and not _event(events, "fall", victim_id).is_empty(),
		"original_player_restored_after_get_up": rise_frames >= ceili(0.25 * hz) and restored and not _event(events, "get_up", victim_id).is_empty() and _event(events, "fall_reset", victim_id).is_empty(),
	}


func _capture_slide(kind: String, detail: Dictionary, victim: FootballPlayer, ball: FootballBall, referee: ElevenReferee) -> void:
	if kind != "slide_body_contact" or detail.get("victim", "") != victim.player_id or not _slide_contact.is_empty():
		return
	var spot: Vector3 = detail.get("contact", Vector3.INF)
	_slide_contact = detail.duplicate(true)
	_slide_contact.erase("contact")
	_slide_contact["contact_spot"] = _vector(spot)
	_slide_contact["seen"] = referee.can_see_contact(spot)
	_slide_contact["referee_position"] = _vector(referee.global_position)
	_slide_contact["ball_gap_m"] = FootballReception.flat(ball.global_position - spot).length()
	_slide_contact["touch_serial"] = ball.touch_serial
	_slide_contact["ragdoll"] = victim.ragdoll.get_instance_id() if victim.ragdoll != null else 0


func _place(player: FootballPlayer, position: Vector3, aim: Vector3) -> void:
	player.global_position = position
	player.aim = aim
	player.reset_physics_interpolation()


func _player_ids(players: Array) -> Array[String]:
	var ids: Array[String] = []
	for player: FootballPlayer in players:
		ids.append(player.player_id)
	ids.sort()
	return ids


func _card_receipts(events: Array, player_id: String) -> Array[String]:
	var receipts: Array[String] = []
	for event: Dictionary in events:
		if event.get("kind") == "card" and event.get("player") == player_id:
			receipts.append("%s/%s" % [event.get("color", ""), event.get("reason", "")])
	return receipts


func _event(events: Array, kind: String, player_id: String, restart_kind: String = "", serial: int = -1) -> Dictionary:
	for event: Dictionary in events:
		if event.get("kind") == kind and event.get("player") == player_id and (restart_kind.is_empty() or event.get("restart") == restart_kind) and (serial < 0 or event.get("touch_serial", -1) == serial):
			return event
	return {}


func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _read_vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2])) if value.size() == 3 else Vector3.INF
