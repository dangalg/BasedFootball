class_name ElevenAttendant
extends Node3D

const PACE := 6.6
const THIGH := 0.39
const SHIN := 0.37
const UPPER_ARM := 0.26
const FOREARM := 0.25
const PALM := Vector3(0.0, -FOREARM, 0.0)
const GRIP_LIFT := Vector3.UP * 0.025

var home_position := Vector3.ZERO
var _velocity := Vector3.ZERO
var _phase := 0.0
var _crouch := 0.0
var _grip_weight := 0.0
var _grip_target := Vector3.ZERO
var _torso: Node3D
var _arms: Array[Node3D] = []
var _elbows: Array[Node3D] = []
var _thighs: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _boots: Array[Node3D] = []


func _ready() -> void:
	var bib := FootballArt.material(Color("c9f54e"))
	var shirt := FootballArt.material(Color("2b3f54"))
	var shorts := FootballArt.material(Color("34384d"))
	var skin := FootballArt.material(Color("b38466"))
	var hair := FootballArt.material(Color("332b24"))
	FootballArt.contact_shadow(self, 1.1)
	_torso = _joint(self, Vector3(0.0, 0.70, 0.0))
	FootballArt.tailored_mesh(_torso, [Vector3(0.0, 0.16, 0.09), Vector3(0.22, 0.17, 0.095),
		Vector3(0.40, 0.21, 0.11), Vector3(0.49, 0.16, 0.085), Vector3(0.50, 0.065, 0.05)], bib)
	FootballArt.cylinder(_torso, 0.043, 0.11, Vector3(0.0, 0.53, 0.0), skin)
	FootballArt.sphere(_torso, 0.114, Vector3(0.0, 0.67, 0.0), skin).scale = Vector3(0.90, 1.08, 0.94)
	FootballArt.sphere(_torso, 0.114, Vector3(0.0, 0.738, 0.014), hair).scale = Vector3(0.94, 0.55, 0.98)
	FootballArt.sphere(_torso, 0.022, Vector3(0.0, 0.66, -0.109), skin)
	for side: float in [-1.0, 1.0]:
		var arm := _joint(_torso, Vector3(side * 0.212, 0.42, 0.0))
		FootballArt.capsule(arm, 0.054, 0.18, Vector3(0.0, -0.078, 0.0), shirt)
		FootballArt.capsule(arm, 0.046, 0.24, Vector3(0.0, -0.133, 0.0), skin)
		var elbow := _joint(arm, Vector3(0.0, -UPPER_ARM, 0.0))
		FootballArt.capsule(elbow, 0.038, 0.24, Vector3(0.0, -0.12, 0.0), skin)
		FootballArt.sphere(elbow, 0.043, PALM, skin)
		_arms.append(arm)
		_elbows.append(elbow)
		var thigh := _joint(self, Vector3(side * 0.105, 0.70, 0.0))
		FootballArt.capsule(thigh, 0.060, 0.37, Vector3(0.0, -0.19, 0.0), skin)
		FootballArt.capsule(thigh, 0.075, 0.24, Vector3(0.0, -0.087, 0.0), shorts)
		var knee := _joint(thigh, Vector3(0.0, -THIGH, 0.0))
		FootballArt.capsule(knee, 0.046, 0.33, Vector3(0.0, -0.18, 0.0), shirt)
		var boot := _joint(knee, Vector3(0.0, -SHIN, 0.0))
		FootballArt.sphere(boot, 0.090, Vector3(0.0, -0.01, -0.045), shorts).scale = Vector3(0.60, 0.46, 1.22)
		_thighs.append(thigh)
		_knees.append(knee)
		_boots.append(boot)
	_animate(0.0, false, Vector3.INF)


func walk_to(target: Vector3, delta: float, carry: bool) -> void:
	var offset := target - global_position
	offset.y = 0.0
	_velocity = _velocity.move_toward((offset * 3.3).limit_length(PACE), 16.0 * delta)
	_move_and_pose(delta, offset, carry)


func hold_ball() -> Vector3:
	return _elbows[0].to_global(PALM).lerp(_elbows[1].to_global(PALM), 0.5) + GRIP_LIFT


func reach_to(world_target: Vector3, delta: float) -> void:
	_velocity = _velocity.move_toward(Vector3.ZERO, 22.0 * delta)
	_move_and_pose(delta, world_target - global_position, false, world_target)


func idle(delta: float) -> void:
	_velocity = _velocity.move_toward(Vector3.ZERO, 16.0 * delta)
	_move_and_pose(delta, Vector3.ZERO, false)

func settled() -> bool:
	return _velocity == Vector3.ZERO and _crouch == 0.0 and _grip_weight == 0.0


func _move_and_pose(delta: float, look: Vector3, carry: bool, reach: Vector3 = Vector3.INF) -> void:
	global_position += _velocity * delta
	var facing := _velocity if _velocity.length_squared() > 0.2 else look
	if facing.x * facing.x + facing.z * facing.z > 0.005:
		rotation.y = lerp_angle(rotation.y, atan2(-facing.x, -facing.z), 1.0 - exp(-11.0 * delta))
	_animate(delta, carry, reach)


func _animate(delta: float, carry: bool, reach: Vector3) -> void:
	var reaching := reach != Vector3.INF
	var speed := _velocity.length()
	var gait := smoothstep(0.15, 1.0, speed)
	var fast := smoothstep(2.0, PACE, speed)
	var stride := lerpf(1.48, 2.37, fast)
	var stance := lerpf(0.51, 0.34, fast)
	_phase = fposmod(_phase + speed * delta / stride, 1.0)
	var crouch_target := 1.0 - smoothstep(0.16, 0.75, reach.y - global_position.y) if reaching else 0.0
	_crouch = move_toward(_crouch, crouch_target, 6.0 * delta)
	_torso.position.y = 0.70 + 0.014 * sin(_phase * TAU * 2.0) * gait - 0.48 * _crouch
	_torso.rotation.x = -0.13 * gait - 0.82 * _crouch
	var needs_grip := carry or reaching
	if needs_grip:
		var target := _torso.to_local(reach - GRIP_LIFT) if reaching else Vector3(0.0, 0.245, -0.30)
		_grip_target = target if _grip_weight <= 0.0 else _grip_target.lerp(target, 1.0 - exp(-18.0 * delta))
	_grip_weight = move_toward(_grip_weight, 1.0 if needs_grip else 0.0, 8.0 * delta)
	for index in range(2):
		var side := -1.0 if index == 0 else 1.0
		var cycle := fposmod(_phase + float(index) * 0.5, 1.0)
		# Advance the planted foot backwards by actual body travel during stance.
		var swing := smoothstep(stance, 1.0, cycle)
		var half_step := stance * stride * 0.5
		var foot_z := cycle * stride - half_step if cycle <= stance else lerpf(half_step, -half_step, swing)
		var foot_y := 0.052 + (0.13 + 0.10 * fast) * sin(PI * swing) * gait
		_thighs[index].position.y = _torso.position.y
		_pose_limb(_thighs[index], _knees[index], Vector3(side * (0.11 + 0.045 * _crouch), foot_y, foot_z * gait),
			Vector3.FORWARD, THIGH, SHIN, 1.0)
		_boots[index].basis = (_thighs[index].basis * _knees[index].basis).inverse()
		_arms[index].rotation = Vector3(sin(cycle * TAU) * 0.68 * gait, 0.0, side * 0.13)
		_elbows[index].rotation = Vector3(lerpf(0.31, 0.99, gait), 0.0, 0.0)
		if _grip_weight > 0.0:
			_pose_limb(_arms[index], _elbows[index], _grip_target + Vector3(side * 0.13, 0.0, 0.0),
				Vector3(side, -0.28, 0.26), UPPER_ARM, FOREARM, _grip_weight)


func _pose_limb(root: Node3D, joint: Node3D, target: Vector3, pole: Vector3,
		upper: float, lower: float, weight: float) -> void:
	var offset := target - root.position
	var direction := offset.normalized()
	if direction == Vector3.ZERO:
		direction = Vector3.DOWN
	var reach := clampf(offset.length(), absf(upper - lower) + 0.001, upper + lower - 0.001)
	var along := (upper * upper + reach * reach - lower * lower) / (2.0 * reach)
	var bend := sqrt(maxf(0.0, upper * upper - along * along))
	var bend_direction := (pole - direction * pole.dot(direction)).normalized()
	var elbow := direction * along + bend_direction * bend
	var upper_pose := Quaternion(Vector3.DOWN, elbow.normalized())
	var lower_direction := Basis(upper_pose).inverse() * (direction * reach - elbow)
	root.quaternion = root.quaternion.slerp(upper_pose, weight)
	joint.quaternion = joint.quaternion.slerp(Quaternion(Vector3.DOWN, lower_direction.normalized()), weight)


func _joint(parent: Node3D, offset: Vector3) -> Node3D:
	var node := Node3D.new()
	node.position = offset
	parent.add_child(node)
	return node
