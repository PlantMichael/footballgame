extends Node

## Cooperative abilities at real snap, movement, catch, award and sub owners.
## godot --headless --path . res://tools/synergy_check.tscn
var failures := 0
var players: Dictionary = {}
const NAMES := ["Lane Merge", "Cris Crosswell", "Wade Window", "Moe Tow", "Stu Wallworth",
	"Lance Layover", "Miles Eventually", "Chip Hammock", "Skip Dinkley", "Duke Dumptruck",
	"Perry Perimeter", "Artie Asphalt", "Gus Everybody", "Al Firstman", "Reggie Seconds",
	"Benny Bookmark", "Freshman Freddie", "Lou Relief", "Conrad Clipboard", "Brock Breather",
	"Chalk Norris", "Phil Echo", "Stan Doubletake", "Otto Pilot"]


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 100
	for p in ShopPlayerDB.all_players(rng):
		players[p.pname] = p
	for name in NAMES:
		_check(players.has(name), "%s obtainable from shop data" % name)
		if players.has(name):
			var p: PlayerData = players[name]
			_check(not AbilityDB.synergy_traits(p.ability_id).is_empty() and p.quality >= 2 and p.quality <= 4,
				"%s has a real ability and shop tier" % name)
	_crossings()
	_patience()
	_screens()
	_sharing()
	_rotation()
	_chalk()
	_echo()
	_decoy()
	_automatic()
	_lifecycle_edges()
	var disposed := _dispose_match()
	_check(disposed[0].get_ref() == null and disposed[1].get_ref() == null,
		"disposing a match releases mutual block/coverage and support references")
	await _substitution_ui()
	print("SYNERGY CHECK: %s" % ("ALL CHECKS PASSED" if failures == 0 else "%d FAILURES" % failures))
	get_tree().quit(1 if failures else 0)


func _fresh(name: String) -> PlayerData:
	var p: PlayerData = players[name].duplicate()
	# Neutral effective stats isolate abilities from their shop balance values.
	for key in PlayerData.STAT_KEYS:
		p.set(key, 5)
	p.items.assign(["", "", ""])
	return p


func _dispose_match() -> Array:
	var sim := _make({"F0": "Moe Tow"})
	var blocker := sim.offense_slot("F0")
	var defender := sim.defense[7]
	blocker.mark = defender
	defender.mark = blocker
	blocker.synergy["block_target"] = defender
	return [weakref(blocker), weakref(defender)]


func _make(selection: Dictionary, start: bool = true) -> MatchSim:
	GameState.new_run(9001)
	var starters := GameState.starters()
	for slot in selection:
		starters[GameState.SLOT_ORDER.find(slot)] = _fresh(selection[slot])
	var sim := MatchSim.new()
	sim.setup(starters, Generator.make_defense(GameState.rng, 4.0), 4.0, "Test defense", 5, 777)
	sim.start_match()
	sim.set_drawn_call(_routes())
	if start:
		sim.snap()
	return sim


func _routes() -> Dictionary:
	var out := {}
	for i in 5:
		out["F%d" % i] = [Vector2(20, 0)]
	return out


func _next(sim: MatchSim, routes: Dictionary = {}) -> void:
	if sim.phase == MatchSim.Phase.LIVE:
		sim._end_play({"kind": "run", "yards": 0.0, "text": "Whistle"})
	# Keep these multi-play fixtures on a long drive; drive reset is explicit.
	sim.down = 1
	sim.advance()
	sim.set_drawn_call(_routes() if routes.is_empty() else routes)
	sim.snap()


func _complete(sim: MatchSim, rec: SimPlayer, depth: float = 3.0) -> void:
	rec.pos = Vector2(sim.los + depth, 15.0)
	rec.vel = Vector2.ZERO
	sim._throw(sim.offense_slot("QB"), rec)
	# Fix catch geometry, not outcome logic; the real catch still rolls.
	sim.ball_to = rec.pos
	var probe := RandomNumberGenerator.new()
	for seed_value in 1000:
		probe.seed = seed_value
		if probe.randf() < 0.01:
			sim.rng.seed = seed_value
			break
	sim._step_ball(sim.ball_air_time + 0.01)
	_check(sim.carrier != null and sim.carrier.data == rec.data, "real catch succeeds for %s" % rec.data.pname)


func _far_defense(sim: MatchSim) -> void:
	for d in sim.defense:
		d.pos = Vector2(100, 50)
		d.mark = null


func _crossings() -> void:
	var s := _make({"QB": "Wade Window", "F0": "Lane Merge", "F1": "Cris Crosswell", "F2": "Moe Tow"})
	var lane := s.offense_slot("F0")
	var cris := s.offense_slot("F1")
	var moe := s.offense_slot("F2")
	var stationary := s.offense_slot("F3")
	lane.pos = Vector2(s.los + 3, 15)
	cris.pos = lane.pos + Vector2(0, 1)
	moe.pos = cris.pos + Vector2(0, 8)
	stationary.pos = lane.pos + Vector2(0, 0.4)
	var man := s.defense[7]
	man.mark = cris
	man.role = SimPlayer.Role.MAN
	s._step_synergies(0.01)
	_check(cris.burst_left == 0, "alignment proximity alone does not trigger a crossing")
	lane.odometer = 1
	cris.odometer = 1
	s._step_synergies(0.01)
	_check(cris.burst_left > 0 and man.stunned > 0, "a nearer stationary receiver cannot suppress Lane and Cris's eligible crossing")
	var burst := cris.burst_left
	s._step_synergies(0.1)
	_check(cris.burst_left < burst, "crossing does not refresh its burst every frame")
	var qb := s.offense_slot("QB")
	cris.vel = Vector2.ZERO
	s.rng.seed = 321
	s._throw(qb, cris)
	var boosted := s.ball_to.distance_to(cris.pos)
	cris.synergy.erase("boost_until")
	s.rng.seed = 321
	s._throw(qb, cris)
	_check(is_equal_approx(boosted, s.ball_to.distance_to(cris.pos) * 0.65), "Wade reduces scatter for a teammate-boosted receiver")
	_far_defense(s)
	s.defense[8].pos = cris.pos + Vector2(3, 0)
	_complete(s, cris)
	_check(moe.role == SimPlayer.Role.BLOCK and moe.mark != null, "Moe escorts a nearby catch")


func _patience() -> void:
	var s := _make({"QB": "Lance Layover", "T0": "Stu Wallworth", "F0": "Miles Eventually", "C": "Chip Hammock"})
	var stu := s.offense_slot("T0")
	var qb := s.offense_slot("QB")
	var base := qb.stat("intelligence")
	stu.engaged = true
	stu.mark = s.defense[0]
	s._step_synergies(0.6)
	stu.engaged = false
	s._step_synergies(0.1)
	stu.engaged = true
	s._step_synergies(0.6)
	_check(qb.stat("intelligence") == base, "Stu must hold an uninterrupted second")
	s._step_synergies(0.4)
	s._step_synergies(4.0)
	_check(qb.stat("intelligence") == mini(15, base + 3), "Stu's pocket support caps at three gains")
	_far_defense(s)
	s.play["dropback"] = 10.0
	for i in 245:
		s.step(1.0 / 60.0)
	var miles := s.offense_slot("F0")
	_check(miles.synergy.has("late_used"), "Miles bursts after three untargeted seconds")
	var dex := miles.stat("dexterity")
	_complete(s, miles, 10)
	_check(miles.stat("dexterity") == mini(dex + 3, 15), "Lance's patient throw improves the actual catch attempt")
	for sp in s.offense:
		sp.energy = 0.2
	s._end_play({"kind": "complete", "yards": 10.0, "text": "Whistle"})
	_check(is_equal_approx(s.offense_slot("T1").energy, 0.4), "Chip restores line fatigue after a real four-second pocket hold")
	var early := _make({"F0": "Miles Eventually"})
	early._throw(early.offense_slot("QB"), early.offense_slot("F0"))
	early.time = 3.1
	early._step_synergies(0.01)
	_check(early.offense_slot("F0").burst_left == 0, "Miles does not burst after being targeted early")
	_late_target_boundary(2.97, false)
	_late_target_boundary(2.99, true)


func _late_target_boundary(before_step: float, should_burst: bool) -> void:
	var s := _make({"F0": "Miles Eventually"})
	_far_defense(s)
	var miles := s.offense_slot("F0")
	for sp in s.flex_players():
		if sp != miles:
			sp.melted = true
	miles.pos = Vector2(s.los + 3, 15)
	s.play["dropback"] = 0.0
	s.time = before_step
	s.step(0.02)
	_check(s.thrown_to == miles, "boundary fixture makes a real first throw at %.2fs" % s.time)
	if not should_burst:
		s.step(0.02)
	_check((miles.burst_left > 0) == should_burst,
		"Miles first targeted %s 3 seconds %s his late burst" % ["after" if should_burst else "before", "receives" if should_burst else "does not receive"])


func _screens() -> void:
	var s := _make({"QB": "Skip Dinkley", "F0": "Duke Dumptruck", "F1": "Perry Perimeter", "T0": "Artie Asphalt"})
	_far_defense(s)
	var duke := s.offense_slot("F0")
	var perry := s.offense_slot("F1")
	perry.pos = Vector2(s.los + 8, 15)
	s.defense[7].pos = Vector2(s.los + 6, 15)
	var strength := duke.stat("strength")
	_complete(s, duke)
	_check(duke.stat("strength") == strength + 2 and duke.burst_left > 0, "Skip's short pass activates Duke's rolling start")
	_check(perry.role == SimPlayer.Role.BLOCK and perry.mark == s.defense[7], "Perry blocks a defender between himself and the catch")
	var artie := s.offense_slot("T0")
	artie.engaged = true
	artie.mark = s.defense[0]
	s._step_synergies(0.01)
	_check(s.speed_patches.size() == 1, "Artie creates pavement on his first held block")
	duke.pos = artie.pos
	duke.burst_left = 0
	duke.energy = 1
	s._step_synergies(0.01)
	_check(is_equal_approx(duke.speed(), duke.max_speed() * 1.25), "teammates crossing pavement move faster")
	s.time = 3.1
	s._step_synergies(0.01)
	_check(s.speed_patches.is_empty() and duke.pavement_left == 0, "pavement expires and cannot be respawned this play")
	var deep := _make({"QB": "Skip Dinkley", "F0": "Duke Dumptruck"})
	_far_defense(deep)
	var deep_str := deep.offense_slot("F0").stat("strength")
	_complete(deep, deep.offense_slot("F0"), 8)
	_check(deep.offense_slot("F0").stat("strength") == deep_str, "Skip does not boost a deeper catch")


func _sharing() -> void:
	var s := _make({"QB": "Gus Everybody", "F0": "Al Firstman", "F1": "Reggie Seconds", "F2": "Benny Bookmark"})
	_far_defense(s)
	var gus := s.offense_slot("QB")
	var benny := s.offense_slot("F2")
	var gus_dex := gus.stat("dexterity")
	var benny_str := benny.stat("strength")
	var reggie_base := s.offense_slot("F1").stat("dexterity")
	_complete(s, s.offense_slot("F0"))
	_check(gus.stat("dexterity") == gus_dex + 1 and benny.stat("strength") == benny_str + 1, "Al's catch feeds Gus and Benny")
	_next(s)
	_far_defense(s)
	var reggie := s.offense_slot("F1")
	var reggie_dex := reggie.stat("dexterity")
	_check(reggie_dex == reggie_base + 1, "Al's drive buff survives the next snap")
	_complete(s, reggie)
	_check(reggie.stat("dexterity") == reggie_dex + 3, "Reggie rewards alternating completion targets")
	_next(s)
	_far_defense(s)
	reggie_dex = reggie.stat("dexterity")
	_complete(s, reggie)
	_check(reggie.stat("dexterity") == reggie_dex and gus.stat("dexterity") == gus_dex + 2,
		"repeating a catcher neither buffs Reggie nor increases diversity")
	s.begin_drive()
	s.set_drawn_call(_routes())
	s.snap()
	_check(gus.stat("dexterity") == gus_dex and reggie.stat("dexterity") == reggie_base and benny.stat("strength") == benny_str,
		"all sharing bonuses reset between drives")


func _rotation() -> void:
	var s := _make({"C": "Conrad Clipboard", "F0": "Brock Breather"}, false)
	var original := s.offense_slot("F1").data
	var starters: Array = []
	for sp in s.offense:
		starters.append(sp.data)
	var freddie := _fresh("Freshman Freddie")
	starters[GameState.SLOT_ORDER.find("F1")] = freddie
	s.resync_offense(starters)
	s.set_drawn_call(_routes())
	s.set_drawn_call(_routes(), false)
	_check(s.offense_slot("F1").stat("agility") == 5, "presnap edits do not grant fresh-leg rewards")
	s.snap()
	_check(s.offense_slot("F1").stat("agility") == 8 and s.offense_slot("F1").stat("intelligence") == 7,
		"Freddie combines bench entry with Conrad's first-snap support")
	s.offense_slot("F1").energy = 0.1
	starters[GameState.SLOT_ORDER.find("F1")] = original
	s.resync_offense(starters)
	s.set_drawn_call(_routes())
	s.snap()
	var brock := s.offense_slot("F0")
	s.carrier = brock
	brock.has_ball = true
	s._end_play({"kind": "run", "yards": 1.0, "text": "Whistle"})
	starters[GameState.SLOT_ORDER.find("F1")] = freddie
	s.resync_offense(starters)
	_check(is_equal_approx(s.offense_slot("F1").energy, 0.65), "Brock restores the remembered bench player's fatigue")
	s.set_drawn_call(_routes())
	s.snap()
	_check(s.offense_slot("F1").stat("agility") == 5 and s.offense_slot("F1").stat("intelligence") == 5,
		"rebuilding players cannot farm Freddie or Conrad again this drive")
	var lou := _fresh("Lou Relief")
	starters[GameState.SLOT_ORDER.find("T1")] = lou
	s.resync_offense(starters)
	s.set_drawn_call(_routes())
	s.offense_slot("T0").energy = 0.2
	s.offense_slot("C").energy = 0.2
	s.snap()
	_check(is_equal_approx(s.offense_slot("T0").energy, 0.5) and is_equal_approx(s.offense_slot("C").energy, 0.5),
		"Lou restores adjacent linemen at the actual substitution snap")


func _chalk() -> void:
	var s := _make({"F0": "Chalk Norris", "F1": "Beelzebub"} if players.has("Beelzebub") else {"F0": "Chalk Norris"}, false)
	# Cursed players have a separate producer, so install the real Boundless player.
	var rng := RandomNumberGenerator.new()
	rng.seed = 111
	s.offense_slot("F1").data = CursedPlayerDB.make_named(rng, "Beelzebub")
	var routes := _routes()
	routes["F0"] = [Vector2(70, 0)]
	routes["F1"] = [Vector2(70, 0)]
	s.set_drawn_call(routes)
	_check(s.route_budget(s.offense_slot("F0")) == 20 and s.route_budget(s.offense_slot("F1")) == 65,
		"Chalk donates after the existing Boundless multiplier")
	_check(RouteBook.route_length(s.play["routes"][0]) == 20 and RouteBook.route_length(s.play["routes"][1]) == 65,
		"simulation clips to the same allowance as drawing")
	_check(RouteBook.route_length(routes["F0"]) == 70, "effective clipping preserves stored route geometry")


func _echo() -> void:
	var s := _make({"F0": "Phil Echo", "F1": "Duke Dumptruck", "F2": "Toby Copycat"})
	var phil := s.offense_slot("F0")
	var duke := s.offense_slot("F1")
	var toby := s.offense_slot("F2")
	phil.pos = Vector2(70, 20)
	duke.pos = Vector2(71, 20)
	toby.pos = Vector2(75, 20)
	phil.eff["strength"] = 14
	s._gain_stat(phil, "strength", 3, true, s.offense_slot("QB"))
	_check(phil.stat("strength") == 15 and duke.stat("strength") == 6 and toby.stat("strength") == 6,
		"Phil and Toby forward the actual capped gain without recursion")
	_check(duke.burst_left > 0, "Phil's echoed Strength activates Duke")
	s._gain_stat(phil, "intelligence", 2, true, s.offense_slot("QB"))
	_check(duke.stat("intelligence") == 5 and toby.stat("intelligence") == 7, "Phil echoes once while Toby still copies later original gains")
	s._gain_stat(phil, "strength", 9)
	_check(duke.stat("strength") == 6 and toby.stat("strength") == 6, "no phantom copies from a capped stat")


func _decoy() -> void:
	var s := _make({"F0": "Stan Doubletake", "F1": "Midas Jr."} if players.has("Midas Jr.") else {"F0": "Stan Doubletake"})
	var rng := RandomNumberGenerator.new()
	rng.seed = 111
	s.offense_slot("F1").data = OddityPlayerDB.make_named(rng, "Midas Jr.")
	var stan := s.offense_slot("F0")
	var rec := s.offense_slot("F1")
	_far_defense(s)
	stan.pos = Vector2(s.los + 5, 40)
	rec.pos = Vector2(s.los + 5, 10)
	for i in [7, 8]:
		s.defense[i].pos = stan.pos + Vector2(0, -3)
		s.defense[i].role = SimPlayer.Role.MAN
		s.defense[i].mark = stan
		s.defense[i].reaction = 0
	s._throw(s.offense_slot("QB"), rec)
	s.ball_to = rec.pos
	var before := s.defense[7].pos.distance_to(stan.pos)
	s._step_defense(0.1)
	_check(s.defense[7].pos.distance_to(stan.pos) < before, "Stan's followers actually move toward him during another receiver's pass")
	_complete(s, rec, 5)
	_check(bool(rec.synergy.get("double_bucks", false)), "two actual followers enable Stan's payout")
	s._award(10, "Probe", rec)
	_check(s._pending_bucks >= 60, "Stan multiplies the existing Golden Touch earnings")
	s._end_play({"kind": "complete", "yards": 20.0, "text": "Whistle"})
	_check(s.result["bucks"] >= 160, "decoy multiplier also reaches end-of-play awards")
	var no_decoy := _make({"F0": "Stan Doubletake"})
	_far_defense(no_decoy)
	for d in no_decoy.defense:
		d.mark = no_decoy.offense_slot("F0")
		d.role = SimPlayer.Role.RUSH
	_complete(no_decoy, no_decoy.offense_slot("F1"))
	_check(not no_decoy.carrier.synergy.has("double_bucks"), "rushers do not count as decoy followers")


func _automatic() -> void:
	var s := _make({"C": "Otto Pilot", "F0": "Sigma Mogmen"}, false)
	s.set_drawn_call({})
	var sigma := s.offense_slot("F0")
	var agi := sigma.stat("agility")
	s.snap()
	_check(sigma.stat("intelligence") == sigma.data.intelligence + 2 and sigma.stat("agility") == agi + 4,
		"Otto supports the existing undrawn-route ability")
	var d := s.defense[7]
	d.mark = sigma
	d.role = SimPlayer.Role.MAN
	d.pos = sigma.pos
	d.next_contact = 0
	d.eff["strength"] = 15
	sigma.eff["strength"] = 1
	# A deterministic successful jam at the real contact owner.
	var probe := RandomNumberGenerator.new()
	for seed_value in 1000:
		probe.seed = seed_value
		if probe.randf() < 0.01:
			s.rng.seed = seed_value
			break
	for other in s.offense:
		other.engaged = false
	s.carrier = null
	s._step_contacts(0.01)
	_check(is_equal_approx(sigma.disrupted, 0.55), "Otto halves an actual successful coverage jam")
	_next(s, _routes())
	_check(not sigma.synergy.has("auto_supported") and sigma.stat("intelligence") == sigma.data.intelligence,
		"drawing a route removes Otto's automatic-route support")


func _check(ok: bool, text: String) -> void:
	print("[%s] %s" % ["ok" if ok else "FAIL", text])
	if not ok:
		failures += 1


func _lifecycle_edges() -> void:
	var s := _make({"F0": "Freshman Freddie", "C": "Conrad Clipboard"})
	_check(s.offense_slot("F0").stat("agility") == 5, "Freddie's opening start is not a bench entry")
	var starters: Array = []
	for sp in s.offense:
		starters.append(sp.data)
	var original: PlayerData = starters[6]
	starters[6] = _fresh("Lane Merge")
	s.resync_offense(starters)
	starters[6] = original
	s.resync_offense(starters)
	s.set_drawn_call(_routes())
	s.snap()
	_check(s.offense_slot("F0").stat("agility") == 5, "unsnapped substitution swaps cannot create a bench entry")
	var otto := _make({"C": "Otto Pilot"}, false)
	var kicker := PlayerData.new()
	kicker.pos = PlayerData.Pos.K
	otto.set_kicker(kicker)
	otto.set_kick_mode(true)
	otto.snap()
	_check(otto._drive_snapped.is_empty(), "a kick does not consume first offensive snaps")
	var sharing := _make({"QB": "Gus Everybody", "F0": "Al Firstman", "F1": "Benny Bookmark"})
	_far_defense(sharing)
	_complete(sharing, sharing.offense_slot("F0"))
	var catcher_count := sharing._drive_catchers.size()
	_next(sharing)
	sharing._throw(sharing.offense_slot("QB"), sharing.offense_slot("F1"))
	sharing.ball_to = Vector2(-100, -100)
	sharing._step_ball(sharing.ball_air_time + 0.1)
	_check(sharing._drive_catchers.size() == catcher_count, "incompletions do not advance catcher history")
	var clone_sim := _make({"QB": "Gus Everybody", "F0": "Mickey Mitosis"} if players.has("Mickey Mitosis") else {"QB": "Gus Everybody"}, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	clone_sim.offense_slot("F0").data = OddityPlayerDB.make_named(rng, "Mickey Mitosis")
	clone_sim.set_drawn_call(_routes())
	clone_sim.snap()
	_far_defense(clone_sim)
	var clone: SimPlayer = clone_sim.offense.back()
	var qb_dex := clone_sim.offense_slot("QB").stat("dexterity")
	_complete(clone_sim, clone_sim.offense_slot("F0"))
	# The other half uses the same real PlayerData identity.
	_complete(clone_sim, clone)
	_check(clone_sim.offense_slot("QB").stat("dexterity") == qb_dex + 1 and clone_sim._drive_catchers.size() == 1,
		"Mitosis halves count as one catcher")
	var saved := _make({"F0": "Potential Man", "F1": "Akira Momiji", "QB": "Gus Everybody"})
	_far_defense(saved)
	var target := saved.offense_slot("F0")
	target.pos = Vector2(MatchSim.GOAL_LINE + 1, 15)
	target.vel = Vector2.ZERO
	saved._throw(saved.offense_slot("QB"), target)
	saved.ball_to = target.pos
	saved._step_ball(saved.ball_air_time + 0.1)
	_check(saved.carrier == saved.offense_slot("F1") and saved._drive_last_receiver == saved.offense_slot("F1").data,
		"a saved drop credits the actual savior to drive synergies")
	var negated := _make({"T0": "Artie Asphalt"})
	var artie := negated.offense_slot("T0")
	artie.ability_negated = true
	artie.engaged = true
	artie.mark = negated.defense[0]
	negated._step_synergies(1.0)
	_check(negated.speed_patches.is_empty(), "negated support abilities cannot fire")


func _substitution_ui() -> void:
	GameState.new_run(99001)
	var original := GameState.player_at("F0")
	GameState.roster.append(_fresh("Chalk Norris"))
	GameState.set_route("F0", [Vector2(30, 0)])
	GameState.set_route("F1", [Vector2(35, 0)])
	var scene: Control = load("res://scenes/match.tscn").instantiate()
	add_child(scene)
	await scene.ready_to_play
	_check(_bar_has(scene, "30 / 30 yd"), "ordinary lineup shows the clipped 30-yard route")
	_check(_click_sub(scene, "Chalk Norris"), "Chalk is selectable through the real substitute button")
	await get_tree().process_frame
	await get_tree().process_frame
	var sim: MatchSim = scene.get("sim")
	_check(_bar_has(scene, "20 / 20 yd") and _bar_has(scene, "35 / 35 yd"),
		"substituting Chalk immediately refreshes his and his teammates' chalk captions")
	_check(RouteBook.route_length(sim.play["routes"][1]) == 35,
		"substitution changes the effective simulated route with its caption")
	_check(_click_sub(scene, original.pname), "original starter can replace Chalk through the real button")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_bar_has(scene, "30 / 30 yd") and not _bar_has(scene, "35 / 35 yd") and not _bar_has(scene, "20 / 20 yd"),
		"removing Chalk refreshes all captions back to ordinary budgets")
	_check(RouteBook.route_length(sim.play["routes"][1]) == 30 and RouteBook.route_length(GameState.route_for("F1")) == 35,
		"removing Chalk clips the effective call while preserving stored chalk")
	scene.queue_free()
	await get_tree().process_frame


func _bar_has(scene: Control, text: String) -> bool:
	for label in scene.get("bar_host").find_children("*", "Label", true, false):
		if label.text == text:
			return true
	return false


func _click_sub(scene: Control, player_name: String) -> bool:
	scene.call("_open_subs", "F0")
	for button in scene.get("side_panel").find_children("*", "Button", true, false):
		for label in button.find_children("*", "Label", true, false):
			if label.text.contains(player_name):
				button.pressed.emit()
				return true
	return false
