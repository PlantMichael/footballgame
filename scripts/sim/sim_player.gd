class_name SimPlayer
extends RefCounted

## One player inside a live play. All positions and distances are in YARDS.
## Field frame: x runs 0..120 downfield (offense attacks +x), y runs 0..53.33
## across, and the offense sees +y as its right.

enum Role { QB, BLOCK, ROUTE, CARRY, RUSH, MAN, ZONE, PURSUE }

var data: PlayerData
var is_offense: bool = false
var slot: String = ""          # "QB", "C", "T0".., "F0".. for offense; "DL0".. for defense
var label: String = ""

var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO

## Where this player should be lined up. Between plays he walks to it rather
## than teleporting, so switching play calls reads as the offense shifting.
var target_pos: Vector2 = Vector2.ZERO
var role: Role = Role.ZONE

## Effective stats for this play: base + item + ability, clamped 1..15.
var eff: Dictionary = {}

## Route waypoints in absolute field coordinates.
var route: Array = []
var route_idx: int = 0
var route_done: bool = false

var mark: SimPlayer = null      # coverage assignment or block assignment
var zone_point: Vector2 = Vector2.ZERO

var energy: float = 1.0         # 1.0 fresh -> 0.0 gassed (hidden from the UI)
var fatigue_floor: float = 0.65

var has_ball: bool = false
var engaged: bool = false       # blocker currently controlling a rusher
var shed_cooldown: float = 0.0  # blocker cannot re-engage while > 0
var stunned: float = 0.0        # knocked off balance, cannot move
var next_contact: float = 3.0   # seconds until the next contact roll
var tackle_cd: float = 0.0      # seconds until this defender may attempt another tackle
var reaction: float = 0.0       # delay before reacting to a live ball carrier
var free_timer: float = 0.0     # just shed a block; briefly cannot be picked up again
var disrupted: float = 0.0      # receiver knocked off the route

## --- Purely visual state, advanced by the renderer -------------------------
## Distance-based walk cycle phase, so the bob matches actual movement.
var stride: float = 0.0
## Seconds since being knocked down. 0 means upright.
var downed: float = 0.0

var trail: PackedVector2Array = PackedVector2Array()


func stat(key: String) -> int:
	return int(eff.get(key, 8))


## Top speed in yards/second before fatigue.
## The base is kept low on purpose: with a big constant term every player runs
## at nearly the same speed, so nobody can ever be run down and one missed
## tackle became an automatic touchdown. This way Agility actually separates.
func max_speed() -> float:
	return 2.9 + float(stat("agility")) * 0.46


## Current speed cap, after fatigue.
func speed() -> float:
	var mult: float = lerpf(fatigue_floor, 1.0, clampf(energy, 0.0, 1.0))
	if disrupted > 0.0:
		mult *= 0.55
	return max_speed() * mult


## Drain endurance. `effort` is 0..1, the fraction of top speed being used.
func drain(delta: float, effort: float) -> void:
	if effort <= 0.3:
		energy = minf(1.0, energy + delta * 0.05)
		return
	var sta := float(stat("stamina"))
	var rate := (0.075 - sta * 0.0035) * effort
	energy = maxf(0.0, energy - rate * delta)


func catch_chance_base() -> float:
	# Anchored on two points from the design: 3 DEX catches 55%, 15 DEX
	# catches 93%. Everything in between is a straight line.
	return 0.455 + float(stat("dexterity")) * 0.031667


func move_toward_point(target: Vector2, delta: float, effort: float = 1.0) -> void:
	if stunned > 0.0:
		stunned -= delta
		vel = vel.lerp(Vector2.ZERO, minf(1.0, delta * 8.0))
		return
	var to := target - pos
	var dist := to.length()
	if dist < 0.05:
		vel = vel.lerp(Vector2.ZERO, minf(1.0, delta * 6.0))
		return
	var want := to / dist * speed() * effort
	# Heavier players change direction more slowly.
	var accel := 26.0 - float(stat("strength")) * 0.5
	vel = vel.lerp(want, clampf(delta * accel * 0.35, 0.0, 1.0))
	if vel.length() > speed():
		vel = vel.normalized() * speed()
	pos += vel * delta
	stride += vel.length() * delta * 3.2
	drain(delta, clampf(vel.length() / maxf(max_speed(), 0.01), 0.0, 1.0))


func hold(delta: float) -> void:
	if stunned > 0.0:
		stunned -= delta
	vel = vel.lerp(Vector2.ZERO, minf(1.0, delta * 8.0))
	pos += vel * delta
	drain(delta, 0.0)
