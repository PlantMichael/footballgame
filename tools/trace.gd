extends Node

## Runs plays until it finds one matching a filter, then dumps that play frame
## by frame. Used to hunt down specific bad outcomes.
##   godot --headless --path . res://tools/trace.tscn

const DT := 1.0 / 60.0
const PLAYS := ["quick_outs", "slant_flood", "curl_and_out", "hb_dive", "four_verticals"]
const MIN_YARDS := 60.0   # only dump plays that gained at least this much
const MAX_TRIALS := 200


func _ready() -> void:
	# Replicate the balance harness exactly: real drives, real down/distance.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000
	var found := 0
	var big := 0
	var total := 0
	var hist := [0, 0, 0, 0, 0, 0, 0]
	var tds := 0
	var kinds := {}
	var neg_kinds := {}
	var by_play := {}
	var by_play_n := {}

	for m in 12:
		GameState.new_run(rng.randi())
		GameState.roster.assign(Generator.starting_roster(GameState.rng, 3.0))
		GameState.auto_fill_lineup()
		GameState.active_plays.assign(PLAYS)

		var opp: Dictionary = GameState.bracket[0]
		var sim := MatchSim.new()
		sim.setup(GameState.starters(),
			Generator.make_defense(GameState.rng, float(opp["quality"])),
			float(opp["quality"]), "Test", int(opp["drives"]))
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
			if sim.phase != MatchSim.Phase.PRESNAP:
				break

			var play: String = PLAYS[total % PLAYS.size()]
			sim.set_play(play)
			sim.snap()
			var log_lines: Array[String] = []
			var t := 0.0
			var next := 0.0
			while sim.phase == MatchSim.Phase.LIVE and t < 20.0:
				sim.step(DT)
				t += DT
				if t >= next:
					next += 0.5
					log_lines.append(_line(sim, t))
			total += 1
			var gained := float(sim.result.get("yards", 0.0))
			if bool(sim.result.get("td", false)):
				tds += 1
			var b := 0
			if gained < 0.0: b = 0
			elif gained < 4.0: b = 1
			elif gained < 10.0: b = 2
			elif gained < 20.0: b = 3
			elif gained < 35.0: b = 4
			elif gained < 60.0: b = 5
			else: b = 6
			hist[b] += 1
			by_play[play] = float(by_play.get(play, 0.0)) + gained
			by_play_n[play] = int(by_play_n.get(play, 0)) + 1
			var k := String(sim.result.get("kind", "?"))
			kinds[k] = int(kinds.get(k, 0)) + 1
			if gained < 0.0:
				neg_kinds[k] = int(neg_kinds.get(k, 0)) + 1
			if gained >= MIN_YARDS:
				big += 1
				if found < 2:
					found += 1
					print("
===== %s gained %.1f  (los was %.0f, down %d) =====" % [
						play, gained, sim.los, sim.down])
					for l in log_lines:
						print(l)
					print("RESULT: %s | kind=%s td=%s" % [
						sim.result.get("text", ""), sim.result.get("kind", ""),
						sim.result.get("td", false)])
			sim.advance()

	print("
%d of %d plays gained %.0f+   (%d TDs)" % [big, total, MIN_YARDS, tds])
	print("per play type:")
	for k in by_play:
		print("   %-16s %5.2f yd over %d" % [k, by_play[k] / float(by_play_n[k]), by_play_n[k]])
	print("kinds: %s" % str(kinds))
	print("negative-yardage kinds: %s" % str(neg_kinds))
	print("gain spread  <0:%d  0-4:%d  4-10:%d  10-20:%d  20-35:%d  35-60:%d  60+:%d" % [
		hist[0], hist[1], hist[2], hist[3], hist[4], hist[5], hist[6]])
	get_tree().quit()


func _call_play(sim: MatchSim) -> String:
	var pool: Array = GameState.active_plays
	if sim.to_go <= 3.0 and sim.down >= 3:
		for id in pool:
			if PlayDB.is_run(id):
				return id
	if sim.down >= 3 and sim.to_go >= 8.0:
		for id in pool:
			if not PlayDB.is_run(id) and float(PlayDB.get_play(id).get("dropback", 1.0)) > 2.0:
				return id
	return pool[GameState.rng.randi_range(0, pool.size() - 1)]


func _line(sim: MatchSim, t: float) -> String:
	if sim.carrier == null:
		return "  t=%.1f  (ball in air)" % t
	var c: SimPlayer = sim.carrier
	var ahead := 0
	var parts: Array[String] = []
	var ranked: Array = sim.defense.duplicate()
	ranked.sort_custom(func(a, b):
		return a.pos.distance_to(c.pos) < b.pos.distance_to(c.pos))
	for d in ranked:
		# "ahead" = between the carrier and the end zone
		if d.pos.x > c.pos.x:
			ahead += 1
	for i in mini(3, ranked.size()):
		var d: SimPlayer = ranked[i]
		parts.append("%s d=%.1f dx=%+.1f v=%.1f" % [
			d.slot, d.pos.distance_to(c.pos), d.pos.x - c.pos.x, d.vel.length()])
	return "  t=%.1f  carrier %s at %+.1f (lat %.0f) v=%.1f/%.1f | %d ahead | %s" % [
		t, c.slot, c.pos.x - sim.los, c.pos.y, c.vel.length(), c.speed(), ahead,
		"  ".join(parts)]
