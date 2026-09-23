class_name RouteThumb
extends Control

## A single route drawn small, for the chalkboard cards on the match screen.
##
## `route` is waypoints relative to the player's alignment, in yards, same
## frame as RouteBook: x downfield, y lateral. The view auto-fits whatever
## shape it is given, so a five yard flat and a thirty yard post both fill
## the card instead of one of them being a speck in the corner.

@export var route: Array = []
@export var drawn: bool = false

const PAD := 10.0
const MIN_SPAN := 8.0


func _ready() -> void:
	# Only a default - a caller that sized the thumb before adding it to the
	# tree keeps its own size.
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(118, 72)
	resized.connect(queue_redraw)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101d18"))
	if route.is_empty():
		return

	# Bounds over the whole path, the player's own spot included.
	var lo := Vector2.ZERO
	var hi := Vector2.ZERO
	for wp in route:
		lo.x = minf(lo.x, wp.x); lo.y = minf(lo.y, wp.y)
		hi.x = maxf(hi.x, wp.x); hi.y = maxf(hi.y, wp.y)
	var span := Vector2(maxf(hi.x - lo.x, MIN_SPAN), maxf(hi.y - lo.y, MIN_SPAN))
	# One shared scale for both axes, so the shape is never stretched into
	# something it is not - a slant has to still look like a slant.
	var s := minf((size.y - PAD * 2.0) / span.x, (size.x - PAD * 2.0) / span.y)
	var mid := (lo + hi) * 0.5

	var to_px := func(v: Vector2) -> Vector2:
		return Vector2(size.x * 0.5 + (v.y - mid.y) * s, size.y * 0.5 - (v.x - mid.x) * s)

	var pts := PackedVector2Array([to_px.call(Vector2.ZERO)])
	for wp in route:
		pts.append(to_px.call(wp))

	var col := Color("f2f6ef") if drawn else Color("93a89c")
	if pts.size() >= 2:
		draw_polyline(pts, Color(col, 0.12), 6.0, true)
		draw_polyline(pts, Color(col, 0.85), 2.2, true)

		var a := pts[pts.size() - 2]
		var b := pts[pts.size() - 1]
		var dir := (b - a).normalized()
		if dir != Vector2.ZERO:
			var perp := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([
				b + dir * 6.0, b - dir * 3.0 + perp * 4.0, b - dir * 3.0 - perp * 4.0
			]), Color(col, 0.9))

	# Where the player starts from.
	draw_circle(pts[0], 3.5, Color(col, 0.95))
