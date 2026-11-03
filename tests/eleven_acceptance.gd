extends SceneTree

## Launch with --script res://tests/eleven_acceptance.gd -- --eleven-acceptance
## Optional --report=<absolute JSON path> preserves the full event log.
## --menu-acceptance --formation-acceptance selects 4-4-2 before kickoff.

const SCENE_PATH := "res://scenes/eleven_match.tscn"
const SAVE_PATH := "user://eleven_acceptance_squad.json"
const MATCH_SECONDS := 180.0
const RESTARTS := ["kickoff", "throw_in", "corner", "goal_kick"]
const DELIVERIES := ["pass", "through", "lob"]
const SEED := 81100


class ControllerDriver extends Node:
	var game: Node3D
	var movement := Vector2.ZERO
	var sprinting := false
	var actions: Dictionary = {}
	var goal_x := 0.0
	var think_in := 0.0
	var release_in := 0.0
	var switch_in := 0.0
	var decisions := 0

	func decide(delta: float) -> void:
		actions.clear()
		if release_in > 0.0:
			release_in -= delta
			if release_in <= 0.0:
				actions["primary_release"] = true
			return
		think_in -= delta
		switch_in -= delta
		if think_in > 0.0:
			return
		think_in = 0.15
		decisions += 1
		var actor: FootballPlayer = game.controlled
		var ball: FootballBall = game.ball
		var distance := actor.global_position.distance_to(ball.global_position)
		if switch_in <= 0.0 and distance > 2.5:
			for teammate: FootballPlayer in game.home_outfield:
				if teammate.global_position.distance_to(ball.global_position) + 1.5 < distance:
					game._switch_player()
					switch_in = 1.0
					actor = game.controlled
					break
		var offset := ball.global_position - actor.global_position
		var desired := Vector2(offset.x, offset.z)
		sprinting = desired.length() > 2.5
		if game._attacking_contact():
			desired = Vector2(goal_x - actor.global_position.x, -actor.global_position.z)
			sprinting = false
			if desired.length() < 11.0 and actor.kick_cooldown <= 0.0 and not game.charging:
				actions["primary"] = true
				release_in = 0.25
			elif actor.kick_cooldown <= 0.0:
				var best_gap := 11.0
				for teammate: FootballPlayer in game.home_outfield:
					var line := teammate.global_position - actor.global_position
					var gap := Vector2(line.x, line.z).length()
					if line.x > 3.0 and gap < best_gap:
						best_gap = gap
						desired = Vector2(line.x, line.z)
						actions["pass"] = true
		movement = desired.normalized()


var _game: Node3D
var _driver: ControllerDriver
var _report_path := ""
var _frames := 0
var _max_frames := 0
var _sample_interval := 0
var _started_at := 0
var _match_seconds := MATCH_SECONDS
var _menu_settings: Dictionary = {}
var _formation_opening: Dictionary = {}
var _finite := true
var _shape_samples := 0
var _initial_shape: Array[Vector2] = []
var _minimum_width: Array[float] = [INF, INF]
var _minimum_depth: Array[float] = [INF, INF]
var _spread_samples: Array[int] = [0, 0]
var _crowd_samples: Array[int] = [0, 0]
var _max_near_ball: Array[int] = [0, 0]
var _max_speed: Array[float] = [0.0, 0.0]
var _max_ball_speed := 0.0
var _roster: Dictionary = {}
var _event_cursor := 0
var _restarts: Array[Dictionary] = []
var _throw_entry_check := false
var _throw_fixture_sent := false
var _throw_serial := -1
var _throw_tracking: Dictionary = {}


func _initialize() -> void:
	call_deferred("_start")


func _start() -> void:
	var arguments := OS.get_cmdline_user_args()
	for argument in arguments:
		if argument.begins_with("--report="):
			_report_path = argument.trim_prefix("--report=")
	if "--eleven-acceptance" not in arguments:
		_abort("Pass -- --eleven-acceptance to isolate career data.")
		return
	var check_formation := "--formation-acceptance" in arguments
	if check_formation and not "--menu-acceptance" in arguments:
		_abort("Pass --menu-acceptance to exercise the formation selector.")
		return
	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		_abort("Could not load the eleven-a-side match scene.")
		return
	_game = scene.instantiate() as Node3D
	root.add_child(_game)
	current_scene = _game
	if not _game.acceptance or _game.squad.save_path != SAVE_PATH:
		_abort("The scene did not select the isolated eleven-a-side save.")
		return
	_roster = _measure_roster()
	if not _roster["valid"]:
		_abort("Expected ten outfield players and one keeper for each team.")
		return
	if not is_equal_approx(float(_game.remaining), MATCH_SECONDS):
		_abort("The match did not start with a 180-second clock.")
		return
	if "--menu-acceptance" in arguments:
		var menu: ElevenMatchMenu = _game.match_menu
		if _game.phase != "setup" or menu == null or not _game.ball.freeze:
			_abort("The kickoff setup menu did not hold play.")
			return
		menu.length_choice.select(1)
		menu.difficulty_choice.select(2)
		if check_formation:
			menu.formation_choice.select(1)
		menu.kickoff_button.pressed.emit()
		if _game.phase != "playing" or _game.match_menu != null or _game.ball.freeze or _game.remaining != 360.0 or _game.opponent_difficulty != 2:
			_abort("The kickoff action did not apply the selected settings.")
			return
		_match_seconds = float(_game.match_duration)
		_menu_settings = {"duration": _match_seconds, "difficulty": int(_game.opponent_difficulty)}
		if check_formation:
			_menu_settings["formation"] = int(_game.home_formation)
			_formation_opening = _measure_opening_formation()
	if "--away-kickoff" in arguments:
		_game.action_log.clear()
		_game.reset_positions(1)
	_throw_entry_check = "--throw-entry" in arguments
	_initial_shape = [_spread(_game.home_outfield), _spread(_game.away_outfield)]
	_driver = ControllerDriver.new()
	_driver.game = _game
	for keeper: FootballPlayer in _game.keepers:
		if keeper.team == 1:
			_driver.goal_x = keeper.global_position.x
	for index in range(_game.players.size()):
		var player: FootballPlayer = _game.players[index]
		player.ai_rng.seed = SEED + index
		player.ai_style = player.ai_rng.randf_range(0.25, 0.75)
	_game.add_child(_driver)
	_game.decision_driver = _driver
	_game.set_process_unhandled_input(false)
	_sample_interval = maxi(1, Engine.physics_ticks_per_second / 2)
	_max_frames = roundi((_match_seconds + 60.0) * Engine.physics_ticks_per_second)
	_started_at = Time.get_ticks_msec()
	physics_frame.connect(_observe)
	print("ELEVEN_ACCEPTANCE_STARTED seed=%d roster=%s" % [SEED, JSON.stringify(_roster)])


func _measure_opening_formation() -> Dictionary:
	var home := _opening_depths(_game.home_outfield, -1.0)
	var away := _opening_depths(_game.away_outfield, 1.0)
	# The home kickoff taker stands at 0.8 m rather than on the formation anchor.
	var home_anchors := [8.0, 8.0, 22.0, 22.0, 22.0, 22.0, 34.0, 34.0, 37.0, 37.0]
	var home_live := [0.8, 8.0, 22.0, 22.0, 22.0, 22.0, 34.0, 34.0, 37.0, 37.0]
	var away_anchors := [6.0, 11.0, 11.0, 20.0, 20.0, 25.0, 34.0, 34.0, 37.0, 37.0]
	var home_valid: bool = home["anchor_depths_m"] == home_anchors and home["live_depths_m"] == home_live
	var away_valid: bool = away["anchor_depths_m"] == away_anchors and away["live_depths_m"] == away_anchors
	return {"home_formation_selected": _game.home_formation == 1, "home_442": home_valid, "away_433": away_valid, "home": home, "away": away}


func _opening_depths(field: Array, side: float) -> Dictionary:
	var anchors: Array[float] = []
	var live: Array[float] = []
	for player: FootballPlayer in field:
		anchors.append(snappedf(player.eleven_home.x * side, 0.01))
		live.append(snappedf(player.global_position.x * side, 0.01))
	anchors.sort()
	live.sort()
	return {"anchor_depths_m": anchors, "live_depths_m": live}


func _measure_roster() -> Dictionary:
	var teams: Array[int] = [0, 0]
	var keepers: Array[int] = [0, 0]
	var ids: Dictionary = {}
	var valid := true
	for player: FootballPlayer in _game.players:
		if player.team not in [0, 1] or player.player_id.is_empty() or ids.has(player.player_id):
			valid = false
			continue
		ids[player.player_id] = true
		teams[player.team] += 1
		if player.is_goalkeeper:
			keepers[player.team] += 1
			valid = valid and player in _game.keepers
		else:
			var field: Array = _game.home_outfield if player.team == 0 else _game.away_outfield
			valid = valid and player in field
	var outfield: Array[int] = [_game.home_outfield.size(), _game.away_outfield.size()]
	valid = valid and teams == [11, 11] and keepers == [1, 1] and outfield == [10, 10]
	valid = valid and _game.players.size() == 22 and _game.keepers.size() == 2
	return {"valid": valid, "players": _game.players.size(), "teams": teams, "keepers": keepers, "outfield": outfield}


func _spread(field: Array) -> Vector2:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for player: FootballPlayer in field:
		var point := Vector2(player.global_position.x, player.global_position.z)
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return maximum - minimum


func _observe() -> void:
	_frames += 1
	_observe_restarts()
	if _throw_entry_check:
		_observe_throw_entry()
	if _game.phase == "finished" or _frames >= _max_frames:
		_finish()
		return
	if _frames % _sample_interval != 0 or _game.phase != "playing" or _game.kickoff_remaining > 0.0 or is_instance_valid(_game.kickoff_taker) or not _game.restart.is_empty():
		return
	_shape_samples += 1
	var ball: FootballBall = _game.ball
	_finite = _finite and ball.global_position.is_finite() and ball.linear_velocity.is_finite()
	if ball.linear_velocity.is_finite():
		_max_ball_speed = maxf(_max_ball_speed, ball.linear_velocity.length())
	for team in range(2):
		var field: Array = _game.home_outfield if team == 0 else _game.away_outfield
		var shape := _spread(field)
		_minimum_width[team] = minf(_minimum_width[team], shape.y)
		_minimum_depth[team] = minf(_minimum_depth[team], shape.x)
		if shape.x >= _initial_shape[team].x * 0.5 and shape.y >= _initial_shape[team].y * 0.5:
			_spread_samples[team] += 1
		var near_ball := 0
		for player: FootballPlayer in field:
			_finite = _finite and player.global_position.is_finite() and player.linear_velocity.is_finite()
			var velocity := Vector2(player.linear_velocity.x, player.linear_velocity.z)
			if velocity.is_finite():
				_max_speed[team] = maxf(_max_speed[team], velocity.length())
			var gap := player.global_position - ball.global_position
			if Vector2(gap.x, gap.z).length() < 3.0:
				near_ball += 1
		_max_near_ball[team] = maxi(_max_near_ball[team], near_ball)
		if near_ball >= 5:
			_crowd_samples[team] += 1
	for keeper: FootballPlayer in _game.keepers:
		_finite = _finite and keeper.global_position.is_finite() and keeper.linear_velocity.is_finite()


func _observe_throw_entry() -> void:
	var ball: FootballBall = _game.ball
	if not _throw_fixture_sent and float(_game.remaining) < _match_seconds - 1.0:
		# Create one out-of-bounds ball. The match awards and takes the throw.
		_throw_fixture_sent = true
		ball.global_position = Vector3(12.0, FootballBall.RADIUS, ElevenPitch.HALF_WIDTH + 0.6)
		ball.last_touch_team = 0
		ball.linear_velocity = Vector3.ZERO
	if _throw_serial != ball.touch_serial or not ball.pass_active or not _throw_tracking.get("entry_receiver", "").is_empty():
		return
	if _throw_tracking.has("outside_receiver") and not _throw_tracking.has("target_depth_m"):
		_throw_tracking["target_depth_m"] = ball.global_position.z - ball.pass_target.z
	if ball.global_position.z < ElevenPitch.HALF_WIDTH - FootballBall.RADIUS:
		_throw_tracking["entry_receiver"] = ball.pass_receiver_id


func _observe_restarts() -> void:
	while _event_cursor < _game.action_log.size():
		var event: Dictionary = _game.action_log[_event_cursor]
		_event_cursor += 1
		var kind: String = event["kind"]
		if kind in RESTARTS:
			_restarts.append({"kind": kind, "team": event["team"], "time": event["time"],
				"start_frame": _frames, "taken_frame": 0, "resumed_frame": 0})
		elif kind == "restart_taken" and not _restarts.is_empty():
			var restart_event: Dictionary = _restarts.back()
			if event.get("restart") == restart_event["kind"]:
				restart_event["taken_frame"] = _frames
				if _throw_entry_check and _throw_serial < 0 and event.get("restart") == "throw_in":
					_throw_serial = int(event["touch_serial"])
		elif kind == "receiver_assigned" and _throw_entry_check and _throw_serial >= 0:
			if int(event["serial"]) == _throw_serial and event.get("detail_kind") == "throw" and float(event["ball"][2]) > ElevenPitch.HALF_WIDTH + 0.2:
				_throw_tracking["outside_receiver"] = event["player"]
				_throw_tracking["assignment_ball_z"] = event["ball"][2]
		elif kind == "kickoff_taken" and not _restarts.is_empty():
			var kickoff: Dictionary = _restarts.back()
			if kickoff["kind"] == "kickoff" and kickoff["team"] == event["team"]:
				kickoff["taken_frame"] = _frames
				kickoff["backward_contact"] = float(event["direction"][0]) > 0.0 and event.has("touch_serial")
	if _restarts.is_empty() or _game.kickoff_remaining > 0.0 or is_instance_valid(_game.kickoff_taker) or not _game.restart.is_empty() or _game.ball.freeze:
		return
	var current: Dictionary = _restarts.back()
	var time := _match_seconds - float(_game.remaining)
	if current["resumed_frame"] == 0 and time > float(current["time"]) + 0.03:
		current["resumed_frame"] = _frames


func _finish() -> void:
	physics_frame.disconnect(_observe)
	var counts: Dictionary = {}
	var by_team: Array[Dictionary] = [{}, {}]
	var shots_on_contact: Array[int] = [0, 0]
	var deliveries := 0
	var stalled_restarts: Array[Dictionary] = []
	var away_kickoffs := 0
	var backward_kickoffs := 0
	var latest_time := _match_seconds - float(_game.remaining)
	for event: Dictionary in _game.action_log:
		var kind: String = event["kind"]
		counts[kind] = int(counts.get(kind, 0)) + 1
		var team := int(event.get("team", -1))
		if team in [0, 1]:
			by_team[team][kind] = int(by_team[team].get(kind, 0)) + 1
			if event.has("contact_distance") and event.get("source", "") in ["controller", "ai"]:
				if kind == "shot":
					shots_on_contact[team] += 1
				elif kind in DELIVERIES:
					deliveries += 1
	for restart_event in _restarts:
		if restart_event["kind"] == "kickoff" and restart_event["team"] == 1:
			away_kickoffs += 1
			if restart_event.get("backward_contact", false):
				backward_kickoffs += 1
		if float(restart_event["time"]) >= _match_seconds - 0.5 and _game.phase == "finished":
			continue
		if restart_event["resumed_frame"] == 0 or (restart_event["kind"] != "kickoff" and restart_event["taken_frame"] == 0):
			stalled_restarts.append(restart_event)
	var minimum_samples := maxi(1, _shape_samples)
	var checks := {
		"full_time": _game.phase == "finished" and is_zero_approx(float(_game.remaining)) and counts.get("full_time", 0) == 1,
		"roster_at_full_time": _measure_roster()["valid"],
		"finite_physics": _finite and _shape_samples > 0,
		"live_ball_actions": deliveries > 0 and counts.get("touch", 0) > 0,
		"both_teams_shoot": shots_on_contact[0] > 0 and shots_on_contact[1] > 0,
		"both_teams_move": _max_speed[0] > 2.0 and _max_speed[1] > 2.0,
		"both_teams_spread": _spread_samples[0] * 2 >= minimum_samples and _spread_samples[1] * 2 >= minimum_samples,
		"crowding_uncommon": _crowd_samples[0] * 2 < minimum_samples and _crowd_samples[1] * 2 < minimum_samples,
		"restart_clock_progression": not _restarts.is_empty() and stalled_restarts.is_empty(),
		"away_kickoff_contact": away_kickoffs == backward_kickoffs and (away_kickoffs > 0 or not "--away-kickoff" in OS.get_cmdline_user_args()),
		"isolated_save": _game.squad.save_path == SAVE_PATH and _game.squad.last_error.is_empty(),
	}
	if _throw_entry_check:
		var entry_receiver: String = _throw_tracking.get("entry_receiver", "")
		checks["throw_receiver_tracks_into_play"] = not entry_receiver.is_empty() and _throw_tracking.get("outside_receiver") == entry_receiver and float(_throw_tracking.get("target_depth_m", 0.0)) > 2.0
	if not _formation_opening.is_empty():
		checks["home_442_applied_at_kickoff"] = _formation_opening["home_formation_selected"] and _formation_opening["home_442"]
		checks["away_433_preserved_at_kickoff"] = _formation_opening["away_433"]
	var passed := not checks.values().has(false)
	var report := {
		"status": "passed" if passed else "failed", "seed": SEED, "roster": _roster, "checks": checks,
		"score": _game.scores, "match_time_s": latest_time, "physics_frames": _frames,
		"menu_settings": _menu_settings,
		"formation_opening": _formation_opening,
		"throw_entry_tracking": _throw_tracking,
		"wall_time_ms": Time.get_ticks_msec() - _started_at, "controller_decisions": _driver.decisions,
		"event_counts": counts, "event_counts_by_team": by_team, "restarts": _restarts, "stalled_restarts": stalled_restarts,
		"shot_contacts_by_team": shots_on_contact, "delivery_contacts": deliveries,
		"shape_samples": _shape_samples, "kickoff_depth_m": [_initial_shape[0].x, _initial_shape[1].x],
		"kickoff_width_m": [_initial_shape[0].y, _initial_shape[1].y], "minimum_depth_m": _minimum_depth,
		"minimum_width_m": _minimum_width, "spread_samples": _spread_samples, "crowd_samples": _crowd_samples,
		"max_players_within_3m_of_ball": _max_near_ball, "max_outfield_speed_mps": _max_speed,
		"max_ball_speed_mps": _max_ball_speed, "save_path": _game.squad.save_path,
	}
	if not _report_path.is_empty():
		var output := FileAccess.open(_report_path, FileAccess.WRITE)
		if output == null:
			_abort("Could not write JSON report to %s" % _report_path)
			return
		var with_events := report.duplicate()
		with_events["events"] = _game.action_log
		output.store_string(JSON.stringify(with_events, "\t") + "\n")
		output.close()
	print("ELEVEN_ACCEPTANCE_RESULT " + JSON.stringify(report))
	quit(0 if passed else 1)


func _abort(message: String) -> void:
	push_error("ELEVEN_ACCEPTANCE_INFRASTRUCTURE " + message)
	quit(2)
