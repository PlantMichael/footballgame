extends Node

## Autoload. Owns everything that persists across a run: roster, lineup,
## drawn routes, inventory, football bucks, and where you are on the run map.

signal bucks_changed(new_total: int)
signal roster_changed()

const SLOT_ORDER := ["QB", "C", "T0", "T1", "T2", "T3", "F0", "F1", "F2", "F3", "F4"]
## The kicker's slot. Optional and not one of the 11 in SLOT_ORDER: he only
## comes on when the coach calls a kick (MatchSim.kick_mode), and a lineup
## without one is still valid - you just can't kick.
const KICKER_SLOT := "K"
## The 4 build-up difficulty tiers. A run's matches are stops on the map (see
## "The run map" below); each match row plays at the next tier, and the bowl
## row at a 5th. `bracket` holds those 5 tiers - quality, drives, a label -
## and is what the tools/ harnesses drive the sim off directly. The bowl
## tier's name comes from whichever bowl the coach heads for (BowlDB).
const ROUND_NAMES := ["Wild Card", "Divisional", "Conference", "Semifinal"]
const DRIVES_PER_MATCH := [4, 4, 5, 5, 5]

## Rosters start in the 2-4 stat band, so the whole difficulty scale sits low
## and climbs slowly. The shop ramps faster than the bracket on purpose.
const ROUND_ONE_QUALITY := 2.8
const QUALITY_PER_ROUND := 0.7

## A loss no longer ends the run outright: you get MAX_LOSSES total across
## the whole run before the season is over. A loss that doesn't end the run
## costs you a life and no win bonus, and you still move on along the map -
## see _apply_loss for anything further it should cost.
const MAX_LOSSES := 3
var losses: int = 0

## Total matches played this run, wins and losses both counting. Defenses get
## a little tougher with every one of them on top of the per-tier ramp.
const MATCH_QUALITY_STEP := 0.15
var matches_played: int = 0

## Weather for the next match (WeatherDB id). Always clear for a run's first
## match; rolled in finish_match for each one after, so the map screen can
## show the forecast - and a mystery event can override it. Dev mode changes
## it from the match screen.
var next_weather: String = WeatherDB.CLEAR

## How many times the Ritual Site has been used this run. The sacrifice cost
## escalates with it (see RitualSite.SACRIFICE_COUNT) - 2 players the first
## visit, 3 the next, and so on - so repeat trips for cursed players cost
## progressively more of the roster instead of staying a flat, repeatable
## trade.
var rituals_completed: int = 0


var rng := RandomNumberGenerator.new()

var team_name: String = "Your Team"
var bucks: int = 0
var roster: Array[PlayerData] = []
var lineup: Dictionary = {}             # slot name -> roster index
var inventory: Array[String] = []       # unequipped item ids
var round_index: int = 0
var bracket: Array = []                 # Array[Dictionary] opponent info
var run_active: bool = false
var last_result: Dictionary = {}        # filled in by the match scene

## Which QBDB entry is leading this run (-1 if a fully-generated QB, no fixed
## pick). Stashed here rather than only applied transiently so a bowl win can
## credit the completion mark to the right QB - see MetaState.award_mark.
var qb_id: int = -1

## The bowl this run is playing for (BowlDB id) - set once the coach picks a
## bowl stop on the map, "" until then.
var chosen_bowl: String = ""

## The chalk. Flex slot name ("F0".."F4") -> Array of Vector2 waypoints,
## relative to that player's alignment (see RouteBook). A slot missing from
## here is one the coach never drew: MatchSim gives him a random stock route
## instead, rerolled every snap. Routes persist between snaps and between
## matches for the whole run, so a concept you like stays on the board until
## you wipe it.
var drawn_routes: Dictionary = {}

## An endless scrimmage with every player, item, and play unlocked and no
## bracket/economy pressure - for tuning and ability testing. See
## start_dev_mode and MatchSim.regenerate_defense (the live difficulty slider
## on the match screen's play-call bar).
var dev_mode: bool = false
const DEV_ROSTER_QUALITY := 13.0
const DEV_DEFENSE_QUALITY := 8.0
## Flat, high odds in dev mode so every one of the 5 defender auras is
## actually reachable for testing without grinding a real run deep. See
## aura_chance below.
const DEV_AURA_CHANCE := 0.35
## A drive count high enough that "last drive" logic (match.gd, MatchSim)
## never actually triggers in a real testing session - simplest way to get
## "infinite drives" without a separate flag threaded through both.
const DEV_DRIVES := 999999


func _ready() -> void:
	rng.randomize()


## `qb_id` is an index into QBDB.QUARTERBACKS; -1 leaves the starting QB
## procedurally generated, same as before the QB-select screen existed.
func new_run(seed_value: int = 0, qb_id: int = -1) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()

	dev_mode = false
	self.qb_id = qb_id
	team_name = Generator.team_name(rng)
	bucks = 150
	roster.assign(Generator.starting_roster(rng))
	if qb_id >= 0:
		_apply_chosen_qb(qb_id)
	drawn_routes.clear()
	inventory.assign(["stickum_gloves", "lead_vest"])
	bought_shop_players.clear()
	bought_items.clear()
	shop_stock = {}
	round_index = 0
	losses = 0
	matches_played = 0
	next_weather = WeatherDB.CLEAR
	rituals_completed = 0
	next_match_mods = {}
	run_active = true
	last_result = {}
	_build_bracket()
	_build_map()
	auto_fill_lineup()
	roster_changed.emit()
	bucks_changed.emit(bucks)


## Sets up an endless scrimmage: a maxed-out generated roster plus every
## hardcoded shop player (so their unique abilities are testable too), every
## item, and every play, all unlocked at once. No bracket, no losses, no
## shop economy - match.gd routes straight past the hub into match.tscn.
func start_dev_mode() -> void:
	rng.randomize()
	dev_mode = true
	team_name = "Dev Squad"
	bucks = 999999
	roster.assign(Generator.full_roster(rng, DEV_ROSTER_QUALITY))
	for p in ShopPlayerDB.all_players(rng):
		roster.append(p)
		_ensure_unique_number(p)
	# The Laboratory's Oddities too - their abilities are just as untestable
	# without a lucky 200-yard game otherwise.
	for oddity_name in OddityPlayerDB.all_names():
		var oddity := OddityPlayerDB.make_named(rng, oddity_name)
		roster.append(oddity)
		_ensure_unique_number(oddity)
	drawn_routes.clear()
	inventory.assign(ItemDB.all_ids())
	round_index = 0
	losses = 0
	matches_played = 0
	next_weather = WeatherDB.CLEAR
	rituals_completed = 0
	next_match_mods = {}
	run_map.clear()
	map_row = -1
	map_col = -1
	target_row = -1
	target_col = -1
	run_complete = false
	bowl_won = false
	chosen_bowl = ""
	run_active = true
	last_result = {}
	bracket = [{
		"name": "Practice Squad", "round": "Scrimmage",
		"quality": DEV_DEFENSE_QUALITY, "drives": DEV_DRIVES, "result": "",
	}]
	auto_fill_lineup()
	roster_changed.emit()
	bucks_changed.emit(bucks)


## Swap the chosen QBDB pick in for the first generated QB on the roster,
## leaving the backup QB procedurally generated.
func _apply_chosen_qb(qb_id: int) -> void:
	for i in roster.size():
		if roster[i].pos == PlayerData.Pos.QB:
			var picked := QBDB.make_player(rng, qb_id)
			roster[i] = picked
			_ensure_unique_number(picked)
			return


func _build_bracket() -> void:
	bracket.clear()
	chosen_bowl = ""
	for i in ROUND_NAMES.size():
		# Opponent quality climbs from a soft opener to a real title team.
		# The ramp is deliberately gentler than the shop's draft ramp: the sim
		# is very sensitive near parity, so a coach who keeps signing upgrades
		# stays ahead while one who hoards bucks gets run over by round three.
		var quality := ROUND_ONE_QUALITY + float(i) * QUALITY_PER_ROUND
		bracket.append({
			"name": Generator.team_name(rng),
			"round": ROUND_NAMES[i],
			"quality": quality,
			"drives": DRIVES_PER_MATCH[i],
			"result": "",
		})
	# The bowl tier. Each bowl stop on the map scales this by its own
	# BowlDB.quality_mult - see _make_opponent.
	var bowl_index := ROUND_NAMES.size()
	bracket.append({
		"name": Generator.team_name(rng),
		"round": "The Bowl",
		"quality": ROUND_ONE_QUALITY + float(bowl_index) * QUALITY_PER_ROUND,
		"drives": DRIVES_PER_MATCH[bowl_index],
		"result": "",
		"bowl_id": "",
	})


## The opponent about to be (or being) played: the match stop picked on the
## map (select_match), or - with none picked, as in dev mode and the tools/
## harnesses - the bracket tier at round_index.
func current_opponent() -> Dictionary:
	var node := target_node()
	if not node.is_empty():
		return node.get("opponent", {})
	if round_index < bracket.size():
		return bracket[round_index]
	return {}


## The opponent quality to actually build a match's defense with: the
## round's base quality, plus a step for every match already played this
## run, plus a bump if the coach's own roster has outpaced that ramp (see
## _difficulty_overshoot) - a stacked lineup keeps facing a defense sized to
## match it instead of stomping whatever round-based quality was expected of
## a rookie roster at this point in the run.
const ROSTER_OVERSHOOT_WEIGHT := 0.6

func current_match_quality() -> float:
	return quality_against(current_opponent())


## current_match_quality for any opponent dict - the map screen previews each
## match stop's difficulty with this before one is picked. "tier_quality" is
## the plain tier's quality (no Elite/bowl bump), which the roster overshoot
## is measured against.
func quality_against(opp: Dictionary) -> float:
	var base := float(opp.get("quality", 3.0)) + float(matches_played) * MATCH_QUALITY_STEP
	var tier_q := float(opp.get("tier_quality", opp.get("quality", ROUND_ONE_QUALITY)))
	var overshoot := maxf(0.0, roster_power() - tier_q)
	return base + overshoot * ROSTER_OVERSHOOT_WEIGHT + star_excess() * STAR_WEIGHT


## Average PlayerData.overall() of the 11 starters, on the same rough 1-15
## scale as the "quality" knob Generator builds a defense from. 0.0 if the
## lineup isn't even filled out yet.
func roster_overall() -> float:
	var total := 0
	var counted := 0
	for slot in SLOT_ORDER:
		var p := player_at(slot)
		if p != null:
			total += p.overall()
			counted += 1
	if counted == 0:
		return 0.0
	return float(total) / float(counted)


## A starter's rating for difficulty purposes: overall plus a bump for rarity
## tier - an All-Star's or cursed player's ability is worth far more than his
## raw stat line.
const TIER_POWER := {0: 0.0, 1: 0.0, 2: 0.5, 3: 1.5, 4: 3.0, 5: 3.0}

func _starter_ratings() -> Array[float]:
	var ratings: Array[float] = []
	for slot in SLOT_ORDER:
		var p := player_at(slot)
		if p != null:
			ratings.append(float(p.overall()) + float(TIER_POWER.get(p.quality, 0.0)))
	return ratings


## The lineup's average rating (see _starter_ratings).
func roster_power() -> float:
	var ratings := _starter_ratings()
	if ratings.is_empty():
		return 0.0
	var total := 0.0
	for r in ratings:
		total += r
	return total / float(ratings.size())


## How far the lineup's standouts tower over the rest of it: every starter's
## rating past the lineup average by more than STAR_SLACK (the spread any
## ordinary roster has), summed. Added to the defense's quality on top of
## everything else - never netted against a roster that's behind the round's
## ramp - so one superstar among rookies makes every match of the run
## tougher, the bowl included, instead of only the early rounds.
const STAR_WEIGHT := 0.18
const STAR_SLACK := 1.5

func star_excess() -> float:
	var avg := roster_power()
	var excess := 0.0
	for r in _starter_ratings():
		excess += maxf(0.0, r - avg - STAR_SLACK)
	return excess


## How far the roster's actual strength has pulled ahead of the round's own
## base quality ramp - 0 for a roster that's still on curve (rookies, or
## just keeping pace round to round), positive once a signing outpaces it.
## Drives both current_match_quality and aura_count.
func _difficulty_overshoot() -> float:
	var opp := current_opponent()
	var base := float(opp.get("tier_quality", opp.get("quality", ROUND_ONE_QUALITY)))
	return maxf(0.0, roster_power() - base)


## True once the bowl at the end of the map has been played, won or lost.
func is_run_over() -> bool:
	return run_complete


## How many defenders spawn with a colored aura (AuraDB) this match. The
## base chance for the first climbs with how deep into the run you are;
## each additional one on top of that is driven purely by the roster
## overshoot, so a coach who stomps early with a stacked lineup runs into
## two or three buffed defenders instead of the usual at-most-one. Dev mode
## gets a flat, high odds at exactly one instead, so every aura stays
## reachable without grinding a real run deep.
const AURA_CHANCE_BASE := 0.22
const AURA_CHANCE_PER_MATCH := 0.07
const AURA_CHANCE_MAX := 0.8
const AURA_OVERSHOOT_PER_POINT := 0.03
const MAX_AURAS := 3

func aura_count(rng_src: RandomNumberGenerator) -> int:
	if dev_mode:
		return 1 if rng_src.randf() < DEV_AURA_CHANCE else 0
	var chance := clampf(
		AURA_CHANCE_BASE + float(matches_played) * AURA_CHANCE_PER_MATCH
			+ (_difficulty_overshoot() + star_excess() * STAR_WEIGHT) * AURA_OVERSHOOT_PER_POINT,
		0.0, AURA_CHANCE_MAX)
	var count := 0
	for i in MAX_AURAS:
		if rng_src.randf() < chance:
			count += 1
		chance *= 0.5   # each additional aura is noticeably less likely than the last
	return count


func add_bucks(amount: int) -> void:
	bucks += amount
	bucks_changed.emit(bucks)


func spend_bucks(amount: int) -> bool:
	if bucks < amount:
		return false
	bucks -= amount
	bucks_changed.emit(bucks)
	return true


# --- Lineup -----------------------------------------------------------------

func player_at(slot: String) -> PlayerData:
	if not lineup.has(slot):
		return null
	var idx: int = lineup[slot]
	if idx < 0 or idx >= roster.size():
		return null
	return roster[idx]


func slot_kind(slot: String) -> String:
	if slot.begins_with("T"):
		return "T"
	if slot.begins_with("F"):
		return "FLEX"
	return slot


## Left tackle/guard, right guard/tackle instead of the internal T0-T3 -
## purely cosmetic, matching the left-to-right lateral order MatchSim
## already lines them up in (_align_offense's tackle_offsets). Gameplay is
## unaffected: a T can still fill any of the 4 slots.
const TACKLE_LABELS := {"T0": "LT", "T1": "LG", "T2": "RG", "T3": "RT"}

func slot_label(slot: String) -> String:
	return TACKLE_LABELS.get(slot, slot)


## True when this roster index is already used by a different slot.
func is_starting(idx: int, except_slot: String = "") -> bool:
	for slot in lineup.keys():
		if slot == except_slot:
			continue
		if lineup[slot] == idx:
			return true
	return false


## True if this roster player is allowed to fill this slot at all: Tackles
## only in the four T slots, the Center only at C, the QB only at QB, and
## RB/WR/TE only in the five FLEX slots.
func fits_slot(idx: int, slot: String) -> bool:
	if idx < 0 or idx >= roster.size():
		return false
	var p: PlayerData = roster[idx]
	return p.natural_slot_kind() == slot_kind(slot)


func set_slot(slot: String, idx: int) -> bool:
	if not fits_slot(idx, slot):
		return false

	# Who is losing this slot, and are they actually being benched rather
	# than just swapping into the incoming player's old spot?
	var displaced := -1
	if lineup.has(slot) and lineup[slot] != idx:
		displaced = lineup[slot]
	var swapped := false

	# A player can only be in one slot; swap if they are already elsewhere.
	for other in lineup.keys():
		if other != slot and lineup[other] == idx:
			if lineup.has(slot):
				lineup[other] = lineup[slot]
				swapped = true
			else:
				lineup.erase(other)
			break
	lineup[slot] = idx

	# A generated rookie who has just been benched by a signed player is cut
	# outright rather than left cluttering the bench - he was only ever a
	# placeholder until you could afford somebody real. Only applies when he
	# is genuinely displaced: a straight swap moves him to another slot, and
	# one default replacing another is just a lineup change.
	if not swapped and displaced >= 0 and _is_default(displaced) and not _is_default(idx):
		cut_player(displaced)
		return true

	roster_changed.emit()
	return true


## A procedurally generated starter, as opposed to somebody signed from the
## shop. PlayerData.quality is 0 for generated players and 1-4 for the
## hardcoded shop roster.
func _is_default(idx: int) -> bool:
	if idx < 0 or idx >= roster.size():
		return false
	return roster[idx].quality == 0


func auto_fill_lineup() -> void:
	lineup.clear()
	var used := {}

	for slot in SLOT_ORDER + [KICKER_SLOT]:
		var kind := slot_kind(slot)
		var best := -1
		var best_score := -1.0
		for i in roster.size():
			if used.has(i):
				continue
			var p: PlayerData = roster[i]
			if p.natural_slot_kind() != kind:
				continue
			var score := float(p.overall())
			if score > best_score:
				best_score = score
				best = i
		if best >= 0:
			lineup[slot] = best
			used[best] = true
	roster_changed.emit()


func lineup_is_valid() -> bool:
	for slot in SLOT_ORDER:
		if player_at(slot) == null:
			return false
	return true


## The kicker in the K slot, or null if there isn't one.
func kicker() -> PlayerData:
	return player_at(KICKER_SLOT)


func starters() -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for slot in SLOT_ORDER:
		out.append(player_at(slot))
	return out


# --- Drawn routes -----------------------------------------------------------

func route_for(slot: String) -> Array:
	return drawn_routes.get(slot, [])


func has_route(slot: String) -> bool:
	return drawn_routes.has(slot) and not drawn_routes[slot].is_empty()


## `route` is waypoints relative to the alignment spot, already truncated to
## RouteBook.BUDGET_YARDS by whoever drew it. An empty route clears the slot
## back to "auto".
func set_route(slot: String, route: Array) -> void:
	if route.is_empty():
		drawn_routes.erase(slot)
	else:
		drawn_routes[slot] = route


func clear_routes() -> void:
	drawn_routes.clear()


# --- Items ------------------------------------------------------------------

## Puts `item_id` from the bag on roster player `roster_index`, in the slot
## for its category (ItemDB.slot_for) - a player wears one helmet, one pair
## of gloves and one pair of cleats. Whatever he had in that slot goes back
## in the bag.
func equip_item(item_id: String, roster_index: int) -> void:
	if roster_index < 0 or roster_index >= roster.size():
		return
	var slot_index := ItemDB.slot_for(item_id)
	if slot_index < 0 or not inventory.has(item_id):
		return
	var p: PlayerData = roster[roster_index]
	if p.items[slot_index] != "":
		inventory.append(p.items[slot_index])
	inventory.erase(item_id)
	p.items[slot_index] = item_id
	roster_changed.emit()


func unequip_item(roster_index: int, slot_index: int) -> void:
	if roster_index < 0 or roster_index >= roster.size():
		return
	if slot_index < 0 or slot_index >= PlayerData.ITEM_SLOTS:
		return
	var p: PlayerData = roster[roster_index]
	if p.items[slot_index] == "":
		return
	inventory.append(p.items[slot_index])
	p.items[slot_index] = ""
	roster_changed.emit()


func add_player(p: PlayerData) -> void:
	_ensure_unique_number(p)
	roster.append(p)
	# The first kicker you sign goes straight into the (optional) K slot, so
	# he's ready to kick without a trip to the lineup screen.
	if p.is_kicker() and kicker() == null:
		lineup[KICKER_SLOT] = roster.size() - 1
	roster_changed.emit()


## Reroll `p`'s jersey number (within its own position's legal bands) until
## it no longer clashes with anyone already on the roster.
func _ensure_unique_number(p: PlayerData) -> void:
	var used := {}
	for r in roster:
		if r != p:
			used[r.number] = true
	var guard := 0
	while used.has(p.number) and guard < 200:
		p.number = Generator.random_number(rng, p.pos)
		guard += 1


func cut_player(roster_index: int) -> void:
	if roster_index < 0 or roster_index >= roster.size():
		return
	var p: PlayerData = roster[roster_index]
	inventory.append_array(p.equipped_items())
	roster.remove_at(roster_index)
	# Rebuild the lineup because every index above the cut shifted down.
	var rebuilt := {}
	for slot in lineup.keys():
		var idx: int = lineup[slot]
		if idx == roster_index:
			continue
		rebuilt[slot] = idx - 1 if idx > roster_index else idx
	lineup = rebuilt
	roster_changed.emit()


# --- Progression ------------------------------------------------------------

const WIN_BONUS := 150

## The win bonus the match being played pays: the bowl's prestige payout, an
## Elite stop's bigger one, or the flat WIN_BONUS. Read it before
## finish_match, which moves you off the stop.
func match_win_bonus() -> int:
	if is_bowl_match():
		return BowlDB.win_bonus(chosen_bowl)
	if is_elite_match():
		return int(round(float(WIN_BONUS) * ELITE_BONUS_MULT))
	return WIN_BONUS


## Bank a finished match: moves you onto its stop on the map, win or lose.
## `tied` - level after overtime: no life lost, but no win either.
func finish_match(won: bool, tied: bool = false) -> void:
	matches_played += 1
	next_weather = WeatherDB.roll(rng)
	var node := target_node()
	var was_bowl := is_bowl_match()
	if not node.is_empty():
		node["done"] = true
		node["result"] = "T" if tied else ("W" if won else "L")
		map_row = target_row
		map_col = target_col
	target_row = -1
	target_col = -1
	if not won and not tied:
		_apply_loss()
	if was_bowl:
		run_complete = true
		bowl_won = won


## What a loss costs: a life (MAX_LOSSES ends the season), plus no win bonus
## - match.gd only pays one on a win. Anything further a loss should cost
## goes here.
func _apply_loss() -> void:
	losses += 1
	if losses >= MAX_LOSSES:
		run_active = false


## The current stage of the run, for headers: the match being played, else
## the next match tier ahead on the map, or the bowl.
func round_label() -> String:
	if not target_node().is_empty():
		return String(current_opponent().get("round", ""))
	if run_complete:
		return "Champions" if bowl_won else "Season over"
	for r in range(map_row + 1, BOWL_ROW):
		var tier := MATCH_ROWS.find(r)
		if tier >= 0:
			return String(ROUND_NAMES[tier])
	return "The Bowl"


# --- The run map ------------------------------------------------------------
#
# A run is a Slay the Spire-style map: BOWL_ROW + 1 rows of stops, each stop
# linked to 1-2 in the next row, walked from row 0 to one of the 6 bowls at
# the end. MATCH_ROWS are matches (sometimes an Elite), STOP_ROWS are
# everything else, and PRE_BOWL_ROW is one last Shop or Practice per bowl
# pair. Five matches a run, same as the old bracket. The shop exists only as
# a stop on the map, and the Ritual Site and Laboratory are stops you choose
# to go to rather than things a match unlocks.

const STOP_MATCH := "match"
const STOP_ELITE := "elite"
const STOP_SHOP := "shop"
const STOP_RITUAL := "ritual"
const STOP_LAB := "lab"
const STOP_PRACTICE := "practice"
const STOP_MYSTERY := "mystery"
const STOP_BOWL := "bowl"

const MATCH_ROWS := [0, 2, 4, 6]   # index in this list = difficulty tier
const STOP_ROWS := [1, 3, 5]
const PRE_BOWL_ROW := 7
const BOWL_ROW := 8
## Relative odds of each stop type on a STOP_ROWS row. Every such row gets at
## least one Shop regardless, and at most one Ritual Site and one Laboratory.
const STOP_WEIGHTS := {
	STOP_SHOP: 0.3, STOP_MYSTERY: 0.3, STOP_PRACTICE: 0.2, STOP_RITUAL: 0.1, STOP_LAB: 0.1,
}
## Odds a match row past the first has an Elite in it (at most one per row):
## a tougher defense with an extra guaranteed aura, a bigger win bonus, and a
## free item for winning it. Rivals will live here later.
const ELITE_ROW_CHANCE := 0.6
const ELITE_QUALITY_BONUS := 0.6
const ELITE_EXTRA_AURAS := 1
const ELITE_BONUS_MULT := 1.5

## Rows of stop Dictionaries: type, row, col, y (0-1 spread within the row,
## for drawing), next (col indices in the row after), done, result,
## opponent (match/elite/bowl), bowl_id (bowl), event (mystery), used
## (ritual/lab/practice/mystery, once the stop's been used up).
var run_map: Array = []
## Where you stand: the last stop entered or match finished. -1 before the
## first stop.
var map_row: int = -1
var map_col: int = -1
## The match stop picked to play next (select_match), until it's finished.
var target_row: int = -1
var target_col: int = -1
var run_complete: bool = false
var bowl_won: bool = false

## Effects queued for the next match by mystery events (EventDB) - handed to
## match.gd when it kicks off (take_match_mods). Keys as EventDB's `effects`
## (weather is applied straight to next_weather instead), plus "notes" (the
## lines the map screen lists) and "player_mods" ([{player, stat, amount}],
## the random starter already picked).
var next_match_mods: Dictionary = {}


func map_node(row: int, col: int) -> Dictionary:
	if row < 0 or row >= run_map.size():
		return {}
	var nodes: Array = run_map[row]
	if col < 0 or col >= nodes.size():
		return {}
	return nodes[col]


## The stop you're standing on ({} before the first one).
func current_node() -> Dictionary:
	return map_node(map_row, map_col)


func target_node() -> Dictionary:
	return map_node(target_row, target_col)


## The stops you can go to next, as Vector2i(row, col).
func reachable() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if run_complete or not run_active or run_map.is_empty():
		return out
	if map_row < 0:
		for c in (run_map[0] as Array).size():
			out.append(Vector2i(0, c))
		return out
	for c in current_node().get("next", []):
		out.append(Vector2i(map_row + 1, int(c)))
	return out


func can_go_to(row: int, col: int) -> bool:
	return reachable().has(Vector2i(row, col))


## Pick a match stop (or a bowl) to play next - match.gd plays whatever this
## points at. Sets round_index to its tier, which the difficulty code reads.
func select_match(row: int, col: int) -> void:
	if not can_go_to(row, col):
		return
	var node := map_node(row, col)
	if not is_match_stop(String(node["type"])):
		return
	target_row = row
	target_col = col
	round_index = int(node["opponent"].get("tier", 0))
	if String(node["type"]) == STOP_BOWL:
		chosen_bowl = String(node["bowl_id"])


## Step onto a non-match stop (shop, ritual, lab, practice, mystery).
func enter_stop(row: int, col: int) -> void:
	if not can_go_to(row, col):
		return
	var node := map_node(row, col)
	if is_match_stop(String(node["type"])):
		return
	map_row = row
	map_col = col
	target_row = -1
	target_col = -1
	node["done"] = true


func is_bowl_match() -> bool:
	return not dev_mode and target_row == BOWL_ROW


func is_elite_match() -> bool:
	var node := target_node()
	return not node.is_empty() and String(node["type"]) == STOP_ELITE


## The stop you're standing on has been used up (a ritual done, an Oddity
## bought, a drill picked, an event resolved).
func stop_used() -> bool:
	return bool(current_node().get("used", false))


func mark_stop_used() -> void:
	var node := current_node()
	if not node.is_empty():
		node["used"] = true


func is_match_stop(t: String) -> bool:
	return t == STOP_MATCH or t == STOP_ELITE or t == STOP_BOWL


## Queue a mystery event choice's effects for the next match.
func add_match_mod(effects: Dictionary, note: String) -> void:
	for key in effects:
		var v: Variant = effects[key]
		match key:
			"weather":
				next_weather = String(v)
			"random_starter":
				var pool: Array = []
				for p in starters():
					if p != null:
						pool.append(p)
				if pool.is_empty():
					continue
				var pick: PlayerData = pool[rng.randi_range(0, pool.size() - 1)]
				var mods: Array = next_match_mods.get("player_mods", [])
				for stat in ["strength", "agility", "dexterity", "stamina", "intelligence"]:
					mods.append({"player": pick, "stat": stat, "amount": int(v)})
				next_match_mods["player_mods"] = mods
				note = "%s (%s)" % [note, pick.pname]
			"qb_mods":
				var qb: Dictionary = next_match_mods.get("qb_mods", {})
				for stat in v:
					qb[stat] = int(qb.get(stat, 0)) + int(v[stat])
				next_match_mods["qb_mods"] = qb
			"peels":
				next_match_mods["peels"] = int(next_match_mods.get("peels", 0)) + int(v)
			"defense_quality":
				next_match_mods["defense_quality"] = float(next_match_mods.get("defense_quality", 0.0)) + float(v)
			"td_bucks_mult":
				next_match_mods["td_bucks_mult"] = float(next_match_mods.get("td_bucks_mult", 1.0)) * float(v)
	if note != "":
		var notes: Array = next_match_mods.get("notes", [])
		notes.append(note)
		next_match_mods["notes"] = notes


## Hands the queued effects to the match about to start, and clears them.
func take_match_mods() -> Dictionary:
	var mods := next_match_mods
	next_match_mods = {}
	return mods


## An Elite win's prize: a random item not bought or held this run, straight
## into the bag. "" if there's nothing left to give.
func grant_elite_item() -> String:
	var pool: Array = []
	for id in ItemDB.all_ids():
		if not bought_items.has(id) and not inventory.has(id):
			pool.append(id)
	if pool.is_empty():
		return ""
	var id: String = pool[rng.randi_range(0, pool.size() - 1)]
	inventory.append(id)
	bought_items[id] = true
	roster_changed.emit()
	return id


func _build_map() -> void:
	run_map.clear()
	map_row = -1
	map_col = -1
	target_row = -1
	target_col = -1
	run_complete = false
	bowl_won = false
	chosen_bowl = ""
	var events_used := {}
	for r in BOWL_ROW + 1:
		var types: Array = _row_types(r)
		var row: Array = []
		for c in types.size():
			var t := String(types[c])
			var node := {"type": t, "row": r, "col": c, "next": [],
				"y": (float(c) + 0.5) / float(types.size()), "done": false, "result": ""}
			if r == BOWL_ROW:
				node["bowl_id"] = _bowl_order()[c]
			if is_match_stop(t):
				node["opponent"] = _make_opponent(r, node)
			if t == STOP_MYSTERY:
				var ev := EventDB.random_id(rng, events_used)
				node["event"] = ev
				events_used[ev] = true
			row.append(node)
		run_map.append(row)
	for r in BOWL_ROW:
		_link_rows(r)


## The 6 bowls in map order, each branch's pair side by side (BowlDB.BRANCHES).
func _bowl_order() -> Array:
	var out: Array = []
	for b in BowlDB.all_branches():
		out.append_array(BowlDB.bowls_in_branch(b))
	return out


func _row_types(r: int) -> Array:
	var out: Array = []
	if r == BOWL_ROW:
		for i in _bowl_order().size():
			out.append(STOP_BOWL)
		return out
	if r == PRE_BOWL_ROW:
		# One per bowl pair. Mostly shops - a last chance to spend before the
		# bowl - with the odd Practice.
		for i in BowlDB.all_branches().size():
			out.append(STOP_PRACTICE if rng.randf() < 0.34 else STOP_SHOP)
		if not out.has(STOP_SHOP):
			out[rng.randi_range(0, out.size() - 1)] = STOP_SHOP
		return out
	var count := 3 if r == 0 else rng.randi_range(3, 4)
	if MATCH_ROWS.has(r):
		var elite_at := -1
		if r > 0 and rng.randf() < ELITE_ROW_CHANCE:
			elite_at = rng.randi_range(0, count - 1)
		for i in count:
			out.append(STOP_ELITE if i == elite_at else STOP_MATCH)
		return out
	for i in count:
		out.append(_weighted_stop())
	# At most one Ritual Site and one Laboratory per row; at least one Shop.
	for once in [STOP_RITUAL, STOP_LAB]:
		var seen := false
		for i in out.size():
			if out[i] == once:
				if seen:
					out[i] = STOP_MYSTERY
				seen = true
	if not out.has(STOP_SHOP):
		out[rng.randi_range(0, out.size() - 1)] = STOP_SHOP
	return out


func _weighted_stop() -> String:
	var total := 0.0
	for t in STOP_WEIGHTS:
		total += float(STOP_WEIGHTS[t])
	var roll := rng.randf() * total
	for t in STOP_WEIGHTS:
		roll -= float(STOP_WEIGHTS[t])
		if roll <= 0.0:
			return String(t)
	return STOP_MYSTERY


## The opponent for a match/elite/bowl stop: a fresh team name at that row's
## difficulty tier (`bracket`), tougher if it's an Elite, scaled by the bowl's
## prestige if it's a bowl.
func _make_opponent(row: int, node: Dictionary) -> Dictionary:
	var t := String(node["type"])
	var tier := bracket.size() - 1 if t == STOP_BOWL else MATCH_ROWS.find(row)
	var tier_info: Dictionary = bracket[tier]
	var quality := float(tier_info["quality"])
	var opp := {
		"name": Generator.team_name(rng),
		"round": String(tier_info["round"]),
		"quality": quality,
		"tier_quality": quality,
		"tier": tier,
		"drives": int(tier_info["drives"]),
		"result": "",
	}
	if t == STOP_ELITE:
		opp["quality"] = quality + ELITE_QUALITY_BONUS
		opp["round"] = "%s - Elite" % tier_info["round"]
		opp["elite"] = true
	elif t == STOP_BOWL:
		var bowl_id := String(node["bowl_id"])
		opp["quality"] = quality * BowlDB.quality_mult(bowl_id)
		opp["round"] = BowlDB.bowl_name(bowl_id)
		opp["bowl_id"] = bowl_id
	return opp


## Connects row `r` to row `r + 1`. Each stop leads to the next-row stop at
## its matching height plus, sometimes, a neighbor - so paths branch without
## the lines crossing all over - then every next-row stop gets a way in. The
## pre-bowl row leads each stop to its own bowl pair, and every stop leading
## into the middle stop row or the pre-bowl row can always reach a Shop.
func _link_rows(r: int) -> void:
	var a: Array = run_map[r]
	var b: Array = run_map[r + 1]
	if r == PRE_BOWL_ROW:
		var per := int(b.size() / a.size())
		for i in a.size():
			for k in per:
				a[i]["next"].append(i * per + k)
		return
	var n := a.size()
	var m := b.size()
	var incoming := {}
	for i in n:
		var j := int(round(float(i) * float(m - 1) / float(maxi(n - 1, 1))))
		var next: Array = [j]
		if rng.randf() < 0.45:
			var k := j + (1 if rng.randf() < 0.5 else -1)
			if k >= 0 and k < m:
				next.append(k)
		next.sort()
		a[i]["next"] = next
		for k in next:
			incoming[k] = true
	for j in m:
		if incoming.has(j):
			continue
		# Nothing leads here yet: link it from the stop at the nearest height.
		var best := 0
		for i in n:
			if absf(float(a[i]["y"]) - float(b[j]["y"])) < absf(float(a[best]["y"]) - float(b[j]["y"])):
				best = i
		a[best]["next"].append(j)
		a[best]["next"].sort()
	if r + 1 == int(STOP_ROWS[1]) or r + 1 == PRE_BOWL_ROW:
		for i in n:
			var has_shop := false
			for k in a[i]["next"]:
				if String(b[int(k)]["type"]) == STOP_SHOP:
					has_shop = true
			if has_shop:
				continue
			var nearest := -1
			for j in m:
				if String(b[j]["type"]) != STOP_SHOP:
					continue
				if nearest < 0 or absf(float(b[j]["y"]) - float(a[i]["y"])) < absf(float(b[nearest]["y"]) - float(a[i]["y"])):
					nearest = j
			if nearest >= 0:
				a[i]["next"].append(nearest)
				a[i]["next"].sort()


# --- Shop stock -------------------------------------------------------------

const REROLL_COST := 30

var shop_stock: Dictionary = {}

## Permanent-for-the-run record of what's already been bought, so a rerolled
## or next-match shop never re-offers it. Keyed differently per category:
## shop players have no stable id besides their name, and items are
## consumable/re-stackable via `inventory` so buying one doesn't remove it
## from there.
var bought_shop_players: Dictionary = {}    # player name -> true
var bought_items: Dictionary = {}           # item id -> true


## Generate stock once per Shop stop on the map; leaving for the lineup screen
## and coming back to the same stop keeps what was on the shelves.
func ensure_shop() -> void:
	if shop_stock.get("stop", "") == _shop_key():
		return
	_roll_shop()


func _shop_key() -> String:
	return "%d:%d" % [map_row, map_col]


func reroll_shop() -> bool:
	if not spend_bucks(REROLL_COST):
		return false
	_roll_shop()
	return true


func _roll_shop() -> void:
	var item_pool: Array = []
	for id in ItemDB.all_ids():
		if not bought_items.has(id):
			item_pool.append(id)
	item_pool.shuffle()

	shop_stock = {
		"stop": _shop_key(),
		"players": ShopPlayerDB.roll_stock(rng, 4, bought_shop_players),
		"items": item_pool.slice(0, 4),
		"sold": {},
	}


func mark_sold(category: String, key: String) -> void:
	var sold: Dictionary = shop_stock.get("sold", {})
	sold["%s:%s" % [category, key]] = true
	shop_stock["sold"] = sold


func is_sold(category: String, key: String) -> bool:
	var sold: Dictionary = shop_stock.get("sold", {})
	return sold.has("%s:%s" % [category, key])
