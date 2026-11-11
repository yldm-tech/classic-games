extends SceneTree

## Headless tests of the console launcher: store, catalog, formatting, strings, the GameSession live-run contract, and the shell with Home and the game screen driven through LauncherRoot.dispatch exactly as a key or gamepad press would.
## Run: make launcher-test GODOT=/path/to/godot

const RootScript := preload("res://launcher/launcher_root.gd")
const StoreScript := preload("res://launcher/launcher_store.gd")
const Catalog := preload("res://launcher/launcher_catalog.gd")
const Format := preload("res://launcher/launcher_format.gd")
const In := preload("res://launcher/launcher_input.gd")
const Tokens := preload("res://launcher/launcher_tokens.gd")
const Strings := preload("res://i18n/strings.gd")
const LauncherTable := preload("res://i18n/launcher_strings.gd")
const GameSessionScript := preload("res://runtime/game_session.gd")

const STORE_PATH := "user://launcher-test.json"
## 2026-11-11 10:30:00 UTC, a moment that is not within an hour of local midnight in any time zone, so "ten minutes ago" is the same calendar day wherever the test runs. Every test that needs "now" uses this instead of the wall clock.
const NOW := 1794393000
const DAY := 86400
## Names, in any spelling, that belong to the design prototype's sample games and must never ship.
const FORBIDDEN_NAMES := ["雪球大作战", "铁血双雄", "爆破迷宫", "砖城坦克", "椰岛冲冲冲", "SNOWBALL BRAWL", "IRON DUO", "BLAST MAZE", "BRICK FORT", "COCONUT DASH", "HD REMASTER", "原版", "街机"]

class PcModeProbe:
	extends Control
	var shell: Node
	var actions: Array[StringName] = []
	func setup(p_shell: Node) -> void:
		shell = p_shell
	func handle_action(action: StringName) -> bool:
		actions.append(action)
		return true

var _passed := 0
var _failed := 0

func _initialize() -> void:
	# These tests assert exact shelves, counts and orders, so they pin the three games they were written against: a game added under games/ must not change what they see.
	LauncherCatalog.limit_to(["shooter", "survivor", "tower_defense"])
	_test_store_defaults_and_round_trip()
	_test_store_survives_bad_files()
	_test_store_run_records()
	_test_catalog_integrity()
	_test_achievement_rules()
	_test_format()
	_test_strings()
	_test_project_settings()
	_test_bindings()
	await _test_session_live_run()
	await _test_main_scene_boots()
	await _test_home_navigation()
	await _test_home_with_history()
	await _test_game_updates_stats()
	await _test_shell_hooks()
	_remove_store_files()
	print("launcher_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

# ---- store ----

func _fresh_store() -> LauncherStore:
	_remove_store_files()
	var store := StoreScript.new(STORE_PATH)
	store.load_from_disk()
	return store

func _remove_store_files() -> void:
	for suffix in ["", ".tmp", ".corrupt"]:
		if FileAccess.file_exists(STORE_PATH + suffix):
			DirAccess.remove_absolute(STORE_PATH + suffix)

func _test_store_defaults_and_round_trip() -> void:
	var store := _fresh_store()
	_check("missing file is a fresh profile", store.recents().is_empty() and store.favorites().is_empty() and not store.recovered_from_corruption)
	_check("unplayed game has zeroed stats", store.stats("shooter") == StoreScript.DEFAULT_STATS and not store.has_played("shooter"))
	_check("unset setting returns the fallback", store.setting("lang", "zh") == "zh")
	var sections: Array[StringName] = []
	store.changed.connect(func(section: StringName) -> void: sections.append(section))
	store.set_setting("lang", "en")
	store.set_favorite("survivor", true)
	store.record_run("shooter", {"score": 1200, "play_seconds": 61.5, "cleared": true}, NOW)
	store.unlock("shooter", "sector_clear", NOW)
	store.set_binding("launcher_accept", [KEY_J])
	_check("every mutation announces its section", sections.has(StoreScript.SECTION_SETTINGS) and sections.has(StoreScript.SECTION_FAVORITES) and sections.has(StoreScript.SECTION_STATS) and sections.has(StoreScript.SECTION_RECENTS) and sections.has(StoreScript.SECTION_ACHIEVEMENTS) and sections.has(StoreScript.SECTION_BINDINGS))
	_check("atomic write leaves no temporary file", FileAccess.file_exists(STORE_PATH) and not FileAccess.file_exists(STORE_PATH + ".tmp"))
	var written: Variant = JSON.parse_string(FileAccess.get_file_as_string(STORE_PATH))
	_check("file is versioned JSON", written is Dictionary and int(written.get("version", 0)) == StoreScript.VERSION)

	var reloaded := StoreScript.new(STORE_PATH)
	reloaded.load_from_disk()
	var stats := reloaded.stats("shooter")
	_check("settings round-trip", reloaded.setting("lang") == "en")
	_check("favourites round-trip", reloaded.is_favorite("survivor") and reloaded.favorites() == ["survivor"])
	_check("stats round-trip", int(stats["best_score"]) == 1200 and int(stats["runs"]) == 1 and int(stats["clears"]) == 1 and is_equal_approx(float(stats["play_seconds"]), 61.5) and int(stats["last_played"]) == NOW)
	_check("recents round-trip", reloaded.recents() == ["shooter"])
	_check("achievements round-trip", reloaded.is_unlocked("shooter", "sector_clear") and reloaded.unlocked_count() == 1 and int(reloaded.achievements("shooter")["sector_clear"]) == NOW)
	_check("bindings round-trip", reloaded.bindings() == {"launcher_accept": [KEY_J]})
	_check("unlocking twice reports false", not reloaded.unlock("shooter", "sector_clear", NOW + 5))
	reloaded.clear_binding("launcher_accept")
	_check("clearing a binding removes the override", reloaded.bindings().is_empty())
	reloaded.wipe_progress()
	_check("wipe keeps settings and drops progress", reloaded.setting("lang") == "en" and reloaded.recents().is_empty() and reloaded.favorites().is_empty() and reloaded.unlocked_count() == 0 and not reloaded.has_played("shooter"))

func _test_store_survives_bad_files() -> void:
	_remove_store_files()
	_write(STORE_PATH, "{ this is not json")
	var store := StoreScript.new(STORE_PATH)
	store.load_from_disk()
	_check("corrupt file loads as a fresh profile", store.recovered_from_corruption and store.recents().is_empty())
	_check("corrupt file is set aside, not overwritten", FileAccess.file_exists(STORE_PATH + ".corrupt") and FileAccess.get_file_as_string(STORE_PATH + ".corrupt") == "{ this is not json")
	store.set_favorite("shooter", true)
	var again := StoreScript.new(STORE_PATH)
	again.load_from_disk()
	_check("store is writable again after recovery", again.is_favorite("shooter") and not again.recovered_from_corruption)

	_remove_store_files()
	_write(STORE_PATH, JSON.stringify({"version": StoreScript.VERSION + 1, "favorites": ["shooter"]}))
	var newer := StoreScript.new(STORE_PATH)
	newer.load_from_disk()
	_check("a newer file version is not misread", newer.recovered_from_corruption and newer.favorites().is_empty())

	_remove_store_files()
	_write(STORE_PATH, JSON.stringify({"version": 1, "favorites": "shooter", "recents": ["survivor", 7, "survivor"], "stats": {"shooter": "many", "survivor": {"runs": 2, "best_score": -5}}, "settings": [1, 2]}))
	var odd := StoreScript.new(STORE_PATH)
	odd.load_from_disk()
	_check("wrongly typed sections fall back to defaults", not odd.recovered_from_corruption and odd.favorites().is_empty() and odd.setting("lang", "zh") == "zh")
	_check("list entries are filtered and de-duplicated", odd.recents() == ["survivor"])
	_check("stat values are clamped to sane ranges", odd.stats("shooter") == StoreScript.DEFAULT_STATS and int(odd.stats("survivor")["runs"]) == 2 and int(odd.stats("survivor")["best_score"]) == 0)

	_remove_store_files()
	_write(STORE_PATH, "[1, 2, 3]")
	var array_file := StoreScript.new(STORE_PATH)
	array_file.load_from_disk()
	_check("a JSON file of the wrong shape is treated as corrupt", array_file.recovered_from_corruption)

func _test_store_run_records() -> void:
	var store := _fresh_store()
	var first := store.record_run("shooter", {"score": 500, "play_seconds": 30.0, "cleared": false}, NOW)
	var second := store.record_run("survivor", {"score": 90, "play_seconds": 12.0, "cleared": true, "aborted": true}, NOW + 10)
	var third := store.record_run("shooter", {"score": 300, "play_seconds": 20.0, "cleared": true}, NOW + 20)
	_check("first score is a new best", first["new_best"] and int(first["previous_best"]) == 0)
	_check("lower score keeps the best", not third["new_best"] and int(store.stats("shooter")["best_score"]) == 500)
	_check("runs and play time accumulate", int(store.stats("shooter")["runs"]) == 2 and is_equal_approx(float(store.stats("shooter")["play_seconds"]), 50.0))
	_check("a quit run counts time and score but not a clear", second["new_best"] and int(store.stats("survivor")["clears"]) == 0 and int(store.stats("survivor")["runs"]) == 1)
	_check("recents are most recent first without duplicates", store.recents() == ["shooter", "survivor"])
	var index := store.remove_recent("shooter")
	_check("removing a recent keeps its stats", index == 0 and store.recents() == ["survivor"] and int(store.stats("shooter")["runs"]) == 2)
	store.restore_recent("shooter", index)
	_check("a removal can be undone in place", store.recents() == ["shooter", "survivor"])
	_check("removing an unlisted game reports -1", store.remove_recent("tower_defense") == -1)
	for i in StoreScript.MAX_RECENTS + 4:
		store.record_run("game_%d" % i, {"score": 1}, NOW + 100 + i)
	_check("recents are capped", store.recents().size() == StoreScript.MAX_RECENTS)

func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()

# ---- catalog, format, strings ----

func _test_catalog_integrity() -> void:
	var games := Catalog.all()
	_check("catalog offers the three runtimes", games.size() == 3)
	var ids := {}
	var runtimes := {}
	var complete := true
	var art_ready := true
	var achievements_ok := true
	var serialized := JSON.stringify(games)
	for game in games:
		ids[game["id"]] = true
		runtimes[str(game["runtime"]).split("@")[0]] = true
		for field in ["name", "genre", "tagline"]:
			if Catalog.text(game, field, "zh") == "" or str((game[field] as Dictionary).get("en", "")) == "":
				complete = false
		var initials := str(game["initials"])
		if initials == "" or initials != initials.to_lower() or not initials.is_valid_identifier():
			complete = false
		var players: Dictionary = game["players"]
		if int(players["min"]) < 1 or int(players["max"]) < int(players["min"]):
			complete = false
		for key in ["title", "shadow", "glow"]:
			if not Color.html_is_valid(str((game["colors"] as Dictionary).get(key, ""))):
				art_ready = false
		for key in ["top", "bottom", "primary", "secondary"]:
			if not Color.html_is_valid(str((game["art"] as Dictionary).get(key, ""))):
				art_ready = false
		if not str((game["art"] as Dictionary).get("motif", "")) in ["orbit", "swarm", "road"]:
			art_ready = false
		if GameSessionScript.baseline_payload(str(game["runtime"])).is_empty():
			complete = false
		var achievement_ids := {}
		for achievement: Dictionary in game["achievements"]:
			achievement_ids[achievement["id"]] = true
			if Catalog.text(achievement, "name", "zh") == "" or str((achievement["name"] as Dictionary).get("en", "")) == "" or Catalog.text(achievement, "desc", "zh") == "" or str((achievement["desc"] as Dictionary).get("en", "")) == "":
				achievements_ok = false
			for key in (achievement["when"] as Dictionary):
				if not key in ["cleared", "min"]:
					achievements_ok = false
		if achievement_ids.size() != (game["achievements"] as Array).size() or achievement_ids.is_empty():
			achievements_ok = false
	_check("game ids are unique", ids.size() == games.size())
	_check("each game runs a different runtime", runtimes.keys() == ["shooter", "survivor", "tower_defense"])
	_check("every game has zh and en names, genre, tagline, initials and a real player count", complete)
	_check("every game has valid accent colours and a known art motif", art_ready)
	_check("every achievement is named in both languages and uses only result fields", achievements_ok)
	var clean := true
	for name in FORBIDDEN_NAMES:
		if serialized.to_upper().contains(str(name).to_upper()) or JSON.stringify(LauncherTable.TABLE).to_upper().contains(str(name).to_upper()):
			clean = false
	_check("no prototype sample title or remaster framing is shipped", clean)
	_check("lookups", Catalog.has("survivor") and Catalog.by_id("nope").is_empty() and Catalog.ids() == ["shooter", "survivor", "tower_defense"])
	_check("single letter matches the first initial only", Catalog.matches(Catalog.by_id("shooter"), "x") and not Catalog.matches(Catalog.by_id("shooter"), "h"))
	_check("longer queries match anywhere, case-insensitively", Catalog.matches(Catalog.by_id("shooter"), "HX") and Catalog.matches(Catalog.by_id("survivor"), "") and not Catalog.matches(Catalog.by_id("survivor"), "zz"))
	_check("player label", Catalog.players_label({"players": {"min": 1, "max": 1}}) == "1P" and Catalog.players_label({"players": {"min": 1, "max": 2}}) == "1–2P")
	_check("unknown locale falls back to zh", Catalog.text(Catalog.by_id("shooter"), "name", "ja") == "星环巡航")

func _test_achievement_rules() -> void:
	_check("a finished run earns the participation achievement only", Catalog.earned("shooter", {"score": 100, "cleared": false}) == ["first_sortie"])
	_check("a clear with a high score earns all three", Catalog.earned("shooter", {"score": 2400, "cleared": true}) == ["first_sortie", "sector_clear", "high_score"])
	_check("a quit run earns nothing", Catalog.earned("shooter", {"score": 5000, "cleared": true, "aborted": true}).is_empty())
	_check("minimums read runtime fields", Catalog.earned("survivor", {"level": 3, "kills": 12, "cleared": false}) == ["first_watch", "level_three"])
	_check("combined conditions need both", not Catalog.earned("tower_defense", {"cleared": true, "base_hp": 19, "kills": 27}).has("untouched") and Catalog.earned("tower_defense", {"cleared": true, "base_hp": 20, "kills": 27}).has("untouched"))
	_check("unknown game earns nothing", Catalog.earned("nope", {"cleared": true}).is_empty())
	_check("achievement total counts every definition", Catalog.achievement_total() == 11)

func _test_format() -> void:
	_check("score grouping", Format.score(0) == "0" and Format.score(999) == "999" and Format.score(1000) == "1,000" and Format.score(128450) == "128,450" and Format.score(1234567) == "1,234,567")
	_check("run clock", Format.clock(0.0) == "00:00" and Format.clock(154.9) == "02:34")
	_check("play time", Format.play_time(20.0, "zh") == "不到 1 分钟" and Format.play_time(300.0, "zh") == "5m" and Format.play_time(11520.0, "en") == "3h 12m")
	_check("never played reads as new", Format.when_day(0, NOW, "zh") == "新" and Format.when_time(0, NOW, "en") == "New")
	_check("relative days", Format.when_day(NOW - 60, NOW, "zh") == "今天" and Format.when_day(NOW - DAY, NOW, "zh") == "昨天" and Format.when_day(NOW - 3 * DAY, NOW, "zh") == "3 天前" and Format.when_day(NOW - 3 * DAY, NOW, "en") == "3 days ago")
	var stamp := Format.when_time(NOW - 60, NOW, "zh")
	_check("relative day with time of day", stamp.begins_with("今天 ") and stamp.length() == 8 and stamp[5] == ":")

func _test_strings() -> void:
	var zh: Dictionary = LauncherTable.TABLE["zh"]
	var en: Dictionary = LauncherTable.TABLE["en"]
	var same_keys := zh.size() == en.size()
	var prefixed := true
	var placeholders := true
	for key: String in zh:
		if not en.has(key):
			same_keys = false
			continue
		if not key.begins_with("launcher."):
			prefixed = false
		if str(zh[key]).count("%") != str(en[key]).count("%"):
			placeholders = false
	_check("zh and en define the same launcher keys", same_keys)
	_check("every launcher key is namespaced", prefixed)
	_check("format placeholders agree between languages", placeholders)
	_check("launcher strings are served by the project's Strings", Strings.t("zh", "launcher.nav.library") == "游戏库" and Strings.t("en", "launcher.nav.library") == "Library")
	_check("a language the launcher has not translated falls back to zh", Strings.t("ja", "launcher.nav.home") == "首页")
	_check("formatting goes through Strings.fmt", Strings.fmt("zh", "launcher.home.achievements_sub_fmt", [2, 11]) == "全部游戏 2 / 11 已解锁")
	_check("the offered languages are exactly the translated ones", Strings.LOCALES == LauncherTable.TABLE.keys())

# ---- project and input ----

func _test_project_settings() -> void:
	_check("canvas is 1920x1080", int(ProjectSettings.get_setting("display/window/size/viewport_width")) == 1920 and int(ProjectSettings.get_setting("display/window/size/viewport_height")) == 1080)
	_check("canvas scales as a whole and keeps 16:9", ProjectSettings.get_setting("display/window/stretch/mode") == "canvas_items" and ProjectSettings.get_setting("display/window/stretch/aspect") == "keep")
	_check("launcher is the main scene", ProjectSettings.get_setting("application/run/main_scene") == "res://launcher/launcher.tscn")
	var complete := true
	for action in In.ALL:
		if not InputMap.has_action(action) or InputMap.action_get_events(action).is_empty():
			complete = false
	_check("every launcher action is in the input map", complete)
	_check("accept is on Enter and the A button", In.keycodes(In.ACCEPT).has(KEY_ENTER) and _has_button(In.ACCEPT, JOY_BUTTON_A))
	_check("back is on Escape and the B button", In.keycodes(In.BACK).has(KEY_ESCAPE) and _has_button(In.BACK, JOY_BUTTON_B))
	_check("shoulders and face buttons are bound", _has_button(In.LB, JOY_BUTTON_LEFT_SHOULDER) and _has_button(In.RB, JOY_BUTTON_RIGHT_SHOULDER) and _has_button(In.X, JOY_BUTTON_X) and _has_button(In.Y, JOY_BUTTON_Y) and _has_button(In.MENU, JOY_BUTTON_START) and _has_button(In.VIEW, JOY_BUTTON_BACK))
	_check("directions are on the d-pad", _has_button(In.UP, JOY_BUTTON_DPAD_UP) and _has_button(In.DOWN, JOY_BUTTON_DPAD_DOWN) and _has_button(In.LEFT, JOY_BUTTON_DPAD_LEFT) and _has_button(In.RIGHT, JOY_BUTTON_DPAD_RIGHT))
	_check("F11 toggles PC mode", In.keycodes(In.PC_MODE) == [KEY_F11])
	_check("a key press maps to its action", In.pressed_action(_key(KEY_DOWN)) == In.DOWN and In.pressed_action(_key(KEY_ESCAPE)) == In.BACK and In.pressed_action(_key(KEY_F5)) == &"")
	var echo := _key(KEY_ENTER)
	echo.echo = true
	var held := _key(KEY_DOWN)
	held.echo = true
	_check("only directions repeat while held", In.pressed_action(echo) == &"" and In.pressed_action(held) == In.DOWN)

func _test_bindings() -> void:
	In.apply_bindings({"launcher_accept": [KEY_J], "no_such_action": [KEY_K], "launcher_back": "broken"})
	_check("a stored binding replaces the keyboard keys only", In.keycodes(In.ACCEPT) == [KEY_J] and _has_button(In.ACCEPT, JOY_BUTTON_A))
	_check("malformed entries are ignored", In.keycodes(In.BACK).has(KEY_ESCAPE))
	InputMap.load_from_project_settings()
	_check("project defaults can be restored", In.keycodes(In.ACCEPT).has(KEY_ENTER))

func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event

func _has_button(action: StringName, button: JoyButton) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == button:
			return true
	return false

# ---- GameSession live-run contract ----

func _test_session_live_run() -> void:
	var session: GameSession = GameSessionScript.new()
	root.add_child(session)
	var seen := {"started": [], "ended": [], "errors": [], "paused": []}
	session.game_started.connect(func(info: Dictionary) -> void: seen["started"].append(info))
	session.game_ended.connect(func(result: Dictionary) -> void: seen["ended"].append(result))
	session.game_error.connect(func(error: Dictionary) -> void: seen["errors"].append(error))
	session.paused_changed.connect(func(paused: bool) -> void: seen["paused"].append(paused))

	_check("baseline payload names the runtime and carries its DSL", GameSessionScript.baseline_payload("survivor@1.0.0").get("runtime") == "survivor@1.0.0" and GameSessionScript.baseline_payload("survivor@1.0.0").get("mod") is Dictionary)
	_check("no baseline for an unknown or malformed runtime", GameSessionScript.baseline_payload("racing@1.0.0").is_empty() and GameSessionScript.baseline_payload("../x@1").is_empty())
	_check("an unknown runtime reports an error instead of starting", not session.start_run({"runtime": "racing@1.0.0", "mod": {"meta": {}}}) and seen["errors"].size() == 1 and seen["errors"][0].get("code") == "UNKNOWN_RUNTIME" and not session.is_running())

	var payload := GameSessionScript.baseline_payload("tower_defense@1.0.0")
	var original := JSON.stringify(payload)
	_check("a live run starts and stays mounted", session.start_run(payload) and session.is_running() and seen["started"].size() == 1 and seen["ended"].is_empty() and session.get_child_count() == 1)
	_check("the runtime is centred on the stage", (session.get_child(0) as Node2D).position == Vector2(GameSessionScript.STAGE_SIZE) / 2.0)
	await _frames(5)
	var before := session.snapshot()
	_check("snapshot carries score, play time and runtime fields", float(before["play_seconds"]) > 0.0 and before.has("score") and before.has("gold") and before.has("base_hp") and (before["tower_ids"] as Array).has("arrow"))
	var gold := int(before["gold"])
	_check("place_tower spends gold through the session", session.perform("place_tower", {"tower": "arrow", "position": Vector2(480, 200)}) and int(session.snapshot()["gold"]) == gold - 50)
	_check("an unaffordable or unknown command is refused", not session.perform("place_tower", {"tower": "nope", "position": Vector2(10, 10)}) and not session.perform("shield") and not session.perform("dance"))
	session.set_paused(true)
	var frozen := float(session.snapshot()["play_seconds"])
	await _frames(5)
	_check("pausing freezes play time and commands", session.is_paused() and is_equal_approx(float(session.snapshot()["play_seconds"]), frozen) and not session.perform("place_tower", {"tower": "arrow", "position": Vector2(300, 300)}) and seen["paused"] == [true])
	session.set_paused(false)
	await _frames(3)
	_check("resuming continues the clock", not session.is_paused() and float(session.snapshot()["play_seconds"]) > frozen and seen["paused"] == [true, false])
	session.end_run()
	_check("ending a run reports an aborted result once", seen["ended"].size() == 1 and seen["ended"][0].get("aborted") == true and seen["ended"][0].get("runtime_ref") == "tower_defense@1.0.0" and not session.is_running())
	session.end_run()
	_check("ending twice does nothing", seen["ended"].size() == 1)
	_check("the caller's payload is never mutated", JSON.stringify(payload) == original)

	# A stage with one weak enemy and a tower next to the road finishes by itself.
	var quick := {"runtime": "tower_defense@1.0.0", "mod": {
		"meta": {"runtime": "tower_defense", "runtime_version": "1.0.0", "fork_of": null},
		"stage": {"background": "grassland", "starting_gold": 100, "base_hp": 5},
		"path": {"points": [[-100, 0], [100, 0]]},
		"towers": {"arrow": {"type": "arrow", "cost": 50, "damage": 50, "range": 400, "cooldown": 0.1}},
		"placements": {"a": {"tower": "arrow", "position": [0, -40]}},
		"waves": {"one": {"enemy": "grunt", "count": 1, "hp": 5, "speed": 40, "reward": 3, "start": 0, "interval": 1}},
	}}
	seen["ended"].clear()
	_check("a second run replaces the first", session.start_run(quick) and session.get_child_count() == 1)
	var finished := await _until(func() -> bool: return not seen["ended"].is_empty(), 20.0)
	var result: Dictionary = seen["ended"][0] if finished else {}
	_check("a run that clears ends by itself with its result", finished and result.get("cleared") == true and result.get("aborted") == false and int(result.get("kills", 0)) == 1 and int(result.get("score", 0)) == 153 and float(result.get("play_seconds", 0.0)) > 0.0)
	_check("the finished stage stays mounted but stopped", not session.is_running() and session.get_child_count() == 1 and session.get_child(0).process_mode == Node.PROCESS_MODE_DISABLED)
	session.clear_run()
	await _frames(2)
	_check("clearing unmounts the stage", session.get_child_count() == 0 and session.snapshot().is_empty())
	session.free()

# ---- shell ----

func _boot(store: LauncherStore) -> LauncherRoot:
	var packed: PackedScene = load(str(ProjectSettings.get_setting("application/run/main_scene")))
	var shell: LauncherRoot = packed.instantiate()
	shell.store = store
	shell.now_provider = func() -> int: return NOW
	root.add_child(shell)
	return shell

func _test_main_scene_boots() -> void:
	var shell := _boot(_fresh_store())
	await _frames(2)
	_check("main scene is the launcher root", shell is LauncherRoot and shell.name == "LauncherRoot")
	_check("launcher opens on Home", shell.current_id() == &"home" and shell.current_screen().visible)
	_check("every design screen id is registered", shell.screen(&"library") != null and shell.screen(&"achievements") != null and shell.screen(&"settings") != null and shell.screen(&"menu") != null and shell.screen(&"pause") != null and shell.screen(&"game") != null)
	var nav := shell.find_child("Nav", false, false) as Control
	_check("top navigation shows the four tabs with Home selected", nav.visible and nav.find_child("Tab_home", true, false).selected and not nav.find_child("Tab_library", true, false).selected and nav.find_child("Tab_achievements", true, false) != null and nav.find_child("Tab_settings", true, false) != null)
	var clock := shell.clock_text()
	_check("clock shows HH:MM", clock.length() == 5 and clock[2] == ":" and clock.left(2).is_valid_int() and clock.right(2).is_valid_int())
	_check("Home asks for the hero backdrop of its game", shell.backdrop_layer() == &"hero" and shell.current_screen().backdrop()["game"] == "shooter")
	_check("the game stage is hidden outside a game", not shell.game_host.visible and not shell.game_host.is_running())
	shell.free()

func _test_home_navigation() -> void:
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	var home: LauncherHomeScreen = shell.current_screen()
	_check("with nothing played the hero is the first catalog game", home.hero_id == "shooter" and home.find_child("Title", true, false).text == "星环巡航")
	_check("hero shows genre, players, Latin name and tagline from the catalog", home.find_child("Meta", true, false).text == "ARENA SHOOTER · 1P" and home.find_child("LatinName", true, false).text == "ORBIT PATROL" and home.find_child("Tagline", true, false).text != "")
	_check("unplayed game says so and shows no progress", home.find_child("Row0", true, false).sub_text() == "尚未游玩" and not home.find_child("Row0", true, false).progress_visible())
	_check("achievement row counts real unlocks", home.find_child("Row2", true, false).sub_text() == "全部游戏 0 / 11 已解锁")
	_check("empty shelf states that nothing was played", home.find_child("Empty", true, false) != null and home.find_child("Card_shooter", true, false) == null and home.find_child("AllGames", true, false).caption_text() == "共 3 款")
	_check("footer offers start, favourite and options", home.footer_captions() == PackedStringArray(["开始", "加入收藏", "选项"]))
	_check("first row starts focused", home.zone == &"menu" and home.row == 0 and home.find_child("Row0", true, false).focused and not home.find_child("Row1", true, false).focused)

	shell.dispatch(In.DOWN)
	_check("down moves focus to the next row", home.row == 1 and home.find_child("Row1", true, false).focused and not home.find_child("Row0", true, false).focused)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	_check("focus stops at the last row", home.row == 2)
	shell.dispatch(In.UP)
	_check("up moves focus back", home.row == 1)
	shell._unhandled_input(_key(KEY_UP))
	_check("a real key event takes the same path", home.row == 0)
	home.find_child("Row2", true, false).hovered.emit()
	_check("mouse hover moves the same focus", home.row == 2 and home.find_child("Row2", true, false).focused)

	shell.dispatch(In.RIGHT)
	_check("right selects the next game and returns focus to start", home.hero_id == "survivor" and home.row == 0 and home.find_child("Title", true, false).text == "长夜草原" and shell.current_screen().backdrop()["game"] == "survivor")
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.RIGHT)
	_check("right past the last game focuses the all-games tile", home.hero_id == "tower_defense" and home.zone == &"tile" and home.find_child("AllGames", true, false).focused and not home.find_child("Row0", true, false).focused)
	shell.dispatch(In.RIGHT)
	_check("the tile is the end of the row", home.zone == &"tile")
	shell.dispatch(In.ACCEPT)
	_check("accept on the tile opens the library", shell.current_id() == &"library")
	_check("the library keeps the navigation over the blurred key art", shell.current_screen() is LauncherLibraryScreen and shell.find_child("Nav", false, false).visible and shell.backdrop_layer() == &"blur")
	shell.dispatch(In.BACK)
	_check("back returns Home", shell.current_id() == &"home")
	shell.dispatch(In.LEFT)
	shell.dispatch(In.LEFT)
	_check("left walks back through the games and stops at the first", home.hero_id == "shooter" and home.zone == &"menu")

	shell.dispatch(In.RB)
	_check("RB switches to the next top-level tab", shell.current_id() == &"library" and shell.find_child("Tab_library", true, false).selected)
	shell.dispatch(In.RT)
	_check("RT does the same", shell.current_id() == &"achievements")
	shell.dispatch(In.LT)
	shell.dispatch(In.LT)
	_check("LT switches back through the tabs", shell.current_id() == &"home")
	shell.dispatch(In.LB)
	_check("tabs wrap around", shell.current_id() == &"settings")
	shell.find_child("Tab_home", true, false).activated.emit()
	_check("clicking a tab opens it", shell.current_id() == &"home")

	shell.dispatch(In.DOWN)
	shell.dispatch(In.ACCEPT)
	_check("the game-menu row opens the menu screen for the selected game", shell.current_id() == &"menu" and not shell.find_child("Nav", false, false).visible)
	shell.dispatch(In.BACK)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.ACCEPT)
	_check("the achievements row opens achievements", shell.current_id() == &"achievements")
	shell.dispatch(In.BACK)

	shell.dispatch(In.Y)
	_check("Y adds the selected game to favourites and says so", store.is_favorite("shooter") and shell.toast_text() == "已收藏「星环巡航」" and shell.can_undo())
	_check("the hero and footer reflect the favourite", home.find_child("FavoriteTag", true, false).visible and home.footer_captions()[1] == "取消收藏")
	shell.dispatch(In.X)
	_check("X undoes it while the toast is up", not store.is_favorite("shooter") and shell.toast_text() == "" and not home.find_child("FavoriteTag", true, false).visible)
	home.find_child("Hint_y", true, false).activated.emit()
	_check("clicking a footer hint is the same as pressing its button", store.is_favorite("shooter"))
	shell.find_child("Undo", true, false).activated.emit()
	_check("clicking undo on the toast works too", not store.is_favorite("shooter"))

	shell.dispatch(In.MENU)
	_check("Menu opens the options panel for the selected game", home.is_panel_open() and shell.has_overlay() and home.zone == &"panel" and shell.find_child("Heading", true, false).text == "星环巡航")
	_check("an unplayed game has no remove-from-recents option", home.panel_labels() == PackedStringArray(["加入收藏", "游戏菜单", "查看成就", "切换到 PC 模式", "设置"]))
	shell.dispatch(In.DOWN)
	_check("the panel has its own focus", home.panel_row == 1 and shell.find_child("PanelRow1", true, false).focused and home.row == 0)
	shell.dispatch(In.RB)
	_check("the panel is modal", shell.current_id() == &"home" and home.is_panel_open())
	shell.dispatch(In.UP)
	shell.dispatch(In.ACCEPT)
	_check("accept runs the focused option and the panel follows the new state", store.is_favorite("shooter") and home.is_panel_open() and home.panel_labels()[0] == "取消收藏")
	shell.dispatch(In.BACK)
	_check("back closes the panel and returns focus to the rows", not home.is_panel_open() and not shell.has_overlay() and home.zone == &"menu" and shell.current_id() == &"home")
	shell.dispatch(In.MENU)
	shell.find_child("Scrim", true, false).activated.emit()
	_check("clicking outside closes the panel", not home.is_panel_open())
	shell.dispatch(In.MENU)
	shell.dispatch(In.UP)
	shell.dispatch(In.ACCEPT)
	_check("the settings option opens settings", shell.current_id() == &"settings")
	shell.dispatch(In.BACK)
	_check("returning Home finds the panel closed", shell.current_id() == &"home" and not home.is_panel_open())
	shell.free()

func _test_home_with_history() -> void:
	var store := _fresh_store()
	store.record_run("survivor", {"score": 120, "play_seconds": 95.0}, NOW - 3 * DAY)
	store.record_run("tower_defense", {"score": 1850, "play_seconds": 240.0, "cleared": true}, NOW - 600)
	store.unlock("tower_defense", "gate_held", NOW - 600)
	store.unlock("tower_defense", "stale_id_from_an_old_build", NOW - 600)
	store.set_favorite("survivor", true)
	var shell := _boot(store)
	await _frames(2)
	var home: LauncherHomeScreen = shell.current_screen()
	_check("hero is the most recently played game", home.hero_id == "tower_defense")
	_check("start row shows the real last-played time and best score", home.find_child("Row0", true, false).sub_text().begins_with("上次游玩 今天 ") and home.find_child("Row0", true, false).sub_text().ends_with("· 最高分 1,850"))
	_check("progress is the share of that game's achievements", home.find_child("Row0", true, false).progress_visible() and is_equal_approx(home.achievement_ratio("tower_defense"), 0.25) and is_zero_approx(home.achievement_ratio("survivor")))
	_check("unlock count ignores ids the catalog no longer has", home.find_child("Row2", true, false).sub_text() == "全部游戏 1 / 11 已解锁")
	var first: Node = home.find_child("Card_tower_defense", true, false)
	var second: Node = home.find_child("Card_survivor", true, false)
	_check("the shelf lists exactly the played games, most recent first", first != null and second != null and home.find_child("Card_shooter", true, false) == null and home.find_child("Empty", true, false) == null and first.get_index() < second.get_index())
	_check("cards show when each game was played", first.note_text() == "今天" and second.note_text() == "3 天前")
	_check("the hero's card is the selected one", first.selected and not second.selected and is_equal_approx(first.progress(), 0.25))
	_check("the favourite badge follows the store", second.is_favorite_shown() and not first.is_favorite_shown())
	second.activated.emit()
	_check("clicking a card selects that game", home.hero_id == "survivor" and second.selected and not first.selected and home.find_child("FavoriteTag", true, false).visible)
	_check("games never played stay reachable after the recents", home.selectable_ids() == ["tower_defense", "survivor", "shooter"])

	shell.dispatch(In.MENU)
	_check("a played game can be removed from recents", home.panel_labels().has("从「最近游玩」移除"))
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.ACCEPT)
	_check("removing closes the panel, drops the card and moves the hero on", not home.is_panel_open() and store.recents() == ["tower_defense"] and home.find_child("Card_survivor", true, false) == null and home.hero_id == "tower_defense" and shell.toast_text() == "已从「最近游玩」移除「长夜草原」")
	_check("its record is kept", int(store.stats("survivor")["best_score"]) == 120)
	shell.undo()
	_check("undo puts the card back where it was and selects it again", store.recents() == ["tower_defense", "survivor"] and home.hero_id == "survivor" and home.find_child("Card_survivor", true, false).selected)

	shell.set_locale("en")
	await _frames(2)
	home = shell.current_screen()
	_check("switching language rebuilds the shell in English and remembers it", shell.find_child("Tab_library", true, false).find_child("Label", true, false).text == "Library" and store.setting("lang") == "en" and home.find_child("Row0", true, false).label_text() == "Start game")
	_check("English uses the Latin name as the title and hides the duplicate subtitle", home.find_child("Title", true, false).text == "GATEWATCH" and not home.find_child("LatinName", true, false).visible)
	shell.free()

	var reopened := _boot(store)
	await _frames(1)
	_check("the stored language is used at the next start", reopened.locale == "en")
	reopened.free()

func _test_game_updates_stats() -> void:
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	var home: LauncherHomeScreen = shell.current_screen()
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.RIGHT)
	_check("tower defense is selected for the run", home.hero_id == "tower_defense")
	shell.dispatch(In.ACCEPT)
	var game: LauncherGameScreen = shell.current_screen() as LauncherGameScreen
	_check("start launches the selected game inside the launcher", shell.current_id() == &"game" and game != null and shell.game_host.is_running() and shell.game_host.game_id() == "tower_defense")
	_check("the game screen shows the stage without the navigation", shell.backdrop_layer() == &"game" and shell.game_host.visible and not shell.find_child("Nav", false, false).visible)
	await _frames(6)
	_check("the HUD follows the live run", game.find_child("Title", true, false).text.begins_with("隘口守卫") and game.find_child("Score", true, false).text == "150" and game.find_child("Stat_gold", true, false).get_node("Value").text == "150" and game.find_child("Tower_arrow", true, false).caption() == "箭塔")
	_check("nothing is recorded while the run is live", not store.has_played("tower_defense") and store.recents().is_empty())

	shell.dispatch(In.RB)
	_check("the game owns the buttons while it runs", shell.current_id() == &"game")
	shell.dispatch(In.ACCEPT)
	_check("accept places the chosen tower at the cursor through the host", int(shell.game_host.snapshot()["gold"]) == 60)
	shell.dispatch(In.MENU)
	var paused_at := float(shell.game_host.snapshot()["play_seconds"])
	await _frames(4)
	_check("Menu pauses the run", shell.game_host.is_paused() and shell.current_id() == &"pause" and is_equal_approx(float(shell.game_host.snapshot()["play_seconds"]), paused_at))
	shell.dispatch(In.MENU)
	_check("Menu again resumes", not shell.game_host.is_paused() and shell.current_id() == &"game")

	# Let the real runtime play itself out, only faster.
	Engine.time_scale = 30.0
	var ended := await _until(func() -> bool: return game.phase == &"result", 60.0)
	Engine.time_scale = 1.0
	var stats := store.stats("tower_defense")
	_check("the run ends by itself and shows a result", ended and game.find_child("Outcome", true, false) != null and not shell.game_host.is_running())
	_check("the finished run is recorded once", int(stats["runs"]) == 1 and int(stats["last_played"]) == NOW and float(stats["play_seconds"]) > 1.0 and store.recents() == ["tower_defense"])
	_check("best score is the run's real score", int(stats["best_score"]) > 0 and game.find_child("FinalScore", true, false).text == Format.score(int(stats["best_score"])) and game.find_child("NewBest", true, false) != null)
	_check("finishing a run unlocks what it earned", store.is_unlocked("tower_defense", "first_defense"))
	var first_best := int(stats["best_score"])

	shell.dispatch(In.ACCEPT)
	await _frames(4)
	_check("play again starts a fresh run", game.phase == &"playing" and shell.game_host.is_running() and game.find_child("Outcome", true, false) == null and int(shell.game_host.snapshot()["gold"]) == 150)
	shell.go(&"home", {"game": "tower_defense"})
	stats = store.stats("tower_defense")
	_check("leaving for Home ends the run with that game selected", shell.current_id() == &"home" and home.hero_id == "tower_defense" and not shell.game_host.is_running() and not shell.game_host.visible)
	_check("the quit run is recorded too", int(stats["runs"]) == 2 and int(stats["best_score"]) == first_best)
	_check("Home now shows the played game on the shelf", home.find_child("Card_tower_defense", true, false) != null and home.find_child("Empty", true, false) == null and home.find_child("Row0", true, false).sub_text().contains(Format.score(first_best)) and home.find_child("Row0", true, false).progress_visible())

	var persisted := StoreScript.new(STORE_PATH)
	persisted.load_from_disk()
	_check("everything the run produced is on disk", int(persisted.stats("tower_defense")["runs"]) == 2 and persisted.is_unlocked("tower_defense", "first_defense") and persisted.recents() == ["tower_defense"])

	shell.dispatch(In.ACCEPT)
	await _frames(3)
	shell.go(&"home")
	_check("leaving the game screen by any route ends and records the run", not shell.game_host.is_running() and int(store.stats("tower_defense")["runs"]) == 3)
	shell.free()

func _test_shell_hooks() -> void:
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	shell.toast("plain")
	_check("a toast without undo offers none", shell.toast_text() == "plain" and not shell.can_undo() and not shell.find_child("Undo", true, false).visible)
	shell.dismiss_toast()
	shell.register_pc_mode(null)
	shell.dispatch(In.PC_MODE)
	_check("without a registered PC mode F11 only says it is unavailable", shell.mode == &"console" and shell.toast_text() == "PC 模式还没有做好")
	shell.dismiss_toast()
	var modes: Array[StringName] = []
	shell.mode_changed.connect(func(mode: StringName) -> void: modes.append(mode))
	shell.register_pc_mode(PcModeProbe)
	shell.dispatch(In.PC_MODE)
	var probe := shell.find_child("PcMode", false, false) as PcModeProbe
	_check("a registered PC mode takes over the canvas", shell.mode == &"pc" and probe != null and probe.visible and probe.shell == shell and not shell.find_child("Screens", false, false).visible and not shell.find_child("Nav", false, false).visible)
	shell.dispatch(In.DOWN)
	_check("PC mode receives the actions instead of the console screen", probe.actions == [In.DOWN] and (shell.current_screen() as LauncherHomeScreen).row == 0)
	shell.dispatch(In.PC_MODE)
	_check("F11 switches back", shell.mode == &"console" and not probe.visible and shell.find_child("Screens", false, false).visible and shell.find_child("Nav", false, false).visible and modes == [&"pc", &"console"])

	shell._unhandled_input(_key(KEY_TAB))
	shell._process(shell.VIEW_HOLD_SECONDS + 0.1)
	_check("holding View toggles PC mode", shell.mode == &"pc")
	shell.dispatch(In.PC_MODE)

	var seen: Array[StringName] = []
	shell.screen_changed.connect(func(id: StringName) -> void: seen.append(id))
	shell.go(&"menu", {"game": "survivor"})
	shell.go(&"achievements")
	shell.go(&"menu")
	shell.go(&"pause")
	shell.go_back()
	_check("back unwinds to where a screen was opened from", shell.current_id() == &"menu")
	shell.go_back()
	_check("and then to the tab underneath", shell.current_id() == &"achievements")
	shell.go_back()
	_check("with no history back goes Home", shell.current_id() == &"home" and seen.size() == 7)
	shell.free()
	_check("the font cache is released with the launcher", Tokens._fonts.is_empty())

# ---- helpers ----

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
