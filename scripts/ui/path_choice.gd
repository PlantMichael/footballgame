extends Control

## Shown once, right after winning the Wild Card round: pick which of the 3
## branches (BowlDB.BRANCHES) to chase. This decides which 2 of the 6 bowls
## are still reachable this run - the specific one gets locked in next, on
## bowl_choice.gd, after the Divisional round.


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

	root.add_child(UIKit.label("CHOOSE YOUR PATH", 30, UIKit.ACCENT))
	root.add_child(UIKit.label("Where this run heads decides which bowl you'll be playing for.", 14, UIKit.MUTED))
	root.add_child(UIKit.rule())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(row)

	for id in BowlDB.all_branches():
		row.add_child(_branch_card(id))


func _branch_card(id: String) -> Control:
	var p := UIKit.panel(UIKit.PANEL_HI)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)

	v.add_child(UIKit.label(BowlDB.branch_name(id), 22, UIKit.TEXT))
	var desc := UIKit.label(BowlDB.branch_desc(id), 13, UIKit.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)

	v.add_child(UIKit.rule())
	v.add_child(UIKit.label("LEADS TOWARD", 12, UIKit.ACCENT))
	for bowl_id in BowlDB.bowls_in_branch(id):
		var bowl_row := HBoxContainer.new()
		bowl_row.add_theme_constant_override("separation", 8)
		var badge := UIKit.bowl_badge(bowl_id, 32)
		if badge != null:
			bowl_row.add_child(badge)
		bowl_row.add_child(UIKit.label(BowlDB.bowl_name(bowl_id), 16, UIKit.TEXT))
		v.add_child(bowl_row)

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)

	var pick := UIKit.primary_button("Take this path", 16)
	pick.pressed.connect(func():
		GameState.choose_branch(id)
		get_tree().change_scene_to_file("res://scenes/hub.tscn"))
	v.add_child(pick)

	return p
