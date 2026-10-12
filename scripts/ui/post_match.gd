extends Control

## End-of-run screen, reached from match.gd once the run is over: the bowl won
## (champions - the QB's completion mark is awarded here), the bowl lost, or
## the last life spent. Every other match goes straight back to the run map,
## so this only offers a fresh run or the main menu - with a plain "back to
## the map" fallback in case it's ever reached mid-run.
##
## Laid out as the morning paper's front page: a masthead, a headline written
## from how the game went, the final score in a box, and the details below.

const NEWSPRINT := Color("efe9da")
const NEWS_INK := Color("1c1c1a")


func _ready() -> void:
	UIKit.background(self)
	_build()


func _build() -> void:
	var r := GameState.last_result
	var won := bool(r.get("won", false))
	var tied := bool(r.get("tied", false))
	var run_over := GameState.is_run_over() or not GameState.run_active
	var champion := won and GameState.is_run_over() and GameState.bowl_won
	if champion:
		MetaState.award_mark(GameState.qb_id, GameState.chosen_bowl)

	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 22)
	add_child(center)

	var paper_holder := CenterContainer.new()
	var tilt := TiltBox.new(-0.8)
	tilt.add_child(_front_page(r, won, tied, run_over, champion))
	paper_holder.add_child(tilt)
	center.add_child(paper_holder)

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


func _front_page(r: Dictionary, won: bool, tied: bool, run_over: bool, champion: bool) -> Control:
	var paper := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = NEWSPRINT
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 22
	sb.content_margin_bottom = 26
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 16
	sb.shadow_offset = Vector2(4, 8)
	paper.add_theme_stylebox_override("panel", sb)
	paper.custom_minimum_size = Vector2(760, 0)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	paper.add_child(v)

	# Masthead.
	var mast := _ink("THE GRIDIRON GAZETTE", 44)
	mast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(mast)
	var dateline := HBoxContainer.new()
	dateline.add_child(_ink("FINAL EDITION", 13, Color(NEWS_INK, 0.7)))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dateline.add_child(gap)
	dateline.add_child(_ink(String(r.get("round", "")).to_upper(), 13, Color(NEWS_INK, 0.7)))
	v.add_child(_double_rule())
	v.add_child(dateline)
	v.add_child(_double_rule())
	v.add_child(UIKit.vsep(4))

	# The headline.
	var head := _ink(_headline(r, won, tied, run_over, champion), 50)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(head)
	var sub := _ink(_subhead(r, won, tied), 18, Color(NEWS_INK, 0.75))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sub)
	v.add_child(UIKit.vsep(8))

	# The score box, with the bowl's logo as the photo on a title run.
	var body := HBoxContainer.new()
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", 24)
	v.add_child(body)
	if champion:
		var badge := UIKit.bowl_badge(GameState.chosen_bowl, 130)
		if badge != null:
			body.add_child(badge)
	body.add_child(_score_box(r))

	v.add_child(UIKit.vsep(6))
	v.add_child(_single_rule())
	var earned := _ink("Football bucks earned: $%d%s" % [int(r.get("bucks", 0)),
		"  (includes the $%d win bonus)" % int(r.get("win_bonus", GameState.WIN_BONUS)) if won else ""],
		16, Color(NEWS_INK, 0.8))
	earned.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(earned)
	return paper


## How the paper calls it.
func _headline(r: Dictionary, won: bool, tied: bool, run_over: bool, champion: bool) -> String:
	var us := GameState.team_name.to_upper()
	var them := String(r.get("opponent", "")).to_upper()
	var margin := absi(int(r.get("score_us", 0)) - int(r.get("score_them", 0)))
	if champion:
		return "%s WIN THE %s!" % [us, BowlDB.bowl_name(GameState.chosen_bowl).to_upper()]
	if tied:
		return "DEADLOCK: %s, %s TIED" % [us, them]
	if won and bool(r.get("overtime", false)):
		return "%s SURVIVE IN OVERTIME" % us
	if won:
		return ("%s ROUT %s" if margin >= 14 else "%s TOP %s") % [us, them]
	if run_over:
		return "SEASON ENDS FOR %s" % us
	return "%s DOWN %s" % [them, us]


func _subhead(r: Dictionary, won: bool, tied: bool) -> String:
	var qb := GameState.player_at("QB")
	var qb_name := qb.pname if qb != null else "The quarterback"
	var result := "tie" if tied else ("win" if won else "loss")
	var ot := " in overtime" if bool(r.get("overtime", false)) else ""
	return "%s leads the offense in a %d-%d %s%s against %s." % [qb_name,
		int(r.get("score_us", 0)), int(r.get("score_them", 0)), result, ot, String(r.get("opponent", ""))]


## The boxed final score, both teams.
func _score_box(r: Dictionary) -> Control:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(NEWS_INK, 0.04)
	sb.set_border_width_all(2)
	sb.border_color = NEWS_INK
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	box.add_theme_stylebox_override("panel", sb)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 0)
	box.add_child(grid)
	grid.add_child(_ink("FINAL" + ("  /  OT" if bool(r.get("overtime", false)) else ""), 13, Color(NEWS_INK, 0.6)))
	grid.add_child(Control.new())
	grid.add_child(_ink(GameState.team_name, 22))
	grid.add_child(_ink(str(int(r.get("score_us", 0))), 30))
	grid.add_child(_ink(String(r.get("opponent", "")), 22))
	grid.add_child(_ink(str(int(r.get("score_them", 0))), 30))
	return box


func _ink(text: String, size: int, col: Color = NEWS_INK) -> Label:
	return UIKit.label(text, size, col)


func _double_rule() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 6)
	c.draw.connect(func():
		c.draw_line(Vector2(0, 1), Vector2(c.size.x, 1), NEWS_INK, 2.0, true)
		c.draw_line(Vector2(0, 5), Vector2(c.size.x, 5), NEWS_INK, 1.0, true))
	return c


func _single_rule() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 3)
	c.draw.connect(func(): c.draw_line(Vector2(0, 1), Vector2(c.size.x, 1), Color(NEWS_INK, 0.5), 1.0, true))
	return c
