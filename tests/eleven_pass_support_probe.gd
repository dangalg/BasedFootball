extends RefCounted

const SAMPLE_TICKS := 6
const MIN_MOVEMENT := 0.75
const MIN_FORWARD_GAIN := 2.5
const MAX_PASS_RANGE := 20.0
const MIN_CLEARANCE := 0.85

var _flights: Dictionary = {}


func sample(game: Node3D, frame: int) -> void:
	var ball: FootballBall = game.ball
	if not ball.pass_active or ball.pass_team != 0 or game.phase != "playing" \
			or not game.restart.is_empty() or game.kickoff_remaining > 0.0 or is_instance_valid(game.kickoff_taker):
		return
	var serial := ball.touch_serial
	if not _flights.has(serial):
		var starts: Dictionary = {}
		for player: FootballPlayer in game.home_outfield:
			if player.player_id != ball.pass_receiver_id:
				starts[player.player_id] = FootballReception.flat(player.global_position)
		_flights[serial] = {"start_frame": frame, "receiver": ball.pass_receiver_id, "starts": starts, "lanes": {}}
	var flight: Dictionary = _flights[serial]
	var origins: Dictionary = flight["starts"]
	# Discard players the controller moved at any point during this flight.
	origins.erase(game.controlled.player_id)
	var lanes: Dictionary = flight["lanes"]
	lanes.erase(game.controlled.player_id)
	if (frame - int(flight["start_frame"])) % SAMPLE_TICKS != 0:
		return
	lanes.clear()
	var attack: float = game.controlled.attack_sign()
	var receive_point := FootballReception.flat(ball.pass_target)
	var onside := ElevenOffside.line(game.players, 0, attack, receive_point.x)
	for player: FootballPlayer in game.home_outfield:
		if not origins.has(player.player_id) or not player.upright_ready() or ElevenOffside.beyond(player, attack, onside):
			continue
		var start: Vector3 = origins[player.player_id]
		var position := FootballReception.flat(player.global_position)
		var movement := position - start
		var offset := position - receive_point
		if movement.length() < MIN_MOVEMENT or offset.x * attack < MIN_FORWARD_GAIN or offset.length() > MAX_PASS_RANGE:
			continue
		var clearance := _clearance(game.players, receive_point, position)
		if clearance < MIN_CLEARANCE:
			continue
		# A lateral move counts only if it actually opens the lane against
		# the same opponent positions used to judge the final location.
		var previous_clearance := _clearance(game.players, receive_point, start)
		if movement.x * attack < 0.50 and previous_clearance >= MIN_CLEARANCE:
			continue
		lanes[player.player_id] = {
			"player": player.player_id, "frame": frame, "start": _vector(start), "position": _vector(position),
			"projected_receive": _vector(receive_point), "onside_depth": onside, "player_depth": position.x * attack,
			"travel_m": movement.length(), "travel_forward_m": movement.x * attack,
			"ahead_of_receive_m": offset.x * attack, "range_m": offset.length(),
			"clearance_m": clearance, "clearance_from_start_m": previous_clearance,
		}


func summarize(game: Node3D, touches: Array[Dictionary]) -> Dictionary:
	var audit: Dictionary = {}
	for touch in touches:
		audit[touch["serial"]] = touch
	var deliveries: Dictionary = {}
	var completed: Array[Dictionary] = []
	var supported: Array[Dictionary] = []
	var max_gain := -INF
	var max_depth := -INF
	var forward_count := 0
	for event: Dictionary in game.action_log:
		if int(event["team"]) != 0:
			continue
		if event["kind"] in ["pass", "through", "lob"] and event.has("touch_serial") and event.has("ball_position"):
			deliveries[event["touch_serial"]] = event
			continue
		if event["kind"] != "receive_contact":
			continue
		var incoming: int = event["incoming_touch_serial"]
		var received: int = event["touch_serial"]
		var delivery: Dictionary = deliveries.get(incoming, {})
		var before: Dictionary = audit.get(incoming, {})
		var after: Dictionary = audit.get(received, {})
		if delivery.is_empty() or not _live_home_touch(before, event["passer"]) or not _live_home_touch(after, event["receiver"]):
			continue
		var attack := -1.0 if float(event["time"]) >= float(game.match_duration) * 0.5 else 1.0
		var depth := float(event["ball_position"][0]) * attack
		var gain := depth - float(delivery["ball_position"][0]) * attack
		var receipt := {
			"incoming_serial": incoming, "receive_serial": received, "frame": after["frame"], "time": event["time"],
			"passer": event["passer"], "receiver": event["receiver"], "source": delivery["source"],
			"pass_position": delivery["ball_position"], "receive_position": event["ball_position"],
			"forward_gain_m": gain, "receive_depth_m": depth,
		}
		completed.append(receipt)
		max_gain = maxf(max_gain, gain)
		max_depth = maxf(max_depth, depth)
		if gain >= MIN_FORWARD_GAIN:
			forward_count += 1
		var flight: Dictionary = _flights.get(incoming, {})
		if flight.get("receiver", "") != event["receiver"]:
			continue
		for lane: Dictionary in flight["lanes"].values():
			var gap := int(after["frame"]) - int(lane["frame"])
			if gap > 0 and gap <= SAMPLE_TICKS + 1:
				supported.append({"receive": receipt, "outlet": lane, "lead_ticks": gap})
	var follow_ons: Array[Dictionary] = []
	for witness in supported:
		var first: Dictionary = witness["receive"]
		var outlet: Dictionary = witness["outlet"]
		for delivery in completed:
			var elapsed := float(delivery["time"]) - float(first["time"])
			if elapsed <= 0.0 or elapsed > 5.0 or delivery["passer"] != first["receiver"] \
					or delivery["receiver"] != outlet["player"] or float(delivery["forward_gain_m"]) < MIN_FORWARD_GAIN:
				continue
			var kept_play := true
			for serial in range(int(first["receive_serial"]) + 1, int(delivery["incoming_serial"])):
				var intervening: Dictionary = audit.get(serial, {})
				if intervening.get("team", -1) != 0 or not bool(intervening.get("live", false)):
					kept_play = false
					break
			if kept_play:
				follow_ons.append({"support": witness, "delivery": delivery})
				break
	return {
		"observed_home_flights": _flights.size(), "physically_completed_home_passes": completed.size(),
		"forward_completions": forward_count, "largest_forward_gain_m": max_gain if is_finite(max_gain) else null,
		"deepest_home_receive_m": max_depth if is_finite(max_depth) else null,
		"flight_support_witnesses": supported.size(), "first_flight_support": supported.front() if not supported.is_empty() else {},
		"linked_forward_deliveries": follow_ons.size(), "first_linked_forward_delivery": follow_ons.front() if not follow_ons.is_empty() else {},
	}


func _clearance(players: Array[FootballPlayer], origin: Vector3, target: Vector3) -> float:
	var offset := target - origin
	var distance := offset.length()
	var direction := offset.normalized()
	var gap := 5.0
	for opponent in players:
		if opponent.team == 0:
			continue
		var relative := FootballReception.flat(opponent.global_position) - origin
		var along := relative.dot(direction)
		if along > 0.35 and along <= distance + 0.3:
			gap = minf(gap, (relative - direction * along).length())
	return gap


func _live_home_touch(touch: Dictionary, player_id: String) -> bool:
	if touch.get("player", "") != player_id or touch.get("team", -1) != 0 or not bool(touch.get("live", false)):
		return false
	var impulse: Array = touch["impulse"]
	return Vector3(float(impulse[0]), float(impulse[1]), float(impulse[2])).length_squared() > 0.000001


func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
