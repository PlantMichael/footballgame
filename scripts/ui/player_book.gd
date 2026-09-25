extends Control

## Browsable reference of every hardcoded player in the game: the shop's
## draft board (ShopPlayerDB) plus the Ritual Site's Cursed roster
## (CursedPlayerDB). Read-only - no signing or sacrificing happens here, just
## a sortable catalog so a coach can plan a run around who's out there.

const CURSED_COLOR := Color("b060e0")
const CURSED_TIER_RANK := 5

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

	var title_box := UIKit.panel(UIKit.PANEL_HI)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_label := UIKit.label("PLAYER BOOK", 24, UIKit.ACCENT)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_child(title_label)
	top.add_child(title_box)

	top.add_child(UIKit.label("Sort:", 15, UIKit.MUTED))

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

	root.add_child(UIKit.label(
		"Every hardcoded shop draft pick and Ritual Site Cursed player in the game.",
		13, UIKit.MUTED))

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	var scroll := UIKit.scroll(grid)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	for entry in _entries():
		grid.add_child(_card(entry))

	root.add_child(UIKit.rule())

	var back := UIKit.button("  <- Back  ", 17)
	back.custom_minimum_size = Vector2(0, 42)
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
			"tier_color": _quality_color(p.quality),
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


func _quality_color(q: int) -> Color:
	match q:
		ShopPlayerDB.QUALITY_ROOKIE: return Color("8a8f96")
		ShopPlayerDB.QUALITY_SOPHOMORE: return Color("5aa9e6")
		ShopPlayerDB.QUALITY_VETERAN: return Color("a06cd5")
		ShopPlayerDB.QUALITY_ALL_STAR: return UIKit.ACCENT
	return UIKit.MUTED


func _card(entry: Dictionary) -> Control:
	var p: PlayerData = entry["player"]
	var tier_color: Color = entry["tier_color"]

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.stylebox(UIKit.PANEL_HI, 8, 3, tier_color))
	card.custom_minimum_size = Vector2(190, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)

	var tier := UIKit.label(String(entry["tier_label"]).to_upper(), 12, tier_color)
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

	var price: int = entry["price"]
	var price_label := UIKit.label(
		"Ritual Site only" if price < 0 else "$%d" % price,
		13, CURSED_COLOR if price < 0 else UIKit.ACCENT)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(price_label)

	return card
