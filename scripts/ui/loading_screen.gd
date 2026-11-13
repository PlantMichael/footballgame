extends CanvasLayer

## Covers scene loading and match preparation. It owns presentation only;
## the destination tells it when its resources and first frame are ready.
var active := false
var _changing := false
var _generation := 0
var _shade: ColorRect
var _bar: ProgressBar
var _status: Label
var _back: Button
var _player: Control
var _player_host: Control
var _clock := 0.0
var _rng := RandomNumberGenerator.new()
var _hands: Array[TextureRect] = []
const HANDS := [preload("res://assets/hands/hand_light.png"), preload("res://assets/hands/hand_dark.png")]
const LOOKS := [["6", "1"], ["4", "2"], ["8", "1"]]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90
	_rng.randomize()
	_shade = ColorRect.new()
	_shade.color = UIKit.BG
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_shade.add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	center.add_child(column)
	var title := UIKit.label("GRIDIRON", 60, UIKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_player_host = Control.new()
	_player_host.custom_minimum_size = Vector2(0, 180)
	column.add_child(_player_host)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(400, 32)
	_bar.show_percentage = false
	_bar.add_theme_stylebox_override("background", UIKit.stylebox(UIKit.PANEL, 3, 1, UIKit.LINE))
	var turf := StyleBoxTexture.new()
	turf.texture = preload("res://assets/ui/loading_turf.svg")
	_bar.add_theme_stylebox_override("fill", turf)
	column.add_child(_bar)
	_status = UIKit.label("", 18, UIKit.TEXT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_back = UIKit.primary_button("BACK TO MENU", 20)
	_back.pressed.connect(func(): go_to("res://scenes/main_menu.tscn"))
	column.add_child(_back)
	hide()

func begin(message: String = "Preparing the field") -> int:
	_generation += 1
	active = true
	_clock = 0.0
	_back.hide()
	if is_instance_valid(_player):
		_player.free()
	var look: Array = LOOKS[_rng.randi_range(0, LOOKS.size() - 1)]
	var data := PlayerData.new()
	data.body = look[0]
	data.head_id = look[1]
	_player = UIKit.player_portrait(data, 144)
	_player.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_player.pivot_offset = Vector2(72, 110)
	_player_host.add_child(_player)
	_hands.clear()
	for i in 2:
		var hand := TextureRect.new()
		hand.texture = HANDS[1 if look[1] == "2" else 0]
		hand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hand.size = Vector2(14, 14)
		_player.add_child(hand)
		_hands.append(hand)
	update_progress(0.0, message)
	show()
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	return _generation

func update_progress(fraction: float, message: String) -> void:
	_bar.value = clampf(fraction, 0.0, 1.0) * 100.0
	_status.text = message

func _input(_event: InputEvent) -> void:
	# Mouse input is intercepted by the shade. Let the error button receive
	# keyboard navigation, otherwise consume keys before game controls.
	if active and not _back.visible:
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not active or not is_instance_valid(_player):
		return
	_clock += delta
	var beat := _clock * 5.5
	_player.position = Vector2((_player_host.size.x - 144.0) * 0.5, 18.0 - absf(sin(beat)) * 18.0)
	_player.rotation = sin(beat) * 0.07
	for i in _hands.size():
		_hands[i].position = Vector2(8.0 if i == 0 else 122.0, 85.0 - (0.5 + 0.5 * sin(beat)) * 52.0)

func finish(generation: int = -1) -> void:
	if generation >= 0 and generation != _generation:
		return
	active = false
	hide()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.gridironReady && window.gridironReady()", true)

func finish_after_frame() -> void:
	var generation := _generation
	await get_tree().process_frame
	await get_tree().process_frame
	if generation == _generation:
		finish()

func fail(message: String) -> void:
	_status.text = message
	_back.show()
	_back.grab_focus()
	# Uncover the runtime error state even if initial Web loading failed.
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.gridironReady && window.gridironReady()", true)

func go_to(path: String) -> void:
	if _changing:
		return
	_changing = true
	begin("Warming up")
	await get_tree().process_frame
	await get_tree().process_frame
	# Keep the project's ordinary scene-loading path. Incremental preparation
	# belongs to the destination's real sprite caches, not a second asset loader.
	var error := get_tree().change_scene_to_file(path)
	_changing = false
	if error != OK:
		fail("Couldn't load the next screen. Try returning to the menu.")
