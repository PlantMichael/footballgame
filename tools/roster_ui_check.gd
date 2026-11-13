extends Node

## Exercise the real roster screens, their controls and canonical state owners.
## godot --headless --path . res://tools/roster_ui_check.tscn
var failures := 0
var screen: Control


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().root.size = Vector2i(1440, 900)
	await _lineup()
	await _shop()
	await _lab()
	await _ritual()
	print("ROSTER UI CHECK: %s" % ("ALL CHECKS PASSED" if failures == 0 else "%d FAILURES" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func _lineup() -> void:
	GameState.new_run(43021)
	var starter := GameState.player_at("F0")
	GameState.equip_item("stickum_gloves", int(GameState.lineup["F0"]))
	var signed: PlayerData
	for p in ShopPlayerDB.all_players(GameState.rng):
		if p.natural_slot_kind() == "FLEX":
			signed = p
			break
	GameState.add_player(signed)
	await _open("lineup")
	var before := GameState.lineup.duplicate()
	# A real focused native button receives the keyboard activation.
	var select := screen.find_child("Select_F0", true, false) as Button
	select.grab_focus()
	await _key(KEY_SPACE, true)
	await _key(KEY_SPACE, false)
	await _settle()
	_check(screen.selected_slot == "F0" and GameState.lineup == before, "keyboard selection inspects without changing starters")
	_check(_has_text(starter.pname) and _has_text("Placeholder rookie"), "starter and automatic rookie-release consequence are visible")
	_check(screen.find_child("Start_" + str(GameState.lineup["C"]), true, false) == null, "ineligible center has no flex action")
	await _press_name("Start_" + str(GameState.roster.find(signed)))
	_check(GameState.player_at("F0") == signed and not GameState.roster.has(starter), "Start assigns signed player despite rookie index shift")
	_check(GameState.inventory.count("stickum_gloves") == 1, "released rookie gear returns exactly once")
	var other := GameState.player_at("F1")
	await _press_name("Start_" + str(GameState.roster.find(other)))
	_check(GameState.player_at("F0") == other and GameState.player_at("F1") == signed, "Swap exchanges both starters without releasing either")
	await _press_name("Tab_equipment")
	await _press_name("Equip_stickum_gloves")
	_check(other.has_item("stickum_gloves") and not GameState.inventory.has("stickum_gloves"), "Equip transfers bag item to selected starter")
	var replacement := ""
	for id in ItemDB.all_ids():
		if ItemDB.item_category(id) == "gloves" and id != "stickum_gloves":
			replacement = id
			break
	GameState.inventory.append(replacement)
	# Reopen the equipment view through its actual tab to reflect new stock.
	await _press_name("Tab_equipment")
	await _press_name("Equip_" + replacement)
	_check(other.has_item(replacement) and GameState.inventory.has("stickum_gloves"), "replacement gear returns previous gloves to bag")
	await _press_name("Unequip_1")
	_check(other.items[1] == "" and GameState.inventory.count(replacement) == 1, "Unequip returns replacement gear exactly once")
	await _press_name("Tab_players")
	var bench := -1
	for idx in GameState.roster.size():
		if not GameState.is_starting(idx) and GameState.fits_slot(idx, "F0"):
			bench = idx
			break
	if bench >= 0:
		var released: PlayerData = GameState.roster[bench]
		await _press_name("Release_" + str(bench))
		var dialog := _dialog()
		_check(dialog != null and dialog.dialog_text.contains(released.pname), "release confirmation names player")
		dialog.get_cancel_button().grab_focus()
		await _key(KEY_SPACE, true)
		await _key(KEY_SPACE, false)
		await _settle()
		_check(GameState.roster.has(released), "cancel release preserves player")
		await _press_name("Release_" + str(bench))
		_dialog().get_ok_button().pressed.emit()
		await _settle()
		_check(not GameState.roster.has(released), "confirmed release removes selected bench player")
	else:
		_check(false, "release fixture has a flex bench player")


func _shop() -> void:
	GameState.new_run(43022)
	GameState.bucks = 5000
	# First-kicker auto-start is an existing acquisition rule worth disclosing.
	var k := GameState.kicker()
	if k != null:
		GameState.cut_player(GameState.roster.find(k))
	var stock_player := Generator.make_player(GameState.rng, PlayerData.Pos.K, 5.0)
	GameState.ensure_shop()
	GameState.shop_stock["players"] = [stock_player]
	GameState.shop_stock["items"] = ["stickum_gloves"]
	await _open("shop")
	_check(_has_text("Starts at K immediately"), "shop explains first-kicker placement before purchase")
	var cost := Generator.player_price(stock_player)
	await _press_text("Sign  $%d" % cost)
	_check(GameState.kicker() != null and _has_text("starting at K"), "signing reports actual automatic starter placement")
	_check(GameState.bucks == 5000 - cost, "signing charges once")
	await _press_text("Gear")
	var bag_count := GameState.inventory.count("stickum_gloves")
	await _press_text("Buy")
	_check(GameState.inventory.count("stickum_gloves") == bag_count + 1 and _has_text("added to the bag"), "gear purchase reports bag placement")
	_check(_button_text("BOUGHT").disabled, "sold gear cannot be purchased twice")


func _lab() -> void:
	GameState.new_run(43023)
	GameState.bucks = 600
	await _open("laboratory")
	var count := GameState.roster.size()
	await _press_text("Recruit random Oddity • $500")
	_check(GameState.bucks == 100 and GameState.roster.size() == count + 1, "lab charges existing price for one player")
	_check(not GameState.is_starting(GameState.roster.size() - 1) and _has_text("joined your bench"), "lab reveals bench placement")
	screen._buy()
	_check(GameState.bucks == 100 and GameState.roster.size() == count + 1, "lab reveal cannot repeat purchase")
	GameState.new_run(43024)
	await _open("laboratory")
	_check(_button_text("Recruit random Oddity • $500").disabled and _has_text("Not enough bucks"), "lab makes insufficient funds visible")


func _ritual() -> void:
	GameState.new_run(43025)
	var offerings: Array[PlayerData] = []
	for i in 2:
		var p := Generator.make_player(GameState.rng, PlayerData.Pos.WR, 5.0)
		GameState.add_player(p)
		offerings.append(p)
	GameState.equip_item("stickum_gloves", GameState.roster.find(offerings[0]))
	await _open("ritual_site")
	_check(_button_text("Review sacrifice • 2 players").disabled, "incomplete sacrifice cannot proceed")
	# Choose through each square's real picker, including eligibility guards.
	for i in 2:
		var squares: Array[Node] = screen.find_children("*", "Button", true, false).filter(func(n): return n.tooltip_text == "Choose offering %d" % (i + 1))
		squares[0].pressed.emit()
		await _settle()
		_check(_button_text("  Can't spare him  ").disabled, "picker protects fieldable roster")
		var offer: Button
		for b in screen.find_children("*", "Button", true, false):
			if b.text == "  Offer  " and _subtree_text(b.get_parent(), offerings[i].pname):
				offer = b
				break
		_check(offer != null, "eligible offering appears in picker")
		if offer == null:
			return
		offer.pressed.emit()
		await _settle()
	var count := GameState.roster.size()
	await _press_text("Review sacrifice • 2 players")
	_check(GameState.roster.size() == count and _dialog().dialog_text.contains("Stickum Gloves"), "review lists returned gear before any loss")
	_dialog().get_cancel_button().pressed.emit()
	await _settle()
	_check(GameState.roster.has(offerings[0]) and GameState.roster.has(offerings[1]), "cancel sacrifice retains both offerings")
	await _press_text("Review sacrifice • 2 players")
	_dialog().get_ok_button().pressed.emit()
	await _settle()
	_check(not GameState.roster.has(offerings[0]) and not GameState.roster.has(offerings[1]) and GameState.roster.size() == count - 1, "confirmed ritual trades exact selections for one Cursed player")
	_check(GameState.inventory.count("stickum_gloves") == 1 and GameState.lineup_is_valid() and GameState.rituals_completed == 1, "ritual returns gear and preserves fieldable lineup")


func _open(tag: String) -> void:
	if is_instance_valid(screen):
		screen.queue_free()
		await get_tree().process_frame
	screen = load("res://scenes/%s.tscn" % tag).instantiate()
	add_child(screen)
	await _settle()


func _settle() -> void:
	for i in 4:
		await get_tree().process_frame


func _key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	await get_tree().process_frame


func _press_name(value: String) -> void:
	var b := screen.find_child(value, true, false) as Button
	_check(b != null and not b.disabled, "action available: " + value)
	if b != null:
		b.pressed.emit()
	await _settle()


func _press_text(value: String) -> void:
	var b := _button_text(value)
	_check(b != null and not b.disabled, "action available: " + value)
	if b != null:
		b.pressed.emit()
	await _settle()


func _button_text(value: String) -> Button:
	for b in screen.find_children("*", "Button", true, false):
		if b.text == value and b.is_visible_in_tree() and not b.is_queued_for_deletion():
			return b
	return null


func _dialog() -> ConfirmationDialog:
	for c in screen.get_children():
		if c is ConfirmationDialog and not c.is_queued_for_deletion():
			return c
	return null


func _has_text(value: String) -> bool:
	return _subtree_text(screen, value)


func _subtree_text(node: Node, value: String) -> bool:
	for l in node.find_children("*", "Label", true, false):
		if l.text.contains(value) and not l.is_queued_for_deletion():
			return true
	return false


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("ROSTER UI: " + message)
	else:
		print("  PASS: " + message)
