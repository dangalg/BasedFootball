extends Node

## One uninterrupted, labelled diagnostic invocation. Initial positions are test
## fixtures between cases only. Production inputs, AI, boots and ball impulses
## determine every action; no fixture is rescued, retried or declared a contact.
const PALETTE: Array[Color] = [Color("24d3c8"),Color("ff9d3c"),Color("d346d1"),Color("a8e043")]
const MAX_WALL: float = 240.0
var cases: Array[Dictionary] = []
var game: Node3D
var session: String = ""
var token: String = ""
var identities: Array = []
var movement: Vector2 = Vector2.ZERO
var sprinting: bool = false
var actions: Dictionary = {}
var scene_ready: bool = false
var started: bool = false
var transitioning: bool = false
var finished: bool = false
var initialized_us: int = 0
var start_us: int = 0
var finish_us: int = 0
var physics_frames: int = 0
var finish_frame: int = 0
var case_index: int = 0
var case_start_frame: int = 0
var setup_count: int = 0
var case_metrics: Dictionary = {}
var case_results: Array[Dictionary] = []
var production_logs: Array[Dictionary] = []
var ai_actors: Array[FootballPlayer] = []
var receiver: FootballPlayer
var alternative: FootballPlayer
var initial_receiver_position: Vector3 = Vector3.ZERO
var initial_human_position: Vector3 = Vector3.ZERO
var recovering: bool = false
var cross_requested: bool = false
var turn_input_recorded: bool = false
var human_cross_frame: int = -1
var initial_receive_frame: int = -1
var first_return_frame: int = -1
var contact_receipts: Dictionary = {}
var dribble_receipts: Array[Dictionary] = []
var kick_receipts: Array[Dictionary] = []
var receive_receipts: Array[Dictionary] = []
var flight_receipts: Array[Dictionary] = []
var ai_choices: Array[Dictionary] = []
var last_choice_by_player: Dictionary = {}
var last_flight_key: String = ""
var last_touch_serial: int = 0
var last_ball_position: Vector3 = Vector3.ZERO
var source_save_hashes: Dictionary = {}
var finite_physics: bool = true
var fps_samples: Array[float] = []
var sample_clock: float = 0.0
var option_clock: float = 0.0
var telemetry: FileAccess
var event_file: FileAccess
var marker: ColorRect
var identity_cells: Array[ColorRect] = []
var frame_cells: Array[ColorRect] = []
var status: Label
var final_exit_code: int = 1

func configure(directory: String, request: Dictionary) -> void:
	session = directory
	token = str(request.capture_token)
	identities = request.identity_phases
	initialized_us = Time.get_ticks_usec()
	process_physics_priority = -100
	cases.append({"name":"straight_control","title":"REFERENCE / straight touch-ahead dribbling / ordinary stick", "seconds":6.0,"mode":"straight","amount":0.7,"sprint":false})
	for speed: String in ["walk","jog","sprint"]:
		for degrees: int in [30,60,90]:
			for side: int in [-1,1]:
				cases.append({"name":"%s_%d_%s" % [speed,degrees,"left" if side < 0 else "right"],
					"title":"TURN / %s / %d degrees %s / physical contact only" % [speed,degrees,"left" if side < 0 else "right"],
					"seconds":4.0,"mode":"turn","amount":0.55 if speed=="walk" else 0.8 if speed=="jog" else 1.0,
					"sprint":speed=="sprint","angle":degrees,"side":side})
	for key: String in ["cross_receive","human_run_return","marked_human_better_AI","pressure_backpass","blocked_return_lane"]:
		cases.append({"name":key,"title":"TEAMWORK / "+key.replace("_"," ")+" / ordinary Cross and production AI","seconds":11.0,"mode":"team"})

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	marker = _rect(layer,Vector2(1120,22),Vector2(100,28),PALETTE[0])
	for index: int in range(12):
		identity_cells.append(_rect(layer,Vector2(1120+index*8,58),Vector2(8,12),PALETTE[int(identities[index])]))
		frame_cells.append(_rect(layer,Vector2(1120+index*8,82),Vector2(8,12),PALETTE[0]))
	status = Label.new()
	status.position = Vector2(16,730)
	status.add_theme_font_size_override("font_size",15)
	status.text = "TURNS / TEAMWORK / preflight held / no behavior started"
	layer.add_child(status)
	telemetry = FileAccess.open(session.path_join("telemetry.jsonl"),FileAccess.WRITE)
	event_file = FileAccess.open(session.path_join("events.jsonl"),FileAccess.WRITE)
	source_save_hashes = _original_saves()

func _rect(parent: Node, position: Vector2, size: Vector2, color: Color) -> ColorRect:
	var cell := ColorRect.new()
	cell.position = position
	cell.size = size
	cell.color = color
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(cell)
	return cell

func prepare() -> void:
	await _new_game()
	if finished or not is_instance_valid(game): return
	_setup()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if telemetry == null or event_file == null:
		_infrastructure_failure("Could not open isolated evidence streams.")
		return
	scene_ready = true
	_write("ready.json",{"scene":"turn_teamwork_acceptance","game_ready":true,"capture_token":token,
		"identity_phases":identities,"hwnd":str(DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)),
		"viewport":[1280,800],"marker_rect":[1120,22,100,28],"identity_rect":[1120,58,96,12],"frame_rect":[1120,82,96,12],
		"physics_hz":Engine.physics_ticks_per_second,"max_wall_seconds":MAX_WALL,"planned_stages":cases,
		"executable_path":OS.get_executable_path(),"pack_path":OS.get_executable_path().get_base_dir().path_join("BasedFootball.pck"),
		"fixture_policy":"Initial placements between labelled cases only; stationary defenders are declared lane/marking fixtures. Real production input/AI, contact and free ball physics within each case. No forced decisions, contacts, rescues or retries."})
	print("TURN_TEAMWORK_READY ",token)

func _new_game() -> void:
	if is_instance_valid(game):
		production_logs.append({"case":cases[case_index-1].name,"log":game.action_log.duplicate(true)})
		game.queue_free()
		await get_tree().process_frame
	var scene: PackedScene = load("res://scenes/match.tscn")
	if scene == null:
		_infrastructure_failure("Production match scene is missing.")
		return
	var career: String = session.path_join(str(cases[case_index].name)+"-squad.json")
	if FileAccess.file_exists(career) or FileAccess.file_exists(career+".tmp"):
		_infrastructure_failure("Refusing to reuse an isolated fixture save.")
		return
	game = scene.instantiate() as Node3D
	game.squad.save_path = career
	game.decision_driver = self
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	# Match clock/restarts are outside this focused fixture; individual player,
	# visual, AI decision, reception and ball physics remain the production code.
	game.set_physics_process(false)
	game.set_process(false)
	game.set_process_unhandled_input(false)
	for player: FootballPlayer in game.players:
		player.freeze = true
		player.intent = Vector3.ZERO
		player.physical_event.connect(_physical.bind(player))
	game.ball.freeze = true
	setup_count += 1

func _setup() -> void:
	var spec: Dictionary = cases[case_index]
	case_metrics = {"name":spec.name,"mode":spec.mode,"max_gap_m":0.0,"free_motion_frames":0,"free_motion_distance_m":0.0,
		"receiver_motion_frame":-1,"assigned_initial_receiver":"","return_contact_frame":-1,"recovery_entries":0,
		"AI_decision_events":0,"blocked_human_observations":0,"finite_physics":true}
	movement = Vector2.ZERO
	sprinting = false
	actions.clear()
	ai_actors.clear()
	contact_receipts.clear()
	dribble_receipts.clear()
	kick_receipts.clear()
	receive_receipts.clear()
	flight_receipts.clear()
	ai_choices.clear()
	last_choice_by_player.clear()
	last_flight_key = ""
	recovering = false
	cross_requested = false
	turn_input_recorded = false
	human_cross_frame = -1
	initial_receive_frame = -1
	first_return_frame = -1
	for index: int in range(game.players.size()):
		var player: FootballPlayer = game.players[index]
		player.global_position = Vector3(-28+float(index)*2,0.025,18 if player.team==0 else -18)
		player.linear_velocity = Vector3.ZERO
		player.angular_velocity = Vector3.ZERO
		player.intent = Vector3.ZERO
		player.sprint = false
		player.aim = Vector3.RIGHT
		player.reset_action()
		player.body_visual.rotation.y = -PI*0.5
	var human: FootballPlayer = game.home_outfield[0]
	game._select(game.players.find(human))
	var start_z: float = -6.0*float(spec.side) if spec.mode=="turn" else 0.0
	human.global_position = Vector3(-9,0.025,start_z)
	if spec.mode=="team":
		human.global_position = Vector3(-8,0.025,-4)
		receiver = game.home_outfield[1]
		alternative = game.home_outfield[2]
		receiver.global_position = Vector3(-2,0.025,-4)
		alternative.global_position = Vector3(-17,0.025,10)
		ai_actors.append(receiver)
		if spec.name in ["marked_human_better_AI","blocked_return_lane","pressure_backpass"]:
			alternative.global_position = Vector3(3,0.025,2)
			ai_actors.append(alternative)
		if spec.name=="marked_human_better_AI":
			game.away_outfield[0].global_position = Vector3(-8,0.025,-3.15)
		elif spec.name=="pressure_backpass":
			game.away_outfield[0].global_position = Vector3(-0.5,0.025,-4)
			game.away_outfield[1].global_position = Vector3(3,0.025,2.85)
		elif spec.name=="blocked_return_lane":
			game.away_outfield[0].global_position = Vector3(-4.7,0.025,-2.9)
			alternative.global_position = Vector3(4,0.025,-8)
		initial_receiver_position = receiver.global_position
	else:
		receiver = null
		alternative = null
	initial_human_position = human.global_position
	game.ball.global_position = human.global_position+Vector3(0.65,FootballBall.RADIUS,0)
	game.ball.linear_velocity = Vector3.ZERO
	game.ball.angular_velocity = Vector3.ZERO
	game.ball.last_touch_id = ""
	game.ball.last_touch_team = -1
	var camera_target: Vector3 = human.global_position+Vector3(0,0.7,0)
	game.camera.size = 16 if spec.mode=="team" else 13 if bool(spec.get("sprint",false)) else 11
	if spec.mode=="team": camera_target = Vector3(-3,0.7,-2)
	game.camera.global_position = camera_target+Vector3(0,13,10)
	game.camera.look_at(camera_target)
	_event("declared_fixture_setup",{"players":_roster(),"ball":_vec(game.ball.global_position),
		"active_AI":ai_actors.map(func(player: FootballPlayer) -> String: return player.player_id),
		"stationary_defenders":"Fixed physical marking/lane fixtures; no opponent decisions in these isolated cases.",
		"match_clock_disabled":true,"initial_positions_only":true})

func _activate() -> void:
	case_start_frame = physics_frames
	game.controlled.freeze = false
	for player: FootballPlayer in ai_actors: player.freeze = false
	game.ball.freeze = false
	last_touch_serial = game.ball.touch_serial
	last_ball_position = game.ball.global_position
	_event("stage_started",cases[case_index])

func _process(delta: float) -> void:
	if marker == null: return
	var elapsed: float = float(Time.get_ticks_usec()-(start_us if started else initialized_us))/1000000.0
	marker.color = PALETTE[int(elapsed*2)%4]
	frame_cells[0].color = PALETTE[2 if finished else 1 if started else 0]
	var counter: int = finish_frame if finished else physics_frames
	for index: int in range(11): frame_cells[index+1].color = PALETTE[(counter>>(index*2))&3]
	if started and not finished:
		fps_samples.append(1.0/maxf(delta,0.000001))
		status.text = str(cases[case_index].title)+(" / next labelled setup" if transitioning else " / %.1fs / %d FPS" % [_case_seconds(),Engine.get_frames_per_second()])
		if not transitioning and cases[case_index].mode!="team":
			var target: Vector3 = game.controlled.global_position+Vector3(0,0.7,0)
			game.camera.global_position = game.camera.global_position.lerp(target+Vector3(0,13,10),minf(1,delta*5))
			game.camera.look_at(target)

func _physics_process(delta: float) -> void:
	if finished:
		var hold: float = float(Time.get_ticks_usec()-finish_us)/1000000.0
		if hold>=1.2 and (_flag("allowexit.flag") or hold>=20): get_tree().quit(final_exit_code)
		return
	if not scene_ready: return
	if not started:
		if _flag("start.flag"):
			started = true
			start_us = Time.get_ticks_usec()
			_write("started.json",{"capture_token":token,"engine_physics_frame":Engine.get_physics_frames(),"system_time_unix":Time.get_unix_time_from_system()})
			get_tree().paused = false
			_activate()
		elif float(Time.get_ticks_usec()-initialized_us)/1000000.0>240:
			_infrastructure_failure("Preflight timed out before behavior.")
		return
	physics_frames += 1
	if transitioning: return
	_drive(delta)
	_monitor(delta)
	sample_clock += delta
	if sample_clock>=0.1:
		sample_clock = fmod(sample_clock,0.1)
		call_deferred("_sample")
	if _case_seconds()>=float(cases[case_index].seconds):
		_finish_case()
		transitioning = true
		call_deferred("_next_case")
	if _wall()>MAX_WALL and not finished: _finish(false,"Safety limit reached; coverage incomplete.")

func _next_case() -> void:
	case_index += 1
	if case_index>=cases.size():
		case_index = cases.size()-1
		_finish(true,"One focused turn and teamwork sequence completed; no full match was requested.")
		return
	await _new_game()
	if finished: return
	_setup()
	# Frozen setup is visible in the continuous recording; the running tree is
	# never paused between cases and no reset relocation counts as contact.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_activate()
	transitioning = false

func decide(_delta: float) -> void:
	# The production match's frame driver is intentionally disabled for fixtures.
	# _drive writes the same ordinary input fields and calls its action method.
	pass

func _drive(delta: float) -> void:
	actions.clear()
	movement = Vector2.ZERO
	sprinting = false
	var spec: Dictionary = cases[case_index]
	var human: FootballPlayer = game.controlled
	var time: float = _case_seconds()
	if spec.mode=="team":
		human.aim = _flat(receiver.global_position-human.global_position).normalized()
		if not cross_requested and time>=0.55:
			cross_requested = true
			movement = Vector2(human.aim.x,human.aim.z)
			actions["pass"] = true
		elif human_cross_frame>=0:
			var target: Vector3 = human.global_position
			if spec.name=="human_run_return": target = Vector3(3.5,0,-0.5)
			elif spec.name=="blocked_return_lane": target = Vector3(-7,0,2)
			var offset: Vector3 = _flat(target-human.global_position)
			if offset.length()>0.45:
				var direction: Vector3 = offset.normalized()
				movement = Vector2(direction.x,direction.z)*minf(1,offset.length())
				sprinting = spec.name=="human_run_return"
			if game.ball.pass_active and game.ball.pass_receiver_id==human.player_id and game.ball.pass_passer_id!=human.player_id:
				var meet: Vector3 = _flat(FootballReception.interception_point(human,game.ball)-human.global_position)
				var incoming: Vector3 = _flat(game.ball.linear_velocity)
				var desired: Vector3 = (incoming*0.35+meet*2).limit_length(human.pace*0.65) if human.global_position.distance_to(game.ball.global_position)<1.6 else meet.normalized()*minf(meet.length()*2,human.pace)
				var base_speed: float = human.pace if meet.length()>2.4 else human.pace*0.66
				movement = Vector2(desired.x,desired.z)/maxf(base_speed,0.1)
				sprinting = meet.length()>2.4
			if first_return_frame>=0:
				movement = Vector2.ZERO
				sprinting = false
	else:
		var direction: Vector3 = Vector3.RIGHT
		if spec.mode=="turn" and time>=1.0:
			direction = Vector3(cos(deg_to_rad(float(spec.angle))),0,float(spec.side)*sin(deg_to_rad(float(spec.angle))))
			if not turn_input_recorded:
				turn_input_recorded = true
				_event("ordinary_turn_input",{"requested_direction":_vec(direction),"angle_degrees":spec.angle,"side":spec.side,"touch_serial":game.ball.touch_serial,"incoming_ball_velocity":_vec(game.ball.linear_velocity)})
		var moving_until: float = 4.2 if spec.mode=="straight" else 2.9
		if time<moving_until:
			var gap: float = _flat(game.ball.global_position-human.global_position).length()
			if not recovering and gap>1.05:
				recovering = true
				case_metrics.recovery_entries = int(case_metrics.recovery_entries)+1
				_event("tester_recovery_entered",{"gap":gap,"exit_gap":0.7})
			if recovering and gap<=0.7:
				recovering = false
				_event("tester_recovery_completed",{"gap":gap})
			if recovering: direction = _flat(game.ball.global_position+game.ball.linear_velocity*0.1-human.global_position).normalized()
			movement = Vector2(direction.x,direction.z)*float(spec.amount)
			sprinting = bool(spec.sprint)
	human.intent = Vector3(movement.x,0,movement.y)
	human.sprint = sprinting
	if movement.length_squared()>0.0025: human.aim = human.intent.normalized()
	game._controller_actions(delta,actions)
	game.reception.update(game,delta)
	for player: FootballPlayer in ai_actors: FootballAI.decide(player,game.players,game.ball,delta)
	game._control_ball()

func _monitor(delta: float) -> void:
	var human: FootballPlayer = game.controlled
	var ball: FootballBall = game.ball
	var valid: bool = ball.global_position.is_finite() and ball.linear_velocity.is_finite()
	for player: FootballPlayer in game.players: valid = valid and player.global_position.is_finite() and player.linear_velocity.is_finite()
	finite_physics = finite_physics and valid
	case_metrics.finite_physics = bool(case_metrics.finite_physics) and valid
	case_metrics.max_gap_m = maxf(float(case_metrics.max_gap_m),_flat(ball.global_position-human.global_position).length())
	if ball.touch_serial==last_touch_serial and ball.linear_velocity.length()>0.3 and not dribble_receipts.is_empty():
		case_metrics.free_motion_frames = int(case_metrics.free_motion_frames)+1
		case_metrics.free_motion_distance_m = float(case_metrics.free_motion_distance_m)+ball.global_position.distance_to(last_ball_position)
	last_touch_serial = ball.touch_serial
	last_ball_position = ball.global_position
	if ball.pass_active:
		var key: String = "%d/%s/%s" % [ball.touch_serial,ball.pass_passer_id,ball.pass_receiver_id]
		if key!=last_flight_key:
			last_flight_key = key
			var flight: Dictionary = {"physics_frames":physics_frames,"case_seconds":_case_seconds(),"passer":ball.pass_passer_id,"receiver":ball.pass_receiver_id,"serial":ball.touch_serial,"velocity":_vec(ball.linear_velocity),"target":_vec(ball.pass_target)}
			flight_receipts.append(flight)
			if ball.pass_passer_id==human.player_id: case_metrics.assigned_initial_receiver = ball.pass_receiver_id
			_event("observed_real_pass_flight",flight)
	if is_instance_valid(receiver) and cases[case_index].mode=="team":
		if ball.pass_active and ball.pass_receiver_id==receiver.player_id and human_cross_frame>=0 and int(case_metrics.receiver_motion_frame)<0 and _flat(receiver.global_position-initial_receiver_position).length()>0.12 and _flat(receiver.linear_velocity).length()>0.15 and _flat(ball.global_position-receiver.global_position).length()>1:
			case_metrics.receiver_motion_frame = physics_frames
		option_clock += delta
		if option_clock>=0.1:
			option_clock = fmod(option_clock,0.1)
			var options: Dictionary = FootballAI.evaluate_options(receiver,game.players,ball)
			case_metrics.latest_options = options
			if initial_receive_frame>=0 and bool(options.get("strike_reachable",false)):
				for candidate: Dictionary in options.get("candidates",[]):
					if str(candidate.get("receiver_id",""))==human.player_id and not bool(candidate.get("eligible",true)) and str(candidate.get("reason",""))=="blocked_lane":
						case_metrics.blocked_human_observations = int(case_metrics.blocked_human_observations)+1

func _physical(kind: String, detail: Dictionary, player: FootballPlayer) -> void:
	if not started or transitioning or finished: return
	var receipt: Dictionary = detail.duplicate(true)
	receipt.merge({"physics_frames":physics_frames,"engine_physics_frame":Engine.get_physics_frames(),"case_seconds":_case_seconds(),"player":player.player_id,"team":player.team},true)
	receipt.test_recovering = recovering
	receipt.test_raw_stick = [movement.x,movement.y]
	if cases[case_index].mode=="turn":
		var spec: Dictionary = cases[case_index]
		receipt.test_requested_turn_direction = [cos(deg_to_rad(float(spec.angle))),0,float(spec.side)*sin(deg_to_rad(float(spec.angle)))]
	if kind in ["dribble_touch","kick_contact","receive_contact"]:
		contact_receipts[int(detail.get("touch_serial",game.ball.touch_serial))] = receipt.duplicate(true)
	if kind=="dribble_touch":
		receipt.last_AI_choice = last_choice_by_player.get(player.player_id,{}).duplicate(true)
		dribble_receipts.append(receipt.duplicate(true))
	elif kind=="kick_contact":
		receipt.human_position = _vec(game.controlled.global_position)
		receipt.human_velocity = _vec(game.controlled.linear_velocity)
		receipt.kicker_position = _vec(player.global_position)
		receipt.nearest_opponent_m = _nearest_opponent(player)
		receipt.last_AI_choice = last_choice_by_player.get(player.player_id,{}).duplicate(true)
		kick_receipts.append(receipt.duplicate(true))
		if player==game.controlled and str(detail.get("kind",""))=="pass": human_cross_frame = physics_frames
	elif kind=="receive_contact":
		receive_receipts.append(receipt.duplicate(true))
		if player==receiver and str(detail.get("passer",""))==game.controlled.player_id and initial_receive_frame<0:
			initial_receive_frame = physics_frames
		if player==game.controlled and is_instance_valid(receiver) and str(detail.get("passer",""))==receiver.player_id:
			first_return_frame = physics_frames
			case_metrics.return_contact_frame = physics_frames
	elif kind=="ai_decision":
		ai_choices.append(receipt.duplicate(true))
		last_choice_by_player[player.player_id] = receipt.duplicate(true)
		case_metrics.AI_decision_events = int(case_metrics.AI_decision_events)+1
	_event(kind,receipt)

func _finish_case() -> void:
	var spec: Dictionary = cases[case_index]
	var human: FootballPlayer = game.controlled
	var ledger_mismatches: Array[Dictionary] = []
	for entry: Dictionary in game.ball.impulse_audit:
		var receipt: Dictionary = contact_receipts.get(int(entry.serial),{})
		var impulse: Vector3 = _from_vec(receipt.get("impulse",receipt.get("applied_impulse",[])))
		if receipt.is_empty() or str(entry.player_id)!=str(receipt.get("player","")) or _from_vec(entry.impulse).distance_to(impulse)>0.00001: ledger_mismatches.append(entry.duplicate(true))
	case_metrics.merge({"spec":spec,"dribble_receipts":dribble_receipts.duplicate(true),"kick_receipts":kick_receipts.duplicate(true),
		"receive_receipts":receive_receipts.duplicate(true),"flight_receipts":flight_receipts.duplicate(true),"AI_choices":ai_choices.duplicate(true),
		"ledger_mismatches":ledger_mismatches,"actual_impulse_ledger":game.ball.impulse_audit.duplicate(true)},true)
	var passed: bool = bool(case_metrics.finite_physics) and ledger_mismatches.is_empty()
	if spec.mode in ["straight","turn"]:
		var feet: Dictionary = {}
		var pushes_before: int = 0
		var steering: Array[Dictionary] = []
		var recovery_steering: Array[Dictionary] = []
		var recovery_contacts: int = 0
		var last_steer_frame: int = -1
		for receipt: Dictionary in dribble_receipts:
			if str(receipt.player)!=human.player_id: continue
			feet[str(receipt.get("foot","unknown"))] = true
			if float(receipt.case_seconds)<1 and not bool(receipt.get("trap",false)): pushes_before += 1
			if spec.mode=="turn" and float(receipt.case_seconds)>=1 and float(receipt.case_seconds)<2.9 and bool(receipt.get("steer",false)):
				var alignment: float = _flat(_from_vec(receipt.get("turn_aim",[]))).normalized().dot(_from_vec(receipt.get("test_requested_turn_direction",[])).normalized())
				if not bool(receipt.get("test_recovering",false)) and alignment>=0.985:
					steering.append(receipt)
					last_steer_frame = int(receipt.physics_frames)
				else:
					recovery_steering.append(receipt)
			elif last_steer_frame>=0 and int(receipt.physics_frames)>last_steer_frame: recovery_contacts += 1
		case_metrics.merge({"actual_feet":feet.keys(),"pre_turn_pushes":pushes_before,"steering_contacts":steering,"recovery_direction_steering_contacts":recovery_steering,"steering_coverage":not steering.is_empty(),"later_actual_recovery_contacts":recovery_contacts},true)
		if spec.mode=="straight":
			passed = passed and dribble_receipts.size()>=3 and feet.has("left") and feet.has("right") and int(case_metrics.free_motion_frames)>=30
		else:
			var bounded_rotation: bool = not steering.is_empty()
			var angle_reduced: bool = false
			for receipt: Dictionary in steering:
				bounded_rotation = bounded_rotation and absf(float(receipt.get("steering_rotation_deg",999)))<=20.001 and float(receipt.get("contact_gap",999))<=FootballBall.RADIUS+0.12
				angle_reduced = angle_reduced or float(receipt.get("turn_angle_after_deg",999))+2<float(receipt.get("turn_angle_before_deg",0))
			case_metrics.merge({"bounded_contact_rotation":bounded_rotation,"angle_reduced_at_real_contact":angle_reduced,"unexercised_is_not_a_pass":steering.is_empty()},true)
			passed = passed and pushes_before>0 and not steering.is_empty() and bounded_rotation and angle_reduced and recovery_contacts>0 and int(case_metrics.free_motion_frames)>10
	else:
		var received_initial: bool = initial_receive_frame>human_cross_frame and human_cross_frame>=0
		var AI_to_human: bool = _real_delivery(receiver.player_id,human.player_id)
		var AI_to_alternative: bool = _real_delivery(receiver.player_id,alternative.player_id)
		case_metrics.merge({"human_cross_frame":human_cross_frame,"initial_receive_frame":initial_receive_frame,"real_initial_reception":received_initial,
			"real_AI_to_human_delivery":AI_to_human,"real_AI_to_alternative_delivery":AI_to_alternative},true)
		passed = passed and received_initial and str(case_metrics.assigned_initial_receiver)==receiver.player_id
		if spec.name=="cross_receive":
			passed = passed and int(case_metrics.receiver_motion_frame)>=0 and int(case_metrics.receiver_motion_frame)<initial_receive_frame
		elif spec.name=="human_run_return":
			var moving_at_return: bool = false
			for kick: Dictionary in kick_receipts:
				if str(kick.player)==receiver.player_id and _kick_targets(kick,human.player_id) and _flat(_from_vec(kick.get("human_velocity",[]))).length()>1 and _flat(_from_vec(kick.get("human_position",[]))-initial_human_position).length()>1: moving_at_return = true
			case_metrics.human_moving_at_AI_contact = moving_at_return
			passed = passed and AI_to_human and first_return_frame>=0 and moving_at_return
		elif spec.name=="marked_human_better_AI":
			passed = passed and AI_to_alternative and _received_from(alternative.player_id,receiver.player_id)
		elif spec.name=="pressure_backpass":
			var backward_under_pressure: bool = false
			for kick: Dictionary in kick_receipts:
				if str(kick.player)==receiver.player_id and _kick_targets(kick,human.player_id) and float(kick.get("nearest_opponent_m",999))<2.1 and _from_vec(kick.get("human_position",[])).x<_from_vec(kick.get("kicker_position",[])).x-1 and _from_vec(kick.get("aim_direction",[])).x<0: backward_under_pressure = true
			case_metrics.backward_contact_under_pressure = backward_under_pressure
			passed = passed and AI_to_human and first_return_frame>=0 and backward_under_pressure
		elif spec.name=="blocked_return_lane":
			var safe_carry: bool = false
			var safe_alternative: bool = false
			for receipt: Dictionary in dribble_receipts:
				var choice: Dictionary = receipt.get("last_AI_choice",{})
				if str(receipt.player)==receiver.player_id and int(receipt.physics_frames)>initial_receive_frame and not bool(receipt.get("trap",false)) and str(choice.get("action",""))=="carry" and _human_lane_blocked(choice,human.player_id): safe_carry = true
			for kick: Dictionary in kick_receipts:
				if str(kick.player)==receiver.player_id and _kick_targets(kick,alternative.player_id) and _human_lane_blocked(kick.get("last_AI_choice",{}),human.player_id): safe_alternative = true
			case_metrics.merge({"safe_actual_carry_touch":safe_carry,"safe_alternative_contact_while_human_blocked":safe_alternative},true)
			# A later return after the human's lane opens is legal. Only the
			# observed decision at a blocked lane is assessed here.
			passed = passed and int(case_metrics.blocked_human_observations)>0 and (safe_alternative or safe_carry)
	case_metrics["pass"] = passed
	case_metrics.first_physics_frame = case_start_frame
	case_metrics.last_physics_frame = physics_frames
	case_metrics.sim_seconds = _case_seconds()
	case_results.append(case_metrics.duplicate(true))
	_event("stage_finished",case_metrics)

func _real_delivery(passer: String, to: String) -> bool:
	for flight: Dictionary in flight_receipts:
		if str(flight.passer)!=passer or str(flight.receiver)!=to: continue
		for kick: Dictionary in kick_receipts:
			if str(kick.player)==passer and int(kick.get("touch_serial",-1))==int(flight.serial) and str(kick.get("kind","")) in ["pass","through","lob"]: return true
	return false

func _received_from(to: String, passer: String) -> bool:
	for receipt: Dictionary in receive_receipts:
		if str(receipt.player)==to and str(receipt.get("passer",""))==passer: return true
	return false

func _kick_targets(kick: Dictionary, to: String) -> bool:
	for flight: Dictionary in flight_receipts:
		if str(flight.passer)==str(kick.player) and str(flight.receiver)==to and int(flight.serial)==int(kick.get("touch_serial",-1)): return true
	return false

func _human_lane_blocked(choice: Dictionary, human_id: String) -> bool:
	for option: Dictionary in choice.get("candidates",[]):
		if str(option.get("receiver_id",""))==human_id and not bool(option.get("eligible",true)) and str(option.get("reason",""))=="blocked_lane": return true
	return false

func _nearest_opponent(player: FootballPlayer) -> float:
	var distance: float = INF
	for other: FootballPlayer in game.players:
		if other.team!=player.team: distance = minf(distance,_flat(other.global_position-player.global_position).length())
	return distance

func _sample() -> void:
	if finished or transitioning or telemetry==null or not is_instance_valid(game): return
	telemetry.store_line(JSON.stringify({"case":cases[case_index].name,"physics_frames":physics_frames,"engine_physics_frame":Engine.get_physics_frames(),
		"sim_seconds":float(physics_frames)/Engine.physics_ticks_per_second,"case_seconds":_case_seconds(),"wall_seconds":_wall(),"fps":Engine.get_frames_per_second(),
		"players":_roster(),"ball":{"position":_vec(game.ball.global_position),"velocity":_vec(game.ball.linear_velocity),"touch_serial":game.ball.touch_serial,
			"last_touch_id":game.ball.last_touch_id,"pass_active":game.ball.pass_active,"passer":game.ball.pass_passer_id,"receiver":game.ball.pass_receiver_id,"pass_end_reason":game.ball.pass_end_reason},
		"input":{"movement":[movement.x,movement.y],"sprint":sprinting,"actions":actions,"recovering":recovering},"metrics":case_metrics}))
	telemetry.flush()

func _roster() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for player: FootballPlayer in game.players:
		rows.append({"id":player.player_id,"team":player.team,"position":_vec(player.global_position),"velocity":_vec(player.linear_velocity),
			"frozen_fixture":player.freeze,"action":player.action_kind,"dribble_phase":player.dribble_phase,"receiving":player.receiving_active,
			"control_reason":player.last_control_reason,"boot_gap":player.last_control_boot_gap,"last_received_from":player.last_received_from,"last_received_frame":player.last_received_frame})
	return rows

func _finish(complete: bool, reason: String) -> void:
	if finished: return
	finished = true
	finish_us = Time.get_ticks_usec()
	finish_frame = physics_frames
	var checks: Dictionary = {"sequence_complete":complete and case_results.size()==cases.size(),"finite_physics":finite_physics,"original_saves_unchanged":source_save_hashes==_original_saves()}
	for result: Dictionary in case_results: checks[str(result.name)] = bool(result.get("pass",false))
	var passed: bool = true
	for value: bool in checks.values(): passed = passed and value
	final_exit_code = 0 if passed else 1
	_event("verification_finished",{"checks":checks,"reason":reason})
	if telemetry!=null: telemetry.close()
	if event_file!=null: event_file.close()
	telemetry = null
	event_file = null
	if is_instance_valid(game): production_logs.append({"case":cases[case_index].name,"log":game.action_log.duplicate(true)})
	var sorted_fps: Array[float] = fps_samples.duplicate()
	sorted_fps.sort()
	_write("events.json",{"stages":case_results,"production_logs":production_logs})
	_write("result.json",{"schema":"turn-teamwork-acceptance/v1","capture_token":token,"pass":passed,"sequence_complete":complete,
		"physics_frames":finish_frame,"sim_seconds":float(finish_frame)/Engine.physics_ticks_per_second,"wall_seconds":_wall(),
		"checks":checks,"stages":case_results,"labelled_fixture_setups":setup_count,"same_case_rescues":0,"retries":0,
		"median_fps":sorted_fps[sorted_fps.size()/2] if not sorted_fps.is_empty() else 0,"reason":reason,
		"original_saves_before":source_save_hashes,"original_saves_after":_original_saves(),"user_data_dir":OS.get_user_data_dir(),
		"full_match_requested":false,"hardware_controller_verified":false,"subjective_fun_verified":false,
		"limitations":["These are labelled focused fixtures, not a normal full match. Individual production physics/actions/AI/reception run; match clock and restarts are disabled.",
			"Stationary defenders are disclosed physical lane/marking fixtures. No AI choice, successful contact or receiver identity is injected.",
			"Unreached sharp-turn balls remain failed/unexercised steering coverage, even when the miss is physically legitimate.",
			"Actual ball.touch receipts/ledger and source freeze support the contact-only dribbling claim; native engine forces are not globally intercepted. Environment collisions and rolling remain expected.",
			"Numeric coverage does not certify natural animation, controller hardware or subjective fun; actual uninterrupted footage must be reviewed."]})
	_write("finished.json",{"capture_token":token,"physics_frames":finish_frame,"sequence_complete":complete,"pass":passed})
	status.text = "TURNS / TEAMWORK FINISHED / acceptance %s / actual evidence preserved" % ("PASS" if passed else "FAIL")
	print("TURN_TEAMWORK_FINISHED ",JSON.stringify(checks))

func _original_saves() -> Dictionary:
	var root: String = OS.get_environment("APPDATA")
	var hashes: Dictionary = {}
	for name: String in ["BasedFootball-KeeperPreview/squad.json","BasedFootball-Recovered-3v3/squad.json","Godot/app_userdata/Based Football/squad.json"]:
		var file: String = root.path_join(name)
		hashes[file] = FileAccess.get_sha256(file) if FileAccess.file_exists(file) else "absent"
	return hashes

func _event(kind: String, detail: Dictionary) -> void:
	if event_file==null: return
	event_file.store_line(JSON.stringify({"kind":kind,"case":cases[case_index].name,"physics_frames":physics_frames,
		"sim_seconds":float(physics_frames)/Engine.physics_ticks_per_second,"case_seconds":_case_seconds(),"wall_seconds":_wall(),"detail":detail}))
	event_file.flush()

func _flag(name: String) -> bool:
	var file: String = session.path_join(name)
	if not FileAccess.file_exists(file): return false
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	return value is Dictionary and str(value.get("capture_token",""))==token

func _write(name: String, value: Dictionary) -> void:
	var output: FileAccess = FileAccess.open(session.path_join(name),FileAccess.WRITE)
	if output!=null: output.store_string(JSON.stringify(value,"\t"))

func _infrastructure_failure(reason: String) -> void:
	_write("infrastructure-error.json",{"capture_token":token,"reason":reason,"behavior_started":started})
	finished = true
	get_tree().quit(2)

func _case_seconds() -> float:
	return float(physics_frames-case_start_frame)/Engine.physics_ticks_per_second

func _wall() -> float:
	return float((finish_us if finished and finish_us>0 else Time.get_ticks_usec())-start_us)/1000000.0 if started else 0.0

func _flat(value: Vector3) -> Vector3:
	return value*Vector3(1,0,1)

func _vec(value: Vector3) -> Array[float]:
	return [value.x,value.y,value.z]

func _from_vec(value: Variant) -> Vector3:
	if value is Vector3: return value
	if value is Array and value.size()==3: return Vector3(float(value[0]),float(value[1]),float(value[2]))
	return Vector3.ZERO
