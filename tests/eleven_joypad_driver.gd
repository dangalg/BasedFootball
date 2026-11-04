extends Node

## Test player for a normal 11v11 match. Observe the pitch and emit mapped
## joypad events. The match owns every action, restart and physical contact.

const THINK_SECONDS := 0.11
const SHOT_HOLD_SECONDS := 0.21
const DEVICE := 0

var game: Node3D
var decisions := 0
var joy_events := 0
var inputs: Array[Dictionary] = []

var _axes: Dictionary = {}
var _buttons: Dictionary = {}
var _pulses: Array[int] = []
var _think_in := 0.0
var _pass_in := 0.0
var _switch_in := 0.0
var _shot_in := -1.0
var _shot_aim := Vector3.ZERO
var _restart_shot := false


func configure(match_node: Node3D) -> void:
	game = match_node
	process_physics_priority = -100


func release_input() -> void:
	for button: int in _buttons.keys():
		_button(button, false)
	for axis: int in _axes.keys():
		_axis(axis, 0.0)
	_pulses.clear()
	_shot_in = -1.0
	Input.flush_buffered_events()


func _physics_process(delta: float) -> void:
	for button in _pulses:
		_button(button, false)
	_pulses.clear()
	_tick_input(delta)
	Input.flush_buffered_events()


func _tick_input(delta: float) -> void:
	if game.phase != "playing" or game.kickoff_remaining > 0.0 or is_instance_valid(game.kickoff_taker):
		_move(Vector3.ZERO)
		_pressure(false)
		_cancel_shot()
		return
	_think_in -= delta
	_switch_in -= delta
	_pass_in -= delta
	var restart: Dictionary = game.restart
	if _shot_in >= 0.0:
		if restart.is_empty() == _restart_shot:
			_cancel_shot()
		else:
			_shot_in -= delta
			if _shot_in <= 0.0:
				_move(_shot_aim * (0.75 if restart.is_empty() else 1.0))
				_button(JOY_BUTTON_B, false)
				_shot_in = -1.0
				_think_in = THINK_SECONDS
			return
	if _think_in > 0.0:
		return
	_think_in = THINK_SECONDS
	decisions += 1
	if not restart.is_empty():
		_play_restart(restart)
		return
	_play_open_ball()


func _play_restart(restart: Dictionary) -> void:
	_pressure(false)
	var manual_defender: FootballPlayer = restart.get("manual_defender")
	if is_instance_valid(manual_defender):
		var wall: ElevenWall = restart.wall
		var away := FootballReception.flat(manual_defender.global_position - wall.spot)
		_move(away.normalized() if away.length() < ElevenWall.MIN_DISTANCE + 0.55 else Vector3.ZERO)
		return
	_move(Vector3.ZERO)
	if not bool(restart.human) or restart.has("attendant") or restart.has("throw_direction") or bool(restart.get("strike_requested", false)):
		return
	if restart.has("wall") and not bool(restart.get("wall_ready", false)):
		return
	var taker: FootballPlayer = restart.taker
	var goal := _goal(taker)
	if restart.kind == "penalty" or (restart.kind == "direct_free_kick" and goal.distance_to(game.ball.global_position) < 23.0):
		_start_shot(FootballReception.flat(goal - game.ball.global_position).normalized(), true)
	else:
		_pulse(JOY_BUTTON_A, "restart_pass")


func _play_open_ball() -> void:
	var actor: FootballPlayer = game.controlled
	var ball: FootballBall = game.ball
	var approach := FootballReception.flat(ball.global_position - actor.global_position)
	var gap := approach.length()
	var defending := ball.last_touch_team == 1
	var held := not ball.grip_holder_id.is_empty()
	_pressure(defending and not held and gap < 22.0)
	if gap > 2.4 and _switch_in <= 0.0 and _try_switch(actor, ball, gap):
		_move(Vector3.ZERO)
		return
	var chase := approach + FootballReception.flat(ball.linear_velocity).limit_length(12.0) * 0.13
	var chase_input := chase.normalized() * clampf((gap - 0.32) * 1.75, 0.27, 1.0)
	if held:
		var homeward := FootballReception.flat(actor.eleven_home - actor.global_position)
		_move(homeward.normalized() * clampf(homeward.length() * 0.20, 0.0, 0.72))
		return
	if defending:
		_move(chase.normalized(), gap > 3.2, gap < 2.6)
		if gap < 1.05 and ball.global_position.y < 0.35 and actor.upright_ready() and actor.tackle_cooldown <= 0.0:
			_pulse(JOY_BUTTON_B, "tackle")
		return
	var playable: bool = gap < 1.5 and game._attacking_contact()
	var carrying := actor.chasing_ball(ball)
	var receiving := ball.pass_active and ball.pass_receiver_id == actor.player_id and gap < 1.55 and ball.global_position.y < 0.55
	if not playable and not carrying and not receiving:
		_move(chase_input, gap > 3.2)
		return
	var goal_offset := FootballReception.flat(_goal(actor) - ball.global_position)
	var goal_distance := goal_offset.length()
	var forward := goal_offset.normalized()
	var can_release: bool = actor.kick_cooldown <= 0.0 and actor.upright_ready() and game.shot_buffer_remaining <= 0.0
	var shot_window := playable or receiving or (carrying and gap < 1.15)
	if can_release and shot_window and goal_distance < 26.0 and forward.x * actor.attack_sign() > 0.58:
		_move(chase_input)
		_start_shot(forward, false, lerpf(0.16, 0.29, clampf((goal_distance - 6.0) / 20.0, 0.0, 1.0)))
		return
	if not playable and gap > 0.95:
		_move(chase_input)
		return
	var pressure := _nearest_opponent(ball.global_position)
	var defender := FootballReception.flat(pressure.global_position - ball.global_position) if pressure != null else Vector3.ZERO
	var pressure_gap := defender.length() if pressure != null else INF
	var side := forward.cross(Vector3.UP)
	var lane_blocked := pressure_gap < 5.2 and defender.dot(forward) > 0.0 and absf(defender.dot(side)) < 1.55
	if playable and can_release and _pass_in <= 0.0 and (lane_blocked or pressure_gap < 2.4):
		var lane := _pass_lane(actor, ball, pressure_gap < 1.8)
		if lane != Vector3.ZERO:
			_move(lane * 0.85)
			_pulse(JOY_BUTTON_A, "pass")
			_pass_in = 1.2
			return
	if lane_blocked:
		var dodge := -signf(defender.dot(side))
		if is_zero_approx(dodge):
			dodge = -1.0 if side.z * actor.global_position.z > 0.0 else 1.0
		forward = (forward + side * dodge * 0.58).normalized()
	_move(forward * (0.76 if lane_blocked else 0.90))


func _try_switch(actor: FootballPlayer, ball: FootballBall, gap: float) -> bool:
	if actor.chasing_ball(ball):
		return false
	var intercept := ball.global_position + FootballReception.flat(ball.linear_velocity).limit_length(12.0) * 0.22
	for teammate: FootballPlayer in game.home_outfield:
		if teammate == actor or teammate.ragdoll != null:
			continue
		var distance := FootballReception.flat(intercept - teammate.global_position).length()
		if distance + 1.35 < gap:
			_pulse(JOY_BUTTON_LEFT_SHOULDER, "switch")
			_switch_in = 0.70
			return true
	return false


func _pass_lane(actor: FootballPlayer, ball: FootballBall, allow_relief: bool) -> Vector3:
	var best := -INF
	var lane := Vector3.ZERO
	var attack := actor.attack_sign()
	var line := ElevenOffside.line(game.players, actor.team, attack, ball.global_position.x)
	for teammate: FootballPlayer in game.home_outfield:
		if teammate == actor or teammate.ragdoll != null or ElevenOffside.beyond(teammate, attack, line):
			continue
		var relative := FootballReception.flat(teammate.global_position - ball.global_position)
		var distance := relative.length()
		var progress := relative.x * attack
		if distance < 3.0 or distance > 17.0 or progress < (-5.0 if allow_relief else 1.5):
			continue
		var direction := (relative + FootballReception.flat(teammate.linear_velocity).limit_length(3.0) * 0.32).normalized()
		var clearance := 4.0
		for opponent: FootballPlayer in game.away_outfield:
			var offset := FootballReception.flat(opponent.global_position - ball.global_position)
			var projection := clampf(offset.dot(direction), 0.45, distance)
			clearance = minf(clearance, (offset - direction * projection).length())
		if clearance < 1.05:
			continue
		var score := clearance * 1.7 + clampf(progress, -5.0, 12.0) * 0.72 - distance * 0.12
		if score > best:
			best = score
			lane = direction
	return lane


func _nearest_opponent(point: Vector3) -> FootballPlayer:
	var nearest: FootballPlayer = null
	var gap := INF
	for opponent: FootballPlayer in game.away_outfield:
		var distance := FootballReception.flat(opponent.global_position - point).length_squared()
		if distance < gap:
			nearest = opponent
			gap = distance
	return nearest


func _goal(actor: FootballPlayer) -> Vector3:
	var keeper: FootballPlayer = game.keepers[1]
	var far_side := -signf(keeper.global_position.z)
	if far_side == 0.0:
		far_side = -1.0 if actor.global_position.z > 0.0 else 1.0
	return Vector3(ElevenPitch.HALF_LENGTH * actor.attack_sign(), 0.0, far_side * 2.2)


func _start_shot(direction: Vector3, at_restart: bool, hold := SHOT_HOLD_SECONDS) -> void:
	_shot_aim = direction
	_shot_in = hold
	_restart_shot = at_restart
	_button(JOY_BUTTON_B, true, "restart_shot" if at_restart else "shoot")


func _cancel_shot() -> void:
	if _shot_in >= 0.0:
		_button(JOY_BUTTON_B, false)
		_shot_in = -1.0


func _pressure(enabled: bool) -> void:
	_button(JOY_BUTTON_DPAD_DOWN, enabled, "teammate_press")


func _move(direction: Vector3, sprint := false, jockey := false) -> void:
	_axis(JOY_AXIS_LEFT_X, direction.x)
	_axis(JOY_AXIS_LEFT_Y, direction.z)
	if _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0 if sprint else 0.0):
		_receipt("sprint", sprint)
	if _axis(JOY_AXIS_TRIGGER_LEFT, 1.0 if jockey else 0.0):
		_receipt("jockey", jockey)


func _pulse(button: int, action: String) -> void:
	_button(button, true, action)
	_pulses.append(button)


func _axis(axis: int, value: float) -> bool:
	if absf(float(_axes.get(axis, 0.0)) - value) < 0.01:
		return false
	_axes[axis] = value
	var event := InputEventJoypadMotion.new()
	event.device = DEVICE
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	joy_events += 1
	return true


func _button(button: int, pressed: bool, action := "") -> void:
	if pressed == _buttons.has(button):
		return
	var event := InputEventJoypadButton.new()
	event.device = DEVICE
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	joy_events += 1
	if pressed:
		_buttons[button] = action
	else:
		action = _buttons[button]
		_buttons.erase(button)
	_receipt(action, pressed)


func _receipt(action: String, pressed: bool) -> void:
	var actor: FootballPlayer = game.controlled
	var ball: FootballBall = game.ball
	var restart: String = game.restart.get("kind", "")
	inputs.append({
		"action": action, "pressed": pressed, "frame": Engine.get_physics_frames(),
		"time": snappedf(float(game.match_duration) - float(game.remaining), 0.01),
		"serial": ball.touch_serial, "player": actor.player_id,
		"ball": [ball.global_position.x, ball.global_position.y, ball.global_position.z],
		"attack_sign": actor.attack_sign(),
		"restart": restart, "defend": ball.last_touch_team == 1,
		"live": restart.is_empty() and game.phase == "playing" and game.kickoff_remaining <= 0.0 and not is_instance_valid(game.kickoff_taker),
	})
