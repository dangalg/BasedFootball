class_name FootballHUD
extends CanvasLayer

var scoreboard: Label
var timer_label: Label
var player_label: Label
var energy_bar: ProgressBar
var charge_bar: ProgressBar
var banner: Label
var overlay: PanelContainer
var overlay_title: Label
var overlay_body: Label
var overlay_hint: Label
var status: Label
var selected_number: Label
var banner_timer: float = 0.0

const INK := Color("13232e")
const PAPER := Color("e1e6da")
const MUTED := Color("95adaf")
const GOLD := Color("e9c463")

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var top := _panel(root, Vector2(24, 22), Vector2(244, 60))
	var badge := TextureRect.new()
	badge.texture = preload("res://assets/branding/based-football.png")
	badge.position = Vector2(12, 12)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(badge)
	badge.size = Vector2(36, 36)
	_label(top, "BASED FOOTBALL", 19, PAPER, Vector2(58, 10))
	_label(top, "3 v 3  /  THE COURTYARD", 11, MUTED, Vector2(59, 35))
	var score_panel := _panel(root, Vector2(552, 18), Vector2(336, 70))
	_label(score_panel, "HOME", 14, Color("71b2db"), Vector2(30, 17))
	_label(score_panel, "AWAY", 14, Color("eb9a7f"), Vector2(263, 17))
	scoreboard = _label(score_panel, "0  :  0", 28, PAPER, Vector2(98, 4))
	scoreboard.size.x = 140
	scoreboard.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label = _label(score_panel, "03:00", 15, GOLD, Vector2(138, 43))
	var rules := _panel(root, Vector2(1184, 22), Vector2(232, 60))
	_label(rules, "ONE BALL. SAME RULES.", 15, PAPER, Vector2(16, 10))
	_label(rules, "No keepers  /  Rebound boards", 12, MUTED, Vector2(16, 35))
	var player_panel := _panel(root, Vector2(24, 802), Vector2(314, 74))
	selected_number = _label(player_panel, "07", 32, GOLD, Vector2(14, 6))
	player_label = _label(player_panel, "ARI / RUNNER", 17, PAPER, Vector2(68, 13))
	energy_bar = ProgressBar.new()
	energy_bar.position = Vector2(70, 43)
	energy_bar.show_percentage = false
	energy_bar.add_theme_stylebox_override("fill", _style(Color("42bfaf"), 4))
	energy_bar.add_theme_stylebox_override("background", _style(Color("304653"), 4))
	player_panel.add_child(energy_bar)
	energy_bar.size = Vector2(225, 6)
	_label(player_panel, "STAMINA", 10, MUTED, Vector2(70, 52))
	charge_bar = ProgressBar.new()
	charge_bar.position = Vector2(14, 66)
	charge_bar.show_percentage = false
	charge_bar.add_theme_stylebox_override("fill", _style(Color("ffd56a"), 3))
	charge_bar.add_theme_stylebox_override("background", _style(Color("304653"), 3))
	player_panel.add_child(charge_bar)
	charge_bar.size = Vector2(281, 4)
	var help := _panel(root, Vector2(716, 818), Vector2(700, 58))
	_label(help, "CROSS PASS   CIRCLE SHOT / TACKLE   SQUARE LOB / SLIDE   TRIANGLE THROUGH", 13, PAPER, Vector2(18, 9))
	_label(help, "R1 hop / E • R2 sprint • L2 shield / jockey • L1 / right stick switch • Options pause", 11, MUTED, Vector2(18, 34))
	status = _label(root, "", 11, MUTED, Vector2(28, 91))
	banner = _label(root, "", 24, GOLD, Vector2(460, 105))
	banner.size = Vector2(520, 36)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay = PanelContainer.new()
	overlay.position = Vector2(365, 250)
	overlay.size = Vector2(710, 360)
	overlay.add_theme_stylebox_override("panel", _style(Color(0.035, 0.075, 0.115, 0.97), 18))
	root.add_child(overlay)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	overlay.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 22)
	margin.add_child(stack)
	overlay_title = Label.new()
	overlay_title.add_theme_font_size_override("font_size", 36)
	overlay_title.add_theme_color_override("font_color", Color("ffd56a"))
	stack.add_child(overlay_title)
	overlay_body = Label.new()
	overlay_body.add_theme_font_size_override("font_size", 18)
	overlay_body.add_theme_color_override("font_color", Color("e9eddf"))
	overlay_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(overlay_body)
	overlay_hint = Label.new()
	overlay_hint.add_theme_font_size_override("font_size", 18)
	overlay_hint.add_theme_color_override("font_color", Color("55cabd"))
	stack.add_child(overlay_hint)
	overlay.hide()

func _panel(parent: Control, pos: Vector2, dimensions: Vector2) -> Panel:
	var panel := Panel.new()
	panel.position = pos
	panel.size = dimensions
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_to_group("hud_panels")
	var style := _style(Color(INK, 0.9), 10)
	style.border_color = Color("31464d")
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel

func _style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style

func _label(parent: Control, value: String, size: int, color: Color, pos: Vector2) -> Label:
	var label := Label.new()
	label.text = value
	label.position = pos
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func update_match(scores: Array[int], remaining: float, player: FootballPlayer, charge: float) -> void:
	scoreboard.text = "%d  :  %d" % [scores[0], scores[1]]
	var seconds := int(ceil(remaining))
	timer_label.text = "%02d:%02d" % [seconds / 60, seconds % 60]
	selected_number.text = "%02d" % player.shirt_number
	player_label.text = "%s / %s" % [player.player_name, player.role.to_upper()]
	energy_bar.value = player.energy * 100
	charge_bar.value = charge * 100

func flash(message: String, duration: float = 2.0) -> void:
	banner.text = message
	banner_timer = duration

func show_overlay(title: String, body: String, hint: String) -> void:
	overlay_title.text = title
	overlay_body.text = body
	overlay_hint.text = hint
	overlay.show()

func _process(delta: float) -> void:
	if banner_timer > 0:
		banner_timer -= delta
		if banner_timer <= 0:
			banner.text = ""
