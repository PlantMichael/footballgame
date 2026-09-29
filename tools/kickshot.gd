extends Node

## Walks a field goal try through the real match screen and saves frames:
## the kick unit lining up, a chalked kick, the ball in the air, and the
## result/celebration.
##   godot --path . res://tools/kickshot.tscn
## (Needs a real renderer; --headless produces blank images.)

const OUT_DIR := "user://shots/kick"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	GameState.new_run(20260817)
	# Sign a kicker - the first one goes straight into the K slot.
	for e in ShopPlayerDB._entries():
		if String(e.get("name", "")) == "Idrop Balls":
			GameState.add_player(ShopPlayerDB._make(e, GameState.rng))
	print("kicker: ", GameState.kicker().pname if GameState.kicker() != null else "none")
	print("shots -> %s" % ProjectSettings.globalize_path(OUT_DIR))

	var inst: Node = load("res://scenes/match.tscn").instantiate()
	add_child(inst)
	await _wait(0.3)
	var sim: MatchSim = inst.get("sim")
	await _shot("0_playcall")

	sim.los = 82.0
	inst.call("_apply_call")
	inst.call("_refresh_bar")
	inst.get("field").call("snap_camera")
	await _wait(0.2)
	# The KICK button.
	sim.set_kick_mode(true)
	inst.call("_refresh_bar")
	await _wait(0.4)
	await _shot("1_kick_unit_walking_on")
	await _wait(1.6)
	await _shot("2_kick_unit_set")
	print("wind %.1f mph %s, range %.1f, distance %.1f" % [sim.wind_mph(), str(sim.wind), sim.kick_range(), sim.kick_distance()])

	# Chalk a kick bent into the wind, the way a coach would.
	var spot := sim.kick_spot()
	var target := Vector2(MatchSim.POSTS_X + 4.0, MatchSim.FIELD_W * 0.5)
	var T := spot.distance_to(target) / MatchSim.KICK_SPEED
	var push := sim.wind * MatchSim.WIND_ACCEL_PER_MPH * 0.5 * T * T
	var mid := spot.lerp(target, 0.5) - push * 0.6
	inst.call("_on_route_drawn", GameState.KICKER_SLOT, [mid - spot, target - push - spot])
	await _wait(0.3)
	await _shot("3_kick_chalked")

	inst.call("_on_snap")
	await _wait(0.9)
	await _shot("4_ball_in_air")
	var guard := 0
	while sim.phase == MatchSim.Phase.LIVE and guard < 600:
		await get_tree().process_frame
		guard += 1
	print("result: ", sim.result.get("text", ""))
	await _wait(0.2)
	await _shot("5_result")
	await _wait(1.8)
	await _shot("6_after")
	inst.call("_on_continue")
	await _wait(0.5)
	await _shot("7_drive_over")
	print("score %d - %d" % [sim.score_us, sim.score_them])
	get_tree().quit()


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, tag])
	print("  ", tag)
