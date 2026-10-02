extends Control

## A Practice stop on the run map: pick 1 of 3 drills, each a permanent stat
## boost for one of your starters. The three are rolled once, the first time
## you walk in, and kept on the map stop - leaving and coming back can't
## reroll them.

const GAIN := 2
const STATS := ["strength", "agility", "dexterity", "intelligence"]

var _picked: Dictionary = {}


func _ready() -> void:
	UIKit.background(self)
	var node := GameState.current_node()
	if not node.has("options"):
		node["options"] = _roll_options()
	_build()


## Three distinct starters, each with a stat that still has room to grow.
func _roll_options() -> Array:
	var pool: Array = []
	for p in GameState.starters():
		if p != null:
			pool.append(p)
	var out: Array = []
	while out.size() < 3 and not pool.is_empty():
		var p: PlayerData = pool.pop_at(GameState.rng.randi_range(0, pool.size() - 1))
		var open: Array = STATS.filter(func(s): return p.stat(s) < 15)
		if open.is_empty():
			continue
		out.append({"player": p, "stat": open[GameState.rng.randi_range(0, open.size() - 1)], "amount": GAIN})
	return out


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
	root.add_child(UIKit.label("PRACTICE", 30, UIKit.GOOD))

	if not _picked.is_empty():
		var p: PlayerData = _picked["player"]
		root.add_child(UIKit.label("%s put in the work: +%d %s, for good." % [
			p.pname, int(_picked["amount"]), UIKit.STAT_LABELS.get(_picked["stat"], _picked["stat"])], 18))
	elif GameState.stop_used():
		root.add_child(UIKit.label("Practice is over for the day.", 16, UIKit.MUTED))
	else:
		root.add_child(UIKit.label("Pick one drill. The boost is permanent.", 14, UIKit.MUTED))
		root.add_child(UIKit.rule())
		for opt in GameState.current_node().get("options", []):
			root.add_child(_option_button(opt))

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(sp)
	var back := UIKit.primary_button("  Back to the map  ", 18) if GameState.stop_used() else UIKit.button("  <- Back to the map (skip practice)  ", 15)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"))
	root.add_child(back)


func _option_button(opt: Dictionary) -> Control:
	var p: PlayerData = opt["player"]
	var stat := String(opt["stat"])
	var amount := int(opt["amount"])
	var b := UIKit.button("", 16)
	b.custom_minimum_size = Vector2(0, 76)
	b.pressed.connect(func():
		p.add_stat(stat, amount)
		GameState.mark_stop_used()
		_picked = opt
		GameState.roster_changed.emit()
		_build())

	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -12
	h.add_theme_constant_override("separation", 12)
	var portrait := UIKit.player_portrait(p, 56)
	if portrait:
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(portrait)
	var name_label := UIKit.label("#%d %s  (%s)" % [p.number, p.pname, p.pos_name()], 17)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(name_label)
	var gain := UIKit.label("+%d %s   %d -> %d" % [amount, UIKit.STAT_LABELS.get(stat, stat),
		p.stat(stat), mini(15, p.stat(stat) + amount)], 17, UIKit.GOOD)
	gain.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(gain)
	b.add_child(h)
	return b
