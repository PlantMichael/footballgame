extends Node

## Runs the prop/trigger abilities (banana peels, chains, kegs, slot machine,
## kneecapper, and the mid-play stat gainers) through a pile of real snaps
## and reports whether each one actually fired and did what it says.
##
##   godot --headless --path . res://tools/prop_check.tscn

const DT := 1.0 / 60.0
const PLAYS := 400

## Two lineups, since there are more new players than flex slots.
const LINEUP_A := {"QB": "Gyro Footballi", "T0": "Wide Nelson", "F0": "Trip Slipson",
	"F1": "Evil Warlock", "F2": "Tony KappaKappaPsi", "F3": "RJ Bildgewater", "F4": "Richard MoneyBags"}
const LINEUP_B := {"F0": "Juanwho Knocks", "F1": "Toby Copycat", "F2": "Sigma Mogmen",
	"F3": "Tainted Eden", "F4": "Potential Man"}

var failures := 0


func _ready() -> void:
	print("=== PROP / TRIGGER ABILITY CHECK ===")
	_run_a()
	_run_b()
	print("\n%s" % ("ALL CHECKS PASSED" if failures == 0 else "%d CHECK(S) FAILED" % failures))
	get_tree().quit(1 if failures > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", text])
	if not ok:
		failures += 1


func _make_sim(lineup: Dictionary, seed_value: int) -> MatchSim:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	GameState.rng.seed = seed_value
	GameState.new_run(seed_value)
	GameState.roster.assign(Generator.starting_roster(GameState.rng, 6.0))
	GameState.auto_fill_lineup()
	var starters: Array = GameState.starters()
	var by_name := {}
	for p in ShopPlayerDB.all_players(rng):
		by_name[p.pname] = p
	for slot in lineup:
		starters[GameState.SLOT_ORDER.find(slot)] = by_name[lineup[slot]]
	var sim := MatchSim.new()
	sim.setup(starters, Generator.make_defense(GameState.rng, 6.0), 6.0, "Test", 999, seed_value)
	sim.start_match()
	GameState.clear_routes()
	return sim


func _by_ability(sim: MatchSim, id: String) -> SimPlayer:
	for sp in sim.offense:
		if sp.data.ability_id == id:
			return sp
	return null


func _log_count(sim: MatchSim, needle: String, from: int) -> int:
	var n := 0
	for i in range(from, sim.play_log.size()):
		if String(sim.play_log[i]).contains(needle):
			n += 1
	return n


func _run_a() -> void:
	print("\n[Lineup A: Trip, Warlock, Tony, RJ, Richard, Gyro QB, Wide Nelson T]")
	var sim := _make_sim(LINEUP_A, 4242)
	var trip := _by_ability(sim, "slippery_trail")
	var tony := _by_ability(sim, "keg_stand")
	var nelson := _by_ability(sim, "warming_up")
	var gyro := _by_ability(sim, "power_scramble")

	var s := {"plays": 0, "peels_max": 0, "peel_drive_resets": 0, "slips": 0,
		"chain_plays": 0, "chain_max": 0.0, "kegs": 0, "lured": 0, "slots": 0, "spins": 0, "hits": 0,
		"shots": 0, "slowed_seen": 0, "nelson_gain_ok": 0, "nelson_plays": 0,
		"scrambles": 0, "gyro_bonus_ok": 0, "jackpot_ok": 0}
	var plays := 0
	var guard := 0
	while plays < PLAYS and guard < PLAYS * 4:
		guard += 1
		if sim.phase == MatchSim.Phase.DRIVE_OVER:
			var before := sim.banana_peels.size()
			sim.begin_drive()
			if before > 0 and sim.banana_peels.is_empty():
				s["peel_drive_resets"] += 1
			continue
		if sim.phase != MatchSim.Phase.PRESNAP:
			sim.advance()
			continue
		sim.set_drawn_call(GameState.drawn_routes)
		if plays % 4 == 3:
			sim.set_planned_action("scramble")
		s["chain_plays"] += 1 if sim.chains.size() == 1 else 0
		var log_from := sim.play_log.size()
		var gyro_str_before := 0
		var team_before := {}
		sim.snap()
		plays += 1
		var nelson_start := nelson.stat("strength")
		var live := 0
		var bonus_checked := false
		var jackpot_checked := false
		while sim.phase == MatchSim.Phase.LIVE and live < 2000:
			if live == 0:
				gyro_str_before = gyro.stat("strength")
			if not jackpot_checked and sim.time < MatchSim.SLOT_SPIN_TIME:
				for o in sim.offense:
					team_before[o] = o.stat("dexterity")
			sim.step(DT)
			live += 1
			for c in sim.chains:
				s["chain_max"] = maxf(s["chain_max"], (c[0] as SimPlayer).pos.distance_to((c[1] as SimPlayer).pos))
			for d in sim.defense:
				if d.slowed > 0.0 and sim.time > 4.5 and sim.time < 4.6:
					s["slowed_seen"] += 1
			if not bonus_checked and sim.qb_scrambling and gyro.run_bonus_used:
				bonus_checked = true
				s["scrambles"] += 1
				if gyro.stat("strength") >= mini(gyro_str_before + 4, 15):
					s["gyro_bonus_ok"] += 1
			if not jackpot_checked and not sim.slot_machine.is_empty() and sim.slot_machine["resolved"]:
				jackpot_checked = true
				if sim.slot_machine["hit"]:
					var all_up := true
					for o in sim.offense:
						if o.stat("dexterity") < mini(int(team_before[o]) + MatchSim.JACKPOT_BONUS, 15):
							all_up = false
					s["jackpot_ok"] += 1 if all_up else 0
		if sim.time >= 3.0:
			s["nelson_plays"] += 1
			if nelson.stat("strength") >= mini(nelson_start + int(sim.time) - 1, 15):
				s["nelson_gain_ok"] += 1
		s["peels_max"] = maxi(s["peels_max"], sim.banana_peels.size())
		s["slips"] += _log_count(sim, "slips on a banana", log_from)
		s["kegs"] += sim.kegs.size()
		for d in sim.defense:
			s["lured"] += 1 if d.lured else 0
		if not sim.slot_machine.is_empty():
			s["slots"] += 1
			# A play over before the reels stop never pays out either way.
			if sim.slot_machine["resolved"]:
				s["spins"] += 1
				s["hits"] += 1 if sim.slot_machine["hit"] else 0
		s["shots"] += sim.shots.size()
		sim.advance()

	s["plays"] = plays
	print("  %d plays" % plays)
	_check(s["peels_max"] >= 2, "peels pile up within a drive (max on field %d)" % s["peels_max"])
	_check(s["peel_drive_resets"] > 0, "peels swept up at the next drive (%d times)" % s["peel_drive_resets"])
	_check(s["slips"] > 0, "defenders slip on peels (%d slips)" % s["slips"])
	_check(s["chain_plays"] == plays, "a chain is on the field every snap (%d/%d)" % [s["chain_plays"], plays])
	_check(s["chain_max"] <= 5.01, "chained pair never more than 5 yd apart (max %.2f)" % s["chain_max"])
	_check(s["kegs"] > 0 and s["lured"] == s["kegs"] * 2, "kegs dropped %d, defenders lured %d" % [s["kegs"], s["lured"]])
	var rate := float(s["hits"]) / maxf(float(s["spins"]), 1.0)
	_check(s["slots"] == plays and rate > 0.25 and rate < 0.41,
		"slot machine every snap (%d), hit rate %.0f%% of %d finished spins" % [s["slots"], 100.0 * rate, s["spins"]])
	_check(s["jackpot_ok"] == s["hits"], "jackpot buffs the whole team (%d/%d)" % [s["jackpot_ok"], s["hits"]])
	_check(s["shots"] == plays, "kneecapper shoots every snap (%d)" % s["shots"])
	_check(s["slowed_seen"] > 0, "a shot defender is still slowed ~4.5s in")
	_check(s["nelson_plays"] > 0 and s["nelson_gain_ok"] == s["nelson_plays"],
		"Wide Nelson +1 STR/sec (%d/%d long plays)" % [s["nelson_gain_ok"], s["nelson_plays"]])
	_check(s["scrambles"] > 0 and s["gyro_bonus_ok"] == s["scrambles"],
		"Gyro +4 STR on scramble (%d/%d)" % [s["gyro_bonus_ok"], s["scrambles"]])


func _run_b() -> void:
	print("\n[Lineup B: Juanwho, Toby, Sigma, Tainted, Potential Man]")
	var sim := _make_sim(LINEUP_B, 777)
	var juan := _by_ability(sim, "knock_knock")
	var toby := _by_ability(sim, "copycat")
	var sigma := _by_ability(sim, "sigma_grindset")
	var eden := _by_ability(sim, "tainted_blessing")
	var pot := _by_ability(sim, "wasted_potential")

	var s := {"handoffs": 0, "juan_ok": 0, "sigma_undrawn_ok": 0, "sigma_undrawn": 0,
		"sigma_drawn_ok": 0, "sigma_drawn": 0, "eden_ok": 0, "toby_copied": 0, "toby_checks": 0,
		"pot_ez": 0, "pot_ez_caught": 0}
	var plays := 0
	var guard := 0
	while plays < PLAYS and guard < PLAYS * 4:
		guard += 1
		if sim.phase == MatchSim.Phase.DRIVE_OVER:
			sim.begin_drive()
			continue
		if sim.phase != MatchSim.Phase.PRESNAP:
			sim.advance()
			continue
		# Every other snap, chalk Sigma a route so both sides of his
		# condition get exercised. Potential Man always runs a go, from
		# close enough that it reaches the end zone.
		sim.los = MatchSim.GOAL_LINE - 12.0
		sim.to_go = 10.0
		GameState.clear_routes()
		var flexes := sim.flex_players()
		var spots := RouteBook.formation_for(flexes)
		for i in flexes.size():
			if flexes[i] == pot:
				GameState.set_route(pot.slot, RouteBook.route_for_spot("go", spots[i]))
			elif flexes[i] == sigma and plays % 2 == 0:
				GameState.set_route(sigma.slot, RouteBook.route_for_spot("slant", spots[i]))
		sim.set_drawn_call(GameState.drawn_routes)
		if plays % 3 == 0:
			sim.set_planned_handoff(juan.slot)
		var sigma_pre := sigma.stat("agility")
		var eden_pre := {}
		for k in MatchSim.STAT_KEYS:
			eden_pre[k] = eden.stat(k)
		var toby_pre := {}
		for k in MatchSim.STAT_KEYS:
			toby_pre[k] = toby.stat(k)
		sim.snap()
		plays += 1

		var undrawn := sim.auto_route_ids.has(sigma.slot)
		var sigma_ok := sigma.stat("agility") == mini(sigma_pre + 4, 15) if undrawn else sigma.stat("agility") == sigma_pre
		if undrawn:
			s["sigma_undrawn"] += 1
			s["sigma_undrawn_ok"] += 1 if sigma_ok else 0
		else:
			s["sigma_drawn"] += 1
			s["sigma_drawn_ok"] += 1 if sigma_ok else 0
		var eden_up := 0
		for k in MatchSim.STAT_KEYS:
			if eden.stat(k) > int(eden_pre[k]):
				eden_up += 1
		s["eden_ok"] += 1 if eden_up == 1 else 0
		# Toby should have copied Eden's random gain (and Sigma's, if any).
		var toby_up := 0
		for k in MatchSim.STAT_KEYS:
			toby_up += toby.stat(k) - int(toby_pre[k])
		s["toby_checks"] += 1
		s["toby_copied"] += 1 if toby_up > 0 else 0

		var juan_pre := 0
		var live := 0
		while sim.phase == MatchSim.Phase.LIVE and live < 2000:
			var was_done := sim.handoff_done
			juan_pre = juan.stat("agility")
			sim.step(DT)
			live += 1
			if not was_done and sim.handoff_done and sim.carrier == juan:
				s["handoffs"] += 1
				s["juan_ok"] += 1 if juan.stat("agility") >= mini(juan_pre + 3, 15) else 0
		if int(pot.eff.get("dexterity", -1)) == 0:
			s["pot_ez"] += 1
			if sim._last_completion_target == pot:
				s["pot_ez_caught"] += 1
		sim.advance()

	print("  %d plays" % plays)
	_check(s["handoffs"] > 0 and s["juan_ok"] == s["handoffs"],
		"Juanwho +3 AGI on handoff (%d/%d)" % [s["juan_ok"], s["handoffs"]])
	_check(s["sigma_undrawn"] > 0 and s["sigma_undrawn_ok"] == s["sigma_undrawn"],
		"Sigma +4 AGI when undrawn (%d/%d)" % [s["sigma_undrawn_ok"], s["sigma_undrawn"]])
	_check(s["sigma_drawn"] > 0 and s["sigma_drawn_ok"] == s["sigma_drawn"],
		"Sigma no bonus when drawn (%d/%d)" % [s["sigma_drawn_ok"], s["sigma_drawn"]])
	_check(s["eden_ok"] == plays, "Tainted Eden exactly one stat up every snap (%d/%d)" % [s["eden_ok"], plays])
	_check(s["toby_copied"] == s["toby_checks"], "Toby copies teammates' snap gains (%d/%d)" % [s["toby_copied"], s["toby_checks"]])
	_check(s["pot_ez"] > 0, "Potential Man hit 0 DEX on an end zone catch attempt (%d plays)" % s["pot_ez"])
	_check(s["pot_ez_caught"] == 0, "Potential Man never catches in the end zone (%d caught)" % s["pot_ez_caught"])
