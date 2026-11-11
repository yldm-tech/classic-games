class_name GameRegistry
extends RefCounted

## Finds the games: every directory under the games root that is not SHARED_DIR is one game, described by its MANIFEST_FILE. Nothing lists the games anywhere else, so adding a directory adds a game. A directory whose manifest is missing, unreadable or invalid is reported in `problems` and left out; it never stops the others from loading.
##
## Works the same in the editor and in an exported build: DirAccess lists the directories packed into the PCK, and the manifests are packed because export_presets.cfg includes *.json.

const Manifest := preload("res://games/shared/game_manifest.gd")

const GAMES_ROOT := "res://games"
const SHARED_DIR := "shared"
const MANIFEST_FILE := "game.json"

static var _cache: Dictionary = {}

## { games: [entry], problems: [{ id, path, errors: [text] }] } for a games root, read once and cached. Entries are sorted by id.
## An entry is the manifest itself plus what the host needs resolved: `dir` (the game's directory), `entry_path` (a module's script), and `art.image_path` when the manifest names a picture. Whole numbers are ints, whatever JSON made of them.
static func catalog(root: String = GAMES_ROOT) -> Dictionary:
	if not _cache.has(root):
		_cache[root] = discover(root)
	return _cache[root]

## Drop what catalog() remembers, so the next call reads the directories again.
static func forget(root: String = "") -> void:
	if root == "":
		_cache.clear()
	else:
		_cache.erase(root)

static func discover(root: String = GAMES_ROOT) -> Dictionary:
	var games: Array[Dictionary] = []
	var problems: Array[Dictionary] = []
	# DirAccess.open reports a root that is not there through its return value; get_directories_at would log an engine error for it.
	var access := DirAccess.open(root)
	if access == null:
		return {"games": games, "problems": problems}
	var names := Array(access.get_directories())
	names.sort()
	for folder: String in names:
		if folder == SHARED_DIR or folder.begins_with(".") or folder.begins_with("_"):
			continue
		var dir := root.path_join(folder)
		var path := dir.path_join(MANIFEST_FILE)
		var loaded := read(path)
		var errors: PackedStringArray = loaded["errors"]
		if errors.is_empty():
			errors = Manifest.validate(loaded["manifest"], dir)
		if not errors.is_empty():
			problems.append({"id": folder, "path": path, "errors": errors})
			continue
		games.append(_resolved(loaded["manifest"], dir))
	return {"games": games, "problems": problems}

## Read one manifest file: { manifest, errors }. A file that is missing or is not a JSON object is an error, not a crash.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"manifest": {}, "errors": PackedStringArray(["%s: missing" % MANIFEST_FILE])}
	# JSON.parse on an instance reports failure through its return value; the static parse_string would also log an engine error for a file this function recovers from.
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {"manifest": {}, "errors": PackedStringArray(["%s: not valid JSON (line %d: %s)" % [MANIFEST_FILE, json.get_error_line(), json.get_error_message()]])}
	if not json.data is Dictionary:
		return {"manifest": {}, "errors": PackedStringArray(["%s: must be a JSON object" % MANIFEST_FILE])}
	return {"manifest": json.data, "errors": PackedStringArray()}

## One line per problem, "<id>: <error>", for a log or a failing check.
static func problem_lines(problems: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for problem: Dictionary in problems:
		for error: String in problem["errors"]:
			out.append("%s: %s" % [problem["id"], error])
	return out

static func _resolved(manifest: Dictionary, dir: String) -> Dictionary:
	var entry: Dictionary = _whole_numbers(manifest)
	entry["dir"] = dir
	if entry.get("kind") == Manifest.KIND_MODULE:
		entry["entry_path"] = dir.path_join(str(entry["entry"]))
	var art: Dictionary = entry["art"]
	if art.has("image"):
		art["image_path"] = dir.path_join(str(art["image"]))
	if not entry.has("options"):
		entry["options"] = []
	return entry

## A deep copy in which every float that holds a whole number is an int. JSON has one number type, and the hosts compare option values, player counts and thresholds as ints.
static func _whole_numbers(value: Variant) -> Variant:
	if value is float:
		return int(value) if is_equal_approx(value, roundf(value)) else value
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[key] = _whole_numbers(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item: Variant in value:
			out.append(_whole_numbers(item))
		return out
	return value
