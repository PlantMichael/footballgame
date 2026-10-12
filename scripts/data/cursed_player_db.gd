class_name CursedPlayerDB
extends RefCounted

## The Ritual Site's payout: 4 fixed, unique, All-Star-tier players, each
## with one bespoke ability found nowhere else (see ability_db.gd/
## match_sim.gd for "combustion"/"boundless"/"corruption"/"aftershock"). A
## hardcoded roster like QBDB rather than a JSON pool, since these aren't
## random rolls within a category - each one IS the category.

const CURSED := [
	{
		"name": "Asmodeus",
		"pos": "WR",
		"strength": 6, "agility": 14, "dexterity": 12, "stamina": 9, "intelligence": 8,
		"ability_id": "combustion",
	},
	{
		"name": "Beelzebub",
		"pos": "WR",
		"strength": 6, "agility": 11, "dexterity": 13, "stamina": 10, "intelligence": 12,
		"ability_id": "boundless",
	},
	{
		"name": "Paimon",
		"pos": "RB",
		"strength": 10, "agility": 11, "dexterity": 9, "stamina": 12, "intelligence": 11,
		"ability_id": "corruption",
	},
	{
		"name": "Abaddon",
		"pos": "TE",
		"strength": 11, "agility": 9, "dexterity": 12, "stamina": 11, "intelligence": 9,
		"ability_id": "aftershock",
	},
]

## Shared body/head - the Ritual Site doesn't hand out different jerseys,
## just the one shared cursed head (assets/cursedplayer*.png) on top of it.
const BODY := "9"
const HEAD := "cursed"


static func all_names() -> Array:
	return DataUtil.names_of(CURSED)


static func make_named(rng: RandomNumberGenerator, name: String) -> PlayerData:
	var e := DataUtil.entry_named(CURSED, name)
	return null if e.is_empty() else _make(rng, e)


## One random Cursed player, preferring a name not already in `exclude_names`
## (roster names -> true) - falls back to allowing a repeat once all 4 are
## already owned.
static func random_cursed(rng: RandomNumberGenerator, exclude_names: Dictionary = {}) -> PlayerData:
	return _make(rng, DataUtil.pick_excluding(rng, CURSED, exclude_names))


static func _make(rng: RandomNumberGenerator, e: Dictionary) -> PlayerData:
	var p := PlayerData.new()
	p.pname = String(e["name"])
	p.pos = ShopPlayerDB.POS_BY_NAME.get(String(e["pos"]), PlayerData.Pos.WR)
	p.number = Generator.random_number(rng, p.pos)
	p.strength = int(e["strength"])
	p.agility = int(e["agility"])
	p.dexterity = int(e["dexterity"])
	p.stamina = int(e["stamina"])
	p.intelligence = int(e["intelligence"])
	p.ability_id = String(e["ability_id"])
	p.body = BODY
	p.head_id = HEAD
	p.quality = ShopPlayerDB.QUALITY_ALL_STAR
	return p
