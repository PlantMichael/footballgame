extends Node

## Difficulty check for a single superstar: plays full matches round by round
## with a rookie-grade roster, once as-is and once with a cursed/All-Star
## player dropped into a flex slot (and made the QB's priority target), using
## the same defense quality the real match screen asks GameState for. Prints
## win rate, score, and the star's yards per match.
##   godot --headless --path . res://tools/star_check.tscn
## STAR=<name> picks the star (default Beelzebub); MATCHES=<n> per round.

const DT := 1.0 / 60.0
const PLAY_POOL := ["quick_outs", "slant_flood", "curl_and_out", "hb_dive", "four_verticals"]
## Same "coach keeps upgrading" model as sim_test.gd.
const ROSTER_BASE := 3.0
const ROSTER_GROWTH := 0.55


func _ready() -> void:
	var star_name := OS.get_environment("STAR")
	if star_name == "":
		star_name = "Beelzebub"
	var matches := int(OS.get_environment("MATCHES")) if OS.get_environment("MATCHES") != "" else 16
	print("=== STAR CHECK (%s, %d matches/round) ===" % [star_name, matches])
	print("round      | no star: win  score      | with star: win  score      star yd  def q")
	for round_index in 5:
		# ONLY_STAR=1 skips the no-star baseline, for faster tuning passes.
		var base := {"win": 0.0, "us": 0.0, "them": 0.0, "q": 0.0} if OS.get_environment("ONLY_STAR") != "" \
			else _run(round_index, "", matches)
		var star := _run(round_index, star_name, matches)
		print("%-10s |   %3.0f%%  %4.1f-%4.1f       |   %3.0f%%  %4.1f-%4.1f     %5.0f   %.1f -> %.1f" % [
			["Wild Card", "Divisional", "Conference", "Semifinal", "Bowl"][round_index],
			base["win"], base["us"], base["them"],
			star["win"], star["us"], star["them"], star["star_yards"], base["q"], star["q"]])
	get_tree().quit()


func _run(round_index: int, star_name: String, matches: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5000 + round_index
	var wins := 0.0
	var us := 0.0
	var them := 0.0
	var star_yards := 0.0
	var q_sum := 0.0
	for m in matches:
		GameState.new_run(rng.randi())
		GameState.round_index = round_index
		GameState.matches_played = round_index
		GameState.roster.assign(Generator.starting_roster(GameState.rng, ROSTER_BASE + round_index * ROSTER_GROWTH))
		var star: PlayerData = null
		if star_name != "":
			star = CursedPlayerDB.make_named(GameState.rng, star_name)
			if star == null:
				star = ShopPlayerDB.all_players(GameState.rng).filter(func(p): return p.pname == star_name).front()
			GameState.roster.append(star)
		GameState.auto_fill_lineup()
		if star != null and not GameState.lineup.values().has(GameState.roster.size() - 1):
			GameState.lineup["F0"] = GameState.roster.size() - 1

		var quality := GameState.current_match_quality()
		q_sum += quality
		var opp: Dictionary = GameState.current_opponent()
		var defense := Generator.make_defense(GameState.rng, quality, GameState.aura_count(GameState.rng))
		# Looked up by name so this harness still runs against older checkouts
		# (for before/after comparisons) that predate it.
		var gen: Script = load("res://scripts/data/generator.gd")
		if gen.get_script_method_list().any(func(m): return m["name"] == "add_shutdown_defender"):
			gen.call("add_shutdown_defender", defense, GameState.starters(), quality)
		var sim := MatchSim.new()
		sim.setup(GameState.starters(), defense, quality, "Test", int(opp["drives"]), rng.randi())
		sim.start_match()
		var guard := 0
		while guard < 500:
			guard += 1
			if sim.phase == MatchSim.Phase.DRIVE_OVER:
				if sim.drive_num >= sim.total_drives:
					break
				sim.sim_opponent_drive()
				sim.begin_drive()
				continue
			if sim.phase == MatchSim.Phase.PRESNAP:
				sim.set_play(PLAY_POOL[GameState.rng.randi_range(0, PLAY_POOL.size() - 1)])
				if star != null:
					for f in sim.flex_players():
						if f.data == star:
							sim.priority_targets[f.slot] = true
				sim.snap()
				var live := 0
				while sim.phase == MatchSim.Phase.LIVE and live < 2000:
					sim.step(DT)
					live += 1
				sim.advance()
		us += sim.score_us
		them += sim.score_them
		if sim.won():
			wins += 1.0
		if star != null:
			var line := sim.stat_line_for(star)
			star_yards += float(line.get("rec_yards", 0.0)) + float(line.get("rush_yards", 0.0))
	var n := float(matches)
	return {"win": 100.0 * wins / n, "us": us / n, "them": them / n, "star_yards": star_yards / n, "q": q_sum / n}
