class_name FootballGoalFlow
extends RefCounted

# A goal is a dead ball, not a teleport. Players return under normal locomotion;
# one receiving teammate retrieves the ball and carries it back visibly.
var game: Node3D
var active := false
var state := ""
var elapsed := 0.0
var total_elapsed := 0.0
var receiving_team := 0
var scorer: FootballPlayer
var runner: FootballPlayer
var carrying := false
var targets: Dictionary = {}
var celebration_target := Vector3.ZERO
var restart_spot := Vector3.ZERO
var restart_kind := "kickoff"
var signalled := false
var ready_elapsed := 0.0
var previous_hand := Vector3.ZERO
var hand_sample_valid := false

func begin_initial(match_node: Node3D, team: int) -> void:
	begin(match_node,1-team)
	state = "returning"
	for player in game.players:
		player.emotion = ""

func begin(match_node: Node3D, scoring: int) -> void:
	game = match_node
	game.referee.return_delay.clear()
	game.referee.last_distance.clear()
	active = true
	state = "celebrating"
	elapsed = 0
	total_elapsed = 0
	receiving_team = 1 - scoring
	restart_spot = Vector3.ZERO
	restart_kind = "kickoff"
	carrying = false
	hand_sample_valid=false
	signalled = false
	ready_elapsed = 0
	scorer = null
	runner = null
	for player in game.players:
		if player.sent_off:
			continue
		if player.player_id == game.ball.last_touch_id:
			scorer = player
		if player.team == receiving_team and player != game.controlled and runner == null:
			runner = player
	if scorer == null or scorer.team != scoring:
		for player in game.players:
			if player.team == scoring and not player.sent_off:
				scorer = player
				break
	if runner == null:
		runner = game.controlled
	celebration_target = scorer.global_position
	for i in range(game.players.size()):
		var player: FootballPlayer = game.players[i]
		var side := -1.0 if player.team == 0 else 1.0
		var index := i % 3
		targets[player.player_id] = Vector3(side * [3.0, 7.0, 11.0][index], .06, [-1.0,5.0,-4.0][index])
		player.buffered_remaining = 0
		player.dribble_active = false
		player.emotion = "celebrate" if player.team == scoring else "sad"
		player.emotion_time = 0
	targets[runner.player_id] = Vector3(-.8 if receiving_team == 0 else .8, .06, 0)
	for player in game.players:
		if player != runner:
			targets[player.player_id] = legal_target(targets[player.player_id],player)
	game.kickoff_remaining = 0
	game.charging = false
	game.delivery_kind = ""
	game._record("celebration_start", scorer, {"team":scoring})

func begin_free_kick(match_node: Node3D, team: int, spot: Vector3) -> void:
	game = match_node
	game.referee.return_delay.clear()
	game.referee.last_distance.clear()
	active = true
	state = "returning"
	elapsed = 0
	total_elapsed = 0
	receiving_team = team
	restart_kind = "free kick"
	restart_spot = Vector3(clampf(spot.x,-16.5,16.5),0,clampf(spot.z,-10.5,10.5))
	carrying = false
	signalled = false
	ready_elapsed = 0
	runner = null
	var best := INF
	for player in game.players:
		if not player.sent_off and player.team == team and player != game.controlled:
			var distance: float = player.global_position.distance_to(game.ball.global_position)
			if distance < best:
				best = distance
				runner = player
	if runner == null:
		runner = game.controlled if game.controlled.team == team else game.players.filter(func(p: FootballPlayer): return p.team == team and not p.sent_off)[0]
	for player in game.players:
		var destination: Vector3 = player.global_position
		if player.team != team:
			var goal := Vector3(-18.0 if player.team == 0 else 18.0,0,0)
			var toward_goal := (goal-restart_spot).normalized()
			var lateral := toward_goal.cross(Vector3.UP)
			var slot: int = game.players.find(player) % 3
			destination = restart_spot + toward_goal * (FootballRules.RESTART_DISTANCE+.3) + lateral * (slot-1) * 1.0
			if goal.distance_to(restart_spot) < FootballRules.RESTART_DISTANCE:
				destination = goal + Vector3(0,0,(slot-1)*.7)
		else:
			var attack := 1.0 if team == 0 else -1.0
			var slot: int = game.players.find(player) % 3
			destination = restart_spot + Vector3(attack * (4 if slot % 2 == 0 else -2),0,3 if slot % 2 == 0 else -4)
			destination.x = clampf(destination.x,-17,17)
			destination.z = clampf(destination.z,-11,11)
		destination = legal_target(destination,player)
		targets[player.player_id] = destination
		player.emotion = ""
	targets[runner.player_id] = restart_spot + Vector3(-.8 if team == 0 else .8,.06,0)
	game.charging = false
	game.delivery_kind = ""
	game.hud.flash("FREE KICK — GIVE SPACE",3)
	game._record("free_kick_awarded",runner,{"spot":game._vec(restart_spot)})
	game.referee.start_marking(restart_spot,team)

func legal_target(preferred: Vector3, player: FootballPlayer) -> Vector3:
	if FootballRules.illegal_position(preferred,player.team,receiving_team,player==runner,restart_kind,restart_spot) == "":
		return preferred
	var best := INF
	var result := preferred
	for i in range(64):
		var candidate := restart_spot + Vector3(cos(i*TAU/64),0,sin(i*TAU/64)) * (FootballRules.RESTART_DISTANCE+.4)
		candidate.x = clampf(candidate.x,-17.8,17.8)
		candidate.z = clampf(candidate.z,-11,11)
		if FootballRules.illegal_position(candidate,player.team,receiving_team,false,restart_kind,restart_spot) != "":
			continue
		var distance := candidate.distance_squared_to(preferred)
		if distance < best:
			best = distance
			result = candidate
	return result

func position_reason(player: FootballPlayer) -> String:
	return FootballRules.illegal_position(player.global_position,player.team,receiving_team,player==runner,restart_kind,restart_spot)

func tick(delta: float) -> void:
	if runner.sent_off:
		for player in game.players:
			if player.team == receiving_team and not player.sent_off:
				runner = player
				if player != game.controlled:
					break
		carrying = false
		state = "returning"
		signalled = false
		targets[runner.player_id] = restart_spot + Vector3(-.8 if receiving_team == 0 else .8,.06,0)
	elapsed += delta
	total_elapsed += delta
	if state == "celebrating" and elapsed >= 3.5:
		state = "returning"
		elapsed = 0
		for player in game.players:
			player.emotion = ""
		game.hud.flash("WALK BACK FOR KICKOFF", 3)
		game._record("return_to_positions", null)
	for player in game.players:
		if player.sent_off:
			continue
		if player == game.controlled:
			if player.intent.length() > .15:
				player.emotion = ""
			continue
		player.sprint = state == "returning" and player == runner
		player.jockey = false
		var destination: Vector3 = targets[player.player_id]
		if state == "celebrating":
			destination = celebration_target + Vector3((game.players.find(player) % 3 - 1) * 1.5, 0, 1.7) if player.team == scorer.team else player.global_position
		elif player == runner and not carrying:
			destination = game.ball.global_position
		_walk(player, destination)
	if state == "ready":
		if not _players_ready():
			signalled = false
			ready_elapsed = 0
			return
		if not signalled:
			signalled = true
			game.sound.play_event("whistle")
		ready_elapsed += delta
		if runner != game.controlled and ready_elapsed > .6 and runner.upright_ready():
			var direction := Vector3(1 if receiving_team == 0 else -1,0,1).normalized()
			for teammate in game.players:
				if teammate.team == receiving_team and teammate != runner and not teammate.sent_off:
					direction = (teammate.global_position-game.ball.global_position).normalized()
					break
			runner.kick(game.ball,direction,9,.08,"pass")
		return
	if state not in ["returning", "placing"]:
		return
	if not carrying and runner.global_position.distance_to(game.ball.global_position) < 1.1:
		carrying = true
		hand_sample_valid=false
		game._record("ball_retrieved", runner)
	if carrying:
		var hand := runner.visual_controller.carry_anchor()
		if state == "placing":
			hand = hand.lerp(restart_spot+Vector3.UP*FootballBall.RADIUS,smoothstep(0,.65,elapsed))
		# The hand midpoint also moves when the torso turns and the arms settle.
		# Root velocity alone misses that motion and lets the ball lag sideways.
		var hand_velocity: Vector3 = (hand-previous_hand)/maxf(delta,.001) if hand_sample_valid else runner.linear_velocity
		hand_velocity=hand_velocity.limit_length(14)
		previous_hand=hand
		hand_sample_valid=true
		runner.emotion = "carry" if state == "returning" else "place"
		# Damping relative to the carrier avoids a speed-dependent trailing ball.
		# Gravity support prevents the carried ball sagging below the palms.
		var force: Vector3 = (hand - game.ball.global_position) * 65 - (game.ball.linear_velocity-hand_velocity) * 7 + Vector3.UP*game.ball.mass*9.8
		game.ball.apply_central_force(force.limit_length(55))
		# No collision exception with opponents: the ball remains interceptable.
		if state == "returning" and runner.global_position.distance_to(targets[runner.player_id]) < .65:
			state = "placing"
			elapsed = 0
	if _players_ready() and state == "placing" and game.referee.mark_state == "" and game.ball.global_position.distance_to(restart_spot + Vector3.UP * FootballBall.RADIUS) < .3 and game.ball.linear_velocity.length() < .2:
		state = "ready"
		carrying = false
		runner.emotion=""
		signalled = true
		game.sound.play_event("whistle")
		game.hud.flash("KICK TO RESTART",2)

func _walk(player: FootballPlayer, destination: Vector3) -> void:
	var offset := destination - player.global_position
	offset.y = 0
	player.intent = offset.normalized() * minf(offset.length() * 1.3, 1.0) if offset.length() > .3 else Vector3.ZERO
	if player.intent.length() > .1:
		player.aim = player.intent.normalized()
	# A loose ball over the boards is fetched by physically hopping them.
	if (absf(destination.z) > 12) != (absf(player.global_position.z) > 12) and absf(absf(player.global_position.z)-12.18) < 1.6 and player.hop():
		player.apply_central_impulse(Vector3.UP * player.mass * 1.5)

func _players_ready() -> bool:
	for player in game.players:
		if player.sent_off:
			continue
		if position_reason(player) != "":
			return false
	return true

func notify_kick(player: FootballPlayer) -> void:
	if not active:
		return
	if state == "ready" and player == runner and signalled and _players_ready():
		_finish()
	else:
		game._record("restart_retake",player)
		state = "returning"
		carrying = false
		signalled = false

func _finish() -> void:
	active = false
	state = ""
	carrying = false
	for player in game.players:
		player.emotion = ""
	game.ball.last_touch_team = receiving_team
	game.ball.last_touch_id = ""
	game.ball.control_block_remaining = 0
	game.sound.play_event("whistle")
	game.hud.flash("PLAY", 1)
	game._record("natural_kickoff" if restart_kind == "kickoff" else "free_kick_ready", runner)
