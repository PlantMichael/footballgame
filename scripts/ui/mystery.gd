extends Control

## A Mystery stop on the run map: one EventDB event, decided when the map was
## built. Each choice can pay or cost bucks on the spot and queue effects on
## the next match (GameState.add_match_mod), which the map screen lists until
## that match kicks off.

const COLOR := Color("5aa9e6")

var _outcome: String = ""


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

	var event := EventDB.get_event(String(GameState.current_node().get("event", "")))
	root.add_child(UIKit.label(String(event.get("title", "Mystery")).to_upper(), 30, COLOR))
	var text := UIKit.label(String(event.get("text", "")), 17)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(text)
	root.add_child(UIKit.rule())

	if _outcome != "":
		root.add_child(UIKit.label(_outcome, 17, UIKit.ACCENT))
	elif GameState.stop_used():
		root.add_child(UIKit.label("Whatever it was, it's over now.", 16, UIKit.MUTED))
	else:
		for choice in event.get("choices", []):
			root.add_child(_choice_button(choice))

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(sp)
	if GameState.stop_used():
		var back := UIKit.primary_button("  Back to the map  ", 18)
		back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"))
		root.add_child(back)


func _choice_button(choice: Dictionary) -> Control:
	var cost := int(choice.get("cost", 0))
	var b := UIKit.button("  %s  " % String(choice.get("label", "OK")), 17)
	b.custom_minimum_size = Vector2(0, 52)
	b.disabled = cost > GameState.bucks
	if b.disabled:
		b.tooltip_text = "You have $%d." % GameState.bucks
	b.pressed.connect(func(): _choose(choice))
	return b


func _choose(choice: Dictionary) -> void:
	var cost := int(choice.get("cost", 0))
	if cost > 0 and not GameState.spend_bucks(cost):
		return
	var gain := int(choice.get("gain", 0))
	if gain > 0:
		GameState.add_bucks(gain)
	var note := String(choice.get("note", ""))
	var effects: Dictionary = choice.get("effects", {})
	GameState.add_match_mod(effects, note)
	GameState.mark_stop_used()
	# add_match_mod may have filled in who it landed on (a random starter).
	var notes: Array = GameState.next_match_mods.get("notes", [])
	var parts: Array = []
	if gain > 0:
		parts.append("+$%d." % gain)
	if not effects.is_empty() and note != "" and not notes.is_empty():
		parts.append("Next match: %s" % String(notes[notes.size() - 1]))
	_outcome = "   ".join(parts) if not parts.is_empty() else "You move on."
	_build()
