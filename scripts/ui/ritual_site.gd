extends Control

## The Ritual Site: sacrifice a roster player, permanently, for one random
## Cursed player (CursedPlayerDB) in return. Unlocked by post_match.gd after
## a loss, or a win by 10+ points.

const RITUAL_COLOR := Color("b060e0")

var _revealed: PlayerData = null


func _ready() -> void:
	UIKit.background(self)
	_build()


func _build() -> void:
	for c in get_children():
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

	root.add_child(UIKit.label("THE RITUAL SITE", 30, RITUAL_COLOR))
	root.add_child(UIKit.label(
		"Sacrifice a player, permanently, for one random Cursed player in return.",
		14, UIKit.MUTED))
	root.add_child(UIKit.rule())

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	for i in GameState.roster.size():
		list.add_child(_roster_row(i))
	var scroll := UIKit.scroll(list)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var back := UIKit.button("  <- Back to hub (no sacrifice)  ", 15)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"))
	root.add_child(back)


func _roster_row(idx: int) -> Control:
	var p: PlayerData = GameState.roster[idx]
	var row := UIKit.panel(UIKit.PANEL_HI)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)

	var card := UIKit.player_card(p)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(card)

	var sac := UIKit.button("  Sacrifice  ", 14)
	sac.add_theme_color_override("font_color", Color("d9534f"))
	sac.pressed.connect(func(): _sacrifice(idx))
	h.add_child(sac)
	return row


func _sacrifice(idx: int) -> void:
	var exclude := {}
	var cursed_names := CursedPlayerDB.all_names()
	for p in GameState.roster:
		if cursed_names.has(p.pname):
			exclude[p.pname] = true
	var cursed := CursedPlayerDB.random_cursed(GameState.rng, exclude)
	GameState.cut_player(idx)
	GameState.add_player(cursed)
	_revealed = cursed
	_build()


func _build_reveal(root: VBoxContainer) -> void:
	root.add_child(UIKit.label("THE RITUAL IS COMPLETE", 30, RITUAL_COLOR))
	root.add_child(UIKit.label("From the sacrifice rises...", 14, UIKit.MUTED))
	root.add_child(UIKit.rule())

	var card_panel := UIKit.panel(UIKit.PANEL_HI)
	card_panel.custom_minimum_size = Vector2(420, 0)
	card_panel.add_child(UIKit.player_card(_revealed))
	root.add_child(card_panel)

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(sp)

	var back := UIKit.primary_button("  Back to hub  ", 18)
	back.custom_minimum_size = Vector2(0, 44)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"))
	root.add_child(back)
