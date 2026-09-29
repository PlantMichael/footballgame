extends Node

## Captures the after-the-whistle animations over time - getting up off a
## tackle, gestures, walking back, then walking onto the next play's spots -
## as a strip of frames per play, so they can be eyeballed.
##   godot --path . res://tools/aftershot.tscn
## (Needs a real renderer; --headless produces blank images.)

const OUT_DIR := "user://shots/after"
## Seconds after the whistle to grab a frame at, then after the next call.
const DEAD_TIMES := [0.15, 1.1, 1.6, 2.4, 3.6]
const PRESNAP_TIMES := [0.25, 0.8]
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

	var want := {"tackle": true, "incomplete": true}
	for attempt in 16:
		if want.is_empty():
			break
		await _wait(0.6)
		sim.snap()
		while sim.phase == MatchSim.Phase.LIVE:
			await get_tree().process_frame
		var kind := String(sim.result.get("kind", ""))
		var tag := ""
		if want.has("tackle") and sim.tackler != null and (kind == "run" or kind == "complete"):
			tag = "tackle"
		elif want.has("incomplete") and kind == "incomplete":
			tag = "incomplete"
		if tag == "":
			inst.call("_on_continue")
			if sim.phase != MatchSim.Phase.PRESNAP:
				sim.begin_drive()
				inst.call("_apply_call")
			continue
		want.erase(tag)
		print("%s: %s" % [tag, sim.result.get("text", "")])
		var t := 0.0
		for i in DEAD_TIMES.size():
			await _wait(float(DEAD_TIMES[i]) - t)
			t = DEAD_TIMES[i]
			await _shot("%s_%d" % [tag, i])
		inst.call("_on_continue")
		if sim.phase != MatchSim.Phase.PRESNAP:
			sim.begin_drive()
			inst.call("_apply_call")
		t = 0.0
		for i in PRESNAP_TIMES.size():
			await _wait(float(PRESNAP_TIMES[i]) - t)
			t = PRESNAP_TIMES[i]
			await _shot("%s_next_%d" % [tag, i])
	print("done")
	get_tree().quit()


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, tag])
	print("  ", tag)
