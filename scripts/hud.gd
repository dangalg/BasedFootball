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

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var top := _panel(root, Vector2(28, 24), Vector2(260, 72))
	_label(top, "BASED / FOOTBALL", 24, Color("f3efdd"), Vector2(18, 9))
	_label(top, "3 v 3     •     THE COURTYARD", 12, Color("9bb8bf"), Vector2(19, 44))
	var score_panel := _panel(root, Vector2(490, 24), Vector2(460, 76))
	scoreboard = _label(score_panel, "HOME  0     :     0  AWAY", 29, Color("f3efdd"), Vector2(30, 5))
	timer_label = _label(score_panel, "03:00", 18, Color("ffd56a"), Vector2(200, 45))
	var rules := _panel(root, Vector2(1114, 24), Vector2(298, 72))
	_label(rules, "ONE BALL. SAME RULES.", 18, Color("f3efdd"), Vector2(18, 10))
	_label(rules, "No keepers  /  Rebound boards", 14, Color("9bb8bf"), Vector2(18, 40))
	var player_panel := _panel(root, Vector2(28, 766), Vector2(370, 108))
	selected_number = _label(player_panel, "07", 42, Color("ffd56a"), Vector2(16, 10))
	player_label = _label(player_panel, "ARI / RUNNER", 20, Color("f3efdd"), Vector2(85, 17))
	energy_bar = ProgressBar.new()
	energy_bar.position = Vector2(87, 55)
	energy_bar.size = Vector2(254, 9)
	energy_bar.show_percentage = false
	energy_bar.add_theme_stylebox_override("fill", _style(Color("42bfaf"), 4))
	energy_bar.add_theme_stylebox_override("background", _style(Color("304653"), 4))
	player_panel.add_child(energy_bar)
	_label(player_panel, "STAMINA", 11, Color("9bb8bf"), Vector2(87, 69))
	charge_bar = ProgressBar.new()
	charge_bar.position = Vector2(16, 95)
	charge_bar.size = Vector2(325, 6)
	charge_bar.show_percentage = false
	charge_bar.add_theme_stylebox_override("fill", _style(Color("ffd56a"), 3))
	charge_bar.add_theme_stylebox_override("background", _style(Color("304653"), 3))
	player_panel.add_child(charge_bar)
	var help := _panel(root, Vector2(430, 806), Vector2(982, 68))
	_label(help, "A  PASS     B  HOLD / SHOOT     X  TACKLE     RT  SPRINT     LB  SWITCH", 17, Color("e9eddf"), Vector2(20, 10))
	_label(help, "Left stick: move + aim     Right stick: select teammate     Menu: pause     Keyboard: WASD / Space / J / K / Shift / Tab", 12, Color("9bb8bf"), Vector2(20, 39))
	status = _label(root, "", 15, Color("c4d6d6"), Vector2(31, 109))
	banner = _label(root, "", 32, Color("ffd56a"), Vector2(340, 153))
	banner.size.x = 760
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
	panel.add_theme_stylebox_override("panel", _style(Color(0.035, 0.075, 0.115, 0.93), 12))
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
	scoreboard.text = "HOME  %d     :     %d  AWAY" % [scores[0], scores[1]]
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
