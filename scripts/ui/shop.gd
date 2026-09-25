extends Control

## Spend football bucks between rounds: draft picks and items. One row of
## big cards at a time - players by default, items behind the "Items ->"
## toggle in the bottom-right corner - rather than a permanent side-by-side
## split, so each card has room to breathe.

var notice: String = ""
var _view: String = "players"   # "players" or "items"


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

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	root.add_child(top)

	var title_box := UIKit.panel(UIKit.PANEL_HI)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_label := UIKit.label("SHOP" if _view == "players" else "ITEMS", 24, UIKit.ACCENT)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_child(title_label)
	top.add_child(title_box)

	var bucks_box := UIKit.panel(UIKit.PANEL_HI)
	var bucks_label := UIKit.label("$%d" % GameState.bucks, 20, UIKit.ACCENT)
	bucks_box.add_child(bucks_label)
	top.add_child(bucks_box)

	var refresh := UIKit.button("Refresh  ($%d)" % GameState.REROLL_COST, 15)
	refresh.disabled = GameState.bucks < GameState.REROLL_COST
	refresh.pressed.connect(func():
		if GameState.reroll_shop():
			notice = ""
		_rebuild())
	top.add_child(refresh)

	if notice != "":
		root.add_child(UIKit.label(notice, 15, UIKit.BAD))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(UIKit.scroll(row))

	if _view == "players":
		for c in _player_cards():
			row.add_child(c)
	else:
		for c in _item_cards():
			row.add_child(c)
		root.add_child(_bag_summary())

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	root.add_child(bottom)

	var back := UIKit.button("  <- Back  ", 17)
	back.custom_minimum_size = Vector2(0, 42)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"))
	bottom.add_child(back)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(sp)

	var toggle := UIKit.primary_button("  Players ->  " if _view == "items" else "  Items ->  ", 17)
	toggle.custom_minimum_size = Vector2(0, 42)
	toggle.pressed.connect(func():
		_view = "items" if _view == "players" else "players"
		_rebuild())
	bottom.add_child(toggle)


## Big, vertical draft-board cards: portrait on top, name/ability/desc below,
## sign button at the bottom - one per shop.gd's "players" stock slot.
func _player_cards() -> Array:
	var out: Array = []
	var stock: Array = GameState.shop_stock.get("players", [])
	for i in stock.size():
		var p: PlayerData = stock[i]
		var cost := Generator.player_price(p)
		var sold := GameState.is_sold("player", str(i))

		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UIKit.stylebox(UIKit.PANEL_HI, 8, 3, _quality_color(p.quality)))
		card.custom_minimum_size = Vector2(190, 0)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		card.add_child(v)

		if p.quality > 0:
			var tier := UIKit.label(ShopPlayerDB.quality_name(p.quality).to_upper(), 12, _quality_color(p.quality))
			tier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(tier)

		var portrait := UIKit.player_portrait(p, 110)
		if portrait:
			var center := CenterContainer.new()
			center.add_child(portrait)
			v.add_child(center)

		var name_label := UIKit.label(p.pname, 16, UIKit.TEXT)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(name_label)
		var pos_label := UIKit.label("#%d  %s  OVR %d" % [p.number, p.pos_name(), p.overall()], 12, UIKit.MUTED)
		pos_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(pos_label)

		v.add_child(UIKit.rule())
		var ability := UIKit.label("Ability: %s" % AbilityDB.ability_name(p.ability_id), 13, UIKit.TEXT)
		ability.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(ability)
		var desc := UIKit.label(AbilityDB.ability_desc(p.ability_id), 11, UIKit.MUTED)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(desc)

		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(sp)

		var buy := UIKit.button("SIGNED" if sold else "Sign  $%d" % cost, 14)
		buy.disabled = sold or GameState.bucks < cost
		buy.pressed.connect(func(): _buy_player(i, p, cost))
		v.add_child(buy)

		out.append(card)
	return out


## Rarity color for the hardcoded draft board, low to high - also used as
## each card's outline so the tier reads at a glance.
func _quality_color(q: int) -> Color:
	match q:
		ShopPlayerDB.QUALITY_ROOKIE: return Color("8a8f96")
		ShopPlayerDB.QUALITY_SOPHOMORE: return Color("5aa9e6")
		ShopPlayerDB.QUALITY_VETERAN: return Color("a06cd5")
		ShopPlayerDB.QUALITY_ALL_STAR: return UIKit.ACCENT
	return UIKit.MUTED


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


## Same big-card shape as _player_cards, for the item stock.
func _item_cards() -> Array:
	var out: Array = []
	var stock: Array = GameState.shop_stock.get("items", [])
	for i in stock.size():
		var id: String = stock[i]
		var cost := ItemDB.item_cost(id)
		var sold := GameState.is_sold("item", str(i))

		var card := UIKit.panel(UIKit.PANEL_HI)
		card.custom_minimum_size = Vector2(190, 0)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		card.add_child(v)

		var name_label := UIKit.label(ItemDB.item_name(id), 16, UIKit.TEXT)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(name_label)
		var cat_label := UIKit.label(ItemDB.category_name(ItemDB.item_category(id)).to_upper(), 11, UIKit.ACCENT)
		cat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(cat_label)
		v.add_child(UIKit.rule())
		var d := UIKit.label(ItemDB.item_desc(id), 12, UIKit.MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)

		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(sp)

		var buy := UIKit.button("BOUGHT" if sold else "Buy  $%d" % cost, 14)
		buy.disabled = sold or GameState.bucks < cost
		buy.pressed.connect(func(): _buy_item(i, id, cost))
		v.add_child(buy)

		out.append(card)
	return out


func _bag_summary() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(UIKit.rule())
	v.add_child(UIKit.label("IN THE BAG", 14, UIKit.ACCENT))
	if GameState.inventory.is_empty():
		v.add_child(UIKit.label("Nothing unequipped.", 12, UIKit.MUTED))
	else:
		var counts := {}
		for item_id in GameState.inventory:
			counts[item_id] = int(counts.get(item_id, 0)) + 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		for item_id in counts:
			row.add_child(UIKit.label("%s x%d" % [ItemDB.item_name(item_id), counts[item_id]], 12, UIKit.TEXT))
		v.add_child(row)
	return v


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
