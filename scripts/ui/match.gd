extends Control

## The match screen. The field fills the whole window; everything else is an
## overlay on top of it:
##   - a thin scoreboard strip along the top
##   - the chalkboard along the bottom, where routes are drawn
##   - a card that pops up when you click a player
##   - a substitution list that slides in from the right
##   - a centered panel after a scoring drive to pick a per-game upgrade
##
## The MatchSim itself lives here; the field view only renders it.

const SUB_STEP := 1.0 / 120.0
## Tall enough for the chalkboard: a header line, the priority-target row,
## and a row of 124px route cards underneath them.
const BAR_TALL := 224
const BAR_SHORT := 74

var sim: MatchSim
var field: Control

var top_bar: PanelContainer
var play_bar: PanelContainer
var bar_host: MarginContainer
var side_panel: PanelContainer
var card: PanelContainer
var upgrade_panel: PanelContainer
var log_label: Label
var cam_btn: Button
var speed_btns: Dictionary = {}   # float speed -> Button, see _build_speed_buttons

var _sb: Dictionary = {}
var _last_phase: int = -1

var speed: float = 1.0
var bucks_earned: int = 0
var opponent_note: String = ""

## The example-concepts overlay (the old playbook, now purely a teaching
## aid). Non-empty id means it is open on that concept.
var examples_panel: PanelContainer
var example_focus: String = ""
var card_player: SimPlayer = null
var sub_slot: String = ""

## Which overlay currently occupies side_panel ("subs", "stats", or "" when
## it's hidden) - just enough state to let the Team Stats button toggle
## itself off on a second press instead of only ever reopening.
var _side_panel_mode: String = ""

## The 3 rolled upgrade choices after a scoring drive, empty when no upgrade
## is pending. Non-empty blocks the drive-over bar from showing until the
## coach picks one and then a player to give it to.
var pending_upgrades: Array = []


func _ready() -> void:
	UIKit.background(self)
	_start_match()
	_build_layout()
	_refresh_bar()


func _start_match() -> void:
	var opp := GameState.current_opponent()
	var quality := GameState.current_match_quality()
	sim = MatchSim.new()
	sim.setup(
		GameState.starters(),
		Generator.make_defense(GameState.rng, quality, GameState.aura_count(GameState.rng)),
		quality,
		String(opp.get("name", "Opponent")),
		int(opp.get("drives", 4))
	)
	sim.is_bowl_game = not GameState.dev_mode and GameState.round_index == GameState.bracket.size() - 1
	sim.start_match()
	bucks_earned = 0
	_apply_call()


# ============================================================================
# Layout
# ============================================================================

func _build_layout() -> void:
	field = preload("res://scripts/ui/field_view.gd").new()
	field.set_anchors_preset(Control.PRESET_FULL_RECT)
	field.sim = sim
	field.player_clicked.connect(_on_player_clicked)
	field.field_clicked.connect(_dismiss_overlays)
	field.route_drawn.connect(_on_route_drawn)
	field.bottom_inset = float(BAR_TALL)
	add_child(field)
	field.snap_camera()

	_build_top_bar()
	_build_log()
	_build_play_bar()
	_build_side_panel()
	_build_card()
	_build_upgrade_panel()
	_build_examples_panel()


func _overlay_style(alpha: float = 0.92) -> StyleBoxFlat:
	var sb := UIKit.stylebox(Color(UIKit.PANEL, alpha), 0, 0)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _build_top_bar() -> void:
	top_bar = PanelContainer.new()
	top_bar.add_theme_stylebox_override("panel", _overlay_style(0.90))
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = 54
	top_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(top_bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	top_bar.add_child(row)

	_add_sb(row, "us", GameState.team_name, UIKit.ACCENT)
	_add_sb(row, "them", sim.opponent_name, UIKit.DEFENSE)
	_add_sb(row, "drive", "Drive", UIKit.TEXT)
	_add_sb(row, "down", "Down", UIKit.TEXT)
	_add_sb(row, "spot", "Ball on", UIKit.TEXT)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_add_sb(row, "earned", "Earned", UIKit.ACCENT)

	_build_speed_buttons(row)

	cam_btn = UIKit.button("", 13)
	cam_btn.custom_minimum_size = Vector2(190, 0)
	cam_btn.pressed.connect(func(): field.toggle_camera_lock())
	row.add_child(cam_btn)
	_update_cam_btn()

	var stats_btn := UIKit.button("Team Stats", 13)
	stats_btn.pressed.connect(func():
		if side_panel.visible and _side_panel_mode == "stats":
			_dismiss_overlays()
		else:
			_open_team_stats())
	row.add_child(stats_btn)

	if GameState.dev_mode:
		# Equipping an item is only possible from the lineup screen (the
		# in-match sub panel only swaps which player is in a slot), so a
		# quick link there is the only way dev mode's item stash is actually
		# reachable rather than just sitting unused in the inventory.
		var lineup_btn := UIKit.button("  Lineup  ", 13)
		lineup_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/lineup.tscn"))
		row.add_child(lineup_btn)

		var exit_dev := UIKit.button("  Exit dev mode  ", 13)
		exit_dev.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
		row.add_child(exit_dev)


func _add_sb(row: HBoxContainer, key: String, title: String, col: Color) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(UIKit.label(title, 11, UIKit.MUTED))
	var value := UIKit.label("", 19, col)
	v.add_child(value)
	row.add_child(v)
	_sb[key] = value


## A two line ticker in the top corner, instead of a full drive log panel.
func _build_log() -> void:
	log_label = UIKit.label("", 13, Color(UIKit.TEXT, 0.75))
	log_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	log_label.offset_left = -430
	log_label.offset_right = -16
	log_label.offset_top = 62
	log_label.offset_bottom = 130
	log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(log_label)


func _build_play_bar() -> void:
	play_bar = PanelContainer.new()
	play_bar.add_theme_stylebox_override("panel", _overlay_style(0.92))
	play_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	play_bar.offset_top = -BAR_TALL
	play_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(play_bar)

	bar_host = MarginContainer.new()
	play_bar.add_child(bar_host)


func _build_side_panel() -> void:
	side_panel = PanelContainer.new()
	side_panel.add_theme_stylebox_override("panel", _overlay_style(0.96))
	side_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	side_panel.offset_left = -380
	side_panel.offset_top = 54
	side_panel.offset_bottom = -BAR_TALL
	side_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	side_panel.visible = false
	add_child(side_panel)


func _build_card() -> void:
	card = PanelContainer.new()
	var sb := UIKit.stylebox(Color(UIKit.PANEL_HI, 0.98), 8, 2, UIKit.ACCENT)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(330, 0)
	card.visible = false
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(card)


func _build_upgrade_panel() -> void:
	upgrade_panel = PanelContainer.new()
	var sb := UIKit.stylebox(Color(UIKit.PANEL_HI, 0.99), 10, 2, UIKit.ACCENT)
	upgrade_panel.add_theme_stylebox_override("panel", sb)
	upgrade_panel.custom_minimum_size = Vector2(460, 0)
	upgrade_panel.visible = false
	upgrade_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(upgrade_panel)


# ============================================================================
# Frame update
# ============================================================================

func _process(delta: float) -> void:
	_update_top_bar()
	_update_log()

	if sim.phase != _last_phase:
		_last_phase = sim.phase
		_refresh_bar()

	if sim.phase == MatchSim.Phase.PRESNAP:
		# Walk the formation onto its spots after a play-call change.
		sim.presnap_step(delta)
		return
	if sim.phase != MatchSim.Phase.LIVE:
		return
	var remaining := delta * speed
	while remaining > 0.0:
		var step := minf(SUB_STEP, remaining)
		sim.step(step)
		remaining -= step
		if sim.phase != MatchSim.Phase.LIVE:
			break
	if sim.phase == MatchSim.Phase.DEAD:
		bucks_earned += int(sim.result.get("bucks", 0))
		_last_phase = sim.phase
		field.trigger_zoom_pulse()
		_refresh_bar()


func _update_top_bar() -> void:
	_set_sb("us", str(sim.score_us))
	_set_sb("them", str(sim.score_them))
	if GameState.dev_mode:
		_set_sb("drive", "%d" % sim.drive_num)
	else:
		_set_sb("drive", "%d / %d" % [sim.drive_num, sim.total_drives])
	_set_sb("down", sim.down_text())
	_set_sb("spot", sim.yard_line_text(sim.los))
	_set_sb("earned", "$%d" % bucks_earned)
	_update_cam_btn()


## Kept in sync every frame since the "L" key can flip the lock without
## going through this button at all.
func _update_cam_btn() -> void:
	var locked: bool = field.get("camera_locked")
	cam_btn.text = "Camera: Following ball (L)" if locked else "Camera: Free - WASD/drag (L)"


## Game-speed control, in the top bar so it's visible in every phase rather
## than only during Phase.LIVE (where it used to live, in _live_bar).
func _build_speed_buttons(row: HBoxContainer) -> void:
	row.add_child(UIKit.label("Speed", 12, UIKit.MUTED))
	for s in [0.5, 1.0, 2.0, 4.0]:
		var b := UIKit.button("%sx" % ("0.5" if s == 0.5 else str(int(s))), 13)
		b.custom_minimum_size = Vector2(48, 0)
		b.pressed.connect(func():
			speed = s
			_update_speed_buttons())
		row.add_child(b)
		speed_btns[s] = b
	_update_speed_buttons()


func _update_speed_buttons() -> void:
	for s in speed_btns:
		var b: Button = speed_btns[s]
		if is_equal_approx(float(s), speed):
			b.add_theme_stylebox_override("normal", UIKit.stylebox(UIKit.LINE, 6, 2, UIKit.ACCENT))
		else:
			b.add_theme_stylebox_override("normal", UIKit.stylebox(UIKit.PANEL_HI, 6, 1))


func _set_sb(key: String, value: String) -> void:
	var l: Label = _sb.get(key)
	if l != null and l.text != value:
		l.text = value


func _update_log() -> void:
	# The ticker lives in the same corner the sub list slides into.
	log_label.visible = not side_panel.visible
	if not log_label.visible:
		return
	var lines: Array = sim.play_log.slice(maxi(0, sim.play_log.size() - 3))
	log_label.text = "\n".join(lines)


# ============================================================================
# Bottom bar
# ============================================================================

func _refresh_bar() -> void:
	_last_phase = sim.phase
	for c in bar_host.get_children():
		c.queue_free()

	field.draw_enabled = sim.phase == MatchSim.Phase.PRESNAP and pending_upgrades.is_empty()
	if not field.draw_enabled:
		field.cancel_stroke()

	var tall := sim.phase != MatchSim.Phase.LIVE
	var bar_height := float(BAR_TALL if tall else BAR_SHORT)
	play_bar.offset_top = -bar_height
	side_panel.offset_bottom = -bar_height
	# The camera centers on what's actually visible above the bar, not the
	# whole control - keep it in sync with the bar's real height (it shrinks
	# during LIVE) or a deep play's downfield half gets clipped short of the
	# true goal line. See field_view.gd's _recompute_transform/_clamp_camera.
	field.bottom_inset = bar_height
	for side in ["left", "right"]:
		bar_host.add_theme_constant_override("margin_" + side, 8)
	bar_host.add_theme_constant_override("margin_top", 4)
	bar_host.add_theme_constant_override("margin_bottom", 4)

	if not pending_upgrades.is_empty():
		bar_host.add_child(_upgrade_pending_bar())
		return

	match sim.phase:
		MatchSim.Phase.PRESNAP:
			bar_host.add_child(_playcall_bar())
		MatchSim.Phase.LIVE:
			bar_host.add_child(_live_bar())
		MatchSim.Phase.DEAD:
			bar_host.add_child(_result_bar())
		MatchSim.Phase.DRIVE_OVER:
			bar_host.add_child(_drive_over_bar())
		_:
			bar_host.add_child(_live_bar())


func _playcall_bar() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(UIKit.label("DRAW UP THE PLAY", 15, UIKit.ACCENT))
	head.add_child(UIKit.label("%s on the %s   -   drag from a receiver to chalk his route, tap him to inspect"
		% [sim.down_text(), sim.yard_line_text(sim.los)], 12, UIKit.MUTED))
	v.add_child(head)

	if GameState.dev_mode:
		v.add_child(_dev_defense_slider())

	v.add_child(_target_priority_row())
	v.add_child(_play_action_row())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(center)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(row)

	for f in sim.flex_players():
		row.add_child(_chalk_card(f))
	row.add_child(_chalk_tools())

	var snap := UIKit.primary_button("SNAP THE BALL", 18)
	snap.custom_minimum_size = Vector2(0, 38)
	snap.pressed.connect(_on_snap)
	body.add_child(_wrap_snap(snap))
	return v


## One card per flex: who he is, how much chalk his route uses, and a
## thumbnail of the shape. Clicking a drawn one wipes it back to auto.
func _chalk_card(f: SimPlayer) -> Control:
	var slot: String = f.slot
	var pd := f.data
	var drawn := GameState.has_route(slot)
	var auto_id := String(sim.auto_route_ids.get(slot, "go"))

	var b := UIKit.button("", 12)
	b.custom_minimum_size = Vector2(132, 124)
	b.tooltip_text = "Drag from #%d on the field to chalk his route." % pd.number
	if drawn:
		b.add_theme_stylebox_override("normal", UIKit.stylebox(UIKit.LINE, 6, 2, UIKit.ACCENT))
		b.tooltip_text += "\nClick this card to wipe it back to auto."
	b.disabled = not drawn
	b.pressed.connect(func():
		GameState.set_route(slot, [])
		_apply_call(false)
		_refresh_bar())

	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 6
	v.offset_right = -6
	v.offset_top = 4
	v.offset_bottom = -4
	v.add_theme_constant_override("separation", 1)

	var name_line := UIKit.label("#%d %s" % [pd.number, pd.pname], 12,
		UIKit.ACCENT if drawn else UIKit.TEXT)
	name_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_line)

	var thumb := RouteThumb.new()
	thumb.route = GameState.route_for(slot) if drawn \
		else RouteBook.route_for_spot(auto_id, _flex_spot(slot))
	thumb.drawn = drawn
	thumb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(thumb)

	var foot: String
	if drawn:
		foot = "%d / %d yd" % [
			int(round(RouteBook.route_length(GameState.route_for(slot)))),
			int(RouteBook.BUDGET_YARDS)]
	else:
		foot = "auto: %s" % RouteBook.STOCK_LABELS.get(auto_id, "?")
	var f_label := UIKit.label(foot, 10, UIKit.MUTED)
	f_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(f_label)

	b.add_child(v)
	return b


## Where a flex is lined up, as a formation-relative spot (what RouteBook
## works in) rather than an absolute field position.
func _flex_spot(slot: String) -> Vector2:
	var a := sim.flex_align(slot)
	return Vector2(a.x - sim.los, a.y - MatchSim.FIELD_W * 0.5)


## Wipe-the-board and teaching-aid buttons, stacked beside the five cards.
func _chalk_tools() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.custom_minimum_size = Vector2(124, 0)

	var ex := UIKit.button("Examples", 12)
	ex.custom_minimum_size = Vector2(0, 32)
	ex.tooltip_text = "Classic route concepts you can load onto the board and then redraw."
	ex.pressed.connect(_open_examples)
	col.add_child(ex)

	var clear := UIKit.button("Wipe board", 12)
	clear.custom_minimum_size = Vector2(0, 32)
	clear.disabled = GameState.drawn_routes.is_empty()
	clear.tooltip_text = "Clear every drawn route back to auto."
	clear.pressed.connect(func():
		GameState.clear_routes()
		_apply_call(false)
		_refresh_bar())
	col.add_child(clear)

	var n := 0
	for f in sim.flex_players():
		if GameState.has_route(f.slot):
			n += 1
	var count := UIKit.label("%d of 5 drawn" % n, 11, UIKit.MUTED)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(count)
	return col


## Rebuild the offensive call from whatever is on the chalkboard. `instant`
## false lets the formation visibly shift instead of teleporting.
func _apply_call(instant: bool = true) -> void:
	sim.set_drawn_call(GameState.drawn_routes, instant)


func _on_route_drawn(slot: String, route: Array) -> void:
	GameState.set_route(slot, route)
	# false: everyone is already standing on their spots, so re-aligning
	# instantly here would snap the other four receivers mid-shift.
	_apply_call(false)
	_refresh_bar()


# ============================================================================
# Example concepts (the old playbook, kept as a teaching aid)
# ============================================================================

func _build_examples_panel() -> void:
	examples_panel = PanelContainer.new()
	var sb := UIKit.stylebox(Color(UIKit.PANEL_HI, 0.99), 10, 2, UIKit.ACCENT)
	examples_panel.add_theme_stylebox_override("panel", sb)
	examples_panel.custom_minimum_size = Vector2(760, 0)
	examples_panel.visible = false
	examples_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(examples_panel)


func _open_examples() -> void:
	_dismiss_overlays()
	var ids := RouteBook.example_ids()
	if ids.is_empty():
		return
	if example_focus == "" or not ids.has(example_focus):
		example_focus = String(ids[0])
	_fill_examples(ids)
	_center_panel(examples_panel)
	examples_panel.visible = true


func _fill_examples(ids: Array) -> void:
	for c in examples_panel.get_children():
		examples_panel.remove_child(c)
		c.queue_free()

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	examples_panel.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(UIKit.label("ROUTE CONCEPTS", 17, UIKit.ACCENT))
	head.add_child(UIKit.label("Load one onto the board, then redraw any of the five.",
		12, UIKit.MUTED))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	var close := UIKit.button("  Close  ", 12)
	close.pressed.connect(func(): examples_panel.visible = false)
	head.add_child(close)
	v.add_child(head)
	v.add_child(UIKit.rule())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	for id in ids:
		var b := UIKit.button(PlayDB.play_name(id), 13)
		b.custom_minimum_size = Vector2(0, 30)
		if id == example_focus:
			b.add_theme_stylebox_override("normal", UIKit.stylebox(UIKit.LINE, 6, 2, UIKit.ACCENT))
		b.pressed.connect(func():
			example_focus = id
			_fill_examples(ids))
		list.add_child(b)
	var scroll := UIKit.scroll(list)
	scroll.custom_minimum_size = Vector2(250, 320)
	body.add_child(scroll)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)

	var pl := PlayDB.get_play(example_focus)
	right.add_child(UIKit.label(String(pl.get("name", "")), 16, UIKit.TEXT))
	var desc := UIKit.label(String(pl.get("desc", "")), 12, UIKit.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(desc)

	var diagram := PlayDiagram.new()
	diagram.play_id = example_focus
	diagram.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(diagram)

	var load_btn := UIKit.primary_button("CHALK THIS UP", 15)
	load_btn.custom_minimum_size = Vector2(0, 36)
	load_btn.pressed.connect(func():
		_load_example(example_focus)
		examples_panel.visible = false)
	right.add_child(load_btn)


## Copies a concept onto the board as five ordinary drawn routes, so it can
## be tweaked freely afterwards rather than being a locked-in play call.
func _load_example(id: String) -> void:
	var flexes := sim.flex_players()
	var spots := RouteBook.formation_for(flexes)
	var routes := RouteBook.example_routes(id, spots)
	for i in flexes.size():
		GameState.set_route(flexes[i].slot, routes[i])
	_apply_call(false)
	_refresh_bar()


## Arms an automatic Hand Off or Scramble for the play about to be snapped -
## replaces the old mid-play HAND OFF/SCRAMBLE buttons, which were too fiddly
## to click in the middle of a live play. Only one can be armed at a time
## (see MatchSim.set_planned_action); clicking the armed one again disarms it.
func _play_action_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UIKit.label("PLAN", 12, UIKit.ACCENT))

	var handoff_btn := UIKit.button("Hand Off", 11)
	handoff_btn.custom_minimum_size = Vector2(0, 26)
	handoff_btn.tooltip_text = "Automatically hand off the instant an eligible RB is close enough to the QB."
	if sim.planned_action == "handoff":
		handoff_btn.add_theme_stylebox_override("normal", UIKit.stylebox(UIKit.LINE, 6, 2, UIKit.ACCENT))
	handoff_btn.pressed.connect(func():
		sim.set_planned_action("handoff")
		_refresh_bar())
	row.add_child(handoff_btn)

	var scramble_btn := UIKit.button("Scramble", 11)
	scramble_btn.custom_minimum_size = Vector2(0, 26)
	scramble_btn.tooltip_text = "The QB takes off running the moment the ball is snapped."
	if sim.planned_action == "scramble":
		scramble_btn.add_theme_stylebox_override("normal", UIKit.stylebox(UIKit.LINE, 6, 2, UIKit.ACCENT))
	scramble_btn.pressed.connect(func():
		sim.set_planned_action("scramble")
		_refresh_bar())
	row.add_child(scramble_btn)

	return row


func _target_priority_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UIKit.label("PRIORITY TARGETS", 12, UIKit.ACCENT))

	for f in sim.flex_players():
		var slot: String = f.slot
		var pd := f.data
		var on := sim.is_priority_target(slot)
		var b := UIKit.button("#%d %s" % [pd.number, pd.pname], 11)
		b.custom_minimum_size = Vector2(0, 26)
		if on:
			b.add_theme_stylebox_override("normal", UIKit.stylebox(UIKit.LINE, 6, 2, UIKit.ACCENT))
		b.pressed.connect(func():
			sim.toggle_priority_target(slot)
			_refresh_bar())
		row.add_child(b)

	var all_on := sim.all_priority_targets_selected()
	var all_btn := UIKit.button("Clear all" if all_on else "Select all", 11)
	all_btn.custom_minimum_size = Vector2(0, 26)
	all_btn.pressed.connect(func():
		if all_on:
			sim.clear_priority_targets()
		else:
			sim.select_all_priority_targets()
		_refresh_bar())
	row.add_child(all_btn)

	return row


## Dev-mode-only: lets the defense's overall quality be dialed up or down
## live, in between plays, without waiting for a new drive. Rebuilding the
## defense re-reads sim.opponent_quality each time this bar redraws (i.e.
## every presnap), so the slider always starts wherever it was last left.
func _dev_defense_slider() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(UIKit.label("DEV: Defender power", 13, UIKit.ACCENT))

	var slider := HSlider.new()
	slider.min_value = 1.0
	slider.max_value = 15.0
	slider.step = 0.5
	slider.value = sim.opponent_quality
	slider.custom_minimum_size = Vector2(240, 0)
	row.add_child(slider)

	var val_label := UIKit.label("%.1f" % sim.opponent_quality, 13, UIKit.TEXT)
	val_label.custom_minimum_size = Vector2(36, 0)
	row.add_child(val_label)

	slider.value_changed.connect(func(v: float):
		sim.regenerate_defense(GameState.rng, v)
		val_label.text = "%.1f" % v
		# The old defenders just got replaced with fresh SimPlayer instances;
		# drop any card/sub panel in case it was pointing at one of them.
		_dismiss_overlays())

	return row


func _wrap_snap(snap: Button) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(180, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(snap)
	return box


func _on_snap() -> void:
	_dismiss_overlays()
	field.cancel_stroke()
	sim.snap()
	field.trigger_zoom_pulse()
	_refresh_bar()


func _live_bar() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.add_child(UIKit.label("LIVE   ", 15, UIKit.ACCENT))

	if sim.planned_action != "":
		var plan_label := "Hand Off" if sim.planned_action == "handoff" else "Scramble"
		row.add_child(UIKit.label("Plan: %s" % plan_label, 13, UIKit.MUTED))

	return row


func _result_bar() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER

	var r := sim.result
	var col := UIKit.TEXT
	if bool(r.get("td", false)):
		col = UIKit.GOOD
	elif bool(r.get("turnover", false)):
		col = UIKit.BAD

	var t := UIKit.label(String(r.get("text", "")), 24, col)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)

	var events: Array = r.get("events", [])
	if not events.is_empty():
		var e := UIKit.label("   ".join(events), 13, UIKit.ACCENT)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(e)

	var cont := UIKit.primary_button("CONTINUE", 18)
	cont.custom_minimum_size = Vector2(0, 40)
	cont.pressed.connect(_on_continue)
	v.add_child(cont)
	return v


func _on_continue() -> void:
	_dismiss_overlays()
	var scored := bool(sim.result.get("td", false))
	var outcome := sim.advance()
	if outcome["drive_over"]:
		opponent_note = ""
		var more_drives_left := sim.drive_num < sim.total_drives
		if more_drives_left:
			opponent_note = sim.sim_opponent_drive()
			sim.log_line(opponent_note)
		# No point handing out a per-game upgrade for a drive that was the
		# match's last - there's no more of the game left for it to matter in.
		if scored and more_drives_left:
			_start_upgrade_choice()
			return
	else:
		_apply_call()
	_refresh_bar()


func _drive_over_bar() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER

	var last_drive := sim.drive_num >= sim.total_drives

	var t := UIKit.label("Drive over.   %s %d  -  %d %s" % [
		GameState.team_name, sim.score_us, sim.score_them, sim.opponent_name], 20, UIKit.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)

	if opponent_note != "":
		var o := UIKit.label(opponent_note, 14, UIKit.DEFENSE)
		o.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(o)

	if last_drive:
		var finish := UIKit.primary_button("FINAL WHISTLE", 18)
		finish.custom_minimum_size = Vector2(0, 40)
		finish.pressed.connect(_finish_match)
		v.add_child(finish)
	else:
		var next := UIKit.primary_button("NEXT DRIVE", 18)
		next.custom_minimum_size = Vector2(0, 40)
		next.pressed.connect(func():
			_dismiss_overlays()
			sim.begin_drive()
			_apply_call()
			field.snap_camera()
			_refresh_bar())
		v.add_child(next)
	return v


func _upgrade_pending_bar() -> Control:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(UIKit.label("Pick your per-game upgrade above to continue.", 16, UIKit.ACCENT))
	return v


# ============================================================================
# Per-game roguelike upgrade (after a scoring drive)
# ============================================================================

## 3 fixed (player, stat, amount) combos - the coach picks one of the 3
## directly, no separate "who gets it" step. See _assign_recipients for the
## "at least one flex player" guarantee.
func _start_upgrade_choice() -> void:
	pending_upgrades = _assign_recipients(UpgradeDB.roll(sim.rng, 3))
	_show_upgrade_choices()


## Pairs each rolled (stat, amount) upgrade with a specific offensive player.
## The first combo is always drawn from the flex slots (WR/RB/TE) - otherwise
## a QB/Center/Tackle-only draw would make this choice mostly about the
## trenches - and later combos avoid repeating an already-chosen player
## while a fresh one is still available.
func _assign_recipients(rolled: Array) -> Array:
	var flexes := sim.flex_players()
	var chosen: Array = []
	var out: Array = []
	for i in rolled.size():
		var pool: Array = flexes if (i == 0 and not flexes.is_empty()) else sim.offense
		var avail: Array = pool.filter(func(sp): return not chosen.has(sp))
		if avail.is_empty():
			avail = pool
		var sp: SimPlayer = avail[sim.rng.randi_range(0, avail.size() - 1)]
		chosen.append(sp)
		var e: Dictionary = (rolled[i] as Dictionary).duplicate()
		e["player"] = sp.data
		e["slot"] = sp.slot
		out.append(e)
	return out


func _show_upgrade_choices() -> void:
	for c in upgrade_panel.get_children():
		c.queue_free()
	upgrade_panel.custom_minimum_size = Vector2(460, 0)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	upgrade_panel.add_child(v)

	v.add_child(UIKit.label("TOUCHDOWN! PICK A BOOST", 18, UIKit.ACCENT))
	v.add_child(UIKit.label("Lasts for the rest of this game only.", 12, UIKit.MUTED))
	v.add_child(UIKit.rule())

	for entry in pending_upgrades:
		v.add_child(_upgrade_choice_row(entry))

	upgrade_panel.visible = true
	_center_upgrade_panel()


func _upgrade_choice_row(entry: Dictionary) -> Control:
	var pd: PlayerData = entry["player"]
	var stat := String(entry.get("stat", ""))
	var amount := int(entry.get("amount", 0))
	var cur := pd.stat(stat) + int(sim.match_bonus_for(pd).get(stat, 0))
	var future := cur + amount

	var b := UIKit.primary_button("", 16)
	b.custom_minimum_size = Vector2(0, 48)
	b.pressed.connect(func(): _apply_upgrade(pd, entry))

	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	h.offset_right = -10
	h.add_theme_constant_override("separation", 8)

	# This sits on a primary_button's solid ACCENT (gold) background, so every
	# label here needs a dark color chosen explicitly - UIKit.label's default
	# light/muted colors (and ACCENT itself) all but disappear on top of it.
	const DARK := Color("13200f")
	h.add_child(UIKit.label("#%d %s" % [pd.number, pd.pname], 14, DARK))
	h.add_child(UIKit.label(pd.pos_name(), 11, Color(DARK, 0.65)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	h.add_child(UIKit.label(UpgradeDB.label(entry), 14, DARK))
	h.add_child(UIKit.label("%s %d -> %d" % [UIKit.STAT_LABELS.get(stat, stat), cur, future], 12, Color(DARK, 0.75)))

	b.add_child(h)
	return b


func _apply_upgrade(pd: PlayerData, entry: Dictionary) -> void:
	sim.add_match_bonus(pd, String(entry.get("stat", "")), int(entry.get("amount", 0)))
	pending_upgrades = []
	upgrade_panel.visible = false
	upgrade_panel.custom_minimum_size = Vector2(460, 0)
	_refresh_bar()


func _center_upgrade_panel() -> void:
	_center_panel(upgrade_panel)


func _center_panel(panel: PanelContainer) -> void:
	await get_tree().process_frame
	panel.position = (size - panel.size) * 0.5


func _finish_match() -> void:
	var won := sim.won()
	# The bowl game (the bracket's last entry) pays out per the chosen bowl's
	# prestige tier instead of the flat build-up-round bonus - see BowlDB.
	var is_bowl_game := GameState.round_index == GameState.bracket.size() - 1
	var win_bonus := BowlDB.win_bonus(GameState.chosen_bowl) if is_bowl_game else 150
	if won:
		bucks_earned += win_bonus
	GameState.add_bucks(bucks_earned)
	GameState.last_result = {
		"won": won,
		"score_us": sim.score_us,
		"score_them": sim.score_them,
		"opponent": sim.opponent_name,
		"bucks": bucks_earned,
		"win_bonus": win_bonus,
		"round": GameState.round_label(),
	}
	GameState.finish_match(won)
	_check_sacrificial_gloves()
	get_tree().change_scene_to_file("res://scenes/post_match.tscn")


## "Sacrificial Gloves": whoever's wearing them at the end of the match is
## cut and replaced with one random Cursed player, win or lose - independent
## of (and can stack with) a Ritual Site visit.
func _check_sacrificial_gloves() -> void:
	for i in GameState.roster.size():
		if GameState.roster[i].item_id == "sacrificial_gloves":
			var exclude := {}
			var cursed_names := CursedPlayerDB.all_names()
			for p in GameState.roster:
				if cursed_names.has(p.pname):
					exclude[p.pname] = true
			var cursed := CursedPlayerDB.random_cursed(GameState.rng, exclude)
			GameState.cut_player(i)
			GameState.add_player(cursed)
			return


# ============================================================================
# Player card and substitutions
# ============================================================================

func _can_substitute() -> bool:
	return sim.phase == MatchSim.Phase.PRESNAP or sim.phase == MatchSim.Phase.DRIVE_OVER


func _on_player_clicked(sp: SimPlayer) -> void:
	card_player = sp
	field.selected = sp
	side_panel.visible = false
	_side_panel_mode = ""
	_show_card(sp)


func _dismiss_overlays() -> void:
	card.visible = false
	side_panel.visible = false
	_side_panel_mode = ""
	card_player = null
	if examples_panel != null:
		examples_panel.visible = false
	if field != null:
		field.selected = null


## An ESPN-style box score for THIS game - passing/rushing/receiving lines
## built from sim.game_stats (see MatchSim._credit_game_stats), not the
## players' static ratings. A player with no snaps in a category just
## doesn't get a row there.
func _open_team_stats() -> void:
	_side_panel_mode = "stats"
	card.visible = false
	for c in side_panel.get_children():
		c.queue_free()

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	side_panel.add_child(v)

	var head := HBoxContainer.new()
	head.add_child(UIKit.label("TEAM STATS", 16, UIKit.ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := UIKit.button("x", 14)
	close.custom_minimum_size = Vector2(32, 0)
	close.pressed.connect(_dismiss_overlays)
	head.add_child(close)
	v.add_child(head)
	v.add_child(UIKit.rule())

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 16)
	list.add_child(_stat_section("PASSING", ["CMP/ATT", "YDS", "TD", "INT"], _passing_rows()))
	list.add_child(_stat_section("RUSHING", ["CAR", "YDS", "TD", "AVG"], _rushing_rows()))
	list.add_child(_stat_section("RECEIVING", ["REC", "YDS", "TD", "AVG"], _receiving_rows()))
	v.add_child(UIKit.scroll(list))
	side_panel.visible = true


func _passing_rows() -> Array:
	var rows: Array = []
	for slot in GameState.SLOT_ORDER:
		var p := GameState.player_at(slot)
		if p == null:
			continue
		var s := sim.stat_line_for(p)
		var att := int(s.get("pass_att", 0))
		if att == 0:
			continue
		rows.append([p.pname, "%d/%d" % [int(s.get("pass_comp", 0)), att],
			"%d" % int(s.get("pass_yards", 0.0)), "%d" % int(s.get("pass_td", 0)),
			"%d" % int(s.get("pass_int", 0))])
	return rows


func _rushing_rows() -> Array:
	var rows: Array = []
	for slot in GameState.SLOT_ORDER:
		var p := GameState.player_at(slot)
		if p == null:
			continue
		var s := sim.stat_line_for(p)
		var att := int(s.get("rush_att", 0))
		if att == 0:
			continue
		var yds := float(s.get("rush_yards", 0.0))
		rows.append([p.pname, "%d" % att, "%d" % int(yds), "%d" % int(s.get("rush_td", 0)),
			"%.1f" % (yds / float(att))])
	return rows


func _receiving_rows() -> Array:
	var rows: Array = []
	for slot in GameState.SLOT_ORDER:
		var p := GameState.player_at(slot)
		if p == null:
			continue
		var s := sim.stat_line_for(p)
		var rec := int(s.get("rec", 0))
		if rec == 0:
			continue
		var yds := float(s.get("rec_yards", 0.0))
		rows.append([p.pname, "%d" % rec, "%d" % int(yds), "%d" % int(s.get("rec_td", 0)),
			"%.1f" % (yds / float(rec))])
	return rows


## One mini box-score table: a header row of column labels, then one row per
## entry in `rows` (each `[name, col1, col2, ...]`), or a muted dash if
## nobody's recorded a stat in this category yet.
func _stat_section(section_title: String, headers: Array, rows: Array) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(UIKit.label(section_title, 13, UIKit.ACCENT))

	var grid := GridContainer.new()
	grid.columns = headers.size() + 1
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)

	grid.add_child(UIKit.label("", 11, UIKit.MUTED))
	for h in headers:
		grid.add_child(UIKit.label(String(h), 11, UIKit.MUTED))

	if rows.is_empty():
		grid.add_child(UIKit.label("-", 12, UIKit.MUTED))
		for i in headers.size():
			grid.add_child(UIKit.label("", 12, UIKit.MUTED))
	else:
		for row in rows:
			grid.add_child(UIKit.label(String(row[0]), 12, UIKit.TEXT))
			for i in range(1, row.size()):
				grid.add_child(UIKit.label(String(row[i]), 12, UIKit.TEXT))

	v.add_child(grid)
	return v


func _show_card(sp: SimPlayer) -> void:
	for c in card.get_children():
		c.queue_free()

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)

	var pd := sp.data
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UIKit.label("#%d" % pd.number, 14, UIKit.MUTED))
	head.add_child(UIKit.label(pd.pname, 18, UIKit.TEXT if sp.is_offense else UIKit.DEFENSE))
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp2)
	head.add_child(UIKit.label(_role_label(sp), 13, UIKit.ACCENT))
	v.add_child(head)
	v.add_child(UIKit.rule())

	# Full stat block, including the effective numbers this play.
	for key in ["strength", "agility", "dexterity", "intelligence"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_label := UIKit.label(UIKit.STAT_LABELS[key], 13, UIKit.MUTED)
		name_label.custom_minimum_size = Vector2(42, 0)
		row.add_child(name_label)
		var base: int = pd.stat(key)
		row.add_child(_stat_bar(base))
		var eff: int = int(sp.eff.get(key, base))
		var text := str(base)
		if eff != base:
			text = "%d  ->  %d" % [base, eff]
		row.add_child(UIKit.label(text, 13, UIKit.stat_color(eff)))
		v.add_child(row)

	v.add_child(UIKit.vsep(2))
	var ab_name := AbilityDB.ability_name(pd.ability_id)
	if pd.ability_id == "":
		v.add_child(UIKit.label("No special ability", 12, UIKit.MUTED))
	else:
		v.add_child(UIKit.label(ab_name, 13, UIKit.ACCENT))
		var ab := UIKit.label(AbilityDB.ability_desc(pd.ability_id), 12, Color("9fc0b2"))
		ab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ab.custom_minimum_size = Vector2(300, 0)
		v.add_child(ab)

	if pd.aura_id != "":
		v.add_child(UIKit.vsep(2))
		var aura_col := AuraDB.aura_color(pd.aura_id)
		v.add_child(UIKit.label("%s AURA" % AuraDB.aura_name(pd.aura_id).to_upper(), 13, aura_col))
		var aura_desc := UIKit.label(AuraDB.aura_desc(pd.aura_id), 12, Color("9fc0b2"))
		aura_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		aura_desc.custom_minimum_size = Vector2(300, 0)
		v.add_child(aura_desc)

	if pd.item_id != "":
		v.add_child(UIKit.label("Item: %s" % ItemDB.item_name(pd.item_id), 12, UIKit.ACCENT))
		var it := UIKit.label(ItemDB.item_desc(pd.item_id), 12, UIKit.MUTED)
		it.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		it.custom_minimum_size = Vector2(300, 0)
		v.add_child(it)

	var bonuses: Dictionary = sim.match_bonus_for(pd)
	if not bonuses.is_empty():
		var parts: Array = []
		for stat in bonuses:
			parts.append("+%d %s" % [int(bonuses[stat]), UIKit.STAT_LABELS.get(stat, stat)])
		v.add_child(UIKit.label("This game: %s" % ", ".join(parts), 12, UIKit.GOOD))

	if sp.is_offense and _can_substitute():
		v.add_child(UIKit.vsep(2))
		var sub := UIKit.button("Substitute this position", 13)
		sub.pressed.connect(func(): _open_subs(sp.slot))
		v.add_child(sub)
	elif sp.is_offense:
		v.add_child(UIKit.label("Subs are only allowed before the snap.", 11, UIKit.MUTED))

	card.visible = true
	_place_card(sp)


func _stat_bar(value: int) -> Control:
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0)
	bar.custom_minimum_size = Vector2(150, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := value
	bar.draw.connect(func():
		bar.draw_rect(Rect2(Vector2.ZERO, bar.size), Color(0, 0, 0, 0.35))
		var w := bar.size.x * clampf(float(v) / 15.0, 0.0, 1.0)
		bar.draw_rect(Rect2(Vector2.ZERO, Vector2(w, bar.size.y)), UIKit.stat_color(v)))
	return bar


func _role_label(sp: SimPlayer) -> String:
	if not sp.is_offense:
		if sp.slot.begins_with("DL"):
			return "DEFENSIVE LINE"
		if sp.slot.begins_with("LB"):
			return "LINEBACKER"
		return "DEFENSIVE BACK"
	if sp.slot.begins_with("T"):
		return "%s  (%s)" % [GameState.slot_label(sp.slot), sp.data.pos_name()]
	if sp.slot.begins_with("F"):
		return "FLEX  (%s)" % sp.data.pos_name()
	return "%s  (%s)" % [sp.slot, sp.data.pos_name()]


## Put the card next to the player without letting it run off screen.
func _place_card(sp: SimPlayer) -> void:
	await get_tree().process_frame
	var p: Vector2 = field.to_px(sp.pos)
	var s := card.size
	var pos: Vector2 = p + Vector2(28, -s.y * 0.5)
	if pos.x + s.x > size.x - 12:
		pos.x = p.x - s.x - 28
	pos.x = clampf(pos.x, 12, maxf(12, size.x - s.x - 12))
	pos.y = clampf(pos.y, 62, maxf(62, size.y - float(BAR_TALL) - s.y - 8))
	card.position = pos


func _open_subs(slot: String) -> void:
	sub_slot = slot
	_side_panel_mode = "subs"
	card.visible = false
	for c in side_panel.get_children():
		c.queue_free()

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	side_panel.add_child(v)

	var head := HBoxContainer.new()
	head.add_child(UIKit.label("SUB AT %s" % _slot_title(slot), 16, UIKit.ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := UIKit.button("x", 14)
	close.custom_minimum_size = Vector2(32, 0)
	close.pressed.connect(_dismiss_overlays)
	head.add_child(close)
	v.add_child(head)

	var current := GameState.player_at(slot)
	if current != null:
		v.add_child(UIKit.label("On the field: #%d %s" % [current.number, current.pname], 12, UIKit.MUTED))
	v.add_child(UIKit.rule())

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)

	var kind := GameState.slot_kind(slot)
	var candidates: Array = []
	for i in GameState.roster.size():
		if GameState.is_starting(i):
			continue
		if not GameState.fits_slot(i, slot):
			continue
		candidates.append(i)
	candidates.sort_custom(func(a, b):
		var pa: PlayerData = GameState.roster[a]
		var pb: PlayerData = GameState.roster[b]
		return pa.overall() > pb.overall())

	if candidates.is_empty():
		list.add_child(UIKit.label("Nobody on the bench.", 13, UIKit.MUTED))
	for idx in candidates:
		list.add_child(_sub_row(idx, kind, slot))

	v.add_child(UIKit.scroll(list))
	side_panel.visible = true


func _sub_row(idx: int, kind: String, slot: String) -> Control:
	var p: PlayerData = GameState.roster[idx]
	var b := UIKit.button("", 12)
	b.custom_minimum_size = Vector2(0, 72)
	b.pressed.connect(func():
		GameState.set_slot(slot, idx)
		sim.resync_offense(GameState.starters())
		# Personnel changed, so the formation may reshuffle - re-hang every
		# drawn route off the new alignment.
		_apply_call(false)
		_dismiss_overlays())

	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8
	h.offset_right = -8
	h.add_theme_constant_override("separation", 8)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.add_child(UIKit.label("#%d %s" % [p.number, p.pname], 14))
	var fit := p.natural_slot_kind() == kind
	line.add_child(UIKit.label(p.pos_name(), 11, UIKit.MUTED if fit else UIKit.BAD))
	col.add_child(line)
	col.add_child(UIKit.stat_row(p, 11))
	var ab_text := "No special ability" if p.ability_id == "" else "* %s" % AbilityDB.ability_name(p.ability_id)
	var ab := UIKit.label(ab_text, 11, UIKit.MUTED if p.ability_id == "" else Color("9fc0b2"))
	col.add_child(ab)
	h.add_child(col)

	var ovr := UIKit.label(str(p.overall()), 18, UIKit.stat_color(p.overall()))
	ovr.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(ovr)

	b.add_child(h)
	return b


func _slot_title(slot: String) -> String:
	if slot.begins_with("T"):
		return GameState.slot_label(slot)
	if slot.begins_with("F"):
		return "FLEX %s" % slot.substr(1, 1)
	return slot
