extends Control

## The match screen. The field fills the whole window; everything else is an
## overlay on top of it:
##   - a thin scoreboard strip along the top
##   - the play menu along the bottom
##   - a card that pops up when you click a player
##   - a substitution list that slides in from the right
##
## The MatchSim itself lives here; the field view only renders it.

const SUB_STEP := 1.0 / 120.0
const BAR_TALL := 186
const BAR_SHORT := 74

var sim: MatchSim
var field: Control

var top_bar: PanelContainer
var play_bar: PanelContainer
var bar_host: MarginContainer
var side_panel: PanelContainer
var card: PanelContainer
var log_label: Label
var cam_btn: Button

var _sb: Dictionary = {}
var _last_phase: int = -1

var speed: float = 1.0
var bucks_earned: int = 0
var selected_play: String = ""
var opponent_note: String = ""
var card_player: SimPlayer = null
var sub_slot: String = ""


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
		Generator.make_defense(GameState.rng, quality),
		quality,
		String(opp.get("name", "Opponent")),
		int(opp.get("drives", 4))
	)
	sim.start_match()
	bucks_earned = 0
	selected_play = GameState.active_plays[0] if not GameState.active_plays.is_empty() else ""
	if selected_play != "":
		sim.set_play(selected_play)


# ============================================================================
# Layout
# ============================================================================

func _build_layout() -> void:
	field = preload("res://scripts/ui/field_view.gd").new()
	field.set_anchors_preset(Control.PRESET_FULL_RECT)
	field.sim = sim
	field.player_clicked.connect(_on_player_clicked)
	field.field_clicked.connect(_dismiss_overlays)
	field.bottom_inset = float(BAR_TALL)
	add_child(field)
	field.snap_camera()

	_build_top_bar()
	_build_log()
	_build_play_bar()
	_build_side_panel()
	_build_card()


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

	cam_btn = UIKit.button("", 13)
	cam_btn.custom_minimum_size = Vector2(190, 0)
	cam_btn.pressed.connect(func(): field.toggle_camera_lock())
	row.add_child(cam_btn)
	_update_cam_btn()

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

	var tall := sim.phase != MatchSim.Phase.LIVE
	play_bar.offset_top = -float(BAR_TALL if tall else BAR_SHORT)
	side_panel.offset_bottom = -float(BAR_TALL if tall else BAR_SHORT)
	for side in ["left", "right"]:
		bar_host.add_theme_constant_override("margin_" + side, 8)
	bar_host.add_theme_constant_override("margin_top", 4)
	bar_host.add_theme_constant_override("margin_bottom", 4)

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
	head.add_child(UIKit.label("CALL THE PLAY", 15, UIKit.ACCENT))
	head.add_child(UIKit.label("%s on the %s   -   click any player to inspect or sub"
		% [sim.down_text(), sim.yard_line_text(sim.los)], 12, UIKit.MUTED))
	v.add_child(head)

	if GameState.dev_mode:
		v.add_child(_dev_defense_slider())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)

	# A horizontal scroller, not a plain row: dev mode's active_plays can hold
	# every play in the book at once, which is wider than the screen.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(row)

	for id in GameState.active_plays:
		row.add_child(_play_card(id))

	var snap := UIKit.primary_button("SNAP THE BALL", 18)
	snap.custom_minimum_size = Vector2(0, 38)
	snap.disabled = selected_play == ""
	snap.pressed.connect(_on_snap)
	body.add_child(_wrap_snap(snap))
	return v


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


func _play_card(id: String) -> Control:
	var pl := PlayDB.get_play(id)
	var chosen := id == selected_play

	var b := UIKit.button("", 12)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(130, 128)
	if chosen:
		b.add_theme_stylebox_override("normal", UIKit.stylebox(UIKit.LINE, 6, 2, UIKit.ACCENT))
	b.pressed.connect(func():
		selected_play = id
		sim.set_play(id, false)
		_refresh_bar())

	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 6
	v.offset_right = -6
	v.offset_top = 4
	v.offset_bottom = -4
	v.add_theme_constant_override("separation", 1)

	var t := UIKit.label(pl.get("name", id), 13, UIKit.ACCENT if chosen else UIKit.TEXT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)

	var diagram := PlayDiagram.new()
	diagram.play_id = id
	diagram.compact = true
	diagram.size_flags_vertical = Control.SIZE_EXPAND_FILL
	diagram.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(diagram)

	b.add_child(v)
	return b


func _on_snap() -> void:
	_dismiss_overlays()
	sim.snap()
	_refresh_bar()


func _live_bar() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.add_child(UIKit.label("LIVE   ", 15, UIKit.ACCENT))
	for s in [0.5, 1.0, 2.0, 4.0]:
		var b := UIKit.button("%sx" % ("0.5" if s == 0.5 else str(int(s))), 14)
		b.custom_minimum_size = Vector2(62, 34)
		if is_equal_approx(s, speed):
			b.add_theme_stylebox_override("normal", UIKit.stylebox(UIKit.LINE, 6, 2, UIKit.ACCENT))
		b.pressed.connect(func():
			speed = s
			_refresh_bar())
		row.add_child(b)
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
	var outcome := sim.advance()
	if outcome["drive_over"]:
		opponent_note = ""
		if sim.drive_num < sim.total_drives:
			opponent_note = sim.sim_opponent_drive()
			sim.log_line(opponent_note)
	else:
		sim.set_play(selected_play)
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
			sim.set_play(selected_play)
			field.snap_camera()
			_refresh_bar())
		v.add_child(next)
	return v


func _finish_match() -> void:
	var won := sim.won()
	if won:
		bucks_earned += 150
	GameState.add_bucks(bucks_earned)
	GameState.last_result = {
		"won": won,
		"score_us": sim.score_us,
		"score_them": sim.score_them,
		"opponent": sim.opponent_name,
		"bucks": bucks_earned,
		"round": GameState.round_label(),
	}
	GameState.finish_match(won)
	get_tree().change_scene_to_file("res://scenes/post_match.tscn")


# ============================================================================
# Player card and substitutions
# ============================================================================

func _can_substitute() -> bool:
	return sim.phase == MatchSim.Phase.PRESNAP or sim.phase == MatchSim.Phase.DRIVE_OVER


func _on_player_clicked(sp: SimPlayer) -> void:
	card_player = sp
	field.selected = sp
	side_panel.visible = false
	_show_card(sp)


func _dismiss_overlays() -> void:
	card.visible = false
	side_panel.visible = false
	card_player = null
	if field != null:
		field.selected = null


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

	if pd.item_id != "":
		v.add_child(UIKit.label("Item: %s" % ItemDB.item_name(pd.item_id), 12, UIKit.ACCENT))
		var it := UIKit.label(ItemDB.item_desc(pd.item_id), 12, UIKit.MUTED)
		it.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		it.custom_minimum_size = Vector2(300, 0)
		v.add_child(it)

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
		return "TACKLE  (%s)" % sp.data.pos_name()
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
	b.custom_minimum_size = Vector2(0, 56)
	b.pressed.connect(func():
		GameState.set_slot(slot, idx)
		sim.resync_offense(GameState.starters())
		sim.set_play(selected_play, false)
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
	h.add_child(col)

	var ovr := UIKit.label(str(p.overall()), 18, UIKit.stat_color(p.overall()))
	ovr.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(ovr)

	b.add_child(h)
	return b


func _slot_title(slot: String) -> String:
	if slot.begins_with("T"):
		return "TACKLE %s" % slot.substr(1, 1)
	if slot.begins_with("F"):
		return "FLEX %s" % slot.substr(1, 1)
	return slot
