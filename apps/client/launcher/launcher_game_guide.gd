class_name LauncherGameGuide
extends RefCounted

## What the launcher knows about playing each catalog game: how it is won and lost, which buttons do what, what its HUD shows, the display names of its towers, and the start options its runtime really honours. Pure data plus the lookups over it; the game menu, the in-game HUD and the pause screen all read it, so a control listed in one place cannot drift from another.
##
## Entry fields (keyed by catalog game id):
##   how       { zh, en } one paragraph: goal, how a run ends
##   controls  [{ id, name { zh, en }, actions [InputMap action names], glyphs [LauncherInput actions], pad { zh, en }?, mouse { zh, en }?, performs [GameSession.perform names]? }]
##             `actions` are the real InputMap actions behind the control: the keyboard keys shown for it are read from the InputMap at display time, so a rebound key shows as rebound. `glyphs` are the gamepad buttons drawn for it, `pad` replaces them with words where a glyph cannot say it (the stick), `mouse` names the mouse gesture when there is one, and `performs` lists the runtime commands the control ends up sending.
##   clock     { mode: "countdown" | "elapsed", field?, total? } which snapshot fields the HUD clock reads
##   vital     { field, max, label } the bar under the score
##   stats     [{ label, fields [one or two snapshot fields] }] the cells at the top right; two fields read "a / b"
##   towers    { tower type: { name { zh, en }, note { zh, en } } }
##   options   [{ id, name { zh, en }, note { zh, en }, path (JSON pointer into the runtime's DSL), values, default }]

const In := preload("res://launcher/launcher_input.gd")

## The master volume is the Settings screen's own key (LauncherSettings.VOLUME_MASTER), an integer 0..VOLUME_STEPS. Pause adjusts the same value, so the two screens always agree.
const SETTING_MASTER_VOLUME := LauncherSettings.VOLUME_MASTER
const VOLUME_STEPS := LauncherSettings.VOLUME_STEPS
const VOLUME_DEFAULT := 10
## Store setting prefix of a game's start options: "<prefix><game id>.<option id>".
const SETTING_OPTION_PREFIX := "game_option."

## The runtime reads movement from Godot's built-in ui_* actions.
const MOVE_ACTIONS: Array[StringName] = [&"ui_up", &"ui_down", &"ui_left", &"ui_right"]
const CURSOR_ACTIONS: Array[StringName] = [In.UP, In.DOWN, In.LEFT, In.RIGHT]

const CONTROL_PAUSE := {"id": "pause", "name": {"zh": "暂停", "en": "Pause"}, "actions": [In.MENU, In.BACK], "glyphs": [In.MENU, In.BACK]}
const CONTROL_HUD := {"id": "hud", "name": {"zh": "显示 / 隐藏界面", "en": "Show / hide HUD"}, "actions": [In.Y], "glyphs": [In.Y]}
const CONTROL_MOVE := {"id": "move", "name": {"zh": "移动", "en": "Move"}, "actions": MOVE_ACTIONS, "glyphs": [], "pad": {"zh": "左摇杆 / 十字键", "en": "Left stick / D-pad"}, "performs": ["move"]}

const GUIDES := {
	"shooter": {
		"how": {
			"zh": "武器自动开火，你只管走位。击落全部敌机和首领即通关；生命归零或倒计时结束，本局结束。按住加速时移动更快，击落得分翻倍。护盾抵消下一次伤害，用过后需要冷却。",
			"en": "The weapon fires by itself; you fly. Destroy every enemy and the boss to clear. The run ends when your HP reaches zero or the countdown runs out. Holding boost makes you faster and doubles the score of each kill. The shield absorbs the next hit and then needs to recharge.",
		},
		"controls": [
			CONTROL_MOVE,
			{"id": "boost", "name": {"zh": "加速（按住）", "en": "Boost (hold)"}, "actions": [In.ACCEPT], "glyphs": [In.ACCEPT], "performs": ["boost"]},
			{"id": "shield", "name": {"zh": "护盾", "en": "Shield"}, "actions": [In.X], "glyphs": [In.X], "performs": ["shield"]},
			CONTROL_HUD,
			CONTROL_PAUSE,
		],
		"clock": {"mode": "countdown", "field": "time_left"},
		"vital": {"field": "hp", "max": "max_hp", "label": "launcher.game.hp"},
		"stats": [{"label": "launcher.game.enemies", "fields": ["enemy_left", "enemy_total"]}],
		"options": [
			{
				"id": "difficulty",
				"name": {"zh": "难度", "en": "Difficulty"},
				"note": {"zh": "每高一级，敌机的速度和耐久各提高四分之一个基准值。首领不受影响。", "en": "Each level adds a quarter of the base value to enemy speed and durability. The boss is not affected."},
				"path": "/stage/difficulty",
				"values": [1, 2, 3, 4, 5],
				"default": 2,
			},
		],
	},
	"survivor": {
		"how": {
			"zh": "武器自动攻击，你只管走位。拾取敌人掉落的经验球升级，每次升级依次强化伤害、攻速、弹数和移速。撑到倒计时结束即通关；生命归零则失败。",
			"en": "The weapon attacks by itself; you move. Collect the orbs enemies drop to level up, and each level strengthens damage, attack speed, projectile count and movement speed in turn. Survive until the countdown ends to clear; you lose when your HP reaches zero.",
		},
		"controls": [CONTROL_MOVE, CONTROL_HUD, CONTROL_PAUSE],
		"clock": {"mode": "countdown", "total": "duration", "field": "elapsed"},
		"vital": {"field": "hp", "max": "max_hp", "label": "launcher.game.hp"},
		"stats": [{"label": "launcher.game.level", "fields": ["level"]}, {"label": "launcher.game.kills", "fields": ["kills"]}],
	},
	"tower_defense": {
		"how": {
			"zh": "敌人沿道路走向终点，每漏过一个，基地就掉血。用金币在任意位置放塔，击倒敌人可以拿回金币。挡下全部波次即通关；基地生命归零则失败。",
			"en": "Enemies walk the road to its end, and each one that gets through damages the base. Spend gold to place towers anywhere; defeating enemies earns gold back. Stop every wave to clear; you lose when the base's HP reaches zero.",
		},
		"controls": [
			{"id": "cursor", "name": {"zh": "移动准星", "en": "Move cursor"}, "actions": CURSOR_ACTIONS, "glyphs": [], "pad": {"zh": "左摇杆 / 十字键", "en": "Left stick / D-pad"}, "mouse": {"zh": "移动鼠标", "en": "Mouse"}},
			{"id": "place", "name": {"zh": "放置防御塔", "en": "Place tower"}, "actions": [In.ACCEPT], "glyphs": [In.ACCEPT], "mouse": {"zh": "左键", "en": "Click"}, "performs": ["place_tower"]},
			{"id": "tower", "name": {"zh": "切换防御塔", "en": "Change tower"}, "actions": [In.LB, In.RB, In.X], "glyphs": [In.LB, In.RB, In.X]},
			CONTROL_HUD,
			CONTROL_PAUSE,
		],
		"clock": {"mode": "elapsed", "field": "play_seconds"},
		"vital": {"field": "base_hp", "max": "base_hp_max", "label": "launcher.game.base"},
		"stats": [{"label": "launcher.game.wave", "fields": ["current_wave", "wave_count"]}, {"label": "launcher.game.gold", "fields": ["gold"]}, {"label": "launcher.game.kills", "fields": ["kills"]}],
		"towers": {
			"arrow": {"name": {"zh": "箭塔", "en": "Arrow"}, "note": {"zh": "单体攻击，便宜", "en": "Single target, cheap"}},
			"cannon": {"name": {"zh": "炮塔", "en": "Cannon"}, "note": {"zh": "爆炸波及周围敌人", "en": "Splash damage"}},
			"frost": {"name": {"zh": "冰霜塔", "en": "Frost"}, "note": {"zh": "命中后减速", "en": "Slows on hit"}},
			"laser": {"name": {"zh": "激光塔", "en": "Laser"}, "note": {"zh": "射程远，出手快", "en": "Long range, fast"}},
			"tesla": {"name": {"zh": "电塔", "en": "Tesla"}, "note": {"zh": "电弧连锁两个敌人", "en": "Chains to two more"}},
		},
	},
}

## Seconds of play the launcher makes the player wait between two uses of the shooter's shield. The runtime grants a shield on every request, so without this the button would make the ship untouchable.
const SHIELD_COOLDOWN := 10.0

static func of(game_id: String) -> Dictionary:
	return GUIDES.get(game_id, {})

static func text(entry: Dictionary, field: String, locale: String) -> String:
	var values: Dictionary = entry.get(field, {}) if entry.get(field) is Dictionary else {}
	return str(values.get(locale, values.get("zh", "")))

static func controls(game_id: String) -> Array:
	return of(game_id).get("controls", [])

## The control of a game that sends this GameSession.perform command, or {}.
static func control_for(game_id: String, perform: String) -> Dictionary:
	for control: Dictionary in controls(game_id):
		if perform in (control.get("performs", []) as Array):
			return control
	return {}

## Display name of a tower type: the guide's, or the raw id for a type the guide does not know (a modded DSL).
static func tower_name(game_id: String, tower_type: String, locale: String) -> String:
	var towers: Dictionary = of(game_id).get("towers", {})
	return text(towers[tower_type], "name", locale) if towers.has(tower_type) else tower_type

static func tower_note(game_id: String, tower_type: String, locale: String) -> String:
	var towers: Dictionary = of(game_id).get("towers", {})
	return text(towers[tower_type], "note", locale) if towers.has(tower_type) else ""

# ---- HUD ----

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

## JSON Patch operations that turn the runtime's baseline into the run these option values describe. Unknown ids and values the option does not list are ignored, and a value equal to the baseline's own produces no operation.
static func option_patch(game_id: String, values: Dictionary) -> Array:
	var ops: Array = []
	for option: Dictionary in options(game_id):
		if not values.has(option["id"]):
			continue
		var raw: Variant = values[option["id"]]
		if not (raw is int or raw is float):
			continue
		var value := int(raw)
		if value in (option["values"] as Array) and value != int(option["default"]):
			ops.append({"op": "replace", "path": option["path"], "value": value})
	return ops

# ---- volume ----

static func stored_volume(store: LauncherStore) -> int:
	return int(LauncherSettings.value(store, SETTING_MASTER_VOLUME))

## Apply a 0..VOLUME_STEPS volume to the Master bus. Step 0 is silent through the gain alone; the bus mute flag belongs to the Settings screen's mute row and is left as it is.
static func apply_volume(steps: int) -> void:
	var master := AudioServer.get_bus_index(&"Master")
	AudioServer.set_bus_volume_db(master, linear_to_db(LauncherSettings.step_gain(steps)))
