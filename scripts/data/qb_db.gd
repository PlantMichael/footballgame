class_name QBDB
extends RefCounted

## The five quarterbacks offered at the start of a run. Abilities lean into
## each QB's tag. An entry's index is its id in MetaState's bowl marks, so
## reordering or replacing one needs a migration there.
##
## "number" is his fixed jersey number (the QB select card shows it, so it
## mustn't change once he's picked), and "diagram" the chalk play on that
## card - see ChalkDiagram for the format.

const QUARTERBACKS := [
	{
		"name": "John Football",
		"number": 10,
		# A plain pass: slant left, go route right.
		"diagram": {
			"o": [Vector2(100, 72), Vector2(45, 56), Vector2(155, 56)],
			"x": [Vector2(68, 36), Vector2(150, 30)],
			"routes": [[Vector2(45, 56), Vector2(45, 42), Vector2(80, 20)], [Vector2(155, 56), Vector2(155, 10)]],
		},
		"tag": "Your average quarterback. No tricks, no gimmicks.",
		"strength": 3, "agility": 3, "dexterity": 4, "stamina": 3, "intelligence": 4,
		"ability_id": "",
		"body": "1",
	},
	{
		"name": "Francis Fasthands",
		"number": 12,
		# Quick hands: a flip to the back, everyone else already moving.
		"diagram": {
			"o": [Vector2(100, 72), Vector2(60, 56), Vector2(140, 56)],
			"x": [Vector2(96, 40), Vector2(126, 34)],
			"routes": [[Vector2(100, 72), Vector2(78, 68), Vector2(55, 40)],
				[Vector2(140, 56), Vector2(140, 26), Vector2(175, 14)], [Vector2(60, 56), Vector2(60, 18)]],
		},
		"tag": "Quick feet, quicker hands - everyone around him speeds up.",
		"strength": 2, "agility": 4, "dexterity": 4, "stamina": 3, "intelligence": 2,
		"ability_id": "fast_hands",
		"body": "2",
	},
	{
		"name": "Tony Pigskin",
		"number": 8,
		# A heavy package: four bodies on the line, power up the middle.
		"diagram": {
			"o": [Vector2(100, 78), Vector2(78, 56), Vector2(92, 56), Vector2(108, 56), Vector2(122, 56), Vector2(100, 66)],
			"x": [Vector2(88, 40), Vector2(112, 38), Vector2(100, 28)],
			"routes": [[Vector2(100, 66), Vector2(100, 46), Vector2(104, 14)]],
		},
		"tag": "Loves a heavy package - the more of a position, the merrier.",
		"strength": 3, "agility": 3, "dexterity": 3, "stamina": 3, "intelligence": 4,
		"ability_id": "strength_in_numbers",
		"body": "4",
	},
	{
		"name": "Luke Luckyfingers",
		"number": 3,
		# The ball finds its man: a deep shot dropped right in his hands.
		"diagram": {
			"o": [Vector2(100, 72), Vector2(150, 56)],
			"x": [Vector2(136, 24), Vector2(160, 30)],
			"routes": [[Vector2(150, 56), Vector2(150, 14)]],
			"throws": [[Vector2(100, 72), Vector2(118, 30), Vector2(148, 14)]],
		},
		"tag": "Doesn't always know how, but the ball finds its man.",
		"strength": 2, "agility": 3, "dexterity": 4, "stamina": 3, "intelligence": 3,
		"ability_id": "lucky_fingers",
		"body": "5",
	},
	{
		"name": "Jett Marlowe",
		"number": 7,
		# The scramble: out of the pocket and up the seam.
		"diagram": {
			"o": [Vector2(100, 72)],
			"x": [Vector2(100, 48), Vector2(122, 56)],
			"routes": [[Vector2(100, 72), Vector2(126, 76), Vector2(144, 62), Vector2(140, 40), Vector2(152, 20), Vector2(166, 10)]],
		},
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
	p.number = int(e.get("number", Generator.random_number(rng, PlayerData.Pos.QB)))
	p.strength = e["strength"]
	p.agility = e["agility"]
	p.dexterity = e["dexterity"]
	p.stamina = e["stamina"]
	p.intelligence = e["intelligence"]
	p.ability_id = String(e.get("ability_id", ""))
	p.body = String(e.get("body", "1"))
	p.head_id = String(e.get("head", Generator.random_head_id(rng)))
	return p
