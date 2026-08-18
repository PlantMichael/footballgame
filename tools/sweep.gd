extends Node

## Sensitivity sweep: how does win rate move as the player's roster quality
## changes against a fixed opponent? Used to pick the bracket difficulty ramp.
##   godot --headless --path . res://tools/sweep.tscn

const MATCHES := 10
const DT := 1.0 / 60.0
const ROSTER_QUALITIES := [2.5, 3.0, 3.5, 4.0, 5.0, 6.0, 7.0]


func _ready() -> void:
	print("=== ROSTER QUALITY SWEEP (win rate %) ===")
	var header := "roster ->   "
	for q in ROSTER_QUALITIES:
		header += "%5.1f" % q
	print(header)

	for round_index in 5:
		var line := "%-11s" % GameState.ROUND_NAMES[round_index]
		var pts := "            "
		for rq in ROSTER_QUALITIES:
			var res := _measure(round_index, float(rq))
			line += "%5.0f" % (100.0 * res[0])
			pts += "%5.1f" % res[1]
		var opp_q: float = 0.0
		GameState.new_run(1)
		opp_q = float(GameState.bracket[round_index]["quality"])
		print("%s   (def %.1f)" % [line, opp_q])
		print("%s   points scored" % pts)
	get_tree().quit()


func _measure(round_index: int, roster_quality: float) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7000 + round_index * 100 + int(roster_quality * 10)
	var wins := 0
	var points := 0
	for m in MATCHES:
		GameState.new_run(rng.randi())
		GameState.round_index = round_index
		GameState.roster.assign(Generator.starting_roster(GameState.rng, roster_quality))
		GameState.auto_fill_lineup()
		for id in PlayDB.all_ids():
			if not GameState.playbook.has(id):
				GameState.playbook.append(id)
		GameState.active_plays.assign(
			["quick_outs", "slant_flood", "curl_and_out", "hb_dive", "four_verticals"])
		var sim := _run(round_index)
		if sim.won():
			wins += 1
		points += sim.score_us
	return [float(wins) / float(MATCHES), float(points) / float(MATCHES)]


func _run(round_index: int) -> MatchSim:
	var opp: Dictionary = GameState.bracket[round_index]
	var sim := MatchSim.new()
	sim.setup(
		GameState.starters(),
		Generator.make_defense(GameState.rng, float(opp["quality"])),
		float(opp["quality"]), String(opp["name"]), int(opp["drives"])
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
			sim.set_play(_call_play(sim))
			sim.snap()
			var live := 0
			while sim.phase == MatchSim.Phase.LIVE and live < 2000:
				sim.step(DT)
				live += 1
			sim.advance()
	return sim


func _call_play(sim: MatchSim) -> String:
	var pool: Array = GameState.active_plays
	if sim.to_go <= 3.0 and sim.down >= 3:
		for id in pool:
			if PlayDB.is_run(id):
				return id
	if sim.down >= 3 and sim.to_go >= 8.0:
		# Pick the deepest concept that still gets the ball out on time, not
		# simply the deepest one in the book.
		var best := ""
		var best_drop := 0.0
		for id in pool:
			if PlayDB.is_run(id):
				continue
			var drop := float(PlayDB.get_play(id).get("dropback", 1.0))
			if drop <= 2.1 and drop > best_drop:
				best_drop = drop
				best = id
		if best != "":
			return best
	return pool[GameState.rng.randi_range(0, pool.size() - 1)]
