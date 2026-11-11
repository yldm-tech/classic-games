class_name LauncherGameGuide
extends RefCounted

## What the launcher knows about playing each catalog game: how it is won and lost, which buttons do what, what its HUD shows, the display names of its towers, and the start options it really honours. All of it is read from the game's manifest through LauncherCatalog; this file holds no per-game data, only the lookups. The game menu, the in-game HUD and the pause screen all read it, so a control listed in one place cannot drift from another.
##
## of(game id) returns:
##   kind          "dsl" | "module"
##   how           { zh, en } one paragraph: goal, how a run ends
##   controls      see controls()
##   clock         { mode: "countdown" | "elapsed" | "none", field?, total? } which snapshot fields the HUD clock reads
##   vital         { field, max, label { zh, en } } the bar under the score; read from a player's own fields when the snapshot has them there
##   stats         [{ label { zh, en }, fields [one or two snapshot fields] }] the cells at the top right; two fields read "a / b"
##   player_stats  the same, read from each player's own fields and shown in that player's corner
##   boss          { field, max, label? } the bar shown while the snapshot carries `field`
##   towers        { tower type: { name { zh, en }, note { zh, en } } }
##   options       [{ id, name { zh, en }, note { zh, en }, values, default, labels?, path? (JSON pointer into a DSL runtime's document) }]
##   tuning        { name: number } rules the launcher applies around a DSL runtime

const In := preload("res://launcher/launcher_input.gd")
const Strings := preload("res://i18n/strings.gd")

## The master volume is the Settings screen's own key (LauncherSettings.VOLUME_MASTER), an integer 0..VOLUME_STEPS. Pause adjusts the same value, so the two screens always agree.
const SETTING_MASTER_VOLUME := LauncherSettings.VOLUME_MASTER
const VOLUME_STEPS := LauncherSettings.VOLUME_STEPS
const VOLUME_DEFAULT := 10
## Store setting prefix of a game's start options: "<prefix><game id>.<option id>".
const SETTING_OPTION_PREFIX := "game_option."
## Store setting prefix of the player count last chosen for a game: "<prefix><game id>".
const SETTING_PLAYERS_PREFIX := "game_players."

const KIND_MODULE := GameSession.KIND_MODULE
## The gamepad button drawn for each logical button of a game module (the mapping itself is LauncherPlayers.PAD_BUTTONS).
const MODULE_GLYPHS := {&"a": In.ACCEPT, &"b": In.BACK, &"x": In.X, &"y": In.Y, &"l": In.LB, &"r": In.RB}
const INPUT_MOVE := "move"

static var _cache: Dictionary = {}
static var _cache_generation := -1

static func of(game_id: String) -> Dictionary:
	if _cache_generation != LauncherCatalog.generation:
		_cache.clear()
		_cache_generation = LauncherCatalog.generation
	if not _cache.has(game_id):
		_cache[game_id] = _build(game_id)
	return _cache[game_id]

static func _build(game_id: String) -> Dictionary:
	var entry := LauncherCatalog.by_id(game_id)
	if entry.is_empty():
		return {}
	var hud: Dictionary = entry.get("hud", {})
	var out := {
		"kind": str(entry.get("kind", "")),
		"how": entry.get("how", {}),
		"clock": hud.get("clock", {}),
		"stats": hud.get("stats", []),
		"player_stats": hud.get("player_stats", []),
		"towers": entry.get("towers", {}),
		"options": entry.get("options", []),
		"tuning": entry.get("tuning", {}),
	}
	for key in ["vital", "boss"]:
		if hud.has(key):
			out[key] = hud[key]
	return out

static func is_module(game_id: String) -> bool:
	return str(LauncherCatalog.by_id(game_id).get("kind", "")) == KIND_MODULE

static func text(entry: Dictionary, field: String, locale: String) -> String:
	var values: Dictionary = entry.get(field, {}) if entry.get(field) is Dictionary else {}
	return str(values.get(locale, values.get("zh", "")))

## The controls of a game as [{ id, name { zh, en }, actions [InputMap action names], glyphs [LauncherInput actions], pad { zh, en }?, mouse { zh, en }?, performs [GameSession.perform names]? }].
## `actions` are the real InputMap actions behind the control: the keyboard keys shown for it are read from the InputMap at display time, so a rebound key shows as rebound. `glyphs` are the gamepad buttons drawn for it, `pad` replaces them with words where a glyph cannot say it (the stick), `mouse` names the mouse gesture when there is one.
## A DSL game's manifest lists these directly. A game module's manifest lists logical inputs ("move", "a", ...), which become the keys of the given keyboard scheme (1 or 2) and the fixed gamepad buttons; the pause control, which belongs to the launcher, is added at the end.
static func controls(game_id: String, scheme: int = 1) -> Array:
	var entry := LauncherCatalog.by_id(game_id)
	var out: Array = []
	var module := str(entry.get("kind", "")) == KIND_MODULE
	for control: Dictionary in entry.get("controls", []):
		var actions: Array[StringName] = []
		var glyphs: Array[StringName] = []
		var item := {"id": control["id"], "name": control["name"]}
		if module:
			for input_name: String in control["inputs"]:
				if input_name == INPUT_MOVE:
					for direction in GameSession.DIRECTIONS:
						actions.append(In.game_action(scheme, direction))
					item["pad"] = _both("launcher.game.pad_move")
				else:
					actions.append(In.game_action(scheme, StringName(input_name)))
					if MODULE_GLYPHS.has(StringName(input_name)):
						glyphs.append(MODULE_GLYPHS[StringName(input_name)])
					else:
						item["pad"] = _both("launcher.game.pad_move")
		else:
			for action: String in control.get("actions", []):
				actions.append(StringName(action))
			for glyph: String in control.get("glyphs", []):
				glyphs.append(StringName(glyph))
			for key in ["pad", "mouse", "performs"]:
				if control.has(key):
					item[key] = control[key]
		item["actions"] = actions
		item["glyphs"] = glyphs
		out.append(item)
	if module:
		var pause_actions: Array[StringName] = [In.MENU, In.BACK]
		var pause_glyphs: Array[StringName] = [In.MENU]
		out.append({"id": "pause", "name": _both("launcher.game.control_pause"), "actions": pause_actions, "glyphs": pause_glyphs})
	return out

static func _both(key: String) -> Dictionary:
	return {"zh": Strings.t("zh", key), "en": Strings.t("en", key)}

## The control of a game that sends this GameSession.perform command, or {}.
static func control_for(game_id: String, perform: String) -> Dictionary:
	for control: Dictionary in controls(game_id):
		if perform in (control.get("performs", []) as Array):
			return control
	return {}

## A number from the manifest's `tuning`, or the fallback.
static func tuning(game_id: String, key: String, fallback: float) -> float:
	var values: Dictionary = of(game_id).get("tuning", {})
	return float(values[key]) if values.has(key) else fallback

## Display name of a tower type: the guide's, or the raw id for a type the guide does not know (a modded DSL).
static func tower_name(game_id: String, tower_type: String, locale: String) -> String:
	var towers: Dictionary = of(game_id).get("towers", {})
	return text(towers[tower_type], "name", locale) if towers.has(tower_type) else tower_type

static func tower_note(game_id: String, tower_type: String, locale: String) -> String:
	var towers: Dictionary = of(game_id).get("towers", {})
	return text(towers[tower_type], "note", locale) if towers.has(tower_type) else ""

# ---- players ----

## { min, max } local players of a game.
static func player_range(game_id: String) -> Vector2i:
	var players: Dictionary = LauncherCatalog.by_id(game_id).get("players", {})
	var low := maxi(1, int(players.get("min", 1)))
	return Vector2i(low, clampi(int(players.get("max", low)), low, GameSession.MAX_PLAYERS))

## Whether a second player may join or leave while a run of this game is live.
static func joins_in_progress(game_id: String) -> bool:
	var players: Dictionary = LauncherCatalog.by_id(game_id).get("players", {})
	return player_range(game_id).y > player_range(game_id).x and bool(players.get("join_in_progress", false))

static func players_key(game_id: String) -> String:
	return SETTING_PLAYERS_PREFIX + game_id

## The player count the next run of a game starts with: the one last chosen in its menu, kept inside what the game supports.
static func stored_players(game_id: String, store: LauncherStore) -> int:
	var limits := player_range(game_id)
	var stored: Variant = store.setting(players_key(game_id), limits.x)
	return clampi(int(stored) if (stored is int or stored is float) else limits.x, limits.x, limits.y)

## What a player's device is called: "键盘 · WASD", "键盘 · 方向键", "手柄 1", with a note when the gamepad is unplugged.
static func device_label(device: String, players: LauncherPlayers, locale: String) -> String:
	if device == LauncherPlayers.KEYBOARD_1:
		return Strings.t(locale, "launcher.players.kb1")
	if device == LauncherPlayers.KEYBOARD_2:
		return Strings.t(locale, "launcher.players.kb2")
	var pad := device.trim_prefix(LauncherPlayers.PAD_PREFIX).to_int()
	var label := Strings.fmt(locale, "launcher.players.pad_fmt", [pad + 1])
	return label if pad in players.pads() else Strings.fmt(locale, "launcher.players.disconnected_fmt", [label])

# ---- HUD ----

## Whether the game shows a clock at all.
static func has_clock(game_id: String) -> bool:
	return str((of(game_id).get("clock", {}) as Dictionary).get("mode", "elapsed")) != "none"

## Whether the game's clock counts down to the end of the run rather than up from its start.
static func is_countdown(game_id: String) -> bool:
	return str((of(game_id).get("clock", {}) as Dictionary).get("mode", "elapsed")) == "countdown"

## Seconds the clock shows for this snapshot: what is left for a game with a time limit, time played otherwise.
static func clock_seconds(game_id: String, state: Dictionary) -> float:
	var clock: Dictionary = of(game_id).get("clock", {})
	var value := float(state.get(str(clock.get("field", "play_seconds")), 0.0))
	if clock.has("total"):
		return maxf(0.0, float(state.get(str(clock["total"]), 0.0)) - value)
	return value

## The clock as text. A countdown is rounded up so it reads 00:01 until the moment it ends.
static func clock_text(game_id: String, state: Dictionary) -> String:
	var seconds := clock_seconds(game_id, state)
	return LauncherFormat.clock(ceilf(seconds) if is_countdown(game_id) else seconds)

## One counter of the `stats` list: a single field as a number, two fields as "a / b".
static func stat_text(stat: Dictionary, state: Dictionary) -> String:
	var parts := PackedStringArray()
	for field: String in stat["fields"]:
		parts.append(LauncherFormat.score(int(state.get(field, 0))))
	return " / ".join(parts)

# ---- keys ----

## Short labels of the keyboard keys bound to these InputMap actions, in order, without repeats.
static func key_labels(actions: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for action: StringName in actions:
		if not InputMap.has_action(action):
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				var label := key_label(event as InputEventKey)
				if label != "" and not out.has(label):
					out.append(label)
	return out

static func key_label(event: InputEventKey) -> String:
	var code := event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	match code:
		KEY_UP: return "↑"
		KEY_DOWN: return "↓"
		KEY_LEFT: return "←"
		KEY_RIGHT: return "→"
		KEY_ENTER, KEY_KP_ENTER: return "Enter"
		KEY_ESCAPE: return "Esc"
		KEY_NONE: return ""
	return OS.get_keycode_string(code)

## Whether any of these InputMap actions has a gamepad button or axis bound.
static func has_gamepad_binding(actions: Array) -> bool:
	for action: StringName in actions:
		if not InputMap.has_action(action):
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				return true
	return false

# ---- start options ----

static func options(game_id: String) -> Array:
	return of(game_id).get("options", [])

## What a value of an option is called: the option's own label for it when the manifest gives one, the number otherwise.
static func option_label(option: Dictionary, value: int, locale: String) -> String:
	var labels: Array = option.get("labels", []) if option.get("labels") is Array else []
	var index := (option["values"] as Array).find(value)
	if index >= 0 and index < labels.size() and labels[index] is Dictionary:
		return str((labels[index] as Dictionary).get(locale, labels[index].get("zh", value)))
	return str(value)

## The stored value of every start option of a game, falling back to the option's default when nothing valid is stored.
static func stored_options(game_id: String, store: LauncherStore) -> Dictionary:
	var out := {}
	for option: Dictionary in options(game_id):
		var stored: Variant = store.setting(option_key(game_id, str(option["id"])), option["default"])
		var value := int(stored) if (stored is float or stored is int) else int(option["default"])
		out[option["id"]] = value if value in (option["values"] as Array) else option["default"]
	return out

static func option_key(game_id: String, option_id: String) -> String:
	return "%s%s.%s" % [SETTING_OPTION_PREFIX, game_id, option_id]

## JSON Patch operations that turn a DSL runtime's baseline into the run these option values describe. Unknown ids and values the option does not list are ignored, and a value equal to the baseline's own produces no operation. A game module has no document to patch: it receives the option values themselves.
static func option_patch(game_id: String, values: Dictionary) -> Array:
	var ops: Array = []
	for option: Dictionary in options(game_id):
		if not values.has(option["id"]):
			continue
		var raw: Variant = values[option["id"]]
		if not (raw is int or raw is float):
			continue
		var value := int(raw)
		if option.has("path") and value in (option["values"] as Array) and value != int(option["default"]):
			ops.append({"op": "replace", "path": option["path"], "value": value})
	return ops

# ---- volume ----

static func stored_volume(store: LauncherStore) -> int:
	return int(LauncherSettings.value(store, SETTING_MASTER_VOLUME))

## Apply a 0..VOLUME_STEPS volume to the Master bus. Step 0 is silent through the gain alone; the bus mute flag belongs to the Settings screen's mute row and is left as it is.
static func apply_volume(steps: int) -> void:
	var master := AudioServer.get_bus_index(&"Master")
	AudioServer.set_bus_volume_db(master, linear_to_db(LauncherSettings.step_gain(steps)))
