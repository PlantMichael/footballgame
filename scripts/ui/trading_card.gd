class_name TradingCard
extends PanelContainer

## A player as a football trading card: white card stock, a tier-colored foil
## banner across the top, a "photo" of him against the stadium in a frame of
## the same color, a nameplate with his number and position, the back-of-card
## stat box, and what his ability does. `footer` (a sign button, a price) sits
## at the bottom; everything above it stays put, so a row of cards with
## different-length abilities still lines their footers up.

const STOCK := Color("f4f1e8")
const PLATE := Color("1d2420")
const PHOTO_H := 132

var tier_color: Color = UIKit.MUTED


func _init(p: PlayerData, tier_name: String, tier_col: Color, footer: Control = null) -> void:
	tier_color = tier_col
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)

	v.add_child(_banner(tier_name.to_upper()))
	v.add_child(_photo(p))
	v.add_child(_nameplate(p))
	v.add_child(_stat_box(p))

	var ab := UIKit.label(AbilityDB.ability_desc(p.ability_id) if p.ability_id != ""
		else "No special ability.", 13, UIKit.INK if p.ability_id != "" else UIKit.INK_MUTED)
	ab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ab.custom_minimum_size = Vector2(150, 0)
	v.add_child(ab)

	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)
	if footer != null:
		v.add_child(footer)


func _draw() -> void:
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0.3)
	shadow.set_corner_radius_all(10)
	draw_style_box(shadow, Rect2(Vector2(3, 5), size))
	var card := StyleBoxFlat.new()
	card.bg_color = STOCK
	card.set_corner_radius_all(10)
	card.set_border_width_all(5)
	card.border_color = tier_color
	draw_style_box(card, Rect2(Vector2.ZERO, size))
	# A thin inner keyline, like a printed border.
	var key := StyleBoxFlat.new()
	key.draw_center = false
	key.set_corner_radius_all(6)
	key.set_border_width_all(1)
	key.border_color = Color(tier_color, 0.55)
	draw_style_box(key, Rect2(Vector2(8, 8), size - Vector2(16, 16)))


## The foil stripe across the top with his tier on it.
func _banner(text: String) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 24)
	var col := tier_color
	c.draw.connect(func():
		var w := c.size.x
		var pts := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w - 10, c.size.y), Vector2(10, c.size.y)])
		c.draw_colored_polygon(pts, col)
		# A glint across the foil.
		c.draw_colored_polygon(PackedVector2Array([Vector2(w * 0.55, 0), Vector2(w * 0.62, 0),
			Vector2(w * 0.56, c.size.y), Vector2(w * 0.49, c.size.y)]), Color(1, 1, 1, 0.25))
		var font := UIKit.FONT_BLOCK
		var fs := 14
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		c.draw_string(font, Vector2((w - tw) * 0.5, 18), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			col.darkened(0.7) if col.get_luminance() > 0.45 else Color.WHITE))
	return c


## His picture: him in front of the stands, in a tier-colored frame.
func _photo(p: PlayerData) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(0, PHOTO_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("2f4f7a")   # evening sky over the stadium
	sb.set_border_width_all(3)
	sb.border_color = tier_color
	frame.add_theme_stylebox_override("panel", sb)
	var scene := Control.new()
	scene.clip_contents = true
	scene.draw.connect(func():
		var s := scene.size
		# Stands, a band of lights, then grass along the bottom.
		scene.draw_rect(Rect2(0, s.y * 0.38, s.x, s.y * 0.32), Color("23324a"))
		for i in 7:
			scene.draw_circle(Vector2(s.x * (0.08 + i * 0.14), s.y * 0.4), 2.0, Color(1, 0.95, 0.75, 0.8))
		scene.draw_rect(Rect2(0, s.y * 0.7, s.x, s.y * 0.3), Color("2e6b3a")))
	frame.add_child(scene)
	var center := CenterContainer.new()
	scene.add_child(center)
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var portrait := UIKit.player_portrait(p, PHOTO_H - 12)
	if portrait != null:
		portrait.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(portrait)
	return frame


## The dark nameplate under the photo: number badge, name, position.
func _nameplate(p: PlayerData) -> Control:
	var plate := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PLATE
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	plate.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	plate.add_child(h)
	var num := UIKit.label(str(p.number), 20, tier_color.lightened(0.15))
	num.custom_minimum_size = Vector2(28, 0)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(num)
	var name_label := UIKit.label(p.pname, 16, Color.WHITE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(name_label)
	h.add_child(UIKit.label(p.pos_name(), 14, Color("c8d3cc")))
	return plate


## The back-of-card numbers: each shown stat, and his overall.
func _stat_box(p: PlayerData) -> Control:
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 2)
	var keys: Array = p.shown_stats(UIKit.STAT_KEYS)
	for key in keys:
		grid.add_child(_stat_cell(UIKit.STAT_LABELS[key], p.stat(key), false))
	grid.add_child(_stat_cell("OVR", p.overall(), true))
	return grid


func _stat_cell(caption: String, value: int, big: bool) -> Control:
	var cell := PanelContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(tier_color, 0.16) if big else Color(0, 0, 0, 0.05)
	sb.set_corner_radius_all(3)
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	cell.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -4)
	cell.add_child(v)
	var cap := UIKit.label(caption, 10, UIKit.INK_MUTED)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	var val := UIKit.label(str(value), 18, UIKit.INK)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(val)
	return cell
