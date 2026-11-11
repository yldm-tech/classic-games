extends SceneTree

## Headless tests of a game module inside the launcher, with the catalog pointed at the fixture games: real player counts on Home, in the Library and in PC mode; the game menu's player and device rows; per-player input from two keyboard schemes and gamepads; the HUD's second corner; pause ownership; joining, leaving and an unplugged gamepad; the result and what is recorded; and how an invalid manifest is reported.
## Run: make games-test GODOT=/path/to/godot

const StoreScript := preload("res://launcher/launcher_store.gd")
const Catalog := preload("res://launcher/launcher_catalog.gd")
const Guide := preload("res://launcher/launcher_game_guide.gd")
const In := preload("res://launcher/launcher_input.gd")

const FIXTURES := "res://testing/games"
const MIXED := "res://testing/mixed_games"
const STORE_PATH := "user://module-flow-test.json"
const NOW := 1794393000
const GAME := "fixture_duo"
## The second fixture: one seat, a smooth stage, achievements that read what finish() added to the result.
const SOLO := "fixture_arena"

var _passed := 0
var _failed := 0
## The gamepads the launcher believes are connected.
var _pads: Array[int] = []

func _initialize() -> void:
	# Nodes added before the first frame are not ready yet, and _boot reaches into the shell right after adding it.
	await process_frame
	Catalog.use_root(FIXTURES)
	_test_guide()
	await _test_player_counts_shown()
	await _test_menu_players()
	await _test_two_player_run()
	await _test_pause_ownership()
	await _test_join_leave_and_lost_device()
	await _test_result_and_record()
	await _test_single_player_devices()
	await _test_single_seat_module()
	await _test_invalid_manifest_reported()
	Catalog.use_root()
	_release_keys()
	_remove_store_files()
	print("module_flow_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

# ---- guide ----

func _test_guide() -> void:
	_check("the catalog reads the fixture root", Catalog.ids() == [SOLO, GAME] and Catalog.problems().is_empty() and Guide.is_module(GAME))
	_check("the player range and join rule come from the manifest", Guide.player_range(GAME) == Vector2i(1, 2) and Guide.joins_in_progress(GAME) and Catalog.players_label(Catalog.by_id(GAME)) == "1–2P" and Catalog.supports_two(Catalog.by_id(GAME)))
	var controls := Guide.controls(GAME)
	var ids: Array = []
	for control: Dictionary in controls:
		ids.append(control["id"])
	_check("a module's controls are its inputs plus the launcher's pause", ids == ["move", "hit", "hurt", "pause"])
	_check("logical inputs become the keys of a keyboard scheme", Guide.key_labels(controls[0]["actions"]) == PackedStringArray(["W", "S", "A", "D"]) and Guide.key_labels(controls[1]["actions"]) == PackedStringArray(["F"]) and Guide.key_labels(Guide.controls(GAME, 2)[0]["actions"]) == PackedStringArray(["↑", "↓", "←", "→"]) and Guide.key_labels(Guide.controls(GAME, 2)[1]["actions"]) == PackedStringArray(["K"]))
	_check("and the fixed gamepad buttons", controls[1]["glyphs"] == [In.ACCEPT] and controls[2]["glyphs"] == [In.BACK] and Guide.text(controls[0], "pad", "zh") == "左摇杆 / 十字键" and Guide.text(controls[0], "pad", "en") == "Left stick / D-pad")
	var guide := Guide.of(GAME)
	_check("the HUD description is the manifest's", Guide.is_countdown(GAME) and Guide.has_clock(GAME) and Guide.text(guide["vital"], "label", "en") == "LIVES" and (guide["player_stats"] as Array).size() == 1 and guide["boss"]["field"] == "boss_hp")
	var option: Dictionary = Guide.options(GAME)[0]
	_check("an option value can carry its own label", Guide.option_label(option, 30, "zh") == "30 秒" and Guide.option_label(option, 5, "en") == "5 s" and Guide.option_patch(GAME, {"duration": 5}).is_empty())
	var entry := Catalog.by_id(GAME)
	_check("achievement rules read min, max and the player count", Catalog.earned(GAME, {"cleared": true, "deaths": 0, "coins": 1, "player_count": 2}) == ["any_run", "boss_down", "flawless", "together"] and Catalog.earned(GAME, {"cleared": true, "deaths": 1, "coins": 3, "player_count": 1}) == ["any_run", "boss_down"] and Catalog.earned(GAME, {"cleared": true, "player_count": 2}) == ["any_run", "boss_down"] and Catalog.earned(GAME, {"cleared": true, "deaths": 0, "aborted": true}).is_empty() and not entry.is_empty())

# ---- player counts ----

func _test_player_counts_shown() -> void:
	# The game last played is the one Home opens on.
	var played := _fresh_store()
	played.record_run(GAME, {"score": 1, "play_seconds": 1.0}, NOW - 60)
	var shell := _boot(played)
	await _frames(2)
	_check("Home shows the game's real player count", str(shell.current_screen().find_child("Meta", true, false).text).ends_with("· 1–2P"))
	shell.go(LauncherRoot.LIBRARY)
	var library := shell.current_screen() as LauncherLibraryScreen
	_check("the Library shows it", library.detail_value("players") == "1–2P")
	shell.toggle_pc_mode()
	await _frames(2)
	var pc := shell.find_child("PcMode", false, false)
	if pc != null:
		pc.call("select", GAME)
		await _frames(2)
	_check("PC mode shows it", pc != null and str(pc.find_child("Eyebrow", true, false).text).ends_with("· 1–2P"))
	shell.toggle_pc_mode()
	shell.free()

# ---- menu ----

func _test_menu_players() -> void:
	_pads = []
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	shell.go(LauncherRoot.MENU, {"game": GAME})
	var menu := shell.current_screen() as LauncherMenuScreen
	var players := shell.game_host.players
	_check("a game two can play has a players row under start", menu.row_ids() == [&"start", &"players", &"how", &"records", &"achievements", &"option:duration", &"favorite", &"back"])
	_check("it starts at the game's minimum", menu.player_count() == 1 and _row(menu, "players").sub_text() == "1 人" and str(menu.find_child("Meta", true, false).text).ends_with("· 1–2P"))
	_check("an option with labels shows the label", _row(menu, "option_duration").sub_text() == "30 秒")
	shell.dispatch(In.DOWN)
	_check("its pane offers the counts and explains a single player's devices", menu.row_id() == &"players" and menu.find_child("Players_1", true, false).active and not menu.find_child("Players_2", true, false).active and menu.find_child("SoloDevices", true, false) != null)
	shell.dispatch(In.RIGHT)
	_check("Right chooses two players, remembers it, and adds a device row per player", menu.player_count() == 2 and store.setting(Guide.players_key(GAME)) == 2 and menu.row_ids().slice(0, 4) == [&"start", &"players", &"device:0", &"device:1"] and menu.row_id() == &"players" and _row(menu, "players").sub_text() == "2 人")
	_check("without a gamepad the two players get the two keyboard schemes", players.count == 2 and players.device(0) == "kb1" and players.device(1) == "kb2" and _row(menu, "device_0").sub_text() == "键盘方案 1" and _row(menu, "device_1").sub_text() == "键盘方案 2")
	_check("the pane lists who plays on what", str(menu.find_child("Seat1", true, false).get_node("Device").text) == "键盘方案 2")
	shell.dispatch(In.RIGHT)
	_check("the count stops at the game's maximum", menu.player_count() == 2)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.RIGHT)
	_check("changing a player's device to the one the other holds swaps them", menu.row_id() == &"device:0" and players.device(0) == "kb2" and players.device(1) == "kb1")
	_check("the device pane marks the current device and shows that scheme's keys", menu.find_child("Device_kb2", true, false).active and not menu.find_child("Device_kb1", true, false).active and menu.find_child("Controls", true, false) != null)
	shell.dispatch(In.LEFT)
	_check("and back", players.device(0) == "kb1" and players.device(1) == "kb2")

	_pads = [0]
	shell.dispatch(In.ACCEPT)
	_check("a connected gamepad is offered as a device", players.available_devices() == ["kb1", "kb2", "pad:0"] and players.device(0) == "kb2")
	shell.dispatch(In.ACCEPT)
	_check("and can be chosen", players.device(0) == "pad:0" and _row(menu, "device_0").sub_text() == "手柄 1")
	shell.dispatch(In.ACCEPT)
	_check("accept walks round the devices", players.device(0) == "kb1")
	shell.dispatch(In.UP)
	shell.dispatch(In.LEFT)
	_check("back to one player removes the device rows", menu.player_count() == 1 and menu.row_ids().slice(0, 3) == [&"start", &"players", &"how"] and menu.row_id() == &"players" and players.count == 1)
	shell.dispatch(In.ACCEPT)
	_check("accept on the players row walks through the counts", menu.player_count() == 2)
	_check("with one gamepad, player one keeps the keyboard and player two takes the gamepad", players.device(0) == "kb1" and players.device(1) == "pad:0")
	_pads = [0, 1]
	players.assign_defaults()
	_check("with two gamepads each player gets one", players.device(0) == "pad:0" and players.device(1) == "pad:1")

	shell.go(LauncherRoot.MENU, {"game": GAME})
	menu = shell.current_screen() as LauncherMenuScreen
	_check("the chosen count is still there when the menu is opened again", menu.player_count() == 2 and menu.row_ids().has(&"device:1"))
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	_check("the how-to pane shows the controls with a note about the schemes", menu.row_id() == &"how" and menu.find_child("Control_hit", true, false) != null and menu.find_child("Control_pause", true, false) != null and menu.find_child("ControlsNote", true, false) != null)
	shell.free()
	_pads = []

# ---- a two-player run ----

func _test_two_player_run() -> void:
	_pads = []
	var store := _fresh_store()
	store.set_setting(Guide.players_key(GAME), 2)
	var shell := _boot(store)
	await _frames(2)
	shell.go(LauncherRoot.GAME, {"game": GAME})
	await _frames(2)
	var game := shell.current_screen() as LauncherGameScreen
	var host := shell.game_host
	_check("the run started with the stored player count", host.is_running() and host.is_module() and host.active_players() == [0, 1] and host.players.count == 2)
	_check("the stage has the module's size and maps to the canvas", host.stage_size() == Vector2i(480, 270) and host.to_stage(Vector2(1920, 1080)) == Vector2(480, 270) and host.to_canvas(Vector2(240, 135)) == Vector2(960, 540))
	var stage := host.find_child("Stage", true, false) as SubViewportContainer
	var viewport := host.find_child("StageViewport", true, false) as SubViewport
	_check("a pixel-art stage is rendered at its own size and enlarged by a whole factor, unfiltered", stage.stretch_shrink == 4 and stage.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and viewport.size_2d_override == Vector2i.ZERO and viewport.canvas_item_default_texture_filter == Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST and viewport.snap_2d_transforms_to_pixel)

	_check("each player has a corner of the HUD", _text(game, "Tag") == "P1 得分" and _text(game, "Tag2") == "P2 得分" and game.find_child("Player2", true, false).is_visible_in_tree() and _text(game, "VitalLabel") == "生命" and _text(game, "VitalValue") == "3 / 3" and _text(game, "VitalValue2") == "3 / 3" and not game.find_child("Hint2", true, false).visible)
	_check("the shared counters, the boss bar and the countdown are the manifest's", _text(game.find_child("Stats", true, false), "Value") == "0 / 3" and game.find_child("Boss", true, false).visible and _text(game, "BossLabel") == "首领" and _text(game, "Title") == "夹具双人 · 剩余时间" and _text(game, "Time") == "00:30")
	_check("a module's HUD cannot be hidden from a button", not game.find_child("HideHud", true, false).visible and game.find_child("PauseButton", true, false).visible)

	var start := host.snapshot()
	_press(shell, KEY_D)
	_press(shell, KEY_LEFT)
	var moved := await _until(func() -> bool:
		var now := host.snapshot()
		return float(now["players"][0]["x"]) > float(start["players"][0]["x"]) + 2.0 and float(now["players"][1]["x"]) < float(start["players"][1]["x"]) - 2.0, 5.0)
	_check("scheme 1 moves player one and scheme 2 moves player two", moved)
	_release(shell, KEY_D)
	_release(shell, KEY_LEFT)
	_check("the launcher's own actions on the same keys are swallowed while a module plays", shell.current_id() == LauncherRoot.GAME and host.is_running())
	_tap_key(shell, KEY_E)
	_tap_key(shell, KEY_Y)
	_check("Q / E / Y do not switch tabs or hide the HUD in a module", shell.current_id() == LauncherRoot.GAME and game.hud_visible)

	_press(shell, KEY_K)
	var hit := await _until(func() -> bool: return int(host.snapshot()["players"][1]["hits"]) == 1, 5.0)
	_release(shell, KEY_K)
	await _frames(2)
	_check("player two's A scores for player two, and the HUD follows", hit and _text(game, "Score2") == "100" and _text(game, "Score") == "0" and int(host.snapshot()["score"]) == 100 and _text(game.find_child("PlayerStats2", true, false), "Value") == "1")
	var echo := _key(KEY_K, true)
	echo.echo = true
	shell._unhandled_input(echo)
	await _frames(3)
	_check("a key repeat is not a second press", int(host.snapshot()["players"][1]["hits"]) == 1)
	_release(shell, KEY_K)

	shell._unhandled_input(_key(KEY_ESCAPE, true))
	_check("Esc pauses for the first keyboard player", shell.current_id() == LauncherRoot.PAUSE and host.is_paused() and host.pause_owner == 0)
	shell.dispatch(In.BACK)
	_check("and resumes", shell.current_id() == LauncherRoot.GAME and not host.is_paused() and host.pause_owner == -1)
	shell.go(LauncherRoot.HOME)
	_check("leaving the game screen ends and records the run once", not host.is_running() and int(store.stats(GAME)["runs"]) == 1 and int(store.stats(GAME)["best_score"]) == 100)
	_check("a run the players walked out of unlocks nothing, not even the achievement for any finished run", store.achievements(GAME).is_empty() and int(store.stats(GAME)["clears"]) == 0)
	shell.free()

# ---- pause ownership ----

func _test_pause_ownership() -> void:
	_pads = [4]
	var store := _fresh_store()
	store.set_setting(Guide.players_key(GAME), 2)
	var shell := _boot(store)
	await _frames(2)
	shell.go(LauncherRoot.GAME, {"game": GAME})
	await _frames(2)
	var host := shell.game_host
	_check("player one is on the keyboard and player two on the gamepad", host.players.device(0) == "kb1" and host.players.device(1) == "pad:4")

	shell._unhandled_input(_button(4, JOY_BUTTON_A, true))
	var hit := await _until(func() -> bool: return int(host.snapshot()["players"][1]["hits"]) == 1, 5.0)
	shell._unhandled_input(_button(4, JOY_BUTTON_A, false))
	_check("the gamepad's A is player two's A, not the launcher's confirm", hit and shell.current_id() == LauncherRoot.GAME)
	shell._unhandled_input(_button(4, JOY_BUTTON_B, true))
	shell._unhandled_input(_button(4, JOY_BUTTON_B, false))
	var hurt := await _until(func() -> bool: return int(host.snapshot()["players"][1]["lives"]) == 2, 5.0)
	_check("B is a game button there, not pause", hurt and shell.current_id() == LauncherRoot.GAME and not host.is_paused())
	var before := float(host.snapshot()["players"][1]["x"])
	shell._unhandled_input(_axis(4, JOY_AXIS_LEFT_X, 0.9))
	var pushed := await _until(func() -> bool: return float(host.snapshot()["players"][1]["x"]) > before + 2.0, 5.0)
	shell._unhandled_input(_axis(4, JOY_AXIS_LEFT_X, 0.0))
	_check("the left stick moves player two", pushed)
	shell._unhandled_input(_button(9, JOY_BUTTON_A, true))
	shell._unhandled_input(_button(9, JOY_BUTTON_A, false))
	await _frames(3)
	_check("a gamepad nobody plays on does nothing in a two-player run", int(host.snapshot()["players"][0]["hits"]) == 0 and int(host.snapshot()["players"][1]["hits"]) == 1)

	shell._unhandled_input(_button(4, JOY_BUTTON_START, true))
	shell._unhandled_input(_button(4, JOY_BUTTON_START, false))
	var pause := shell.current_screen() as LauncherPauseScreen
	_check("player two pauses from the gamepad and owns the pause", pause != null and host.is_paused() and host.pause_owner == 1 and _text(pause, "Meta") == "PAUSED · P2")
	_check("the pause lists the player rows", pause.row_ids() == [&"resume", &"restart", &"volume", &"join", &"device0", &"device1", &"quit"] and pause.find_child("Row3", true, false).label_text() == "移除玩家 2" and pause.find_child("Row5", true, false).sub_text() == "手柄 5")
	_check("each player's controls are listed under their device", _text(pause, "PlayerCaption0") == "P1 · 键盘方案 1" and _text(pause, "PlayerCaption1") == "P2 · 手柄 5" and pause.find_child("Controls1", true, false) != null)

	shell._unhandled_input(_key(KEY_DOWN, true))
	_check("the other player's keyboard cannot drive it, and is told why", pause.row == 0 and shell.toast_text() == "游戏由 P2 暂停，请由这位玩家操作。")
	shell._unhandled_input(_key(KEY_ESCAPE, true))
	_check("nor end it", shell.current_id() == LauncherRoot.PAUSE and host.is_paused())
	shell.dismiss_toast()
	shell._unhandled_input(_button(4, JOY_BUTTON_DPAD_DOWN, true))
	shell._unhandled_input(_button(4, JOY_BUTTON_DPAD_DOWN, false))
	_check("the owner's gamepad moves the focus", pause.row == 1 and shell.toast_text() == "")
	shell._unhandled_input(_button(4, JOY_BUTTON_B, true))
	shell._unhandled_input(_button(4, JOY_BUTTON_B, false))
	_check("and resumes", shell.current_id() == LauncherRoot.GAME and not host.is_paused() and host.pause_owner == -1)
	await _frames(3)
	_check("the button that resumed is not played as a game button", int(host.snapshot()["players"][1]["lives"]) == 2)

	shell._unhandled_input(_key(KEY_M, true))
	pause = shell.current_screen() as LauncherPauseScreen
	_check("the keyboard player pauses with Menu and owns it", host.pause_owner == 0 and _text(pause, "Meta") == "PAUSED · P1")
	shell._unhandled_input(_button(4, JOY_BUTTON_A, true))
	shell._unhandled_input(_button(4, JOY_BUTTON_A, false))
	_check("now the gamepad is the one that is refused", shell.current_id() == LauncherRoot.PAUSE and shell.toast_text() == "游戏由 P1 暂停，请由这位玩家操作。")
	shell._unhandled_input(_key(KEY_ENTER, true))
	_check("and the keyboard resumes", shell.current_id() == LauncherRoot.GAME)
	shell.free()
	_pads = []

# ---- join, leave, lost device ----

func _test_join_leave_and_lost_device() -> void:
	_pads = [0]
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	shell.go(LauncherRoot.GAME, {"game": GAME})
	await _frames(2)
	var game := shell.current_screen() as LauncherGameScreen
	var host := shell.game_host
	_check("a one-player run shows where player two could sit", host.active_players() == [0] and game.find_child("Player2", true, false).is_visible_in_tree() and _text(game, "Hint2") == "P2 可从暂停菜单加入" and game.find_child("Hint2", true, false).visible and not game.find_child("Score2", true, false).visible)
	shell._unhandled_input(_key(KEY_M, true))
	var pause := shell.current_screen() as LauncherPauseScreen
	_check("its pause offers to add player two, and no device rows yet", pause.row_ids() == [&"resume", &"restart", &"volume", &"join", &"quit"] and pause.find_child("Row3", true, false).label_text() == "加入玩家 2" and _text(pause, "Meta") == "PAUSED")
	for step in 3:
		shell.dispatch(In.DOWN)
	shell.dispatch(In.ACCEPT)
	_check("adding seats player two on the free gamepad and shows the device rows", host.active_players() == [0, 1] and host.players.count == 2 and host.players.device(1) == "pad:0" and pause.row_ids() == [&"resume", &"restart", &"volume", &"join", &"device0", &"device1", &"quit"] and pause.row_id() == &"join" and shell.toast_text() == "玩家 2 已加入。")
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.RIGHT)
	_check("a player's device can be changed from the pause", pause.row_id() == &"device1" and host.players.device(1) == "kb1" and host.players.device(0) == "pad:0" and pause.find_child("Row5", true, false).sub_text() == "键盘方案 1")
	shell.dispatch(In.LEFT)
	shell.dispatch(In.BACK)
	await _frames(2)
	_check("back in the game both corners are live", shell.current_id() == LauncherRoot.GAME and _text(game, "Tag2") == "P2 得分" and not game.find_child("Hint2", true, false).visible and _text(game, "VitalValue2") == "3 / 3")

	_pads = []
	shell._on_joy_connection_changed(0, false)
	await _frames(2)
	pause = shell.current_screen() as LauncherPauseScreen
	_check("unplugging a player's gamepad pauses the run and says so", pause != null and host.is_paused() and host.pause_owner == -1 and shell.toast_text() == "P2 的手柄已断开，游戏已暂停。")
	_check("the device row shows it is gone", pause.find_child("Row5", true, false).sub_text() == "手柄 1（未连接）")
	shell.dismiss_toast()
	shell._unhandled_input(_key(KEY_DOWN, true))
	_check("a pause nobody owns takes input from anyone", pause.row == 1 and shell.toast_text() == "")
	for step in 4:
		shell.dispatch(In.DOWN)
	shell.dispatch(In.RIGHT)
	_check("the player can move to a device that is there", pause.row_id() == &"device1" and host.players.device(1) == "kb2" and host.players.is_device_connected(1))
	shell.dispatch(In.UP)
	shell.dispatch(In.UP)
	shell.dispatch(In.ACCEPT)
	_check("or leave: removing player two drops the device rows", pause.row_id() == &"join" and host.active_players() == [0] and pause.row_ids() == [&"resume", &"restart", &"volume", &"join", &"quit"] and shell.toast_text() == "玩家 2 已退出。")
	shell.dispatch(In.BACK)
	await _frames(2)
	_check("and the HUD shows the empty seat again", _text(game, "Hint2") == "P2 可从暂停菜单加入" and game.find_child("Hint2", true, false).visible)
	shell.go(LauncherRoot.HOME)
	shell.free()

# ---- result ----

func _test_result_and_record() -> void:
	_pads = []
	var store := _fresh_store()
	store.set_setting(Guide.players_key(GAME), 2)
	store.set_setting(Guide.option_key(GAME, "duration"), 60)
	var shell := _boot(store)
	await _frames(2)
	shell.go(LauncherRoot.GAME, {"game": GAME})
	await _frames(2)
	var game := shell.current_screen() as LauncherGameScreen
	var host := shell.game_host
	_check("the stored option reached the module", is_equal_approx(float(host.snapshot()["duration"]), 60.0))
	var finished: Array = []
	host.run_finished.connect(func(_id: String, result: Dictionary, record: Dictionary) -> void: finished.append([result, record]))
	for hit in 5:
		var slot := hit % 2
		var wanted := int(host.snapshot()["players"][slot]["hits"]) + 1
		host.set_control(slot, &"a", 1.0)
		await _until(func() -> bool: return not host.is_running() or int(host.snapshot()["players"][slot]["hits"]) >= wanted, 5.0)
		host.set_control(slot, &"a", 0.0)
		await _frames(2)
	await _until(func() -> bool: return not finished.is_empty(), 5.0)
	_check("the module ending the run shows the result", finished.size() == 1 and game.phase == LauncherGameScreen.PHASE_RESULT and _text(game, "Outcome") == "通关" and _text(game, "FinalScore") == "500")
	_check("with each player's score next to the total", _text(game.find_child("PlayerScore1", true, false), "Value") == "300" and _text(game.find_child("PlayerScore2", true, false), "Value") == "200")
	_check("it is recorded once, with the achievements its result earns", int(store.stats(GAME)["runs"]) == 1 and int(store.stats(GAME)["clears"]) == 1 and int(store.stats(GAME)["best_score"]) == 500 and finished[0][1]["unlocked"] == ["any_run", "boss_down", "flawless"] and store.is_unlocked(GAME, "flawless") and not store.is_unlocked(GAME, "together"))
	_check("the unlocked achievements are listed", game.find_child("Unlocked_flawless", true, false) != null)
	shell.dispatch(In.ACCEPT)
	await _frames(2)
	_check("play again starts a fresh run with the same players", host.is_running() and host.active_players() == [0, 1] and int(host.snapshot()["score"]) == 0 and game.phase == LauncherGameScreen.PHASE_PLAYING)
	shell.go(LauncherRoot.HOME)
	_check("and leaving records that one too", int(store.stats(GAME)["runs"]) == 2)
	shell.free()

# ---- one player ----

func _test_single_player_devices() -> void:
	_pads = [2]
	var shell := _boot(_fresh_store())
	await _frames(2)
	shell.go(LauncherRoot.GAME, {"game": GAME})
	await _frames(2)
	var host := shell.game_host
	var start := float(host.snapshot()["players"][0]["x"])
	_press(shell, KEY_RIGHT)
	var by_arrows := await _until(func() -> bool: return float(host.snapshot()["players"][0]["x"]) > start + 2.0, 5.0)
	_press(shell, KEY_D)
	_release(shell, KEY_RIGHT)
	var here := float(host.snapshot()["players"][0]["x"])
	var still_held := await _until(func() -> bool: return float(host.snapshot()["players"][0]["x"]) > here + 2.0, 5.0)
	_release(shell, KEY_D)
	_check("with one player both keyboard schemes drive player one", by_arrows)
	_check("a direction held on both stays held until both let go", still_held)
	shell._unhandled_input(_button(2, JOY_BUTTON_A, true))
	var hit := await _until(func() -> bool: return int(host.snapshot()["players"][0]["hits"]) == 1, 5.0)
	shell._unhandled_input(_button(2, JOY_BUTTON_A, false))
	_check("and so does any gamepad", hit)
	shell._unhandled_input(_button(2, JOY_BUTTON_START, true))
	shell._unhandled_input(_button(2, JOY_BUTTON_START, false))
	_check("a one-player pause belongs to whoever is at the controls", shell.current_id() == LauncherRoot.PAUSE and host.pause_owner == 0)
	shell._unhandled_input(_key(KEY_ESCAPE, true))
	_check("so the keyboard can end a pause the gamepad started", shell.current_id() == LauncherRoot.GAME)
	var from := float(host.snapshot()["players"][0]["x"])
	_press(shell, KEY_D)
	await _until(func() -> bool: return float(host.snapshot()["players"][0]["x"]) > from + 1.0, 5.0)
	shell.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(3)
	var parked := float(host.snapshot()["players"][0]["x"])
	await _frames(6)
	_check("losing the window's focus lets go of every held control", is_equal_approx(float(host.snapshot()["players"][0]["x"]), parked))
	shell.free()
	_pads = []

# ---- a game with one seat ----

func _test_single_seat_module() -> void:
	_pads = [3]
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	shell.go(LauncherRoot.MENU, {"game": SOLO})
	var menu := shell.current_screen() as LauncherMenuScreen
	_check("a one-seat module has no players row, and an option without labels shows its number", menu.row_ids() == [&"start", &"how", &"records", &"achievements", &"option:sparks", &"favorite", &"back"] and _row(menu, "option_sparks").sub_text().begins_with("8"))
	shell.go(LauncherRoot.GAME, {"game": SOLO})
	await _frames(2)
	var game := shell.current_screen() as LauncherGameScreen
	var host := shell.game_host
	var stage := host.find_child("Stage", true, false) as SubViewportContainer
	var viewport := host.find_child("StageViewport", true, false) as SubViewport
	_check("a smooth stage is rendered at the canvas's resolution with the module's coordinates mapped onto it", host.is_module() and host.stage_size() == Vector2i(640, 360) and stage.stretch_shrink == 1 and viewport.size_2d_override == Vector2i(640, 360) and viewport.size_2d_override_stretch and viewport.canvas_item_default_texture_filter == Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR and not viewport.snap_2d_transforms_to_pixel)
	_check("its HUD has one corner, an elapsed clock and the manifest's counters", _text(game, "Tag") == "得分" and not game.find_child("Player2", true, false).is_visible_in_tree() and _text(game, "VitalLabel") == "护盾" and _text(game, "VitalValue") == "3 / 3" and _text(game.find_child("Stats", true, false), "Value") == "8 / 8" and _text(game, "Title") == "圆场清扫 · 时间")

	var from: Vector2 = host.snapshot()["ship"]
	shell._unhandled_input(_axis(3, JOY_AXIS_LEFT_X, 0.6))
	var pushed := await _until(func() -> bool: return (host.snapshot()["ship"] as Vector2).x > from.x + 2.0, 5.0)
	_check("the stick of any gamepad flies the one player", pushed)
	_pads = []
	shell._on_joy_connection_changed(3, false)
	await _frames(3)
	_check("unplugging the gamepad that was being played on pauses a one-player run too", shell.current_id() == LauncherRoot.PAUSE and host.is_paused() and host.pause_owner == -1 and shell.toast_text() == "P1 的手柄已断开，游戏已暂停。")
	shell.dismiss_toast()
	shell._unhandled_input(_key(KEY_ESCAPE, true))
	await _frames(3)
	var parked: Vector2 = host.snapshot()["ship"]
	await _frames(8)
	_check("and the stick it held over is let go: after resuming from the keyboard the ship stays put", shell.current_id() == LauncherRoot.GAME and not host.is_paused() and (host.snapshot()["ship"] as Vector2).is_equal_approx(parked))

	_pads = [3, 5]
	shell._on_joy_connection_changed(5, true)
	shell._unhandled_input(_axis(5, JOY_AXIS_LEFT_Y, 0.9))
	await _until(func() -> bool: return (host.snapshot()["ship"] as Vector2).y > parked.y + 2.0, 5.0)
	_press(shell, KEY_D)
	_pads = [3]
	shell._on_joy_connection_changed(5, false)
	await _frames(2)
	_check("a gamepad unplugged while the keyboard is the one being played on does not pause", shell.current_id() == LauncherRoot.GAME and not host.is_paused())
	var drifting: Vector2 = host.snapshot()["ship"]
	var kept := await _until(func() -> bool: return (host.snapshot()["ship"] as Vector2).x > drifting.x + 2.0, 5.0)
	await _frames(2)
	_check("it only lets go of what that gamepad held: the key still moves the ship, the stick no longer does", kept and is_equal_approx((host.snapshot()["ship"] as Vector2).y, drifting.y))
	_release(shell, KEY_D)

	_check("achievement rules read the fields finish() added to the result", Catalog.earned(SOLO, {"cleared": true, "hits_taken": 0, "accuracy": 85}) == ["swept", "untouched", "marksman"] and Catalog.earned(SOLO, {"cleared": true, "hits_taken": 2, "accuracy": 40}) == ["swept"] and Catalog.earned(SOLO, {"cleared": false, "defeated": true, "hits_taken": 3, "accuracy": 100}).is_empty())
	_check("a result field that is not a number satisfies no rule instead of raising an error", Catalog.earned(SOLO, {"cleared": true, "hits_taken": Vector2.ZERO, "accuracy": [90]}) == ["swept"])
	shell.go(LauncherRoot.HOME)
	_check("leaving records the one-seat run once and unlocks nothing", int(store.stats(SOLO)["runs"]) == 1 and store.achievements(SOLO).is_empty())
	shell.free()
	_pads = []

# ---- invalid manifest ----

func _test_invalid_manifest_reported() -> void:
	Catalog.use_root(MIXED)
	_check("a directory with one good and one broken game offers the good one", Catalog.ids() == ["ok_solo"] and Catalog.problems().size() == 1 and Catalog.problems()[0]["id"] == "broken_one")
	var shell := _boot(_fresh_store())
	await _frames(2)
	_check("the launcher starts and says a game could not be loaded", shell.current_id() == LauncherRoot.HOME and shell.toast_text().begins_with("有 1 款游戏无法加载（broken_one："))
	shell.go(LauncherRoot.SETTINGS, {"category": "about"})
	var settings := shell.current_screen() as LauncherSettingsScreen
	var row := settings.find_child("Row_problem_broken_one", true, false) as LauncherSettingsControls.SettingRow
	_check("Settings lists it with what is wrong", row != null and row.label_text() == "无法加载：broken_one" and settings.find_child("Row_games", true, false).value_text() == "1 款")
	shell.go(LauncherRoot.MENU, {"game": "ok_solo"})
	var menu := shell.current_screen() as LauncherMenuScreen
	_check("the good game is fully usable, and a single-player game has no players row", menu.game_id == "ok_solo" and not menu.row_ids().has(&"players") and Catalog.players_label(Catalog.by_id("ok_solo")) == "1P")
	shell.free()
	Catalog.use_root(FIXTURES)

# ---- helpers ----

func _fresh_store() -> LauncherStore:
	_remove_store_files()
	var store := StoreScript.new(STORE_PATH)
	store.load_from_disk()
	return store

func _remove_store_files() -> void:
	for suffix in ["", ".tmp", ".corrupt"]:
		if FileAccess.file_exists(STORE_PATH + suffix):
			DirAccess.remove_absolute(STORE_PATH + suffix)

func _boot(store: LauncherStore) -> LauncherRoot:
	_release_keys()
	var packed: PackedScene = load(str(ProjectSettings.get_setting("application/run/main_scene")))
	var shell: LauncherRoot = packed.instantiate()
	shell.store = store
	shell.now_provider = func() -> int: return NOW
	root.add_child(shell)
	shell.game_host.players.pads_provider = func() -> Array[int]: return _pads
	shell.game_host.run_seed = 7
	(shell.screen(LauncherRoot.GAME) as LauncherGameScreen).pause_on_focus_loss = false
	return shell

func _release_keys() -> void:
	for action in In.ALL:
		Input.action_release(action)

func _key(code: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	return event

func _button(device: int, button: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = pressed
	return event

func _axis(device: int, axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	return event

func _press(shell: LauncherRoot, code: Key) -> void:
	shell._unhandled_input(_key(code, true))

func _release(shell: LauncherRoot, code: Key) -> void:
	shell._unhandled_input(_key(code, false))

func _tap_key(shell: LauncherRoot, code: Key) -> void:
	_press(shell, code)
	_release(shell, code)

func _row(screen: Node, id: String) -> LauncherControls.FocusRow:
	return screen.find_child("Row_%s" % id, true, false)

func _text(screen: Node, node_name: String) -> String:
	return str(screen.find_child(node_name, true, false).text)

func _frames(count: int) -> void:
	for index in count:
		await process_frame

## Wait until `done` holds or `seconds` of wall-clock time have passed. Returns whether it held.
func _until(done: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not done.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await process_frame
	return true

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + label)
