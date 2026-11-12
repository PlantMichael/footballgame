class_name ScoreDigits
extends Label

## Keep a real Label's text/sizing/semantics; render it as a stadium display.
## Label.text and resize already schedule redraws, so no processing is needed.
const DIGITS := [0b1111110, 0b0110000, 0b1101101, 0b1111001, 0b0110011,
	0b1011011, 0b1011111, 0b1110000, 0b1111111, 0b1111011]
const AMBER := Color("ffc567")

func _init() -> void:
	add_theme_color_override("font_color", Color.TRANSPARENT)
	add_theme_font_size_override("font_size", 24)
	custom_minimum_size = Vector2(76, 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var shown := text.lpad(2, "0")
	var height := minf(36.0, size.y - 4.0)
	height = minf(height, (size.x - 8.0) / (shown.length() * 0.55 + (shown.length() - 1) * 0.15))
	if height <= 0.0:
		return
	var width := height * 0.55
	var gap := height * 0.15
	var start := (size.x - (width + gap) * shown.length() + gap) * 0.5
	var segments := [
		[Vector2(0.1, 0.05), Vector2(0.9, 0.05)],
		[Vector2(0.94, 0.1), Vector2(0.94, 0.45)],
		[Vector2(0.94, 0.55), Vector2(0.94, 0.9)],
		[Vector2(0.1, 0.95), Vector2(0.9, 0.95)],
		[Vector2(0.06, 0.55), Vector2(0.06, 0.9)],
		[Vector2(0.06, 0.1), Vector2(0.06, 0.45)],
		[Vector2(0.13, 0.5), Vector2(0.87, 0.5)],
	]
	for i in shown.length():
		var digit := int(shown[i])
		var origin := Vector2(start + i * (width + gap), (size.y - height) * 0.5)
		for segment in 7:
			var lit: bool = (DIGITS[digit] & (1 << (6 - segment))) != 0
			var a: Vector2 = origin + segments[segment][0] * Vector2(width, height)
			var b: Vector2 = origin + segments[segment][1] * Vector2(width, height)
			var thickness := height * 0.075
			if lit:
				draw_line(a, b, Color(AMBER, 0.09), thickness * 2.6, true)
			var direction := (b - a).normalized()
			var normal := Vector2(-direction.y, direction.x) * thickness * 0.5
			draw_colored_polygon(PackedVector2Array([a - direction * thickness * 0.35,
				a + normal, b + normal, b + direction * thickness * 0.35, b - normal, a - normal]),
				AMBER if lit else Color(AMBER, 0.055))
