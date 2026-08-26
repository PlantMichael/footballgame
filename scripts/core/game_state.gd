extends Node

## Autoload. Owns everything that persists across a run: roster, lineup,
## playbook, inventory, football bucks, and bracket progress.

signal bucks_changed(new_total: int)
signal roster_changed()

const SLOT_ORDER := ["QB", "C", "T0", "T1", "T2", "T3", "F0", "F1", "F2", "F3", "F4"]
const ROUND_NAMES := ["Wild Card", "Divisional", "Conference", "Semifinal", "CHAMPIONSHIP"]
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
var playbook: Array[String] = []        # play ids
var inventory: Array[String] = []       # unequipped item ids
var round_index: int = 0
var bracket: Array = []                 # Array[Dictionary] opponent info
var run_active: bool = false
var last_result: Dictionary = {}        # filled in by the match scene

## Selected plays for the upcoming match, capped at PLAY_SLOTS.
const PLAY_SLOTS := 5
var active_plays: Array[String] = []

## An endless scrimmage with every player, item, and play unlocked and no
## bracket/economy pressure - for tuning and ability testing. See
## start_dev_mode and MatchSim.regenerate_defense (the live difficulty slider
## on the match screen's play-call bar).
var dev_mode: bool = false
const DEV_ROSTER_QUALITY := 13.0
const DEV_DEFENSE_QUALITY := 8.0
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
	team_name = Generator.team_name(rng)
	bucks = 150
	roster.assign(Generator.starting_roster(rng))
	if qb_id >= 0:
		_apply_chosen_qb(qb_id)
	playbook.assign(PlayDB.random_starter_ids(rng))
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
	auto_fill_plays()
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
	playbook.assign(PlayDB.all_ids())
	active_plays.assign(PlayDB.all_ids())
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


func current_opponent() -> Dictionary:
	if round_index < bracket.size():
		return bracket[round_index]
	return {}


## The opponent quality to actually build a match's defense with: the
## round's base quality plus a step for every match already played this run.
func current_match_quality() -> float:
	return float(current_opponent().get("quality", 3.0)) + float(matches_played) * MATCH_QUALITY_STEP


func is_run_over() -> bool:
	return round_index >= bracket.size()


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
	# A player can only be in one slot; swap if they are already elsewhere.
	for other in lineup.keys():
		if other != slot and lineup[other] == idx:
			if lineup.has(slot):
				lineup[other] = lineup[slot]
			else:
				lineup.erase(other)
			break
	lineup[slot] = idx
	roster_changed.emit()
	return true


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


# --- Playbook ---------------------------------------------------------------

func auto_fill_plays() -> void:
	active_plays.clear()
	for id in playbook:
		if active_plays.size() >= PLAY_SLOTS:
			break
		active_plays.append(id)


func toggle_active_play(id: String) -> bool:
	if active_plays.has(id):
		active_plays.erase(id)
		return true
	if active_plays.size() >= PLAY_SLOTS:
		return false
	active_plays.append(id)
	return true


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
	return "Champions"


# --- Shop stock -------------------------------------------------------------

const REROLL_COST := 30

var shop_stock: Dictionary = {}

## Permanent-for-the-run record of what's already been bought, so a rerolled
## or next-match shop never re-offers it. Keyed differently per category:
## plays already have `playbook` for this (an id membership check), but shop
## players have no stable id besides their name, and items are consumable/
## re-stackable via `inventory` so buying one doesn't remove it from there.
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
	var play_pool: Array = []
	for id in PlayDB.all_ids():
		if not playbook.has(id):
			play_pool.append(id)
	play_pool.shuffle()

	var item_pool: Array = []
	for id in ItemDB.all_ids():
		if not bought_items.has(id):
			item_pool.append(id)
	item_pool.shuffle()

	shop_stock = {
		"matches": matches_played,
		"plays": play_pool.slice(0, mini(3, play_pool.size())),
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
