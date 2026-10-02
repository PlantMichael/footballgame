class_name BowlDB
extends RefCounted

## The 6 bowls a run can end in, and the 3 branch choices that funnel toward
## them. GameState._build_bracket appends the bowl as the run's 5th and final
## match; needs_branch_choice/needs_bowl_choice/choose_branch/choose_bowl walk
## the coach through picking one after rounds 0 and 1. Each starting QB earns
## a permanent completion mark per bowl won (see MetaState), Isaac-style.

const BOWLS := {
	"superbowl": {
		"name": "Superb Bowl",
		"branch": "spotlight",
		"quality_mult": 1.35,
		"win_bonus": 300,
		"desc": "The one every coach dreams about.",
		"logo_cell": Vector2i(0, 0),
	},
	"pro_bowl": {
		"name": "Pro Bowl",
		"branch": "spotlight",
		"quality_mult": 1.15,
		"win_bonus": 220,
		"desc": "An All-Star showcase against the league's best.",
		"logo_cell": Vector2i(1, 0),
	},
	"olympic_bowl": {
		"name": "Olympic Bowl",
		"branch": "wild",
		"quality_mult": 1.05,
		"win_bonus": 190,
		"desc": "An international exhibition, ratings-hungry and unpredictable.",
		"logo_cell": Vector2i(2, 0),
	},
	"alligator_bowl": {
		"name": "Alligator Bowl",
		"branch": "wild",
		"quality_mult": 0.95,
		"win_bonus": 170,
		"desc": "A swampy mid-tier bowl with teeth.",
		"logo_cell": Vector2i(0, 1),
	},
	"gleech_bowl": {
		"name": "G. Leech Bowl",
		"branch": "grind",
		"quality_mult": 0.85,
		"win_bonus": 150,
		"desc": "Named for its longtime sponsor. Nobody's proud of this one.",
		"logo_cell": Vector2i(2, 1),
	},
	"toilet_bowl": {
		"name": "Toilet Bowl",
		"branch": "grind",
		"quality_mult": 0.75,
		"win_bonus": 130,
		"desc": "For the teams playing out the string.",
		"logo_cell": Vector2i(1, 1),
	},
}

## assets/bowl.png is a hand-drawn 3x2 sheet of the 6 bowl logos, one square
## cell each - see each entry's "logo_cell" above for which. The game uses
## assets/bowl_cut.png, the same sheet with the white paper cut away
## (assets/_cut_bowls.py), so a logo can sit straight on any background.
## Sliced with AtlasTexture (a view onto the shared sheet, not a copy) and
## cached so every call site sharing a bowl id shares one texture instance.
const LOGO_SHEET := "res://assets/bowl_cut.png"
const LOGO_CELL_PX := 512

static var _logo_sheet: Texture2D
static var _logo_cache: Dictionary = {}


## This bowl's logo, cropped from the shared sheet, or null if the sheet or
## this id's cell is missing - callers should skip the badge rather than
## show a blank square.
static func logo(id: String) -> Texture2D:
	if _logo_cache.has(id):
		return _logo_cache[id]
	var cell: Vector2i = BOWLS.get(id, {}).get("logo_cell", Vector2i(-1, -1))
	if cell.x < 0:
		return null
	if _logo_sheet == null:
		if not ResourceLoader.exists(LOGO_SHEET):
			return null
		_logo_sheet = load(LOGO_SHEET)
	var at := AtlasTexture.new()
	at.atlas = _logo_sheet
	at.region = Rect2(Vector2(cell.x, cell.y) * LOGO_CELL_PX, Vector2(LOGO_CELL_PX, LOGO_CELL_PX))
	_logo_cache[id] = at
	return at

const BRANCHES := {
	"spotlight": {
		"name": "The Spotlight",
		"desc": "Chase the biggest stage in the sport.",
		"bowls": ["superbowl", "pro_bowl"],
	},
	"wild": {
		"name": "The Wild Route",
		"desc": "Anything can happen out here.",
		"bowls": ["olympic_bowl", "alligator_bowl"],
	},
	"grind": {
		"name": "The Grind",
		"desc": "Ugly football, low stakes, still a bowl.",
		"bowls": ["gleech_bowl", "toilet_bowl"],
	},
}


## Bowl gimmicks: each bowl can field one named special defender whose mere
## presence changes the game - see place_gimmick_player (match.gd puts him in
## the bowl game's defense) and MatchSim._gimmick_active for the effects.
## `defense_index` is his spot in Generator.make_defense's lineup (0-3 DL,
## 4-6 LB, 7-10 DB); index 1 is the inside-left lineman, the closest the
## defense has to a center. A bowl missing from here has no special player.
## Weather still rolls for a bowl game like any other match.
const GIMMICK_COLOR := Color("9d4dff")
const DESTROYER := "destroyer"
const IRON_WALL := "iron_wall"

const GIMMICKS := {
	DESTROYER: {
		"bowl": "pro_bowl",
		"name": "Deshawn the Destroyer",
		"defense_index": 4,
		"effect": "Running backs suffer -4 Agility.",
	},
	IRON_WALL: {
		"bowl": "toilet_bowl",
		"name": "Marcus Williams, the Iron Wall",
		"defense_index": 1,
		"effect": "All your linemen's abilities are negated, not counting your center.",
	},
}

## RB Agility penalty while Deshawn the Destroyer is on the field.
const DESTROYER_RB_AGILITY := -4


static func gimmick_for_bowl(bowl_id: String) -> String:
	for id in GIMMICKS:
		if GIMMICKS[id]["bowl"] == bowl_id:
			return id
	return ""


static func gimmick_name(id: String) -> String:
	return String(GIMMICKS.get(id, {}).get("name", ""))


static func gimmick_effect(id: String) -> String:
	return String(GIMMICKS.get(id, {}).get("effect", ""))


## Turns one generated defender into `bowl_id`'s special player, if it has
## one: his name, and his gimmick. He keeps the generated stat line (so he
## scales with the bowl's difficulty like everyone else) but never an aura
## on top of it - one special thing per player.
static func place_gimmick_player(defense: Array, bowl_id: String) -> void:
	var id := gimmick_for_bowl(bowl_id)
	if id == "":
		return
	var idx := int(GIMMICKS[id]["defense_index"])
	if idx < 0 or idx >= defense.size():
		return
	var p: PlayerData = defense[idx]
	p.pname = gimmick_name(id)
	p.gimmick_id = id
	p.aura_id = ""


static func all_ids() -> Array:
	return BOWLS.keys()


static func bowl_name(id: String) -> String:
	return BOWLS.get(id, {}).get("name", "The Bowl")


static func quality_mult(id: String) -> float:
	return float(BOWLS.get(id, {}).get("quality_mult", 1.0))


static func win_bonus(id: String) -> int:
	return int(BOWLS.get(id, {}).get("win_bonus", 150))


static func bowl_desc(id: String) -> String:
	return String(BOWLS.get(id, {}).get("desc", ""))


static func branch_of(id: String) -> String:
	return String(BOWLS.get(id, {}).get("branch", ""))


static func bowls_in_branch(branch_id: String) -> Array:
	return BRANCHES.get(branch_id, {}).get("bowls", [])


static func all_branches() -> Array:
	return BRANCHES.keys()


static func branch_name(id: String) -> String:
	return String(BRANCHES.get(id, {}).get("name", id))


static func branch_desc(id: String) -> String:
	return String(BRANCHES.get(id, {}).get("desc", ""))
