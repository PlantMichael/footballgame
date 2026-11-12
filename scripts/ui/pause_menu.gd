extends CanvasLayer

## One modal pause menu for every gameplay screen. Only this layer keeps
## processing while the tree is paused, so plays and countdowns stop together.
signal opening

const MAIN_MENU := "res://scenes/main_menu.tscn"

var _shade: ColorRect
var _actions: VBoxContainer
var _confirm: VBoxContainer
var _resume_button: Button
var _cancel_button: Button
var _previous_focus: Control
var _quit_game: bool = false
var _hint: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_build()
	hide()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if visible:
			if _confirm.visible:
				_show_actions()
			else:
				resume()
		else:
			open()
		if visible or get_tree().current_scene != null and get_tree().current_scene.scene_file_path != MAIN_MENU:
			get_viewport().set_input_as_handled()


func open() -> void:
	var scene := get_tree().current_scene
	if visible or scene == null or scene.scene_file_path == MAIN_MENU:
		return
	_previous_focus = get_viewport().gui_get_focus_owner()
	opening.emit()
	get_tree().paused = true
	show()
	_show_actions()


func resume() -> void:
	hide()
	get_tree().paused = false
	if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	else:
		_resume_button.release_focus()
	_previous_focus = null


func _build() -> void:
	_shade = ColorRect.new()
	_shade.color = Color(UIKit.BG, 0.85)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.add_child(center)
	var panel := UIKit.chalkboard()
	panel.custom_minimum_size = Vector2(360, 0)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)
	var title := UIKit.chalk_label("TIME OUT", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_hint = UIKit.label("", 16, UIKit.TEXT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_hint)

	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 12)
	column.add_child(_actions)
	_resume_button = _button("RESUME", resume, true)
	_actions.add_child(_resume_button)
	_actions.add_child(_button("MAIN MENU", _ask_leave))
	if not OS.has_feature("web"):
		_actions.add_child(_button("QUIT GAME", func(): _ask_leave(true)))

	_confirm = VBoxContainer.new()
	_confirm.add_theme_constant_override("separation", 12)
	column.add_child(_confirm)
	var warning := UIKit.label("Leaving ends this run.\nOnly bowl completion marks are saved.", 18, UIKit.TEXT)
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm.add_child(warning)
	_cancel_button = _button("BACK", _show_actions, true)
	_confirm.add_child(_cancel_button)
	var leave := _button("LEAVE RUN", _leave)
	_confirm.add_child(leave)
	# Keep keyboard focus inside whichever group is visible.
	for group in [_actions, _confirm]:
		var buttons: Array = group.get_children().filter(func(c): return c is Button)
		for i in buttons.size():
			var b: Button = buttons[i]
			b.focus_neighbor_top = b.get_path_to(buttons[posmod(i - 1, buttons.size())])
			b.focus_neighbor_bottom = b.get_path_to(buttons[(i + 1) % buttons.size()])
			b.focus_next = b.focus_neighbor_bottom
			b.focus_previous = b.focus_neighbor_top


func _button(text: String, action: Callable, primary: bool = false) -> Button:
	var b := UIKit.primary_button(text, 20) if primary else UIKit.button(text, 20)
	b.custom_minimum_size.y = 48
	b.add_theme_color_override("font_focus_color", Color("13200f") if primary else UIKit.TEXT)
	b.add_theme_stylebox_override("focus", UIKit.stylebox(Color.TRANSPARENT, 6, 3, UIKit.TEXT))
	b.pressed.connect(action)
	return b


func _show_actions() -> void:
	_hint.text = "Game paused  -  Esc to resume"
	_confirm.hide()
	_actions.show()
	_resume_button.grab_focus()


func _ask_leave(quit_game: bool = false) -> void:
	_hint.text = "Game paused  -  Esc to go back"
	_quit_game = quit_game
	_actions.hide()
	_confirm.show()
	_cancel_button.grab_focus()


func _leave() -> void:
	if _quit_game:
		get_tree().quit()
		return
	var error := get_tree().change_scene_to_file(MAIN_MENU)
	if error == OK:
		GameState.run_active = false
		_previous_focus = null
		resume()
	else:
		push_error("PauseMenu: could not return to main menu (%s)" % error)
