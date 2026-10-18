extends SceneTree

## Test-only entry point. The ordinary desktop match and user save are unchanged.
func _initialize() -> void:
	call_deferred("_install")

func _install() -> void:
	var session: String = OS.get_environment("BASED_FOOTBALL_TEAMWORK_SESSION")
	if session.is_empty():
		printerr("BASED_FOOTBALL_TEAMWORK_SESSION must name a fresh capture session.")
		quit(2)
		return
	var request_path: String = session.path_join("capture-request.json")
	if not FileAccess.file_exists(request_path):
		printerr("Turn/teamwork capture-request.json is missing.")
		quit(2)
		return
	var request: Variant = JSON.parse_string(FileAccess.get_file_as_string(request_path))
	if not request is Dictionary or str(request.get("capture_token", "")).is_empty() or not request.get("identity_phases", []) is Array or request.get("identity_phases", []).size() != 12:
		printerr("Turn/teamwork capture identity is invalid.")
		quit(2)
		return
	var window: Window = get_root()
	window.size = Vector2i(1280, 800)
	window.content_scale_size = Vector2i(1280, 800)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.position = Vector2i(24, 24)
	window.borderless = true
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	window.title = "Based Football | Turns and Teamwork | One Recorded Sequence"
	Engine.max_fps = 60
	paused = true
	var driver: Node = load("res://tests/turn_teamwork_acceptance.gd").new()
	driver.process_mode = Node.PROCESS_MODE_ALWAYS
	driver.configure(session, request)
	root.add_child(driver)
	driver.prepare()
