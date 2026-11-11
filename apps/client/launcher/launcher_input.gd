class_name LauncherInput
extends RefCounted

## Names of the launcher's input actions (defined in project.godot under [input]) and the two things done with them: turning an InputEvent into one action, and applying stored key overrides.
## Screens never read InputEvents. LauncherRoot translates each press into one of these names and hands it to LauncherScreen.handle_action.

const UP := &"launcher_up"
const DOWN := &"launcher_down"
const LEFT := &"launcher_left"
const RIGHT := &"launcher_right"
const ACCEPT := &"launcher_accept"
const BACK := &"launcher_back"
const X := &"launcher_x"
const Y := &"launcher_y"
const LB := &"launcher_lb"
const RB := &"launcher_rb"
const LT := &"launcher_lt"
const RT := &"launcher_rt"
const MENU := &"launcher_menu"
const VIEW := &"launcher_view"
const PC_MODE := &"launcher_pc_mode"

const ALL: Array[StringName] = [UP, DOWN, LEFT, RIGHT, ACCEPT, BACK, X, Y, LB, RB, LT, RT, MENU, VIEW, PC_MODE]
## Held directions repeat; everything else fires once per press.
const REPEATING: Array[StringName] = [UP, DOWN, LEFT, RIGHT]
## A direction held on the d-pad or a stick repeats like a held key: first after REPEAT_DELAY seconds, then every REPEAT_INTERVAL. LauncherRoot does the timing.
const REPEAT_DELAY := 0.4
const REPEAT_INTERVAL := 0.1

## The keyboard side of a game module's per-player controls: two schemes of InputMap actions, "game_p<scheme>_<control>", defined in project.godot and rebindable like the launcher's own. Which scheme (or gamepad) drives which player is LauncherPlayers' business.
const GAME_SCHEMES: Array[int] = [1, 2]
const GAME_ACTION_FMT := "game_p%d_%s"

static func game_action(scheme: int, control: StringName) -> StringName:
	return StringName(GAME_ACTION_FMT % [scheme, control])

## The ten actions of one keyboard scheme, in GameSession.CONTROLS order.
static func game_actions(scheme: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for control in GameSession.CONTROLS:
		out.append(game_action(scheme, control))
	return out

static func all_game_actions() -> Array[StringName]:
	var out: Array[StringName] = []
	for scheme in GAME_SCHEMES:
		out.append_array(game_actions(scheme))
	return out

static func is_game_action(action: StringName) -> bool:
	return String(action).begins_with("game_p")

## Text drawn inside a glyph for an action. MENU and VIEW are drawn as icons, so they have no entry.
const GLYPH_TEXT := {ACCEPT: "A", BACK: "B", X: "X", Y: "Y", LB: "LB", RB: "RB", LT: "LT", RT: "RT"}

## The action this event presses, or &"" when it is not a launcher press. Keyboard echo counts only for the directions.
static func pressed_action(event: InputEvent) -> StringName:
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return &""
	for action in ALL:
		if event.is_action_pressed(action, action in REPEATING, true):
			return action
	return &""

static func released_action(event: InputEvent) -> StringName:
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return &""
	for action in ALL:
		if event.is_action_released(action, true):
			return action
	return &""

## Replace the keyboard events of each listed action with the stored physical keycodes; gamepad events are left alone. `bindings` is LauncherStore.bindings(). Unknown actions are ignored, so a stale entry cannot break input.
static func apply_bindings(bindings: Dictionary) -> void:
	for action in bindings:
		if not InputMap.has_action(action) or not bindings[action] is Array:
			continue
		var codes := _valid_codes(bindings[action])
		# An entry without one usable key would leave the action unreachable from the keyboard, so it keeps the project default instead.
		if codes.is_empty():
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				InputMap.action_erase_event(action, event)
		for code in codes:
			var key := InputEventKey.new()
			key.physical_keycode = code as Key
			InputMap.action_add_event(action, key)

## Physical keycodes currently bound to an action, for a rebinding screen to display.
static func keycodes(action: StringName) -> Array[int]:
	var out: Array[int] = []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			out.append(int((event as InputEventKey).physical_keycode))
	return out

static func _valid_codes(raw: Array) -> Array[int]:
	var out: Array[int] = []
	for code in raw:
		if (code is int or code is float) and int(code) > 0 and not out.has(int(code)):
			out.append(int(code))
	return out

## Put every action back to its project default, then apply the stored overrides. Use this instead of apply_bindings after an override was removed, since apply_bindings only touches the actions it is given.
static func reset_and_apply(bindings: Dictionary) -> void:
	InputMap.load_from_project_settings()
	apply_bindings(bindings)

## Physical keycodes an action has in project.godot, before any override.
static func default_keycodes(action: StringName) -> Array[int]:
	var out: Array[int] = []
	var entry: Variant = ProjectSettings.get_setting("input/%s" % action)
	if entry is Dictionary:
		for event in entry.get("events", []):
			if event is InputEventKey:
				out.append(int((event as InputEventKey).physical_keycode))
	return out
