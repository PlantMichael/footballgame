extends Control

## Result screen. Continues the run on a win, ends it on a loss.


func _ready() -> void:
	UIKit.background(self)
	_build()


func _build() -> void:
	var r := GameState.last_result
	var won := bool(r.get("won", false))

	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 8)
	add_child(center)

	var champion := won and GameState.is_run_over()
	var out_of_lives := not won and not GameState.run_active

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
	elif out_of_lives:
		headline = "SEASON OVER"
		col = UIKit.BAD
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

	var earned := UIKit.label("Earned $%d football bucks%s" % [
		int(r.get("bucks", 0)),
		"  (includes the $%d win bonus)" % int(r.get("win_bonus", 150)) if won else ""
	], 16, UIKit.ACCENT)
	earned.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(earned)

	if not champion and not out_of_lives:
		var lives_left := GameState.MAX_LOSSES - GameState.losses
		var lives := UIKit.label("%d loss%s left before the season is over" % [
			lives_left, "" if lives_left == 1 else "es"
		], 14, UIKit.MUTED)
		lives.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		center.add_child(lives)

	center.add_child(UIKit.vsep(24))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	center.add_child(row)

	if won and not champion:
		var dest := "res://scenes/hub.tscn"
		var label := "  ON TO THE %s  " % GameState.round_label().to_upper()
		if GameState.needs_branch_choice():
			dest = "res://scenes/path_choice.tscn"
			label = "  CHOOSE YOUR PATH  "
		elif GameState.needs_bowl_choice():
			dest = "res://scenes/bowl_choice.tscn"
			label = "  CHOOSE YOUR BOWL  "
		var next := UIKit.primary_button(label, 20)
		next.custom_minimum_size = Vector2(0, 50)
		next.pressed.connect(func(): get_tree().change_scene_to_file(dest))
		row.add_child(next)

		var shop := UIKit.button("  Straight to the shop  ", 17)
		shop.custom_minimum_size = Vector2(0, 50)
		shop.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/shop.tscn"))
		row.add_child(shop)
	elif not champion and not out_of_lives:
		# Lost, but still have a life left: retry the same round rather than
		# ending the run. GameState.round_index didn't move, so the hub and
		# shop both still point at the same opponent as before.
		var retry := UIKit.primary_button("  TRY THE %s AGAIN  " % GameState.round_label().to_upper(), 20)
		retry.custom_minimum_size = Vector2(0, 50)
		retry.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"))
		row.add_child(retry)

		var shop2 := UIKit.button("  Straight to the shop  ", 17)
		shop2.custom_minimum_size = Vector2(0, 50)
		shop2.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/shop.tscn"))
		row.add_child(shop2)
	else:
		var again := UIKit.primary_button("  START A NEW RUN  ", 20)
		again.custom_minimum_size = Vector2(0, 50)
		again.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/qb_select.tscn"))
		row.add_child(again)

		var menu := UIKit.button("  Main menu  ", 17)
		menu.custom_minimum_size = Vector2(0, 50)
		menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
		row.add_child(menu)
