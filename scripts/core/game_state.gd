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


func _ready() -> void:
	rng.randomize()


func new_run(seed_value: int = 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()

	team_name = Generator.team_name(rng)
	bucks = 150
	roster.assign(Generator.starting_roster(rng))
	playbook.assign(PlayDB.starter_ids())
	inventory.assign(["stickum_gloves", "lead_vest"])
	round_index = 0
	run_active = true
	last_result = {}
	_build_bracket()
	auto_fill_lineup()
	auto_fill_plays()
	roster_changed.emit()
	bucks_changed.emit(bucks)


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


func set_slot(slot: String, idx: int) -> void:
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
			var score := float(p.overall())
			if p.natural_slot_kind() != kind:
				score -= 6.0
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
	roster.append(p)
	roster_changed.emit()


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
	if round_index < bracket.size():
		bracket[round_index]["result"] = "W" if won else "L"
	if won:
		round_index += 1
	else:
		run_active = false


func round_label() -> String:
	if round_index < ROUND_NAMES.size():
		return ROUND_NAMES[round_index]
	return "Champions"


# --- Shop stock -------------------------------------------------------------

const REROLL_COST := 30

var shop_stock: Dictionary = {}


## Generate stock for the current round once; repeat calls are no-ops.
func ensure_shop() -> void:
	if shop_stock.get("round", -1) == round_index:
		return
	_roll_shop()


func reroll_shop() -> bool:
	if not spend_bucks(REROLL_COST):
		return false
	_roll_shop()
	return true


func _roll_shop() -> void:
	var quality := 4.5 + float(round_index) * 1.3

	var play_pool: Array = []
	for id in PlayDB.buyable_ids():
		if not playbook.has(id):
			play_pool.append(id)
	play_pool.shuffle()

	var item_pool: Array = ItemDB.all_ids().duplicate()
	item_pool.shuffle()

	shop_stock = {
		"round": round_index,
		"plays": play_pool.slice(0, mini(3, play_pool.size())),
		"players": Generator.draft_class(rng, 4, quality),
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
