class_name LauncherPcLibrary
extends RefCounted

## The data side of PC mode: which games a category, a search text and a genre leave, and in what order. Every function is pure: it takes the catalog entries and the store and returns entries, so the views only draw what they are handed.

const CAT_ALL := &"all"
const CAT_FAVORITES := &"favorites"
const CAT_RECENT := &"recent"
const CAT_UNPLAYED := &"unplayed"
const CATEGORIES: Array[StringName] = [CAT_ALL, CAT_FAVORITES, CAT_RECENT, CAT_UNPLAYED]

const SORT_NAME := &"name"
const SORT_RECENT := &"recent"
const SORT_PROGRESS := &"progress"
const SORT_TIME := &"time"
const SORTS: Array[StringName] = [SORT_NAME, SORT_RECENT, SORT_PROGRESS, SORT_TIME]

static func in_category(entry: Dictionary, category: StringName, store: LauncherStore) -> bool:
	var id := str(entry["id"])
	match category:
		CAT_FAVORITES:
			return store.is_favorite(id)
		CAT_RECENT:
			return store.recents().has(id)
		CAT_UNPLAYED:
			return not store.has_played(id)
	return true

## A typed search matches the Chinese name anywhere, the Latin name (anywhere for two letters or more, at the start of a word for a single letter), or the pinyin initials the way LauncherCatalog.matches does. Case is ignored.
static func matches(entry: Dictionary, query: String) -> bool:
	var q := query.strip_edges().to_lower()
	if q == "":
		return true
	if LauncherCatalog.text(entry, "name", "zh").to_lower().contains(q):
		return true
	var latin := LauncherCatalog.text(entry, "name", "en").to_lower()
	if q.length() > 1 and latin.contains(q):
		return true
	if q.length() == 1:
		for word in latin.split(" ", false):
			if word.begins_with(q):
				return true
	return LauncherCatalog.matches(entry, q)

## The genre of an entry as a filter key. The English label is the key because it is the same in every interface language.
static func genre_key(entry: Dictionary) -> String:
	return LauncherCatalog.text(entry, "genre", "en")

## [{ key, label, count }] for every genre the entries have, in first-seen order.
static func genres(entries: Array, locale: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var index := {}
	for entry: Dictionary in entries:
		var key := genre_key(entry)
		if not index.has(key):
			index[key] = out.size()
			out.append({"key": key, "label": LauncherCatalog.text(entry, "genre", locale), "count": 0})
		out[index[key]]["count"] += 1
	return out

static func count_in(entries: Array, category: StringName, store: LauncherStore) -> int:
	var count := 0
	for entry: Dictionary in entries:
		if in_category(entry, category, store):
			count += 1
	return count

## Share of an entry's achievements that are unlocked, 0..1.
static func achievement_ratio(entry: Dictionary, store: LauncherStore) -> float:
	var defined: Array = entry.get("achievements", [])
	if defined.is_empty():
		return 0.0
	return float(unlocked_count(entry, store)) / float(defined.size())

static func unlocked_count(entry: Dictionary, store: LauncherStore) -> int:
	var unlocked := store.achievements(str(entry["id"]))
	var count := 0
	for achievement: Dictionary in entry.get("achievements", []):
		if unlocked.has(achievement["id"]):
			count += 1
	return count

## The entries that pass the category, the search text and the genre ("" = every genre), in the requested order.
static func visible(entries: Array, store: LauncherStore, category: StringName, query: String, genre: String, sort: StringName, locale: String) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if in_category(entry, category, store) and matches(entry, query) and (genre == "" or genre_key(entry) == genre):
			kept.append(entry)
	return sorted(kept, store, sort, locale)

## Name order is by pinyin initials in Chinese and by the Latin name otherwise. The other orders put the most recent, most complete or most played first. Ties keep the order the entries came in.
static func sorted(entries: Array[Dictionary], store: LauncherStore, sort: StringName, locale: String) -> Array[Dictionary]:
	var keyed: Array = []
	for index in entries.size():
		var entry := entries[index]
		var stats := store.stats(str(entry["id"]))
		var key: Variant
		match sort:
			SORT_RECENT:
				key = -int(stats["last_played"])
			SORT_PROGRESS:
				key = -achievement_ratio(entry, store)
			SORT_TIME:
				key = -float(stats["play_seconds"])
			_:
				key = str(entry.get("initials", "")) if locale == "zh" else LauncherCatalog.text(entry, "name", "en").to_lower()
		keyed.append([key, index, entry])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	var out: Array[Dictionary] = []
	for item: Array in keyed:
		out.append(item[2])
	return out
