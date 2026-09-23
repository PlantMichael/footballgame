extends Control


func _ready() -> void:
	UIKit.background(self)

	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 10)
	add_child(center)

	var t := UIKit.label("GRIDIRON RUN", 62, UIKit.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(t)

	var s := UIKit.label("Chart a path to one of 6 bowls. 3 losses and the season is over.", 18, UIKit.MUTED)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(s)

	center.add_child(UIKit.vsep(30))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	center.add_child(row)

	var start := UIKit.primary_button("  NEW RUN  ", 22)
	start.custom_minimum_size = Vector2(240, 54)
	start.pressed.connect(_on_new_run)
	row.add_child(start)

	var quit := UIKit.button("  Quit  ", 18)
	quit.custom_minimum_size = Vector2(140, 54)
	quit.pressed.connect(func(): get_tree().quit())
	row.add_child(quit)

	var dev := UIKit.button("  Dev mode  ", 14)
	dev.custom_minimum_size = Vector2(140, 34)
	dev.pressed.connect(_on_dev_mode)
	center.add_child(dev)

	center.add_child(UIKit.vsep(40))

	var help := UIKit.label(
		"You coach the offense. Set your lineup, pick five plays, and score.\n"
		+ "Football bucks earned on the field buy plays, players, and items between rounds.",
		15, UIKit.MUTED)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(help)


func _on_new_run() -> void:
	get_tree().change_scene_to_file("res://scenes/qb_select.tscn")


## Endless scrimmage with everything unlocked, skipping the QB pick and hub
## entirely - straight into the field for tuning and ability testing.
func _on_dev_mode() -> void:
	GameState.start_dev_mode()
	get_tree().change_scene_to_file("res://scenes/match.tscn")
