extends Node

## Presentation state plus the real FieldView clock/pause boundary.
## godot --headless --path . res://tools/sideline_check.tscn
var failures := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.new_run(99001)
	var screen: Node = load("res://scenes/match.tscn").instantiate()
	screen.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(screen)
	await screen.ready_to_play
	screen.set_process(false)
	var sim: MatchSim = screen.sim
	var field = screen.field
	var crowd: SidelineCrowd = field.sidelines
	field.set_process(false)
	_check(crowd.people.size() >= 180 and crowd.officials.size() == 2 and crowd.props.size() >= 50,
		"crowd, refs and props are ready before the match is revealed")
	var body_count := crowd._textures.size()
	var head_count := crowd._heads.size()
	_check(body_count > 0 and head_count > 0, "sideline sprites are warmed before reveal")
	_check(crowd.warm_resources(sim) and crowd._textures.size() == body_count and crowd._heads.size() == head_count,
		"turns and reactions need no additional sideline sprite loads")
	crowd.advance(sim, 0.016)
	_check(crowd.people.size() >= 180 and crowd.officials.size() == 2, "denser sidelines and two officials")
	_check(crowd.props.size() >= 50, "bench and equipment stations populate both sidelines")
	var lateral_positions := {}
	var moving: Dictionary = {}
	for actor in crowd.people:
		lateral_positions[snappedf(actor.home.y, 0.1)] = true
		if actor.activity == "pace":
			moving = actor
		if actor.activity != "rest":
			for prop in crowd.props:
				var footprint: Vector2 = SidelineCrowd.PROP_SIZES[prop.kind]
				_check(not Rect2(prop.pos - footprint * 0.5, footprint).has_point(actor.home), "standing groups leave furniture space")
	_check(lateral_positions.size() > 40, "crowd is scattered across sideline depth rather than straight rows")
	_check(not moving.is_empty(), "sideline includes pacing NPCs")
	if not moving.is_empty():
		var start: Vector2 = moving.pos
		crowd.advance(sim, 1.0)
		_check(moving.pos != start and moving.pos.distance_to(moving.home) < 0.5, "ambient pacing moves within a bounded personal space")
	_walking_lanes(crowd, sim)
	_staggered_reactions(crowd, sim)
	_replacement_reaction(crowd, sim)
	for actor in crowd.people + crowd.officials:
		var pos: Vector2 = actor.pos
		_check(pos.y < 0.0 or pos.y > MatchSim.FIELD_W, "ambient actors stay outside the playing field")
	for prop in crowd.props:
		var footprint: Vector2 = SidelineCrowd.PROP_SIZES[prop.kind]
		_check(prop.pos.y + footprint.y * 0.5 < -2.0 or prop.pos.y - footprint.y * 0.5 > MatchSim.FIELD_W + 2.0,
			"decorations keep the field and officials' lane clear")
	sim.defense_jersey = "red"
	_check(crowd.team_palette(true, sim) == "blue" and crowd.team_palette(false, sim) == "red", "red opponent jersey palette")
	sim.defense_jersey = "green"
	_check(crowd.team_palette(false, sim) == "green", "palette follows a changed opponent")
	var rng_before := sim.rng.state
	var ball_before := sim.ball_pos
	var player_before := sim.offense[0].pos
	var time_before := sim.time
	var run_rng_before := GameState.rng.state
	crowd.reset(sim)
	for i in 10:
		crowd.advance(sim, 0.016)
	_check(sim.rng.state == rng_before and GameState.rng.state == run_rng_before and sim.ball_pos == ball_before and sim.time == time_before
		and sim.offense[0].pos == player_before and sim.offense.size() == 11 and sim.defense.size() == 11,
		"sideline updates preserve gameplay state and seeded RNG")
	sim.snap()
	crowd.advance(sim, 0.016)
	var ref_before: Vector2 = crowd.officials[0].pos
	sim.ball_pos.x = ref_before.x + 30.0
	crowd.advance(sim, 0.1)
	var ref_after: Vector2 = crowd.officials[0].pos
	_check(ref_after.x > ref_before.x and ref_after.x - ref_before.x <= 1.101 and ref_after.y == ref_before.y,
		"ref follows the play at bounded speed along its sideline")
	# Possession can change entirely between renderer frames at 4x speed.
	sim.carrier = sim.offense[6]
	sim.carrier.pos.x = sim.los + 2.0
	sim.handoff_done = false
	crowd.advance(sim, 0.016)
	_check(crowd.offense_mode == "clap" and crowd.defense_mode == "tense", "catch reacts without observing the pass in flight")
	sim.carrier.pos.x = sim.los + sim.to_go + 1.0
	crowd.advance(sim, 0.016)
	_check(crowd.offense_mode == "cheer", "big gain gets a live celebration")
	_result(crowd, sim, {"kind":"touchdown", "td":true, "yards":25.0}, "cheer", "groan", "touchdown")
	_result(crowd, sim, {"kind":"touchdown", "td":true, "yards":25.0}, "cheer", "groan", "touchdown")
	_result(crowd, sim, {"kind":"interception", "turnover":true, "yards":0.0}, "groan", "cheer", "turnover")
	_result(crowd, sim, {"kind":"sack", "yards":-3.0}, "groan", "cheer", "stop")
	_result(crowd, sim, {"kind":"incomplete", "yards":0.0}, "groan", "clap", "incomplete")
	sim.down = 4
	_result(crowd, sim, {"kind":"incomplete", "yards":0.0}, "groan", "cheer", "incomplete")
	_result(crowd, sim, {"kind":"run", "yards":2.0}, "groan", "cheer", "turnover")
	sim.down = 1
	_result(crowd, sim, {"kind":"complete", "yards":sim.to_go}, "cheer", "groan", "first_down")
	_result(crowd, sim, {"kind":"field_goal", "kick":true, "fg_good":true, "yards":0.0}, "cheer", "groan", "touchdown")
	_result(crowd, sim, {"kind":"missed_fg", "kick":true, "fg_good":false, "yards":0.0}, "groan", "cheer", "no_good")
	crowd.advance(sim, 3.0)
	_check(crowd.offense_mode == "idle" and crowd.ref_signal.is_empty(), "shared event and official signal settle after the result")
	sim.phase = MatchSim.Phase.DRIVE_OVER
	crowd.advance(sim, 0.016)
	_check(crowd.offense_mode == "idle", "drive transition does not replay the same result")
	_fourth_down_spot(crowd, sim, 8.0)
	_fourth_down_spot(crowd, sim, -3.0)
	crowd.advance(sim, 0.016, {true:"jump", false:"lie"})
	crowd.advance(sim, 4.0, {true:"jump", false:"lie"})
	_check(crowd.offense_mode == "cheer" and crowd.defense_mode == "groan", "final team reactions persist")
	var other := MatchSim.new()
	other.los = 80.0
	crowd.advance(other, 0.016)
	_check(crowd.offense_mode == "idle" and crowd.officials[0].pos.x > 70.0, "a replacement match resets presentation")
	# Restore the real owner and prove its visual clock freezes in a paused tree.
	field.set_process(true)
	await get_tree().process_frame
	var clock_before := crowd.clock
	var people_before: Array = crowd.people.map(func(actor): return actor.pos)
	var refs_before: Array = crowd.officials.map(func(actor): return actor.pos)
	get_tree().paused = true
	await get_tree().create_timer(0.1).timeout
	_check(crowd.clock == clock_before, "pause freezes NPC animation and official motion")
	_check(crowd.people.map(func(actor): return actor.pos) == people_before
		and crowd.officials.map(func(actor): return actor.pos) == refs_before, "pause freezes ambient pacing and referees")
	get_tree().paused = false
	await get_tree().process_frame
	await get_tree().process_frame
	_check(crowd.clock > clock_before, "NPC animation resumes with the game")
	screen.queue_free()
	print("SIDELINE CHECK: %s" % ("ALL CHECKS PASSED" if failures == 0 else "%d FAILURES" % failures))
	get_tree().quit(1 if failures else 0)

func _fourth_down_spot(crowd: SidelineCrowd, sim: MatchSim, yards: float) -> void:
	sim.phase = MatchSim.Phase.PRESNAP
	crowd.advance(sim, 0.016)
	sim.los = 40.0
	sim.to_go = 10.0
	sim.down = 4
	sim.phase = MatchSim.Phase.LIVE
	sim.carrier.pos.x = sim.los + yards
	sim.ball_pos = sim.carrier.pos
	sim.call("_end_play", {"kind":"run", "yards":yards, "text":"Fourth-down spot fixture."})
	crowd.advance(sim, 10.0)
	var dead_spot: Vector2 = crowd.officials[0].pos
	_check(is_equal_approx(dead_spot.x, 40.0 + yards), "official reaches the dead-ball spot")
	var outcome := sim.advance()
	_check(outcome.drive_over and sim.phase == MatchSim.Phase.DRIVE_OVER, "real advance ends a failed fourth down")
	crowd.advance(sim, 1.0)
	for official in crowd.officials:
		_check(is_equal_approx(official.pos.x, dead_spot.x), "official holds the same spot after fourth-down advance (%s yd)" % yards)

func _walking_lanes(crowd: SidelineCrowd, sim: MatchSim) -> void:
	var walkers: Array = crowd.people.filter(func(actor): return actor.activity == "walk")
	_check(walkers.filter(func(actor): return actor.offense).size() >= 4
		and walkers.filter(func(actor): return not actor.offense).size() >= 4,
		"both sidelines have several genuine walkers")
	if walkers.is_empty():
		return
	var observed := {}
	var minimum: float = walkers[0].pos.x
	var maximum := minimum
	for i in 160:
		var before: Array = walkers.map(func(actor): return actor.pos)
		crowd.advance(sim, 0.25)
		for j in walkers.size():
			var actor: Dictionary = walkers[j]
			_check(actor.pos.distance_to(before[j]) <= 0.326, "walkers move at walking speed without teleporting")
			_check(absf(actor.pos.y - actor.home.y) < 0.001, "walking lane stays separate from the field and officials")
			for prop in crowd.props:
				var footprint: Vector2 = SidelineCrowd.PROP_SIZES[prop.kind]
				_check(not Rect2(prop.pos - footprint * 0.5, footprint).grow(0.65).has_point(actor.pos), "walking route clears sideline furniture")
		minimum = minf(minimum, walkers[0].pos.x)
		maximum = maxf(maximum, walkers[0].pos.x)
		observed[signf(float(walkers[0].velocity))] = true
	_check(maximum - minimum > 8.0, "walkers cover a visible stretch rather than shuffling in place")
	_check(observed.has(-1.0) and observed.has(0.0) and observed.has(1.0), "walkers turn around and pause at both ends")
	sim.phase = MatchSim.Phase.DEAD
	sim.result = {"kind":"touchdown", "td":true, "yards":25.0}
	crowd.advance(sim, 0.01)
	crowd.advance(sim, 0.5)
	var stopped: Array = walkers.map(func(actor): return actor.pos)
	crowd.advance(sim, 0.3)
	_check(walkers.map(func(actor): return actor.pos) == stopped, "walkers stop in place for a game reaction")
	sim.phase = MatchSim.Phase.PRESNAP
	sim.result = {}
	var traveled := PackedFloat32Array()
	traveled.resize(walkers.size())
	for i in 40:
		var before: Array = walkers.map(func(actor): return actor.pos)
		crowd.advance(sim, 0.25)
		for j in walkers.size():
			var step: float = walkers[j].pos.distance_to(before[j])
			_check(step <= 0.326, "walking resumes from the stopped position without jumping")
			traveled[j] += step
	for distance in traveled:
		_check(distance > 3.0, "each walker continues traveling after the reaction and any endpoint pause")

func _staggered_reactions(crowd: SidelineCrowd, sim: MatchSim) -> void:
	var sim_rng_before := sim.rng.state
	var run_rng_before := GameState.rng.state
	var first_finishes: Array = []
	for wave in 2:
		sim.phase = MatchSim.Phase.PRESNAP
		sim.result = {}
		crowd.advance(sim, 0.016)
		sim.phase = MatchSim.Phase.DEAD
		sim.result = {"kind":"touchdown", "td":true, "yards":25.0}
		crowd.advance(sim, 0.016)
		crowd.advance(sim, 0.8)
		_check(crowd.people.all(func(actor): return crowd.call("_reaction_weight", actor) > 0.0), "the crowd joins the score reaction")
		# Starting the next play must not force everybody back to ambient at once.
		sim.phase = MatchSim.Phase.PRESNAP
		sim.result = {}
		crowd.advance(sim, 0.016)
		_check(crowd.people.all(func(actor): return crowd.call("_reaction_weight", actor) > 0.0), "personal reactions survive the shared next-play reset")
		var finishes := {}
		var mixed := false
		var eased := false
		for step in 110:
			crowd.advance(sim, 0.05)
			var active := 0
			for i in crowd.people.size():
				var weight: float = crowd.call("_reaction_weight", crowd.people[i])
				if weight > 0.0:
					active += 1
					eased = eased or weight < 1.0
				elif not finishes.has(i):
					finishes[i] = step
			mixed = mixed or (active > 0 and active < crowd.people.size())
		_check(mixed and eased, "some NPCs settle smoothly while others keep reacting")
		_check(finishes.size() == crowd.people.size(), "all personal reactions eventually return to ambient")
		if finishes.size() != crowd.people.size():
			continue
		var times := range(crowd.people.size()).map(func(i): return finishes[i])
		_check(times.max() - times.min() > 10, "reaction endings are spread across the crowd rather than one frame")
		if wave == 0:
			first_finishes = times
		else:
			_check(times != first_finishes, "each new event varies who settles first")
	_check(sim.rng.state == sim_rng_before and GameState.rng.state == run_rng_before,
		"random reaction timing preserves simulation and run RNG")

func _replacement_reaction(crowd: SidelineCrowd, sim: MatchSim) -> void:
	_result(crowd, sim, {"kind":"touchdown", "td":true, "yards":25.0}, "cheer", "groan", "touchdown")
	crowd.advance(sim, 0.7)
	_check(crowd.people.all(func(actor): return crowd.call("_reaction_weight", actor) > 0.0), "replacement starts with an active crowd")
	sim.phase = MatchSim.Phase.PRESNAP
	sim.result = {}
	crowd.advance(sim, 0.016)
	sim.snap()
	sim.carrier = sim.offense[6]
	sim.handoff_done = false
	var sim_rng_before := sim.rng.state
	var weights: Array = crowd.people.map(func(actor): return crowd.call("_reaction_weight", actor))
	crowd.advance(sim, 0.016)
	_check(crowd.offense_mode == "clap", "a real new-play catch refreshes the crowd reaction")
	_check(crowd.people.all(func(actor): return crowd.call("_reaction_weight", actor) > 0.0),
		"a replacement event never drops the active crowd collectively to ambient")
	_check(range(crowd.people.size()).all(func(i): return crowd.call("_reaction_weight", crowd.people[i]) >= weights[i] - 0.001),
		"refreshing an active event preserves each NPC's gesture strength")
	_check(sim.rng.state == sim_rng_before, "refreshing an active reaction preserves simulation RNG")

func _result(crowd: SidelineCrowd, sim: MatchSim, result: Dictionary, ours: String, theirs: String, signal_name: String) -> void:
	sim.phase = MatchSim.Phase.PRESNAP
	sim.result = {}
	crowd.advance(sim, 0.016)
	_check(crowd.offense_mode == "idle" and crowd.ref_signal.is_empty(), "next play clears the shared event and official signal")
	sim.phase = MatchSim.Phase.DEAD
	sim.result = result
	crowd.advance(sim, 0.016)
	_check(crowd.offense_mode == ours and crowd.defense_mode == theirs and crowd.ref_signal == signal_name,
		"team reactions and official signal: %s (down %d)" % [result.kind, sim.down])
	var left := crowd.reaction_left
	crowd.advance(sim, 0.1)
	_check(crowd.reaction_left < left, "result is consumed once")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
