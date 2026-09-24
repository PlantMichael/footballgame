class_name UIKit
extends RefCounted

## Shared colors and widget builders. Every screen is constructed in code so
## the look stays consistent without hand-maintaining a dozen .tscn files.

const BG := Color("0d1512")
const PANEL := Color("152420")
const PANEL_HI := Color("1e332c")
const LINE := Color("2c4a40")
const TEXT := Color("dce8e2")
const MUTED := Color("7d968c")
const ACCENT := Color("f2c14e")
const GOOD := Color("6ec46e")
const BAD := Color("d9534f")
const TURF := Color("1d4429")
const TURF_ALT := Color("22502f")
const CHALK := Color("e8f0ea")
const OFFENSE := Color("f2c14e")
const DEFENSE := Color("5aa9e6")
const BALL := Color("c86b32")

const STAT_KEYS := ["strength", "agility", "dexterity", "intelligence"]
const STAT_LABELS := {
	"strength": "STR",
	"agility": "AGI",
	"dexterity": "DEX",
	"intelligence": "INT",
	"stamina": "STA",
}


static func stylebox(color: Color, radius: int = 6, border: int = 0, border_color: Color = LINE) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	if border > 0:
		sb.border_width_left = border
		sb.border_width_right = border
		sb.border_width_top = border
		sb.border_width_bottom = border
		sb.border_color = border_color
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


static func panel(color: Color = PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", stylebox(color, 8, 1))
	return p


static func label(text: String, size: int = 15, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func title(text: String) -> Label:
	return label(text, 30, ACCENT)


static func button(text: String, size: int = 15) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", ACCENT)
	b.add_theme_stylebox_override("normal", stylebox(PANEL_HI, 6, 1))
	b.add_theme_stylebox_override("hover", stylebox(LINE, 6, 1, ACCENT))
	b.add_theme_stylebox_override("pressed", stylebox(ACCENT.darkened(0.5), 6, 1, ACCENT))
	b.add_theme_stylebox_override("disabled", stylebox(PANEL, 6, 1))
	b.add_theme_color_override("font_disabled_color", MUTED)
	return b


static func primary_button(text: String, size: int = 18) -> Button:
	var b := button(text, size)
	b.add_theme_color_override("font_color", Color("13200f"))
	b.add_theme_color_override("font_hover_color", Color("13200f"))
	b.add_theme_stylebox_override("normal", stylebox(ACCENT, 6, 0))
	b.add_theme_stylebox_override("hover", stylebox(ACCENT.lightened(0.15), 6, 0))
	b.add_theme_stylebox_override("pressed", stylebox(ACCENT.darkened(0.2), 6, 0))
	b.custom_minimum_size = Vector2(0, 44)
	return b


static func hsep(amount: int = 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(amount, 0)
	return c


static func vsep(amount: int = 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, amount)
	return c


static func rule() -> HSeparator:
	var s := HSeparator.new()
	var sb := StyleBoxLine.new()
	sb.color = LINE
	sb.thickness = 1
	s.add_theme_stylebox_override("separator", sb)
	return s


static func stat_color(v: int) -> Color:
	if v >= 13:
		return GOOD
	if v >= 10:
		return Color("b8d98a")
	if v >= 7:
		return TEXT
	if v >= 4:
		return Color("d8a15a")
	return BAD


## A compact one-line stat readout: STR 12  AGI 9 ... Stamina is deliberately
## omitted; the design doc keeps it hidden from the player.
static func stat_row(p: PlayerData, size: int = 13) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var mods := ItemDB.stat_mods(p.item_id)
	for key in STAT_KEYS:
		var v: int = p.stat(key)
		var l := label("%s %d" % [STAT_LABELS[key], v], size, stat_color(v))
		if mods.has(key):
			var delta: int = mods[key]
			l.text = "%s %d%s%d" % [STAT_LABELS[key], v, "+" if delta > 0 else "", delta]
			l.add_theme_color_override("font_color", GOOD if delta > 0 else BAD)
		box.add_child(l)
	return box


## Body sprite for `p`, or null if its `body` id doesn't resolve to one of
## the extracted assets/players/<view>/body_0N.png files (e.g. hardcoded
## QBDB entries that haven't had a body picked yet).
static func body_texture(p: PlayerData, view: String = "front") -> Texture2D:
	var n := int(p.body)
	if n < 1 or n > 9:
		return null
	var path := "res://assets/players/%s/body_%02d.png" % [view, n]
	if not ResourceLoader.exists(path):
		return null
	return load(path)


## Small boxed portrait for `p`, or null if it has no body art yet - callers
## should skip adding it rather than show an empty box. Layers a front-facing
## head (HeadArtDB) on top of the jersey art, anchored at that sprite's own
## collar depth (BodyArtDB) - same idea as field_view.gd's live-match
## rendering, just done with Control offsets instead of canvas draw calls.
static func player_portrait(p: PlayerData, size: int = 56) -> Control:
	var tex := body_texture(p, "front")
	if tex == null:
		return null
	var box := Panel.new()
	box.custom_minimum_size = Vector2(size, size)
	box.add_theme_stylebox_override("panel", stylebox(PANEL_HI, 8, 1))
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.offset_left = 4
	t.offset_top = 4
	t.offset_right = -4
	t.offset_bottom = -4
	box.add_child(t)

	var head_tex := HeadArtDB.head_texture(p.head_id if p.head_id != "" else "1", "front")
	if head_tex != null:
		# STRETCH_KEEP_ASPECT_CENTERED letterboxes the body texture inside
		# `t`'s rect - work out where it actually landed so the head can be
		# anchored on the real collar instead of a fixed generic offset.
		var inner := Vector2(size - 8.0, size - 8.0)
		var tex_size := tex.get_size()
		var k := minf(inner.x / tex_size.x, inner.y / tex_size.y)
		var drawn_h := tex_size.y * k
		var drawn_top := (inner.y - drawn_h) * 0.5 + 4.0
		var neck_y := drawn_top + drawn_h * BodyArtDB.neck_frac("front", p.body)

		var head_h := drawn_h * 0.34
		var head := TextureRect.new()
		head.texture = head_tex
		head.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		head.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.position = Vector2((size - head_h) * 0.5, neck_y - head_h * 0.92)
		head.size = Vector2(head_h, head_h)
		box.add_child(head)

	return box


## A bowl's logo (BowlDB.logo) on a white card backing, sized to `size`.
## The sheet's cells are opaque white squares rather than transparent
## cutouts, so this leans into that as a deliberate patch/badge look
## instead of fighting it. `dim` greys out an unearned bowl - see
## qb_select.gd's completion marks.
static func bowl_badge(bowl_id: String, size: int = 64, dim: bool = false) -> Control:
	var tex := BowlDB.logo(bowl_id)
	if tex == null:
		return null
	var box := Panel.new()
	box.custom_minimum_size = Vector2(size, size)
	box.add_theme_stylebox_override("panel", stylebox(Color.WHITE, 8, 1, LINE))
	box.tooltip_text = BowlDB.bowl_name(bowl_id)
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.offset_left = 3
	t.offset_top = 3
	t.offset_right = -3
	t.offset_bottom = -3
	if dim:
		t.modulate = Color(0.55, 0.55, 0.55, 0.6)
	box.add_child(t)
	return box


## Full player card used by the lineup and shop screens.
static func player_card(p: PlayerData, show_item: bool = true) -> HBoxContainer:
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	var portrait := player_portrait(p, 56)
	if portrait:
		outer.add_child(portrait)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(label("#%d" % p.number, 13, MUTED))
	head.add_child(label(p.pname, 16, TEXT))
	head.add_child(label(p.pos_name(), 13, ACCENT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(label("OVR %d" % p.overall(), 14, stat_color(p.overall())))
	v.add_child(head)

	v.add_child(stat_row(p))

	var ab := label("* %s: %s" % [AbilityDB.ability_name(p.ability_id), AbilityDB.ability_desc(p.ability_id)], 12, Color("9fc0b2"))
	ab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(ab)

	if show_item:
		var item_text := "Item: none"
		if p.item_id != "":
			item_text = "Item: %s (%s)" % [ItemDB.item_name(p.item_id), ItemDB.item_desc(p.item_id)]
		var il := label(item_text, 12, ACCENT if p.item_id != "" else MUTED)
		il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(il)

	return outer


static func scroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


static func background(root: Control) -> void:
	var cr := ColorRect.new()
	cr.color = BG
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cr)
	root.move_child(cr, 0)


## Standard header strip: title on the left, bucks and round on the right.
static func header(title_text: String, subtitle: String = "") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var left := VBoxContainer.new()
	left.add_child(title(title_text))
	if subtitle != "":
		left.add_child(label(subtitle, 14, MUTED))
	h.add_child(left)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_END
	var bucks := label("$%d" % GameState.bucks, 26, ACCENT)
	bucks.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(bucks)
	var fb := label("football bucks", 12, MUTED)
	fb.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(fb)
	h.add_child(right)
	return h
