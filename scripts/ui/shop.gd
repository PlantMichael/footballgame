extends Control

## Spend football bucks between rounds: draft picks and items. One row of
## cards at a time - players by default, items behind the "Items ->" toggle
## in the bottom-right corner. Players are trading cards (TradingCard), gear
## is a paper equipment tag (PlayCard), all tossed on the turf.

var notice: String = ""
## Whether `notice` is bad news (a thrown flag) or a confirmation.
var notice_bad: bool = false
var _view: String = "players"   # "players" or "items"

const PLAYER_TILTS := [-1.2, 0.8, -0.5, 1.1, -0.9, 0.6]
const ITEM_TILTS := [-1.4, 0.9, -0.6, 1.3]


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
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var head := UIKit.header("Shop" if _view == "players" else "Shop - Gear",
		"Sign players and buy gear. Every Shop stop on the map has its own stock.")
	var refresh := UIKit.button("  Refresh stock  ($%d)  " % GameState.REROLL_COST, 15)
	refresh.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	refresh.custom_minimum_size = Vector2(0, 40)
	refresh.disabled = GameState.bucks < GameState.REROLL_COST
	refresh.pressed.connect(func():
		if GameState.reroll_shop():
			notice = ""
		_rebuild())
	head.add_child(refresh)
	head.move_child(refresh, head.get_child_count() - 2)
	root.add_child(head)

	var notice_row := CenterContainer.new()
	notice_row.custom_minimum_size = Vector2(0, 26)
	if notice != "":
		notice_row.add_child(UIKit.flag_notice(notice) if notice_bad
			else UIKit.outlined(UIKit.label(notice, 16, UIKit.GOOD), 5))
	root.add_child(notice_row)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var space := VBoxContainer.new()
	space.alignment = BoxContainer.ALIGNMENT_CENTER
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	space.add_child(row)
	root.add_child(space)

	var cards := _player_cards() if _view == "players" else _item_cards()
	var tilts: Array = PLAYER_TILTS if _view == "players" else ITEM_TILTS
	for i in cards.size():
		var tilt := TiltBox.new(tilts[i % tilts.size()])
		tilt.add_child(cards[i])
		row.add_child(tilt)
	if cards.is_empty():
		row.add_child(UIKit.outlined(UIKit.label("Sold out. Refresh the stock for more.", 18, UIKit.TEXT)))
	if _view == "items":
		root.add_child(_bag_summary())

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	root.add_child(bottom)

	var back := UIKit.button("  <- Back to the map  ", 17)
	back.custom_minimum_size = Vector2(0, 42)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"))
	bottom.add_child(back)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(sp)

	var toggle := UIKit.primary_button("  Players ->  " if _view == "items" else "  Gear ->  ", 17)
	toggle.custom_minimum_size = Vector2(0, 42)
	toggle.pressed.connect(func():
		_view = "items" if _view == "players" else "players"
		notice = ""
		_rebuild())
	bottom.add_child(toggle)


## One trading card per player in this stop's stock, each with its sign
## button (or a SIGNED stamp) along the bottom.
func _player_cards() -> Array:
	var out: Array = []
	var stock: Array = GameState.shop_stock.get("players", [])
	for i in stock.size():
		var p: PlayerData = stock[i]
		var cost := Generator.player_price(p)
		var sold := GameState.is_sold("player", str(i))
		var buy := _buy_button("SIGNED" if sold else "Sign  $%d" % cost, sold or GameState.bucks < cost)
		buy.pressed.connect(func(): _buy_player(i, p, cost))
		var card := TradingCard.new(p, ShopPlayerDB.quality_name(p.quality), UIKit.quality_color(p.quality), buy)
		card.custom_minimum_size = Vector2(200, 0)
		if sold:
			card.modulate = Color(1, 1, 1, 0.55)
		out.append(card)
	return out


## Gear comes on a paper equipment tag: its slot on the red tab, then the
## name, what it does, and its price.
func _item_cards() -> Array:
	var out: Array = []
	var stock: Array = GameState.shop_stock.get("items", [])
	for i in stock.size():
		var id: String = stock[i]
		var cost := ItemDB.item_cost(id)
		var sold := GameState.is_sold("item", str(i))

		var card := PlayCard.new(ItemDB.category_name(ItemDB.item_category(id)).to_upper())
		card.custom_minimum_size = Vector2(240, 300)
		if sold:
			card.modulate = Color(1, 1, 1, 0.55)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		card.add_child(v)

		v.add_child(UIKit.vsep(10))
		var name_label := UIKit.marker_label(ItemDB.item_name(id), 22, UIKit.INK)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(name_label)
		var d := UIKit.label(ItemDB.item_desc(id), 15, UIKit.INK_MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)

		var fill := Control.new()
		fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(fill)
		var price := UIKit.marker_label("$%d" % cost, 26, UIKit.INK_RED)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.add_child(price)
		var buy := _buy_button("BOUGHT" if sold else "Buy", sold or GameState.bucks < cost)
		buy.pressed.connect(func(): _buy_item(i, id, cost))
		v.add_child(buy)
		out.append(card)
	return out


## The gold stamp-style button at the foot of a card.
func _buy_button(text: String, disabled: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 36)
	b.add_theme_font_size_override("font_size", 16)
	var dark := Color("3a2a05")
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, dark)
	b.add_theme_color_override("font_disabled_color", Color(UIKit.INK, 0.55))
	var looks := {"normal": UIKit.ACCENT, "hover": UIKit.ACCENT.lightened(0.15),
		"pressed": UIKit.ACCENT.darkened(0.15), "disabled": Color("d8d2c0")}
	for state in looks:
		b.add_theme_stylebox_override(state, UIKit.stylebox(looks[state], 0, 2, Color(UIKit.INK, 0.8)))
	return b


func _bag_summary() -> Control:
	var center := CenterContainer.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	center.add_child(h)
	h.add_child(UIKit.outlined(UIKit.label("IN THE BAG:", 15, UIKit.ACCENT), 5))
	if GameState.inventory.is_empty():
		h.add_child(UIKit.outlined(UIKit.label("nothing unequipped", 15, UIKit.TEXT), 5))
	else:
		var counts := {}
		for item_id in GameState.inventory:
			counts[item_id] = int(counts.get(item_id, 0)) + 1
		for item_id in counts:
			h.add_child(UIKit.outlined(UIKit.label("%s x%d" % [ItemDB.item_name(item_id), counts[item_id]],
				15, UIKit.TEXT), 5))
	return center


func _buy_player(index: int, p: PlayerData, cost: int) -> void:
	if not GameState.spend_bucks(cost):
		notice = "Not enough football bucks."
		notice_bad = true
		_rebuild()
		return
	GameState.add_player(p.duplicate_player())
	GameState.mark_sold("player", str(index))
	GameState.bought_shop_players[p.pname] = true
	notice = "%s signed. Set him in the lineup." % p.pname
	notice_bad = false
	_rebuild()


func _buy_item(index: int, id: String, cost: int) -> void:
	if not GameState.spend_bucks(cost):
		notice = "Not enough football bucks."
		notice_bad = true
		_rebuild()
		return
	GameState.inventory.append(id)
	GameState.mark_sold("item", str(index))
	GameState.bought_items[id] = true
	notice = "%s added to the bag. Equip it on the lineup screen." % ItemDB.item_name(id)
	notice_bad = false
	_rebuild()
