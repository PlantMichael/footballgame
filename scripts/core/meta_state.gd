extends Node

## Autoload. The only state that survives a fresh "New Run" or a full restart
## of the game: which QB has won which bowl, Isaac-character-mark style. See
## BowlDB for the bowl ids and qb_select.gd for where the marks are shown.

const SAVE_PATH := "user://progress.json"

## qb_id (String, since JSON dictionary keys are always strings) -> {bowl_id: true}
var marks: Dictionary = {}


func _ready() -> void:
	_load()


func has_mark(qb_id: int, bowl_id: String) -> bool:
	var won: Dictionary = marks.get(str(qb_id), {})
	return won.get(bowl_id, false)


func award_mark(qb_id: int, bowl_id: String) -> void:
	if qb_id < 0 or bowl_id == "":
		return
	var key := str(qb_id)
	var won: Dictionary = marks.get(key, {})
	if won.get(bowl_id, false):
		return
	won[bowl_id] = true
	marks[key] = won
	_save()


func _load() -> void:
	marks = {}
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		marks = parsed.get("marks", {})


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("MetaState: could not open %s for writing" % SAVE_PATH)
		return
	f.store_string(JSON.stringify({"marks": marks}))
