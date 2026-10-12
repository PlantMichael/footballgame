class_name PlayCard
extends PanelContainer

## A coach's index card: cream paper with faint blue rules, a binder clip
## across the top, a drop shadow lifting it off the turf, and an optional red
## position tag stuck to the right edge. Fill it like any PanelContainer -
## the paper is drawn behind whatever it holds. Ink colors and fonts to write
## on it with live in UIKit (INK*, FONT_MARKER).

const RULE_GAP := 22.0
const CLIP_SIZE := Vector2(70, 20)
const SHADOW := Vector2(3, 5)

## Text on the red tab at the top-right corner, e.g. "QB". "" for none.
var tag: String = ""


func _init(tag_text: String = "") -> void:
	tag = tag_text
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 22
	sb.content_margin_bottom = 14
	add_theme_stylebox_override("panel", sb)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)

	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0.28)
	shadow.set_corner_radius_all(6)
	draw_style_box(shadow, Rect2(SHADOW, size))

	var paper := StyleBoxFlat.new()
	paper.bg_color = UIKit.PAPER
	paper.set_corner_radius_all(6)
	draw_style_box(paper, r)

	# Ruled like an index card, clear of the rounded corners.
	var y := RULE_GAP
	while y < size.y - 4.0:
		draw_line(Vector2(3, y), Vector2(size.x - 3, y), UIKit.PAPER_RULE, 1.0)
		y += RULE_GAP

	# The binder clip it hangs from.
	var clip := StyleBoxFlat.new()
	clip.bg_color = Color("9aa3ab")
	clip.set_corner_radius_all(4)
	clip.set_border_width_all(2)
	clip.border_color = Color("5f676e")
	draw_style_box(clip, Rect2(Vector2((size.x - CLIP_SIZE.x) * 0.5, -12), CLIP_SIZE))

	if tag != "":
		var font := UIKit.FONT_BLOCK
		var fs := 13
		var w := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 20.0
		var tab := Rect2(Vector2(size.x - w + 6, 10), Vector2(w, 20))
		draw_rect(tab, UIKit.INK_RED)
		draw_string(font, tab.position + Vector2(10, 15), tag, HORIZONTAL_ALIGNMENT_LEFT,
			-1, fs, Color("fbe9e7"))
