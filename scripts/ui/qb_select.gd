extends Control

## First screen of a new run: pick one of five hardcoded quarterbacks
## (QBDB) to lead the offense. Each one is a coach's play card (PlayCard)
## tossed on the turf: his number, his chalked-up style of play, his stat
## line, and what his ability does.

## Each card sits at its own slight angle, so the row looks dealt by hand.
const TILTS := [-1.5, 1.2, -0.8, 1.6, -1.2]
const CARD_WIDTH := 236

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
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)

	root.add_child(UIKit.outlined(UIKit.label("CHOOSE YOUR QUARTERBACK", 38, UIKit.ACCENT)))
	root.add_child(UIKit.outlined(UIKit.label("This is who leads your offense for the whole run.", 16, UIKit.TEXT)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	# Shrunk to the tallest card and centered in the space below the title;
	# every card then fills the row's height, so they all match.
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var space := VBoxContainer.new()
	space.alignment = BoxContainer.ALIGNMENT_CENTER
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	space.add_child(row)
	root.add_child(space)

	for id in QBDB.count():
		var tilt := TiltBox.new(TILTS[id % TILTS.size()])
		tilt.add_child(_qb_card(id))
		row.add_child(tilt)


func _qb_card(id: int) -> Control:
	var e := QBDB.entry(id)
	var preview := QBDB.make_player(_preview_rng, id)

	var card := PlayCard.new("QB")
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)

	# His number, big, with his portrait beside it.
	var head := HBoxContainer.new()
	head.add_child(UIKit.label(str(preview.number), 50, UIKit.INK_BLUE))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	var portrait := UIKit.player_portrait(preview, 64)
	if portrait:
		portrait.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(portrait)
	v.add_child(head)

	v.add_child(UIKit.marker_label(preview.pname, 21, UIKit.INK))
	var tag := UIKit.label(String(e.get("tag", "")), 13, UIKit.INK_MUTED)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tag)

	v.add_child(UIKit.vsep(2))
	v.add_child(ChalkDiagram.new(e.get("diagram", {})))
	v.add_child(UIKit.vsep(4))

	for key in UIKit.STAT_KEYS:
		v.add_child(_stat_row(key, preview.stat(key)))

	# What his ability does - never its name, which is for the code only.
	v.add_child(UIKit.vsep(4))
	var has_ability := preview.ability_id != ""
	var ability := UIKit.marker_label(AbilityDB.ability_desc(preview.ability_id) if has_ability
		else "No special ability.", 14, UIKit.INK_RED if has_ability else UIKit.INK_MUTED)
	ability.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(ability)

	# Pushes the bowl marks and SELECT to the bottom, level across every card.
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)

	var marks := CenterContainer.new()
	marks.add_child(_bowl_marks_row(id))
	v.add_child(marks)
	v.add_child(_select_button(id))
	return card


## One stat as a pen-filled bar on the card - out of the full 15 scale, same
## as everywhere else in the game.
func _stat_row(key: String, value: int) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var name_label := UIKit.label(UIKit.STAT_LABELS[key], 13, UIKit.INK_MUTED)
	name_label.custom_minimum_size = Vector2(30, 0)
	h.add_child(name_label)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, 9)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.draw.connect(func():
		bar.draw_rect(Rect2(Vector2.ZERO, bar.size), Color("ddd2b5"))
		bar.draw_rect(Rect2(Vector2.ZERO, Vector2(bar.size.x * clampf(value / 15.0, 0.0, 1.0), bar.size.y)),
			UIKit.INK_BLUE))
	h.add_child(bar)
	var val := UIKit.label(str(value), 13, UIKit.INK)
	val.custom_minimum_size = Vector2(16, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)
	return h


## The gold "SELECT" stamp at the bottom of each card.
func _select_button(id: int) -> Button:
	var b := Button.new()
	b.text = "SELECT"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 38)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 17)
	var dark := Color("3a2a05")
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, dark)
	var looks := {"normal": UIKit.ACCENT, "hover": UIKit.ACCENT.lightened(0.15),
		"pressed": UIKit.ACCENT.darkened(0.15)}
	for state in looks:
		b.add_theme_stylebox_override(state, UIKit.stylebox(looks[state], 0, 2, UIKit.INK))
	b.pressed.connect(func():
		GameState.new_run(0, id)
		get_tree().change_scene_to_file("res://scenes/hub.tscn"))
	return b


## Isaac-style completion marks: one per bowl, its own logo lit up full
## color if this QB has already won it in a previous run (MetaState,
## persisted to user://progress.json), greyed out otherwise.
const MARK_SIZE := 40

func _bowl_marks_row(qb_id: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	for bowl_id in BowlDB.all_ids():
		var won := MetaState.has_mark(qb_id, bowl_id)
		var badge := UIKit.bowl_badge(bowl_id, MARK_SIZE, not won, false)
		if badge != null:
			badge.tooltip_text = "%s%s" % [BowlDB.bowl_name(bowl_id), " - won" if won else ""]
			row.add_child(badge)
	return row
