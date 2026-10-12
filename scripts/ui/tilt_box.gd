class_name TiltBox
extends Container

## Holds one child at a slight angle, like a card tossed onto the turf.
## Containers reset their children's rotation every time they lay them out,
## so a plain `rotation` on a card inside an HBox never sticks - this lays the
## child out over its own whole rect, then turns it about its centre. Sized
## to the child's minimum, so it drops into any box layout like the card
## would have.

@export var tilt_degrees: float = 0.0


func _init(degrees: float = 0.0) -> void:
	tilt_degrees = degrees


func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN:
		return
	for c in get_children():
		if c is Control:
			fit_child_in_rect(c, Rect2(Vector2.ZERO, size))
			c.pivot_offset = size * 0.5
			c.rotation = deg_to_rad(tilt_degrees)


func _get_minimum_size() -> Vector2:
	var m := Vector2.ZERO
	for c in get_children():
		if c is Control and c.visible:
			m = m.max(c.get_combined_minimum_size())
	return m
