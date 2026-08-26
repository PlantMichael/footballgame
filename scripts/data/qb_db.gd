class_name QBDB
extends RefCounted

## The five quarterbacks offered at the start of a run. Abilities lean into
## each QB's tag, in the risk/accuracy/decision-making vein of the QB
## signature mechanic.

const QUARTERBACKS := [
	{
		"name": "Colt Ferris",
		"tag": "Gunslinger arm, throws before the read is finished.",
		"strength": 3, "agility": 3, "dexterity": 5, "stamina": 3, "intelligence": 2,
		"ability_id": "gunslinger",
	},
	{
		"name": "Doc Halloway",
		"tag": "Field general, picks the defense apart before the snap.",
		"strength": 2, "agility": 2, "dexterity": 3, "stamina": 3, "intelligence": 5,
		"ability_id": "field_general",
	},
	{
		"name": "Jett Marlowe",
		"tag": "Scrambler, always looking for the seam to take off.",
		"strength": 2, "agility": 5, "dexterity": 3, "stamina": 4, "intelligence": 2,
		"ability_id": "down_and_distance",
	},
	{
		"name": "Boone Radcliff",
		"tag": "Bruiser, shrugs off the rush and keeps his feet.",
		"strength": 5, "agility": 2, "dexterity": 3, "stamina": 4, "intelligence": 2,
		"ability_id": "escape_artist",
	},
	{
		"name": "Wyatt Cole",
		"tag": "Steady all-rounder, no glaring weakness.",
		"strength": 3, "agility": 3, "dexterity": 3, "stamina": 3, "intelligence": 4,
		"ability_id": "clutch_gene",
	},
]


static func count() -> int:
	return QUARTERBACKS.size()


static func entry(id: int) -> Dictionary:
	return QUARTERBACKS[id]


static func make_player(rng: RandomNumberGenerator, id: int) -> PlayerData:
	var e: Dictionary = QUARTERBACKS[id]
	var p := PlayerData.new()
	p.pname = e["name"]
	p.pos = PlayerData.Pos.QB
	p.number = Generator.random_number(rng, PlayerData.Pos.QB)
	p.strength = e["strength"]
	p.agility = e["agility"]
	p.dexterity = e["dexterity"]
	p.stamina = e["stamina"]
	p.intelligence = e["intelligence"]
	p.ability_id = String(e.get("ability_id", ""))
	return p
