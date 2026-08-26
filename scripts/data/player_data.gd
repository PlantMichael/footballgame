class_name PlayerData
extends Resource

## A single football player. Stats are 1-15; stamina is hidden from the UI
## per the design doc but drives in-play fatigue.

enum Pos { QB, C, T, RB, WR, TE }

const POS_NAMES := ["QB", "C", "T", "RB", "WR", "TE"]

@export var pname: String = "Player"
@export var pos: Pos = Pos.WR
@export var number: int = 0

@export var strength: int = 8
@export var agility: int = 8
@export var dexterity: int = 8
@export var stamina: int = 8
@export var intelligence: int = 8

@export var ability_id: String = ""
@export var item_id: String = ""

## Rarity tier for hardcoded shop players (1 Rookie - 4 All Star). 0 means
## this player was procedurally generated and has no fixed tier.
@export var quality: int = 0
## Body sprite id, e.g. "6" for assets/players/{front,back,left}/body_06.png.
## Fixed per position for procedurally generated players (see
## Generator.BODY_BY_POS); set by hand per entry for shop players.
@export var body: String = "medium"


func pos_name() -> String:
	return POS_NAMES[pos]


## Slot family this player is naturally suited to.
## Lineup slots are C, QB, T x4, FLEX x5 (RB/WR/TE).
func natural_slot_kind() -> String:
	match pos:
		Pos.QB: return "QB"
		Pos.C: return "C"
		Pos.T: return "T"
		_: return "FLEX"


func overall() -> int:
	# Weighted by what the position actually does. Stamina is excluded from
	# the visible rating since the player never sees it.
	match pos:
		Pos.QB:
			return int(round(intelligence * 0.45 + dexterity * 0.25 + agility * 0.2 + strength * 0.1))
		Pos.C, Pos.T:
			return int(round(strength * 0.55 + intelligence * 0.25 + agility * 0.2))
		Pos.RB:
			return int(round(agility * 0.4 + strength * 0.3 + dexterity * 0.15 + intelligence * 0.15))
		Pos.TE:
			return int(round(dexterity * 0.35 + strength * 0.3 + agility * 0.2 + intelligence * 0.15))
		_:
			return int(round(dexterity * 0.4 + agility * 0.35 + intelligence * 0.15 + strength * 0.1))


func stat(key: String) -> int:
	match key:
		"strength": return strength
		"agility": return agility
		"dexterity": return dexterity
		"stamina": return stamina
		"intelligence": return intelligence
	return 0


func add_stat(key: String, amount: int) -> void:
	match key:
		"strength": strength = clampi(strength + amount, 1, 15)
		"agility": agility = clampi(agility + amount, 1, 15)
		"dexterity": dexterity = clampi(dexterity + amount, 1, 15)
		"stamina": stamina = clampi(stamina + amount, 1, 15)
		"intelligence": intelligence = clampi(intelligence + amount, 1, 15)


func duplicate_player() -> PlayerData:
	var p := PlayerData.new()
	p.pname = pname
	p.pos = pos
	p.number = number
	p.strength = strength
	p.agility = agility
	p.dexterity = dexterity
	p.stamina = stamina
	p.intelligence = intelligence
	p.ability_id = ability_id
	p.item_id = item_id
	p.quality = quality
	p.body = body
	return p
