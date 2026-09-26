class_name OddityPlayerDB
extends RefCounted

## The Laboratory's payout (see laboratory.gd): fixed names and bespoke
## abilities like CursedPlayerDB, but unlike every other hardcoded player the
## stat line is NOT fixed - each one is rolled fresh when he's made, a
## `stat_pool` of points split randomly across the four visible stats
## (Strength, Agility, Dexterity, Intelligence), each capped at 15. Stamina is
## hidden from the coach anyway, so it's rolled on its own rather than eating
## into the pool.
##
## They're their own tier, ShopPlayerDB.QUALITY_ODDITY, and draw with a bright
## green outline on the field (field_view.gd).

const COLOR := Color("39ff5a")

## The default pool - 30 points is an average of 7.5 across the four stats,
## but a lopsided roll can just as easily give a 13 and a 2.
const BASE_POOL := 30

const ODDITIES := [
	{
		"name": "Mickey Mitosis",
		"pos": "WR",
		"ability_id": "mitosis",
		"stat_pool": BASE_POOL,
		"body": "9",
	},
	{
		"name": "Ricky Dooper IV",
		"pos": "T",
		"ability_id": "rogue_lineman",
		"stat_pool": BASE_POOL,
		"body": "2",
	},
	{
		"name": "Flixian Flopper",
		"pos": "WR",
		"ability_id": "flip_flop",
		"stat_pool": BASE_POOL,
		"body": "5",
	},
	{
		# "Unusually high stats" - paid for by melting out of plays.
		"name": "Sfdsvd Kytgseg",
		"pos": "TE",
		"ability_id": "meltdown",
		"stat_pool": 44,
		"body": "4",
	},
	{
		# "Slightly lower stats than normal" - paid for by the double cash.
		"name": "Midas Jr.",
		"pos": "RB",
		"ability_id": "golden_touch",
		"stat_pool": 25,
		"body": "8",
	},
]

const POOL_STATS := ["strength", "agility", "dexterity", "intelligence"]
const STAMINA_MIN := 4
const STAMINA_MAX := 10


static func all_names() -> Array:
	var out: Array = []
	for e in ODDITIES:
		out.append(String(e["name"]))
	return out


static func make_named(rng: RandomNumberGenerator, name: String) -> PlayerData:
	for e in ODDITIES:
		if e["name"] == name:
			return _make(rng, e)
	return null


## One random Oddity, preferring a name not already in `exclude_names`
## (roster names -> true) - falls back to allowing a repeat once every one
## of them is already on the roster.
static func random_oddity(rng: RandomNumberGenerator, exclude_names: Dictionary = {}) -> PlayerData:
	var pool: Array = []
	for e in ODDITIES:
		if not exclude_names.has(String(e["name"])):
			pool.append(e)
	if pool.is_empty():
		pool = ODDITIES
	return _make(rng, pool[rng.randi_range(0, pool.size() - 1)])


static func _make(rng: RandomNumberGenerator, e: Dictionary) -> PlayerData:
	var p := PlayerData.new()
	p.pname = String(e["name"])
	p.pos = ShopPlayerDB.POS_BY_NAME.get(String(e["pos"]), PlayerData.Pos.WR)
	p.number = Generator.random_number(rng, p.pos)
	var split := split_pool(rng, int(e["stat_pool"]))
	p.strength = split["strength"]
	p.agility = split["agility"]
	p.dexterity = split["dexterity"]
	p.intelligence = split["intelligence"]
	p.stamina = rng.randi_range(STAMINA_MIN, STAMINA_MAX)
	p.ability_id = String(e["ability_id"])
	p.body = String(e["body"])
	p.head_id = Generator.random_head_id(rng)
	p.quality = ShopPlayerDB.QUALITY_ODDITY
	return p


## Split `pool` points across POOL_STATS at random, each stat 1-15. Every stat
## gets a random weight up front and points are then handed out one at a time
## in proportion to those weights - so a roll can come out genuinely lopsided
## (a plain uniform one-at-a-time split just converges on ~7 each), and a stat
## that hits 15 simply stops taking points.
static func split_pool(rng: RandomNumberGenerator, pool: int) -> Dictionary:
	var out := {}
	var weights := {}
	for key in POOL_STATS:
		out[key] = 1
		weights[key] = rng.randf_range(0.1, 1.0)
	var left := clampi(pool, POOL_STATS.size(), POOL_STATS.size() * 15) - POOL_STATS.size()
	while left > 0:
		var total := 0.0
		for key in POOL_STATS:
			if int(out[key]) < 15:
				total += float(weights[key])
		var roll := rng.randf() * total
		var pick := ""
		for key in POOL_STATS:
			if int(out[key]) >= 15:
				continue
			pick = key   # float rounding can leave roll a hair above 0 - the last open stat takes it
			roll -= float(weights[key])
			if roll <= 0.0:
				break
		out[pick] = int(out[pick]) + 1
		left -= 1
	return out
