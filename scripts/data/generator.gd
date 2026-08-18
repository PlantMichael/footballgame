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
	p.number = rng.randi_range(1, 99)

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
	var pool: Array = []
	match pos:
		PlayerData.Pos.QB:
			pool = ["gunslinger", "field_general", "film_study", "clutch_gene", "second_wind", "route_technician"]
		PlayerData.Pos.C, PlayerData.Pos.T:
			pool = ["immovable", "iron_anchor", "blindside_wall", "workhorse", "clutch_gene", "chain_mover"]
		PlayerData.Pos.RB:
			pool = ["bulldozer", "escape_artist", "scat_back", "workhorse", "goal_line_back", "chain_mover"]
		PlayerData.Pos.WR:
			pool = ["corps_of_three", "sure_hands", "deep_threat", "contested_king", "spread_specialist", "route_technician", "possession_man"]
		PlayerData.Pos.TE:
			pool = ["red_zone_beast", "sure_hands", "contested_king", "film_study", "possession_man", "immovable"]
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


static func _dedupe_numbers(roster: Array[PlayerData], rng: RandomNumberGenerator) -> void:
	var used := {}
	for p in roster:
		while used.has(p.number):
			p.number = rng.randi_range(1, 99)
		used[p.number] = true


## An opponent defense. `strength_rating` is the average defensive stat.
static func make_defense(rng: RandomNumberGenerator, strength_rating: float) -> Array[PlayerData]:
	var d: Array[PlayerData] = []
	# 4 linemen, 3 linebackers, 4 defensive backs.
	for i in 4:
		d.append(_make_defender(rng, "DL", strength_rating))
	for i in 3:
		d.append(_make_defender(rng, "LB", strength_rating))
	for i in 4:
		d.append(_make_defender(rng, "DB", strength_rating))
	return d


static func _make_defender(rng: RandomNumberGenerator, role: String, quality: float) -> PlayerData:
	var p := PlayerData.new()
	p.pname = random_name(rng)
	p.number = rng.randi_range(1, 99)
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
	return p


## Draft board offered in the shop.
static func draft_class(rng: RandomNumberGenerator, count: int, quality: float) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for i in count:
		# Flex bodies show up more often than centers and quarterbacks.
		var roll := rng.randf()
		var pos: PlayerData.Pos
		if roll < 0.10:
			pos = PlayerData.Pos.QB
		elif roll < 0.18:
			pos = PlayerData.Pos.C
		elif roll < 0.40:
			pos = PlayerData.Pos.T
		elif roll < 0.58:
			pos = PlayerData.Pos.RB
		elif roll < 0.82:
			pos = PlayerData.Pos.WR
		else:
			pos = PlayerData.Pos.TE
		out.append(make_player(rng, pos, quality + rng.randf_range(-1.0, 2.0)))
	return out


static func player_price(p: PlayerData) -> int:
	var ovr := p.overall()
	return int(clampi(60 + ovr * ovr * 2, 80, 600))
