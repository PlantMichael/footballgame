class_name HeadArtDB
extends RefCounted

## Head sprites, cut out of the canvases they ship on - one set per
## `PlayerData.head_id`: "1" and "2" are the two generic random styles every
## rolled player picks between, and a handful of named players (see
## Generator.RANDOM_HEAD_IDS, ShopPlayerDB's optional "head" JSON field, and
## CursedPlayerDB) get their own unique id instead.
##
## The art arrives as a head drawn well off to one side of a big canvas - the
## same framing in every file - so a texture used straight from the file
## would draw a small head in the corner of a mostly empty rect. This crops
## each one down to the head's own pixels the first time it's asked for, and
## hands back a square texture whose edges are the head's edges. That's what
## the draw code wants: something it can size by diameter and centre on the
## collar.
##
## The crop is measured from the alpha channel rather than written down, so
## re-exporting the art at a different position or size needs nothing here.

const SOURCE := {
	"1": {
		"front": "res://assets/heads_outlined/headforward.png",
		"back": "res://assets/heads_outlined/headback.png",
		"left": "res://assets/heads_outlined/headleft.png",
		"right": "res://assets/heads_outlined/headright.png",
	},
	"2": {
		"front": "res://assets/heads_outlined/head2front.png",
		"back": "res://assets/heads_outlined/head2back.png",
		"left": "res://assets/heads_outlined/head2left.png",
		"right": "res://assets/heads_outlined/head2right.png",
	},
	"runnadball": {
		"front": "res://assets/heads_outlined/runnadballfront.png",
		"back": "res://assets/heads_outlined/runnadballback.png",
		"left": "res://assets/heads_outlined/runnadballleft.png",
		"right": "res://assets/heads_outlined/runnadballright.png",
	},
	"rockstonehead": {
		"front": "res://assets/heads_outlined/rockstonehead.png",
		"back": "res://assets/heads_outlined/rockstoneheadback.png",
		"left": "res://assets/heads_outlined/rockstoneheadleft.png",
		"right": "res://assets/heads_outlined/rockstoneheadright.png",
	},
	"amillionbuggs": {
		"front": "res://assets/heads_outlined/amillionbuggsfront.png",
		"back": "res://assets/heads_outlined/amillionbuggsback.png",
		"left": "res://assets/heads_outlined/amillionbuggsleft.png",
		"right": "res://assets/heads_outlined/amillionbuggsright.png",
	},
	"cursed": {
		"front": "res://assets/heads_outlined/cursedplayerfront.png",
		"back": "res://assets/heads_outlined/cursedplayerback.png",
		"left": "res://assets/heads_outlined/cursedplayerleft.png",
		"right": "res://assets/heads_outlined/cursedplayerright.png",
	},
}

## "set_id:view" -> Texture2D, or null once we've established that combo has
## no art.
static var _cache: Dictionary = {}

## Where the round face sits on each source canvas ([x, y, w, h], canvas
## pixels), keyed by file name without extension - measured by
## assets/heads_outlined/_outline_heads.py. Heads are sized and placed by
## their FACE, so hair or anything else drawn past the circle hangs over the
## edge instead of shrinking the face to fit.
const FACES_PATH := "res://assets/heads_outlined/faces.json"
static var _faces: Dictionary = {}
static var _faces_loaded := false
## "set_id:view" -> Rect2, the face within that head's cropped texture.
static var _face_cache: Dictionary = {}


## Which head goes with a body sprite view. The body art has a single side
## view that field_view mirrors to face the other way; the heads ship as a
## real left/right pair, so the right-facing head is its own sprite rather
## than a flipped copy of the left one.
static func view_for(body_view: String, mirrored: bool) -> String:
	if body_view == "left":
		return "right" if mirrored else "left"
	return body_view


## Cropped head for `set_id`'s `view`, or null if that combo is missing -
## callers fall back to the plain drawn circle.
static func head_texture(set_id: String, view: String) -> Texture2D:
	var key := "%s:%s" % [set_id, view]
	if not _cache.has(key):
		_cache[key] = _load_cropped(set_id, view)
	return _cache[key]


## The face's rect inside head_texture(set_id, view), in that texture's
## pixels. For a plain round head it's the whole texture; for one with hair
## sticking out it's the circle below it. Draw the texture so THIS rect
## lands where the head goes (see face_draw_rect).
static func face_rect(set_id: String, view: String) -> Rect2:
	var key := "%s:%s" % [set_id, view]
	if not _face_cache.has(key):
		head_texture(set_id, view)   # fills _face_cache as a side effect
	return _face_cache.get(key, Rect2())


## Where to draw head_texture(set_id, view) so its face is a circle of
## `face_h` pixels centred on the origin - the rest of the art (hair)
## overflows around it. Local coordinates: draw with a transform at the
## head's centre.
static func face_draw_rect(set_id: String, view: String, tex: Texture2D, face_h: float) -> Rect2:
	var face := face_rect(set_id, view)
	if face.size.y <= 0.0:
		var ts := tex.get_size()
		return Rect2(Vector2(-face_h * 0.5 * ts.x / maxf(ts.y, 1.0), -face_h * 0.5),
			Vector2(face_h * ts.x / maxf(ts.y, 1.0), face_h))
	var k := face_h / face.size.y
	return Rect2(-(face.position + face.size * 0.5) * k, tex.get_size() * k)


static func _face_canvas_rect(path: String) -> Rect2:
	if not _faces_loaded:
		_faces_loaded = true
		if FileAccess.file_exists(FACES_PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FACES_PATH))
			if parsed is Dictionary:
				_faces = parsed
	var f: Variant = _faces.get(path.get_file().get_basename())
	if f is Array and f.size() == 4:
		return Rect2(float(f[0]), float(f[1]), float(f[2]), float(f[3]))
	return Rect2()


static func _load_cropped(set_id: String, view: String) -> Texture2D:
	var by_view: Dictionary = SOURCE.get(set_id, {})
	var path: String = by_view.get(view, "")
	if path == "" or not ResourceLoader.exists(path):
		return null
	var src: Texture2D = load(path)
	if src == null:
		return null
	var img := src.get_image()
	if img == null:
		return null
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return null
	var cut := img.get_region(used)
	var face := _face_canvas_rect(path)
	_face_cache["%s:%s" % [set_id, view]] = Rect2(face.position - Vector2(used.position), face.size) 		if face.size.y > 0.0 else Rect2(Vector2.ZERO, Vector2(used.size))
	# Heads are drawn at roughly 1/25th of the source size. The body sprites
	# get away without mipmaps at a similar reduction because they're broad
	# shapes; the eyes here are a couple of source pixels wide once scaled
	# and drop in and out between frames as the player moves without them.
	cut.generate_mipmaps()
	return ImageTexture.create_from_image(cut)
