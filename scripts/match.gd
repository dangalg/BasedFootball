extends Node3D

signal match_finished

const DURATION := 180.0
var players: Array[FootballPlayer] = []
var ball: FootballBall
var camera: Camera3D
var hud: FootballHUD
var sound: FootballSound
var squad := FootballSquad.new()
var controlled: FootballPlayer
var selected_index: int = 0
var scores: Array[int] = [0, 0]
var remaining: float = DURATION
var kickoff_remaining: float = 1.5
var phase: String = "playing"
var charge: float = 0.0
var charging: bool = false
var delivery_kind := ""
var delivery_charge := 0.0
var delivery_high := false
var vibration_intensity := 0.6
var right_stick_latched: bool = false
var camera_focus := Vector3.ZERO
var aim_line: MeshInstance3D
var action_log: Array[Dictionary] = []
var match_count: int = 0
var acceptance: bool = false
var pause_requested: bool = false
var decision_driver: Node
var pause_states: Array[Dictionary] = []
var goal_flow := FootballGoalFlow.new()

func _ready() -> void:
	var visual_acceptance := "--visual-acceptance" in OS.get_cmdline_user_args()
	var handling_acceptance := "--handling-acceptance" in OS.get_cmdline_user_args()
	var decision_acceptance := "--decision-acceptance" in OS.get_cmdline_user_args()
	var impact_acceptance := "--impact-acceptance" in OS.get_cmdline_user_args()
	var athlete_acceptance := "--athlete-acceptance" in OS.get_cmdline_user_args()
	var skinned_shot_acceptance := "--skinned-shot-acceptance" in OS.get_cmdline_user_args()
	var shots_team_acceptance := "--shots-team-acceptance" in OS.get_cmdline_user_args()
	var human_motion_acceptance := "--human-motion-acceptance" in OS.get_cmdline_user_args()
	var teamplay_acceptance := "--teamplay-acceptance" in OS.get_cmdline_user_args()
	var contact_play_acceptance := "--contact-play-acceptance" in OS.get_cmdline_user_args()
	var core_handling_acceptance := "--core-handling-acceptance" in OS.get_cmdline_user_args()
	var core_striking_acceptance := "--core-striking-acceptance" in OS.get_cmdline_user_args()
	core_handling_acceptance = core_handling_acceptance or core_striking_acceptance
	contact_play_acceptance = contact_play_acceptance or core_handling_acceptance
	shots_team_acceptance = shots_team_acceptance or human_motion_acceptance or teamplay_acceptance or contact_play_acceptance
	skinned_shot_acceptance = skinned_shot_acceptance or shots_team_acceptance
	athlete_acceptance = athlete_acceptance or skinned_shot_acceptance
	visual_acceptance = visual_acceptance or athlete_acceptance
	acceptance = impact_acceptance or decision_acceptance or handling_acceptance or visual_acceptance or "--acceptance" in OS.get_cmdline_user_args() or "--dribble-acceptance" in OS.get_cmdline_user_args()
	_install_input()
	squad.load_squad(acceptance)
	_build_pitch()
	_build_players()
	ball = FootballBall.new()
	ball.name = "Ball"
	add_child(ball)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 43
	camera.position = Vector3(0, 34, 29)
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	hud = FootballHUD.new()
	add_child(hud)
	sound = FootballSound.new()
	add_child(sound)
	var aim_shape := BoxMesh.new()
	aim_shape.size = Vector3(0.065, 0.04, 1.7)
	aim_line = FootballArt.mesh(self, aim_shape, FootballArt.material(Color("ffe58b")))
	reset_positions(0)
	_select(0)
	hud.flash("YOUR TEAM. YOUR GAME.", 3.0)
	if visual_acceptance or handling_acceptance or impact_acceptance:
		# Windowless scene validation never reads hardware input or runs a match.
		set_physics_process(false)
		set_process(false)
		set_process_unhandled_input(false)
		for player in players:
			player.freeze = true
		ball.freeze = true
		var session: Node = load("res://tests/core_striking_acceptance.gd" if core_striking_acceptance else "res://tests/core_handling_acceptance.gd" if core_handling_acceptance else "res://tests/contact_play_acceptance.gd" if contact_play_acceptance else "res://tests/teamplay_acceptance.gd" if teamplay_acceptance else "res://tests/human_motion_acceptance.gd" if human_motion_acceptance else "res://tests/shots_team_acceptance.gd" if shots_team_acceptance else "res://tests/skinned_shot_acceptance.gd" if skinned_shot_acceptance else "res://tests/athlete_acceptance.gd" if athlete_acceptance else "res://tests/impact_acceptance.gd" if impact_acceptance else "res://tests/handling_acceptance.gd" if handling_acceptance else "res://tests/visual_acceptance.gd").new()
		add_child(session)
		session.begin(self)
	elif decision_acceptance:
		set_process_unhandled_input(false)
		decision_driver = load("res://tests/decision_acceptance.gd").new()
		add_child(decision_driver)
		decision_driver.begin(self)
	elif acceptance:
		var session_path := "res://tests/dribble_acceptance.gd" if "--dribble-acceptance" in OS.get_cmdline_user_args() else "res://tests/acceptance.gd"
		var session: Node = load(session_path).new()
		add_child(session)
		session.begin(self)

func _install_input() -> void:
	for action in ["left", "right", "up", "down", "pass", "shoot", "lob", "through", "jockey", "tackle", "slide", "shoulder", "hop", "sprint", "switch", "modifier_r1", "pause", "confirm", "quit"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.18)
	var key_bindings := {"left": KEY_A, "right": KEY_D, "up": KEY_W, "down": KEY_S, "pass": KEY_SPACE, "shoot": KEY_J, "lob": KEY_U, "through": KEY_I, "jockey": KEY_CTRL, "tackle": KEY_K, "slide": KEY_L, "shoulder": KEY_H, "sprint": KEY_SHIFT, "switch": KEY_TAB, "pause": KEY_ESCAPE, "confirm": KEY_ENTER, "quit": KEY_Q}
	for action in key_bindings:
		var key := InputEventKey.new()
		key.physical_keycode = key_bindings[action]
		InputMap.action_add_event(action, key)
	var hop_key := InputEventKey.new()
	hop_key.physical_keycode = KEY_E
	InputMap.action_add_event("hop", hop_key)
	var modifier_key := InputEventKey.new()
	modifier_key.physical_keycode = KEY_F
	InputMap.action_add_event("modifier_r1", modifier_key)
	# Godot's standardized south/east/west/north slots also cover PlayStation pads.
	var buttons := {"pass": JOY_BUTTON_A, "shoot": JOY_BUTTON_B, "lob": JOY_BUTTON_X, "through": JOY_BUTTON_Y, "switch": JOY_BUTTON_LEFT_SHOULDER, "pause": JOY_BUTTON_START, "confirm": JOY_BUTTON_A, "quit": JOY_BUTTON_BACK}
	for action in buttons:
		var button := InputEventJoypadButton.new()
		button.button_index = buttons[action]
		InputMap.action_add_event(action, button)
	var hop_button := InputEventJoypadButton.new()
	hop_button.button_index = JOY_BUTTON_RIGHT_STICK
	InputMap.action_add_event("hop", hop_button)
	var modifier_button := InputEventJoypadButton.new()
	modifier_button.button_index = JOY_BUTTON_RIGHT_SHOULDER
	InputMap.action_add_event("modifier_r1", modifier_button)
	for mapping in [["left", JOY_AXIS_LEFT_X, -1.0], ["right", JOY_AXIS_LEFT_X, 1.0], ["up", JOY_AXIS_LEFT_Y, -1.0], ["down", JOY_AXIS_LEFT_Y, 1.0], ["sprint", JOY_AXIS_TRIGGER_RIGHT, 1.0], ["jockey", JOY_AXIS_TRIGGER_LEFT, 1.0]]:
		var axis := InputEventJoypadMotion.new()
		axis.axis = mapping[1]
		axis.axis_value = mapping[2]
		InputMap.action_add_event(mapping[0], axis)

func _build_pitch() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("1b2930")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c4d3da")
	environment.ambient_light_energy = 0.4
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -28, 0)
	sun.light_color = Color("fff1dc")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80
	sun.shadow_blur = 1.5
	add_child(sun)
	var concrete := FootballArt.surface(Color("39474b"), FootballArt.CONCRETE, 12)
	var grass_dark := FootballArt.surface(Color("275c49"), FootballArt.TURF, 14)
	var grass_light := FootballArt.surface(Color("2c6350"), FootballArt.TURF, 14)
	var white := FootballArt.material(Color("ced8bd"))
	var board := FootballArt.material(Color("495d61"))
	var blue := FootballArt.material(Color("328da9"))
	var orange := FootballArt.material(Color("cb6a53"))
	var trim := FootballArt.material(Color("b0b5a5"))
	var rail := FootballArt.material(Color("253b44"), 0.5)
	FootballArt.solid(self, Vector3(70, 0.5, 55), Vector3(0, -0.4, 0), concrete)
	FootballArt.solid(self, Vector3(36, 0.25, 24), Vector3(0, -0.13, 0), grass_dark)
	for i in range(8):
		FootballArt.box(self, Vector3(4.5, 0.006, 24), Vector3(-15.75 + i * 4.5, 0.002, 0), grass_light if i % 2 == 0 else grass_dark)
	for side in [-1.0, 1.0]:
		FootballArt.solid(self, Vector3(36.8, 1.0, 0.35), Vector3(0, 0.5, side * 12.18), board)
		FootballArt.box(self, Vector3(36.8, 0.07, 0.4), Vector3(0, 1.025, side * 12.18), trim)
		FootballArt.box(self, Vector3(36, 0.055, 0.018), Vector3(0, 0.24, side * 11.99), blue if side < 0 else orange)
		for segment in range(18):
			FootballArt.box(self, Vector3(0.035, 0.86, 0.018), Vector3(-17 + segment * 2, 0.53, side * 11.995), rail)
		for lane in [-1.0, 1.0]:
			FootballArt.solid(self, Vector3(0.35, 1.0, 9.8), Vector3(side * 18.18, 0.5, lane * 7.25), board)
			FootballArt.box(self, Vector3(0.4, 0.07, 9.8), Vector3(side * 18.18, 1.025, lane * 7.25), trim)
		_build_goal(side, blue if side < 0 else orange)
		FootballArt.line(self, Vector3(-17.9, 0.015, side * 11.9), Vector3(17.9, 0.015, side * 11.9), 0.06, white)
		FootballArt.line(self, Vector3(side * 17.9, 0.015, -11.9), Vector3(side * 17.9, 0.015, 11.9), 0.06, white)
		FootballArt.line(self, Vector3(side * 12.5, 0.015, -4.2), Vector3(side * 12.5, 0.015, 4.2), 0.06, white)
		for lane in [-1.0, 1.0]:
			FootballArt.line(self, Vector3(side * 12.5, 0.015, lane * 4.2), Vector3(side * 17.9, 0.015, lane * 4.2), 0.06, white)
		# All courtyard dressing is visual-only and stays outside the playing area.
		for row in range(3):
			FootballArt.box(self, Vector3(30, 0.5, 1.15), Vector3(0, 0.15 + row * 0.5, side * (14.0 + row * 1.2)), concrete)
			for seat in range(14):
				FootballArt.box(self, Vector3(0.78, 0.12, 0.62), Vector3(-13 + seat * 2, 0.48 + row * 0.5, side * (14.0 + row * 1.2)), blue if side < 0 else orange)
		# Fence uprights and a low perimeter wall frame the court without a crowd.
		FootballArt.box(self, Vector3(44, 0.7, 0.4), Vector3(0, 0.35, side * 18.7), concrete)
		for x in range(-22, 23, 4):
			FootballArt.cylinder(self, 0.045, 2.0, Vector3(x, 1.65, side * 18.7), rail)
		for height in [0.95, 1.7, 2.6]:
			FootballArt.box(self, Vector3(44, 0.035, 0.035), Vector3(0, height, side * 18.7), rail)
	FootballArt.line(self, Vector3(0, 0.015, -11.9), Vector3(0, 0.015, 11.9), 0.07, white)
	FootballArt.circle(self, 3.0, Vector3(0, 0.018, 0), white, 0.035)
	FootballArt.cylinder(self, 0.12, 0.02, Vector3(0, 0.025, 0), white)
	# Branding sits on a small board at the far edge, away from the scoreboard.
	FootballArt.box(self, Vector3(7.6, 1.0, 0.16), Vector3(-10, 1.6, -13), rail)
	var sign := FootballArt.text(self, "THE COURTYARD", Vector3(-10, 1.6, -12.88), 36, Color("c9d9c7"))
	sign.pixel_size = 0.008
	sign.outline_size = 0
	for x in [-21.0, 21.0]:
		for z in [-14.0, 14.0]:
			FootballArt.cylinder(self, 0.12, 6.0, Vector3(x, 3, z), concrete)
			FootballArt.box(self, Vector3(1.3, 0.2, 0.55), Vector3(x, 6, z), white)
	# Planters and benches provide scale without adding gameplay obstacles.
	var leaves := FootballArt.material(Color("345845"))
	var wood := FootballArt.material(Color("927058"))
	for x in [-22.0, 22.0]:
		for z in [-9.0, 9.0]:
			FootballArt.box(self, Vector3(1.8, 0.7, 1.8), Vector3(x, 0.35, z), concrete)
			FootballArt.sphere(self, 0.85, Vector3(x, 0.9, z), leaves).scale = Vector3(1, 0.7, 1)
		FootballArt.box(self, Vector3(0.9, 0.15, 4), Vector3(x, 0.65, 0), wood)
		for z in [-1.5, 1.5]:
			FootballArt.box(self, Vector3(0.7, 0.55, 0.12), Vector3(x, 0.3, z), rail)

func _build_goal(side: float, mat: Material) -> void:
	var post := FootballArt.material(Color("d6dbc9"), 0.45)
	# Collision boxes are identical; round posts and open nets replace only meshes.
	for z in [-2.3, 2.3]:
		FootballArt.hide_solid_mesh(FootballArt.solid(self, Vector3(0.18, 2.4, 0.18), Vector3(side * 18.1, 1.2, z), post))
		FootballArt.cylinder(self, 0.1, 2.4, Vector3(side * 18.1, 1.2, z), post)
	FootballArt.hide_solid_mesh(FootballArt.solid(self, Vector3(0.18, 0.18, 4.78), Vector3(side * 18.1, 2.4, 0), post))
	var crossbar := FootballArt.cylinder(self, 0.1, 4.78, Vector3(side * 18.1, 2.4, 0), post)
	crossbar.rotation.x = PI * 0.5
	FootballArt.hide_solid_mesh(FootballArt.solid(self, Vector3(0.2, 2.4, 4.8), Vector3(side * 20.1, 1.2, 0), mat))
	for z in [-2.4, 2.4]:
		FootballArt.hide_solid_mesh(FootballArt.solid(self, Vector3(2.1, 2.4, 0.15), Vector3(side * 19.1, 1.2, z), mat))
		FootballArt.net(self, Vector2(2.05, 2.3), Vector3(side * 19.1, 1.2, z), 0)
		FootballArt.box(self, Vector3(2.1, 0.065, 0.065), Vector3(side * 19.1, 2.35, z), post)
	FootballArt.net(self, Vector2(4.6, 2.3), Vector3(side * 20.0, 1.2, 0), PI * 0.5)
	var roof := FootballArt.net(self, Vector2(4.6, 2.05), Vector3(side * 19.1, 2.35, 0), PI * 0.5)
	roof.rotation.x = PI * 0.5

func _build_players() -> void:
	for team in range(2):
		for index in range(3):
			var player := FootballPlayer.new()
			player.team = team
			squad.apply_to(player, index)
			if team == 1:
				# Identical base abilities; opponents do not inherit your career XP.
				var entry: Dictionary = squad.entries[index]
				player.player_id = "opponent_" + str(entry["id"])
				player.player_name = ["FINN", "RAE", "MAX"][index]
				player.touch_skill = float(entry["touch"])
				player.stamina_trait = float(entry["stamina"])
				player.mass = float(entry["mass"])
			player.name = player.player_id
			add_child(player)
			player.strike_contact.connect(_on_strike_contact.bind(player))
			player.dribble_contact.connect(_on_dribble_contact.bind(player))
			player.physical_event.connect(_on_physical_event.bind(player))
			players.append(player)

func reset_positions(kickoff_team: int) -> void:
	for i in range(players.size()):
		var player := players[i]
		var index := i % 3
		var side := -1.0 if player.team == 0 else 1.0
		var pos := Vector3(side * [3.0, 7.0, 11.0][index], 0.06, [-1.0, 5.0, -4.0][index])
		if player.team == kickoff_team and index == 0:
			pos = Vector3(side * 0.8, 0.06, 0)
		player.global_position = pos
		player.linear_velocity = Vector3.ZERO
		player.angular_velocity = Vector3.ZERO
		player.intent = Vector3.ZERO
		player.aim = Vector3(-side, 0, 0)
		player.kick_cooldown = 0.0
		player.touch_cooldown = 0.0
		player.reset_action()
		player.reset_physics_interpolation()
	ball.global_position = Vector3(0, FootballBall.RADIUS + 0.02, 0)
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.control_block_remaining = 0
	ball.control_candidate_id = ""
	# The new kickoff belongs to its receiving side, not the previous scorer.
	# Clear individual touch continuity so it cannot survive a dead-ball restart.
	ball.last_touch_team = kickoff_team
	ball.last_touch_id = ""
	ball.reset_physics_interpolation()
	kickoff_remaining = 1.5
	charging = false
	charge = 0.0
	delivery_kind = ""
	delivery_charge = 0

func _select(index: int) -> void:
	delivery_kind = ""
	delivery_charge = 0
	if controlled != null:
		controlled.jockey = false
		controlled.shot_preparation = 0
	selected_index = clampi(index, 0, 2)
	controlled = players[selected_index]
	for player in players:
		player.selected = player == controlled
	charging = false
	charge = 0.0

func _switch_player(direction: Vector3 = Vector3.ZERO) -> void:
	var best := -INF
	var winner := selected_index
	var carrier: FootballPlayer = null
	var nearest := INF
	for opponent in players:
		if opponent.team != controlled.team and opponent.upright_ready() and opponent.reach_ball(ball, 1.4):
			var distance := opponent.global_position.distance_to(ball.global_position)
			if distance < nearest:
				nearest = distance
				carrier = opponent
	var own_goal := Vector3(-18 if controlled.team == 0 else 18, 0, 0)
	for i in range(3):
		if i == selected_index or not players[i].upright_ready():
			continue
		var value := -players[i].global_position.distance_to(ball.global_position)
		if carrier != null:
			var segment := own_goal - carrier.global_position
			segment.y = 0
			var offset := players[i].global_position - carrier.global_position
			offset.y = 0
			var along := offset.dot(segment) / maxf(segment.length_squared(), 0.001)
			var lateral := (offset - segment * clampf(along, 0, 1)).length()
			value = (20.0 if along > 0 and along < 1 else 0.0) - lateral * 4 - offset.length() * 0.25
		if direction.length_squared() > 0.1:
			var offset := players[i].global_position - controlled.global_position
			offset.y = 0
			value = offset.normalized().dot(direction) * 100 - offset.length()
		if value > best:
			best = value
			winner = i
	_select(winner)
	_record("switch", controlled, {"source": "controller"})

func _physics_process(delta: float) -> void:
	if phase != "playing":
		return
	kickoff_remaining = maxf(0, kickoff_remaining - delta)
	if not goal_flow.active:
		remaining = maxf(0, remaining - delta)
	if decision_driver != null:
		decision_driver.decide(delta)
	var movement: Vector2 = Input.get_vector("left", "right", "up", "down") if decision_driver == null else decision_driver.movement
	controlled.intent = Vector3(movement.x, 0, movement.y)
	controlled.sprint = Input.is_action_pressed("sprint") if decision_driver == null else decision_driver.sprinting
	controlled.jockey = Input.is_action_pressed("jockey") if decision_driver == null else false
	if controlled.jockey and not _attacking_contact():
		var facing := ball.global_position - controlled.global_position
		facing.y = 0
		controlled.aim = facing.normalized()
	if movement.length_squared() > 0.04:
		if not controlled.jockey or _attacking_contact():
			controlled.aim = controlled.intent.normalized()
	if decision_driver == null and Input.is_action_just_pressed("switch") and not _attacking_contact():
		_switch_player()
	var right := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)) if decision_driver == null else Vector2.ZERO
	if right.length() > 0.6 and not right_stick_latched:
		_switch_player(Vector3(right.x, 0, right.y).normalized())
	right_stick_latched = right.length() > 0.4
	var controller_actions: Dictionary = {
		"pass": Input.is_action_just_pressed("pass"), "through": Input.is_action_just_pressed("through"),
		"primary": Input.is_action_just_pressed("shoot"), "primary_release": Input.is_action_just_released("shoot"),
		"primary_held": Input.is_action_pressed("shoot"),
		"pass_held": Input.is_action_pressed("pass"), "pass_release": Input.is_action_just_released("pass"),
		"through_held": Input.is_action_pressed("through"), "through_release": Input.is_action_just_released("through"),
		"square_held": Input.is_action_pressed("lob"), "square_release": Input.is_action_just_released("lob"),
		"square": Input.is_action_just_pressed("lob"), "hop": Input.is_action_just_pressed("hop"),
		"l1": Input.is_action_pressed("switch"), "r1": Input.is_action_pressed("modifier_r1"), "l2": controlled.jockey,
		"run": Input.is_action_just_pressed("switch"), "support": Input.is_action_just_pressed("modifier_r1")
	}
	if decision_driver != null:
		controller_actions = decision_driver.actions
	_controller_actions(delta, controller_actions)
	if decision_driver == null and Input.is_action_just_pressed("tackle"):
		if controlled.tackle(ball):
			_record("tackle", controlled, {"source": "controller"})
	if decision_driver == null and Input.is_action_just_pressed("slide"):
		if controlled.slide(ball):
			_record("slide", controlled, {"source": "controller"})
	if decision_driver == null and Input.is_action_just_pressed("shoulder"):
		if controlled.shoulder(ball):
			_record("shoulder", controlled, {"source": "controller"})
	if goal_flow.active:
		goal_flow.tick(delta)
		return
	for player in players:
		if player != controlled:
			var action := FootballAI.decide(player, players, ball, delta)
			if action != "":
				_record(action + "_attempt" if action in ["pass", "shot"] else action, player, {"source": "ai"})
	_control_ball()
	controlled.try_buffered_kick(ball)
	_check_goal()
	# This is a visible dead-ball restart for an escape over the low boards.
	if absf(ball.global_position.z) > 13.2 or absf(ball.global_position.x) > 21 or ball.global_position.y < -1:
		_record("out_of_court", null)
		reset_positions(1 if ball.last_touch_team == 0 else 0)
		hud.flash("BALL OUT — CENTRE RESTART")
	if remaining <= 0:
		_finish_match()

func _attacking_contact() -> bool:
	return controlled.reach_ball(ball) and ball.last_touch_team in [-1, controlled.team]

func _controller_actions(delta: float, pressed: Dictionary) -> void:
	if controlled.action_kind == "grab":
		controlled.grab_held = pressed.get("primary_held", false) and pressed.get("l2", false)
	var shot_direction := controlled.intent.normalized() if controlled.intent.length() > 0.2 else controlled.aim
	for button in ["pass", "through", "square"]:
		if pressed.get(button, false) and (_attacking_contact() or controlled.incoming_pass_remaining > 0) and not charging:
			delivery_kind = button
			delivery_charge = 0
			delivery_high = pressed.get("l1", false)
	if delivery_kind != "":
		delivery_charge = minf(1, delivery_charge + delta / 0.65)
		if pressed.get(delivery_kind + "_release", false):
			_release_delivery(shot_direction, delivery_kind, delivery_charge, delivery_high)
			delivery_kind = ""
			delivery_charge = 0
	if _attacking_contact() and (pressed.get("run", false) or pressed.get("support", false)) and not pressed.get("primary", false) and not charging:
		var candidate: FootballPlayer = null
		var closest := INF
		for teammate in players:
			if teammate != controlled and teammate.team == controlled.team and teammate.global_position.distance_to(controlled.global_position) < closest:
				candidate = teammate
				closest = teammate.global_position.distance_to(controlled.global_position)
		if candidate != null:
			if pressed.get("run", false):
				candidate.run_requested = 2.5
			else:
				candidate.support_requested = 2.5
	if pressed.get("hop", false):
		controlled.hop()
	if controlled.ragdoll != null or controlled.hop_active:
		charging = false
		delivery_kind = ""
		return
	# Context is selected at button-down. Losing contact during a wind-up can miss.
	if pressed.get("primary", false):
		if _attacking_contact() or controlled.incoming_pass_remaining > 0:
			charging = true
			charge = 0
		else:
			var opponent := _close_opponent(controlled)
			if opponent != null:
				var toward := opponent.global_position - controlled.global_position
				toward.y = 0
				controlled.aim = toward.normalized()
			if pressed.get("l2", false):
				controlled.grab(ball)
			elif opponent != null:
				controlled.push(ball)
			else:
				controlled.tackle(ball)
	if charging:
		charge = minf(1, charge + delta / 0.8)
		controlled.shot_preparation = charge
		if pressed.get("primary_release", false):
			var kind := "power" if pressed.get("l1", false) and pressed.get("r1", false) else "chip" if pressed.get("l1", false) else "finesse" if pressed.get("r1", false) else "outside" if pressed.get("l2", false) else "shot"
			if kind == "chip":
				controlled.loft(ball, shot_direction, lerpf(5, 15, charge), false, kind)
			else:
				var strength := lerpf(22, 34, charge) if kind == "power" else lerpf(13, 23, charge) if kind in ["finesse", "outside"] else lerpf(14, 27, charge)
				var lift := lerpf(0.35, 1.4, charge) if kind == "power" else lerpf(0.35, 1.8, charge)
				if not controlled.kick(ball, shot_direction, strength, lift, kind) and controlled.incoming_pass_remaining > 0:
					controlled.buffer_kick(kind, shot_direction, strength, lift)
			charging = false
			charge = 0
			controlled.shot_preparation = 0
	else:
		controlled.shot_preparation = 0
	if pressed.get("square", false):
		if not _attacking_contact() and controlled.incoming_pass_remaining <= 0:
			controlled.slide(ball)

func _release_delivery(direction: Vector3, button: String, power: float, high: bool) -> void:
	var receiver := _pass_receiver(controlled, direction)
	var strength := lerpf(8, 21, power) if button == "through" else lerpf(6.5, 19, power)
	var distance := lerpf(5, 24, power)
	if receiver != null:
		var flight := clampf(receiver.global_position.distance_to(controlled.global_position) / strength, 0.15, 1.6)
		var lead := receiver.global_position + receiver.linear_velocity * flight
		if button == "through":
			lead += Vector3(1 if controlled.team == 0 else -1, 0, 0) * lerpf(1.2, 3.8, power)
		var offset := lead - controlled.global_position
		offset.y = 0
		direction = offset.normalized()
	if button == "square" or (button == "through" and high):
		var apex: float = clampf(2.4 + distance * 0.055, 2.8, 4.0) + (1.3 if high else 0)
		var launch := FootballBall.loft_launch(distance, apex)
		if not controlled.kick(ball, direction, launch.x, launch.y, "lob") and controlled.incoming_pass_remaining > 0:
			controlled.buffer_kick("lob", direction, launch.x, launch.y)
	else:
		var kind := "through" if button == "through" else "pass"
		if not controlled.kick(ball, direction, strength, 0.08, kind) and controlled.incoming_pass_remaining > 0:
			controlled.buffer_kick(kind, direction, strength, 0.08)

func _close_opponent(player: FootballPlayer) -> FootballPlayer:
	var closest := 1.05
	var winner: FootballPlayer = null
	for opponent in players:
		if opponent.team == player.team or not opponent.upright_ready():
			continue
		var distance := opponent.global_position.distance_to(player.global_position)
		if distance < closest:
			closest = distance
			winner = opponent
	return winner

func _pass_distance(direction: Vector3) -> float:
	var distance := 12.0
	var best := 0.55
	for teammate in players:
		if teammate.team != controlled.team or teammate == controlled:
			continue
		var offset := teammate.global_position - controlled.global_position
		offset.y = 0
		var alignment := offset.normalized().dot(direction)
		if alignment > best:
			best = alignment
			distance = offset.length()
	return clampf(distance, 6, 20)

func _on_strike_contact(kind: String, player: FootballPlayer) -> void:
	# Missed swings emit no contact and therefore create no receiving assignment.
	for teammate in players:
		teammate.incoming_pass_remaining = 0
	if kind in ["pass", "through", "lob"]:
		var receiver := _pass_receiver(player, player.action_direction)
		if receiver != null:
			receiver.incoming_pass_from = player.player_id
			receiver.incoming_pass_remaining = 3.5
			receiver.reaction_timer = 0
	_record(kind, player, {"source": "controller" if player == controlled else "ai", "contact_distance": player.last_kick_contact_distance})
	sound.play_contact(kind, clampf(player.kick_strength / 30, 0.15, 1))
	if player == controlled and not acceptance and not Input.get_connected_joypads().is_empty():
		Input.start_joy_vibration(0, vibration_intensity * 0.2, vibration_intensity * clampf(player.kick_strength / 32, 0.15, 1), 0.09)

func _pass_receiver(passer: FootballPlayer, direction: Vector3) -> FootballPlayer:
	var receiver: FootballPlayer = null
	var best := -INF
	for teammate in players:
		if teammate == passer or teammate.team != passer.team or not teammate.upright_ready():
			continue
		var offset := teammate.global_position - ball.global_position
		offset.y = 0
		var along := offset.dot(direction)
		var lateral := (offset - direction * along).length()
		if along < 0.4 or lateral > maxf(2.5, along * 0.65):
			continue
		var score := -lateral * 3 - along * 0.08
		if score > best:
			best = score
			receiver = teammate
	return receiver

func _on_dribble_contact(player: FootballPlayer) -> void:
	_record("touch", player)
	sound.play_contact("touch", 0.2)

func _on_physical_event(kind: String, detail: Dictionary, player: FootballPlayer) -> void:
	_record(kind, player, detail)

func _control_ball() -> FootballPlayer:
	# One nearest eligible foot per tick, with a small continuity preference.
	# This never blocks tackles or body collisions and applies equally to both teams.
	var candidate: FootballPlayer = null
	var best_distance := INF
	for player in players:
		if not player.can_control(ball):
			continue
		var offset := ball.global_position - player.global_position
		offset.y = 0
		var distance := offset.length()
		if ball.last_touch_id == player.player_id:
			distance -= 0.12
		if distance < best_distance:
			best_distance = distance
			candidate = player
	ball.control_candidate_id = candidate.player_id if candidate != null else ""
	if candidate != null:
		candidate.shield_direction = Vector3.ZERO
		if candidate.jockey:
			var nearest_opponent := INF
			for opponent in players:
				if opponent.team == candidate.team:
					continue
				var away := candidate.global_position - opponent.global_position
				away.y = 0
				if away.length() < nearest_opponent:
					nearest_opponent = away.length()
					candidate.shield_direction = away.normalized()
		if candidate.dribble(ball):
			_record("touch", candidate)
	return candidate

func _check_goal() -> void:
	if goal_flow.active:
		return
	# Entire sphere must cross the line, within the mouth and under the bar.
	if absf(ball.global_position.x) > 18.1 + FootballBall.RADIUS and absf(ball.global_position.x) < 20.3 and absf(ball.global_position.z) < 2.21 - FootballBall.RADIUS and ball.global_position.y < 2.31 - FootballBall.RADIUS:
		var scoring := 0 if ball.global_position.x > 0 else 1
		scores[scoring] += 1
		_record("goal", null, {"team": scoring, "ball": _vec(ball.global_position)})
		sound.play_event("goal")
		hud.flash("%s GOAL!" % ("HOME" if scoring == 0 else "AWAY"), 2.0)
		goal_flow.begin(self, scoring)

func _finish_match() -> void:
	phase = "finished"
	match_count += 1
	for player in players:
		player.intent = Vector3.ZERO
		player.sprint = false
	var report := squad.finish(players)
	hud.show_overlay("FULL TIME  /  %d : %d" % [scores[0], scores[1]], "Your squad is growing through play.\n\n" + report, "Cross / Enter  REMATCH     •     Q  EXIT")
	sound.play_event("whistle")
	_record("full_time", null, {"score": scores.duplicate(), "save_error": squad.last_error})
	match_finished.emit()

func rematch() -> void:
	goal_flow.active = false
	for player in players:
		player.emotion = ""
	remaining = DURATION
	scores = [0, 0]
	phase = "playing"
	hud.overlay.hide()
	for i in range(3):
		squad.apply_to(players[i], i)
	for player in players:
		player.energy = 1.0
		player.active_seconds = 0
		player.match_touches = 0
	reset_positions(0)
	_select(0)
	_record("rematch", null)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo():
		if phase == "playing":
			delivery_kind = ""
			charging = false
			charge = 0
			phase = "paused"
			pause_states.clear()
			for player in players:
				_pause_node(player)
				if player.ragdoll != null:
					_pause_node(player.ragdoll)
					for body in player.ragdoll.bodies:
						_pause_node(body)
			ball.freeze = true
			hud.show_overlay("HALF A BREATH", "Left stick: move + aim. Hold/release Cross: pass. Triangle: through pass.\nCircle: hold/release shot, or tackle/push in defence. L2 + Circle: hold grab.\nHold/release Square: lob in attack; press for a slide in defence.\nR3: timed hop. R1 + Circle: finesse. R2: sprint. L2: shield / jockey. L1 / right stick: switch.\nKeyboard: Space pass / J shot / U lob / I through.\nK tackle / L slide / H shoulder / Ctrl jockey / E hop. Blue attacks right.", "Triangle / I: vibration intensity   •   Options / Esc RESUME   •   Q EXIT")
		elif phase == "paused":
			phase = "playing"
			for saved in pause_states:
				var node: Node = saved.node
				if is_instance_valid(node):
					node.set_physics_process(saved.physics)
					if node is RigidBody3D:
						node.freeze = saved.freeze
			pause_states.clear()
			ball.freeze = false
			hud.overlay.hide()
	elif phase == "finished" and event.is_action_pressed("confirm"):
		rematch()
	elif phase == "paused" and event.is_action_pressed("through") and not event.is_echo():
		vibration_intensity = 0 if vibration_intensity >= 0.9 else vibration_intensity + 0.3
		hud.overlay_hint.text = "Triangle / I: vibration %d%%   •   Options / Esc RESUME   •   Q EXIT" % int(vibration_intensity * 100)
	elif phase != "playing" and event.is_action_pressed("quit"):
		get_tree().quit()

func _pause_node(node: Node) -> void:
	pause_states.append({"node": node, "physics": node.is_physics_processing(), "freeze": node.freeze if node is RigidBody3D else false})
	node.set_physics_process(false)
	if node is RigidBody3D:
		node.freeze = true

func _process(delta: float) -> void:
	if controlled == null:
		return
	var focus := ball.get_global_transform_interpolated().origin * 0.3
	focus.x = clampf(focus.x, -2.5, 2.5)
	focus.y = 0
	focus.z = clampf(focus.z, -1.6, 1.6)
	camera_focus = camera_focus.lerp(focus, 1.0 - exp(-delta * 3.0))
	camera.position = camera_focus + Vector3(0, 34, 29)
	camera.look_at(camera_focus)
	var player_pos := controlled.get_global_transform_interpolated().origin
	aim_line.position = player_pos + controlled.aim * 1.5 + Vector3(0, 0.05, 0)
	aim_line.rotation.y = atan2(controlled.aim.x, controlled.aim.z)
	aim_line.visible = phase == "playing"
	hud.update_match(scores, remaining, controlled, maxf(charge, delivery_charge))
	var devices := Input.get_connected_joypads()
	if goal_flow.active and goal_flow.state != "celebrating":
		var target: Vector3 = goal_flow.targets[controlled.player_id]
		var direction := target - controlled.global_position
		direction.y = 0
		aim_line.position = controlled.global_position + direction.normalized() * 1.5 + Vector3.UP * .05
		aim_line.rotation.y = atan2(direction.x, direction.z)
		hud.status.text = "WALK TO YOUR KICKOFF POSITION  /  %.1f m" % direction.length()
	else:
		hud.status.text = "DECISION PLAYTEST / HARDWARE INPUT DISABLED" if decision_driver != null else ("CONTROLLER CONNECTED" if not devices.is_empty() else "KEYBOARD READY  /  CONNECT A CONTROLLER ANYTIME")

func _record(kind: String, player: FootballPlayer, extra: Dictionary = {}) -> void:
	var entry := {"time": snappedf(DURATION - remaining, 0.01), "kind": kind, "player": player.player_id if player != null else "", "team": player.team if player != null else -1}
	entry.merge(extra, true)
	action_log.append(entry)

func _vec(value: Vector3) -> Array:
	return [snappedf(value.x, 0.001), snappedf(value.y, 0.001), snappedf(value.z, 0.001)]
