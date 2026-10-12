extends Control

## Title screen, under the stadium lights: a football over the varsity-style
## name, a one-line pitch, and the top-level options painted on the turf like
## end-zone lettering - no button boxes, just words that light up gold under
## the cursor.

const MENU_TEXT := Color("dce8e2")       # UIKit.TEXT
const MENU_HOVER := Color("f2c14e")      # UIKit.ACCENT
const MENU_PRESSED := Color("ffe9a8")


func _ready() -> void:
	UIKit.background(self, true)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)

	var ball := CenterContainer.new()
	ball.add_child(_football())
	v.add_child(ball)

	# Varsity lettering: gold, a thick dark outline, and a drop shadow.
	var t := UIKit.label("GRIDIRON RUN", 96, UIKit.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_override("font", _spaced(6))
	t.add_theme_constant_override("outline_size", 14)
	t.add_theme_color_override("font_outline_color", Color("1a1206"))
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	t.add_theme_constant_override("shadow_offset_x", 0)
	t.add_theme_constant_override("shadow_offset_y", 8)
	t.add_theme_constant_override("shadow_outline_size", 14)
	v.add_child(t)


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


## One entry in the menu list: flat, boxless, widely spaced lettering like
## paint in an end zone, brightening to gold under the cursor.
func _menu_item(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.custom_minimum_size = Vector2(360, 0)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_override("font", _spaced(5))
	b.add_theme_font_size_override("font_size", 34)
	b.add_theme_color_override("font_color", MENU_TEXT)
	b.add_theme_color_override("font_hover_color", MENU_HOVER)
	b.add_theme_color_override("font_focus_color", MENU_TEXT)
	b.add_theme_color_override("font_hover_pressed_color", MENU_PRESSED)
	b.add_theme_color_override("font_pressed_color", MENU_PRESSED)
	b.add_theme_constant_override("outline_size", 5)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, empty)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


## The block font with extra space between letters, like painted lettering.
func _spaced(px: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = UIKit.FONT_BLOCK
	f.spacing_glyph = px
	return f


## A football, laces up, drawn over the title.
func _football() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(120, 64)
	c.draw.connect(func():
		var mid := c.size * 0.5
		var pts := PackedVector2Array()
		for i in 48:
			var a := TAU * float(i) / 48.0
			# A prolate spheroid's outline: fuller in the middle, pointed at the ends.
			var x := cos(a) * 56.0
			var y := sin(a) * 28.0 * (1.0 - 0.15 * absf(cos(a)))
			pts.append(mid + Vector2(x, y))
		c.draw_colored_polygon(pts, Color("7a3f1d"))
		c.draw_polyline(pts + PackedVector2Array([pts[0]]), Color("1a1206"), 4.0, true)
		# The white stripes near each tip, and the laces.
		for side in [-1.0, 1.0]:
			c.draw_line(mid + Vector2(side * 38.0, -20.0), mid + Vector2(side * 38.0, 20.0), Color("f4efe4"), 4.0, true)
		c.draw_line(mid + Vector2(-16, -2), mid + Vector2(16, -2), Color("f4efe4"), 3.0, true)
		for i in 5:
			var x := -12.0 + 6.0 * float(i)
			c.draw_line(mid + Vector2(x, -8), mid + Vector2(x, 4), Color("f4efe4"), 2.5, true))
	return c


func _on_new_run() -> void:
	get_tree().change_scene_to_file("res://scenes/qb_select.tscn")


## Endless scrimmage with everything unlocked, skipping the QB pick and hub
## entirely - straight into the field for tuning and ability testing.
func _on_dev_mode() -> void:
	GameState.start_dev_mode()
	get_tree().change_scene_to_file("res://scenes/match.tscn")
