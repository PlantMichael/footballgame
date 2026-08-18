class_name MatchSim
extends RefCounted

## Simulates one football play at a time, plus the down/drive bookkeeping
## around it. Everything is in yards; the renderer converts to pixels.
##
## Field frame: x from 0 to 120. The offense always attacks +x, so its own
## goal line is x=10 and the scoring goal line is x=110.

const FIELD_LEN := 120.0
const FIELD_W := 53.33
const GOAL_LINE := 110.0
const OWN_GOAL := 10.0
const MAX_PLAY_TIME := 16.0
const CONTACT_INTERVAL := 3.0
const FIRST_CONTACT := 1.2      # the first rush move comes before the 3s beat

enum Phase { PRESNAP, LIVE, DEAD, DRIVE_OVER, MATCH_OVER }

# --- Match/drive state ------------------------------------------------------

var phase: Phase = Phase.PRESNAP
var score_us: int = 0
var score_them: int = 0
var drive_num: int = 0
var total_drives: int = 4
var down: int = 1
var to_go: float = 10.0
var los: float = 35.0
var opponent_quality: float = 6.0
var opponent_name: String = "Opponent"

# --- Play state -------------------------------------------------------------

var offense: Array[SimPlayer] = []   # index 0..10, matching GameState.SLOT_ORDER
var defense: Array[SimPlayer] = []   # 4 linemen, 3 linebackers, 4 defensive backs
var play_id: String = ""
var play: Dictionary = {}
var time: float = 0.0
var carrier: SimPlayer = null
var thrown_to: SimPlayer = null

var ball_pos: Vector2 = Vector2.ZERO
var ball_in_air: bool = false
var ball_from: Vector2 = Vector2.ZERO
var ball_to: Vector2 = Vector2.ZERO
var ball_t: float = 0.0
var ball_air_time: float = 0.0

var pursuit_triggered: bool = false
var handoff_done: bool = false
var qb_decision_timer: float = 0.0
var qb_scrambling: bool = false
var catch_x: float = 0.0   # field x where the last completion was caught

var result: Dictionary = {}
var play_log: Array = []         # human-readable lines for the match feed

var rng := RandomNumberGenerator.new()
var _roster_defense: Array = []      # Array[PlayerData] for the opposing 11


# ============================================================================
# Setup
# ============================================================================

func setup(starters: Array, defense_data: Array, quality: float, opp_name: String, drives: int, seed_value: int = 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	_roster_defense = defense_data
	opponent_quality = quality
	opponent_name = opp_name
	total_drives = drives
	score_us = 0
	score_them = 0
	drive_num = 0
	play_log.clear()
	_build_offense(starters)
	_build_defense()


func _build_offense(starters: Array) -> void:
	offense.clear()
	for i in GameState.SLOT_ORDER.size():
		var slot: String = GameState.SLOT_ORDER[i]
		var pd: PlayerData = starters[i]
		var sp := SimPlayer.new()
		sp.data = pd
		sp.is_offense = true
		sp.slot = slot
		sp.label = str(pd.number)
		offense.append(sp)


func _build_defense() -> void:
	defense.clear()
	var labels := ["DL0", "DL1", "DL2", "DL3", "LB0", "LB1", "LB2", "DB0", "DB1", "DB2", "DB3"]
	for i in labels.size():
		var sp := SimPlayer.new()
		sp.data = _roster_defense[i]
		sp.is_offense = false
		sp.slot = labels[i]
		sp.label = str(sp.data.number)
		defense.append(sp)


func offense_slot(slot: String) -> SimPlayer:
	for sp in offense:
		if sp.slot == slot:
			return sp
	return null


func flex_players() -> Array[SimPlayer]:
	var out: Array[SimPlayer] = []
	for sp in offense:
		if sp.slot.begins_with("F"):
			out.append(sp)
	return out


# ============================================================================
# Drive management
# ============================================================================

func start_match() -> void:
	drive_num = 0
	score_us = 0
	score_them = 0
	begin_drive()


func begin_drive() -> void:
	drive_num += 1
	los = 25.0 + OWN_GOAL + rng.randf_range(-5.0, 5.0)
	los = clampf(los, 20.0, 45.0)
	down = 1
	to_go = 10.0
	phase = Phase.PRESNAP
	result = {}
	# Everybody catches their breath between drives.
	for sp in offense:
		sp.energy = minf(1.0, sp.energy + 0.55)
	for sp in defense:
		sp.energy = minf(1.0, sp.energy + 0.55)
	log_line("--- Drive %d of %d, ball on the %s ---" % [drive_num, total_drives, yard_line_text(los)])


func yard_line_text(x: float) -> String:
	var from_own := x - OWN_GOAL
	if from_own <= 50.0:
		return "own %d" % int(round(from_own))
	return "opp %d" % int(round(100.0 - from_own))


func down_text() -> String:
	var suffix: String = ["1st", "2nd", "3rd", "4th"][clampi(down - 1, 0, 3)]
	if los + to_go >= GOAL_LINE:
		return "%s & Goal" % suffix
	return "%s & %d" % [suffix, int(ceil(to_go))]


func yards_to_endzone() -> float:
	return GOAL_LINE - los


# ============================================================================
# Formation
# ============================================================================

## Position everyone for the chosen play and compute the route preview.
##
## `instant` teleports everyone onto their spots, which is what you want after
## a whistle when the ball has moved. Changing the play call between snaps
## passes false so the formation visibly shifts instead.
func set_play(id: String, instant: bool = true) -> void:
	play_id = id
	play = PlayDB.get_play(id)
	if play.is_empty():
		return
	time = 0.0
	carrier = null
	thrown_to = null
	ball_in_air = false
	pursuit_triggered = false
	handoff_done = false
	qb_scrambling = false
	qb_decision_timer = 0.0
	catch_x = 0.0
	result = {}
	phase = Phase.PRESNAP
	for sp in offense:
		sp.energy = minf(1.0, sp.energy + 0.30)
	for sp in defense:
		sp.energy = minf(1.0, sp.energy + 0.30)
	_align_offense()
	_align_defense()
	if instant:
		for sp in offense:
			sp.pos = sp.target_pos
			sp.vel = Vector2.ZERO
			sp.trail = PackedVector2Array([sp.pos])
		for sp in defense:
			sp.pos = sp.target_pos
			sp.vel = Vector2.ZERO
	ball_pos = Vector2(los, FIELD_W * 0.5)


## Walk everyone toward their alignment while the play is being chosen.
func presnap_step(delta: float) -> void:
	if phase != Phase.PRESNAP:
		return
	for sp in offense:
		_shift(sp, delta)
	for sp in defense:
		_shift(sp, delta)
	var qb := offense_slot("QB")
	if qb != null:
		ball_pos = qb.pos


func _shift(sp: SimPlayer, delta: float) -> void:
	var to := sp.target_pos - sp.pos
	if to.length() < 0.06:
		sp.pos = sp.target_pos
		sp.vel = sp.vel.lerp(Vector2.ZERO, clampf(delta * 12.0, 0.0, 1.0))
		return
	var prev := sp.pos
	sp.pos = sp.pos.lerp(sp.target_pos, clampf(delta * 9.0, 0.0, 1.0))
	sp.vel = (sp.pos - prev) / maxf(delta, 0.0001)
	sp.stride += sp.vel.length() * delta * 3.2


func _snap_context(is_run_play: bool) -> Dictionary:
	var wr := 0
	var te := 0
	var rb := 0
	for f in flex_players():
		match f.data.pos:
			PlayerData.Pos.WR: wr += 1
			PlayerData.Pos.TE: te += 1
			PlayerData.Pos.RB: rb += 1
	return {
		"wr_count": wr,
		"te_count": te,
		"rb_count": rb,
		"down": down,
		"to_go": to_go,
		"yards_to_endzone": yards_to_endzone(),
		"score_diff": score_us - score_them,
		"is_run_play": is_run_play,
	}


## Bake item and ability modifiers into `eff` for the duration of this play.
func _apply_modifiers(sp: SimPlayer, ctx: Dictionary) -> void:
	var pd := sp.data
	var base := {
		"strength": pd.strength,
		"agility": pd.agility,
		"dexterity": pd.dexterity,
		"stamina": pd.stamina,
		"intelligence": pd.intelligence,
	}
	for key in ItemDB.stat_mods(pd.item_id):
		base[key] = int(base[key]) + int(ItemDB.stat_mods(pd.item_id)[key])
	for key in AbilityDB.snap_bonus(pd.ability_id, pd, ctx):
		base[key] = int(base[key]) + int(AbilityDB.snap_bonus(pd.ability_id, pd, ctx)[key])
	for key in base:
		base[key] = clampi(int(base[key]), 1, 15)
	sp.eff = base
	sp.fatigue_floor = AbilityDB.fatigue_floor(pd.ability_id)


## Penalty for lining a player up somewhere he does not belong.
func _out_of_position_penalty(sp: SimPlayer, wanted: String) -> void:
	var natural := sp.data.pos_name()
	if natural == wanted:
		return
	var family_ok := (
		(wanted in ["WR", "TE", "RB"] and natural in ["WR", "TE", "RB"])
	)
	# Proportional, not flat: subtracting 3 from a rookie with 3 Strength
	# wiped him out entirely.
	var mult := 0.85 if family_ok else 0.65
	for key in sp.eff:
		sp.eff[key] = clampi(int(round(float(sp.eff[key]) * mult)), 1, 15)


func _align_offense() -> void:
	var cy := FIELD_W * 0.5
	var is_run := PlayDB.is_run(play_id)
	var ctx := _snap_context(is_run)

	var c := offense_slot("C")
	c.target_pos = Vector2(los, cy)
	c.role = SimPlayer.Role.BLOCK

	var tackle_offsets := [-5.2, -2.6, 2.6, 5.2]
	for i in 4:
		var t := offense_slot("T%d" % i)
		t.target_pos = Vector2(los, cy + tackle_offsets[i])
		t.role = SimPlayer.Role.BLOCK

	var qb := offense_slot("QB")
	qb.target_pos = Vector2(los - 5.0, cy)
	qb.role = SimPlayer.Role.QB
	qb.has_ball = true
	carrier = qb

	var aligns: Array = play["align"]
	var routes: Array = play["routes"]
	var slot_pos: Array = play["slot_pos"]

	for i in 5:
		var f := offense_slot("F%d" % i)
		var a: Vector2 = aligns[i]
		f.target_pos = Vector2(los + a.x, clampf(cy + a.y, 1.5, FIELD_W - 1.5))
		f.route = []
		f.route_idx = 0
		f.route_done = false
		var assign = routes[i]
		if assign is String:
			f.role = SimPlayer.Role.BLOCK if assign == PlayDB.BLOCK else SimPlayer.Role.CARRY
		else:
			f.role = SimPlayer.Role.ROUTE
			# Routes are relative to the alignment spot, not wherever he is
			# standing mid-shift.
			for wp in assign:
				f.route.append(Vector2(f.target_pos.x + wp.x,
					clampf(f.target_pos.y + wp.y, 0.8, FIELD_W - 0.8)))

	# Modifiers last, so ability context sees the final personnel grouping.
	for i in offense.size():
		var sp: SimPlayer = offense[i]
		sp.engaged = false
		sp.stunned = 0.0
		sp.disrupted = 0.0
		sp.downed = 0.0
		sp.shed_cooldown = 0.0
		sp.next_contact = FIRST_CONTACT
		sp.tackle_cd = 0.0
		sp.has_ball = (sp.slot == "QB")
		sp.trail = PackedVector2Array([sp.pos])
		_apply_modifiers(sp, ctx)

	_out_of_position_penalty(offense_slot("QB"), "QB")
	_out_of_position_penalty(offense_slot("C"), "C")
	for i in 4:
		_out_of_position_penalty(offense_slot("T%d" % i), "T")
	for i in 5:
		_out_of_position_penalty(offense_slot("F%d" % i), str(slot_pos[i]))


func _align_defense() -> void:
	var cy := FIELD_W * 0.5
	var ctx := {"down": down, "to_go": to_go, "yards_to_endzone": yards_to_endzone()}

	for sp in defense:
		sp.engaged = false
		sp.stunned = 0.0
		sp.downed = 0.0
		sp.shed_cooldown = 0.0
		sp.mark = null
		sp.next_contact = FIRST_CONTACT
		sp.tackle_cd = 0.0
		sp.free_timer = 0.0
		sp.trail = PackedVector2Array()
		_apply_modifiers(sp, ctx)
		sp.reaction = maxf(0.15, 0.75 - float(sp.stat("intelligence")) * 0.035)

	# Front four always rush.
	var dl_offsets := [-4.6, -1.6, 1.6, 4.6]
	for i in 4:
		var d: SimPlayer = defense[i]
		d.target_pos = Vector2(los + 1.0, cy + dl_offsets[i])
		d.role = SimPlayer.Role.RUSH

	# Who is actually running a route?
	var runners: Array[SimPlayer] = []
	for f in flex_players():
		if f.role == SimPlayer.Role.ROUTE:
			runners.append(f)
	runners.sort_custom(func(a, b): return absf(a.target_pos.y - cy) > absf(b.target_pos.y - cy))

	var zone_scheme := rng.randf() < clampf(0.25 + opponent_quality * 0.02, 0.2, 0.55)
	var blitz := rng.randf() < (0.12 + (0.10 if down >= 3 else 0.0))

	var backs: Array[SimPlayer] = [defense[7], defense[8], defense[9], defense[10]]
	var lbs: Array[SimPlayer] = [defense[4], defense[5], defense[6]]

	var assigned := 0
	# In man, the last defensive back stays home as a free safety.
	var man_backs := 3 if not zone_scheme else 0
	for bi in backs.size():
		var d: SimPlayer = backs[bi]
		if bi < man_backs and assigned < runners.size():
			var r: SimPlayer = runners[assigned]
			d.role = SimPlayer.Role.MAN
			d.mark = r
			d.target_pos = Vector2(r.target_pos.x + rng.randf_range(5.0, 8.0),
				r.target_pos.y + rng.randf_range(-1.0, 1.0))
			assigned += 1
		elif not zone_scheme:
			# Free safety, centre field.
			d.role = SimPlayer.Role.ZONE
			d.zone_point = Vector2(los + rng.randf_range(17.0, 21.0), cy + rng.randf_range(-3.0, 3.0))
			d.target_pos = Vector2(d.zone_point.x - 3.0, d.zone_point.y)
		else:
			# Four across: two deep halves outside, two intermediate flats.
			d.role = SimPlayer.Role.ZONE
			var side := -1.0 if (bi % 2 == 0) else 1.0
			if bi < 2:
				d.zone_point = Vector2(los + rng.randf_range(19.0, 23.0), cy + side * rng.randf_range(8.0, 13.0))
			else:
				d.zone_point = Vector2(los + rng.randf_range(10.0, 13.0), cy + side * rng.randf_range(14.0, 19.0))
			d.target_pos = Vector2(d.zone_point.x - 3.0, d.zone_point.y)

	for i in lbs.size():
		var lb: SimPlayer = lbs[i]
		lb.target_pos = Vector2(los + 5.5, cy + [-7.5, 0.0, 7.5][i])
		if blitz and i == 1:
			lb.role = SimPlayer.Role.RUSH
		elif assigned < runners.size() and not zone_scheme:
			lb.role = SimPlayer.Role.MAN
			lb.mark = runners[assigned]
			assigned += 1
		else:
			lb.role = SimPlayer.Role.ZONE
			lb.zone_point = Vector2(los + 7.0, cy + [-9.0, 0.0, 9.0][i])
			lb.target_pos = Vector2(los + 5.5, cy + [-7.5, 0.0, 7.5][i])

	# Note: the defense deliberately gets no pre-snap tell about run vs pass.
	# Linebackers only crash downhill once _trigger_pursuit fires after the
	# handoff, and their reaction time is set by Intelligence.


## Route lines for the pre-snap preview, in yards.
func preview_routes() -> Array:
	var out: Array = []
	for f in flex_players():
		if f.role == SimPlayer.Role.ROUTE and not f.route.is_empty():
			var line := PackedVector2Array()
			line.append(f.target_pos)
			for wp in f.route:
				line.append(wp)
			out.append({"line": line, "kind": "route", "player": f})
		elif f.role == SimPlayer.Role.CARRY:
			var line2 := PackedVector2Array([f.target_pos,
				Vector2(los + 4.0, f.target_pos.y * 0.4 + FIELD_W * 0.3)])
			out.append({"line": line2, "kind": "carry", "player": f})
		else:
			out.append({"line": PackedVector2Array([f.target_pos]), "kind": "block", "player": f})
	return out


# ============================================================================
# Live simulation
# ============================================================================

func snap() -> void:
	if phase != Phase.PRESNAP:
		return
	# Start trails from where everyone actually is, not from the alignment they
	# were walking away from when the play call changed.
	for sp in offense:
		sp.trail = PackedVector2Array([sp.pos])
	phase = Phase.LIVE
	time = 0.0


func step(delta: float) -> void:
	if phase != Phase.LIVE:
		return
	time += delta
	_step_offense(delta)
	_step_defense(delta)
	_step_ball(delta)
	_step_contacts(delta)
	_record_trails()
	_check_dead()


func _record_trails() -> void:
	for sp in offense:
		if sp.trail.size() == 0 or sp.trail[sp.trail.size() - 1].distance_to(sp.pos) > 0.8:
			sp.trail.append(sp.pos)
			if sp.trail.size() > 60:
				sp.trail.remove_at(0)


# --- Offense ----------------------------------------------------------------

func _step_offense(delta: float) -> void:
	# Blockers re-assert this every frame, so clear it once up front rather
	# than inside each defender's update (which ran after the contact pass).
	for d in defense:
		d.engaged = false
	_assign_blocks()
	for sp in offense:
		if sp.disrupted > 0.0:
			sp.disrupted -= delta
		if sp == carrier and sp.slot != "QB":
			_carry_logic(sp, delta)
			continue
		match sp.role:
			SimPlayer.Role.QB:
				_qb_logic(sp, delta)
			SimPlayer.Role.BLOCK:
				_block_logic(sp, delta)
			SimPlayer.Role.ROUTE:
				_route_logic(sp, delta)
			SimPlayer.Role.CARRY:
				_pre_handoff_logic(sp, delta)
			_:
				sp.hold(delta)


func _qb_logic(qb: SimPlayer, delta: float) -> void:
	if not qb.has_ball:
		# Ball is gone: become a (bad) blocker so the QB is not a statue.
		_block_logic(qb, delta)
		return

	if qb_scrambling:
		_carry_logic(qb, delta)
		return

	var dropback := float(play.get("dropback", 1.5))
	var cy := FIELD_W * 0.5

	if PlayDB.is_run(play_id):
		var rb := _carry_target()
		if rb != null and not handoff_done:
			qb.move_toward_point(Vector2(los - 4.0, rb.pos.y), delta, 0.5)
			if time >= dropback and qb.pos.distance_to(rb.pos) < 5.0:
				_do_handoff(qb, rb)
		else:
			qb.hold(delta)
		return

	if time < dropback:
		qb.move_toward_point(Vector2(los - 7.0, cy), delta, 0.85)
		return

	# Slide in the pocket away from the closest free rusher.
	var threat := _closest_free_rusher(qb)
	var threat_dist := 99.0
	if threat != null:
		threat_dist = threat.pos.distance_to(qb.pos)
		if threat_dist < 6.0:
			var away := (qb.pos - threat.pos).normalized()
			qb.move_toward_point(qb.pos + Vector2(away.x * 0.4, away.y) * 3.0, delta, 0.7)
		else:
			qb.hold(delta)
	else:
		qb.hold(delta)

	qb_decision_timer -= delta
	if qb_decision_timer > 0.0:
		return
	qb_decision_timer = 0.12

	var hold_time := time - dropback
	var best := _evaluate_targets(qb)
	var pressure := threat_dist < 3.6
	var threshold := 8.5 - hold_time * 1.1
	if pressure:
		threshold -= 3.0

	# About to be hit: get rid of it. Sacks should be the punishment for a line
	# that loses instantly, not for one that loses eventually.
	if threat_dist < 2.3:
		if best.get("player") != null and float(best.get("score", -99.0)) > -3.0:
			_throw(qb, best["player"])
		elif hold_time > 0.4:
			_throwaway(qb)
		else:
			qb_scrambling = true
			log_line("%s escapes the pocket!" % qb.data.pname)
		return

	if best.get("player") != null and float(best["score"]) > threshold:
		_throw(qb, best["player"])
		return

	if hold_time > 2.6 and pressure and float(best.get("score", -99.0)) < 2.0:
		qb_scrambling = true
		log_line("%s takes off scrambling!" % qb.data.pname)
		return

	if hold_time > 3.0:
		if best.get("player") != null:
			_throw(qb, best["player"])
		else:
			_throwaway(qb)


func _carry_target() -> SimPlayer:
	for f in flex_players():
		if f.role == SimPlayer.Role.CARRY:
			return f
	return null


func _do_handoff(qb: SimPlayer, rb: SimPlayer) -> void:
	handoff_done = true
	qb.has_ball = false
	rb.has_ball = true
	carrier = rb
	_trigger_pursuit()
	log_line("Handoff to %s." % rb.data.pname)


func _pre_handoff_logic(sp: SimPlayer, delta: float) -> void:
	# Drift toward the mesh point until the QB gives it up.
	var qb := offense_slot("QB")
	if handoff_done:
		sp.hold(delta)
		return
	sp.move_toward_point(Vector2(los - 2.0, qb.pos.y), delta, 1.0)


func _route_logic(sp: SimPlayer, delta: float) -> void:
	# Once the ball is up, the target stops running his route and works
	# back to the catch point. Without this, throws land where nobody is.
	if ball_in_air and sp == thrown_to:
		sp.move_toward_point(ball_to, delta, 1.0)
		return
	if sp.route.is_empty():
		sp.hold(delta)
		return
	if sp.route_idx >= sp.route.size():
		# Route finished: work back toward the QB or drift to open space.
		var qb := offense_slot("QB")
		if qb != null and qb.has_ball:
			var open_dir := _open_drift(sp)
			sp.move_toward_point(sp.pos + open_dir * 4.0, delta, 0.55)
		else:
			sp.hold(delta)
		return

	var target: Vector2 = sp.route[sp.route_idx]
	# Low Intelligence players round off their breaks and drift off the line.
	var sloppiness := (15.0 - float(sp.stat("intelligence"))) * 0.06
	var arrive := 0.6 + sloppiness * 3.0
	sp.move_toward_point(target, delta, 1.0)
	if sp.pos.distance_to(target) < arrive:
		sp.route_idx += 1
		if sp.route_idx >= sp.route.size():
			sp.route_done = true


func _open_drift(sp: SimPlayer) -> Vector2:
	var away := Vector2.ZERO
	for d in defense:
		var to := sp.pos - d.pos
		var dist := to.length()
		if dist < 9.0 and dist > 0.01:
			away += to / (dist * dist)
	if away.length() < 0.01:
		return Vector2(0.3, 0.0)
	return away.normalized()


## One blocker per rusher. Assignments are made for the whole line at once so
## two linemen never claim the same defender while a third goes unblocked.
func _assign_blocks() -> void:
	var protect_point := carrier.pos if carrier != null else Vector2(los - 5.0, FIELD_W * 0.5)

	var free_blockers: Array[SimPlayer] = []
	var claimed := {}
	for sp in offense:
		if sp.role != SimPlayer.Role.BLOCK or sp == carrier:
			continue
		if sp.shed_cooldown > 0.0:
			sp.mark = null
			continue
		# Keep a valid existing assignment so blocks do not flicker.
		if sp.mark != null and _is_threat(sp.mark) and sp.mark.stunned <= 0.0 and not claimed.has(sp.mark):
			claimed[sp.mark] = true
			continue
		sp.mark = null
		free_blockers.append(sp)

	var threats: Array[SimPlayer] = []
	for d in defense:
		if d.free_timer > 0.0:
			continue  # just beat his man; give him a beat before help arrives
		if _is_threat(d) and d.stunned <= 0.0 and not claimed.has(d):
			threats.append(d)
	threats.sort_custom(func(a: SimPlayer, b: SimPlayer) -> bool:
		return a.pos.distance_to(protect_point) < b.pos.distance_to(protect_point))

	# Most dangerous rusher first, taken by whichever free blocker is closest.
	for d in threats:
		var best: SimPlayer = null
		var best_dist := 1e9
		for sp in free_blockers:
			if sp.mark != null:
				continue
			var dist: float = sp.pos.distance_to(d.pos)
			if dist < best_dist:
				best_dist = dist
				best = sp
		if best != null:
			best.mark = d
			claimed[d] = true


func _block_logic(sp: SimPlayer, delta: float) -> void:
	if sp.shed_cooldown > 0.0:
		sp.shed_cooldown -= delta

	var protect_point := carrier.pos if carrier != null else Vector2(los - 5.0, FIELD_W * 0.5)

	if sp.mark == null:
		sp.move_toward_point(Vector2(sp.pos.x + 1.0, sp.pos.y), delta, 0.4)
		return

	var d: SimPlayer = sp.mark
	# Stand in the gap between the defender and whoever has the ball.
	var to_protect := (protect_point - d.pos)
	var stand := d.pos + (to_protect.normalized() * 0.9 if to_protect.length() > 0.01 else Vector2(-0.9, 0.0))
	sp.move_toward_point(stand, delta, 1.0)

	# A block only counts when the blocker actually has position on the
	# defender, not merely when he is trailing him toward the ball.
	var contact_dist := sp.pos.distance_to(d.pos)
	var has_leverage := sp.pos.distance_to(protect_point) <= d.pos.distance_to(protect_point) + 0.6
	sp.engaged = contact_dist < 1.8 and has_leverage and sp.shed_cooldown <= 0.0
	if sp.engaged:
		d.engaged = true


func _is_threat(d: SimPlayer) -> bool:
	if d == null:
		return false
	if d.role == SimPlayer.Role.RUSH or d.role == SimPlayer.Role.PURSUE:
		return true
	# On a run, anybody in the box has to be accounted for at the snap.
	if PlayDB.is_run(play_id) and (d.pos.x - los) < 9.0:
		return true
	# After a catch, the nearest defenders are worth blocking too.
	if carrier != null and carrier.slot != "QB":
		return d.pos.distance_to(carrier.pos) < 10.0
	return false


func _carry_logic(sp: SimPlayer, delta: float) -> void:
	# Head for the end zone while bending away from nearby defenders.
	var forward := Vector2(1.0, 0.0)
	var avoid := Vector2.ZERO
	for d in defense:
		if d.stunned > 0.0:
			continue
		var to := sp.pos - d.pos
		var dist := to.length()
		if dist < 10.0 and dist > 0.01:
			var weight := 1.0 / maxf(dist * dist, 0.5)
			# A defender who is engaged with a blocker is not the threat an
			# unblocked one is, so the runner presses that gap instead.
			var danger := 1.0 if not d.engaged else 0.25
			# Only dodge defenders in front or alongside.
			if d.pos.x > sp.pos.x - 1.0:
				avoid += to.normalized() * weight * 4.0 * danger
	# Stay off the sideline unless it is the only way out.
	var edge := 0.0
	if sp.pos.y < 5.0:
		edge = (5.0 - sp.pos.y) * 0.35
	elif sp.pos.y > FIELD_W - 5.0:
		edge = -(sp.pos.y - (FIELD_W - 5.0)) * 0.35

	var vision := clampf(float(sp.stat("intelligence")) / 15.0, 0.3, 1.0)
	var dir := (forward * 1.5 + avoid * vision + Vector2(0.0, edge)).normalized()
	# Running with the ball is a touch slower than running free.
	sp.move_toward_point(sp.pos + dir * 6.0, delta, 0.92)


# --- QB decision making -----------------------------------------------------

func _evaluate_targets(qb: SimPlayer) -> Dictionary:
	var progression: Array = play.get("progression", [])
	var best := {"player": null, "score": -99.0}
	var qb_int := float(qb.stat("intelligence"))

	for f in flex_players():
		if f.role != SimPlayer.Role.ROUTE and f.role != SimPlayer.Role.CARRY:
			continue
		if f == carrier:
			continue
		var throw_dist := qb.pos.distance_to(f.pos)
		if throw_dist > 48.0:
			continue
		var sep := _nearest_defender_dist(f)
		var openness := clampf(sep, 0.0, 9.0)
		# Depth is worth something, but not so much that a covered deep route
		# always outranks a wide open checkdown.
		var downfield := clampf((f.pos.x - los) * 0.11, -1.0, 3.0)
		var slot_index := int(f.slot.substr(1, 1))
		var order := progression.find(slot_index)
		var prog_bonus := 0.0
		if order >= 0:
			prog_bonus = float(progression.size() - order) * 0.7
		# A worse QB misreads coverage: the noise scales with missing INT.
		var noise := rng.randfn(0.0, (16.0 - qb_int) * 0.18)
		var score := openness + downfield + prog_bonus - throw_dist * 0.045 + noise
		if score > float(best["score"]):
			best = {"player": f, "score": score}
	return best


func _nearest_defender_dist(sp: SimPlayer) -> float:
	var best := 99.0
	for d in defense:
		best = minf(best, d.pos.distance_to(sp.pos))
	return best


func _closest_free_rusher(qb: SimPlayer) -> SimPlayer:
	var best: SimPlayer = null
	var best_d := 99.0
	for d in defense:
		if d.role != SimPlayer.Role.RUSH and d.role != SimPlayer.Role.PURSUE:
			continue
		if d.engaged:
			continue
		var dist := d.pos.distance_to(qb.pos)
		if dist < best_d:
			best_d = dist
			best = d
	return best


func _throw(qb: SimPlayer, target: SimPlayer) -> void:
	var air_speed := 19.0 + float(qb.stat("strength")) * 0.75
	# Two passes of lead estimation is plenty at these speeds.
	var aim := target.pos
	for i in 2:
		var t := qb.pos.distance_to(aim) / air_speed
		aim = target.pos + target.vel * t

	var acc := (16.0 - float(qb.stat("intelligence"))) * 0.028 + (16.0 - float(qb.stat("dexterity"))) * 0.045
	var pressure := _closest_free_rusher(qb)
	if pressure != null and pressure.pos.distance_to(qb.pos) < 3.5:
		acc += 0.7
	acc *= lerpf(1.35, 1.0, clampf(qb.energy, 0.0, 1.0))
	aim += Vector2(rng.randfn(0.0, acc), rng.randfn(0.0, acc))
	aim.y = clampf(aim.y, -2.0, FIELD_W + 2.0)

	ball_from = qb.pos
	ball_to = aim
	ball_air_time = maxf(0.18, qb.pos.distance_to(aim) / air_speed)
	ball_t = 0.0
	ball_in_air = true
	qb.has_ball = false
	carrier = null
	thrown_to = target
	_trigger_pursuit()
	log_line("%s throws to %s." % [qb.data.pname, target.data.pname])


func _throwaway(qb: SimPlayer) -> void:
	ball_from = qb.pos
	ball_to = Vector2(los + 12.0, -3.0 if rng.randf() < 0.5 else FIELD_W + 3.0)
	ball_air_time = 0.9
	ball_t = 0.0
	ball_in_air = true
	qb.has_ball = false
	carrier = null
	thrown_to = null
	_end_play({
		"kind": "incomplete",
		"yards": 0.0,
		"text": "%s throws it away." % qb.data.pname,
	})


func _trigger_pursuit() -> void:
	if pursuit_triggered:
		return
	pursuit_triggered = true
	for d in defense:
		d.reaction = maxf(0.1, 0.7 - float(d.stat("intelligence")) * 0.033)


# --- Defense ----------------------------------------------------------------

func _step_defense(delta: float) -> void:
	for d in defense:
		if d.free_timer > 0.0:
			d.free_timer -= delta
		if d.stunned > 0.0:
			d.stunned -= delta
			if d.stunned <= 0.0:
				d.downed = 0.0   # back on his feet
			d.hold(delta)
			continue
		if d.tackle_cd > 0.0:
			d.tackle_cd -= delta

		if pursuit_triggered and carrier != null:
			d.reaction -= delta
			if d.reaction <= 0.0 and d.role != SimPlayer.Role.RUSH:
				d.role = SimPlayer.Role.PURSUE

		# Coverage players who can reach the throw attack the catch point.
		if ball_in_air and d.role != SimPlayer.Role.RUSH:
			if d.pos.distance_to(ball_to) < 16.0:
				d.move_toward_point(ball_to, delta, 1.0)
				continue

		match d.role:
			SimPlayer.Role.RUSH:
				_rush_logic(d, delta)
			SimPlayer.Role.MAN:
				_man_logic(d, delta)
			SimPlayer.Role.ZONE:
				_zone_logic(d, delta)
			SimPlayer.Role.PURSUE:
				_pursue_logic(d, delta)
			_:
				d.hold(delta)


func _rush_logic(d: SimPlayer, delta: float) -> void:
	var target := carrier.pos if carrier != null else ball_pos
	if d.engaged:
		# Fighting through a block: heavy speed penalty until the shed roll wins.
		d.move_toward_point(target, delta, 0.20)
	else:
		d.move_toward_point(target, delta, 1.0)


func _man_logic(d: SimPlayer, delta: float) -> void:
	if d.mark == null:
		_zone_logic(d, delta)
		return
	var r: SimPlayer = d.mark
	var qb := offense_slot("QB")
	var ball_side := (qb.pos - r.pos).normalized() if qb != null else Vector2(-1, 0)
	# Leverage, not cushion: a good cover man rides the receiver's hip and
	# lets any separation come from the Agility gap between them.
	var cushion := lerpf(0.9, 0.25, clampf(float(d.stat("intelligence")) / 15.0, 0.0, 1.0))
	var spot := r.pos + ball_side * cushion
	d.move_toward_point(spot, delta, 1.0)


func _zone_logic(d: SimPlayer, delta: float) -> void:
	var is_deep := (d.zone_point.x - los) >= 15.0

	# Find the receiver who most threatens this area.
	var threat: SimPlayer = null
	var best := 15.0 if is_deep else 11.0
	for f in offense:
		if f.role != SimPlayer.Role.ROUTE and f != carrier:
			continue
		var dist := f.pos.distance_to(d.zone_point)
		# A deep defender cares most about whoever is furthest downfield.
		if is_deep:
			dist -= maxf(0.0, f.pos.x - d.zone_point.x) * 0.8
		if dist < best:
			best = dist
			threat = f

	if threat == null:
		d.move_toward_point(d.zone_point, delta, 0.75)
		return

	if is_deep:
		# Keep the cushion: stay on top of the route, never let it behind you.
		var depth := maxf(d.zone_point.x, threat.pos.x + 3.0)
		d.move_toward_point(Vector2(depth, threat.pos.y), delta, 1.0)
	else:
		var qb := offense_slot("QB")
		var lead := (qb.pos - threat.pos).normalized() * 1.2 if qb != null else Vector2.ZERO
		d.move_toward_point(threat.pos + lead, delta, 1.0)


func _pursue_logic(d: SimPlayer, delta: float) -> void:
	if carrier == null:
		_zone_logic(d, delta)
		return
	# Solve for an actual interception point rather than running at where the
	# carrier is now. With a short lead cap, a defender trailing an equally
	# fast runner could never close, so every broken tackle ran forever.
	var t := 0.0
	for i in 3:
		t = d.pos.distance_to(carrier.pos + carrier.vel * t) / maxf(d.speed(), 0.1)
		t = clampf(t, 0.0, 6.0)
	# Poor decision makers take worse angles and under-lead the runner.
	var skill := clampf(float(d.stat("intelligence")) / 11.0, 0.35, 1.0)
	var aim := carrier.pos + carrier.vel * t * skill
	if d.engaged:
		d.move_toward_point(aim, delta, 0.2)
	else:
		d.move_toward_point(aim, delta, 1.0)


# --- Ball -------------------------------------------------------------------

func _step_ball(delta: float) -> void:
	if carrier != null:
		ball_pos = carrier.pos
		return
	if not ball_in_air:
		return
	ball_t += delta
	var t := clampf(ball_t / ball_air_time, 0.0, 1.0)
	ball_pos = ball_from.lerp(ball_to, t)
	if ball_t >= ball_air_time:
		ball_in_air = false
		if phase == Phase.LIVE:
			_resolve_catch()


func _resolve_catch() -> void:
	if thrown_to == null:
		_end_play({"kind": "incomplete", "yards": 0.0, "text": "Pass falls incomplete."})
		return

	var spot := ball_to
	var rec: SimPlayer = thrown_to
	var rec_dist := rec.pos.distance_to(spot)
	var def_near: SimPlayer = null
	var def_dist := 99.0
	for d in defense:
		var dist := d.pos.distance_to(spot)
		if dist < def_dist:
			def_dist = dist
			def_near = d

	var contested := def_dist <= 2.0
	var would_be_first := (spot.x - los) >= to_go
	var ctx := {
		"nearest_defender_dist": def_dist,
		"would_be_first_down": would_be_first,
		"target_is_deep": (spot.x - los) >= 20.0,
	}

	if rec_dist > 4.2:
		# Badly off target. Only a defender in the area can do anything with it.
		if def_dist < 1.2 and rng.randf() < 0.10 + float(def_near.stat("dexterity")) * 0.007:
			_interception(def_near)
		else:
			_end_play({"kind": "incomplete", "yards": 0.0, "text": "Pass sails incomplete."})
		return

	var p := rec.catch_chance_base()
	p += AbilityDB.catch_mod(rec.data.ability_id, ctx)
	p += ItemDB.catch_mod(rec.data.item_id)
	# Kept deliberately small: the Dexterity curve is the design contract, and
	# heavy coverage/accuracy penalties on top of it made every pass a drop.
	p -= 0.11 * clampf(1.0 - def_dist / 2.6, 0.0, 1.0)
	p -= clampf((rec_dist - 1.8) * 0.07, 0.0, 0.11)
	p = clampf(p, 0.03, 0.97)

	if rng.randf() < p:
		rec.has_ball = true
		catch_x = spot.x
		carrier = rec
		thrown_to = null
		rec.pos = rec.pos.lerp(spot, 0.6)
		var bucks := 5
		var msg := "%s hauls it in." % rec.data.pname
		if contested:
			bucks = 15
			msg = "%s makes a contested grab!" % rec.data.pname
		_award(bucks, msg)
		_trigger_pursuit()
	else:
		if def_dist < 1.4:
			var int_chance := 0.05 + float(def_near.stat("dexterity")) * 0.006
			if rng.randf() < int_chance:
				_interception(def_near)
				return
		_end_play({
			"kind": "incomplete",
			"yards": 0.0,
			"text": "%s cannot hang on." % rec.data.pname,
		})


func _interception(d: SimPlayer) -> void:
	_end_play({
		"kind": "interception",
		"yards": 0.0,
		"turnover": true,
		"text": "INTERCEPTED by %s!" % d.data.pname,
	})


# --- Contact ----------------------------------------------------------------

## An engaged blocker displaces his man away from the ball. This is what
## makes Strength matter on the line: an immovable blocker opens a hole,
## a weak one gets driven back into his own backfield.
func _resolve_engagements(delta: float) -> void:
	var ball_point := carrier.pos if carrier != null else Vector2(los - 5.0, FIELD_W * 0.5)
	for b in offense:
		if not b.engaged or b.mark == null:
			continue
		var d: SimPlayer = b.mark
		var away := d.pos - ball_point
		if away.length() < 0.01:
			away = Vector2(1.0, 0.0)
		var diff := float(b.stat("strength") - d.stat("strength"))
		# Yards per second of displacement; a losing blocker gets driven back.
		# The lower clamp matters: a blocker losing the strength matchup should
		# give ground slowly, not get driven into his own backfield, or an
		# outmatched line gives up a sack on nearly every drop back.
		var push := clampf(0.35 + diff * 0.16, -0.20, 2.4)
		# On a run the line fires out and drive blocks rather than pass sets.
		if PlayDB.is_run(play_id):
			push += 0.40
		d.pos += away.normalized() * push * delta


func _step_contacts(delta: float) -> void:
	_resolve_engagements(delta)
	# Blocks: every CONTACT_INTERVAL the defender tries to shed.
	for b in offense:
		if not b.engaged or b.mark == null:
			continue
		b.next_contact -= delta
		if b.next_contact > 0.0:
			continue
		b.next_contact = CONTACT_INTERVAL
		var d: SimPlayer = b.mark
		if _contact_roll(d, b, "block"):
			b.engaged = false
			b.shed_cooldown = 1.6
			b.mark = null
			d.free_timer = 0.8

	# Coverage: defenders jam receivers off their routes.
	for d in defense:
		if d.role != SimPlayer.Role.MAN or d.mark == null:
			continue
		if d.pos.distance_to(d.mark.pos) > 1.6:
			continue
		d.next_contact -= delta
		if d.next_contact > 0.0:
			continue
		d.next_contact = CONTACT_INTERVAL
		if _contact_roll(d, d.mark, "cover"):
			d.mark.disrupted = 1.1

	# Tackles.
	if carrier == null:
		return
	for d in defense:
		if d.stunned > 0.0 or d.tackle_cd > 0.0:
			continue
		var reach: float = d.pos.distance_to(carrier.pos)
		# A defender being blocked can only make the play if the runner comes
		# right to him; otherwise the blocker has him walled off.
		var limit := 0.9 if d.engaged else 1.8
		if reach > limit:
			continue
		d.tackle_cd = 0.4
		var chance := 0.88 + float(d.stat("strength") - carrier.stat("strength")) * 0.020
		chance -= AbilityDB.contact_mod(carrier.data.ability_id, "carry")
		chance -= ItemDB.contact_mod(carrier.data.item_id, "carry")
		chance = clampf(chance, 0.12, 0.95)
		if rng.randf() < chance:
			_tackle(d)
			return
		else:
			# He stays up, but the contact costs him his momentum and gives
			# the rest of the pursuit time to close.
			d.stunned = 0.5
			d.downed = 0.0001
			carrier.vel *= 0.5
			carrier.disrupted = maxf(carrier.disrupted, 0.6)
			_award(8, "%s breaks the tackle!" % carrier.data.pname)


## Doc rule: the bigger the strength gap, the better the chance of a push-off,
## capped at 25% per contact. Ability and item modifiers stack on top.
func _contact_roll(winner: SimPlayer, loser: SimPlayer, role: String) -> bool:
	# Doc rule: bigger strength gap means a better push-off, capped at 25%.
	# An even matchup still gets a small chance, otherwise nobody ever sheds.
	var diff := float(winner.stat("strength") - loser.stat("strength"))
	var chance := clampf(0.06 + diff * 0.024, 0.0, 0.25)
	chance += AbilityDB.contact_mod(winner.data.ability_id, role)
	chance += ItemDB.contact_mod(winner.data.item_id, role)
	chance -= AbilityDB.contact_mod(loser.data.ability_id, role)
	chance -= ItemDB.contact_mod(loser.data.item_id, role)
	return rng.randf() < clampf(chance, 0.0, 0.85)


func _tackle(d: SimPlayer) -> void:
	carrier.downed = 0.0001
	var end_x := carrier.pos.x
	var is_sack := carrier.slot == "QB" and not qb_scrambling and not PlayDB.is_run(play_id)
	var kind := "sack" if is_sack else ("run" if PlayDB.is_run(play_id) or qb_scrambling else "complete")
	var text := "%s is tackled by %s." % [carrier.data.pname, d.data.pname]
	if is_sack:
		text = "SACK! %s gets to %s." % [d.data.pname, carrier.data.pname]
	_end_play({"kind": kind, "yards": end_x - los, "text": text})


# --- End of play ------------------------------------------------------------

func _check_dead() -> void:
	if phase != Phase.LIVE:
		return
	if carrier != null:
		if carrier.pos.x >= GOAL_LINE:
			_end_play({
				"kind": "touchdown",
				"yards": GOAL_LINE - los,
				"td": true,
				"text": "TOUCHDOWN, %s!" % carrier.data.pname,
			})
			return
		if carrier.pos.y <= 0.3 or carrier.pos.y >= FIELD_W - 0.3:
			_end_play({
				"kind": "run" if PlayDB.is_run(play_id) else "complete",
				"yards": carrier.pos.x - los,
				"text": "%s steps out of bounds." % carrier.data.pname,
			})
			return
		if carrier.pos.x <= OWN_GOAL:
			_end_play({
				"kind": "safety",
				"yards": carrier.pos.x - los,
				"turnover": true,
				"text": "Tackled in the end zone. Safety!",
			})
			return
	if time > MAX_PLAY_TIME:
		var yards := 0.0
		if carrier != null:
			yards = carrier.pos.x - los
		_end_play({"kind": "run", "yards": yards, "timeout": true, "text": "The play is whistled dead."})


func _end_play(res: Dictionary) -> void:
	if phase != Phase.LIVE:
		return
	phase = Phase.DEAD
	res["yards"] = float(res.get("yards", 0.0))
	res["td"] = bool(res.get("td", false))
	res["turnover"] = bool(res.get("turnover", false))
	res["bucks"] = int(res.get("bucks", 0)) + _pending_bucks
	res["events"] = _pending_events.duplicate()
	_pending_bucks = 0
	_pending_events.clear()

	var gained: float = res["yards"]
	if res["kind"] != "incomplete" and res["kind"] != "interception":
		res["text"] = "%s  (%s%d yd)" % [res["text"], "+" if gained >= 0 else "", int(round(gained))]

	if res["td"]:
		res["bucks"] = int(res["bucks"]) + 100
		res["events"].append("Touchdown! +100")
	elif not res["turnover"] and gained >= to_go:
		res["bucks"] = int(res["bucks"]) + 15
		res["events"].append("First down +15")
	if gained >= 20.0:
		res["bucks"] = int(res["bucks"]) + 25
		res["events"].append("Big play +25")

	res["duration"] = time
	result = res
	log_line(res["text"])


var _pending_bucks: int = 0
var _pending_events: Array = []


func _award(amount: int, text: String) -> void:
	_pending_bucks += amount
	_pending_events.append("%s +%d" % [text, amount])
	log_line(text)


func log_line(text: String) -> void:
	play_log.append(text)
	if play_log.size() > 120:
		play_log.remove_at(0)


# ============================================================================
# Advancing the down / drive
# ============================================================================

## Apply the finished play. Returns a Dictionary describing what happens next:
##   {"drive_over": bool, "reason": String, "match_over": bool}
func advance() -> Dictionary:
	if phase != Phase.DEAD:
		return {"drive_over": false, "reason": "", "match_over": false}

	var out := {"drive_over": false, "reason": "", "match_over": false}

	if bool(result.get("td", false)):
		score_us += 7
		out["drive_over"] = true
		out["reason"] = "Touchdown! Extra point is good."
	elif result.get("kind", "") == "safety":
		score_them += 2
		out["drive_over"] = true
		out["reason"] = "Safety. Two points for %s." % opponent_name
	elif bool(result.get("turnover", false)):
		out["drive_over"] = true
		out["reason"] = "Turnover."
	else:
		var gained: float = float(result.get("yards", 0.0))
		los = clampf(los + gained, OWN_GOAL + 1.0, GOAL_LINE - 0.5)
		to_go -= gained
		if to_go <= 0.0:
			down = 1
			to_go = minf(10.0, GOAL_LINE - los)
		else:
			down += 1
			if down > 4:
				out["drive_over"] = true
				out["reason"] = "Turnover on downs."

	if out["drive_over"]:
		phase = Phase.DRIVE_OVER
		log_line(out["reason"])
	else:
		phase = Phase.PRESNAP

	return out


## Abstract simulation of the opponent possession between your drives.
func sim_opponent_drive() -> String:
	var td_chance := clampf(
		0.22 + (opponent_quality - GameState.ROUND_ONE_QUALITY) * 0.075, 0.12, 0.60)
	var roll := rng.randf()
	if roll < td_chance:
		score_them += 7
		return "%s marches down and scores a touchdown." % opponent_name
	elif roll < td_chance + 0.18:
		score_them += 3
		return "%s stalls out and settles for a field goal." % opponent_name
	elif roll < td_chance + 0.30:
		return "%s turns it over. Your defense comes up big." % opponent_name
	return "%s goes three and out." % opponent_name


func match_finished() -> bool:
	return drive_num >= total_drives and phase == Phase.DRIVE_OVER


func won() -> bool:
	return score_us > score_them


## Rebuild the offense from a new lineup between drives, keeping the fatigue
## already accumulated by players who stay on the field.
func resync_offense(new_starters: Array) -> void:
	var prev := {}
	for sp in offense:
		prev[sp.data] = sp.energy
	_build_offense(new_starters)
	for sp in offense:
		if prev.has(sp.data):
			sp.energy = prev[sp.data]
