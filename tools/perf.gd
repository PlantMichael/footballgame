extends Node

## Runs live plays on the real match screen for a few seconds after a
## warm-up and reports frame-time stats.
##   godot --path . res://tools/perf.tscn

var _frames: Array = []
var _draw_us: Array = []


func _ready() -> void:
	GameState.new_run(20260817)
	var inst: Node = load("res://scenes/match.tscn").instantiate()
	add_child(inst)
	for i in 30:
		await get_tree().process_frame
	var sim: MatchSim = inst.get("sim")
	var t0 := Time.get_ticks_usec()
	var last := t0
	var plays := 0
	var warm := true
	while Time.get_ticks_usec() - t0 < 12_000_000:
		if warm and Time.get_ticks_usec() - t0 > 3_000_000:
			warm = false
			_frames.clear()
			print("warm-up done, plays so far ", plays)
		if sim.phase == MatchSim.Phase.PRESNAP:
			sim.snap()
			plays += 1
		elif sim.phase != MatchSim.Phase.LIVE:
			sim.advance()
			if sim.phase != MatchSim.Phase.PRESNAP:
				sim.begin_drive()
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		_frames.append(float(now - last) / 1000.0)
		last = now
	_frames.sort()
	var n := _frames.size()
	var sum := 0.0
	for f in _frames: sum += f
	print("plays %d frames %d avg %.2fms p50 %.2f p90 %.2f p99 %.2f max %.2f" % [plays, n, sum / n, _frames[n/2], _frames[int(n*0.9)], _frames[int(n*0.99)], _frames[n-1]])
	print("process %.2fms  physics %.2fms  draw_calls %d  objects %d" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	print("vsync ", DisplayServer.window_get_vsync_mode(), " max_fps ", Engine.max_fps, " fps ", Engine.get_frames_per_second())
	get_tree().quit()
