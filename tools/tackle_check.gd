extends Node

## Breaks down every tackle attempt on Hand Off plays - who tried (DL/LB/DB),
## whether he was tied up in a block at the time, his odds, whether it
## worked, and where the back was first touched. Reads MatchSim.tackle_log.
##
##   godot --headless --path . res://tools/tackle_check.tscn
func _ready() -> void:
	for q in [6.0, 7.5]:
		_run(q)
	get_tree().quit()

func _run(q: float) -> void:
	GameState.rng.seed = 5150
	GameState.new_run(5150)
	GameState.roster.assign(Generator.starting_roster(GameState.rng, q))
	GameState.auto_fill_lineup()
	var starters: Array = GameState.starters()
	starters[GameState.SLOT_ORDER.find("F0")] = Generator.make_player(GameState.rng, PlayerData.Pos.RB, q)
	var sim := MatchSim.new()
	sim.setup(starters, Generator.make_defense(GameState.rng, q), q, "T", 999, 4242)
	sim.start_match()
	GameState.clear_routes()
	var s := {}
	var plays := 0
	var n := 0
	while plays < 300 and n < 2000:
		n += 1
		if sim.phase == MatchSim.Phase.DRIVE_OVER:
			sim.begin_drive(); sim.regenerate_defense(GameState.rng, q); continue
		if sim.phase != MatchSim.Phase.PRESNAP:
			sim.advance()
			if sim.phase == MatchSim.Phase.PRESNAP and plays % 6 == 0: sim.phase = MatchSim.Phase.DRIVE_OVER
			continue
		sim.set_drawn_call(GameState.drawn_routes)
		sim.set_planned_handoff("F0")
		sim.snap(); plays += 1
		var ho_t := -1.0
		var rb := sim.offense_slot("F0")
		var first_contact_x := 99.0
		var g := 0
		while sim.phase == MatchSim.Phase.LIVE and g < 2000:
			var before := sim.tackle_log.size()
			sim.step(1.0 / 60.0); g += 1
			if ho_t < 0.0 and sim.handoff_done: ho_t = sim.time
			if sim.tackle_log.size() > before and first_contact_x == 99.0:
				first_contact_x = rb.pos.x - sim.los
		for a in sim.tackle_log:
			var role: String = (a["d"] as SimPlayer).slot.substr(0, 2)
			var key := "%s %s" % [role, "blocked" if a["engaged"] else "free"]
			var e: Array = s.get(key, [0, 0, 0.0, 0.0])
			e[0] += 1; e[1] += 1 if a["made"] else 0; e[2] += float(a["chance"]); e[3] += float(a["time"]) - ho_t
			s[key] = e
		var fc := "none" if first_contact_x == 99.0 else ("behind LOS" if first_contact_x < 0.0 else ("0-3 yd" if first_contact_x < 3.0 else "3+ yd"))
		s["first contact " + fc] = int(s.get("first contact " + fc, 0)) + 1
		s["_attempts_per_play"] = int(s.get("_attempts_per_play", 0)) + sim.tackle_log.size()
		s["_yards"] = float(s.get("_yards", 0.0)) + float(sim.result.get("yards", 0.0))
	print("\n=== defense %.1f: %d handoffs, %.2f yd/carry, %.2f tackle attempts per carry ===" % [q, plays, s["_yards"] / plays, float(s["_attempts_per_play"]) / plays])
	var keys := s.keys(); keys.sort()
	for k in keys:
		if k.begins_with("_"): continue
		var e = s[k]
		if e is Array:
			print("  %-12s attempts %4d  made %4d (%2.0f%%)  avg odds %2.0f%%  avg %.2fs after handoff" % [k, e[0], e[1], 100.0 * e[1] / e[0], 100.0 * e[2] / e[0], e[3] / e[0]])
		else:
			print("  %-26s %d" % [k, e])
