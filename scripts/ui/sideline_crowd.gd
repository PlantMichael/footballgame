class_name SidelineCrowd
extends RefCounted

## Ambient actors only: never appended to MatchSim's players or collisions.
## Positions use the field's yard frame. The FieldView owns this visual clock.
const BODIES := [1, 3, 4, 6, 7, 8, 9]
const PEOPLE_PER_SIDE := 100
const MARGIN := 11.0
const REF_SPEED := 11.0
const REACTION_SECONDS := 2.6
const PROP_ART := {
	"bench": preload("res://assets/sidelines/props/bench.svg"),
	"cooler_station": preload("res://assets/sidelines/props/cooler_station.svg"),
	"bottle_crate": preload("res://assets/sidelines/props/bottle_crate.svg"),
	"kit_bag": preload("res://assets/sidelines/props/kit_bag.svg"),
	"towel_bin": preload("res://assets/sidelines/props/towel_bin.svg"),
	"cone": preload("res://assets/sidelines/props/cone.svg"),
}
const BOTTLE := preload("res://assets/sidelines/props/bottle.svg")
## Footprints in downfield/lateral yards, including room around furniture.
const PROP_SIZES := {"bench": Vector2(4.8, 1.5), "cooler_station": Vector2(2.0, 2.0),
	"bottle_crate": Vector2(1.25, 1.4), "kit_bag": Vector2(1.1, 1.6),
	"towel_bin": Vector2(1.4, 1.4), "cone": Vector2(0.65, 0.6)}
const HANDS := {
	"1": preload("res://assets/hands/hand_light.png"),
	"2": preload("res://assets/hands/hand_dark.png"),
}

var people: Array[Dictionary] = []
var officials: Array[Dictionary] = []
var props: Array[Dictionary] = []
var clock: float = 0.0
var offense_mode: String = "idle"
var defense_mode: String = "idle"
var ref_signal: String = ""
var reaction_left: float = 0.0
var _last_sim: WeakRef
var _last_phase: int = -1
var _last_time: float = 0.0
var _result_seen: bool = false
var _catch_seen: bool = false
var _gain_seen: bool = false
var _react_at: float = 0.0
var _textures: Dictionary = {}
var _heads: Dictionary = {}


func reset(sim: MatchSim) -> void:
	people.clear()
	officials.clear()
	props.clear()
	clock = 0.0
	offense_mode = "idle"
	defense_mode = "idle"
	ref_signal = ""
	reaction_left = 0.0
	_result_seen = false
	_catch_seen = false
	_gain_seen = false
	_react_at = 0.0
	_last_phase = -1
	_last_time = sim.time
	_last_sim = weakref(sim)
	# Private, fixed layout RNG: no effect on match or global randomness.
	var layout := RandomNumberGenerator.new()
	layout.seed = 48291
	for side in 2:
		for station in 5:
			var x := 20.0 + station * 18.0
			_add_prop("bench", x, 8.0, side)
			_add_prop("cooler_station", x + 4.0, 8.3, side)
			_add_prop("bottle_crate", x + 5.8, 8.6, side)
			_add_prop("kit_bag", x - 3.1, 9.0, side)
			_add_prop("towel_bin", x - 4.9, 8.6, side)
			for seat in 2:
				_add_person(Vector2(x + (-1.1 if seat == 0 else 1.1), _side_y(8.0, side)), side, "rest", layout)
		for i in 10:
			_add_prop("cone", 13.0 + i * 10.0, 2.9, side)
		# Small groups, uneven gaps and individual spacing replace parade rows.
		var anchors: Array[Vector2] = []
		for i in 16:
			anchors.append(Vector2(14.0 + i * 6.0 + layout.randf_range(-1.5, 1.5), layout.randf_range(4.2, 8.8)))
		var placed := 10
		for attempt in 12000:
			if placed >= PEOPLE_PER_SIDE:
				break
			var anchor := anchors[attempt % anchors.size()]
			var x := clampf(anchor.x + layout.randf_range(-5.5, 5.5), 11.5, 108.5)
			var depth := clampf(anchor.y + layout.randf_range(-2.0, 2.0), 3.9, 9.8)
			var at := Vector2(x, _side_y(depth, side))
			if not _free_home(at):
				continue
			var activity: String = ["watch", "chat", "drink", "pace", "watch"][placed % 5]
			_add_person(at, side, activity, layout)
			placed += 1
	for side in 2:
		officials.append({"pos": Vector2(clampf(sim.los + (-3.0 if side == 0 else 6.0), 4.0, 116.0),
			-1.8 if side == 0 else MatchSim.FIELD_W + 1.8), "offense": side == 0,
			"body": 4 if side == 0 else 8, "head": str(side + 1), "beat": float(side) * 1.7,
			"ref": true, "stride": 0.0, "velocity": 0.0})


func _side_y(depth: float, side: int) -> float:
	return -depth if side == 0 else MatchSim.FIELD_W + depth


func _add_prop(kind: String, x: float, depth: float, side: int) -> void:
	props.append({"kind": kind, "pos": Vector2(x, _side_y(depth, side)), "offense": side == 0})


func _free_home(at: Vector2) -> bool:
	for prop in props:
		var footprint: Vector2 = PROP_SIZES[prop.kind]
		if Rect2(prop.pos - footprint * 0.5, footprint).grow(0.75).has_point(at):
			return false
	for actor in people:
		if at.distance_squared_to(actor.home) < 1.65 * 1.65:
			return false
	return true


func _add_person(at: Vector2, side: int, activity: String, layout: RandomNumberGenerator) -> void:
	var index := people.size()
	people.append({"pos": at, "home": at, "offense": side == 0,
		"body": BODIES[index % BODIES.size()], "head": str(1 + index % 2),
		"beat": layout.randf_range(0.0, TAU), "delay": layout.randf_range(0.0, 0.45),
		"activity": activity, "ref": false})


func advance(sim: MatchSim, delta: float, final_pose: Dictionary = {}) -> void:
	if _last_sim == null or _last_sim.get_ref() != sim:
		reset(sim)
	clock += delta
	for actor in people:
		# A small personal pacing space keeps walkers clear of props and refs.
		var home: Vector2 = actor.home
		actor.pos = home + Vector2(sin(clock * 0.65 + float(actor.beat)) * 0.38,
			sin(clock * 0.43 + float(actor.beat)) * 0.18) if actor.activity == "pace" else home
	reaction_left = maxf(0.0, reaction_left - delta)
	if reaction_left == 0.0:
		offense_mode = "watch" if sim.phase == MatchSim.Phase.LIVE else "idle"
		defense_mode = offense_mode
		ref_signal = ""
	var fresh_play := sim.phase == MatchSim.Phase.PRESNAP and _last_phase != sim.phase
	fresh_play = fresh_play or (sim.phase == MatchSim.Phase.LIVE and (_last_phase != sim.phase or sim.time < _last_time))
	if fresh_play:
		_result_seen = false
		_catch_seen = false
		_gain_seen = false
		reaction_left = 0.0
		ref_signal = ""
		offense_mode = "idle"
		defense_mode = "idle"
	if sim.phase == MatchSim.Phase.LIVE:
		# Reading possession also catches a throw AND catch between render frames.
		if not _catch_seen and sim.carrier != null and sim.carrier.is_offense \
				and sim.carrier.slot != "QB" and not sim.handoff_done:
			_catch_seen = true
			_react("clap", "tense", "", 0.9)
		if not _gain_seen and sim.carrier != null and sim.carrier.is_offense \
				and sim.carrier.pos.x - sim.los >= minf(sim.to_go, 20.0):
			_gain_seen = true
			_react("cheer", "tense", "", 1.2)
	if not _result_seen and not sim.result.is_empty() \
			and sim.phase in [MatchSim.Phase.DEAD, MatchSim.Phase.DRIVE_OVER]:
		_result_seen = true
		_result_reaction(sim)
	if not final_pose.is_empty():
		offense_mode = "cheer" if final_pose.get(true, "") == "jump" else "groan" if final_pose.get(true, "") == "lie" else "idle"
		defense_mode = "cheer" if final_pose.get(false, "") == "jump" else "groan" if final_pose.get(false, "") == "lie" else "idle"
	var ball_x := sim.ball_pos.x if sim.phase == MatchSim.Phase.LIVE else sim.los
	if sim.phase in [MatchSim.Phase.DEAD, MatchSim.Phase.DRIVE_OVER]:
		# advance() applies ordinary fourth-down yardage before DRIVE_OVER.
		# Scores, kicks and explicit turnovers leave los at the original spot.
		var spot_applied: bool = sim.phase == MatchSim.Phase.DRIVE_OVER \
			and not bool(sim.result.get("td", false)) and not bool(sim.result.get("kick", false)) \
			and not bool(sim.result.get("turnover", false)) and sim.result.get("kind", "") != "safety"
		ball_x = clampf(sim.los + (0.0 if spot_applied else float(sim.result.get("yards", 0.0))), 4.0, 116.0)
	var motion_delta := maxf(delta, maxf(0.0, sim.time - _last_time)) if sim.phase == MatchSim.Phase.LIVE else delta
	for i in officials.size():
		var ref := officials[i]
		var at: Vector2 = ref["pos"]
		var offset := (-3.0 if i == 0 else 6.0) if sim.phase == MatchSim.Phase.LIVE else 0.0
		var target := clampf(ball_x + offset, 4.0, 116.0)
		var next := move_toward(at.x, target, REF_SPEED * motion_delta)
		ref["velocity"] = (next - at.x) / maxf(motion_delta, 0.0001)
		ref["stride"] = float(ref["stride"]) + absf(next - at.x) * 3.0
		ref["pos"] = Vector2(next, at.y)
	_last_time = sim.time
	_last_phase = sim.phase


func _react(ours: String, theirs: String, signal_name: String, seconds: float = REACTION_SECONDS) -> void:
	offense_mode = ours
	defense_mode = theirs
	ref_signal = signal_name
	reaction_left = seconds
	_react_at = clock


func _result_reaction(sim: MatchSim) -> void:
	var result := sim.result
	var kind := String(result.get("kind", ""))
	var yards := float(result.get("yards", 0.0))
	if bool(result.get("td", false)) or kind == "field_goal":
		var offense_scored := sim.carrier == null or sim.carrier.is_offense
		_react("cheer" if offense_scored else "groan", "groan" if offense_scored else "cheer", "touchdown")
	elif bool(result.get("turnover", false)) or kind in ["safety", "sack", "missed_fg"] or yards < 0.0:
		_react("groan", "cheer", "no_good" if kind == "missed_fg" else "turnover" if bool(result.get("turnover", false)) else "stop")
	elif kind == "incomplete":
		_react("groan", "cheer" if sim.down >= 4 else "clap", "incomplete")
	elif yards >= sim.to_go:
		_react("cheer", "groan", "first_down")
	elif sim.down >= 4:
		_react("groan", "cheer", "turnover")
	else:
		_react("clap" if yards > 0.0 else "tense", "tense" if yards > 0.0 else "clap", "stop", 1.6)


func team_palette(offense: bool, sim: MatchSim) -> String:
	var jersey := JerseyDB.BLUE if offense else sim.defense_jersey
	return jersey if jersey in ["red", "green"] else "blue"


func draw_on(field, sim: MatchSim) -> void:
	var visible := Rect2(Vector2(-70, -100), field.size + Vector2(140, 200))
	var scale: float = field.get("_scale")
	for prop in props:
		var p: Vector2 = field.to_px(prop.pos)
		if not visible.has_point(p):
			continue
		var footprint: Vector2 = PROP_SIZES[prop.kind]
		var dimensions := Vector2(footprint.y, footprint.x) * scale
		field.draw_style_box(_prop_shadow(), Rect2(p - dimensions * 0.5 + Vector2(3, 4), dimensions))
		var art: Texture2D = PROP_ART[prop.kind]
		field.draw_set_transform(p, 0.0, Vector2(-1.0 if prop.kind == "bench" and not prop.offense else 1.0, 1.0))
		field.draw_texture_rect(art, Rect2(-dimensions * 0.5, dimensions), false)
		field.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var actors := people + officials
	actors.sort_custom(func(a, b): return a.pos.x > b.pos.x)
	for actor in actors:
		var p: Vector2 = field.to_px(actor["pos"])
		if visible.has_point(p):
			_draw_actor(field, sim, actor, p)


var _shadow: StyleBoxFlat
func _prop_shadow() -> StyleBoxFlat:
	if _shadow == null:
		_shadow = StyleBoxFlat.new()
		_shadow.bg_color = Color(0.0, 0.0, 0.0, 0.22)
		_shadow.set_corner_radius_all(7)
	return _shadow


func _body(palette: String, view: String, body: int) -> Texture2D:
	var key := "%s/%s/body_%02d.png" % [palette, view, body]
	if not _textures.has(key):
		_textures[key] = load("res://assets/sidelines/" + key)
	return _textures[key]


func _head(set_id: String, view: String) -> Array:
	var key := set_id + ":" + view
	if not _heads.has(key):
		var tex := HeadArtDB.head_texture(set_id, view)
		_heads[key] = [tex, HeadArtDB.face_draw_rect(set_id, view, tex, 1.0)]
	return _heads[key]


func _draw_actor(field, sim: MatchSim, actor: Dictionary, ground: Vector2) -> void:
	var referee: bool = actor["ref"]
	var ours: bool = actor["offense"]
	var mode := ref_signal if referee else offense_mode if ours else defense_mode
	var activity: String = actor.get("activity", "watch")
	if not referee:
		if mode in ["idle", "watch"] or (reaction_left > 0.0 and clock - _react_at < float(actor.delay)):
			mode = activity
			# Drinking and conversations come in short, offset bursts.
			if activity in ["chat", "drink"] and fmod(clock + float(actor.beat) * 2.0, 8.0) > 3.2:
				mode = "watch"
	var t := clock * 7.5 + float(actor["beat"])
	var scale: float = field.get("_scale")
	var h := scale * (1.5 if referee else 1.35)
	if not referee:
		h *= 1.0 + sin(float(actor.beat)) * 0.08
	if activity == "rest":
		h *= 0.83
	var face_h := scale * 0.72
	var stride := float(actor.get("stride", 0.0))
	var running := referee and absf(float(actor["velocity"])) > 0.2
	var pacing := not referee and activity == "pace" and mode == "pace"
	if pacing:
		stride = clock * 3.0 + float(actor.beat)
		running = true
	var hop := absf(sin(t)) * h * 0.2 if mode == "cheer" else 0.0
	var bob := absf(sin(stride)) * h * 0.07 if running else sin(clock * 2.0 + float(actor["beat"])) * h * 0.018
	var center := ground + Vector2(sin(stride) * h * 0.03 if running else 0.0, -hop - bob)
	var view := "left"
	var flip := ours
	if mode in ["cheer", "clap", "groan", "touchdown", "incomplete", "no_good", "first_down", "turnover", "stop"]:
		view = "front"
		flip = false
	elif running:
		var velocity := float(actor.velocity) if referee else cos(clock * 0.65 + float(actor.beat))
		view = "back" if velocity > 0 else "front"
		flip = false
	elif mode == "chat":
		view = "front" if sin(float(actor.beat)) > 0 else "back"
		flip = false
	var palette := "ref" if referee else team_palette(ours, sim)
	var tex := _body(palette, view, int(actor["body"]))
	var width := h * tex.get_width() / maxf(tex.get_height(), 1.0)
	field.draw_circle(ground + Vector2(0, h * 0.4), h * 0.32, Color(0, 0, 0, 0.2))
	field.draw_set_transform(center, 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	field.draw_texture_rect(tex, Rect2(-width * 0.5, -h * 0.5, width, h), false)
	field.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var head_at := center + Vector2(0, -h * 0.4 - face_h * 0.38)
	if mode == "groan":
		head_at.y += h * 0.1
	var head_view := HeadArtDB.view_for(view, flip)
	var art := _head(actor["head"], head_view)
	var box: Rect2 = art[1]
	field.draw_texture_rect(art[0], Rect2(head_at + box.position * face_h, box.size * face_h), false)
	var hands := _hand_positions(mode, center, head_at, h, t, running)
	var hand: Texture2D = HANDS[actor["head"]]
	for at: Vector2 in hands:
		var d := face_h * 0.43
		field.draw_texture_rect(hand, Rect2(at - Vector2.ONE * d * 0.5, Vector2.ONE * d), false)
	if mode == "drink":
		var bottle_size := Vector2(h * 0.18, h * 0.41)
		field.draw_texture_rect(BOTTLE, Rect2(head_at + Vector2(h * 0.15, -h * 0.02), bottle_size), false)


func _hand_positions(mode: String, center: Vector2, head: Vector2, h: float, t: float, running: bool) -> Array:
	match mode:
		"cheer", "touchdown":
			return [head + Vector2(-h * 0.42, -h * 0.42 + sin(t) * h * 0.08), head + Vector2(h * 0.42, -h * 0.42 - sin(t) * h * 0.08)]
		"clap":
			var spread := h * (0.1 + absf(sin(t)) * 0.22)
			return [center + Vector2(-spread, -h * 0.18), center + Vector2(spread, -h * 0.18)]
		"groan":
			return [head + Vector2(-h * 0.28, h * 0.08), head + Vector2(h * 0.28, h * 0.08)]
		"incomplete", "no_good":
			return [center + Vector2(-h * (0.65 + sin(t) * 0.12), -h * 0.1), center + Vector2(h * (0.65 + sin(t) * 0.12), -h * 0.1)]
		"first_down", "turnover":
			return [center + Vector2(-h * 0.55, h * 0.1), head + Vector2(h * 0.4, -h * 0.6 if mode == "first_down" else h * 0.9)]
		"stop":
			return [head + Vector2(-h * 0.45, -h * 0.15), center + Vector2(h * 0.4, h * 0.1)]
		"tense":
			return [center + Vector2(-h * 0.38, -h * 0.25), center + Vector2(h * 0.38, -h * 0.25)]
		"chat":
			return [center + Vector2(-h * 0.4, -h * (0.16 + sin(t * 0.5) * 0.14)), center + Vector2(h * 0.35, h * 0.18)]
		"drink":
			return [head + Vector2(h * 0.24, h * 0.28), center + Vector2(-h * 0.35, h * 0.18)]
		"rest":
			return [center + Vector2(-h * 0.23, h * 0.28), center + Vector2(h * 0.23, h * 0.28)]
	if running:
		return [center + Vector2(-h * 0.4, sin(t) * h * 0.15), center + Vector2(h * 0.4, -sin(t) * h * 0.15)]
	return []
