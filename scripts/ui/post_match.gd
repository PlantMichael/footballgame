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

	var headline := "YOU WIN"
	var col := UIKit.GOOD
	if champion:
		headline = "CHAMPIONS"
		col = UIKit.ACCENT
	elif not won:
		headline = "SEASON OVER"
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
		int(r.get("bucks", 0)), "  (includes the $150 win bonus)" if won else ""
	], 16, UIKit.ACCENT)
	earned.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(earned)

	center.add_child(UIKit.vsep(24))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	center.add_child(row)

	if won and not champion:
		var next := UIKit.primary_button("  ON TO THE %s  " % GameState.round_label().to_upper(), 20)
		next.custom_minimum_size = Vector2(0, 50)
		next.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"))
		row.add_child(next)

		var shop := UIKit.button("  Straight to the shop  ", 17)
		shop.custom_minimum_size = Vector2(0, 50)
		shop.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/shop.tscn"))
		row.add_child(shop)
	else:
		var again := UIKit.primary_button("  START A NEW RUN  ", 20)
		again.custom_minimum_size = Vector2(0, 50)
		again.pressed.connect(func():
			GameState.new_run()
			get_tree().change_scene_to_file("res://scenes/hub.tscn"))
		row.add_child(again)

		var menu := UIKit.button("  Main menu  ", 17)
		menu.custom_minimum_size = Vector2(0, 50)
		menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
		row.add_child(menu)
