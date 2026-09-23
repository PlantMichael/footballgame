extends Control

## First screen of a new run: pick one of five hardcoded quarterbacks to
## lead the offense. Abilities are left blank until they're designed; only
## stats and flavor differ between them for now.

var _preview_rng := RandomNumberGenerator.new()


func _ready() -> void:
	UIKit.background(self)
	_preview_rng.seed = 1
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

	var t := UIKit.label("CHOOSE YOUR QUARTERBACK", 30, UIKit.ACCENT)
	root.add_child(t)
	root.add_child(UIKit.label("This is who leads your offense for the whole run.", 14, UIKit.MUTED))
	root.add_child(UIKit.rule())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(row)

	for id in QBDB.count():
		row.add_child(_qb_card(id))


func _qb_card(id: int) -> Control:
	var e := QBDB.entry(id)
	var preview := QBDB.make_player(_preview_rng, id)

	var p := UIKit.panel(UIKit.PANEL_HI)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)

	var portrait := UIKit.player_portrait(preview, 72)
	if portrait:
		var center := CenterContainer.new()
		center.add_child(portrait)
		v.add_child(center)

	v.add_child(UIKit.label(preview.pname, 18, UIKit.TEXT))

	var tag := UIKit.label(String(e.get("tag", "")), 12, Color("9fc0b2"))
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tag)

	v.add_child(UIKit.rule())

	for key in ["strength", "agility", "dexterity", "stamina", "intelligence"]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var name_label := UIKit.label(UIKit.STAT_LABELS[key], 13, UIKit.MUTED)
		name_label.custom_minimum_size = Vector2(42, 0)
		line.add_child(name_label)
		var val: int = preview.stat(key)
		line.add_child(UIKit.label(str(val), 13, UIKit.stat_color(val)))
		v.add_child(line)

	var ability_label := UIKit.label(AbilityDB.ability_name(preview.ability_id), 13, UIKit.TEXT)
	v.add_child(ability_label)
	var ability_desc := UIKit.label(AbilityDB.ability_desc(preview.ability_id), 11, UIKit.MUTED)
	ability_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(ability_desc)

	v.add_child(UIKit.rule())
	v.add_child(_bowl_marks_row(id))

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)

	var pick := UIKit.primary_button("Pick %s" % preview.pname.split(" ")[0], 16)
	pick.pressed.connect(func():
		GameState.new_run(0, id)
		get_tree().change_scene_to_file("res://scenes/hub.tscn"))
	v.add_child(pick)

	return p


## Isaac-style completion marks: one per bowl, its own logo lit up full
## color if this QB has already won it in a previous run (MetaState,
## persisted to user://progress.json), greyed out otherwise.
func _bowl_marks_row(qb_id: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for bowl_id in BowlDB.all_ids():
		var won := MetaState.has_mark(qb_id, bowl_id)
		var badge := UIKit.bowl_badge(bowl_id, 30, not won)
		if badge != null:
			badge.tooltip_text = "%s%s" % [BowlDB.bowl_name(bowl_id), " - won" if won else ""]
			row.add_child(badge)
	return row
