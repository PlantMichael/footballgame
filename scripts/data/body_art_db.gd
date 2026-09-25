class_name BodyArtDB
extends RefCounted

## Where the head sits on each body sprite. The jersey art has no head baked
## in - field_view.gd and UIKit.player_portrait lay a HeadArtDB head on top -
## and collar depth, canvas size, and aspect ratio all vary sprite to sprite,
## so each body/view gets its own placement.
##
## That placement is authored by hand, not written down here: every body has
## a rig scene per view at RIG_PATH, a Node2D with a "Body" Sprite2D (locked
## in the editor so clicks go to the head) and a "Head" Sprite2D. Open one in
## the Godot editor, drag and scale the Head until it looks right on that
## body, and save - the game reads the Head's position, scale, and rotation
## straight out of the scene. The Body's own scale sizes the jersey (select
## it in the scene tree, since it's click-locked in the viewport). The head texture in the
## rig is just a stand-in for sizing; whichever head set a player actually
## has is drawn at the same spot and height.
##
## Front-view skin-tone variants (body_0N_dark/_pale) share the plain
## body's rig, since only the collar colour differs.

const RIG_PATH := "res://assets/players/rigs/%s/body_%02d.tscn"

## Used when a body/view has no rig scene (e.g. left body_09, which has no
## sprite at all and falls back to the plain capsule anyway).
const DEFAULT_RIG := {"offset": Vector2(0.0, -0.42), "height": 0.5, "rotation": 0.0,
	"body_scale": Vector2.ONE, "body_offset": Vector2.ZERO}

static var _cache: Dictionary = {}


## Placement read from `view`'s `body_id` rig, all in the rig scene's own
## space (what you see in the editor is what gets drawn), measured against
## the body texture's unscaled size so the game's equal-area body sizing
## still applies on top:
##   body_scale  - Vector2, the Body sprite's scale. Shrinks/grows just the
##                 jersey, e.g. to bring a tall, skinny sprite down to the
##                 same height as the rest. The head is unaffected.
##   body_offset - the Body sprite's position, as a fraction of its texture
##                 width/height.
##   offset      - the Head's centre, as a fraction of the body texture's
##                 width/height (+y is down - an unmirrored, upright body).
##   height      - the Head's drawn height, as a fraction of the body
##                 texture's height.
##   rotation    - the Head's rotation in radians.
static func head_rig(view: String, body_id: String) -> Dictionary:
	var key := "%s:%s" % [view, body_id]
	if not _cache.has(key):
		_cache[key] = _load_rig(view, int(body_id))
	return _cache[key]


static func _load_rig(view: String, n: int) -> Dictionary:
	var path := RIG_PATH % [view, n]
	if n < 1 or not ResourceLoader.exists(path):
		return DEFAULT_RIG
	var scene: PackedScene = load(path)
	if scene == null:
		return DEFAULT_RIG
	var root := scene.instantiate()
	var body := root.get_node_or_null("Body") as Sprite2D
	var head := root.get_node_or_null("Head") as Sprite2D
	var out := DEFAULT_RIG
	if body != null and head != null and body.texture != null and head.texture != null:
		var body_size := body.texture.get_size()
		var head_h := head.region_rect.size.y if head.region_enabled else head.texture.get_size().y
		head_h *= absf(head.scale.y)
		out = {
			"offset": head.position / body_size,
			"height": head_h / body_size.y,
			"rotation": head.rotation,
			"body_scale": body.scale.abs(),
			"body_offset": body.position / body_size,
		}
	root.free()
	return out
