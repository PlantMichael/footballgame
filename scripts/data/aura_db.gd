class_name AuraDB
extends RefCounted

## Difficulty-scaled defender auras (see GameState.aura_chance and
## Generator.make_defense). At most one defender per match spawns with one of
## these, colored so he stands out on the field (see field_view.gd).
##
## Unlike AbilityDB, this isn't a generic hook registry - each aura is a single
## one-off behavior wired directly at its call site in match_sim.gd/sim_player.gd
## (same style as the ability-specific _apply_distraction/_apply_taunt), since
## there's no shared shape across 5 entries to justify a dispatch layer.

const SPEEDFREAK := "speedfreak"
const BIG_BLOCKER := "big_blocker"
const STRONGMAN := "strongman"
const MIND_READER := "mind_reader"
const BUTTER_FINGERS := "butter_fingers"

const AURAS := {
	SPEEDFREAK: {
		"name": "Speedfreak",
		"color": Color("5ad65a"),
		"desc": "Speeds up the longer the play goes on.",
	},
	BIG_BLOCKER: {
		"name": "Big Blocker",
		"color": Color("5aa9e6"),
		"desc": "Tackles ball carriers more easily.",
	},
	STRONGMAN: {
		"name": "Strongman",
		"color": Color("d94c4c"),
		"desc": "Always overpowers whoever he's blocking - the bigger the Strength gap, the faster.",
	},
	MIND_READER: {
		"name": "Mind Reader",
		"color": Color("b060e0"),
		"desc": "Finds whoever's most open and goes straight after him.",
	},
	BUTTER_FINGERS: {
		"name": "Butter Fingers",
		"color": Color("e6d24c"),
		"desc": "Lowers the Dexterity of any opposing player within 5 yards of him.",
	},
}

## Speedfreak: speed multiplier ramps by this much per second of live play,
## capped at SPEEDFREAK_MAX_MULT extra.
const SPEEDFREAK_RAMP := 0.05
const SPEEDFREAK_MAX_MULT := 0.6

## Big Blocker: flat additive bonus to the tackle-chance roll.
const BIG_BLOCKER_TACKLE_BONUS := 0.15

## Strongman: always sheds his block; the interval before he can do it again
## (if re-engaged) shrinks with his Strength edge over the blocker, down to a
## floor so it's never instant.
const STRONGMAN_BASE_INTERVAL := 3.0
const STRONGMAN_MIN_INTERVAL := 0.6
const STRONGMAN_INTERVAL_PER_STR := 0.18

## Butter Fingers: Dexterity penalty applied to anyone within this radius
## (yards), at the two points Dexterity actually matters in the sim - QB
## throw accuracy and receiver catch chance.
const BUTTER_FINGERS_RADIUS := 5.0
const BUTTER_FINGERS_DEX_PENALTY := 4


static func all_ids() -> Array:
	return AURAS.keys()


static func aura_name(id: String) -> String:
	return AURAS.get(id, {}).get("name", "-")


static func aura_color(id: String) -> Color:
	return AURAS.get(id, {}).get("color", Color.WHITE)


static func aura_desc(id: String) -> String:
	return AURAS.get(id, {}).get("desc", "")
