extends SceneTree

## Extract the supplied civilian/ref sheets without removing enclosed whites.
## godot --headless --path . --script assets/sidelines/_cut_assets.gd -- SOURCE_FOLDER
const SHEETS := {
	"blue": {"front": "exec-cb489ef0-7312-4373-adfe-70ced6ade943.png", "back": "exec-4356f504-f98f-49bd-ab00-2631a380f56e.png", "left": "exec-9da32a4e-6f32-44c7-bc43-f0d30e002d4d.png"},
	"red": {"front": "exec-06e54852-e761-48d1-8d9c-e83ce208f0cd.png", "back": "exec-6470c085-adcd-48bc-b959-563fdf948593.png", "left": "exec-b84306d8-c322-4707-8c6b-c76cdaebdeda.png"},
	"green": {"front": "exec-05c9eb3f-53a3-42c7-aa24-6c207b054ea6.png", "back": "exec-a23d8b12-e2c1-4e3d-be5b-49c76e4bbf50.png", "left": "exec-24723ccc-1e18-44ff-8fcb-89c528af6c59.png"},
	"ref": {"front": "exec-e6c20ff6-8459-4843-b2cf-c9b706121612.png", "back": "exec-31419a97-22df-4c83-b819-4888dc1e8e62.png", "left": "exec-dfbc6ffd-384f-4f8a-9e56-ae0f57f73609.png"},
}
const BOXES := {
	1: Rect2i(0, 0, 315, 280), 3: Rect2i(615, 0, 300, 280),
	4: Rect2i(915, 0, 305, 280), 6: Rect2i(0, 280, 420, 250),
	7: Rect2i(420, 280, 290, 250), 8: Rect2i(710, 280, 390, 250),
	9: Rect2i(1100, 280, 436, 250),
}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Supply the source civilian-assets folder.")
		quit(1)
		return
	var count := 0
	for palette in SHEETS:
		for view in SHEETS[palette]:
			var source := Image.load_from_file(args[0].path_join(palette).path_join(SHEETS[palette][view]))
			if source == null:
				quit(1)
				return
			for body in BOXES:
				if palette == "ref" and body not in [4, 8]:
					continue
				var image := source.get_region(BOXES[body])
				image.convert(Image.FORMAT_RGBA8)
				_remove_paper(image)
				var used := image.get_used_rect()
				if used.size == Vector2i.ZERO:
					push_error("Empty cut: %s/%s/%s" % [palette, view, body])
					quit(1)
					return
				image = image.get_region(used.grow(2).intersection(Rect2i(Vector2i.ZERO, image.get_size())))
				var factor := minf(1.0, 256.0 / maxf(image.get_width(), image.get_height()))
				if factor < 1.0:
					image.resize(maxi(1, int(image.get_width() * factor)), maxi(1, int(image.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
				var folder := "res://assets/sidelines/%s/%s" % [palette, view]
				DirAccess.make_dir_recursive_absolute(folder)
				if image.save_png(folder.path_join("body_%02d.png" % body)) != OK:
					quit(1)
					return
				count += 1
	print("SIDELINE ASSETS: %d transparent bodies extracted" % count)
	quit()

func _remove_paper(image: Image) -> void:
	var w := image.get_width()
	var h := image.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	var queue := PackedInt32Array()
	for x in w:
		queue.append(x)
		queue.append((h - 1) * w + x)
	for y in h:
		queue.append(y * w)
		queue.append(y * w + w - 1)
	var read := 0
	while read < queue.size():
		var index := queue[read]
		read += 1
		if seen[index]:
			continue
		seen[index] = 1
		var x := index % w
		var y := index / w
		var c := image.get_pixel(x, y)
		if minf(c.r, minf(c.g, c.b)) < 232.0 / 255.0:
			continue
		image.set_pixel(x, y, Color.TRANSPARENT)
		if x > 0: queue.append(index - 1)
		if x + 1 < w: queue.append(index + 1)
		if y > 0: queue.append(index - w)
		if y + 1 < h: queue.append(index + w)
	# Re-ink soft paper-facing pixels so they do not leave a white fringe.
	var original: Image = image.duplicate()
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var c := original.get_pixel(x, y)
			var light := minf(c.r, minf(c.g, c.b))
			if c.a == 0.0 or light < 0.45:
				continue
			if original.get_pixel(x - 1, y).a == 0.0 or original.get_pixel(x + 1, y).a == 0.0 \
					or original.get_pixel(x, y - 1).a == 0.0 or original.get_pixel(x, y + 1).a == 0.0:
				image.set_pixel(x, y, Color(0.03, 0.03, 0.04, 1.0 - light))
