extends SceneTree

## Headless tests of the game flow: the per-game guide data, the game menu, the in-game HUD and input, the pause screen, the result overlay, and the rule that every run is recorded exactly once however it ends. The shell is driven through LauncherRoot.dispatch exactly as a key or gamepad press would drive it, and the games are the real runtimes.
## Run: make game-flow-test GODOT=/path/to/godot

const StoreScript := preload("res://launcher/launcher_store.gd")
const Catalog := preload("res://launcher/launcher_catalog.gd")
const Guide := preload("res://launcher/launcher_game_guide.gd")
const Format := preload("res://launcher/launcher_format.gd")
const In := preload("res://launcher/launcher_input.gd")
const LauncherTable := preload("res://i18n/launcher_strings.gd")

const STORE_PATH := "user://game-flow-test.json"
## 2026-11-11 10:30:00 UTC; see launcher_test.gd for why this moment.
const NOW := 1794393000
const DAY := 86400
## The GameSession.perform commands each runtime really acts on.
const RUNTIME_COMMANDS := {"shooter": ["move", "boost", "shield"], "survivor": ["move"], "tower_defense": ["place_tower"]}

class PcModeProbe:
	extends Control
	func handle_action(_action: StringName) -> bool:
		return true

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_test_guide_data()
	_test_strings()
	await _test_bindings_cover_the_runtimes()
	await _test_history_helper()
	await _test_menu_fresh()
	await _test_menu_played()
	await _test_hud_tower_defense()
	await _test_hud_shooter_and_survivor()
	await _test_pause_flow()
	await _test_recorded_exactly_once()
	await _test_result_routing()
	await _test_english()
	_release_all()
	_remove_store_files()
	print("game_flow_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

# ---- guide data ----

func _test_guide_data() -> void:
	var complete := true
	for id in Catalog.ids():
		var guide := Guide.of(id)
		if Guide.text(guide, "how", "zh") == "" or Guide.text(guide, "how", "en") == "" or Guide.text(guide, "how", "zh") == Guide.text(guide, "how", "en"):
			complete = false
		if Guide.controls(id).is_empty() or not guide.has("clock") or not guide.has("vital") or (guide.get("stats", []) as Array).is_empty():
			complete = false
		for control: Dictionary in Guide.controls(id):
			if Guide.text(control, "name", "zh") == "" or (control["name"] as Dictionary).get("en", "") == "":
				complete = false
	_check("every catalog game has a how-to, controls and HUD description in both languages", complete)

	var bound := true
	for id in Catalog.ids():
		for control: Dictionary in Guide.controls(id):
			for action: StringName in control["actions"]:
				if not InputMap.has_action(action):
					bound = false
			if Guide.key_labels(control["actions"]).is_empty() or not Guide.has_gamepad_binding(control["actions"]):
				bound = false
			if (control.get("glyphs", []) as Array).is_empty() and not control.has("pad"):
				bound = false
	_check("every listed control has a real keyboard key and a real gamepad binding behind it", bound)
	_check("every game can be paused and its HUD hidden from the keyboard and the gamepad", _has_control("shooter", "pause") and _has_control("survivor", "pause") and _has_control("tower_defense", "pause") and _has_control("survivor", "hud"))

	_check("keys are shown the way they are printed on a keyboard", Guide.key_labels(Guide.MOVE_ACTIONS) == PackedStringArray(["↑", "↓", "←", "→"]) and Guide.key_labels([In.ACCEPT]) == PackedStringArray(["Enter", "Space"]) and Guide.key_labels([In.MENU, In.BACK]) == PackedStringArray(["M", "Esc", "Backspace"]))
	var rebound := InputEventKey.new()
	rebound.physical_keycode = KEY_J
	InputMap.action_add_event(In.X, rebound)
	_check("a rebound key shows up in the controls", Guide.key_labels([In.X]) == PackedStringArray(["X", "J"]))
	InputMap.action_erase_event(In.X, rebound)

	_check("tower types have display names in both languages", Guide.tower_name("tower_defense", "arrow", "zh") == "箭塔" and Guide.tower_name("tower_defense", "tesla", "en") == "Tesla" and Guide.tower_note("tower_defense", "frost", "zh") != "")
	_check("an unknown tower type falls back to its id", Guide.tower_name("tower_defense", "catapult", "zh") == "catapult" and Guide.tower_note("tower_defense", "catapult", "zh") == "")

	var option: Dictionary = Guide.options("shooter")[0]
	var baseline: Dictionary = GameSession.baseline_payload("shooter@1.0.0")["mod"]
	_check("only the shooter has a start option, and its default is the baseline's own value", Guide.options("survivor").is_empty() and Guide.options("tower_defense").is_empty() and option["id"] == "difficulty" and int(baseline["stage"]["difficulty"]) == int(option["default"]))
	_check("an option value becomes one replace operation on the baseline", Guide.option_patch("shooter", {"difficulty": 4}) == [{"op": "replace", "path": "/stage/difficulty", "value": 4}])
	_check("the default, an unlisted value, a wrong type and an unknown option change nothing", Guide.option_patch("shooter", {"difficulty": 2}).is_empty() and Guide.option_patch("shooter", {"difficulty": 9}).is_empty() and Guide.option_patch("shooter", {"difficulty": "hard"}).is_empty() and Guide.option_patch("shooter", {"lives": 3}).is_empty() and Guide.option_patch("survivor", {"difficulty": 4}).is_empty())

	var store := _fresh_store()
	_check("options and volume fall back to their defaults", Guide.stored_options("shooter", store) == {"difficulty": 2} and Guide.stored_volume(store) == Guide.VOLUME_DEFAULT)
	store.set_setting(Guide.option_key("shooter", "difficulty"), 5.0)
	store.set_setting(Guide.SETTING_MASTER_VOLUME, 3.0)
	_check("stored values are read back as integers", Guide.stored_options("shooter", store) == {"difficulty": 5} and Guide.stored_volume(store) == 3)
	store = _fresh_store()
	store.set_setting(Guide.option_key("shooter", "difficulty"), 42)
	store.set_setting(Guide.SETTING_MASTER_VOLUME, "loud")
	_check("values a hand-edited file could hold are not trusted", Guide.stored_options("shooter", store) == {"difficulty": 2} and Guide.stored_volume(store) == Guide.VOLUME_DEFAULT)

	_check("a countdown reads what is left, rounded up", Guide.is_countdown("shooter") and Guide.clock_text("shooter", {"time_left": 61}) == "01:01" and Guide.clock_text("survivor", {"duration": 180.0, "elapsed": 59.2}) == "02:01" and Guide.clock_text("survivor", {"duration": 180.0, "elapsed": 400.0}) == "00:00")
	_check("an open-ended game reads time played", not Guide.is_countdown("tower_defense") and Guide.clock_text("tower_defense", {"play_seconds": 75.9}) == "01:15")
	_check("a counter is one number or a pair", Guide.stat_text({"fields": ["gold"]}, {"gold": 1250}) == "1,250" and Guide.stat_text({"fields": ["current_wave", "wave_count"]}, {"current_wave": 1, "wave_count": 2}) == "1 / 2")

	Guide.apply_volume(5)
	var master := AudioServer.get_bus_index(&"Master")
	_check("volume is applied to the Master bus", not AudioServer.is_bus_mute(master) and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(master)), 0.5))
	Guide.apply_volume(0)
	_check("zero mutes it", AudioServer.is_bus_mute(master))
	Guide.apply_volume(Guide.VOLUME_STEPS)
	_check("full volume is unity gain", not AudioServer.is_bus_mute(master) and is_zero_approx(AudioServer.get_bus_volume_db(master)))

func _has_control(game_id: String, control_id: String) -> bool:
	for control: Dictionary in Guide.controls(game_id):
		if control["id"] == control_id:
			return true
	return false

func _test_strings() -> void:
	var zh: Dictionary = LauncherTable.TABLE["zh"]
	var en: Dictionary = LauncherTable.TABLE["en"]
	var paired := true
	var count := 0
	for key: String in zh:
		if key.begins_with("launcher.menu.") or key.begins_with("launcher.pause.") or key.begins_with("launcher.game."):
			count += 1
			if not en.has(key) or str(en[key]) == "":
				paired = false
			if str(zh[key]).count("%") != str(en[key]).count("%"):
				paired = false
	_check("menu, game and pause strings exist in both languages with the same placeholders", paired and count > 60)
	var referenced := true
	for id in Catalog.ids():
		var guide := Guide.of(id)
		var keys: Array = [str((guide["vital"] as Dictionary)["label"])]
		for stat: Dictionary in guide["stats"]:
			keys.append(str(stat["label"]))
		for key: String in keys:
			if not zh.has(key):
				referenced = false
	_check("every string key the guide names exists", referenced)

## The guide may only list a command the runtime really accepts, and must list every one it does.
func _test_bindings_cover_the_runtimes() -> void:
	var shell := _boot(_fresh_store())
	await _frames(2)
	var host := shell.game_host
	for id: String in RUNTIME_COMMANDS:
		host.launch(id)
		await _frames(2)
		var accepted := {
			"boost": host.perform("boost", {"on": true}),
			"shield": host.perform("shield"),
			"place_tower": host.perform("place_tower", {"tower": str((host.snapshot().get("tower_ids", [""]) as Array)[0]), "position": Vector2(100, 100)}),
		}
		var matches := true
		for command: String in accepted:
			if bool(accepted[command]) != (command in (RUNTIME_COMMANDS[id] as Array)):
				matches = false
			if bool(accepted[command]) != (not Guide.control_for(id, command).is_empty()):
				matches = false
		_check("%s: the controls list exactly the commands the runtime accepts" % id, matches)
		_check("%s: movement is listed only where the runtime reads it" % id, ("move" in (RUNTIME_COMMANDS[id] as Array)) == (not Guide.control_for(id, "move").is_empty()))
	shell.free()

# ---- shell helper ----

func _test_history_helper() -> void:
	var shell := _boot(_fresh_store())
	await _frames(2)
	shell.go(&"library")
	shell.go(&"menu", {"game": "survivor"})
	shell.go(&"pause")
	shell.close_to(&"menu", {"game": "survivor"}, [&"pause"])
	_check("close_to shows the destination", shell.current_id() == &"menu")
	shell.dispatch(In.BACK)
	_check("and back from it skips the closed screens and the destination's own earlier entry", shell.current_id() == &"library")
	shell.go(&"menu", {"game": "survivor"})
	shell.go(&"settings")
	shell.close_to(&"home")
	shell.dispatch(In.BACK)
	_check("close_to a top-level tab clears the history", shell.current_id() == &"home")
	shell.free()

# ---- game menu ----

func _test_menu_fresh() -> void:
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.ACCEPT)
	var menu := shell.current_screen() as LauncherMenuScreen
	_check("Home's game-menu row opens the menu of the selected game", menu != null and menu.game_id == "survivor" and menu.find_child("Title", true, false).text == "长夜草原" and menu.find_child("Crumb", true, false).text == "长夜草原")
	_check("the menu sits on the game's key art without the top navigation", shell.backdrop_layer() == &"hero" and menu.backdrop()["game"] == "survivor" and not shell.find_child("Nav", false, false).visible)
	_check("the hero column shows genre, players and the Latin name", menu.find_child("Meta", true, false).text == "SURVIVAL ACTION · 1P" and menu.find_child("LatinName", true, false).text == "MEADOW VIGIL")
	_check("a game without start options has the six fixed rows", menu.row_ids() == [&"start", &"how", &"records", &"achievements", &"favorite", &"back"])
	_check("start is focused and says the game was never played", menu.row == 0 and _row(menu, "start").focused and _row(menu, "start").label_text() == "开始游戏" and _row(menu, "start").sub_text() == "尚未游玩")
	_check("the overview shows the tagline and no invented numbers", menu.find_child("Tagline", true, false).text == Catalog.text(Catalog.by_id("survivor"), "tagline", "zh") and _stat(menu, "best") == "—" and _stat(menu, "time") == "—" and _stat(menu, "achievements") == "0 / 4")
	_check("the footer offers start, favourite and back", menu.footer_captions() == PackedStringArray(["开始", "加入收藏", "返回"]))

	shell.dispatch(In.DOWN)
	_check("how to play shows the rules and the game's real controls", menu.row_id() == &"how" and menu.find_child("Control_move", true, false) != null and menu.find_child("Control_pause", true, false) != null and menu.find_child("Control_boost", true, false) == null)
	_check("a row that only informs offers no accept hint", menu.footer_captions() == PackedStringArray(["加入收藏", "返回"]))
	shell.dispatch(In.ACCEPT)
	_check("and accept does nothing there", shell.current_id() == &"menu" and menu.row_id() == &"how")
	shell.dispatch(In.DOWN)
	_check("records of an unplayed game say there are none", menu.row_id() == &"records" and menu.find_child("RecordsEmpty", true, false) != null and menu.find_child("Stat_runs", true, false) == null)
	shell.dispatch(In.DOWN)
	var locked: Node = menu.find_child("Achievement_first_watch", true, false)
	_check("achievements lists every achievement of the game as locked", menu.row_id() == &"achievements" and _row(menu, "achievements").sub_text() == "0 / 4 已解锁" and locked != null and not locked.unlocked and locked.find_child("State", true, false).text == "未解锁" and menu.find_child("Achievement_thirty_down", true, false) != null)
	shell.dispatch(In.ACCEPT)
	_check("accept there opens the achievements screen", shell.current_id() == &"achievements")
	shell.dispatch(In.BACK)
	_check("achievements is a top-level tab, so back from it is Home", shell.current_id() == &"home")
	shell.go(&"menu", {"game": "survivor"})

	shell.dispatch(In.Y)
	_check("Y toggles the favourite and says so", store.is_favorite("survivor") and shell.toast_text() == "已收藏「长夜草原」" and _row(menu, "favorite").label_text() == "取消收藏" and menu.footer_captions().has("取消收藏"))
	shell.dispatch(In.X)
	_check("the toast's undo takes it back", not store.is_favorite("survivor") and _row(menu, "favorite").label_text() == "加入收藏")
	_row(menu, "favorite").hovered.emit()
	_check("mouse hover moves the focus", menu.row_id() == &"favorite" and _row(menu, "favorite").focused)
	shell.dispatch(In.ACCEPT)
	_check("the favourite row does the same as Y", store.is_favorite("survivor"))
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	_check("focus stops at the last row", menu.row_id() == &"back")
	shell.dispatch(In.LB)
	shell.dispatch(In.RT)
	_check("the tab buttons do nothing without the navigation", shell.current_id() == &"menu")
	shell.dispatch(In.ACCEPT)
	_check("the back row returns to where the menu was opened from", shell.current_id() == &"home")

	shell.go(&"menu", {"game": "shooter"})
	menu = shell.current_screen()
	_check("a game with a start option gets a row for it", menu.row_ids() == [&"start", &"how", &"records", &"achievements", &"option:difficulty", &"favorite", &"back"] and _row(menu, "option_difficulty").label_text() == "难度" and _row(menu, "option_difficulty").sub_text().begins_with("2 / 5"))
	for i in 4:
		shell.dispatch(In.DOWN)
	_check("its pane explains it and marks the current value", menu.row_id() == &"option:difficulty" and menu.find_child("Value_2", true, false).active and not menu.find_child("Value_3", true, false).active and menu.find_child("Value_2", true, false).note() == "默认")
	shell.dispatch(In.RIGHT)
	_check("right raises it and stores it", Guide.stored_options("shooter", store) == {"difficulty": 3} and _row(menu, "option_difficulty").sub_text().begins_with("3 / 5") and menu.find_child("Value_3", true, false).active)
	for i in 6:
		shell.dispatch(In.LEFT)
	_check("left lowers it and stops at the lowest", Guide.stored_options("shooter", store) == {"difficulty": 1})
	menu.find_child("Value_5", true, false).activated.emit()
	_check("clicking a value picks it", Guide.stored_options("shooter", store) == {"difficulty": 5})
	shell.dispatch(In.ACCEPT)
	_check("accept walks through the values and wraps", Guide.stored_options("shooter", store) == {"difficulty": 1})
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.RIGHT)

	_row(menu, "start").activated.emit()
	await _frames(3)
	_check("start launches the game from its menu", shell.current_id() == &"game" and shell.game_host.is_running() and shell.game_host.game_id() == "shooter")
	_check("the run uses the chosen option", shell.game_host.run_options() == {"difficulty": 4} and int(_run_node(shell).get_meta("difficulty")) == 4)
	shell.go(&"menu", {"game": "nonexistent"})
	_check("an unknown game id keeps the menu on a real game", (shell.current_screen() as LauncherMenuScreen).game_id == "shooter")
	shell.free()

func _test_menu_played() -> void:
	var store := _fresh_store()
	store.record_run("tower_defense", {"score": 900, "play_seconds": 300.0, "cleared": false}, NOW - 2 * DAY)
	store.record_run("tower_defense", {"score": 2130, "play_seconds": 355.0, "cleared": true}, NOW - 600)
	store.unlock("tower_defense", "first_defense", NOW - 2 * DAY)
	store.unlock("tower_defense", "gate_held", NOW - 600)
	store.set_favorite("tower_defense", true)
	var shell := _boot(store)
	await _frames(2)
	shell.go(&"menu", {"game": "tower_defense"})
	var menu := shell.current_screen() as LauncherMenuScreen
	_check("start shows the real last-played time and best score", _row(menu, "start").sub_text().begins_with("上次游玩 今天 ") and _row(menu, "start").sub_text().ends_with("· 最高分 2,130"))
	_check("the overview carries best score, play time and achievement count", _stat(menu, "best") == "2,130" and _stat(menu, "time") == "10m" and _stat(menu, "achievements") == "2 / 4")
	_check("a favourite game offers to remove it", _row(menu, "favorite").label_text() == "取消收藏")
	shell.dispatch(In.DOWN)
	_check("the tower-defense controls include cursor, placing and tower selection", menu.find_child("Control_cursor", true, false) != null and menu.find_child("Control_place", true, false) != null and menu.find_child("Control_tower", true, false) != null)
	shell.dispatch(In.DOWN)
	_check("records show best score, runs, clears, play time and last played from the store", _stat(menu, "best") == "2,130" and _stat(menu, "runs") == "2" and _stat(menu, "clears") == "1" and _stat(menu, "time") == "10m" and _stat(menu, "last").begins_with("今天 ") and menu.find_child("RecordsEmpty", true, false) == null)
	shell.dispatch(In.DOWN)
	var done: Node = menu.find_child("Achievement_gate_held", true, false)
	var old: Node = menu.find_child("Achievement_first_defense", true, false)
	var open: Node = menu.find_child("Achievement_untouched", true, false)
	_check("achievements show which are unlocked and when", done.unlocked and done.find_child("State", true, false).text.begins_with("今天 ") and old.unlocked and old.find_child("State", true, false).text.begins_with("2 天前 ") and not open.unlocked and menu.find_child("PaneHeader", true, false).find_child("Title", true, false).text == "成就  2 / 4")
	store.unlock("tower_defense", "untouched", NOW)
	_check("the menu follows the store while it is open", (menu.find_child("Achievement_untouched", true, false) as Node).unlocked and _row(menu, "achievements").sub_text() == "3 / 4 已解锁")
	shell.free()

# ---- in-game HUD and input ----

func _test_hud_tower_defense() -> void:
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	shell.go(&"game", {"game": "tower_defense"})
	var game := shell.current_screen() as LauncherGameScreen
	await _frames(3)
	_check("the stage is rendered at the canvas's resolution in the runtime's own coordinates", (shell.game_host.find_child("StageViewport", true, false) as SubViewport).size == Vector2i(1920, 1080) and (shell.game_host.find_child("StageViewport", true, false) as SubViewport).size_2d_override == GameSession.STAGE_SIZE and shell.game_host.to_canvas(Vector2(480, 270)) == Vector2(960, 540))
	_check("the HUD names the game and what its clock counts", _text(game, "Title") == "隘口守卫 · 时间" and _text(game, "Time") == "00:00")
	_check("score, base health and counters come from the snapshot", _text(game, "Score") == "150" and _text(game, "VitalLabel") == "基地" and _text(game, "VitalValue") == "20 / 20" and is_equal_approx(game.find_child("VitalMeter", true, false).ratio, 1.0) and _hud_stat(game, "current_wave") == "1 / 2" and _hud_stat(game, "gold") == "150" and _hud_stat(game, "kills") == "0")
	_check("the snapshot carries the tower catalogue and the base's full health", (shell.game_host.snapshot()["towers"] as Array).size() == 5 and shell.game_host.snapshot()["towers"][1] == {"id": "cannon", "type": "cannon", "cost": 90, "damage": 30, "range": 140.0, "cooldown": 1.4} and int(shell.game_host.snapshot()["base_hp_max"]) == 20)
	var arrow: Node = game.find_child("Tower_arrow", true, false)
	var laser: Node = game.find_child("Tower_laser", true, false)
	_check("towers are offered by their localised names with their cost", arrow.caption() == "箭塔" and arrow.note() == "50" and laser.caption() == "激光塔" and laser.note() == "120" and game.find_child("Tower_tesla", true, false).caption() == "电塔")
	_check("the first tower is selected and described", game.tower_index == 0 and arrow.active and not laser.active and _text(game, "ToolNote") == "箭塔 · 单体攻击，便宜 · 伤害 12 · 射程 180")
	_check("the cursor starts in the middle of the stage with the tower's reach around it", game.cursor_at == Vector2(480, 270) and game.find_child("Cursor", true, false).visible and game.find_child("Cursor", true, false).position == Vector2(960, 540) and is_equal_approx(game.find_child("Cursor", true, false).reach, 360.0))
	_check("no shooter tools on a tower-defense HUD", game.find_child("Boost", true, false) == null and game.find_child("Shield", true, false) == null)

	Input.action_press(In.RIGHT)
	game._process(1.0)
	_check("a held direction moves the cursor at a steady speed", game.cursor_at.is_equal_approx(Vector2(480 + LauncherGameScreen.CURSOR_SPEED, 270)))
	game._process(10.0)
	_check("the cursor stays on the stage", game.cursor_at.is_equal_approx(Vector2(960, 270)))
	Input.action_release(In.RIGHT)
	Input.action_press(In.UP, 0.5)
	Input.action_press(In.LEFT, 0.5)
	game._process(1.0)
	Input.action_release(In.UP)
	Input.action_release(In.LEFT)
	_check("a half-tilted stick moves it slower, on both axes", game.cursor_at.x > 960.0 - LauncherGameScreen.CURSOR_SPEED and game.cursor_at.x < 960.0 and game.cursor_at.y < 270.0 and game.cursor_at.y > 270.0 - LauncherGameScreen.CURSOR_SPEED)
	shell.dispatch(In.RIGHT)
	var parked := game.cursor_at
	game._process(0.0)
	_check("a released direction leaves it where it is", game.cursor_at == parked)

	shell.dispatch(In.RB)
	_check("RB selects the next tower", game.tower_index == 1)
	shell.dispatch(In.X)
	_check("X does too", game.tower_index == 2)
	shell.dispatch(In.LB)
	shell.dispatch(In.LB)
	shell.dispatch(In.LB)
	_check("LB goes back and wraps", game.tower_index == 4)
	shell.dispatch(In.RB)
	_check("RB wraps forward", game.tower_index == 0 and shell.current_id() == &"game")
	game.find_child("Tower_frost", true, false).activated.emit()
	await _frames(2)
	_check("clicking a tower selects it", game.tower_index == 2 and game.find_child("Tower_frost", true, false).active and not arrow.active and _text(game, "ToolNote").begins_with("冰霜塔"))

	game.cursor_at = Vector2(300, 400)
	var towers: Node = shell.game_host.find_child("Towers", true, false)
	var before := towers.get_child_count()
	shell.dispatch(In.ACCEPT)
	await _frames(2)
	var placed := towers.get_child(towers.get_child_count() - 1) as Node2D
	_check("accept places the selected tower at the cursor", towers.get_child_count() == before + 1 and placed.position.is_equal_approx(Vector2(300, 400) - Vector2(GameSession.STAGE_SIZE) / 2.0) and str(placed.get_meta("config")["type"]) == "frost")
	_check("the HUD follows the snapshot: gold and score drop by the cost", _hud_stat(game, "gold") == "75" and _text(game, "Score") == "75")
	_check("towers the player cannot afford are dimmed", game.find_child("Tower_cannon", true, false).dimmed and laser.dimmed and not arrow.dimmed and game.find_child("Cursor", true, false).affordable)
	shell.dispatch(In.RB)
	shell.dispatch(In.ACCEPT)
	await _frames(2)
	_check("placing what cannot be paid for is refused and says why", towers.get_child_count() == before + 1 and shell.toast_text() == "金币不足" and not game.find_child("Cursor", true, false).affordable)
	shell.dismiss_toast()
	game.select_tower(0)
	game.find_child("StageClick", true, false).activated.emit()
	await _frames(2)
	_check("a click on the stage places at the mouse position", towers.get_child_count() == before + 2 and _hud_stat(game, "gold") == "25")

	shell.dispatch(In.Y)
	_check("Y hides the HUD and leaves a way back", not game.find_child("Hud", true, false).visible and game.find_child("HudOff", true, false).visible and not game.hud_visible)
	game.find_child("ShowHud", true, false).activated.emit()
	_check("clicking it shows the HUD again", game.find_child("Hud", true, false).visible and not game.find_child("HudOff", true, false).visible)
	shell.free()

func _test_hud_shooter_and_survivor() -> void:
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	shell.go(&"game", {"game": "shooter"})
	var game := shell.current_screen() as LauncherGameScreen
	await _frames(3)
	var state := shell.game_host.snapshot()
	_check("the shooter snapshot carries full health, shield, boost and the boss", int(state["max_hp"]) == 100 and int(state["shield_hits"]) == 0 and state["boost"] == false and int(state["boss_hp"]) == 2000 and int(state["boss_max_hp"]) == 2000)
	_check("the shooter HUD counts down and shows health, enemies and the boss", _text(game, "Title") == "星环巡航 · 剩余时间" and _text(game, "Time") == "01:30" and _text(game, "VitalLabel") == "生命" and _text(game, "VitalValue") == "100 / 100" and _hud_stat(game, "enemy_left") == "24 / 24" and game.find_child("Boss", true, false).visible and is_equal_approx(game.find_child("BossMeter", true, false).ratio, 1.0))
	_check("it offers boost and shield instead of towers", game.find_child("Boost", true, false) != null and game.find_child("Shield", true, false).note() == "就绪" and game.find_child("Tower_arrow", true, false) == null and not game.find_child("Cursor", true, false).visible)

	Input.action_press(In.ACCEPT)
	await _frames(2)
	_check("holding accept boosts", shell.game_host.snapshot()["boost"] == true and game.find_child("Boost", true, false).active)
	Input.action_release(In.ACCEPT)
	await _frames(2)
	_check("letting go stops it", shell.game_host.snapshot()["boost"] == false and not game.find_child("Boost", true, false).active)

	shell.dispatch(In.X)
	await _frames(2)
	_check("X raises the shield", int(shell.game_host.snapshot()["shield_hits"]) == 1 and game.find_child("Shield", true, false).note() == "生效中" and game.find_child("Shield", true, false).active)
	shell.dispatch(In.X)
	_check("a raised shield cannot be stacked", int(shell.game_host.snapshot()["shield_hits"]) == 1)
	# The runtime spends the shield on the next hit; do that by hand instead of waiting for an enemy.
	shell.game_host.find_child("Player", true, false).set_meta("shield_hits", 0)
	await _frames(2)
	var shield: Node = game.find_child("Shield", true, false)
	_check("a spent shield recharges before it can be used again", shield.note() == "%d 秒" % int(Guide.SHIELD_COOLDOWN) and shield.dimmed and not shield.active)
	shield.activated.emit()
	_check("and is refused meanwhile, by button or by click", int(shell.game_host.snapshot()["shield_hits"]) == 0)
	game._shield_ready_at = 0.0
	await _frames(2)
	_check("once recharged it says so", shield.note() == "就绪" and not shield.dimmed)
	shield.activated.emit()
	_check("and works again", int(shell.game_host.snapshot()["shield_hits"]) == 1)

	shell.game_host.find_child("Player", true, false).set_meta("hp", 40)
	shell.game_host.find_child("Boss", true, false).set_meta("hp", 500)
	await _frames(2)
	_check("the bars follow health as it changes", _text(game, "VitalValue") == "40 / 100" and is_equal_approx(game.find_child("VitalMeter", true, false).ratio, 0.4) and is_equal_approx(game.find_child("BossMeter", true, false).ratio, 0.25))

	Input.action_press(In.ACCEPT)
	await _frames(2)
	shell.dispatch(In.MENU)
	_check("pausing lets go of the boost", shell.current_id() == &"pause" and shell.game_host.snapshot()["boost"] == false)
	Input.action_release(In.ACCEPT)
	shell.dispatch(In.BACK)
	await _frames(2)
	_check("and resuming does not bring it back by itself", shell.current_id() == &"game" and shell.game_host.snapshot()["boost"] == false)

	shell.go(&"game", {"game": "survivor"})
	await _frames(3)
	state = shell.game_host.snapshot()
	_check("starting another game ends and records the one before", int(store.stats("shooter")["runs"]) == 1 and shell.game_host.game_id() == "survivor")
	_check("the survivor HUD counts down three minutes and shows level and kills", _text(game, "Title") == "长夜草原 · 剩余时间" and _text(game, "Time") == "03:00" and _text(game, "VitalValue") == "100 / 100" and _hud_stat(game, "level") == "1" and _hud_stat(game, "kills") == "0" and int(state["max_hp"]) == 100 and not state.has("shield_hits"))
	_check("it has no tools, only the HUD and pause buttons", game.find_child("Boost", true, false) == null and game.find_child("Shield", true, false) == null and game.find_child("Tower_arrow", true, false) == null and not game.find_child("Boss", true, false).visible and game.find_child("PauseButton", true, false) != null)
	shell.dispatch(In.X)
	shell.dispatch(In.ACCEPT)
	shell.dispatch(In.RB)
	_check("buttons the game does not use do nothing and never reach the shell", shell.current_id() == &"game" and shell.game_host.is_running())
	shell.free()

# ---- pause ----

func _test_pause_flow() -> void:
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	var finished: Array = []
	shell.game_host.run_finished.connect(func(id: String, result: Dictionary, _record: Dictionary) -> void: finished.append([id, bool(result.get("aborted", false))]))
	shell.go(&"menu", {"game": "tower_defense"})
	shell.dispatch(In.ACCEPT)
	var game := shell.current_screen() as LauncherGameScreen
	await _frames(4)
	shell.dispatch(In.ACCEPT)
	await _frames(2)

	shell.dispatch(In.BACK)
	var pause := shell.current_screen() as LauncherPauseScreen
	var frozen := float(shell.game_host.snapshot()["play_seconds"])
	await _frames(4)
	_check("B pauses instead of quitting", pause != null and shell.game_host.is_running() and shell.game_host.is_paused() and is_equal_approx(float(shell.game_host.snapshot()["play_seconds"]), frozen))
	_check("the run is neither ended nor recorded", finished.is_empty() and not store.has_played("tower_defense"))
	_check("pause is drawn over the frozen stage without the navigation", shell.backdrop_layer() == &"game" and shell.game_host.visible and not shell.find_child("Nav", false, false).visible and not game.visible)
	_check("it names the game and shows the run so far", _text(pause, "GameName") == "隘口守卫" and _text(pause, "RunClock").begins_with("时间 00:0") and _text(pause, "Score") == "100" and _text(pause, "Played").begins_with("已游玩 00:0") and _text(pause, "Heading") == "已暂停")
	_check("resume is focused", pause.row == 0 and pause.find_child("Row0", true, false).focused and pause.find_child("Row0", true, false).label_text() == "继续游戏" and pause.find_child("Row1", true, false).label_text() == "重新开始" and pause.find_child("Row2", true, false).label_text() == "主音量" and pause.find_child("Row3", true, false).label_text() == "退出到游戏菜单")
	_check("the controls of the paused game are listed", pause.find_child("Control_place", true, false) != null and pause.find_child("Control_tower", true, false) != null and pause.find_child("Control_boost", true, false) == null)
	_check("the footer offers confirm and resume", pause.footer_captions() == PackedStringArray(["确认", "继续游戏"]))
	shell.dispatch(In.RB)
	shell.dispatch(In.Y)
	_check("pause is modal", shell.current_id() == &"pause")

	shell.dispatch(In.BACK)
	await _frames(3)
	_check("B resumes the same run", shell.current_id() == &"game" and shell.game_host.is_running() and not shell.game_host.is_paused() and float(shell.game_host.snapshot()["play_seconds"]) > frozen and int(shell.game_host.snapshot()["gold"]) == 100 and finished.is_empty())
	_check("the HUD is back with the run's state", game.find_child("Hud", true, false).visible and _hud_stat(game, "gold") == "100")
	shell.dispatch(In.MENU)
	_check("Menu pauses too", shell.current_id() == &"pause" and shell.game_host.is_paused())
	shell.dispatch(In.ACCEPT)
	_check("accept on resume resumes", shell.current_id() == &"game" and not shell.game_host.is_paused())
	game.find_child("PauseButton", true, false).activated.emit()
	_check("the on-screen pause button pauses", shell.current_id() == &"pause")
	shell.dispatch(In.MENU)
	# Delivered the way the window delivers it: to the whole tree at once.
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(1)
	_check("losing window focus pauses", shell.current_id() == &"pause" and shell.game_host.is_paused() and shell.current_screen().is_inside_tree())
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(1)
	_check("losing it again while paused changes nothing", shell.current_id() == &"pause" and finished.is_empty())
	shell.dispatch(In.BACK)
	game.pause_on_focus_loss = false
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(1)
	_check("a tool can turn that off", shell.current_id() == &"game" and not shell.game_host.is_paused())
	game.pause_on_focus_loss = true
	shell.dispatch(In.MENU)

	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	var volume: Node = pause.find_child("Row2", true, false)
	_check("the volume row shows the stored volume", pause.row == 2 and volume.value == Guide.VOLUME_DEFAULT and volume.find_child("Number", true, false).text == "8")
	shell.dispatch(In.LEFT)
	var master := AudioServer.get_bus_index(&"Master")
	_check("left lowers the master volume, stores it and applies it", volume.value == 7 and int(store.setting(Guide.SETTING_MASTER_VOLUME)) == 7 and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(master)), 0.7))
	for i in 5:
		shell.dispatch(In.RIGHT)
	_check("right raises it and stops at full", volume.value == 10 and int(store.setting(Guide.SETTING_MASTER_VOLUME)) == 10)
	volume.find_child("Segment4", true, false).activated.emit()
	_check("clicking a segment sets it", volume.value == 4 and int(store.setting(Guide.SETTING_MASTER_VOLUME)) == 4)
	volume.find_child("Segment4", true, false).activated.emit()
	_check("clicking the current segment steps one down", volume.value == 3)
	shell.dispatch(In.ACCEPT)
	_check("accept on the volume row does nothing", shell.current_id() == &"pause" and not pause.is_asking())
	shell.dispatch(In.RIGHT)
	_check("left and right leave the other rows alone", volume.value == 4)
	shell.dispatch(In.UP)
	shell.dispatch(In.LEFT)
	_check("and do nothing on them", pause.row == 1 and volume.value == 4)

	shell.dispatch(In.ACCEPT)
	var dialog: Node = shell.find_child("ConfirmDialog", true, false)
	_check("restart asks first, with cancel focused", pause.is_asking() and pause.asking == &"restart" and shell.has_overlay() and dialog != null and dialog.focus == 0 and dialog.find_child("Cancel", true, false).focused and not dialog.find_child("Confirm", true, false).focused and dialog.find_child("Title", true, false).text == "重新开始？")
	shell.dispatch(In.ACCEPT)
	_check("accepting the default cancels", not pause.is_asking() and not shell.has_overlay() and shell.current_id() == &"pause" and shell.game_host.is_running() and finished.is_empty() and pause.row == 1)
	shell.dispatch(In.ACCEPT)
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.LEFT)
	shell.dispatch(In.DOWN)
	dialog = shell.find_child("ConfirmDialog", true, false)
	_check("directions move between the two buttons", dialog.focus == 1 and dialog.find_child("Confirm", true, false).focused)
	shell.dispatch(In.RB)
	_check("the dialog is modal", pause.is_asking() and shell.current_id() == &"pause")
	shell.dispatch(In.ACCEPT)
	await _frames(3)
	_check("confirming restarts: the old run is recorded once and a new one is live", shell.current_id() == &"game" and finished == [["tower_defense", true]] and int(store.stats("tower_defense")["runs"]) == 1 and shell.game_host.is_running() and not shell.game_host.is_paused() and int(shell.game_host.snapshot()["gold"]) == 150 and float(shell.game_host.snapshot()["play_seconds"]) < frozen + 1.0)
	_check("the new run starts with a fresh HUD", game.phase == &"playing" and _text(game, "Score") == "150" and game.tower_index == 0 and game.cursor_at == Vector2(480, 270) and not shell.has_overlay())

	shell.dispatch(In.MENU)
	pause = shell.current_screen()
	shell.dispatch(In.UP)
	for i in 5:
		shell.dispatch(In.DOWN)
	_check("focus stops at quit", pause.row == 3)
	shell.dispatch(In.ACCEPT)
	_check("quit asks first, with cancel focused", pause.asking == &"quit" and shell.find_child("ConfirmDialog", true, false).focus == 0 and shell.find_child("ConfirmDialog", true, false).find_child("Title", true, false).text == "退出到游戏菜单？")
	shell.dispatch(In.BACK)
	_check("B cancels", not pause.is_asking() and shell.current_id() == &"pause" and finished.size() == 1)
	shell.dispatch(In.ACCEPT)
	shell.find_child("DialogScrim", true, false).activated.emit()
	_check("clicking outside cancels", not pause.is_asking() and shell.game_host.is_running())
	pause.find_child("Row3", true, false).activated.emit()
	shell.find_child("ConfirmDialog", true, false).find_child("Cancel", true, false).activated.emit()
	_check("clicking cancel cancels", not pause.is_asking() and shell.game_host.is_running() and finished.size() == 1)
	shell.dispatch(In.ACCEPT)
	shell.find_child("ConfirmDialog", true, false).find_child("Confirm", true, false).hovered.emit()
	_check("hovering a button focuses it", shell.find_child("ConfirmDialog", true, false).focus == 1)
	shell.dispatch(In.ACCEPT)
	await _frames(2)
	var menu := shell.current_screen() as LauncherMenuScreen
	_check("confirming quits to the menu of that game", menu != null and menu.game_id == "tower_defense" and not shell.game_host.is_running() and not shell.game_host.visible and shell.game_host.game_id() == "" and not shell.has_overlay())
	_check("the quit run is recorded once, as a quit", finished == [["tower_defense", true], ["tower_defense", true]] and int(store.stats("tower_defense")["runs"]) == 2 and int(store.stats("tower_defense")["clears"]) == 0 and store.achievements("tower_defense").is_empty())
	_check("the menu already shows it", _row(menu, "start").sub_text().begins_with("上次游玩 今天 ") and store.recents() == ["tower_defense"])
	shell.dispatch(In.BACK)
	_check("back from the menu goes to where the flow started, not into the finished game", shell.current_id() == &"home")
	shell.dispatch(In.BACK)
	_check("and Home is the end of the history", shell.current_id() == &"home" and finished.size() == 2)

	(shell.current_screen() as LauncherHomeScreen).start_game()
	await _frames(3)
	shell.dispatch(In.MENU)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.ACCEPT)
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.ACCEPT)
	_check("a game started straight from Home also quits to its menu", shell.current_id() == &"menu" and finished.size() == 3)
	shell.dispatch(In.BACK)
	_check("and back from there is Home", shell.current_id() == &"home")

	shell.go(&"pause")
	_check("the pause screen with nothing to pause is harmless", shell.current_id() == &"pause" and not shell.game_host.is_running() and _text(shell.current_screen(), "Played") == "")
	shell.dispatch(In.BACK)
	_check("and resume just leaves it", shell.current_id() == &"home" and finished.size() == 3)
	shell.free()

# ---- recording ----

func _test_recorded_exactly_once() -> void:
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	var count := {"finished": 0}
	shell.game_host.run_finished.connect(func(_id: String, _result: Dictionary, _record: Dictionary) -> void: count["finished"] += 1)

	shell.go(&"game", {"game": "survivor"})
	await _frames(3)
	shell.dispatch(In.MENU)
	shell.go(&"home")
	_check("leaving the pause screen by another route ends the run once", not shell.game_host.is_running() and count["finished"] == 1 and _runs(store, "survivor") == 1)
	shell.go(&"home")
	_check("and nothing is recorded twice afterwards", count["finished"] == 1 and _runs(store, "survivor") == 1)

	shell.go(&"game", {"game": "survivor"})
	await _frames(3)
	shell.go(&"library")
	_check("leaving the game screen by another route ends the run once", not shell.game_host.is_running() and count["finished"] == 2 and _runs(store, "survivor") == 2)

	shell.go(&"game", {"game": "survivor"})
	await _frames(3)
	shell.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	_check("closing the window ends and records the live run", not shell.game_host.is_running() and count["finished"] == 3 and _runs(store, "survivor") == 3)
	shell.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	_check("a second close request records nothing more", count["finished"] == 3 and _runs(store, "survivor") == 3)
	_check("the game screen stays put, there is nowhere to go", shell.current_id() == &"game")
	shell.go(&"home")
	_check("and leaving afterwards records nothing more", count["finished"] == 3 and _runs(store, "survivor") == 3)

	shell.go(&"game", {"game": "survivor"})
	await _frames(3)
	shell.dispatch(In.MENU)
	shell.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	_check("closing the window while paused records the run too", count["finished"] == 4 and _runs(store, "survivor") == 4)
	shell.dispatch(In.BACK)
	await _frames(2)
	_check("resuming after that starts over rather than showing a dead stage", shell.current_id() == &"game" and shell.game_host.is_running() and count["finished"] == 4)

	shell.register_pc_mode(PcModeProbe)
	shell.dispatch(In.PC_MODE)
	_check("switching to PC mode pauses the run instead of letting it play unseen", shell.game_host.is_paused() and shell.current_id() == &"pause" and count["finished"] == 4)
	shell.dispatch(In.PC_MODE)
	shell.dispatch(In.BACK)
	await _frames(2)
	_check("and it can be resumed back in console mode", shell.current_id() == &"game" and not shell.game_host.is_paused())

	shell.free()
	var persisted := StoreScript.new(STORE_PATH)
	persisted.load_from_disk()
	_check("tearing the launcher down with a run live records it", _runs(persisted, "survivor") == 5 and float(persisted.stats("survivor")["play_seconds"]) > 0.0)

# ---- result ----

func _test_result_routing() -> void:
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	shell.go(&"menu", {"game": "tower_defense"})
	shell.dispatch(In.ACCEPT)
	var game := shell.current_screen() as LauncherGameScreen
	await _frames(3)

	var ended := await _play_out(game)
	var stats := store.stats("tower_defense")
	_check("the run ends by itself and is recorded once", ended and not shell.game_host.is_running() and int(stats["runs"]) == 1 and int(stats["last_played"]) == NOW)
	_check("the result shows the outcome and the real score", game.find_child("Outcome", true, false).text in ["通关", "失败"] and _text(game, "FinalScore") == Format.score(int(stats["best_score"])) and int(stats["best_score"]) > 0)
	_check("a first score is a new best with nothing to compare against", game.find_child("NewBest", true, false) != null and _text(game, "BestLine") == "")
	_check("achievements unlocked by this run are listed", store.is_unlocked("tower_defense", "first_defense") and game.find_child("Unlocked_first_defense", true, false) != null and game.find_child("Unlocked_first_defense", true, false).find_child("State", true, false).text == "刚刚解锁")
	_check("the HUD and the cursor make way for the result", not game.find_child("Hud", true, false).visible and not game.find_child("Cursor", true, false).visible and game.find_child("ResultStats", true, false).get_child_count() == 4)
	_check("it offers retry, game menu and home, with retry focused", game.find_child("ResultRow0", true, false).label_text() == "再来一局" and game.find_child("ResultRow1", true, false).label_text() == "返回游戏菜单" and game.find_child("ResultRow2", true, false).label_text() == "返回首页" and game.find_child("ResultRow0", true, false).focused and game.footer_captions() == PackedStringArray(["确认", "返回游戏菜单"]))
	shell.dispatch(In.MENU)
	shell.dispatch(In.RB)
	shell.dispatch(In.UP)
	_check("the result is modal and cannot be paused", shell.current_id() == &"game" and game.phase == &"result" and game.result_row == 0)

	shell.dispatch(In.DOWN)
	shell.dispatch(In.ACCEPT)
	_check("game menu leads to that game's menu", shell.current_id() == &"menu" and (shell.current_screen() as LauncherMenuScreen).game_id == "tower_defense" and shell.game_host.game_id() == "")
	_check("nothing more was recorded on the way", int(store.stats("tower_defense")["runs"]) == 1)
	shell.dispatch(In.BACK)
	_check("back from there is Home, not the finished game", shell.current_id() == &"home")

	var first_best := int(stats["best_score"])
	(shell.current_screen() as LauncherHomeScreen).hero_id = "tower_defense"
	(shell.current_screen() as LauncherHomeScreen).start_game()
	await _frames(3)
	shell.game_host.perform("place_tower", {"tower": "arrow", "position": Vector2(10, 10)})
	shell.game_host.perform("place_tower", {"tower": "arrow", "position": Vector2(20, 10)})
	shell.game_host.perform("place_tower", {"tower": "arrow", "position": Vector2(30, 10)})
	ended = await _play_out(game)
	_check("a lower score is not a new best and says what the best is", ended and int(store.stats("tower_defense")["best_score"]) == first_best and game.find_child("NewBest", true, false) == null and _text(game, "BestLine") == "最高分 %s" % Format.score(first_best))
	_check("achievements already held are not announced again", game.find_child("Unlocked_first_defense", true, false) == null)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	_check("focus stops at the last action", game.result_row == 2 and game.find_child("ResultRow2", true, false).focused)
	shell.dispatch(In.ACCEPT)
	_check("home leads Home with that game selected", shell.current_id() == &"home" and (shell.current_screen() as LauncherHomeScreen).hero_id == "tower_defense" and not shell.game_host.visible)

	shell.dispatch(In.ACCEPT)
	await _frames(3)
	ended = await _play_out(game)
	game.find_child("ResultRow0", true, false).activated.emit()
	await _frames(3)
	_check("retry starts a fresh run on the same screen", ended and shell.current_id() == &"game" and game.phase == &"playing" and shell.game_host.is_running() and game.find_child("Outcome", true, false) == null and game.find_child("Hud", true, false).visible and int(shell.game_host.snapshot()["gold"]) == 150 and int(store.stats("tower_defense")["runs"]) == 3)
	ended = await _play_out(game)
	shell.dispatch(In.BACK)
	_check("B on the result goes to the game menu", ended and shell.current_id() == &"menu" and int(store.stats("tower_defense")["runs"]) == 4)
	shell.free()

## Let the real runtime play itself out, only faster.
func _play_out(game: LauncherGameScreen) -> bool:
	Engine.time_scale = 30.0
	var ended := await _until(func() -> bool: return game.phase == &"result", 60.0)
	Engine.time_scale = 1.0
	return ended

# ---- English ----

func _test_english() -> void:
	var store := _fresh_store()
	store.set_setting("lang", "en")
	var shell := _boot(store)
	await _frames(2)
	shell.go(&"menu", {"game": "tower_defense"})
	var menu := shell.current_screen() as LauncherMenuScreen
	_check("the menu is in English", _row(menu, "start").label_text() == "Start game" and _row(menu, "start").sub_text() == "Not played yet" and _row(menu, "how").label_text() == "How to play" and menu.footer_captions() == PackedStringArray(["Start", "Add to favourites", "Back"]))
	_check("the Latin name is the title and is not repeated under it", menu.find_child("Title", true, false).text == "GATEWATCH" and not menu.find_child("LatinName", true, false).visible)
	shell.dispatch(In.DOWN)
	_check("controls and rules are in English", menu.find_child("Control_place", true, false).find_child("Label", true, false).text == "Place tower" and menu.find_child("Control_cursor", true, false).find_child("Pad", true, false).get_child(0).text == "Left stick / D-pad")
	shell.dispatch(In.UP)
	shell.dispatch(In.ACCEPT)
	var game := shell.current_screen() as LauncherGameScreen
	await _frames(3)
	_check("the HUD is in English", _text(game, "Title") == "GATEWATCH · Time" and _text(game, "VitalLabel") == "Base" and game.find_child("Tower_arrow", true, false).caption() == "Arrow" and _text(game, "ToolNote") == "Arrow · Single target, cheap · Damage 12 · Range 180" and game.find_child("PauseButton", true, false).caption() == "Pause")
	shell.dispatch(In.MENU)
	var pause := shell.current_screen() as LauncherPauseScreen
	_check("pause is in English", _text(pause, "Heading") == "Paused" and pause.find_child("Row0", true, false).label_text() == "Resume" and pause.find_child("Row2", true, false).label_text() == "Master volume" and _text(pause, "Played").begins_with("Played 00:0"))
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.ACCEPT)
	var dialog: Node = shell.find_child("ConfirmDialog", true, false)
	_check("the confirmation is in English", dialog.find_child("Title", true, false).text == "Quit to the game menu?" and dialog.find_child("Cancel", true, false).find_child("Label", true, false).text == "Cancel" and dialog.find_child("Confirm", true, false).find_child("Label", true, false).text == "Quit")
	shell.dispatch(In.BACK)
	shell.dispatch(In.BACK)
	await _frames(2)
	var ended := await _play_out(game)
	_check("the result is in English", ended and game.find_child("Outcome", true, false).text in ["Cleared", "Defeated"] and game.find_child("ResultRow0", true, false).label_text() == "Play again" and game.find_child("ResultRow1", true, false).label_text() == "Back to game menu" and game.find_child("ResultRow2", true, false).label_text() == "Back to Home" and game.find_child("NewBest", true, false).text == "New best")
	shell.free()

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
	_release_all()
	var packed: PackedScene = load(str(ProjectSettings.get_setting("application/run/main_scene")))
	var shell: LauncherRoot = packed.instantiate()
	shell.store = store
	shell.now_provider = func() -> int: return NOW
	root.add_child(shell)
	return shell

func _release_all() -> void:
	for action in In.ALL:
		Input.action_release(action)

func _row(screen: Node, id: String) -> LauncherControls.FocusRow:
	return screen.find_child("Row_%s" % id, true, false)

func _text(screen: Node, node_name: String) -> String:
	return str(screen.find_child(node_name, true, false).text)

## Value of a stat cell in the menu pane.
func _stat(screen: Node, id: String) -> String:
	return str(screen.find_child("Pane", true, false).find_child("Stat_%s" % id, true, false).get_node("Value").text)

## Value of a counter at the top right of the HUD.
func _hud_stat(game: Node, field: String) -> String:
	return str(game.find_child("Stats", true, false).get_node("Stat_%s/Value" % field).text)

func _runs(store: LauncherStore, game_id: String) -> int:
	return int(store.stats(game_id)["runs"])

## The runtime node of the live run, for the few checks that have to look past the snapshot.
func _run_node(shell: LauncherRoot) -> Node:
	return shell.game_host.find_child("GameSession", true, false).get_child(0)

func _frames(count: int) -> void:
	for i in count:
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
