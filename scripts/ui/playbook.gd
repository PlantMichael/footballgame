extends Control

## Choose which plays you can call during the match. A route diagram is drawn
## for whichever play is hovered or selected.

var focus_play: String = ""


func _ready() -> void:
	UIKit.background(self)
	if not GameState.playbook.is_empty():
		focus_play = GameState.playbook[0]
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

	root.add_child(UIKit.header("Playbook", "Take %d plays into the match (%d selected)" % [
		GameState.PLAY_SLOTS, GameState.active_plays.size()]))
	root.add_child(UIKit.rule())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var list_panel := UIKit.panel()
	list_panel.custom_minimum_size = Vector2(520, 0)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	list_panel.add_child(lv)
	lv.add_child(UIKit.label("YOUR PLAYS", 18, UIKit.ACCENT))
	lv.add_child(UIKit.rule())

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	for id in GameState.playbook:
		inner.add_child(_play_row(id))
	lv.add_child(UIKit.scroll(inner))
	body.add_child(list_panel)

	var diagram_panel := UIKit.panel()
	diagram_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 8)
	diagram_panel.add_child(dv)
	if focus_play != "":
		var pl := PlayDB.get_play(focus_play)
		dv.add_child(UIKit.label(pl.get("name", ""), 24, UIKit.ACCENT))
		var d := UIKit.label(pl.get("desc", ""), 14, UIKit.MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dv.add_child(d)
		dv.add_child(UIKit.label("Type: %s   Drop: %.1fs" % [
			String(pl.get("kind", "pass")).to_upper(), float(pl.get("dropback", 1.5))], 13, UIKit.MUTED))
		var diagram := PlayDiagram.new()
		diagram.play_id = focus_play
		diagram.size_flags_vertical = Control.SIZE_EXPAND_FILL
		dv.add_child(diagram)
	body.add_child(diagram_panel)

	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(sp)
	var back := UIKit.primary_button("Back to hub", 17)
	back.custom_minimum_size = Vector2(200, 42)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"))
	bottom.add_child(back)


func _play_row(id: String) -> Control:
	var pl := PlayDB.get_play(id)
	var active: bool = GameState.active_plays.has(id)

	var b := UIKit.button("", 14)
	b.custom_minimum_size = Vector2(0, 62)
	if active:
		b.add_theme_stylebox_override("normal", UIKit.stylebox(UIKit.LINE, 6, 2, UIKit.ACCENT))
	b.pressed.connect(func():
		focus_play = id
		GameState.toggle_active_play(id)
		_rebuild())
	b.mouse_entered.connect(func():
		focus_play = id
		_rebuild())

	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -12
	h.add_theme_constant_override("separation", 10)

	var mark := UIKit.label("[x]" if active else "[ ]", 16, UIKit.ACCENT if active else UIKit.MUTED)
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(mark)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	v.add_child(UIKit.label(pl.get("name", id), 16))
	var d := UIKit.label(pl.get("desc", ""), 12, UIKit.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	h.add_child(v)

	var kind := UIKit.label(String(pl.get("kind", "pass")).to_upper(), 12,
		UIKit.GOOD if pl.get("kind", "pass") == "run" else UIKit.DEFENSE)
	kind.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(kind)

	b.add_child(h)
	return b
