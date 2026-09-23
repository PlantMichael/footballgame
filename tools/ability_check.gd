extends Node

## Measures whether a passer's "Trusted Target" ability actually reaches the
## catch roll, by running the same matchup twice - once with the ability on
## the QB and once without - and comparing tight-end catch rates.
##
##   godot --headless --path . res://tools/ability_check.tscn

const DT := 1.0 / 120.0
const PLAYS := 900


func _ready() -> void:
	print("=== TRUSTED TARGET (TE) CHECK ===")
	var off := _run("")
	var on := _run("trusted_target_te")

	print("  QB without the ability   %3d/%3d TE catches  (%.0f%%)" % [
		off["caught"], off["targets"], 100.0 * _rate(off)])
	print("  QB with    the ability   %3d/%3d TE catches  (%.0f%%)" % [
		on["caught"], on["targets"], 100.0 * _rate(on)])
	print("  difference               %+.1f points" % (100.0 * (_rate(on) - _rate(off))))
	print("")
	print("  DEX bonus actually applied on %d of %d TE targets" % [on["bonused"], on["targets"]])
	print("  avg TE dexterity at the catch roll:  without %.1f   with %.1f" % [
		off["dex_sum"] / maxf(float(off["targets"]), 1.0),
		on["dex_sum"] / maxf(float(on["targets"]), 1.0)])
	print("  avg air yards on those throws:       without %.1f   with %.1f" % [
		off["air_sum"] / maxf(float(off["targets"]), 1.0),
		on["air_sum"] / maxf(float(on["targets"]), 1.0)])
	get_tree().quit()


func _rate(d: Dictionary) -> float:
	return float(d["caught"]) / maxf(float(d["targets"]), 1.0)


func _run(qb_ability: String) -> Dictionary:
	# Same seed both times, so the only difference is the ability itself.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99001
	GameState.rng.seed = 99001
	GameState.new_run(99001)
	GameState.roster.assign(Generator.starting_roster(GameState.rng, 6.0))
	GameState.auto_fill_lineup()

	# Force the matchup: a known QB and a known TE in the first flex slot.
	var qb := GameState.player_at("QB")
	qb.ability_id = qb_ability
	qb.dexterity = 10
	qb.intelligence = 10
	var te := GameState.player_at("F0")
	te.pos = PlayerData.Pos.TE
	te.dexterity = 10
	te.ability_id = ""

	var out := {"targets": 0, "caught": 0, "bonused": 0, "dex_sum": 0.0, "air_sum": 0.0}

	var sim := MatchSim.new()
	sim.setup(GameState.starters(),
		Generator.make_defense(GameState.rng, 5.0), 5.0, "Test", 999, 99001)
	sim.start_match()

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

		GameState.clear_routes()
		var flexes := sim.flex_players()
		var spots := RouteBook.formation_for(flexes)
		for i in flexes.size():
			GameState.set_route(flexes[i].slot,
				RouteBook.route_for_spot("dig" if i == 0 else "checkdown", spots[i]))
		sim.set_drawn_call(GameState.drawn_routes)
		# Make the TE the read, so most throws go his way.
		sim.clear_priority_targets()
		sim.toggle_priority_target("F0")
		sim.snap()

		var target: SimPlayer = null
		var dex_at_throw := 0
		var live := 0
		while sim.phase == MatchSim.Phase.LIVE and live < 3000:
			var was_in_air := sim.ball_in_air
			sim.step(DT)
			live += 1
			if sim.ball_in_air and not was_in_air:
				target = sim.thrown_to
				if target != null:
					dex_at_throw = target.stat("dexterity")

		if target != null and target.slot == "F0":
			out["targets"] += 1
			out["air_sum"] += maxf(0.0, sim.catch_x - sim.los)
			# eff still holds whatever the catch roll saw.
			var dex_now: int = target.stat("dexterity")
			out["dex_sum"] += float(dex_now)
			if dex_now > dex_at_throw:
				out["bonused"] += 1
			if String(sim.result.get("kind", "")) in ["complete", "touchdown"]:
				out["caught"] += 1

		plays += 1
		sim.advance()

	return out
