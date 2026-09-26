class_name Laboratory
extends Control

## The Laboratory: the Ritual Site's alternative. Instead of sacrificing
## players, pay PRICE football bucks for one random Oddity (OddityPlayerDB) -
## a strange experimental player with a bespoke ability and a stat line
## rolled fresh on the spot. Unlocked when one of your players goes over 200
## receiving or rushing yards in a match (GameState.lab_available, set by
## match.gd), and open from the hub until the next kickoff. One Oddity per
## visit.

const PRICE := 500

var _revealed: PlayerData = null


func _ready() -> void:
	UIKit.background(self)
	_build()


func _build() -> void:
	for c in get_children():
		if c is ColorRect:
			continue
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

	root.add_child(UIKit.label("THE LABORATORY", 30, OddityPlayerDB.COLOR))
	root.add_child(UIKit.label(
		"$%d buys one random Oddity. Every Oddity's stats are rolled the moment he walks out of the tank - %d points split at random across Strength, Agility, Dexterity and Intelligence." % [PRICE, OddityPlayerDB.BASE_POOL],
		14, UIKit.MUTED))
	root.add_child(UIKit.label("You have $%d." % GameState.bucks, 16, UIKit.ACCENT))
	root.add_child(UIKit.rule())

	root.add_child(UIKit.label("WHAT MIGHT COME OUT", 16, UIKit.ACCENT))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	var owned := _owned_names()
	for e in OddityPlayerDB.ODDITIES:
		list.add_child(_specimen_row(e, owned.has(String(e["name"]))))
	var scroll := UIKit.scroll(list)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	root.add_child(footer)

	var note := "Specimens already on your roster won't come out again while there are others left."
	if GameState.bucks < PRICE:
		note = "Not enough football bucks - you need $%d." % PRICE
	var status := UIKit.label(note, 13, UIKit.BAD if GameState.bucks < PRICE else UIKit.MUTED)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(status)

	var buy := UIKit.primary_button("  Pay $%d  " % PRICE, 16)
	buy.disabled = GameState.bucks < PRICE
	buy.pressed.connect(_buy)
	footer.add_child(buy)

	var back := UIKit.button("  <- Back to hub  ", 15)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"))
	root.add_child(back)


## One possible result: name, position, and ability - no stats, since
## they're rolled on the spot.
func _specimen_row(e: Dictionary, owned: bool) -> Control:
	var row := UIKit.panel(UIKit.PANEL_HI)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	row.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UIKit.label(String(e["name"]), 16, OddityPlayerDB.COLOR))
	head.add_child(UIKit.label(String(e["pos"]), 13, UIKit.ACCENT))
	if owned:
		head.add_child(UIKit.label("(on your roster)", 12, UIKit.MUTED))
	v.add_child(head)

	var id := String(e["ability_id"])
	var ab := UIKit.label("* %s: %s" % [AbilityDB.ability_name(id), AbilityDB.ability_desc(id)], 12, Color("9fc0b2"))
	ab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(ab)
	return row


func _owned_names() -> Dictionary:
	var out := {}
	var names := OddityPlayerDB.all_names()
	for p in GameState.roster:
		if names.has(p.pname):
			out[p.pname] = true
	return out


func _buy() -> void:
	if not GameState.spend_bucks(PRICE):
		return
	var oddity := OddityPlayerDB.random_oddity(GameState.rng, _owned_names())
	GameState.add_player(oddity)
	# One Oddity per unlock - the hub's button goes away with it.
	GameState.lab_available = false
	_revealed = oddity
	_build()


func _build_reveal(root: VBoxContainer) -> void:
	root.add_child(UIKit.label("IT'S ALIVE", 30, OddityPlayerDB.COLOR))
	root.add_child(UIKit.label("Something climbs out of the tank...", 14, UIKit.MUTED))
	root.add_child(UIKit.rule())

	var card_panel := PanelContainer.new()
	card_panel.add_theme_stylebox_override("panel", UIKit.stylebox(UIKit.PANEL_HI, 8, 3, OddityPlayerDB.COLOR))
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
