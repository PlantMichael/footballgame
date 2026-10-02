extends Control

## Between matches: the run map (map_view.gd, GameState.run_map). Click a
## stop you can reach to see what it is, then go there - kick off a match,
## or step into a Shop, Ritual Site, Laboratory, Practice or Mystery stop.
## The lineup and Route Book are reachable from here at any time.

const MapView := preload("res://scripts/ui/map_view.gd")

## The stop whose details are showing (-1, -1 for none).
var _sel := Vector2i(-1, -1)
var _map: Control
var _detail: VBoxContainer


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
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var lives_left := GameState.MAX_LOSSES - GameState.losses
	root.add_child(UIKit.header(GameState.team_name, "Next: %s   -   %d loss%s left before the season is over" % [
		GameState.round_label(), lives_left, "" if lives_left == 1 else "es"]))

	var map_panel := UIKit.panel()
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(map_panel)
	_map = MapView.new()
	_map.custom_minimum_size = Vector2(0, 360)
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.set("selected", _sel)
	_map.connect("stop_clicked", _on_stop_clicked)
	map_panel.add_child(_map)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	bottom.custom_minimum_size = Vector2(0, 250)
	root.add_child(bottom)

	var detail_panel := UIKit.panel()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(detail_panel)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 8)
	detail_panel.add_child(_detail)
	_fill_detail()

	bottom.add_child(_side_panel())


func _on_stop_clicked(row: int, col: int) -> void:
	if not GameState.can_go_to(row, col) and not _is_current_shop(row, col):
		return
	_sel = Vector2i(row, col)
	_map.set("selected", _sel)
	for c in _detail.get_children():
		c.queue_free()
	_fill_detail()


## Standing on a Shop you haven't left yet - you can walk back in (say,
## after a trip to the lineup screen).
func _is_current_shop(row: int, col: int) -> bool:
	return row == GameState.map_row and col == GameState.map_col \
		and String(GameState.current_node().get("type", "")) == GameState.STOP_SHOP


func _fill_detail() -> void:
	if _sel.x < 0:
		_detail.add_child(UIKit.label("PICK YOUR NEXT STOP", 18, UIKit.ACCENT))
		var hint := UIKit.label("The stops you can reach next are pulsing on the map. Click one to see what's there.", 14, UIKit.MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(hint)
		if _is_current_shop(GameState.map_row, GameState.map_col):
			var back := UIKit.button("  Back into the Shop  ", 16)
			back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/shop.tscn"))
			_detail.add_child(back)
		return

	var node := GameState.map_node(_sel.x, _sel.y)
	var t := String(node["type"])
	if GameState.is_match_stop(t):
		_match_detail(node)
		return

	var info: Dictionary = STOP_INFO.get(t, {})
	_detail.add_child(UIKit.label(String(info.get("title", t)).to_upper(), 22, info.get("color", UIKit.ACCENT)))
	var desc := UIKit.label(String(info.get("desc", "")), 14, UIKit.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(desc)
	if t == GameState.STOP_LAB and GameState.bucks < Laboratory.PRICE:
		_detail.add_child(UIKit.label("You have $%d - not enough for an Oddity yet." % GameState.bucks, 13, UIKit.BAD))
	_spacer(_detail)
	var scene := String(info.get("scene", ""))
	if _is_current_shop(_sel.x, _sel.y):
		var back := UIKit.primary_button("BACK INTO THE SHOP", 20)
		back.pressed.connect(func(): get_tree().change_scene_to_file(scene))
		_detail.add_child(back)
		return
	var go := UIKit.primary_button("GO THERE", 20)
	var at := _sel
	go.pressed.connect(func():
		GameState.enter_stop(at.x, at.y)
		get_tree().change_scene_to_file(scene))
	_detail.add_child(go)


## Each non-match stop's look and blurb on the detail panel, and its scene.
const STOP_INFO := {
	"shop": {"title": "Shop", "color": Color("f2c14e"), "scene": "res://scenes/shop.tscn",
		"desc": "Spend football bucks on players and items. Every Shop on the map has its own stock - this is the only place to buy."},
	"ritual": {"title": "Ritual Site", "color": Color("b060e0"), "scene": "res://scenes/ritual_site.tscn",
		"desc": "Sacrifice players, permanently, for one random Cursed player. Each ritual costs one more player than the last."},
	"lab": {"title": "Laboratory", "color": Color("39ff5a"), "scene": "res://scenes/laboratory.tscn",
		"desc": "Pay $500 for a random Oddity: a strange player with a one-of-a-kind ability and a stat line rolled on the spot."},
	"practice": {"title": "Practice", "color": Color("6ec46e"), "scene": "res://scenes/practice.tscn",
		"desc": "Run a drill: pick 1 of 3 permanent stat boosts for your starters."},
	"mystery": {"title": "Mystery", "color": Color("5aa9e6"), "scene": "res://scenes/mystery.tscn",
		"desc": "Something's going on. Whatever it is, it'll shape your next match."},
}


func _match_detail(node: Dictionary) -> void:
	var opp: Dictionary = node["opponent"]
	var t := String(node["type"])
	var bowl_id := String(opp.get("bowl_id", ""))

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	if bowl_id != "":
		var badge := UIKit.bowl_badge(bowl_id, 56)
		if badge != null:
			top.add_child(badge)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	var kind := "ELITE MATCH" if t == GameState.STOP_ELITE else ("BOWL GAME" if bowl_id != "" else "MATCH")
	var kind_col: Color = MapView.STYLE[t]["color"]
	if t == GameState.STOP_MATCH:
		kind_col = UIKit.ACCENT
	col.add_child(UIKit.label(kind, 15, kind_col))
	col.add_child(UIKit.label(String(opp["name"]), 28))
	top.add_child(col)
	_detail.add_child(top)

	_detail.add_child(UIKit.label("%s  -  %d drives  -  difficulty %s" % [
		opp["round"], opp["drives"], _difficulty_stars(GameState.quality_against(opp))], 14, UIKit.MUTED))
	if t == GameState.STOP_ELITE:
		_detail.add_child(UIKit.label("Tougher defense with an extra aura. Win it: +50% win bonus and a free item.", 13, kind_col))
	if bowl_id != "":
		var desc := UIKit.label("%s  Win bonus $%d." % [BowlDB.bowl_desc(bowl_id), BowlDB.win_bonus(bowl_id)], 13, UIKit.MUTED)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(desc)
		if MetaState.has_mark(GameState.qb_id, bowl_id):
			_detail.add_child(UIKit.label("Already won with this QB", 12, UIKit.GOOD))
		var gimmick := BowlDB.gimmick_for_bowl(bowl_id)
		if gimmick != "":
			var special := UIKit.label("Special player: %s - %s" % [BowlDB.gimmick_name(gimmick),
				BowlDB.gimmick_effect(gimmick)], 13, BowlDB.GIMMICK_COLOR)
			special.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_detail.add_child(special)

	_spacer(_detail)
	if not GameState.lineup_is_valid():
		_detail.add_child(UIKit.label("Your lineup is incomplete.", 14, UIKit.BAD))
	var kick := UIKit.primary_button("KICKOFF", 22)
	kick.disabled = not GameState.lineup_is_valid()
	var at := _sel
	kick.pressed.connect(func():
		GameState.select_match(at.x, at.y)
		get_tree().change_scene_to_file("res://scenes/match.tscn"))
	_detail.add_child(kick)


## Right-hand column: lineup / Route Book, the next match's conditions, and
## who's taking the field.
func _side_panel() -> Control:
	var p := UIKit.panel()
	p.custom_minimum_size = Vector2(520, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	nav.add_child(_nav_button("Lineup", "Starters and items.", "res://scenes/lineup.tscn"))
	nav.add_child(_nav_button("Route Book", "Classic concepts to chalk.", "res://scenes/playbook.tscn"))
	v.add_child(nav)

	var forecast := UIKit.label("Next match forecast: %s - %s" % [WeatherDB.weather_name(GameState.next_weather),
		WeatherDB.weather_desc(GameState.next_weather)], 13,
		UIKit.MUTED if GameState.next_weather == WeatherDB.CLEAR else UIKit.ACCENT)
	forecast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(forecast)
	for note in GameState.next_match_mods.get("notes", []):
		v.add_child(UIKit.label("Next match: %s" % note, 13, Color("5aa9e6")))

	v.add_child(_starters_summary())
	return p


func _spacer(box: Container) -> void:
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(sp)


## Compact read-out of who is actually taking the field.
func _starters_summary() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(UIKit.label("TAKING THE FIELD", 14, UIKit.ACCENT))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 2)

	var total := 0
	var counted := 0
	for slot in GameState.SLOT_ORDER:
		var p := GameState.player_at(slot)
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		var tag := UIKit.label(GameState.slot_kind(slot) if slot.begins_with("F") else GameState.slot_label(slot), 12, UIKit.MUTED)
		tag.custom_minimum_size = Vector2(38, 0)
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


func _nav_button(title: String, desc: String, path: String, title_color: Color = UIKit.ACCENT) -> Control:
	var b := UIKit.button("", 16)
	b.custom_minimum_size = Vector2(240, 64)
	b.pressed.connect(func(): get_tree().change_scene_to_file(path))

	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_top = 8
	v.offset_right = -12
	v.add_child(UIKit.label(title, 18, title_color))
	var d := UIKit.label(desc, 12, UIKit.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	b.add_child(v)
	return b


## One star per difficulty tier, matching the quality ramp in GameState.
func _difficulty_stars(q: float) -> String:
	var n := clampi(int(round((q - GameState.ROUND_ONE_QUALITY) / GameState.QUALITY_PER_ROUND)) + 1, 1, 5)
	return "*".repeat(n)
