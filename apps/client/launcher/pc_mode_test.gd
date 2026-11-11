extends SceneTree

## Headless tests of the launcher's PC mode: the filtering and ordering rules, entering and leaving the mode with the selection kept, the boot setting, the detail page and the library for fresh and played profiles, favourites, starting a game and coming back, keyboard traversal, reflow with many games, and both languages. The shell is booted from the main scene and driven through LauncherRoot.dispatch and the widgets' own signals, the way a key press or a click would.
## Run: make pc-mode-test GODOT=/path/to/godot

const StoreScript := preload("res://launcher/launcher_store.gd")
const Catalog := preload("res://launcher/launcher_catalog.gd")
const In := preload("res://launcher/launcher_input.gd")
const Lib := preload("res://launcher/pc_library.gd")
const PcMode := preload("res://launcher/pc_mode.gd")
const PC := preload("res://launcher/pc_controls.gd")

const STORE_PATH := "user://pc-mode-test.json"
## The same fixed moment launcher_test uses: not within an hour of local midnight in any time zone.
const NOW := 1794393000
const DAY := 86400

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_test_library_rules()
	await _test_toggle_keeps_selection()
	await _test_default_mode()
	await _test_search_sort_filter()
	await _test_detail_fresh()
	await _test_detail_played()
	await _test_favorites()
	await _test_menus()
	await _test_launch_and_return()
	await _test_console_excursions()
	await _test_settings_excursion()
	await _test_keyboard()
	await _test_real_events()
	await _test_reflow_with_many_games()
	await _test_locales()
	_remove_store_files()
	print("pc_mode_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

# ---- fixtures ----

func _fresh_store() -> LauncherStore:
	_remove_store_files()
	var store := StoreScript.new(STORE_PATH)
	store.load_from_disk()
	return store

## Three games played on different days, one favourite, a few achievements: shooter today (best 1,800), tower defense yesterday (cleared, 2,130), survivor three days ago.
func _played_store() -> LauncherStore:
	var store := _fresh_store()
	store.record_run("survivor", {"score": 240, "play_seconds": 412.0, "cleared": false}, NOW - 3 * DAY)
	store.unlock("survivor", "first_watch", NOW - 3 * DAY)
	store.record_run("tower_defense", {"score": 2130, "play_seconds": 655.0, "cleared": true}, NOW - DAY)
	store.unlock("tower_defense", "first_defense", NOW - DAY)
	store.unlock("tower_defense", "gate_held", NOW - DAY)
	store.record_run("shooter", {"score": 1800, "play_seconds": 388.0, "cleared": false}, NOW - 600)
	store.unlock("shooter", "first_sortie", NOW - 600)
	store.set_favorite("shooter", true)
	return store

func _remove_store_files() -> void:
	for suffix in ["", ".tmp", ".corrupt"]:
		if FileAccess.file_exists(STORE_PATH + suffix):
			DirAccess.remove_absolute(STORE_PATH + suffix)

func _boot(store: LauncherStore) -> LauncherRoot:
	var packed: PackedScene = load(str(ProjectSettings.get_setting("application/run/main_scene")))
	var shell: LauncherRoot = packed.instantiate()
	shell.store = store
	shell.now_provider = func() -> int: return NOW
	root.add_child(shell)
	return shell

## Boot the launcher and switch to PC mode with F11.
func _boot_pc(store: LauncherStore) -> LauncherRoot:
	var shell := _boot(store)
	await _frames(2)
	shell.dispatch(In.PC_MODE)
	await _frames(2)
	return shell

func _pc(shell: LauncherRoot) -> LauncherPcMode:
	return shell.find_child("PcMode", false, false) as LauncherPcMode

func _detail(shell: LauncherRoot) -> Control:
	return _pc(shell).find_child("Detail", true, false)

func _library(shell: LauncherRoot) -> LauncherPcLibraryView:
	return _pc(shell).find_child("Library", true, false) as LauncherPcLibraryView

func _text(parent: Node, node_name: String) -> String:
	var node := parent.find_child(node_name, true, false)
	return str(node.get("text")) if node != null else "<missing %s>" % node_name

func _click(parent: Node, node_name: String) -> void:
	(parent.find_child(node_name, true, false) as LauncherControls.Pressable).activated.emit()

## The catalog plus `count` copies of its games under new ids and numbered names.
func _many(count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = Catalog.all().duplicate()
	var real := Catalog.all()
	for index in count:
		var copy: Dictionary = real[index % real.size()].duplicate(true)
		copy["id"] = "%s_%02d" % [copy["id"], index + 2]
		copy["name"] = {"zh": "%s %d" % [copy["name"]["zh"], index + 2], "en": "%s %d" % [copy["name"]["en"], index + 2]}
		out.append(copy)
	return out

func _key(code: Key, ctrl: bool = false, shift: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	event.pressed = true
	return event

func _ids(entries: Array[Dictionary]) -> Array:
	var out: Array = []
	for entry in entries:
		out.append(entry["id"])
	return out

# ---- rules ----

func _test_library_rules() -> void:
	var store := _played_store()
	var games := Catalog.all()
	var shooter := Catalog.by_id("shooter")
	_check("search matches pinyin initials like the catalog does", Lib.matches(shooter, "x") and Lib.matches(shooter, "HX") and not Lib.matches(shooter, "h"))
	_check("search matches the name in either language", Lib.matches(shooter, "星环") and Lib.matches(shooter, "orbit") and Lib.matches(shooter, " Patrol ") and not Lib.matches(shooter, "草原"))
	_check("an empty search matches everything", Lib.matches(shooter, "") and Lib.matches(shooter, "   "))
	_check("categories read the store", Lib.count_in(games, Lib.CAT_ALL, store) == 3 and Lib.count_in(games, Lib.CAT_FAVORITES, store) == 1 and Lib.count_in(games, Lib.CAT_RECENT, store) == 3 and Lib.count_in(games, Lib.CAT_UNPLAYED, store) == 0)
	_check("name order follows the pinyin initials", _ids(Lib.visible(games, store, Lib.CAT_ALL, "", "", Lib.SORT_NAME, "zh")) == ["tower_defense", "survivor", "shooter"])
	_check("recent order puts the last played first", _ids(Lib.visible(games, store, Lib.CAT_ALL, "", "", Lib.SORT_RECENT, "zh")) == ["shooter", "tower_defense", "survivor"])
	_check("progress order puts the most complete first", _ids(Lib.visible(games, store, Lib.CAT_ALL, "", "", Lib.SORT_PROGRESS, "zh")) == ["tower_defense", "shooter", "survivor"])
	_check("time order puts the most played first", _ids(Lib.visible(games, store, Lib.CAT_ALL, "", "", Lib.SORT_TIME, "zh")) == ["tower_defense", "survivor", "shooter"])
	_check("category, search and genre combine", _ids(Lib.visible(games, store, Lib.CAT_FAVORITES, "", "", Lib.SORT_NAME, "zh")) == ["shooter"] and _ids(Lib.visible(games, store, Lib.CAT_ALL, "c", "", Lib.SORT_NAME, "zh")) == ["survivor"] and _ids(Lib.visible(games, store, Lib.CAT_ALL, "", "TOWER DEFENSE", Lib.SORT_NAME, "zh")) == ["tower_defense"] and Lib.visible(games, store, Lib.CAT_FAVORITES, "c", "", Lib.SORT_NAME, "zh").is_empty())
	var genres := Lib.genres(games, "zh")
	_check("genres are listed once with their counts", genres.size() == 3 and genres[0] == {"key": "ARENA SHOOTER", "label": "飞行射击", "count": 1})
	_check("achievement ratio counts defined achievements only", is_equal_approx(Lib.achievement_ratio(Catalog.by_id("tower_defense"), store), 0.5) and Lib.unlocked_count(shooter, store) == 1)
	var fresh := _fresh_store()
	_check("a fresh profile has everything unplayed and unsorted ties keep catalog order", Lib.count_in(games, Lib.CAT_UNPLAYED, fresh) == 3 and _ids(Lib.visible(games, fresh, Lib.CAT_ALL, "", "", Lib.SORT_RECENT, "zh")) == ["shooter", "survivor", "tower_defense"])

# ---- mode switching ----

func _test_toggle_keeps_selection() -> void:
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	var home := shell.current_screen() as LauncherHomeScreen
	shell.dispatch(In.RIGHT)
	_check("Home selected the second game", home.hero_id == "survivor")
	shell.dispatch(In.PC_MODE)
	await _frames(2)
	var pc := _pc(shell)
	_check("F11 opens the registered PC mode over the hidden console layers", shell.mode == &"pc" and pc != null and pc.visible and not shell.find_child("Screens", false, false).visible and not shell.find_child("Nav", false, false).visible and shell.toast_text() == "")
	_check("PC mode opens on the game Home had selected", pc.selected == "survivor" and pc.view == &"detail" and _text(_detail(shell), "Title") == "长夜草原" and (pc.find_child("Row_survivor", true, false) as PC.GameRow).selected)
	_check("the title strip offers the way back and draws no window buttons", _text(pc.find_child("ConsoleMode", true, false), "Label") == "主机模式" and pc.find_child("Minimize", true, false) == null and pc.find_child("Close", true, false) == null)

	_click(pc, "Row_tower_defense")
	pc.set_view(&"library")
	pc.set_query("a")
	_check("clicking a sidebar game selects it", pc.selected == "tower_defense")
	_click(pc, "ConsoleMode")
	await _frames(2)
	_check("the console button leaves PC mode", shell.mode == &"console" and not pc.visible and shell.find_child("Screens", false, false).visible)
	_check("Home shows the game that was selected in PC mode", shell.current_id() == &"home" and home.hero_id == "tower_defense" and home.find_child("Title", true, false).text == "隘口守卫")

	shell.dispatch(In.LEFT)
	shell.dispatch(In.PC_MODE)
	await _frames(2)
	_check("coming back keeps PC mode's own state and follows Home again", shell.mode == &"pc" and pc == _pc(shell) and pc.view == &"library" and pc.query == "a" and pc.selected == "survivor")

	shell.dispatch(In.PC_MODE)
	shell.go(&"achievements")
	shell.dispatch(In.PC_MODE)
	pc.select("shooter")
	shell.dispatch(In.PC_MODE)
	_check("leaving from another console screen still hands the selection to Home", shell.current_id() == &"achievements" and home.hero_id == "shooter")
	shell.free()

func _test_default_mode() -> void:
	var store := _fresh_store()
	store.set_setting("default_mode", "pc")
	var shell := _boot(store)
	await _frames(2)
	_check("default_mode = pc starts in PC mode", shell.mode == &"pc" and _pc(shell) != null and _pc(shell).visible and _pc(shell).selected == "shooter")
	shell.free()
	store.set_setting("default_mode", "console")
	shell = _boot(store)
	await _frames(2)
	_check("default_mode = console starts in console mode", shell.mode == &"console" and _pc(shell) == null)
	shell.free()
	store.set_setting("default_mode", "tv")
	shell = _boot(store)
	await _frames(2)
	_check("an unknown default_mode falls back to console", shell.mode == &"console")
	shell.free()

# ---- library ----

func _test_search_sort_filter() -> void:
	var store := _played_store()
	var shell := await _boot_pc(store)
	var pc := _pc(shell)
	var library := _library(shell)
	_check("the sidebar lists every game by name with real status lines", pc.result_ids() == ["tower_defense", "survivor", "shooter"] and _text(pc, "ListTitle") == "GAMES" and (pc.find_child("Row_shooter", true, false) as PC.GameRow).status_text() == "上次游玩 今天" and (pc.find_child("Row_survivor", true, false) as PC.GameRow).status_text() == "上次游玩 3 天前")
	_check("categories show real counts", (pc.find_child("Category_all", true, false) as PC.SideRow).count_text() == "3" and (pc.find_child("Category_favorites", true, false) as PC.SideRow).count_text() == "1" and (pc.find_child("Category_unplayed", true, false) as PC.SideRow).count_text() == "0")

	_click(pc, "OpenLibrary")
	await _frames(2)
	_check("the library entry shows the grid", pc.view == &"library" and library.visible and not _detail(shell).visible and library.order() == ["tower_defense", "survivor", "shooter"] and _text(library, "Title") == "全部游戏" and _text(library, "Count") == "3 款")
	var card := library.item("shooter") as PC.LibraryCard
	_check("a card shows name, facts, progress and the favourite", card.name_text() == "星环巡航" and card.meta_text() == "飞行射击 · 1P · 今天" and is_equal_approx(card.progress(), 1.0 / 3.0) and card.is_favorite_shown() and not (library.item("survivor") as PC.LibraryCard).is_favorite_shown())

	var edit := pc.find_child("Edit", true, false) as LineEdit
	edit.text = "c"
	edit.text_changed.emit("c")
	await _frames(1)
	_check("typing in the search field filters the list and the grid", pc.query == "c" and pc.result_ids() == ["survivor"] and library.order() == ["survivor"] and _text(pc, "ListTitle") == "RESULTS · 1" and _text(library, "Count") == "1 款" and pc.find_child("Row_shooter", true, false) == null)
	_check("a filter offers to clear it", (library.find_child("ClearFilters", true, false) as Control).visible)
	pc.set_query("zz")
	await _frames(1)
	_check("no match says so in both places", pc.result_ids().is_empty() and _text(library, "EmptyTitle") == "没有找到「zz」" and _text(pc, "ListEmpty") == "没有符合的游戏" and edit.text == "zz")
	_click(library, "ClearAll")
	await _frames(1)
	_check("clearing brings everything back", pc.query == "" and edit.text == "" and library.order().size() == 3 and not (library.find_child("ClearFilters", true, false) as Control).visible)

	_click(library, "Sort")
	_check("the sort control opens a menu of the four orders", pc.is_menu_open() and pc.menu_labels() == PackedStringArray(["名称", "最近游玩", "成就进度", "游玩时长"]))
	shell.dispatch(In.DOWN)
	shell.dispatch(In.ACCEPT)
	await _frames(1)
	_check("picking an order re-sorts and is remembered", not pc.is_menu_open() and pc.sort == &"recent" and library.order() == ["shooter", "tower_defense", "survivor"] and pc.result_ids() == ["shooter", "tower_defense", "survivor"] and _text(library.find_child("Sort", true, false), "Label") == "最近游玩" and store.setting("pc_sort") == "recent")
	pc.set_sort(&"time")
	_check("time order", library.order() == ["tower_defense", "survivor", "shooter"])

	_click(library, "Genre_2")
	await _frames(1)
	_check("a genre chip filters", pc.genre == "SURVIVAL ACTION" and library.order() == ["survivor"] and (library.find_child("Genre_2", true, false) as PC.Pill).on and not (library.find_child("Genre_0", true, false) as PC.Pill).on)
	_click(library, "Genre_0")
	_click(pc, "Category_favorites")
	await _frames(1)
	_check("a category filters and names the shelf", pc.category == &"favorites" and library.order() == ["shooter"] and _text(library, "Title") == "收藏" and (pc.find_child("Category_favorites", true, false) as PC.SideRow).selected)
	_click(pc, "Category_unplayed")
	await _frames(1)
	_check("an empty category is an honest empty state", library.order().is_empty() and _text(library, "EmptyTitle") == "这里还没有游戏")
	_click(pc, "Category_all")

	_click(library, "ListLayout")
	await _frames(2)
	var row := library.item("tower_defense") as PC.ListRow
	_check("the list layout shows the same games as rows and is remembered", pc.layout == &"list" and row != null and row.name_text() == "隘口守卫" and row.time_text() == "10m" and library.columns() == 1 and store.setting("pc_layout") == "list")
	shell.free()

	var reopened := await _boot_pc(store)
	_check("sort and layout survive a restart", _pc(reopened).sort == &"time" and _pc(reopened).layout == &"list")
	reopened.free()

# ---- detail ----

func _test_detail_fresh() -> void:
	var shell := await _boot_pc(_fresh_store())
	var pc := _pc(shell)
	var detail := _detail(shell)
	_check("a fresh profile opens on the first game", pc.selected == "shooter" and _text(detail, "Title") == "星环巡航" and _text(detail, "Eyebrow") == "ARENA SHOOTER · 1P" and _text(detail, "Tagline") == "清空这片星域，再击落守在尽头的机甲。")
	_check("an unplayed game shows no invented numbers", _text(detail, "Record") == "尚未游玩" and _text(detail, "Summary_best") == "—" and _text(detail, "Summary_progress") == "0%" and _text(detail, "Summary_time") == "—" and detail.find_child("OverviewEmpty", true, false) != null and detail.find_child("Stats", true, false) == null and detail.find_child("RecentUnlocks", true, false) == null)
	_check("the sidebar says it was never played", (pc.find_child("Row_shooter", true, false) as PC.GameRow).status_text() == "尚未游玩" and not (pc.find_child("Row_shooter", true, false) as PC.GameRow).is_favorite_shown())
	_check("the play button starts a game, it does not resume one", _text(detail.find_child("Play", true, false), "Label") == "开始游戏")
	_click(detail, "Tab1")
	await _frames(2)
	var cards := detail.find_child("Achievements", true, false)
	_check("the achievements tab lists the game's real achievements, all locked", pc.tab == 1 and _text(detail, "AchievementCount") == "0 / 3" and cards.get_child_count() == 3 and not (cards.get_child(0) as PC.AchievementCard).unlocked and (cards.get_child(0) as PC.AchievementCard).name_text() == "首次出击" and (cards.get_child(0) as PC.AchievementCard).state_text() == "未解锁")
	shell.free()

func _test_detail_played() -> void:
	var shell := await _boot_pc(_played_store())
	var pc := _pc(shell)
	var detail := _detail(shell)
	pc.select("tower_defense")
	await _frames(2)
	_check("a played game shows its real record", _text(detail, "Title") == "隘口守卫" and _text(detail, "Record").begins_with("上次游玩 昨天 ") and _text(detail, "Summary_best") == "2,130" and _text(detail, "Summary_progress") == "50%" and _text(detail, "Summary_time") == "10m")
	_check("the overview tiles come from the store", _text(detail.find_child("Stat_best", true, false), "Value") == "2,130" and _text(detail.find_child("Stat_runs", true, false), "Value") == "1" and _text(detail.find_child("Stat_clears", true, false), "Value") == "1" and _text(detail.find_child("Stat_time", true, false), "Value") == "10m" and _text(detail.find_child("Stat_progress", true, false), "Value") == "2 / 4" and detail.find_child("OverviewEmpty", true, false) == null)
	_check("recently unlocked achievements are listed", detail.find_child("RecentUnlocks", true, false).get_child_count() == 2)
	_click(detail, "Tab1")
	await _frames(2)
	var cards := detail.find_child("Achievements", true, false)
	var first := cards.find_child("Achievement_first_defense", true, false) as PC.AchievementCard
	var shared_icons := true
	for definition: Dictionary in Catalog.by_id("tower_defense")["achievements"]:
		var card := cards.find_child("Achievement_%s" % definition["id"], true, false) as PC.AchievementCard
		shared_icons = shared_icons and card.icon_kind() == str(definition["icon"]) and card.icon_kind() in LauncherControls.Icon.BADGES
	_check("each card shows its catalog icon, one the shared badge painter draws", shared_icons)
	_check("the achievements tab marks what is unlocked and when", _text(detail, "AchievementCount") == "2 / 4" and cards.get_child_count() == 4 and first.unlocked and first.state_text() == "已解锁 · 昨天" and not (cards.find_child("Achievement_untouched", true, false) as PC.AchievementCard).unlocked)
	_click(detail, "OnlyLocked")
	await _frames(2)
	cards = detail.find_child("Achievements", true, false)
	_check("locked only hides the unlocked ones", pc.only_locked and cards.get_child_count() == 2 and cards.find_child("Achievement_first_defense", true, false) == null and (detail.find_child("OnlyLocked", true, false) as PC.Check).checked)
	shell.store.unlock("tower_defense", "untouched", NOW)
	shell.store.unlock("tower_defense", "full_sweep", NOW)
	await _frames(2)
	_check("the page follows the store, and says when nothing is left locked", _text(detail, "AchievementCount") == "4 / 4" and detail.find_child("AchievementsEmpty", true, false) != null)
	shell.free()

# ---- favourites and menus ----

func _test_favorites() -> void:
	var store := _fresh_store()
	var shell := await _boot_pc(store)
	var pc := _pc(shell)
	var detail := _detail(shell)
	_click(detail, "Favorite")
	_check("the favourite button writes the store and says so", store.is_favorite("shooter") and shell.toast_text() == "已收藏「星环巡航」" and shell.can_undo() and (detail.find_child("Favorite", true, false) as PC.IconButton).icon_kind() == "heart" and (pc.find_child("Row_shooter", true, false) as PC.GameRow).is_favorite_shown())
	var persisted := StoreScript.new(STORE_PATH)
	persisted.load_from_disk()
	_check("the favourite is on disk", persisted.favorites() == ["shooter"])
	shell.dispatch(In.X)
	_check("X undoes it while the toast is up", not store.is_favorite("shooter") and (detail.find_child("Favorite", true, false) as PC.IconButton).icon_kind() == "heart_line")
	shell.dispatch(In.Y)
	_check("Y toggles the selected game's favourite", store.is_favorite("shooter"))
	shell.dismiss_toast()
	pc.set_view(&"library")
	await _frames(2)
	var library := _library(shell)
	(library.item("survivor") as PC.LibraryCard).favorite_pressed.emit()
	_check("a card's heart toggles that game without selecting it", store.is_favorite("survivor") and pc.selected == "shooter" and (library.item("survivor") as PC.LibraryCard).is_favorite_shown() and (pc.find_child("Category_favorites", true, false) as PC.SideRow).count_text() == "2")
	shell.free()

func _test_menus() -> void:
	var store := _played_store()
	var shell := await _boot_pc(store)
	var pc := _pc(shell)
	var opened: Array[String] = []
	pc.folder_opener = func(path: String) -> void: opened.append(path)
	_click(_detail(shell), "More")
	_check("the more button opens the game's menu", pc.is_menu_open() and pc.menu_labels() == PackedStringArray(["开始游戏", "取消收藏", "游戏菜单", "查看成就", "从「最近游玩」移除", "打开存档文件夹"]))
	shell.dispatch(In.RB)
	_check("the menu is modal for the keyboard", pc.is_menu_open() and pc.view == &"detail")
	shell.dispatch(In.BACK)
	_check("Esc closes it", not pc.is_menu_open())

	pc.set_view(&"library")
	await _frames(2)
	var library := _library(shell)
	(library.item("survivor") as PC.LibraryCard).context_requested.emit()
	_check("a right click selects the game and opens its menu, with the way to its page", pc.selected == "survivor" and pc.is_menu_open() and pc.menu_labels()[1] == "查看详情" and pc.menu_labels()[2] == "加入收藏")
	_click(pc.find_child("Menu", true, false), "Item1")
	await _frames(1)
	_check("view details opens the page", not pc.is_menu_open() and pc.view == &"detail" and _text(_detail(shell), "Title") == "长夜草原")
	(pc.find_child("Row_survivor", true, false) as PC.GameRow).context_requested.emit()
	_click(pc.find_child("Menu", true, false), "Item3")
	await _frames(2)
	_check("view achievements opens that tab", pc.tab == 1 and _text(_detail(shell), "AchievementCount") == "1 / 4")
	shell.dispatch(In.MENU)
	shell.dispatch(In.UP)
	shell.dispatch(In.UP)
	shell.dispatch(In.ACCEPT)
	_check("the Menu button opens it too; remove from recents is undoable", not store.recents().has("survivor") and shell.can_undo() and int(store.stats("survivor")["runs"]) == 1)
	shell.undo()
	_check("undo restores the recent", store.recents() == ["shooter", "tower_defense", "survivor"])
	shell.dispatch(In.MENU)
	shell.dispatch(In.UP)
	shell.dispatch(In.ACCEPT)
	_check("open save folder asks the system for the profile's folder", opened.size() == 1 and opened[0] == ProjectSettings.globalize_path("user://"))
	shell.dispatch(In.MENU)
	_click(pc, "Scrim")
	_check("clicking away closes the menu", not pc.is_menu_open())
	shell.free()

# ---- launching ----

func _test_launch_and_return() -> void:
	var store := _fresh_store()
	var shell := await _boot_pc(store)
	var pc := _pc(shell)
	pc.select("tower_defense")
	_click(_detail(shell), "Play")
	await _frames(3)
	_check("play starts the game through the console game screen", shell.mode == &"console" and shell.current_id() == &"game" and shell.game_host.is_running() and shell.game_host.game_id() == "tower_defense" and shell.game_host.visible and not pc.visible and pc.excursion() == &"game")
	shell.dispatch(In.PC_MODE)
	_check("PC mode cannot be entered over a live run", shell.mode == &"console" and shell.game_host.is_running() and shell.toast_text() == "游戏进行中，先退出游戏再切换到 PC 模式")
	shell.dismiss_toast()
	shell.dispatch(In.BACK)
	_check("B pauses the run instead of quitting it", shell.mode == &"console" and shell.current_id() == &"pause" and shell.game_host.is_running() and shell.game_host.is_paused() and pc.excursion() == &"game")
	shell.dispatch(In.PC_MODE)
	_check("nor over a paused one", shell.mode == &"console" and shell.current_id() == &"pause" and shell.game_host.is_paused() and shell.toast_text() == "游戏进行中，先退出游戏再切换到 PC 模式")
	shell.dismiss_toast()
	shell.dispatch(In.BACK)
	await _frames(2)
	_check("resuming keeps the player in the game", shell.mode == &"console" and shell.current_id() == &"game" and shell.game_host.is_running() and not shell.game_host.is_paused())
	await _quit_run(shell)
	_check("quitting the game lands back in PC mode on that game", shell.mode == &"pc" and pc.visible and not shell.game_host.is_running() and not shell.game_host.visible and pc.selected == "tower_defense" and pc.view == &"detail" and pc.excursion() == &"" and shell.current_id() == &"home")
	_check("the run is recorded and shown", int(store.stats("tower_defense")["runs"]) == 1 and _text(_detail(shell), "Record").begins_with("上次游玩 今天 ") and (pc.find_child("Row_tower_defense", true, false) as PC.GameRow).status_text() == "上次游玩 今天" and (pc.find_child("Category_recent", true, false) as PC.SideRow).count_text() == "1")

	pc.set_view(&"library")
	await _frames(2)
	pc.select("shooter")
	(_library(shell).item("tower_defense") as PC.LibraryCard).double_clicked.emit()
	await _frames(3)
	_check("a double click on a card starts that game", shell.mode == &"console" and shell.current_id() == &"game" and shell.game_host.game_id() == "tower_defense" and pc.selected == "tower_defense")
	Engine.time_scale = 30.0
	var game := shell.current_screen() as LauncherGameScreen
	var ended := await _until(func() -> bool: return game.phase == &"result", 60.0)
	Engine.time_scale = 1.0
	_check("a run that ends by itself shows the console result first", ended and shell.mode == &"console")
	shell.dispatch(In.PC_MODE)
	await _frames(2)
	_check("F11 on the result panel returns to PC mode on that game", shell.mode == &"pc" and pc.selected == "tower_defense" and pc.view == &"library" and int(store.stats("tower_defense")["runs"]) == 2)
	shell.dispatch(In.PC_MODE)
	shell.dispatch(In.BACK)
	await _frames(2)
	_check("back from the result goes to the game menu in console mode once the player took over", shell.mode == &"console" and shell.current_id() == &"menu" and (shell.current_screen() as LauncherMenuScreen).game_id == "tower_defense")

	shell.dispatch(In.PC_MODE)
	(pc.find_child("Row_survivor", true, false) as PC.GameRow).double_clicked.emit()
	await _frames(3)
	_check("a double click in the sidebar starts that game", shell.current_id() == &"game" and shell.game_host.game_id() == "survivor")
	await _quit_run(shell)
	_check("and quitting it returns to the library it was started from", shell.mode == &"pc" and pc.view == &"library" and pc.selected == "survivor" and int(store.stats("survivor")["runs"]) == 1)

	pc.play("tower_defense")
	await _frames(3)
	var ended_again := await _play_out(shell)
	_check("PC mode stays aside while the result is shown", ended_again and shell.mode == &"console" and shell.current_id() == &"game" and pc.excursion() == &"game")
	shell.dispatch(In.ACCEPT)
	await _frames(3)
	_check("play again keeps the player in the game", shell.mode == &"console" and shell.current_id() == &"game" and shell.game_host.is_running() and pc.excursion() == &"game" and int(store.stats("tower_defense")["runs"]) == 3)
	ended_again = await _play_out(shell)
	shell.dispatch(In.BACK)
	await _frames(2)
	_check("B on the result of a run started from PC mode returns to PC mode", ended_again and shell.mode == &"pc" and pc.selected == "tower_defense" and pc.excursion() == &"" and shell.current_id() == &"home" and not shell.game_host.visible and int(store.stats("tower_defense")["runs"]) == 4)
	pc.play("tower_defense")
	await _frames(3)
	ended_again = await _play_out(shell)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.ACCEPT)
	await _frames(2)
	_check("so does its game-menu row", ended_again and shell.mode == &"pc" and pc.selected == "tower_defense" and shell.current_id() == &"home")
	pc.play("tower_defense")
	await _frames(3)
	ended_again = await _play_out(shell)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.ACCEPT)
	await _frames(2)
	_check("and its home row", ended_again and shell.mode == &"pc" and pc.selected == "tower_defense" and shell.current_id() == &"home" and int(store.stats("tower_defense")["runs"]) == 6)

	shell.dispatch(In.PC_MODE)
	shell.go(&"achievements")
	shell.dispatch(In.PC_MODE)
	pc.select("survivor")
	pc.play("survivor")
	await _frames(3)
	await _quit_run(shell)
	_check("a run started while the console sat on another screen returns to PC mode all the same", shell.mode == &"pc" and pc.selected == "survivor" and shell.current_id() == &"home")
	pc.open_console(&"game", {"game": "no_such_game"})
	await _frames(3)
	_check("a launch that fails returns to PC mode and says why", shell.mode == &"pc" and pc.excursion() == &"" and shell.current_id() == &"home" and shell.toast_text() == "无法启动「no_such_game」")
	shell.dismiss_toast()
	pc.set_entries(_many(2))
	pc.play("shooter_02")
	_check("a game the catalog cannot run is refused with a message", shell.mode == &"pc" and shell.toast_text() == "无法启动「星环巡航 2」")
	shell.free()

func _test_console_excursions() -> void:
	var shell := await _boot_pc(_played_store())
	var pc := _pc(shell)
	pc.select("survivor")
	_click(pc, "Settings")
	_check("the settings entry opens the console Settings screen", shell.mode == &"console" and shell.current_id() == &"settings" and pc.excursion() == &"settings" and shell.find_child("Nav", false, false).visible)
	shell.dispatch(In.BACK)
	await _frames(1)
	_check("backing out returns to PC mode with the selection intact", shell.mode == &"pc" and pc.selected == "survivor" and pc.excursion() == &"")
	_click(_detail(shell), "GameMenu")
	var menu := shell.current_screen() as LauncherMenuScreen
	_check("the game menu button opens the console game menu for that game", shell.mode == &"console" and shell.current_id() == &"menu" and menu != null and menu.game_id == "survivor" and menu.find_child("Crumb", true, false).text == "长夜草原" and pc.excursion() == &"menu" and (shell.screen(&"home") as LauncherHomeScreen).hero_id == "survivor")
	shell.dispatch(In.BACK)
	_check("and back returns", shell.mode == &"pc" and pc.selected == "survivor" and pc.excursion() == &"")
	_click(_detail(shell), "GameMenu")
	menu.find_child("BackLink", true, false).activated.emit()
	_check("so does the menu's own back link", shell.mode == &"pc" and pc.selected == "survivor")

	_click(_detail(shell), "GameMenu")
	shell.dispatch(In.ACCEPT)
	await _frames(3)
	_check("the game can be started from that menu", shell.mode == &"console" and shell.current_id() == &"game" and shell.game_host.is_running() and shell.game_host.game_id() == "survivor" and pc.excursion() == &"menu")
	shell.dispatch(In.PC_MODE)
	_check("and cannot be left for PC mode while it runs", shell.mode == &"console" and shell.game_host.is_running() and shell.toast_text() == "游戏进行中，先退出游戏再切换到 PC 模式")
	shell.dismiss_toast()
	var runs_before := int(shell.store.stats("survivor")["runs"])
	await _quit_run(shell)
	_check("quitting it goes back to the menu it was started from", shell.mode == &"console" and shell.current_id() == &"menu" and menu.game_id == "survivor" and not shell.game_host.is_running() and int(shell.store.stats("survivor")["runs"]) == runs_before + 1)
	shell.dispatch(In.BACK)
	_check("and back from the menu returns to PC mode, not into the finished game", shell.mode == &"pc" and pc.selected == "survivor" and pc.excursion() == &"" and shell.current_id() == &"home")

	pc.select("tower_defense")
	_click(_detail(shell), "GameMenu")
	shell.dispatch(In.ACCEPT)
	await _frames(3)
	var ended := await _play_out(shell)
	shell.dispatch(In.BACK)
	_check("a finished run started from the menu also goes back to the menu", ended and shell.mode == &"console" and shell.current_id() == &"menu" and menu.game_id == "tower_defense")
	shell.dispatch(In.ACCEPT)
	await _frames(3)
	ended = await _play_out(shell)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.ACCEPT)
	await _frames(2)
	_check("and its home row returns to PC mode", ended and shell.mode == &"pc" and pc.selected == "tower_defense" and pc.excursion() == &"")

	shell.dispatch(In.PC_MODE)
	shell.go(&"library")
	shell.dispatch(In.PC_MODE)
	pc.select("survivor")
	_click(_detail(shell), "GameMenu")
	shell.dispatch(In.BACK)
	_check("back returns to PC mode whatever console screen it was entered from", shell.mode == &"pc" and pc.selected == "survivor" and shell.current_id() == &"home")
	pc.set_tab(1)
	await _frames(1)
	_click(_detail(shell), "AllAchievements")
	_check("all achievements opens the console achievements screen", shell.mode == &"console" and shell.current_id() == &"achievements")
	shell.dispatch(In.PC_MODE)
	_check("F11 during an excursion simply returns", shell.mode == &"pc" and pc.excursion() == &"")
	shell.dispatch(In.PC_MODE)
	shell.go(&"home")
	_check("after that the player's own trip to console mode stays in console mode", shell.mode == &"console" and shell.current_id() == &"home")
	shell.free()

func _test_settings_excursion() -> void:
	var store := _played_store()
	var shell := await _boot_pc(store)
	var pc := _pc(shell)
	pc.select("survivor")
	pc.set_view(&"library")
	pc.set_query("m")
	_click(pc, "Settings")
	shell.dispatch(In.RIGHT)
	var settings := shell.current_screen() as LauncherSettingsScreen
	_check("Settings opens on the language row", settings != null and settings.zone == &"rows" and settings.find_child("Row_lang", true, false) != null and shell.locale == "zh")
	shell.dispatch(In.RIGHT)
	await _frames(2)
	_check("changing the language there keeps the excursion going", shell.locale == "en" and shell.mode == &"console" and shell.current_id() == &"settings" and pc.excursion() == &"settings")
	shell.dispatch(In.BACK)
	shell.dispatch(In.BACK)
	await _frames(2)
	pc = _pc(shell)
	_check("coming back shows PC mode rebuilt in the new language", shell.mode == &"pc" and pc.visible and (pc.find_child("Category_all", true, false) as PC.SideRow).label_text() == "All games" and _text(pc.find_child("ConsoleMode", true, false), "Label") == "Console mode" and (pc.find_child("Row_survivor", true, false) as PC.GameRow).name_text() == "MEADOW VIGIL" and _text(_library(shell), "Title") == "All games" and (pc.find_child("Edit", true, false) as LineEdit).placeholder_text == shell.t("launcher.pc.search.placeholder"))
	_check("with its own state kept", pc.selected == "survivor" and pc.view == &"library" and pc.query == "m" and pc.result_ids() == ["survivor"] and pc.excursion() == &"")

	pc.set_query("")
	_click(pc, "Settings")
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.RIGHT)
	_check("the launch mode row writes default_mode", store.setting("default_mode") == "pc")
	shell.dispatch(In.BACK)
	shell.dispatch(In.BACK)
	_check("and back returns once more", shell.mode == &"pc")
	shell.free()
	var reloaded := StoreScript.new(STORE_PATH)
	reloaded.load_from_disk()
	shell = _boot(reloaded)
	await _frames(2)
	pc = _pc(shell)
	_check("the next start on that profile opens in PC mode, in the chosen language", shell.mode == &"pc" and pc != null and pc.visible and shell.locale == "en" and (pc.find_child("Category_all", true, false) as PC.SideRow).label_text() == "All games" and not shell.find_child("Screens", false, false).visible)
	shell.dispatch(In.PC_MODE)
	shell.go(&"settings")
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.LEFT)
	shell.free()
	reloaded = StoreScript.new(STORE_PATH)
	reloaded.load_from_disk()
	shell = _boot(reloaded)
	await _frames(2)
	_check("and after choosing console there, the start after that is in console mode", reloaded.setting("default_mode") == "console" and shell.mode == &"console" and _pc(shell) == null)
	shell.free()

# ---- keyboard ----

func _test_keyboard() -> void:
	var store := _played_store()
	var shell := await _boot_pc(store)
	var pc := _pc(shell)
	var edit := pc.find_child("Edit", true, false) as LineEdit
	_check("no focus ring before a key is used", pc.zone == &"sidebar" and not pc.focus_visible)
	shell.dispatch(In.DOWN)
	_check("the first key shows the ring on the sidebar", pc.focus_visible and (pc.focused_widget() as PC.Clickable).focus_ring and pc.focused_widget().name == "Category_favorites")
	for i in 3:
		shell.dispatch(In.DOWN)
	_check("down walks the categories and the library entry", pc.focused_widget().name == "OpenLibrary" and pc.selected == "shooter")
	shell.dispatch(In.DOWN)
	_check("reaching a game in the list selects it", pc.focused_widget().name == "Row_tower_defense" and pc.selected == "tower_defense" and _text(_detail(shell), "Title") == "隘口守卫")
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	_check("the list ends at the settings entry", pc.focused_widget().name == "Settings" and pc.selected == "shooter")
	shell.dispatch(In.RIGHT)
	_check("right enters the page at the play button", pc.zone == &"main" and pc.focused_widget().name == "Play" and (pc.focused_widget() as PC.Clickable).focus_ring and not (pc.find_child("Settings", true, false) as PC.Clickable).focus_ring)
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.RIGHT)
	_check("right moves along the buttons", pc.focused_widget().name == "Favorite")
	shell.dispatch(In.ACCEPT)
	_check("Enter presses the focused button", not store.is_favorite("shooter"))
	shell.dismiss_toast()
	shell.dispatch(In.DOWN)
	_check("down goes to the tabs", pc.focused_widget().name.begins_with("Tab"))
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.ACCEPT)
	await _frames(1)
	_check("Enter on a tab opens it and its controls become reachable", pc.tab == 1)
	shell.dispatch(In.DOWN)
	_check("down reaches the tab's own controls", pc.focused_widget().name in ["OnlyLocked", "AllAchievements"])
	shell.dispatch(In.LEFT)
	shell.dispatch(In.LEFT)
	shell.dispatch(In.LEFT)
	_check("left past the first control returns to the sidebar on the selected game", pc.zone == &"sidebar" and pc.focused_widget().name == "Row_shooter")

	shell.dispatch(In.VIEW)
	_check("Tab goes to the next zone", pc.zone == &"main")
	shell.dispatch(In.VIEW)
	_check("then to the search field, which takes typing focus", pc.zone == &"search" and edit.has_focus() and pc.focused_widget() == null)
	_check("Shift+Tab goes back", pc.handle_key(_key(KEY_TAB, false, true)) and pc.zone == &"main" and not edit.has_focus())
	_check("Ctrl+F jumps to the search field", pc.handle_key(_key(KEY_F, true)) and pc.zone == &"search" and edit.has_focus())
	pc._enter_zone(&"sidebar")
	_check("so does the slash key, but not a plain letter", pc.handle_key(_key(KEY_SLASH)) and edit.has_focus() and not pc.handle_key(_key(KEY_F)))
	edit.text = "a"
	edit.text_changed.emit("a")
	pc._on_search_input(_key(KEY_ESCAPE))
	_check("Esc in the field clears the search first", pc.query == "" and edit.text == "" and edit.has_focus())
	pc._on_search_input(_key(KEY_ESCAPE))
	_check("and leaves the field when it is already empty", not edit.has_focus() and pc.zone == &"sidebar")
	pc.focus_search()
	edit.text = "c"
	edit.text_changed.emit("c")
	pc._on_search_input(_key(KEY_ENTER))
	await _frames(1)
	_check("Enter in the field goes to the first result", not edit.has_focus() and pc.selected == "survivor" and pc.zone == &"sidebar" and pc.focused_widget().name == "Row_survivor")
	shell.dispatch(In.BACK)
	_check("Esc outside the field clears the search too", pc.query == "" and pc.result_ids().size() == 3)
	shell.dispatch(In.UP)
	for i in 6:
		shell.dispatch(In.UP)
	_check("up from the top of the sidebar reaches the search field", pc.zone == &"search" and edit.has_focus())
	shell.dispatch(In.DOWN)
	_check("and down leaves it for the list", not edit.has_focus() and pc.zone == &"sidebar")

	shell.dispatch(In.RB)
	await _frames(2)
	_check("the shoulder button switches between page and library", pc.view == &"library")
	shell.dispatch(In.VIEW)
	var library := _library(shell)
	_check("entering the library lands on the selected game's card", pc.zone == &"main" and pc.focused_widget() == library.item(pc.selected))
	pc.select("tower_defense")
	shell.dispatch(In.RIGHT)
	_check("right moves across the grid and selects", pc.selected == "survivor" and (library.item("survivor") as PC.LibraryCard).selected and not (library.item("tower_defense") as PC.LibraryCard).selected)
	shell.dispatch(In.UP)
	_check("up from the first row reaches the filter chips", pc.focused_widget().name.begins_with("Genre_") and pc.selected == "survivor")
	shell.dispatch(In.UP)
	_check("and then the sort and layout controls", pc.focused_widget().name in ["Sort", "GridLayout", "ListLayout"])
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	_check("down returns to the grid", pc.focused_widget() is PC.LibraryCard)
	shell.dispatch(In.X)
	await _frames(1)
	_check("X opens the selected game's page", pc.view == &"detail")
	shell.dispatch(In.LB)
	await _frames(2)
	pc.select("shooter")
	shell.dispatch(In.ACCEPT)
	await _frames(3)
	_check("Enter on a game starts it", shell.mode == &"console" and shell.current_id() == &"game" and shell.game_host.game_id() == "shooter")
	await _quit_run(shell)
	_check("and the library is there again afterwards", shell.mode == &"pc" and pc.view == &"library" and pc.selected == "shooter")
	shell.free()

# ---- real input events ----

## The same paths as above, but with real mouse and key events pushed into the window, so the plumbing between Godot's input and PC mode (hover tracking, click / double click / right click, the wheel, typing, the keys that are not launcher actions) is exercised too. Positions are canvas coordinates.
func _test_real_events() -> void:
	var store := _played_store()
	var shell := await _boot_pc(store)
	var pc := _pc(shell)
	pc.set_view(&"library")
	await _frames(3)
	var library := _library(shell)
	var survivor := library.item("survivor") as PC.LibraryCard
	var at := survivor.get_global_rect().get_center()
	_move_mouse(at)
	_check("the pointer over a card is tracked as hover", survivor.hover and not (library.item("shooter") as PC.LibraryCard).hover)
	_press(at, MOUSE_BUTTON_LEFT)
	_check("the card looks pressed while the button is down", survivor.down and pc.selected == "shooter")
	_release(at, MOUSE_BUTTON_LEFT)
	_check("a click selects the card and moves keyboard focus to it", pc.selected == "survivor" and survivor.selected and not survivor.down and pc.zone == &"main" and pc.focused_widget() == survivor and not pc.focus_visible and shell.mode == &"pc")
	var heart := survivor.find_child("Favorite", true, false) as Control
	_move_mouse(heart.get_global_rect().get_center())
	_check("the favourite button appears under the pointer and the card stays hovered", heart.visible and survivor.hover)
	_click_at(heart.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	_check("clicking it toggles the favourite only", store.is_favorite("survivor") and shell.mode == &"pc")
	shell.dismiss_toast()

	var tower := library.item("tower_defense") as PC.LibraryCard
	at = tower.get_global_rect().get_center()
	_move_mouse(at)
	_check("leaving a card ends its hover", tower.hover and not survivor.hover)
	_click_at(at, MOUSE_BUTTON_RIGHT)
	var menu := pc.find_child("Menu", true, false) as Control
	_check("a right click opens the game's menu at the pointer", pc.is_menu_open() and pc.selected == "tower_defense" and menu != null and menu.position.distance_to(at) < 1.0)
	_move_mouse(Vector2(1700, 900))
	_click_at(Vector2(1700, 900), MOUSE_BUTTON_LEFT)
	_check("a click outside closes it without doing anything else", not pc.is_menu_open() and pc.selected == "tower_defense" and shell.mode == &"pc")

	pc.set_entries(_many(40))
	await _frames(3)
	var scroll := library.scroll_area()
	_move_mouse(scroll.get_global_rect().get_center())
	_press(scroll.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	_release(scroll.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	await _frames(1)
	_check("the wheel scrolls the grid even over a card", scroll.scroll_vertical > 0 and shell.mode == &"pc")
	pc.set_entries(Catalog.all())
	await _frames(3)

	var edit := pc.find_child("Edit", true, false) as LineEdit
	_move_mouse(edit.get_global_rect().get_center())
	_click_at(edit.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	_check("clicking the search field gives it typing focus", edit.has_focus() and pc.zone == &"search")
	_type(KEY_M, "m")
	# LineEdit reports a typed change at the end of the frame.
	await _frames(1)
	_check("letters go into the field, not to the launcher's key bindings", edit.text == "m" and pc.query == "m" and not pc.is_menu_open() and pc.result_ids() == ["survivor"])
	_type(KEY_ESCAPE)
	_check("Esc clears the typed search", edit.text == "" and pc.query == "" and edit.has_focus() and shell.mode == &"pc")
	_type(KEY_TAB)
	_check("Tab leaves the field for the next zone", not edit.has_focus() and pc.zone == &"sidebar" and pc.focus_visible)
	_type(KEY_TAB)
	_check("Tab outside the field arrives through the shell", pc.zone == &"main")
	_type(KEY_SLASH, "/")
	_check("the slash key focuses the field without typing a slash", edit.has_focus() and edit.text == "")
	_type(KEY_TAB)
	var control_f := _key(KEY_F, true)
	root.push_input(control_f, true)
	_check("Ctrl+F focuses the field", edit.has_focus())
	at = (library.item("survivor") as PC.LibraryCard).get_global_rect().get_center()
	_move_mouse(at)
	_press(at, MOUSE_BUTTON_LEFT)
	_check("pressing elsewhere takes typing focus away", not edit.has_focus())
	_release(at, MOUSE_BUTTON_LEFT)

	at = (library.item("shooter") as PC.LibraryCard).get_global_rect().get_center()
	_move_mouse(at)
	_click_at(at, MOUSE_BUTTON_LEFT)
	_press(at, MOUSE_BUTTON_LEFT, true)
	_check("the second press of a double click starts nothing yet", shell.mode == &"pc")
	_release(at, MOUSE_BUTTON_LEFT)
	await _frames(3)
	_check("a real double click starts the game", shell.mode == &"console" and shell.current_id() == &"game" and shell.game_host.game_id() == "shooter")
	_type(KEY_ESCAPE)
	_check("Esc in the game pauses it", shell.mode == &"console" and shell.current_id() == &"pause" and shell.game_host.is_paused())
	_type(KEY_F11)
	_check("F11 as a real key is refused while the run is paused", shell.mode == &"console" and shell.current_id() == &"pause" and shell.toast_text() != "")
	shell.dismiss_toast()
	for i in 3:
		_type(KEY_DOWN)
	_type(KEY_ENTER)
	_type(KEY_RIGHT)
	_type(KEY_ENTER)
	await _frames(2)
	_check("and quitting from the pause screen with real keys comes back to PC mode", shell.mode == &"pc" and pc.selected == "shooter" and not shell.game_host.is_running())
	_type(KEY_F11)
	_check("F11 as a real key leaves PC mode", shell.mode == &"console")
	shell.free()

func _move_mouse(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion, true)

func _press(at: Vector2, button: MouseButton, double: bool = false) -> void:
	_button(at, button, true, double)

func _release(at: Vector2, button: MouseButton) -> void:
	_button(at, button, false, false)

func _click_at(at: Vector2, button: MouseButton) -> void:
	_button(at, button, true, false)
	_button(at, button, false, false)

func _button(at: Vector2, button: MouseButton, pressed: bool, double: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = button
	event.pressed = pressed
	event.double_click = double
	root.push_input(event, true)

## Press and release one key, with the character it types when it types one.
func _type(code: Key, character: String = "") -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.unicode = character.unicode_at(0) if character != "" and pressed else 0
		event.pressed = pressed
		root.push_input(event, true)

# ---- reflow ----

func _test_reflow_with_many_games() -> void:
	var shell := await _boot_pc(_fresh_store())
	var pc := _pc(shell)
	pc.set_entries(_many(40))
	pc.set_view(&"library")
	await _frames(3)
	var library := _library(shell)
	var flow := library.find_child("Items", true, false) as PC.Flow
	var scroll := library.scroll_area()
	_check("43 games fill a four-column grid at full width", library.order().size() == 43 and flow.get_child_count() == 43 and library.columns() == 4 and _text(library, "Count") == "43 款" and _text(pc, "ListTitle") == "GAMES")
	_check("every card stays inside the grid", _fits(flow))
	_check("the grid is taller than its area and shows a scrollbar", flow.size.y > scroll.size.y and scroll.get_v_scroll_bar().visible and scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page)
	_check("the sidebar list scrolls too", (pc.find_child("GameList", true, false) as ScrollContainer).get_v_scroll_bar().visible)
	var first := library.order()[0]
	pc.select(first)
	pc._enter_zone(&"main")
	shell.dispatch(In.DOWN)
	_check("down moves one row of four", pc.selected == library.order()[4])
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.RIGHT)
	_check("right stops at the end of a row", pc.selected == library.order()[7])
	for i in 9:
		shell.dispatch(In.DOWN)
	await _frames(3)
	_check("moving down scrolls the focused card into view", pc.selected == library.order()[42] and scroll.scroll_vertical > 0 and scroll.get_global_rect().encloses(library.item(pc.selected).get_global_rect()))
	shell.dispatch(In.LT)
	await _frames(1)
	_check("PageUp scrolls the area", scroll.scroll_vertical < int(scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page))

	pc.anchor_right = 0.0
	pc.offset_right = 1280.0
	await _frames(3)
	_check("a narrower area reflows to two columns", library.columns() == 2 and _fits(flow) and flow.size.x < 1000.0)
	pc.offset_right = 1000.0
	await _frames(3)
	_check("and to one", library.columns() == 1 and _fits(flow))
	pc.offset_right = 1920.0
	pc.set_layout(&"list")
	await _frames(3)
	flow = library.find_child("Items", true, false) as PC.Flow
	_check("the list layout is one column of rows at any width", library.columns() == 1 and flow.get_child_count() == 43 and _fits(flow))
	pc.set_query("2")
	await _frames(2)
	_check("search works on synthetic names", library.order().size() == 13)
	shell.free()

func _fits(flow: Control) -> bool:
	for child in flow.get_children():
		var item := child as Control
		if item.position.x < -0.5 or item.position.x + item.size.x > flow.size.x + 0.5:
			return false
	return true

# ---- languages ----

func _test_locales() -> void:
	var store := _played_store()
	store.set_setting("lang", "en")
	var shell := await _boot_pc(store)
	var pc := _pc(shell)
	var detail := _detail(shell)
	_check("PC mode is in English when the launcher is", (pc.find_child("Category_all", true, false) as PC.SideRow).label_text() == "All games" and _text(detail, "Title") == "ORBIT PATROL" and _text(detail.find_child("Play", true, false), "Label") == "Start game" and _text(detail, "Record").begins_with("Last played Today ") and _text(pc.find_child("ConsoleMode", true, false), "Label") == "Console mode" and (pc.find_child("Row_shooter", true, false) as PC.GameRow).name_text() == "ORBIT PATROL")
	_check("English name order uses the Latin names", pc.result_ids() == ["tower_defense", "survivor", "shooter"])
	pc.set_view(&"library")
	await _frames(2)
	var library := _library(shell)
	_check("the library is in English too", _text(library, "Title") == "All games" and _text(library, "Count") == "3 shown" and (library.item("shooter") as PC.LibraryCard).meta_text() == "ARENA SHOOTER · 1P · Today" and _text(library.find_child("Genre_0", true, false), "Label") == "All")
	pc.set_query("meadow")
	_check("English names are searchable", pc.result_ids() == ["survivor"])
	pc.set_query("zz")
	await _frames(1)
	_check("the empty state is translated", _text(library, "EmptyTitle") == "Nothing found for \"zz\"")
	pc.set_query("")
	pc._enter_zone(&"sidebar")
	shell.dispatch(In.PC_MODE)
	shell.set_locale("zh")
	shell.dispatch(In.PC_MODE)
	await _frames(2)
	_check("a language change with keyboard focus on a listed game rebuilds cleanly", (pc.find_child("Row_shooter", true, false) as PC.GameRow).name_text() == "星环巡航" and pc.result_ids().size() == 3 and pc.focused_widget() != null)
	shell.dispatch(In.PC_MODE)
	shell.set_locale("en")
	shell.dispatch(In.PC_MODE)
	pc.set_query("zz")
	shell.dispatch(In.PC_MODE)
	shell.set_locale("zh")
	shell.dispatch(In.PC_MODE)
	await _frames(2)
	pc = _pc(shell)
	_check("changing the language rebuilds PC mode and keeps its state", (pc.find_child("Category_all", true, false) as PC.SideRow).label_text() == "全部游戏" and pc.view == &"library" and pc.query == "zz" and _text(_library(shell), "EmptyTitle") == "没有找到「zz」" and (pc.find_child("Edit", true, false) as LineEdit).text == "zz")
	shell.free()

# ---- helpers ----

## Leave the live run the way a player does: pause, go down to "quit", confirm the question (whose focus starts on cancel).
func _quit_run(shell: LauncherRoot) -> void:
	shell.dispatch(In.BACK)
	for i in 3:
		shell.dispatch(In.DOWN)
	shell.dispatch(In.ACCEPT)
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.ACCEPT)
	await _frames(2)

## Let the real runtime on the game screen play itself out, only faster. True once the result is on screen.
func _play_out(shell: LauncherRoot) -> bool:
	var game := shell.screen(&"game") as LauncherGameScreen
	Engine.time_scale = 30.0
	var ended := await _until(func() -> bool: return game.phase == &"result", 60.0)
	Engine.time_scale = 1.0
	return ended

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
