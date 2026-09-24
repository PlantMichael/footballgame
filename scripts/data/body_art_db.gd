class_name BodyArtDB
extends RefCounted

## Per-sprite collar depth for assets/players/<view>/body_0N.png, so the
## head drawn on top of the jersey art can be anchored at each sprite's
## actual neckline instead of one fixed generic offset. The jersey art has
## no head baked in - field_view.gd lays the head sprite on top (HeadArtDB)
## - and since collar depth and canvas aspect ratio both vary per sprite, a
## single constant offset put the head noticeably off the collar for several
## of them.
##
## Value is the V-neck's deepest point (where the collar cutout bottoms out
## into fabric) as a fraction of the sprite's pixel height, measured down
## from the top of the image. Measured directly from each PNG's alpha
## channel with assets/players/_analyze.js - rerun that script and update
## this table if the art is replaced.

const NECK_FRAC := {
	"front": {1: 0.137, 2: 0.115, 3: 0.095, 4: 0.119, 5: 0.098, 6: 0.064, 8: 0.108, 9: 0.037},
	"back": {1: 0.076, 2: 0.069, 3: 0.066, 4: 0.078, 5: 0.074, 6: 0.063, 8: 0.063, 9: 0.044},
	"left": {1: 0.118, 2: 0.113, 3: 0.115, 4: 0.105, 5: 0.091, 6: 0.121, 8: 0.122},
}

## Used for any body/view combo not in the table above (e.g. left_09, which
## has no sprite at all yet and falls back to the plain capsule anyway).
const DEFAULT_FRAC := 0.09


static func neck_frac(view: String, body_id: String) -> float:
	var n := int(body_id)
	var by_view: Dictionary = NECK_FRAC.get(view, {})
	return float(by_view.get(n, DEFAULT_FRAC))
