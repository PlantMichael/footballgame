extends Control

## Lineup and equipment. Pick a slot on the left, then click a player on the
## right to put him there. Items are assigned from each player row.

var selected_slot: String = "QB"


func _ready() -> void:
	UIKit.background(self)
	_build()


func _rebuild() -> void:
	for c in get_children():
		if c is ColorRect:
			continue
		c.queue_free()
	await get_tree().process_frame
	_build()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var head := UIKit.header("Lineup", "Click a slot, then click a player to fill it")
	root.add_child(head)
	root.add_child(UIKit.rule())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	body.add_child(_slots_panel())
	body.add_child(_roster_panel())

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	root.add_child(bottom)

	var auto := UIKit.button("Auto-fill best lineup")
	auto.pressed.connect(func():
		GameState.auto_fill_lineup()
		_rebuild())
	bottom.add_child(auto)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(sp)

	var back := UIKit.primary_button("Back to hub", 17)
	back.custom_minimum_size = Vector2(200, 42)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"))
	bottom.add_child(back)


func _slots_panel() -> Control:
	var p := UIKit.panel()
	p.custom_minimum_size = Vector2(430, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)

	v.add_child(UIKit.label("STARTERS", 18, UIKit.ACCENT))
	v.add_child(UIKit.rule())

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)

	for slot in GameState.SLOT_ORDER:
		inner.add_child(_slot_row(slot))

	v.add_child(UIKit.scroll(inner))
	return p


func _slot_row(slot: String) -> Control:
	var b := UIKit.button("", 14)
	b.custom_minimum_size = Vector2(0, 54)
	b.pressed.connect(func():
		selected_slot = slot
		_rebuild())
	if slot == selected_slot:
		b.add_theme_stylebox_override("normal", UIKit.stylebox(UIKit.LINE, 6, 2, UIKit.ACCENT))

	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	h.offset_right = -10
	h.add_theme_constant_override("separation", 10)

	var tag := UIKit.label(_slot_label(slot), 15, UIKit.ACCENT)
	tag.custom_minimum_size = Vector2(56, 0)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(tag)

	var p := GameState.player_at(slot)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	if p == null:
		col.add_child(UIKit.label("- empty -", 15, UIKit.BAD))
	else:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		line.add_child(UIKit.label("#%d %s" % [p.number, p.pname], 15))
		var kind := GameState.slot_kind(slot)
		var natural := p.natural_slot_kind()
		if natural != kind:
			line.add_child(UIKit.label("(%s out of position)" % p.pos_name(), 12, UIKit.BAD))
		else:
			line.add_child(UIKit.label(p.pos_name(), 12, UIKit.MUTED))
		col.add_child(line)
		col.add_child(UIKit.stat_row(p, 12))
	h.add_child(col)

	if p != null:
		var ovr := UIKit.label("%d" % p.overall(), 20, UIKit.stat_color(p.overall()))
		ovr.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(ovr)

	b.add_child(h)
	return b


func _slot_label(slot: String) -> String:
	if slot.begins_with("T"):
		return "T%s" % slot.substr(1, 1)
	if slot.begins_with("F"):
		return "FLEX"
	return slot


func _roster_panel() -> Control:
	var p := UIKit.panel()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)

	v.add_child(UIKit.label("ROSTER  (filling: %s)" % _slot_label(selected_slot), 18, UIKit.ACCENT))
	v.add_child(UIKit.rule())

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)

	var order := range(GameState.roster.size())
	order.sort_custom(func(a, b):
		var pa: PlayerData = GameState.roster[a]
		var pb: PlayerData = GameState.roster[b]
		if pa.pos != pb.pos:
			return pa.pos < pb.pos
		return pa.overall() > pb.overall())

	for idx in order:
		inner.add_child(_roster_row(idx))

	v.add_child(UIKit.scroll(inner))
	return p


func _roster_row(idx: int) -> Control:
	var p: PlayerData = GameState.roster[idx]
	var box := UIKit.panel(UIKit.PANEL_HI if GameState.is_starting(idx) else UIKit.PANEL.darkened(0.15))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	box.add_child(h)

	var card := UIKit.player_card(p, false)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(card)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(210, 0)
	side.add_theme_constant_override("separation", 4)
	h.add_child(side)

	var place := UIKit.button("Put at %s" % _slot_label(selected_slot), 13)
	place.pressed.connect(func():
		GameState.set_slot(selected_slot, idx)
		_rebuild())
	side.add_child(place)

	side.add_child(_item_picker(idx, p))

	if not GameState.is_starting(idx):
		var cut := UIKit.button("Release", 12)
		cut.add_theme_color_override("font_color", UIKit.BAD)
		cut.pressed.connect(func():
			GameState.cut_player(idx)
			_rebuild())
		side.add_child(cut)

	return box


func _item_picker(idx: int, p: PlayerData) -> Control:
	var opt := OptionButton.new()
	opt.add_theme_font_size_override("font_size", 12)
	opt.add_theme_stylebox_override("normal", UIKit.stylebox(UIKit.PANEL, 6, 1))
	opt.add_theme_stylebox_override("hover", UIKit.stylebox(UIKit.LINE, 6, 1))
	opt.add_theme_stylebox_override("pressed", UIKit.stylebox(UIKit.LINE, 6, 1))

	var ids: Array = [""]
	opt.add_item("Item: none")
	if p.item_id != "":
		ids.append(p.item_id)
		opt.add_item("* " + ItemDB.item_name(p.item_id))
	var seen := {}
	for item_id in GameState.inventory:
		if seen.has(item_id):
			continue
		seen[item_id] = true
		var count: int = GameState.inventory.count(item_id)
		ids.append(item_id)
		opt.add_item("%s%s" % [ItemDB.item_name(item_id), (" x%d" % count) if count > 1 else ""])

	opt.selected = 1 if p.item_id != "" else 0
	opt.item_selected.connect(func(sel: int):
		var chosen: String = ids[sel]
		if chosen == "":
			GameState.unequip_item(idx)
		elif chosen != p.item_id:
			GameState.equip_item(chosen, idx)
		_rebuild())
	return opt
