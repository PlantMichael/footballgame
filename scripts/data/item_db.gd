class_name ItemDB
extends RefCounted

## Equippable items. The list itself lives in res://data/items.json, not
## in code, so adding an item is a data edit. Each entry:
##   id             String, unique - what rosters, the bag and the shop store
##   name           String
##   category       "helmet", "gloves" or "cleats" - a player wears at most one
##                  of each (see CATEGORIES / PlayerData.items)
##   desc           String shown on cards and tooltips
##   cost           int, shop price in football bucks
##   mods           optional {stat: int} flat stat changes, e.g. {"strength": 2}
##   catch          optional float added to catch chance (0.06 = +6%)
##   contact        optional float added to contact rolls (0.12 = +12%)
##   contact_roles  optional ["carry", "block", "cover"] - which contact rolls
##                  `contact` applies to; leave it out for all of them
## `catch`/`contact` work the same way the matching ability hooks do.

const DATA_PATH := "res://data/items.json"

## Equipment categories, in the order of a player's item slots
## (PlayerData.items[i] holds his CATEGORIES[i] item).
const CATEGORIES := ["helmet", "gloves", "cleats"]
const CATEGORY_NAMES := {"helmet": "Helmet", "gloves": "Gloves", "cleats": "Cleats"}

static var _items: Dictionary = {}   # id -> entry
static var _order: Array = []        # ids in file order
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(DATA_PATH):
		push_error("ItemDB: missing %s" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not (parsed is Array):
		push_error("ItemDB: %s did not parse to a JSON array" % DATA_PATH)
		return
	for e in parsed:
		if not (e is Dictionary):
			continue
		var id := String(e.get("id", ""))
		var category := String(e.get("category", ""))
		if id == "" or _items.has(id):
			push_warning("ItemDB: skipping an item with a missing or duplicate id (%s)" % id)
			continue
		if not CATEGORIES.has(category):
			push_warning("ItemDB: item '%s' has category '%s' - must be one of %s; skipped" % [id, category, CATEGORIES])
			continue
		_items[id] = e
		_order.append(id)


static func get_item(id: String) -> Dictionary:
	_ensure_loaded()
	return _items.get(id, {})


static func item_name(id: String) -> String:
	if id == "":
		return ""
	var i: Dictionary = get_item(id)
	return i.get("name", "?")


static func item_desc(id: String) -> String:
	var i: Dictionary = get_item(id)
	return i.get("desc", "")


static func item_cost(id: String) -> int:
	var i: Dictionary = get_item(id)
	return int(i.get("cost", 100))


static func all_ids() -> Array:
	_ensure_loaded()
	return _order.duplicate()


## "helmet"/"gloves"/"cleats", or "" for an unknown id.
static func item_category(id: String) -> String:
	return String(get_item(id).get("category", ""))


## Which of a player's item slots this item goes in, or -1.
static func slot_for(id: String) -> int:
	return CATEGORIES.find(item_category(id))


static func category_name(category: String) -> String:
	return String(CATEGORY_NAMES.get(category, category.capitalize()))


static func stat_mods(id: String) -> Dictionary:
	if id == "":
		return {}
	var i: Dictionary = get_item(id)
	return i.get("mods", {})


static func catch_mod(id: String) -> float:
	if id == "":
		return 0.0
	var i: Dictionary = get_item(id)
	return float(i.get("catch", 0.0))


## Combined effect of every item in `ids` (a player's equipped items) - the
## per-item functions above summed, which is what the sim and the UI use.
static func total_stat_mods(ids: Array) -> Dictionary:
	var out := {}
	for id in ids:
		var mods := stat_mods(id)
		for key in mods:
			out[key] = int(out.get(key, 0)) + int(mods[key])
	return out


static func total_catch_mod(ids: Array) -> float:
	var out := 0.0
	for id in ids:
		out += catch_mod(id)
	return out


static func total_contact_mod(ids: Array, role: String) -> float:
	var out := 0.0
	for id in ids:
		out += contact_mod(id, role)
	return out


static func contact_mod(id: String, role: String) -> float:
	if id == "":
		return 0.0
	var i: Dictionary = get_item(id)
	var amount := float(i.get("contact", 0.0))
	if amount == 0.0:
		return 0.0
	var roles: Array = i.get("contact_roles", [])
	if roles.is_empty() or roles.has(role):
		return amount
	return 0.0
