class_name ElevenRadar
extends Control

const PITCH_SIZE := Vector2(ElevenPitch.HALF_LENGTH * 2.0, ElevenPitch.HALF_WIDTH * 2.0)
const UPDATE_INTERVAL_MS: int = 50
const HOME_COLOR := Color("5bc6fc")
const AWAY_COLOR := Color("ff9369")
const SELECTED_COLOR := Color("ffe087")
const PITCH_LINE := Color(0.76, 0.88, 0.77, 0.62)

var _home := PackedVector2Array()
var _away := PackedVector2Array()
var _ball_position := Vector2.ZERO
var _controlled_position := Vector2.ZERO
var _has_ball: bool = false
var _has_controlled: bool = false
var _controlled_id: int = 0
var _next_update_ms: int = 0


func _ready() -> void:
	custom_minimum_size = Vector2(240.0, 154.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func update_positions(players: Array, ball: Node3D, controlled: Node3D) -> void:
	var now := Time.get_ticks_msec()
	var controlled_id: int = controlled.get_instance_id() if is_instance_valid(controlled) else 0
	if now < _next_update_ms and controlled_id == _controlled_id:
		return
	_next_update_ms = now + UPDATE_INTERVAL_MS
	_controlled_id = controlled_id
	_home.clear()
	_away.clear()
	for entry in players:
		if not is_instance_valid(entry):
			continue
		var player := entry as Node3D
		if player == null or not player.is_inside_tree():
			continue
		var position_on_pitch := _normalize(player.global_position)
		if int(player.get("team")) == 0:
			_home.append(position_on_pitch)
		else:
			_away.append(position_on_pitch)
	_has_ball = is_instance_valid(ball) and ball.is_inside_tree()
	if _has_ball:
		_ball_position = _normalize(ball.global_position)
	_has_controlled = controlled_id != 0 and controlled.is_inside_tree()
	if _has_controlled:
		_controlled_position = _normalize(controlled.global_position)
	queue_redraw()


func _draw() -> void:
	var available := size - Vector2(16.0, 16.0)
	if available.x <= 0.0 or available.y <= 0.0:
		return
	var pitch_scale := minf(available.x / PITCH_SIZE.x, available.y / PITCH_SIZE.y)
	var field_size := PITCH_SIZE * pitch_scale
	var field := Rect2((size - field_size) * 0.5, field_size)
	draw_rect(field.grow(6.0), Color(0.04, 0.08, 0.07, 0.91))
	draw_rect(field, Color(0.11, 0.24, 0.17, 0.89))
	draw_rect(field, PITCH_LINE, false, 1.0)
	var center := field.get_center()
	draw_line(Vector2(center.x, field.position.y), Vector2(center.x, field.end.y), PITCH_LINE, 1.0, true)
	draw_arc(center, ElevenPitch.CIRCLE_RADIUS * pitch_scale, 0.0, TAU, 32, PITCH_LINE, 1.0, true)
	draw_circle(center, 1.25, PITCH_LINE)
	_draw_boxes(field, pitch_scale, ElevenPitch.PENALTY_DEPTH, ElevenPitch.GOAL_HALF_WIDTH + ElevenPitch.PENALTY_DEPTH)
	_draw_boxes(field, pitch_scale, 5.5, ElevenPitch.GOAL_HALF_WIDTH + 5.5)
	_draw_team(field, _home, HOME_COLOR)
	_draw_team(field, _away, AWAY_COLOR)
	if _has_controlled:
		draw_arc(field.position + _controlled_position * field.size, 6.0, 0.0, TAU, 24, SELECTED_COLOR, 1.7, true)
	if _has_ball:
		var point := field.position + _ball_position * field.size
		draw_circle(point, 3.6, Color("18232a"))
		draw_circle(point, 2.3, Color("fff9e5"))


func _draw_boxes(field: Rect2, pitch_scale: float, depth: float, half_width: float) -> void:
	var box_size := Vector2(depth, 2.0 * half_width) * pitch_scale
	var top := field.get_center().y - box_size.y * 0.5
	draw_rect(Rect2(Vector2(field.position.x, top), box_size), PITCH_LINE, false, 1.0)
	draw_rect(Rect2(Vector2(field.end.x - box_size.x, top), box_size), PITCH_LINE, false, 1.0)


func _draw_team(field: Rect2, positions: PackedVector2Array, color: Color) -> void:
	for normalized in positions:
		var point := field.position + normalized * field.size
		draw_circle(point, 3.6, Color("142628"))
		draw_circle(point, 2.8, color)


static func _normalize(world_position: Vector3) -> Vector2:
	return (Vector2(world_position.x, world_position.z) / PITCH_SIZE + Vector2(0.5, 0.5)).clamp(Vector2.ZERO, Vector2.ONE)
