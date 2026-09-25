extends Control

## Lineup and equipment, laid out like the formation: the five linemen across
## the top, the quarterback in the middle with the flexes either side of him.
## Clicking a player selects him - he grows, his three item slots appear
## beside him, and the strip along the bottom fills with everyone on the
## roster who could take his spot. Click one of those to swap him in; click an
## item slot to equip something from the bag or take its item off.

var selected_slot: String = "QB"

## Formation rows, left to right as the field looks from behind the offense.
const LINE_ROW := ["T0", "T1", "C", "T2", "T3"]
const BACK_ROW_LEFT := ["F0", "F1"]
const BACK_ROW_RIGHT := ["F2", "F3", "F4"]

const CIRCLE := 92
const CIRCLE_SELECTED := 124
const ITEM_CIRCLE := 34
const BENCH_PORTRAIT := 72


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

	root.add_child(UIKit.header("Lineup", "Click a player to see his items and who can replace him"))
	root.add_child(UIKit.rule())

	var field := VBoxContainer.new()
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field.alignment = BoxContainer.ALIGNMENT_CENTER
	field.add_theme_constant_override("separation", 28)
	root.add_child(field)

	var line := _row()
	for slot in LINE_ROW:
		line.add_child(_slot_widget(slot))
	field.add_child(line)

	var backs := _row()
	for slot in BACK_ROW_LEFT:
		backs.add_child(_slot_widget(slot))
	backs.add_child(_gap(40))
	backs.add_child(_slot_widget("QB"))
	backs.add_child(_gap(40))
	for slot in BACK_ROW_RIGHT:
		backs.add_child(_slot_widget(slot))
	field.add_child(backs)

	root.add_child(_selected_info())
	root.add_child(_bench_strip())

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	root.add_child(bottom)

	var auto := UIKit.button("Auto-fill best lineup")
	auto.pressed.connect(func():
		GameState.auto_fill_lineup()
		_rebuild())
	bottom.add_child(auto)

	var bag := UIKit.label("%d item%s in the bag" % [GameState.inventory.size(),
		"" if GameState.inventory.size() == 1 else "s"], 14, UIKit.MUTED)
	bag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(bag)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(sp)

	var back := UIKit.primary_button("Back to hub", 17)
	back.custom_minimum_size = Vector2(200, 42)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"))
	bottom.add_child(back)


func _row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 22)
	return h


func _gap(w: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	return c


func _slot_label(slot: String) -> String:
	if slot.begins_with("T"):
		return GameState.slot_label(slot)
	if slot.begins_with("F"):
		return "FLEX"
	return slot


# ============================================================================
# Formation slots
# ============================================================================

## One starter: his circle with position and name under it, plus - if he's
## the selected one - his three item slots stacked to his left.
func _slot_widget(slot: String) -> Control:
	var selected := slot == selected_slot
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 10)

	var p := GameState.player_at(slot)
	if selected and p != null:
		var items := VBoxContainer.new()
		items.alignment = BoxContainer.ALIGNMENT_CENTER
		items.add_theme_constant_override("separation", 8)
		for i in PlayerData.ITEM_SLOTS:
			items.add_child(_item_circle(p, i))
		h.add_child(items)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	col.add_child(_player_circle(slot, p, CIRCLE_SELECTED if selected else CIRCLE, selected))

	var tag := UIKit.label(_slot_label(slot), 12, UIKit.ACCENT if selected else UIKit.MUTED)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)
	var name_text := "- empty -" if p == null else "#%d %s" % [p.number, p.pname]
	var name_label := UIKit.label(name_text, 13, UIKit.BAD if p == null else UIKit.TEXT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_label)
	h.add_child(col)
	return h


## A round button with the player's portrait inside it.
func _player_circle(slot: String, p: PlayerData, size: int, selected: bool) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(size, size)
	# Otherwise it stretches to the width of the name under it - an oval.
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	var ring := UIKit.ACCENT if selected else UIKit.LINE
	var width := 4 if selected else 2
	for state in ["normal", "hover", "pressed"]:
		var col := UIKit.PANEL_HI if state == "hover" else UIKit.PANEL
		b.add_theme_stylebox_override(state, UIKit.stylebox(col, size / 2, width, ring))
	b.pressed.connect(func():
		selected_slot = slot
		_rebuild())

	if p != null:
		var portrait := UIKit.player_portrait(p, size - 8)
		if portrait != null:
			# The portrait brings its own rounded-square frame; inside the
			# circle it just needs to be see-through and not eat the click.
			portrait.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
			portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
			portrait.position = Vector2(4, 4)
			b.add_child(portrait)
		if GameState.slot_kind(slot) != p.natural_slot_kind():
			b.tooltip_text = "%s playing out of position" % p.pos_name()
	return b


## One of the selected player's item slots - helmet, gloves or cleats. Click
## it for a menu of that kind of item in the bag (and, if it's filled, the
## option to take it off).
func _item_circle(p: PlayerData, slot_index: int) -> Control:
	var item_id: String = p.items[slot_index]
	var category: String = ItemDB.CATEGORIES[slot_index]
	var category_name := ItemDB.category_name(category)
	var b := Button.new()
	b.custom_minimum_size = Vector2(ITEM_CIRCLE, ITEM_CIRCLE)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	var ring := UIKit.ACCENT if item_id != "" else UIKit.LINE
	for state in ["normal", "hover", "pressed"]:
		var col := UIKit.PANEL_HI if state == "hover" else UIKit.PANEL
		b.add_theme_stylebox_override(state, UIKit.stylebox(col, ITEM_CIRCLE / 2, 2, ring))
	if item_id == "":
		# Empty: the category's initial, dimmed.
		b.text = category_name.substr(0, 1)
		b.add_theme_color_override("font_color", UIKit.MUTED)
		b.tooltip_text = "%s: empty" % category_name
	else:
		b.text = _item_initials(item_id)
		b.add_theme_color_override("font_color", UIKit.ACCENT)
		b.tooltip_text = "%s: %s\n%s" % [category_name, ItemDB.item_name(item_id), ItemDB.item_desc(item_id)]

	var menu := PopupMenu.new()
	b.add_child(menu)
	var choices: Array = []   # parallel to the menu entries: "" = unequip
	if item_id != "":
		menu.add_item("Take off %s" % ItemDB.item_name(item_id))
		choices.append("")
		menu.add_separator()
		choices.append(null)
	var seen := {}
	for bag_id in GameState.inventory:
		if seen.has(bag_id) or ItemDB.item_category(bag_id) != category:
			continue
		seen[bag_id] = true
		var count: int = GameState.inventory.count(bag_id)
		menu.add_item("%s%s" % [ItemDB.item_name(bag_id), (" x%d" % count) if count > 1 else ""])
		choices.append(bag_id)
	if choices.is_empty():
		menu.add_item("No %s in the bag" % category_name.to_lower())
		menu.set_item_disabled(0, true)
		choices.append(null)

	var idx := GameState.lineup.get(selected_slot, -1) as int
	menu.index_pressed.connect(func(i: int):
		var choice = choices[i]
		if choice == null:
			return
		if choice == "":
			GameState.unequip_item(idx, slot_index)
		else:
			GameState.equip_item(choice, idx)
		_rebuild())
	b.pressed.connect(func():
		menu.position = Vector2i(b.get_screen_position() + Vector2(b.size.x + 6, 0))
		menu.popup())
	return b


## Two-letter badge for an item inside its little circle ("Stickum Gloves"
## -> "SG").
func _item_initials(item_id: String) -> String:
	var out := ""
	for word in ItemDB.item_name(item_id).split(" ", false):
		out += word.substr(0, 1).to_upper()
		if out.length() >= 2:
			break
	return out


# ============================================================================
# Selected player + replacements
# ============================================================================

## One line under the formation: the selected player's stats and ability.
func _selected_info() -> Control:
	var p := GameState.player_at(selected_slot)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 14)
	if p == null:
		h.add_child(UIKit.label("Nobody at %s - pick someone below." % _slot_label(selected_slot), 14, UIKit.BAD))
		return h
	h.add_child(UIKit.label("%s  %s" % [p.pname, p.pos_name()], 15, UIKit.ACCENT))
	h.add_child(UIKit.stat_row(p, 13))
	h.add_child(UIKit.label("OVR %d" % p.overall(), 14, UIKit.stat_color(p.overall())))
	var ab := UIKit.label("%s: %s" % [AbilityDB.ability_name(p.ability_id), AbilityDB.ability_desc(p.ability_id)],
		12, Color("9fc0b2"))
	ab.custom_minimum_size = Vector2(360, 0)
	ab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(ab)
	return h


## Everyone on the roster who could play the selected spot, bench first.
## Clicking one puts him there (a starter just swaps spots).
func _bench_strip() -> Control:
	var p := UIKit.panel()
	p.custom_minimum_size = Vector2(0, 150)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	v.add_child(UIKit.label("REPLACEMENTS FOR %s" % _slot_label(selected_slot), 14, UIKit.ACCENT))

	var current := int(GameState.lineup.get(selected_slot, -1))
	var candidates: Array = []
	for idx in GameState.roster.size():
		if idx != current and GameState.fits_slot(idx, selected_slot):
			candidates.append(idx)
	candidates.sort_custom(func(a, b):
		var sa := GameState.is_starting(a)
		var sb := GameState.is_starting(b)
		if sa != sb:
			return not sa
		return (GameState.roster[a] as PlayerData).overall() > (GameState.roster[b] as PlayerData).overall())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	if candidates.is_empty():
		row.add_child(UIKit.label("Nobody else on the roster can play %s." % _slot_label(selected_slot), 13, UIKit.MUTED))
	for idx in candidates:
		row.add_child(_bench_card(idx))
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(row)
	v.add_child(scroll)
	return p


func _bench_card(idx: int) -> Control:
	var pd: PlayerData = GameState.roster[idx]
	var starting := GameState.is_starting(idx)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)

	var b := Button.new()
	b.custom_minimum_size = Vector2(BENCH_PORTRAIT, BENCH_PORTRAIT)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.tooltip_text = "Put %s at %s%s" % [pd.pname, _slot_label(selected_slot),
		" (swaps spots with him)" if starting else ""]
	b.pressed.connect(func():
		GameState.set_slot(selected_slot, idx)
		_rebuild())
	var portrait := UIKit.player_portrait(pd, BENCH_PORTRAIT)
	if portrait != null:
		portrait.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(portrait)
	col.add_child(b)

	var name_label := UIKit.label(pd.pname, 12)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_label)
	var sub := UIKit.label("%s  OVR %d%s" % [pd.pos_name(), pd.overall(), "  (starting)" if starting else ""],
		11, UIKit.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	if not starting:
		var cut := UIKit.button("Release", 11)
		cut.add_theme_color_override("font_color", UIKit.BAD)
		cut.pressed.connect(func():
			GameState.cut_player(idx)
			_rebuild())
		col.add_child(cut)
	return col
