class_name AbilityDB
extends RefCounted

## Special abilities. Every player has exactly one.
##
## An ability is data plus a hook name. Hooks are resolved in the three places
## the sim asks about them:
##   snap    -> stat deltas applied for the duration of one play
##   catch   -> additive modifier to catch probability
##   contact -> additive modifier to winning a contact/push-off roll
##
## `ctx` is a Dictionary the sim fills in. Keys used below:
##   wr_count, te_count, rb_count : players of that position on the field
##   down, to_go, yards_to_endzone
##   is_carrier, target_is_deep, defenders_near, score_diff

const ABILITIES := {
	"corps_of_three": {
		"name": "Corps of Three",
		"desc": "+3 Agility if there are 2 other wide receivers on the field.",
		"hook": "snap",
	},
	"iron_anchor": {
		"name": "Iron Anchor",
		"desc": "+4 Strength on 3rd or 4th down.",
		"hook": "snap",
	},
	"sure_hands": {
		"name": "Sure Hands",
		"desc": "+8% catch chance on any throw.",
		"hook": "catch",
	},
	"contested_king": {
		"name": "Contested King",
		"desc": "+18% catch chance when a defender is within 2 yards.",
		"hook": "catch",
	},
	"deep_threat": {
		"name": "Deep Threat",
		"desc": "+2 Agility and +10% catch chance on throws 20+ yards downfield.",
		"hook": "both",
	},
	"red_zone_beast": {
		"name": "Red Zone Beast",
		"desc": "+3 Strength and +3 Dexterity inside the 20.",
		"hook": "snap",
	},
	"bulldozer": {
		"name": "Bulldozer",
		"desc": "+20% to win contact rolls while carrying the ball.",
		"hook": "contact",
	},
	"immovable": {
		"name": "Immovable",
		"desc": "+25% to win contact rolls while blocking.",
		"hook": "contact",
	},
	"film_study": {
		"name": "Film Study",
		"desc": "+4 Intelligence if 2 or more tight ends are on the field.",
		"hook": "snap",
	},
	"gunslinger": {
		"name": "Gunslinger",
		"desc": "+3 Dexterity, -2 Intelligence. Throws harder and sooner.",
		"hook": "snap",
	},
	"field_general": {
		"name": "Field General",
		"desc": "+3 Intelligence when trailing.",
		"hook": "snap",
	},
	"second_wind": {
		"name": "Second Wind",
		"desc": "+4 Stamina, and +2 Agility on 3rd down or later.",
		"hook": "snap",
	},
	"scat_back": {
		"name": "Scat Back",
		"desc": "+4 Agility if no other running backs are on the field.",
		"hook": "snap",
	},
	"possession_man": {
		"name": "Possession Man",
		"desc": "+12% catch chance when the throw gains a first down.",
		"hook": "catch",
	},
	"blindside_wall": {
		"name": "Blindside Wall",
		"desc": "+3 Strength and +2 Intelligence while pass blocking.",
		"hook": "snap",
	},
	"escape_artist": {
		"name": "Escape Artist",
		"desc": "+15% to break tackles, +1 Agility.",
		"hook": "contact",
	},
	"chain_mover": {
		"name": "Chain Mover",
		"desc": "+3 Strength and +2 Agility when 3 yards or fewer to go.",
		"hook": "snap",
	},
	"route_technician": {
		"name": "Route Technician",
		"desc": "+5 Intelligence, -1 Strength. Runs routes crisply.",
		"hook": "snap",
	},
	"workhorse": {
		"name": "Workhorse",
		"desc": "+5 Stamina. Never slows below 85% speed.",
		"hook": "snap",
	},
	"clutch_gene": {
		"name": "Clutch Gene",
		"desc": "+2 to every stat on 4th down.",
		"hook": "snap",
	},
	"spread_specialist": {
		"name": "Spread Specialist",
		"desc": "+3 Dexterity if 3 or more wide receivers are on the field.",
		"hook": "snap",
	},
	"goal_line_back": {
		"name": "Goal Line Back",
		"desc": "+5 Strength inside the 5 yard line.",
		"hook": "snap",
	},
}


static func get_ability(id: String) -> Dictionary:
	return ABILITIES.get(id, {})


static func ability_name(id: String) -> String:
	var a: Dictionary = ABILITIES.get(id, {})
	return a.get("name", "-")


static func ability_desc(id: String) -> String:
	var a: Dictionary = ABILITIES.get(id, {})
	return a.get("desc", "No special ability.")


static func all_ids() -> Array:
	return ABILITIES.keys()


## Stat deltas granted at the snap. Returns {stat_key: int}.
static func snap_bonus(id: String, p: PlayerData, ctx: Dictionary) -> Dictionary:
	var out := {}
	match id:
		"corps_of_three":
			if int(ctx.get("wr_count", 0)) - (1 if p.pos == PlayerData.Pos.WR else 0) >= 2:
				out["agility"] = 3
		"iron_anchor":
			if int(ctx.get("down", 1)) >= 3:
				out["strength"] = 4
		"deep_threat":
			if bool(ctx.get("target_is_deep", false)):
				out["agility"] = 2
		"red_zone_beast":
			if float(ctx.get("yards_to_endzone", 99.0)) <= 20.0:
				out["strength"] = 3
				out["dexterity"] = 3
		"film_study":
			if int(ctx.get("te_count", 0)) >= 2:
				out["intelligence"] = 4
		"gunslinger":
			out["dexterity"] = 3
			out["intelligence"] = -2
		"field_general":
			if int(ctx.get("score_diff", 0)) < 0:
				out["intelligence"] = 3
		"second_wind":
			out["stamina"] = 4
			if int(ctx.get("down", 1)) >= 3:
				out["agility"] = 2
		"scat_back":
			if int(ctx.get("rb_count", 0)) <= 1:
				out["agility"] = 4
		"blindside_wall":
			if not bool(ctx.get("is_run_play", false)):
				out["strength"] = 3
				out["intelligence"] = 2
		"escape_artist":
			out["agility"] = 1
		"chain_mover":
			if float(ctx.get("to_go", 10.0)) <= 3.0:
				out["strength"] = 3
				out["agility"] = 2
		"route_technician":
			out["intelligence"] = 5
			out["strength"] = -1
		"workhorse":
			out["stamina"] = 5
		"clutch_gene":
			if int(ctx.get("down", 1)) == 4:
				out["strength"] = 2
				out["agility"] = 2
				out["dexterity"] = 2
				out["stamina"] = 2
				out["intelligence"] = 2
		"spread_specialist":
			if int(ctx.get("wr_count", 0)) >= 3:
				out["dexterity"] = 3
		"goal_line_back":
			if float(ctx.get("yards_to_endzone", 99.0)) <= 5.0:
				out["strength"] = 5
	return out


## Additive modifier to catch probability (0.0-1.0 scale).
static func catch_mod(id: String, ctx: Dictionary) -> float:
	match id:
		"sure_hands":
			return 0.08
		"contested_king":
			if float(ctx.get("nearest_defender_dist", 99.0)) <= 2.0:
				return 0.18
		"deep_threat":
			if bool(ctx.get("target_is_deep", false)):
				return 0.10
		"possession_man":
			if bool(ctx.get("would_be_first_down", false)):
				return 0.12
	return 0.0


## Additive modifier to a contact/push-off roll (0.0-1.0 scale).
## `role` is "carry", "block", or "cover".
static func contact_mod(id: String, role: String) -> float:
	match id:
		"bulldozer":
			if role == "carry":
				return 0.20
		"immovable":
			if role == "block":
				return 0.25
		"escape_artist":
			if role == "carry":
				return 0.15
	return 0.0


## Floor on speed loss from fatigue, as a fraction of max speed.
static func fatigue_floor(id: String) -> float:
	if id == "workhorse":
		return 0.85
	return 0.65
