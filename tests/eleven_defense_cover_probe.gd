extends RefCounted

const SAMPLE_TICKS := 6
const SUSTAINED_SAMPLES := 4
const COVER_START_DEPTH := 22.0
const CLOSE_PRESS_RANGE := 2.8
const MIN_COVER_DEPTH := 1.5
const MAX_COVER_LATERAL := 2.5

var _coverage: Array[Dictionary] = []
var _streaks: Dictionary = {}


func _init() -> void:
	for _index in range(4):
		_coverage.append({
			"carrier_samples": 0, "pressure_samples": 0, "paired_samples": 0,
			"cover_candidate_samples": 0, "assigned_cover_is_press_samples": 0,
			"episodes": 0, "longest_samples": 0, "longest_witness": {},
			"closest_cover_miss": {}, "closest_assigned_cover_miss": {},
		})


func sample(game: Node3D, frame: int) -> void:
	var ball: FootballBall = game.ball
	if frame % SAMPLE_TICKS != 0 or game.phase != "playing" or not game.restart.is_empty() \
			or game.kickoff_remaining > 0.0 or is_instance_valid(game.kickoff_taker) or ball.freeze \
			or ball.pass_active or not ball.grip_holder_id.is_empty() or absf(ball.global_position.x) < COVER_START_DEPTH:
		return
	var carrier: FootballPlayer = null
	for player: FootballPlayer in game.players:
		if player.player_id == ball.last_touch_id and not player.is_goalkeeper:
			carrier = player
			break
	if carrier == null or not (carrier.controlling_ball() or carrier.chasing_ball(ball)):
		return
	var attack := carrier.attack_sign()
	var ball_position := FootballReception.flat(ball.global_position)
	var origin := FootballReception.flat(carrier.global_position)
	if ball_position.x * attack < COVER_START_DEPTH or origin.distance_to(ball_position) > 1.5:
		return
	var own_goal := Vector3(attack * ElevenPitch.HALF_LENGTH, 0.0, 0.0)
	var to_goal := own_goal - origin
	var goalward := to_goal.normalized()
	var max_cover_depth := minf(7.0, to_goal.length())
	var defense := 1 - carrier.team
	var half := 1 if game.ends_swapped else 0
	var group := defense * 2 + half
	var stats := _coverage[group]
	stats["carrier_samples"] += 1
	var press: FootballPlayer = null
	var press_gap := CLOSE_PRESS_RANGE
	var press_speed := 0.0
	for defender: FootballPlayer in game.players:
		if defender.team != defense or defender.is_goalkeeper or defender.ragdoll != null or defender.hop_active \
				or defender.recovery_remaining > 0.0 or defender.stagger_remaining > 0.0:
			continue
		var toward := origin - FootballReception.flat(defender.global_position)
		var distance := toward.length()
		var speed := FootballReception.flat(defender.linear_velocity).dot(toward.normalized())
		var challenging := defender.action_kind in ["standing", "slide", "shoulder"]
		if distance < press_gap and (speed >= 0.5 or challenging):
			press = defender
			press_gap = distance
			press_speed = speed
	if press == null:
		return
	stats["pressure_samples"] += 1
	var assigned_cover: FootballPlayer = null
	var assigned_press: FootballPlayer = null
	var assigned_point := Vector3.INF
	var assignment: Variant = game.get("_containment")
	if assignment is Dictionary and assignment.get("carrier") == carrier:
		assigned_cover = assignment.get("cover")
		assigned_press = assignment.get("press")
		assigned_point = assignment.get("point", Vector3.INF)
	if assigned_cover == press:
		stats["assigned_cover_is_press_samples"] += 1
	var paired := false
	var has_candidate := false
	for defender: FootballPlayer in game.players:
		if defender.team != defense or defender == press or defender.is_goalkeeper or defender.selected \
				or defender.eleven_slot < 3 or not defender.upright_ready():
			continue
		has_candidate = true
		var position := FootballReception.flat(defender.global_position)
		var offset := position - origin
		var advance := offset.dot(goalward)
		var lateral := (offset - goalward * advance).length()
		var cover_gap := offset.length()
		if advance < MIN_COVER_DEPTH or advance > max_cover_depth or lateral > MAX_COVER_LATERAL or cover_gap <= press_gap:
			var depth_excess := maxf(MIN_COVER_DEPTH - advance, maxf(0.0, advance - max_cover_depth))
			var lateral_excess := maxf(0.0, lateral - MAX_COVER_LATERAL)
			var press_order_excess := maxf(0.0, press_gap - cover_gap)
			var total_excess := Vector3(depth_excess, lateral_excess, press_order_excess).length()
			var closest: Dictionary = stats["closest_cover_miss"]
			var closest_assigned: Dictionary = stats["closest_assigned_cover_miss"]
			var is_closest := total_excess < float(closest.get("total_excess_m", INF))
			var is_closest_assigned := defender == assigned_cover and total_excess < float(closest_assigned.get("total_excess_m", INF))
			if is_closest or is_closest_assigned:
				var miss := {
					"frame": frame, "carrier": carrier.player_id, "press": press.player_id, "cover": defender.player_id,
					"assigned_press": assigned_press.player_id if assigned_press != null else "",
					"assigned_cover": assigned_cover.player_id if assigned_cover != null else "",
					"assigned_cover_point": _vector(assigned_point) if assigned_point.is_finite() else [],
					"carrier_position": _vector(origin), "ball_position": _vector(ball_position),
					"press_position": _vector(press.global_position), "cover_position": _vector(position),
					"press_range_m": press_gap, "cover_range_m": cover_gap, "cover_goalward_m": advance, "cover_lateral_m": lateral,
					"depth_excess_m": depth_excess, "lateral_excess_m": lateral_excess, "press_order_excess_m": press_order_excess,
					"total_excess_m": total_excess,
				}
				if is_closest:
					stats["closest_cover_miss"] = miss
				if is_closest_assigned:
					stats["closest_assigned_cover_miss"] = miss
			continue
		paired = true
		var key := "%d:%s:%s:%s" % [group, carrier.player_id, press.player_id, defender.player_id]
		var run: Dictionary = _streaks.get(key, {})
		if run.is_empty() or int(run["last_frame"]) + SAMPLE_TICKS != frame:
			run = {"samples": 0, "start_frame": frame, "start_cover": position, "start_lateral_m": lateral}
		run["last_frame"] = frame
		run["samples"] += 1
		_streaks[key] = run
		var samples: int = run["samples"]
		if samples == SUSTAINED_SAMPLES:
			stats["episodes"] += 1
		if samples > int(stats["longest_samples"]):
			var start: Vector3 = run["start_cover"]
			stats["longest_samples"] = samples
			stats["longest_witness"] = {
				"start_frame": run["start_frame"], "last_frame": frame, "carrier": carrier.player_id,
				"press": press.player_id, "cover": defender.player_id, "carrier_position": _vector(origin),
				"press_position": _vector(press.global_position), "cover_position": _vector(position), "own_goal": _vector(own_goal),
				"press_range_m": press_gap, "press_speed_toward_carrier_mps": press_speed, "press_action": press.action_kind,
				"cover_goalward_m": advance, "cover_lateral_m": lateral, "cover_travel_m": position.distance_to(start),
				"cover_start_lateral_m": run["start_lateral_m"],
			}
	if paired:
		stats["paired_samples"] += 1
	if has_candidate:
		stats["cover_candidate_samples"] += 1


func summarize(game: Node3D, touches: Array[Dictionary]) -> Dictionary:
	var audit: Dictionary = {}
	for touch in touches:
		audit[touch["serial"]] = touch
	var shots: Dictionary = {}
	var keeper_events: Array[Dictionary] = []
	var results: Array[Dictionary] = []
	for _team in range(2):
		results.append({"live_shots": 0, "goalward_shots": 0, "attacking_third_shots": 0, "goals": 0, "own_goals_for": 0,
			"live_keeper_catches": 0, "live_keeper_parries": 0, "live_keeper_saves_after_shot": 0})
	for event: Dictionary in game.action_log:
		var team := int(event["team"])
		if team not in [0, 1]:
			continue
		var metrics := results[team]
		if event["kind"] == "goal":
			metrics["goals"] += 1
			if event.get("own_goal", false):
				metrics["own_goals_for"] += 1
		if event["kind"] in ["shot", "kick_contact", "keeper_catch", "keeper_parry"] and event.has("touch_serial"):
			var serial: int = event["touch_serial"]
			var physical: Dictionary = audit.get(serial, {})
			if not bool(physical.get("live", false)) or physical.get("player") != event["player"] or physical.get("team") != team:
				continue
			if event["kind"] == "shot" and event.has("ball_position"):
				shots[serial] = event
				metrics["live_shots"] += 1
				var attack := _attack_sign(team, float(event["time"]), float(game.match_duration))
				if float(event["ball_position"][0]) * attack >= ElevenPitch.HALF_LENGTH / 3.0:
					metrics["attacking_third_shots"] += 1
			elif event["kind"] == "kick_contact" and event.get("detail_kind") == "shot" and event.has("predicted_velocity_after"):
				var attack := _attack_sign(team, float(event["time"]), float(game.match_duration))
				if float(event["predicted_velocity_after"][0]) * attack > 0.0:
					metrics["goalward_shots"] += 1
			elif event["kind"] in ["keeper_catch", "keeper_parry"] and physical["kind"] == "save" and event.get("hand_contact", false):
				var outcome := "live_keeper_catches" if event["kind"] == "keeper_catch" else "live_keeper_parries"
				metrics[outcome] += 1
				var shot: Dictionary = shots.get(serial - 1, {})
				if not shot.is_empty() and shot["team"] != team:
					metrics["live_keeper_saves_after_shot"] += 1
				keeper_events.append(event)
	return {
		"home_first_half": _coverage[0], "home_second_half": _coverage[1],
		"away_first_half": _coverage[2], "away_second_half": _coverage[3],
		"home_outcomes": results[0], "away_outcomes": results[1], "keeper_contacts": keeper_events,
	}


func _attack_sign(team: int, time: float, duration: float) -> float:
	return 1.0 if (team == 0) == (time < duration * 0.5) else -1.0


func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
