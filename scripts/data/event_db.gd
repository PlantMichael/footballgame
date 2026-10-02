class_name EventDB
extends RefCounted

## Mystery stops on the run map (GameState map, mystery.gd). Like Mewgenics'
## events, every one of these shapes the NEXT match rather than the run as a
## whole - the weather it's played in, who's banged up, what's on the field.
##
## Each event is a title, a little story, and 1-3 choices. A choice can:
##   gain     int  - football bucks paid out on the spot
##   cost     int  - football bucks it costs (the choice is disabled if you
##                  can't afford it)
##   effects  Dictionary - queued for the next match (GameState.add_match_mod):
##       weather          String WeatherDB id - the next match's weather
##       qb_mods          {stat: amount} - your starting QB, for that match
##       random_starter   int - every stat of one random starter, for that match
##       peels            int - banana peels scattered on the field each drive
##                        (they only trip defenders)
##       defense_quality  float - added to the next defense's quality
##       td_bucks_mult    float - multiplies the touchdown payout
##   note     String - how the effect is listed on the map screen ("" = none)
## A choice with no effects, gain or cost is just "walk away".

const EVENTS := {
	"bad_forecast": {
		"title": "Bad Forecast",
		"text": "The local weatherman looks grim. Sheets of rain are rolling in, right on top of your next kickoff.",
		"choices": [
			{"label": "Break out the ponchos", "effects": {"weather": WeatherDB.RAINY},
				"note": "Bad Forecast: rain"},
		],
	},
	"blizzard": {
		"title": "Blizzard Warning",
		"text": "A freak cold front is barreling down on the stadium. The grounds crew is already losing the fight.",
		"choices": [
			{"label": "Bundle up", "effects": {"weather": WeatherDB.SNOWY},
				"note": "Blizzard Warning: snow"},
		],
	},
	"gale": {
		"title": "Gale Warning",
		"text": "Flags around the stadium are standing straight out. Whatever your QB throws next game, the wind gets a vote.",
		"choices": [
			{"label": "Hold onto your hats", "effects": {"weather": WeatherDB.WINDY},
				"note": "Gale Warning: wind"},
		],
	},
	"shady_booster": {
		"title": "A Shady Booster",
		"text": "A man in a very expensive coat offers your quarterback an envelope of cash - and a long night out on the town before the next game.",
		"choices": [
			{"label": "Take the envelope (+$200, QB -2 Dexterity next game)", "gain": 200,
				"effects": {"qb_mods": {"dexterity": -2}}, "note": "Shady Booster: QB -2 DEX"},
			{"label": "Show him the door", "effects": {}},
		],
	},
	"cafeteria_tacos": {
		"title": "Cafeteria Taco Night",
		"text": "Half the locker room is lining up for the bathroom. The team doctor has a cure - for a price.",
		"choices": [
			{"label": "Pay the doctor (-$80)", "cost": 80, "effects": {}},
			{"label": "Tough it out (a random starter -2 to every stat next game)",
				"effects": {"random_starter": -2}, "note": "Bad Tacos"},
		],
	},
	"banana_truck": {
		"title": "Banana Truck Overturned",
		"text": "A produce truck flipped outside the stadium. Nobody has cleaned the field. The other team's cleats are not ready for this.",
		"choices": [
			{"label": "Leave them where they lie", "effects": {"peels": 6},
				"note": "Banana Truck: peels on the field"},
		],
	},
	"leaked_playbook": {
		"title": "A Reporter Calls",
		"text": "A reporter offers good money for an exclusive look at your playbook. Your next opponent reads that paper.",
		"choices": [
			{"label": "Sell it (+$150, next defense much tougher)", "gain": 150,
				"effects": {"defense_quality": 0.8}, "note": "Leaked Playbook: tougher defense"},
			{"label": "No comment", "effects": {}},
		],
	},
	"hype_machine": {
		"title": "Hype Machine",
		"text": "A sports network picks your next game for primetime. Every touchdown is going to be on every highlight reel in the country.",
		"choices": [
			{"label": "Smile for the cameras", "effects": {"td_bucks_mult": 2.0},
				"note": "Primetime: touchdowns pay double"},
		],
	},
}


static func all_ids() -> Array:
	return EVENTS.keys()


static func get_event(id: String) -> Dictionary:
	return EVENTS.get(id, {})


## One event id, preferring ones not in `exclude` (ids already on this run's
## map) so a run doesn't hand out the same story twice while others are left.
static func random_id(rng: RandomNumberGenerator, exclude: Dictionary = {}) -> String:
	var pool: Array = []
	for id in EVENTS:
		if not exclude.has(id):
			pool.append(id)
	if pool.is_empty():
		pool = EVENTS.keys()
	return String(pool[rng.randi_range(0, pool.size() - 1)])
