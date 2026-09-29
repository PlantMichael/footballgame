extends Node

## Captures the floating-hand poses (block, reach, catch, touchdown high
## five, final-whistle win) as zoomed crops so they can be eyeballed.
##   godot --path . res://tools/handshot.tscn
## (Needs a real renderer; --headless produces blank images.)

const OUT_DIR := "user://shots/hands"
var inst: Node
var sim: MatchSim
var field: Control


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	GameState.new_run(20260817)
	print("shots -> %s" % ProjectSettings.globalize_path(OUT_DIR))
	inst = load("res://scenes/match.tscn").instantiate()
	add_child(inst)
	for i in 10:
		await get_tree().process_frame
	sim = inst.get("sim")
	field = inst.get("field")
	field.set("_zoom", 2.0)
	# Optional: force the opponent's jersey, e.g. JERSEY=red.
	if OS.get_environment("JERSEY") != "":
		sim.defense_jersey = OS.get_environment("JERSEY")

	var got := {}
	for attempt in 12:
		if got.has("block") and got.has("reach") and got.has("catch"):
			break
		for i in 30:
			await get_tree().process_frame
		sim.snap()
		var was_air := false
		var guard := 0
		while sim.phase == MatchSim.Phase.LIVE and guard < 900:
			guard += 1
			await get_tree().process_frame
			if not got.has("block") and sim.time > 0.6:
				for b in sim.offense:
					if b.engaged and b.mark != null:
						await _shot("block", b.pos)
						got["block"] = true
						break
			if not got.has("block_late") and sim.time > 1.8:
				for b in sim.offense:
					if b.engaged and b.mark != null:
						await _shot("block_late", b.pos)
						got["block_late"] = true
						break
			if sim.ball_in_air and sim.thrown_to != null and not got.has("reach") \
					and sim.ball_t / sim.ball_air_time > 0.8 \
					and Rect2(Vector2(0, 90), field.size - Vector2(0, 180)).has_point(field.call("to_px", sim.thrown_to.pos)):
				await _shot("reach", sim.thrown_to.pos, 200)
				got["reach"] = true
			if was_air and not sim.ball_in_air and sim.carrier != null and not got.has("catch"):
				await get_tree().process_frame
				await _shot("catch", sim.carrier.pos)
				got["catch"] = true
			was_air = sim.ball_in_air
		for i in 5:
			await get_tree().process_frame
		sim.advance()
		if sim.phase != MatchSim.Phase.PRESNAP:
			sim.begin_drive()
		inst.call("_refresh_bar")
	print("got: ", got.keys())

	# Touchdown celebration: fake a scoring play ending next to a teammate.
	for i in 30:
		await get_tree().process_frame
	sim.snap()
	for i in 20:
		await get_tree().process_frame
	var scorer: SimPlayer = sim.offense_slot("F1")
	var mate: SimPlayer = sim.offense_slot("F2")
	for sp in sim.offense + sim.defense:
		sp.vel = Vector2.ZERO
		sp.downed = 0.0
	scorer.pos = Vector2(sim.los + 8.0, 26.0)
	mate.pos = scorer.pos + Vector2(0.6, 2.2)
	sim.carrier = scorer
	sim.ball_in_air = false
	sim.result = {"td": true, "kind": "touchdown", "yards": 5.0, "turnover": false,
		"text": "TOUCHDOWN!", "bucks": 100, "events": []}
	sim.phase = MatchSim.Phase.DEAD
	var mid := (scorer.pos + mate.pos) * 0.5
	await _wait(0.2)
	await _shot("td_cheer", mid)
	await _wait(0.2)
	await _shot("td_reach", mid)
	await _wait(0.18)
	await _shot("td_slap", mid)
	await _wait(0.6)
	await _shot("td_after", mid)

	sim.phase = MatchSim.Phase.DRIVE_OVER
	field.call("set_end_pose", "jump", "lie")
	await _wait(0.5)
	await _shot("win_jump", mid, 240, true)
	print("done")
	get_tree().quit()


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shot(tag: String, at_yards: Vector2, half: int = 170, whole: bool = false) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var c: Vector2 = field.get_global_rect().position + field.call("to_px", at_yards)
	var rect := Rect2i(Vector2i(c) - Vector2i(half, half), Vector2i(half * 2, half * 2))
	rect = rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img if whole else img.get_region(rect)
	crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/%s.png" % [OUT_DIR, tag])
	print("  ", tag)
