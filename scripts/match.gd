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
var right_stick_latched: bool = false
var camera_focus := Vector3.ZERO
var aim_line: MeshInstance3D
var action_log: Array[Dictionary] = []
var match_count: int = 0
var acceptance: bool = false
var pause_requested: bool = false

func _ready() -> void:
	acceptance = "--acceptance" in OS.get_cmdline_user_args()
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
	if acceptance:
		var session: Node = load("res://tests/acceptance.gd").new()
		add_child(session)
		session.begin(self)

func _install_input() -> void:
	for action in ["left", "right", "up", "down", "pass", "shoot", "tackle", "sprint", "switch", "pause", "confirm", "quit"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.18)
	var key_bindings := {"left": KEY_A, "right": KEY_D, "up": KEY_W, "down": KEY_S, "pass": KEY_SPACE, "shoot": KEY_J, "tackle": KEY_K, "sprint": KEY_SHIFT, "switch": KEY_TAB, "pause": KEY_ESCAPE, "confirm": KEY_ENTER, "quit": KEY_Q}
	for action in key_bindings:
		var key := InputEventKey.new()
		key.physical_keycode = key_bindings[action]
		InputMap.action_add_event(action, key)
	var buttons := {"pass": JOY_BUTTON_A, "shoot": JOY_BUTTON_B, "tackle": JOY_BUTTON_X, "switch": JOY_BUTTON_LEFT_SHOULDER, "pause": JOY_BUTTON_START, "confirm": JOY_BUTTON_A, "quit": JOY_BUTTON_BACK}
	for action in buttons:
		var button := InputEventJoypadButton.new()
		button.button_index = buttons[action]
		InputMap.action_add_event(action, button)
	for mapping in [["left", JOY_AXIS_LEFT_X, -1.0], ["right", JOY_AXIS_LEFT_X, 1.0], ["up", JOY_AXIS_LEFT_Y, -1.0], ["down", JOY_AXIS_LEFT_Y, 1.0], ["sprint", JOY_AXIS_TRIGGER_RIGHT, 1.0]]:
		var axis := InputEventJoypadMotion.new()
		axis.axis = mapping[1]
		axis.axis_value = mapping[2]
		InputMap.action_add_event(mapping[0], axis)

func _build_pitch() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("182737")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("cadbe3")
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, -30, 0)
	sun.light_color = Color("fff0d5")
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80
	add_child(sun)
	var concrete := FootballArt.material(Color("334758"))
	var grass_dark := FootballArt.material(Color("286856"))
	var grass_light := FootballArt.material(Color("2c715e"))
	var white := FootballArt.material(Color("c7ded0"))
	var board := FootballArt.material(Color("e1e6cf"))
	var blue := FootballArt.material(Color("2686bf"))
	var orange := FootballArt.material(Color("df6954"))
	FootballArt.solid(self, Vector3(70, 0.5, 55), Vector3(0, -0.4, 0), concrete)
	FootballArt.solid(self, Vector3(36, 0.25, 24), Vector3(0, -0.13, 0), grass_dark)
	for i in range(8):
		FootballArt.box(self, Vector3(4.5, 0.006, 24), Vector3(-15.75 + i * 4.5, 0.002, 0), grass_light if i % 2 == 0 else grass_dark)
	for side in [-1.0, 1.0]:
		FootballArt.solid(self, Vector3(36.8, 1.0, 0.35), Vector3(0, 0.5, side * 12.18), board)
		for lane in [-1.0, 1.0]:
			FootballArt.solid(self, Vector3(0.35, 1.0, 9.8), Vector3(side * 18.18, 0.5, lane * 7.25), board)
		_build_goal(side, blue if side < 0 else orange)
		FootballArt.line(self, Vector3(-17.9, 0.015, side * 11.9), Vector3(17.9, 0.015, side * 11.9), 0.06, white)
		FootballArt.line(self, Vector3(side * 17.9, 0.015, -11.9), Vector3(side * 17.9, 0.015, 11.9), 0.06, white)
		FootballArt.line(self, Vector3(side * 12.5, 0.015, -4.2), Vector3(side * 12.5, 0.015, 4.2), 0.06, white)
		for lane in [-1.0, 1.0]:
			FootballArt.line(self, Vector3(side * 12.5, 0.015, lane * 4.2), Vector3(side * 17.9, 0.015, lane * 4.2), 0.06, white)
		# Low terrace seating and lamps give the small court a sense of place.
		for row in range(3):
			FootballArt.box(self, Vector3(30, 0.5, 1.15), Vector3(0, 0.15 + row * 0.5, side * (14.0 + row * 1.2)), concrete)
			for seat in range(18):
				FootballArt.box(self, Vector3(0.85, 0.12, 0.65), Vector3(-14.5 + seat * 1.7, 0.48 + row * 0.5, side * (14.0 + row * 1.2)), blue if seat % 3 else orange)
	FootballArt.line(self, Vector3(0, 0.015, -11.9), Vector3(0, 0.015, 11.9), 0.07, white)
	FootballArt.circle(self, 3.0, Vector3(0, 0.018, 0), white, 0.035)
	FootballArt.cylinder(self, 0.12, 0.02, Vector3(0, 0.025, 0), white)
	var sign := FootballArt.text(self, "BASED FOOTBALL     /     PLAY YOUR WAY", Vector3(0, 1.75, -12.4), 66, Color("f3efdd"))
	sign.rotation.x = deg_to_rad(-12)
	for x in [-21.0, 21.0]:
		for z in [-14.0, 14.0]:
			FootballArt.cylinder(self, 0.12, 6.0, Vector3(x, 3, z), concrete)
			FootballArt.box(self, Vector3(1.3, 0.2, 0.55), Vector3(x, 6, z), white)

func _build_goal(side: float, mat: Material) -> void:
	var post := FootballArt.material(Color("f4efd8"))
	FootballArt.solid(self, Vector3(0.18, 2.4, 0.18), Vector3(side * 18.1, 1.2, -2.3), post)
	FootballArt.solid(self, Vector3(0.18, 2.4, 0.18), Vector3(side * 18.1, 1.2, 2.3), post)
	FootballArt.solid(self, Vector3(0.18, 0.18, 4.78), Vector3(side * 18.1, 2.4, 0), post)
	FootballArt.solid(self, Vector3(0.2, 2.4, 4.8), Vector3(side * 20.1, 1.2, 0), mat)
	for z in [-2.4, 2.4]:
		FootballArt.solid(self, Vector3(2.1, 2.4, 0.15), Vector3(side * 19.1, 1.2, z), mat)
	# Open front; stylized net strands sit in front of the back wall.
	for i in range(12):
		FootballArt.box(self, Vector3(0.03, 2.3, 0.018), Vector3(side * 19.97, 1.2, -2.2 + i * 0.4), post)
	for i in range(6):
		FootballArt.box(self, Vector3(0.03, 0.025, 4.5), Vector3(side * 19.96, 0.2 + i * 0.4, 0), post)

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
		player.reset_physics_interpolation()
	ball.global_position = Vector3(0, 0.3, 0)
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.reset_physics_interpolation()
	kickoff_remaining = 1.5
	charging = false
	charge = 0.0

func _select(index: int) -> void:
	selected_index = clampi(index, 0, 2)
	controlled = players[selected_index]
	for player in players:
		player.selected = player == controlled
	charging = false
	charge = 0.0

func _switch_player(direction: Vector3 = Vector3.ZERO) -> void:
	var best := -INF
	var winner := selected_index
	for i in range(3):
		if i == selected_index:
			continue
		var value := -players[i].global_position.distance_to(ball.global_position)
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
	if kickoff_remaining > 0:
		kickoff_remaining -= delta
		for player in players:
			player.intent = Vector3.ZERO
		return
	remaining = maxf(0, remaining - delta)
	var movement := Input.get_vector("left", "right", "up", "down")
	controlled.intent = Vector3(movement.x, 0, movement.y)
	controlled.sprint = Input.is_action_pressed("sprint")
	if movement.length_squared() > 0.04:
		controlled.aim = controlled.intent.normalized()
	if Input.is_action_just_pressed("switch"):
		_switch_player()
	var right := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if right.length() > 0.6 and not right_stick_latched:
		_switch_player(Vector3(right.x, 0, right.y).normalized())
	right_stick_latched = right.length() > 0.4
	if Input.is_action_just_pressed("pass"):
		_record("pass_attempt", controlled, {"source": "controller"})
		if controlled.kick(ball, controlled.aim, 10.5, 0.28):
			_record("pass", controlled, {"source": "controller"})
			sound.play_event("kick")
	if Input.is_action_just_pressed("shoot"):
		charging = true
		charge = 0.0
	if charging:
		charge = minf(1.0, charge + delta / 0.8)
		if Input.is_action_just_released("shoot"):
			_record("shot_attempt", controlled, {"source": "controller"})
			if controlled.kick(ball, controlled.aim, lerpf(12, 23, charge), lerpf(0.6, 2.3, charge)):
				_record("shot", controlled, {"source": "controller"})
				sound.play_event("kick")
			charging = false
			charge = 0.0
	if Input.is_action_just_pressed("tackle"):
		if controlled.tackle(ball):
			_record("tackle", controlled, {"source": "controller"})
	for player in players:
		if player != controlled:
			var action := FootballAI.decide(player, players, ball, delta)
			if action != "":
				_record(action, player, {"source": "ai"})
				sound.play_event("kick")
		if player.dribble(ball):
			_record("touch", player)
	_check_goal()
	# This is a visible dead-ball restart for an escape over the low boards.
	if absf(ball.global_position.z) > 13.2 or absf(ball.global_position.x) > 21 or ball.global_position.y < -1:
		_record("out_of_court", null)
		reset_positions(1 if ball.last_touch_team == 0 else 0)
		hud.flash("BALL OUT — CENTRE RESTART")
	if remaining <= 0:
		_finish_match()

func _check_goal() -> void:
	# Entire sphere must cross the line, within the mouth and under the bar.
	if absf(ball.global_position.x) > 18.38 and absf(ball.global_position.x) < 20.3 and absf(ball.global_position.z) < 2.0 and ball.global_position.y < 2.1:
		var scoring := 0 if ball.global_position.x > 0 else 1
		scores[scoring] += 1
		_record("goal", null, {"team": scoring, "ball": _vec(ball.global_position)})
		sound.play_event("goal")
		hud.flash("%s GOAL!" % ("HOME" if scoring == 0 else "AWAY"), 2.0)
		reset_positions(1 - scoring)

func _finish_match() -> void:
	phase = "finished"
	match_count += 1
	for player in players:
		player.intent = Vector3.ZERO
		player.sprint = false
	var report := squad.finish(players)
	hud.show_overlay("FULL TIME  /  %d : %d" % [scores[0], scores[1]], "Your squad is growing through play.\n\n" + report, "A / Enter  REMATCH     •     Back / Q  EXIT")
	sound.play_event("whistle")
	_record("full_time", null, {"score": scores.duplicate(), "save_error": squad.last_error})
	match_finished.emit()

func rematch() -> void:
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
			phase = "paused"
			for player in players:
				player.freeze = true
			ball.freeze = true
			hud.show_overlay("HALF A BREATH", "Move + aim with the left stick. Pass into space.\nHold B to charge a shot. Sprint stretches your touches.\nMiss a tackle and you need a moment to recover.\n\nBlue attacks right. Orange attacks left.", "Menu / Esc  RESUME     •     Back / Q  EXIT")
		elif phase == "paused":
			phase = "playing"
			for player in players:
				player.freeze = false
			ball.freeze = false
			hud.overlay.hide()
	elif phase == "finished" and event.is_action_pressed("confirm"):
		rematch()
	elif phase != "playing" and event.is_action_pressed("quit"):
		get_tree().quit()

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
	hud.update_match(scores, remaining, controlled, charge)
	var devices := Input.get_connected_joypads()
	hud.status.text = "CONTROLLER CONNECTED" if not devices.is_empty() else "KEYBOARD READY  /  CONNECT A CONTROLLER ANYTIME"

func _record(kind: String, player: FootballPlayer, extra: Dictionary = {}) -> void:
	var entry := {"time": snappedf(DURATION - remaining, 0.01), "kind": kind, "player": player.player_id if player != null else "", "team": player.team if player != null else -1}
	entry.merge(extra, true)
	action_log.append(entry)

func _vec(value: Vector3) -> Array:
	return [snappedf(value.x, 0.001), snappedf(value.y, 0.001), snappedf(value.z, 0.001)]
