extends Node

## Captures the after-play gestures (facepalm, shrug, wave-off, fist pump) and
## the tackle dust puff as zoomed crops.
##   godot --path . res://tools/gestureshot.tscn

const OUT_DIR := "user://shots/gestures"
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
	field.set("_zoom", 3.0)

	var rec: SimPlayer = sim.offense_slot("F1")
	var qb: SimPlayer = sim.offense_slot("QB")
	var cb: SimPlayer = sim.defense[sim.defense.size() - 1]

	# A drop: receiver facepalms, the nearest defender waves it off.
	await _stage(rec, cb, {"kind": "incomplete", "drop": true})
	await _wait(0.45)
	await _shot("facepalm", rec.pos + Vector2(0.0, 1.0))
	await _wait(0.3)
	await _shot("facepalm_late", rec.pos + Vector2(0.0, 1.0))

	# The other drop reactions, forced so each one gets a shot.
	for how in ["weep", "stomp"]:
		await _stage(rec, cb, {"kind": "incomplete", "drop": true})
		await _wait(0.05)
		field.call("_gesture", rec, how)
		await _wait(0.5)
		await _shot(how, rec.pos + Vector2(0.0, 1.0))

	# A bad ball: the QB shrugs.
	await _stage(rec, cb, {"kind": "incomplete"})
	await _wait(0.5)
	await _shot("shrug", qb.pos)

	# A long gain: fist pump.
	await _stage(rec, null, {"kind": "complete", "yards": 22.0})
	sim.carrier = rec
	await _wait(0.45)
	await _shot("pump", rec.pos)

	# Tackle dust.
	await _back_to_presnap()
	sim.snap()
	await _wait(0.4)
	cb.vel = Vector2(-3.0, 1.0)
	cb.downed = 0.0001
	await _wait(0.12)
	await _shot("dust", cb.pos)
	print("done")
	get_tree().quit()


func _stage(rec: SimPlayer, cover: SimPlayer, res: Dictionary) -> void:
	await _back_to_presnap()
	sim.snap()
	await _wait(0.3)
	for sp in sim.offense + sim.defense:
		sp.vel = Vector2.ZERO
		sp.downed = 0.0
	rec.pos = Vector2(sim.los + 8.0, 20.0)
	if cover != null:
		cover.pos = rec.pos + Vector2(0.4, 2.0)
	sim.thrown_to = rec
	sim.carrier = null
	sim.ball_in_air = false
	var full := {"yards": 0.0, "td": false, "turnover": false, "text": "", "bucks": 0, "events": []}
	full.merge(res, true)
	sim.result = full
	sim.phase = MatchSim.Phase.DEAD


func _back_to_presnap() -> void:
	if sim.phase != MatchSim.Phase.PRESNAP:
		sim.advance()
		if sim.phase != MatchSim.Phase.PRESNAP:
			sim.begin_drive()
		inst.call("_refresh_bar")
	await _wait(0.3)


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shot(tag: String, at_yards: Vector2, half: int = 170) -> void:
	field.set("camera_locked", false)
	field.set("_cam_x", at_yards.x)
	field.set("_cam_y", at_yards.y)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var c: Vector2 = field.get_global_rect().position + field.call("to_px", at_yards)
	var rect := Rect2i(Vector2i(c) - Vector2i(half, half), Vector2i(half * 2, half * 2))
	rect = rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(rect)
	crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/%s.png" % [OUT_DIR, tag])
	print("  ", tag)
