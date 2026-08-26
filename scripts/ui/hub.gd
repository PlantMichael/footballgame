extends Control

## Between-rounds hub: shows the bracket and routes to lineup, playbook,
## shop, and the next match.


func _ready() -> void:
	UIKit.background(self)
	_build()
	GameState.bucks_changed.connect(func(_v): _rebuild())
	GameState.roster_changed.connect(_rebuild)


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
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)

	root.add_child(UIKit.header(GameState.team_name, "%s round" % GameState.round_label()))
	root.add_child(UIKit.rule())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	body.add_child(_bracket_panel())
	body.add_child(_matchup_panel())


func _bracket_panel() -> Control:
	var p := UIKit.panel()
	p.custom_minimum_size = Vector2(420, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)

	v.add_child(UIKit.label("THE BRACKET", 18, UIKit.ACCENT))
	v.add_child(UIKit.rule())

	for i in GameState.bracket.size():
		var b: Dictionary = GameState.bracket[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		# A round only ever counts as won once round_index has moved past it -
		# a loss just spends a life and sends you right back at the same
		# round, so mid-run its result field can say "L" while it's still
		# the one you're about to try again.
		var status := "  "
		var col := UIKit.MUTED
		if i < GameState.round_index:
			status = "W "
			col = UIKit.GOOD
		elif i == GameState.round_index and GameState.run_active:
			status = "> "
			col = UIKit.ACCENT
		elif b["result"] == "L":
			status = "L "
			col = UIKit.BAD

		row.add_child(UIKit.label(status, 15, col))
		var name_label := UIKit.label(b["round"], 15, col)
		name_label.custom_minimum_size = Vector2(120, 0)
		row.add_child(name_label)
		row.add_child(UIKit.label(b["name"], 15, col if i <= GameState.round_index else UIKit.MUTED))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sp)
		row.add_child(UIKit.label("%d drives" % b["drives"], 12, UIKit.MUTED))
		v.add_child(row)

	var lives_left := GameState.MAX_LOSSES - GameState.losses
	v.add_child(UIKit.label("%d loss%s left before the season is over" % [
		lives_left, "" if lives_left == 1 else "es"
	], 13, UIKit.MUTED if lives_left > 1 else UIKit.BAD))

	v.add_child(UIKit.vsep(10))
	v.add_child(UIKit.rule())
	v.add_child(UIKit.label("ROSTER", 18, UIKit.ACCENT))

	var starters_count := 0
	for slot in GameState.SLOT_ORDER:
		if GameState.player_at(slot) != null:
			starters_count += 1
	v.add_child(UIKit.label("%d players signed, %d/11 starters set" % [GameState.roster.size(), starters_count], 14))
	v.add_child(UIKit.label("%d plays in the book, %d selected for the match" % [GameState.playbook.size(), GameState.active_plays.size()], 14))
	v.add_child(UIKit.label("%d items in the bag" % GameState.inventory.size(), 14))

	var sp2 := Control.new()
	sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp2)
	return p


func _matchup_panel() -> Control:
	var p := UIKit.panel()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)

	var opp := GameState.current_opponent()
	if opp.is_empty():
		v.add_child(UIKit.label("You won it all.", 24, UIKit.ACCENT))
		return p

	v.add_child(UIKit.label("NEXT UP", 18, UIKit.ACCENT))
	v.add_child(UIKit.label(opp["name"], 34))
	v.add_child(UIKit.label("%s  -  %d drives  -  difficulty %s" % [
		opp["round"], opp["drives"], _difficulty_stars(GameState.current_match_quality())
	], 15, UIKit.MUTED))

	v.add_child(UIKit.vsep(6))
	v.add_child(UIKit.rule())

	var warn := ""
	if not GameState.lineup_is_valid():
		warn = "Your lineup is incomplete."
	elif GameState.active_plays.is_empty():
		warn = "Select at least one play before kickoff."
	if warn != "":
		v.add_child(UIKit.label(warn, 15, UIKit.BAD))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)

	grid.add_child(_nav_button("Lineup", "Set your 11 starters and hand out items.", "res://scenes/lineup.tscn"))
	grid.add_child(_nav_button("Playbook", "Choose the %d plays you can call." % GameState.PLAY_SLOTS, "res://scenes/playbook.tscn"))
	grid.add_child(_nav_button("Shop", "Spend football bucks on plays, players, and items.", "res://scenes/shop.tscn"))

	v.add_child(UIKit.vsep(4))
	v.add_child(_starters_summary())

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)

	var kick := UIKit.primary_button("KICKOFF", 22)
	kick.disabled = not GameState.lineup_is_valid() or GameState.active_plays.is_empty()
	kick.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/match.tscn"))
	v.add_child(kick)
	return p


## Compact read-out of who is actually taking the field.
func _starters_summary() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(UIKit.label("TAKING THE FIELD", 14, UIKit.ACCENT))

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 2)

	var total := 0
	var counted := 0
	for slot in GameState.SLOT_ORDER:
		var p := GameState.player_at(slot)
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		var tag := UIKit.label(GameState.slot_kind(slot) if slot.begins_with("F") else slot, 12, UIKit.MUTED)
		tag.custom_minimum_size = Vector2(42, 0)
		cell.add_child(tag)
		if p == null:
			cell.add_child(UIKit.label("empty", 13, UIKit.BAD))
		else:
			cell.add_child(UIKit.label(p.pname, 13))
			cell.add_child(UIKit.label(str(p.overall()), 13, UIKit.stat_color(p.overall())))
			total += p.overall()
			counted += 1
		grid.add_child(cell)
	box.add_child(grid)

	if counted > 0:
		box.add_child(UIKit.label("Average starter rating: %.1f" % (float(total) / float(counted)),
			13, UIKit.MUTED))
	return box


func _nav_button(title: String, desc: String, path: String) -> Control:
	var b := UIKit.button("", 16)
	b.custom_minimum_size = Vector2(240, 80)
	b.pressed.connect(func(): get_tree().change_scene_to_file(path))

	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_top = 10
	v.offset_right = -12
	v.add_child(UIKit.label(title, 19, UIKit.ACCENT))
	var d := UIKit.label(desc, 12, UIKit.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	b.add_child(v)
	return b


## One star per bracket round, matching the quality ramp in GameState.
func _difficulty_stars(q: float) -> String:
	var n := clampi(int(round((q - GameState.ROUND_ONE_QUALITY) / GameState.QUALITY_PER_ROUND)) + 1, 1, 5)
	return "*".repeat(n)
