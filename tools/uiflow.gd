extends Node

## End-to-end exercise of the match screen through the same entry points the
## buttons call, so handler bugs surface without clicking through the game.
##   godot --path . res://tools/uiflow.tscn

var failures: Array[String] = []


func _ready() -> void:
	print("=== UI FLOW TEST ===")
	# The match scene advances the sim from _process in real time, so run the
	# engine clock fast rather than waiting out twenty plays at 1x.
	Engine.time_scale = 20.0
	GameState.new_run(99001)
	await _play_full_match()
	await _check_screen("post_match", "res://scenes/post_match.tscn")
	await _check_screen("hub", "res://scenes/hub.tscn")
	await _check_screen("lineup", "res://scenes/lineup.tscn")
	await _check_screen("playbook", "res://scenes/playbook.tscn")
	await _check_screen("shop", "res://scenes/shop.tscn")

	if failures.is_empty():
		print("\nALL CHECKS PASSED")
	else:
		print("\n%d FAILURES:" % failures.size())
		for f in failures:
			print("  - " + f)
	get_tree().quit()


func _fail(msg: String) -> void:
	failures.append(msg)
	print("  FAIL: " + msg)


func _play_full_match() -> void:
	var scene: Node = load("res://scenes/match.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame

	var sim: MatchSim = scene.get("sim")
	if sim == null:
		_fail("match scene did not build a sim")
		return

	var plays := 0
	var drives_played := 0
	var guard := 0

	while guard < 4000:
		guard += 1
		await get_tree().process_frame

		match sim.phase:
			MatchSim.Phase.PRESNAP:
				# Chalk a route up for a different receiver each snap, so the
				# draw -> apply -> snap path is what gets exercised.
				_chalk_a_route(sim, plays)
				scene.call("_apply_call", true)
				scene.call("_refresh_bar")
				scene.call("_on_snap")
				if sim.phase != MatchSim.Phase.LIVE:
					_fail("snap did not make the play live")
					return
				plays += 1

			MatchSim.Phase.LIVE:
				# _process advances the sim; just let frames tick.
				pass

			MatchSim.Phase.DEAD:
				if not sim.result.has("text"):
					_fail("dead play produced no result text")
				scene.call("_on_continue")

			MatchSim.Phase.DRIVE_OVER:
				drives_played += 1
				if sim.drive_num >= sim.total_drives:
					break
				# Exercise the substitution path once per match.
				if drives_played == 1:
					_try_substitution(scene, sim)
				sim.begin_drive()
				scene.call("_apply_call", true)
				scene.call("_refresh_bar")

	print("  played %d plays over %d drives, final %d-%d" % [
		plays, drives_played, sim.score_us, sim.score_them])

	if plays < 8:
		_fail("only %d plays ran; the match loop is stalling" % plays)
	if drives_played < sim.total_drives:
		_fail("only %d of %d drives completed" % [drives_played, sim.total_drives])

	var earned: int = scene.get("bucks_earned")
	if earned <= 0:
		_fail("no football bucks earned across a whole match")

	# Finish the match the way the final whistle button does, minus the
	# scene change (which would tear down this harness).
	var won := sim.won()
	GameState.last_result = {
		"won": won, "score_us": sim.score_us, "score_them": sim.score_them,
		"opponent": sim.opponent_name, "bucks": earned, "round": GameState.round_label(),
	}
	GameState.add_bucks(earned)
	GameState.finish_match(won)
	print("  result: %s, bucks now $%d, round_index=%d" % [
		"WIN" if won else "LOSS", GameState.bucks, GameState.round_index])

	scene.queue_free()
	await get_tree().process_frame


func _try_substitution(scene: Node, sim: MatchSim) -> void:
	# Same entry points the field clicks hit.
	var clicked: SimPlayer = sim.offense_slot("F4")
	scene.call("_on_player_clicked", clicked)
	if not bool(scene.get("card").visible):
		_fail("clicking a player did not raise the info card")
	scene.call("_open_subs", "F4")
	if not bool(scene.get("side_panel").visible):
		_fail("substitute action did not open the side panel")
	scene.call("_dismiss_overlays")
	if bool(scene.get("card").visible) or bool(scene.get("side_panel").visible):
		_fail("overlays did not dismiss")
	var bench := -1
	for i in GameState.roster.size():
		if not GameState.is_starting(i) and GameState.fits_slot(i, "F4"):
			bench = i
			break
	if bench < 0:
		return
	var before: PlayerData = GameState.player_at("F4")
	if not GameState.set_slot("F4", bench):
		_fail("set_slot rejected a bench player that fits F4")
		return
	var after: PlayerData = GameState.player_at("F4")
	if after == before:
		_fail("substitution did not change the F4 starter")
	sim.resync_offense(GameState.starters())
	var f4 := sim.offense_slot("F4")
	if f4 == null or f4.data != after:
		_fail("resync_offense did not pick up the substitution")
	else:
		print("  substitution ok: F4 is now %s" % after.pname)


func _check_screen(tag: String, path: String) -> void:
	var scene: Node = load(path).instantiate()
	add_child(scene)
	for i in 4:
		await get_tree().process_frame
	if scene.get_child_count() == 0:
		_fail("%s built no UI" % tag)
	else:
		print("  %s ok (%d root children)" % [tag, scene.get_child_count()])
	scene.queue_free()
	await get_tree().process_frame


## Draws a plausible route for one flex, straight into GameState the way the
## field view does when the coach finishes a stroke.
func _chalk_a_route(sim: MatchSim, n: int) -> void:
	var flexes := sim.flex_players()
	if flexes.is_empty():
		return
	var f: SimPlayer = flexes[n % flexes.size()]
	var ids: Array = RouteBook.STOCK.keys()
	var spot := Vector2(f.target_pos.x - sim.los, f.target_pos.y - MatchSim.FIELD_W * 0.5)
	GameState.set_route(f.slot, RouteBook.route_for_spot(String(ids[n % ids.size()]), spot))
