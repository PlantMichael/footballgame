extends Node

## Real match controls and pre-GUI Enter routing, including modal boundaries.
## godot --headless --path . res://tools/playcall_check.tscn
var failures := 0
var screen: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().current_scene = null
	_run.call_deferred()

func _run() -> void:
	get_tree().root.size = Vector2i(1440, 900)
	await _match()
	var choice := _link("Priority_F0")
	await _click(choice)
	_check(screen.sim.is_priority_target("F0"), "player-column target choice selects the matching player")
	choice = _link("Priority_F0")
	_check(choice != null and choice.button_pressed, "selection has native checked state after rebuilding")
	if choice != null:
		choice.grab_focus()
	await _key(KEY_SPACE)
	_check(not screen.sim.is_priority_target("F0"), "Space can change a focused name choice")
	await _click(_link("AllTargets"))
	_check(screen.sim.all_priority_targets_selected(), "shared target-all selects every player")
	await _click(_link("AllTargets"))
	_check(screen.sim.priority_targets.is_empty(), "shared clear-targets clears every player")
	var rb: SimPlayer
	for f: SimPlayer in screen.sim.flex_players():
		if screen.sim.plays_rb(f):
			rb = f
			break
	_check(rb != null, "lineup has an eligible handoff player")
	if rb != null:
		await _click(_link("Handoff_" + rb.slot))
		_check(screen.sim.planned_action == "handoff" and screen.sim.planned_handoff_slot == rb.slot,
			"handoff under the player's route arms that player")
	await _click(_link("Scramble"))
	_check(screen.sim.planned_action == "scramble", "shared QB scramble replaces the handoff")
	await _click(_link("Scramble"))
	_check(screen.sim.planned_action == "", "selecting QB scramble again cancels it")
	choice = _link("Priority_F0")
	if choice != null:
		choice.grab_focus()
	await _key(KEY_ENTER)
	_check(screen.sim.phase == MatchSim.Phase.LIVE and not screen.sim.is_priority_target("F0"),
		"Enter starts the play before the focused name consumes it")
	screen.sim.time = 1.25
	await _key(KEY_ENTER)
	_check(screen.sim.time == 1.25, "Enter during LIVE does not restart the play")

	await _match()
	var snap := _button("SNAP", screen)
	if snap != null:
		await _click_at(snap.get_global_rect().position + Vector2(2, 2))
		_check(screen.sim.phase == MatchSim.Phase.PRESNAP, "outside the circular face does not snap")
	await _click(snap)
	_check(screen.sim.phase == MatchSim.Phase.LIVE, "clicking the circular face snaps")

	await _match()
	screen.call("_open_examples")
	await get_tree().process_frame
	var close := _button("Close", screen.examples_panel)
	if close != null:
		close.grab_focus()
	await _key(KEY_ENTER)
	_check(not screen.examples_panel.visible and screen.sim.phase == MatchSim.Phase.PRESNAP,
		"Enter activates the open panel's Close button without snapping underneath")
	screen.call("_open_team_stats")
	await _key(KEY_ENTER)
	_check(screen.sim.phase == MatchSim.Phase.PRESNAP, "open side panel blocks the snap shortcut")
	screen.call("_dismiss_overlays")
	PauseMenu.open()
	await _key(KEY_ENTER)
	_check(not get_tree().paused and screen.sim.phase == MatchSim.Phase.PRESNAP,
		"Enter resumes the real pause menu without also snapping")
	await _key(KEY_ENTER, true)
	_check(screen.sim.phase == MatchSim.Phase.PRESNAP, "held Enter repeat does not start a play")
	await _key(KEY_ENTER)
	_check(screen.sim.phase == MatchSim.Phase.LIVE, "fresh Enter starts after resuming")
	screen.sim.set_drawn_call(GameState.drawn_routes)
	screen.call("_refresh_bar")
	await _key(KEY_ENTER, true)
	_check(screen.sim.phase == MatchSim.Phase.PRESNAP, "repeat delivery on the next play still waits for a fresh press")
	screen.sim.set_kick_mode(true)
	screen.call("_refresh_bar")
	await _key(KEY_KP_ENTER)
	_check(screen.sim.phase == MatchSim.Phase.LIVE and screen.sim.kick_play,
		"keypad Enter starts the ready field-goal play")
	print("PLAYCALL CHECK: %s" % ("ALL CHECKS PASSED" if failures == 0 else "%d FAILURES" % failures))
	get_tree().quit(1 if failures else 0)

func _match() -> void:
	GameState.new_run(99003)
	get_tree().change_scene_to_file("res://scenes/match.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	screen = get_tree().current_scene
	if screen.loading:
		await screen.ready_to_play
	# Freeze only the simulation driver; real input/control/field owners stay active.
	screen.set_process(false)

func _link(control_name: String) -> LinkButton:
	for link in screen.bar_host.find_children("*", "LinkButton", true, false):
		if link.name == control_name:
			return link
	_check(false, "player call choice available: " + control_name)
	return null

func _button(caption: String, parent: Node) -> Button:
	for button in parent.find_children("*", "Button", true, false):
		if button.text.strip_edges() == caption and button.is_visible_in_tree():
			return button
	_check(false, "button available: " + caption)
	return null

func _key(code: Key, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = InputEventKey.new()
	event.keycode = code
	Input.parse_input_event(event)
	await get_tree().process_frame
	# Release actions rebuild the panel using queue_free; focus the replacement
	# controls only after the previous frame's deferred deletion has completed.
	await get_tree().process_frame

func _click(control: Control) -> void:
	if control != null:
		await _click_at(control.get_global_rect().get_center())

func _click_at(at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.global_position = at
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
	await get_tree().process_frame

func _check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
		push_error(description)
