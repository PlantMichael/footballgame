class_name DataUtil
extends RefCounted

## Small helpers the data tables share: loading a JSON array off disk, and
## the two kinds of random draw (weighted, and "prefer someone you don't
## already have") several of them make. Everything draws from the `rng`
## passed in - never Godot's global RNG - so seeded runs stay reproducible.


## The JSON array at `path`, or [] (with an error naming `who`) if the file
## is missing or isn't an array.
static func load_json_array(path: String, who: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("%s: missing %s" % [who, path])
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Array):
		push_error("%s: %s did not parse to a JSON array" % [who, path])
		return []
	return parsed


## An index into `weights` (relative, not probabilities), drawn in proportion
## to them. -1 if `weights` is empty.
static func weighted_index(rng: RandomNumberGenerator, weights: Array) -> int:
	if weights.is_empty():
		return -1
	var total := 0.0
	for w in weights:
		total += float(w)
	var roll := rng.randf() * total
	for i in weights.size():
		roll -= float(weights[i])
		if roll <= 0.0:
			return i
	# Float rounding can leave the roll a hair above 0 - the last one takes it.
	return weights.size() - 1


## Every entry's "name", in order.
static func names_of(entries: Array) -> Array:
	var out: Array = []
	for e in entries:
		out.append(String(e["name"]))
	return out


## The entry named `name`, or {}.
static func entry_named(entries: Array, name: String) -> Dictionary:
	for e in entries:
		if e["name"] == name:
			return e
	return {}


## A random entry whose "name" isn't in `exclude_names` (name -> true),
## falling back to any entry once every one of them is excluded.
static func pick_excluding(rng: RandomNumberGenerator, entries: Array, exclude_names: Dictionary) -> Dictionary:
	var pool: Array = []
	for e in entries:
		if not exclude_names.has(String(e["name"])):
			pool.append(e)
	if pool.is_empty():
		pool = entries
	return pool[rng.randi_range(0, pool.size() - 1)]
