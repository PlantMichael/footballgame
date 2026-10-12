extends Node

## Replays the oline_check setup until the first sack and prints the sacker,
## his blocker, and the QB every 0.1s, to see how a blocked rusher gets home.
##
##   godot --headless --path . res://tools/sack_trace.tscn
func _ready() -> void:
	GameState.rng.seed = 777
	GameState.new_run(777)
	GameState.roster.assign(Generator.starting_roster(GameState.rng, 4.0))
	GameState.auto_fill_lineup()
	var starters: Array = GameState.starters()
	for i in starters.size():
		var slot: String = GameState.SLOT_ORDER[i]
		var p: PlayerData = starters[i]
		if slot == "C" or slot.begins_with("T"):
			p.strength = 4; p.ability_id = ""; p.items = []
		if slot == "QB":
			p.agility = 4
	var defense := Generator.make_defense(GameState.rng, 4.0)
	for d in defense:
		d.aura_id = ""
	for i in 4:
		defense[i].strength = 4
	var sim := MatchSim.new()
	sim.setup(starters, defense, 4.0, "T", 999, 4242)
	sim.start_match()
	GameState.clear_routes()
	var shown := 0
	var n := 0
	while shown < 3 and n < 4000:
		n += 1
		if sim.phase == MatchSim.Phase.DRIVE_OVER:
			sim.begin_drive(); continue
		if sim.phase != MatchSim.Phase.PRESNAP:
			sim.advance(); continue
		sim.scout_log.clear(); sim.scout_reads = {}
		sim.set_drawn_call(GameState.drawn_routes)
		sim.snap()
		var frames: Array = []
		var g := 0
		while sim.phase == MatchSim.Phase.LIVE and g < 2000:
			sim.step(1.0 / 60.0); g += 1
			var qb := sim.offense_slot("QB")
			var line := "t=%.2f QB(%.1f,%.1f) |" % [sim.time, qb.pos.x - sim.los, qb.pos.y]
			for d in sim.defense:
				if not d.slot.begins_with("DL"):
					continue
				var blk := "-"
				for b in sim.offense:
					if b.mark == d:
						blk = "%s%s d=%.1f" % [b.slot, "*" if b.engaged else "", b.pos.distance_to(d.pos)]
				line += " %s(%.1f,%.1f)%s[%s] dQB=%.1f |" % [d.slot, d.pos.x - sim.los, d.pos.y, "E" if d.engaged else "", blk, d.pos.distance_to(qb.pos)]
			frames.append(line)
		if String(sim.result.get("kind", "")) == "sack":
			shown += 1
			print("\n--- sack by %s at %.2fs ---" % [sim.tackler.slot, sim.time])
			for i in range(0, frames.size(), 6):
				print(frames[i])
			print(frames[frames.size() - 1])
	get_tree().quit()
