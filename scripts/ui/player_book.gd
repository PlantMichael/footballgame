extends Control

## Browsable reference of every hardcoded player in the game: the shop's
## draft board (ShopPlayerDB) plus the Ritual Site's Cursed roster
## (CursedPlayerDB) and the Laboratory's Oddities (OddityPlayerDB).
## Read-only - no signing or sacrificing happens here, just a sortable
## catalog so a coach can plan a run around who's out there.

const CURSED_COLOR := Color("b060e0")
const CURSED_TIER_RANK := 5
const ODDITY_TIER_RANK := 6

var _sort_mode: String = "rarity"   # "rarity" or "position"
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
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

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	root.add_child(top)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 0)
	title_box.add_child(UIKit.outlined(UIKit.label("PLAYER BOOK", 34, UIKit.ACCENT)))
	title_box.add_child(UIKit.outlined(UIKit.label(
		"Every hardcoded shop draft pick, Ritual Site Cursed player, and Laboratory Oddity in the game.",
		15, UIKit.TEXT), 5))
	top.add_child(title_box)

	var sort_label := UIKit.outlined(UIKit.label("Sort:", 15, UIKit.TEXT), 5)
	sort_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(sort_label)

	var by_rarity := UIKit.primary_button("  Rarity  ", 14) if _sort_mode == "rarity" else UIKit.button("  Rarity  ", 14)
	by_rarity.pressed.connect(func():
		_sort_mode = "rarity"
		_rebuild())
	top.add_child(by_rarity)

	var by_pos := UIKit.primary_button("  Position  ", 14) if _sort_mode == "position" else UIKit.button("  Position  ", 14)
	by_pos.pressed.connect(func():
		_sort_mode = "position"
		_rebuild())
	top.add_child(by_pos)

	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 20)
	# Centered in the scroll, with room around it for the cards' shadows.
	var holder := CenterContainer.new()
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 8)
	pad.add_child(grid)
	holder.add_child(pad)
	var scroll := UIKit.scroll(holder)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	for entry in _entries():
		grid.add_child(_card(entry))

	var back := UIKit.button("  <- Back  ", 17)
	back.custom_minimum_size = Vector2(0, 42)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	root.add_child(back)


## One dictionary per catalog entry: player, tier_rank (1 Rookie .. 4 All
## Star, 5 Cursed), tier_label, tier_color, and price (-1 for Cursed, which
## isn't bought with bucks - see ritual_site.gd).
func _entries() -> Array:
	var out: Array = []
	for p in ShopPlayerDB.all_players(_rng):
		out.append({
			"player": p,
			"tier_rank": p.quality,
			"tier_label": ShopPlayerDB.quality_name(p.quality),
			"tier_color": UIKit.quality_color(p.quality),
			"price": Generator.player_price(p),
		})
	for cursed_name in CursedPlayerDB.all_names():
		var p := CursedPlayerDB.make_named(_rng, cursed_name)
		out.append({
			"player": p,
			"tier_rank": CURSED_TIER_RANK,
			"tier_label": "Cursed",
			"tier_color": CURSED_COLOR,
			"price": -1,
		})
	# Oddities' stats are rolled fresh every time one is made, so the OVR
	# shown is just one sample roll - the price line says as much.
	for oddity_name in OddityPlayerDB.all_names():
		var p := OddityPlayerDB.make_named(_rng, oddity_name)
		out.append({
			"player": p,
			"tier_rank": ODDITY_TIER_RANK,
			"tier_label": "Oddity",
			"tier_color": OddityPlayerDB.COLOR,
			"price": Laboratory.PRICE,
		})

	if _sort_mode == "position":
		out.sort_custom(func(a, b):
			var pa: PlayerData = a["player"]
			var pb: PlayerData = b["player"]
			if pa.pos != pb.pos:
				return pa.pos < pb.pos
			if a["tier_rank"] != b["tier_rank"]:
				return a["tier_rank"] < b["tier_rank"]
			return pa.pname < pb.pname)
	else:
		out.sort_custom(func(a, b):
			if a["tier_rank"] != b["tier_rank"]:
				return a["tier_rank"] < b["tier_rank"]
			var pa: PlayerData = a["player"]
			var pb: PlayerData = b["player"]
			return pa.pname < pb.pname)
	return out


func _card(entry: Dictionary) -> Control:
	var p: PlayerData = entry["player"]
	var price: int = entry["price"]
	var price_text := "Ritual Site only" if price < 0 else "$%d" % price
	if int(entry["tier_rank"]) == ODDITY_TIER_RANK:
		price_text = "Laboratory - $%d, random stats" % price
	var price_label := UIKit.marker_label(price_text, 17, UIKit.INK_RED)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var card := TradingCard.new(p, String(entry["tier_label"]), entry["tier_color"], price_label)
	card.custom_minimum_size = Vector2(200, 0)
	return card
