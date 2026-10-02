extends Control

## The run map (GameState.run_map), drawn left to right: one column per row of
## stops, starting matches on the left and the 6 bowls on the right. Stops you
## can go to next pulse; the path you've taken is traced in gold; everything
## out of reach is dimmed. Clicking a stop emits stop_clicked - the hub
## decides what that means.

signal stop_clicked(row: int, col: int)

const NODE_R := 22.0
const BOWL_R := 27.0
const PAD_X := 44.0
const PAD_Y := 32.0

## Per stop type: ring color and the short label inside the circle.
const STYLE := {
	"match": {"color": Color("dce8e2"), "text": "VS"},
	"elite": {"color": Color("e8613c"), "text": "ELITE"},
	"shop": {"color": Color("f2c14e"), "text": "$"},
	"ritual": {"color": Color("b060e0"), "text": "RIT"},
	"lab": {"color": Color("39ff5a"), "text": "LAB"},
	"practice": {"color": Color("6ec46e"), "text": "+"},
	"mystery": {"color": Color("5aa9e6"), "text": "?"},
	"bowl": {"color": Color("f2c14e"), "text": ""},
}

## The stop the hub has picked to show details for (-1, -1 for none).
var selected := Vector2i(-1, -1)
var _hover := Vector2i(-1, -1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


func _process(_delta: float) -> void:
	queue_redraw()   # the pulse on reachable stops


func stop_pos(row: int, col: int) -> Vector2:
	var node := GameState.map_node(row, col)
	var rows := maxi(GameState.run_map.size() - 1, 1)
	return Vector2(
		PAD_X + (size.x - PAD_X * 2.0) * float(row) / float(rows),
		PAD_Y + (size.y - PAD_Y * 2.0) * float(node.get("y", 0.5)))


func _radius(row: int) -> float:
	return BOWL_R if row == GameState.BOWL_ROW else NODE_R


func _hit(at: Vector2) -> Vector2i:
	for r in GameState.run_map.size():
		for c in (GameState.run_map[r] as Array).size():
			if at.distance_to(stop_pos(r, c)) <= _radius(r) * 1.25:
				return Vector2i(r, c)
	return Vector2i(-1, -1)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _hit((event as InputEventMouseMotion).position)
		if h != _hover:
			_hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h.x >= 0 else Control.CURSOR_ARROW
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var h := _hit(mb.position)
			if h.x >= 0:
				stop_clicked.emit(h.x, h.y)
				accept_event()


func _draw() -> void:
	if GameState.run_map.is_empty():
		return
	_draw_links()
	for r in GameState.run_map.size():
		for c in (GameState.run_map[r] as Array).size():
			_draw_stop(r, c)


## The lines between stops: gold along the path walked so far (one stop per
## row, so two done stops in neighboring rows were walked between), bright
## out of where you're standing, faint everywhere else.
func _draw_links() -> void:
	for r in GameState.run_map.size() - 1:
		for c in (GameState.run_map[r] as Array).size():
			var node := GameState.map_node(r, c)
			for n in node.get("next", []):
				var to := GameState.map_node(r + 1, int(n))
				var col := Color(UIKit.LINE, 0.9)
				var width := 2.0
				if bool(node["done"]) and bool(to["done"]):
					col = Color(UIKit.ACCENT, 0.85)
					width = 3.5
				elif GameState.can_go_to(r + 1, int(n)) and (r == GameState.map_row and c == GameState.map_col):
					col = Color(UIKit.TEXT, 0.7)
					width = 3.0
				draw_line(stop_pos(r, c), stop_pos(r + 1, int(n)), col, width, true)
	# From the start line into row 0, before the first stop is picked.
	if GameState.map_row < 0:
		for c in (GameState.run_map[0] as Array).size():
			var p := stop_pos(0, c)
			draw_line(Vector2(6.0, p.y), p, Color(UIKit.TEXT, 0.5), 2.0, true)


## A little padlock centered on `at`, `s` pixels tall-ish: shackle arc over
## a solid body with a keyhole.
func _draw_padlock(at: Vector2, s: float) -> void:
	var lock_col := Color("cfd8d3")
	draw_arc(at + Vector2(0.0, -s * 0.15), s * 0.42, PI, TAU, 12, lock_col, maxf(2.0, s * 0.18), true)
	var body := Rect2(at + Vector2(-s * 0.6, -s * 0.15), Vector2(s * 1.2, s * 0.95))
	draw_rect(body.grow(1.5), Color(0, 0, 0, 0.8))
	draw_rect(body, lock_col)
	draw_circle(at + Vector2(0.0, s * 0.28), s * 0.13, Color(0.1, 0.1, 0.1))


func _draw_stop(r: int, c: int) -> void:
	var node := GameState.map_node(r, c)
	var t := String(node["type"])
	var style: Dictionary = STYLE.get(t, STYLE["match"])
	var col: Color = style["color"]
	var p := stop_pos(r, c)
	var rad := _radius(r)
	var reach := GameState.can_go_to(r, c)
	var here := r == GameState.map_row and c == GameState.map_col
	var done := bool(node["done"])
	var lit := reach or here or done
	if Vector2i(r, c) == _hover and reach:
		rad *= 1.08

	if reach:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
		draw_arc(p, rad + 6.0 + pulse * 3.0, 0.0, TAU, 32, Color(col, 0.35 + 0.35 * pulse), 2.5, true)
	draw_circle(p, rad, UIKit.PANEL_HI if lit else UIKit.PANEL)
	draw_arc(p, rad, 0.0, TAU, 32, Color(col, 1.0 if lit else 0.3), 3.0 if lit else 2.0, true)
	if Vector2i(r, c) == selected:
		draw_arc(p, rad + 4.0, 0.0, TAU, 32, Color.WHITE, 3.0, true)
	if here:
		draw_arc(p, rad - 5.0, 0.0, TAU, 28, Color(UIKit.ACCENT, 0.9), 2.0, true)

	if t == GameState.STOP_BOWL:
		var logo := BowlDB.logo(String(node["bowl_id"]))
		if logo != null:
			var s := rad * 1.5
			draw_texture_rect(logo, Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), false,
				Color(1, 1, 1, 1.0 if lit else 0.4))
	else:
		var text := String(style["text"])
		var fs := 11 if text.length() > 3 else (14 if text.length() > 1 else 20)
		var font := ThemeDB.fallback_font
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, p + Vector2(-w * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(col, 1.0 if lit else 0.4))

	# A Ritual Site / Laboratory still waiting on its challenge: a padlock.
	if bool(node.get("locked", false)):
		_draw_padlock(p + Vector2(rad * 0.72, -rad * 0.72), rad * 0.42)

	# A finished match shows how it went.
	var result := String(node.get("result", ""))
	if result != "":
		var rc: Color = UIKit.GOOD if result == "W" else (UIKit.BAD if result == "L" else UIKit.MUTED)
		var font2 := ThemeDB.fallback_font
		var w2 := font2.get_string_size(result, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font2, p + Vector2(-w2 * 0.5, rad + 16.0), result, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, rc)
