class_name ElevenReferee
extends Node3D

const PACE := 3.9
const STRIDE := 1.62
const THIGH_LENGTH := 0.41
const SHIN_LENGTH := 0.40
const SIGHT_RANGE := 27.0

var signal_kind := "play"
var card_color := ""
var _velocity := Vector3.ZERO
var _last_ball := Vector3.ZERO
var _has_ball_sample := false
var _ball_speed_x := 0.0
var _trail_sign := 1.0
var _flank := 1.0
var _signal_direction := Vector3.RIGHT
var _signal_spot := Vector3.ZERO
var _signal_raised := false
var _signal_weight := 0.0
var _phase := 0.0
var _torso: Node3D
var _signal_label: Label3D
var _card: MeshInstance3D
var _yellow_card: Material
var _red_card: Material
var _arms: Array[Node3D] = []
var _elbows: Array[Node3D] = []
var _thighs: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _boots: Array[Node3D] = []


func _ready() -> void:
	var black := FootballArt.material(Color("22272b"))
	var shorts := FootballArt.material(Color("151a1e"))
	var trim := FootballArt.material(Color("f4d363"))
	var skin := FootballArt.material(Color("a87555"))
	var hair := FootballArt.material(Color("2e251f"))
	FootballArt.contact_shadow(self, 1.1)
	_signal_label = FootballArt.text(self, "REF", Vector3(0.0, 2.10, 0.0), 28, Color("edf5ec"))
	_signal_label.pixel_size = 0.025
	_signal_label.outline_size = 6
	_signal_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_signal_label.hide()
	_torso = _joint(self, Vector3(0.0, 0.75, 0.0))
	FootballArt.tailored_mesh(_torso, [Vector3(0, 0.16, 0.10), Vector3(0.16, 0.18, 0.105),
		Vector3(0.44, 0.22, 0.11), Vector3(0.51, 0.18, 0.095), Vector3(0.54, 0.07, 0.06)], black)
	FootballArt.box(_torso, Vector3(0.18, 0.04, 0.01), Vector3(0.0, 0.43, -0.11), trim)
	FootballArt.cylinder(_torso, 0.046, 0.12, Vector3(0.0, 0.57, 0.0), skin)
	FootballArt.sphere(_torso, 0.121, Vector3(0.0, 0.72, 0.0), skin).scale = Vector3(0.91, 1.08, 0.95)
	FootballArt.sphere(_torso, 0.12, Vector3(0.0, 0.785, 0.014), hair).scale = Vector3(0.96, 0.58, 0.98)
	FootballArt.sphere(_torso, 0.024, Vector3(0.0, 0.71, -0.114), skin)
	for side: float in [-1.0, 1.0]:
		var arm := _joint(_torso, Vector3(side * 0.225, 0.455, 0.0))
		FootballArt.capsule(arm, 0.049, 0.25, Vector3(0.0, -0.13, 0.0), skin)
		FootballArt.capsule(arm, 0.061, 0.16, Vector3(0.0, -0.075, 0.0), black)
		FootballArt.cylinder(arm, 0.058, 0.027, Vector3(0.0, -0.135, 0.0), trim)
		var elbow := _joint(arm, Vector3(0.0, -0.25, 0.0))
		FootballArt.capsule(elbow, 0.042, 0.23, Vector3(0.0, -0.11, 0.0), skin)
		FootballArt.sphere(elbow, 0.045, Vector3(0.0, -0.23, 0.0), skin)
		_arms.append(arm)
		_elbows.append(elbow)
		var thigh := _joint(self, Vector3(side * 0.102, 0.75, 0.0))
		FootballArt.capsule(thigh, 0.065, 0.40, Vector3(0.0, -0.20, 0.0), skin)
		FootballArt.capsule(thigh, 0.083, 0.25, Vector3(0.0, -0.085, 0.0), shorts)
		var knee := _joint(thigh, Vector3(0.0, -THIGH_LENGTH, 0.0))
		FootballArt.capsule(knee, 0.049, 0.37, Vector3(0.0, -0.18, 0.0), black)
		FootballArt.cylinder(knee, 0.051, 0.025, Vector3(0.0, -0.08, 0.0), trim)
		var boot := _joint(knee, Vector3(0.0, -SHIN_LENGTH, 0.0))
		FootballArt.sphere(boot, 0.093, Vector3(0.0, -0.01, -0.045), shorts).scale = Vector3(0.58, 0.45, 1.25)
		_thighs.append(thigh)
		_knees.append(knee)
		_boots.append(boot)
	_yellow_card = FootballArt.marker(Color("ffdf23"))
	_red_card = FootballArt.marker(Color("ff344b"))
	_card = FootballArt.box(_elbows[1], Vector3(0.18, 0.24, 0.025), Vector3(0.0, -0.326, 0.0), _yellow_card)
	_card.name = "DisciplineCard"
	_card.rotation.y = 0.35
	_card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_card.hide()
	_animate(0.0)


func track_ball(ball_position: Vector3, delta: float) -> void:
	if _has_ball_sample and delta > 0.0:
		var speed_x := clampf((ball_position.x - _last_ball.x) / delta, -12.0, 12.0)
		_ball_speed_x = lerpf(_ball_speed_x, speed_x, 1.0 - exp(-4.0 * delta))
		if absf(_ball_speed_x) > 0.85:
			_trail_sign = signf(_ball_speed_x)
	_has_ball_sample = true
	_last_ball = ball_position
	if absf(ball_position.z) > 21.0:
		_flank = -signf(ball_position.z)
	var trail := signf(ball_position.x) if absf(ball_position.x) > 36.0 else _trail_sign
	var target := Vector3(clampf(ball_position.x - trail * 6.0, -43.0, 43.0), 0.0,
		clampf(ball_position.z + _flank * 8.0, -27.0, 27.0))
	var offset := target - position
	_velocity = _velocity.move_toward((offset * 1.6).limit_length(PACE), 8.0 * delta)
	_move_and_pose(delta, ball_position - position)


func can_see_contact(spot: Vector3) -> bool:
	var offset := spot - global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance > SIGHT_RANGE:
		return false
	if distance < 0.01:
		return true
	var facing := -global_basis.z
	facing.y = 0.0
	# Wide peripheral vision nearby narrows to the main field of view at distance.
	var minimum_alignment := lerpf(-0.10, 0.45, smoothstep(5.0, 15.0, distance))
	return facing.normalized().dot(offset / distance) >= minimum_alignment


func signal_restart(spot: Vector3, direction: Vector3, indirect: bool) -> void:
	signal_kind = "indirect" if indirect else "restart"
	_signal_raised = indirect
	card_color = ""
	_card.hide()
	_signal_label.show()
	_signal_spot = spot
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() > 0.001:
		_signal_direction = flat.normalized()


func show_card(color: String, contact: Vector3) -> void:
	if color != "yellow" and color != "red":
		return
	card_color = color
	_signal_spot = contact
	_signal_raised = true
	_card.material_override = _yellow_card if color == "yellow" else _red_card
	_card.show()


func hold_position(delta: float) -> void:
	_velocity = _velocity.move_toward(Vector3.ZERO, 12.0 * delta)
	_move_and_pose(delta, _signal_spot - position)


func resume_play() -> void:
	signal_kind = "play"
	card_color = ""
	_card.hide()
	_signal_label.hide()
	_has_ball_sample = false
	_ball_speed_x = 0.0


func _move_and_pose(delta: float, look: Vector3) -> void:
	position += _velocity * delta
	var facing := _velocity if _velocity.length_squared() > 0.16 else look
	if facing.x * facing.x + facing.z * facing.z > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-facing.x, -facing.z), 1.0 - exp(-7.0 * delta))
	_animate(delta)


func _animate(delta: float) -> void:
	var speed := _velocity.length()
	_phase = fposmod(_phase + speed * delta / STRIDE, 1.0)
	var gait := smoothstep(0.15, 1.0, speed)
	_torso.position.y = 0.75 + 0.012 * sin(_phase * TAU * 2.0) * gait
	_torso.rotation.x = -0.11 * gait
	_signal_weight = move_toward(_signal_weight, 0.0 if signal_kind == "play" else 1.0, 5.5 * delta)
	for index in range(2):
		var side := -1.0 if index == 0 else 1.0
		var cycle := fposmod(_phase + float(index) * 0.5, 1.0)
		# Travel drives the stance foot backwards by the same distance the body advances.
		var swing := smoothstep(0.5, 1.0, cycle)
		var foot_z := (cycle - 0.25) * STRIDE if cycle <= 0.5 else lerpf(STRIDE * 0.25, -STRIDE * 0.25, swing)
		var foot_y := 0.052 + 0.15 * sin(swing * PI) * gait
		_pose_leg(index, Vector3(side * 0.107, foot_y, foot_z * gait))
		_arms[index].rotation = Vector3(sin(cycle * TAU) * 0.60 * gait, 0.0, side * 0.13)
		_elbows[index].rotation.x = lerpf(0.27, 0.98, gait)
	if _signal_weight > 0.0:
		if _signal_raised:
			# Keep the arm lifting forward even when the jogging swing is behind the body.
			_arms[1].rotation = _arms[1].rotation.lerp(Vector3(PI + 0.11 * gait, 0.0, 0.12), _signal_weight)
		else:
			var point := Quaternion(Vector3.DOWN, (_torso.global_basis.inverse() * _signal_direction).normalized())
			_arms[1].quaternion = _arms[1].quaternion.slerp(point, _signal_weight)
		_elbows[1].rotation.x = lerpf(_elbows[1].rotation.x, 0.08, _signal_weight)


func _pose_leg(index: int, foot: Vector3) -> void:
	var thigh := _thighs[index]
	thigh.position.y = _torso.position.y
	var offset := foot - thigh.position
	var reach := minf(offset.length(), THIGH_LENGTH + SHIN_LENGTH - 0.001)
	var direction := offset.normalized()
	var along := (THIGH_LENGTH * THIGH_LENGTH + reach * reach - SHIN_LENGTH * SHIN_LENGTH) / (2.0 * reach)
	var bend := sqrt(maxf(0.0, THIGH_LENGTH * THIGH_LENGTH - along * along))
	var pole := (Vector3.FORWARD - direction * Vector3.FORWARD.dot(direction)).normalized()
	var joint := direction * along + pole * bend
	thigh.quaternion = Quaternion(Vector3.DOWN, joint.normalized())
	var shin := thigh.basis.inverse() * (direction * reach - joint)
	_knees[index].quaternion = Quaternion(Vector3.DOWN, shin.normalized())
	_boots[index].basis = (thigh.basis * _knees[index].basis).inverse()


func _joint(parent: Node3D, offset: Vector3) -> Node3D:
	var joint := Node3D.new()
	joint.position = offset
	parent.add_child(joint)
	return joint
