extends Node

## Pass protection under a single weak lineman. Pins every offensive lineman
## and every DL to set Strength values, runs a few hundred random-route pass
## plays, and reports sack rate, time to sack, and which blocker got beaten
## first. Scouting and auras are switched off so only the blocking math shows.
##
##   godot --headless --path . res://tools/oline_check.tscn
func _ready() -> void:
	_run("even: OL 4, DL 4", 4, 4, -1, 4)
	_run("one T at 2, DL 4", 4, 4, 2, 2)
	_run("one T at 2, DL 6", 4, 6, 2, 2)
	_run("even: OL 6, DL 6", 6, 6, -1, 6)
	get_tree().quit()

func _run(label: String, ol_str: int, dl_str: int, weak_idx: int, weak_str: int) -> void:
	GameState.rng.seed = 777
	GameState.new_run(777)
	GameState.roster.assign(Generator.starting_roster(GameState.rng, 4.0))
	GameState.auto_fill_lineup()
	var starters: Array = GameState.starters()
	for i in starters.size():
		var slot: String = GameState.SLOT_ORDER[i]
		var p: PlayerData = starters[i]
		if slot == "C" or slot.begins_with("T"):
			p.strength = ol_str
			p.ability_id = ""
			p.items = []
		if slot == "QB":
			p.agility = 4
	if weak_idx >= 0:
		(starters[GameState.SLOT_ORDER.find("T%d" % weak_idx)] as PlayerData).strength = weak_str
	var defense := Generator.make_defense(GameState.rng, 4.0)
	for d in defense:
		d.aura_id = ""
	for i in 4:
		defense[i].strength = dl_str
	var sim := MatchSim.new()
	sim.setup(starters, defense, 4.0, "T", 999, 4242)
	sim.start_match()
	GameState.clear_routes()

	var plays := 0
	var sacks := 0
	var fast_sacks := 0
	var sack_time := 0.0
	var first_beaten := {}
	var sheds := {}
	var sackers := {}
	var rush_hist := {}
	var n := 0
	while plays < 400 and n < 4000:
		n += 1
		if sim.phase == MatchSim.Phase.DRIVE_OVER:
			sim.begin_drive(); continue
		if sim.phase != MatchSim.Phase.PRESNAP:
			sim.advance()
			continue
		sim.scout_log.clear()
		sim.scout_reads = {}
		sim.set_drawn_call(GameState.drawn_routes)
		sim.snap(); plays += 1
		var beaten := ""
		var cds := {}
		var ever_blocked := {}
		var rushers := 0
		for d in sim.defense:
			if d.role == SimPlayer.Role.RUSH:
				rushers += 1
		rush_hist[rushers] = int(rush_hist.get(rushers, 0)) + 1
		var g := 0
		while sim.phase == MatchSim.Phase.LIVE and g < 2000:
			sim.step(1.0 / 60.0); g += 1
			for b in sim.offense:
				if not (b.slot == "C" or b.slot.begins_with("T")):
					continue
				if b.shed_cooldown > 0.0 and float(cds.get(b.slot, 0.0)) <= 0.0:
					sheds[b.slot] = int(sheds.get(b.slot, 0)) + 1
					if beaten == "":
						beaten = "%s @%.1fs" % [b.slot, sim.time]
				cds[b.slot] = b.shed_cooldown
			for b in sim.offense:
				if b.mark != null:
					ever_blocked[b.mark] = true
		if String(sim.result.get("kind", "")) == "sack":
			sacks += 1
			sack_time += sim.time
			if sim.time < 2.5:
				fast_sacks += 1
			var key := beaten.get_slice(" ", 0) if beaten != "" else "nobody shed"
			first_beaten[key] = int(first_beaten.get(key, 0)) + 1
			var t: SimPlayer = sim.tackler
			var who := "%s %s, %d rushers" % [t.slot.substr(0, 2), "was blocked" if ever_blocked.has(t) else "NEVER blocked", rushers]
			sackers[who] = int(sackers.get(who, 0)) + 1
	print("\n=== %s: %d dropbacks ===" % [label, plays])
	print("  sacks %d (%.0f%%), under 2.5s %d, avg %.2fs" % [sacks, 100.0 * sacks / plays, fast_sacks, sack_time / maxf(sacks, 1)])
	print("  first blocker beaten on sacks: ", first_beaten)
	print("  sackers: ", sackers)
	print("  rushers per snap: ", rush_hist)
	print("  sheds per blocker (all plays): ", sheds)
