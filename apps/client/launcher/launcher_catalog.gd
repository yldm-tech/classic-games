class_name LauncherCatalog
extends RefCounted

## The games the launcher offers. Pure data: adding a game is adding one entry to GAMES (and, when its art is ready, one texture for LauncherKeyArt). Nothing here reads local state; play time, scores and unlocked achievements live in LauncherStore.
##
## Entry fields:
##   id            stable key used by the store, key art and i18n-free lookups
##   runtime       runtime reference handed to GameSession ("name@version"); the game runs that runtime's baseline DSL
##   name          { zh, en }; the en name is also the Latin subtitle shown under the title in every locale
##   initials      lowercase pinyin initials of the zh name, for search
##   genre         { zh, en }
##   players       { min, max } local players the runtime really supports
##   tagline       { zh, en }, one line
##   colors        { title, shadow, glow } for the hero title
##   art           { motif, top, bottom, primary, secondary } for the procedural key art placeholder
##   achievements  [{ id, icon, name { zh, en }, desc { zh, en }, when }]
##
## An achievement's `when` is checked against the result GameSession emits with game_ended: `cleared` (optional bool) must match, and every `min` field must be at least the given number. A run the player quit (aborted) never awards anything.

const GAMES: Array[Dictionary] = [
	{
		"id": "shooter",
		"runtime": "shooter@1.0.0",
		"name": {"zh": "星环巡航", "en": "ORBIT PATROL"},
		"initials": "xhxh",
		"genre": {"zh": "飞行射击", "en": "ARENA SHOOTER"},
		"players": {"min": 1, "max": 1},
		"tagline": {"zh": "清空这片星域，再击落守在尽头的机甲。", "en": "Clear the sector, then bring down the mech that guards it."},
		"colors": {"title": "EAF4FF", "shadow": "2456C8", "glow": "5AA0FF"},
		"art": {"motif": "orbit", "top": "020413", "bottom": "0C1F4A", "primary": "5AA0FF", "secondary": "FFC857"},
		"achievements": [
			{"id": "first_sortie", "icon": "bolt", "name": {"zh": "首次出击", "en": "First Sortie"}, "desc": {"zh": "完成一局，无论胜负。", "en": "Finish a run, win or lose."}, "when": {}},
			{"id": "sector_clear", "icon": "cup", "name": {"zh": "星域肃清", "en": "Sector Clear"}, "desc": {"zh": "击落全部敌机与首领。", "en": "Destroy every enemy and the boss."}, "when": {"cleared": true}},
			{"id": "high_score", "icon": "star", "name": {"zh": "两千分", "en": "Two Thousand"}, "desc": {"zh": "单局得分达到 2,000。", "en": "Score 2,000 in a single run."}, "when": {"min": {"score": 2000}}},
		],
	},
	{
		"id": "survivor",
		"runtime": "survivor@1.0.0",
		"name": {"zh": "长夜草原", "en": "MEADOW VIGIL"},
		"initials": "cycy",
		"genre": {"zh": "生存动作", "en": "SURVIVAL ACTION"},
		"players": {"min": 1, "max": 1},
		"tagline": {"zh": "只管走位，武器自己开火。撑过三分钟。", "en": "You move, the weapon fires itself. Last three minutes."},
		"colors": {"title": "F1FFE4", "shadow": "2F7D3A", "glow": "8CE678"},
		"art": {"motif": "swarm", "top": "04110A", "bottom": "14532D", "primary": "8CE678", "secondary": "FDE047"},
		"achievements": [
			{"id": "first_watch", "icon": "bolt", "name": {"zh": "第一夜", "en": "First Watch"}, "desc": {"zh": "完成一局，无论胜负。", "en": "Finish a run, win or lose."}, "when": {}},
			{"id": "until_dawn", "icon": "cup", "name": {"zh": "守到天亮", "en": "Until Dawn"}, "desc": {"zh": "存活到计时结束。", "en": "Survive until the timer runs out."}, "when": {"cleared": true}},
			{"id": "level_three", "icon": "star", "name": {"zh": "渐入佳境", "en": "Warmed Up"}, "desc": {"zh": "单局升到 3 级。", "en": "Reach level 3 in a single run."}, "when": {"min": {"level": 3}}},
			{"id": "thirty_down", "icon": "shield", "name": {"zh": "三十个", "en": "Thirty Down"}, "desc": {"zh": "单局击倒 30 个敌人。", "en": "Defeat 30 enemies in a single run."}, "when": {"min": {"kills": 30}}},
		],
	},
	{
		"id": "tower_defense",
		"runtime": "tower_defense@1.0.0",
		"name": {"zh": "隘口守卫", "en": "GATEWATCH"},
		"initials": "aksw",
		"genre": {"zh": "塔防", "en": "TOWER DEFENSE"},
		"players": {"min": 1, "max": 1},
		"tagline": {"zh": "沿路布下箭塔与炮台，别让一个敌人走到终点。", "en": "Line the road with towers and let nothing reach the end."},
		"colors": {"title": "FFE9C2", "shadow": "B4561E", "glow": "FFAA50"},
		"art": {"motif": "road", "top": "140B1E", "bottom": "5A2B1C", "primary": "FFAA50", "secondary": "67E8F9"},
		"achievements": [
			{"id": "first_defense", "icon": "bolt", "name": {"zh": "初次布防", "en": "First Defense"}, "desc": {"zh": "完成一局，无论胜负。", "en": "Finish a run, win or lose."}, "when": {}},
			{"id": "gate_held", "icon": "cup", "name": {"zh": "守住隘口", "en": "Gate Held"}, "desc": {"zh": "挡下全部波次。", "en": "Stop every wave."}, "when": {"cleared": true}},
			{"id": "untouched", "icon": "shield", "name": {"zh": "滴水不漏", "en": "Watertight"}, "desc": {"zh": "通关时基地未失一点生命。", "en": "Clear with the base at full health."}, "when": {"cleared": true, "min": {"base_hp": 20}}},
			{"id": "full_sweep", "icon": "star", "name": {"zh": "一个不留", "en": "Full Sweep"}, "desc": {"zh": "单局击倒 27 个敌人。", "en": "Defeat 27 enemies in a single run."}, "when": {"min": {"kills": 27}}},
		],
	},
]

static func all() -> Array[Dictionary]:
	return GAMES

static func ids() -> Array[String]:
	var out: Array[String] = []
	for game in GAMES:
		out.append(str(game["id"]))
	return out

## The entry for an id, or {} when the catalog has no such game (a stale id in the store, for example).
static func by_id(id: String) -> Dictionary:
	for game in GAMES:
		if game["id"] == id:
			return game
	return {}

static func has(id: String) -> bool:
	return not by_id(id).is_empty()

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
	for game in GAMES:
		total += (game["achievements"] as Array).size()
	return total

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
	var minimums: Dictionary = when.get("min", {})
	for field in minimums:
		if float(result.get(field, 0)) < float(minimums[field]):
			return false
	return true
