class_name Generator
extends RefCounted

## Procedural generation of players, opponents, and shop stock.

const FIRST_NAMES := [
	"Deion", "Marcus", "Trey", "Jamal", "Cooper", "Ezra", "Silas", "Boone",
	"Rashad", "Tyreek", "Dax", "Kellen", "Amari", "Bo", "Cade", "Jaylen",
	"Roman", "Odell", "Zane", "Micah", "Tank", "Quinn", "Rome", "Hollis",
	"Devante", "Isaiah", "Kaleb", "Rory", "Beau", "Nico", "Malachi", "Wes",
	"Duke", "Kai", "Sterling", "Ace", "Rowdy", "Junior", "Cash", "Titus",
]

const LAST_NAMES := [
	"Boone", "Ashford", "Vance", "Holloway", "Ridge", "Cutler", "Mangan",
	"Okafor", "Sandoval", "Petrov", "Lindqvist", "Boateng", "Ramsey", "Dunn",
	"Kowalski", "Delgado", "Fairbanks", "Nakamura", "Oyelaran", "Wexler",
	"Stallworth", "Crockett", "Bautista", "Renfroe", "Hargrove", "Tinsley",
	"Alderman", "Pruitt", "Vasquez", "Larkin", "Youngblood", "Castellanos",
	"Mbeki", "Sorensen", "Quintero", "Whitlock", "Amadi", "Rousseau",
]

const TEAM_CITIES := [
	"Ann Arbor", "Tallahassee", "Youngstown", "Akron", "Columbus", "St. Louis", "Alburquerque",
	"Spokane", "Shreveport", "Tulsa", "Tacoma", "Irvine", "Wichita",
	"Fresno", "Roanoke", "Bakersfield", "Salt Lake City", "Anchorage", "Fayetteville", "Erie",
]

const TEAM_MASCOTS := [
	"Bison", "Steeljacks", "Penguins", "Vultures", "Cutwaters", "Doxxers",
	"Unicorns", "Orangutans", "Kitties", "Combines", "Anvils", "Coyotes",
	"Marines", "Incels", "Steamers", "Bandits", "Skinwalkers", "Cryptids",
]

## Which stats each position leans on. Used to bias generated stat lines.
const POS_WEIGHTS := {
	PlayerData.Pos.QB: {"strength": 0.6, "agility": 0.8, "dexterity": 1.1, "stamina": 0.9, "intelligence": 1.5},
	PlayerData.Pos.C: {"strength": 1.6, "agility": 0.6, "dexterity": 0.4, "stamina": 1.1, "intelligence": 1.2},
	PlayerData.Pos.T: {"strength": 1.7, "agility": 0.6, "dexterity": 0.3, "stamina": 1.2, "intelligence": 0.9},
	PlayerData.Pos.RB: {"strength": 1.1, "agility": 1.5, "dexterity": 0.9, "stamina": 1.1, "intelligence": 0.8},
	PlayerData.Pos.WR: {"strength": 0.6, "agility": 1.4, "dexterity": 1.5, "stamina": 1.0, "intelligence": 1.0},
	PlayerData.Pos.TE: {"strength": 1.2, "agility": 0.9, "dexterity": 1.2, "stamina": 1.0, "intelligence": 1.0},
}

const STAT_KEYS := ["strength", "agility", "dexterity", "stamina", "intelligence"]

## Body sprite id (matches assets/players/{front,back,left}/body_0N.png) for
## procedurally generated players. Every position uses one fixed body type;
## shop players are exempt - their body is set by hand in shop_players.json.
const BODY_BY_POS := {
	PlayerData.Pos.QB: "5",
	PlayerData.Pos.C: "6",
	PlayerData.Pos.T: "2",
	PlayerData.Pos.RB: "5",
	PlayerData.Pos.WR: "9",
	PlayerData.Pos.TE: "1",
}

## NFL-style jersey number bands, inclusive. A position can have more than
## one legal band (e.g. a wide receiver can wear 1-49 or 80-89).
const NUMBER_BANDS := {
	PlayerData.Pos.QB: [[0, 19]],
	PlayerData.Pos.C: [[50, 79]],
	PlayerData.Pos.T: [[50, 79]],
	PlayerData.Pos.RB: [[0, 49], [80, 89]],
	PlayerData.Pos.WR: [[0, 49], [80, 89]],
	PlayerData.Pos.TE: [[0, 49], [80, 89]],
}

## Same idea for defense, keyed by role rather than PlayerData.Pos - the
## defensive generator reuses Pos purely to bias stats, not to mean the
## real position, so numbering has to key off the role string instead.
const DEFENSE_NUMBER_BANDS := {
	"DL": [[50, 79], [90, 99]],
	"LB": [[0, 59], [90, 99]],
	"DB": [[0, 49]],
}


static func random_number(rng: RandomNumberGenerator, pos: PlayerData.Pos) -> int:
	return _pick_from_bands(rng, NUMBER_BANDS.get(pos, [[1, 99]]))


static func random_defense_number(rng: RandomNumberGenerator, role: String) -> int:
	return _pick_from_bands(rng, DEFENSE_NUMBER_BANDS.get(role, [[1, 99]]))


static func _pick_from_bands(rng: RandomNumberGenerator, bands: Array) -> int:
	var total := 0
	for b in bands:
		total += int(b[1]) - int(b[0]) + 1
	var roll := rng.randi_range(0, total - 1)
	for b in bands:
		var span := int(b[1]) - int(b[0]) + 1
		if roll < span:
			return int(b[0]) + roll
		roll -= span
	return 1


static func random_name(rng: RandomNumberGenerator) -> String:
	return "%s %s" % [
		FIRST_NAMES[rng.randi_range(0, FIRST_NAMES.size() - 1)],
		LAST_NAMES[rng.randi_range(0, LAST_NAMES.size() - 1)],
	]


static func team_name(rng: RandomNumberGenerator) -> String:
	return "%s %s" % [
		TEAM_CITIES[rng.randi_range(0, TEAM_CITIES.size() - 1)],
		TEAM_MASCOTS[rng.randi_range(0, TEAM_MASCOTS.size() - 1)],
	]


## `quality` is roughly the average stat the player should land on (1-15).
## `spread` is the standard deviation; keep it small for the starting roster
## so every rookie really does land in the 2-4 band.
static func make_player(rng: RandomNumberGenerator, pos: PlayerData.Pos, quality: float,
		spread: float = 1.9, with_ability: bool = true) -> PlayerData:
	var p := PlayerData.new()
	p.pos = pos
	p.pname = random_name(rng)
	p.number = random_number(rng, pos)
	p.body = BODY_BY_POS.get(pos, p.body)

	var weights: Dictionary = POS_WEIGHTS[pos]
	for key in STAT_KEYS:
		var w := float(weights[key])
		# Center on quality, tilt by positional weight, then add spread.
		var base := quality * (0.55 + 0.45 * w)
		var value := base + rng.randfn(0.0, spread)
		p.add_stat(key, int(round(clampf(value, 1.0, 15.0))) - p.stat(key))

	p.ability_id = _pick_ability(rng, pos) if with_ability else ""
	return p


static func _pick_ability(rng: RandomNumberGenerator, pos: PlayerData.Pos) -> String:
	# Bias toward abilities that make sense for the position, but allow anything.
	# Pools lean into each position's signature mechanic (see design agenda):
	# QB = risk/accuracy/decision-making, RB = momentum/breaking tackles/agility,
	# WR = route progression/separation/big plays, TE = switching blocking &
	# receiving, T = blocking/protection/anchoring, C = buffing/coordinating
	# the line.
	var pool: Array = []
	match pos:
		PlayerData.Pos.QB:
			pool = ["gunslinger", "field_general", "pressure_reader", "clutch_gene", "film_study", "trusted_target_wr", "trusted_target_te"]
		PlayerData.Pos.C:
			pool = ["line_captain", "qb_whisperer", "power_scheme", "field_command", "spacing_coach", "immovable", "iron_anchor"]
		PlayerData.Pos.T:
			pool = ["immovable", "iron_anchor", "blindside_wall", "workhorse", "chain_mover", "lockdown_block"]
		PlayerData.Pos.RB:
			pool = ["bulldozer", "escape_artist", "scat_back", "goal_line_back", "chain_mover", "instant_burst", "power_surge", "phantom_step", "misdirection", "down_and_distance"]
		PlayerData.Pos.WR:
			pool = ["corps_of_three", "sure_hands", "deep_threat", "contested_king", "spread_specialist", "route_technician", "possession_man", "ghost_route"]
		PlayerData.Pos.TE:
			pool = ["red_zone_beast", "sure_hands", "contested_king", "film_study", "possession_man", "immovable", "cloaked_route", "guardian_angel", "lockdown_block"]
	if rng.randf() < 0.15:
		var all_ids: Array = AbilityDB.all_ids()
		return all_ids[rng.randi_range(0, all_ids.size() - 1)]
	return pool[rng.randi_range(0, pool.size() - 1)]


## A full starting roster: 1 QB, 1 C, 4 T, and 8 flex bodies plus a backup QB.
## Rookies land in the 2-4 stat band and have no special ability yet; both are
## things the shop is meant to fix over the course of a run.
const ROOKIE_QUALITY := 3.0
const ROOKIE_SPREAD := 0.55
const ROOKIE_MIN := 2
const ROOKIE_MAX := 4

static func starting_roster(rng: RandomNumberGenerator, quality: float = ROOKIE_QUALITY) -> Array[PlayerData]:
	var roster: Array[PlayerData] = []
	var q := quality
	var counts := {
		PlayerData.Pos.QB: 2, PlayerData.Pos.C: 1, PlayerData.Pos.T: 5,
		PlayerData.Pos.WR: 4, PlayerData.Pos.RB: 2, PlayerData.Pos.TE: 2,
	}
	for pos in counts:
		for i in int(counts[pos]):
			var p := make_player(rng, pos, q, ROOKIE_SPREAD, false)
			# Hard clamp: every rookie starts somewhere in the 2-4 band, whatever
			# the positional tilt would otherwise have rolled.
			for key in STAT_KEYS:
				var v: int = p.stat(key)
				p.add_stat(key, clampi(v, ROOKIE_MIN, ROOKIE_MAX) - v)
			roster.append(p)
	_dedupe_numbers(roster, rng)
	return roster


## Same shape as starting_roster (1 QB, 1 C, 5 T, 4 WR, 2 RB, 2 TE) but
## without the rookie clamp, abilities included - `quality` actually lands
## instead of always getting overwritten down to 2-4. Used by dev mode to
## build a maxed-out roster for testing.
static func full_roster(rng: RandomNumberGenerator, quality: float, spread: float = 1.0) -> Array[PlayerData]:
	var roster: Array[PlayerData] = []
	var counts := {
		PlayerData.Pos.QB: 2, PlayerData.Pos.C: 1, PlayerData.Pos.T: 5,
		PlayerData.Pos.WR: 4, PlayerData.Pos.RB: 2, PlayerData.Pos.TE: 2,
	}
	for pos in counts:
		for i in int(counts[pos]):
			roster.append(make_player(rng, pos, quality, spread, true))
	_dedupe_numbers(roster, rng)
	return roster


static func _dedupe_numbers(roster: Array[PlayerData], rng: RandomNumberGenerator) -> void:
	var used := {}
	for p in roster:
		var guard := 0
		while used.has(p.number) and guard < 200:
			p.number = random_number(rng, p.pos)
			guard += 1
		used[p.number] = true


## An opponent defense. `strength_rating` is the average defensive stat.
## `aura_chance` (see GameState.aura_chance) is the odds that ONE random
## defender on this unit spawns with a colored aura (AuraDB) - never more
## than one per match.
static func make_defense(rng: RandomNumberGenerator, strength_rating: float, aura_chance: float = 0.0) -> Array[PlayerData]:
	var d: Array[PlayerData] = []
	# 4 linemen, 3 linebackers, 4 defensive backs.
	for i in 4:
		d.append(_make_defender(rng, "DL", strength_rating))
	for i in 3:
		d.append(_make_defender(rng, "LB", strength_rating))
	for i in 4:
		d.append(_make_defender(rng, "DB", strength_rating))
	if rng.randf() < aura_chance:
		var auras: Array = AuraDB.all_ids()
		d[rng.randi_range(0, d.size() - 1)].aura_id = auras[rng.randi_range(0, auras.size() - 1)]
	return d


static func _make_defender(rng: RandomNumberGenerator, role: String, quality: float) -> PlayerData:
	var p := PlayerData.new()
	p.pname = random_name(rng)
	p.number = random_defense_number(rng, role)
	var weights: Dictionary
	match role:
		"DL":
			weights = {"strength": 1.6, "agility": 1.0, "dexterity": 0.5, "stamina": 1.1, "intelligence": 0.8}
			p.pos = PlayerData.Pos.T
		"LB":
			weights = {"strength": 1.3, "agility": 1.1, "dexterity": 0.8, "stamina": 1.1, "intelligence": 1.2}
			p.pos = PlayerData.Pos.TE
		_:
			weights = {"strength": 0.8, "agility": 1.5, "dexterity": 1.1, "stamina": 1.0, "intelligence": 1.2}
			p.pos = PlayerData.Pos.WR
	for key in STAT_KEYS:
		var w := float(weights[key])
		var value := quality * (0.55 + 0.45 * w) + rng.randfn(0.0, maxf(0.5, quality * 0.16))
		p.add_stat(key, int(round(clampf(value, 1.0, 15.0))) - p.stat(key))
	p.body = BODY_BY_POS.get(p.pos, p.body)
	return p


## Roguelike-style pricing: driven mostly by rarity tier, so a single All
## Star costs most of what one win pays out, with a smaller nudge from the
## player's own stat line so two players of the same tier aren't identical.
const TIER_BASE_PRICE := {0: 60, 1: 80, 2: 160, 3: 300, 4: 500}
const TIER_OVERALL_MULT := 10

static func player_price(p: PlayerData) -> int:
	if p.quality > 0:
		var base: int = TIER_BASE_PRICE.get(p.quality, 300)
		return int(clampi(base + p.overall() * TIER_OVERALL_MULT, base, 900))
	var ovr := p.overall()
	return int(clampi(60 + ovr * ovr * 2, 80, 600))
