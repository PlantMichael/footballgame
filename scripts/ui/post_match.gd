extends Control

## End-of-run screen, reached from match.gd once the run is over: the bowl won
## (champions - the QB's completion mark is awarded here), the bowl lost, or
## the last life spent. Every other match goes straight back to the run map,
## so this only offers a fresh run or the main menu - with a plain "back to
## the map" fallback in case it's ever reached mid-run.


func _ready() -> void:
	UIKit.background(self)
	_build()


func _build() -> void:
	var r := GameState.last_result
	var won := bool(r.get("won", false))
	var tied := bool(r.get("tied", false))

	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 8)
	add_child(center)

	var run_over := GameState.is_run_over() or not GameState.run_active
	var champion := won and GameState.is_run_over() and GameState.bowl_won

	if champion:
		MetaState.award_mark(GameState.qb_id, GameState.chosen_bowl)
		var badge := UIKit.bowl_badge(GameState.chosen_bowl, 140)
		if badge != null:
			var center_badge := CenterContainer.new()
			center_badge.add_child(badge)
			center.add_child(center_badge)

	var headline := "YOU WIN"
	var col := UIKit.GOOD
	if champion:
		headline = "%s CHAMPIONS" % BowlDB.bowl_name(GameState.chosen_bowl).to_upper()
		col = UIKit.ACCENT
	elif run_over:
		headline = "SEASON OVER"
		col = UIKit.BAD
	elif tied:
		headline = "TIE GAME"
		col = UIKit.ACCENT
	elif not won:
		headline = "TOUGH LOSS"
		col = UIKit.BAD

	var h := UIKit.label(headline, 58, col)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(h)

	var score := UIKit.label("%s %d  -  %d %s" % [
		GameState.team_name, int(r.get("score_us", 0)),
		int(r.get("score_them", 0)), String(r.get("opponent", ""))
	], 26)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(score)
	if bool(r.get("overtime", false)):
		var ot := UIKit.label("after overtime", 15, UIKit.MUTED)
		ot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		center.add_child(ot)

	var earned := UIKit.label("Earned $%d football bucks%s" % [
		int(r.get("bucks", 0)),
		"  (includes the $%d win bonus)" % int(r.get("win_bonus", GameState.WIN_BONUS)) if won else ""
	], 16, UIKit.ACCENT)
	earned.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(earned)

	center.add_child(UIKit.vsep(24))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	center.add_child(row)

	if not run_over:
		var back := UIKit.primary_button("  BACK TO THE MAP  ", 20)
		back.custom_minimum_size = Vector2(0, 50)
		back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"))
		row.add_child(back)
		return

	var again := UIKit.primary_button("  START A NEW RUN  ", 20)
	again.custom_minimum_size = Vector2(0, 50)
	again.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/qb_select.tscn"))
	row.add_child(again)

	var menu := UIKit.button("  Main menu  ", 17)
	menu.custom_minimum_size = Vector2(0, 50)
	menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	row.add_child(menu)
