class_name JerseyDB
extends RefCounted

## Jersey colours. Your team always wears BLUE - the original body art in
## assets/players/<view>/. Every other colour is a full copy of that art cut
## from its own sprite sheets by assets/players/_cut_jerseys.py, fitted to
## the blue bodies pixel for pixel, in assets/players/<colour>/<view>/.
## The opponent draws one of COLORS at random each match (MatchSim.setup).
##
## Adding a colour: run _cut_jerseys.py on its three sheets, then list it
## here.

const BLUE := ""
const COLORS := ["green", "red"]


## A random opponent colour, or blue if no others exist yet.
static func random_opponent() -> String:
	return BLUE if COLORS.is_empty() else String(COLORS.pick_random())
