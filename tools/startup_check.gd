extends Node

## Real scene handoff, input isolation, repeated loading and error recovery.
var failures := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().current_scene = null
	_run.call_deferred()

func _run() -> void:
	LoadingScreen.go_to("res://scenes/main_menu.tscn")
	await _settled()
	_check(get_tree().current_scene.scene_file_path.ends_with("main_menu.tscn"), "boot handoff reaches the menu")
	for entry in 2:
		GameState.start_dev_mode() if entry == 0 else GameState.new_run(99011)
		LoadingScreen.go_to("res://scenes/match.tscn")
		await get_tree().scene_changed
		_check(get_tree().current_scene.loading and not get_tree().current_scene.visible, "match stays hidden during resource preparation")
		await _key(KEY_ESCAPE)
		await _key(KEY_ENTER)
		PauseMenu.open()
		_check(LoadingScreen.active and not get_tree().paused, "preparation cannot be paused or exposed")
		await _settled()
		var screen := get_tree().current_scene
		_check(not screen.loading and screen.visible and screen.sim.phase == MatchSim.Phase.PRESNAP,
			"each prepared entry reveals an unsnapped match")
		await _key(KEY_ENTER)
		_check(screen.sim.phase == MatchSim.Phase.LIVE, "Enter works after readiness")
		LoadingScreen.go_to("res://scenes/main_menu.tscn")
		await _settled()
	# A required sprite cannot be prepared. Exercise the real failed-match
	# cleanup while the next menu owns a newer loading presentation.
	GameState.new_run(99012)
	LoadingScreen.go_to("res://scenes/match.tscn")
	await get_tree().scene_changed
	get_tree().current_scene.field.sidelines._textures["blue/front/body_01.png"] = null
	for frame in 600:
		if LoadingScreen._back.visible:
			break
		await get_tree().process_frame
	_check(LoadingScreen._back.visible, "sprite preparation failure exposes recovery")
	LoadingScreen._back.pressed.emit()
	await _settled()
	_check(get_tree().current_scene != null and get_tree().current_scene.scene_file_path.ends_with("main_menu.tscn"),
		"failed match cleanup cannot hide the next screen's loading layer")
	# Expected resource error: the real loading owner must present recovery.
	await LoadingScreen.go_to("res://scenes/missing-startup-check.tscn")
	_check(LoadingScreen.active and LoadingScreen._back.visible, "load failure presents a usable menu action")
	LoadingScreen._back.pressed.emit()
	await _settled()
	_check(get_tree().current_scene.scene_file_path.ends_with("main_menu.tscn"), "failure recovers to the menu")
	print("STARTUP CHECK: ", "ALL CHECKS PASSED" if failures == 0 else "%d FAILURES" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _settled() -> void:
	var frames := 0
	while LoadingScreen.active and frames < 600:
		await get_tree().process_frame
		frames += 1
	_check(not LoadingScreen.active, "loading finishes within the test deadline")

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = InputEventKey.new()
	event.keycode = code
	Input.parse_input_event(event)
	await get_tree().process_frame

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("STARTUP CHECK: " + message)
