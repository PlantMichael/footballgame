extends Control

## The formation selects a position; only named actions change the roster.
var selected_slot: String = "QB"
var _view: String = "players"
var _notice: String = "Select a position, then choose Start, Swap or Equip."
var _rebuilding := false

const LINE_ROW := ["T0", "T1", "C", "T2", "T3"]
const BACK_ROW := ["F0", "F1", "QB", "F2", "F3", "F4"]


func _ready() -> void:
	UIKit.background(self)
	_build()


func _rebuild(focus_name: String = "") -> void:
	if _rebuilding:
		return
	_rebuilding = true
	for c in get_children():
		if c is ColorRect:
			continue
		if c is Control:
			c.hide()
		c.queue_free()
	await get_tree().process_frame
	_build()
	_rebuilding = false
	if focus_name != "":
		var target := find_child(focus_name, true, false) as Control
		if target != null:
			target.grab_focus()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	root.add_child(UIKit.header("Lineup", "Your formation on the left. Your next decision on the right."))
	root.add_child(UIKit.outlined(_text(_notice, 16, UIKit.TEXT)))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)

	var board := UIKit.chalkboard()
	board.custom_minimum_size.x = 566
	body.add_child(board)
	var field := VBoxContainer.new()
	field.add_theme_constant_override("separation", 8)
	board.add_child(field)
	field.add_child(UIKit.chalk_label("Starting offense", 22))
	field.add_child(_text("Select a position to manage its starter.", 15, UIKit.CHALK))
	for slots in [LINE_ROW, BACK_ROW]:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 5)
		for slot in slots:
			row.add_child(_slot_widget(slot))
		field.add_child(row)
		if slots == LINE_ROW:
			field.add_child(UIKit.rule())
	field.add_child(UIKit.rule())
	var special := HBoxContainer.new()
	special.add_theme_constant_override("separation", 16)
	special.add_child(_slot_widget(GameState.KICKER_SLOT))
	var note := VBoxContainer.new()
	note.alignment = BoxContainer.ALIGNMENT_CENTER
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.add_child(UIKit.chalk_label("Special teams", 18))
	note.add_child(_text("Kicker is optional. Without one, you cannot call a kick.", 15, UIKit.CHALK))
	special.add_child(note)
	field.add_child(special)
	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field.add_child(space)
	field.add_child(_text("FLEX: RB / WR / TE    •    LT / LG / RG / RT: Tackles", 14, UIKit.CHALK))
	field.add_child(_action("Auto-fill best lineup", func():
		GameState.auto_fill_lineup()
		_notice = "Best available players assigned by overall rating."
		_rebuild("Select_" + selected_slot)))

	var inspector := UIKit.panel()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(inspector)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 10)
	inspector.add_child(details)
	details.add_child(UIKit.marker_label("%s • Starter" % _slot_label(selected_slot), 24, UIKit.ACCENT))
	var starter := GameState.player_at(selected_slot)
	if starter == null:
		details.add_child(_text("Empty position. Choose an eligible player below.", 17))
	else:
		details.add_child(_player_summary(starter))
	details.add_child(UIKit.rule())
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	for tab in ["players", "equipment"]:
		var label_text := "Replacements" if tab == "players" else "Equipment • %d in bag" % GameState.inventory.size()
		var button := _action(label_text, func():
			_view = tab
			_rebuild("Tab_" + tab), _view == tab)
		button.name = "Tab_" + tab
		button.toggle_mode = true
		button.button_pressed = _view == tab
		if _view == tab:
			button.add_theme_stylebox_override("pressed", UIKit.stylebox(UIKit.ACCENT, 6))
		tabs.add_child(button)
	details.add_child(tabs)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	if _view == "players":
		_build_replacements(list, starter)
	else:
		_build_equipment(list, starter)
	var scroll := UIKit.scroll(list)
	scroll.follow_focus = true
	details.add_child(scroll)

	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	var bag := _text("%d players on roster   •   %d items in bag" % [GameState.roster.size(), GameState.inventory.size()], 16)
	bag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(UIKit.outlined(bag))
	bottom.add_child(_action("Back to scrimmage" if GameState.dev_mode else "Back to hub", func():
		if GameState.dev_mode:
			LoadingScreen.go_to("res://scenes/match.tscn")
		else:
			get_tree().change_scene_to_file("res://scenes/hub.tscn"), true))


func _slot_label(slot: String) -> String:
	if slot.begins_with("F"):
		return "FLEX %d" % (int(slot.substr(1)) + 1)
	return GameState.slot_label(slot)


func _slot_widget(slot: String) -> Control:
	var p := GameState.player_at(slot)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 80
	col.add_theme_constant_override("separation", 3)
	var b := Button.new()
	b.name = "Select_" + slot
	b.custom_minimum_size = Vector2(62, 62)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.tooltip_text = "Manage " + _slot_label(slot) + (": " + p.pname if p != null else ": empty")
	b.accessibility_name = b.tooltip_text
	b.toggle_mode = true
	b.button_pressed = slot == selected_slot
	for state in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(state, UIKit.stylebox(UIKit.CHALKBOARD.lightened(0.08), 31,
			3 if slot == selected_slot else 1, UIKit.ACCENT if slot == selected_slot else UIKit.CHALK))
	b.add_theme_stylebox_override("focus", _focus_style())
	if p != null:
		var portrait := UIKit.player_portrait(p, 54)
		portrait.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.position = Vector2(4, 4)
		b.add_child(portrait)
	else:
		b.text = "+"
	b.pressed.connect(func():
		selected_slot = slot
		_notice = "Managing %s. Select an explicit action below." % _slot_label(slot)
		_rebuild("Select_" + slot))
	col.add_child(b)
	var tag := UIKit.label(_slot_label(slot), 15, UIKit.ACCENT if slot == selected_slot else UIKit.CHALK)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)
	var player_name := _text(p.pname if p != null else "Empty", 13, UIKit.CHALK)
	player_name.custom_minimum_size = Vector2(80, 38)
	player_name.max_lines_visible = 2
	player_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	player_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(player_name)
	return col


func _player_summary(p: PlayerData) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(UIKit.player_portrait(p, 76))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_text("#%d  %s  •  %s  •  OVR %d" % [p.number, p.pname, p.pos_name(), p.overall()], 20))
	var stats := UIKit.stat_row(p, 15)
	for l in stats.get_children():
		l.add_theme_color_override("font_color", UIKit.TEXT)
	v.add_child(stats)
	v.add_child(_text(AbilityDB.ability_desc(p.ability_id), 15))
	row.add_child(v)
	return row


func _starting_slot(idx: int) -> String:
	for slot in GameState.lineup:
		if int(GameState.lineup[slot]) == idx:
			return slot
	return ""


func _build_replacements(list: VBoxContainer, starter: PlayerData) -> void:
	list.add_child(_text("Base stats compared with the starter; equipment stays with each player.", 14))
	var current := int(GameState.lineup.get(selected_slot, -1))
	var candidates: Array[int] = []
	for idx in GameState.roster.size():
		if idx != current and GameState.fits_slot(idx, selected_slot):
			candidates.append(idx)
	candidates.sort_custom(func(a: int, b: int):
		if GameState.is_starting(a) != GameState.is_starting(b):
			return not GameState.is_starting(a)
		return GameState.roster[a].overall() > GameState.roster[b].overall())
	if candidates.is_empty():
		list.add_child(_text("No eligible replacements. Sign a %s in the shop." % ("RB, WR or TE" if GameState.slot_kind(selected_slot) == "FLEX" else GameState.slot_kind(selected_slot)), 17))
	for idx in candidates:
		var p: PlayerData = GameState.roster[idx]
		var origin := _starting_slot(idx)
		var card := UIKit.panel(UIKit.PANEL_HI)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		card.add_child(v)
		v.add_child(_text("%s  •  %s  •  OVR %d  •  %s" % [p.pname, p.pos_name(), p.overall(),
			"Bench" if origin == "" else "Starting at " + _slot_label(origin)], 18, UIKit.ACCENT))
		var stats := HBoxContainer.new()
		stats.add_theme_constant_override("separation", 18)
		for key in p.shown_stats(UIKit.STAT_KEYS):
			var delta := p.stat(key) - starter.stat(key) if starter != null else 0
			stats.add_child(UIKit.label("%s %d%s" % [UIKit.STAT_LABELS[key], p.stat(key),
				" (%+d)" % delta if starter != null else ""], 15,
				UIKit.GOOD if delta > 0 else (UIKit.TEXT if delta == 0 else Color("ffaaa1"))))
		v.add_child(stats)
		v.add_child(_text(AbilityDB.ability_desc(p.ability_id), 15))
		var consequence := ""
		if origin != "":
			consequence = "%s moves to %s." % [starter.pname, _slot_label(origin)] if starter != null else "%s becomes empty." % _slot_label(origin)
		elif starter != null:
			consequence = "%s goes to the bench." % starter.pname
			if starter.quality == 0 and p.quality != 0:
				consequence = "Placeholder rookie %s is released; his gear returns to the bag." % starter.pname
		if consequence != "":
			v.add_child(_text(consequence, 14))
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 10)
		var start := _action(("Swap" if origin != "" else "Start") + " at " + _slot_label(selected_slot), func():
			if _rebuilding:
				return
			if GameState.set_slot(selected_slot, idx):
				_notice = "%s now starts at %s. %s" % [p.pname, _slot_label(selected_slot), consequence]
				_rebuild("Select_" + selected_slot), true)
		start.name = "Start_" + str(idx)
		actions.add_child(start)
		if origin == "":
			var release := _action("Release " + p.pname, func(): _ask_release(p))
			release.name = "Release_" + str(idx)
			actions.add_child(release)
		v.add_child(actions)
		list.add_child(card)


func _build_equipment(list: VBoxContainer, p: PlayerData) -> void:
	if p == null:
		list.add_child(_text("Start a player here before equipping gear.", 17))
		return
	list.add_child(_text("One item per category. Replaced gear returns to the bag.", 14))
	var idx := int(GameState.lineup[selected_slot])
	for category_index in PlayerData.ITEM_SLOTS:
		var category: String = ItemDB.CATEGORIES[category_index]
		var equipped: String = p.items[category_index]
		var card := UIKit.panel(UIKit.PANEL_HI)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		card.add_child(v)
		v.add_child(_text(ItemDB.category_name(category).to_upper(), 18, UIKit.ACCENT))
		v.add_child(_text("Equipped: " + (ItemDB.item_name(equipped) if equipped != "" else "None"), 17))
		if equipped != "":
			v.add_child(_text(ItemDB.item_desc(equipped), 15))
			var remove := _action("Unequip " + ItemDB.item_name(equipped), func():
				if _rebuilding:
					return
				GameState.unequip_item(idx, category_index)
				_notice = ItemDB.item_name(equipped) + " returned to the bag."
				_rebuild("Tab_equipment"))
			remove.name = "Unequip_" + str(category_index)
			v.add_child(remove)
		var seen := {}
		for bag_id in GameState.inventory:
			if seen.has(bag_id) or ItemDB.item_category(bag_id) != category:
				continue
			seen[bag_id] = true
			v.add_child(UIKit.rule())
			v.add_child(_text("In bag: %s ×%d" % [ItemDB.item_name(bag_id), GameState.inventory.count(bag_id)], 16))
			v.add_child(_text(ItemDB.item_desc(bag_id), 15))
			var equip := _action("Equip " + ItemDB.item_name(bag_id), func():
				if _rebuilding:
					return
				GameState.equip_item(bag_id, idx)
				_notice = "%s equipped on %s.%s" % [ItemDB.item_name(bag_id), p.pname,
					" Previous gear returned to the bag." if equipped != "" else ""]
				_rebuild("Tab_equipment"), true)
			equip.name = "Equip_" + bag_id
			v.add_child(equip)
		if seen.is_empty():
			v.add_child(_text("No spare %s in the bag." % ItemDB.category_name(category).to_lower(), 15))
		list.add_child(card)


func _ask_release(p: PlayerData) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Release player?"
	dialog.dialog_text = "%s leaves the roster permanently.\nAll equipped gear returns to the bag." % p.pname
	dialog.ok_button_text = "Release player"
	dialog.cancel_button_text = "Keep player"
	add_child(dialog)
	dialog.confirmed.connect(func():
		var idx := GameState.roster.find(p)
		if idx >= 0 and not GameState.is_starting(idx):
			GameState.cut_player(idx)
			_notice = "%s released. His equipped gear is in the bag." % p.pname
			_rebuild("Select_" + selected_slot)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(500, 160))
	dialog.get_cancel_button().grab_focus()


func _text(value: String, size: int = 15, color: Color = UIKit.TEXT) -> Label:
	var l := UIKit.label(value, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _focus_style() -> StyleBoxFlat:
	var sb := UIKit.stylebox(Color.TRANSPARENT, 6, 3, UIKit.ACCENT)
	sb.draw_center = false
	return sb


func _action(value: String, callback: Callable, primary: bool = false) -> Button:
	var b := UIKit.primary_button(value, 16) if primary else UIKit.button(value, 15)
	b.custom_minimum_size.y = 38
	if primary:
		b.add_theme_color_override("font_pressed_color", UIKit.BG)
	b.add_theme_stylebox_override("focus", _focus_style())
	b.pressed.connect(callback)
	return b
