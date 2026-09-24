extends Control

## The Ritual Site: sacrifice roster players, permanently, for one random
## Cursed player (CursedPlayerDB) in return. Unlocked by post_match.gd after
## a loss, or a win by 10+ points. The cost escalates with GameState.
## rituals_completed - 2 players the first visit, 3 the next, and so on - so
## it stays a real trade instead of a repeatable freebie once a run has a
## few cursed players already.
const RITUAL_COLOR := Color("b060e0")
const BASE_SACRIFICE_COUNT := 2

var _revealed: PlayerData = null

## How many players this particular ritual costs - fixed for the lifetime of
## this screen instance so the requirement can't shift under the coach mid-
## selection (e.g. if _sacrifice fires and rituals_completed bumps before
## _build reruns). Set from GameState.rituals_completed in _ready.
var _sacrifice_count: int = BASE_SACRIFICE_COUNT

## Roster indices the coach has tapped to offer up, in click order. Capped at
## _sacrifice_count - tapping one more than that bumps the oldest selection
## off rather than refusing the tap, so the coach can freely change their
## mind without having to deselect first.
var _selected: Array[int] = []


func _ready() -> void:
	_sacrifice_count = BASE_SACRIFICE_COUNT + GameState.rituals_completed
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
		"Sacrifice %d players, permanently, for one random Cursed player in return." % _sacrifice_count,
		14, UIKit.MUTED))
	root.add_child(UIKit.rule())

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	for i in GameState.roster.size():
		list.add_child(_roster_row(i))
	var scroll := UIKit.scroll(list)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	root.add_child(footer)

	var status := UIKit.label("%d / %d chosen" % [_selected.size(), _sacrifice_count], 14, UIKit.MUTED)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(status)

	var confirm := UIKit.primary_button("  Complete the Ritual  ", 16)
	confirm.disabled = _selected.size() != _sacrifice_count
	confirm.pressed.connect(_sacrifice)
	footer.add_child(confirm)

	var back := UIKit.button("  <- Back to hub (no sacrifice)  ", 15)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"))
	root.add_child(back)


func _roster_row(idx: int) -> Control:
	var p: PlayerData = GameState.roster[idx]
	var chosen := _selected.has(idx)
	var row := UIKit.panel(RITUAL_COLOR.darkened(0.75) if chosen else UIKit.PANEL_HI)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)

	var card := UIKit.player_card(p)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(card)

	var toggle := UIKit.button("  Chosen  " if chosen else "  Choose  ", 14)
	toggle.add_theme_color_override("font_color", RITUAL_COLOR if chosen else Color("d9534f"))
	toggle.pressed.connect(func(): _toggle_selected(idx))
	h.add_child(toggle)
	return row


## Tapping an unselected player adds him, up to _sacrifice_count; tapping
## past that bumps the oldest pick rather than refusing, so re-picking never
## takes two taps. Tapping an already-selected player drops him.
func _toggle_selected(idx: int) -> void:
	if _selected.has(idx):
		_selected.erase(idx)
	else:
		_selected.append(idx)
		while _selected.size() > _sacrifice_count:
			_selected.pop_front()
	_build()


func _sacrifice() -> void:
	if _selected.size() != _sacrifice_count:
		return
	var exclude := {}
	var cursed_names := CursedPlayerDB.all_names()
	for p in GameState.roster:
		if cursed_names.has(p.pname):
			exclude[p.pname] = true
	var cursed := CursedPlayerDB.random_cursed(GameState.rng, exclude)
	# Cut from highest index to lowest so each cut_player's index shift only
	# ever affects picks already handled, never the ones still queued.
	var order := _selected.duplicate()
	order.sort()
	order.reverse()
	for idx in order:
		GameState.cut_player(idx)
	GameState.add_player(cursed)
	# Next visit costs one more - see GameState.rituals_completed.
	GameState.rituals_completed += 1
	_selected.clear()
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
