extends Node

## One-off visual check for the collar skin-tone variants (see
## UIKit.HEAD_SKIN_TONE_SUFFIX): renders every body id under head "1"
## (default tone), head "2" (dark) and "cursed" (pale) side by side so a
## mismatch is obvious at a glance.
##   godot --path . res://tools/collar_check.tscn

const OUT_DIR := "user://shots"
const BODY_IDS := ["1", "2", "3", "4", "5", "6", "8", "9"]
const HEADS := ["1", "2", "cursed"]
const PORTRAIT_SIZE := 90


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color("0d1512")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	move_child(bg, 0)

	for head in HEADS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		root.add_child(row)
		row.add_child(UIKit.label("head " + head, 16, UIKit.TEXT))
		for body_id in BODY_IDS:
			var p := PlayerData.new()
			p.pname = "B" + body_id
			p.pos = PlayerData.Pos.WR
			p.body = body_id
			p.head_id = head
			var portrait := UIKit.player_portrait(p, PORTRAIT_SIZE)
			if portrait:
				row.add_child(portrait)

	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/collar_check.png" % OUT_DIR
	img.save_png(path)
	print("saved -> %s" % ProjectSettings.globalize_path(path))
	get_tree().quit()
