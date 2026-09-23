extends Node

## Headless balance harness for the chalkboard. Same shape as sim_test.gd,
## but every snap is a drawn call instead of a scripted PlayDB play, so the
## numbers answer the question sim_test cannot: does five receivers running
## and nobody staying in to help block still produce playable football?
##
##   godot --headless --path . res://tools/routesim.tscn
##
## Three coaches are compared at each round:
##   "blank"   - nothing drawn, all five on random stock routes
##   "spread"  - a sensible five-route concept drawn every snap
##   "deep"    - everyone drawing the full 30 yards downfield

const MATCHES_PER_COACH := 10
const ROSTER_BASE := 3.0
const ROSTER_GROWTH := 0.55
const DT := 1.0 / 60.0
const ROUNDS := [0, 2, 4]

## Five hand-drawn concepts, keyed the way a coach would actually chalk them:
## a couple of quick outlets, an intermediate dig, and one shot downfield.
const SPREAD := ["out", "slant", "dig", "post", "checkdown"]
const DEEP := ["go", "seam", "go", "post", "corner"]


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	print("=== GRIDIRON RUN :: CHALKBOARD HARNESS ===")
	for round_index in ROUNDS:
		var round_name: String = GameState.ROUND_NAMES[round_index] if round_index < GameState.ROUND_NAMES.size() else "Bowl"
		print("\n[%s]" % round_name)
		for coach in ["blank", "spread", "deep"]:
			_run(round_index, coach)
	print("\nElapsed %d ms" % (Time.get_ticks_msec() - t0))
	get_tree().quit()


func _run(round_index: int, coach: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7000 + round_index

	var t := {
		"wins": 0, "plays": 0, "yards": 0.0, "pts_us": 0, "pts_them": 0,
		"sacks": 0, "completions": 0, "incomplete": 0, "ints": 0, "tds": 0,
		"long": 0.0,
	}

	for m in MATCHES_PER_COACH:
		GameState.rng.seed = rng.randi()
		GameState.new_run(rng.randi())
		GameState.round_index = round_index
		GameState.roster.assign(Generator.starting_roster(
			GameState.rng, ROSTER_BASE + round_index * ROSTER_GROWTH))
		GameState.auto_fill_lineup()
		_play_match(round_index, coach, t)

	var n := float(MATCHES_PER_COACH)
	var plays := maxf(float(t["plays"]), 1.0)
	var att := maxf(float(t["completions"] + t["incomplete"] + t["ints"] + t["sacks"]), 1.0)
	print("  %-7s win %3.0f%%   %4.1f-%4.1f   %5.2f yd/play   comp %2.0f%%   sack %2.0f%%   TD/gm %.2f   long %2.0f" % [
		coach,
		100.0 * t["wins"] / n,
		t["pts_us"] / n, t["pts_them"] / n,
		t["yards"] / plays,
		100.0 * t["completions"] / att,
		100.0 * t["sacks"] / att,
		t["tds"] / n,
		t["long"],
	])


func _play_match(round_index: int, coach: String, t: Dictionary) -> void:
	var opp: Dictionary = GameState.bracket[round_index]
	var sim := MatchSim.new()
	sim.setup(
		GameState.starters(),
		Generator.make_defense(GameState.rng, float(opp["quality"])),
		float(opp["quality"]),
		String(opp["name"]),
		int(opp["drives"])
	)
	sim.start_match()

	var guard := 0
	while guard < 400:
		guard += 1
		if sim.phase == MatchSim.Phase.DRIVE_OVER:
			if sim.drive_num >= sim.total_drives:
				break
			sim.sim_opponent_drive()
			sim.begin_drive()
			continue

		if sim.phase == MatchSim.Phase.PRESNAP:
			_chalk(sim, coach)
			sim.set_drawn_call(GameState.drawn_routes)
			sim.snap()
			var live := 0
			while sim.phase == MatchSim.Phase.LIVE and live < 2000:
				sim.step(DT)
				live += 1
			_tally(sim, t)
			sim.advance()

	t["pts_us"] += sim.score_us
	t["pts_them"] += sim.score_them
	if sim.won():
		t["wins"] += 1


## Puts this coach's routes on the board. The blank coach draws nothing, so
## MatchSim hands every flex a random stock route instead.
func _chalk(sim: MatchSim, coach: String) -> void:
	GameState.clear_routes()
	if coach == "blank":
		return
	var shapes: Array = SPREAD if coach == "spread" else DEEP
	var flexes := sim.flex_players()
	var spots := RouteBook.formation_for(flexes)
	for i in flexes.size():
		GameState.set_route(flexes[i].slot,
			RouteBook.route_for_spot(String(shapes[i % shapes.size()]), spots[i]))


func _tally(sim: MatchSim, t: Dictionary) -> void:
	var r := sim.result
	if r.is_empty():
		return
	t["plays"] += 1
	var y := float(r.get("yards", 0.0))
	t["yards"] += y
	t["long"] = maxf(float(t["long"]), y)
	match String(r.get("kind", "")):
		"sack": t["sacks"] += 1
		"complete": t["completions"] += 1
		"incomplete": t["incomplete"] += 1
		"interception": t["ints"] += 1
		"touchdown":
			t["completions"] += 1
			t["tds"] += 1
	if bool(r.get("td", false)) and String(r.get("kind", "")) != "touchdown":
		t["tds"] += 1
