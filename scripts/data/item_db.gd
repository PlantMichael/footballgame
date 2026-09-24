class_name ItemDB
extends RefCounted

## Equippable items. Every player may hold exactly one.
## `mods` are flat stat changes. `catch`/`contact` are additive probability
## modifiers applied the same way abilities are.

const ITEMS := {
	"lead_vest": {
		"name": "Lead Vest",
		"desc": "+3 Strength, -1 Agility.",
		"cost": 90,
		"mods": {"strength": 3, "agility": -1},
	},
	"track_cleats": {
		"name": "Track Cleats",
		"desc": "+3 Agility, -1 Strength.",
		"cost": 90,
		"mods": {"agility": 3, "strength": -1},
	},
	"stickum_gloves": {
		"name": "Stickum Gloves",
		"desc": "+2 Dexterity and +6% catch chance.",
		"cost": 120,
		"mods": {"dexterity": 2},
		"catch": 0.06,
	},
	"wristband_script": {
		"name": "Wristband Script",
		"desc": "+3 Intelligence.",
		"cost": 85,
		"mods": {"intelligence": 3},
	},
	"oxygen_mask": {
		"name": "Oxygen Mask",
		"desc": "+5 Stamina. Fatigue sets in far later.",
		"cost": 75,
		"mods": {"stamina": 5},
	},
	"shoulder_cannons": {
		"name": "Shoulder Cannons",
		"desc": "+2 Strength and +12% on contact rolls.",
		"cost": 140,
		"mods": {"strength": 2},
		"contact": 0.12,
	},
	"greased_jersey": {
		"name": "Greased Jersey",
		"desc": "+18% to break tackles while carrying.",
		"cost": 130,
		"mods": {},
		"contact": 0.18,
		"contact_roles": ["carry"],
	},
	"lineman_mitts": {
		"name": "Lineman Mitts",
		"desc": "+20% on blocking contact rolls, -2 Dexterity.",
		"cost": 110,
		"mods": {"dexterity": -2},
		"contact": 0.20,
		"contact_roles": ["block"],
	},
	"visor_optics": {
		"name": "Visor Optics",
		"desc": "+2 Intelligence and +2 Dexterity.",
		"cost": 150,
		"mods": {"intelligence": 2, "dexterity": 2},
	},
	"weighted_ball": {
		"name": "Weighted Ball",
		"desc": "+4 Dexterity, -2 Intelligence. Big arm, questionable reads.",
		"cost": 125,
		"mods": {"dexterity": 4, "intelligence": -2},
	},
	"ankle_braces": {
		"name": "Ankle Braces",
		"desc": "+2 Agility and +2 Stamina.",
		"cost": 115,
		"mods": {"agility": 2, "stamina": 2},
	},
	"war_paint": {
		"name": "War Paint",
		"desc": "+1 to every stat.",
		"cost": 200,
		"mods": {"strength": 1, "agility": 1, "dexterity": 1, "stamina": 1, "intelligence": 1},
	},
	"foam_pads": {
		"name": "Foam Pads",
		"desc": "+4 Agility, -3 Strength.",
		"cost": 100,
		"mods": {"agility": 4, "strength": -3},
	},
	"chain_gang_belt": {
		"name": "Chain Gang Belt",
		"desc": "+10% catch chance, -1 Agility.",
		"cost": 120,
		"mods": {"agility": -1},
		"catch": 0.10,
	},
	"sacrificial_gloves": {
		"name": "Sacrificial Gloves",
		"desc": "At the end of the match, the player wearing these is sacrificed - you receive one random Cursed player in return.",
		"cost": 300,
		"mods": {},
	},
}


static func get_item(id: String) -> Dictionary:
	return ITEMS.get(id, {})


static func item_name(id: String) -> String:
	if id == "":
		return ""
	var i: Dictionary = ITEMS.get(id, {})
	return i.get("name", "?")


static func item_desc(id: String) -> String:
	var i: Dictionary = ITEMS.get(id, {})
	return i.get("desc", "")


static func item_cost(id: String) -> int:
	var i: Dictionary = ITEMS.get(id, {})
	return int(i.get("cost", 100))


static func all_ids() -> Array:
	return ITEMS.keys()


static func stat_mods(id: String) -> Dictionary:
	if id == "":
		return {}
	var i: Dictionary = ITEMS.get(id, {})
	return i.get("mods", {})


static func catch_mod(id: String) -> float:
	if id == "":
		return 0.0
	var i: Dictionary = ITEMS.get(id, {})
	return float(i.get("catch", 0.0))


static func contact_mod(id: String, role: String) -> float:
	if id == "":
		return 0.0
	var i: Dictionary = ITEMS.get(id, {})
	var amount := float(i.get("contact", 0.0))
	if amount == 0.0:
		return 0.0
	var roles: Array = i.get("contact_roles", [])
	if roles.is_empty() or roles.has(role):
		return amount
	return 0.0
