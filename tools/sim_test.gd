extends Node

## Headless balance harness. Plays a pile of matches with an auto-coach and
## prints aggregate numbers so the sim can be tuned without clicking through
## the UI. Run with:
##   godot --headless --path . res://tools/sim_test.tscn

const MATCHES_PER_ROUND := 12

## Models a coach who keeps signing upgrades. Rosters start in the 2-4 band,
## so this has to track GameState's own quality scale.
const ROSTER_BASE := 3.0
const ROSTER_GROWTH := 0.55
const DT := 1.0 / 60.0


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	print("=== GRIDIRON RUN :: SIM HARNESS ===")
	for round_index in 5:
		_run_round(round_index)
	print("\nElapsed %d ms" % (Time.get_ticks_msec() - t0))
	get_tree().quit()


func _run_round(round_index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + round_index

	var totals := {
		"wins": 0, "pts_us": 0, "pts_them": 0, "plays": 0,
		"yards": 0.0, "tds": 0, "ints": 0, "sacks": 0,
		"incomplete": 0, "completions": 0, "runs": 0, "passes": 0,
		"bucks": 0, "long": 0.0, "explosive": 0, "three_and_outs": 0,
		"drives": 0, "kinds": null, "hist": null, "tdair": 0.0, "nontd_comp": 0, "nontd_yards": 0.0, "nontd_yac": 0.0, "td_yards": 0.0, "timeouts": 0, "duration": 0.0, "air": 0.0, "yac": 0.0, "comp_yards": 0.0, "run_yards": 0.0,
	}

	totals["hist"] = [0, 0, 0, 0, 0, 0, 0]
	totals["kinds"] = {}
	for m in MATCHES_PER_ROUND:
		GameState.rng.seed = rng.randi()
		GameState.new_run(rng.randi())
		GameState.round_index = round_index
		# Model a coach who has been upgrading: the roster keeps roughly one
		# step behind the bracket rather than staying at week-one quality.
		GameState.roster.assign(Generator.starting_roster(GameState.rng, ROSTER_BASE + round_index * ROSTER_GROWTH))
		GameState.auto_fill_lineup()
		# Give the roster a plausible mid-run playbook.
		for id in PlayDB.all_ids():
			if not GameState.playbook.has(id):
				GameState.playbook.append(id)
		GameState.active_plays = ["quick_outs", "slant_flood", "curl_and_out", "hb_dive", "four_verticals"]
		_play_match(round_index, totals)

	var n := float(MATCHES_PER_ROUND)
	var plays := maxf(float(totals["plays"]), 1.0)
	var attempts := maxf(float(totals["passes"]), 1.0)
	print("\n[%s]  quality %.1f" % [GameState.ROUND_NAMES[round_index], float(GameState.bracket[round_index]["quality"])])
	print("  win rate        %.0f%%" % (100.0 * totals["wins"] / n))
	print("  avg score       %.1f - %.1f" % [totals["pts_us"] / n, totals["pts_them"] / n])
	print("  yards per play  %.2f   (%d plays)" % [totals["yards"] / plays, totals["plays"]])
	print("  completion pct  %.0f%%  (%d att)" % [100.0 * totals["completions"] / attempts, totals["passes"]])
	print("  sack rate       %.0f%%" % (100.0 * totals["sacks"] / attempts))
	print("  int rate        %.1f%%" % (100.0 * totals["ints"] / attempts))
	print("  TDs per match   %.2f" % (totals["tds"] / n))
	print("  explosive 20+   %.0f%% of plays   longest %d yd" % [100.0 * totals["explosive"] / plays, int(totals["long"])])
	print("  yards per rush  %.2f  (%d rushes)" % [totals["run_yards"] / maxf(float(totals["runs"]), 1.0), totals["runs"]])
	print("  per completion  %.1f yd  = %.1f air + %.1f YAC" % [
		totals["comp_yards"] / maxf(float(totals["completions"]), 1.0),
		totals["air"] / maxf(float(totals["completions"]), 1.0),
		totals["yac"] / maxf(float(totals["completions"]), 1.0)])
	print("  non-TD catch    %.1f yd (%.1f YAC) over %d   |  TD avg %.1f yd" % [
		totals["nontd_yards"] / maxf(float(totals["nontd_comp"]), 1.0),
		totals["nontd_yac"] / maxf(float(totals["nontd_comp"]), 1.0),
		totals["nontd_comp"],
		totals["td_yards"] / maxf(float(totals["tds"]), 1.0)])
	print("  never tackled   %.0f%% of plays   avg play %.1fs" % [
		100.0 * totals["timeouts"] / plays, totals["duration"] / plays])
	var h: Array = totals["hist"]
	print("  gain spread     <0:%d  0-4:%d  4-10:%d  10-20:%d  20-35:%d  35-60:%d  60+:%d" % [
		h[0], h[1], h[2], h[3], h[4], h[5], h[6]])
	print("  kinds           %s" % str(totals["kinds"]))
	print("  TD air yards    %.1f avg" % (totals["tdair"] / maxf(float(totals["tds"]), 1.0)))
	print("  plays per drive %.1f" % (float(totals["plays"]) / maxf(float(totals["drives"]), 1.0)))
	print("  bucks per match %.0f" % (totals["bucks"] / n))


func _play_match(round_index: int, totals: Dictionary) -> void:
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

	var bucks := 0
	var guard := 0
	while guard < 400:
		guard += 1
		if sim.phase == MatchSim.Phase.DRIVE_OVER:
			totals["drives"] += 1
			if sim.drive_num >= sim.total_drives:
				break
			sim.sim_opponent_drive()
			sim.begin_drive()
			continue

		if sim.phase == MatchSim.Phase.PRESNAP:
			sim.set_play(_call_play(sim))
			sim.snap()
			var live_guard := 0
			while sim.phase == MatchSim.Phase.LIVE and live_guard < 2000:
				sim.step(DT)
				live_guard += 1
			_tally(sim, totals)
			bucks += int(sim.result.get("bucks", 0))
			sim.advance()

	totals["pts_us"] += sim.score_us
	totals["pts_them"] += sim.score_them
	totals["bucks"] += bucks + (150 if sim.won() else 0)
	if sim.won():
		totals["wins"] += 1


## A simple auto-coach so the harness exercises realistic play mixes.
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


func _tally(sim: MatchSim, totals: Dictionary) -> void:
	var r := sim.result
	var kind := String(r.get("kind", ""))
	var yards := float(r.get("yards", 0.0))

	totals["plays"] += 1
	totals["yards"] += yards
	var bucket := 0
	if yards < 0.0: bucket = 0
	elif yards < 4.0: bucket = 1
	elif yards < 10.0: bucket = 2
	elif yards < 20.0: bucket = 3
	elif yards < 35.0: bucket = 4
	elif yards < 60.0: bucket = 5
	else: bucket = 6
	totals["hist"][bucket] += 1
	var k := String(r.get("kind", "?"))
	totals["kinds"][k] = int(totals["kinds"].get(k, 0)) + 1
	if bool(r.get("td", false)) and sim.catch_x > 0.0:
		totals["tdair"] += sim.catch_x - sim.los
	totals["duration"] += float(r.get("duration", 0.0))
	if bool(r.get("timeout", false)):
		totals["timeouts"] += 1
	totals["long"] = maxf(float(totals["long"]), yards)
	if yards >= 20.0:
		totals["explosive"] += 1
	if bool(r.get("td", false)):
		totals["tds"] += 1

	var is_run_play := PlayDB.is_run(sim.play_id)
	if is_run_play:
		totals["runs"] += 1
		totals["run_yards"] += yards
		return

	totals["passes"] += 1
	match kind:
		"incomplete":
			totals["incomplete"] += 1
		"interception":
			totals["ints"] += 1
		"sack":
			totals["sacks"] += 1
		_:
			totals["completions"] += 1
			totals["comp_yards"] += yards
			if sim.catch_x > 0.0:
				totals["air"] += sim.catch_x - sim.los
				totals["yac"] += yards - (sim.catch_x - sim.los)
				if not bool(r.get("td", false)):
					totals["nontd_comp"] += 1
					totals["nontd_yards"] += yards
					totals["nontd_yac"] += yards - (sim.catch_x - sim.los)
				else:
					totals["td_yards"] += yards
