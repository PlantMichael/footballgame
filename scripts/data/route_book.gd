class_name RouteBook
extends RefCounted

## Everything about hand-drawn routes: where the five flex players line up,
## how long a route is allowed to be, the stock routes an undrawn player
## falls back to, and the geometry helpers the chalk tool needs.
##
## Geometry convention matches PlayDB: a route is an Array of Vector2
## waypoints RELATIVE TO THE PLAYER'S ALIGNMENT, where x is downfield yards
## and y is lateral yards (negative = the offense's left).

## Every flex gets the same chalk allowance, so route design is about shape
## and spacing rather than about who on the roster can afford to run deep.
const BUDGET_YARDS := 30.0

## Points closer together than this are dropped while drawing; the whole
## stroke is then simplified to SIMPLIFY_TOL. Together they turn a few
## hundred raw mouse samples into the handful of waypoints the sim walks.
const SAMPLE_MIN_YARDS := 0.45
const SIMPLIFY_TOL := 0.55
const MIN_ROUTE_YARDS := 1.5

## The five spots, widest first. Personnel is slotted into these by position
## (see formation_for), so a three-WR set spreads out and a two-TE set
## tightens up without the coach having to think about it.
const SPOT_WIDE_LEFT := Vector2(0.0, -20.0)
const SPOT_SLOT_LEFT := Vector2(0.0, -9.0)
const SPOT_SLOT_RIGHT := Vector2(0.0, 9.0)
const SPOT_WIDE_RIGHT := Vector2(0.0, 20.0)
const SPOT_BACKFIELD := Vector2(-5.0, 2.0)

## Filled in preference order per position group: the first free spot in a
## group's list is the one that player takes.
const _WR_SPOTS := [SPOT_WIDE_LEFT, SPOT_WIDE_RIGHT, SPOT_SLOT_LEFT, SPOT_SLOT_RIGHT, SPOT_BACKFIELD]
const _TE_SPOTS := [SPOT_SLOT_LEFT, SPOT_SLOT_RIGHT, SPOT_WIDE_LEFT, SPOT_WIDE_RIGHT, SPOT_BACKFIELD]
const _RB_SPOTS := [SPOT_BACKFIELD, SPOT_SLOT_RIGHT, SPOT_SLOT_LEFT, SPOT_WIDE_RIGHT, SPOT_WIDE_LEFT]


## Alignment for each of the five flex players, in the order they are given.
## `players` is an Array of anything exposing `.data.pos` (a SimPlayer) or
## `.pos` (a PlayerData); both are accepted so the UI can preview a
## formation without a live sim.
static func formation_for(players: Array) -> Array:
	var taken := {}
	var out: Array = []
	out.resize(players.size())

	# Backs and tight ends claim their spots before receivers do, otherwise
	# three WRs take both slots and the RB ends up split out wide.
	var order := []
	for i in players.size():
		order.append(i)
	order.sort_custom(func(a, b):
		return _claim_rank(players[a]) < _claim_rank(players[b]))

	for i in order:
		var prefs := _spots_for(players[i])
		var spot: Vector2 = SPOT_BACKFIELD
		for s in prefs:
			if not taken.has(s):
				spot = s
				break
		taken[spot] = true
		out[i] = spot
	return out


static func _pos_of(p) -> int:
	if p == null:
		return PlayerData.Pos.WR
	var data = p.data if "data" in p else p
	if data == null:
		return PlayerData.Pos.WR
	return data.pos


static func _claim_rank(p) -> int:
	match _pos_of(p):
		PlayerData.Pos.RB: return 0
		PlayerData.Pos.TE: return 1
		_: return 2


static func _spots_for(p) -> Array:
	match _pos_of(p):
		PlayerData.Pos.RB: return _RB_SPOTS
		PlayerData.Pos.TE: return _TE_SPOTS
		_: return _WR_SPOTS


## The position a flex is effectively playing at `spot`, used for the
## out-of-position penalty. A back split out wide is doing a receiver's job,
## so the formation reports what the spot asks for, not what the player is.
static func role_name_for_spot(spot: Vector2) -> String:
	if spot.x < -1.0:
		return "RB"
	if absf(spot.y) < 14.0:
		return "TE"
	return "WR"


# ============================================================================
# Stock routes
# ============================================================================

## The fallback pool. A flex the coach did not draw for runs one of these,
## rerolled every snap, so an undrawn player is unpredictable rather than
## useless. Every shape here is already inside BUDGET_YARDS.
const STOCK := {
	"go": [Vector2(24, 0)],
	"slant": [Vector2(4, 0), Vector2(12, 7)],
	"out": [Vector2(8, 0), Vector2(9, -6)],
	"in": [Vector2(8, 0), Vector2(9, 6)],
	"curl": [Vector2(12, 0), Vector2(10, -1)],
	"comeback": [Vector2(15, 0), Vector2(12, -3)],
	"post": [Vector2(12, 0), Vector2(22, 6)],
	"corner": [Vector2(12, 0), Vector2(20, -7)],
	"drag": [Vector2(3, 0), Vector2(4, 12)],
	"wheel": [Vector2(0, 7), Vector2(8, 10), Vector2(18, 11)],
	"flat": [Vector2(1, 5), Vector2(2, 11)],
	"dig": [Vector2(14, 0), Vector2(15, -9)],
	"checkdown": [Vector2(3, 3), Vector2(4, 8)],
	"seam": [Vector2(20, 1)],
}

const STOCK_LABELS := {
	"go": "Go", "slant": "Slant", "out": "Out", "in": "In", "curl": "Curl",
	"comeback": "Comeback", "post": "Post", "corner": "Corner", "drag": "Drag",
	"wheel": "Wheel", "flat": "Flat", "dig": "Dig", "checkdown": "Checkdown",
	"seam": "Seam",
}


## A stock route for a player aligned at `spot`. Uses `rng` rather than
## Array.pick_random so a seeded match stays reproducible.
static func random_route(rng: RandomNumberGenerator, spot: Vector2) -> Array:
	var ids: Array = STOCK.keys()
	var id: String = ids[rng.randi_range(0, ids.size() - 1)]
	return route_for_spot(id, spot)


## `id`'s shape, flipped to suit which side of the formation `spot` is on.
## The raw shapes break to the right (+y); a player already near the right
## sideline gets the mirror image so his break has room to develop.
static func route_for_spot(id: String, spot: Vector2) -> Array:
	var base: Array = STOCK.get(id, STOCK["go"])
	var flip := spot.y > 0.0
	var out: Array = []
	for wp in base:
		out.append(Vector2(wp.x, -wp.y if flip else wp.y))
	return out


# ============================================================================
# Geometry
# ============================================================================

## Total path length of a polyline of waypoints measured from the alignment
## spot, i.e. including the leg from the player to his first waypoint.
static func route_length(route: Array) -> float:
	var total := 0.0
	var prev := Vector2.ZERO
	for wp in route:
		total += prev.distance_to(wp)
		prev = wp
	return total


## Cuts `route` short at `budget` yards of chalk, interpolating the final
## waypoint so the line ends exactly on the allowance rather than at the
## last whole waypoint before it.
static func truncate(route: Array, budget: float = BUDGET_YARDS) -> Array:
	var out: Array = []
	var used := 0.0
	var prev := Vector2.ZERO
	for wp in route:
		var leg := prev.distance_to(wp)
		if used + leg <= budget or leg < 0.0001:
			out.append(wp)
			used += leg
			prev = wp
			continue
		out.append(prev + (wp - prev).normalized() * (budget - used))
		return out
	return out


## Ramer-Douglas-Peucker. Turns the raw mouse trail into the few waypoints
## the sim actually steers between, while keeping every real break.
static func simplify(points: Array, tol: float = SIMPLIFY_TOL) -> Array:
	if points.size() < 3:
		return points.duplicate()
	var keep := _rdp(points, 0, points.size() - 1, tol)
	var out: Array = []
	for i in points.size():
		if keep.get(i, false):
			out.append(points[i])
	return out


static func _rdp(points: Array, first: int, last: int, tol: float) -> Dictionary:
	var keep := {first: true, last: true}
	if last <= first + 1:
		return keep
	var a: Vector2 = points[first]
	var b: Vector2 = points[last]
	var worst := -1.0
	var worst_i := -1
	for i in range(first + 1, last):
		var d := _point_line_dist(points[i], a, b)
		if d > worst:
			worst = d
			worst_i = i
	if worst <= tol or worst_i < 0:
		return keep
	for k in _rdp(points, first, worst_i, tol):
		keep[k] = true
	for k in _rdp(points, worst_i, last, tol):
		keep[k] = true
	return keep


static func _point_line_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# ============================================================================
# Examples
# ============================================================================

## The old playbook, kept purely as a teaching aid: each entry is a complete
## five-route concept the coach can load onto the chalkboard as a starting
## point (see the EXAMPLES panel on the match screen). Nothing here is owned,
## bought, or called - loading one just fills in five drawn routes that can
## then be redrawn freely.
static func example_ids() -> Array:
	var out: Array = []
	for id in PlayDB.all_ids():
		if not PlayDB.is_run(id):
			out.append(id)
	return out


## The five routes of example `id`, each already truncated to the budget and
## re-hung off `spots` (the live formation) rather than the example's own
## alignment. Blockers and ball carriers in the source play become short
## checkdown-style routes, since nobody sits in to block on a drawn call.
static func example_routes(id: String, spots: Array) -> Array:
	var pl := PlayDB.get_play(id)
	var src: Array = pl.get("routes", [])
	var out: Array = []
	for i in spots.size():
		var spot: Vector2 = spots[i]
		if i >= src.size() or src[i] is String:
			out.append(route_for_spot("checkdown", spot))
			continue
		var route: Array = []
		for wp in src[i]:
			route.append(wp)
		out.append(truncate(route))
	return out
