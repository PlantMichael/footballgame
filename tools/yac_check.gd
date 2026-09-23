extends Node

## Verifies the post-catch behaviour: a receiver who catches the ball should
## keep running the waypoints the coach drew for him, skipping any that would
## take him backward, and only then convert to an ordinary ball carrier.
##
##   godot --headless --path . res://tools/yac_check.tscn

const DT := 1.0 / 120.0
const MATCHES := 6
## 0.2s at the sim's substep rate. Long enough for his velocity to have
## actually turned (the accel lerp settles in ~0.12s), short enough that he
## cannot yet have REACHED the waypoint and moved on to carry logic - which
## a longer window conflates with having ignored the route in the first place.
const SAMPLE_FRAMES := 24


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	var catches := 0
	var with_route_left := 0
	var all_backward := 0
	var followed := 0
	var wrong_way := 0
	var ambiguous := 0
	var wrong_dist: Array = []
	var tackled_at_once := 0
	var yac_on_route := 0.0

	for m in MATCHES:
		GameState.rng.seed = rng.randi()
		GameState.new_run(rng.randi())
		GameState.roster.assign(Generator.starting_roster(GameState.rng, 6.0))
		GameState.auto_fill_lineup()

		var opp: Dictionary = GameState.bracket[0]
		var sim := MatchSim.new()
		sim.setup(GameState.starters(),
			Generator.make_defense(GameState.rng, 3.0),
			3.0, "Test", 5)
		sim.start_match()

		var guard := 0
		while guard < 300:
			guard += 1
			if sim.phase == MatchSim.Phase.DRIVE_OVER:
				if sim.drive_num >= sim.total_drives:
					break
				sim.begin_drive()
				continue
			if sim.phase != MatchSim.Phase.PRESNAP:
				continue

			_chalk(sim)
			sim.set_drawn_call(GameState.drawn_routes)
			sim.snap()

			var seen_catch := false
			var at_catch := Vector2.ZERO
			var target := Vector2.ZERO
			var had_left := false
			var catch_frame := 0
			var sampled := false
			var sample_pos := Vector2.ZERO
			var sample_vel := Vector2.ZERO
			var live := 0
			while sim.phase == MatchSim.Phase.LIVE and live < 3000:
				sim.step(DT)
				live += 1
				var c := sim.carrier

				# Look only at the first stretch after the catch. Measuring to
				# the end of the play blends in the upfield running he does
				# once the route IS used up, which is not what is under test.
				if seen_catch:
					if not sampled and c != null:
						sample_pos = c.pos
						sample_vel = c.vel
						if live - catch_frame >= SAMPLE_FRAMES:
							sampled = true
					continue

				if c == null or c.slot == "QB" or not c.slot.begins_with("F"):
					continue
				# First frame this receiver has the ball.
				seen_catch = true
				catch_frame = live
				catches += 1
				at_catch = c.pos
				sample_pos = c.pos
				if c.route.size() - c.route_idx > 0:
					with_route_left += 1
					# Is anything left actually downfield of him?
					var fwd := -1
					for i in range(c.route_idx, c.route.size()):
						if c.route[i].x > c.pos.x + 0.5:
							fwd = i
							break
					if fwd < 0:
						all_backward += 1
					else:
						had_left = true
						target = c.route[fwd]

			if had_left:
				# Did he head for the waypoint, or just turn straight upfield?
				var wanted := (target - at_catch).normalized()
				var went := sample_pos - at_catch
				if went.length() > 0.5 and sample_vel.length() > 0.5:
					var heading := sample_vel.normalized()
					var straight_up := heading.x
					if heading.dot(wanted) > 0.7:
						followed += 1
					elif straight_up > 0.9 and absf(wanted.y) > 0.3:
						wrong_way += 1
						wrong_dist.append(at_catch.distance_to(target))
					else:
						ambiguous += 1
					yac_on_route += went.length()
				else:
					tackled_at_once += 1

			sim.advance()

	print("=== POST-CATCH ROUTE CHECK ===")
	print("  catches by a flex          %d" % catches)
	print("  had waypoints left         %d" % with_route_left)
	print("    ...all of them backward  %d  (skipped, straight to carry logic)" % all_backward)
	print("  with a forward waypoint    %d" % (followed + wrong_way + ambiguous + tackled_at_once))
	print("    followed the drawn line  %d" % followed)
	print("    turned straight upfield  %d" % wrong_way)
	if not wrong_dist.is_empty():
		var lo := 999.0
		var hi := 0.0
		for d in wrong_dist:
			lo = minf(lo, d)
			hi = maxf(hi, d)
		print("      (waypoint was %.1f-%.1f yd away)" % [lo, hi])
	print("    in between               %d" % ambiguous)
	print("    tackled on the spot      %d" % tackled_at_once)
	var moved := followed + wrong_way + ambiguous
	if moved > 0:
		print("  (judged on heading at the sample point, not net displacement)")
		print("  avg yards in first %.1fs   %.1f" % [
			float(SAMPLE_FRAMES) * DT, yac_on_route / float(moved)])
	get_tree().quit()


## A board with deliberate shape: two crossers that keep working across the
## field after the catch, and a curl whose last waypoint runs backward.
func _chalk(sim: MatchSim) -> void:
	GameState.clear_routes()
	var shapes := ["drag", "curl", "dig", "post", "flat"]
	var flexes := sim.flex_players()
	var spots := RouteBook.formation_for(flexes)
	for i in flexes.size():
		GameState.set_route(flexes[i].slot,
			RouteBook.route_for_spot(shapes[i % shapes.size()], spots[i]))
