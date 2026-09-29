extends Control

## Title screen: the name, a one-line pitch, and the top-level options as a
## plain vertical list of text - no button boxes, just outlined words that
## light up gold under the cursor.

const MENU_TEXT := Color("dce8e2")       # UIKit.TEXT
const MENU_HOVER := Color("f2c14e")      # UIKit.ACCENT
const MENU_PRESSED := Color("ffe9a8")


func _ready() -> void:
	UIKit.background(self)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)

	var t := UIKit.label("GRIDIRON RUN", 62, UIKit.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 6)
	t.add_theme_color_override("font_outline_color", Color.BLACK)
	v.add_child(t)

	var s := UIKit.label("Chart a path to one of 6 bowls. 3 losses and the season is over.", 18, UIKit.MUTED)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)

	v.add_child(UIKit.vsep(36))

	var play := _menu_item("PLAY")
	play.pressed.connect(_on_new_run)
	v.add_child(play)

	var dev := _menu_item("DEV MODE")
	dev.pressed.connect(_on_dev_mode)
	v.add_child(dev)

	var book := _menu_item("PLAYER BOOK")
	book.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/player_book.tscn"))
	v.add_child(book)

	# A browser tab can't be quit from inside the page, so the web build
	# leaves it off.
	if not OS.has_feature("web"):
		var quit := _menu_item("QUIT")
		quit.pressed.connect(func(): get_tree().quit())
		v.add_child(quit)

	v.add_child(UIKit.vsep(36))

	var help := UIKit.label(
		"You coach the offense. Set your lineup, pick five plays, and score.\n"
		+ "Football bucks earned on the field buy plays, players, and items between rounds.",
		15, UIKit.MUTED)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(help)


## One entry in the menu list: flat, boxless text with a black outline,
## brightening to gold under the cursor.
func _menu_item(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.custom_minimum_size = Vector2(320, 0)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", MENU_TEXT)
	b.add_theme_color_override("font_hover_color", MENU_HOVER)
	b.add_theme_color_override("font_focus_color", MENU_TEXT)
	b.add_theme_color_override("font_hover_pressed_color", MENU_PRESSED)
	b.add_theme_color_override("font_pressed_color", MENU_PRESSED)
	b.add_theme_constant_override("outline_size", 4)
	b.add_theme_color_override("font_outline_color", Color.BLACK)
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, empty)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func _on_new_run() -> void:
	get_tree().change_scene_to_file("res://scenes/qb_select.tscn")


## Endless scrimmage with everything unlocked, skipping the QB pick and hub
## entirely - straight into the field for tuning and ability testing.
func _on_dev_mode() -> void:
	GameState.start_dev_mode()
	get_tree().change_scene_to_file("res://scenes/match.tscn")
