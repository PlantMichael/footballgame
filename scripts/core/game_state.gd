extends Node

## Autoload. Owns everything that persists across a run: roster, lineup,
## drawn routes, inventory, football bucks, and bracket progress.

signal bucks_changed(new_total: int)
signal roster_changed()

const SLOT_ORDER := ["QB", "C", "T0", "T1", "T2", "T3", "F0", "F1", "F2", "F3", "F4"]
## The 4 build-up rounds. The 5th and final bracket entry is the bowl game
## itself - its name comes from BowlDB once the coach picks a branch and then
## a bowl (see needs_branch_choice/needs_bowl_choice/choose_branch/choose_bowl),
## not from this list. DRIVES_PER_MATCH still has a slot for it at index 4.
const ROUND_NAMES := ["Wild Card", "Divisional", "Conference", "Semifinal"]
const DRIVES_PER_MATCH := [4, 4, 5, 5, 5]

## Rosters start in the 2-4 stat band, so the whole difficulty scale sits low
## and climbs slowly. The shop ramps faster than the bracket on purpose.
const ROUND_ONE_QUALITY := 2.8
const QUALITY_PER_ROUND := 0.7

## A loss no longer ends the run outright: you get MAX_LOSSES total across
## the whole run before the season is over. A loss that doesn't end the run
## simply costs you a life and you retry the same round.
const MAX_LOSSES := 3
var losses: int = 0

## Total matches played this run, wins and retried losses both counting.
## Defenses get a little tougher with every one of them on top of the
## per-round ramp, so grinding out extra attempts at a round (or just
## playing deep into a run) doesn't stay easy forever.
const MATCH_QUALITY_STEP := 0.15
var matches_played: int = 0

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

## The roguelike path to one of the 6 bowls (BowlDB). Chosen in two steps:
## a branch after round 0, then a specific bowl within that branch after
## round 1 - see needs_branch_choice/needs_bowl_choice below.
var chosen_branch: String = ""
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
	run_active = true
	last_result = {}
	_build_bracket()
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
	drawn_routes.clear()
	inventory.assign(ItemDB.all_ids())
	round_index = 0
	losses = 0
	matches_played = 0
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
	chosen_branch = ""
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
	# The bowl game itself: which one is decided later via choose_branch/
	# choose_bowl, so this starts as a placeholder and gets filled in.
	var bowl_index := ROUND_NAMES.size()
	bracket.append({
		"name": Generator.team_name(rng),
		"round": "The Bowl",
		"quality": ROUND_ONE_QUALITY + float(bowl_index) * QUALITY_PER_ROUND,
		"drives": DRIVES_PER_MATCH[bowl_index],
		"result": "",
		"bowl_id": "",
	})


func current_opponent() -> Dictionary:
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
	var base := float(current_opponent().get("quality", 3.0)) + float(matches_played) * MATCH_QUALITY_STEP
	return base + _difficulty_overshoot() * ROSTER_OVERSHOOT_WEIGHT


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


## How far the roster's actual strength has pulled ahead of the round's own
## base quality ramp - 0 for a roster that's still on curve (rookies, or
## just keeping pace round to round), positive once a signing outpaces it.
## Drives both current_match_quality and aura_count.
func _difficulty_overshoot() -> float:
	var base := float(current_opponent().get("quality", ROUND_ONE_QUALITY))
	return maxf(0.0, roster_overall() - base)


func is_run_over() -> bool:
	return round_index >= bracket.size()


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
			+ _difficulty_overshoot() * AURA_OVERSHOOT_PER_POINT,
		0.0, AURA_CHANCE_MAX)
	var count := 0
	for i in MAX_AURAS:
		if rng_src.randf() < chance:
			count += 1
		chance *= 0.5   # each additional aura is noticeably less likely than the last
	return count


# --- Bowl path choices -------------------------------------------------------

## True once round 0 (Wild Card) is won and the coach still needs to pick a
## branch (see BowlDB.BRANCHES) toward one of the 6 bowls.
func needs_branch_choice() -> bool:
	return not dev_mode and run_active and round_index == 1 and chosen_branch == ""


## True once round 1 (Divisional) is won, a branch is picked, and the coach
## still needs to pick which of that branch's 2 bowls to play for.
func needs_bowl_choice() -> bool:
	return not dev_mode and run_active and round_index == 2 and chosen_branch != "" and chosen_bowl == ""


func choose_branch(id: String) -> void:
	if not BowlDB.BRANCHES.has(id):
		return
	chosen_branch = id


func choose_bowl(id: String) -> void:
	if chosen_branch == "" or not BowlDB.bowls_in_branch(chosen_branch).has(id):
		return
	chosen_bowl = id
	var idx := bracket.size() - 1
	bracket[idx]["round"] = BowlDB.bowl_name(id)
	bracket[idx]["bowl_id"] = id
	bracket[idx]["quality"] = float(bracket[idx]["quality"]) * BowlDB.quality_mult(id)


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

	for slot in SLOT_ORDER:
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

func equip_item(item_id: String, roster_index: int) -> void:
	if roster_index < 0 or roster_index >= roster.size():
		return
	var p: PlayerData = roster[roster_index]
	if p.item_id != "":
		inventory.append(p.item_id)
	inventory.erase(item_id)
	p.item_id = item_id
	roster_changed.emit()


func unequip_item(roster_index: int) -> void:
	if roster_index < 0 or roster_index >= roster.size():
		return
	var p: PlayerData = roster[roster_index]
	if p.item_id == "":
		return
	inventory.append(p.item_id)
	p.item_id = ""
	roster_changed.emit()


func add_player(p: PlayerData) -> void:
	_ensure_unique_number(p)
	roster.append(p)
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
	if p.item_id != "":
		inventory.append(p.item_id)
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

func finish_match(won: bool) -> void:
	matches_played += 1
	if round_index < bracket.size():
		bracket[round_index]["result"] = "W" if won else "L"
	if won:
		round_index += 1
	else:
		losses += 1
		if losses >= MAX_LOSSES:
			run_active = false
		# Otherwise the run continues and this same round is retried.


func round_label() -> String:
	if round_index < ROUND_NAMES.size():
		return ROUND_NAMES[round_index]
	if round_index < bracket.size():
		return String(bracket[round_index].get("round", "The Bowl"))
	return "Champions"


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


## Generate stock once per match played; repeat calls in between are no-ops.
## Keyed on matches_played rather than round_index so a loss-retry (which
## does not advance round_index) still gets a fresh shop, not the stale one
## from before that match.
func ensure_shop() -> void:
	if shop_stock.get("matches", -1) == matches_played:
		return
	_roll_shop()


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
		"matches": matches_played,
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
