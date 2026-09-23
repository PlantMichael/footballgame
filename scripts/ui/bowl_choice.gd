extends Control

## Shown once, right after winning the Divisional round: pick which of the
## chosen branch's 2 bowls to play for. This locks in the run's final match
## (GameState.choose_bowl updates the bracket's last entry's name/quality).


func _ready() -> void:
	UIKit.background(self)
	_build()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	root.add_child(UIKit.label("CHOOSE YOUR BOWL", 30, UIKit.ACCENT))
	root.add_child(UIKit.label(
		"%s. This is the run's final match - win it and it's yours forever." % BowlDB.branch_name(GameState.chosen_branch),
		14, UIKit.MUTED))
	root.add_child(UIKit.rule())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(row)

	for id in BowlDB.bowls_in_branch(GameState.chosen_branch):
		row.add_child(_bowl_card(id))


func _bowl_card(id: String) -> Control:
	var p := UIKit.panel(UIKit.PANEL_HI)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)

	var badge := UIKit.bowl_badge(id, 84)
	if badge != null:
		var center := CenterContainer.new()
		center.add_child(badge)
		v.add_child(center)

	v.add_child(UIKit.label(BowlDB.bowl_name(id), 22, UIKit.TEXT))
	var already := MetaState.has_mark(GameState.qb_id, id)
	if already:
		v.add_child(UIKit.label("Already won with this QB", 12, UIKit.GOOD))
	var desc := UIKit.label(BowlDB.bowl_desc(id), 13, UIKit.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)

	v.add_child(UIKit.rule())
	var stars := clampi(int(round(BowlDB.quality_mult(id) * 4.0)), 1, 5)
	v.add_child(UIKit.label("Difficulty: %s" % "*".repeat(stars), 13, UIKit.MUTED))
	v.add_child(UIKit.label("Win bonus: $%d" % BowlDB.win_bonus(id), 13, UIKit.ACCENT))

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)

	var pick := UIKit.primary_button("Play for it", 16)
	pick.pressed.connect(func():
		GameState.choose_bowl(id)
		get_tree().change_scene_to_file("res://scenes/hub.tscn"))
	v.add_child(pick)

	return p
