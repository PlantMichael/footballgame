extends Node

## Run with a rendering driver after changing loading portraits or splash art:
## godot --path . --windowed res://tools/export_loader_art.tscn
func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(144, 144)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var splash: Texture2D = load("res://assets/ui/boot_splash.svg")
	splash.get_image().save_png("res://assets/ui/boot_splash.png")
	var icon: Texture2D = load("res://icon.svg")
	icon.get_image().save_png("res://web_build/index.icon.png")
	var touch := icon.get_image()
	touch.resize(180, 180, Image.INTERPOLATE_LANCZOS)
	touch.save_png("res://web_build/index.apple-touch-icon.png")
	for i in LoadingScreen.LOOKS.size():
		var look: Array = LoadingScreen.LOOKS[i]
		var data := PlayerData.new()
		data.body = look[0]
		data.head_id = look[1]
		var portrait := UIKit.player_portrait(data, 144)
		portrait.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		viewport.add_child(portrait)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		image.save_png("res://web_build/loader-player-%d.png" % (i + 1))
		portrait.free()
	print("LOADER_ART_EXPORTED")
	get_tree().quit()
