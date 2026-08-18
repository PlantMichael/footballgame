class_name PlayDB
extends RefCounted

## The playbook.
##
## Geometry convention (all values in YARDS, local to the formation):
##   align: Vector2(x, y) where x is depth relative to the line of scrimmage
##          (negative = in the backfield) and y is lateral offset from the
##          center (negative = left of center from the offense's view).
##   route: an Array of Vector2 waypoints RELATIVE TO THE PLAYER'S ALIGNMENT,
##          in the same x-downfield / y-lateral frame.
##
## An assignment is either an Array of waypoints (a route), or one of the
## strings "block" (stay in and protect) or "carry" (take the handoff).

const BLOCK := "block"
const CARRY := "carry"

static var _plays: Dictionary = {}


static func _build() -> void:
	if not _plays.is_empty():
		return
	var p := {}

	p["quick_outs"] = {
		"name": "Quick Outs",
		"desc": "Three-step drop with breaking outs. Safe, fast, moves the chains.",
		"kind": "pass",
		"cost": 0,
		"dropback": 0.9,
		"align": [Vector2(0, -20), Vector2(0, -11), Vector2(0, 11), Vector2(0, 20), Vector2(-5, -3)],
		"slot_pos": ["WR", "WR", "TE", "WR", "RB"],
		"routes": [
			[Vector2(6, 0), Vector2(7, -5)],
			[Vector2(8, 0), Vector2(9, -4)],
			[Vector2(7, 0), Vector2(8, 4)],
			[Vector2(6, 0), Vector2(7, 5)],
			BLOCK,
		],
		"progression": [1, 2, 0, 3],
	}

	p["slant_flood"] = {
		"name": "Slant Flood",
		"desc": "Slants underneath with a flood to the right. Beats soft coverage.",
		"kind": "pass",
		"cost": 0,
		"dropback": 1.1,
		"align": [Vector2(0, -18), Vector2(0, -9), Vector2(0, 9), Vector2(0, 18), Vector2(-5, 2)],
		"slot_pos": ["WR", "WR", "TE", "WR", "RB"],
		"routes": [
			[Vector2(4, 0), Vector2(12, 7)],
			[Vector2(3, 0), Vector2(10, 6)],
			[Vector2(5, 0), Vector2(14, 3)],
			[Vector2(12, 0), Vector2(13, 6)],
			[Vector2(1, 4), Vector2(2, 10)],
		],
		"progression": [1, 0, 2, 4, 3],
	}

	p["curl_and_out"] = {
		"name": "Curl & Out",
		"desc": "Curls at the sticks with outs behind them. A chain-moving staple.",
		"kind": "pass",
		"cost": 0,
		"dropback": 1.5,
		"align": [Vector2(0, -19), Vector2(0, -10), Vector2(0, 10), Vector2(0, 19), Vector2(-5, -2)],
		"slot_pos": ["WR", "TE", "TE", "WR", "RB"],
		"routes": [
			[Vector2(11, 0), Vector2(9, -1)],
			[Vector2(8, 0), Vector2(9, -6)],
			[Vector2(8, 0), Vector2(9, 6)],
			[Vector2(11, 0), Vector2(9, 1)],
			BLOCK,
		],
		"progression": [0, 3, 1, 2],
	}

	p["hb_dive"] = {
		"name": "HB Dive",
		"desc": "Straight ahead handoff. Grinds out yards when you need three.",
		"kind": "run",
		"cost": 0,
		"dropback": 0.4,
		"align": [Vector2(0, -17), Vector2(-1, -6), Vector2(-1, 6), Vector2(0, 17), Vector2(-6, 0)],
		"slot_pos": ["WR", "TE", "TE", "WR", "RB"],
		"routes": [
			[Vector2(9, 0)],
			BLOCK,
			BLOCK,
			[Vector2(9, 0)],
			CARRY,
		],
		"progression": [4],
	}

	p["four_verticals"] = {
		"name": "Four Verticals",
		"desc": "Everybody runs deep. Boom or bust, and it needs time to protect.",
		"kind": "pass",
		"cost": 160,
		"dropback": 2.4,
		"align": [Vector2(0, -21), Vector2(0, -8), Vector2(0, 8), Vector2(0, 21), Vector2(-5, 0)],
		"slot_pos": ["WR", "WR", "WR", "WR", "RB"],
		"routes": [
			[Vector2(24, 1)],
			[Vector2(26, -2)],
			[Vector2(26, 2)],
			[Vector2(24, -1)],
			BLOCK,
		],
		"progression": [1, 2, 0, 3],
	}

	p["mesh_cross"] = {
		"name": "Mesh Cross",
		"desc": "Crossers rub off each other underneath. A man coverage killer.",
		"kind": "pass",
		"cost": 140,
		"dropback": 1.6,
		"align": [Vector2(0, -18), Vector2(0, -7), Vector2(0, 7), Vector2(0, 18), Vector2(-5, 3)],
		"slot_pos": ["WR", "TE", "TE", "WR", "RB"],
		"routes": [
			[Vector2(14, 2), Vector2(16, -8)],
			[Vector2(4, 0), Vector2(5, 12)],
			[Vector2(5, 0), Vector2(6, -12)],
			[Vector2(14, -2), Vector2(16, 8)],
			[Vector2(2, 5), Vector2(3, 12)],
		],
		"progression": [1, 2, 4, 0, 3],
	}

	p["post_corner"] = {
		"name": "Post-Corner Shot",
		"desc": "Double move on the outside. Rewards high Intelligence receivers.",
		"kind": "pass",
		"cost": 180,
		"dropback": 2.2,
		"align": [Vector2(0, -22), Vector2(0, -9), Vector2(0, 9), Vector2(0, 22), Vector2(-5, -2)],
		"slot_pos": ["WR", "WR", "TE", "WR", "RB"],
		"routes": [
			[Vector2(12, 0), Vector2(18, 5), Vector2(24, -3)],
			[Vector2(10, 0), Vector2(11, -5)],
			[Vector2(9, 0), Vector2(10, 4)],
			[Vector2(12, 0), Vector2(18, -5), Vector2(24, 3)],
			BLOCK,
		],
		"progression": [0, 3, 1, 2],
	}

	p["screen_left"] = {
		"name": "Screen Left",
		"desc": "Let them rush, then dump it off behind a wall of blockers.",
		"kind": "pass",
		"cost": 130,
		"dropback": 1.8,
		"align": [Vector2(0, -20), Vector2(0, -12), Vector2(0, 12), Vector2(0, 20), Vector2(-5, -4)],
		"slot_pos": ["WR", "TE", "WR", "WR", "RB"],
		"routes": [
			[Vector2(14, 0)],
			[Vector2(-1, -6), Vector2(3, -10)],
			[Vector2(14, 0)],
			[Vector2(12, 0)],
			[Vector2(-3, -6), Vector2(-2, -12)],
		],
		"progression": [4, 1, 0],
	}

	p["power_sweep"] = {
		"name": "Power Sweep",
		"desc": "Get outside with a lead blocker. Big gains if the edge holds.",
		"kind": "run",
		"cost": 120,
		"dropback": 0.5,
		"align": [Vector2(0, -16), Vector2(-1, -5), Vector2(-1, 5), Vector2(0, 16), Vector2(-6, -2)],
		"slot_pos": ["WR", "TE", "TE", "WR", "RB"],
		"routes": [
			[Vector2(8, 3)],
			[Vector2(1, 8)],
			BLOCK,
			[Vector2(8, -3)],
			CARRY,
		],
		"progression": [4],
	}

	p["draw_play"] = {
		"name": "Draw Play",
		"desc": "Sell the pass, then hand it off. Punishes an aggressive rush.",
		"kind": "run",
		"cost": 110,
		"dropback": 1.3,
		"align": [Vector2(0, -19), Vector2(0, -9), Vector2(0, 9), Vector2(0, 19), Vector2(-6, 1)],
		"slot_pos": ["WR", "WR", "TE", "WR", "RB"],
		"routes": [
			[Vector2(12, 0)],
			[Vector2(10, 0)],
			BLOCK,
			[Vector2(12, 0)],
			CARRY,
		],
		"progression": [4],
	}

	p["wheel_route"] = {
		"name": "Wheel Route",
		"desc": "The back leaks out and turns up the sideline. Linebackers hate it.",
		"kind": "pass",
		"cost": 150,
		"dropback": 2.0,
		"align": [Vector2(0, -20), Vector2(0, -10), Vector2(0, 12), Vector2(0, 21), Vector2(-5, 4)],
		"slot_pos": ["WR", "TE", "WR", "WR", "RB"],
		"routes": [
			[Vector2(16, 0), Vector2(17, 4)],
			[Vector2(6, 0), Vector2(7, -6)],
			[Vector2(13, 0), Vector2(15, -6)],
			[Vector2(9, 0), Vector2(10, 5)],
			[Vector2(0, 8), Vector2(9, 12), Vector2(20, 13)],
		],
		"progression": [4, 2, 1, 0, 3],
	}

	p["play_action_deep"] = {
		"name": "Play Action Deep",
		"desc": "Fake the dive and take the top off. Slow to develop, huge payoff.",
		"kind": "pass",
		"cost": 200,
		"dropback": 2.8,
		"align": [Vector2(0, -21), Vector2(0, -11), Vector2(-1, 8), Vector2(0, 21), Vector2(-6, 0)],
		"slot_pos": ["WR", "WR", "TE", "WR", "RB"],
		"routes": [
			[Vector2(28, -1)],
			[Vector2(20, 0), Vector2(26, 6)],
			BLOCK,
			[Vector2(30, 1)],
			BLOCK,
		],
		"progression": [3, 0, 1],
	}

	p["goal_line_smash"] = {
		"name": "Goal Line Smash",
		"desc": "Heavy set, everybody blocks down. Built for the 2 yard line.",
		"kind": "run",
		"cost": 100,
		"dropback": 0.4,
		"align": [Vector2(-1, -8), Vector2(-1, -4), Vector2(-1, 4), Vector2(-1, 8), Vector2(-5, 0)],
		"slot_pos": ["TE", "TE", "TE", "TE", "RB"],
		"routes": [BLOCK, BLOCK, BLOCK, BLOCK, CARRY],
		"progression": [4],
	}

	p["trips_flood"] = {
		"name": "Trips Right Flood",
		"desc": "Three receivers to one side at three depths. Overloads a zone.",
		"kind": "pass",
		"cost": 170,
		"dropback": 1.9,
		"align": [Vector2(0, -20), Vector2(0, 8), Vector2(0, 14), Vector2(0, 20), Vector2(-5, -3)],
		"slot_pos": ["WR", "TE", "WR", "WR", "RB"],
		"routes": [
			[Vector2(15, 0), Vector2(19, -5)],
			[Vector2(5, 0), Vector2(6, 8)],
			[Vector2(12, 0), Vector2(14, 6)],
			[Vector2(22, 0)],
			BLOCK,
		],
		"progression": [1, 2, 3, 0],
	}

	p["double_seam"] = {
		"name": "Double Slot Seam",
		"desc": "Two seams up the hash with checkdowns underneath.",
		"kind": "pass",
		"cost": 155,
		"dropback": 2.0,
		"align": [Vector2(0, -19), Vector2(0, -6), Vector2(0, 6), Vector2(0, 19), Vector2(-5, 2)],
		"slot_pos": ["WR", "TE", "TE", "WR", "RB"],
		"routes": [
			[Vector2(7, 0), Vector2(8, -6)],
			[Vector2(20, -1)],
			[Vector2(20, 1)],
			[Vector2(7, 0), Vector2(8, 6)],
			[Vector2(3, 3), Vector2(4, 8)],
		],
		"progression": [1, 2, 4, 0, 3],
	}

	_plays = p


static func all() -> Dictionary:
	_build()
	return _plays


static func get_play(id: String) -> Dictionary:
	_build()
	return _plays.get(id, {})


static func play_name(id: String) -> String:
	return get_play(id).get("name", "?")


static func play_cost(id: String) -> int:
	return int(get_play(id).get("cost", 150))


static func all_ids() -> Array:
	_build()
	return _plays.keys()


static func starter_ids() -> Array:
	return ["quick_outs", "slant_flood", "curl_and_out", "hb_dive"]


static func buyable_ids() -> Array:
	var starters := starter_ids()
	var out := []
	for id in all_ids():
		if not starters.has(id):
			out.append(id)
	return out


static func is_run(id: String) -> bool:
	return get_play(id).get("kind", "pass") == "run"
