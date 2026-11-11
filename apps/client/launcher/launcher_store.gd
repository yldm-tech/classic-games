class_name LauncherStore
extends RefCounted

## The launcher's only local state: one versioned JSON file under user://. Everything a screen shows about the player (play time, last played, best score, favourites, recents, achievements, settings, key bindings) is read from here, and only real play and real user actions write to it.
##
## Every mutation saves immediately. The file is written to a temporary sibling first and then renamed over the old one, so a crash mid-write leaves the previous file intact. A missing file means a fresh profile; an unreadable one is set aside as `<path>.corrupt` and replaced by a fresh profile rather than being overwritten in place.

signal changed(section: StringName)

const VERSION := 1
const DEFAULT_PATH := "user://launcher.json"
const MAX_RECENTS := 12

const SECTION_SETTINGS := &"settings"
const SECTION_FAVORITES := &"favorites"
const SECTION_RECENTS := &"recents"
const SECTION_STATS := &"stats"
const SECTION_ACHIEVEMENTS := &"achievements"
const SECTION_BINDINGS := &"bindings"

const DEFAULT_STATS := {"play_seconds": 0.0, "last_played": 0, "best_score": 0, "runs": 0, "clears": 0}

var path := DEFAULT_PATH
## True when the last load found a file it could not read and moved it aside.
var recovered_from_corruption := false

var _data: Dictionary = _fresh()

func _init(p_path: String = DEFAULT_PATH) -> void:
	path = p_path

static func _fresh() -> Dictionary:
	return {"version": VERSION, "settings": {}, "favorites": [], "recents": [], "stats": {}, "achievements": {}, "bindings": {}}

# ---- load / save ----

func load_from_disk() -> void:
	recovered_from_corruption = false
	_data = _fresh()
	if not FileAccess.file_exists(path):
		return
	# JSON.parse on an instance reports failure through its return value; the static parse_string would also log an engine error for a file we recover from.
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
	if not parsed is Dictionary or not _is_supported(parsed):
		recovered_from_corruption = true
		DirAccess.rename_absolute(path, path + ".corrupt")
		return
	_data = _normalised(parsed)

func save() -> bool:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_error("launcher store: cannot write %s (%s)" % [temporary, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(_data, "\t"))
	file.close()
	var renamed := DirAccess.rename_absolute(temporary, path)
	if renamed != OK:
		# Some platforms refuse to rename over an existing file.
		DirAccess.remove_absolute(path)
		renamed = DirAccess.rename_absolute(temporary, path)
	if renamed != OK:
		push_error("launcher store: cannot replace %s (%s)" % [path, error_string(renamed)])
		return false
	return true

static func _is_supported(parsed: Dictionary) -> bool:
	var version: Variant = parsed.get("version")
	return (version is float or version is int) and int(version) >= 1 and int(version) <= VERSION

## Copy only well-typed sections out of a parsed file, so a hand-edited or partially written file cannot put the wrong shape into memory.
static func _normalised(parsed: Dictionary) -> Dictionary:
	var out := _fresh()
	for section in ["settings", "stats", "achievements", "bindings"]:
		if parsed.get(section) is Dictionary:
			out[section] = (parsed[section] as Dictionary).duplicate(true)
	for section in ["favorites", "recents"]:
		if parsed.get(section) is Array:
			var ids: Array = []
			for id in parsed[section]:
				if id is String and not ids.has(id):
					ids.append(id)
			out[section] = ids
	for game_id in (out["stats"] as Dictionary).keys():
		if not out["stats"][game_id] is Dictionary:
			out["stats"].erase(game_id)
	for game_id in (out["achievements"] as Dictionary).keys():
		if not out["achievements"][game_id] is Dictionary:
			out["achievements"].erase(game_id)
	return out

func _commit(section: StringName) -> void:
	save()
	changed.emit(section)

# ---- settings ----

func setting(key: String, fallback: Variant = null) -> Variant:
	return (_data["settings"] as Dictionary).get(key, fallback)

func set_setting(key: String, value: Variant) -> void:
	var current: Variant = (_data["settings"] as Dictionary).get(key)
	# Compare types first: == between unrelated types (a number and a string from a hand-edited file) is a script error.
	if typeof(current) == typeof(value) and current == value:
		return
	_data["settings"][key] = value
	_commit(SECTION_SETTINGS)

# ---- favourites ----

func is_favorite(game_id: String) -> bool:
	return (_data["favorites"] as Array).has(game_id)

func favorites() -> Array[String]:
	return _string_array(_data["favorites"])

func set_favorite(game_id: String, on: bool) -> void:
	if is_favorite(game_id) == on:
		return
	if on:
		(_data["favorites"] as Array).append(game_id)
	else:
		(_data["favorites"] as Array).erase(game_id)
	_commit(SECTION_FAVORITES)

# ---- recents ----

## Game ids, most recently played first.
func recents() -> Array[String]:
	return _string_array(_data["recents"])

## Take a game off the recents list without touching its stats. Returns the index it had (-1 when it was not listed) so the removal can be undone with restore_recent.
func remove_recent(game_id: String) -> int:
	var index := (_data["recents"] as Array).find(game_id)
	if index < 0:
		return -1
	(_data["recents"] as Array).remove_at(index)
	_commit(SECTION_RECENTS)
	return index

func restore_recent(game_id: String, index: int) -> void:
	var list: Array = _data["recents"]
	if index < 0 or list.has(game_id):
		return
	list.insert(mini(index, list.size()), game_id)
	_commit(SECTION_RECENTS)

# ---- per-game stats ----

## { play_seconds, last_played (unix seconds, 0 = never), best_score, runs, clears } with defaults filled in.
func stats(game_id: String) -> Dictionary:
	var out := DEFAULT_STATS.duplicate()
	var stored: Variant = (_data["stats"] as Dictionary).get(game_id)
	if stored is Dictionary:
		out["play_seconds"] = maxf(0.0, float(stored.get("play_seconds", 0.0)))
		out["last_played"] = maxi(0, int(stored.get("last_played", 0)))
		out["best_score"] = maxi(0, int(stored.get("best_score", 0)))
		out["runs"] = maxi(0, int(stored.get("runs", 0)))
		out["clears"] = maxi(0, int(stored.get("clears", 0)))
	return out

func has_played(game_id: String) -> bool:
	return int(stats(game_id)["runs"]) > 0

## Record one finished run. `result` is the dictionary GameSession emits with game_ended (score, play_seconds, cleared, aborted); `now` is unix seconds.
## Returns { new_best, previous_best }. A run the player quit still counts its play time and its score, because both really happened.
func record_run(game_id: String, result: Dictionary, now: int) -> Dictionary:
	var current := stats(game_id)
	var score := maxi(0, int(result.get("score", 0)))
	var previous_best := int(current["best_score"])
	current["play_seconds"] = float(current["play_seconds"]) + maxf(0.0, float(result.get("play_seconds", 0.0)))
	current["last_played"] = now
	current["runs"] = int(current["runs"]) + 1
	if bool(result.get("cleared", false)) and not bool(result.get("aborted", false)):
		current["clears"] = int(current["clears"]) + 1
	current["best_score"] = maxi(previous_best, score)
	_data["stats"][game_id] = current
	var list: Array = _data["recents"]
	list.erase(game_id)
	list.push_front(game_id)
	if list.size() > MAX_RECENTS:
		list.resize(MAX_RECENTS)
	save()
	changed.emit(SECTION_STATS)
	changed.emit(SECTION_RECENTS)
	return {"new_best": score > previous_best, "previous_best": previous_best}

# ---- achievements ----

## { achievement_id: unix seconds it was unlocked } for one game.
func achievements(game_id: String) -> Dictionary:
	var stored: Variant = (_data["achievements"] as Dictionary).get(game_id)
	return (stored as Dictionary).duplicate() if stored is Dictionary else {}

func is_unlocked(game_id: String, achievement_id: String) -> bool:
	return achievements(game_id).has(achievement_id)

## Returns true when this call unlocked it, false when it already was.
func unlock(game_id: String, achievement_id: String, now: int) -> bool:
	if is_unlocked(game_id, achievement_id):
		return false
	if not (_data["achievements"] as Dictionary).has(game_id):
		_data["achievements"][game_id] = {}
	_data["achievements"][game_id][achievement_id] = now
	_commit(SECTION_ACHIEVEMENTS)
	return true

func unlocked_count(game_id: String = "") -> int:
	if game_id != "":
		return achievements(game_id).size()
	var total := 0
	for id in _data["achievements"]:
		total += (_data["achievements"][id] as Dictionary).size()
	return total

# ---- key bindings ----

## { action name: [physical keycodes] }. Only overrides are stored; an action that is not listed keeps the project default.
func bindings() -> Dictionary:
	var out := {}
	for action in _data["bindings"]:
		if not _data["bindings"][action] is Array:
			continue
		# JSON has one number type, so codes come back from disk as floats.
		var codes: Array = []
		for code in _data["bindings"][action]:
			codes.append(int(code))
		out[str(action)] = codes
	return out

func set_binding(action: String, keycodes: Array) -> void:
	var codes: Array = []
	for code in keycodes:
		codes.append(int(code))
	_data["bindings"][action] = codes
	_commit(SECTION_BINDINGS)

func clear_binding(action: String) -> void:
	if (_data["bindings"] as Dictionary).erase(action):
		_commit(SECTION_BINDINGS)

# ---- whole profile ----

## Forget everything the player did (stats, recents, favourites, achievements). Settings and key bindings stay.
func wipe_progress() -> void:
	_data["favorites"] = []
	_data["recents"] = []
	_data["stats"] = {}
	_data["achievements"] = {}
	save()
	for section in [SECTION_FAVORITES, SECTION_RECENTS, SECTION_STATS, SECTION_ACHIEVEMENTS]:
		changed.emit(section)

static func _string_array(values: Array) -> Array[String]:
	var out: Array[String] = []
	for value in values:
		out.append(str(value))
	return out

# ---- export / import ----

## Write the whole profile (same versioned JSON as the store's own file) to `target`. Returns false when the file cannot be written.
func export_to(target: String) -> bool:
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(_data, "\t"))
	file.close()
	return true

## Read a profile file through the same version check and normalisation as load_from_disk, without touching this store. Returns {} when the file is missing, unreadable, of the wrong shape, or of an unsupported version.
static func read_profile(source: String) -> Dictionary:
	if not FileAccess.file_exists(source):
		return {}
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(FileAccess.get_file_as_string(source)) == OK else null
	if not parsed is Dictionary or not _is_supported(parsed):
		return {}
	return _normalised(parsed)

## A copy of everything wipe_progress forgets (favourites, recents, stats, achievements), for replace_progress to restore.
func progress() -> Dictionary:
	var out := {}
	for section in ["favorites", "recents", "stats", "achievements"]:
		out[section] = _data[section].duplicate(true)
	return out

## Replace the progress sections with those of `profile` (the result of read_profile or progress). Settings and key bindings stay, as with wipe_progress.
func replace_progress(profile: Dictionary) -> void:
	var clean := _normalised(profile)
	for section in ["favorites", "recents", "stats", "achievements"]:
		_data[section] = clean[section]
	save()
	for section in [SECTION_FAVORITES, SECTION_RECENTS, SECTION_STATS, SECTION_ACHIEVEMENTS]:
		changed.emit(section)
