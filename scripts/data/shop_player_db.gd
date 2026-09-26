class_name ShopPlayerDB
extends RefCounted

## Hardcoded, roguelike-style buyable players (like Binding of Isaac items):
## fixed names, fixed stat lines, fixed abilities. The shop always offers
## exactly 4 of these, drawn without repeats and weighted by rarity so the
## higher tiers show up less often.
##
## The roster itself lives in res://data/shop_players.json, not in code, so
## adding a player is a data edit rather than a script change. Each entry:
##   name          String
##   pos           String, one of QB/C/T/RB/WR/TE
##   quality       int 1-4 (see QUALITY_* below: Rookie/Sophomore/Veteran/All Star)
##   strength, agility, dexterity, stamina, intelligence   int 1-15
##   ability_id    String, an id from AbilityDB.ABILITIES ("" for none)
##   body          String, sprite id ("6" -> assets/players/*/body_06.png)
##   head          String, optional - a HeadArtDB set id (e.g. "runnadball" for
##                 a player with his own unique head). Omit it to roll randomly
##                 between the generic "1"/"2" styles like a generated player.

const DATA_PATH := "res://data/shop_players.json"

const QUALITY_ROOKIE := 1
const QUALITY_SOPHOMORE := 2
const QUALITY_VETERAN := 3
const QUALITY_ALL_STAR := 4
## Laboratory-only (OddityPlayerDB) - never in the shop's JSON pool, so it has
## no QUALITY_WEIGHTS entry and roll_stock can't draw it.
const QUALITY_ODDITY := 5

const QUALITY_NAMES := {
	QUALITY_ROOKIE: "Rookie",
	QUALITY_SOPHOMORE: "Sophomore",
	QUALITY_VETERAN: "Veteran",
	QUALITY_ALL_STAR: "All Star",
	QUALITY_ODDITY: "Oddity",
}

## Higher rarities are drawn less often; weight is relative, not a probability.
const QUALITY_WEIGHTS := {
	QUALITY_ROOKIE: 1.0,
	QUALITY_SOPHOMORE: 1.0,
	QUALITY_VETERAN: 0.8,
	QUALITY_ALL_STAR: 0.5,
}

const POS_BY_NAME := {
	"QB": PlayerData.Pos.QB, "C": PlayerData.Pos.C, "T": PlayerData.Pos.T,
	"RB": PlayerData.Pos.RB, "WR": PlayerData.Pos.WR, "TE": PlayerData.Pos.TE,
}

static var _cache: Array = []
static var _loaded := false


static func quality_name(q: int) -> String:
	return QUALITY_NAMES.get(q, "?")


## Raw entries as loaded from JSON, read once and cached from then on.
static func _entries() -> Array:
	if not _loaded:
		_load()
	return _cache


static func _load() -> void:
	_loaded = true
	_cache = []
	if not FileAccess.file_exists(DATA_PATH):
		push_error("ShopPlayerDB: missing %s" % DATA_PATH)
		return
	var text := FileAccess.get_file_as_string(DATA_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Array):
		push_error("ShopPlayerDB: %s did not parse to a JSON array" % DATA_PATH)
		return
	_cache = parsed


static func _make(entry: Dictionary, rng: RandomNumberGenerator) -> PlayerData:
	var p := PlayerData.new()
	p.pname = String(entry.get("name", "?"))
	p.pos = POS_BY_NAME.get(String(entry.get("pos", "WR")), PlayerData.Pos.WR)
	p.number = Generator.random_number(rng, p.pos)
	p.strength = int(entry.get("strength", 5))
	p.agility = int(entry.get("agility", 5))
	p.dexterity = int(entry.get("dexterity", 5))
	p.stamina = int(entry.get("stamina", 5))
	p.intelligence = int(entry.get("intelligence", 5))
	p.ability_id = String(entry.get("ability_id", ""))
	p.body = String(entry.get("body", "medium"))
	p.head_id = String(entry.get("head", Generator.random_head_id(rng)))
	p.quality = int(entry.get("quality", QUALITY_ROOKIE))
	return p


## Draw `count` distinct players from the hardcoded pool, weighted by rarity.
## `exclude_names` (player name -> true) leaves out anyone already signed
## this run, so a rerolled or next-match shop never re-offers them.
## With only a handful of players in the pool today this often returns the
## whole pool regardless of order; the weighting starts to matter more once
## the JSON file has more entries than a single shop visit shows.
static func roll_stock(rng: RandomNumberGenerator, count: int = 4,
		exclude_names: Dictionary = {}) -> Array[PlayerData]:
	var pool := []
	for e in _entries():
		if not exclude_names.has(String(e.get("name", ""))):
			pool.append(e)
	var out: Array[PlayerData] = []
	while pool.size() > 0 and out.size() < count:
		var total := 0.0
		for e in pool:
			total += float(QUALITY_WEIGHTS.get(int(e.get("quality", 1)), 1.0))
		var roll := rng.randf() * total
		var acc := 0.0
		var pick_i := pool.size() - 1
		for i in pool.size():
			acc += float(QUALITY_WEIGHTS.get(int(pool[i].get("quality", 1)), 1.0))
			if roll <= acc:
				pick_i = i
				break
		out.append(_make(pool[pick_i], rng))
		pool.remove_at(pick_i)
	return out


## Every hardcoded player, unweighted and with no cap - used by dev mode to
## hand out the whole pool at once instead of a random weighted draw.
static func all_players(rng: RandomNumberGenerator) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for entry in _entries():
		out.append(_make(entry, rng))
	return out
