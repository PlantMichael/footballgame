extends Control

## Result screen. Continues the run on a win; a loss (or an overtime tie) retries
## the round, and a loss with no lives left ends the run.


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

	var champion := won and GameState.is_run_over()
	var out_of_lives := not won and not tied and not GameState.run_active
	# The Ritual Site / Laboratory unlocks are decided at the final whistle
	# (match.gd _finish_match) - and only while the run is actually
	# continuing, since a new player only matters for a roster you'll keep
	# playing with this run. The match screen normally sends a continuing run
	# straight to the hub, which offers them too.
	var ritual_eligible := not champion and not out_of_lives and GameState.ritual_available
	var lab_eligible := not champion and not out_of_lives and GameState.lab_available

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
	if tied:
		var tie_note := UIKit.label("No loss counted - but you'll have to play this round again.", 16, UIKit.TEXT)
		tie_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		center.add_child(tie_note)

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
		if ritual_eligible:
			row.add_child(_ritual_button())
		if lab_eligible:
			row.add_child(_lab_button())
	elif not champion and not out_of_lives:
		# Lost (or tied), but still have a life left: retry the same round
		# rather than ending the run. GameState.round_index didn't move, so the hub and
		# shop both still point at the same opponent as before.
		var retry_text := "  REPLAY THE %s  " if tied else "  TRY THE %s AGAIN  "
		var retry := UIKit.primary_button(retry_text % GameState.round_label().to_upper(), 20)
		retry.custom_minimum_size = Vector2(0, 50)
		retry.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"))
		row.add_child(retry)

		var shop2 := UIKit.button("  Straight to the shop  ", 17)
		shop2.custom_minimum_size = Vector2(0, 50)
		shop2.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/shop.tscn"))
		row.add_child(shop2)
		if ritual_eligible:
			row.add_child(_ritual_button())
		if lab_eligible:
			row.add_child(_lab_button())
	else:
		var again := UIKit.primary_button("  START A NEW RUN  ", 20)
		again.custom_minimum_size = Vector2(0, 50)
		again.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/qb_select.tscn"))
		row.add_child(again)

		var menu := UIKit.button("  Main menu  ", 17)
		menu.custom_minimum_size = Vector2(0, 50)
		menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
		row.add_child(menu)


func _ritual_button() -> Control:
	var b := UIKit.button("  Visit the Ritual Site  ", 17)
	b.custom_minimum_size = Vector2(0, 50)
	b.add_theme_color_override("font_color", Color("b060e0"))
	b.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ritual_site.tscn"))
	return b


func _lab_button() -> Control:
	var b := UIKit.button("  Visit the Laboratory  ", 17)
	b.custom_minimum_size = Vector2(0, 50)
	b.add_theme_color_override("font_color", OddityPlayerDB.COLOR)
	b.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/laboratory.tscn"))
	return b
