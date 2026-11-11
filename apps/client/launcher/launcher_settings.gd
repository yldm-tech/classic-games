class_name LauncherSettings
extends RefCounted

## The launcher's settings: their keys in LauncherStore, their defaults and allowed values, and the code that applies them to the engine (window, frame pacing, audio buses). The Settings screen edits them; LauncherRoot applies all of them once at start.
##
## Keys (all under the store's "settings" section):
##   lang          "zh" | "en"                              interface language, applied through LauncherRoot.set_locale
##   clock_24h     bool                                     the shell clock shows 24-hour or 12-hour time
##   default_mode  "console" | "pc"                         the mode the launcher should open in; read by the PC mode at start
##   window_mode   "windowed" | "fullscreen" | "exclusive"  windowed, borderless fullscreen, exclusive fullscreen
##   vsync         bool
##   max_fps       0 | 30 | 60 | 120 | 144                  0 means no cap
##   volume_master 0..10                                    step of the Master bus, 10 = full
##   volume_music  0..10                                    step of the Music bus
##   volume_sfx    0..10                                    step of the SFX bus (the sound effects of game modules)
##   audio_mute    bool                                     mutes the Master bus
##
## Values read from the store are untrusted (the file can be edited by hand): value() returns the default for anything that is not an allowed value.

const Strings := preload("res://i18n/strings.gd")

const LANG := "lang"
const CLOCK_24H := "clock_24h"
const DEFAULT_MODE := "default_mode"
const WINDOW_MODE := "window_mode"
const VSYNC := "vsync"
const MAX_FPS := "max_fps"
const VOLUME_MASTER := "volume_master"
const VOLUME_MUSIC := "volume_music"
const VOLUME_SFX := "volume_sfx"
const AUDIO_MUTE := "audio_mute"

const VOLUME_STEPS := 10
const BUS_MASTER := &"Master"
const BUS_MUSIC := &"Music"
const BUS_SFX := &"SFX"

## The defaults reproduce what the project does with no settings stored.
const DEFAULTS := {
	LANG: "zh",
	CLOCK_24H: true,
	DEFAULT_MODE: "console",
	WINDOW_MODE: "windowed",
	VSYNC: true,
	MAX_FPS: 0,
	VOLUME_MASTER: 10,
	VOLUME_MUSIC: 10,
	VOLUME_SFX: 10,
	AUDIO_MUTE: false,
}

## Allowed values of the settings that are a choice, in the order the screen cycles through them.
const CHOICES := {
	LANG: ["zh", "en"],
	DEFAULT_MODE: ["console", "pc"],
	WINDOW_MODE: ["windowed", "fullscreen", "exclusive"],
	MAX_FPS: [30, 60, 120, 144, 0],
}

## The stored value of a setting, or its default when nothing valid is stored.
static func value(store: LauncherStore, key: String) -> Variant:
	var fallback: Variant = DEFAULTS[key]
	var stored: Variant = store.setting(key)
	if fallback is bool:
		return stored if stored is bool else fallback
	if fallback is int:
		# JSON has one number type, so integers come back from disk as floats.
		if not (stored is int or stored is float):
			return fallback
		var number := int(stored)
		if CHOICES.has(key):
			return number if (CHOICES[key] as Array).has(number) else fallback
		return clampi(number, 0, VOLUME_STEPS)
	return stored if stored is String and (CHOICES[key] as Array).has(stored) else fallback

## Whether this node is the content of the real game window. False in headless runs and when the launcher is mounted in an off-screen viewport (the screenshot script), where window settings must not be applied.
static func drives_window(node: Node) -> bool:
	return DisplayServer.get_name() != "headless" and node.is_inside_tree() and node.get_viewport() == node.get_tree().root

## Apply every engine-facing setting. `window` says whether the window itself may be changed (see drives_window).
static func apply_all(store: LauncherStore, window: bool) -> void:
	for key in [WINDOW_MODE, VSYNC, MAX_FPS, VOLUME_MASTER, VOLUME_MUSIC, VOLUME_SFX, AUDIO_MUTE]:
		apply(store, key, window)

## Apply one setting to the engine. Language and clock are the shell's (LauncherRoot.set_locale, refresh_clock) and default_mode is only read at start, so those keys do nothing here.
static func apply(store: LauncherStore, key: String, window: bool) -> void:
	match key:
		WINDOW_MODE:
			if window:
				var mode := display_mode(str(value(store, WINDOW_MODE)))
				if DisplayServer.window_get_mode() != mode:
					DisplayServer.window_set_mode(mode)
		VSYNC:
			if window:
				DisplayServer.window_set_vsync_mode(vsync_mode(bool(value(store, VSYNC))))
		MAX_FPS:
			Engine.max_fps = int(value(store, MAX_FPS))
		VOLUME_MASTER:
			_set_bus_volume(BUS_MASTER, int(value(store, VOLUME_MASTER)))
		VOLUME_MUSIC:
			_set_bus_volume(BUS_MUSIC, int(value(store, VOLUME_MUSIC)))
		VOLUME_SFX:
			_set_bus_volume(BUS_SFX, int(value(store, VOLUME_SFX)))
		AUDIO_MUTE:
			var bus := AudioServer.get_bus_index(BUS_MASTER)
			if bus >= 0:
				AudioServer.set_bus_mute(bus, bool(value(store, AUDIO_MUTE)))

static func display_mode(window_mode: String) -> DisplayServer.WindowMode:
	match window_mode:
		"fullscreen":
			return DisplayServer.WINDOW_MODE_FULLSCREEN
		"exclusive":
			return DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	return DisplayServer.WINDOW_MODE_WINDOWED

static func vsync_mode(on: bool) -> DisplayServer.VSyncMode:
	return DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED

## Linear gain of a volume step: 0 is silent, VOLUME_STEPS is unity.
static func step_gain(step: int) -> float:
	return float(clampi(step, 0, VOLUME_STEPS)) / float(VOLUME_STEPS)

static func _set_bus_volume(bus_name: StringName, step: int) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(step_gain(step)))

## The shell clock's text: "18:02", or "下午 6:02" / "6:02 PM" in 12-hour form.
static func clock_text(hour: int, minute: int, use_24h: bool, locale: String) -> String:
	if use_24h:
		return "%02d:%02d" % [hour, minute]
	var key := "launcher.settings.clock_pm_fmt" if hour >= 12 else "launcher.settings.clock_am_fmt"
	var short_hour := hour % 12
	return Strings.fmt(locale, key, ["%d:%02d" % [12 if short_hour == 0 else short_hour, minute]])
