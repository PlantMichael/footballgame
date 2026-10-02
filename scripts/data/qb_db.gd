class_name QBDB
extends RefCounted

## The five quarterbacks offered at the start of a run. Abilities lean into
## each QB's tag. An entry's index is its id in MetaState's bowl marks, so
## reordering or replacing one needs a migration there.

const QUARTERBACKS := [
	{
		"name": "John Football",
		"tag": "Your average quarterback. No tricks, no gimmicks.",
		"strength": 3, "agility": 3, "dexterity": 4, "stamina": 3, "intelligence": 4,
		"ability_id": "",
		"body": "1",
	},
	{
		"name": "Francis Fasthands",
		"tag": "Quick feet, quicker hands - everyone around him speeds up.",
		"strength": 2, "agility": 4, "dexterity": 4, "stamina": 3, "intelligence": 2,
		"ability_id": "fast_hands",
		"body": "2",
	},
	{
		"name": "Tony Pigskin",
		"tag": "Loves a heavy package - the more of a position, the merrier.",
		"strength": 3, "agility": 3, "dexterity": 3, "stamina": 3, "intelligence": 4,
		"ability_id": "strength_in_numbers",
		"body": "4",
	},
	{
		"name": "Luke Luckyfingers",
		"tag": "Doesn't always know how, but the ball finds its man.",
		"strength": 2, "agility": 3, "dexterity": 4, "stamina": 3, "intelligence": 3,
		"ability_id": "lucky_fingers",
		"body": "5",
	},
	{
		"name": "Jett Marlowe",
		"tag": "Scrambler, always looking for the seam to take off.",
		"strength": 2, "agility": 5, "dexterity": 3, "stamina": 4, "intelligence": 2,
		"ability_id": "down_and_distance",
		"body": "3",
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
	p.body = String(e.get("body", "1"))
	p.head_id = String(e.get("head", Generator.random_head_id(rng)))
	return p
