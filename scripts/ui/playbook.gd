extends Control

## The route book: a reference shelf of classic concepts, plus a glossary of
## the individual routes. Nothing here is owned or called - you draw your own
## routes on the field during the match. This screen exists so a coach who
## does not already know what a "dig" or a "flood" is can go and look.

var focus_play: String = ""


func _ready() -> void:
	UIKit.background(self)
	var ids := RouteBook.example_ids()
	if not ids.is_empty():
		focus_play = String(ids[0])
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

	root.add_child(UIKit.header("Route Book",
		"Reference only. You chalk your own routes up during the match - "
		+ "each receiver gets %d yards of chalk." % int(RouteBook.BUDGET_YARDS)))
	root.add_child(UIKit.rule())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	body.add_child(_concepts_panel())
	body.add_child(_diagram_panel())
	body.add_child(_glossary_panel())

	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(sp)
	var back := UIKit.primary_button("Back to hub", 17)
	back.custom_minimum_size = Vector2(200, 42)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"))
	bottom.add_child(back)


## Whole five-receiver concepts, the ones the match screen can load onto the
## chalkboard as a starting point.
func _concepts_panel() -> Control:
	var panel := UIKit.panel()
	panel.custom_minimum_size = Vector2(400, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	v.add_child(UIKit.label("CONCEPTS", 18, UIKit.ACCENT))
	v.add_child(UIKit.rule())

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	for id in RouteBook.example_ids():
		inner.add_child(_concept_row(id))
	v.add_child(UIKit.scroll(inner))
	return panel


func _concept_row(id: String) -> Control:
	var pl := PlayDB.get_play(id)
	var focused := id == focus_play

	var b := UIKit.button("", 14)
	b.custom_minimum_size = Vector2(0, 62)
	if focused:
		b.add_theme_stylebox_override("normal", UIKit.stylebox(UIKit.LINE, 6, 2, UIKit.ACCENT))
	b.pressed.connect(func():
		focus_play = id
		_rebuild())

	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -12
	h.add_theme_constant_override("separation", 10)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	v.add_child(UIKit.label(pl.get("name", id), 16))
	var d := UIKit.label(pl.get("desc", ""), 12, UIKit.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	h.add_child(v)

	b.add_child(h)
	return b


func _diagram_panel() -> Control:
	var panel := UIKit.panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	if focus_play == "":
		return panel

	var pl := PlayDB.get_play(focus_play)
	v.add_child(UIKit.label(pl.get("name", ""), 24, UIKit.ACCENT))
	var d := UIKit.label(pl.get("desc", ""), 14, UIKit.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)

	var diagram := PlayDiagram.new()
	diagram.play_id = focus_play
	diagram.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(diagram)

	v.add_child(UIKit.label(
		"Load this onto the chalkboard from the EXAMPLES button during a match, "
		+ "then redraw any receiver you like.", 12, UIKit.MUTED))
	return panel


## The single routes, which is what an undrawn receiver runs and what most of
## the concepts are built out of.
func _glossary_panel() -> Control:
	var panel := UIKit.panel()
	panel.custom_minimum_size = Vector2(262, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	v.add_child(UIKit.label("THE ROUTES", 18, UIKit.ACCENT))
	var blurb := UIKit.label("An undrawn receiver runs one of these at random.",
		12, UIKit.MUTED)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(blurb)
	v.add_child(UIKit.rule())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for id in RouteBook.STOCK.keys():
		grid.add_child(_glossary_card(String(id)))
	v.add_child(UIKit.scroll(grid))
	return panel


func _glossary_card(id: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var thumb := RouteThumb.new()
	thumb.route = RouteBook.STOCK[id]
	thumb.drawn = true
	thumb.custom_minimum_size = Vector2(106, 68)
	box.add_child(thumb)

	var name_label := UIKit.label(String(RouteBook.STOCK_LABELS.get(id, id)), 13)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)

	var yards := UIKit.label("%d yd" % int(round(RouteBook.route_length(RouteBook.STOCK[id]))),
		11, UIKit.MUTED)
	yards.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(yards)
	return box
