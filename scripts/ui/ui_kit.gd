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

## The look of things written on paper by the coach (UIKit.play_card,
## PlayCard): a cream index card with faint blue rules, inked in blue,
## black and red pen, with a chalkboard for X's and O's.
const PAPER := Color("f3ead2")
const PAPER_RULE := Color("cfdcec")
const INK := Color("23262b")
const INK_MUTED := Color("5b5f66")
const INK_BLUE := Color("1a3d8f")
const INK_RED := Color("c8372d")
const CHALKBOARD := Color("203127")
const CHALK_WOOD := Color("6b4a2b")

## Fonts. BLOCK (Oswald) is the game-wide default - set as the project's
## custom font, so every Label and Button already uses it - and the tall
## athletic face for numbers and headers. MARKER (Permanent Marker) is for
## anything the coach wrote by hand.
const FONT_BLOCK := preload("res://assets/fonts/Oswald.ttf")
const FONT_MARKER := preload("res://assets/fonts/PermanentMarker.ttf")

const TURF_SHADER := preload("res://assets/shaders/turf.gdshader")

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


## A stadium panel: dark, a touch see-through so the turf reads at its edges,
## with a hairline rim and a soft shadow lifting it off the grass. `color`
## overrides the fill (still made a little see-through).
static func panel(color: Color = PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := stylebox(Color(color.darkened(0.25), 0.9), 10, 1, Color(1, 1, 1, 0.09))
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 4)
	p.add_theme_stylebox_override("panel", sb)
	return p


## A wood-framed chalkboard to draw X's and O's on (or lay out a formation).
static func chalkboard() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := stylebox(CHALKBOARD, 8, 6, CHALK_WOOD)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 5)
	p.add_theme_stylebox_override("panel", sb)
	return p


## Text chalked onto a chalkboard: the marker hand, in chalk white.
static func chalk_label(text: String, size: int = 15, alpha: float = 0.9) -> Label:
	return marker_label(text, size, Color(CHALK, alpha))


## A stadium scoreboard readout: a small caption over a big amber number in a
## black box - for football bucks, scores, anything worth counting.
static func scoreboard(caption: String, value: String, value_size: int = 28) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := stylebox(Color("0b0f0d"), 6, 2, Color("3a3f3b"))
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -4)
	p.add_child(v)
	var cap := label(caption.to_upper(), 11, Color("8f9a93"))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	var num := label(value, value_size, Color("ffb52e"))
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(num)
	return p


## Text set straight on the turf gets a dark outline so it reads over grass.
static func outlined(l: Label, size: int = 6) -> Label:
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", size)
	return l


## A thrown penalty flag with the message beside it - for "not enough bucks"
## and the like.
static func flag_notice(text: String, size: int = 15) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var flag := Control.new()
	flag.custom_minimum_size = Vector2(22, 22)
	flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flag.draw.connect(func():
		# A yellow cloth knotted at one corner, the weight's knot dark.
		var pts := PackedVector2Array([Vector2(3, 3), Vector2(20, 6), Vector2(17, 20), Vector2(2, 17)])
		flag.draw_colored_polygon(pts, Color("f5d000"))
		flag.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.6), 1.5, true)
		flag.draw_circle(Vector2(4, 4), 3.0, Color("2b2b2b")))
	h.add_child(flag)
	h.add_child(outlined(label(text, size, Color("ffe36b")), 5))
	return h


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


## A rounded, pill-shaped primary_button - for the floating calls to action
## that sit over the field rather than inside a panel.
static func pill_button(text: String, size: int = 16) -> Button:
	var b := primary_button(text, size)
	for state in ["normal", "hover", "pressed"]:
		var sb: StyleBoxFlat = b.get_theme_stylebox(state).duplicate()
		sb.set_corner_radius_all(22)
		sb.content_margin_left = 26
		sb.content_margin_right = 26
		b.add_theme_stylebox_override(state, sb)
	b.custom_minimum_size = Vector2(220, 44)
	return b


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


## Rarity color for a hardcoded player's tier (ShopPlayerDB.QUALITY_*), low
## to high - used as card outlines so the tier reads at a glance.
static func quality_color(q: int) -> Color:
	match q:
		ShopPlayerDB.QUALITY_ROOKIE: return Color("8a8f96")
		ShopPlayerDB.QUALITY_SOPHOMORE: return Color("5aa9e6")
		ShopPlayerDB.QUALITY_VETERAN: return Color("a06cd5")
		ShopPlayerDB.QUALITY_ALL_STAR: return ACCENT
	return MUTED


## A compact one-line stat readout: STR 12  AGI 9 ... Stamina is deliberately
## omitted; the design doc keeps it hidden from the player.
static func stat_row(p: PlayerData, size: int = 13) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var mods := ItemDB.total_stat_mods(p.items)
	for key in p.shown_stats(STAT_KEYS):
		var v: int = p.stat(key)
		var l := label("%s %d" % [STAT_LABELS[key], v], size, stat_color(v))
		if mods.has(key):
			var delta: int = mods[key]
			l.text = "%s %d%s%d" % [STAT_LABELS[key], v, "+" if delta > 0 else "", delta]
			l.add_theme_color_override("font_color", GOOD if delta > 0 else BAD)
		box.add_child(l)
	return box


## Which collar-skin-tone variant of the front body art goes with a given
## head_id (HeadArtDB), so the sliver of neck the jersey shows off matches
## the head sitting on top of it. Unlisted head ids (the default "1" roll,
## and any other named head) fall back to the plain, no-suffix file - the
## original tone the body art shipped with.
const HEAD_SKIN_TONE_SUFFIX := {
	"2": "_dark",
	"cursed": "_pale",
}

## Body sprite for `p`, or null if its `body` id doesn't resolve to one of
## the extracted assets/players/<view>/body_0N.png files (e.g. hardcoded
## QBDB entries that haven't had a body picked yet). `jersey` is a JerseyDB
## colour; blue (the default) is the plain assets/players/<view>/ art, and
## anything a colour lacks falls back to blue.
static func body_texture(p: PlayerData, view: String = "front", jersey: String = JerseyDB.BLUE) -> Texture2D:
	var n := int(p.body)
	if n < 1 or n > 9:
		return null
	var suffix: String = HEAD_SKIN_TONE_SUFFIX.get(p.head_id, "") if view == "front" else ""
	var dirs: Array = ["%s/%s" % [jersey, view], view] if jersey != JerseyDB.BLUE else [view]
	for dir in dirs:
		for sfx in [suffix, ""]:
			var path := "res://assets/players/%s/body_%02d%s.png" % [dir, n, sfx]
			if ResourceLoader.exists(path):
				return load(path)
	return null


## Small boxed portrait for `p`, or null if it has no body art yet - callers
## should skip adding it rather than show an empty box. Layers a front-facing
## head (HeadArtDB) on top of the jersey art where that body's rig scene puts
## it (BodyArtDB.head_rig) - same placement field_view.gd uses on the field,
## just done with Control offsets instead of canvas draw calls.
static func player_portrait(p: PlayerData, size: int = 56) -> Control:
	var tex := body_texture(p, "front")
	if tex == null:
		return null
	var box := Panel.new()
	box.custom_minimum_size = Vector2(size, size)
	box.add_theme_stylebox_override("panel", stylebox(PANEL_HI, 8, 1))

	var margin := 4.0
	var inner := Vector2(size, size) - Vector2(margin, margin) * 2.0
	var tex_size := tex.get_size()
	var head_set := p.head_id if p.head_id != "" else "1"
	var head_tex := HeadArtDB.head_texture(head_set, "front")
	var rig := BodyArtDB.head_rig("front", p.body)

	# Everything below is in body-texture pixels, origin at the body's
	# centre, until the final fit. The head usually pokes out above the
	# jersey, so fit the union of the two rects - not the jersey alone - or
	# the head ends up off the top of the box.
	var body_size := tex_size * (rig["body_scale"] as Vector2)
	var body_rect := Rect2((rig["body_offset"] as Vector2) * tex_size - body_size * 0.5, body_size)
	var bounds := body_rect
	var head_rect := Rect2()
	var off: Vector2 = rig["offset"]
	var face_center := Vector2(off.x * tex_size.x, off.y * tex_size.y)
	if head_tex != null:
		# Sized by the face; any hair past it overflows (and is included in
		# the fit, so it doesn't poke out of the box either).
		var face_h: float = float(rig["height"]) * tex_size.y
		var draw := HeadArtDB.face_draw_rect(head_set, "front", head_tex, face_h)
		head_rect = Rect2(face_center + draw.position, draw.size)
		bounds = bounds.merge(head_rect)
	var k := minf(inner.x / bounds.size.x, inner.y / bounds.size.y)
	# Where the body centre (body-texture origin) lands in the box.
	var origin := Vector2(margin, margin) + (inner - bounds.size * k) * 0.5 - bounds.position * k

	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.position = origin + body_rect.position * k
	t.size = body_rect.size * k
	box.add_child(t)

	if head_tex != null:
		var head := TextureRect.new()
		head.texture = head_tex
		head.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		head.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.position = origin + head_rect.position * k
		head.size = head_rect.size * k
		# Turn about the face's centre, not the middle of the hair-and-all rect.
		head.pivot_offset = (face_center - head_rect.position) * k
		head.rotation = float(rig["rotation"])
		box.add_child(head)

	return box


## A bowl's logo (BowlDB.logo) on a white card backing, sized to `size`.
## The sheet's cells are opaque white squares rather than transparent
## cutouts, so this leans into that as a deliberate patch/badge look
## instead of fighting it. `dim` greys out an unearned bowl - see
## qb_select.gd's completion marks.
## `boxed` sits the logo on a white rounded tile; without it the cut-out logo
## is drawn straight onto whatever's behind it. `dim` greys it out (a bowl
## not yet won).
static func bowl_badge(bowl_id: String, size: int = 64, dim: bool = false, boxed: bool = true) -> Control:
	var tex := BowlDB.logo(bowl_id)
	if tex == null:
		return null
	var box: Control
	if boxed:
		box = Panel.new()
		box.add_theme_stylebox_override("panel", stylebox(Color.WHITE, 8, 1, LINE))
	else:
		box = Control.new()
	box.custom_minimum_size = Vector2(size, size)
	box.tooltip_text = BowlDB.bowl_name(bowl_id)
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad := 3 if boxed else 0
	t.offset_left = pad
	t.offset_top = pad
	t.offset_right = -pad
	t.offset_bottom = -pad
	if dim:
		t.modulate = Color(0.55, 0.55, 0.55, 0.6) if boxed else Color(0.3, 0.3, 0.3, 0.45)
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
	if p.quality == ShopPlayerDB.QUALITY_ODDITY:
		head.add_child(label("ODDITY", 12, OddityPlayerDB.COLOR))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(label("OVR %d" % p.overall(), 14, stat_color(p.overall())))
	v.add_child(head)

	v.add_child(stat_row(p))

	var ab := label("* %s" % AbilityDB.ability_desc(p.ability_id), 12, Color("9fc0b2"))
	ab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(ab)

	if show_item:
		var equipped := p.equipped_items()
		if equipped.is_empty():
			v.add_child(label("Items: none", 12, MUTED))
		for item_id in equipped:
			var il := label("Item: %s (%s)" % [ItemDB.item_name(item_id), ItemDB.item_desc(item_id)], 12, ACCENT)
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


## A full-screen illustrated background (e.g. assets/ritual.png), scaled to
## cover the window, with a black `shade` over it so text stays readable.
## Call it in _ready right after background() and before building anything
## else - it adds to the end of the child list, so it lands above the plain
## background (still there as a fallback) and under everything built after.
## Both nodes carry the "backdrop" meta: screens that rebuild by clearing
## their children should skip anything with it.
static func backdrop(root: Control, path: String, shade: float = 0.3) -> void:
	var tex := load(path) as Texture2D
	if tex != null:
		var art := TextureRect.new()
		art.texture = tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.set_meta("backdrop", true)
		root.add_child(art)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, shade)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_meta("backdrop", true)
	root.add_child(dim)


## A label in the coach's handwriting (FONT_MARKER).
static func marker_label(text: String, size: int = 15, color: Color = INK) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", FONT_MARKER)
	return l


## Every screen's backdrop: a mowed field (assets/shaders/turf.gdshader).
## Still a ColorRect - screens that rebuild skip their ColorRect children -
## with BG as the color underneath in case the shader can't run. `night`
## turns on the stadium floodlights and a vignette (the title screen).
static func background(root: Control, night: bool = false) -> void:
	var cr := ColorRect.new()
	cr.color = BG
	var mat := ShaderMaterial.new()
	mat.shader = TURF_SHADER
	if night:
		mat.set_shader_parameter("floodlight", 1.0)
		mat.set_shader_parameter("vignette", 0.55)
	cr.material = mat
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cr)
	root.move_child(cr, 0)


## Standard header strip: title on the left, bucks and round on the right.
## Standard header strip: the screen's title on the turf on the left, the
## bucks on a scoreboard on the right.
static func header(title_text: String, subtitle: String = "") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 0)
	left.add_child(outlined(label(title_text.to_upper(), 34, ACCENT)))
	if subtitle != "":
		left.add_child(outlined(label(subtitle, 15, TEXT), 5))
	h.add_child(left)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	var bucks := scoreboard("Football bucks", "$%d" % GameState.bucks)
	bucks.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bucks)
	return h
