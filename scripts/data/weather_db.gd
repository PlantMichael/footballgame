class_name WeatherDB
extends RefCounted

## Match weather. The first match of a run is always clear; after that each
## match rolls its weather when the previous one ends (GameState.finish_match
## -> GameState.next_weather), so the hub can show the forecast before
## kickoff. MatchSim applies the stat effects at every snap (_apply_weather)
## and owns the rain puddles; field_view.gd draws the rest.

const CLEAR := "clear"
const WINDY := "windy"
const RAINY := "rainy"
const SNOWY := "snowy"

## Order the dev-mode Weather button cycles through.
const ALL := [CLEAR, WINDY, RAINY, SNOWY]

const WEATHER := {
	CLEAR: {"name": "Clear", "desc": "No weather effects."},
	WINDY: {"name": "Windy", "desc": "Quarterbacks have -2 Dexterity (never below 2)."},
	RAINY: {"name": "Rainy", "desc": "Every player has -2 Agility. Puddles form on the field and slow anyone who runs through them."},
	SNOWY: {"name": "Snowy", "desc": "Every player has -2 Strength."},
}

## Relative odds for a match after the first. Clear still comes up, so the
## weather is an occasional twist rather than a constant.
const ROLL_WEIGHTS := {CLEAR: 4.0, WINDY: 2.0, RAINY: 2.0, SNOWY: 2.0}

const WINDY_QB_DEX := -2
const WINDY_QB_DEX_FLOOR := 2
const RAINY_AGILITY := -2
const SNOWY_STRENGTH := -2

## Rain puddles: how many are on the field at kickoff, how many more form
## every drive, their radius range in yards, and the speed multiplier while
## standing in one.
const PUDDLES_AT_START := 26
const PUDDLES_PER_DRIVE := 4
const PUDDLE_RADIUS_MIN := 1.2
const PUDDLE_RADIUS_MAX := 2.6
const PUDDLE_SPEED_MULT := 0.6


static func weather_name(id: String) -> String:
	return String(WEATHER.get(id, WEATHER[CLEAR])["name"])


static func weather_desc(id: String) -> String:
	return String(WEATHER.get(id, WEATHER[CLEAR])["desc"])


static func roll(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for id in ROLL_WEIGHTS:
		total += float(ROLL_WEIGHTS[id])
	var r := rng.randf() * total
	for id in ROLL_WEIGHTS:
		r -= float(ROLL_WEIGHTS[id])
		if r <= 0.0:
			return id
	return CLEAR


## Next id in ALL after `id`, wrapping - the dev-mode Weather button.
static func next_in_cycle(id: String) -> String:
	var i := ALL.find(id)
	return ALL[(i + 1) % ALL.size()]
