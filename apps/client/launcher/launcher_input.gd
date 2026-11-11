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
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				InputMap.action_erase_event(action, event)
		for code in bindings[action]:
			var key := InputEventKey.new()
			key.physical_keycode = int(code) as Key
			InputMap.action_add_event(action, key)

## Physical keycodes currently bound to an action, for a rebinding screen to display.
static func keycodes(action: StringName) -> Array[int]:
	var out: Array[int] = []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			out.append(int((event as InputEventKey).physical_keycode))
	return out
