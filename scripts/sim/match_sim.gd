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
## Pure safety valve against a true stalemate (nobody ever closes on the
## carrier) - not meant to cap an ordinary long run. It used to sit at 16s,
## which was shorter than a breakaway TD from deep in your own territory
## actually takes at realistic sim speeds, so long runs kept getting whistled
## dead mid-field instead of finishing. Kept under 33s (some of the tools/
## balance harnesses cap a single play's own step loop at 2000 steps of
## 1/60s DT, i.e. ~33.3s - this needs to stay under that or their own cap
## would silently cut the play short before this one gets the chance to).
const MAX_PLAY_TIME := 30.0
const CONTACT_INTERVAL := 3.0
const FIRST_CONTACT := 1.2      # the first rush move comes before the 3s beat

## When a blocker loses a shed roll, the SAME blocker is out of the rotation
## for SHED_COOLDOWN seconds (can't take on any rusher, not just his old
## one). The rusher himself only runs truly free for FREE_RUSH_TIME - a
## different, already-idle blocker can step in as soon as that expires.
## These used to be 1.6s and 0.8s: long enough that a single shed reliably
## covered most of the distance to the QB risk-free, and - combined with
## every blocker's first contact roll landing on the exact same instant
## (FIRST_CONTACT is one shared constant), so multiple blocks routinely
## failed in the same frame - a spare lineman standing right there with
## nothing to do still couldn't help for most of a second. That's what was
## producing an offensive line that looked like it was just standing around
## while a rusher ran straight through to the QB.
const FREE_RUSH_TIME := 0.15
const SHED_COOLDOWN := 1.0

## How close a free rusher has to get before the QB abandons the rest of his
## drop and starts looking for an answer. Deliberately short: at 4+ yards he
## bails on nearly every snap and the pocket stops meaning anything, and
## every would-be sack turns into a scramble. See _qb_logic.
const PANIC_DIST := 2.2

## Agility a QB needs to escape a pocket that breaks before his drop is even
## finished. Below it he takes the sack, so a statue behind a bad line is a
## real liability and a mobile one is worth paying for.
const SCRAMBLE_AGILITY := 9

## How close a flex playing RB has to be to the QB for a "Hand Off" plan to
## fire automatically - see can_handoff_to/request_handoff.
const HANDOFF_RANGE := 3.5

## How much downfield a remaining waypoint has to be worth before a fresh
## ball carrier bothers running to it, and how close he has to get to call it
## reached. See _carry_route_logic.
const CARRY_ROUTE_MIN_GAIN := 0.5
const CARRY_ROUTE_ARRIVE := 0.8

## How close a defender standing right on top of a remaining waypoint has to
## be before that waypoint (and the route from there) is abandoned in favor
## of open-field running - see _carry_route_logic. Running through traffic
## mid-route is still on the coach; this only catches a waypoint that would
## flat-out run the receiver into a defender who's already standing on it.
const CARRY_ROUTE_ABORT_DIST := 2.0

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

## Set by match.gd before start_match() when this is the run's final, chosen
## bowl game - see AbilityDB's "bowl_jitters" and _snap_context's
## is_bowl_game ctx key. Never true in dev mode.
var is_bowl_game: bool = false

# --- Play state -------------------------------------------------------------

var offense: Array[SimPlayer] = []   # index 0..10, matching GameState.SLOT_ORDER
var defense: Array[SimPlayer] = []   # 4 linemen, 3 linebackers, 4 defensive backs
var play_id: String = ""
var play: Dictionary = {}

## Air yards of every catch made since the renderer last looked. Drained by
## field_view.gd, which turns each one into a screen shake scaled to how far
## the ball travelled. Purely presentational - nothing in the sim reads it.
var catch_shakes: Array = []

## One entry per "combustion" explosion or "aftershock" earthquake since the
## renderer last looked - just a count, drained by field_view.gd into one
## big multi-directional shake each, bigger than an ordinary catch_shakes
## entry. Purely presentational.
var big_shakes: Array = []

## For flexes nobody drew a route for: slot -> the RouteBook.STOCK id they
## were handed this snap, so the chalkboard can name it instead of just
## saying "auto". Empty on a scripted play.
var auto_route_ids: Dictionary = {}
var time: float = 0.0
var carrier: SimPlayer = null
var thrown_to: SimPlayer = null

## Box-score stat line per PlayerData for THIS match - see stat_line_for and
## _credit_game_stats. Purely presentational (the match screen's Team Stats
## panel); nothing in the sim itself reads it back.
var game_stats: Dictionary = {}

## Play-scoped bookkeeping for _credit_game_stats, reset in _begin_call.
var _last_passer: SimPlayer = null
var _last_completion_target: SimPlayer = null
var _pass_completed_this_play: bool = false

var ball_pos: Vector2 = Vector2.ZERO
var ball_in_air: bool = false
var ball_from: Vector2 = Vector2.ZERO
var ball_to: Vector2 = Vector2.ZERO
var ball_t: float = 0.0
var ball_air_time: float = 0.0

## Slots (from flex_players) the coach marked as priority targets before the
## snap - see set_play/toggle_priority_target. The QB's target evaluation
## gives them a flat score bonus so they get thrown to noticeably more
## often, without ever being a hard override: a wide open non-priority
## receiver can still out-score a priority target nobody can get open.
const PRIORITY_TARGET_BONUS := 5.0
var priority_targets: Dictionary = {}   # slot String -> true

## Roguelike per-game upgrades picked after a scoring drive (see
## GameState/match.gd's upgrade-choice overlay). Keyed by PlayerData rather
## than slot so a bonus follows the player even if he's later subbed to the
## bench and back in. Lives only on this MatchSim - a fresh match starts
## with none, so these never carry over between games.
var match_bonuses: Dictionary = {}   # PlayerData -> {stat String -> int amount}

var pursuit_triggered: bool = false
var handoff_done: bool = false
var qb_decision_timer: float = 0.0
var qb_scrambling: bool = false
var catch_x: float = 0.0   # field x where the last completion was caught

## Armed before the snap via set_planned_handoff/set_planned_action, since
## clicking HAND OFF/SCRAMBLE mid-play was too fiddly to hit in time. "" /
## "handoff" / "scramble" - only one at a time. Checked each frame in
## _qb_logic and cleared for the next down in begin_drive/advance.
var planned_action: String = ""

## The specific flex slot a "handoff" plan targets - picked pre-snap the same
## way a priority target is, not "whoever's closest" during the play. Only
## meaningful when planned_action == "handoff".
var planned_handoff_slot: String = ""

var result: Dictionary = {}
var play_log: Array = []         # human-readable lines for the match feed

## Rolled once per DOWN, not per chalk edit (see _begin_call), before offense
## alignment, so the offense's own snap context (see _snap_context) can react
## to whether the defense is blitzing. Assignment itself still happens in
## _align_defense - this only decides it earlier so both sides can see it.
var _blitz_this_play: bool = false
var _zone_scheme_this_play: bool = false

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


## Dev-mode hook: swap in a freshly generated defense at `quality`, live,
## without waiting for a new drive. Re-aligns the new defenders onto
## whatever play is currently called so a mid-presnap change takes effect
## immediately instead of only after the next snap.
func regenerate_defense(rng_src: RandomNumberGenerator, quality: float) -> void:
	opponent_quality = quality
	_roster_defense = Generator.make_defense(rng_src, quality, GameState.aura_count(rng_src))
	_build_defense()
	if not play.is_empty():
		_align_defense()
		for sp in defense:
			sp.pos = sp.target_pos
			sp.vel = Vector2.ZERO


func offense_slot(slot: String) -> SimPlayer:
	for sp in offense:
		if sp.slot == slot:
			return sp
	return null


## Where flex `slot` is aligned for the current call, in field yards. The
## chalk tool stores strokes relative to this so a route keeps its shape when
## the ball moves or personnel shuffles the formation.
func flex_align(slot: String) -> Vector2:
	var sp := offense_slot(slot)
	return sp.target_pos if sp != null else Vector2.ZERO


func flex_players() -> Array[SimPlayer]:
	var out: Array[SimPlayer] = []
	for sp in offense:
		if sp.slot.begins_with("F"):
			out.append(sp)
	return out


# --- Pre-snap target priority ------------------------------------------------

func is_priority_target(slot: String) -> bool:
	return priority_targets.has(slot)


func toggle_priority_target(slot: String) -> void:
	if priority_targets.has(slot):
		priority_targets.erase(slot)
	else:
		priority_targets[slot] = true


func clear_priority_targets() -> void:
	priority_targets.clear()


func select_all_priority_targets() -> void:
	for f in flex_players():
		priority_targets[f.slot] = true


func all_priority_targets_selected() -> bool:
	for f in flex_players():
		if not priority_targets.has(f.slot):
			return false
	return true


# --- Per-game roguelike upgrades ---------------------------------------------

func add_match_bonus(pd: PlayerData, stat: String, amount: int) -> void:
	var mods: Dictionary = match_bonuses.get(pd, {})
	mods[stat] = int(mods.get(stat, 0)) + amount
	match_bonuses[pd] = mods


func match_bonus_for(pd: PlayerData) -> Dictionary:
	return match_bonuses.get(pd, {})


# --- Box score ----------------------------------------------------------

## This match's counting stats for `pd` - see the field comment on
## game_stats for the keys (pass_att, pass_comp, pass_yards, pass_td,
## pass_int, rush_att, rush_yards, rush_td, rec, rec_yards, rec_td).
func stat_line_for(pd: PlayerData) -> Dictionary:
	return game_stats.get(pd, {})


func _bump_stat(pd: PlayerData, key: String, amount: float = 1.0) -> void:
	var line: Dictionary = game_stats.get(pd, {})
	line[key] = float(line.get(key, 0.0)) + amount
	game_stats[pd] = line


## Credits whoever threw/caught/carried on this play with the box-score
## stats a completion, incompletion, interception, or run should produce.
## Sacks and safeties intentionally credit nobody, matching the real
## convention of excluding sacks from both pass and rush attempts.
func _credit_game_stats(res: Dictionary) -> void:
	var kind := String(res.get("kind", ""))
	var yards: float = res.get("yards", 0.0)
	var td := bool(res.get("td", false))

	if kind == "touchdown":
		kind = "complete" if _pass_completed_this_play else "run"

	match kind:
		"complete":
			if _last_passer != null:
				_bump_stat(_last_passer.data, "pass_att")
				_bump_stat(_last_passer.data, "pass_comp")
				_bump_stat(_last_passer.data, "pass_yards", yards)
				if td:
					_bump_stat(_last_passer.data, "pass_td")
			if _last_completion_target != null:
				_bump_stat(_last_completion_target.data, "rec")
				_bump_stat(_last_completion_target.data, "rec_yards", yards)
				if td:
					_bump_stat(_last_completion_target.data, "rec_td")
		"incomplete":
			if _last_passer != null:
				_bump_stat(_last_passer.data, "pass_att")
		"interception":
			if _last_passer != null:
				_bump_stat(_last_passer.data, "pass_att")
				_bump_stat(_last_passer.data, "pass_int")
		"run":
			if carrier != null:
				_bump_stat(carrier.data, "rush_att")
				_bump_stat(carrier.data, "rush_yards", yards)
				if td:
					_bump_stat(carrier.data, "rush_td")


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
	priority_targets.clear()
	planned_action = ""
	planned_handoff_slot = ""
	# Everybody catches their breath between drives.
	for sp in offense:
		sp.energy = minf(1.0, sp.energy + 0.55)
		sp.stat_decay = 0
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

## Build the offensive call from the coach's chalkboard: the five flex
## players line up in a RouteBook formation and run whatever was drawn for
## them, with a random stock route standing in for anyone left blank.
##
## This is the normal path. `set_play` below is the scripted-play path, kept
## for the batch balance harnesses in tools/.
func set_drawn_call(routes_by_slot: Dictionary, instant: bool = true) -> void:
	var flexes := flex_players()
	var spots := RouteBook.formation_for(flexes)
	var routes: Array = []
	var slot_pos: Array = []
	# How deep the SHALLOWEST receiver goes - see the dropback below.
	var quickest := 99.0
	auto_route_ids.clear()

	for i in flexes.size():
		var slot: String = flexes[i].slot
		var spot: Vector2 = spots[i]
		var route: Array = routes_by_slot.get(slot, [])
		if route.is_empty():
			# Nobody drew for him: give him a stock route, rerolled every
			# snap so an undrawn receiver stays unpredictable rather than
			# running the same thing all game.
			var ids: Array = RouteBook.STOCK.keys()
			var pick: String = ids[rng.randi_range(0, ids.size() - 1)]
			auto_route_ids[slot] = pick
			route = RouteBook.route_for_spot(pick, spot)
		routes.append(route)
		slot_pos.append(RouteBook.role_name_for_spot(spot))
		var depth := 0.0
		for wp in route:
			depth = maxf(depth, wp.x)
		quickest = minf(quickest, depth)

	play_id = ""
	play = {
		"name": "Chalk",
		"kind": "pass",
		# Keyed to the QUICKEST route on the board, not the deepest: how fast
		# the ball can come out is set by the shortest outlet, not the longest
		# route. Chalk a checkdown and the QB gets rid of it; send all five
		# deep and he has to stand there and wear it.
		"dropback": clampf(0.8 + minf(quickest, 30.0) * 0.055, 0.8, 2.4),
		"align": spots,
		"slot_pos": slot_pos,
		"routes": routes,
		# No scripted read order on a drawn call - the QB works off who is
		# actually open, nudged by whatever the coach flagged as a priority
		# target. See _evaluate_targets.
		"progression": [],
	}
	_begin_call(instant)


## Position everyone for a scripted PlayDB play. Used by the tools/ balance
## harnesses, which drive the sim off the old playbook so their tuning
## baselines stay comparable across this change.
##
## `instant` teleports everyone onto their spots, which is what you want after
## a whistle when the ball has moved. Changing the call between snaps passes
## false so the formation visibly shifts instead.
func set_play(id: String, instant: bool = true) -> void:
	play_id = id
	play = PlayDB.get_play(id)
	auto_route_ids.clear()
	if play.is_empty():
		return
	_begin_call(instant)


## Shared reset + alignment for both call paths. `play` must already be set.
func _begin_call(instant: bool) -> void:
	time = 0.0
	# Nothing drains this when the sim runs headless, so reset it per play
	# rather than letting a batch harness grow it for thousands of snaps.
	catch_shakes.clear()
	big_shakes.clear()
	carrier = null
	thrown_to = null
	ball_in_air = false
	pursuit_triggered = false
	handoff_done = false
	qb_scrambling = false
	qb_decision_timer = 0.0
	catch_x = 0.0
	_last_passer = null
	_last_completion_target = null
	_pass_completed_this_play = false
	result = {}
	phase = Phase.PRESNAP
	for sp in offense:
		sp.energy = minf(1.0, sp.energy + 0.30)
	for sp in defense:
		sp.energy = minf(1.0, sp.energy + 0.30)
	_align_offense()
	# The defense calls its play once per down, not once per chalk edit: `instant`
	# is true only for a genuinely new snap (see set_drawn_call/set_play callers in
	# match.gd), false for a same-down route redraw. Re-rolling blitz/zone and
	# re-running _align_defense on every redraw let the defense visibly "react" to
	# whatever the coach just drew - a real defense's call is locked in before that.
	if instant:
		_blitz_this_play = rng.randf() < (0.12 + (0.10 if down >= 3 else 0.0))
		_zone_scheme_this_play = rng.randf() < clampf(0.25 + opponent_quality * 0.02, 0.2, 0.55)
		_align_defense()
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
		for pos in _effective_positions(f.data):
			match pos:
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
		"is_blitzed": _blitz_this_play,
		"is_bowl_game": is_bowl_game,
	}


## `pd`'s positions for personnel counts, team buffs, and the out-of-position
## penalty - his real one, unless an ability (AbilityDB.counts_as_positions,
## e.g. "positionless") replaces it with a whole set at once.
func _effective_positions(pd: PlayerData) -> Array:
	var extra := AbilityDB.counts_as_positions(pd.ability_id)
	return extra if not extra.is_empty() else [pd.pos]


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
	var decay_start := AbilityDB.decaying_stat_start(pd.ability_id)
	if decay_start > 0:
		var decayed := clampi(decay_start - sp.stat_decay, AbilityDB.decaying_stat_floor(pd.ability_id), 15)
		for key in base:
			base[key] = decayed
	for key in ItemDB.stat_mods(pd.item_id):
		base[key] = int(base[key]) + int(ItemDB.stat_mods(pd.item_id)[key])
	for key in match_bonus_for(pd):
		base[key] = int(base[key]) + int(match_bonus_for(pd)[key])
	for key in AbilityDB.snap_bonus(pd.ability_id, pd, ctx):
		base[key] = int(base[key]) + int(AbilityDB.snap_bonus(pd.ability_id, pd, ctx)[key])
	var agi_cap := AbilityDB.speed_cap(pd.ability_id)
	if agi_cap < 99:
		base["agility"] = mini(int(base["agility"]), agi_cap)
	for key in base:
		base[key] = clampi(int(base[key]), 1, 15)
	sp.eff = base
	sp.fatigue_floor = AbilityDB.fatigue_floor(pd.ability_id)


## True if the offense should be treated as running the ball for blocking
## purposes RIGHT NOW - either an old-style scripted PlayDB run play
## (PlayDB.is_run, only ever set by the tools/ tuning harness - the live game
## always calls set_drawn_call, which leaves play_id "" and PlayDB.is_run
## permanently false), or the coach's own drawn-up call: the "Hand Off"/
## "Scramble" plan is armed for this snap (even before it's actually
## triggered - the box has to be accounted for from the snap, not from the
## moment the ball changes hands), the QB is already scrambling, or the
## handoff already happened. Used for box-defender blocking assignments
## (_is_threat) and the run-blocking push (_resolve_engagements). Deliberately
## broader than _play_was_a_run() below - counting the ARMED plan even if it
## never actually fires is correct here (nobody should sit unblocked just
## because the RB never got the ball), but wrong for box-score crediting,
## which must reflect what actually happened this play.
func _is_run_play() -> bool:
	return (PlayDB.is_run(play_id) or planned_action == "handoff" or planned_action == "scramble"
		or handoff_done or qb_scrambling)


## True if the ball was ACTUALLY run this play - a real handoff happened or
## the QB actually scrambled, or (tuning harness only) a scripted PlayDB run
## play. Unlike _is_run_play() above, this ignores a merely-armed Hand Off/
## Scramble plan that never actually fired (e.g. the RB never got in range
## before the whistle, and the QB threw it downfield instead) - crediting
## that as a run would mislabel what was actually a completed pass. Used by
## _tackle/_check_dead/_credit_game_stats to classify the finished play.
func _play_was_a_run() -> bool:
	return PlayDB.is_run(play_id) or handoff_done or qb_scrambling


## True if anyone in the current offense (e.g. "stat_shield") stops
## decaying_stat_start abilities like "stat_pad" from advancing this play.
func _team_blocks_stat_loss() -> bool:
	for sp in offense:
		if AbilityDB.blocks_stat_loss(sp.data.ability_id):
			return true
	return false


## Penalty for lining a player up somewhere he does not belong.
func _out_of_position_penalty(sp: SimPlayer, wanted: String) -> void:
	var natural := sp.data.pos_name()
	if natural == wanted:
		return
	for pos in _effective_positions(sp.data):
		if PlayerData.POS_NAMES[pos] == wanted:
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
		if AbilityDB.dedicated_blocker(f.data.ability_id):
			# Overrides whatever the coach drew for him: he never runs a
			# route or takes a handoff, and locks onto his own target for
			# the whole play instead of the normal per-frame assignment -
			# see _assign_blocks.
			f.role = SimPlayer.Role.BLOCK
			f.route = []
			f.mark = _pick_dedicated_target()

	# Modifiers last, so ability context sees the final personnel grouping.
	for i in offense.size():
		var sp: SimPlayer = offense[i]
		sp.engaged = false
		sp.stunned = 0.0
		sp.disrupted = 0.0
		sp.downed = 0.0
		sp.shed_cooldown = 0.0
		# Small per-blocker jitter: FIRST_CONTACT alone put every block's
		# first shed roll on the exact same instant, so once the defense had
		# any edge, blocks failed in clumps instead of one at a time - which
		# is what let two rushers come free simultaneously and overwhelm the
		# one spare blocker who could otherwise have picked either one up.
		sp.next_contact = FIRST_CONTACT + rng.randf_range(-0.2, 0.2)
		sp.tackle_cd = 0.0
		sp.has_ball = (sp.slot == "QB")
		sp.trail = PackedVector2Array([sp.pos])
		sp.dodge_used = false
		sp.carry_seconds = 0.0
		sp.pending_stat_gains.clear()
		sp.pending_events.clear()
		_apply_modifiers(sp, ctx)

	_out_of_position_penalty(offense_slot("QB"), "QB")
	_out_of_position_penalty(offense_slot("C"), "C")
	for i in 4:
		_out_of_position_penalty(offense_slot("T%d" % i), "T")
	for i in 5:
		_out_of_position_penalty(offense_slot("F%d" % i), str(slot_pos[i]))

	_apply_team_buffs()
	_apply_alignment_buffs()
	_apply_tier_buffs()


## "Right Side Coach"-style abilities (AbilityDB.right_side_buff): buffs the
## `count` flex players aligned furthest to the formation's right (largest
## lateral offset), regardless of who's actually holding the ability - he's
## usually a lineman, not a flex, coaching up whoever lines up out there.
func _apply_alignment_buffs() -> void:
	var source: SimPlayer = null
	for sp in offense:
		if not AbilityDB.right_side_buff(sp.data.ability_id).is_empty():
			source = sp
			break
	if source == null:
		return
	var buff := AbilityDB.right_side_buff(source.data.ability_id)
	var stat: String = String(buff.get("stat", ""))
	var amount: int = int(buff.get("amount", 0))
	var count: int = int(buff.get("count", 0))
	if stat == "" or amount == 0 or count <= 0:
		return
	var flexes := flex_players()
	flexes.sort_custom(func(a: SimPlayer, b: SimPlayer) -> bool: return a.target_pos.y > b.target_pos.y)
	for i in mini(count, flexes.size()):
		var f: SimPlayer = flexes[i]
		f.eff[stat] = clampi(f.stat(stat) + amount, 1, 15)


## "Veteran Mentor"-style abilities (AbilityDB.tier_buff): +amount to every
## stat for any teammate whose shop rarity tier is in the ability's list.
## Generated (non-shop) players are always quality 0 and never match.
func _apply_tier_buffs() -> void:
	for sp in offense:
		var buff := AbilityDB.tier_buff(sp.data.ability_id)
		if buff.is_empty():
			continue
		var qualities: Array = buff.get("qualities", [])
		var amount: int = int(buff.get("amount", 0))
		for other in offense:
			if other == sp or not qualities.has(other.data.quality):
				continue
			for stat in ["strength", "agility", "dexterity", "stamina", "intelligence"]:
				other.eff[stat] = clampi(other.stat(stat) + amount, 1, 15)


## Some abilities (e.g. a Center's "give all TEs +2 Int") buff every
## teammate at a given position rather than just the ability holder, so they
## get a second pass after individual snap modifiers and the out-of-position
## penalty are already baked into `eff`.
func _apply_team_buffs() -> void:
	for sp in offense:
		var buff := AbilityDB.team_buff(sp.data.ability_id)
		if buff.is_empty():
			continue
		var target_pos: PlayerData.Pos = buff["pos"]
		var stat: String = buff["stat"]
		var amount: int = buff["amount"]
		for other in offense:
			if other == sp or not _effective_positions(other.data).has(target_pos):
				continue
			other.eff[stat] = clampi(other.stat(stat) + amount, 1, 15)


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
		sp.aura_timer = 0.0
		sp.turned = false
		_apply_modifiers(sp, ctx)
		sp.reaction = maxf(0.15, 0.75 - float(sp.stat("intelligence")) * 0.035)

	# Front four always rush.
	var dl_offsets := [-4.6, -1.6, 1.6, 4.6]
	for i in 4:
		var d: SimPlayer = defense[i]
		d.target_pos = Vector2(los + 1.0, cy + dl_offsets[i])
		d.role = SimPlayer.Role.RUSH

	# Who is actually running a route? Anyone with evades_man_coverage is left
	# out entirely - no defender is ever assigned to man him up, though a
	# zone defender can still happen to be standing near him.
	var runners: Array[SimPlayer] = []
	for f in flex_players():
		if f.role == SimPlayer.Role.ROUTE and not AbilityDB.evades_man_coverage(f.data.ability_id):
			runners.append(f)
	runners.sort_custom(func(a, b): return absf(a.target_pos.y - cy) > absf(b.target_pos.y - cy))

	var zone_scheme := _zone_scheme_this_play
	var blitz := _blitz_this_play

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

	_apply_distraction()
	_apply_taunt()
	_apply_snap_push()
	_apply_curse()


## "Drive Block"-style abilities (AbilityDB.pushes_defense_at_snap): shoves
## every defender's presnap starting spot back this many yards. Only their
## starting point moves - man coverage recomputes off the receiver's actual
## position the instant the ball's live, so the cushion this buys erodes
## over the play exactly like a real off-the-ball push would, rather than
## permanently deepening anyone's zone.
func _apply_snap_push() -> void:
	var push := 0.0
	for sp in offense:
		push = maxf(push, AbilityDB.pushes_defense_at_snap(sp.data.ability_id))
	if push <= 0.0:
		return
	for d in defense:
		d.target_pos.x = minf(d.target_pos.x + push, FIELD_LEN - 1.0)


## "Corruption": curses the nearest defender to Paimon's own alignment spot
## at the snap - see SimPlayer.turned, _turned_logic.
func _apply_curse() -> void:
	var source: SimPlayer = null
	for sp in offense:
		if AbilityDB.curses_nearest_defender(sp.data.ability_id):
			source = sp
			break
	if source == null:
		return
	var best: SimPlayer = null
	var best_dist := 1e9
	for d in defense:
		var dist := d.target_pos.distance_to(source.target_pos)
		if dist < best_dist:
			best_dist = dist
			best = d
	if best != null:
		best.turned = true
		log_line("%s curses %s!" % [source.data.pname, best.data.pname])


## Any offensive player with distracts_defenders pulls the two defenders
## nearest his alignment out of focus for the play - a flat Intelligence
## penalty representing them keying on him instead of their real assignment.
func _apply_distraction() -> void:
	var source: SimPlayer = null
	for f in flex_players():
		if AbilityDB.distracts_defenders(f.data.ability_id):
			source = f
			break
	if source == null:
		return
	var by_dist := defense.duplicate()
	by_dist.sort_custom(func(a, b):
		return a.target_pos.distance_to(source.target_pos) < b.target_pos.distance_to(source.target_pos))
	for i in mini(2, by_dist.size()):
		var d: SimPlayer = by_dist[i]
		d.eff["intelligence"] = clampi(d.stat("intelligence") - 1, 1, 15)


## Any offensive player with taunts_defenders pulls the two defenders
## nearest his alignment out of position - a flat Strength penalty
## representing them chasing him instead of squaring up the real tackle.
func _apply_taunt() -> void:
	var source: SimPlayer = null
	for f in flex_players():
		if AbilityDB.taunts_defenders(f.data.ability_id):
			source = f
			break
	if source == null:
		return
	var by_dist := defense.duplicate()
	by_dist.sort_custom(func(a, b):
		return a.target_pos.distance_to(source.target_pos) < b.target_pos.distance_to(source.target_pos))
	for i in mini(2, by_dist.size()):
		var d: SimPlayer = by_dist[i]
		d.eff["strength"] = clampi(d.stat("strength") - 2, 1, 15)


## Route lines for the pre-snap preview, in yards.
func preview_routes() -> Array:
	var out: Array = []
	for f in flex_players():
		if f.role == SimPlayer.Role.ROUTE and not f.route.is_empty():
			var line := PackedVector2Array()
			line.append(f.target_pos)
			for wp in f.route:
				line.append(wp)
			out.append({"line": line, "kind": "route", "player": f,
				"auto": auto_route_ids.has(f.slot)})
		elif f.role == SimPlayer.Role.CARRY:
			var line2 := PackedVector2Array([f.target_pos,
				Vector2(los + 4.0, f.target_pos.y * 0.4 + FIELD_W * 0.3)])
			out.append({"line": line2, "kind": "carry", "player": f, "auto": false})
		else:
			out.append({"line": PackedVector2Array([f.target_pos]), "kind": "block",
				"player": f, "auto": false})
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
		if sp.role != SimPlayer.Role.QB and sp.role != SimPlayer.Role.BLOCK \
				and AbilityDB.dashes_at_snap(sp.data.ability_id):
			sp.pos.x = minf(sp.pos.x + 5.0, GOAL_LINE - 0.5)
		if sp.role == SimPlayer.Role.BLOCK and AbilityDB.locks_dl_at_snap(sp.data.ability_id):
			sp.mark = _closest_lineman(sp)
		sp.trail = PackedVector2Array([sp.pos])
	phase = Phase.LIVE
	time = 0.0


## Nearest defensive lineman to `sp`, for abilities that claim a block
## assignment instantly instead of waiting for the normal per-frame pass.
func _closest_lineman(sp: SimPlayer) -> SimPlayer:
	var best: SimPlayer = null
	var best_dist := 1e9
	for d in defense:
		if not d.slot.begins_with("DL"):
			continue
		var dist := sp.pos.distance_to(d.pos)
		if dist < best_dist:
			best_dist = dist
			best = d
	return best


func step(delta: float) -> void:
	if phase != Phase.LIVE:
		return
	time += delta
	_step_offense(delta)
	_step_defense(delta)
	_step_ball(delta)
	_step_contacts(delta)
	_clamp_inbounds()
	_record_trails()
	_check_dead()


## Nobody drifts out of bounds mid-play except the ball carrier, who is
## allowed to step out on his own terms to end the play (handled below in
## _check_dead). Receivers running routes, blockers, and coverage all stay
## on the field even when their target would carry them past the sideline.
func _clamp_inbounds() -> void:
	const MARGIN := 0.3
	for sp in offense:
		if sp == carrier:
			continue
		sp.pos.y = clampf(sp.pos.y, MARGIN, FIELD_W - MARGIN)
	for d in defense:
		d.pos.y = clampf(d.pos.y, MARGIN, FIELD_W - MARGIN)


func _record_trails() -> void:
	for sp in offense:
		if sp.trail.size() == 0 or sp.trail[sp.trail.size() - 1].distance_to(sp.pos) > 0.8:
			sp.trail.append(sp.pos)
			if sp.trail.size() > 60:
				sp.trail.remove_at(0)


# --- Offense ----------------------------------------------------------------

func _step_offense(delta: float) -> void:
	# "Combustion": a lit fuse that ends the play the instant it runs out,
	# checked before anything else moves this frame since there's no point
	# stepping a play that's about to be blown up anyway.
	if carrier != null:
		var fuse := AbilityDB.explodes_after_seconds(carrier.data.ability_id)
		if fuse > 0.0:
			carrier.carry_seconds += delta
			if carrier.carry_seconds >= fuse:
				_trigger_explosion(carrier)
				return

	# Blockers re-assert this every frame, so clear it once up front rather
	# than inside each defender's update (which ran after the contact pass).
	for d in defense:
		d.engaged = false
	_assign_blocks()
	for sp in offense:
		if sp.disrupted > 0.0:
			sp.disrupted -= delta
		if sp == carrier and sp.slot != "QB":
			# The route he was given gets first refusal - only once it is
			# used up does he become an ordinary ball carrier.
			if not _carry_route_logic(sp, delta):
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

	if planned_action == "handoff":
		var target := offense_slot(planned_handoff_slot) if planned_handoff_slot != "" else null
		if target != null and request_handoff(target):
			return
	elif planned_action == "scramble" and not qb_scrambling:
		request_scramble()

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

	# A drop is a plan, not a contract: a rusher already in his lap ends it
	# early and the QB starts looking for an answer. Without this he keeps
	# backpedalling into a sack he can see coming - survivable when a back
	# stayed in to help protect, ruinous now that all five receivers release.
	#
	# Bailing early is not a free pass, though: see `in_drop` below. The drop
	# is where sacks come from, and it has to stay that way.
	var in_drop := time < dropback
	if in_drop:
		var early := _closest_free_rusher(qb)
		if early == null or early.pos.distance_to(qb.pos) > PANIC_DIST:
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
	#
	# Everything here is much harder while he is still in his drop. Routes
	# have not developed, so the bar for a throw is high; there is nothing
	# downfield yet to throw it away past; and only a genuinely mobile QB can
	# get out of it. Anyone else wears the sack, which is what keeps a
	# collapsing pocket costly.
	if threat_dist < 2.3:
		var bar := 3.5 if in_drop else -3.0
		if best.get("player") != null and float(best.get("score", -99.0)) > bar:
			_throw(qb, best["player"])
		elif not in_drop and (hold_time > 0.4 or time > 1.2):
			_throwaway(qb)
		elif not in_drop or qb.stat("agility") >= SCRAMBLE_AGILITY:
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


## True if `sp` plays RB for handoff purposes - his real position, or an
## ability like "positionless" that counts him as one. See can_handoff_to
## and the Hand Off target picker in match.gd.
func plays_rb(sp: SimPlayer) -> bool:
	return _effective_positions(sp.data).has(PlayerData.Pos.RB)


## True if `sp` could be handed the ball right now - the QB still has it,
## `sp` plays RB, and he's standing close enough. Drives both a "Hand Off"
## plan firing (see request_handoff) and the pulsing "eligible" ring in
## field_view.gd.
func can_handoff_to(sp: SimPlayer) -> bool:
	if phase != Phase.LIVE or handoff_done:
		return false
	if carrier == null or carrier.slot != "QB" or not carrier.has_ball:
		return false
	if sp == null or not sp.is_offense or sp == carrier:
		return false
	if not plays_rb(sp):
		return false
	return sp.pos.distance_to(carrier.pos) <= HANDOFF_RANGE


## Arms (or, clicking the same target again, disarms) a "Hand Off" plan aimed
## at one specific flex, picked before the snap the same way a priority
## target is - see planned_handoff_slot. Always clears any armed Scramble,
## since the coach can only call one or the other for a given play.
func set_planned_handoff(slot: String) -> void:
	if planned_action == "handoff" and planned_handoff_slot == slot:
		planned_action = ""
		planned_handoff_slot = ""
	else:
		planned_action = "handoff"
		planned_handoff_slot = slot


## Arms (or, clicking the same one again, disarms) the "Scramble" plan - see
## `planned_action`. Always clears any armed Hand Off target.
func set_planned_action(action: String) -> void:
	if planned_action == action:
		planned_action = ""
	else:
		planned_action = action
	planned_handoff_slot = ""


## Hands off to `sp` right now - fired automatically by a "Hand Off" plan the
## instant its chosen target comes into range (as opposed to a called run
## play's automatic one - see _qb_logic/_carry_target). Returns false without
## effect if can_handoff_to(sp) no longer holds (e.g. the RB drifted out of
## range between frames).
func request_handoff(sp: SimPlayer) -> bool:
	if not can_handoff_to(sp):
		return false
	_do_handoff(carrier, sp)
	return true


## Triggers a scramble right now - fired automatically by a "Scramble" plan
## the instant the ball is snapped, using the same qb_scrambling flag
## _qb_logic already sets on its own under pressure. False without effect if
## the QB doesn't currently have the ball.
func request_scramble() -> bool:
	if phase != Phase.LIVE or carrier == null or carrier.slot != "QB" or not carrier.has_ball:
		return false
	if qb_scrambling:
		return false
	qb_scrambling = true
	log_line("%s takes off scrambling!" % carrier.data.pname)
	return true


func _do_handoff(qb: SimPlayer, rb: SimPlayer) -> void:
	handoff_done = true
	qb.has_ball = false
	rb.has_ball = true
	_set_carrier(rb)
	_trigger_pursuit()
	_apply_misdirection(rb)
	_block_for_handoff(rb)
	log_line("Handoff to %s." % rb.data.pname)


## Every other flex still running a route switches to blocking once the
## handoff happens, alongside the linemen who were already blocking by
## default - the existing block-assignment machinery (_assign_blocks/
## _is_threat's "defender near a non-QB carrier" branch) already treats
## nearby defenders as threats once someone besides the QB is carrying, so
## flipping their role is all that's needed for them to converge and seal
## the hole.
func _block_for_handoff(rb: SimPlayer) -> void:
	for f in flex_players():
		if f == rb:
			continue
		if f.role == SimPlayer.Role.ROUTE or f.role == SimPlayer.Role.CARRY:
			f.role = SimPlayer.Role.BLOCK
			f.mark = null


## Hands `sp` the ball and applies whatever ability triggers off of that -
## e.g. "power_surge" grants Strength the instant he becomes the carrier.
func _set_carrier(sp: SimPlayer) -> void:
	carrier = sp
	var bonus := AbilityDB.on_carry_bonus(sp.data.ability_id)
	for stat in bonus:
		var amount := int(bonus[stat])
		sp.eff[stat] = clampi(sp.stat(stat) + amount, 1, 15)
		_grant_stat_gain(sp, stat, amount)


## Abilities that specifically trigger on RECEIVING the ball (a catch, not a
## handoff) - "combustion"'s instant max Agility and "aftershock"'s
## earthquake. Called right after _set_carrier from both of _resolve_catch's
## success branches (the real catch and a "guardian_angel"-style save).
func _on_receive(sp: SimPlayer) -> void:
	if AbilityDB.max_agility_on_catch(sp.data.ability_id):
		var delta := 15 - sp.stat("agility")
		if delta > 0:
			sp.eff["agility"] = 15
			_grant_stat_gain(sp, "agility", delta)
	if AbilityDB.earthquake_on_catch(sp.data.ability_id):
		_trigger_earthquake(sp)


## "Aftershock": stuns every other player on the field for 1 second and
## queues one big shake, instead of the field_view's usual air-yards-scaled
## catch shake.
func _trigger_earthquake(sp: SimPlayer) -> void:
	big_shakes.append(1)
	for o in offense:
		if o != sp:
			o.stunned = maxf(o.stunned, 1.0)
	for d in defense:
		d.stunned = maxf(d.stunned, 1.0)
	log_line("%s TRIGGERS AN EARTHQUAKE!" % sp.data.pname)


## Queue one popup per point of `amount` (positive or negative) so the
## renderer can play them in quick succession rather than as one number.
func _grant_stat_gain(sp: SimPlayer, stat: String, amount: int) -> void:
	var sign_prefix := "-" if amount < 0 else ""
	for i in absi(amount):
		sp.pending_stat_gains.append(sign_prefix + stat)


## Queue a plain flavor-text popup (e.g. "DROP") - purely cosmetic, no effect
## on the play's outcome.
func _grant_event(sp: SimPlayer, text: String) -> void:
	sp.pending_events.append(text)


## A carrier with a misdirection-style ability can fool some defenders into
## still reading the play as if the QB has the ball, delaying when they
## start pursuing him for real.
func _apply_misdirection(rb: SimPlayer) -> void:
	var chance := AbilityDB.fake_chance(rb.data.ability_id)
	if chance <= 0.0:
		return
	for d in defense:
		if rng.randf() < chance:
			d.reaction += 0.6


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
		if AbilityDB.dedicated_blocker(sp.data.ability_id):
			# Locked onto his own pick for the whole play (see _align_offense
			# / _pick_dedicated_target) - never reassigned, and his target is
			# claimed so a normal blocker doesn't also get routed onto him.
			if sp.mark != null:
				claimed[sp.mark] = true
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
		# No rusher to pick up: hold the gap instead of drifting. This used to
		# aim 1 yard ahead of wherever he currently was, recomputed every
		# frame - since that target moves with him, he never arrived and just
		# crept downfield for as long as he stayed unmarked, sometimes tens
		# of yards over a long-developing play.
		sp.move_toward_point(sp.target_pos, delta, 0.4)
		return

	var d: SimPlayer = sp.mark
	# Aim for where the rusher is headed, not just where he is - a blocker
	# who only chases the defender's current position perpetually trails a
	# moving target and can never close the gap. This matters most for a
	# blocker picking up help duty on someone already in motion (e.g. after
	# the original blocker on him got shed), same problem _pursue_logic
	# already solves for defenders chasing the ball carrier.
	var lead_t := 0.0
	for i in 2:
		lead_t = sp.pos.distance_to(d.pos + d.vel * lead_t) / maxf(sp.speed(), 0.1)
		lead_t = clampf(lead_t, 0.0, 1.2)
	var predicted := d.pos + d.vel * lead_t
	# Stand in the gap between the defender and whoever has the ball.
	var to_protect := (protect_point - predicted)
	var stand := predicted + (to_protect.normalized() * 0.9 if to_protect.length() > 0.01 else Vector2(-0.9, 0.0))
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
	if _is_run_play() and (d.pos.x - los) < 9.0:
		return true
	# After a catch, the nearest defenders are worth blocking too.
	if carrier != null and carrier.slot != "QB":
		return d.pos.distance_to(carrier.pos) < 10.0
	return false


## The single highest-Strength defender who isn't a defensive lineman -
## what "Enforcer" (AbilityDB.dedicated_blocker) locks onto for the whole
## play, regardless of whether that defender is actually rushing. Reads
## base Strength (d.data), not the live per-play `eff` - this runs inside
## _align_offense, before _align_defense has necessarily populated `eff`
## for the play, and the pick shouldn't flap with a temporary modifier
## (an aura, an item) anyway.
func _pick_dedicated_target() -> SimPlayer:
	var best: SimPlayer = null
	var best_str := -1
	for d in defense:
		if d.slot.begins_with("DL"):
			continue
		var s := d.data.strength
		if s > best_str:
			best_str = s
			best = d
	return best


## A receiver who catches the ball keeps running the route the coach drew for
## him, and only turns into an ordinary ball carrier once it runs out. In a
## game about drawing routes the line should not evaporate the instant the
## ball arrives - a crosser you chalked to keep working across the field will
## now actually keep working across it after the catch.
##
## Waypoints that are not downfield of him are skipped: a curl or a comeback
## has him working BACK toward the QB, and finishing that with the ball in his
## hands would just lose yards. If nothing worth running is left, this returns
## false and the caller falls through to _carry_logic.
##
## There's deliberately no defender avoidance WHILE running a given leg - he
## runs the line he was given, and drawing a route through traffic is
## supposed to cost you. The one exception is a waypoint that would run him
## flat into a defender already standing right on top of it (some flex spots'
## stock/drawn routes do this) - that one waypoint gets skipped just like an
## already-passed one, handing him off to the avoidance-aware _carry_logic
## instead of threading him into a tackle for free.
func _carry_route_logic(sp: SimPlayer, delta: float) -> bool:
	if sp.role != SimPlayer.Role.ROUTE:
		return false

	while sp.route_idx < sp.route.size() \
			and (sp.route[sp.route_idx].x <= sp.pos.x + CARRY_ROUTE_MIN_GAIN
				or _nearest_defender_dist_to(sp.route[sp.route_idx]) < CARRY_ROUTE_ABORT_DIST):
		sp.route_idx += 1
	if sp.route_idx >= sp.route.size():
		sp.route_done = true
		return false

	var target: Vector2 = sp.route[sp.route_idx]
	# Same effort as _carry_logic: running with the ball is a touch slower.
	sp.move_toward_point(target, delta, 0.92)
	if sp.pos.distance_to(target) < CARRY_ROUTE_ARRIVE:
		sp.route_idx += 1
		if sp.route_idx >= sp.route.size():
			sp.route_done = true
	return true


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
		if priority_targets.has(f.slot):
			score += PRIORITY_TARGET_BONUS
		if score > float(best["score"]):
			best = {"player": f, "score": score}
	return best


func _nearest_defender_dist(sp: SimPlayer) -> float:
	return _nearest_defender_dist_to(sp.pos)


func _nearest_defender_dist_to(point: Vector2) -> float:
	var best := 99.0
	for d in defense:
		best = minf(best, d.pos.distance_to(point))
	return best


## Butter Fingers' Dexterity penalty for anyone standing within
## AuraDB.BUTTER_FINGERS_RADIUS yards of `pos` - applied directly at the two
## points Dexterity actually matters (see _throw, _resolve_catch) rather than
## by mutating eff dictionaries, so there's no baseline to snapshot/restore.
func _butter_fingers_penalty(pos: Vector2) -> int:
	for d in defense:
		if d.data.aura_id == AuraDB.BUTTER_FINGERS and d.pos.distance_to(pos) <= AuraDB.BUTTER_FINGERS_RADIUS:
			return AuraDB.BUTTER_FINGERS_DEX_PENALTY
	return 0


## Whoever's currently least covered - what the Mind Reader aura targets
## instead of his assigned man/zone. Same "openness" measure _evaluate_targets
## uses for the QB, just read from the defense's side of the ball.
func _most_open_receiver() -> SimPlayer:
	var best: SimPlayer = null
	var best_open := -1.0
	for f in flex_players():
		if f.role != SimPlayer.Role.ROUTE and f.role != SimPlayer.Role.CARRY:
			continue
		if f == carrier:
			continue
		var openness := _nearest_defender_dist(f)
		if openness > best_open:
			best_open = openness
			best = f
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
	# Butter Fingers' Dexterity penalty, expressed directly as the accuracy
	# hit it would cause - same 0.045-per-point coefficient as the term above.
	acc += float(_butter_fingers_penalty(qb.pos)) * 0.045
	var pressure := _closest_free_rusher(qb)
	if pressure != null and pressure.pos.distance_to(qb.pos) < 3.5:
		acc += 0.7
	acc *= lerpf(1.35, 1.0, clampf(qb.energy, 0.0, 1.0))
	if AbilityDB.perfect_aim(qb.data.ability_id):
		acc = 0.0
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
	_last_passer = qb
	# The passer_dex_bonus itself is applied in _resolve_catch, not here -
	# it should land the moment the ball actually reaches the receiver, not
	# the instant it leaves the QB's hand.
	_trigger_pursuit()
	log_line("%s throws to %s." % [qb.data.pname, target.data.pname])

	# "Gunslinger Growth": a permanent Dexterity gain (not a per-play eff
	# bonus - see AbilityDB.dex_per_throw_yards) based on how far downfield
	# this throw was aimed, whether or not it's actually completed.
	var growth_rate := AbilityDB.dex_per_throw_yards(qb.data.ability_id)
	if growth_rate > 0.0:
		var air_yards := maxf(0.0, aim.x - los)
		var gain := int(floor(air_yards * growth_rate))
		if gain > 0:
			qb.data.add_stat("dexterity", gain)
			_grant_stat_gain(qb, "dexterity", gain)


func _throwaway(qb: SimPlayer) -> void:
	ball_from = qb.pos
	ball_to = Vector2(los + 12.0, -3.0 if rng.randf() < 0.5 else FIELD_W + 3.0)
	ball_air_time = 0.9
	ball_t = 0.0
	ball_in_air = true
	qb.has_ball = false
	carrier = null
	thrown_to = null
	_last_passer = qb
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
		d.aura_timer += delta
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

		# "Corruption": a cursed defender blocks for the offense instead of
		# running his own assignment - skips the normal role dispatch (and
		# the pursuit-role-flip below) entirely.
		if d.turned:
			_turned_logic(d, delta)
			continue

		if pursuit_triggered and carrier != null:
			d.reaction -= delta
			if d.reaction <= 0.0 and d.role != SimPlayer.Role.RUSH:
				d.role = SimPlayer.Role.PURSUE

		# Coverage players who can reach the throw attack the catch point.
		if ball_in_air and d.role != SimPlayer.Role.RUSH:
			if d.pos.distance_to(ball_to) < 16.0:
				d.move_toward_point(ball_to, delta, 1.0)
				continue

		# Mind Reader ignores his assigned man/zone and beelines for whoever's
		# actually most open, the same way the QB reads the field - see
		# _most_open_receiver.
		if d.data.aura_id == AuraDB.MIND_READER and d.role != SimPlayer.Role.RUSH:
			var target := _most_open_receiver()
			if target != null:
				d.move_toward_point(target.pos, delta, 1.0)
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
	var target := _rush_target(d)
	if d.engaged:
		# Fighting through a block: heavy speed penalty until the shed roll wins.
		d.move_toward_point(target, delta, 0.20)
	else:
		d.move_toward_point(target, delta, 1.0)


## Where a rushing defender (front four, or a blitzing linebacker) is
## currently converging on. He was bearing down on the quarterback before
## the snap and has no special knowledge the instant the ball changes hands
## (a handoff, a scramble) - only once his own reaction delay has actually
## run out (the same Intelligence-scaled timer _step_defense uses to flip a
## MAN/ZONE defender into PURSUE, reset by _trigger_pursuit and stretched by
## a misdirection-style ability - see _apply_misdirection) does he start
## tracking the real ball carrier instead of still crashing the mesh point.
## Without this a defensive lineman - who is already right on top of the
## backfield by design - retargeted onto the runner with zero delay, making
## every handoff instantly stuffed regardless of any fake.
func _rush_target(d: SimPlayer) -> Vector2:
	if carrier == null:
		return ball_pos
	if carrier.slot == "QB" or d.reaction <= 0.0:
		return carrier.pos
	var qb := offense_slot("QB")
	return qb.pos if qb != null else carrier.pos


## "Corruption": a cursed defender (SimPlayer.turned) closes on whichever
## OTHER defender is currently nearest the ball carrier's protect point and
## briefly stuns him on contact - a stand-in for "blocks for your team"
## that doesn't require restructuring the offense/defense arrays to let a
## defense-side entity actually throw a real block.
func _turned_logic(d: SimPlayer, delta: float) -> void:
	var protect_point := carrier.pos if carrier != null else Vector2(los - 5.0, FIELD_W * 0.5)
	var target: SimPlayer = null
	var best_dist := 1e9
	for other in defense:
		if other == d or other.turned:
			continue
		var dist := other.pos.distance_to(protect_point)
		if dist < best_dist:
			best_dist = dist
			target = other
	if target == null:
		d.hold(delta)
		return
	d.move_toward_point(target.pos, delta, 1.0)
	if d.pos.distance_to(target.pos) < 1.8:
		target.stunned = maxf(target.stunned, 0.5)


func _man_logic(d: SimPlayer, delta: float) -> void:
	if d.mark == null:
		_zone_logic(d, delta)
		return
	var r: SimPlayer = d.mark
	if time < AbilityDB.cloak_seconds(r.data.ability_id):
		d.hold(delta)
		return
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
	if spot.y < 0.0 or spot.y > FIELD_W:
		# A ball that lands out of bounds is incomplete no matter where the
		# receiver's feet are - nobody can legally catch it there.
		_end_play({"kind": "incomplete", "yards": 0.0, "text": "Pass sails out of bounds."})
		return
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

	# The ball has actually reached the receiver now, so this is where a
	# passer's on-target ability (e.g. "trusted_target_wr") lands, not the
	# instant it was thrown.
	var qb := offense_slot("QB")
	if qb != null:
		var dex_bonus := AbilityDB.passer_dex_bonus(qb.data.ability_id, rec.data.pos)
		if dex_bonus != 0:
			rec.eff["dexterity"] = clampi(rec.stat("dexterity") + dex_bonus, 1, 15)
			_grant_stat_gain(rec, "dexterity", dex_bonus)

	# Air yards, not straight-line QB-to-target distance: a receiver split
	# wide on a short out is a short, safe throw even though he might be 20
	# yards from the QB laterally.
	var air_yards := maxf(0.0, spot.x - los)
	var p := rec.catch_chance_base(air_yards)
	p += AbilityDB.catch_mod(rec.data.ability_id, ctx)
	p += ItemDB.catch_mod(rec.data.item_id)
	# Kept deliberately small: the distance/Dexterity curve above is the
	# design contract, and heavy coverage penalties on top of it made every
	# covered pass a drop regardless of how the curve was tuned.
	p -= 0.11 * clampf(1.0 - def_dist / 2.6, 0.0, 1.0)
	p -= clampf((rec_dist - 1.8) * 0.07, 0.0, 0.11)
	# Butter Fingers' Dexterity penalty, same 0.015-per-point coefficient
	# catch_chance_base uses internally for Dexterity.
	p -= float(_butter_fingers_penalty(rec.pos)) * 0.015
	p = clampf(p, 0.03, 0.97)
	if AbilityDB.guarantees_catch(rec.data.ability_id):
		p = 1.0

	if rng.randf() < p:
		rec.has_ball = true
		catch_x = spot.x
		catch_shakes.append(air_yards)
		_set_carrier(rec)
		_on_receive(rec)
		thrown_to = null
		_pass_completed_this_play = true
		_last_completion_target = rec
		rec.pos = rec.pos.lerp(spot, 0.6)
		var bucks := 5
		var msg := "%s hauls it in." % rec.data.pname
		if contested:
			bucks = 15
			msg = "%s makes a contested grab!" % rec.data.pname
		_award(bucks, msg)
		_trigger_pursuit()
	else:
		var savior := _find_catch_savior(rec)
		if savior != null:
			savior.pos = spot
			savior.has_ball = true
			catch_x = spot.x
			catch_shakes.append(air_yards)
			_set_carrier(savior)
			_on_receive(savior)
			thrown_to = null
			_pass_completed_this_play = true
			_last_completion_target = savior
			_award(20, "%s swoops in and steals the catch away from %s!" % [savior.data.pname, rec.data.pname])
			_trigger_pursuit()
			return
		if def_dist < 1.4:
			var int_chance := 0.05 + float(def_near.stat("dexterity")) * 0.006
			if rng.randf() < int_chance:
				_interception(def_near)
				return
		_grant_event(rec, "DROP")
		_end_play({
			"kind": "incomplete",
			"yards": 0.0,
			"text": "%s cannot hang on." % rec.data.pname,
		})


## A teammate with "guardian_angel" (must be running a live route himself,
## not blocking or already down) swaps in for a receiver about to drop a
## catchable ball and hauls it in instead.
func _find_catch_savior(rec: SimPlayer) -> SimPlayer:
	for f in flex_players():
		if f == rec or f.role != SimPlayer.Role.ROUTE:
			continue
		if f.downed > 0.0 or f.stunned > 0.0:
			continue
		if AbilityDB.catches_drops(f.data.ability_id):
			return f
	return null


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
		if _is_run_play():
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
		var shed := false
		if d.data.aura_id == AuraDB.STRONGMAN:
			# Strongman always wins the shed; the interval before he can do it
			# again (if a fresh blocker picks him up) shrinks with his
			# Strength edge instead of the normal probabilistic roll.
			shed = true
			var diff := float(d.stat("strength") - b.stat("strength"))
			b.next_contact = clampf(
				AuraDB.STRONGMAN_BASE_INTERVAL - diff * AuraDB.STRONGMAN_INTERVAL_PER_STR,
				AuraDB.STRONGMAN_MIN_INTERVAL, AuraDB.STRONGMAN_BASE_INTERVAL)
		else:
			shed = _contact_roll(d, b, "block")
		if shed:
			b.engaged = false
			b.shed_cooldown = SHED_COOLDOWN
			b.mark = null
			d.free_timer = FREE_RUSH_TIME

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
			d.mark.disrupted = 1.1 * AbilityDB.disrupted_mult(d.mark.data.ability_id)

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

		if AbilityDB.dodges_once(carrier.data.ability_id) and not carrier.dodge_used:
			carrier.dodge_used = true
			carrier.eff["agility"] = clampi(carrier.stat("agility") - 5, 1, 15)
			_grant_stat_gain(carrier, "agility", -5)
			carrier.vel *= 0.92
			_award(10, "%s dashes right past %s!" % [carrier.data.pname, d.data.pname])
			continue

		var chance := 0.88 + float(d.stat("strength") - carrier.stat("strength")) * 0.020
		chance -= AbilityDB.contact_mod(carrier.data.ability_id, "carry")
		chance -= ItemDB.contact_mod(carrier.data.item_id, "carry")
		if d.data.aura_id == AuraDB.BIG_BLOCKER:
			chance += AuraDB.BIG_BLOCKER_TACKLE_BONUS
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
	# Contact resolution runs after movement each frame, so a receiver who
	# already crossed the goal line this same frame can still reach here
	# before _check_dead gets a look at him. Once he's past the plane with
	# the ball it's a touchdown no matter what happens a moment later - a
	# tackle can't retroactively undo it.
	if carrier.pos.x >= GOAL_LINE:
		_end_play({
			"kind": "touchdown",
			"yards": GOAL_LINE - los,
			"td": true,
			"text": "TOUCHDOWN, %s!" % carrier.data.pname,
		})
		return
	carrier.downed = 0.0001
	var end_x := carrier.pos.x
	var is_sack := carrier.slot == "QB" and not qb_scrambling and not _play_was_a_run()
	var kind := "sack" if is_sack else ("run" if _play_was_a_run() else "complete")
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
				"kind": "run" if _play_was_a_run() else "complete",
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


## "Combustion"'s fuse running out - ends the play on the spot, same as an
## ordinary tackle (the drive continues normally), with a bigger shake than
## an ordinary catch.
func _trigger_explosion(sp: SimPlayer) -> void:
	big_shakes.append(1)
	_end_play({
		"kind": "explosion",
		"yards": sp.pos.x - los,
		"text": "%s COULDN'T CONTAIN THE CURSE AND EXPLODES!" % sp.data.pname,
	})


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
	_credit_game_stats(res)
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

	if not _team_blocks_stat_loss():
		for sp in offense:
			if AbilityDB.decaying_stat_start(sp.data.ability_id) > 0:
				sp.stat_decay += 1

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
		planned_action = ""
		planned_handoff_slot = ""

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
