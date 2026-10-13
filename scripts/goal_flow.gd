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

func begin(match_node: Node3D, scoring: int) -> void:
	game = match_node
	active = true
	state = "celebrating"
	elapsed = 0
	total_elapsed = 0
	receiving_team = 1 - scoring
	carrying = false
	scorer = null
	runner = null
	for player in game.players:
		if player.player_id == game.ball.last_touch_id:
			scorer = player
		if player.team == receiving_team and player != game.controlled and runner == null:
			runner = player
	if scorer == null or scorer.team != scoring:
		scorer = game.players[scoring * 3]
	celebration_target = scorer.global_position
	for i in range(game.players.size()):
		var player: FootballPlayer = game.players[i]
		var side := -1.0 if player.team == 0 else 1.0
		var index := i % 3
		targets[player.player_id] = Vector3(side * [3.0, 7.0, 11.0][index], .06, [-1.0,5.0,-4.0][index])
		player.reset_action()
		player.emotion = "celebrate" if player.team == scoring else "sad"
		player.emotion_time = 0
	targets[runner.player_id] = Vector3(-.8 if receiving_team == 0 else .8, .06, 0)
	game.kickoff_remaining = 0
	game.charging = false
	game.delivery_kind = ""
	game._record("celebration_start", scorer, {"team":scoring})

func tick(delta: float) -> void:
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
		if player == game.controlled:
			if player.intent.length() > .15:
				player.emotion = ""
			continue
		player.sprint = false
		player.jockey = false
		var destination: Vector3 = targets[player.player_id]
		if state == "celebrating":
			destination = celebration_target + Vector3((game.players.find(player) % 3 - 1) * 1.5, 0, 1.7) if player.team == scorer.team else player.global_position
		elif player == runner and not carrying:
			destination = game.ball.global_position
		_walk(player, destination)
	if state not in ["returning", "placing"]:
		return
	if not carrying and runner.global_position.distance_to(game.ball.global_position) < 1.1:
		carrying = true
		game._record("ball_retrieved", runner)
	if carrying:
		var hand := runner.global_position + Vector3.UP * 1.04 + runner.aim * .42
		if state == "placing":
			hand = Vector3(0, FootballBall.RADIUS, 0)
		runner.emotion = "carry" if state == "returning" else ""
		var force: Vector3 = (hand - game.ball.global_position) * 32 - game.ball.linear_velocity * 5
		game.ball.apply_central_force(force.limit_length(35))
		# No collision exception with opponents: the ball remains interceptable.
		if state == "returning" and runner.global_position.distance_to(targets[runner.player_id]) < .65:
			state = "placing"
			elapsed = 0
	if _players_ready() and state == "placing" and game.ball.global_position.distance_to(Vector3(0, FootballBall.RADIUS, 0)) < .45 and game.ball.linear_velocity.length() < 1.2:
		_finish()

func _walk(player: FootballPlayer, destination: Vector3) -> void:
	var offset := destination - player.global_position
	offset.y = 0
	player.intent = offset.normalized() * minf(offset.length() * .9, .65) if offset.length() > .3 else Vector3.ZERO
	if player.intent.length() > .1:
		player.aim = player.intent.normalized()

func _players_ready() -> bool:
	for player in game.players:
		if player.global_position.distance_to(targets[player.player_id]) > 1.5 or not player.upright_ready():
			return false
	return true

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
	game._record("natural_kickoff", runner)
