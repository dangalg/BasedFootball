extends SceneTree

## --headless --script res://tests/eleven_wall_acceptance.gd
## -- --eleven-acceptance --report=<fresh absolute JSON path>

const MATCH := preload("res://scenes/eleven_match.tscn")
const SAVE_PATH := "user://eleven_acceptance_squad.json"
const RESTART := "direct_free_kick"
const SPOT := Vector3(28.0, FootballBall.RADIUS, 0.0)
const DISTANCE := 9.15


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
	var report := await _exercise(game, "--wall-movie" in arguments)
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
	print("ELEVEN_WALL_ACCEPTANCE %s %s" % ["PASS" if report["passed"] else "FAIL", report_path])
	quit(0 if report["passed"] else 1)


func _exercise(game: Node3D, movie: bool) -> Dictionary:
	var ball: FootballBall = game.ball
	var referee: ElevenReferee = game.referee
	var hz := Engine.physics_ticks_per_second
	for index in range(game.players.size()):
		var player: FootballPlayer = game.players[index]
		player.ai_rng.seed = 81100 + index
	_place(game.controlled, Vector3(27.1, 0.06, 0.0))
	for index in range(3):
		_place(game.away_outfield[6 + index], Vector3(34.6, 0.06, float(index - 1) * 1.5))
	ball.global_position = SPOT
	ball.reset_physics_interpolation()
	var settle_seconds := 0.50 if movie else 0.23
	for _frame in range(ceili(settle_seconds * hz)):
		await physics_frame
	referee.global_position = Vector3(35.15, 0.0, 0.0)
	var referee_start := referee.global_position
	var first_event: int = game.action_log.size()
	var seed_serial := ball.touch_serial
	var stopped_clock: float = game.remaining
	game.kickoff_remaining = 0.0
	game._begin_restart(RESTART, 0, SPOT)
	var wall: ElevenWall = game.restart.get("wall")
	var taker: FootballPlayer = game.restart.get("taker")
	var members: Array[FootballPlayer] = []
	var targets: Array[Vector3] = []
	if wall != null:
		members = wall.members.duplicate()
		targets = wall.targets.duplicate()
	var starts: Array[Vector3] = []
	var previous_positions: Array[Vector3] = []
	var max_step := 0.0
	for member in members:
		starts.append(member.global_position)
		previous_positions.append(member.global_position)
	var initial_mark := referee.wall_marked
	var expected_mark := SPOT + Vector3.RIGHT * DISTANCE
	var referee_target := referee._wall_target
	var first_paint: Dictionary = {}
	var mark: Dictionary = {}
	var formed: Dictionary = {}
	var resumed := false
	var sampled_free_strike := false
	var samples: Array[Dictionary] = []
	var follow_seconds := 0.35 if movie else 0.08
	for frame in range(ceili(10.0 * hz)):
		await physics_frame
		var physics_frame_id := Engine.get_physics_frames()
		if first_paint.is_empty() and _has_visible_mark(referee):
			first_paint = {
				"frame": physics_frame_id, "position": _vector(referee.global_position),
				"moved_m": _flat_gap(referee_start, referee.global_position),
				"target_gap_m": _flat_gap(referee.global_position, referee_target),
			}
		if mark.is_empty() and referee.wall_marked:
			mark = {
				"frame": physics_frame_id, "position": _vector(referee.wall_mark_position),
				"referee_position": _vector(referee.global_position),
				"referee_moved_m": _flat_gap(referee_start, referee.global_position),
				"referee_gap_m": _flat_gap(referee.global_position, referee.wall_mark_position),
			}
		if game.restart.get("kind") == RESTART and not game.restart.get("strike_requested", false):
			for index in range(members.size()):
				var position := members[index].global_position
				max_step = maxf(max_step, _flat_gap(position, previous_positions[index]))
				previous_positions[index] = position
			if referee.wall_marked and _wall_is_formed(members, targets):
				formed = {"frame": physics_frame_id, "players": _wall_receipt(members, starts, targets), "largest_step_m": max_step}
		if frame % 8 == 0:
			samples.append({
				"frame": physics_frame_id, "remaining": game.remaining, "marked": referee.wall_marked,
				"referee": _vector(referee.global_position), "ball": _vector(ball.global_position),
				"wall": _wall_receipt(members, starts, targets),
			})
		if taker != null and ball.touch_serial == seed_serial + 1 and ball.last_touch_id == taker.player_id and not ball.freeze and ball.grip_holder_id.is_empty() and ball.linear_velocity.length() > 2.0:
			sampled_free_strike = true
		if game.restart.is_empty() and float(game.remaining) < stopped_clock - follow_seconds:
			resumed = true
			break
	var events: Array = game.action_log.slice(first_event)
	var taker_id := taker.player_id if taker != null else ""
	var taken := _event(events, "restart_taken", taker_id)
	var serial := int(taken.get("touch_serial", -1))
	var boot := _event(events, "kick_contact", taker_id, serial)
	var ready := _event(events, "wall_ready", taker_id)
	var boot_gap := float(boot.get("boot_gap", INF))
	var audited := false
	for entry in ball.impulse_audit:
		if entry["serial"] == serial and entry["player_id"] == taker_id:
			audited = _read_vector(entry["impulse"]).length_squared() > 0.00001
			break
	var walked := not formed.is_empty() and max_step <= 8.0 / float(hz)
	for player: Dictionary in formed.get("players", []):
		walked = walked and float(player["moved_m"]) > 0.5
	var checks := {
		"three_defenders_formed_legal_goal_side_wall": not formed.is_empty() and ready.get("formed", false) and ready.get("marked", false),
		"wall_members_walked_to_targets": walked,
		"referee_walked_and_marked_on_arrival": not initial_mark and float(first_paint.get("moved_m", 0.0)) > 0.5 and float(first_paint.get("target_gap_m", INF)) <= 0.23 and _flat_gap(_read_vector(mark.get("position", [])), expected_mark) <= 0.06,
		"physical_free_kick_and_clock_resumed": resumed and taken.get("restart", "") == RESTART and taken.get("team", -1) == 0 and serial == seed_serial + 1 and boot_gap >= 0.0 and boot_gap <= FootballPlayer.STRIKE_BOOT_REACH and audited and sampled_free_strike,
	}
	return {
		"passed": not checks.values().has(false), "checks": checks,
		"fixture": "Initial placements, then production direct free-kick award. Match owns all movement, mark, ball contact and restart.",
		"spot": _vector(SPOT), "referee_start": _vector(referee_start), "referee_target": _vector(referee_target),
		"first_visible_paint": first_paint, "mark": mark, "formed_wall": formed,
		"taker": taker_id, "samples": samples, "match_action_log": events, "impulse_audit": ball.impulse_audit.duplicate(true),
	}


func _has_visible_mark(referee: ElevenReferee) -> bool:
	for segment: MeshInstance3D in referee._wall_segments:
		if segment.visible:
			return true
	return false


func _wall_is_formed(members: Array[FootballPlayer], targets: Array[Vector3]) -> bool:
	if members.size() != 3 or targets.size() != 3:
		return false
	for index in range(members.size()):
		var member := members[index]
		var point := member.global_position
		if member.team != 1 or point.x <= SPOT.x or _flat_gap(point, SPOT) < DISTANCE - 0.01 or _flat_gap(point, targets[index]) > 0.38:
			return false
	return true


func _wall_receipt(members: Array[FootballPlayer], starts: Array[Vector3], targets: Array[Vector3]) -> Array[Dictionary]:
	var receipt: Array[Dictionary] = []
	for index in range(members.size()):
		var point := members[index].global_position
		receipt.append({
			"id": members[index].player_id, "position": _vector(point), "start": _vector(starts[index]),
			"target": _vector(targets[index]) if index < targets.size() else [],
			"moved_m": _flat_gap(point, starts[index]), "ball_gap_m": _flat_gap(point, SPOT),
		})
	return receipt


func _event(events: Array, kind: String, player_id: String, serial: int = -1) -> Dictionary:
	for event: Dictionary in events:
		if event.get("kind") == kind and event.get("player") == player_id and (serial < 0 or event.get("touch_serial", -1) == serial):
			return event
	return {}


func _place(player: FootballPlayer, position: Vector3) -> void:
	player.global_position = position
	player.reset_physics_interpolation()


func _flat_gap(a: Vector3, b: Vector3) -> float:
	return FootballReception.flat(a - b).length()


func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _read_vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2])) if value.size() == 3 else Vector3.INF
