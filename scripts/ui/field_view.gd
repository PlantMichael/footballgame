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
## Defensive linemen (slots DL0-DL3) are drawn this much bigger - see _draw_person.
const DL_SCALE := 1.15

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
## Kick chalk, and the goalposts it's aimed at. GOALPOST_RISE is how tall
## the uprights stand on screen, in yards.
const CHALK_KICK := Color("ffd35a")
const GOALPOST := Color("f2d23c")
const GOALPOST_RISE := 3.2
## How much higher than a pass a kick goes up, on screen.
const KICK_LIFT := 5.5

var _scale: float = 20.0
var _center: Vector2 = Vector2.ZERO
var _cam_x: float = 30.0
var _cam_y: float = 0.0        # lateral camera focus, in field yards
var _zoom: float = 1.0
## Extra zoom-out while a kick is on (see _recompute_transform), eased.
var _kick_fit: float = 1.0
var _kick_fit_target: float = 1.0
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
## Likewise the scoreboard strip across the top.
var top_inset: float = 0.0

## How far past the back of either end zone the camera may go, so the end
## zone isn't jammed against the edge of the screen.
const END_OVERSCROLL := 4.0
## In the red zone the camera shows the whole end zone as long as it can
## still keep this many yards of field behind the ball.
const RED_ZONE_BEHIND := 6.0

## End-of-match celebration, set once by match.gd at the final whistle:
## is_offense (bool) -> "jump" (won - bouncing up and down), "lie" (lost -
## flat on the turf), or "" (a tie - they just stand there). Empty until then.
var end_pose: Dictionary = {}
var _end_t: float = 0.0
const JUMP_HEIGHT := 0.9      # times the player radius
const JUMP_RATE := 6.5        # radians/second of the hop cycle
const LIE_DOWN_TIME := 0.55   # seconds to settle onto the turf

## Body sprite lookups, cached so _draw doesn't hit ResourceLoader every
## frame for every player on the field. "view:body_id:head_id:jersey" -> Texture2D
## (or null if that player has no body art yet, e.g. a hand-picked QB not
## assigned one - those fall back to the old plain capsule). head_id is part
## of the key because UIKit.body_texture picks a collar-skin-tone variant
## from it for the front view - two players sharing a body id but not a head
## id must not collide on the same cached texture.
var _tex_cache: Dictionary = {}

## Per-player front of _tex_cache and BodyArtDB.head_rig, so the per-frame
## draw doesn't build a string key for every player several times a frame.
## SimPlayer -> {"body", "head", "jersey", "ability": what it was built for,
## "tex": {view: Texture2D}, "rig": {view: Dictionary}, "heads": {view:
## [Texture2D, Rect2]}, "cloak": float}. Rebuilt whenever any of the first
## four change (a sub, a dev-mode swap, a negated ability).
var _look: Dictionary = {}

## --- Floating hands ---------------------------------------------------------
## Players have no arms: a pair of outlined, skin-matched hands floats beside
## the body only while he's DOING something with them - reaching for a pass
## (receiver, and any defender contesting it), securing a catch, shoving in a
## block, throwing them up after a touchdown (with a high five from the
## nearest teammate) or at a final-whistle win. The rest of the time he has
## none, and nothing outside the match draws them at all.
## Art: assets/hands/_outline_hands.py cuts and outlines these.
const HAND_TEX := {
	"light": preload("res://assets/hands/hand_light.png"),
	"dark": preload("res://assets/hands/hand_dark.png"),
}
## The skin each hand sprite is painted in. A head's own skin
## (HeadArtDB.skin_color) picks the nearer one; anything in between - a
## stone head, a pale cursed one - is tinted down from it.
const HAND_SKIN := {"light": Color8(255, 209, 180), "dark": Color8(126, 87, 62)}
## Hand diameter as a fraction of the head's face size. _outline_hands.py
## sizes the ink line from this too.
const HAND_OF_FACE := 0.62
const HAND_MOVE_RATE := 18.0      # how fast hands chase their pose (1/s)
const HAND_POP_RATE := 9.0        # how fast they pop in / out (1/s)
const CATCH_SECURE_TIME := 0.45   # hands stay tucked on the ball after a catch
## Touchdown high five, in seconds after the play ends: the scorer and his
## nearest teammate reach, slap, and go back to hands-up.
const HF_REACH := 0.3
const HF_SLAP := 0.58
const HF_DONE := 0.95
const HIGH_FIVE_YARDS := 6.0

## SimPlayer -> {"l", "r": Vector2 hand offsets from the body centre in
## units of r, "s": 0..1 pop-in scale}. Only players with hands out.
var _hands: Dictionary = {}
var _catch_t: Dictionary = {}     # SimPlayer -> seconds since he caught it
var _block_foe: Dictionary = {}   # SimPlayer -> who he's locked up with this frame
var _hand_look: Dictionary = {}   # head set id -> [Texture2D, modulate Color]
var _hand_dt: float = 0.0
var _ball_was_in_air: bool = false
var _hand_phase: int = -1
var _dead_t: float = 0.0
var _scorer: SimPlayer = null
var _hf_partner: SimPlayer = null

## --- After the whistle -------------------------------------------------------
## Between the whistle and the next snap nobody freezes: whoever went down in
## the tackle climbs back up, a scorer's (or a pick's) teammates jog over to
## mob him, a first down gets signalled, a dropped ball gets hands on the
## head, and everyone else ambles back toward where the next play lines up.
## Purely visual - it only moves players the sim has finished with, and the
## next call (MatchSim.set_drawn_call with `walk`) walks them the rest of the
## way onto their spots from wherever they ended up.
const GETUP_TIME := 0.45
const AMBLE_SPEED := 2.4   # yd/s, walking back toward the line
const JOG_SPEED := 5.5     # yd/s, running over to celebrate
## Easing out of the play: how fast (1/s) a player's speed chases where it's
## headed after the whistle. Low enough that a sprinter coasts a few strides
## to a stop, or bends straight into his walk back, instead of braking dead.
const COAST_RATE := 1.8     # pulling up with nowhere to go
const BLEND_RATE := 2.6     # easing from a sprint into a walk or jog
const GESTURE_TIME := 1.6  # how long a signal or gesture is held
const POINT_TIME := 0.7    # the first-down point is a quick jab, not a pose
const BIG_GAIN_YARDS := 15.0   # a gain this long (short of a score) earns a fist pump
const STIFF_ARM_YARDS := 1.8   # a carrier sticks a hand out at a defender this close
const THROW_FOLLOW_TIME := 0.28  # seconds the passer's arm stays out after the release

## Dust kicked up where somebody hits the turf - {"pos": Vector2 yards,
## "age": s, "seed": float}. See _advance_dust/_draw_dust.
const DUST_LIFE := 0.55
const DUST_COLOR := Color(0.78, 0.72, 0.55)
var _dust: Array = []
var _was_down: Dictionary = {}   # SimPlayer -> true while he's on the turf
var _stomp_beat: Dictionary = {}  # SimPlayer -> last stomp landing index (for dust)

## How a receiver takes a drop - one picked at random each time. "flop" isn't
## a hand gesture: he goes down flat on his back instead (see _plan_after_play).
const DROP_REACTIONS := ["facepalm", "stomp", "flop", "weep"]
const STOMP_RATE := 13.0      # stomps land at this many half-cycles a second
const TEAR_COLOR := Color(0.62, 0.84, 1.0)
## Idle breathing and glancing about, for anyone standing still.
const BREATHE_RATE := 2.6
const GLANCE_EVERY := 3.4
const GLANCE_TIME := 0.8
const GLANCE_TILT := 0.22   # radians the head tips over at the height of a glance

## SimPlayer -> {"getup": s after the whistle he starts getting up (-1 if he
## isn't down), "walk": s he starts walking, "to": Vector2 yards or null to
## stay put, "speed": yd/s, "act": "cheer" / "point" / "head" / "", "act_at":
## s the gesture starts, "act_len": s it lasts}.
var _after: Dictionary = {}
var _after_rng := RandomNumberGenerator.new()

func _body_tex(sp: SimPlayer, view: String) -> Texture2D:
	var look := _look_of(sp)
	var texs: Dictionary = look["tex"]
	if not texs.has(view):
		var key := "%s:%s:%s:%s" % [view, sp.data.body, sp.data.head_id, look["jersey"]]
		if not _tex_cache.has(key):
			_tex_cache[key] = UIKit.body_texture(sp.data, view, look["jersey"])
		texs[view] = _tex_cache[key]
	return texs[view]


## BodyArtDB.head_rig for `sp`'s body in `view`, via _look.
func _rig(sp: SimPlayer, view: String) -> Dictionary:
	var rigs: Dictionary = _look_of(sp)["rig"]
	if not rigs.has(view):
		rigs[view] = BodyArtDB.head_rig(view, sp.data.body)
	return rigs[view]


## [HeadArtDB.head_texture, its face_draw_rect for a 1px face] for `sp` in
## `view`, via _look - the rect scales linearly with face height.
func _head_art(sp: SimPlayer, head_set: String, view: String) -> Array:
	var heads: Dictionary = _look_of(sp)["heads"]
	if not heads.has(view):
		var tex := HeadArtDB.head_texture(head_set, view)
		heads[view] = [tex, HeadArtDB.face_draw_rect(head_set, view, tex, 1.0) if tex != null else Rect2()]
	return heads[view]


func _look_of(sp: SimPlayer) -> Dictionary:
	# Your team is always blue; the opponent wears this match's colour.
	var jersey := JerseyDB.BLUE if sp.is_offense else sim.defense_jersey
	var look: Dictionary = _look.get(sp, {})
	if look.is_empty() or look["body"] != sp.data.body or look["head"] != sp.data.head_id \
			or look["jersey"] != jersey or look["ability"] != sp.ability():
		look = {"body": sp.data.body, "head": sp.data.head_id, "jersey": jersey,
			"ability": sp.ability(), "tex": {}, "rig": {}, "heads": {},
			"cloak": AbilityDB.cloak_seconds(sp.ability())}
		_look[sp] = look
	return look


## Which sprite view to show and whether to mirror it, from screen-space
## facing direction: velocity while moving, otherwise the idle stance -
## offense faces upfield (away from camera, "back"), defense faces the
## offense (toward camera, "front"), matching real presnap alignment.
## How much better (dot product with his direction, 0..1) a new facing has
## to fit before he turns to it - about 13 degrees past the 45 degree line.
const FACING_STICK := 0.16

func _facing_view(sp: SimPlayer) -> Array:
	var dir := UP if sp.is_offense else -UP
	var foe: SimPlayer = _block_foe.get(sp)
	if foe != null and foe.pos != sp.pos:
		# Locked in a block he faces his man, even while being driven
		# backward - otherwise he'd turn his back on him and shove blind.
		dir = (to_px(foe.pos) - to_px(sp.pos)).normalized()
	elif _reach_amount(sp) > 0.0 and sim.ball_from != sim.ball_to:
		# Reaching for a pass he turns to look the ball in: back along the
		# line it was thrown on, which (unlike the ball's own position)
		# doesn't swing around as it comes down on top of him.
		dir = (to_px(sim.ball_from) - to_px(sim.ball_to)).normalized()
	elif sp.vel.length() > 0.35:
		dir = Vector2(sp.vel.y, -sp.vel.x).normalized()
	elif _after_play() and _gesturing(sp) != "":
		# Reacting to the play: turned to the camera so it reads.
		dir = -UP
	elif _after_play() and not _look_of(sp).get("facing", []).is_empty():
		# Pulled up after the whistle: stay facing the way he was going
		# rather than snapping round to his presnap stance.
		return _look_of(sp)["facing"]
	# Scores for each way he could be drawn - [view, flip, how well it fits].
	var options := [["back", false, dir.dot(UP)], ["front", false, dir.dot(-UP)]]
	# A body with no side-view art (body 9 - the defensive backs' and a few
	# receivers' body) sticks to front/back rather than dropping to the plain
	# capsule whenever he runs across the field.
	if not (_body_tex(sp, "left") == null and _body_tex(sp, "front") != null):
		options.append(["left", false, dir.dot(Vector2.LEFT)])
		options.append(["left", true, dir.dot(Vector2.RIGHT)])
	var pick: Array = options[0]
	for o in options:
		if float(o[2]) > float(pick[2]):
			pick = o
	# Sticky: running on a near-45 degree line the best fit would flip between
	# front and side every other frame (his head's eyes blinking in and out),
	# so he only turns once the new facing is clearly better than his current one.
	var look := _look_of(sp)
	var prev: Array = look.get("facing", [])
	if not prev.is_empty() and (pick[0] != prev[0] or pick[1] != prev[1]):
		for o in options:
			if o[0] == prev[0] and o[1] == prev[1] and float(o[2]) >= float(pick[2]) - FACING_STICK:
				pick = o
				break
	var view: String = pick[0]
	var flip: bool = pick[1]
	look["facing"] = [view, flip]
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
		_kick_fit = lerpf(_kick_fit, _kick_fit_target, clampf(delta * 4.0, 0.0, 1.0))
		if not end_pose.is_empty():
			_end_t += delta
		for sp in sim.offense:
			_advance_anim(sp, delta)
			_advance_pops(sp, delta)
		for sp in sim.defense:
			_advance_anim(sp, delta)
			_advance_pops(sp, delta)
		_advance_hands(delta)
		_advance_dust(delta)
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


## Reads what the sim did since last frame for the hand poses: who just made
## a catch, who is locked up in a block, and - when a play ends in a
## touchdown - who celebrates and who comes over for the high five.
func _advance_hands(delta: float) -> void:
	_hand_dt = delta
	for sp in _catch_t.keys():
		_catch_t[sp] += delta
		if _catch_t[sp] > CATCH_SECURE_TIME:
			_catch_t.erase(sp)
	# The ball came down in somebody's hands (a catch, a teammate stealing
	# it, or a pick).
	if _ball_was_in_air and not sim.ball_in_air and sim.carrier != null:
		_catch_t[sim.carrier] = 0.0
	_ball_was_in_air = sim.ball_in_air

	if sim.phase != _hand_phase:
		var was := _hand_phase
		_hand_phase = sim.phase
		if sim.phase == MatchSim.Phase.DRIVE_OVER and was == MatchSim.Phase.DEAD:
			pass   # the celebration carries on under the drive-over panel
		else:
			_dead_t = 0.0
			_scorer = null
			_hf_partner = null
			_after.clear()
			if sim.phase == MatchSim.Phase.DEAD:
				_pick_celebrators()
				_plan_after_play()
			elif sim.phase == MatchSim.Phase.PRESNAP:
				_catch_t.clear()
				_hands.clear()
	_dead_t += delta
	_advance_after_play(delta)

	_block_foe.clear()
	if sim.phase == MatchSim.Phase.LIVE:
		for b in sim.offense:
			if b.engaged and b.mark != null and not b.mark.melted:
				_block_foe[b] = b.mark
				if not _block_foe.has(b.mark):
					_block_foe[b.mark] = b


func _pick_celebrators() -> void:
	if not bool(sim.result.get("td", false)) or sim.carrier == null:
		return
	_scorer = sim.carrier
	var team: Array = sim.offense if _scorer.is_offense else sim.defense
	var best := HIGH_FIVE_YARDS
	for sp in team:
		if sp == _scorer or sp.melted or sp.downed > 0.0:
			continue
		var d: float = sp.pos.distance_to(_scorer.pos)
		if d < best:
			best = d
			_hf_partner = sp


## True from the whistle until the next play is called (including the
## drive-over panel after a score or turnover).
func _after_play() -> bool:
	return sim.phase == MatchSim.Phase.DEAD or sim.phase == MatchSim.Phase.DRIVE_OVER


## Decides, once at the whistle, what everyone does until the next snap -
## see `_after`.
func _plan_after_play() -> void:
	_after_rng.randomize()
	var res := sim.result
	var kind := String(res.get("kind", ""))
	var yards := float(res.get("yards", 0.0))
	var td := bool(res.get("td", false))
	var turnover := bool(res.get("turnover", false))
	# The play's hero: the scorer, or the man who picked it off. His
	# teammates run over to mob him; the other side just stands there.
	var hero: SimPlayer = _scorer
	if hero == null and kind == "interception":
		hero = sim.interceptor
	if hero == null and kind == "field_goal":
		hero = sim.kicker_sp   # it's good - the kicker gets mobbed
	# Otherwise everyone heads for where the next snap will be, if there is
	# one on this drive.
	var shift := 0.0
	var go_home := hero == null and not td and not turnover
	if go_home:
		var next_los := clampf(sim.los + yards, MatchSim.OWN_GOAL + 1.0, MatchSim.GOAL_LINE - 0.5)
		shift = next_los - sim.los

	for sp in sim.offense + sim.defense:
		if sp.melted:
			continue
		var a := {"getup": -1.0, "walk": 0.15 + _after_rng.randf() * 0.5, "to": null,
			"speed": AMBLE_SPEED, "act": "", "act_at": 0.0, "act_len": GESTURE_TIME}
		var ready := 0.2
		if sp.downed > 0.0:
			a["getup"] = 0.9 + _after_rng.randf() * 0.7
			ready = float(a["getup"]) + GETUP_TIME + 0.1
			a["walk"] = ready + 0.2 + _after_rng.randf() * 0.5
		if hero != null:
			if sp == hero:
				if sp != _scorer:   # the scorer's cheer is the TD block's
					a["act"] = "cheer"
					a["act_at"] = ready
					a["act_len"] = 99.0
			elif sp.is_offense == hero.is_offense:
				var away := sp.pos - hero.pos
				if away.length() < 0.1:
					away = Vector2.from_angle(_after_rng.randf() * TAU)
				var ring := 1.4 if sp == _hf_partner else 1.8 + _after_rng.randf() * 1.4
				a["to"] = hero.pos + away.normalized() * ring
				a["speed"] = JOG_SPEED
				a["walk"] = maxf(ready, 0.1 + _after_rng.randf() * 0.4)
				if sp != _hf_partner:
					var run_time := maxf(0.0, away.length() - ring) / JOG_SPEED
					a["act"] = "cheer"
					a["act_at"] = float(a["walk"]) + run_time + 0.1
					a["act_len"] = 99.0
		elif go_home:
			a["to"] = sp.target_pos + Vector2(shift, 0.0)
		_after[sp] = a

	var qb := sim.offense_slot("QB")
	if kind == "interception" and qb != null and _after.has(qb):
		_gesture(qb, "facepalm")
	# Whoever was nearest the scorer and couldn't stop him.
	if td and _scorer != null:
		var beaten := _nearest_of(sim.defense if _scorer.is_offense else sim.offense, _scorer.pos, 4.0)
		if beaten != null and _after.has(beaten):
			_gesture(beaten, "head")
	if hero != null:
		return
	# Somebody always has something to say about how the play went.
	var carrier: SimPlayer = sim.carrier
	if kind == "incomplete" and sim.thrown_to != null and _after.has(sim.thrown_to):
		var dropped := bool(res.get("drop", false))
		# A drop is on him; a bad ball is on the QB, who shrugs it off.
		if dropped:
			_react_to_drop(sim.thrown_to)
		else:
			_gesture(sim.thrown_to, "head")
		if not dropped and qb != null and qb != sim.thrown_to and _after.has(qb):
			_gesture(qb, "shrug")
		var cover := _nearest_of(sim.defense, sim.thrown_to.pos, 3.0)
		if cover != null and _after.has(cover):
			_gesture(cover, "wave_off")   # "no catch!"
	if kind == "sack" and qb != null and _after.has(qb):
		_gesture(qb, "head")
	if kind == "missed_fg" and sim.kicker_sp != null and _after.has(sim.kicker_sp):
		_gesture(sim.kicker_sp, "head")
	if carrier != null and _after.has(carrier) and (kind == "run" or kind == "complete") \
			and yards >= BIG_GAIN_YARDS:
		_gesture(carrier, "pump")
	elif carrier != null and _after.has(carrier) and (kind == "run" or kind == "complete") \
			and yards >= sim.to_go:
		_gesture(carrier, "point", POINT_TIME)   # moving the chains
	var stop := kind == "sack" or kind == "safety" or yards < 0.0
	if sim.tackler != null and _after.has(sim.tackler) and stop:
		_gesture(sim.tackler, "cheer")


## A receiver who just dropped one: facepalm, stomp, flop onto his back, or
## weep into his hands.
func _react_to_drop(sp: SimPlayer) -> void:
	var how: String = DROP_REACTIONS[_after_rng.randi_range(0, DROP_REACTIONS.size() - 1)]
	if how != "flop" or sp.downed > 0.0:
		_gesture(sp, how if how != "flop" else "facepalm")
		return
	# Throws himself down backwards and lies there a beat before getting up.
	var a: Dictionary = _after[sp]
	var back := -sp.vel.normalized() if sp.vel.length() > 0.1 else Vector2(-1.0, 0.0)
	sp.vel = back * 0.6
	sp.downed = 0.0001
	a["getup"] = 1.7 + _after_rng.randf() * 0.6
	a["walk"] = float(a["getup"]) + GETUP_TIME + 0.3


## The closest live player in `group` to `at`, within `max_yards`, or null.
func _nearest_of(group: Array, at: Vector2, max_yards: float) -> SimPlayer:
	var best: SimPlayer = null
	var best_d := max_yards
	for sp in group:
		if sp.melted:
			continue
		var d: float = sp.pos.distance_to(at)
		if d < best_d:
			best_d = d
			best = sp
	return best


## Queues `act` for him as soon as he's on his feet, and holds his walk
## until he's done.
func _gesture(sp: SimPlayer, act: String, length: float = GESTURE_TIME) -> void:
	var a: Dictionary = _after[sp]
	var at := 0.25
	if float(a["getup"]) >= 0.0:
		at = float(a["getup"]) + GETUP_TIME + 0.1
	a["act"] = act
	a["act_at"] = at
	a["act_len"] = length
	a["walk"] = maxf(float(a["walk"]), at + length)


## Seconds since his current gesture started.
func _gesture_t(sp: SimPlayer) -> float:
	var a: Dictionary = _after.get(sp, {})
	return 0.0 if a.is_empty() else _dead_t - float(a["act_at"])


func _gesturing(sp: SimPlayer) -> String:
	var a: Dictionary = _after.get(sp, {})
	if a.is_empty() or String(a["act"]) == "":
		return ""
	var since := _dead_t - float(a["act_at"])
	return String(a["act"]) if since >= 0.0 and since < float(a["act_len"]) else ""


## 0 while he's still down, easing to 1 as he gets back up.
func _getup(sp: SimPlayer) -> float:
	if not end_pose.is_empty():
		return 0.0
	var a: Dictionary = _after.get(sp, {})
	if a.is_empty() or float(a["getup"]) < 0.0:
		return 0.0
	var f := clampf((_dead_t - float(a["getup"])) / GETUP_TIME, 0.0, 1.0)
	return f * f * (3.0 - 2.0 * f)


## Moves everyone through their after-play plan: the downed get up, then
## each walks (or jogs) to his spot once his start time comes round.
func _advance_after_play(delta: float) -> void:
	if _after.is_empty() or not end_pose.is_empty():
		return
	for sp in _after:
		var a: Dictionary = _after[sp]
		if sp.downed > 0.0:
			if float(a["getup"]) >= 0.0 and _dead_t >= float(a["getup"]) + GETUP_TIME:
				sp.downed = 0.0
				sp.vel = Vector2.ZERO
			continue   # still down - and his velocity says which way he fell
		var target: Variant = a["to"]
		var want := Vector2.ZERO
		if target != null and _dead_t >= float(a["walk"]) and _gesturing(sp) == "":
			var to: Vector2 = (target as Vector2) - sp.pos
			var dist := to.length()
			if dist > 0.1:
				want = to / dist * minf(float(a["speed"]), dist * 3.0)
		# Anyone still running at the whistle pulls up over a few strides
		# rather than stopping dead.
		sp.vel = sp.vel.lerp(want, clampf(delta * (BLEND_RATE if want != Vector2.ZERO else COAST_RATE), 0.0, 1.0))
		if sp.vel.length() < 0.05:
			sp.vel = Vector2.ZERO
		sp.pos += sp.vel * delta
		sp.stride += sp.vel.length() * delta * 3.2


## A puff of dust the moment anyone hits the turf.
func _advance_dust(delta: float) -> void:
	for group in [sim.offense, sim.defense]:
		for sp in group:
			var down: bool = sp.downed > 0.0 and not sp.melted
			if down and not _was_down.has(sp):
				_was_down[sp] = true
				# Kicked up a little way along the way he fell.
				var spot: Vector2 = sp.pos
				if sp.vel.length() > 0.1:
					spot += sp.vel.normalized() * 0.4
				_dust.append({"pos": spot, "age": 0.0, "seed": randf() * TAU})
			elif not down:
				_was_down.erase(sp)
			# A stomp kicks up a little dust every time his foot comes down.
			if _after_play() and _gesturing(sp) == "stomp":
				var beat := int(floor(_gesture_t(sp) * STOMP_RATE / PI))
				if beat != int(_stomp_beat.get(sp, -1)):
					_stomp_beat[sp] = beat
					_dust.append({"pos": sp.pos + Vector2(-0.3, 0.0), "age": DUST_LIFE * 0.35, "seed": randf() * TAU})
	if _dust.is_empty():
		return
	var kept: Array = []
	for d in _dust:
		d["age"] += delta
		if float(d["age"]) < DUST_LIFE:
			kept.append(d)
	_dust = kept


func _draw_dust() -> void:
	if _dust.is_empty():
		return
	var r := _player_radius()
	for d in _dust:
		var f: float = float(d["age"]) / DUST_LIFE
		var c := to_px(d["pos"])
		var seed_a: float = d["seed"]
		# Five little clouds billowing outward and fading.
		for i in 5:
			var ang := seed_a + TAU * float(i) / 5.0
			var at := c + Vector2(cos(ang), sin(ang) * 0.6) * r * (0.35 + 0.9 * f)
			_draw_disc(at, r * (0.28 + 0.25 * f), Color(DUST_COLOR, 0.6 * (1.0 - f)))


## Where the two high-fivers' hands meet: above and between their heads.
func _high_five_point(r: float) -> Vector2:
	return (to_px(_scorer.pos) + to_px(_hf_partner.pos)) * 0.5 + Vector2(0.0, -r * 1.25)


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
## start of a new drive). Without `relock` it has no effect while the camera
## is unlocked - free camera position is left exactly where the player put it.
func snap_camera(relock: bool = false) -> void:
	_glide_t = 0.0
	# A new drive always starts with the camera back on the ball, even if the
	# coach had panned it off somewhere during the last one.
	if relock:
		camera_locked = true
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
	# Lining up a kick: as much of the way to the uprights as fits, with the
	# kicker still on screen at the bottom.
	if sim.kick_mode and sim.phase == MatchSim.Phase.PRESNAP:
		var spot := sim.kick_spot().x
		return minf((spot + MatchSim.POSTS_X) * 0.5, spot - 4.0 + _visible_yards * 0.5)
	var ball := sim.los
	var focus := sim.los + CAM_LEAD
	if sim.phase == MatchSim.Phase.LIVE or sim.phase == MatchSim.Phase.DEAD:
		ball = sim.ball_pos.x
		focus = sim.ball_pos.x + CAM_LEAD * 0.5
	# In the red zone, pull up far enough to show the whole end zone (and a
	# little grass past it) as long as that still keeps some field in view
	# behind the ball.
	var half := _visible_yards * 0.5
	var whole_ez := YD + END_OVERSCROLL - half
	if whole_ez - half <= ball - RED_ZONE_BEHIND:
		focus = maxf(focus, whole_ez)
	return focus


func _camera_target_y() -> float:
	if sim.phase == MatchSim.Phase.LIVE or sim.phase == MatchSim.Phase.DEAD:
		return sim.ball_pos.y
	return YW * 0.5


## Keeps the camera focus from showing past the sidelines/end zones, however
## it got there (auto-follow, WASD, or drag).
func _clamp_camera() -> void:
	var half_y := _visible_yards * 0.5
	_cam_x = clampf(_cam_x, half_y - END_OVERSCROLL, YD + END_OVERSCROLL - half_y)
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
	# Same for the scoreboard strip across the top: the far end zone used to
	# sit underneath it whenever the camera was clamped at the back line.
	var usable_h := maxf(size.y - bottom_inset - top_inset, 1.0)
	_scale = minf(size.x / YW, usable_h / MIN_VERT_YARDS) * (_zoom + _zoom_pulse())
	# A kick zooms out (never in) far enough to show the kicker and the
	# uprights together, then eases back once the next play is called.
	_kick_fit_target = 1.0
	if sim != null and (sim.kick_mode or sim.kick_play):
		var need := (MatchSim.POSTS_X + GOALPOST_RISE + 4.0) - (sim.kick_spot().x - 5.0)
		_kick_fit_target = minf(1.0, (usable_h / _scale) / need)
	_scale *= _kick_fit
	_visible_yards = usable_h / _scale
	_center = Vector2(size.x * 0.5, top_inset + usable_h * 0.5)


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
		# (While the kick unit is out, only the kicker draws - his kick.)
		var drawable := hit != null and hit.is_offense and ((hit.slot.begins_with("F") and not sim.kick_mode) \
			or (sim.kick_mode and hit == sim.kicker_sp))
		if drawable and draw_enabled and sim.phase == MatchSim.Phase.PRESNAP:
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
	# sim will run it from. A kick hangs off the spot the ball is held at.
	_stroke = [sim.kick_spot() if sp == sim.kicker_sp else sp.target_pos]
	_stroke_len = 0.0


## RouteBook.BUDGET_YARDS, scaled up for a player with "boundless" (route
## budget quadrupled) - the only ability that touches how much chalk the
## coach gets, so this is the one place it needs to be threaded through
## rather than changing the global constant.
func _route_budget() -> float:
	if _stroke_player == null:
		return RouteBook.BUDGET_YARDS
	if _stroke_player == sim.kicker_sp:
		return sim.kick_range()   # a kicker's chalk is his leg
	return RouteBook.BUDGET_YARDS * AbilityDB.route_budget_mult(_stroke_player.ability())


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
		if sim.kick_mode:
			_draw_kick_preview()
		else:
			_draw_route_preview()
		_draw_stroke()
	if sim.phase == MatchSim.Phase.LIVE or sim.phase == MatchSim.Phase.DEAD:
		_draw_trails()
	_draw_ground_props()
	_draw_dust()
	_draw_chains()
	_draw_players()
	_draw_prop_overlays()
	_draw_goalposts()
	_draw_ball()
	_draw_weather_sky()
	_draw_stat_pops()
	if sim.kick_mode or sim.kick_play:
		_draw_wind()


func _visible_range() -> Vector2i:
	var half := _visible_yards * 0.5
	# _visible_yards only spans the view above the bottom bar, but the bar
	# floats with field showing around and under it - draw that strip too, or
	# it shows through as bare sideline grass.
	var below := bottom_inset / maxf(_scale, 0.01)
	var above := top_inset / maxf(_scale, 0.01)
	return Vector2i(
		int(floor(maxf(0.0, _cam_x - half - below - 2.0))),
		int(ceil(minf(YD, _cam_x + half + above + 2.0)))
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


## The chalked kick (or the straight default if nothing's drawn yet), from
## the spot the ball is held at.
func _draw_kick_preview() -> void:
	if _stroke_slot == GameState.KICKER_SLOT:
		return   # the live stroke stands in for it
	var line := sim.kick_line()
	var pts := PackedVector2Array()
	for pt in line:
		pts.append(to_px(pt))
	var auto := sim.kick_route.is_empty()
	_chalk(pts, CHALK_KICK, 3.0, auto)
	_chalk_arrow(pts, CHALK_KICK)
	_chalk_tag(pts[pts.size() - 1], "K", CHALK_KICK)


## Goalposts on the back line of each end zone: the crossbar across the
## field and the two uprights standing up off it (up the screen, as if seen
## from a little behind), in goalpost yellow with a dark edge.
func _draw_goalposts() -> void:
	var half := MatchSim.POST_HALF
	var cy := YW * 0.5
	var rise := _scale * GOALPOST_RISE
	var w := maxf(3.0, _scale * 0.18)
	for x in [0.0, YD]:
		var a := to_px(Vector2(x, cy - half))
		var b := to_px(Vector2(x, cy + half))
		if a.y < -rise - 20.0 or a.y > size.y + 20.0:
			continue
		var stem := to_px(Vector2(x, cy))
		var base := stem + Vector2(0.0, _scale * (0.9 if x > 0.0 else -0.9))
		for pass_i in 2:
			var col := Color(0.12, 0.10, 0.02, 0.9) if pass_i == 0 else GOALPOST
			var ww := w + (3.0 if pass_i == 0 else 0.0)
			draw_line(base, stem, col, ww)
			draw_line(a, b, col, ww)
			draw_line(a, a - Vector2(0.0, rise), col, ww)
			draw_line(b, b - Vector2(0.0, rise), col, ww)


## Wind for the kick, top-left of the field: an arrow the way it blows (on
## screen) and its speed.
func _draw_wind() -> void:
	var c := Vector2(62.0, top_inset + 66.0)
	var rad := 40.0
	draw_circle(c, rad + 6.0, Color(0.04, 0.07, 0.06, 0.78))
	draw_arc(c, rad + 6.0, 0.0, TAU, 40, Color(UIKit.ACCENT, 0.7), 2.0, true)
	var font := ThemeDB.fallback_font
	var mph := sim.wind_mph()
	# Field (downfield, across) -> screen (right, down).
	var dir := Vector2(sim.wind.y, -sim.wind.x)
	if dir.length() > 0.01:
		dir = dir.normalized()
		var sway := sin(Time.get_ticks_msec() * 0.004) * 0.06
		dir = dir.rotated(sway)
		var tip := c + dir * rad * 0.78
		var tail := c - dir * rad * 0.78
		var side := Vector2(-dir.y, dir.x)
		draw_line(tail, tip - dir * 8.0, Color(0, 0, 0, 0.6), 7.0, true)
		draw_line(tail, tip - dir * 8.0, UIKit.CHALK, 4.0, true)
		draw_colored_polygon(PackedVector2Array([tip, tip - dir * 15.0 + side * 9.0,
			tip - dir * 15.0 - side * 9.0]), UIKit.CHALK)
	var text := "%d mph" % int(round(mph))
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string_outline(font, c + Vector2(-tw * 0.5, rad + 26.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
		4, Color(0, 0, 0, 0.8))
	draw_string(font, c + Vector2(-tw * 0.5, rad + 26.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UIKit.CHALK)
	var lbl := "WIND"
	var lw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(font, c + Vector2(-lw * 0.5, -rad - 12.0), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.ACCENT)


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
	return int(maxf(8.0, r * 0.52))


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
	_draw_high_five_slap(r)


## A quick burst where the high-fivers' palms meet.
func _draw_high_five_slap(r: float) -> void:
	if _hf_partner == null or not _after_play():
		return
	var since := _dead_t - HF_SLAP
	if since < 0.0 or since > 0.3:
		return
	var f := since / 0.3
	var at := _high_five_point(r)
	var col := Color(1.0, 0.97, 0.8, 1.0 - f)
	for i in 8:
		var dir := Vector2.from_angle(TAU * float(i) / 8.0 + 0.2)
		draw_line(at + dir * r * (0.3 + 0.5 * f), at + dir * r * (0.55 + 0.7 * f), col, 2.5, true)


func _is_flat(sp: SimPlayer) -> bool:
	if sp.melted or _pose_of(sp) == "lie":
		return true
	return sp.downed > 0.0 and _pose_of(sp) != "jump" and _getup(sp) < 0.5


## A body seen from above: a slim upright capsule with the jersey number on it
## and a head circle at the top.
##
## Players always stand upright — they never lean into the direction they are
## running. The only thing that rotates the body is being tackled, and then it
## topples the way the player was going over FALL_TIME seconds.
func _draw_person(sp: SimPlayer, r: float, font: Font, fs: int) -> void:
	var p := to_px(sp.pos)
	# The defensive front four are drawn a size up, so the trenches read as
	# big bodies. Purely visual - reach, tackles and clicks are all in yards.
	if not sp.is_offense and sp.slot.begins_with("DL"):
		r *= DL_SCALE
		fs = _num_font_size(r)

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
		fall *= 1.0 - _getup(sp)   # ...and back up again after the whistle

	# Walk cycle: a small waddle plus a bounce, both tied to distance covered.
	var moving := clampf(sp.vel.length() / 3.0, 0.0, 1.0) * (1.0 - fall)
	if pose != "":
		moving = 0.0
	var sway := sin(sp.stride) * moving
	var bounce := absf(sin(sp.stride)) * moving
	var center := p + Vector2(sway * r * 0.11, -bounce * r * 0.07)
	# Idle: standing still he breathes - a slow rise and fall, the head
	# lagging the shoulders a touch - so a stopped player never looks frozen.
	var idle := moving < 0.05 and fall <= 0.0 and pose == ""
	var breath := 0.0
	if idle:
		breath = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * BREATHE_RATE + _pose_phase(sp))
		center.y -= breath * r * 0.05
	# Winners hop up and down; the shadow stays on the ground and shrinks.
	var hop := 0.0
	if pose == "jump":
		hop = absf(sin(_end_t * JUMP_RATE + _pose_phase(sp))) * r * JUMP_HEIGHT
		center.y -= hop
	elif _after_play() and _gesturing(sp) == "stomp":
		# Stamping his feet after a drop - little hops, dust on each landing.
		hop = absf(sin(_gesture_t(sp) * STOMP_RATE)) * r * 0.16
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
	_draw_disc(center + Vector2(2.0, 4.0 + hop), shadow_r, Color(0, 0, 0, 0.16))

	# A bowl special player (BowlDB.GIMMICKS) - a heavy purple double ring,
	# so he can't be mistaken for a purple Mind Reader aura's single one.
	if not sp.is_offense and sp.data.gimmick_id != "" and fall <= 0.0:
		var pulse5 := 0.06 * sin(Time.get_ticks_msec() * 0.005)
		draw_arc(center, r * (1.30 + pulse5), 0, TAU, 32, BowlDB.GIMMICK_COLOR, 4.0)
		draw_arc(center, r * (1.52 + pulse5), 0, TAU, 32, Color(BowlDB.GIMMICK_COLOR, 0.55), 2.0)

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
		var cloak_dur: float = _look_of(sp)["cloak"]
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
	var tex := _body_tex(sp, view_name)
	var tex_w := 0.0
	var tex_h := 0.0
	if tex == null:
		_capsule(a, b, wide + 3.0, body.darkened(0.5))
		_capsule(a, b, wide, body)
	else:
		# Team-color backdrop. Kept very faint, but it is still the only
		# per-team cue the fixed-navy jersey art gives us, so the rim stays a
		# little stronger than the fill to keep the sides apart at a glance.
		_draw_disc(center, r * 1.12, Color(body, DISC_ALPHA))
		_draw_ring(center, r * 1.12, Color(body, DISC_RIM_ALPHA))

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
		var body_rig := _rig(sp, view_name)
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

	# Jersey number, printed high on the chest just below the head, in light
	# text with a black outline so it reads on any jersey colour. Only the
	# plain-capsule fallback still needs the per-team dark/light split tuned
	# for its gold/blue fill.
	if fall < 0.6:
		var text := sp.label
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var np := center - axis * r * 0.12
		var num_color := Color(0.92, 0.95, 1.0, 1.0 - fall)
		if tex == null:
			num_color = Color(0.16, 0.12, 0.04, 1.0 - fall) if sp.is_offense \
				else Color(0.88, 0.95, 1.0, 1.0 - fall)
		var at := np + Vector2(-tw * 0.5, float(fs) * 0.35)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			maxi(3, int(round(float(fs) * 0.28))), Color(0.03, 0.03, 0.04, 1.0 - fall))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, num_color)

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
		var rig := _rig(sp, view_name)
		var off: Vector2 = rig["offset"]
		var mirror := -1.0 if mirrored else 1.0
		hp = center + Vector2(off.x * tex_w * mirror, off.y * tex_h).rotated(body_rot)
		head_h = float(rig["height"]) * tex_h
		head_rot += float(rig["rotation"]) * mirror
	else:
		hp = center + axis * r * 0.50
		head_h = r * 0.76
	head_h *= 1.0 + 0.07 * sin(sp.stride * 2.0) * moving
	if idle:
		hp.y -= (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * BREATHE_RATE + _pose_phase(sp) - 0.6)) 			* r * 0.025
	var gesture := _gesturing(sp) if _after_play() else ""
	if gesture == "facepalm":
		hp.x += sin(_gesture_t(sp) * 9.0) * r * 0.06
	elif gesture == "weep":
		hp.y += r * 0.08   # head hung
	var hr := head_h * 0.5
	var head_set := sp.data.head_id if sp.data.head_id != "" else "1"
	var head_view := HeadArtDB.view_for(view_name, mirrored)
	# Standing around after the whistle, he glances off to one side now and
	# then, each man on his own clock - a tilt of the head, not a swap to the
	# side-view head art, which on a front or back body just reads as a
	# missing eye.
	if idle and _after_play() and (head_view == "front" or head_view == "back"):
		var glance := fmod(_dead_t + _pose_phase(sp), GLANCE_EVERY)
		if glance < GLANCE_TIME:
			var side := 1.0 if int(_pose_phase(sp) * 10.0) % 2 == 0 else -1.0
			head_rot += side * GLANCE_TILT * sin(glance / GLANCE_TIME * PI)
	var head_art := _head_art(sp, head_set, head_view)
	var head_tex: Texture2D = head_art[0]
	if head_tex == null:
		draw_circle(hp, hr * 1.12, Color("241d16"))
		draw_circle(hp, hr, head)
	else:
		# The head art carries its own black outline, baked to match the
		# body's (assets/heads_outlined/_outline_heads.py). head_h is the
		# FACE's size - hair or anything else past the round face overflows
		# around it (HeadArtDB.face_draw_rect) rather than shrinking it.
		draw_set_transform(hp, head_rot, Vector2.ONE)
		var unit: Rect2 = head_art[1]
		draw_texture_rect(head_tex, Rect2(unit.position * head_h, unit.size * head_h), false, head_tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_draw_hands(sp, center, hp, head_h, r, pose, fall, head_tint)

	# Weeping into his hands: tears dripping out from between the fingers.
	if gesture == "weep":
		for i in 4:
			var ph := fmod(_gesture_t(sp) * 1.6 + float(i) * 0.25, 1.0)
			var side := -1.0 if i % 2 == 0 else 1.0
			var at := hp + Vector2(side * r * (0.32 + 0.1 * ph), r * (0.2 + 0.7 * ph))
			_draw_disc(at, r * 0.08 * (1.0 - 0.4 * ph), Color(TEAR_COLOR, 0.9 * (1.0 - ph)))


## The floating hands, if he's doing anything with them right now - see
## HAND_TEX. They chase their pose rather than snapping to it, and pop in
## and out by scale instead of appearing from nowhere.
func _draw_hands(sp: SimPlayer, center: Vector2, hp: Vector2, head_h: float, r: float,
		pose: String, fall: float, tint: Color) -> void:
	var hand_d := head_h * HAND_OF_FACE
	var targets: Array = [] if fall > 0.0 else _hand_targets(sp, center, hp, r, hand_d, pose)
	# Hands never cover his own face: any pose that would put one over the
	# head slides it out to just past the head's edge.
	var clear := head_h * 0.5 + hand_d * 0.45
	# ...except the facepalm's right hand, which is the whole point.
	var guarded := targets.size()
	match _gesturing(sp):
		"facepalm": guarded = 1
		"weep": guarded = 0
	for i in guarded:
		var off: Vector2 = targets[i] - hp
		if off.length() < clear:
			var out := off.normalized() if off.length() > 0.01 else Vector2(-1.0 if i == 0 else 1.0, 0.0)
			targets[i] = hp + out * clear
	var on := not targets.is_empty()
	var st: Dictionary = _hands.get(sp, {})
	if st.is_empty():
		if not on:
			return
		st = {"l": Vector2.ZERO, "r": Vector2.ZERO, "s": 0.0}
	if on:
		var tl: Vector2 = (targets[0] - center) / r
		var tr: Vector2 = (targets[1] - center) / r
		if st["s"] <= 0.01:
			# Popping in: appear where they belong, don't fly in from elsewhere.
			st["l"] = tl
			st["r"] = tr
		else:
			var k := 1.0 - exp(-_hand_dt * HAND_MOVE_RATE)
			st["l"] = (st["l"] as Vector2).lerp(tl, k)
			st["r"] = (st["r"] as Vector2).lerp(tr, k)
	st["s"] = move_toward(float(st["s"]), 1.0 if on else 0.0, _hand_dt * HAND_POP_RATE)
	if st["s"] <= 0.0:
		_hands.erase(sp)
		return
	_hands[sp] = st

	var look := _hand_style(sp)
	# A little overshoot on the way in, so they pop rather than fade.
	var s: float = st["s"]
	var d := hand_d * (s + 0.25 * sin(s * PI)) if on else hand_d * s
	for key in ["l", "r"]:
		var p: Vector2 = center + (st[key] as Vector2) * r
		draw_texture_rect(look[0], Rect2(p - Vector2(d, d) * 0.5, Vector2(d, d)), false,
			(look[1] as Color) * tint)


## Screen positions for [left hand, right hand] this frame, or [] for no
## hands. First match wins.
func _hand_targets(sp: SimPlayer, center: Vector2, hp: Vector2, r: float, hand_d: float,
		pose: String) -> Array:
	if sp.melted:
		return []

	# Winning at the final whistle: both hands up, hopping with him.
	if pose == "jump":
		return _hands_up(hp, r, _end_t * JUMP_RATE + _pose_phase(sp))

	# Touchdown: the scorer throws his hands up, and his nearest teammate
	# comes in for a high five before joining him.
	if _after_play() and _scorer != null and (sp == _scorer or sp == _hf_partner):
		var cheer := _hands_up(hp, r, _dead_t * 9.0 + _pose_phase(sp))
		if _hf_partner == null or _dead_t < HF_REACH or _dead_t > HF_DONE:
			return cheer
		var other: SimPlayer = _hf_partner if sp == _scorer else _scorer
		var mine := to_px(sp.pos)
		var theirs := to_px(other.pos)
		var near := 1 if theirs.x >= mine.x else 0
		var k := smoothstep(HF_REACH, HF_SLAP, _dead_t) if _dead_t < HF_SLAP \
			else 1.0 - smoothstep(HF_SLAP + 0.07, HF_DONE, _dead_t)
		# Stop a hand's radius short of the meeting point, so the two palms
		# touch instead of stacking.
		var away := (mine - theirs).normalized() if mine != theirs else Vector2.LEFT
		var palm := _high_five_point(r) + away * hand_d * 0.45
		cheer[near] = (cheer[near] as Vector2).lerp(palm, k)
		return cheer

	# After-the-whistle gestures (see _plan_after_play).
	if _after_play():
		match _gesturing(sp):
			"cheer":
				return _hands_up(hp, r, _dead_t * 9.0 + _pose_phase(sp))
			"point":
				# Moving the chains: a quick one-handed point downfield (up the
				# screen) at shoulder height - out in front of him, not raised
				# over his head - with the other hand down at his side.
				var jab := absf(sin(_dead_t * 9.0)) * r * 0.12
				return [center + Vector2(-r * 0.55, r * 0.1),
					hp + Vector2(r * 0.55, -r * 0.2 - jab)]
			"head":
				# Hands on his helmet after the drop - the face guard in
				# _draw_hands keeps them to the sides of it.
				var shake := sin(_dead_t * 10.0) * r * 0.03
				return [hp + Vector2(-r * 0.3, -r * 0.2 + shake), hp + Vector2(r * 0.3, -r * 0.2 - shake)]
			"facepalm":
				# One hand slapped flat over his face, the other hanging
				# limp; the head shakes under it (see _draw_person).
				return [center + Vector2(-r * 0.6, r * 0.25), hp + Vector2(r * 0.05, r * 0.05)]
			"weep":
				# Face buried in both hands, shoulders heaving.
				var sob := sin(_gesture_t(sp) * 7.0) * r * 0.03
				return [hp + Vector2(-r * 0.2, r * 0.08 + sob), hp + Vector2(r * 0.2, r * 0.08 - sob)]
			"stomp":
				# Fists balled down at his sides, pumping with each stomp.
				var pump2 := absf(sin(_gesture_t(sp) * STOMP_RATE)) * r * 0.12
				return [center + Vector2(-r * 0.7, r * 0.2 - pump2), center + Vector2(r * 0.7, r * 0.2 - pump2)]
			"shrug":
				# Palms out at his sides, shoulders going up and down: "what
				# was that?"
				var lift := absf(sin(_gesture_t(sp) * 5.0)) * r * 0.22
				return [center + Vector2(-r * 0.95, -r * 0.05 - lift), center + Vector2(r * 0.95, -r * 0.05 - lift)]
			"wave_off":
				# The incompletion signal: both hands swept back and forth
				# in front of him, crossing in the middle.
				var sweep := sin(_gesture_t(sp) * 11.0) * r * 0.75
				return [center + Vector2(-sweep, -r * 0.15), center + Vector2(sweep, -r * 0.3)]
			"pump":
				# A fist pumped down and up beside his head, the other at his side.
				var pump := absf(sin(_gesture_t(sp) * 8.0)) * r * 0.45
				return [center + Vector2(-r * 0.6, r * 0.1), hp + Vector2(r * 0.6, r * 0.2 - pump)]
		return []

	if sim.phase != MatchSim.Phase.LIVE:
		return []

	# Just caught it: hands come down and tuck the ball in.
	if _catch_t.has(sp) and sp == sim.carrier:
		var tuck := center + Vector2(0.0, -r * 0.05)
		return [tuck + Vector2(-r * 0.2, 0.0), tuck + Vector2(r * 0.2, 0.0)]

	# Ball in the air: the intended receiver reaches up for it, and so does
	# any defender close enough to where it's coming down to contest it.
	var reach := _reach_amount(sp)
	if reach > 0.0:
		var t := clampf(sim.ball_t / maxf(sim.ball_air_time, 0.01), 0.0, 1.0)
		var ball := to_px(sim.ball_pos) - Vector2(0.0, sin(t * PI) * _scale * 1.8)
		var up := hp + Vector2(0.0, -r * 0.55)
		# Always UP over his head - just leaning toward the ball's side,
		# so the hands never end up covering his face.
		var aim := up + Vector2(clampf(ball.x - up.x, -r * 0.3, r * 0.3), -r * 0.1)
		var wave := sin(Time.get_ticks_msec() * 0.02 + _pose_phase(sp)) * r * 0.05
		return [
			(center + Vector2(-r * 0.6, 0.0)).lerp(aim + Vector2(-r * 0.3, wave), reach),
			(center + Vector2(r * 0.6, 0.0)).lerp(aim + Vector2(r * 0.3, -wave), reach),
		]

	# The release: his throwing hand snaps out after the ball, then drops.
	if sim.ball_in_air and not sim.kick_play and sp == sim._last_passer and sim.ball_t < THROW_FOLLOW_TIME:
		var aim_dir := (to_px(sim.ball_to) - to_px(sp.pos)).normalized()
		var reach_out := 1.0 - sim.ball_t / THROW_FOLLOW_TIME
		return [center + Vector2(-r * 0.55, r * 0.05),
			center + aim_dir * r * (0.7 + 0.45 * reach_out) + Vector2(0.0, -r * 0.3)]

	# Carrying it with a tackler closing in: a stiff arm at the nearest one,
	# the ball tucked in on his other side.
	if sp == sim.carrier and sp.downed <= 0.0:
		var foe_near := _nearest_of(sim.defense if sp.is_offense else sim.offense, sp.pos, STIFF_ARM_YARDS)
		if foe_near != null and not foe_near.engaged:
			var arm := to_px(foe_near.pos) - center
			arm = arm.normalized() if arm.length() > 0.01 else UP
			var tuck_side := -1.0 if arm.x >= 0.0 else 1.0
			return [center + Vector2(tuck_side * r * 0.3, 0.0), center + arm * r * 1.05]

	# Locked up in a block: both hands out on the other man, shoving.
	var foe: SimPlayer = _block_foe.get(sp)
	if foe != null:
		var dir := to_px(foe.pos) - to_px(sp.pos)
		dir = dir.normalized() if dir.length() > 0.01 else (UP if sp.is_offense else -UP)
		var side := Vector2(-dir.y, dir.x)
		if side.x > 0.0:
			side = -side   # hand 0 stays the screen-left one
		var shove := maxf(0.0, sin(Time.get_ticks_msec() * 0.011 + _pose_phase(sp))) * r * 0.16
		var base := center + dir * (r * 0.95 + shove) + Vector2(0.0, -r * 0.08)
		# Out past his head and onto the other man, shoulder width apart.
		return [base + side * r * 0.45, base - side * r * 0.45]

	return []


## 0..1 how far he's reaching for a pass in the air: the intended receiver
## as it comes down, and any defender close enough to its landing spot to
## contest it. Drives both his hands and his facing.
func _reach_amount(sp: SimPlayer) -> float:
	if sim.phase != MatchSim.Phase.LIVE or not sim.ball_in_air or sim.thrown_to == null or sp.melted:
		return 0.0
	var t := clampf(sim.ball_t / maxf(sim.ball_air_time, 0.01), 0.0, 1.0)
	if sp == sim.thrown_to:
		return smoothstep(0.35, 0.8, t)
	if not sp.is_offense and sp.pos.distance_to(sim.ball_to) < 2.2:
		return smoothstep(0.55, 0.9, t)
	return 0.0


## Both hands thrown up over his head, pumping on `phase`.
func _hands_up(hp: Vector2, r: float, phase: float) -> Array:
	return [
		hp + Vector2(-r * 0.62, -r * (0.3 + 0.2 * absf(sin(phase)))),
		hp + Vector2(r * 0.62, -r * (0.3 + 0.2 * absf(sin(phase + 0.9)))),
	]


## [texture, modulate] for his hands: whichever hand sprite is nearer his
## head's skin, tinted the rest of the way to it.
func _hand_style(sp: SimPlayer) -> Array:
	var set_id := sp.data.head_id if sp.data.head_id != "" else "1"
	if not _hand_look.has(set_id):
		var skin := HeadArtDB.skin_color(set_id)
		var pick := "light"
		var best := INF
		for key in HAND_SKIN:
			var c: Color = HAND_SKIN[key]
			var dist := Vector3(c.r - skin.r, c.g - skin.g, c.b - skin.b).length()
			if dist < best:
				best = dist
				pick = key
		var base: Color = HAND_SKIN[pick]
		var mod := Color(minf(1.0, skin.r / base.r), minf(1.0, skin.g / base.g), minf(1.0, skin.b / base.b))
		_hand_look[set_id] = [HAND_TEX[pick], mod]
	return _hand_look[set_id]


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


## Filled and outline circles drawn from baked textures rather than
## draw_circle/draw_arc, which tessellate fresh geometry on every call - with
## a few per player per frame that was the single biggest cost of _draw,
## badly so on the web build.
const DISC_TEX_SIZE := 128
## The rim's width as a fraction of its radius - DISC_RIM_WIDTH at the
## minimum player size (PLAYER_R_MIN * 1.12 px).
const RING_FRAC := DISC_RIM_WIDTH / (PLAYER_R_MIN * 1.12)
static var _disc_tex: Texture2D
static var _ring_tex: Texture2D


func _draw_disc(c: Vector2, rad: float, col: Color) -> void:
	if _disc_tex == null:
		_disc_tex = _bake_circle(1.0)
	draw_texture_rect(_disc_tex, Rect2(c - Vector2(rad, rad), Vector2(rad, rad) * 2.0), false, col)


## A ring centred on radius `rad`, RING_FRAC * rad wide.
func _draw_ring(c: Vector2, rad: float, col: Color) -> void:
	if _ring_tex == null:
		_ring_tex = _bake_circle(RING_FRAC / (1.0 + RING_FRAC * 0.5))
	var outer := rad * (1.0 + RING_FRAC * 0.5)
	draw_texture_rect(_ring_tex, Rect2(c - Vector2(outer, outer), Vector2(outer, outer) * 2.0), false, col)


## White circle texture: a disc (`band` 1.0) or a ring `band` of the radius
## wide at the outside edge, with a one-pixel soft edge so it scales cleanly.
static func _bake_circle(band: float) -> Texture2D:
	var n := DISC_TEX_SIZE
	var img := Image.create_empty(n, n, true, Image.FORMAT_RGBA8)
	var half := n * 0.5
	var outer := half - 1.0
	var inner := outer * (1.0 - band)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - half, y + 0.5 - half).length()
			var a := clampf(outer - d + 0.5, 0.0, 1.0)
			if band < 1.0:
				a = minf(a, clampf(d - inner + 0.5, 0.0, 1.0))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _capsule(a: Vector2, b: Vector2, width: float, col: Color) -> void:
	draw_line(a, b, col, width)
	draw_circle(a, width * 0.5, col)
	draw_circle(b, width * 0.5, col)


func _draw_ball() -> void:
	# Held for the kick, on the spot.
	if (sim.kick_mode or sim.kick_play) and not sim.ball_in_air and sim.phase != MatchSim.Phase.DEAD \
			and sim.phase != MatchSim.Phase.DRIVE_OVER:
		var at := to_px(sim.kick_spot())
		var br := maxf(5.0, _scale * 0.30)
		draw_circle(at + Vector2(1.5, 2.0), br, Color(0, 0, 0, 0.3))
		draw_circle(at, br, UIKit.BALL)
		draw_arc(at, br, 0, TAU, 14, Color("f8ecd0"), 1.6)
		return
	if sim.carrier != null or not sim.ball_in_air:
		return
	var t := clampf(sim.ball_t / maxf(sim.ball_air_time, 0.01), 0.0, 1.0)
	var ground := to_px(sim.ball_pos)
	var lift := sin(t * PI) * _scale * (KICK_LIFT if sim.kick_play else 1.8)
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
