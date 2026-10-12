class_name PlayDiagram
extends Control

## Standalone chalkboard drawing of a play, straight from PlayDB data.
## Used on the playbook screen and on the in-match play-call cards.

@export var play_id: String = ""
@export var compact: bool = false

const DEPTH_BACK := 8.0     # yards of backfield shown
const MIN_DEPTH_FWD := 13.0 # never zoom in tighter than this
const HALF_WIDTH := 26.0    # yards either side of center

## Depth shown downfield, fitted to the deepest route in this play so a set of
## six yard outs does not get drawn in the bottom quarter of the frame.
var _depth_fwd: float = MIN_DEPTH_FWD


func _ready() -> void:
	custom_minimum_size = Vector2(160, 110) if compact else Vector2(320, 260)
	resized.connect(queue_redraw)


func set_play(id: String) -> void:
	play_id = id
	queue_redraw()


func _fit_depth() -> void:
	var pl := PlayDB.get_play(play_id)
	if pl.is_empty():
		_depth_fwd = MIN_DEPTH_FWD
		return
	var deepest := 0.0
	var aligns: Array = pl["align"]
	for i in 5:
		var a: Vector2 = aligns[i]
		var assign = pl["routes"][i]
		if assign is String:
			deepest = maxf(deepest, a.x + (6.0 if assign == PlayDB.CARRY else 0.0))
			continue
		for wp in assign:
			deepest = maxf(deepest, a.x + wp.x)
	_depth_fwd = maxf(MIN_DEPTH_FWD, deepest + 3.0)


func _to_px(v: Vector2) -> Vector2:
	# v is (depth, lateral) in yards. Depth grows upward on screen.
	var sx := size.x / (HALF_WIDTH * 2.0)
	var sy := size.y / (DEPTH_BACK + _depth_fwd)
	return Vector2(
		size.x * 0.5 + v.y * sx,
		size.y - (v.x + DEPTH_BACK) * sy
	)


func _draw() -> void:
	var pl := PlayDB.get_play(play_id)
	# Chalked up on a wood-framed board, like the rest of the coach's X's and O's.
	var board := StyleBoxFlat.new()
	board.bg_color = UIKit.CHALKBOARD
	board.set_corner_radius_all(4)
	board.set_border_width_all(0 if compact else 5)
	board.border_color = UIKit.CHALK_WOOD
	draw_style_box(board, Rect2(Vector2.ZERO, size))
	if pl.is_empty():
		return
	_fit_depth()

	# Yard grid every 5 yards.
	for d in range(-5, int(_depth_fwd) + 1, 5):
		var y := _to_px(Vector2(d, 0)).y
		var col := Color(UIKit.CHALK, 0.30 if d == 0 else 0.10)
		draw_line(Vector2(4, y), Vector2(size.x - 4, y), col, 2.0 if d == 0 else 1.0)

	var r := 6.0 if not compact else 4.0
	var font := UIKit.FONT_MARKER
	var chalk := Color(UIKit.CHALK, 0.9)
	var fs := 11 if not compact else 8

	# Interior line: center plus four tackles.
	for off in [-5.2, -2.6, 0.0, 2.6, 5.2]:
		var p := _to_px(Vector2(0, off))
		draw_arc(p, r, 0, TAU, 16, Color(UIKit.CHALK, 0.55), 2.0, true)

	# Quarterback.
	var qbp := _to_px(Vector2(-5, 0))
	draw_arc(qbp, r, 0, TAU, 16, chalk, 2.0, true)
	if not compact:
		draw_string(font, qbp + Vector2(-4, -r - 3.0), "Q", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, chalk)

	var aligns: Array = pl["align"]
	var routes: Array = pl["routes"]
	var slot_pos: Array = pl["slot_pos"]

	for i in 5:
		var a: Vector2 = aligns[i]
		var start := _to_px(a)
		var assign = routes[i]

		if assign is String:
			var col := Color("ffb38a") if assign == PlayDB.CARRY else Color(UIKit.CHALK, 0.55)
			draw_arc(start, r, 0, TAU, 16, col, 2.0, true)
			if assign == PlayDB.CARRY:
				var tip := _to_px(a + Vector2(6, 0))
				_arrow(start, tip, col, 2.0)
			else:
				draw_arc(start, r + 3.0, 0, TAU, 16, col, 1.5, true)
		else:
			var pts := PackedVector2Array([start])
			var acc := a
			for wp in assign:
				acc = Vector2(a.x + wp.x, a.y + wp.y)
				pts.append(_to_px(acc))
			if pts.size() >= 2:
				draw_polyline(pts, Color(UIKit.CHALK, 0.12), 6.0, true)
				draw_polyline(pts, chalk, 2.0, true)
				_arrow(pts[pts.size() - 2], pts[pts.size() - 1], chalk, 2.0)
			draw_arc(start, r, 0, TAU, 16, chalk, 2.0, true)

		if not compact:
			var tag := str(slot_pos[i])
			var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, start + Vector2(-tw * 0.5, r + fs + 2.0), tag,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UIKit.CHALK, 0.6))


func _arrow(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var dir := (b - a)
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var head := 6.0 if not compact else 4.0
	draw_colored_polygon(PackedVector2Array([
		b + dir * head, b - dir * head * 0.4 + perp * head * 0.7, b - dir * head * 0.4 - perp * head * 0.7
	]), col)
