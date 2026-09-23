class_name UpgradeDB
extends RefCounted

## Per-game roguelike upgrades: every scoring drive offers 3 of these, drawn
## from res://data/upgrades.json (much like ShopPlayerDB's hardcoded
## players), and the coach picks one to hand to a player on the roster.
## The bonus only lasts for the current match - see MatchSim.match_bonuses -
## it never touches the player's permanent stat line.
##
## Stamina is deliberately left out of the pool: it's a hidden stat the
## player never sees a number for (see PlayerData / the design doc), so a
## "+2 Stamina" reward would advertise a stat that's invisible everywhere
## else in the UI.

const DATA_PATH := "res://data/upgrades.json"

static var _cache: Array = []
static var _loaded := false


static func _entries() -> Array:
	if not _loaded:
		_load()
	return _cache


static func _load() -> void:
	_loaded = true
	_cache = []
	if not FileAccess.file_exists(DATA_PATH):
		push_error("UpgradeDB: missing %s" % DATA_PATH)
		return
	var text := FileAccess.get_file_as_string(DATA_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Array):
		push_error("UpgradeDB: %s did not parse to a JSON array" % DATA_PATH)
		return
	_cache = parsed


static func label(entry: Dictionary) -> String:
	var stat: String = entry.get("stat", "")
	var amount: int = int(entry.get("amount", 0))
	return "+%d %s" % [amount, UIKit.STAT_LABELS.get(stat, stat.capitalize())]


## Draw `count` distinct upgrades, weighted so the bigger tiers show up less
## often - same weighted-draw shape as ShopPlayerDB.roll_stock.
static func roll(rng: RandomNumberGenerator, count: int = 3) -> Array:
	var pool := _entries().duplicate()
	var out: Array = []
	while pool.size() > 0 and out.size() < count:
		var total := 0.0
		for e in pool:
			total += float(e.get("weight", 1.0))
		var roll_val := rng.randf() * total
		var acc := 0.0
		var pick_i := pool.size() - 1
		for i in pool.size():
			acc += float(pool[i].get("weight", 1.0))
			if roll_val <= acc:
				pick_i = i
				break
		out.append(pool[pick_i])
		pool.remove_at(pick_i)
	return out
