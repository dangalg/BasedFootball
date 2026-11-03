class_name ElevenPitch
extends RefCounted

const HALF_LENGTH: float = 50.0
const HALF_WIDTH: float = 32.0
const GOAL_HALF_WIDTH: float = 3.66
const CROSSBAR_HEIGHT: float = 2.44
const GOAL_DEPTH: float = 2.1
const LINE_WIDTH: float = 0.10
const LINE_Y: float = 0.012
const PENALTY_DEPTH: float = 16.5
const PENALTY_SPOT: float = 11.0
const CIRCLE_RADIUS: float = 9.15


static func build(host: Node3D) -> void:
	var pitch := Node3D.new()
	pitch.name = "ElevenPitch"
	host.add_child(pitch)
	var runoff := FootballArt.surface(Color("315c37"), FootballArt.TURF, 36.0)
	var dark := FootballArt.surface(Color("397744"), FootballArt.TURF, 17.0)
	var light := FootballArt.surface(Color("40804a"), FootballArt.TURF, 17.0)
	var paint := FootballArt.material(Color("f3f0dd"))
	FootballArt.solid(pitch, Vector3(132.0, 0.5, 96.0), Vector3(0.0, -0.25, 0.0), runoff)
	for stripe in range(12):
		var stripe_width := HALF_LENGTH * 2.0 / 12.0
		FootballArt.box(pitch, Vector3(stripe_width, 0.002, HALF_WIDTH * 2.0),
			Vector3(-HALF_LENGTH + (float(stripe) + 0.5) * stripe_width, 0.001, 0.0),
			light if stripe % 2 == 0 else dark)
	for side in [-1.0, 1.0]:
		var direction: float = side
		var goal_x := direction * HALF_LENGTH
		_line(pitch, Vector2(-HALF_LENGTH, direction * HALF_WIDTH),
			Vector2(HALF_LENGTH, direction * HALF_WIDTH), paint)
		_line(pitch, Vector2(goal_x, -HALF_WIDTH), Vector2(goal_x, HALF_WIDTH), paint)
		_box_marking(pitch, direction, PENALTY_DEPTH, GOAL_HALF_WIDTH + PENALTY_DEPTH, paint)
		_box_marking(pitch, direction, 5.5, GOAL_HALF_WIDTH + 5.5, paint)
		var spot_x := direction * (HALF_LENGTH - PENALTY_SPOT)
		_spot(pitch, spot_x, paint)
		var arc_angle := acos((PENALTY_DEPTH - PENALTY_SPOT) / CIRCLE_RADIUS)
		_arc(pitch, Vector2(spot_x, 0.0), CIRCLE_RADIUS, -arc_angle, arc_angle,
			Vector2(-direction, 1.0), paint, 24)
		_goal(pitch, direction, paint)
		for edge in [-1.0, 1.0]:
			var flank: float = edge
			_arc(pitch, Vector2(goal_x, flank * HALF_WIDTH), 1.0, 0.0, PI * 0.5,
				Vector2(-direction, -flank), paint, 10)
			_corner_flag(pitch, direction, flank, paint)
	_line(pitch, Vector2(0.0, -HALF_WIDTH), Vector2(0.0, HALF_WIDTH), paint)
	_arc(pitch, Vector2.ZERO, CIRCLE_RADIUS, 0.0, TAU, Vector2.ONE, paint, 64)
	_spot(pitch, 0.0, paint)


static func _line(pitch: Node3D, start: Vector2, finish: Vector2, paint: Material) -> void:
	FootballArt.line(pitch, Vector3(start.x, LINE_Y, start.y),
		Vector3(finish.x, LINE_Y, finish.y), LINE_WIDTH, paint)


static func _box_marking(pitch: Node3D, side: float, depth: float, half_width: float, paint: Material) -> void:
	var end := side * HALF_LENGTH
	var front := side * (HALF_LENGTH - depth)
	_line(pitch, Vector2(end, -half_width), Vector2(front, -half_width), paint)
	_line(pitch, Vector2(front, -half_width), Vector2(front, half_width), paint)
	_line(pitch, Vector2(front, half_width), Vector2(end, half_width), paint)


static func _arc(pitch: Node3D, center: Vector2, radius: float, start: float, finish: float,
		sign_axes: Vector2, paint: Material, segments: int) -> void:
	var previous := center + Vector2(cos(start), sin(start)) * sign_axes * radius
	for index in range(1, segments + 1):
		var angle := lerpf(start, finish, float(index) / float(segments))
		var point := center + Vector2(cos(angle), sin(angle)) * sign_axes * radius
		_line(pitch, previous, point, paint)
		previous = point


static func _spot(pitch: Node3D, x: float, paint: Material) -> void:
	FootballArt.cylinder(pitch, 0.10, 0.014, Vector3(x, LINE_Y, 0.0), paint)


static func _goal(pitch: Node3D, side: float, paint: Material) -> void:
	var x := side * HALF_LENGTH
	var post_size := 0.12
	var post_center := GOAL_HALF_WIDTH + post_size * 0.5
	for edge in [-1.0, 1.0]:
		var z := float(edge) * post_center
		FootballArt.solid(pitch, Vector3(post_size, CROSSBAR_HEIGHT, post_size),
			Vector3(x, CROSSBAR_HEIGHT * 0.5, z), paint)
	var outside_width := (GOAL_HALF_WIDTH + post_size) * 2.0
	FootballArt.solid(pitch, Vector3(post_size, post_size, outside_width),
		Vector3(x, CROSSBAR_HEIGHT + post_size * 0.5, 0.0), paint)
	var back := x + side * GOAL_DEPTH
	var middle := (x + back) * 0.5
	FootballArt.net(pitch, Vector2(outside_width, CROSSBAR_HEIGHT),
		Vector3(back, CROSSBAR_HEIGHT * 0.5, 0.0), PI * 0.5)
	for edge in [-1.0, 1.0]:
		FootballArt.net(pitch, Vector2(GOAL_DEPTH, CROSSBAR_HEIGHT),
			Vector3(middle, CROSSBAR_HEIGHT * 0.5, float(edge) * post_center), 0.0)
	var roof := FootballArt.net(pitch, Vector2(GOAL_DEPTH, outside_width),
		Vector3(middle, CROSSBAR_HEIGHT, 0.0), 0.0)
	roof.rotation.x = -PI * 0.5


static func _corner_flag(pitch: Node3D, end: float, side: float, pole: Material) -> void:
	var x := end * (HALF_LENGTH + 0.14)
	var z := side * (HALF_WIDTH + 0.14)
	FootballArt.cylinder(pitch, 0.020, 1.55, Vector3(x, 0.775, z), pole)
	FootballArt.box(pitch, Vector3(0.33, 0.23, 0.025),
		Vector3(x - end * 0.16, 1.40, z), FootballArt.material(Color("e9b54c")))
