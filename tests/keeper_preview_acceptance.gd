extends Node

## One continuous acceptance invocation. Initial fixtures are disclosed and set
## ONLY between labelled drills. A fresh, ordinary match follows; its bodies,
## ball, clock, score and outcomes are never corrected by this test.

const PALETTE: Array[Color] = [Color("24d3c8"), Color("ff9d3c"), Color("d346d1"), Color("a8e043")]
const CASES: Array[Dictionary] = [
	{"name":"walk_dribble", "title":"DRILL 1A / walking touches, free ball travel, catch-up and stop", "seconds":18.0},
	{"name":"sprint_dribble", "title":"DRILL 1B / sprint touches, free ball travel, catch-up and stop", "seconds":20.0},
	{"name":"loose_shot", "title":"DRILL 2A / opponent last touch / ground shot / aim on release", "seconds":5.0},
	{"name":"incoming_shot", "title":"DRILL 2B / moving incoming ball / first-time shot", "seconds":5.0},
	{"name":"miss_swing", "title":"DRILL 2C / ball behind physical reach / deliberate air swing", "seconds":4.0},
	{"name":"raw_lob", "title":"DRILL 2D / Square lob follows raw stick, no teammate retarget", "seconds":4.0},
	{"name":"raw_through", "title":"DRILL 2E / Through pass follows raw stick, no teammate retarget", "seconds":4.0},
	{"name":"receive", "title":"DRILL 3A / ordinary Cross pass / moving receiver", "seconds":6.0},
	{"name":"intercept", "title":"DRILL 3B / ordinary Cross pass / physical interception", "seconds":6.0},
	{"name":"keeper_catch", "title":"DRILL 4A / declared chest-height impulse / catch and release", "seconds":6.0},
	{"name":"keeper_parry", "title":"DRILL 4B / declared faster impulse / physical parry", "seconds":6.0},
	{"name":"keeper_outside", "title":"DRILL 4C / keeper outside area / no hand possession", "seconds":6.0},
	{"name":"match", "title":"NORMAL 4 v 4 MATCH / fresh production kickoff / 180-second clock", "seconds":0.0}
]
const MAX_TOTAL_WALL: float = 420.0
const MAX_MATCH_WALL: float = 300.0
var game: Node3D
var session: String = ""
var token: String = ""
var identities: Array = []
var movement: Vector2 = Vector2.ZERO
var sprinting: bool = false
var actions: Dictionary = {}
var scene_ready: bool = false
var started: bool = false
var finished: bool = false
var transitioning: bool = false
var initialized_us: int = 0
var start_us: int = 0
var finish_us: int = 0
var physics_frames: int = 0
var finish_frame: int = 0
var case_index: int = 0
var case_start_frame: int = 0
var case_start_us: int = 0
var case_metrics: Dictionary = {}
var drill_results: Dictionary = {}
var stage_records: Array[Dictionary] = []
var setup_count: int = 0
var manual_fixture: bool = true
var receiver: FootballPlayer
var interceptor: FootballPlayer
var drill_keeper: FootballPlayer
var launch_impulse: Vector3 = Vector3.ZERO
var initial_receiver_position: Vector3 = Vector3.ZERO
var dribble_gap_max: float = 0.0
var last_observed_touch_serial: int = 0
var actual_sprint_seconds: float = 0.0
var actual_stop_speed: float = INF
var controlled_passes: int = 0
var controlled_shots: int = 0
var controlled_touches: int = 0
var ai_contacts: int = 0
var opponent_contacts: int = 0
var finite_physics: bool = true
var match_full_time: bool = false
var match_start_frame: int = 0
var match_start_us: int = 0
var match_roster_valid: bool = false
var match_save_path: String = ""
var think_remaining: float = 0.0
var switch_remaining: float = 0.0
var next_action_at: float = 0.0
var shot_release_at: float = -1.0
var stop_until: float = 0.0
var stop_requested: bool = false
var switches: int = 0
var fps_samples: Array[float] = []
var source_save_hashes: Dictionary = {}
var telemetry: FileAccess
var event_file: FileAccess
var sample_clock: float = 0.0
var marker: ColorRect
var identity_cells: Array[ColorRect] = []
var frame_cells: Array[ColorRect] = []
var status: Label
var final_exit_code: int = 1
var cycle: Dictionary = {}
var cycles: Array[Dictionary] = []
var contact_serials: Dictionary = {}
var contacted_feet: Dictionary = {}
var start_touch_serial: int = 0
var kick_frame: int = -1
var intended_kick_direction: Vector3 = Vector3.RIGHT
var waypoint_index: int = 0
var shot_pressed: bool = false
var shot_released: bool = false

func configure(directory: String, request: Dictionary) -> void:
	session = directory
	token = str(request.capture_token)
	identities = request.identity_phases
	initialized_us = Time.get_ticks_usec()
	process_physics_priority = -100

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	marker = _rect(layer, Vector2(1120,22), Vector2(100,28), PALETTE[0])
	for index: int in range(12):
		identity_cells.append(_rect(layer, Vector2(1120+index*8,58), Vector2(8,12), PALETTE[int(identities[index])]))
		frame_cells.append(_rect(layer, Vector2(1120+index*8,82), Vector2(8,12), PALETTE[0]))
	status = Label.new()
	status.position = Vector2(18, 730)
	status.add_theme_font_size_override("font_size", 15)
	status.add_theme_color_override("font_color", Color.WHITE)
	status.text = "KEEPER PREVIEW / recording preflight / initial fixture held"
	layer.add_child(status)
	telemetry = FileAccess.open(session.path_join("telemetry.jsonl"), FileAccess.WRITE)
	event_file = FileAccess.open(session.path_join("events.jsonl"), FileAccess.WRITE)
	source_save_hashes = _original_saves()

func _rect(parent: Node, position: Vector2, size: Vector2, color: Color) -> ColorRect:
	var result := ColorRect.new()
	result.position = position
	result.size = size
	result.color = color
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

func prepare() -> void:
	await _new_game(true, "walk_dribble")
	if not is_instance_valid(game) or telemetry == null or event_file == null:
		_infrastructure_failure("Could not construct the isolated drill scene or evidence streams.")
		return
	_setup_case()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	scene_ready = true
	_write("ready.json", {"scene":"keeper_preview_acceptance", "game_ready":true, "capture_token":token,
		"identity_phases":identities, "hwnd":str(DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)),
		"viewport":[1280,800], "marker_rect":[1120,22,100,28], "identity_rect":[1120,58,96,12], "frame_rect":[1120,82,96,12],
		"physics_hz":Engine.physics_ticks_per_second, "max_wall_seconds":MAX_TOTAL_WALL,
		"executable_path":OS.get_executable_path(), "pack_path":OS.get_executable_path().get_base_dir().path_join("BasedFootball.pck"),
		"planned_stages":CASES, "custom_user_dir":ProjectSettings.get_setting("application/config/custom_user_dir_name", ""),
		"fixture_policy":"Declared initial placements and finite impulses only between isolated labelled drills; one fresh normal match, no corrections or forced outcomes within any case."})
	print("KEEPER_PREVIEW_READY ", token)

func _new_game(manual: bool, key: String) -> void:
	if is_instance_valid(game):
		game.queue_free()
		await get_tree().process_frame
	var packed: PackedScene = load("res://scenes/match.tscn")
	if packed == null:
		_infrastructure_failure("Production match scene is missing.")
		return
	game = packed.instantiate() as Node3D
	var save_path: String = session.path_join(key + "-squad.json")
	if FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path + ".tmp"):
		_infrastructure_failure("Refusing to reuse an existing isolated career save.")
		return
	game.squad.save_path = save_path
	game.decision_driver = self
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	manual_fixture = manual
	game.set_physics_process(not manual)
	game.set_process(not manual)
	game.set_process_unhandled_input(false)
	for player: FootballPlayer in game.players:
		player.strike_contact.connect(_strike.bind(player))
		player.dribble_contact.connect(_touch.bind(player))
		player.physical_event.connect(_physical.bind(player))
		if manual:
			player.freeze = true
			player.intent = Vector3.ZERO
	game.ball.freeze = manual
	if not manual:
		game.match_finished.connect(_match_finished, CONNECT_ONE_SHOT)
		match_save_path = save_path
	setup_count += 1

func _setup_case() -> void:
	var name: String = str(CASES[case_index].name)
	case_metrics = {"name":name, "pass_contacts":0, "shot_contacts":0, "receive_contacts":0, "receiver_started_before_contact":false,
		"receiver_motion_frame":-1, "receiver_contact_frame":-1, "pass_strike_frame":-1, "assigned_receiver":"",
		"opponent_contact_frame":-1, "interception_cancels_intent":false, "catches":0, "parries":0, "releases":0,
		"held_samples":0, "held_free_body":true, "outside_close_hand_samples":0, "outside_hand_events":0, "min_hand_gap":999.0,
		"kick_contacts":0,"kick_swing_observed":false,"kick_raw_direction_dot":-1.0,"actual_outgoing_direction_dot":-1.0,
		"actual_post_kick_velocity":[],"pre_shot_dribble_contacts":0,"kick_contact_details":{},"max_gap_m":0.0}
	cycle.clear()
	cycles.clear()
	contact_serials.clear()
	contacted_feet.clear()
	dribble_gap_max = 0.0
	actual_sprint_seconds = 0.0
	actual_stop_speed = INF
	waypoint_index = 0
	shot_pressed = false
	shot_released = false
	kick_frame = -1
	intended_kick_direction = Vector3(0.8,0,0.6).normalized()
	movement = Vector2.ZERO
	sprinting = false
	actions.clear()
	launch_impulse = Vector3.ZERO
	receiver = null
	interceptor = null
	drill_keeper = null
	if name == "match":
		var team_counts: Array[int] = [0,0]
		var keeper_count: int = 0
		for player: FootballPlayer in game.players:
			team_counts[player.team] += 1
			keeper_count += 1 if player.is_goalkeeper else 0
		match_roster_valid = game.players.size() == 8 and team_counts == [4,4] and keeper_count == 2
		match_start_frame = physics_frames
		match_start_us = Time.get_ticks_usec()
		think_remaining = 0.0
		switch_remaining = 0.0
		next_action_at = 0.0
		shot_release_at = -1.0
		stop_requested = false
		return
	for index: int in range(game.players.size()):
		var player: FootballPlayer = game.players[index]
		player.global_position = Vector3(-14.0+float(index)*3.0, 0.025, 9.0 if player.team == 0 else -9.0)
		player.linear_velocity = Vector3.ZERO
		player.angular_velocity = Vector3.ZERO
		player.intent = Vector3.ZERO
		player.sprint = false
		player.aim = Vector3.RIGHT
		player.reset_action()
		player.body_visual.rotation.y = -PI*0.5
	var actor: FootballPlayer = game.home_outfield[0]
	game._select(game.players.find(actor))
	game.ball.global_position = Vector3(-7.35, FootballBall.RADIUS+0.025, -4.0)
	game.ball.linear_velocity = Vector3.ZERO
	game.ball.angular_velocity = Vector3.ZERO
	actor.global_position = Vector3(-8.0, 0.025, -4.0)
	if _is_strike_case(name):
		game.ball.last_touch_team = 1
		game.ball.last_touch_id = "declared_opponent_last_touch"
		if name == "incoming_shot":
			game.ball.global_position = actor.global_position + Vector3(1.1,FootballBall.RADIUS,0)
			launch_impulse = Vector3(-2.4,0,0)*game.ball.mass
		elif name == "miss_swing":
			game.ball.global_position = actor.global_position + Vector3(-1.6,FootballBall.RADIUS,0)
			intended_kick_direction = Vector3.RIGHT
		elif name == "raw_through":
			intended_kick_direction = Vector3(0.9,0,-0.435).normalized()
	if name == "receive" or name == "intercept":
		receiver = game.home_outfield[1]
		receiver.global_position = Vector3(-1.8, 0.025, -4.0)
		initial_receiver_position = receiver.global_position
		if name == "intercept":
			interceptor = game.away_outfield[0]
			interceptor.global_position = Vector3(-4.5, 0.025, -4.0)
			interceptor.aim = Vector3.LEFT
	elif name.begins_with("keeper_"):
		drill_keeper = game.keepers[0]
		drill_keeper.global_position = Vector3(-11.0 if name == "keeper_outside" else -17.0, 0.025, 0.0)
		drill_keeper.aim = Vector3.RIGHT
		# The next activation uses evaluated gloves; initial launch is a declared
		# finite impulse, not a fake player contact, catch, parry or save count.
	game.camera.size = 12.0 if name == "walk_dribble" else 14.0 if name == "sprint_dribble" else 16.0
	var target := Vector3(-3.0,0.7,-2.0)
	if name.begins_with("keeper_"):
		game.camera.size = 12.0
		target = Vector3(-15.0,0.9,0.0)
	game.camera.global_position = target + Vector3(0,15,12)
	game.camera.look_at(target)
	case_metrics.initial_last_touch_team = game.ball.last_touch_team
	_event("declared_fixture_setup", {"case":name, "initial_player_positions":_roster(), "ball":_vec(game.ball.global_position),
		"other_players_frozen":true, "production_match_physics_disabled_for_drill":true})

func _activate_case() -> void:
	case_start_frame = physics_frames
	case_start_us = Time.get_ticks_usec()
	var name: String = str(CASES[case_index].name)
	if manual_fixture:
		game.ball.freeze = false
		if name.begins_with("keeper_"):
			drill_keeper.freeze = false
			var hands: Array = drill_keeper.call("hand_positions")
			if hands.size() < 2:
				_infrastructure_failure("Keeper hand probes are unavailable.")
				return
			var center: Vector3 = hands[0] if name == "keeper_outside" else (hands[0] + hands[1]) * 0.5
			var distance: float = 0.30 if name == "keeper_outside" else 1.5 if name == "keeper_parry" else 0.9
			var speed: float = 8.8 if name in ["keeper_parry","keeper_outside"] else 2.8
			var travel: float = distance / speed
			var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
			game.ball.global_position = center + Vector3(distance,0,0)
			game.ball.last_touch_team = 1
			game.ball.last_touch_id = "declared_ball_launcher"
			launch_impulse = Vector3(-speed,gravity*travel*0.5,0) * game.ball.mass
			game.ball.apply_central_impulse(launch_impulse)
			_event("declared_finite_launch", {"case":name,"ball_position":_vec(game.ball.global_position),"initial_impulse":_vec(launch_impulse),
				"requested_speed":speed,"intended_arrival_height":center.y,"source":"labelled initial physics fixture, not a player kick"})
		else:
			game.controlled.freeze = false
			if is_instance_valid(receiver): receiver.freeze = false
			if is_instance_valid(interceptor): interceptor.freeze = false
			if launch_impulse.length_squared() > 0.0:
				game.ball.apply_central_impulse(launch_impulse)
				_event("declared_finite_launch",{"case":name,"impulse":_vec(launch_impulse),"ball_position":_vec(game.ball.global_position),"source":"labelled initial incoming-ball fixture"})
	last_observed_touch_serial = int(game.ball.touch_serial)
	start_touch_serial = int(game.ball.touch_serial)
	_event("stage_started", {"case":name,"title":CASES[case_index].title,"initial_match_remaining":game.remaining,"setup_count":setup_count})

func _process(delta: float) -> void:
	if marker == null:
		return
	var seconds: float = float(Time.get_ticks_usec()-(start_us if started else initialized_us))/1000000.0
	marker.color = PALETTE[int(seconds*2.0)%4]
	frame_cells[0].color = PALETTE[2 if finished else 1 if started else 0]
	var count: int = finish_frame if finished else physics_frames
	for index: int in range(11): frame_cells[index+1].color = PALETTE[(count>>(index*2))&3]
	if started and not finished:
		fps_samples.append(1.0/maxf(delta,0.000001))
		status.text = str(CASES[case_index].title) + (" / setting up next labelled fixture" if transitioning else " / %.1fs / %d FPS" % [_case_seconds(),Engine.get_frames_per_second()])
		if manual_fixture and not transitioning and _is_dribble_case(str(CASES[case_index].name)):
			var target: Vector3 = game.controlled.global_position + Vector3(0,0.7,0)
			game.camera.global_position = game.camera.global_position.lerp(target+Vector3(0,12,9),minf(1.0,delta*5.0))
			game.camera.look_at(target)

func _physics_process(delta: float) -> void:
	if finished:
		var hold: float = float(Time.get_ticks_usec()-finish_us)/1000000.0
		if hold >= 1.2 and (_flag("allowexit.flag") or hold >= 20.0): get_tree().quit(final_exit_code)
		return
	if not scene_ready:
		return
	if not started:
		if _flag("start.flag"):
			started = true
			start_us = Time.get_ticks_usec()
			_write("started.json", {"capture_token":token,"physics_frame":Engine.get_physics_frames(),"system_time_unix":Time.get_unix_time_from_system()})
			get_tree().paused = false
			_activate_case()
		elif float(Time.get_ticks_usec()-initialized_us)/1000000.0 > 240.0:
			_infrastructure_failure("Preflight timed out before any behavior.")
		return
	physics_frames += 1
	if transitioning:
		return
	if manual_fixture:
		_drive_drill(delta)
	_monitor(delta)
	sample_clock += delta
	if sample_clock >= 0.1:
		sample_clock = fmod(sample_clock,0.1)
		call_deferred("_sample")
	if manual_fixture and _case_seconds() >= float(CASES[case_index].seconds):
		_finish_case()
		transitioning = true
		call_deferred("_next_case")
	elif not manual_fixture and float(Time.get_ticks_usec()-match_start_us)/1000000.0 > MAX_MATCH_WALL:
		_finish(false,"Normal match did not reach full-time within its safety limit.")
	if _wall() > MAX_TOTAL_WALL and not finished:
		_finish(false,"Acceptance safety limit reached.")

func _next_case() -> void:
	case_index += 1
	var name: String = str(CASES[case_index].name)
	await _new_game(name != "match", name)
	if finished:
		return
	_setup_case()
	# Let frozen bodies and real glove histories settle after the disclosed
	# setup teleport; never count a fixture relocation as a swept hand contact.
	# The tree is running and setup remains visible in this same recording.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_activate_case()
	transitioning = false

func _drive_drill(delta: float) -> void:
	var name: String = str(CASES[case_index].name)
	var actor: FootballPlayer = game.controlled
	var time: float = _case_seconds()
	actions.clear()
	movement = Vector2.ZERO
	sprinting = false
	if _is_dribble_case(name):
		var points: Array[Vector3] = [Vector3(-1,0,-4),Vector3(5,0,0),Vector3(2,0,5),Vector3(-5,0,4),Vector3(-8,0,-2)]
		var target: Vector3 = points[waypoint_index%points.size()]
		if _flat(target-actor.global_position).length() < 1.0:
			waypoint_index += 1
			target = points[waypoint_index%points.size()]
			_event("ordinary_stick_turn",{"target":_vec(target),"player":_vec(actor.global_position),"ball_velocity_before_input":_vec(game.ball.linear_velocity),"last_touch_serial":game.ball.touch_serial})
		var gap: float = _flat(game.ball.global_position-actor.global_position).length()
		# This is ordinary observed-ball steering, not a body/ball correction.
		if gap > 1.05: target = game.ball.global_position+_flat(game.ball.linear_velocity)*0.1
		var offset: Vector3 = _flat(target-actor.global_position)
		var amount: float = 1.0 if name == "sprint_dribble" else 0.70 if gap > 1.05 else 0.55
		var moving_until: float = float(CASES[case_index].seconds)-3.0
		var direction: Vector3 = offset.normalized()*minf(amount,offset.length()/1.2) if time < moving_until else Vector3.ZERO
		movement = Vector2(direction.x,direction.z)
		sprinting = name == "sprint_dribble" and time < moving_until
	elif _is_strike_case(name):
		var press_at: float = 0.05 if name == "incoming_shot" else 0.30
		var release_at: float = 0.10 if name == "incoming_shot" else 0.58
		if not shot_pressed and time >= press_at:
			shot_pressed = true
			if name in ["loose_shot","incoming_shot"]:
				actions["primary"] = true
			else:
				movement = Vector2(intended_kick_direction.x,intended_kick_direction.z)
				actions["square" if name == "raw_lob" else "through"] = true
		if name in ["loose_shot","incoming_shot"] and not shot_released and time >= release_at:
			shot_released = true
			movement = Vector2(intended_kick_direction.x,intended_kick_direction.z)
			actions["primary_release"] = true
	elif name == "receive" or name == "intercept":
		actor.aim = Vector3.RIGHT
		if time >= 0.6 and time < 0.6+delta: actions["pass"] = true
	actor.intent = Vector3(movement.x,0,movement.y)
	actor.sprint = sprinting
	if movement.length_squared() > 0.04: actor.aim = actor.intent.normalized()
	game._controller_actions(delta,actions)
	game.reception.update(game,delta)
	if is_instance_valid(receiver) and game.ball.pass_active:
		FootballAI.decide(receiver,game.players,game.ball,delta)
	if is_instance_valid(interceptor) and game.ball.pass_active:
		FootballAI.decide(interceptor,game.players,game.ball,delta)
	if is_instance_valid(drill_keeper):
		drill_keeper.call("decide_keeper",game.players,game.ball,delta)
	# The loose/moving-ball strike cases must not gain possession by an earlier
	# auto-dribble. Only their ordinary kick action may make player contact.
	if not _is_strike_case(name): game._control_ball()

func decide(delta: float) -> void:
	actions.clear()
	if not started or finished or transitioning or manual_fixture:
		movement = Vector2.ZERO
		sprinting = false
		return
	var seconds: float = _case_seconds()
	switch_remaining = maxf(0.0,switch_remaining-delta)
	if shot_release_at >= 0.0 and seconds >= shot_release_at:
		actions["primary_release"] = true
		shot_release_at = -1.0
		var release_direction: Vector3 = _flat(Vector3(18.8,0,0)-game.controlled.global_position).normalized()
		movement = Vector2(release_direction.x,release_direction.z)
		sprinting = false
		return
	think_remaining -= delta
	if think_remaining > 0.0: return
	think_remaining = 0.12
	var actor: FootballPlayer = game.controlled
	var ball: FootballBall = game.ball
	var nearest: FootballPlayer = actor
	for teammate: FootballPlayer in game.home_outfield:
		if teammate.ragdoll == null and teammate.global_position.distance_to(ball.global_position) < nearest.global_position.distance_to(ball.global_position): nearest = teammate
	if nearest != actor and switch_remaining <= 0.0 and not game.charging and actor.global_position.distance_to(ball.global_position) > 2.4:
		game._switch_player(_flat(nearest.global_position-actor.global_position).normalized())
		actor = game.controlled
		switches += 1
		switch_remaining = 0.8
	var offset: Vector3 = _flat(ball.global_position-actor.global_position)
	var goal: Vector3 = _flat(Vector3(18.8,0,0)-actor.global_position)
	var desired: Vector3 = _flat(ball.global_position+ball.linear_velocity*0.12-actor.global_position).normalized()
	sprinting = offset.length() > 2.0
	if seconds < stop_until or game.charging:
		movement = Vector2.ZERO
		sprinting = false
		return
	if game._attacking_contact():
		desired = goal.normalized()
		var danger: float = INF
		for opponent: FootballPlayer in game.players:
			if opponent.team != actor.team: danger = minf(danger,_flat(opponent.global_position-actor.global_position).length())
		sprinting = danger > 2.3 and goal.length() > 7.0
		if not stop_requested and controlled_touches > 0 and seconds > 5.0:
			stop_requested = true
			stop_until = seconds+0.45
			movement = Vector2.ZERO
			sprinting = false
			return
		if actor.kick_cooldown <= 0.0 and actor.action_kind.is_empty() and seconds >= next_action_at:
			var target: FootballPlayer = _pass_option(actor)
			if target != null and (controlled_passes == 0 or (danger < 1.6 and goal.length() > 9.0)):
				desired = _flat(target.global_position-actor.global_position).normalized()
				actions["pass"] = true
				next_action_at = seconds+2.3
			elif goal.length() < 14.0 or (controlled_shots == 0 and seconds > 35.0):
				actions["primary"] = true
				shot_release_at = seconds+(0.08 if _flat(ball.linear_velocity).length() > 0.7 else 0.24)
				next_action_at = seconds+2.3
	elif ball.last_touch_team == 1 and offset.length() < 0.95 and actor.tackle_cooldown <= 0.0 and seconds >= next_action_at:
		actions["primary"] = true
		next_action_at = seconds+0.8
	movement = Vector2(desired.x,desired.z)

func _pass_option(actor: FootballPlayer) -> FootballPlayer:
	var best: FootballPlayer
	var best_score: float = -INF
	for teammate: FootballPlayer in game.home_outfield:
		if teammate == actor or teammate.ragdoll != null: continue
		var offset: Vector3 = _flat(teammate.global_position-actor.global_position)
		if offset.length() < 2.0: continue
		var clearance: float = 20.0
		for opponent: FootballPlayer in game.away_outfield: clearance = minf(clearance,_flat(opponent.global_position-teammate.global_position).length())
		var score: float = clearance+clampf(offset.x,-5.0,5.0)*0.2-offset.length()*0.08
		if score > best_score:
			best = teammate
			best_score = score
	return best

func _monitor(delta: float) -> void:
	for player: FootballPlayer in game.players: finite_physics = finite_physics and player.global_position.is_finite() and player.linear_velocity.is_finite()
	finite_physics = finite_physics and game.ball.global_position.is_finite() and game.ball.linear_velocity.is_finite()
	var name: String = str(CASES[case_index].name)
	if _is_dribble_case(name):
		var gap: float = _flat(game.ball.global_position-game.controlled.global_position).length()
		dribble_gap_max = maxf(dribble_gap_max,gap)
		if sprinting and _flat(game.controlled.linear_velocity).length() > 4.5: actual_sprint_seconds += delta
		_observe_cycle()
		if _case_seconds() > float(CASES[case_index].seconds)-0.5:
			actual_stop_speed = _flat(game.controlled.linear_velocity).length()
			case_metrics.stop_ball_speed_mps = game.ball.linear_velocity.length()
	elif _is_strike_case(name):
		case_metrics.kick_swing_observed = bool(case_metrics.kick_swing_observed) or game.controlled.action_kind == "kick"
		if kick_frame >= 0 and physics_frames > kick_frame and (case_metrics.actual_post_kick_velocity as Array).is_empty():
			var outgoing: Vector3 = _flat(game.ball.linear_velocity)
			case_metrics.actual_post_kick_velocity = _vec(game.ball.linear_velocity)
			case_metrics.actual_outgoing_direction_dot = outgoing.normalized().dot(intended_kick_direction) if outgoing.length() > 0.1 else -1.0
	elif name == "receive" and is_instance_valid(receiver):
		if game.ball.pass_active and str(case_metrics.assigned_receiver).is_empty(): case_metrics.assigned_receiver = game.ball.pass_receiver_id
		var ball_gap: float = _flat(game.ball.global_position-receiver.global_position).length()
		var flight_direction: Vector3 = _flat(game.ball.pass_target-receiver.global_position).normalized()
		var toward_flight: float = _flat(receiver.linear_velocity).dot(flight_direction)
		if game.ball.pass_active and game.ball.pass_receiver_id == receiver.player_id and int(case_metrics.pass_strike_frame) >= 0 and int(case_metrics.receiver_motion_frame) < 0 and ball_gap > 1.0 and toward_flight > 0.05 and _flat(receiver.linear_velocity).length() > 0.15 and _flat(receiver.global_position-initial_receiver_position).length() > 0.12:
			case_metrics.receiver_motion_frame = physics_frames
			_event("receiver_started_on_real_flight", {"receiver":receiver.player_id,"ball_gap":ball_gap,"ball":_vec(game.ball.global_position),"velocity":_vec(receiver.linear_velocity),"toward_flight_speed":toward_flight,"pass_active":game.ball.pass_active})
	elif name == "intercept":
		if int(game.ball.touch_serial) != last_observed_touch_serial and game.ball.last_touch_team == 1 and int(case_metrics.pass_strike_frame) >= 0:
			case_metrics.opponent_contact_frame = physics_frames
			_event("observed_opponent_ball_contact",{"touch_serial":game.ball.touch_serial,"last_touch_id":game.ball.last_touch_id,"pass_active":game.ball.pass_active})
		if int(case_metrics.opponent_contact_frame) >= 0 and game.ball.last_touch_team == 1 and not game.ball.pass_active:
			case_metrics.interception_cancels_intent = true
	if is_instance_valid(drill_keeper):
		var hands: Array = drill_keeper.call("hand_positions")
		var gap: float = INF
		for hand: Vector3 in hands: gap = minf(gap,hand.distance_to(game.ball.global_position))
		case_metrics.min_hand_gap = minf(float(case_metrics.min_hand_gap),gap)
		if drill_keeper.get("held_ball") == game.ball:
			case_metrics.held_samples = int(case_metrics.held_samples)+1
			case_metrics.held_free_body = bool(case_metrics.held_free_body) and not game.ball.freeze and game.ball.get_parent() == game
		if name == "keeper_outside" and not bool(drill_keeper.call("area_contains",drill_keeper.global_position)) and gap < 0.32:
			case_metrics.outside_close_hand_samples = int(case_metrics.outside_close_hand_samples)+1
	last_observed_touch_serial = int(game.ball.touch_serial)

func _finish_case() -> void:
	var name: String = str(CASES[case_index].name)
	if _is_dribble_case(name):
		_observe_cycle()
		var unmatched: Array[Dictionary] = []
		for entry: Dictionary in game.ball.impulse_audit:
			if int(entry.serial) <= start_touch_serial: continue
			var receipt: Dictionary = contact_serials.get(int(entry.serial),{})
			if receipt.is_empty() or str(entry.player_id) != game.controlled.player_id or _from_vector(entry.impulse).distance_to(_from_vector(receipt.get("impulse",[]))) > 0.00001:
				unmatched.append(entry.duplicate(true))
		case_metrics.merge({"contacts":contact_serials.size(),"cycles":cycles.duplicate(true),"completed_cycles":cycles.size(),
			"feet_used":contacted_feet.keys(),"max_gap_m":dribble_gap_max,"sprint_seconds":actual_sprint_seconds,
			"stop_body_speed_mps":actual_stop_speed,"unmatched_ball_touch_impulses":unmatched,"ball_impulse_ledger":game.ball.impulse_audit.duplicate(true),
			"continuous_force_evidence":"Frozen production source audit plus actual ball.touch ledger/event serial alignment and observed free lead/catch-up motion; native engine calls are not globally intercepted."})
		case_metrics["pass"] = cycles.size() >= 3 and contacted_feet.has("left") and contacted_feet.has("right") and unmatched.is_empty() and dribble_gap_max <= 2.5 and actual_stop_speed < 0.25 and float(case_metrics.get("stop_ball_speed_mps",999.0)) < 0.35 and (name != "sprint_dribble" or actual_sprint_seconds > 1.0)
	elif _is_strike_case(name):
		case_metrics.final_touch_serial_delta = int(game.ball.touch_serial)-start_touch_serial
		case_metrics.intended_raw_direction = _vec(intended_kick_direction)
		if name == "miss_swing":
			case_metrics["pass"] = bool(case_metrics.kick_swing_observed) and int(case_metrics.kick_contacts) == 0 and int(case_metrics.final_touch_serial_delta) == 0
		else:
			var expected_kind: String = "lob" if name == "raw_lob" else "through" if name == "raw_through" else "shot"
			var actual_kind: String = str(case_metrics.kick_contact_details.get("kind",""))
			var incoming_speed: float = _flat(_from_vector(case_metrics.kick_contact_details.get("incoming_velocity",[]))).length()
			case_metrics["pass"] = bool(case_metrics.kick_swing_observed) and int(case_metrics.kick_contacts) > 0 and int(case_metrics.pre_shot_dribble_contacts) == 0 and float(case_metrics.kick_raw_direction_dot) >= 0.98 and float(case_metrics.actual_outgoing_direction_dot) >= 0.85 and actual_kind == expected_kind and (name != "incoming_shot" or incoming_speed > 0.5)
	elif name == "receive":
		case_metrics.receiver_started_before_contact = int(case_metrics.receiver_motion_frame) >= 0 and int(case_metrics.receiver_contact_frame) > int(case_metrics.receiver_motion_frame)
		case_metrics["pass"] = int(case_metrics.pass_contacts) > 0 and int(case_metrics.receive_contacts) > 0 and bool(case_metrics.receiver_started_before_contact) and str(case_metrics.assigned_receiver) == receiver.player_id
	elif name == "intercept":
		case_metrics["pass"] = int(case_metrics.pass_contacts) > 0 and int(case_metrics.opponent_contact_frame) >= 0 and bool(case_metrics.interception_cancels_intent)
	elif name == "keeper_catch":
		case_metrics["pass"] = int(case_metrics.catches) > 0 and int(case_metrics.releases) > 0 and int(case_metrics.held_samples) > 0 and bool(case_metrics.held_free_body)
	elif name == "keeper_parry":
		case_metrics["pass"] = int(case_metrics.parries) > 0
	elif name == "keeper_outside":
		case_metrics["pass"] = int(case_metrics.outside_close_hand_samples) > 0 and int(case_metrics.outside_hand_events) == 0 and int(case_metrics.catches) == 0
	drill_results[name] = case_metrics.duplicate(true)
	stage_records.append({"name":name,"first_physics_frame":case_start_frame,"last_physics_frame":physics_frames,"sim_seconds":_case_seconds(),"metrics":case_metrics.duplicate(true)})
	_event("stage_finished",case_metrics)

func _strike(kind: String, player: FootballPlayer) -> void:
	if not started or transitioning or finished: return
	if manual_fixture:
		if player == game.controlled and (kind == "pass" or kind == "through"):
			case_metrics.pass_contacts = int(case_metrics.pass_contacts)+1
			case_metrics.pass_strike_frame = physics_frames
			case_metrics.assigned_receiver = game.ball.pass_receiver_id
		elif player == game.controlled and kind == "shot": case_metrics.shot_contacts = int(case_metrics.shot_contacts)+1
	else:
		if player == game.controlled:
			if kind == "pass" or kind == "through": controlled_passes += 1
			elif kind == "shot": controlled_shots += 1
		else: ai_contacts += 1
		if player.team == 1: opponent_contacts += 1
	_event("strike_contact", {"kind":kind,"player":player.player_id,"team":player.team,"assigned_receiver":game.ball.pass_receiver_id})

func _touch(player: FootballPlayer) -> void:
	if not started or transitioning or finished: return
	var name: String = str(CASES[case_index].name)
	if name == "intercept" and player.team == 1: case_metrics.opponent_contact_frame = physics_frames
	if not manual_fixture:
		if player == game.controlled: controlled_touches += 1
		else: ai_contacts += 1
		if player.team == 1: opponent_contacts += 1
	_event("dribble_contact", {"player":player.player_id,"team":player.team,"ball":_vec(game.ball.global_position)})

func _physical(kind: String, detail: Dictionary, player: FootballPlayer) -> void:
	if not started or transitioning or finished: return
	if manual_fixture:
		var name: String = str(CASES[case_index].name)
		if kind == "dribble_touch" and player == game.controlled:
			if _is_dribble_case(name):
				_observe_cycle()
				cycle.clear()
				var serial: int = int(detail.get("touch_serial",game.ball.touch_serial))
				contact_serials[serial] = detail.duplicate(true)
				contacted_feet[str(detail.get("foot","unknown"))] = true
				if not bool(detail.get("trap",false)):
					var offset: Vector3 = _flat(game.ball.global_position-player.global_position)
					var direction: Vector3 = _flat(_from_vector(detail.get("direction",[]))).normalized()
					cycle = {"touch_serial":serial,"contact_frame":physics_frames,"foot":detail.get("foot","unknown"),
						"initial_gap":offset.length(),"initial_lead":offset.dot(direction),"peak_gap":offset.length(),"peak_lead":offset.dot(direction),
						"direction":_vec(direction),"completed":false,"contact_details":detail.duplicate(true)}
			elif _is_strike_case(name) and kick_frame < 0:
				case_metrics.pre_shot_dribble_contacts = int(case_metrics.pre_shot_dribble_contacts)+1
		if kind == "kick_contact" and player == game.controlled and _is_strike_case(name):
			case_metrics.kick_contacts = int(case_metrics.kick_contacts)+1
			case_metrics.kick_contact_details = detail.duplicate(true)
			case_metrics.kick_raw_direction_dot = _flat(_from_vector(detail.get("aim_direction",[]))).normalized().dot(intended_kick_direction)
			kick_frame = physics_frames
		if kind == "receive_contact" and player == receiver:
			case_metrics.receive_contacts = int(case_metrics.receive_contacts)+1
			case_metrics.receiver_contact_frame = physics_frames
		if kind == "receive_contact" and player.team == 1: case_metrics.opponent_contact_frame = physics_frames
		if player == drill_keeper:
			if kind == "keeper_catch": case_metrics.catches = int(case_metrics.catches)+1
			elif kind == "keeper_parry": case_metrics.parries = int(case_metrics.parries)+1
			elif kind == "keeper_release": case_metrics.releases = int(case_metrics.releases)+1
			if kind in ["keeper_catch","keeper_parry"] and not bool(drill_keeper.call("area_contains",drill_keeper.global_position)): case_metrics.outside_hand_events = int(case_metrics.outside_hand_events)+1
	_event(kind,detail.merged({"player":player.player_id,"team":player.team}))

func _sample() -> void:
	if finished or transitioning or telemetry == null or not is_instance_valid(game): return
	telemetry.store_line(JSON.stringify({"physics_frames":physics_frames,"engine_physics_frame":Engine.get_physics_frames(),"case":CASES[case_index].name,
		"case_seconds":_case_seconds(),"sim_seconds":float(physics_frames)/Engine.physics_ticks_per_second,"wall_seconds":_wall(),
		"remaining":game.remaining,"phase":game.phase,"score":game.scores,"players":_roster(),
		"ball":{"position":_vec(game.ball.global_position),"velocity":_vec(game.ball.linear_velocity),"last_touch_id":game.ball.last_touch_id,
			"last_touch_team":game.ball.last_touch_team,"pass_active":game.ball.pass_active,"receiver_id":game.ball.pass_receiver_id,"grip_holder_id":game.ball.grip_holder_id},
		"input":{"movement":[movement.x,movement.y],"sprint":sprinting,"actions":actions},"case_metrics":case_metrics,"fps":Engine.get_frames_per_second()}))
	telemetry.flush()

func _roster() -> Array[Dictionary]:
	var roster: Array[Dictionary] = []
	for player: FootballPlayer in game.players:
		roster.append({"id":player.player_id,"team":player.team,"keeper":player.is_goalkeeper,"position":_vec(player.global_position),
			"velocity":_vec(player.linear_velocity),"frozen_for_drill":player.freeze,"action":player.action_kind,"receiving":player.receiving_active,
			"actual_boot_gap":player.last_control_boot_gap,"anatomical_reach_gap":player.last_control_reach_gap,"control_reason":player.last_control_reason,
			"control_misses":player.control_misses,"receive_contacts":player.completed_receive_contacts})
	return roster

func _match_finished() -> void:
	match_full_time = true
	_finish(true,"Production match_finished signal after the fresh normal four-a-side match.")

func _finish(full_time: bool, reason: String) -> void:
	if finished: return
	finished = true
	finish_us = Time.get_ticks_usec()
	finish_frame = physics_frames
	movement = Vector2.ZERO
	sprinting = false
	actions.clear()
	var checks: Dictionary = {"walk_kick_ahead_fixture":false,"sprint_kick_ahead_fixture":false,"loose_ball_shot_fixture":false,
		"incoming_first_time_shot_fixture":false,"deliberate_miss_fixture":false,"raw_lob_direction_fixture":false,"raw_through_direction_fixture":false,
		"moving_receive_fixture":false,"interception_fixture":false,
		"keeper_catch_release_fixture":false,"keeper_parry_fixture":false,"keeper_outside_area_fixture":false}
	var mapping: Dictionary = {"walk_dribble":"walk_kick_ahead_fixture","sprint_dribble":"sprint_kick_ahead_fixture",
		"loose_shot":"loose_ball_shot_fixture","incoming_shot":"incoming_first_time_shot_fixture","miss_swing":"deliberate_miss_fixture",
		"raw_lob":"raw_lob_direction_fixture","raw_through":"raw_through_direction_fixture","receive":"moving_receive_fixture","intercept":"interception_fixture",
		"keeper_catch":"keeper_catch_release_fixture","keeper_parry":"keeper_parry_fixture","keeper_outside":"keeper_outside_area_fixture"}
	for key: String in mapping: checks[mapping[key]] = bool(drill_results.get(key,{}).get("pass",false))
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(match_save_path)) if not match_save_path.is_empty() and FileAccess.file_exists(match_save_path) else null
	var progression_ok: bool = saved is Dictionary and int(saved.get("matches",0)) == 1
	if progression_ok:
		for entry: Dictionary in game.squad.entries: progression_ok = progression_ok and int(saved.get("xp",{}).get(str(entry.id),0)) > 0
	checks.merge({"normal_full_time":full_time and game.phase == "finished" and game.remaining <= 0.0 and game.match_count == 1,
		"four_a_side_roster":match_roster_valid,"normal_pass_contact":controlled_passes > 0,"normal_shot_contact":controlled_shots > 0,
		"normal_dribble_contact":controlled_touches > 0,"normal_AI_played_ball":ai_contacts > 0,"normal_opponents_played_ball":opponent_contacts > 0,
		"finite_physics":finite_physics,"isolated_progression_saved":progression_ok and game.squad.last_error.is_empty(),
		"original_saves_unchanged":source_save_hashes == _original_saves()})
	var passed: bool = true
	for value: bool in checks.values(): passed = passed and value
	final_exit_code = 0 if passed else 1
	var sorted_fps: Array[float] = fps_samples.duplicate()
	sorted_fps.sort()
	var median_fps: float = sorted_fps[sorted_fps.size()/2] if not sorted_fps.is_empty() else 0.0
	_event("verification_finished",{"match_full_time":full_time,"reason":reason,"checks":checks})
	if telemetry != null: telemetry.close()
	if event_file != null: event_file.close()
	telemetry = null
	event_file = null
	_write("events.json",{"stages":stage_records,"normal_match_production_log":game.action_log})
	_write("result.json",{"schema":"keeper-preview-acceptance/v1","capture_token":token,"pass":passed,"match_full_time":full_time,
		"physics_frames":finish_frame,"sim_seconds":float(finish_frame)/Engine.physics_ticks_per_second,"wall_seconds":float(finish_us-start_us)/1000000.0,
		"normal_match_seconds":float(finish_frame-match_start_frame)/Engine.physics_ticks_per_second,"normal_match_wall_seconds":float(finish_us-match_start_us)/1000000.0,
		"checks":checks,"drills":drill_results,"final_phase":game.phase,"remaining":game.remaining,"score":game.scores,"match_count":game.match_count,
		"controlled_passes":controlled_passes,"controlled_shots":controlled_shots,"controlled_touches":controlled_touches,"ai_contacts":ai_contacts,"opponent_contacts":opponent_contacts,
		"median_fps":median_fps,"switches":switches,"labelled_fixture_setups":setup_count,"match_fixture_resets":0,
		"original_saves_before":source_save_hashes,"original_saves_after":_original_saves(),"career_save":match_save_path,"saved_career":saved,
		"user_data_dir":OS.get_user_data_dir(),"reason":reason,"hardware_controller_verified":false,"subjective_fun_verified":false,
		"limitations":["Labelled drill initial positions and keeper incoming impulses are test fixtures; no catch or contact counters are injected.",
			"Only declared actors and their production AI/actions run in the drills; the full normal match uses all eight players.",
			"Historical goals/out-of-court centre resets remain production behavior.","No same-case ball rescue or player repositioning; no retry of failed drills.",
			"No continuous dribbling control force is assessed through frozen source audit, actual ball.touch ledger/event serial alignment and observed free lead/catch-up motion. Native engine force calls are not globally intercepted; rolling, Magnus, collisions and keeper grip remain physical environment effects.",
			"Numeric checks cannot establish natural animation, physical controller compatibility or subjective fun."]})
	_write("finished.json",{"capture_token":token,"match_full_time":full_time,"physics_frames":finish_frame,"pass":passed})
	status.text = "KEEPER PREVIEW FINISHED / full-time %s / acceptance %s / recorded evidence preserved" % [str(full_time),"PASS" if passed else "FAIL"]
	print("KEEPER_PREVIEW_FINISHED ",JSON.stringify(checks))

func _original_saves() -> Dictionary:
	var appdata: String = OS.get_environment("APPDATA")
	var result: Dictionary = {}
	for relative: String in ["BasedFootball-Recovered-3v3/squad.json","Godot/app_userdata/Based Football/squad.json"]:
		var path: String = appdata.path_join(relative)
		result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	return result

func _event(kind: String, detail: Dictionary) -> void:
	if event_file == null: return
	event_file.store_line(JSON.stringify({"kind":kind,"case":CASES[case_index].name,"physics_frames":physics_frames,
		"sim_seconds":float(physics_frames)/Engine.physics_ticks_per_second,"wall_seconds":_wall(),"detail":detail}))
	event_file.flush()

func _flag(name: String) -> bool:
	var path: String = session.path_join(name)
	if not FileAccess.file_exists(path): return false
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value is Dictionary and str(value.get("capture_token","")) == token

func _write(name: String, data: Dictionary) -> void:
	var output: FileAccess = FileAccess.open(session.path_join(name),FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify(data,"\t"))

func _infrastructure_failure(reason: String) -> void:
	_write("infrastructure-error.json",{"capture_token":token,"reason":reason,"behavior_started":started})
	get_tree().quit(2)

func _case_seconds() -> float:
	return float(physics_frames-case_start_frame)/Engine.physics_ticks_per_second

func _wall() -> float:
	return float(Time.get_ticks_usec()-start_us)/1000000.0 if started else 0.0

func _flat(value: Vector3) -> Vector3:
	return value*Vector3(1,0,1)

func _vec(value: Vector3) -> Array[float]:
	return [value.x,value.y,value.z]

func _is_dribble_case(name: String) -> bool:
	return name in ["walk_dribble","sprint_dribble"]

func _is_strike_case(name: String) -> bool:
	return name in ["loose_shot","incoming_shot","miss_swing","raw_lob","raw_through"]

func _from_vector(value: Variant) -> Vector3:
	if value is Vector3: return value
	if value is Array and value.size() == 3: return Vector3(float(value[0]),float(value[1]),float(value[2]))
	return Vector3.ZERO

func _observe_cycle() -> void:
	if cycle.is_empty() or bool(cycle.get("completed",false)): return
	var offset: Vector3 = _flat(game.ball.global_position-game.controlled.global_position)
	var direction: Vector3 = _from_vector(cycle.direction)
	var gap: float = offset.length()
	var lead: float = offset.dot(direction)
	cycle.peak_gap = maxf(float(cycle.peak_gap),gap)
	cycle.peak_lead = maxf(float(cycle.peak_lead),lead)
	var gap_growth: float = float(cycle.peak_gap)-float(cycle.initial_gap)
	var lead_growth: float = float(cycle.peak_lead)-float(cycle.initial_lead)
	var gap_shrink: float = float(cycle.peak_gap)-gap
	var lead_shrink: float = float(cycle.peak_lead)-lead
	if gap_growth >= 0.12 and lead_growth >= 0.12 and gap_shrink >= 0.12 and lead_shrink >= 0.12:
		cycle.completed = true
		cycle.catchup_frame = physics_frames
		cycle.gap_growth_m = gap_growth
		cycle.lead_growth_m = lead_growth
		cycle.gap_shrink_m = gap_shrink
		cycle.lead_shrink_m = lead_shrink
		cycle.catchup_gap_m = gap
		cycle.seconds_since_real_touch = float(physics_frames-int(cycle.contact_frame))/Engine.physics_ticks_per_second
		cycles.append(cycle.duplicate(true))
		_event("measured_touch_ahead_catchup_cycle",cycle)
