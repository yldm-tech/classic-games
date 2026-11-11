class_name LauncherPlayers
extends RefCounted

## The local player slots of a game module and the device that drives each one. It turns raw input events into "player N, control C, this hard", which LauncherGameHost passes on through GameSession.set_control; a game never sees a device.
##
## Devices are "kb1" and "kb2" (the two keyboard schemes, InputMap actions game_p1_* and game_p2_*, rebindable in Settings) and "pad:<device id>" for every connected gamepad. With one player, every device drives that player: both keyboard schemes and all gamepads. With two, each slot has exactly one device and input from an unassigned device is ignored.
##
## Gamepads are mapped by position, not by InputMap: d-pad and left stick are the directions, A B X Y the first four buttons, LB and RB the shoulder controls. Start (Menu) is the launcher's pause and never reaches a game.

signal changed

const KEYBOARD_1 := "kb1"
const KEYBOARD_2 := "kb2"
const PAD_PREFIX := "pad:"
## What an action came from, for pause ownership: SOURCE_KEYBOARD (also the mouse) or "pad:<device id>".
const SOURCE_KEYBOARD := "keyboard"
const MAX_PLAYERS := GameSession.MAX_PLAYERS
const STICK_DEADZONE := 0.25

const PAD_BUTTONS := {
	JOY_BUTTON_A: &"a", JOY_BUTTON_B: &"b", JOY_BUTTON_X: &"x", JOY_BUTTON_Y: &"y",
	JOY_BUTTON_LEFT_SHOULDER: &"l", JOY_BUTTON_RIGHT_SHOULDER: &"r",
	JOY_BUTTON_DPAD_UP: &"up", JOY_BUTTON_DPAD_DOWN: &"down", JOY_BUTTON_DPAD_LEFT: &"left", JOY_BUTTON_DPAD_RIGHT: &"right",
}

## How many players the current or next run has.
var count := 1
## Returns the device ids of the connected gamepads. Tests replace it; the default asks the engine.
var pads_provider := func() -> Array[int]: return Input.get_connected_joypads()

var _devices: Array[String] = [KEYBOARD_1, KEYBOARD_2]
## The gamepad that last moved a control of the game, -1 when the keyboard did or nothing has yet. In a one-player run every device plays, so this is the only way to tell that the gamepad just unplugged was the one in the player's hands.
var _last_pad := -1
## "slot/control" -> { source: strength }: a control held from two places (stick and d-pad, or both keyboard schemes in a one-player run) stays held until both let go.
var _held: Dictionary = {}

# ---- assignment ----

func pads() -> Array[int]:
	var out: Array[int] = []
	out.assign(pads_provider.call())
	return out

## Every device a slot could use right now: the two keyboard schemes, then one entry per connected gamepad.
func available_devices() -> Array[String]:
	var out: Array[String] = [KEYBOARD_1, KEYBOARD_2]
	for pad in pads():
		out.append(PAD_PREFIX + str(pad))
	return out

## Set the player count and, when it changed or a slot's gamepad is gone, hand out devices again: with one gamepad, player one keeps the keyboard and player two takes the gamepad; with two or more, each player gets a gamepad; with none, the two keyboard schemes.
func set_count(players: int) -> void:
	var wanted := clampi(players, 1, MAX_PLAYERS)
	var stale := false
	for slot in MAX_PLAYERS:
		stale = stale or not is_device_connected(slot)
	if wanted == count and not stale:
		return
	count = wanted
	assign_defaults()

func assign_defaults() -> void:
	var connected := pads()
	if connected.size() >= 2:
		_devices = [PAD_PREFIX + str(connected[0]), PAD_PREFIX + str(connected[1])]
	elif connected.size() == 1:
		_devices = [KEYBOARD_1, PAD_PREFIX + str(connected[0])]
	else:
		_devices = [KEYBOARD_1, KEYBOARD_2]
	release_all()
	changed.emit()

func device(slot: int) -> String:
	return _devices[clampi(slot, 0, MAX_PLAYERS - 1)]

## Give a slot a device. A device the other slot holds is swapped with it, so two players never share one and neither is left without.
func set_device(slot: int, wanted: String) -> void:
	if slot < 0 or slot >= MAX_PLAYERS or not wanted in available_devices() or _devices[slot] == wanted:
		return
	var other := 1 - slot
	if _devices[other] == wanted:
		_devices[other] = _devices[slot]
	_devices[slot] = wanted
	release_all()
	changed.emit()

## Move a slot to the next (or previous) available device.
func cycle_device(slot: int, step: int) -> void:
	var options := available_devices()
	var index := options.find(device(slot))
	set_device(slot, options[posmod((index if index >= 0 else 0) + step, options.size())])

## Whether the device of a slot is there. A keyboard always is; a gamepad can be unplugged.
func is_device_connected(slot: int) -> bool:
	var name := device(slot)
	return not name.begins_with(PAD_PREFIX) or name.trim_prefix(PAD_PREFIX).to_int() in pads()

## Slots (among the playing ones) whose gamepad is no longer connected.
func disconnected_slots() -> Array[int]:
	var out: Array[int] = []
	if count >= 2:
		for slot in count:
			if not is_device_connected(slot):
				out.append(slot)
	return out

# ---- ownership ----

## Where an event came from: SOURCE_KEYBOARD or "pad:<device id>".
static func source_of(event: InputEvent) -> String:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return PAD_PREFIX + str(event.device)
	return SOURCE_KEYBOARD

## The player a source belongs to. In a one-player run everything is player one. In a two-player run a gamepad belongs to the slot it drives (-1 for an unassigned one) and the keyboard to the first slot that plays on a keyboard scheme.
func slot_of_source(source: String) -> int:
	if count <= 1:
		return 0
	for slot in count:
		var name := device(slot)
		if name == source or (source == SOURCE_KEYBOARD and not name.begins_with(PAD_PREFIX)):
			return slot
	return -1

## Whether input from `source` may act for `slot`: its own device does, and anything does when that device is unplugged, so a pause can never be left without someone able to end it.
func source_controls(source: String, slot: int) -> bool:
	if count <= 1 or slot < 0 or slot >= count or not is_device_connected(slot):
		return true
	var name := device(slot)
	return name == source if name.begins_with(PAD_PREFIX) else source == SOURCE_KEYBOARD

# ---- events ----

## The control changes an event causes: [[slot, control, strength], ...]. Empty for an event that is not game input or belongs to no playing slot.
func translate(event: InputEvent) -> Array:
	var out := _translate(event)
	if not out.is_empty():
		_last_pad = event.device if (event is InputEventJoypadButton or event is InputEventJoypadMotion) else -1
	return out

func _translate(event: InputEvent) -> Array:
	var out: Array = []
	if event is InputEventKey:
		if (event as InputEventKey).echo:
			return out
		for scheme in LauncherInput.GAME_SCHEMES:
			var slot := _slot_of_device(KEYBOARD_1 if scheme == 1 else KEYBOARD_2)
			if slot < 0:
				continue
			for control in GameSession.CONTROLS:
				if InputMap.event_is_action(event, LauncherInput.game_action(scheme, control), true):
					out.append(_hold(slot, control, "kb%d" % scheme, 1.0 if event.is_pressed() else 0.0))
	elif event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		var slot := _slot_of_device(PAD_PREFIX + str(button.device))
		if slot >= 0 and PAD_BUTTONS.has(button.button_index):
			out.append(_hold(slot, PAD_BUTTONS[button.button_index], "pad%d:button" % button.device, 1.0 if button.pressed else 0.0))
	elif event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		var slot := _slot_of_device(PAD_PREFIX + str(motion.device))
		if slot >= 0 and (motion.axis == JOY_AXIS_LEFT_X or motion.axis == JOY_AXIS_LEFT_Y):
			var value := motion.axis_value if absf(motion.axis_value) >= STICK_DEADZONE else 0.0
			var low: StringName = &"left" if motion.axis == JOY_AXIS_LEFT_X else &"up"
			var high: StringName = &"right" if motion.axis == JOY_AXIS_LEFT_X else &"down"
			var source := "pad%d:stick" % motion.device
			out.append(_hold(slot, low, source, maxf(0.0, -value)))
			out.append(_hold(slot, high, source, maxf(0.0, value)))
	return out

## Let go of whatever the gamepads that are no longer connected were holding, and return the control changes that causes, like translate(). A gamepad that is unplugged with its stick pushed over or a button down never sends the event that would let go, in a one-player run as much as in a two-player one.
func release_missing_pads() -> Array:
	var connected := pads()
	var out: Array = []
	for key: String in _held.keys():
		var sources: Dictionary = _held[key]
		var dropped := false
		for source: String in sources.keys():
			# A gamepad's sources are "pad<device id>:button" and "pad<device id>:stick"; the keyboard's are "kb1" and "kb2".
			if source.begins_with("pad") and not source.trim_prefix("pad").get_slice(":", 0).to_int() in connected:
				sources.erase(source)
				dropped = true
		if not dropped:
			continue
		var strongest := 0.0
		for held: float in sources.values():
			strongest = maxf(strongest, held)
		out.append([key.get_slice("/", 0).to_int(), StringName(key.get_slice("/", 1)), strongest])
	return out

## Forget everything held. The caller releases the game's controls itself (GameSession.release_controls).
func release_all() -> void:
	_held.clear()

## Whether the gamepad that was last played on is no longer connected. Asking forgets it, so one unplugging is reported once.
func take_lost_active_pad() -> bool:
	if _last_pad < 0 or _last_pad in pads():
		return false
	_last_pad = -1
	return true

func _slot_of_device(name: String) -> int:
	if count <= 1:
		return 0
	for slot in count:
		if _devices[slot] == name:
			return slot
	return -1

func _hold(slot: int, control: StringName, source: String, strength: float) -> Array:
	var key := "%d/%s" % [slot, control]
	var sources: Dictionary = _held.get(key, {})
	if strength > 0.0:
		sources[source] = strength
	else:
		sources.erase(source)
	_held[key] = sources
	var strongest := 0.0
	for held: float in sources.values():
		strongest = maxf(strongest, held)
	return [slot, control, strongest]
