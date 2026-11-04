extends Node3D

signal match_finished

const DURATION := 180.0
const SHOT_BUFFER_SECONDS := 0.18
const PASS_CALL_SECONDS := 1.8
const TEAM_PRESS_RANGE := 12.0
const HALFTIME_SECONDS := 3.0
const GOAL_CELEBRATION_SECONDS := 1.6
const THROW_WINDUP := 0.58
const THROW_MIN_INWARD := 0.32
const ELEVEN_ANCHORS: Array[Vector2] = [
	Vector2(6, 0), Vector2(11, -22), Vector2(11, 22),
	Vector2(20, -12), Vector2(20, 12), Vector2(25, 0),
	Vector2(34, -23), Vector2(37, -8), Vector2(37, 8), Vector2(34, 23),
]
const ELEVEN_FORMATIONS := [
	ELEVEN_ANCHORS,
	[
		Vector2(8, -7), Vector2(8, 7),
		Vector2(22, -23), Vector2(22, -8), Vector2(22, 8), Vector2(22, 23),
		Vector2(34, -23), Vector2(37, -8), Vector2(37, 8), Vector2(34, 23),
	],
	[
		Vector2(7, 0), Vector2(16, -22), Vector2(16, 0), Vector2(16, 22),
		Vector2(26, -8), Vector2(26, 8),
		Vector2(34, -23), Vector2(37, -8), Vector2(37, 8), Vector2(34, 23),
	],
]
@export var eleven_a_side := false
var restart: Dictionary = {}
var throw_entry_side := 0.0
var throw_entry_time := 0.0
var offside_team := -1
var offside_candidates: Dictionary = {}
var pending_indirect_player: FootballPlayer
var pending_indirect_reason := ""
var indirect_spot := Vector3.ZERO
var indirect_taker: FootballPlayer
var players: Array[FootballPlayer] = []
var home_outfield: Array[FootballPlayer] = []
var away_outfield: Array[FootballPlayer] = []
var outfield_teams: Array = [home_outfield, away_outfield]
var keepers: Array[FootballPlayer] = []
var reception := FootballReception.new()
var ball: FootballBall
var referee: ElevenReferee
var camera: Camera3D
var hud: FootballHUD
var sound: FootballSound
var squad := FootballSquad.new()
var controlled: FootballPlayer
var called_runner: FootballPlayer
var pass_call_remaining := 0.0
var pressure_teammate: FootballPlayer
var selected_index: int = 0
var scores: Array[int] = [0, 0]
var remaining: float = DURATION
var match_duration: float = DURATION
var opponent_difficulty := 1
var home_formation := 0
var ends_swapped := false
var halftime_remaining := 0.0
var opening_kickoff_team := 0
var celebration_elapsed := 0.0
var celebration_team := -1
var celebration_scorer: FootballPlayer
var celebration_focus := Vector3.ZERO
var celebration_zoom := 12.5
var match_menu: ElevenMatchMenu
var kickoff_remaining: float = 1.5
var kickoff_taker: FootballPlayer
var kickoff_receiver: FootballPlayer
var kickoff_strike_remaining := 0.0
var phase: String = "playing"
var charge: float = 0.0
var charging: bool = false
var shot_buffer_remaining := 0.0
var shot_buffer_direction := Vector3.ZERO
var shot_buffer_charge := 0.0
var shot_style := "normal"
var right_stick_latched: bool = false
var camera_focus := Vector3.ZERO
var camera_offset := Vector3(0.0, 34.0, 29.0)
var aim_line: MeshInstance3D
var action_log: Array[Dictionary] = []
var match_count: int = 0
var acceptance: bool = false
var pause_requested: bool = false
var decision_driver: Node
var pause_states: Array[Dictionary] = []

func _ready() -> void:
	var visual_acceptance := "--visual-acceptance" in OS.get_cmdline_user_args()
	var handling_acceptance := "--handling-acceptance" in OS.get_cmdline_user_args()
	var decision_acceptance := "--decision-acceptance" in OS.get_cmdline_user_args()
	var impact_acceptance := "--impact-acceptance" in OS.get_cmdline_user_args()
	var eleven_acceptance := eleven_a_side and "--eleven-acceptance" in OS.get_cmdline_user_args()
	acceptance = impact_acceptance or decision_acceptance or handling_acceptance or visual_acceptance or "--acceptance" in OS.get_cmdline_user_args() or "--dribble-acceptance" in OS.get_cmdline_user_args()
	acceptance = acceptance or eleven_acceptance
	_install_input()
	squad.load_squad(acceptance, eleven_a_side)
	if eleven_acceptance:
		squad.save_path = "user://eleven_acceptance_squad.json"
		set_process_unhandled_input(false)
	if eleven_a_side:
		_build_lighting()
		ElevenPitch.build(self)
	else:
		_build_pitch()
	_build_players()
	ball = FootballBall.new()
	ball.name = "Ball"
	if eleven_a_side:
		ball.set_collision_mask_value(ElevenPitch.NET_COLLISION_LAYER, true)
		ball.played.connect(_on_ball_played)
	add_child(ball)
	if eleven_a_side:
		referee = ElevenReferee.new()
		referee.name = "Referee"
		referee.position = Vector3(-6.0, 0.0, 7.0)
		add_child(referee)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 48 if eleven_a_side else 43
	camera.position = camera_offset
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	hud = FootballHUD.new()
	hud.eleven_a_side = eleven_a_side
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
		var session: Node = load("res://tests/impact_acceptance.gd" if impact_acceptance else "res://tests/handling_acceptance.gd" if handling_acceptance else "res://tests/visual_acceptance.gd").new()
		add_child(session)
		session.begin(self)
	elif decision_acceptance:
		set_process_unhandled_input(false)
		decision_driver = load("res://tests/decision_acceptance.gd").new()
		add_child(decision_driver)
		decision_driver.begin(self)
	elif acceptance and not eleven_acceptance:
		var session_path := "res://tests/dribble_acceptance.gd" if "--dribble-acceptance" in OS.get_cmdline_user_args() else "res://tests/acceptance.gd"
		var session: Node = load(session_path).new()
		add_child(session)
		session.begin(self)
	if eleven_a_side and (not acceptance or (eleven_acceptance and "--menu-acceptance" in OS.get_cmdline_user_args())):
		_show_match_setup()

func _show_match_setup() -> void:
	if is_instance_valid(match_menu):
		return
	phase = "setup"
	ball.freeze = true
	for player: FootballPlayer in players:
		player.freeze = true
	match_menu = ElevenMatchMenu.new()
	hud.add_child(match_menu)
	match_menu.length_choice.select(ElevenMatchMenu.MATCH_SECONDS.find(match_duration))
	match_menu.difficulty_choice.select(opponent_difficulty)
	match_menu.select_formation(home_formation)
	match_menu.kickoff_requested.connect(_start_configured_match)

func _start_configured_match(seconds: float, difficulty: int, formation: int) -> void:
	match_duration = seconds if seconds in [180.0, 360.0, 600.0] else DURATION
	opponent_difficulty = clampi(difficulty, 0, 2)
	home_formation = clampi(formation, 0, ELEVEN_FORMATIONS.size() - 1)
	_set_ends_swapped(false)
	var anchors: Array = ELEVEN_FORMATIONS[home_formation]
	for player in home_outfield:
		var anchor: Vector2 = anchors[player.eleven_slot]
		player.eleven_home = Vector3(-anchor.x, 0.06, anchor.y)
	match_menu.hide()
	match_menu.queue_free()
	match_menu = null
	for player: FootballPlayer in players:
		player.freeze = false
	rematch()
	_record("match_configured", null, {"duration": match_duration, "difficulty": opponent_difficulty, "formation": home_formation})

func _install_input() -> void:
	for action in ["left", "right", "up", "down", "pass", "shoot", "lob", "through", "jockey", "tackle", "slide", "shoulder", "hop", "sprint", "switch", "pause", "confirm", "quit"]:
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
	# Godot's standardized south/east/west/north slots also cover PlayStation pads.
	var buttons := {"pass": JOY_BUTTON_A, "shoot": JOY_BUTTON_B, "lob": JOY_BUTTON_X, "through": JOY_BUTTON_Y, "switch": JOY_BUTTON_LEFT_SHOULDER, "pause": JOY_BUTTON_START, "confirm": JOY_BUTTON_A, "quit": JOY_BUTTON_BACK}
	for action in buttons:
		var button := InputEventJoypadButton.new()
		button.button_index = buttons[action]
		InputMap.action_add_event(action, button)
	var hop_button := InputEventJoypadButton.new()
	hop_button.button_index = JOY_BUTTON_RIGHT_SHOULDER
	InputMap.action_add_event("hop", hop_button)
	if eleven_a_side:
		if not InputMap.has_action("match_setup"):
			InputMap.add_action("match_setup")
		var setup_key := InputEventKey.new()
		setup_key.physical_keycode = KEY_M
		InputMap.action_add_event("match_setup", setup_key)
		var setup_button := InputEventJoypadButton.new()
		setup_button.button_index = JOY_BUTTON_Y
		InputMap.action_add_event("match_setup", setup_button)
		for binding: Array in [["finesse_modifier", KEY_R, JOY_BUTTON_RIGHT_SHOULDER], ["chip_modifier", KEY_F, JOY_BUTTON_LEFT_SHOULDER], ["send_run", KEY_G, JOY_BUTTON_DPAD_UP], ["teammate_press", KEY_T, JOY_BUTTON_DPAD_DOWN]]:
			var name_key: String = binding[0]
			if not InputMap.has_action(name_key):
				InputMap.add_action(name_key)
			var modifier_key := InputEventKey.new()
			modifier_key.physical_keycode = binding[1]
			InputMap.action_add_event(name_key, modifier_key)
			var modifier_button := InputEventJoypadButton.new()
			modifier_button.button_index = binding[2]
			InputMap.action_add_event(name_key, modifier_button)
	for mapping in [["left", JOY_AXIS_LEFT_X, -1.0], ["right", JOY_AXIS_LEFT_X, 1.0], ["up", JOY_AXIS_LEFT_Y, -1.0], ["down", JOY_AXIS_LEFT_Y, 1.0], ["sprint", JOY_AXIS_TRIGGER_RIGHT, 1.0], ["jockey", JOY_AXIS_TRIGGER_LEFT, 1.0]]:
		var axis := InputEventJoypadMotion.new()
		axis.axis = mapping[1]
		axis.axis_value = mapping[2]
		InputMap.action_add_event(mapping[0], axis)

func _build_lighting() -> void:
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

func _build_pitch() -> void:
	_build_lighting()
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
		for index in range(_outfield_count()):
			var player := FootballPlayer.new()
			player.team = team
			squad.apply_to(player, index)
			if eleven_a_side:
				player.eleven_slot = index
				var anchor := ELEVEN_ANCHORS[index]
				player.eleven_home = Vector3(anchor.x * (-1 if team == 0 else 1), 0.06, anchor.y)
			if team == 1:
				# Identical base abilities; opponents do not inherit your career XP.
				var entry: Dictionary = squad.entries[index]
				player.player_id = "opponent_" + str(entry["id"])
				player.player_name = str(entry.get("opponent", player.player_name)) if eleven_a_side else ["FINN", "RAE", "MAX"][index]
				player.touch_skill = float(entry["touch"])
				player.stamina_trait = float(entry["stamina"])
				player.mass = float(entry["mass"])
			player.name = player.player_id
			add_child(player)
			player.strike_contact.connect(_on_strike_contact.bind(player))
			player.dribble_contact.connect(_on_dribble_contact.bind(player))
			player.physical_event.connect(_on_physical_event.bind(player))
			players.append(player)
			if team == 0:
				home_outfield.append(player)
			else:
				away_outfield.append(player)
	for team in range(2):
		var keeper := FootballGoalkeeper.new()
		keeper.team = team
		keeper.full_pitch = eleven_a_side
		squad.apply_to(keeper, _outfield_count())
		if eleven_a_side:
			keeper.eleven_slot = _outfield_count()
		if team == 1:
			keeper.player_id = "opponent_keeper"
			keeper.player_name = "LEE"
			var entry: Dictionary = squad.entries[_outfield_count()]
			keeper.touch_skill = float(entry["touch"])
			keeper.stamina_trait = float(entry["stamina"])
			keeper.mass = float(entry["mass"])
			keeper.balance_skill = float(entry.get("balance",1.0))
			keeper.agility_skill = float(entry.get("agility",1.0))
		keeper.name = keeper.player_id
		add_child(keeper)
		keeper.strike_contact.connect(_on_strike_contact.bind(keeper))
		keeper.dribble_contact.connect(_on_dribble_contact.bind(keeper))
		keeper.physical_event.connect(_on_physical_event.bind(keeper))
		players.append(keeper)
		keepers.append(keeper)

func _outfield_count() -> int:
	return ELEVEN_ANCHORS.size() if eleven_a_side else 3

func reset_positions(kickoff_team: int) -> void:
	_clear_offside()
	indirect_taker = null
	if referee != null:
		referee.resume_play()
	shot_buffer_remaining = 0.0
	_set_pressure_teammate(null)
	pass_call_remaining = 0.0
	throw_entry_time = 0.0
	kickoff_taker = null
	kickoff_receiver = null
	if not ends_swapped and is_equal_approx(remaining, match_duration):
		opening_kickoff_team = kickoff_team
	restart.clear()
	ball.freeze = false
	for keeper: FootballPlayer in keepers:
		(keeper as FootballGoalkeeper).drop_ball("kickoff")
	reception.reset(ball)
	for i in range(players.size()):
		var player := players[i]
		var field: Array[FootballPlayer] = home_outfield if player.team == 0 else away_outfield
		var index: int = field.find(player)
		var side := -player.attack_sign()
		var pos: Vector3
		if eleven_a_side:
			pos = Vector3(side * 48.5, 0.06, 0) if player.is_goalkeeper else player.eleven_home
		else:
			pos = Vector3(side*16.8,0.06,0) if player.is_goalkeeper else Vector3(side * [3.0, 7.0, 11.0][index], 0.06, [-1.0, 5.0, -4.0][index])
		if not player.is_goalkeeper and player.team == kickoff_team and index == 0:
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
	ball.clear_finesse()
	ball.control_block_remaining = 0
	ball.control_candidate_id = ""
	ball.passer_block_id = ""
	ball.passer_block_remaining = 0.0
	ball.grip_holder_id = ""
	# The new kickoff belongs to its receiving side, not the previous scorer.
	# Clear individual touch continuity so it cannot survive a dead-ball restart.
	ball.last_touch_team = kickoff_team
	ball.last_touch_id = ""
	ball.reset_physics_interpolation()
	kickoff_remaining = 1.5
	charging = false
	charge = 0.0
	if eleven_a_side:
		if kickoff_team == 0:
			_select(0)
		else:
			_prepare_away_kickoff()
		_record("kickoff", null, {"team": kickoff_team})

func _prepare_away_kickoff() -> void:
	kickoff_taker = away_outfield[0]
	kickoff_receiver = away_outfield[5]
	var own_side := -kickoff_taker.attack_sign()
	kickoff_receiver.global_position = Vector3(7.0 * own_side, 0.06, 2.6 * own_side)
	kickoff_receiver.reset_physics_interpolation()
	var direction := FootballReception.flat(kickoff_receiver.global_position).normalized()
	kickoff_taker.global_position = Vector3.UP * 0.06 - direction * 0.55
	kickoff_taker.aim = direction
	kickoff_taker.reset_physics_interpolation()
	kickoff_strike_remaining = 2.2

func _tick_away_kickoff(delta: float) -> void:
	kickoff_strike_remaining -= delta
	if kickoff_strike_remaining <= 0.0:
		_record("kickoff_untaken", kickoff_taker)
		kickoff_taker.intent = Vector3.ZERO
		kickoff_taker = null
		kickoff_receiver = null
		return
	if kickoff_taker.action_kind != "" or kickoff_taker.kick_cooldown > 0.0:
		return
	var direction := FootballReception.flat(kickoff_receiver.global_position - ball.global_position).normalized()
	kickoff_taker.aim = direction
	var stance := FootballReception.flat(ball.global_position - kickoff_taker.global_position) - direction * 0.55
	if stance.length() > 0.12:
		kickoff_taker.intent = stance.limit_length(0.5)
		return
	kickoff_taker.intent = Vector3.ZERO
	if kickoff_taker.kick(ball, direction, 8.5, 0.06, "pass"):
		kickoff_taker.pending_receiver_id = kickoff_receiver.player_id

func _select(index: int) -> void:
	shot_buffer_remaining = 0.0
	pass_call_remaining = 0.0
	if controlled != null:
		controlled.jockey = false
	selected_index = clampi(index, 0, home_outfield.size()-1)
	controlled = home_outfield[selected_index]
	for player in players:
		player.selected = player == controlled
	charging = false
	charge = 0.0

func _switch_player(direction: Vector3 = Vector3.ZERO) -> void:
	var best := -INF
	var winner := selected_index
	var directional := direction.length_squared() > 0.1
	var intercept := ball.global_position
	if eleven_a_side and not directional:
		intercept += FootballReception.flat(ball.linear_velocity).limit_length(12.0) * 0.24
	for i in range(home_outfield.size()):
		if i == selected_index:
			continue
		var candidate := home_outfield[i]
		if eleven_a_side and candidate.ragdoll != null:
			continue
		var value := -candidate.global_position.distance_to(intercept)
		if directional:
			var offset := FootballReception.flat(candidate.global_position - controlled.global_position)
			var alignment := offset.normalized().dot(direction)
			if eleven_a_side and alignment < 0.45:
				continue
			value = alignment * 100 - offset.length()
		elif eleven_a_side:
			value /= maxf(candidate.pace, 1.0)
			if ball.pass_active and ball.pass_receiver_id == candidate.player_id:
				value += 8.0
		if value > best:
			best = value
			winner = i
	if eleven_a_side and winner == selected_index:
		return
	_select(winner)
	_record("switch", controlled, {"source": "controller"})

func _set_ends_swapped(swapped: bool) -> void:
	if ends_swapped == swapped:
		return
	ends_swapped = swapped
	for player in players:
		player.ends_swapped = swapped
		player.eleven_home *= Vector3(-1.0, 1.0, -1.0)

func _begin_halftime() -> void:
	phase = "halftime"
	halftime_remaining = HALFTIME_SECONDS
	_set_pressure_teammate(null)
	charging = false
	charge = 0.0
	_pause_players()
	ball.freeze = true
	sound.play_event("whistle")
	hud.show_overlay("HALF TIME  /  %d : %d" % [scores[0], scores[1]], "Teams switch ends. Blue attacks left in the second half.", "SECOND HALF STARTS AUTOMATICALLY")
	_record("half_time", null, {"score": scores.duplicate()})

func _tick_halftime(delta: float) -> void:
	halftime_remaining -= delta
	if halftime_remaining > 0.0:
		return
	_resume_players()
	_set_ends_swapped(true)
	var kickoff_team := 1 - opening_kickoff_team
	reset_positions(kickoff_team)
	phase = "playing"
	hud.overlay.hide()
	hud.flash("SECOND HALF  /  BLUE ATTACKS LEFT", 3.0)
	_record("half_started", null, {"half": 2, "score": scores.duplicate(), "home_attack_sign": controlled.attack_sign(), "kickoff_team": kickoff_team})

func _physics_process(delta: float) -> void:
	if phase == "halftime":
		_tick_halftime(delta)
		return
	if phase == "goal_celebration":
		_tick_goal_celebration(delta)
		return
	if phase != "playing":
		return
	if _award_indirect_restart():
		return
	if not restart.is_empty():
		if referee != null:
			referee.hold_position(delta)
		_tick_restart(delta)
		return
	if referee != null:
		referee.track_ball(ball.global_position, delta)
	if kickoff_remaining > 0:
		kickoff_remaining -= delta
		for player in players:
			player.intent = Vector3.ZERO
		return
	if is_instance_valid(kickoff_taker):
		_tick_away_kickoff(delta)
		return
	remaining = maxf(0, remaining - delta)
	if eleven_a_side and not ends_swapped and remaining <= match_duration * 0.5:
		remaining = match_duration * 0.5
		_begin_halftime()
		return
	pass_call_remaining = maxf(0.0, pass_call_remaining - delta) if ball.last_touch_team == controlled.team else 0.0
	reception.update(self,delta)
	if decision_driver != null:
		decision_driver.decide(delta)
	if decision_driver == null and Input.is_action_just_pressed("switch") and not (Input.is_action_pressed("chip_modifier") and _can_modify_shot()):
		_switch_player()
	var right := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)) if decision_driver == null else Vector2.ZERO
	if right.length() > 0.6 and not right_stick_latched:
		_switch_player(Vector3(right.x, 0, right.y).normalized())
	right_stick_latched = right.length() > 0.4
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
	var controller_actions: Dictionary = {
		"pass": Input.is_action_just_pressed("pass"), "through": Input.is_action_just_pressed("through"),
		"primary": Input.is_action_just_pressed("shoot"), "primary_release": Input.is_action_just_released("shoot"),
		"square": Input.is_action_just_pressed("lob"), "hop": Input.is_action_just_pressed("hop")
	}
	if eleven_a_side and decision_driver == null:
		controller_actions["finesse_modifier"] = Input.is_action_pressed("finesse_modifier")
		controller_actions["chip_modifier"] = Input.is_action_pressed("chip_modifier")
		controller_actions["send_run"] = Input.is_action_just_pressed("send_run")
		controller_actions["teammate_press"] = Input.is_action_pressed("teammate_press")
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
	for player in players:
		if player != controlled:
			var difficulty := opponent_difficulty if player.team == 1 else 1
			var called_receiver := controlled if pass_call_remaining > 0.0 and player.team == controlled.team else null
			var action: String = (player as FootballGoalkeeper).decide_keeper(players,ball,delta) if player.is_goalkeeper else FootballAI.decide(player, players, ball, delta, eleven_a_side, difficulty, called_receiver, pressure_teammate)
			if action != "":
				_record(action + "_attempt" if action in ["pass", "shot"] else action, player, {"source": "ai"})
	_control_ball()
	if _award_indirect_restart():
		return
	_check_goal()
	if phase == "goal_celebration":
		return
	# This is a visible dead-ball restart for an escape over the low boards.
	if eleven_a_side:
		_check_eleven_boundary(delta)
	elif absf(ball.global_position.z) > 13.2 or absf(ball.global_position.x) > 21 or ball.global_position.y < -1:
		_record("out_of_court", null)
		reset_positions(1 if ball.last_touch_team == 0 else 0)
		hud.flash("BALL OUT — CENTRE RESTART")
	if remaining <= 0:
		_finish_match()

func _attacking_contact() -> bool:
	# This selects a nearby strike opportunity, not ownership of the ball.
	# A reachable opponent touch or incoming pass can be hit first-time.
	return ball.grip_holder_id.is_empty() and controlled.predict_strike_reach(ball, 0.22)

func _can_modify_shot() -> bool:
	if not eleven_a_side or not ball.grip_holder_id.is_empty():
		return false
	return charging or controlled.chasing_ball(ball) or (controlled.reach_ball(ball, 1.1) and _attacking_contact())

func _requested_shot_style(pressed: Dictionary) -> String:
	var finesse := bool(pressed.get("finesse_modifier", false))
	var chip := bool(pressed.get("chip_modifier", false))
	if finesse and chip:
		return "power"
	if finesse:
		return "finesse"
	if chip:
		return "chip"
	return "normal"

func _shot_launch(style: String, power: float) -> Vector2:
	match style:
		"finesse":
			return Vector2(lerpf(11.5, 18.5, power), lerpf(1.0, 3.4, power))
		"chip":
			return Vector2(lerpf(8.0, 13.0, power), lerpf(5.5, 8.2, power))
		"power":
			return Vector2(lerpf(17.0, 26.0, power), lerpf(0.8, 2.6, power))
	return Vector2(lerpf(12.0, 23.0, power), lerpf(0.7, 3.2, power))

func _strike_direction() -> Vector3:
	var stick := Vector3(controlled.intent.x, 0, controlled.intent.z)
	return stick.normalized() if stick.length_squared() > 0.0025 else controlled.aim.normalized()

func _intended_receiver(direction: Vector3, preferred: String = "") -> FootballPlayer:
	# The stick still chooses the kick direction. This chooses who should read
	# that delivery, without bending the ball towards an unavailable teammate.
	return FootballReception.choose_receiver(controlled, players, ball.global_position, direction, preferred)

func _send_teammate_run() -> void:
	if ball.last_touch_team != controlled.team or not _can_modify_shot():
		return
	var runner := FootballAI.choose_called_runner(controlled, players, _strike_direction())
	if runner == null:
		return
	if is_instance_valid(called_runner):
		called_runner.called_run_remaining = 0.0
	called_runner = runner
	var origin := runner.global_position
	runner.called_run_target = Vector3(clampf(origin.x + 8.0 * runner.attack_sign(), -48.0, 48.0), origin.y, origin.z)
	runner.called_run_remaining = 1.65
	_record("run_called", runner, {"target": _vec(runner.called_run_target)})
	hud.flash(runner.player_name.to_upper() + " MAKES A RUN", 1.3)

func _request_delivery(kind: String, strength: float, lift: float) -> void:
	var direction := _strike_direction()
	var preferred := ""
	if kind == "through" and is_instance_valid(called_runner) and called_runner.called_run_remaining > 0.0 and ball.last_touch_team == controlled.team:
		preferred = called_runner.player_id
	var receiver := _intended_receiver(direction, preferred)
	# A kick may miss. Reading an intended receiver never rotates the strike
	# towards that player or creates a successful contact.
	if controlled.kick(ball, direction, strength, lift, kind):
		controlled.pending_receiver_id = receiver.player_id if receiver != null else ""
		if not preferred.is_empty() and controlled.pending_receiver_id == preferred:
			_record("run_through_requested", controlled, {"receiver": preferred})

func _available_presser(player: FootballPlayer) -> bool:
	return player != controlled and player.ragdoll == null and not player.hop_active and player.recovery_remaining <= 0.0 and player.energy > 0.15 and FootballReception.flat(player.global_position - ball.global_position).length_squared() < TEAM_PRESS_RANGE * TEAM_PRESS_RANGE

func _set_pressure_teammate(player: FootballPlayer) -> void:
	if pressure_teammate == player:
		return
	for teammate in home_outfield:
		teammate.reaction_timer = 0.0
	if pressure_teammate != null:
		_record("pressure_ended", pressure_teammate)
	pressure_teammate = player
	if player != null:
		_record("pressure_started", player)
		hud.flash(player.player_name.to_upper() + " PRESSES", 0.85)

func _update_team_pressure(held: bool) -> void:
	if not held or ball.last_touch_team != 1 or not ball.grip_holder_id.is_empty():
		_set_pressure_teammate(null)
		return
	var opponent_has_ball := false
	for opponent in away_outfield:
		if opponent.controlling_ball() or opponent.chasing_ball(ball):
			opponent_has_ball = true
			break
	if not opponent_has_ball:
		_set_pressure_teammate(null)
		return
	if pressure_teammate != null and _available_presser(pressure_teammate):
		return
	var closest: FootballPlayer = null
	var closest_distance := INF
	for teammate in home_outfield:
		if not _available_presser(teammate):
			continue
		var distance := FootballReception.flat(teammate.global_position - ball.global_position).length_squared()
		if distance < closest_distance:
			closest_distance = distance
			closest = teammate
	_set_pressure_teammate(closest)

func _controller_actions(delta: float, pressed: Dictionary) -> void:
	if eleven_a_side:
		_update_team_pressure(bool(pressed.get("teammate_press", false)))
	if pressed.get("hop", false) and not _can_modify_shot() and not (eleven_a_side and pressed.get("primary", false) and pressed.get("finesse_modifier", false)):
		controlled.hop()
	if controlled.ragdoll != null or controlled.hop_active:
		charging = false
		charge = 0.0
		shot_buffer_remaining = 0.0
		return
	if eleven_a_side and pressed.get("send_run", false):
		_send_teammate_run()
	if pressed.get("primary", false):
		shot_buffer_remaining = 0.0
		var attack := _attacking_contact()
		if eleven_a_side and ball.grip_holder_id.is_empty():
			attack = attack or controlled.chasing_ball(ball) or (ball.pass_active and ball.pass_receiver_id == controlled.player_id and controlled.reach_ball(ball, 1.65))
		if attack:
			charging = true
			charge = 0
			shot_style = _requested_shot_style(pressed) if eleven_a_side else "normal"
		else:
			var shouldered := false
			for opponent in players:
				if opponent.team == controlled.team or not opponent.reach_ball(ball):
					continue
				var side := opponent.global_position - controlled.global_position
				side.y = 0
				if side.length() < 0.95 and absf(side.normalized().dot(controlled.aim)) < 0.6:
					shouldered = controlled.shoulder(ball)
					break
			if not shouldered:
				controlled.tackle(ball)
	if charging:
		charge = minf(1, charge + delta / (1.0 if shot_style == "power" else 0.8))
		if pressed.get("primary_release", false):
			if eleven_a_side:
				shot_buffer_direction = _strike_direction()
				shot_buffer_charge = charge
				shot_buffer_remaining = SHOT_BUFFER_SECONDS
				_record("shot_requested", controlled, {"direction": _vec(shot_buffer_direction), "power": shot_buffer_charge, "style": shot_style})
			elif controlled.kick(ball, _strike_direction(), lerpf(12, 23, charge), lerpf(0.7, 3.2, charge), "shot"):
				controlled.pending_receiver_id = ""
			charging = false
			charge = 0
	if pressed.get("pass", false) or pressed.get("through", false) or pressed.get("square", false):
		shot_buffer_remaining = 0.0
	if shot_buffer_remaining > 0.0:
		var launch := _shot_launch(shot_style, shot_buffer_charge)
		if controlled.kick(ball, shot_buffer_direction, launch.x, launch.y, "shot", shot_style):
			controlled.pending_receiver_id = ""
			_record("shot_queued", controlled, {"buffer_wait_s": SHOT_BUFFER_SECONDS - shot_buffer_remaining, "contact_delay_s": controlled.kick_contact_time, "style": shot_style})
			shot_buffer_remaining = 0.0
			return
		shot_buffer_remaining = maxf(0.0, shot_buffer_remaining - delta)
		if shot_buffer_remaining == 0.0:
			_record("shot_buffer_expired", controlled)
	if pressed.get("square", false):
		if _attacking_contact():
			_request_delivery("lob", 12.5, 5.2)
		else:
			controlled.slide(ball)
	if pressed.get("pass", false):
		if eleven_a_side and ball.last_touch_team == controlled.team and ball.grip_holder_id.is_empty() and not _attacking_contact() and not controlled.chasing_ball(ball):
			pass_call_remaining = PASS_CALL_SECONDS
			_record("pass_called", controlled)
			hud.flash("PASS REQUESTED", 0.85)
		else:
			_request_delivery("pass", 10.5, 0.12)
	if pressed.get("through", false):
		_request_delivery("through", 13.5, 0.14)

func _clear_offside() -> void:
	offside_team = -1
	offside_candidates.clear()
	pending_indirect_player = null

func _on_ball_played(team: int, player_id: String, touch_kind: String) -> void:
	if phase != "playing" or pending_indirect_player != null or team not in [0, 1]:
		return
	var restart_kind: String = restart.get("kind", "")
	if indirect_taker != null:
		if player_id == indirect_taker.player_id and restart_kind.is_empty():
			_queue_indirect_restart(indirect_taker, "double_touch")
			return
		if player_id != indirect_taker.player_id:
			indirect_taker = null
			referee.resume_play()
	if restart_kind in ["throw_in", "corner", "goal_kick"]:
		return
	if restart_kind == "indirect_free_kick":
		indirect_taker = restart.taker
	if team == offside_team and offside_candidates.has(player_id):
		_queue_indirect_restart(offside_candidates[player_id], "offside")
		return
	if team != offside_team and touch_kind in ["save", "deflection"]:
		return
	offside_candidates.clear()
	offside_team = team
	var attack := keepers[team].attack_sign()
	var depth := ElevenOffside.line(players, team, attack, ball.global_position.x)
	for teammate: FootballPlayer in outfield_teams[team]:
		if teammate.player_id != player_id and ElevenOffside.beyond(teammate, attack, depth):
			offside_candidates[teammate.player_id] = teammate

func _queue_indirect_restart(player: FootballPlayer, reason: String) -> void:
	pending_indirect_player = player
	pending_indirect_reason = reason
	indirect_spot = ball.global_position

func _award_indirect_restart() -> bool:
	if pending_indirect_player == null:
		return false
	var offender := pending_indirect_player
	var spot := Vector3(clampf(indirect_spot.x, -49.5, 49.5), FootballBall.RADIUS, clampf(indirect_spot.z, -31.85, 31.85))
	var label := "OFFSIDE" if pending_indirect_reason == "offside" else "SECOND TOUCH"
	_record(pending_indirect_reason, offender, {"spot": _vec(spot)})
	_begin_restart("indirect_free_kick", 1 - offender.team, spot)
	sound.play_event("whistle")
	var hint := "  /  CROSS OR SPACE TO TAKE" if bool(restart.human) else ""
	hud.flash(label + "  /  INDIRECT FREE KICK" + hint, 3.0)
	return true

func _on_strike_contact(kind: String, player: FootballPlayer) -> void:
	if pass_call_remaining > 0.0 and player.team == controlled.team and player != controlled and player.pending_receiver_id == controlled.player_id and kind in ["pass", "through"]:
		pass_call_remaining = 0.0
	reception.queue_delivery(player,kind,ball)
	var detail := {"source": "controller" if player == controlled else "ai", "contact_distance": player.last_kick_contact_distance, "ball_position": _vec(ball.global_position), "touch_serial": ball.touch_serial}
	if kind == "shot":
		detail["style"] = player.kick_style if not player.kick_style.is_empty() else "normal"
	_record(kind, player, detail)
	if player == kickoff_taker and kind == "pass":
		_record("kickoff_taken", player, {"direction": _vec(player.action_direction), "touch_serial": ball.touch_serial})
		kickoff_taker = null
		kickoff_receiver = null
	if not restart.is_empty() and bool(restart.get("strike_requested", false)) and restart.taker == player and kind == str(restart.get("strike_kind", "")):
		_record("restart_taken", player, {"restart": restart.kind, "touch_serial": ball.touch_serial})
		if restart.kind != "indirect_free_kick":
			referee.resume_play()
		restart.clear()
	sound.play_event("kick")

func _on_dribble_contact(player: FootballPlayer) -> void:
	_record("touch", player)

func _on_physical_event(kind: String, detail: Dictionary, player: FootballPlayer) -> void:
	if kind == "keeper_release":
		reception.queue_delivery(player,str(detail.get("kind","roll")),ball,str(detail.get("receiver_id","")))
	_record(kind, player, detail)

func _control_ball() -> FootballPlayer:
	if not ball.grip_holder_id.is_empty():
		ball.control_candidate_id = ""
		return null
	for player: FootballPlayer in players:
		if player.player_id == ball.pass_receiver_id and ball.pass_active and not player.is_goalkeeper:
			player.receive(ball)
	# One nearest eligible foot per tick, with a small continuity preference.
	# This never blocks tackles or body collisions and applies equally to both teams.
	var candidate: FootballPlayer = null
	var best_distance := INF
	for player in players:
		if player.is_goalkeeper:
			continue
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
	# Entire sphere must cross the line, within the mouth and under the bar.
	var line := ElevenPitch.HALF_LENGTH if eleven_a_side else 18.1
	var mouth := ElevenPitch.GOAL_HALF_WIDTH if eleven_a_side else 2.21
	var bar := ElevenPitch.CROSSBAR_HEIGHT if eleven_a_side else 2.31
	if absf(ball.global_position.x) > line + FootballBall.RADIUS and absf(ball.global_position.x) < line + 2.2 and absf(ball.global_position.z) < mouth - FootballBall.RADIUS and ball.global_position.y < bar - FootballBall.RADIUS:
		var scoring := 0 if ball.global_position.x * keepers[0].attack_sign() > 0 else 1
		if eleven_a_side and indirect_taker != null:
			var side := signf(ball.global_position.x)
			if ball.last_touch_team == scoring:
				_begin_restart("goal_kick", 1 - scoring, Vector3(side * 44.5, FootballBall.RADIUS, 0.0))
			else:
				_begin_restart("corner", scoring, Vector3(side * 49.65, FootballBall.RADIUS, 31.65 if ball.global_position.z >= 0.0 else -31.65))
			return
		scores[scoring] += 1
		sound.play_event("goal")
		if eleven_a_side:
			_begin_goal_celebration(scoring)
		else:
			_record("goal", null, {"team": scoring, "ball": _vec(ball.global_position)})
			hud.flash("%s GOAL!" % ("HOME" if scoring == 0 else "AWAY"), 2.0)
			reset_positions(1 - scoring)

func _begin_goal_celebration(scoring: int) -> void:
	phase = "goal_celebration"
	celebration_elapsed = 0.0
	celebration_team = scoring
	celebration_scorer = null
	var last_player: FootballPlayer = null
	for player in players:
		if player.player_id == ball.last_touch_id:
			last_player = player
			break
	var own_goal := last_player != null and last_player.team != scoring
	var message := "%s GOAL!" % ("HOME" if scoring == 0 else "AWAY")
	if last_player != null:
		message += "  /  " + last_player.player_name.to_upper()
		if own_goal:
			message += " (OWN GOAL)"
		elif last_player.ragdoll == null and not last_player.hop_active:
			celebration_scorer = last_player
	celebration_focus = FootballReception.flat(ball.global_position)
	celebration_zoom = 12.5
	if celebration_scorer != null:
		var to_scorer := FootballReception.flat(celebration_scorer.global_position - celebration_focus)
		celebration_focus += to_scorer.limit_length(20.0) * 0.48
		celebration_zoom = clampf(9.0 + to_scorer.length() * 0.60, 12.5, 22.0)
	charging = false
	charge = 0.0
	shot_buffer_remaining = 0.0
	_set_pressure_teammate(null)
	_pause_players()
	hud.flash(message, GOAL_CELEBRATION_SECONDS)
	_record("goal", last_player, {"team": scoring, "ball": _vec(ball.global_position), "own_goal": own_goal})

func _tick_goal_celebration(delta: float) -> void:
	celebration_elapsed += delta
	if celebration_scorer != null:
		celebration_scorer.visual_controller.pose_celebration(celebration_scorer, celebration_elapsed)
	if celebration_elapsed < GOAL_CELEBRATION_SECONDS:
		return
	_resume_players()
	_record("goal_celebration_finished", celebration_scorer, {"team": celebration_team})
	celebration_scorer = null
	if remaining <= 0.0:
		_finish_match()
		return
	phase = "playing"
	reset_positions(1 - celebration_team)

func _check_eleven_boundary(delta: float) -> void:
	var point := ball.global_position
	var radius := FootballBall.RADIUS
	if throw_entry_time > 0.0:
		throw_entry_time = maxf(0.0, throw_entry_time - delta)
		if throw_entering_pitch():
			return
		throw_entry_time = 0.0
	if absf(point.z) > ElevenPitch.HALF_WIDTH + radius:
		var spot := Vector3(clampf(point.x, -49.5, 49.5), radius, signf(point.z) * 31.85)
		_begin_restart("throw_in", 1 if ball.last_touch_team == 0 else 0, spot)
	elif absf(point.x) > ElevenPitch.HALF_LENGTH + radius:
		var defender := 0 if point.x * keepers[0].attack_sign() < 0 else 1
		if ball.last_touch_team == defender:
			_begin_restart("corner", 1 - defender, Vector3(signf(point.x) * 49.65, radius, 31.65 if point.z >= 0.0 else -31.65))
		else:
			_begin_restart("goal_kick", defender, Vector3(signf(point.x) * 44.5, radius, clampf(point.z, -8.0, 8.0)))
	elif point.y < -1.0:
		reset_positions(1 if ball.last_touch_team == 0 else 0)

func throw_entering_pitch() -> bool:
	var point := ball.global_position
	return throw_entry_time > 0.0 and point.z * throw_entry_side > ElevenPitch.HALF_WIDTH - FootballBall.RADIUS and ball.linear_velocity.z * throw_entry_side < 0.0 and absf(point.x) <= ElevenPitch.HALF_LENGTH + FootballBall.RADIUS

func _begin_restart(kind: String, team: int, spot: Vector3) -> void:
	_clear_offside()
	indirect_taker = null
	_set_pressure_teammate(null)
	throw_entry_time = 0.0
	shot_buffer_remaining = 0.0
	pass_call_remaining = 0.0
	charging = false
	charge = 0.0
	var taker: FootballPlayer = keepers[team] if kind == "goal_kick" else null
	var field: Array[FootballPlayer] = home_outfield if team == 0 else away_outfield
	if taker == null:
		var best := INF
		for player: FootballPlayer in field:
			var distance := player.global_position.distance_squared_to(spot)
			if player.ragdoll == null and distance < best:
				taker = player
				best = distance
		if taker == null:
			taker = field[0]
	reception.reset(ball)
	for keeper: FootballPlayer in keepers:
		(keeper as FootballGoalkeeper).drop_ball("restart")
	for player: FootballPlayer in players:
		player.intent = Vector3.ZERO
		player.sprint = false
		player.reset_action()
	var inward := Vector3(-signf(spot.x) if kind != "throw_in" else 0.0, 0.0, -signf(spot.z) if kind != "goal_kick" else 0.0).normalized()
	if kind == "indirect_free_kick":
		inward = Vector3.RIGHT * taker.attack_sign()
	var stance_distance := 0.8 if kind == "throw_in" else 0.55
	taker.global_position = Vector3(spot.x, 0.06, spot.z) - inward * stance_distance
	taker.aim = inward
	if kind != "throw_in":
		taker.kick_cooldown = 0.0
	taker.linear_velocity = Vector3.ZERO
	taker.angular_velocity = Vector3.ZERO
	taker.reset_physics_interpolation()
	ball.freeze = true
	ball.clear_finesse()
	ball.global_position = spot
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.reset_physics_interpolation()
	if kind == "throw_in":
		taker.throw_in_phase = 0.0
		ball.global_position = taker.visual_controller.throw_in_hand_center(taker)
		ball.reset_physics_interpolation()
	var human := team == 0 and not taker.is_goalkeeper and decision_driver == null and not acceptance
	if human:
		_select(field.find(taker))
	restart = {"kind": kind, "taker": taker, "inward": inward, "remaining": 4.0 if human else 1.0, "human": human}
	referee.signal_restart(spot, Vector3.RIGHT * taker.attack_sign(), kind == "indirect_free_kick")
	_record(kind, taker)
	hud.flash(kind.replace("_", " ").to_upper() + ("  /  CROSS OR SPACE TO TAKE" if human else ""), 3.0)

func _tick_restart(delta: float) -> void:
	if restart.has("throw_direction"):
		_tick_throw_in(delta)
		return
	if restart.kind == "throw_in":
		var thrower: FootballPlayer = restart.taker
		ball.global_position = thrower.visual_controller.throw_in_hand_center(thrower)
	if bool(restart.get("strike_requested", false)):
		var kicker: FootballPlayer = restart.taker
		restart.strike_timeout -= delta
		if kicker.action_kind == "kick":
			return
		if float(restart.strike_timeout) <= 0.0:
			kicker.intent = Vector3.ZERO
			ball.freeze = false
			ball.sleeping = false
			_record("restart_strike_timeout", kicker, {"restart": restart.kind})
			restart.clear()
			referee.resume_play()
			return
		var aim_direction: Vector3 = restart.strike_direction
		var stance := ball.global_position - aim_direction * 0.55
		var approach := FootballReception.flat(stance - kicker.global_position)
		kicker.aim = aim_direction
		kicker.intent = approach.limit_length(0.35) if approach.length_squared() > 0.16 * 0.16 else Vector3.ZERO
		if kicker.intent != Vector3.ZERO or FootballReception.flat(kicker.linear_velocity).length_squared() > 0.75 * 0.75:
			return
		var lift := 4.2 if restart.kind == "corner" else 1.1
		if kicker.kick(ball, aim_direction, float(restart.strike_speed), lift, str(restart.strike_kind)):
			kicker.pending_receiver_id = str(restart.strike_receiver_id)
			ball.freeze = false
			ball.sleeping = false
		return
	restart.remaining -= delta
	var take_now := bool(restart.human) and Input.is_action_just_pressed("pass")
	if float(restart.remaining) > 0.0 and not take_now:
		return
	var taker: FootballPlayer = restart.taker
	var direction: Vector3 = restart.inward
	var kind: String = restart.kind
	var minimum_alignment := THROW_MIN_INWARD if kind == "throw_in" else 0.15
	var receiver: FootballPlayer = null
	var best := -INF
	for player: FootballPlayer in players:
		if player == taker or player.team != taker.team or player.is_goalkeeper:
			continue
		var offset := FootballReception.flat(player.global_position - ball.global_position)
		var distance := offset.length()
		var alignment := offset.normalized().dot(direction)
		if (kind != "indirect_free_kick" and alignment <= minimum_alignment) or player.ragdoll != null:
			continue
		var score := alignment * 10.0 - absf(distance - 11.0) * 0.4
		if distance > 2.5 and distance < 28.0 and score > best:
			receiver = player
			best = score
	if receiver != null:
		direction = FootballReception.flat(receiver.global_position - ball.global_position).normalized()
	if take_now:
		var stick := Input.get_vector("left", "right", "up", "down")
		if stick.length() > 0.25:
			var intended := Vector3(stick.x, 0, stick.y).normalized()
			var inward: Vector3 = restart.inward
			if kind == "indirect_free_kick" or intended.dot(inward) > minimum_alignment:
				direction = intended
				receiver = null
	var speed := 12.0 if receiver == null else clampf(ball.global_position.distance_to(receiver.global_position) * 0.9, 7.5, 16.0)
	if kind != "throw_in":
		restart.strike_requested = true
		restart.strike_timeout = 2.5
		restart.strike_direction = direction
		restart.strike_kind = "lob" if kind == "corner" else "pass"
		restart.strike_receiver_id = receiver.player_id if receiver != null else ""
		restart.strike_speed = speed
		return
	taker.aim = direction
	restart.throw_direction = direction
	restart.throw_elapsed = 0.0
	restart.throw_speed = speed
	restart.throw_receiver_id = receiver.player_id if receiver != null else ""

func _tick_throw_in(delta: float) -> void:
	var taker: FootballPlayer = restart.taker
	var hand_center := taker.visual_controller.throw_in_hand_center(taker)
	ball.global_position = hand_center
	# The player animates after the match callback. Wait until the sampled
	# hands have reached the release pose before unfreezing the ball.
	if taker.throw_in_phase < 0.7:
		restart.throw_elapsed += delta
		taker.throw_in_phase = 0.7 * clampf(float(restart.throw_elapsed) / THROW_WINDUP, 0.0, 1.0)
		return
	var direction: Vector3 = restart.throw_direction
	var release_velocity := direction * float(restart.throw_speed) + Vector3.UP * 2.6
	taker.throw_in_recovery = 0.18
	throw_entry_side = -signf((restart.inward as Vector3).z)
	throw_entry_time = 0.45
	ball.freeze = false
	ball.sleeping = false
	ball.touch(taker.team, taker.player_id, release_velocity * ball.mass)
	reception.queue_delivery(taker, "throw", ball, str(restart.throw_receiver_id))
	_record("restart_taken", taker, {
		"restart": "throw_in", "hand_center": _vec(hand_center), "release_position": _vec(ball.global_position),
		"release_velocity": _vec(release_velocity), "touch_serial": ball.touch_serial,
	})
	restart.clear()
	referee.resume_play()

func _finish_match() -> void:
	reception.reset(ball)
	for keeper: FootballPlayer in keepers:
		(keeper as FootballGoalkeeper).drop_ball("full_time")
	phase = "finished"
	match_count += 1
	for player in players:
		player.intent = Vector3.ZERO
		player.sprint = false
	var report := squad.finish(players)
	var hint := "Cross / Enter  REMATCH     •     Q  EXIT"
	if eleven_a_side:
		hint = "Cross / Enter  REMATCH     •     Triangle / M  SETUP     •     Q  EXIT"
	hud.show_overlay("FULL TIME  /  %d : %d" % [scores[0], scores[1]], "Your squad is growing through play.\n\n" + report, hint)
	sound.play_event("whistle")
	_record("full_time", null, {"score": scores.duplicate(), "save_error": squad.last_error})
	match_finished.emit()

func rematch() -> void:
	_set_ends_swapped(false)
	remaining = match_duration
	action_log.clear()
	scores = [0, 0]
	phase = "playing"
	hud.overlay.hide()
	for i in range(home_outfield.size()):
		squad.apply_to(home_outfield[i], i)
	squad.apply_to(keepers[0], _outfield_count())
	for player in players:
		player.energy = 1.0
		player.active_seconds = 0
		player.match_touches = 0
	reset_positions(0)
	_select(0)
	_record("rematch", null)

func _unhandled_input(event: InputEvent) -> void:
	if phase == "setup":
		return
	if event.is_action_pressed("pause") and not event.is_echo():
		if phase == "playing":
			phase = "paused"
			charging = false
			charge = 0.0
			shot_buffer_remaining = 0.0
			_pause_players()
			ball.freeze = true
			var styles := "\nHold R1 for finesse, L1 for chip, or both for power before Circle. Keyboard modifiers: R and F." if eleven_a_side else ""
			var runs := "\nD-pad up / G: send a runner. Cross / Space off the ball: ask for a pass.\nHold D-pad down / T: teammate pressure in defence." if eleven_a_side else ""
			var attack_side := "left" if ends_swapped else "right"
			hud.show_overlay("HALF A BREATH", "Left stick: move + aim. Cross: pass. Triangle: through pass.\nCircle: hold/release shot, or tackle/shoulder in defence." + styles + "\nSquare: lofted pass in attack, sliding tackle in defence.\nR1: timed hop. R2: sprint. L2: shield / jockey. L1 / right stick: switch.\nKeyboard: Space pass / J shot / U lob / I through.\nK tackle / L slide / H shoulder / Ctrl jockey / E hop. Blue attacks %s." % attack_side + runs, "Options / Esc  RESUME     •     Q  EXIT")
		elif phase == "paused":
			phase = "playing"
			_resume_players()
			ball.freeze = false
			hud.overlay.hide()
	elif phase == "finished" and eleven_a_side and event.is_action_pressed("match_setup"):
		_show_match_setup()
	elif phase == "finished" and event.is_action_pressed("confirm"):
		rematch()
	elif phase != "playing" and event.is_action_pressed("quit"):
		get_tree().quit()

func _pause_players() -> void:
	pause_states.clear()
	for player in players:
		_pause_node(player)
		if player.ragdoll != null:
			_pause_node(player.ragdoll)
			for body in player.ragdoll.bodies:
				_pause_node(body)

func _resume_players() -> void:
	for saved in pause_states:
		var node: Node = saved.node
		if is_instance_valid(node):
			node.set_physics_process(saved.physics)
			if node is RigidBody3D:
				node.freeze = saved.freeze
	pause_states.clear()

func _pause_node(node: Node) -> void:
	pause_states.append({"node": node, "physics": node.is_physics_processing(), "freeze": node.freeze if node is RigidBody3D else false})
	node.set_physics_process(false)
	if node is RigidBody3D:
		node.freeze = true

func _process(delta: float) -> void:
	if controlled == null:
		return
	var ball_pos := ball.get_global_transform_interpolated().origin
	var player_pos := controlled.get_global_transform_interpolated().origin
	var focus := ball_pos * 0.3
	var offset := Vector3(0.0, 34.0, 29.0)
	var on_goal := phase == "goal_celebration"
	var blend := 1.0 - exp(-delta * (5.0 if on_goal else 3.0))
	if eleven_a_side:
		var between := FootballReception.flat(player_pos - ball_pos)
		focus = ball_pos + between.limit_length(30.0) * 0.40
		var zoom := clampf(42.0 + between.length() * 0.28, 42.0, 57.0)
		if on_goal:
			focus = celebration_focus + Vector3.UP * 0.7
			offset = Vector3(signf(celebration_focus.x) * 5.5, 5.6, 9.0)
			zoom = celebration_zoom
		camera.size = lerpf(camera.size, zoom, blend)
	var horizontal_limit := 48.0 if on_goal else (37.0 if eleven_a_side else 2.5)
	focus.x = clampf(focus.x, -horizontal_limit, horizontal_limit)
	if not on_goal:
		focus.y = 0.0
	focus.z = clampf(focus.z, -21.0 if eleven_a_side else -1.6, 21.0 if eleven_a_side else 1.6)
	camera_focus = camera_focus.lerp(focus, blend)
	camera_offset = camera_offset.lerp(offset, blend)
	camera.position = camera_focus + camera_offset
	camera.look_at(camera_focus)
	var strike_direction := _strike_direction()
	aim_line.position = player_pos + strike_direction * 1.5 + Vector3(0, 0.05, 0)
	aim_line.rotation.y = atan2(strike_direction.x, strike_direction.z)
	aim_line.visible = phase == "playing"
	hud.update_match(scores, remaining, controlled, charge, (2 if ends_swapped else 1) if eleven_a_side else 0)
	if eleven_a_side:
		var live := phase == "playing" and restart.is_empty() and kickoff_remaining <= 0.0 and not is_instance_valid(kickoff_taker)
		var receiving_id := ball.pass_receiver_id if live and ball.pass_active and ball.pass_team == 0 else ""
		var runner_id := ""
		for player in home_outfield:
			var marker := ""
			if player.player_id == receiving_id:
				marker = "receive"
			elif live and player == called_runner and player.called_run_remaining > 0.0:
				marker = "run"
				runner_id = player.player_id
			player.visual_controller.set_tactical_marker(player, marker)
		if hud.radar != null:
			hud.radar.update_positions(players, ball, controlled, runner_id, receiving_id)
	var devices := Input.get_connected_joypads()
	hud.status.text = "DECISION PLAYTEST / HARDWARE INPUT DISABLED" if decision_driver != null else ("CONTROLLER CONNECTED" if not devices.is_empty() else "KEYBOARD READY  /  CONNECT A CONTROLLER ANYTIME")
	if eleven_a_side and charging:
		hud.status.text = shot_style.to_upper() + " SHOT  /  RELEASE TO STRIKE"

func _record(kind: String, player: FootballPlayer, extra: Dictionary = {}) -> void:
	var entry := {"time": snappedf(match_duration - remaining, 0.01), "kind": kind, "player": player.player_id if player != null else "", "team": player.team if player != null else -1}
	entry.merge(extra, true)
	if eleven_a_side and entry["kind"] != kind:
		entry["detail_kind"] = entry["kind"]
		entry["kind"] = kind
	action_log.append(entry)

func _vec(value: Vector3) -> Array:
	return [snappedf(value.x, 0.001), snappedf(value.y, 0.001), snappedf(value.z, 0.001)]
