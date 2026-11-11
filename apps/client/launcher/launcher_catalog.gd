class_name LauncherCatalog
extends RefCounted

## The games the launcher offers, read from the manifests under games/ (one directory per game, see docs/20-adding-a-game.md). This file holds no per-game data: adding a game is adding a directory, and nothing here changes. Nothing here reads local state either; play time, scores and unlocked achievements live in LauncherStore.
##
## The manifests are found and validated by the game side and reach the launcher through GameSession.catalog(), the launcher's one door to the games. They are read once, the first time anything asks. A game whose manifest is invalid is not offered; problems() lists what is wrong with it so the launcher can say so.
##
## Entry fields the launcher's screens use (the full manifest is documented in games/shared/game_manifest.gd):
##   id            stable key used by the store, key art and lookups
##   kind          "dsl" (runs a built-in runtime's baseline DSL, `runtime` is its reference) or "module" (a game module)
##   name          { zh, en }; the en name is also the Latin subtitle shown under the title in every locale
##   initials      lowercase pinyin initials of the zh name, for search
##   genre         { zh, en }
##   players       { min, max, join_in_progress? } local players the game really supports
##   tagline       { zh, en }, one line
##   colors        { title, shadow, glow } for the hero title
##   art           { motif, top, bottom, primary, secondary } for the procedural key art placeholder, and image_path when the game ships a picture
##   achievements  [{ id, icon, name { zh, en }, desc { zh, en }, when }]
##
## An achievement's `when` is checked against the result GameSession emits with game_ended: `cleared` (optional bool) must match, `players` (optional) is the least number of players the run must have ended with, every `min` field must be at least the given number and every `max` field at most. A run the player quit (aborted) never awards anything.

static var _root := GameSession.GAMES_ROOT
static var _games: Array[Dictionary] = []
static var _problems: Array[Dictionary] = []
static var _loaded := false
## Counts reloads, so a cache built from the catalog (LauncherGameGuide) knows when it is stale.
static var generation := 0

## Read the manifests again, optionally from another games directory (tests use a fixture directory).
static func use_root(root: String = GameSession.GAMES_ROOT) -> void:
	_root = root
	GameSession.forget_catalog()
	_loaded = false
	_load()

static func _load() -> void:
	if _loaded:
		return
	var found := GameSession.catalog(_root)
	_games.assign(found["games"])
	_problems.assign(found["problems"])
	_loaded = true
	generation += 1

static func all() -> Array[Dictionary]:
	_load()
	return _games

## Games that were found but cannot be offered: [{ id, path, errors: [text] }].
static func problems() -> Array[Dictionary]:
	_load()
	return _problems

static func ids() -> Array[String]:
	var out: Array[String] = []
	for game in all():
		out.append(str(game["id"]))
	return out

## The entry for an id, or {} when the catalog has no such game (a stale id in the store, for example).
static func by_id(id: String) -> Dictionary:
	for game in all():
		if game["id"] == id:
			return game
	return {}

static func has(id: String) -> bool:
	return not by_id(id).is_empty()

## The first game, for a screen that must show something before the player picked one. "" when no game could be loaded.
static func first_id() -> String:
	return str(all()[0]["id"]) if not all().is_empty() else ""

## Localised text of a { zh, en } field, falling back to zh.
static func text(entry: Dictionary, field: String, locale: String) -> String:
	var values: Dictionary = entry.get(field, {})
	return str(values.get(locale, values.get("zh", "")))

static func color(entry: Dictionary, group: String, key: String, fallback: Color = Color.WHITE) -> Color:
	var values: Dictionary = entry.get(group, {})
	return Color(str(values[key])) if values.has(key) else fallback

## "1P" or "1-2P" style label of the supported local player count.
static func players_label(entry: Dictionary) -> String:
	var players: Dictionary = entry.get("players", {})
	var low := int(players.get("min", 1))
	var high := int(players.get("max", low))
	return "%dP" % low if high <= low else "%d–%dP" % [low, high]

## Search by pinyin initials the way the prototype does: one letter matches the first initial, longer queries match anywhere.
static func matches(entry: Dictionary, query: String) -> bool:
	var q := query.strip_edges().to_lower()
	if q == "":
		return true
	var initials := str(entry.get("initials", ""))
	return initials.begins_with(q) if q.length() == 1 else initials.contains(q)

static func achievement_total() -> int:
	var total := 0
	for game in all():
		total += (game["achievements"] as Array).size()
	return total

## Whether the game can be played by two local players.
static func supports_two(entry: Dictionary) -> bool:
	return int((entry.get("players", {}) as Dictionary).get("max", 1)) >= 2

## Ids of the game's achievements that this result satisfies. `result` is the dictionary GameSession emits with game_ended.
static func earned(game_id: String, result: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if bool(result.get("aborted", false)):
		return out
	for achievement: Dictionary in by_id(game_id).get("achievements", []):
		if _satisfied(achievement.get("when", {}), result):
			out.append(str(achievement["id"]))
	return out

static func _satisfied(when: Dictionary, result: Dictionary) -> bool:
	if when.has("cleared") and bool(result.get("cleared", false)) != bool(when["cleared"]):
		return false
	if when.has("players") and int(result.get("player_count", 1)) < int(when["players"]):
		return false
	var minimums: Dictionary = when.get("min", {})
	for field in minimums:
		if not _is_number(result.get(field, 0)) or float(result.get(field, 0)) < float(minimums[field]):
			return false
	var maximums: Dictionary = when.get("max", {})
	for field in maximums:
		# A field the result does not carry cannot satisfy an upper bound: "at most 0 deaths" must not be awarded by a game that never reported deaths.
		if not result.has(field) or not _is_number(result[field]) or float(result[field]) > float(maximums[field]):
			return false
	return true

## A result field a condition can compare: a number, or a flag read as 0 or 1. A game may put anything in its result (a position, a list); such a field satisfies no condition instead of raising an error.
static func _is_number(value: Variant) -> bool:
	return value is int or value is float or value is bool
