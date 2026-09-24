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
		"front": "res://assets/headforward.png",
		"back": "res://assets/headback.png",
		"left": "res://assets/headleft.png",
		"right": "res://assets/headright.png",
	},
	"2": {
		"front": "res://assets/head2front.png",
		"back": "res://assets/head2back.png",
		"left": "res://assets/head2left.png",
		"right": "res://assets/head2right.png",
	},
	"runnadball": {
		"front": "res://assets/runnadballfront.png",
		"back": "res://assets/runnadballback.png",
		"left": "res://assets/runnadballleft.png",
		"right": "res://assets/runnadballright.png",
	},
	"rockstonehead": {
		"front": "res://assets/rockstonehead.png",
		"back": "res://assets/rockstoneheadback.png",
		"left": "res://assets/rockstoneheadleft.png",
		"right": "res://assets/rockstoneheadright.png",
	},
	"cursed": {
		"front": "res://assets/cursedplayerfront.png",
		"back": "res://assets/cursedplayerback.png",
		"left": "res://assets/cursedplayerleft.png",
		"right": "res://assets/cursedplayerright.png",
	},
}

## "set_id:view" -> Texture2D, or null once we've established that combo has
## no art.
static var _cache: Dictionary = {}


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
	# Heads are drawn at roughly 1/25th of the source size. The body sprites
	# get away without mipmaps at a similar reduction because they're broad
	# shapes; the eyes here are a couple of source pixels wide once scaled
	# and drop in and out between frames as the player moves without them.
	cut.generate_mipmaps()
	return ImageTexture.create_from_image(cut)
