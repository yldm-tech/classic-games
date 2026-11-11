extends SceneTree

## Headless tests of the Settings screen and what it drives: the settings model and its application to the engine, every row kind, application at start, key rebinding with conflicts and the lock-out guard, restoring defaults, the saves rows (export, import, wipe) and gamepad repeat in the shell. The screen is driven through LauncherRoot.dispatch exactly as a key or gamepad press would.
## Run: make settings-test GODOT=/path/to/godot

const StoreScript := preload("res://launcher/launcher_store.gd")
const S := preload("res://launcher/launcher_settings.gd")
const In := preload("res://launcher/launcher_input.gd")
const Format := preload("res://launcher/launcher_format.gd")

const STORE_PATH := "user://settings-test.json"
const EXPORT_DIR := "user://settings-test-exports"
## 2026-11-11 10:30:00 UTC, the same fixed moment launcher_test uses.
const NOW := 1794393000

var _passed := 0
var _failed := 0

func _initialize() -> void:
	# These tests assert exact shelves, counts and orders, so they pin the three games they were written against: a game added under games/ must not change what they see.
	LauncherCatalog.limit_to(["shooter", "survivor", "tower_defense"])
	_test_model()
	_test_store_profiles()
	await _test_focus()
	await _test_choice_rows()
	await _test_toggle_rows()
	await _test_slider_rows()
	await _test_language()
	await _test_applied_at_start()
	await _test_rebinding()
	await _test_binding_persistence_and_reset()
	await _test_player_keys()
	await _test_effects_volume()
	await _test_saves()
	await _test_about_and_english()
	await _test_gamepad_repeat()
	_reset_engine()
	_remove_files()
	print("settings_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

# ---- model ----

func _test_model() -> void:
	var store := _fresh_store()
	var defaults := true
	for key: String in S.DEFAULTS:
		if S.value(store, key) != S.DEFAULTS[key]:
			defaults = false
	_check("an empty store reads as the defaults", defaults)
	store.set_setting(S.MAX_FPS, 77)
	store.set_setting(S.VOLUME_MASTER, "loud")
	store.set_setting(S.VOLUME_MUSIC, 99)
	store.set_setting(S.WINDOW_MODE, "holographic")
	store.set_setting(S.VSYNC, "yes")
	store.set_setting(S.LANG, "ja")
	_check("values that are not allowed fall back or are clamped", S.value(store, S.MAX_FPS) == 0 and S.value(store, S.VOLUME_MASTER) == 10 and S.value(store, S.VOLUME_MUSIC) == 10 and S.value(store, S.WINDOW_MODE) == "windowed" and S.value(store, S.VSYNC) == true and S.value(store, S.LANG) == "zh")
	store.set_setting(S.MAX_FPS, 60.0)
	_check("numbers read back from JSON as floats are accepted", S.value(store, S.MAX_FPS) == 60)
	_check("window modes map to the display server's", S.display_mode("windowed") == DisplayServer.WINDOW_MODE_WINDOWED and S.display_mode("fullscreen") == DisplayServer.WINDOW_MODE_FULLSCREEN and S.display_mode("exclusive") == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN and S.display_mode("nonsense") == DisplayServer.WINDOW_MODE_WINDOWED)
	_check("vsync maps to the display server's", S.vsync_mode(true) == DisplayServer.VSYNC_ENABLED and S.vsync_mode(false) == DisplayServer.VSYNC_DISABLED)
	_check("the window is never driven in a headless run", not S.drives_window(root))
	_check("volume steps are a linear gain", is_zero_approx(S.step_gain(0)) and is_equal_approx(S.step_gain(5), 0.5) and is_equal_approx(S.step_gain(10), 1.0) and is_equal_approx(S.step_gain(40), 1.0))
	_check("24-hour clock", S.clock_text(0, 5, true, "zh") == "00:05" and S.clock_text(18, 2, true, "en") == "18:02")
	_check("12-hour clock in both languages", S.clock_text(0, 5, false, "zh") == "上午 12:05" and S.clock_text(18, 2, false, "zh") == "下午 6:02" and S.clock_text(12, 0, false, "en") == "12:00 PM" and S.clock_text(9, 30, false, "en") == "9:30 AM")
	_check("the project has a Music bus that feeds Master", AudioServer.get_bus_index(S.BUS_MUSIC) > 0 and AudioServer.get_bus_send(AudioServer.get_bus_index(S.BUS_MUSIC)) == S.BUS_MASTER)

func _test_store_profiles() -> void:
	var store := _fresh_store()
	store.record_run("shooter", {"score": 700, "play_seconds": 90.0, "cleared": true}, NOW)
	store.unlock("shooter", "first_sortie", NOW)
	store.set_favorite("survivor", true)
	store.set_setting(S.MAX_FPS, 60)
	DirAccess.make_dir_recursive_absolute(EXPORT_DIR)
	var target := EXPORT_DIR.path_join("profile.json")
	_check("a profile exports to a file", store.export_to(target) and FileAccess.file_exists(target))
	_check("exporting to a folder that does not exist reports failure", not store.export_to("user://no-such-folder/profile.json"))
	var read := StoreScript.read_profile(target)
	_check("an exported profile reads back whole", read.get("recents") == ["shooter"] and read.get("favorites") == ["survivor"] and int((read["stats"] as Dictionary)["shooter"]["best_score"]) == 700 and (read["achievements"] as Dictionary)["shooter"].has("first_sortie"))
	_write(target, JSON.stringify({"version": StoreScript.VERSION + 1, "recents": ["shooter"]}))
	_check("a profile from a newer version is refused", StoreScript.read_profile(target).is_empty())
	_write(target, "{ not json")
	_check("an unreadable or missing profile is refused", StoreScript.read_profile(target).is_empty() and StoreScript.read_profile(EXPORT_DIR.path_join("missing.json")).is_empty())
	var before := store.progress()
	store.wipe_progress()
	_check("progress() is a copy the wipe does not reach", (before["recents"] as Array) == ["shooter"] and store.recents().is_empty())
	var sections: Array[StringName] = []
	store.changed.connect(func(section: StringName) -> void: sections.append(section))
	store.replace_progress(before)
	_check("replacing progress restores it, announces it and keeps settings", store.recents() == ["shooter"] and store.is_favorite("survivor") and store.is_unlocked("shooter", "first_sortie") and int(store.stats("shooter")["best_score"]) == 700 and S.value(store, S.MAX_FPS) == 60 and sections.has(StoreScript.SECTION_STATS) and sections.has(StoreScript.SECTION_ACHIEVEMENTS))
	store.replace_progress({"favorites": "nope", "recents": ["shooter", 3], "stats": {"shooter": "broken"}})
	_check("replacing progress normalises what it is given", store.favorites().is_empty() and store.recents() == ["shooter"] and not store.has_played("shooter") and store.unlocked_count() == 0)
	var reloaded := StoreScript.new(STORE_PATH)
	reloaded.load_from_disk()
	_check("the replaced progress is on disk", reloaded.recents() == ["shooter"] and reloaded.favorites().is_empty())

# ---- screen: focus ----

func _test_focus() -> void:
	var shell := _boot(_fresh_store())
	await _frames(2)
	shell.go(&"settings")
	var screen := shell.current_screen() as LauncherSettingsScreen
	_check("the settings tab opens the settings screen with the navigation", screen != null and shell.find_child("Nav", false, false).visible and shell.find_child("Tab_settings", true, false).selected and shell.backdrop_layer() == &"blur")
	_check("it lists the seven categories in order", _category_labels(screen) == PackedStringArray(["常规", "画面", "声音", "控制", "玩家按键", "存档", "关于"]))
	_check("focus starts on the first category with no row focused", screen.zone == &"categories" and screen.category == 0 and screen.find_child("Category_general", true, false).focused and not _row(screen, "lang").focused and screen.find_child("Title", true, false).text == "常规")
	_check("the help panel describes the category", screen.find_child("HelpTitle", true, false).text == "常规" and screen.help_text() == "语言、时钟和启动时进入的模式。")
	_check("the footer offers select, restore and back", screen.footer_captions() == PackedStringArray(["选择", "恢复本页默认", "返回"]))
	_check("general lists language, clock and launch mode", _row_ids(screen) == ["lang", "clock_24h", "default_mode"])

	shell.dispatch(In.DOWN)
	_check("down selects the next category and shows its rows", screen.category == 1 and screen.find_child("Category_display", true, false).focused and not screen.find_child("Category_general", true, false).focused and screen.find_child("Title", true, false).text == "画面" and _row_ids(screen) == ["window_mode", "vsync", "max_fps"])
	shell.dispatch(In.UP)
	shell.dispatch(In.UP)
	_check("the category list stops at its ends", screen.category == 0)
	for i in 8:
		shell.dispatch(In.DOWN)
	_check("and at the last one", screen.category == 6 and _row_ids(screen) == ["version", "engine", "license", "art", "repo", "games"])
	_check("a page with nothing to restore has no restore hint", screen.footer_captions() == PackedStringArray(["选择", "返回"]))
	screen.find_child("Category_audio", true, false).hovered.emit()
	_check("hovering a category selects it", screen.category == 2 and _row_ids(screen) == ["volume_master", "volume_music", "volume_sfx", "audio_mute"])
	screen.find_child("Category_general", true, false).activated.emit()
	_check("clicking a category selects it", screen.category == 0 and screen.zone == &"categories")

	shell.dispatch(In.RIGHT)
	_check("right moves focus into the rows", screen.zone == &"rows" and screen.row == 0 and _row(screen, "lang").focused and screen.find_child("Category_general", true, false).focused)
	_check("the help panel follows the focused row", screen.find_child("HelpTitle", true, false).text == "语言" and screen.help_text().begins_with("界面文字的语言"))
	_check("the footer names what A does on the row", screen.footer_captions() == PackedStringArray(["切换", "恢复本页默认", "返回"]))
	shell.dispatch(In.DOWN)
	_check("down moves to the next row", screen.row == 1 and _row(screen, "clock_24h").focused and not _row(screen, "lang").focused and screen.footer_captions()[0] == "开关")
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	_check("the rows stop at the last one", screen.row == 2)
	shell.dispatch(In.UP)
	shell.dispatch(In.UP)
	shell.dispatch(In.UP)
	_check("and at the first", screen.row == 0)
	_row(screen, "default_mode").hovered.emit()
	_check("hovering a row focuses it", screen.zone == &"rows" and screen.row == 2 and _row(screen, "default_mode").focused)
	shell.dispatch(In.BACK)
	_check("back returns from the rows to the categories", shell.current_id() == &"settings" and screen.zone == &"categories" and not _row(screen, "default_mode").focused)
	shell.dispatch(In.ACCEPT)
	_check("accept on a category also enters its rows", screen.zone == &"rows")
	shell.dispatch(In.RB)
	_check("the shoulder buttons still switch tabs", shell.current_id() == &"home")
	shell.dispatch(In.LB)
	_check("coming back starts on the categories and keeps the category", shell.current_id() == &"settings" and screen.zone == &"categories" and screen.category == 0)
	shell.dispatch(In.BACK)
	_check("back from the categories leaves the screen", shell.current_id() == &"home")
	shell.go(&"settings", {"category": "controls"})
	_check("a caller can open a given category", screen.category == 3 and screen.find_child("Title", true, false).text == "控制")
	shell.free()
	_reset_engine()

# ---- screen: row kinds ----

func _test_choice_rows() -> void:
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	shell.go(&"settings", {"category": "display"})
	var screen := shell.current_screen() as LauncherSettingsScreen
	shell.dispatch(In.RIGHT)
	var window_row := _row(screen, "window_mode")
	_check("a choice row shows the current option", window_row.kind == &"choice" and window_row.value_text() == "窗口化")
	shell.dispatch(In.RIGHT)
	_check("right picks the next option and stores it", store.setting(S.WINDOW_MODE) == "fullscreen" and window_row.value_text() == "无边框全屏")
	shell.dispatch(In.LEFT)
	shell.dispatch(In.LEFT)
	_check("left goes back and wraps around", store.setting(S.WINDOW_MODE) == "exclusive" and window_row.value_text() == "独占全屏")
	shell.dispatch(In.ACCEPT)
	_check("accept picks the next option too", store.setting(S.WINDOW_MODE) == "windowed")
	window_row.find_child("Next", true, false).activated.emit()
	_check("clicking an arrow steps the option", store.setting(S.WINDOW_MODE) == "fullscreen" and screen.row == 0)
	window_row.find_child("Previous", true, false).activated.emit()
	_check("in either direction", store.setting(S.WINDOW_MODE) == "windowed")
	window_row.activated.emit()
	_check("clicking the row itself steps forward", store.setting(S.WINDOW_MODE) == "fullscreen")
	_check("the choice is on disk", _reload().setting(S.WINDOW_MODE) == "fullscreen")

	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	var fps_row := _row(screen, "max_fps")
	_check("frame cap starts unlimited", fps_row.value_text() == "不限" and Engine.max_fps == 0)
	shell.dispatch(In.RIGHT)
	_check("changing the frame cap applies it to the engine at once", Engine.max_fps == 30 and fps_row.value_text() == "30" and int(_reload().setting(S.MAX_FPS)) == 30)
	shell.dispatch(In.RIGHT)
	_check("each option is a real cap", Engine.max_fps == 60 and fps_row.value_text() == "60")
	shell.dispatch(In.X)
	_check("X restores the page's defaults and says so", store.setting(S.WINDOW_MODE) == "windowed" and Engine.max_fps == 0 and fps_row.value_text() == "不限" and window_row.value_text() == "窗口化" and shell.toast_text() == "已恢复本页默认设置" and shell.can_undo())
	shell.dispatch(In.X)
	_check("X again undoes the restore while the toast is up", store.setting(S.WINDOW_MODE) == "fullscreen" and Engine.max_fps == 60 and fps_row.value_text() == "60" and window_row.value_text() == "无边框全屏")
	shell.free()
	_reset_engine()

func _test_toggle_rows() -> void:
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	shell.go(&"settings", {"category": "display"})
	var screen := shell.current_screen() as LauncherSettingsScreen
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.DOWN)
	var vsync_row := _row(screen, "vsync")
	_check("a toggle row shows its state", vsync_row.kind == &"toggle" and vsync_row.is_on() and vsync_row.value_text() == "开")
	shell.dispatch(In.ACCEPT)
	_check("accept flips it and stores it", store.setting(S.VSYNC) == false and not vsync_row.is_on() and vsync_row.value_text() == "关" and _reload().setting(S.VSYNC) == false)
	shell.dispatch(In.RIGHT)
	_check("right turns it on", store.setting(S.VSYNC) == true and vsync_row.is_on())
	shell.dispatch(In.RIGHT)
	_check("right again leaves it on", store.setting(S.VSYNC) == true)
	shell.dispatch(In.LEFT)
	_check("left turns it off", store.setting(S.VSYNC) == false)
	vsync_row.activated.emit()
	_check("clicking the row flips it", store.setting(S.VSYNC) == true and vsync_row.is_on())

	shell.go(&"settings", {"category": "general"})
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.DOWN)
	var clock := shell.clock_text()
	_check("the clock starts in 24-hour form", clock.length() == 5 and clock[2] == ":")
	shell.dispatch(In.ACCEPT)
	_check("turning 24-hour off changes the shell clock at once", store.setting(S.CLOCK_24H) == false and (shell.clock_text().begins_with("上午 ") or shell.clock_text().begins_with("下午 ")))
	shell.dispatch(In.ACCEPT)
	_check("and back", store.setting(S.CLOCK_24H) == true and shell.clock_text().length() == 5)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.RIGHT)
	_check("the launch mode is stored under default_mode for the PC mode to read", store.setting("default_mode") == "pc" and _row(screen, "default_mode").value_text() == "PC 模式" and _reload().setting("default_mode") == "pc")

	shell.go(&"settings", {"category": "audio"})
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.ACCEPT)
	_check("mute silences the Master bus", store.setting(S.AUDIO_MUTE) == true and AudioServer.is_bus_mute(0) and _row(screen, "audio_mute").is_on())
	shell.dispatch(In.ACCEPT)
	_check("and unmutes it", not AudioServer.is_bus_mute(0))
	shell.free()
	_reset_engine()

func _test_slider_rows() -> void:
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	shell.go(&"settings", {"category": "audio"})
	var screen := shell.current_screen() as LauncherSettingsScreen
	shell.dispatch(In.RIGHT)
	var master := _row(screen, "volume_master")
	var music_bus := AudioServer.get_bus_index(S.BUS_MUSIC)
	_check("a slider row shows its step and has no accept action", master.kind == &"slider" and master.step() == 10 and master.value_text() == "10" and screen.footer_captions() == PackedStringArray(["恢复本页默认", "返回"]))
	shell.dispatch(In.RIGHT)
	_check("a slider stops at its top", master.step() == 10 and store.setting(S.VOLUME_MASTER) == null)
	shell.dispatch(In.LEFT)
	shell.dispatch(In.LEFT)
	_check("left lowers the Master bus one step at a time", master.step() == 8 and int(store.setting(S.VOLUME_MASTER)) == 8 and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)), 0.8) and int(_reload().setting(S.VOLUME_MASTER)) == 8)
	shell.dispatch(In.ACCEPT)
	_check("accept does nothing on a slider", master.step() == 8)
	for i in 12:
		shell.dispatch(In.LEFT)
	_check("a slider stops at zero, which is silent", master.step() == 0 and is_zero_approx(db_to_linear(AudioServer.get_bus_volume_db(0))))
	shell.dispatch(In.DOWN)
	var music := _row(screen, "volume_music")
	music.find_child("Segments", true, false).get_child(3).activated.emit()
	_check("clicking a block sets the Music bus to that step", music.step() == 4 and int(store.setting(S.VOLUME_MUSIC)) == 4 and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(music_bus)), 0.4) and screen.row == 1)
	music.find_child("Segments", true, false).get_child(3).activated.emit()
	_check("clicking the last filled block steps one down", music.step() == 3)
	shell.dispatch(In.X)
	_check("restoring the page brings both buses back to full", master.step() == 10 and music.step() == 10 and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)), 1.0) and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(music_bus)), 1.0))
	shell.free()
	_reset_engine()

func _test_language() -> void:
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	shell.go(&"settings")
	var first := shell.current_screen() as LauncherSettingsScreen
	shell.dispatch(In.RIGHT)
	_check("language starts as Chinese", _row(first, "lang").value_text() == "简体中文")
	shell.dispatch(In.RIGHT)
	await _frames(2)
	var screen := shell.current_screen() as LauncherSettingsScreen
	_check("changing the language switches the shell and stores it", shell.locale == "en" and store.setting(S.LANG) == "en" and _reload().setting(S.LANG) == "en")
	_check("the screen is rebuilt in English where it was", screen != first and shell.current_id() == &"settings" and screen.zone == &"rows" and screen.category == 0 and screen.row == 0 and _row(screen, "lang").focused and screen.find_child("Title", true, false).text == "General" and _row(screen, "lang").label_text() == "Language" and _row(screen, "lang").value_text() == "English")
	_check("the navigation is English too", shell.find_child("Tab_settings", true, false).find_child("Label", true, false).text == "Settings")
	shell.dispatch(In.DOWN)
	shell.dispatch(In.ACCEPT)
	_check("the 12-hour clock follows the language", shell.clock_text().ends_with(" AM") or shell.clock_text().ends_with(" PM"))
	shell.dispatch(In.X)
	await _frames(2)
	screen = shell.current_screen() as LauncherSettingsScreen
	_check("restoring the page puts the language back as well", shell.locale == "zh" and store.setting(S.CLOCK_24H) == true and screen.find_child("Title", true, false).text == "常规" and screen.row == 1 and screen.zone == &"rows")
	shell.undo()
	await _frames(2)
	screen = shell.current_screen() as LauncherSettingsScreen
	_check("and the undo survives the rebuild", shell.locale == "en" and store.setting(S.CLOCK_24H) == false and screen.find_child("Title", true, false).text == "General" and _row(screen, "clock_24h").value_text() == "Off")
	shell.free()
	_reset_engine()

func _test_applied_at_start() -> void:
	var store := _fresh_store()
	store.set_setting(S.LANG, "en")
	store.set_setting(S.CLOCK_24H, false)
	store.set_setting(S.WINDOW_MODE, "fullscreen")
	store.set_setting(S.VSYNC, false)
	store.set_setting(S.MAX_FPS, 30)
	store.set_setting(S.VOLUME_MASTER, 5)
	store.set_setting(S.VOLUME_MUSIC, 2)
	store.set_setting(S.AUDIO_MUTE, true)
	store.set_binding("launcher_accept", [KEY_J])
	store.set_binding("launcher_back", [])
	_reset_engine()
	# A second store reads the file, as a real start would.
	var shell := _boot(_reload())
	await _frames(2)
	var music_bus := AudioServer.get_bus_index(S.BUS_MUSIC)
	_check("the stored frame cap is applied at start", Engine.max_fps == 30)
	_check("the stored volumes and mute are applied at start", is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)), 0.5) and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(music_bus)), 0.2) and AudioServer.is_bus_mute(0))
	_check("the stored language and clock form are applied at start", shell.locale == "en" and (shell.clock_text().ends_with(" AM") or shell.clock_text().ends_with(" PM")))
	_check("stored key bindings are applied at start", In.keycodes(In.ACCEPT) == [KEY_J] and In.pressed_action(_key(KEY_J)) == In.ACCEPT and In.pressed_action(_key(KEY_ENTER)) == &"")
	_check("a stored binding without a key cannot take an action off the keyboard", In.keycodes(In.BACK).has(KEY_ESCAPE))
	shell.go(&"settings", {"category": "display"})
	var screen := shell.current_screen() as LauncherSettingsScreen
	_check("the screen shows the stored display values", _row(screen, "window_mode").value_text() == "Borderless fullscreen" and not _row(screen, "vsync").is_on() and _row(screen, "max_fps").value_text() == "30")
	_check("fullscreen is stored but not applied to a headless run", not S.drives_window(shell) and DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN)
	shell.go(&"settings", {"category": "audio"})
	_check("and the stored audio values", _row(screen, "volume_master").step() == 5 and _row(screen, "volume_music").step() == 2 and _row(screen, "audio_mute").is_on())
	shell.free()
	_reset_engine()

# ---- rebinding ----

func _test_rebinding() -> void:
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	shell.go(&"settings", {"category": "controls"})
	var screen := shell.current_screen() as LauncherSettingsScreen
	_check("controls lists every launcher action", _row_ids(screen).size() == In.ALL.size() and _row_ids(screen)[4] == "bind_accept")
	var accept_row := _row(screen, "bind_accept")
	_check("a binding row shows the current keys and a rebind button", accept_row.value_text() == "Enter / Kp Enter / Space" and accept_row.button_text() == "改键")
	shell.dispatch(In.RIGHT)
	for i in 4:
		shell.dispatch(In.DOWN)
	_check("its help lists the keyboard keys and the fixed gamepad button", screen.row == 4 and screen.help_text().contains("键盘：Enter / Kp Enter / Space") and screen.help_text().contains("手柄：A（固定）"))
	_check("the gamepad reference comes from the input map", screen.pad_names(In.UP) == "十字键 ↑ / 左摇杆 ↑" and screen.pad_names(In.LT) == "LT" and screen.pad_names(In.VIEW) == "View" and screen.pad_names(In.PC_MODE) == "长按 View")

	shell.dispatch(In.ACCEPT)
	var capture := shell.find_child("KeyCapture", true, false)
	_check("accept opens the key capture", screen.is_capturing() and shell.has_overlay() and capture != null and shell.find_child("DialogTitle", true, false).text == "为「确认（A）」设置按键" and screen.footer_captions() == PackedStringArray(["取消"]))
	shell.dispatch(In.DOWN)
	shell.dispatch(In.RB)
	_check("the capture is modal", screen.is_capturing() and screen.row == 4 and shell.current_id() == &"settings")
	shell.dispatch(In.BACK)
	_check("B on the gamepad cancels it", not screen.is_capturing() and not shell.has_overlay() and screen.zone == &"rows" and store.bindings().is_empty())

	shell.dispatch(In.ACCEPT)
	capture = shell.find_child("KeyCapture", true, false)
	capture._input(_key(KEY_ESCAPE))
	_check("Escape cancels it and is not bound", not screen.is_capturing() and store.bindings().is_empty() and In.keycodes(In.BACK).has(KEY_ESCAPE))

	shell.dispatch(In.ACCEPT)
	screen.capture_key(KEY_SHIFT)
	_check("a modifier on its own is refused and the capture goes on", screen.is_capturing() and shell.toast_text() == "这个键不能单独用作按键" and store.bindings().is_empty())
	capture = shell.find_child("KeyCapture", true, false)
	var echo := _key(KEY_J)
	echo.echo = true
	capture._input(echo)
	var released := _key(KEY_J)
	released.pressed = false
	capture._input(released)
	_check("key repeats and releases are not captured", screen.is_capturing())
	capture._input(_key(KEY_J))
	_check("a free key is bound at once and replaces the old keys", not screen.is_capturing() and In.keycodes(In.ACCEPT) == [KEY_J] and store.bindings() == {"launcher_accept": [KEY_J]} and accept_row.value_text() == "J" and shell.toast_text() == "「确认（A）」已改为 J")
	_check("the new key works and the old ones do not", In.pressed_action(_key(KEY_J)) == In.ACCEPT and In.pressed_action(_key(KEY_ENTER)) == &"" and _has_button(In.ACCEPT, JOY_BUTTON_A))
	shell._unhandled_input(_key(KEY_DOWN))
	_check("the screen keeps working after a rebinding", screen.row == 5)

	# Back wants J, which is Confirm's only key: Confirm must take over Back's old keys.
	shell.dispatch(In.ACCEPT)
	screen.capture_key(KEY_J)
	_check("a key another action uses opens the conflict dialog", screen.is_dialog_open() and not screen.is_capturing() and shell.find_child("ConflictDialog", true, false) != null and screen.dialog_labels() == PackedStringArray(["取消", "替换"]))
	_check("the dialog explains the swap", shell.find_child("DialogBody", true, false).text == "J 已用于「确认（A）」。替换后，「确认（A）」会改用 Escape / Backspace。")
	_check("its focus starts on cancel", screen.dialog_focus() == 0)
	shell.dispatch(In.ACCEPT)
	_check("cancelling changes nothing", not screen.is_dialog_open() and In.keycodes(In.BACK) == [KEY_ESCAPE, KEY_BACKSPACE] and In.keycodes(In.ACCEPT) == [KEY_J])
	shell.dispatch(In.ACCEPT)
	screen.capture_key(KEY_J)
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.ACCEPT)
	_check("replacing swaps the keys so neither action is left without one", In.keycodes(In.BACK) == [KEY_J] and In.keycodes(In.ACCEPT) == [KEY_ESCAPE, KEY_BACKSPACE] and store.bindings() == {"launcher_accept": [KEY_ESCAPE, KEY_BACKSPACE], "launcher_back": [KEY_J]})
	_check("the rows show the swapped keys", accept_row.value_text() == "Escape / Backspace" and _row(screen, "bind_back").value_text() == "J")

	# X wants Escape, one of Confirm's two keys: Confirm keeps the other.
	shell.dispatch(In.DOWN)
	shell._unhandled_input(_key(KEY_ESCAPE))
	_check("the swapped key now confirms", screen.is_capturing())
	screen.capture_key(KEY_BACKSPACE)
	_check("taking one of several keys says which ones remain", screen.is_dialog_open() and shell.find_child("DialogBody", true, false).text == "Backspace 已用于「确认（A）」。替换后，「确认（A）」仍可使用 Escape。")
	shell.dispatch(In.DOWN)
	shell.dispatch(In.ACCEPT)
	_check("replacing takes only that key", In.keycodes(In.X) == [KEY_BACKSPACE] and In.keycodes(In.ACCEPT) == [KEY_ESCAPE])

	var reachable := true
	var owners := {}
	for action in In.ALL:
		if In.keycodes(action).is_empty():
			reachable = false
		for code in In.keycodes(action):
			if owners.has(code):
				reachable = false
			owners[code] = action
	_check("after every rebinding each action still has a key and no key is shared", reachable)

	_row(screen, "bind_x").activated.emit()
	screen.capture_key(KEY_X)
	_check("binding an action back to its default key drops the override", In.keycodes(In.X) == [KEY_X] and not store.bindings().has("launcher_x"))
	_row(screen, "bind_y").activated.emit()
	_check("clicking a row starts its capture", screen.is_capturing() and screen.row == 7)
	shell.find_child("Scrim", true, false).activated.emit()
	_check("clicking outside cancels it", not screen.is_capturing())
	shell.free()
	_reset_engine()

func _test_binding_persistence_and_reset() -> void:
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	shell.go(&"settings", {"category": "controls"})
	var screen := shell.current_screen() as LauncherSettingsScreen
	screen.begin_capture(In.MENU)
	screen.capture_key(KEY_N)
	screen.begin_capture(In.DOWN)
	screen.capture_key(KEY_S)
	shell.free()
	_reset_engine()
	_check("resetting the input map alone forgets the keys", In.keycodes(In.MENU) == [KEY_M])

	shell = _boot(_reload())
	await _frames(2)
	_check("rebound keys are applied again at the next start", In.keycodes(In.MENU) == [KEY_N] and In.keycodes(In.DOWN) == [KEY_S] and In.pressed_action(_key(KEY_S)) == In.DOWN)
	shell.go(&"settings", {"category": "controls"})
	screen = shell.current_screen() as LauncherSettingsScreen
	_check("and shown", _row(screen, "bind_menu").value_text() == "N" and _row(screen, "bind_down").value_text() == "S")
	shell.dispatch(In.RIGHT)
	for i in 12:
		shell.dispatch(In.DOWN)
	var list := screen.find_child("Rows", true, false)
	_check("the list scrolls to keep the focused row in view", screen.row == 12 and list.first_visible == 3 and is_equal_approx(list.column.position.y, -3.0 * LauncherTokens.SETTING_ROW_HEIGHT))
	_row(screen, "bind_view").hovered.emit()
	_check("a row that slides under a resting pointer does not take focus", screen.row == 12)
	await _frames(4)
	_row(screen, "bind_view").hovered.emit()
	_check("once the list is at rest hover focuses again", screen.row == 13)
	for i in 13:
		shell.dispatch(In.UP)
	_check("and back to the top", screen.row == 0 and list.first_visible == 0)
	await _frames(4)
	list.wheel.emit(1)
	_row(screen, "bind_left").hovered.emit()
	_check("the mouse wheel scrolls it without moving focus", list.first_visible == 1 and screen.row == 0)

	_check("controls can be restored", screen.footer_captions().has("恢复本页默认"))
	shell.dispatch(In.X)
	_check("X restores the default keys and says so", shell.store.bindings().is_empty() and In.keycodes(In.MENU) == [KEY_M] and In.keycodes(In.DOWN) == [KEY_DOWN] and _row(screen, "bind_menu").value_text() == "M" and shell.toast_text() == "已恢复默认按键" and shell.can_undo())
	_check("the defaults are on disk", _reload().bindings().is_empty())
	shell.undo()
	_check("undo brings the custom keys back", In.keycodes(In.MENU) == [KEY_N] and In.keycodes(In.DOWN) == [KEY_S] and shell.store.bindings() == {"launcher_menu": [KEY_N], "launcher_down": [KEY_S]} and _row(screen, "bind_menu").value_text() == "N")
	shell.free()
	_reset_engine()

# ---- saves ----

func _test_saves() -> void:
	_remove_files()
	var store := _fresh_store()
	store.record_run("shooter", {"score": 700, "play_seconds": 300.0, "cleared": true}, NOW - 600)
	store.record_run("survivor", {"score": 40, "play_seconds": 120.0}, NOW - 300)
	store.record_run("survivor", {"score": 90, "play_seconds": 240.0}, NOW - 100)
	store.unlock("shooter", "first_sortie", NOW - 600)
	store.unlock("survivor", "first_watch", NOW - 300)
	store.unlock("survivor", "stale_id_from_an_old_build", NOW - 300)
	store.set_favorite("shooter", true)
	store.set_setting(S.MAX_FPS, 120)
	var shell := _boot(store)
	await _frames(2)
	shell.go(&"settings", {"category": "saves"})
	var screen := shell.current_screen() as LauncherSettingsScreen
	screen.export_dir = EXPORT_DIR
	_check("saves lists the totals, the file and the three actions", _row_ids(screen) == ["play_time", "runs", "achievements", "file", "export", "import", "wipe"])
	_check("the totals are sums of the real records", _row(screen, "play_time").value_text() == "11m" and _row(screen, "runs").value_text() == "3 局" and _row(screen, "achievements").value_text() == "2 / 11")
	_check("the profile file is named", _row(screen, "file").kind == &"info" and _row(screen, "file").value_text() == "settings-test.json")
	shell.dispatch(In.RIGHT)
	for i in 3:
		shell.dispatch(In.DOWN)
	_check("its help says where the file is", screen.help_text().ends_with("settings-test.json") and screen.help_text().contains(OS.get_user_data_dir().get_file()) and screen.footer_captions() == PackedStringArray(["返回"]))
	shell.dispatch(In.ACCEPT)
	shell.dispatch(In.RIGHT)
	_check("an info row has nothing to change", shell.current_id() == &"settings" and not screen.is_dialog_open())

	shell.dispatch(In.DOWN)
	_check("the export row is an action", _row(screen, "export").kind == &"action" and _row(screen, "export").button_text() == "导出" and screen.footer_captions()[0] == "导出")
	shell.dispatch(In.ACCEPT)
	var files := screen.export_files()
	_check("export writes one dated profile file and says where", files.size() == 1 and files[0].begins_with("classic-games-profile-2026111") and shell.toast_text().begins_with("已导出到 ") and shell.toast_text().ends_with(files[0]))
	var exported := StoreScript.read_profile(EXPORT_DIR.path_join(files[0]))
	_check("the exported file is a complete, valid profile", exported.get("recents") == ["survivor", "shooter"] and int((exported["stats"] as Dictionary)["survivor"]["runs"]) == 2 and int((exported["settings"] as Dictionary)[S.MAX_FPS]) == 120)

	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	_check("the wipe row is marked as dangerous", _row(screen, "wipe").find_child("Button", true, false).danger and screen.row == 6)
	shell.dispatch(In.ACCEPT)
	_check("wipe asks first, with focus on cancel", screen.is_dialog_open() and shell.has_overlay() and shell.find_child("WipeDialog", true, false) != null and screen.dialog_labels() == PackedStringArray(["取消", "确认清除"]) and screen.dialog_focus() == 0 and shell.find_child("DialogTitle", true, false).text == "清除全部进度？")
	shell.dispatch(In.RB)
	shell.dispatch(In.X)
	_check("the dialog is modal", shell.current_id() == &"settings" and screen.is_dialog_open() and store.has_played("shooter"))
	shell.dispatch(In.ACCEPT)
	_check("accept on the default choice cancels and wipes nothing", not screen.is_dialog_open() and not shell.has_overlay() and store.has_played("shooter") and store.recents().size() == 2 and screen.zone == &"rows")
	shell.dispatch(In.ACCEPT)
	shell.dispatch(In.BACK)
	_check("back cancels the dialog", not screen.is_dialog_open() and store.has_played("shooter") and shell.current_id() == &"settings")
	shell.dispatch(In.ACCEPT)
	shell.find_child("Scrim", true, false).activated.emit()
	_check("clicking outside cancels it", not screen.is_dialog_open() and store.has_played("shooter"))
	shell.dispatch(In.ACCEPT)
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.RIGHT)
	_check("focus moves to confirm and stops there", screen.dialog_focus() == 1)
	shell.dispatch(In.ACCEPT)
	_check("confirming wipes the progress and keeps the settings", not screen.is_dialog_open() and store.recents().is_empty() and store.favorites().is_empty() and store.unlocked_count() == 0 and not store.has_played("survivor") and int(store.setting(S.MAX_FPS)) == 120 and shell.toast_text() == "已清除全部进度" and not shell.can_undo())
	_check("the totals follow the wipe", _row(screen, "play_time").value_text() == "不到 1 分钟" and _row(screen, "runs").value_text() == "0 局" and _row(screen, "achievements").value_text() == "0 / 11")

	shell.dispatch(In.UP)
	shell.dispatch(In.ACCEPT)
	_check("import lists the exported files with focus on cancel", screen.is_dialog_open() and shell.find_child("ImportDialog", true, false) != null and screen.dialog_labels() == PackedStringArray([files[0].trim_prefix("classic-games-profile-").trim_suffix(".json"), "取消"]) and screen.dialog_focus() == 1)
	shell.dispatch(In.ACCEPT)
	_check("cancelling imports nothing", not screen.is_dialog_open() and store.recents().is_empty())
	shell.dispatch(In.ACCEPT)
	shell.dispatch(In.UP)
	shell.dispatch(In.ACCEPT)
	_check("importing a file restores its progress", not screen.is_dialog_open() and store.recents() == ["survivor", "shooter"] and store.is_favorite("shooter") and int(store.stats("survivor")["best_score"]) == 90 and store.is_unlocked("shooter", "first_sortie") and shell.toast_text() == "已导入进度" and shell.can_undo())
	_check("the totals follow the import", _row(screen, "runs").value_text() == "3 局" and _row(screen, "achievements").value_text() == "2 / 11")
	_check("the imported progress is on disk", _reload().recents() == ["survivor", "shooter"])
	shell.undo()
	_check("an import can be undone", store.recents().is_empty() and _row(screen, "runs").value_text() == "0 局")

	var bad := EXPORT_DIR.path_join("classic-games-profile-99990101-000000.json")
	_write(bad, JSON.stringify({"version": StoreScript.VERSION + 1, "recents": ["shooter"]}))
	_check("exports are listed newest first", screen.export_files()[0] == bad.get_file())
	shell.dispatch(In.ACCEPT)
	shell.dispatch(In.UP)
	shell.dispatch(In.UP)
	shell.dispatch(In.ACCEPT)
	_check("a file from a newer version is refused and nothing changes", store.recents().is_empty() and shell.toast_text() == "这个文件无法读取，或来自更新的版本" and not screen.is_dialog_open())
	_remove_exports()
	shell.dispatch(In.ACCEPT)
	_check("with no exported file import only says so", not screen.is_dialog_open() and shell.toast_text().ends_with("里没有导出文件"))
	shell.free()
	_reset_engine()

# ---- about, English ----

func _test_about_and_english() -> void:
	var store := _fresh_store()
	store.set_setting(S.LANG, "en")
	var shell := _boot(store)
	await _frames(2)
	shell.go(&"settings", {"category": "about"})
	var screen := shell.current_screen() as LauncherSettingsScreen
	_check("the categories are in English", _category_labels(screen) == PackedStringArray(["General", "Display", "Audio", "Controls", "Player keys", "Saves", "About"]))
	_check("about shows the project version from the project settings", _row(screen, "version").value_text() == str(ProjectSettings.get_setting("application/config/version")) and _row(screen, "version").value_text() != "")
	_check("about shows the running engine version", _row(screen, "engine").value_text() == "Godot " + str(Engine.get_version_info()["string"]))
	_check("about names the licence, the key art's origin and the repository", _row(screen, "license").value_text() == "Apache-2.0" and _row(screen, "art").value_text() == "AI-generated" and _row(screen, "repo").value_text() == "github.com/yldm-tech/classic-games")
	shell.dispatch(In.RIGHT)
	for i in 3:
		shell.dispatch(In.DOWN)
	_check("the key art row points at the licence notes", screen.help_text().contains("docs/legal/licenses.md"))
	_check("the English footer", screen.footer_captions() == PackedStringArray(["Back"]))
	shell.go(&"settings", {"category": "controls"})
	_check("actions and gamepad names are in English", _row(screen, "bind_accept").label_text() == "Confirm (A)" and _row(screen, "bind_accept").button_text() == "Rebind" and screen.pad_names(In.LEFT) == "D-pad ← / Left stick ←")
	shell.go(&"settings", {"category": "saves"})
	_check("save totals are in English", _row(screen, "play_time").value_text() == "Under a minute" and _row(screen, "runs").value_text() == "0")
	shell.dispatch(In.RIGHT)
	for i in 6:
		shell.dispatch(In.DOWN)
	shell.dispatch(In.ACCEPT)
	_check("the wipe dialog is in English", screen.dialog_labels() == PackedStringArray(["Cancel", "Wipe"]) and shell.find_child("DialogTitle", true, false).text == "Wipe all progress?")
	shell.go(&"home")
	_check("leaving the screen closes its dialog", not shell.has_overlay() and not screen.is_dialog_open())
	shell.free()
	_reset_engine()

# ---- gamepad repeat ----

func _test_gamepad_repeat() -> void:
	var shell := _boot(_fresh_store())
	await _frames(2)
	shell.go(&"settings", {"category": "controls"})
	var screen := shell.current_screen() as LauncherSettingsScreen
	shell.dispatch(In.RIGHT)
	shell._unhandled_input(_pad(JOY_BUTTON_DPAD_DOWN, true))
	_check("a d-pad press moves once", screen.row == 1)
	shell._process(In.REPEAT_DELAY - 0.05)
	_check("nothing repeats before the initial delay", screen.row == 1)
	shell._process(0.1)
	_check("holding repeats after the initial delay", screen.row == 2)
	shell._process(In.REPEAT_INTERVAL * 0.5)
	_check("and then waits for the interval", screen.row == 2)
	shell._process(In.REPEAT_INTERVAL * 0.6)
	shell._process(In.REPEAT_INTERVAL)
	_check("repeating at the interval", screen.row == 4)
	shell._process(5.0)
	_check("a long frame is one repeat, not a burst", screen.row == 5)
	shell._unhandled_input(_axis(JOY_AXIS_LEFT_Y, 0.05))
	shell._process(In.REPEAT_INTERVAL)
	_check("stick noise does not cancel a held d-pad", screen.row == 6)
	shell._unhandled_input(_pad(JOY_BUTTON_DPAD_DOWN, false))
	shell._process(2.0)
	_check("releasing stops it", screen.row == 6)

	shell._unhandled_input(_axis(JOY_AXIS_LEFT_Y, -1.0))
	_check("pushing the stick moves once", screen.row == 5)
	shell._unhandled_input(_axis(JOY_AXIS_LEFT_Y, -0.9))
	_check("more motion past the deadzone is still one press", screen.row == 5)
	shell._process(In.REPEAT_DELAY + 0.01)
	shell._process(In.REPEAT_INTERVAL)
	_check("a held stick repeats too", screen.row == 3)
	shell._unhandled_input(_axis(JOY_AXIS_LEFT_Y, 0.0))
	shell._process(2.0)
	_check("and stops when it returns to the centre", screen.row == 3)

	shell._unhandled_input(_pad(JOY_BUTTON_DPAD_UP, true))
	shell._unhandled_input(_pad(JOY_BUTTON_DPAD_DOWN, true))
	shell._unhandled_input(_pad(JOY_BUTTON_DPAD_UP, false))
	shell._process(In.REPEAT_DELAY + 0.01)
	_check("the direction pressed last is the one that repeats", screen.row == 4)
	shell._unhandled_input(_pad(JOY_BUTTON_DPAD_DOWN, false))

	shell.go(&"settings", {"category": "display"})
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.DOWN)
	shell._unhandled_input(_pad(JOY_BUTTON_A, true))
	_check("A on the gamepad flips the toggle", shell.store.setting(S.VSYNC) == false)
	shell._process(2.0)
	shell._process(2.0)
	_check("buttons other than directions never repeat", shell.store.setting(S.VSYNC) == false)
	shell._unhandled_input(_pad(JOY_BUTTON_A, false))
	shell.go(&"settings", {"category": "controls"})
	shell.dispatch(In.RIGHT)
	shell._unhandled_input(_pad(JOY_BUTTON_DPAD_DOWN, true))
	shell.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	shell._process(2.0)
	_check("losing focus drops a held direction", screen.row == 1)
	shell.free()
	_reset_engine()

# ---- helpers ----

func _boot(store: LauncherStore) -> LauncherRoot:
	var packed: PackedScene = load(str(ProjectSettings.get_setting("application/run/main_scene")))
	var shell: LauncherRoot = packed.instantiate()
	shell.store = store
	shell.now_provider = func() -> int: return NOW
	root.add_child(shell)
	return shell

func _fresh_store() -> LauncherStore:
	for suffix in ["", ".tmp", ".corrupt"]:
		if FileAccess.file_exists(STORE_PATH + suffix):
			DirAccess.remove_absolute(STORE_PATH + suffix)
	var store := StoreScript.new(STORE_PATH)
	store.load_from_disk()
	return store

## A second store reading the same file: what is really on disk.
func _reload() -> LauncherStore:
	var store := StoreScript.new(STORE_PATH)
	store.load_from_disk()
	return store

func _remove_exports() -> void:
	var dir := DirAccess.open(EXPORT_DIR)
	if dir != null:
		for file in dir.get_files():
			dir.remove(file)

func _remove_files() -> void:
	_remove_exports()
	if DirAccess.dir_exists_absolute(EXPORT_DIR):
		DirAccess.remove_absolute(EXPORT_DIR)
	for suffix in ["", ".tmp", ".corrupt"]:
		if FileAccess.file_exists(STORE_PATH + suffix):
			DirAccess.remove_absolute(STORE_PATH + suffix)

## Undo everything a shell applies to the engine, so each test starts from the project's own state.
# ---- player keys ----

## The second settings page of keys: the two keyboard schemes game modules are played with. They rebind like the launcher's own keys, clash only with each other, and can never share a key with pause.
func _test_player_keys() -> void:
	_reset_engine()
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	var p1_a := In.game_action(1, &"a")
	var p2_a := In.game_action(2, &"a")
	var p2_up := In.game_action(2, &"up")
	_check("both schemes exist in the project with one key per control", In.keycodes(p1_a) == [KEY_F] and In.keycodes(p2_a) == [KEY_K] and In.keycodes(In.game_action(1, &"up")) == [KEY_W] and In.keycodes(p2_up) == [KEY_UP] and In.all_game_actions().size() == 20)
	var unique := {}
	for action in In.all_game_actions():
		for code in In.keycodes(action):
			unique[code] = true
	_check("no two player controls share a default key", unique.size() == 20)
	var apart := true
	for action in In.all_game_actions():
		for code in In.keycodes(action):
			apart = apart and not In.keycodes(In.MENU).has(code) and not In.keycodes(In.BACK).has(code)
	_check("and none of them is a pause key", apart)

	shell.go(&"settings", {"category": "players"})
	var screen := shell.current_screen() as LauncherSettingsScreen
	_check("the player keys page lists player 1's ten controls, then player 2's", screen.find_child("Title", true, false).text == "玩家按键" and _row_ids(screen).size() == 20 and _row_ids(screen)[0] == "bind_game_p1_up" and _row_ids(screen)[10] == "bind_game_p2_up" and _row_ids(screen)[19] == "bind_game_p2_r")
	_check("each row names the player and shows the key", _row(screen, "bind_game_p2_a").label_text() == "玩家 2 · A 键" and _row(screen, "bind_game_p2_a").value_text() == "K" and _row(screen, "bind_game_p1_left").value_text() == "A")
	_check("the gamepad side is shown as fixed", screen.pad_names(p2_a) == "A" and screen.pad_names(p2_up) == "十字键 ↑ / 左摇杆 ↑" and screen.pad_names(In.game_action(1, &"l")) == "LB")

	screen.begin_capture(p2_a)
	screen.capture_key(KEY_M)
	_check("a pause key is refused for a player control, and the capture goes on", screen.is_capturing() and shell.toast_text() == "M 已用于「选项（Menu）」，暂停键、PC 模式键和玩家按键不能共用。" and store.bindings().is_empty())
	screen.capture_key(KEY_ESCAPE)
	_check("so is the other pause key", screen.is_capturing() and In.keycodes(p2_a) == [KEY_K])
	screen.capture_key(KEY_ENTER)
	_check("a key the interface uses for something else is free for a player", not screen.is_capturing() and not screen.is_dialog_open() and In.keycodes(p2_a) == [KEY_ENTER] and In.keycodes(In.ACCEPT).has(KEY_ENTER) and store.bindings() == {"game_p2_a": [KEY_ENTER]})

	screen.begin_capture(p2_a)
	screen.capture_key(KEY_F)
	_check("a key the other player uses opens the conflict dialog", screen.is_dialog_open() and shell.find_child("DialogBody", true, false).text == "F 已用于「玩家 1 · A 键」。替换后，「玩家 1 · A 键」会改用 Enter。")
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.ACCEPT)
	_check("replacing swaps the two, so neither player is locked out", In.keycodes(p2_a) == [KEY_F] and In.keycodes(p1_a) == [KEY_ENTER] and _row(screen, "bind_game_p1_a").value_text() == "Enter" and _row(screen, "bind_game_p2_a").value_text() == "F")
	var bound := true
	for action in In.all_game_actions():
		bound = bound and In.keycodes(action).size() == 1
	_check("every control of both players still has a key", bound)

	shell.go(&"settings", {"category": "controls"})
	screen = shell.current_screen() as LauncherSettingsScreen
	screen.begin_capture(In.MENU)
	screen.capture_key(KEY_F)
	_check("a player key is refused for pause", screen.is_capturing() and In.keycodes(In.MENU) == [KEY_M] and shell.toast_text() == "F 已用于「玩家 2 · A 键」，暂停键、PC 模式键和玩家按键不能共用。")
	screen.capture_key(KEY_N)
	_check("a free key is accepted", In.keycodes(In.MENU) == [KEY_N])
	screen.begin_capture(In.UP)
	screen.capture_key(KEY_W)
	_check("a navigation key may be a player's key too: the two are never live together", not screen.is_dialog_open() and In.keycodes(In.UP) == [KEY_W] and In.keycodes(In.game_action(1, &"up")) == [KEY_W])

	shell.free()
	_reset_engine()
	shell = _boot(_reload())
	await _frames(2)
	_check("player keys are stored and applied at the next start", In.keycodes(p2_a) == [KEY_F] and In.keycodes(p1_a) == [KEY_ENTER] and In.keycodes(In.MENU) == [KEY_N])
	shell.go(&"settings", {"category": "players"})
	screen = shell.current_screen() as LauncherSettingsScreen
	shell.dispatch(In.RIGHT)
	_check("the page can be restored", screen.can_reset())
	screen.reset_page()
	_check("restoring this page resets the player keys and leaves the interface's", In.keycodes(p2_a) == [KEY_K] and In.keycodes(p1_a) == [KEY_F] and In.keycodes(In.MENU) == [KEY_N] and In.keycodes(In.UP) == [KEY_W] and shell.store.bindings() == {"launcher_menu": [KEY_N], "launcher_up": [KEY_W]})
	shell.undo()
	_check("and can be undone", In.keycodes(p2_a) == [KEY_F] and In.keycodes(p1_a) == [KEY_ENTER])
	shell.go(&"settings", {"category": "controls"})
	screen = shell.current_screen() as LauncherSettingsScreen
	screen.reset_page()
	_check("restoring the interface page leaves the player keys", In.keycodes(In.MENU) == [KEY_M] and In.keycodes(In.UP) == [KEY_UP] and In.keycodes(p2_a) == [KEY_F] and shell.store.bindings() == {"game_p1_a": [KEY_ENTER], "game_p2_a": [KEY_F]})

	# A reset must not bring back a default that the other side of the pause boundary has taken in the meantime.
	var p1_b := In.game_action(1, &"b")
	screen.begin_capture(In.MENU)
	screen.capture_key(KEY_N)
	shell.go(&"settings", {"category": "players"})
	screen = shell.current_screen() as LauncherSettingsScreen
	screen.begin_capture(p1_b)
	screen.capture_key(KEY_M)
	_check("a key the pause gave up can become a player's", In.keycodes(p1_b) == [KEY_M] and In.keycodes(In.MENU) == [KEY_N])
	screen.begin_capture(p1_b)
	screen.capture_key(KEY_F11)
	_check("the PC mode key is refused for a player, like a pause key: it stays live during a game", screen.is_capturing() and In.keycodes(p1_b) == [KEY_M] and shell.toast_text().begins_with("F11 已用于"))
	screen.cancel_capture()
	shell.dismiss_toast()
	shell.go(&"settings", {"category": "controls"})
	screen = shell.current_screen() as LauncherSettingsScreen
	screen.begin_capture(In.PC_MODE)
	screen.capture_key(KEY_M)
	_check("and a player key is refused for PC mode", screen.is_capturing() and In.keycodes(In.PC_MODE) == [KEY_F11])
	screen.cancel_capture()
	shell.dismiss_toast()
	screen.reset_page()
	_check("restoring the interface keys when Menu's default now belongs to a player restores both pages, so no key both plays and pauses", In.keycodes(In.MENU) == [KEY_M] and In.keycodes(p1_b) == [KEY_G] and In.keycodes(p1_a) == [KEY_F] and shell.store.bindings().is_empty() and shell.toast_text() == "默认按键与另一页的自定义按键冲突，两页按键已一并恢复默认")
	shell.undo()
	_check("and one undo brings both pages back", In.keycodes(In.MENU) == [KEY_N] and In.keycodes(p1_b) == [KEY_M] and In.keycodes(p1_a) == [KEY_ENTER])
	screen.reset_page()
	shell.dismiss_toast()
	screen.begin_capture(In.MENU)
	screen.capture_key(KEY_N)
	shell.go(&"settings", {"category": "players"})
	screen = shell.current_screen() as LauncherSettingsScreen
	screen.begin_capture(p2_a)
	screen.capture_key(KEY_J)
	shell.go(&"settings", {"category": "controls"})
	screen = shell.current_screen() as LauncherSettingsScreen
	screen.begin_capture(In.MENU)
	screen.capture_key(KEY_K)
	_check("the other way round: a key a player gave up can become the pause key", In.keycodes(In.MENU) == [KEY_K] and In.keycodes(p2_a) == [KEY_J])
	shell.go(&"settings", {"category": "players"})
	screen = shell.current_screen() as LauncherSettingsScreen
	screen.reset_page()
	_check("restoring the player keys when one of their defaults now pauses restores both pages too", In.keycodes(p2_a) == [KEY_K] and In.keycodes(In.MENU) == [KEY_M] and shell.store.bindings().is_empty())
	shell.dismiss_toast()
	shell.free()
	_reset_engine()

func _test_effects_volume() -> void:
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	var bus := AudioServer.get_bus_index(&"SFX")
	_check("there is an SFX bus under Master, next to Music", bus > 0 and AudioServer.get_bus_send(bus) == &"Master" and AudioServer.get_bus_index(&"Music") > 0)
	shell.go(&"settings", {"category": "audio"})
	var screen := shell.current_screen() as LauncherSettingsScreen
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	_check("the effects row is the third audio row and starts full", screen.row == 2 and _row_ids(screen)[2] == "volume_sfx" and _row(screen, "volume_sfx").label_text() == "音效" and S.value(store, S.VOLUME_SFX) == 10)
	for press in 4:
		shell.dispatch(In.LEFT)
	_check("lowering it lowers the SFX bus only", store.setting(S.VOLUME_SFX) == 6 and is_equal_approx(AudioServer.get_bus_volume_db(bus), linear_to_db(0.6)) and is_zero_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music"))) and is_zero_approx(AudioServer.get_bus_volume_db(0)))
	shell.free()
	_reset_engine()
	shell = _boot(_reload())
	await _frames(2)
	_check("it is applied again at the next start", is_equal_approx(AudioServer.get_bus_volume_db(bus), linear_to_db(0.6)))
	shell.go(&"settings", {"category": "audio"})
	screen = shell.current_screen() as LauncherSettingsScreen
	shell.dispatch(In.RIGHT)
	screen.reset_page()
	_check("and is part of what the audio page restores", S.value(shell.store, S.VOLUME_SFX) == 10 and is_zero_approx(AudioServer.get_bus_volume_db(bus)))
	shell.free()
	_reset_engine()

func _reset_engine() -> void:
	Engine.max_fps = 0
	for bus in AudioServer.bus_count:
		AudioServer.set_bus_volume_db(bus, 0.0)
		AudioServer.set_bus_mute(bus, false)
	InputMap.load_from_project_settings()

func _row(screen: LauncherSettingsScreen, id: String) -> LauncherSettingsControls.SettingRow:
	return screen.find_child("Row_" + id, true, false) as LauncherSettingsControls.SettingRow

func _row_ids(screen: LauncherSettingsScreen) -> Array:
	var out: Array = []
	for child in (screen.find_child("Rows", true, false) as LauncherSettingsControls.RowList).column.get_children():
		if not child.is_queued_for_deletion():
			out.append(String(child.name).trim_prefix("Row_"))
	return out

func _category_labels(screen: LauncherSettingsScreen) -> PackedStringArray:
	var out := PackedStringArray()
	for id in LauncherSettingsScreen.CATEGORIES:
		out.append((screen.find_child("Category_%s" % id, true, false) as LauncherControls.FocusRow).label_text())
	return out

func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event

func _pad(button: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	return event

func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event

func _has_button(action: StringName, button: JoyButton) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == button:
			return true
	return false

func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + label)
