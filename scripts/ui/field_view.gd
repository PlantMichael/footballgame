extends Control

## Draws the field and everything on it. Reads straight from a MatchSim;
## it owns no game state of its own.
##
## The field runs VERTICALLY: your offense attacks up the screen. Field-x
## (downfield yards) maps to screen -y, and field-y (lateral yards) maps to
## screen x. The camera follows the ball and is clamped to the field.

signal player_clicked(sp: SimPlayer)
signal field_clicked()

const YD := MatchSim.FIELD_LEN
const YW := MatchSim.FIELD_W

## Never show less than this much of the field vertically, so deep routes
## stay on screen instead of the camera slamming into the ball.
const MIN_VERT_YARDS := 38.0
const CAM_LEAD := 6.0        # bias the camera downfield of the ball
const CAM_SPEED := 3.5
const UP := Vector2(0.0, -1.0)

## Free-camera controls: WASD pans, right-click-drag pans, the scroll wheel
## zooms. Any manual pan disengages `camera_locked`; toggling it back on
## (see toggle_camera_lock) resumes following the ball.
const PAN_SPEED := 22.0      # yards/second at 1x zoom
const ZOOM_MIN := 0.6
const ZOOM_MAX := 2.5
const ZOOM_STEP := 0.1

var sim: MatchSim = null
var show_preview: bool = true
var selected: SimPlayer = null
var camera_locked: bool = true

var _scale: float = 20.0
var _center: Vector2 = Vector2.ZERO
var _cam_x: float = 30.0
var _cam_y: float = 0.0        # lateral camera focus, in field yards
var _zoom: float = 1.0
var _visible_yards: float = MIN_VERT_YARDS
var _dragging: bool = false

## Floating "+ STAT" stat-gain popups. MatchSim queues raw events onto each
## SimPlayer's `pending_stat_gains` (one entry per point, so +5 Agility is 5
## separate events); this drains that queue at a steady pace per player and
## animates whatever's currently showing. SimPlayer -> Array of
## {"stat": String, "age": float}.
var _pops: Dictionary = {}
var _pop_timers: Dictionary = {}   # SimPlayer -> seconds until the next drain
const POP_INTERVAL := 0.10         # gap between successive pops for one player
const POP_LIFETIME := 0.85         # how long a single popup stays alive
const POP_GROW_TIME := 0.12        # quick pop-in before it settles
const POP_HOLD_TIME := 0.30        # full size/opacity before it starts fading
const POP_RISE := 30.0             # pixels risen over its lifetime; older pops in a
                                    # burst are naturally higher since they've had
                                    # more time to rise, giving a rising trail for free

## Pixels of the bottom edge hidden behind the play menu; the camera centres
## on what is actually visible rather than on the whole control.
var bottom_inset: float = 0.0

## Body sprite lookups, cached so _draw doesn't hit ResourceLoader every
## frame for every player on the field. "view:body_id" -> Texture2D (or null
## if that player has no body art yet, e.g. a hand-picked QB not assigned
## one - those fall back to the old plain capsule).
var _tex_cache: Dictionary = {}

func _body_tex(data: PlayerData, view: String) -> Texture2D:
	var key := "%s:%s" % [view, data.body]
	if not _tex_cache.has(key):
		_tex_cache[key] = UIKit.body_texture(data, view)
	return _tex_cache[key]


## Which sprite view to show and whether to mirror it, from screen-space
## facing direction: velocity while moving, otherwise the idle stance -
## offense faces upfield (away from camera, "back"), defense faces the
## offense (toward camera, "front"), matching real presnap alignment.
func _facing_view(sp: SimPlayer) -> Array:
	var dir := UP if sp.is_offense else -UP
	if sp.vel.length() > 0.35:
		dir = Vector2(sp.vel.y, -sp.vel.x).normalized()
	var best := dir.dot(UP)
	var view := "back"
	var flip := false
	if dir.dot(-UP) > best:
		best = dir.dot(-UP); view = "front"; flip = false
	if dir.dot(Vector2.LEFT) > best:
		best = dir.dot(Vector2.LEFT); view = "left"; flip = false
	if dir.dot(Vector2.RIGHT) > best:
		best = dir.dot(Vector2.RIGHT); view = "left"; flip = true
	return [view, flip]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	set_process(true)
	_cam_y = YW * 0.5


## "L" toggles the ball-follow lock from anywhere on the match screen, no
## need to have the field itself focused.
func _unhandled_input(event: InputEvent) -> void:
	if sim == null:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_L:
		toggle_camera_lock()


const FALL_TIME := 0.34

func _process(delta: float) -> void:
	if sim != null:
		if camera_locked:
			_cam_x = lerpf(_cam_x, _camera_target_x(), clampf(delta * CAM_SPEED, 0.0, 1.0))
			_cam_y = lerpf(_cam_y, _camera_target_y(), clampf(delta * CAM_SPEED, 0.0, 1.0))
		else:
			_handle_pan_keys(delta)
		_clamp_camera()
		for sp in sim.offense:
			_advance_anim(sp, delta)
			_advance_pops(sp, delta)
		for sp in sim.defense:
			_advance_anim(sp, delta)
			_advance_pops(sp, delta)
	queue_redraw()


func _advance_anim(sp: SimPlayer, delta: float) -> void:
	if sp.downed > 0.0 and sp.downed < FALL_TIME * 2.0:
		sp.downed += delta


## Ages out active popups, then - once the pacing timer allows - pulls the
## next queued stat gain (if any) off the player and starts it popping.
func _advance_pops(sp: SimPlayer, delta: float) -> void:
	var active: Array = _pops.get(sp, [])
	if not active.is_empty():
		for entry in active:
			entry["age"] += delta
		active = active.filter(func(e): return e["age"] < POP_LIFETIME)
		_pops[sp] = active

	var timer: float = _pop_timers.get(sp, 0.0) - delta
	if timer <= 0.0 and not sp.pending_stat_gains.is_empty():
		var stat: String = sp.pending_stat_gains.pop_front()
		active.append({"stat": stat, "age": 0.0})
		_pops[sp] = active
		timer = POP_INTERVAL
	elif timer <= 0.0 and not sp.pending_events.is_empty():
		var text: String = sp.pending_events.pop_front()
		active.append({"text": text, "age": 0.0})
		_pops[sp] = active
		timer = POP_INTERVAL
	_pop_timers[sp] = timer


## Snaps the locked camera straight to its target with no lerp (e.g. at the
## start of a new drive). Has no effect while the camera is unlocked - free
## camera position is left exactly where the player put it.
func snap_camera() -> void:
	if sim != null and camera_locked:
		_cam_x = _camera_target_x()
		_cam_y = _camera_target_y()
		_clamp_camera()


func toggle_camera_lock() -> void:
	camera_locked = not camera_locked


func _camera_target_x() -> float:
	var focus := sim.los + CAM_LEAD
	if sim.phase == MatchSim.Phase.LIVE or sim.phase == MatchSim.Phase.DEAD:
		focus = sim.ball_pos.x + CAM_LEAD * 0.5
	return focus


func _camera_target_y() -> float:
	if sim.phase == MatchSim.Phase.LIVE or sim.phase == MatchSim.Phase.DEAD:
		return sim.ball_pos.y
	return YW * 0.5


## Keeps the camera focus from showing past the sidelines/end zones, however
## it got there (auto-follow, WASD, or drag).
func _clamp_camera() -> void:
	var half_y := _visible_yards * 0.5
	_cam_x = clampf(_cam_x, half_y, YD - half_y)
	var half_x := (size.x / maxf(_scale, 0.01)) * 0.5
	if half_x * 2.0 >= YW:
		_cam_y = YW * 0.5
	else:
		_cam_y = clampf(_cam_y, half_x, YW - half_x)


func _handle_pan_keys(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		move.x += 1.0
	if Input.is_key_pressed(KEY_S):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		move.y += 1.0
	if Input.is_key_pressed(KEY_A):
		move.y -= 1.0
	if move == Vector2.ZERO:
		return
	var speed := PAN_SPEED / maxf(_zoom, 0.01)
	_cam_x += move.x * speed * delta
	_cam_y += move.y * speed * delta


func _recompute_transform() -> void:
	_scale = minf(size.x / YW, size.y / MIN_VERT_YARDS) * _zoom
	_visible_yards = size.y / _scale
	_center = Vector2(size.x * 0.5, (size.y - bottom_inset) * 0.5)


## Field yards (downfield, lateral) -> screen pixels.
func to_px(p: Vector2) -> Vector2:
	return Vector2(
		_center.x + (p.y - _cam_y) * _scale,
		_center.y - (p.x - _cam_x) * _scale
	)


func _gui_input(event: InputEvent) -> void:
	if sim == null:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
			if mb.pressed:
				camera_locked = false
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			return
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return

		var hit: SimPlayer = null
		var best := _scale * 1.1     # roughly one yard of slop
		for sp in sim.offense:
			var d := to_px(sp.pos).distance_to(mb.position)
			if d < best:
				best = d
				hit = sp
		if hit == null:
			for sp in sim.defense:
				var d := to_px(sp.pos).distance_to(mb.position)
				if d < best:
					best = d
					hit = sp

		if hit != null:
			player_clicked.emit(hit)
		else:
			field_clicked.emit()
		return

	if event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		camera_locked = false
		_cam_y -= mm.relative.x / maxf(_scale, 0.01)
		_cam_x += mm.relative.y / maxf(_scale, 0.01)
		_clamp_camera()


# ============================================================================
# Drawing
# ============================================================================

func _draw() -> void:
	_recompute_transform()
	if sim == null:
		draw_rect(Rect2(Vector2.ZERO, size), UIKit.TURF)
		return
	_draw_field()
	_draw_lines_of_scrimmage()
	if show_preview and sim.phase == MatchSim.Phase.PRESNAP:
		_draw_route_preview()
	if sim.phase == MatchSim.Phase.LIVE or sim.phase == MatchSim.Phase.DEAD:
		_draw_trails()
	_draw_players()
	_draw_ball()
	_draw_stat_pops()


func _visible_range() -> Vector2i:
	var half := _visible_yards * 0.5
	return Vector2i(
		int(floor(maxf(0.0, _cam_x - half - 2.0))),
		int(ceil(minf(YD, _cam_x + half + 2.0)))
	)


func _draw_field() -> void:
	# Everything outside the sidelines.
	draw_rect(Rect2(Vector2.ZERO, size), Color("0a120f"))

	var lo := _visible_range()
	var left := to_px(Vector2(0.0, 0.0)).x
	var right := to_px(Vector2(0.0, YW)).x
	var top := to_px(Vector2(float(lo.y), 0.0)).y
	var bottom := to_px(Vector2(float(lo.x), 0.0)).y
	draw_rect(Rect2(Vector2(left, top), Vector2(right - left, bottom - top)), UIKit.TURF)

	# Alternating five yard bands give the eye something to judge motion by.
	var band_start := int(floor(float(lo.x) / 5.0)) * 5
	for x in range(band_start, lo.y + 5, 5):
		if x < 10 or x >= 110:
			continue
		if int(x / 5) % 2 == 1:
			var y0 := to_px(Vector2(float(x + 5), 0.0)).y
			var y1 := to_px(Vector2(float(x), 0.0)).y
			draw_rect(Rect2(Vector2(left, y0), Vector2(right - left, y1 - y0)), UIKit.TURF_ALT)

	# End zones.
	for ez in [[0.0, 10.0], [110.0, 120.0]]:
		var y0 := to_px(Vector2(ez[1], 0.0)).y
		var y1 := to_px(Vector2(ez[0], 0.0)).y
		if y0 < size.y and y1 > 0.0:
			draw_rect(Rect2(Vector2(left, y0), Vector2(right - left, y1 - y0)),
				UIKit.TURF.darkened(0.4))

	var chalk := Color(UIKit.CHALK, 0.32)
	for x in range(maxi(10, band_start), mini(111, lo.y + 5)):
		if x % 5 != 0:
			continue
		var y := to_px(Vector2(float(x), 0.0)).y
		draw_line(Vector2(left, y), Vector2(right, y), chalk, 2.0 if x % 10 == 0 else 1.0)

	# Hash marks.
	for x in range(maxi(11, lo.x), mini(110, lo.y + 1)):
		var y := to_px(Vector2(float(x), 0.0)).y
		for hx in [YW * 0.36, YW * 0.64]:
			var px := to_px(Vector2(0.0, hx)).x
			var half_tick := _scale * 0.33
			draw_line(Vector2(px - half_tick, y), Vector2(px + half_tick, y),
				Color(UIKit.CHALK, 0.30), 2.0)

	# Yard numbers down both sidelines.
	var font := ThemeDB.fallback_font
	var fs := int(maxf(12.0, _scale * 0.85))
	for x in range(20, 105, 10):
		if x < lo.x - 2 or x > lo.y + 2:
			continue
		var num: int = 100 - (x - 10) if (x - 10) > 50 else (x - 10)
		var text := str(num)
		var y := to_px(Vector2(float(x), 0.0)).y
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		for lat in [6.0, YW - 6.0]:
			var px := to_px(Vector2(0.0, lat)).x
			draw_string(font, Vector2(px - w * 0.5, y + fs * 0.35), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UIKit.CHALK, 0.45))

	# Sidelines and goal lines.
	draw_line(Vector2(left, 0.0), Vector2(left, size.y), Color(UIKit.CHALK, 0.55), 2.0)
	draw_line(Vector2(right, 0.0), Vector2(right, size.y), Color(UIKit.CHALK, 0.55), 2.0)
	for gl in [10.0, 110.0]:
		var y := to_px(Vector2(gl, 0.0)).y
		if y > -10.0 and y < size.y + 10.0:
			draw_line(Vector2(left, y), Vector2(right, y), Color(UIKit.CHALK, 0.85), 3.0)


func _draw_lines_of_scrimmage() -> void:
	var left := to_px(Vector2(0.0, 0.0)).x
	var right := to_px(Vector2(0.0, YW)).x

	var los_y := to_px(Vector2(sim.los, 0.0)).y
	draw_line(Vector2(left, los_y), Vector2(right, los_y), Color("4a86c8"), 2.5)

	var first := sim.los + sim.to_go
	if first < MatchSim.GOAL_LINE:
		var fy := to_px(Vector2(first, 0.0)).y
		draw_line(Vector2(left, fy), Vector2(right, fy), Color("f2c14e"), 2.5)


func _draw_route_preview() -> void:
	for entry in sim.preview_routes():
		var line: PackedVector2Array = entry["line"]
		var kind: String = entry["kind"]
		if line.size() < 2:
			continue
		var col := Color("ffe28a") if kind == "route" else Color("ff9f6e")
		var pts := PackedVector2Array()
		for p in line:
			pts.append(to_px(p))
		draw_polyline(pts, col, 3.0, true)
		var a := pts[pts.size() - 2]
		var b := pts[pts.size() - 1]
		var dir := (b - a).normalized()
		var perp := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([
			b + dir * 9.0, b - dir * 4.0 + perp * 6.0, b - dir * 4.0 - perp * 6.0
		]), col)


func _draw_trails() -> void:
	for sp in sim.offense:
		if sp.trail.size() < 2:
			continue
		var pts := PackedVector2Array()
		for p in sp.trail:
			pts.append(to_px(p))
		draw_polyline(pts, Color(UIKit.OFFENSE, 0.20), 2.0, true)


## Screen-space direction a tackled player topples: the way he was running,
## or straight ahead from his stance if he was standing still.
func _fall_dir(sp: SimPlayer) -> Vector2:
	if sp.vel.length() > 0.35:
		var v := sp.vel.normalized()
		# Convert field-space velocity into screen space.
		return Vector2(v.y, -v.x)
	return UP if sp.is_offense else -UP


func _num_font_size(r: float) -> int:
	return int(maxf(9.0, r * 0.62))


func _draw_players() -> void:
	var font := ThemeDB.fallback_font
	var r := maxf(10.0, _scale * 0.62)
	var fs := _num_font_size(r)

	# Downed players first so anyone still standing draws on top of them.
	for group in [sim.defense, sim.offense]:
		for sp in group:
			if sp.downed > 0.0:
				_draw_person(sp, r, font, fs)
	for group2 in [sim.defense, sim.offense]:
		for sp in group2:
			if sp.downed <= 0.0:
				_draw_person(sp, r, font, fs)


## A body seen from above: a slim upright capsule with the jersey number on it
## and a head circle at the top.
##
## Players always stand upright — they never lean into the direction they are
## running. The only thing that rotates the body is being tackled, and then it
## topples the way the player was going over FALL_TIME seconds.
func _draw_person(sp: SimPlayer, r: float, font: Font, fs: int) -> void:
	var p := to_px(sp.pos)

	var fall := 0.0
	if sp.downed > 0.0:
		fall = clampf(sp.downed / FALL_TIME, 0.0, 1.0)
		fall = fall * fall * (3.0 - 2.0 * fall)   # ease so he tips, then settles

	# Walk cycle: a small waddle plus a bounce, both tied to distance covered.
	var moving := clampf(sp.vel.length() / 3.0, 0.0, 1.0) * (1.0 - fall)
	var sway := sin(sp.stride) * moving
	var bounce := absf(sin(sp.stride)) * moving
	var center := p + Vector2(sway * r * 0.11, -bounce * r * 0.07)

	var body := UIKit.OFFENSE if sp.is_offense else UIKit.DEFENSE.darkened(0.08)
	var head := Color("c9a37a") if sp.is_offense else Color("a8845f")
	if fall > 0.0:
		body = body.darkened(0.22 * fall)
		head = head.darkened(0.22 * fall)

	# Upright unless he is going down, in which case rotate toward the way he
	# was travelling. The body keeps its own proportions the whole time -
	# only its facing changes, so he topples over rather than stretching out.
	var axis := UP
	if fall > 0.0:
		var down_dir := _fall_dir(sp)
		axis = UP.rotated(angle_difference(UP.angle(), down_dir.angle()) * fall)
	var half := r * 0.46
	var wide := r * 0.95
	var a := center - axis * half
	var b := center + axis * half

	draw_circle(center + Vector2(2, 4), r * lerpf(0.92, 0.78, fall), Color(0, 0, 0, 0.30))

	var facing := _facing_view(sp)
	var tex := _body_tex(sp.data, facing[0])
	if tex == null:
		_capsule(a, b, wide + 3.0, body.darkened(0.5))
		_capsule(a, b, wide, body)
	else:
		# Team-color backdrop so offense/defense stay readable at a glance -
		# the jersey art itself is a fixed navy, so this is the only team cue.
		draw_circle(center, r * 1.05, body.darkened(0.35))

		var flip: bool = facing[1]
		var tex_size := tex.get_size()
		var box_w := r * 1.55
		var box_h := r * 1.95
		var w := box_w
		var h := w * tex_size.y / tex_size.x
		if h > box_h:
			h = box_h
			w = h * tex_size.x / tex_size.y

		draw_set_transform(center, axis.angle() - UP.angle(), Vector2(-1.0 if flip else 1.0, 1.0))
		draw_texture_rect(tex, Rect2(Vector2(-w * 0.5, -h * 0.5), Vector2(w, h)), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if sp == sim.carrier and fall <= 0.0:
		draw_arc(center, r * 1.18, 0, TAU, 26, UIKit.BALL, 3.0)
	if sp == selected:
		draw_arc(center, r * 1.45, 0, TAU, 28, Color("9be8ff"), 2.5)

	# Jersey number, printed on the body below the head. The sprite path is
	# always a navy jersey regardless of team, so it always gets light text;
	# only the plain-capsule fallback still needs the per-team dark/light
	# split tuned for its gold/blue fill.
	if fall < 0.6:
		var text := sp.label
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var np := center - axis * r * 0.34
		var num_color := Color(0.92, 0.95, 1.0, 1.0 - fall)
		if tex == null:
			num_color = Color(0.16, 0.12, 0.04, 1.0 - fall) if sp.is_offense \
				else Color(0.88, 0.95, 1.0, 1.0 - fall)
		draw_string(font, np + Vector2(-tw * 0.5, float(fs) * 0.35), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, num_color)

	# Head: sits at the top of the body, rotating with it as he falls.
	var hp := center + axis * r * 0.50
	var hr := r * 0.38 * (1.0 + 0.07 * sin(sp.stride * 2.0) * moving)
	draw_circle(hp, hr * 1.22, Color("241d16"))
	draw_circle(hp, hr, head)


func _capsule(a: Vector2, b: Vector2, width: float, col: Color) -> void:
	draw_line(a, b, col, width)
	draw_circle(a, width * 0.5, col)
	draw_circle(b, width * 0.5, col)


func _draw_ball() -> void:
	if sim.carrier != null or not sim.ball_in_air:
		return
	var t := clampf(sim.ball_t / maxf(sim.ball_air_time, 0.01), 0.0, 1.0)
	var ground := to_px(sim.ball_pos)
	var lift := sin(t * PI) * _scale * 1.8
	draw_circle(ground, _scale * 0.22, Color(0, 0, 0, 0.4))
	var b := ground - Vector2(0, lift)
	var r := maxf(5.0, _scale * 0.30)
	draw_circle(b, r, UIKit.BALL)
	draw_arc(b, r, 0, TAU, 14, Color("f8ecd0"), 1.6)


## Floating "+ STAT" / "- STAT" popups to the right of whoever an ability
## just changed the stats of. Rendered oldest-first so a newer pop that has
## barely started rising never draws on top of one that's further along.
func _draw_stat_pops() -> void:
	if _pops.is_empty():
		return
	var font := ThemeDB.fallback_font
	var r := maxf(10.0, _scale * 0.62)
	var base_fs := int(maxf(13.0, _scale * 0.75))
	var fade_start := POP_GROW_TIME + POP_HOLD_TIME

	for sp in _pops.keys():
		var active: Array = _pops[sp]
		if active.is_empty():
			continue
		var anchor := to_px(sp.pos) + Vector2(r * 1.55, 0.0)

		for entry in active:
			var age: float = entry["age"]
			var col: Color
			var label: String
			if entry.has("text"):
				# Plain flavor-text event (e.g. "DROP") - always reads as bad news.
				col = UIKit.BAD
				label = String(entry["text"])
			else:
				var stat: String = entry["stat"]
				var negative := stat.begins_with("-")
				var key := stat.substr(1) if negative else stat
				col = UIKit.BAD if negative else UIKit.GOOD
				label = "%s %s" % ["-" if negative else "+", UIKit.STAT_LABELS.get(key, key.to_upper())]

			# Quick pop-in with a small overshoot, then settle - the "satisfying"
			# part of a stat popup is that little bounce at the start.
			var scale := 1.0
			if age < POP_GROW_TIME:
				scale = lerpf(0.35, 1.15, age / POP_GROW_TIME)
			elif age < POP_GROW_TIME + 0.08:
				scale = lerpf(1.15, 1.0, (age - POP_GROW_TIME) / 0.08)

			var alpha := 1.0
			if age > fade_start:
				alpha = 1.0 - clampf((age - fade_start) / maxf(0.01, POP_LIFETIME - fade_start), 0.0, 1.0)

			var pos := anchor + Vector2(0.0, -(age / POP_LIFETIME) * POP_RISE)
			var fs := maxi(9, int(round(float(base_fs) * scale)))

			# A soft drop shadow keeps it readable over both teams' colors.
			draw_string(font, pos + Vector2(1.0, float(fs) * 0.32 + 1.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.0, 0.0, 0.0, alpha * 0.55))
			draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, alpha))
