class_name GameManifest
extends RefCounted

## The schema of a game manifest (games/<id>/game.json) as code: validate() returns every problem of one manifest as a readable line, so a broken game is reported instead of crashing the launcher. docs/20-adding-a-game.md is the reference for authors; this file is what actually decides.
##
## Fields (schema 1):
##   schema        1
##   id            the directory name: lowercase letters, digits and underscores, starting with a letter
##   kind          "module" (a GameModule script in this directory) or "dsl" (one of the built-in DSL runtimes)
##   entry         module: the GameModule script, a path inside the directory
##   runtime       dsl: the runtime reference, "name@version"
##   stage         module: { size: [width, height], pixel_art: bool }; size is 1920x1080 divided by a whole number
##   name, genre, tagline, how        { zh, en }
##   initials      lowercase pinyin initials of the zh name, for search
##   players       { min, max, join_in_progress? } with 1 <= min <= max <= 2
##   colors        { title, shadow, glow } as RRGGBB
##   art           { top, bottom, primary, secondary } as RRGGBB, plus optional motif and image (a picture inside the directory)
##   achievements  [{ id, icon, name, desc, when }]; when: { cleared?: bool, players?: int, min?: { field: number }, max?: { field: number } }
##   controls      module: [{ id, name, inputs: ["move" | a GameInput control] }]; dsl: [{ id, name, actions, glyphs, pad?, mouse?, performs? }]
##   hud           { clock: { mode, field?, total? }, vital?: { field, max, label }, stats?: [{ label, fields }], player_stats?: [{ label, fields }], boss?: { field, max, label? } }
##   options       [{ id, name, note, values: [int], default, labels?: [{ zh, en }], path?: JSON pointer (dsl only, required there) }]
##   site          optional, for the website only: { screenshot: a picture inside the directory, screenshot_alt: { zh, en }, art_alt: { zh, en } }
##   towers, tuning   dsl only: display names of tower types, and numbers the host applies around the runtime

const SCHEMA := 1
const KIND_MODULE := "module"
const KIND_DSL := "dsl"
const MAX_PLAYERS := 2
const CANVAS := Vector2i(1920, 1080)
const ICONS := ["star", "bolt", "cup", "shield"]
const CLOCK_MODES := ["countdown", "elapsed", "none"]
const INPUT_MOVE := "move"
const INPUTS := ["move", "up", "down", "left", "right", "a", "b", "x", "y", "l", "r"]
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp"]
const KEYS_COMMON := ["schema", "id", "kind", "name", "initials", "genre", "tagline", "how", "players", "colors", "art", "achievements", "controls", "hud", "options", "site"]
const KEYS_MODULE := ["entry", "stage"]
const KEYS_DSL := ["runtime", "towers", "tuning"]

## Every problem of a manifest, each as "<field>: <what is wrong>". Empty when it is valid. `dir` is the game's directory (the games root plus its id), used to check that the files it names exist.
static func validate(manifest: Dictionary, dir: String) -> PackedStringArray:
	var errors := PackedStringArray()
	var folder := dir.get_file()
	if not _is_int(manifest.get("schema")) or int(manifest["schema"]) != SCHEMA:
		errors.append("schema: must be %d" % SCHEMA)
	var id: Variant = manifest.get("id")
	if not id is String or not is_id(id):
		errors.append("id: must be lowercase letters, digits and underscores, starting with a letter")
	elif id != folder:
		errors.append("id: \"%s\" must equal the directory name \"%s\"" % [id, folder])
	var kind: Variant = manifest.get("kind")
	if not kind is String or not kind in [KIND_MODULE, KIND_DSL]:
		errors.append("kind: must be \"module\" or \"dsl\"")
		kind = ""
	var allowed: Array = KEYS_COMMON + (KEYS_MODULE if kind == KIND_MODULE else KEYS_DSL if kind == KIND_DSL else KEYS_MODULE + KEYS_DSL)
	for key: Variant in manifest:
		if not key in allowed:
			errors.append("%s: unknown field" % str(key))

	if kind == KIND_MODULE:
		_check_file(errors, "entry", manifest.get("entry"), dir, ["gd"])
		_check_stage(errors, manifest.get("stage"))
	elif kind == KIND_DSL:
		var runtime: Variant = manifest.get("runtime")
		if not runtime is String or (runtime as String).split("@").size() != 2 or not (runtime as String).split("@")[0].is_valid_identifier():
			errors.append("runtime: must be \"name@version\"")

	for field in ["name", "genre", "tagline", "how"]:
		_check_text(errors, field, manifest.get(field))
	var initials: Variant = manifest.get("initials")
	if not initials is String or initials == "" or initials != (initials as String).to_lower() or not (initials as String).is_valid_identifier():
		errors.append("initials: must be lowercase letters")
	_check_players(errors, manifest.get("players"))
	_check_colors(errors, "colors", manifest.get("colors"), ["title", "shadow", "glow"])
	_check_colors(errors, "art", manifest.get("art"), ["top", "bottom", "primary", "secondary"])
	if manifest.get("art") is Dictionary:
		var art: Dictionary = manifest["art"]
		if art.has("image"):
			_check_file(errors, "art.image", art["image"], dir, IMAGE_EXTENSIONS)
		if art.has("motif") and not art["motif"] is String:
			errors.append("art.motif: must be a string")
	_check_achievements(errors, manifest.get("achievements"), manifest.get("players"))
	_check_controls(errors, manifest.get("controls"), str(kind))
	_check_hud(errors, manifest.get("hud"))
	_check_options(errors, manifest.get("options", []), str(kind))
	if manifest.has("site"):
		var site: Variant = manifest["site"]
		if not site is Dictionary:
			errors.append("site: must be an object")
		else:
			if (site as Dictionary).has("screenshot"):
				_check_file(errors, "site.screenshot", site["screenshot"], dir, IMAGE_EXTENSIONS)
			for key: Variant in site:
				match str(key):
					"screenshot":
						pass
					"screenshot_alt", "art_alt":
						_check_text(errors, "site.%s" % key, site[key])
					_:
						errors.append("site.%s: unknown field" % str(key))
	if manifest.has("towers") and not manifest["towers"] is Dictionary:
		errors.append("towers: must be an object")
	if manifest.has("tuning"):
		var tuning: Variant = manifest["tuning"]
		if not tuning is Dictionary:
			errors.append("tuning: must be an object")
		else:
			for key: Variant in tuning:
				if not _is_number(tuning[key]):
					errors.append("tuning.%s: must be a number" % str(key))
	return errors

static func is_id(value: String) -> bool:
	return value != "" and value == value.to_lower() and value.is_valid_identifier() and not value.begins_with("_")

## The stage of a module manifest as { size: Vector2i, pixel_art: bool, scale: int }; scale is how many canvas pixels one stage pixel covers. Call only on a valid manifest.
static func stage(manifest: Dictionary) -> Dictionary:
	var spec: Dictionary = manifest.get("stage", {})
	var raw: Array = spec.get("size", [960, 540])
	var size := Vector2i(int(raw[0]), int(raw[1]))
	return {"size": size, "pixel_art": bool(spec.get("pixel_art", false)), "scale": maxi(1, CANVAS.x / maxi(1, size.x))}

static func _is_int(value: Variant) -> bool:
	return value is int or (value is float and is_equal_approx(value, roundf(value)))

static func _is_number(value: Variant) -> bool:
	return value is int or value is float

static func _is_text(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for locale in ["zh", "en"]:
		if not (value as Dictionary).get(locale) is String or str(value[locale]).strip_edges() == "":
			return false
	return true

static func _check_text(errors: PackedStringArray, field: String, value: Variant) -> void:
	if not _is_text(value):
		errors.append("%s: must be { \"zh\": text, \"en\": text }, both filled in" % field)

static func _is_hex(value: Variant) -> bool:
	return value is String and (value as String).length() == 6 and (value as String).is_valid_hex_number()

static func _check_colors(errors: PackedStringArray, field: String, value: Variant, keys: Array) -> void:
	if not value is Dictionary:
		errors.append("%s: must be an object" % field)
		return
	for key: String in keys:
		if not _is_hex((value as Dictionary).get(key)):
			errors.append("%s.%s: must be a colour as RRGGBB" % [field, key])

## A file the manifest names must be a plain relative path that stays inside the game's directory and exists.
static func _check_file(errors: PackedStringArray, field: String, value: Variant, dir: String, extensions: Array) -> void:
	if not value is String or value == "":
		errors.append("%s: must be a file name inside the game's directory" % field)
		return
	var path := value as String
	if path.begins_with("/") or path.contains("..") or path.contains("://") or path.contains("\\"):
		errors.append("%s: \"%s\" must be a relative path inside the game's directory" % [field, path])
		return
	if not path.get_extension().to_lower() in extensions:
		errors.append("%s: \"%s\" must end in .%s" % [field, path, " / .".join(PackedStringArray(extensions))])
		return
	# An imported picture is shipped as its import, not as the file itself; ResourceLoader knows both forms.
	if not FileAccess.file_exists(dir.path_join(path)) and not ResourceLoader.exists(dir.path_join(path)):
		errors.append("%s: \"%s\" does not exist in %s" % [field, path, dir])

static func _check_stage(errors: PackedStringArray, value: Variant) -> void:
	if not value is Dictionary:
		errors.append("stage: must be { \"size\": [width, height], \"pixel_art\": bool }")
		return
	var size: Variant = (value as Dictionary).get("size")
	if not size is Array or (size as Array).size() != 2 or not _is_int(size[0]) or not _is_int(size[1]):
		errors.append("stage.size: must be [width, height]")
	else:
		var width := int(size[0])
		var height := int(size[1])
		if width < 160 or CANVAS.x % width != 0 or CANVAS.y % maxi(1, height) != 0 or CANVAS.x / width != CANVAS.y / maxi(1, height):
			errors.append("stage.size: [%d, %d] must be 1920x1080 divided by a whole number (960x540, 640x360, 480x270, 384x216, 320x180 ...)" % [width, height])
	if (value as Dictionary).has("pixel_art") and not value["pixel_art"] is bool:
		errors.append("stage.pixel_art: must be true or false")

static func _check_players(errors: PackedStringArray, value: Variant) -> void:
	if not value is Dictionary or not _is_int((value as Dictionary).get("min")) or not _is_int((value as Dictionary).get("max")):
		errors.append("players: must be { \"min\": n, \"max\": n }")
		return
	var low := int(value["min"])
	var high := int(value["max"])
	if low < 1 or high < low or high > MAX_PLAYERS:
		errors.append("players: needs 1 <= min <= max <= %d" % MAX_PLAYERS)
	if (value as Dictionary).has("join_in_progress") and not value["join_in_progress"] is bool:
		errors.append("players.join_in_progress: must be true or false")

static func _check_achievements(errors: PackedStringArray, value: Variant, players: Variant) -> void:
	if not value is Array:
		errors.append("achievements: must be a list")
		return
	var seen: Array = []
	for index in (value as Array).size():
		var at := "achievements[%d]" % index
		var item: Variant = value[index]
		if not item is Dictionary:
			errors.append("%s: must be an object" % at)
			continue
		var id: Variant = (item as Dictionary).get("id")
		if not id is String or not is_id(id):
			errors.append("%s.id: must be lowercase letters, digits and underscores" % at)
		elif id in seen:
			errors.append("%s.id: \"%s\" is used twice" % [at, id])
		else:
			seen.append(id)
		if not (item as Dictionary).get("icon") in ICONS:
			errors.append("%s.icon: must be one of %s" % [at, ", ".join(PackedStringArray(ICONS))])
		_check_text(errors, at + ".name", item.get("name"))
		_check_text(errors, at + ".desc", item.get("desc"))
		var when: Variant = (item as Dictionary).get("when")
		if not when is Dictionary:
			errors.append("%s.when: must be an object ({} unlocks on any finished run)" % at)
			continue
		for key: Variant in when:
			match str(key):
				"cleared":
					if not when[key] is bool:
						errors.append("%s.when.cleared: must be true or false" % at)
				"players":
					var most := int(players["max"]) if players is Dictionary and _is_int((players as Dictionary).get("max")) else MAX_PLAYERS
					if not _is_int(when[key]) or int(when[key]) < 1 or int(when[key]) > most:
						errors.append("%s.when.players: must be a player count the game supports" % at)
				"min", "max":
					if not when[key] is Dictionary:
						errors.append("%s.when.%s: must be { field: number }" % [at, key])
						continue
					for field: Variant in when[key]:
						if not _is_number(when[key][field]):
							errors.append("%s.when.%s.%s: must be a number" % [at, key, str(field)])
				_:
					errors.append("%s.when.%s: unknown condition (cleared, players, min, max)" % [at, str(key)])

static func _is_strings(value: Variant) -> bool:
	if not value is Array:
		return false
	for item: Variant in value:
		if not item is String or item == "":
			return false
	return true

static func _check_controls(errors: PackedStringArray, value: Variant, kind: String) -> void:
	if not value is Array or (value as Array).is_empty():
		errors.append("controls: must be a non-empty list")
		return
	var seen: Array = []
	for index in (value as Array).size():
		var at := "controls[%d]" % index
		var item: Variant = value[index]
		if not item is Dictionary:
			errors.append("%s: must be an object" % at)
			continue
		var id: Variant = (item as Dictionary).get("id")
		if not id is String or not is_id(id) or id in seen:
			errors.append("%s.id: must be a unique lowercase identifier" % at)
		seen.append(id)
		_check_text(errors, at + ".name", item.get("name"))
		if kind == KIND_MODULE:
			var inputs: Variant = (item as Dictionary).get("inputs")
			if not _is_strings(inputs) or (inputs as Array).is_empty():
				errors.append("%s.inputs: must be a non-empty list of %s" % [at, ", ".join(PackedStringArray(INPUTS))])
			else:
				for input_name: String in inputs:
					if not input_name in INPUTS:
						errors.append("%s.inputs: \"%s\" is not one of %s" % [at, input_name, ", ".join(PackedStringArray(INPUTS))])
			for key: Variant in item:
				if not str(key) in ["id", "name", "inputs"]:
					errors.append("%s.%s: unknown field" % [at, str(key)])
		elif kind == KIND_DSL:
			for field in ["actions", "glyphs"]:
				if not _is_strings((item as Dictionary).get(field)):
					errors.append("%s.%s: must be a list of action names" % [at, field])
			for field in ["pad", "mouse"]:
				if (item as Dictionary).has(field):
					_check_text(errors, "%s.%s" % [at, field], item[field])
			if (item as Dictionary).has("performs") and not _is_strings(item["performs"]):
				errors.append("%s.performs: must be a list of command names" % at)

static func _check_cells(errors: PackedStringArray, field: String, value: Variant) -> void:
	if not value is Array:
		errors.append("%s: must be a list" % field)
		return
	for index in (value as Array).size():
		var at := "%s[%d]" % [field, index]
		var item: Variant = value[index]
		if not item is Dictionary:
			errors.append("%s: must be an object" % at)
			continue
		_check_text(errors, at + ".label", item.get("label"))
		var fields: Variant = (item as Dictionary).get("fields")
		if not _is_strings(fields) or (fields as Array).is_empty() or (fields as Array).size() > 2:
			errors.append("%s.fields: must name one or two snapshot fields" % at)

static func _check_meter(errors: PackedStringArray, field: String, value: Variant, needs_label: bool) -> void:
	if not value is Dictionary:
		errors.append("%s: must be an object" % field)
		return
	for key in ["field", "max"]:
		if not (value as Dictionary).get(key) is String or value[key] == "":
			errors.append("%s.%s: must name a snapshot field" % [field, key])
	if needs_label or (value as Dictionary).has("label"):
		_check_text(errors, field + ".label", value.get("label"))

static func _check_hud(errors: PackedStringArray, value: Variant) -> void:
	if not value is Dictionary:
		errors.append("hud: must be an object")
		return
	var hud: Dictionary = value
	var clock: Variant = hud.get("clock")
	if not clock is Dictionary or not (clock as Dictionary).get("mode") in CLOCK_MODES:
		errors.append("hud.clock.mode: must be one of %s" % ", ".join(PackedStringArray(CLOCK_MODES)))
	else:
		for key in ["field", "total"]:
			if (clock as Dictionary).has(key) and (not clock[key] is String or clock[key] == ""):
				errors.append("hud.clock.%s: must name a snapshot field" % key)
	if hud.has("vital"):
		_check_meter(errors, "hud.vital", hud["vital"], true)
	if hud.has("boss"):
		_check_meter(errors, "hud.boss", hud["boss"], false)
	for field in ["stats", "player_stats"]:
		if hud.has(field):
			_check_cells(errors, "hud." + field, hud[field])
	for key: Variant in hud:
		if not str(key) in ["clock", "vital", "boss", "stats", "player_stats"]:
			errors.append("hud.%s: unknown field" % str(key))

static func _check_options(errors: PackedStringArray, value: Variant, kind: String) -> void:
	if not value is Array:
		errors.append("options: must be a list")
		return
	var seen: Array = []
	for index in (value as Array).size():
		var at := "options[%d]" % index
		var item: Variant = value[index]
		if not item is Dictionary:
			errors.append("%s: must be an object" % at)
			continue
		var id: Variant = (item as Dictionary).get("id")
		if not id is String or not is_id(id) or id in seen:
			errors.append("%s.id: must be a unique lowercase identifier" % at)
		seen.append(id)
		_check_text(errors, at + ".name", item.get("name"))
		_check_text(errors, at + ".note", item.get("note"))
		var values: Variant = (item as Dictionary).get("values")
		var valid_values := values is Array and not (values as Array).is_empty()
		if valid_values:
			for entry: Variant in values:
				valid_values = valid_values and _is_int(entry)
		if not valid_values:
			errors.append("%s.values: must be a non-empty list of whole numbers" % at)
		elif not _is_int(item.get("default")) or not _has_number(values, int(item["default"])):
			errors.append("%s.default: must be one of the values" % at)
		if (item as Dictionary).has("labels"):
			var labels: Variant = item["labels"]
			if not labels is Array or not values is Array or (labels as Array).size() != (values as Array).size():
				errors.append("%s.labels: must have one { zh, en } per value" % at)
			else:
				for label_index in (labels as Array).size():
					_check_text(errors, "%s.labels[%d]" % [at, label_index], labels[label_index])
		if kind == KIND_DSL:
			if not (item as Dictionary).get("path") is String or not str(item["path"]).begins_with("/"):
				errors.append("%s.path: must be a JSON pointer into the runtime's DSL" % at)
		elif (item as Dictionary).has("path"):
			errors.append("%s.path: only a dsl game has one" % at)

static func _has_number(values: Array, wanted: int) -> bool:
	for entry: Variant in values:
		if int(entry) == wanted:
			return true
	return false
