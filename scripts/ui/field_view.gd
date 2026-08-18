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

var sim: MatchSim = null
var show_preview: bool = true
var selected: SimPlayer = null

var _scale: float = 20.0
var _center: Vector2 = Vector2.ZERO
var _cam_x: float = 30.0
var _visible_yards: float = MIN_VERT_YARDS

## Pixels of the bottom edge hidden behind the play menu; the camera centres
## on what is actually visible rather than on the whole control.
var bottom_inset: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	set_process(true)


const FALL_TIME := 0.34

func _process(delta: float) -> void:
	if sim != null:
		var target := _camera_target()
		_cam_x = lerpf(_cam_x, target, clampf(delta * CAM_SPEED, 0.0, 1.0))
		for sp in sim.offense:
			_advance_anim(sp, delta)
		for sp in sim.defense:
			_advance_anim(sp, delta)
	queue_redraw()


func _advance_anim(sp: SimPlayer, delta: float) -> void:
	if sp.downed > 0.0 and sp.downed < FALL_TIME * 2.0:
		sp.downed += delta


func snap_camera() -> void:
	if sim != null:
		_cam_x = _camera_target()


func _camera_target() -> float:
	var focus := sim.los + CAM_LEAD
	if sim.phase == MatchSim.Phase.LIVE or sim.phase == MatchSim.Phase.DEAD:
		focus = sim.ball_pos.x + CAM_LEAD * 0.5
	var half := _visible_yards * 0.5
	return clampf(focus, half, YD - half)


func _recompute_transform() -> void:
	_scale = minf(size.x / YW, size.y / MIN_VERT_YARDS)
	_visible_yards = size.y / _scale
	_center = Vector2(size.x * 0.5, (size.y - bottom_inset) * 0.5)


## Field yards (downfield, lateral) -> screen pixels.
func to_px(p: Vector2) -> Vector2:
	return Vector2(
		_center.x + (p.y - YW * 0.5) * _scale,
		_center.y - (p.x - _cam_x) * _scale
	)


func _gui_input(event: InputEvent) -> void:
	if sim == null:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
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
	# was travelling and stretch the shape out along it.
	var axis := UP
	if fall > 0.0:
		var down_dir := _fall_dir(sp)
		axis = UP.rotated(angle_difference(UP.angle(), down_dir.angle()) * fall)
	var half := lerpf(r * 0.46, r * 0.98, fall)
	var wide := lerpf(r * 0.95, r * 0.80, fall)
	var a := center - axis * half
	var b := center + axis * half

	draw_circle(center + Vector2(2, 4), r * lerpf(0.92, 0.78, fall), Color(0, 0, 0, 0.30))

	_capsule(a, b, wide + 3.0, body.darkened(0.5))
	_capsule(a, b, wide, body)

	if sp == sim.carrier and fall <= 0.0:
		draw_arc(center, r * 1.18, 0, TAU, 26, UIKit.BALL, 3.0)
	if sp == selected:
		draw_arc(center, r * 1.45, 0, TAU, 28, Color("9be8ff"), 2.5)

	# Jersey number, printed on the body below the head.
	if fall < 0.6:
		var text := sp.label
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var np := center - axis * r * 0.34
		draw_string(font, np + Vector2(-tw * 0.5, float(fs) * 0.35), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(0.16, 0.12, 0.04, 1.0 - fall) if sp.is_offense
			else Color(0.88, 0.95, 1.0, 1.0 - fall))

	# Head: sits at the top of the body, and slides out to the end as he falls.
	var hp := center + axis * lerpf(r * 0.50, r * 1.12, fall)
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
