extends Control

## Draws the field and everything on it. Reads straight from a MatchSim;
## it owns no game state of its own.
##
## The field runs VERTICALLY: your offense attacks up the screen. Field-x
## (downfield yards) maps to screen -y, and field-y (lateral yards) maps to
## screen x. The camera follows the ball and is clamped to the field.

signal player_clicked(sp: SimPlayer)
signal field_clicked()

## Emitted when the coach finishes a chalk stroke on a flex player. `route`
## is waypoints in yards RELATIVE to that player's alignment, already
## simplified and truncated to the budget - i.e. ready to hand straight to
## GameState.set_route.
signal route_drawn(slot: String, route: Array)

const YD := MatchSim.FIELD_LEN
const YW := MatchSim.FIELD_W

## Never show less than this much of the field vertically, so deep routes
## stay on screen instead of the camera slamming into the ball.
const MIN_VERT_YARDS := 38.0
const CAM_LEAD := 6.0        # bias the camera downfield of the ball
## Lower than it used to be (3.5) - the follow-cam read as too snappy/jerky
## panning between plays. See _zoom_pulse for the distinct quick-zoom punch
## at the start/end of a play, which is a separate effect from this.
const CAM_SPEED := 2.0
const UP := Vector2(0.0, -1.0)

## A brief extra zoom-in, triggered once at the snap and once when a play
## ends (see trigger_zoom_pulse, called from match.gd), that eases back to
## nothing over ZOOM_PULSE_TIME. Same decay-over-time shape as the screen
## shake below, just applied to zoom instead of a pixel offset.
const ZOOM_PULSE_AMOUNT := 0.12
const ZOOM_PULSE_TIME := 0.35
var _zoom_pulse_t: float = 0.0

## An eased camera move between plays (see glide_camera): from where the last
## play ended back to the new line of scrimmage, instead of either cutting
## there or trailing after it on the ordinary follow lerp.
const GLIDE_TIME := 0.7
var _glide_t: float = 0.0          # seconds left; 0 = not gliding
var _glide_from: Vector2 = Vector2.ZERO   # (cam_x, cam_y) when it started

## Free-camera controls: WASD pans, right-click-drag pans, the scroll wheel
## zooms. Any manual pan disengages `camera_locked`; toggling it back on
## (see toggle_camera_lock) resumes following the ball.
const PAN_SPEED := 22.0      # yards/second at 1x zoom
const ZOOM_MIN := 0.6
const ZOOM_MAX := 2.5
const ZOOM_STEP := 0.1

## Out of bounds. Lighter than UIKit.TURF so the sidelines read as grass
## rather than as a void, while the darker playing surface still stands out.
const SIDELINE_GRASS := Color("356f47")

## Player rendering. `r` is the base player radius in pixels, derived from the
## zoom; everything else about a body is expressed as a multiple of it.
const PLAYER_R := 0.72          # yards of radius per player, times _scale
const PLAYER_R_MIN := 12.0

## Bodies are normalised to equal AREA rather than fitted inside a box. The
## source sprites are framed very inconsistently - front-view aspect ratios
## run from 0.57 to 1.39 - so box-fitting drew the wide ones as squat blobs
## and the narrow ones as tall slivers at noticeably different visual sizes.
## Matching area instead makes every body take up about the same amount of
## screen, whatever its framing. The value is the side of that area square,
## in units of `r`.
const BODY_AREA := 1.95

## The team-colour disc behind each player. The FILL is near-invisible, per
## request. The rim is not: the jersey art is a fixed navy for both sides, so
## with the fill gone this outline becomes the only thing telling offence
## from defence, and at a faint alpha the two teams were genuinely
## indistinguishable on the field.
const DISC_ALPHA := 0.12
const DISC_RIM_ALPHA := 0.5
const DISC_RIM_WIDTH := 2.6

## Screen shake on a catch, scaled by how far the ball travelled.
const SHAKE_MIN_PX := 2.0
const SHAKE_MAX_PX := 16.0
const SHAKE_FULL_YARDS := 28.0   # air yards at which the shake maxes out
const SHAKE_TIME := 0.38

## A bigger, longer shake for "combustion"/"aftershock" (see MatchSim.
## big_shakes) - well past what any ordinary catch produces.
const BIG_SHAKE_PX := 26.0
const BIG_SHAKE_TIME := 0.65

## Ability props (see MatchSim's "Ability props" section), cut out of
## assets/assets.png by assets/props/_cut_props.py. Sizes are in yards.
const TEX_PEEL := preload("res://assets/props/banana_peel.png")
const TEX_CHAIN := preload("res://assets/props/chain.png")
const TEX_KEG := preload("res://assets/props/beer_keg.png")
const TEX_SLOT := preload("res://assets/props/slot_machine.png")
const PEEL_W := 2.0
const KEG_H := 2.0
const SLOT_H := 2.8
const CHAIN_THICK := 0.65
const JACKPOT_TEXT_TIME := 1.6
const SHOT_FLASH_TIME := 0.3

## Weather (see WeatherDB): screen-space particles - raindrops, snowflakes,
## wind streaks - each {"p": Vector2 px, "v": Vector2 px/s, "age": float,
## "life": float, "size": float, "phase": float}. Topped up to the weather's
## count every frame; purely visual.
var _wx: Array = []
const RAIN_DROPS := 240
const SNOW_FLAKES := 170
const WIND_STREAKS := 22
const RAIN_TINT := Color(0.05, 0.08, 0.16, 0.20)
const SNOW_COVER := Color(0.93, 0.96, 1.0, 0.20)
const PUDDLE_FILL := Color(0.24, 0.38, 0.50, 0.60)
const PUDDLE_RIM := Color(0.62, 0.78, 0.90, 0.45)

var sim: MatchSim = null
var show_preview: bool = true
var selected: SimPlayer = null
var camera_locked: bool = true

## Chalk drawing. Pressing on a flex player and dragging draws his route;
## pressing and releasing without really moving is still a plain click, so
## inspecting a receiver and drawing for him share the same gesture.
## `_stroke` is in absolute field yards - it is converted to alignment-
## relative waypoints only when the stroke is finished.
var draw_enabled: bool = false
var _stroke_slot: String = ""
var _stroke: Array = []
var _stroke_len: float = 0.0
var _stroke_player: SimPlayer = null
const DRAW_TAP_YARDS := 1.2

var _scale: float = 20.0
var _center: Vector2 = Vector2.ZERO
var _cam_x: float = 30.0
var _cam_y: float = 0.0        # lateral camera focus, in field yards
var _zoom: float = 1.0
var _visible_yards: float = MIN_VERT_YARDS
var _dragging: bool = false

## Active screen shake: current amplitude in pixels, seconds left, and a
## phase that drives the wobble. Applied as a pure pixel offset on top of the
## camera (see to_px/to_yards) so it never touches camera state or clamping.
var _shake_px: float = 0.0
var _shake_left: float = 0.0
var _shake_total: float = SHAKE_TIME   # duration of the currently-running shake, for the decay ratio below
var _shake_phase: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO

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

## End-of-match celebration, set once by match.gd at the final whistle:
## is_offense (bool) -> "jump" (won - bouncing up and down), "lie" (lost -
## flat on the turf), or "" (a tie - they just stand there). Empty until then.
var end_pose: Dictionary = {}
var _end_t: float = 0.0
const JUMP_HEIGHT := 0.9      # times the player radius
const JUMP_RATE := 6.5        # radians/second of the hop cycle
const LIE_DOWN_TIME := 0.55   # seconds to settle onto the turf

## Body sprite lookups, cached so _draw doesn't hit ResourceLoader every
## frame for every player on the field. "view:body_id:head_id" -> Texture2D
## (or null if that player has no body art yet, e.g. a hand-picked QB not
## assigned one - those fall back to the old plain capsule). head_id is part
## of the key because UIKit.body_texture picks a collar-skin-tone variant
## from it for the front view - two players sharing a body id but not a head
## id must not collide on the same cached texture.
var _tex_cache: Dictionary = {}

func _body_tex(data: PlayerData, view: String) -> Texture2D:
	var key := "%s:%s:%s" % [view, data.body, data.head_id]
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
	# A body with no side-view art (body 9 - the defensive backs' and a few
	# receivers' body) sticks to front/back rather than dropping to the plain
	# capsule whenever he runs across the field.
	if _body_tex(sp.data, "left") == null and _body_tex(sp.data, "front") != null:
		return [view, flip]
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
		if camera_locked and _glide_t > 0.0:
			_glide_t = maxf(0.0, _glide_t - delta)
			var f := 1.0 - _glide_t / GLIDE_TIME
			f = f * f * (3.0 - 2.0 * f)   # ease in and out
			_cam_x = lerpf(_glide_from.x, _camera_target_x(), f)
			_cam_y = lerpf(_glide_from.y, _camera_target_y(), f)
		elif camera_locked:
			_cam_x = lerpf(_cam_x, _camera_target_x(), clampf(delta * CAM_SPEED, 0.0, 1.0))
			_cam_y = lerpf(_cam_y, _camera_target_y(), clampf(delta * CAM_SPEED, 0.0, 1.0))
		else:
			_glide_t = 0.0   # the coach took the camera; don't resume later
			_handle_pan_keys(delta)
		_clamp_camera()
		_zoom_pulse_t = maxf(0.0, _zoom_pulse_t - delta)
		if not end_pose.is_empty():
			_end_t += delta
		for sp in sim.offense:
			_advance_anim(sp, delta)
			_advance_pops(sp, delta)
		for sp in sim.defense:
			_advance_anim(sp, delta)
			_advance_pops(sp, delta)
		# A Control only sees _gui_input while the pointer is over it, so a
		# stroke released off the edge of the window would otherwise never
		# commit.
		if _stroke_slot != "" and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_finish_stroke()
		_advance_shake(delta)
		_advance_weather(delta)
	queue_redraw()


## Drains any catches the sim has logged since the last frame and shakes the
## camera for them, then decays whatever shake is already running. A longer
## throw hits harder, up to SHAKE_FULL_YARDS.
func _advance_shake(delta: float) -> void:
	while not sim.catch_shakes.is_empty():
		var air: float = float(sim.catch_shakes.pop_front())
		var t := clampf(air / SHAKE_FULL_YARDS, 0.0, 1.0)
		# Eased so the difference between a 5 and a 15 yard grab is felt,
		# rather than everything short feeling identical.
		t = t * t * (3.0 - 2.0 * t)
		_shake_px = maxf(_shake_px, lerpf(SHAKE_MIN_PX, SHAKE_MAX_PX, t))
		_shake_left = SHAKE_TIME
		_shake_total = SHAKE_TIME

	# "Combustion"/"Aftershock" - bigger and longer than any ordinary catch.
	while not sim.big_shakes.is_empty():
		sim.big_shakes.pop_front()
		_shake_px = BIG_SHAKE_PX
		_shake_left = BIG_SHAKE_TIME
		_shake_total = BIG_SHAKE_TIME

	if _shake_left <= 0.0:
		_shake_offset = Vector2.ZERO
		_shake_px = 0.0
		return

	_shake_left = maxf(0.0, _shake_left - delta)
	_shake_phase += delta
	# Two incommensurate frequencies so it reads as a rattle rather than a
	# clean oscillation, faded out over the tail.
	var amp := _shake_px * (_shake_left / _shake_total)
	_shake_offset = Vector2(
		sin(_shake_phase * 71.0) * amp,
		cos(_shake_phase * 53.0) * amp * 0.8
	)


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
	_glide_t = 0.0
	if sim != null and camera_locked:
		_cam_x = _camera_target_x()
		_cam_y = _camera_target_y()
		_clamp_camera()


## Smoothly pans the locked camera from wherever it is now to its current
## target over GLIDE_TIME (e.g. from the catch back to the QB for the next
## snap). No effect while the camera is unlocked.
func glide_camera() -> void:
	if sim == null or not camera_locked:
		return
	_glide_from = Vector2(_cam_x, _cam_y)
	_glide_t = GLIDE_TIME


func toggle_camera_lock() -> void:
	camera_locked = not camera_locked


## Starts the end-of-match animation - see `end_pose`. Everyone stops where
## they are; the jumpers get back up first if the last play had them down.
func set_end_pose(offense_pose: String, defense_pose: String) -> void:
	end_pose = {true: offense_pose, false: defense_pose}
	_end_t = 0.0
	for group in [sim.offense, sim.defense]:
		for sp in group:
			if _pose_of(sp) == "jump":
				sp.downed = 0.0
			# A man already on the ground keeps his velocity - _fall_dir reads
			# it to know which way he went down.
			if sp.downed <= 0.0:
				sp.vel = Vector2.ZERO


func _pose_of(sp: SimPlayer) -> String:
	if sp.melted:
		return ""   # a puddle celebrates by staying a puddle
	return String(end_pose.get(sp.is_offense, ""))


## Per-player constants so a team doesn't hop or fall in lockstep.
func _pose_phase(sp: SimPlayer) -> float:
	return float(sp.get_instance_id() % 997) * 0.37


func _lie_dir(sp: SimPlayer) -> Vector2:
	return Vector2.from_angle(float(sp.get_instance_id() % 628) * 0.01)


## A quick zoom-in punch, eased back out over ZOOM_PULSE_TIME - called once
## from match.gd when a play starts (the snap) and once when it ends (phase
## goes DEAD), so those two moments read as a deliberate beat instead of the
## camera just continuing to glide.
func trigger_zoom_pulse() -> void:
	_zoom_pulse_t = ZOOM_PULSE_TIME


func _zoom_pulse() -> float:
	if _zoom_pulse_t <= 0.0:
		return 0.0
	var t := _zoom_pulse_t / ZOOM_PULSE_TIME
	return ZOOM_PULSE_AMOUNT * t * t


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
	# Base the scale/visible-yards budget on the height actually visible
	# above the bottom bar, not the whole control - otherwise the clamp in
	# _clamp_camera lets the camera sit closer to midfield than the visible
	# area can really show, cutting the far (downfield/endzone) half of the
	# screen short of the true goal line by about bottom_inset worth of yards.
	var usable_h := maxf(size.y - bottom_inset, 1.0)
	_scale = minf(size.x / YW, usable_h / MIN_VERT_YARDS) * (_zoom + _zoom_pulse())
	_visible_yards = usable_h / _scale
	_center = Vector2(size.x * 0.5, usable_h * 0.5)


## Field yards (downfield, lateral) -> screen pixels.
func to_px(p: Vector2) -> Vector2:
	return Vector2(
		_center.x + _shake_offset.x + (p.y - _cam_y) * _scale,
		_center.y + _shake_offset.y - (p.x - _cam_x) * _scale
	)


## Screen pixels -> field yards, clamped inside the playing surface so a
## stroke dragged off the edge of the window still lands on the field.
func to_yards(px: Vector2) -> Vector2:
	return Vector2(
		clampf((_center.y + _shake_offset.y - px.y) / maxf(_scale, 0.01) + _cam_x, 0.0, YD),
		clampf((px.x - _center.x - _shake_offset.x) / maxf(_scale, 0.01) + _cam_y, 0.8, YW - 0.8)
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
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and _stroke_slot != "":
			_finish_stroke()
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

		# Pressing on one of your own flex players starts a chalk stroke.
		# A press that never really moves is still just a click (see
		# _finish_stroke), so inspecting and drawing share one gesture.
		if hit != null and draw_enabled and hit.is_offense and hit.slot.begins_with("F") 				and sim.phase == MatchSim.Phase.PRESNAP:
			_begin_stroke(hit)
			return

		if hit != null:
			player_clicked.emit(hit)
		else:
			field_clicked.emit()
		return

	if event is InputEventMouseMotion and _stroke_slot != "":
		_extend_stroke(to_yards((event as InputEventMouseMotion).position))
		return

	if event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		camera_locked = false
		_cam_y -= mm.relative.x / maxf(_scale, 0.01)
		_cam_x += mm.relative.y / maxf(_scale, 0.01)
		_clamp_camera()


# ============================================================================
# Chalk strokes
# ============================================================================

func _begin_stroke(sp: SimPlayer) -> void:
	_stroke_player = sp
	_stroke_slot = sp.slot
	# Always anchored at the alignment spot rather than wherever he happens to
	# be standing mid-shift, so the stored route hangs off the same point the
	# sim will run it from.
	_stroke = [sp.target_pos]
	_stroke_len = 0.0


## RouteBook.BUDGET_YARDS, scaled up for a player with "boundless" (route
## budget quadrupled) - the only ability that touches how much chalk the
## coach gets, so this is the one place it needs to be threaded through
## rather than changing the global constant.
func _route_budget() -> float:
	if _stroke_player == null:
		return RouteBook.BUDGET_YARDS
	return RouteBook.BUDGET_YARDS * AbilityDB.route_budget_mult(_stroke_player.data.ability_id)


func _extend_stroke(point: Vector2) -> void:
	if _stroke.is_empty():
		return
	var last: Vector2 = _stroke[_stroke.size() - 1]
	var leg := last.distance_to(point)
	if leg < RouteBook.SAMPLE_MIN_YARDS:
		return
	var budget_left := _route_budget() - _stroke_len
	if budget_left <= 0.01:
		return
	# Out of chalk mid-leg: land exactly on the allowance instead of
	# overshooting it or dropping the segment entirely.
	if leg > budget_left:
		point = last + (point - last).normalized() * budget_left
		leg = budget_left
	_stroke.append(point)
	_stroke_len += leg


## Turns the raw trail into waypoints relative to the alignment spot and
## hands it off. A stroke that barely moved is treated as a click on the
## player instead, so tapping a receiver still opens his card.
func _finish_stroke() -> void:
	var sp := _stroke_player
	var points := _stroke
	var total := _stroke_len
	var budget := _route_budget()
	cancel_stroke()

	if sp == null:
		return
	if total < maxf(RouteBook.MIN_ROUTE_YARDS, DRAW_TAP_YARDS) or points.size() < 2:
		player_clicked.emit(sp)
		return

	var origin: Vector2 = points[0]
	var simplified := RouteBook.simplify(points)
	var route: Array = []
	for i in range(1, simplified.size()):
		route.append(simplified[i] - origin)
	route = RouteBook.truncate(route, budget)
	if route.is_empty():
		player_clicked.emit(sp)
		return
	route_drawn.emit(sp.slot, route)


## Wipes an in-progress stroke without committing it (e.g. the ball was
## snapped out from under the coach).
func cancel_stroke() -> void:
	_stroke_slot = ""
	_stroke_player = null
	_stroke = []
	_stroke_len = 0.0


# ============================================================================
# Drawing
# ============================================================================

func _draw() -> void:
	_recompute_transform()
	if sim == null:
		draw_rect(Rect2(Vector2.ZERO, size), UIKit.TURF)
		return
	_draw_field()
	_draw_weather_ground()
	_draw_lines_of_scrimmage()
	if show_preview and sim.phase == MatchSim.Phase.PRESNAP:
		_draw_route_preview()
		_draw_stroke()
	if sim.phase == MatchSim.Phase.LIVE or sim.phase == MatchSim.Phase.DEAD:
		_draw_trails()
	_draw_ground_props()
	_draw_chains()
	_draw_players()
	_draw_prop_overlays()
	_draw_ball()
	_draw_weather_sky()
	_draw_stat_pops()


func _visible_range() -> Vector2i:
	var half := _visible_yards * 0.5
	return Vector2i(
		int(floor(maxf(0.0, _cam_x - half - 2.0))),
		int(ceil(minf(YD, _cam_x + half + 2.0)))
	)


func _draw_field() -> void:
	# Everything outside the sidelines: grass too, just a lighter, flatter
	# green than the playing surface so the field still reads as the field.
	draw_rect(Rect2(Vector2.ZERO, size), SIDELINE_GRASS)

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


## Chalk colours. A route you drew is bright and solid; one the game filled
## in for you is dimmer and dashed, so at a glance you can see which of the
## five you actually own.
const CHALK_DRAWN := Color("f2f6ef")
const CHALK_AUTO := Color("93a89c")
const CHALK_LIVE := Color("ffe9a8")


func _draw_route_preview() -> void:
	for entry in sim.preview_routes():
		var line: PackedVector2Array = entry["line"]
		if line.size() < 2:
			continue
		var auto: bool = bool(entry.get("auto", false))
		var sp: SimPlayer = entry["player"]
		# The player currently being drawn for has his old route hidden - the
		# live stroke stands in for it.
		if sp != null and sp.slot == _stroke_slot:
			continue
		var pts := PackedVector2Array()
		for pt in line:
			pts.append(to_px(pt))
		var col := CHALK_AUTO if auto else CHALK_DRAWN
		if String(entry["kind"]) == "carry":
			col = Color("ff9f6e")
		_chalk(pts, col, 3.0, auto)
		_chalk_arrow(pts, col)
		if sp != null:
			_chalk_tag(pts[pts.size() - 1], sp.label, col)


## A chalk line: a soft wide underlay for the dust, the stroke itself, then a
## scatter of specks along it. The specks are placed from a hash of the point
## index rather than from randf, so the line does not shimmer between frames.
func _chalk(pts: PackedVector2Array, col: Color, width: float, dashed: bool = false) -> void:
	if pts.size() < 2:
		return
	if dashed:
		var on := true
		for i in range(pts.size() - 1):
			var seg_len := pts[i].distance_to(pts[i + 1])
			var step := maxf(1.0, seg_len / maxf(1.0, round(seg_len / 9.0)))
			var walked := 0.0
			while walked < seg_len:
				var a := pts[i].lerp(pts[i + 1], walked / maxf(seg_len, 0.01))
				var b := pts[i].lerp(pts[i + 1], minf(1.0, (walked + step) / maxf(seg_len, 0.01)))
				if on:
					draw_line(a, b, Color(col, 0.10), width * 2.6, true)
					draw_line(a, b, Color(col, 0.72), width, true)
				on = not on
				walked += step
		return

	draw_polyline(pts, Color(col, 0.10), width * 2.8, true)
	draw_polyline(pts, Color(col, 0.92), width, true)
	for i in pts.size():
		var h := (i * 1103515245 + 12345) & 0xFFFF
		var off := Vector2(float(h % 13) - 6.0, float((h >> 4) % 13) - 6.0) * 0.28
		draw_circle(pts[i] + off, width * 0.30, Color(col, 0.35))


func _chalk_arrow(pts: PackedVector2Array, col: Color) -> void:
	var a := pts[pts.size() - 2]
	var b := pts[pts.size() - 1]
	var dir := (b - a).normalized()
	if dir == Vector2.ZERO:
		return
	var perp := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([
		b + dir * 9.0, b - dir * 4.0 + perp * 6.0, b - dir * 4.0 - perp * 6.0
	]), Color(col, 0.92))


## The jersey number chalked at the end of a route, so five lines on the same
## side of the field are still tellable apart.
func _chalk_tag(at: Vector2, text: String, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var fs := int(maxf(11.0, _scale * 0.5))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := at + Vector2(-w * 0.5, -float(fs) * 0.75)
	draw_string(font, p + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(0, 0, 0, 0.45))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, 0.95))


## The stroke currently under the cursor, plus how much chalk is left. The
## remaining-yards readout rides the head of the line so the coach never has
## to look away from what he is drawing.
func _draw_stroke() -> void:
	if _stroke.size() < 1:
		return
	var pts := PackedVector2Array()
	for pt in _stroke:
		pts.append(to_px(pt))
	if pts.size() >= 2:
		_chalk(pts, CHALK_LIVE, 3.4)
		_chalk_arrow(pts, CHALK_LIVE)

	var head: Vector2 = pts[pts.size() - 1]
	var left := maxf(0.0, _route_budget() - _stroke_len)
	var font := ThemeDB.fallback_font
	var fs := int(maxf(12.0, _scale * 0.55))
	var text := "%d yd left" % int(round(left))
	var col := CHALK_LIVE if left > 4.0 else UIKit.BAD
	draw_string(font, head + Vector2(12.0, -10.0) + Vector2(1, 1), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.5))
	draw_string(font, head + Vector2(12.0, -10.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, 0.95))


func _draw_trails() -> void:
	for sp in sim.offense:
		if sp.trail.size() < 2:
			continue
		var pts := PackedVector2Array()
		for p in sp.trail:
			pts.append(to_px(p))
		draw_polyline(pts, Color(UIKit.OFFENSE, 0.20), 2.0, true)


# ============================================================================
# Weather
# ============================================================================

func _weather_count() -> int:
	match sim.weather:
		WeatherDB.RAINY: return RAIN_DROPS
		WeatherDB.SNOWY: return SNOW_FLAKES
		WeatherDB.WINDY: return WIND_STREAKS
	return 0


## A fresh particle for the current weather. `anywhere` scatters it across
## the whole screen (filling up when the weather first appears); otherwise
## it starts just off the edge it blows/falls in from.
func _spawn_wx(anywhere: bool) -> Dictionary:
	var w := maxf(size.x, 1.0)
	var h := maxf(size.y, 1.0)
	match sim.weather:
		WeatherDB.RAINY:
			var p := Vector2(randf_range(-80.0, w + 80.0), randf_range(0.0, h) if anywhere else randf_range(-60.0, -10.0))
			return {"p": p, "v": Vector2(-140.0, randf_range(820.0, 1000.0)), "age": 0.0,
				"life": 99.0, "size": randf_range(10.0, 18.0), "phase": 0.0}
		WeatherDB.SNOWY:
			var p2 := Vector2(randf_range(-20.0, w + 20.0), randf_range(0.0, h) if anywhere else randf_range(-30.0, -5.0))
			return {"p": p2, "v": Vector2(randf_range(-12.0, 12.0), randf_range(45.0, 105.0)), "age": 0.0,
				"life": 99.0, "size": randf_range(1.4, 3.6), "phase": randf() * TAU}
		_:
			# Wind: a streak blowing left to right across the screen.
			var p3 := Vector2(randf_range(0.0, w) if anywhere else randf_range(-240.0, -40.0), randf_range(0.0, h))
			return {"p": p3, "v": Vector2(randf_range(650.0, 1000.0), randf_range(-25.0, 25.0)), "age": 0.0,
				"life": randf_range(0.8, 1.6), "size": randf_range(60.0, 140.0), "phase": randf() * TAU}


func _advance_weather(delta: float) -> void:
	var want := _weather_count()
	var h := size.y
	var w := size.x
	var kept: Array = []
	for pt in _wx:
		pt["age"] += delta
		pt["p"] += pt["v"] * delta
		if sim.weather == WeatherDB.SNOWY:
			# Flakes drift side to side as they fall.
			pt["p"].x += sin(pt["age"] * 1.7 + pt["phase"]) * 18.0 * delta
		var p: Vector2 = pt["p"]
		if pt["age"] < pt["life"] and p.y < h + 40.0 and p.x < w + 260.0 and p.x > -300.0:
			kept.append(pt)
	# A different weather's particles don't belong any more (dev-mode switch).
	if kept.size() > want:
		kept.resize(want)
	var first_fill := kept.is_empty()
	while kept.size() < want:
		kept.append(_spawn_wx(first_fill))
	_wx = kept


## Weather that sits on the turf, under everyone: rain puddles (in field
## yards, so they scroll with the field) and snow cover.
func _draw_weather_ground() -> void:
	if sim.weather == WeatherDB.SNOWY:
		var left := to_px(Vector2(0.0, 0.0)).x
		var right := to_px(Vector2(0.0, YW)).x
		draw_rect(Rect2(Vector2(left, 0.0), Vector2(right - left, size.y)), SNOW_COVER)
	if sim.puddles.is_empty():
		return
	var t := Time.get_ticks_msec() * 0.001
	for i in sim.puddles.size():
		var pd: Dictionary = sim.puddles[i]
		var c := to_px(pd["pos"])
		var rad: float = float(pd["r"]) * _scale
		if c.y < -rad or c.y > size.y + rad:
			continue
		var stretch: float = pd["stretch"]
		draw_set_transform(c, 0.0, Vector2(1.0, stretch))
		draw_circle(Vector2.ZERO, rad, PUDDLE_FILL)
		draw_arc(Vector2.ZERO, rad, 0.0, TAU, 32, PUDDLE_RIM, 2.0, true)
		# Raindrops landing: two rings per puddle expanding out and fading,
		# staggered by index so they don't all pulse together.
		for k in 2:
			var ph := fmod(t * 0.8 + float(i) * 0.37 + float(k) * 0.5, 1.0)
			var ring := rad * (0.15 + 0.7 * ph)
			var off := Vector2(sin(float(i) * 2.3 + float(k)), cos(float(i) * 1.7 + float(k))) * rad * 0.3
			draw_arc(off, ring, 0.0, TAU, 20, Color(PUDDLE_RIM, 0.5 * (1.0 - ph)), 1.5, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Weather in the air, over everything but the stat popups.
func _draw_weather_sky() -> void:
	match sim.weather:
		WeatherDB.RAINY:
			draw_rect(Rect2(Vector2.ZERO, size), RAIN_TINT)
			for pt in _wx:
				var p: Vector2 = pt["p"]
				var dir: Vector2 = (pt["v"] as Vector2).normalized()
				draw_line(p, p - dir * float(pt["size"]), Color(0.75, 0.85, 1.0, 0.45), 1.3, true)
		WeatherDB.SNOWY:
			for pt in _wx:
				draw_circle(pt["p"], float(pt["size"]), Color(1.0, 1.0, 1.0, 0.85))
		WeatherDB.WINDY:
			for pt in _wx:
				var p2: Vector2 = pt["p"]
				var len: float = pt["size"]
				# Fades in, then out, over its life; a gentle wave along it.
				var life_t: float = float(pt["age"]) / float(pt["life"])
				var alpha := 0.32 * sin(clampf(life_t, 0.0, 1.0) * PI)
				var pts := PackedVector2Array()
				for s in 7:
					var f := float(s) / 6.0
					pts.append(p2 + Vector2(-len * f, sin(f * TAU + float(pt["phase"]) + float(pt["age"]) * 6.0) * 4.0))
				draw_polyline(pts, Color(1.0, 1.0, 1.0, alpha), 2.0, true)


## A prop sprite standing upright on the field at `at` (yards), `h` pixels
## tall, its feet at the point rather than its middle so it sits on the turf.
func _draw_prop(tex: Texture2D, at: Vector2, h: float, rot: float = 0.0,
		tint: Color = Color.WHITE) -> void:
	var ts := tex.get_size()
	var w := ts.x * h / maxf(ts.y, 1.0)
	var p := to_px(at)
	draw_circle(p + Vector2(2, 2), w * 0.36, Color(0, 0, 0, 0.18))
	draw_set_transform(p, rot, Vector2.ONE)
	draw_texture_rect(tex, Rect2(Vector2(-w * 0.5, -h * 0.85), Vector2(w, h)), false, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Banana peels, kegs, and the slot machine - everything that sits on the
## turf underneath the players.
func _draw_ground_props() -> void:
	var peel_h := PEEL_W * _scale * TEX_PEEL.get_height() / maxf(TEX_PEEL.get_width(), 1.0)
	for peel in sim.banana_peels:
		_draw_prop(TEX_PEEL, peel, peel_h)
	for keg in sim.kegs:
		_draw_prop(TEX_KEG, keg, KEG_H * _scale)
	var sm := sim.slot_machine
	if not sm.is_empty():
		var rot := 0.0
		if not sm["resolved"]:
			# Rattles while the reels spin.
			rot = sin(Time.get_ticks_msec() * 0.05) * 0.06
		elif sm["hit"]:
			var pulse := 0.1 * sin(Time.get_ticks_msec() * 0.012)
			draw_circle(to_px(sm["pos"]), SLOT_H * _scale * (0.75 + pulse),
				Color(UIKit.BALL, 0.35))
		var tint := Color.WHITE if (not sm["resolved"] or sm["hit"]) else Color(0.6, 0.6, 0.6)
		_draw_prop(TEX_SLOT, sm["pos"], SLOT_H * _scale, rot, tint)


## "Dark Chains": the chain texture tiled along the line between the two
## chained defenders' feet.
func _draw_chains() -> void:
	for c in sim.chains:
		var a := to_px((c[0] as SimPlayer).pos)
		var b := to_px((c[1] as SimPlayer).pos)
		var span := a.distance_to(b)
		if span < 1.0:
			continue
		var tex_size := TEX_CHAIN.get_size()
		var thick := maxf(6.0, CHAIN_THICK * _scale)
		var k := thick / tex_size.y
		var tile_w := tex_size.x * k
		draw_set_transform(a, (b - a).angle(), Vector2.ONE)
		var x := 0.0
		while x < span:
			var seg := minf(tile_w, span - x)
			draw_texture_rect_region(TEX_CHAIN, Rect2(Vector2(x, -thick * 0.5), Vector2(seg, thick)),
				Rect2(Vector2.ZERO, Vector2(seg / k, tex_size.y)))
			x += tile_w
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Things that play over the top of the players: the "kneecapper" muzzle
## flash and the slot machine's result.
func _draw_prop_overlays() -> void:
	if sim.phase == MatchSim.Phase.LIVE and sim.time < SHOT_FLASH_TIME:
		var fade := 1.0 - sim.time / SHOT_FLASH_TIME
		for shot in sim.shots:
			var from := to_px((shot["from"] as SimPlayer).pos)
			var to := to_px((shot["to"] as SimPlayer).pos)
			draw_line(from, to, Color(1.0, 0.92, 0.5, fade), 4.0, true)
			draw_circle(from, _player_radius() * 0.6 * fade, Color(1.0, 0.75, 0.3, fade))

	var sm := sim.slot_machine
	if sm.is_empty() or not sm["resolved"]:
		return
	var since := sim.time - MatchSim.SLOT_SPIN_TIME
	if since > JACKPOT_TEXT_TIME:
		return
	var font := ThemeDB.fallback_font
	var fs := int(maxf(16.0, _scale * (1.0 if sm["hit"] else 0.7)))
	var text := "JACKPOT!" if sm["hit"] else "BUST"
	var col := UIKit.BALL if sm["hit"] else Color(0.8, 0.8, 0.8)
	var alpha := 1.0 - clampf((since - JACKPOT_TEXT_TIME * 0.6) / (JACKPOT_TEXT_TIME * 0.4), 0.0, 1.0)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := to_px(sm["pos"]) + Vector2(-w * 0.5, -SLOT_H * _scale - since * 20.0)
	draw_string(font, at + Vector2(2, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6 * alpha))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, alpha))


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


## Base player radius in pixels. Everything about a body - sprite size, head,
## jersey number, rings - is a multiple of this, so players stay in
## proportion at every zoom level.
func _player_radius() -> float:
	return maxf(PLAYER_R_MIN, _scale * PLAYER_R)


func _draw_players() -> void:
	var font := ThemeDB.fallback_font
	var r := _player_radius()
	var fs := _num_font_size(r)

	# Downed players (and puddles) first so anyone still standing draws on
	# top of them.
	for group in [sim.defense, sim.offense]:
		for sp in group:
			if _is_flat(sp):
				_draw_person(sp, r, font, fs)
	for group2 in [sim.defense, sim.offense]:
		for sp in group2:
			if not _is_flat(sp):
				_draw_person(sp, r, font, fs)


func _is_flat(sp: SimPlayer) -> bool:
	if sp.melted or _pose_of(sp) == "lie":
		return true
	return sp.downed > 0.0 and _pose_of(sp) != "jump"


## A body seen from above: a slim upright capsule with the jersey number on it
## and a head circle at the top.
##
## Players always stand upright — they never lean into the direction they are
## running. The only thing that rotates the body is being tackled, and then it
## topples the way the player was going over FALL_TIME seconds.
func _draw_person(sp: SimPlayer, r: float, font: Font, fs: int) -> void:
	var p := to_px(sp.pos)

	# "Meltdown": nothing left of him but a puddle until the next snap.
	if sp.melted:
		_draw_puddle(sp, p, r)
		return

	var pose := _pose_of(sp)
	# Somebody the last play already put down just stays the way he fell.
	if pose == "lie" and sp.downed > 0.0:
		pose = "down"
	var fall := 0.0
	if pose == "lie":
		# Losers go down slowly and stay down, each on his own beat.
		var settle := clampf((_end_t - fmod(_pose_phase(sp), 0.4)) / LIE_DOWN_TIME, 0.0, 1.0)
		fall = settle * settle * (3.0 - 2.0 * settle)
	elif sp.downed > 0.0 and pose != "jump":
		fall = clampf(sp.downed / FALL_TIME, 0.0, 1.0)
		fall = fall * fall * (3.0 - 2.0 * fall)   # ease so he tips, then settles

	# Walk cycle: a small waddle plus a bounce, both tied to distance covered.
	var moving := clampf(sp.vel.length() / 3.0, 0.0, 1.0) * (1.0 - fall)
	if pose != "":
		moving = 0.0
	var sway := sin(sp.stride) * moving
	var bounce := absf(sin(sp.stride)) * moving
	var center := p + Vector2(sway * r * 0.11, -bounce * r * 0.07)
	# Winners hop up and down; the shadow stays on the ground and shrinks.
	var hop := 0.0
	if pose == "jump":
		hop = absf(sin(_end_t * JUMP_RATE + _pose_phase(sp))) * r * JUMP_HEIGHT
		center.y -= hop

	var body := UIKit.OFFENSE if sp.is_offense else UIKit.DEFENSE.darkened(0.08)
	var head := Color("c9a37a") if sp.is_offense else Color("a8845f")
	# The head sprite carries its own skin tone, so the per-side shade that
	# used to BE the head colour is applied to it as a modulate instead -
	# the same ratio between the two, just expressed as a tint.
	var head_tint := Color.WHITE if sp.is_offense else Color(0.84, 0.81, 0.78)
	if fall > 0.0:
		body = body.darkened(0.22 * fall)
		head = head.darkened(0.22 * fall)
		head_tint = head_tint.darkened(0.22 * fall)

	# Upright unless he is going down, in which case rotate toward the way he
	# was travelling. The body keeps its own proportions the whole time -
	# only its facing changes, so he topples over rather than stretching out.
	var axis := UP
	if fall > 0.0:
		var down_dir := _lie_dir(sp) if pose == "lie" else _fall_dir(sp)
		axis = UP.rotated(angle_difference(UP.angle(), down_dir.angle()) * fall)
	var half := r * 0.46
	var wide := r * 0.95
	var a := center - axis * half
	var b := center + axis * half

	var shadow_r := r * lerpf(0.92, 0.78, fall) * (1.0 - 0.3 * hop / maxf(r * JUMP_HEIGHT, 0.01))
	draw_circle(center + Vector2(2.0, 4.0 + hop), shadow_r, Color(0, 0, 0, 0.16))

	# Laboratory Oddities (OddityPlayerDB) always wear a bright green outline,
	# presnap included, so the coach can pick them out at a glance.
	if sp.is_offense and sp.data.quality == ShopPlayerDB.QUALITY_ODDITY and fall < 0.5:
		draw_arc(center, r * 1.22, 0, TAU, 30, OddityPlayerDB.COLOR, 3.5)

	# Aura'd defenders (see AuraDB/GameState.aura_count) get a pulsing colored
	# ring so the "colored enemy" reads at a glance on the field.
	if not sp.is_offense and sp.data.aura_id != "" and fall <= 0.0:
		var aura_col := AuraDB.aura_color(sp.data.aura_id)
		var pulse := 0.08 * sin(Time.get_ticks_msec() * 0.006)
		draw_arc(center, r * (1.32 + pulse), 0, TAU, 30, aura_col, 3.0)

	# A RB close enough to take a live handoff (see MatchSim.can_handoff_to)
	# gets his own pulsing ring so clicking him to hand it off is discoverable
	# instead of a hidden gesture.
	if sp.is_offense and fall <= 0.0 and sim.phase == MatchSim.Phase.LIVE and sim.can_handoff_to(sp):
		var pulse2 := 0.08 * sin(Time.get_ticks_msec() * 0.008)
		draw_arc(center, r * (1.32 + pulse2), 0, TAU, 30, UIKit.GOOD, 3.0)

	# A receiver whose man defender is still ignoring him (e.g. "Cloaked
	# Route") gets his own ring for as long as that lasts, so the effect
	# reads as something actually happening rather than an invisible number.
	if sp.is_offense and fall <= 0.0 and sim.phase == MatchSim.Phase.LIVE:
		var cloak_dur := AbilityDB.cloak_seconds(sp.data.ability_id)
		if cloak_dur > 0.0 and sim.time < cloak_dur:
			var pulse3 := 0.08 * sin(Time.get_ticks_msec() * 0.01)
			draw_arc(center, r * (1.32 + pulse3), 0, TAU, 30, Color("bfe9ff"), 3.0)

	# "Corruption": a cursed defender fighting for the offense's side.
	if not sp.is_offense and sp.turned and fall <= 0.0:
		var pulse4 := 0.08 * sin(Time.get_ticks_msec() * 0.012)
		draw_arc(center, r * (1.32 + pulse4), 0, TAU, 30, Color("8b3fd1"), 3.0)

	# "Kneecapper": limping at half speed.
	if not sp.is_offense and sp.slowed > 0.0 and fall <= 0.0:
		draw_arc(center, r * 1.25, 0, TAU, 30, Color(UIKit.BAD, 0.85), 3.0)
	# "Keg Stand": off drinking instead of covering anyone.
	if not sp.is_offense and sp.lured and fall <= 0.0:
		draw_arc(center, r * 1.4, 0, TAU, 30, Color("e8b04a"), 2.5)

	var facing := _facing_view(sp)
	var view_name: String = facing[0]
	var mirrored: bool = facing[1]
	var tex := _body_tex(sp.data, view_name)
	var tex_w := 0.0
	var tex_h := 0.0
	if tex == null:
		_capsule(a, b, wide + 3.0, body.darkened(0.5))
		_capsule(a, b, wide, body)
	else:
		# Team-color backdrop. Kept very faint, but it is still the only
		# per-team cue the fixed-navy jersey art gives us, so the rim stays a
		# little stronger than the fill to keep the sides apart at a glance.
		draw_circle(center, r * 1.12, Color(body, DISC_ALPHA))
		draw_arc(center, r * 1.12, 0.0, TAU, 28, Color(body, DISC_RIM_ALPHA),
			DISC_RIM_WIDTH, true)

		var tex_size := tex.get_size()
		# Equal-area normalisation - see BODY_AREA. Fitting inside a box made
		# wide sprites squat and narrow ones tall, at very different apparent
		# sizes; matching area evens them out without touching the art.
		var k := (r * BODY_AREA) / maxf(sqrt(tex_size.x * tex_size.y), 1.0)
		var w := tex_size.x * k
		var h := tex_size.y * k
		tex_w = w
		tex_h = h
		# The rig's Body scale/position (BodyArtDB.head_rig) on top of that -
		# e.g. shrinking a tall, skinny sprite to the others' height. tex_w/h
		# stay unscaled: the head is placed in the rig's own space.
		var body_rig := BodyArtDB.head_rig(view_name, sp.data.body)
		var bs: Vector2 = body_rig["body_scale"]
		var bo: Vector2 = body_rig["body_offset"]
		var body_rect := Rect2(Vector2(bo.x * w - w * bs.x * 0.5, bo.y * h - h * bs.y * 0.5),
			Vector2(w * bs.x, h * bs.y))

		draw_set_transform(center, axis.angle() - UP.angle(),
			Vector2(-1.0 if mirrored else 1.0, 1.0))
		draw_texture_rect(tex, body_rect, false)
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

	# Head: placed from this body's rig scene (BodyArtDB.head_rig - drag the
	# Head in assets/players/rigs/<view>/body_0N.tscn to move it), in the
	# body sprite's own frame, so it stays glued to the collar as he topples
	# and mirrors along with a mirrored side view. Falls back to a fixed
	# offset for the plain-capsule case, which has no jersey art to align to.
	var body_rot := axis.angle() - UP.angle()
	var hp: Vector2
	var head_h: float
	var head_rot := body_rot
	if tex != null:
		var rig := BodyArtDB.head_rig(view_name, sp.data.body)
		var off: Vector2 = rig["offset"]
		var mirror := -1.0 if mirrored else 1.0
		hp = center + Vector2(off.x * tex_w * mirror, off.y * tex_h).rotated(body_rot)
		head_h = float(rig["height"]) * tex_h
		head_rot += float(rig["rotation"]) * mirror
	else:
		hp = center + axis * r * 0.50
		head_h = r * 0.76
	head_h *= 1.0 + 0.07 * sin(sp.stride * 2.0) * moving
	var hr := head_h * 0.5
	var head_set := sp.data.head_id if sp.data.head_id != "" else "1"
	var head_view := HeadArtDB.view_for(view_name, mirrored)
	var head_tex := HeadArtDB.head_texture(head_set, head_view)
	if head_tex == null:
		draw_circle(hp, hr * 1.12, Color("241d16"))
		draw_circle(hp, hr, head)
	else:
		# The head art carries its own black outline, baked to match the
		# body's (assets/heads_outlined/_outline_heads.py). head_h is the
		# FACE's size - hair or anything else past the round face overflows
		# around it (HeadArtDB.face_draw_rect) rather than shrinking it.
		draw_set_transform(hp, head_rot, Vector2.ONE)
		draw_texture_rect(head_tex, HeadArtDB.face_draw_rect(head_set, head_view, head_tex, head_h),
			false, head_tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A melted "Meltdown" player: a flat, wobbling green-grey slick where he was
## standing, with his jersey number floating in it.
func _draw_puddle(sp: SimPlayer, p: Vector2, r: float) -> void:
	var t := Time.get_ticks_msec() * 0.003 + _pose_phase(sp)
	var pts := PackedVector2Array()
	for i in 18:
		var ang := TAU * float(i) / 18.0
		var wobble := 1.0 + 0.10 * sin(ang * 3.0 + t) + 0.06 * sin(ang * 5.0 - t * 1.3)
		pts.append(p + Vector2(cos(ang) * r * 1.35, sin(ang) * r * 0.75) * wobble)
	draw_colored_polygon(pts, Color(0.45, 0.62, 0.38, 0.85))
	pts.append(pts[0])
	draw_polyline(pts, Color(0.22, 0.34, 0.18, 0.9), 2.0, true)
	draw_circle(p + Vector2(-r * 0.3, -r * 0.15), r * 0.18, Color(1, 1, 1, 0.35))
	var font := ThemeDB.fallback_font
	var fs := _num_font_size(r)
	var tw := font.get_string_size(sp.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, p + Vector2(-tw * 0.5, float(fs) * 0.35), sp.label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.1, 0.16, 0.08, 0.7))


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
	var r := _player_radius()
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
