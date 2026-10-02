extends Control

## The Ritual Site: sacrifice roster players, permanently, for one random
## Cursed player (CursedPlayerDB) in return. A stop on the run map (hub.gd),
## locked until its challenge is completed - one ritual per visit. The cost
## escalates with GameState.rituals_completed - 2 players the first visit, 3
## the next, and so on - so it stays a real trade instead of a repeatable
## freebie once a run has a few cursed players already.
##
## Laid out over assets/ritual.png: one empty square per player owed, sitting
## on the pentagram. Click a square to pick who goes in it from your roster;
## once every square is filled the ritual can be completed.

const RITUAL_COLOR := Color("b060e0")
const BASE_SACRIFICE_COUNT := 2
const BACKGROUND := "res://assets/ritual.png"
const SQUARE := Vector2(150, 190)

var _revealed: PlayerData = null

## How many players this particular ritual costs - fixed for the lifetime of
## this screen instance so the requirement can't shift under the coach mid-
## selection. Set from GameState.rituals_completed in _ready.
var _sacrifice_count: int = BASE_SACRIFICE_COUNT

## Roster index offered in each square, -1 for an empty one.
var _slots: Array[int] = []

## The square whose player picker is open, -1 when it's closed.
var _picking: int = -1


func _ready() -> void:
	_sacrifice_count = BASE_SACRIFICE_COUNT + GameState.rituals_completed
	for i in _sacrifice_count:
		_slots.append(-1)
	UIKit.background(self)
	get_child(0).set_meta("backdrop", true)
	UIKit.backdrop(self, BACKGROUND, 0.2)
	_build()


func _build() -> void:
	for c in get_children():
		if c.has_meta("backdrop"):
			continue
		c.queue_free()

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	if _revealed != null:
		_build_reveal(root)
		return

	var head := _veil()
	var head_v := VBoxContainer.new()
	head_v.add_theme_constant_override("separation", 4)
	head.add_child(head_v)
	var title := UIKit.label("THE RITUAL SITE", 32, RITUAL_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head_v.add_child(title)
	var desc := UIKit.label(
		"The circle wants %d of your players - forever. Fill every square and a Cursed player rises in their place. Anything they're wearing goes back in the bag." % _sacrifice_count,
		15, UIKit.TEXT)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(620, 0)
	head_v.add_child(desc)
	root.add_child(_centered(head))

	# The squares sit low, on the pentagram.
	var top_space := Control.new()
	top_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_space.size_flags_stretch_ratio = 2.2
	root.add_child(top_space)

	var squares := HBoxContainer.new()
	squares.add_theme_constant_override("separation", 22)
	for i in _slots.size():
		squares.add_child(_square(i))
	root.add_child(_centered(squares))

	var low_space := Control.new()
	low_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(low_space)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	var filled := _slots.count(-1) == 0
	var confirm := UIKit.primary_button("  Complete the Ritual  ", 18)
	confirm.custom_minimum_size = Vector2(0, 46)
	confirm.disabled = not filled
	confirm.pressed.connect(_sacrifice)
	buttons.add_child(confirm)
	var back := UIKit.button("  Back to the map (no sacrifice)  ", 15)
	back.custom_minimum_size = Vector2(0, 46)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"))
	buttons.add_child(back)
	root.add_child(_centered(buttons))

	if _picking >= 0:
		_build_picker()


## A dark translucent panel to sit text on over the artwork.
func _veil(border: Color = Color(RITUAL_COLOR, 0.6)) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UIKit.stylebox(Color(0.03, 0.01, 0.05, 0.78), 10, 2, border)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	p.add_theme_stylebox_override("panel", sb)
	return p


func _centered(c: Control) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.add_child(c)
	return cc


## One offering square: a "+" while empty, the player once one is picked.
## Clicking it (either way) opens the picker for this square.
func _square(i: int) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)

	var b := Button.new()
	b.custom_minimum_size = SQUARE
	var filled := _slots[i] >= 0
	var normal := UIKit.stylebox(Color(0.06, 0.0, 0.09, 0.82), 12, 3,
		RITUAL_COLOR if filled else Color(RITUAL_COLOR, 0.75))
	var hover := UIKit.stylebox(Color(0.16, 0.03, 0.2, 0.9), 12, 3, RITUAL_COLOR.lightened(0.25))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func():
		_picking = i
		_build())
	col.add_child(b)

	var inner := VBoxContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 2)
	b.add_child(inner)

	if not filled:
		var plus := UIKit.label("+", 72, RITUAL_COLOR)
		plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(plus)
		var hint := UIKit.label("Offer a player", 12, UIKit.MUTED)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(hint)
		return col

	var p: PlayerData = GameState.roster[_slots[i]]
	var portrait := UIKit.player_portrait(p, 84)
	if portrait:
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pc := CenterContainer.new()
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc.add_child(portrait)
		inner.add_child(pc)
	var name_label := UIKit.label(p.pname, 14)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(SQUARE.x - 16, 0)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(name_label)
	var pos := UIKit.label("%s  OVR %d" % [p.pos_name(), p.overall()], 12, UIKit.MUTED)
	pos.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(pos)

	var remove := UIKit.button("Remove", 12)
	remove.pressed.connect(func():
		_slots[i] = -1
		_build())
	col.add_child(remove)
	return col


## The roster list for the square being filled, over a dimmed screen.
## Players already offered in another square are left out.
func _build_picker() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_picking = -1
			_build())
	add_child(shade)

	var panel := _veil(RITUAL_COLOR)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(780, 600)
	panel.offset_left = -390
	panel.offset_right = 390
	panel.offset_top = -300
	panel.offset_bottom = 300
	add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var head := HBoxContainer.new()
	var title := UIKit.label("WHO GOES INTO THE CIRCLE?", 22, RITUAL_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := UIKit.button("  Close  ", 14)
	close.pressed.connect(func():
		_picking = -1
		_build())
	head.add_child(close)
	v.add_child(head)
	v.add_child(UIKit.rule())

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	for idx in _roster_order():
		if _slots.has(idx) and _slots[_picking] != idx:
			continue
		list.add_child(_pick_row(idx))
	var scroll := UIKit.scroll(list)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)


## Starters first, in formation order, so it's obvious who you'd be pulling
## out of the lineup; then the bench.
func _roster_order() -> Array:
	var order: Array = []
	for slot in GameState.SLOT_ORDER:
		var idx := int(GameState.lineup.get(slot, -1))
		if idx >= 0 and not order.has(idx):
			order.append(idx)
	for i in GameState.roster.size():
		if not order.has(i):
			order.append(i)
	return order


func _pick_row(idx: int) -> Control:
	var p: PlayerData = GameState.roster[idx]
	var row := UIKit.panel(UIKit.PANEL_HI)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)

	var card := UIKit.player_card(p, false)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(card)
	h.add_child(_status_column(idx, p))

	var current := _slots[_picking] == idx
	var offer := UIKit.button("  In this square  " if current else "  Offer  ", 14)
	offer.add_theme_color_override("font_color", RITUAL_COLOR if current else Color("d9534f"))
	offer.pressed.connect(func():
		_slots[_picking] = idx
		_picking = -1
		_build())
	h.add_child(offer)
	return row


## Where he stands on the team: which lineup spot he starts at (or bench),
## and what's in each of his three item slots.
func _status_column(idx: int, p: PlayerData) -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(200, 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)

	var slot := _starting_slot(idx)
	if slot != "":
		v.add_child(UIKit.label("STARTING  -  %s" % _slot_name(slot), 13, UIKit.ACCENT))
	else:
		v.add_child(UIKit.label("BENCH", 13, UIKit.MUTED))

	for i in PlayerData.ITEM_SLOTS:
		var item_id: String = p.items[i]
		if item_id == "":
			continue
		var l := UIKit.label("%s: %s" % [ItemDB.category_name(ItemDB.CATEGORIES[i]), ItemDB.item_name(item_id)], 12, UIKit.TEXT)
		l.tooltip_text = ItemDB.item_desc(item_id)
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		v.add_child(l)
	return v


func _starting_slot(idx: int) -> String:
	for slot in GameState.lineup:
		if int(GameState.lineup[slot]) == idx:
			return slot
	return ""


func _slot_name(slot: String) -> String:
	if slot.begins_with("T"):
		return GameState.slot_label(slot)
	if slot.begins_with("F"):
		return "FLEX"
	return slot


func _sacrifice() -> void:
	if _slots.count(-1) > 0:
		return
	var exclude := {}
	var cursed_names := CursedPlayerDB.all_names()
	for p in GameState.roster:
		if cursed_names.has(p.pname):
			exclude[p.pname] = true
	var cursed := CursedPlayerDB.random_cursed(GameState.rng, exclude)
	# Cut from highest index to lowest so each cut_player's index shift only
	# ever affects picks already handled, never the ones still queued.
	var order := _slots.duplicate()
	order.sort()
	order.reverse()
	for idx in order:
		GameState.cut_player(idx)
	GameState.add_player(cursed)
	# Next visit costs one more - see GameState.rituals_completed.
	GameState.rituals_completed += 1
	# One ritual per visit to this stop.
	GameState.mark_stop_used()
	_revealed = cursed
	_build()


func _build_reveal(root: VBoxContainer) -> void:
	var top_space := Control.new()
	top_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(top_space)

	var veil := _veil(RITUAL_COLOR)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	veil.add_child(v)
	var title := UIKit.label("THE RITUAL IS COMPLETE", 32, RITUAL_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := UIKit.label("From the sacrifice rises...", 15, UIKit.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(UIKit.rule())
	var card := UIKit.player_card(_revealed)
	card.custom_minimum_size = Vector2(460, 0)
	v.add_child(card)
	var back := UIKit.primary_button("  Back to the map  ", 18)
	back.custom_minimum_size = Vector2(0, 44)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"))
	v.add_child(back)
	root.add_child(_centered(veil))

	var low_space := Control.new()
	low_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(low_space)
