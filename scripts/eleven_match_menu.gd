class_name ElevenMatchMenu
extends Control

signal kickoff_requested(seconds: float, difficulty: int, formation: int)

const MATCH_SECONDS: Array[float] = [180.0, 360.0, 600.0]
const FORMATION_DESCRIPTIONS: Array[String] = [
	"Three midfielders with a wide front three.",
	"Two banks of four behind a pair of strikers.",
	"Two deeper midfielders behind an attacking three.",
]
const INK := Color("12252c")
const PAPER := Color("edf5ec")
const MUTED := Color("aac2bc")
const GOLD := Color("e9c463")

var length_choice: OptionButton
var difficulty_choice: OptionButton
var formation_choice: OptionButton
var formation_detail: Label
var kickoff_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.035, 0.075, 0.085, 0.91)
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 588
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 18)
	panel.add_child(contents)

	contents.add_child(_label("BASED FOOTBALL  /  11 v 11", 16, GOLD))
	contents.add_child(_label("Match setup", 46, PAPER))
	contents.add_child(_label("Full pitch  •  Solo against AI", 19, MUTED))
	contents.add_child(HSeparator.new())
	length_choice = _add_choice(contents, "Match length", ["3 minutes", "6 minutes", "10 minutes"], 0)
	difficulty_choice = _add_choice(contents, "Opponent difficulty", ["Relaxed", "Standard", "Competitive"], 1)
	formation_choice = _add_choice(contents, "Formation", ["4-3-3", "4-4-2", "4-2-3-1"], 0)
	formation_detail = _label(FORMATION_DESCRIPTIONS[0], 16, MUTED)
	contents.add_child(formation_detail)
	formation_choice.item_selected.connect(select_formation)

	kickoff_button = Button.new()
	kickoff_button.text = "Kick off"
	kickoff_button.custom_minimum_size.y = 58
	kickoff_button.add_theme_font_size_override("font_size", 24)
	kickoff_button.pressed.connect(_request_kickoff)
	contents.add_child(kickoff_button)
	contents.add_child(_label("Navigate with arrows or D-pad. Select with Enter or ✕.", 16, MUTED))
	contents.add_child(_label("Move with WASD or left stick. Hold J or ○ to shoot.", 16, MUTED))

	length_choice.focus_neighbor_top = length_choice.get_path_to(kickoff_button)
	length_choice.focus_neighbor_bottom = length_choice.get_path_to(difficulty_choice)
	difficulty_choice.focus_neighbor_top = difficulty_choice.get_path_to(length_choice)
	difficulty_choice.focus_neighbor_bottom = difficulty_choice.get_path_to(formation_choice)
	formation_choice.focus_neighbor_top = formation_choice.get_path_to(difficulty_choice)
	formation_choice.focus_neighbor_bottom = formation_choice.get_path_to(kickoff_button)
	kickoff_button.focus_neighbor_top = kickoff_button.get_path_to(formation_choice)
	kickoff_button.focus_neighbor_bottom = kickoff_button.get_path_to(length_choice)
	visibility_changed.connect(_focus_setup)
	_focus_setup.call_deferred()


func _add_choice(parent: VBoxContainer, title: String, choices: Array[String], selected: int) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	parent.add_child(row)
	var caption := _label(title, 20, PAPER)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption)
	var choice := OptionButton.new()
	choice.custom_minimum_size = Vector2(218, 48)
	choice.add_theme_font_size_override("font_size", 20)
	choice.get_popup().add_theme_font_size_override("font_size", 20)
	for item in choices:
		choice.add_item(item)
	choice.select(selected)
	row.add_child(choice)
	return choice


func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	style.border_color = Color("40625b")
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.content_margin_left = 36
	style.content_margin_right = 36
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	return style


func _focus_setup() -> void:
	if is_visible_in_tree():
		length_choice.grab_focus()

func select_formation(index: int) -> void:
	formation_choice.select(index)
	formation_detail.text = FORMATION_DESCRIPTIONS[index]

func _request_kickoff() -> void:
	kickoff_requested.emit(MATCH_SECONDS[length_choice.selected], difficulty_choice.selected, formation_choice.selected)
