class_name HeadArtDB
extends RefCounted

## The four head sprites, cut out of the canvases they ship on.
##
## The art arrives as a head drawn well off to one side of a big 1920x919
## canvas - the same framing in all four files - so a texture used straight
## from the file would draw a small head in the corner of a mostly empty
## rect. This crops each one down to the head's own pixels the first time
## it's asked for, and hands back a square texture whose edges are the
## head's edges. That's what the draw code wants: something it can size by
## diameter and centre on the collar.
##
## The crop is measured from the alpha channel rather than written down, so
## re-exporting the art at a different position or size needs nothing here.

const SOURCE := {
	"front": "res://assets/headforward.png",
	"back": "res://assets/headback.png",
	"left": "res://assets/headleft.png",
	"right": "res://assets/headright.png",
}

## view -> Texture2D, or null once we've established that view has no art.
static var _cache: Dictionary = {}


## Which head goes with a body sprite view. The body art has a single side
## view that field_view mirrors to face the other way; the heads ship as a
## real left/right pair, so the right-facing head is its own sprite rather
## than a flipped copy of the left one.
static func view_for(body_view: String, mirrored: bool) -> String:
	if body_view == "left":
		return "right" if mirrored else "left"
	return body_view


## Cropped head for `view`, or null if that sprite is missing - callers fall
## back to the plain drawn circle.
static func head_texture(view: String) -> Texture2D:
	if not _cache.has(view):
		_cache[view] = _load_cropped(view)
	return _cache[view]


static func _load_cropped(view: String) -> Texture2D:
	var path: String = SOURCE.get(view, "")
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
