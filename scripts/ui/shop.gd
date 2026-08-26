extends Control

## Spend football bucks between rounds: plays, draft picks, and items.

var notice: String = ""


func _ready() -> void:
	UIKit.background(self)
	GameState.ensure_shop()
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

	root.add_child(UIKit.header("Shop", "Stock refreshes each round"))
	root.add_child(UIKit.rule())

	if notice != "":
		root.add_child(UIKit.label(notice, 15, UIKit.BAD))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	body.add_child(_plays_column())
	body.add_child(_players_column())
	body.add_child(_items_column())

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	root.add_child(bottom)

	var reroll := UIKit.button("Reroll stock  ($%d)" % GameState.REROLL_COST)
	reroll.disabled = GameState.bucks < GameState.REROLL_COST
	reroll.pressed.connect(func():
		if GameState.reroll_shop():
			notice = ""
		_rebuild())
	bottom.add_child(reroll)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(sp)

	var back := UIKit.primary_button("Back to hub", 17)
	back.custom_minimum_size = Vector2(200, 42)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"))
	bottom.add_child(back)


func _column(title: String) -> Array:
	var p := UIKit.panel()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	v.add_child(UIKit.label(title, 18, UIKit.ACCENT))
	v.add_child(UIKit.rule())
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	v.add_child(UIKit.scroll(inner))
	return [p, inner]


func _plays_column() -> Control:
	var parts := _column("PLAYS")
	var inner: VBoxContainer = parts[1]

	var stock: Array = GameState.shop_stock.get("plays", [])
	if stock.is_empty():
		inner.add_child(UIKit.label("Sold out of new plays.", 14, UIKit.MUTED))

	for id in stock:
		var pl := PlayDB.get_play(id)
		var cost := PlayDB.play_cost(id)
		var sold := GameState.is_sold("play", id) or GameState.playbook.has(id)

		var card := UIKit.panel(UIKit.PANEL_HI)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		card.add_child(v)

		var head := HBoxContainer.new()
		head.add_child(UIKit.label(pl.get("name", id), 16))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(sp)
		head.add_child(UIKit.label(String(pl.get("kind", "pass")).to_upper(), 12, UIKit.MUTED))
		v.add_child(head)

		var d := UIKit.label(pl.get("desc", ""), 12, UIKit.MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)

		var diagram := PlayDiagram.new()
		diagram.play_id = id
		diagram.compact = true
		diagram.custom_minimum_size = Vector2(0, 130)
		v.add_child(diagram)

		var buy := UIKit.button("SOLD" if sold else "Buy  $%d" % cost, 14)
		buy.disabled = sold or GameState.bucks < cost
		buy.pressed.connect(func(): _buy_play(id, cost))
		v.add_child(buy)
		inner.add_child(card)

	return parts[0]


func _buy_play(id: String, cost: int) -> void:
	if not GameState.spend_bucks(cost):
		notice = "Not enough football bucks."
		_rebuild()
		return
	GameState.playbook.append(id)
	GameState.mark_sold("play", id)
	if GameState.active_plays.size() < GameState.PLAY_SLOTS:
		GameState.active_plays.append(id)
	notice = "Added %s to the playbook." % PlayDB.play_name(id)
	_rebuild()


func _players_column() -> Control:
	var parts := _column("DRAFT BOARD")
	var inner: VBoxContainer = parts[1]

	var stock: Array = GameState.shop_stock.get("players", [])
	for i in stock.size():
		var p: PlayerData = stock[i]
		var cost := Generator.player_price(p)
		var sold := GameState.is_sold("player", str(i))

		var card := UIKit.panel(UIKit.PANEL_HI)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		card.add_child(v)
		if p.quality > 0:
			v.add_child(UIKit.label(ShopPlayerDB.quality_name(p.quality).to_upper(),
				12, _quality_color(p.quality)))
		v.add_child(UIKit.player_card(p, false))

		var buy := UIKit.button("SIGNED" if sold else "Sign  $%d" % cost, 14)
		buy.disabled = sold or GameState.bucks < cost
		buy.pressed.connect(func(): _buy_player(i, p, cost))
		v.add_child(buy)
		inner.add_child(card)

	return parts[0]


## Rarity color for the hardcoded draft board, low to high.
func _quality_color(q: int) -> Color:
	match q:
		ShopPlayerDB.QUALITY_ROOKIE: return UIKit.MUTED
		ShopPlayerDB.QUALITY_SOPHOMORE: return UIKit.TEXT
		ShopPlayerDB.QUALITY_VETERAN: return UIKit.GOOD
		ShopPlayerDB.QUALITY_ALL_STAR: return UIKit.ACCENT
	return UIKit.TEXT


func _buy_player(index: int, p: PlayerData, cost: int) -> void:
	if not GameState.spend_bucks(cost):
		notice = "Not enough football bucks."
		_rebuild()
		return
	GameState.add_player(p.duplicate_player())
	GameState.mark_sold("player", str(index))
	GameState.bought_shop_players[p.pname] = true
	notice = "%s signed. Set him in the lineup." % p.pname
	_rebuild()


func _items_column() -> Control:
	var parts := _column("ITEMS")
	var inner: VBoxContainer = parts[1]

	var stock: Array = GameState.shop_stock.get("items", [])
	for i in stock.size():
		var id: String = stock[i]
		var cost := ItemDB.item_cost(id)
		var sold := GameState.is_sold("item", str(i))

		var card := UIKit.panel(UIKit.PANEL_HI)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		card.add_child(v)
		v.add_child(UIKit.label(ItemDB.item_name(id), 16))
		var d := UIKit.label(ItemDB.item_desc(id), 12, UIKit.MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)

		var buy := UIKit.button("BOUGHT" if sold else "Buy  $%d" % cost, 14)
		buy.disabled = sold or GameState.bucks < cost
		buy.pressed.connect(func(): _buy_item(i, id, cost))
		v.add_child(buy)
		inner.add_child(card)

	inner.add_child(UIKit.vsep(8))
	inner.add_child(UIKit.rule())
	inner.add_child(UIKit.label("IN THE BAG", 14, UIKit.ACCENT))
	if GameState.inventory.is_empty():
		inner.add_child(UIKit.label("Nothing unequipped.", 12, UIKit.MUTED))
	else:
		var counts := {}
		for item_id in GameState.inventory:
			counts[item_id] = int(counts.get(item_id, 0)) + 1
		for item_id in counts:
			inner.add_child(UIKit.label("%s x%d" % [ItemDB.item_name(item_id), counts[item_id]], 12, UIKit.TEXT))

	return parts[0]


func _buy_item(index: int, id: String, cost: int) -> void:
	if not GameState.spend_bucks(cost):
		notice = "Not enough football bucks."
		_rebuild()
		return
	GameState.inventory.append(id)
	GameState.mark_sold("item", str(index))
	GameState.bought_items[id] = true
	notice = "%s added to the bag. Equip it on the lineup screen." % ItemDB.item_name(id)
	_rebuild()
