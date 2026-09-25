extends Node

## Runs a batch of "Hand Off" plays and reports how they actually go: where
## the back is when he gets the ball, how close the nearest rusher is at
## that moment, who ends up making the tackle, and the yards gained.
##
##   godot --headless --path . res://tools/handoff_check.tscn

const DT := 1.0 / 60.0
const PLAYS := 300
const DRIVE_LEN := 6


func _ready() -> void:
	print("=== HANDOFF CHECK ===")
	for q in [4.5, 6.0, 7.5]:
		print("
##### defense quality %.1f #####" % q)
		for rb_name in ["", "Paimon"]:
			_run(rb_name, q, "")
		_run("", q, "slant")
	# Same back and defense, only the offensive line's Strength changes -
	# run blocking should be what separates these.
	print("
##### offensive line strength (defense 6.0) #####")
	for ol in [3, 12]:
		_run("", 6.0, "", ol)
	get_tree().quit()


## `drawn` - a RouteBook stock route id to chalk for the back, or "" to leave
## him undrawn (random stock route, reads the line for a gap on a handoff).
## `ol_str` - if nonzero, every offensive lineman's Strength is set to it.
func _run(rb_name: String, quality: float, drawn: String, ol_str: int = 0) -> void:
	GameState.rng.seed = 5150
	GameState.new_run(5150)
	GameState.roster.assign(Generator.starting_roster(GameState.rng, quality))
	GameState.auto_fill_lineup()
	var starters: Array = GameState.starters()
	# Make F0 a running back - generated at roster quality, or a named player.
	var rb: PlayerData = null
	if rb_name != "":
		rb = CursedPlayerDB.make_named(RandomNumberGenerator.new(), rb_name)
		rb.pos = PlayerData.Pos.RB
	else:
		rb = Generator.make_player(GameState.rng, PlayerData.Pos.RB, quality)
	starters[GameState.SLOT_ORDER.find("F0")] = rb
	if ol_str > 0:
		for slot in ["C", "T0", "T1", "T2", "T3"]:
			var lineman: PlayerData = (starters[GameState.SLOT_ORDER.find(slot)] as PlayerData).duplicate_player()
			lineman.strength = ol_str
			starters[GameState.SLOT_ORDER.find(slot)] = lineman
	var sim := MatchSim.new()
	sim.setup(starters, Generator.make_defense(GameState.rng, quality), quality, "Test", 999, 4242)
	sim.start_match()
	GameState.clear_routes()

	var n := 0
	var handoffs := 0
	var yards: Array[float] = []
	var by_tackler := {}
	var t_handoff := 0.0
	var ho_depth := 0.0
	var ho_rush_dist := 0.0
	var t_tackle := 0.0
	var guard := 0
	while n < PLAYS and guard < PLAYS * 4:
		guard += 1
		if sim.phase == MatchSim.Phase.DRIVE_OVER:
			sim.begin_drive()
			# A fresh defense every drive, so this isn't one matchup replayed.
			sim.regenerate_defense(GameState.rng, quality)
			continue
		if sim.phase != MatchSim.Phase.PRESNAP:
			sim.advance()
			# Every run gains, so drives here would otherwise never end and
			# fatigue would pile up far past anything a real match sees.
			if sim.phase == MatchSim.Phase.PRESNAP and n % DRIVE_LEN == 0:
				sim.phase = MatchSim.Phase.DRIVE_OVER
			continue
		GameState.clear_routes()
		if drawn != "":
			var spots := RouteBook.formation_for(sim.flex_players())
			GameState.set_route("F0", RouteBook.route_for_spot(drawn, spots[0]))
		sim.set_drawn_call(GameState.drawn_routes)
		var carrier_sp := sim.offense_slot("F0")
		sim.set_planned_handoff("F0")
		sim.snap()
		n += 1
		var live := 0
		var got := false
		while sim.phase == MatchSim.Phase.LIVE and live < 2000:
			sim.step(DT)
			live += 1
			if not got and sim.handoff_done:
				got = true
				handoffs += 1
				t_handoff += sim.time
				ho_depth += carrier_sp.pos.x - sim.los
				var best := 99.0
				for d in sim.defense:
					if d.slot.begins_with("DL") or d.role == SimPlayer.Role.RUSH:
						best = minf(best, d.pos.distance_to(carrier_sp.pos))
				ho_rush_dist += best
		if got:
			yards.append(float(sim.result.get("yards", 0.0)))
			t_tackle += sim.time
			var text := String(sim.result.get("text", ""))
			var who := "other"
			for d in sim.defense:
				if text.contains("tackled by %s" % d.data.pname):
					who = d.slot.substr(0, 2)
			by_tackler[who] = int(by_tackler.get(who, 0)) + 1
	yards.sort()
	var h := maxf(float(handoffs), 1.0)
	var total := 0.0
	var neg := 0
	for y in yards:
		total += y
		neg += 1 if y <= 0.0 else 0
	print("\n[RB: %s  str %d agi %d]" % [rb.pname, rb.strength, rb.agility])
	print("  handoffs %d / %d plays" % [handoffs, n])
	print("  avg handoff at %.2fs, %.1f yd from LOS, nearest rusher %.1f yd away" % [
		t_handoff / h, ho_depth / h, ho_rush_dist / h])
	print("  avg %.2f yd/carry, median %.1f, %.0f%% for <= 0, avg play %.2fs" % [
		total / h, yards[yards.size() / 2] if not yards.is_empty() else 0.0,
		100.0 * neg / h, t_tackle / h])
	print("  tackled by: %s" % str(by_tackler))
