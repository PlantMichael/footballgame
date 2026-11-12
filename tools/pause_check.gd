extends Node

## Real-tree pause regression: input, live simulation, countdowns and exit.
## godot --headless --path . res://tools/pause_check.tscn
var failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Keep the harness alive while the real game changes current_scene.
	get_tree().current_scene = null
	_run.call_deferred()


func _run() -> void:
	await _screen("main_menu")
	await _escape()
	_check(not get_tree().paused and not PauseMenu.visible, "title screen ignores pause")
	GameState.new_run(99001)
	await _screen("hub")
	await _escape()
	_check(get_tree().paused and PauseMenu.visible, "Esc pauses the map")
	_check(get_viewport().gui_get_focus_owner().text == "RESUME", "resume receives keyboard focus")
	_press("MAIN MENU")
	_check(get_tree().paused and _visible_button("BACK") != null, "leaving requires confirmation")
	await _escape()
	_check(get_tree().paused and _visible_button("RESUME") != null, "Esc cancels leaving without unpausing")
	_press("RESUME")
	_check(not get_tree().paused, "resume button unpauses")

	await _screen("match")
	var match_screen := get_tree().current_scene
	var sim: MatchSim = match_screen.sim
	match_screen.call("_on_snap")
	await get_tree().create_timer(0.1).timeout
	_check(sim.phase == MatchSim.Phase.LIVE, "real match has a live play")
	_press("Pause (Esc)")
	var time_before := sim.time
	var ball_before := sim.ball_pos
	await get_tree().create_timer(0.15).timeout
	_check(sim.time == time_before and sim.ball_pos == ball_before, "pause freezes the live play")
	await _escape()
	await get_tree().create_timer(0.1).timeout
	_check(sim.time > time_before, "Esc resumes the same play")

	# The real result-card and end-of-match counters must also stay frozen.
	sim.phase = MatchSim.Phase.DEAD
	match_screen.set("_auto_left", 3.0)
	PauseMenu.open()
	await get_tree().create_timer(0.1).timeout
	_check(match_screen.get("_auto_left") == 3.0, "result countdown stops")
	PauseMenu.resume()
	match_screen.set("_match_ended", true)
	match_screen.set("_end_countdown", 4.0)
	PauseMenu.open()
	await get_tree().create_timer(0.1).timeout
	_check(match_screen.get("_end_countdown") == 4.0, "match-end countdown stops")
	_press("MAIN MENU")
	_press("LEAVE RUN")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not get_tree().paused and not PauseMenu.visible, "exit clears pause")
	_check(get_tree().current_scene.scene_file_path.ends_with("main_menu.tscn"), "confirmed exit reaches title")
	_check(not GameState.run_active, "confirmed exit ends the run")
	GameState.new_run(99002)
	await _screen("shop")
	await _escape()
	_check(get_tree().paused, "pause works after leaving and starting another run")
	await _escape()
	_check(not get_tree().paused, "second run resumes")
	print("PAUSE CHECK: %s" % ("ALL CHECKS PASSED" if failures == 0 else "%d FAILURES" % failures))
	get_tree().quit(1 if failures else 0)


func _screen(id: String) -> void:
	get_tree().change_scene_to_file("res://scenes/%s.tscn" % id)
	await get_tree().process_frame
	await get_tree().process_frame


func _escape() -> void:
	await get_tree().process_frame
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = InputEventKey.new()
	event.keycode = KEY_ESCAPE
	Input.parse_input_event(event)
	await get_tree().process_frame


func _visible_button(text: String) -> Button:
	for node in get_tree().root.find_children("*", "Button", true, false):
		if node.text == text and node.is_visible_in_tree():
			return node
	return null


func _press(text: String) -> void:
	var button := _visible_button(text)
	_check(button != null, "%s button available" % text)
	if button != null:
		button.pressed.emit()


func _check(ok: bool, text: String) -> void:
	print("[%s] %s" % ["ok" if ok else "FAIL", text])
	if not ok:
		failures += 1
