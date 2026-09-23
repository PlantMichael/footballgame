extends Node

## Loads every screen in turn and writes a PNG of each so the UI can be
## eyeballed without clicking through the game by hand.
##   godot --path . res://tools/uishot.tscn
## (Must run with a real renderer; --headless produces blank images.)

const OUT_DIR := "user://shots"
const SCREENS := [
	["main_menu", "res://scenes/main_menu.tscn"],
	["hub", "res://scenes/hub.tscn"],
	["lineup", "res://scenes/lineup.tscn"],
	["playbook", "res://scenes/playbook.tscn"],
	["shop", "res://scenes/shop.tscn"],
	["post_match", "res://scenes/post_match.tscn"],
]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	GameState.new_run(20260817)
	GameState.last_result = {
		"won": true, "score_us": 24, "score_them": 17,
		"opponent": "Duluth Bison", "bucks": 470, "round": "Divisional",
	}
	print("shots -> %s" % ProjectSettings.globalize_path(OUT_DIR))

	for entry in SCREENS:
		await _shoot(String(entry[0]), String(entry[1]))

	await _shoot_match()
	print("done")
	get_tree().quit()


func _shoot(tag: String, path: String) -> void:
	var scene: PackedScene = load(path)
	var inst: Node = scene.instantiate()
	add_child(inst)
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save(tag)
	inst.queue_free()
	await get_tree().process_frame


## The match screen needs a few extra steps to show a play in progress.
func _shoot_match() -> void:
	var inst: Node = load("res://scenes/match.tscn").instantiate()
	add_child(inst)
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save("match_playcall")

	var sim: MatchSim = inst.get("sim")

	# Click a receiver to raise the inspect card, then open the sub list.
	var target: SimPlayer = sim.offense_slot("F1")
	inst.call("_on_player_clicked", target)
	for i in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save("match_card")

	inst.call("_open_subs", "F1")
	for i in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save("match_subs")

	inst.call("_dismiss_overlays")
	for i in 3:
		await get_tree().process_frame

	# Chalk a fresh route up and grab the formation part way through its shift.
	var flexes := sim.flex_players()
	var f: SimPlayer = flexes[0]
	var spot := Vector2(f.target_pos.x - sim.los, f.target_pos.y - MatchSim.FIELD_W * 0.5)
	GameState.set_route(f.slot, RouteBook.route_for_spot("corner", spot))
	inst.call("_apply_call", false)
	inst.call("_refresh_bar")
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save("match_shift")

	# The route-concept overlay, reachable from the chalkboard.
	inst.call("_open_examples")
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save("match_examples")
	inst.call("_dismiss_overlays")
	for i in 3:
		await get_tree().process_frame

	# Let it settle before snapping.
	for i in 40:
		await get_tree().process_frame

	sim.snap()
	for i in 90:
		sim.step(1.0 / 60.0)
		if sim.phase != MatchSim.Phase.LIVE:
			break
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save("match_live")

	# Let the play finish so the result panel renders.
	var guard := 0
	while sim.phase == MatchSim.Phase.LIVE and guard < 2000:
		sim.step(1.0 / 60.0)
		guard += 1

	# Keep running plays until one actually ends in a tackle, so the topple
	# animation is what gets captured.
	var tries := 0
	while tries < 20 and not _was_tackled(sim):
		tries += 1
		sim.advance()
		if sim.phase != MatchSim.Phase.PRESNAP:
			sim.begin_drive()
		sim.set_drawn_call(GameState.drawn_routes)
		sim.snap()
		var g2 := 0
		while sim.phase == MatchSim.Phase.LIVE and g2 < 2000:
			sim.step(1.0 / 60.0)
			g2 += 1
	inst.call("_refresh_bar")

	# The fall animation is driven by the renderer, so let real frames elapse.
	for i in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save("match_result")

	# Knock down the isolated wide receivers so the topple pose can be seen
	# without a pile of bodies on top of it.
	for slot in ["F0", "F3", "T0", "T3"]:
		var sp: SimPlayer = sim.offense_slot(slot)
		if sp != null:
			sp.vel = Vector2(2.0, 0.4)
			sp.downed = 0.0001
	for d in sim.defense:
		d.vel = Vector2(-1.5, 0.3)
		d.downed = 0.0001
	for i in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save("match_downed")

	await _shoot_upgrade_flow(inst, sim)
	inst.queue_free()


## Forces a touchdown result and walks through the per-game upgrade overlay
## (choice, then recipient picker) so both states can be eyeballed.
func _shoot_upgrade_flow(inst: Node, sim: MatchSim) -> void:
	sim.result = {
		"td": true, "yards": 5.0, "turnover": false,
		"text": "TOUCHDOWN, Test Player!", "bucks": 100, "events": [],
	}
	sim.phase = MatchSim.Phase.DEAD
	inst.call("_refresh_bar")
	for i in 3:
		await get_tree().process_frame
	inst.call("_on_continue")
	for i in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save("match_upgrade_choice")

	var pending: Array = inst.get("pending_upgrades")
	if pending.is_empty():
		print("  ERR match_upgrade_choice: pending_upgrades was empty")
		return

	var target: PlayerData = pending[0]["player"]
	inst.call("_apply_upgrade", target, pending[0])
	for i in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save("match_upgrade_applied")


func _was_tackled(sim: MatchSim) -> bool:
	var kind := String(sim.result.get("kind", ""))
	return kind in ["run", "complete", "sack", "touchdown"]


func _save(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, tag]
	var err := img.save_png(path)
	print("  %s  %s (%dx%d)" % [
		"ok " if err == OK else "ERR", tag, img.get_width(), img.get_height()])
