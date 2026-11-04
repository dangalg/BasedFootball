extends RefCounted

const DELIVERIES := ["pass", "through", "lob"]
const DEFENSIVE_INPUTS := ["switch", "jockey", "teammate_press", "tackle", "slide", "shoulder"]


static func summarize(game: Node3D, inputs: Array[Dictionary], event_frames: Array[int], touches: Array[Dictionary]) -> Dictionary:
	var hz := float(Engine.physics_ticks_per_second)
	var audit := {}
	for touch in touches:
		audit[int(touch["serial"])] = touch
	var assignments := {}
	var receives := {}
	var kick_contacts := {}
	var strikes: Array[Dictionary] = []
	var switches: Array[Dictionary] = []
	var requests := {}
	var queued := {}
	var shot_sequences := {}
	var contested_circle_tackles: Array[Dictionary] = []
	var defensive_shot_requests: Array[Dictionary] = []
	var defensive_shot_queues := 0
	var counts := {}
	var goal_score: Array[int] = [0, 0]
	var full_time_score: Array = []
	for index in range(game.action_log.size()):
		var event: Dictionary = game.action_log[index]
		var kind: String = event["kind"]
		var player: String = event["player"]
		var frame := event_frames[index] if index < event_frames.size() else -1
		var serial := int(event.get("touch_serial", -1))
		counts[kind] = int(counts.get(kind, 0)) + 1
		match kind:
			"receiver_assigned":
				assignments[int(event["serial"])] = event
			"receive_contact":
				receives[int(event["incoming_touch_serial"])] = event
			"kick_contact":
				kick_contacts[serial] = event
			"pass", "through", "lob", "shot":
				if event.get("source") == "controller" and event.has("contact_distance"):
					strikes.append(event)
				if kind == "shot" and serial >= 0:
					var sequence: Dictionary = queued.get(player, {})
					if not sequence.is_empty() and frame - int(sequence["queue_frame"]) <= ceili(hz * 0.35):
						shot_sequences[serial] = sequence
					queued.erase(player)
			"shot_requested":
				var request := {"request": event, "request_frame": frame}
				var release := _recent_input(inputs, ["tackle"], frame, 2, player, false, -1, 2)
				if not release.is_empty():
					var press := _recent_input(inputs, ["tackle"], int(release["frame"]), ceili(hz * 0.6), player, true)
					if press.get("defend", false):
						request["defensive_circle"] = {"press": press, "release": release}
						defensive_shot_requests.append(request)
				requests[player] = request
				queued.erase(player)
			"shot_queued":
				var request: Dictionary = requests.get(player, {})
				if not request.is_empty() and frame - int(request["request_frame"]) <= ceili(hz * 0.6):
					queued[player] = request.merged({"queue": event, "queue_frame": frame})
					if request.has("defensive_circle"):
						defensive_shot_queues += 1
			"shot_buffer_expired":
				requests.erase(player)
				queued.erase(player)
			"switch":
				var command := _recent_input(inputs, ["switch"], frame, 2, "", true, -1, 2)
				if event.get("source") == "controller" and not command.is_empty() and command["player"] != player:
					switches.append({"input": command, "event": event})
			"circle_tackle":
				var command := _recent_input(inputs, ["tackle"], frame, 2, player, true, serial, 2)
				if event.get("strike_in_reach", false) and event.get("queued", false) and command.get("defend", false):
					contested_circle_tackles.append({"input": command, "event": event})
			"goal":
				var scoring := int(event["team"])
				if scoring in [0, 1]:
					goal_score[scoring] += 1
			"full_time":
				full_time_score = event["score"]

	var pass_receipts: Array[Dictionary] = []
	var received_passes: Array[Dictionary] = []
	var shot_receipts: Array[Dictionary] = []
	var defensive_shot_contacts := 0
	for strike in strikes:
		var serial: int = strike["touch_serial"]
		var player: String = strike["player"]
		var kind: String = strike["kind"]
		var kick: Dictionary = kick_contacts.get(serial, {})
		var touch: Dictionary = audit.get(serial, {})
		if not _physical_touch(touch, player) or touch.get("controlled") != player or kick.get("player") != player or kick.get("detail_kind") != kind:
			continue
		if float(kick.get("boot_gap", INF)) > FootballPlayer.STRIKE_BOOT_REACH:
			continue
		if kind in DELIVERIES:
			var command := _recent_input(inputs, [kind], int(touch["frame"]), ceili(hz * 0.28), player, true, serial - 1)
			if command.is_empty():
				continue
			var receipt := {"input": command, "strike": strike, "touch": touch}
			pass_receipts.append(receipt)
			var receive: Dictionary = receives.get(serial, {})
			var assignment: Dictionary = assignments.get(serial, {})
			var receiver: String = receive.get("receiver", "")
			var receive_touch: Dictionary = audit.get(int(receive.get("touch_serial", -1)), {})
			if receiver != player and assignment.get("player") == receiver and assignment.get("passer") == player and receive.get("passer") == player and _physical_touch(receive_touch, receiver):
				received_passes.append(receipt.merged({"assignment": assignment, "receive": receive, "receive_touch": receive_touch}))
		elif kind == "shot":
			var sequence: Dictionary = shot_sequences.get(serial, {})
			if sequence.is_empty():
				continue
			if sequence.has("defensive_circle"):
				defensive_shot_contacts += 1
				continue
			var release := _recent_input(inputs, ["shoot"], int(sequence["request_frame"]), 2, player, false, -1, 2)
			if release.is_empty():
				continue
			var press := _recent_input(inputs, ["shoot"], int(release["frame"]), ceili(hz * 1.25), player, true)
			if not press.is_empty():
				shot_receipts.append(sequence.merged({"press": press, "release": release, "strike": strike, "touch": touch}))

	var regains: Array[Dictionary] = []
	var deflections := 0
	for index in range(1, touches.size()):
		var previous := touches[index - 1]
		var touch := touches[index]
		var player: String = touch["player"]
		var frame: int = touch["frame"]
		if previous["team"] != 1 or not previous["live"] or not _physical_touch(touch, player) or touch["controlled"] != player:
			continue
		var incoming_serial := int(previous["serial"])
		var command := _recent_input(inputs, DEFENSIVE_INPUTS, frame, ceili(hz * 2.0), "", true, incoming_serial)
		var is_deflection: bool = touch["kind"] == "deflection"
		if is_deflection and command.is_empty():
			command = _recent_input(inputs, ["shoot", "lob"], frame, ceili(hz * 0.5), player, true, incoming_serial)
		if command.is_empty():
			continue
		regains.append({"input": command, "away_touch": previous, "home_touch": touch})
		if is_deflection:
			deflections += 1

	var input_counts := {}
	for command in inputs:
		if bool(command.get("pressed", true)) and bool(command.get("live", false)):
			var action: String = command["action"]
			input_counts[action] = int(input_counts.get(action, 0)) + 1
	return {
		"checks": {
			"joypad_pass_reaches_teammate": not received_passes.is_empty(),
			"joypad_shot_makes_boot_contact": not shot_receipts.is_empty(),
			"joypad_switch_changes_player": not switches.is_empty(),
			"defensive_input_precedes_selected_player_regain": not regains.is_empty(),
			"contested_circle_queues_tackle": not contested_circle_tackles.is_empty(),
			"defensive_circle_never_requests_shot": defensive_shot_requests.is_empty(),
			"goals_account_for_score": goal_score == game.scores and goal_score == full_time_score and counts.get("goal", 0) == goal_score[0] + goal_score[1],
		},
		"live_input_counts": input_counts,
		"delivery_contacts": pass_receipts.size(),
		"delivery_receptions": received_passes.size(),
		"shot_requests": counts.get("shot_requested", 0),
		"shot_queues": counts.get("shot_queued", 0),
		"shot_expirations": counts.get("shot_buffer_expired", 0),
		"shot_contacts": shot_receipts.size(),
		"switches": switches.size(),
		"regains_after_defensive_input": regains.size(),
		"selected_deflections_during_regains": deflections,
		"contested_circle_tackles": contested_circle_tackles.size(),
		"defensive_circle_shot_requests": defensive_shot_requests.size(),
		"defensive_circle_shot_queues": defensive_shot_queues,
		"defensive_circle_shot_contacts": defensive_shot_contacts,
		"goal_ledger": goal_score,
		"full_time_score": full_time_score,
		"examples": {
			"delivery": _first(pass_receipts),
			"reception": _first(received_passes),
			"shot": _first(shot_receipts),
			"switch": _first(switches),
			"regain": _first(regains),
			"contested_circle_tackle": _first(contested_circle_tackles),
			"defensive_circle_shot_request": _first(defensive_shot_requests),
		},
	}


static func _physical_touch(touch: Dictionary, player: String) -> bool:
	if touch.is_empty() or not touch.get("live", false) or touch.get("player") != player or touch.get("team") != 0:
		return false
	var impulse: Variant = touch.get("impulse")
	if impulse is Vector3:
		return impulse.is_finite() and impulse.length_squared() > 0.000001
	if impulse is Array and impulse.size() == 3:
		var force := Vector3(float(impulse[0]), float(impulse[1]), float(impulse[2]))
		return force.is_finite() and force.length_squared() > 0.000001
	return false


static func _recent_input(inputs: Array[Dictionary], actions: Array, frame: int, window: int, player: String, pressed: bool, serial: int = -1, frame_tolerance: int = 0) -> Dictionary:
	for index in range(inputs.size() - 1, -1, -1):
		var command := inputs[index]
		var age := frame - int(command["frame"])
		if age > window:
			break
		if age < -frame_tolerance or not command.get("live", false) or command.get("pressed", true) != pressed or not command["action"] in actions:
			continue
		if serial >= 0 and int(command.get("serial", -1)) != serial:
			continue
		if player.is_empty() or command["player"] == player:
			return command
	return {}


static func _first(receipts: Array[Dictionary]) -> Dictionary:
	return {} if receipts.is_empty() else receipts[0]
