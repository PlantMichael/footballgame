class_name ChalkDiagram
extends Control

## A little X's-and-O's play on a wood-framed chalkboard, for cards. `play`
## is drawn in a fixed FRAME of board units (y down, the line of scrimmage at
## LOS_Y) and scaled to fit:
##   "o"      Array[Vector2] - the offense, drawn as circles
##   "x"      Array[Vector2] - the defense, drawn as X's
##   "routes" Array of point arrays - solid chalk with an arrowhead
##   "throws" Array of point arrays - dashed, for a ball in the air

const FRAME := Vector2(200, 86)
const LOS_Y := 60.0
const CHALK := Color("e8f0ea")

var play: Dictionary = {}


func _init(play_data: Dictionary = {}) -> void:
	play = play_data
	custom_minimum_size = Vector2(0, 92)


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var board := StyleBoxFlat.new()
	board.bg_color = UIKit.CHALKBOARD
	board.set_corner_radius_all(4)
	board.set_border_width_all(3)
	board.border_color = UIKit.CHALK_WOOD
	draw_style_box(board, Rect2(Vector2.ZERO, size))

	var inner := size - Vector2(6, 6)
	var k := minf(inner.x / FRAME.x, inner.y / FRAME.y)
	var origin := Vector2(3, 3) + (inner - FRAME * k) * 0.5
	var at := func(p: Vector2) -> Vector2: return origin + p * k

	_dashed(at.call(Vector2(10, LOS_Y)), at.call(Vector2(190, LOS_Y)), Color(CHALK, 0.45), 1.5, 4.0 * k)

	for pts in play.get("routes", []):
		var line := PackedVector2Array()
		for p in pts:
			line.append(at.call(p))
		draw_polyline(line, Color(CHALK, 0.12), 6.0, true)
		draw_polyline(line, Color(CHALK, 0.9), 2.0, true)
		_arrow(line, Color(CHALK, 0.9))
	for pts in play.get("throws", []):
		for i in range(1, pts.size()):
			_dashed(at.call(pts[i - 1]), at.call(pts[i]), Color(CHALK, 0.8), 2.0, 5.0 * k)
	for p in play.get("o", []):
		draw_arc(at.call(p), 5.0 * k, 0.0, TAU, 20, Color(CHALK, 0.9), 2.0, true)
	for p in play.get("x", []):
		var c: Vector2 = at.call(p)
		var h := 4.0 * k
		draw_line(c + Vector2(-h, -h), c + Vector2(h, h), Color(CHALK, 0.9), 2.0, true)
		draw_line(c + Vector2(h, -h), c + Vector2(-h, h), Color(CHALK, 0.9), 2.0, true)


func _arrow(line: PackedVector2Array, col: Color) -> void:
	if line.size() < 2:
		return
	var b := line[line.size() - 1]
	var dir := (b - line[line.size() - 2]).normalized()
	if dir == Vector2.ZERO:
		return
	var perp := Vector2(-dir.y, dir.x)
	draw_line(b, b - dir * 7.0 + perp * 4.0, col, 2.0, true)
	draw_line(b, b - dir * 7.0 - perp * 4.0, col, 2.0, true)


func _dashed(a: Vector2, b: Vector2, col: Color, width: float, dash: float) -> void:
	var length := a.distance_to(b)
	var t := 0.0
	while t < length:
		var e := minf(t + dash, length)
		draw_line(a.lerp(b, t / length), a.lerp(b, e / length), col, width, true)
		t += dash * 2.0
