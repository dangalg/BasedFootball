extends SceneTree

## External test entry point. The recovered production scene and scripts remain
## untouched; this wrapper redirects only the career save and controller input.

var session := ""
var driver: Node

func _initialize() -> void:
	call_deferred("_install")

func _install() -> void:
	session = OS.get_environment("BASED_FOOTBALL_RECOVERY_SESSION")
	if session.is_empty():
		printerr("BASED_FOOTBALL_RECOVERY_SESSION must name a fresh capture session.")
		quit(2)
		return
	var request_file := session.path_join("capture-request.json")
	if not FileAccess.file_exists(request_file):
		printerr("Recovery capture-request.json is missing.")
		quit(2)
		return
	var request: Variant = JSON.parse_string(FileAccess.get_file_as_string(request_file))
	if not request is Dictionary or str(request.get("capture_token", "")).is_empty() or not request.get("identity_phases", []) is Array or request.get("identity_phases", []).size() != 12:
		printerr("Recovery capture request has invalid identity data.")
		quit(2)
		return
	var window := get_root()
	window.size = Vector2i(1280, 800)
	window.content_scale_size = Vector2i(1280, 800)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.position = Vector2i(24, 24)
	window.borderless = true
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	window.title = "Based Football | Recovered 2d5d7ad | Full Match Verification"
	Engine.max_fps = 60
	# The production initial fixture is held only before verified recording.
	# There is no pause, time scaling, repositioning or clock edit after start.
	paused = true
	var packed := load("res://scenes/match.tscn") as PackedScene
	if packed == null:
		printerr("Historical match scene failed to load.")
		quit(2)
		return
	var game := packed.instantiate() as Node3D
	game.squad.save_path = session.path_join("isolated-squad.json")
	if FileAccess.file_exists(game.squad.save_path) or FileAccess.file_exists(game.squad.save_path + ".tmp"):
		printerr("Refusing to reuse an existing isolated career save.")
		quit(2)
		return
	driver = load("res://tests/recovery_match_driver.gd").new()
	driver.process_mode = Node.PROCESS_MODE_ALWAYS
	driver.configure(game, session, request)
	game.decision_driver = driver
	root.add_child(driver)
	root.add_child(game)
	current_scene = game
	game.set_process_unhandled_input(false)
	driver.bind_match()
