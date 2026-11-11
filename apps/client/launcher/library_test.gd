extends SceneTree

## Headless tests of the library and the achievements screen, driven through LauncherRoot.dispatch exactly as a key or gamepad press would: grid movement and scrolling, categories, sorting, search (on-screen keys and typed letters), favourites with undo, empty states, launch and menu routing, and achievements for a fresh and a played profile, in zh and en.
## Run: make library-test GODOT=/path/to/godot

const StoreScript := preload("res://launcher/launcher_store.gd")
const Catalog := preload("res://launcher/launcher_catalog.gd")
const Format := preload("res://launcher/launcher_format.gd")
const In := preload("res://launcher/launcher_input.gd")
const Grid := preload("res://launcher/launcher_scroll_grid.gd")
const LibraryScript := preload("res://launcher/library_screen.gd")

const STORE_PATH := "user://library-test.json"
## 2026-11-11 10:30:00 UTC, the same fixed clock as launcher_test: not within an hour of local midnight in any time zone.
const NOW := 1794393000
const DAY := 86400
const LIBRARY := &"library"
const ACHIEVEMENTS := &"achievements"

## Stands in for the game and the game-menu screen, so routing can be checked without starting a runtime.
class ProbeScreen:
	extends LauncherScreen
	var entered: Array[Dictionary] = []
	func on_enter(args: Dictionary) -> void:
		entered.append(args)
	func shows_nav() -> bool:
		return false

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_test_grid_steps()
	_test_search_matching()
	await _test_library_fresh()
	await _test_library_favorites()
	await _test_library_played()
	await _test_library_search()
	await _test_library_many()
	await _test_library_english()
	await _test_achievements_fresh()
	await _test_achievements_played()
	await _test_achievements_english()
	_remove_store_files()
	print("library_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

# ---- pure helpers ----

func _test_grid_steps() -> void:
	# Ten cells in four columns: rows of 4, 4 and 2.
	_check("left and right stop at the ends of a row", Grid.step(4, 10, 4, In.LEFT) == -1 and Grid.step(5, 10, 4, In.LEFT) == 4 and Grid.step(7, 10, 4, In.RIGHT) == -1 and Grid.step(6, 10, 4, In.RIGHT) == 7)
	_check("right stops at the last cell of a short row", Grid.step(9, 10, 4, In.RIGHT) == -1 and Grid.step(8, 10, 4, In.RIGHT) == 9)
	_check("up and down move by one row and stop at the edges", Grid.step(5, 10, 4, In.UP) == 1 and Grid.step(1, 10, 4, In.UP) == -1 and Grid.step(1, 10, 4, In.DOWN) == 5 and Grid.step(8, 10, 4, In.DOWN) == -1)
	_check("down onto a shorter last row lands on its last cell", Grid.step(7, 10, 4, In.DOWN) == 9 and Grid.step(4, 10, 4, In.DOWN) == 8)
	_check("an index outside the grid leads nowhere", Grid.step(-1, 10, 4, In.DOWN) == -1 and Grid.step(0, 0, 4, In.RIGHT) == -1)

func _test_search_matching() -> void:
	var shooter := Catalog.by_id("shooter")
	var survivor := Catalog.by_id("survivor")
	_check("search matches pinyin initials", LibraryScript.matches(shooter, "x") and LibraryScript.matches(shooter, "xhx") and not LibraryScript.matches(survivor, "x"))
	_check("search matches the start of an English word", LibraryScript.matches(shooter, "orb") and LibraryScript.matches(shooter, "PAT") and LibraryScript.matches(survivor, "vigil") and not LibraryScript.matches(survivor, "igil"))
	_check("an empty search matches everything", LibraryScript.matches(shooter, "") and LibraryScript.matches(survivor, "  "))

# ---- library ----

func _test_library_fresh() -> void:
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	var game: ProbeScreen = shell.screen(LauncherRoot.GAME)
	var menu: ProbeScreen = shell.screen(LauncherRoot.MENU)
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.ACCEPT)
	var lib := shell.current_screen() as LauncherLibraryScreen
	_check("Home's all-games tile opens the library", lib != null and shell.current_id() == LIBRARY and shell.find_child("Nav", false, false).visible)
	_check("categories are all, recent, favourites and the catalog's genres", lib.categories() == ["all", "recent", "favorites", "genre:ARENA SHOOTER", "genre:SURVIVAL ACTION", "genre:TOWER DEFENSE"])
	_check("tabs show how many games each holds", _tab(lib, "all").count_text() == "3" and _tab(lib, "recent").count_text() == "0" and _tab(lib, "favorites").count_text() == "0" and _tab(lib, "genre_TOWER_DEFENSE").count_text() == "1" and _tab(lib, "genre_ARENA_SHOOTER").find_child("Label", true, false).text == "飞行射击")
	_check("the first tab is selected and sorting starts by name", _tab(lib, "all").selected and lib.sort == &"name" and lib.find_child("Sort", true, false).text() == "排序：名称")
	_check("names sort by pinyin initials", lib.shown_ids() == ["tower_defense", "survivor", "shooter"])
	_check("the first cover has focus with ring and title", lib.zone == &"grid" and lib.focus_id == "tower_defense" and _cover(lib, "tower_defense").selected and not _cover(lib, "survivor").selected and _cover(lib, "tower_defense").title_text() == "隘口守卫")
	_check("the backdrop is the focused game, blurred", shell.backdrop_layer() == &"blur" and lib.backdrop()["game"] == "tower_defense")
	_check("an unplayed game shows no invented figures", lib.detail_value("genre") == "塔防" and lib.detail_value("players") == "1P" and lib.detail_value("time") == "—" and lib.detail_value("last") == "尚未游玩" and lib.detail_value("best") == "—" and lib.detail_value("runs") == "0" and lib.detail_value("achievements") == "0 / 4")
	_check("the detail strip names the game in both scripts", lib.find_child("Detail", true, false).find_child("Title", true, false).text == "隘口守卫" and lib.find_child("LatinName", true, false).text == "GATEWATCH" and not lib.find_child("FavoriteTag", true, false).visible)
	_check("an unplayed game has an empty progress bar", is_zero_approx(_cover(lib, "tower_defense").progress()))
	_check("footer offers start, favourite, game menu and back", lib.footer_captions() == PackedStringArray(["开始", "加入收藏", "游戏菜单", "返回"]))

	shell.dispatch(In.RIGHT)
	_check("right moves to the next cover", lib.focus_id == "survivor" and _cover(lib, "survivor").selected and not _cover(lib, "tower_defense").selected and lib.backdrop()["game"] == "survivor")
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.RIGHT)
	_check("right stops at the last cover", lib.focus_id == "shooter")
	shell.dispatch(In.DOWN)
	_check("down stays when there is no row below", lib.focus_id == "shooter" and lib.zone == &"grid")
	shell.dispatch(In.LEFT)
	shell.dispatch(In.LEFT)
	shell.dispatch(In.LEFT)
	_check("left walks back and stops at the first cover", lib.focus_id == "tower_defense")
	shell._unhandled_input(_key(KEY_RIGHT))
	_check("a real key event takes the same path", lib.focus_id == "survivor")
	_cover(lib, "shooter").pointed.emit()
	_check("moving the mouse over a cover focuses it", lib.focus_id == "shooter" and _cover(lib, "shooter").selected)

	shell.dispatch(In.UP)
	_check("up from the first row reaches the toolbar", lib.zone == &"toolbar" and lib.find_child("Sort", true, false).focused and not _cover(lib, "shooter").selected and lib.footer_captions() == PackedStringArray(["选择", "返回"]))
	shell.dispatch(In.ACCEPT)
	_check("A on the sort chip cycles the order", lib.sort == &"recent" and lib.find_child("Sort", true, false).text() == "排序：最近游玩" and lib.zone == &"toolbar")
	shell.dispatch(In.ACCEPT)
	shell.dispatch(In.ACCEPT)
	_check("the order wraps back to name", lib.sort == &"name")
	shell.dispatch(In.RIGHT)
	_check("right moves to the search chip", lib.find_child("Search", true, false).focused and not lib.find_child("Sort", true, false).focused)
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.UP)
	_check("the toolbar ends there", lib.zone == &"toolbar" and lib.tool_index == 1)
	shell.dispatch(In.DOWN)
	_check("down returns to the cover that had focus", lib.zone == &"grid" and lib.focus_id == "shooter" and _cover(lib, "shooter").selected)
	lib.find_child("Sort", true, false).activated.emit()
	_check("clicking the sort chip cycles too", lib.sort == &"recent" and lib.zone == &"toolbar")
	shell.dispatch(In.ACCEPT)
	shell.dispatch(In.ACCEPT)
	shell.dispatch(In.DOWN)

	shell.dispatch(In.RB)
	_check("RB switches the category, not the top-level tab", shell.current_id() == LIBRARY and lib.category == "recent" and _tab(lib, "recent").selected and not _tab(lib, "all").selected)
	_check("nothing played is an honest empty state", lib.empty_title() == "还没有游玩记录" and lib.shown_ids().is_empty() and lib.focus_id == "" and not lib.find_child("Detail", true, false).visible and lib.footer_captions() == PackedStringArray(["返回"]))
	shell.dispatch(In.ACCEPT)
	shell.dispatch(In.Y)
	shell.dispatch(In.MENU)
	_check("an empty grid starts nothing", shell.current_id() == LIBRARY and store.favorites().is_empty() and game.entered.is_empty() and menu.entered.is_empty())
	shell.dispatch(In.RB)
	_check("no favourites says how to add one", lib.category == "favorites" and lib.empty_title() == "还没有收藏" and lib.find_child("Empty", true, false).find_child("Body", true, false).text.contains("Y"))
	shell.dispatch(In.RB)
	_check("a genre tab lists that genre", lib.category == "genre:ARENA SHOOTER" and lib.shown_ids() == ["shooter"] and lib.empty_title() == "")
	shell.dispatch(In.LB)
	shell.dispatch(In.LB)
	shell.dispatch(In.LB)
	shell.dispatch(In.LB)
	_check("LB walks back and wraps to the last category", lib.category == "genre:TOWER DEFENSE" and lib.focus_id == "tower_defense")
	_tab(lib, "all").activated.emit()
	_check("clicking a tab selects it", lib.category == "all" and lib.shown_ids().size() == 3)
	shell.dispatch(In.RT)
	_check("RT still switches the top-level tab", shell.current_id() == ACHIEVEMENTS)
	shell.dispatch(In.LT)
	_check("LT comes back with the library as it was", shell.current_id() == LIBRARY and lib.category == "all" and lib.focus_id == "tower_defense")

	shell.dispatch(In.RIGHT)
	shell.dispatch(In.ACCEPT)
	_check("A starts the focused game the way Home does", shell.current_id() == LauncherRoot.GAME and game.entered == [{"game": "survivor"}])
	shell.dispatch(In.BACK)
	_check("back from the game screen returns to the library", shell.current_id() == LIBRARY and lib.focus_id == "survivor")
	shell.dispatch(In.MENU)
	_check("Menu opens the game menu for the focused game", shell.current_id() == LauncherRoot.MENU and menu.entered == [{"game": "survivor"}])
	shell.dispatch(In.BACK)
	_cover(lib, "shooter").activated.emit()
	_check("clicking a cover starts that game", shell.current_id() == LauncherRoot.GAME and game.entered.back() == {"game": "shooter"})
	shell.dispatch(In.BACK)
	shell.dispatch(In.BACK)
	_check("B leaves the library for Home", shell.current_id() == &"home")
	shell.free()

func _test_library_favorites() -> void:
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	shell.go(LIBRARY)
	var lib := shell.current_screen() as LauncherLibraryScreen
	shell.dispatch(In.Y)
	_check("Y adds the focused game to favourites and says so", store.is_favorite("tower_defense") and shell.toast_text() == "已收藏「隘口守卫」" and shell.can_undo())
	_check("cover, strip, tab count and footer reflect the favourite", _cover(lib, "tower_defense").is_favorite_shown() and lib.find_child("FavoriteTag", true, false).visible and _tab(lib, "favorites").count_text() == "1" and lib.footer_captions()[1] == "取消收藏")
	shell.dispatch(In.X)
	_check("X on the toast undoes it instead of opening the search", not store.is_favorite("tower_defense") and not lib.is_search_open() and not _cover(lib, "tower_defense").is_favorite_shown() and lib.footer_captions()[1] == "加入收藏")

	store.set_favorite("shooter", true)
	store.set_favorite("survivor", true)
	_check("a change in the store shows up while the library is open", _cover(lib, "shooter").is_favorite_shown() and _tab(lib, "favorites").count_text() == "2")
	shell.dismiss_toast()
	shell.dispatch(In.RB)
	shell.dispatch(In.RB)
	_check("the favourites tab lists them", lib.category == "favorites" and lib.shown_ids() == ["survivor", "shooter"] and lib.focus_id == "survivor")
	shell.dispatch(In.Y)
	_check("removing a favourite on its own tab moves the focus on", not store.is_favorite("survivor") and lib.shown_ids() == ["shooter"] and lib.focus_id == "shooter" and shell.toast_text() == "已取消收藏「长夜草原」")
	shell.undo()
	_check("undo brings the cover and the focus back", store.is_favorite("survivor") and lib.shown_ids() == ["survivor", "shooter"] and lib.focus_id == "survivor" and _cover(lib, "survivor").selected)
	shell.free()

func _test_library_played() -> void:
	var store := _fresh_store()
	store.record_run("tower_defense", {"score": 2130, "play_seconds": 655.0, "cleared": true}, NOW - DAY)
	store.unlock("tower_defense", "first_defense", NOW - DAY)
	store.unlock("tower_defense", "gate_held", NOW - DAY)
	store.record_run("shooter", {"score": 1800, "play_seconds": 388.0, "cleared": false}, NOW - 600)
	store.unlock("shooter", "first_sortie", NOW - 600)
	store.unlock("shooter", "retired_achievement", NOW - 600)
	var shell := _boot(store)
	await _frames(2)
	shell.go(LIBRARY, {"game": "shooter"})
	var lib := shell.current_screen() as LauncherLibraryScreen
	_check("an incoming game is focused", lib.focus_id == "shooter" and _cover(lib, "shooter").selected)
	_check("the strip shows the real record", lib.detail_value("time") == "6m" and lib.detail_value("last") == Format.when_time(NOW - 600, NOW, "zh") and lib.detail_value("last").begins_with("今天") and lib.detail_value("best") == "1,800" and lib.detail_value("runs") == "1")
	_check("achievements count only what the catalog defines", lib.detail_value("achievements") == "1 / 3" and is_equal_approx(_cover(lib, "shooter").progress(), 1.0 / 3.0) and is_equal_approx(_cover(lib, "tower_defense").progress(), 0.5))
	_check("recently played holds the played games", _tab(lib, "recent").count_text() == "2" and lib.ids_in("recent") == ["shooter", "tower_defense"])

	shell.dispatch(In.UP)
	shell.dispatch(In.ACCEPT)
	_check("sorting by recently played puts the latest first and unplayed last", lib.sort == &"recent" and lib.shown_ids() == ["shooter", "tower_defense", "survivor"])
	shell.dispatch(In.ACCEPT)
	_check("sorting by play time puts the longest first", lib.sort == &"time" and lib.shown_ids() == ["tower_defense", "shooter", "survivor"] and lib.find_child("Sort", true, false).text() == "排序：游玩时长")
	_check("re-sorting keeps the focus on the same game", lib.focus_id == "shooter")
	shell.dispatch(In.DOWN)
	shell.dispatch(In.LEFT)
	_check("movement follows the sorted order", lib.focus_id == "tower_defense")

	shell.dispatch(In.RB)
	shell.dispatch(In.RB)
	_check("the favourites tab is empty for this profile", lib.category == "favorites" and lib.focus_id == "")
	shell.go(&"home")
	shell.go(LIBRARY, {"game": "survivor"})
	_check("an incoming game that the category hides switches back to all", lib.category == "all" and lib.focus_id == "survivor")
	shell.go(&"home")
	shell.go(LIBRARY, {"game": "no_such_game"})
	_check("an unknown incoming game is ignored", lib.focus_id == "survivor")
	shell.free()

func _test_library_search() -> void:
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	shell.go(LIBRARY)
	var lib := shell.current_screen() as LauncherLibraryScreen
	shell.dispatch(In.X)
	var layer := shell.find_child("SearchLayer", true, false) as Control
	_check("X opens the search layer over the shell", lib.is_search_open() and shell.has_overlay() and layer != null and lib.zone == &"search")
	_check("the keyboard starts on its first key with an empty field", layer.find_child("Key_q", true, false).focused and layer.find_child("Query", true, false).text == "_" and layer.find_child("Count", true, false).text == "3 款符合")
	shell.dispatch(In.UP)
	shell.dispatch(In.LEFT)
	_check("the keyboard's edges stop the focus", lib.key_row == 0 and lib.key_index == 0)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.ACCEPT)
	_check("A types the focused letter and filters at once", lib.query == "x" and layer.find_child("Key_x", true, false).focused and layer.find_child("Query", true, false).text == "X" and lib.shown_ids() == ["shooter"] and layer.find_child("Count", true, false).text == "1 款符合")
	_check("the search chip shows the query", lib.find_child("Search", true, false).text() == "搜索：X" and lib.find_child("Search", true, false).active)
	for i in 6:
		shell.dispatch(In.RIGHT)
	_check("right walks along the row onto backspace", layer.find_child("Key_backspace", true, false).focused)
	shell.dispatch(In.DOWN)
	_check("down reaches the done button", layer.find_child("Key_done", true, false).focused)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.UP)
	_check("up from done returns to the column it came from", layer.find_child("Key_backspace", true, false).focused)
	shell.dispatch(In.UP)
	_check("up from a wide key lands on the letter above its first column", layer.find_child("Key_j", true, false).focused)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.ACCEPT)
	_check("the backspace key deletes", lib.query == "" and lib.shown_ids().size() == 3)

	shell.dispatch(In.LB)
	shell.dispatch(In.RT)
	_check("the layer is modal: shoulder buttons do nothing behind it", lib.category == "all" and shell.current_id() == LIBRARY and lib.is_search_open())

	layer._input(_typed(KEY_C, "c"))
	_check("a typed letter goes into the search, even one bound to a button", lib.query == "c" and lib.shown_ids() == ["survivor"] and lib.focus_id == "survivor")
	_check("typing parks the focus on done", layer.find_child("Key_done", true, false).focused)
	layer._input(_typed(KEY_X, "x"))
	_check("X as a typed letter is text here, not the X button", lib.query == "cx" and lib.is_search_open())
	_check("no match says so", lib.shown_ids().is_empty() and lib.empty_title() == "没有符合的游戏" and layer.find_child("Count", true, false).text == "0 款符合" and not lib.find_child("Detail", true, false).visible)
	layer._input(_key(KEY_BACKSPACE))
	_check("the Backspace key deletes instead of going back", lib.query == "c" and lib.is_search_open() and shell.current_id() == LIBRARY)
	_check("other keys are left to the launcher", not lib.handle_search_key(_key(KEY_UP)) and not lib.handle_search_key(_key(KEY_ENTER)))
	shell.dispatch(In.X)
	_check("the X button is backspace while the layer is open", lib.query == "")
	for letter in "abcdefghij":
		lib.type_letter(letter)
	_check("the query is capped", lib.query == "abcdefgh")
	shell.dispatch(In.Y)
	_check("the Y button clears the search", lib.query == "")
	layer._input(_typed(KEY_C, "c"))
	shell.dispatch(In.ACCEPT)
	_check("A on done closes the layer and keeps the filter", not lib.is_search_open() and not shell.has_overlay() and lib.zone == &"grid" and lib.query == "c" and lib.shown_ids() == ["survivor"] and lib.find_child("Search", true, false).active)
	_check("tab counts ignore the search", _tab(lib, "all").count_text() == "3")

	shell.dispatch(In.UP)
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.ACCEPT)
	_check("A on the search chip opens it again", lib.is_search_open())
	shell.dispatch(In.BACK)
	_check("B closes the layer without leaving the library", not lib.is_search_open() and shell.current_id() == LIBRARY)
	lib.find_child("Search", true, false).activated.emit()
	(shell.find_child("SearchLayer", true, false).find_child("Key_clear", true, false) as Control).activated.emit()
	_check("the keys work with the mouse", lib.is_search_open() and lib.query == "")
	(shell.find_child("SearchLayer", true, false).find_child("SearchScrim", true, false) as Control).activated.emit()
	_check("clicking outside the dialog closes it", not lib.is_search_open())
	shell.dispatch(In.X)
	shell.go(&"home")
	_check("leaving the screen closes the layer", not shell.has_overlay() and not lib.is_search_open())
	shell.free()

func _test_library_many() -> void:
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	shell.go(LIBRARY)
	var lib := shell.current_screen() as LauncherLibraryScreen
	var grid := lib.find_child("Grid", true, false) as LauncherScrollGrid
	_check("three games fit without scrolling", not grid.is_scrollable() and lib.first_visible_row() == 0)
	# 22 entries in four columns: five full rows and a last row of two.
	lib.set_entries(_many(19, 0))
	var shown := lib.shown_ids()
	_check("a larger catalog fills the grid in order", shown.size() == 22 and shown[0] == "tower_defense" and shown[3] == "t00" and shown[21] == "t18" and grid.is_scrollable() and _tab(lib, "all").count_text() == "22")
	_check("rows outside the view are not drawn", lib.focus_id == shown[0] and _cover(lib, shown[4]).visible and not _cover(lib, shown[20]).visible)
	shell.dispatch(In.DOWN)
	_check("down moves one row inside the view", lib.focus_id == shown[4] and lib.first_visible_row() == 0)
	shell.dispatch(In.DOWN)
	_check("past the last visible row the grid scrolls", lib.focus_id == shown[8] and lib.first_visible_row() == 1 and grid.is_index_visible(8) and not grid.is_index_visible(0))
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	_check("down reaches the short last row", lib.focus_id == shown[20] and lib.first_visible_row() == 4 and _cover(lib, shown[20]).visible and _cover(lib, shown[20]).selected)
	shell.dispatch(In.DOWN)
	_check("and stops there", lib.focus_id == shown[20])
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.RIGHT)
	_check("right stops at the last cover of the short row", lib.focus_id == shown[21])
	shell.dispatch(In.UP)
	_check("up keeps the column and does not scroll while the row is in view", lib.focus_id == shown[17] and lib.first_visible_row() == 4)
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.DOWN)
	_check("down from a column the last row lacks lands on its last cover", lib.focus_id == shown[21])
	for i in 5:
		shell.dispatch(In.UP)
	_check("up scrolls back to the top", lib.focus_id == shown[1] and lib.first_visible_row() == 0)
	shell.dispatch(In.UP)
	_check("and then reaches the toolbar", lib.zone == &"toolbar")
	shell.dispatch(In.DOWN)
	grid.wheeled.emit(1)
	grid.wheeled.emit(1)
	_check("the mouse wheel moves the focus by rows", lib.focus_id == shown[9] and lib.first_visible_row() == 1)
	grid.wheeled.emit(-1)
	_check("in both directions", lib.focus_id == shown[5])
	_cover(lib, shown[21]).pointed.emit()
	_check("pointing at a cover never scrolls it away", lib.focus_id == shown[21])

	lib.type_letter("z")
	lib.type_letter("z")
	lib.type_letter("1")
	_check("searching a large catalog narrows it and keeps a still-listed focus in view", lib.shown_ids().size() == 9 and lib.focus_id == "t18" and lib.first_visible_row() == 1 and grid.is_index_visible(8))
	lib.set_query("")

	lib.set_entries(_many(21, 7))
	_check("genres come from the entries, each with its count", lib.categories().size() == 13 and _tab(lib, "genre_KIND_0").count_text() == "3" and _tab(lib, "genre_KIND_0").find_child("Label", true, false).text == "类别 0")
	await _frames(2)
	_check("the first tab is in view", lib.is_tab_in_view("all"))
	for i in 12:
		shell.dispatch(In.RB)
	_check("a long tab row slides to keep the selected tab in view", lib.category == "genre:KIND 6" and lib.is_tab_in_view("genre:KIND 6") and not lib.is_tab_in_view("all") and lib.shown_ids() == ["t06", "t13", "t20"])
	_check("the toolbar stays inside the page margin", (lib.find_child("Bar", true, false) as Control).get_combined_minimum_size().x <= LauncherTokens.CANVAS.x - LauncherTokens.MARGIN * 2.0)
	shell.dispatch(In.RB)
	_check("wrapping round slides back", lib.category == "all" and lib.is_tab_in_view("all"))
	shell.free()

func _test_library_english() -> void:
	var store := _fresh_store()
	store.set_setting("lang", "en")
	store.record_run("shooter", {"score": 1800, "play_seconds": 388.0, "cleared": false}, NOW - 2 * DAY)
	var shell := _boot(store)
	await _frames(2)
	shell.go(LIBRARY, {"game": "shooter"})
	var lib := shell.current_screen() as LauncherLibraryScreen
	_check("tabs and toolbar are in English", _tab(lib, "all").find_child("Label", true, false).text == "All" and _tab(lib, "favorites").find_child("Label", true, false).text == "Favourites" and _tab(lib, "genre_ARENA_SHOOTER").find_child("Label", true, false).text == "ARENA SHOOTER" and lib.find_child("Sort", true, false).text() == "Sort: Name" and lib.find_child("Search", true, false).text() == "Search")
	_check("names sort by the English name", lib.shown_ids() == ["tower_defense", "survivor", "shooter"])
	_check("the strip is in English and does not repeat the Latin name", lib.find_child("Detail", true, false).find_child("Title", true, false).text == "ORBIT PATROL" and not lib.find_child("LatinName", true, false).visible and lib.detail_value("genre") == "ARENA SHOOTER" and lib.detail_value("last").begins_with("2 days ago"))
	_check("footer is in English", lib.footer_captions() == PackedStringArray(["Start", "Add to favourites", "Game menu", "Back"]))
	shell.dispatch(In.RB)
	shell.dispatch(In.RB)
	_check("empty states are in English", lib.empty_title() == "No favourites yet")
	shell.dispatch(In.X)
	var layer := shell.find_child("SearchLayer", true, false) as Control
	layer._input(_typed(KEY_Q, "q"))
	_check("the search layer is in English", layer.find_child("Count", true, false).text == "0 found" and layer.find_child("Key_done", true, false).find_child("Label", true, false).text == "Done" and lib.empty_title() == "No games match")
	shell.free()

# ---- achievements ----

func _test_achievements_fresh() -> void:
	var store := _fresh_store()
	var shell := _boot(store)
	await _frames(2)
	var menu: ProbeScreen = shell.screen(LauncherRoot.MENU)
	shell.go(ACHIEVEMENTS)
	var ach := shell.current_screen() as LauncherAchievementsScreen
	_check("the achievements tab opens the achievements screen", ach != null and shell.find_child("Nav", false, false).visible and shell.backdrop_layer() == &"blur")
	_check("a fresh profile has nothing unlocked", ach.find_child("Unlocked", true, false).text == "0" and ach.find_child("Defined", true, false).text == "/ 11" and is_zero_approx((ach.find_child("Fill", true, false) as Control).size.x))
	_check("the switcher lists all games with their counts", ach.game == "" and ach.find_child("Game_all", true, false).count_text() == "0 / 11" and ach.find_child("Game_shooter", true, false).count_text() == "0 / 3" and ach.find_child("Game_survivor", true, false).count_text() == "0 / 4" and ach.find_child("Game_tower_defense", true, false).count_text() == "0 / 4" and ach.find_child("Game_all", true, false).selected)
	_check("filters count the pool", ach.find_child("Filter_all", true, false).count_text() == "11" and ach.find_child("Filter_unlocked", true, false).count_text() == "0" and ach.find_child("Filter_locked", true, false).count_text() == "11" and ach.find_child("Filter_all", true, false).selected)
	_check("every defined achievement is listed in catalog order", ach.shown_keys().size() == 11 and ach.shown_keys()[0] == "shooter/first_sortie" and ach.shown_keys()[3] == "survivor/first_watch" and ach.shown_keys()[10] == "tower_defense/full_sweep")
	var first := _tile(ach, "shooter/first_sortie")
	_check("a locked achievement shows its icon, name and that it is locked", first.icon_kind() == "bolt" and first.title_text() == "首次出击" and first.status_text() == "未解锁" and not first.unlocked and first.find_child("Description", true, false).text == "完成一局，无论胜负。")
	_check("the list starts focused on the first achievement", ach.zone == &"list" and ach.pick == "shooter/first_sortie" and first.focused)
	var detail := ach.find_child("Detail", true, false) as Control
	_check("the detail panel describes the picked achievement honestly", detail.visible and detail.find_child("Title", true, false).text == "首次出击" and detail.find_child("Game", true, false).text == "星环巡航" and detail.find_child("State", true, false).text == "未解锁" and not (detail.find_child("When", true, false) as Control).is_visible_in_tree() and detail.find_child("Open", true, false).text() == "去挑战")
	_check("footer offers the challenge and back", ach.footer_captions() == PackedStringArray(["去挑战", "返回"]))
	var icons_known := true
	for entry in Catalog.all():
		for definition: Dictionary in entry["achievements"]:
			icons_known = icons_known and str(definition["icon"]) in ["bolt", "cup", "star", "shield"]
	_check("every catalog icon is one the launcher draws", icons_known)

	shell.dispatch(In.RIGHT)
	_check("right moves across the two columns", ach.pick == "shooter/sector_clear" and _tile(ach, "shooter/sector_clear").focused and not first.focused)
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.UP)
	_check("the list's edges stop the focus", ach.pick == "shooter/sector_clear" and ach.zone == &"list")
	shell.dispatch(In.DOWN)
	shell.dispatch(In.LEFT)
	_check("down and left move by row and column", ach.pick == "shooter/high_score" and detail.find_child("Title", true, false).text == "两千分")
	for i in 6:
		shell.dispatch(In.DOWN)
	_check("down stops on the last row", ach.pick == "tower_defense/full_sweep")
	shell.dispatch(In.UP)
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.DOWN)
	_check("down from the second column lands on the short last row", ach.pick == "tower_defense/full_sweep" and ach.backdrop()["game"] == "tower_defense")
	shell.dispatch(In.LEFT)
	_check("left from the first column moves to the switcher", ach.zone == &"games" and ach.find_child("Game_all", true, false).focused and not _tile(ach, "tower_defense/full_sweep").focused and _tile(ach, "tower_defense/full_sweep").picked and ach.footer_captions() == PackedStringArray(["查看成就", "返回"]))
	shell.dispatch(In.UP)
	_check("the switcher stops at its first entry", ach.game == "")
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	_check("down chooses the next game and lists only its achievements", ach.game == "survivor" and ach.shown_keys().size() == 4 and ach.pick == "survivor/first_watch" and ach.find_child("Game_survivor", true, false).focused and not ach.find_child("Game_all", true, false).selected and ach.find_child("Filter_all", true, false).count_text() == "4" and ach.backdrop()["game"] == "survivor")
	_check("tiles of other games are not shown", not _tile(ach, "shooter/first_sortie").visible and _tile(ach, "survivor/first_watch").visible)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	_check("the switcher stops at its last entry", ach.game == "tower_defense")
	shell.dispatch(In.RIGHT)
	_check("right steps into the list", ach.zone == &"list" and ach.pick == "tower_defense/first_defense" and _tile(ach, "tower_defense/first_defense").focused and ach.find_child("Game_tower_defense", true, false).selected and not ach.find_child("Game_tower_defense", true, false).focused)
	shell.dispatch(In.ACCEPT)
	_check("A opens the game menu of that achievement's game", shell.current_id() == LauncherRoot.MENU and menu.entered == [{"game": "tower_defense"}])
	shell.dispatch(In.BACK)
	_check("back returns to the achievements as they were", shell.current_id() == ACHIEVEMENTS and ach.game == "tower_defense")

	shell.dispatch(In.RB)
	_check("RB switches the filter, not the top-level tab", shell.current_id() == ACHIEVEMENTS and ach.filter == 1 and ach.find_child("Filter_unlocked", true, false).selected)
	_check("nothing unlocked is an honest empty state", ach.empty_title() == "还没有解锁成就" and ach.shown_keys().is_empty() and not detail.visible and ach.zone == &"games" and ach.footer_captions() == PackedStringArray(["返回"]))
	shell.dispatch(In.RIGHT)
	shell.dispatch(In.ACCEPT)
	_check("an empty list cannot take the focus", ach.zone == &"games" and shell.current_id() == ACHIEVEMENTS)
	shell.dispatch(In.RB)
	_check("the locked filter lists what is left", ach.filter == 2 and ach.shown_keys().size() == 4 and ach.empty_title() == "")
	shell.dispatch(In.RB)
	shell.dispatch(In.LB)
	_check("the filters wrap in both directions", ach.filter == 2)
	ach.find_child("Filter_all", true, false).activated.emit()
	_check("clicking a filter selects it", ach.filter == 0)
	ach.find_child("Game_shooter", true, false).activated.emit()
	_check("clicking a game chooses it", ach.game == "shooter" and ach.shown_keys().size() == 3)
	_tile(ach, "shooter/high_score").pointed.emit()
	_check("moving the mouse over an achievement picks it", ach.zone == &"list" and ach.pick == "shooter/high_score" and detail.find_child("Title", true, false).text == "两千分")
	(detail.find_child("Open", true, false) as Control).activated.emit()
	_check("the panel's button goes to the game menu too", shell.current_id() == LauncherRoot.MENU and menu.entered.back() == {"game": "shooter"})
	shell.dispatch(In.BACK)
	shell.dispatch(In.LT)
	_check("LT still switches the top-level tab", shell.current_id() == LIBRARY)

	shell.go(ACHIEVEMENTS, {"game": "survivor"})
	_check("an incoming game is chosen with all its achievements", ach.game == "survivor" and ach.filter == 0 and ach.zone == &"list" and ach.pick == "survivor/first_watch")
	shell.go(ACHIEVEMENTS, {"game": "no_such_game"})
	_check("an unknown incoming game is ignored", ach.game == "survivor")
	shell.free()

func _test_achievements_played() -> void:
	var store := _fresh_store()
	store.unlock("shooter", "first_sortie", NOW - 600)
	store.unlock("tower_defense", "first_defense", NOW - DAY)
	store.unlock("tower_defense", "gate_held", NOW - 3 * DAY)
	store.unlock("shooter", "retired_achievement", NOW - 600)
	var shell := _boot(store)
	await _frames(2)
	# The same route Home's achievements row takes.
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.ACCEPT)
	var ach := shell.current_screen() as LauncherAchievementsScreen
	_check("Home's achievements row opens the hero's achievements", ach != null and ach.game == "shooter" and ach.shown_keys().size() == 3)
	_check("the summary counts only achievements the catalog defines", ach.find_child("Unlocked", true, false).text == "3" and ach.find_child("Defined", true, false).text == "/ 11" and is_equal_approx((ach.find_child("Fill", true, false) as Control).size.x, 340.0 * 3.0 / 11.0))
	_check("each game shows its own progress", ach.find_child("Game_all", true, false).count_text() == "3 / 11" and ach.find_child("Game_shooter", true, false).count_text() == "1 / 3" and ach.find_child("Game_survivor", true, false).count_text() == "0 / 4" and ach.find_child("Game_tower_defense", true, false).count_text() == "2 / 4")
	var first := _tile(ach, "shooter/first_sortie")
	_check("an unlocked achievement says when", first.unlocked and first.status_text() == "已解锁 · 今天" and not _tile(ach, "shooter/sector_clear").unlocked and _tile(ach, "shooter/sector_clear").status_text() == "未解锁")
	var detail := ach.find_child("Detail", true, false) as Control
	_check("the detail panel shows the unlock time", detail.find_child("State", true, false).text == "已解锁" and (detail.find_child("When", true, false) as Control).is_visible_in_tree() and detail.find_child("When", true, false).text == Format.when_time(NOW - 600, NOW, "zh") and detail.find_child("Open", true, false).text() == "游戏菜单" and ach.footer_captions()[0] == "游戏菜单")
	_check("filter counts follow the store", ach.find_child("Filter_unlocked", true, false).count_text() == "1" and ach.find_child("Filter_locked", true, false).count_text() == "2")

	shell.dispatch(In.LEFT)
	shell.dispatch(In.UP)
	shell.dispatch(In.RB)
	_check("the unlocked filter over all games lists the real unlocks", ach.game == "" and ach.shown_keys() == PackedStringArray(["shooter/first_sortie", "tower_defense/first_defense", "tower_defense/gate_held"]))
	_check("older unlocks say how long ago", _tile(ach, "tower_defense/first_defense").status_text() == "已解锁 · 昨天" and _tile(ach, "tower_defense/gate_held").status_text() == "已解锁 · 3 天前" and _tile(ach, "tower_defense/gate_held").icon_kind() == "cup")
	shell.dispatch(In.RB)
	_check("the locked filter lists the rest", ach.shown_keys().size() == 8 and not ach.shown_keys().has("shooter/first_sortie"))
	store.unlock("survivor", "first_watch", NOW)
	_check("a new unlock shows up while the screen is open", ach.find_child("Unlocked", true, false).text == "4" and ach.shown_keys().size() == 7 and ach.find_child("Game_survivor", true, false).count_text() == "1 / 4")
	for id in ["sector_clear", "high_score"]:
		store.unlock("shooter", id, NOW)
	shell.go(ACHIEVEMENTS, {"game": "shooter"})
	shell.dispatch(In.RB)
	shell.dispatch(In.RB)
	_check("a fully unlocked game has an honest empty locked list", ach.filter == 2 and ach.empty_title() == "这里的成就都已解锁" and not detail.visible)
	shell.free()

func _test_achievements_english() -> void:
	var store := _fresh_store()
	store.set_setting("lang", "en")
	store.unlock("survivor", "first_watch", NOW - DAY)
	var shell := _boot(store)
	await _frames(2)
	shell.go(ACHIEVEMENTS, {"game": "survivor"})
	var ach := shell.current_screen() as LauncherAchievementsScreen
	var detail := ach.find_child("Detail", true, false) as Control
	_check("switcher and filters are in English", ach.find_child("Game_all", true, false).find_child("Label", true, false).text == "All games" and ach.find_child("Game_survivor", true, false).find_child("Label", true, false).text == "MEADOW VIGIL" and ach.find_child("Filter_unlocked", true, false).find_child("Label", true, false).text == "Unlocked")
	_check("tiles and the detail panel are in English", _tile(ach, "survivor/first_watch").title_text() == "First Watch" and _tile(ach, "survivor/first_watch").status_text() == "Unlocked · Yesterday" and _tile(ach, "survivor/until_dawn").status_text() == "Locked" and detail.find_child("Title", true, false).text == "First Watch" and detail.find_child("State", true, false).text == "Unlocked" and detail.find_child("Open", true, false).text() == "Game menu")
	shell.dispatch(In.RIGHT)
	_check("footer is in English", ach.footer_captions() == PackedStringArray(["Go for it", "Back"]))
	shell.dispatch(In.RB)
	shell.dispatch(In.RB)
	shell.dispatch(In.LEFT)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.DOWN)
	shell.dispatch(In.LB)
	_check("empty states are in English", ach.game == "tower_defense" and ach.filter == 1 and ach.empty_title() == "Nothing unlocked yet")
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

## The launcher with the game and game-menu screens replaced by probes.
func _boot(store: LauncherStore) -> LauncherRoot:
	var packed: PackedScene = load(str(ProjectSettings.get_setting("application/run/main_scene")))
	var shell: LauncherRoot = packed.instantiate()
	shell.store = store
	shell.now_provider = func() -> int: return NOW
	shell.register_screen(LauncherRoot.GAME, ProbeScreen)
	shell.register_screen(LauncherRoot.MENU, ProbeScreen)
	root.add_child(shell)
	return shell

## The catalog plus `extra` synthetic entries that sort after it by name. With `genres` > 0 they are spread over that many genres of their own.
func _many(extra: int, genres: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(Catalog.all())
	for index in extra:
		var sample: Dictionary = Catalog.all()[index % Catalog.all().size()].duplicate(true)
		sample["id"] = "t%02d" % index
		sample["name"] = {"zh": "测试 %02d" % index, "en": "ZZ TEST %02d" % index}
		sample["initials"] = "zz%02d" % index
		if genres > 0:
			sample["genre"] = {"zh": "类别 %d" % (index % genres), "en": "KIND %d" % (index % genres)}
		out.append(sample)
	return out

func _tab(lib: LauncherLibraryScreen, key: String) -> LauncherControls.Tab:
	return lib.find_child("Tab_%s" % key, true, false) as LauncherControls.Tab

func _cover(lib: LauncherLibraryScreen, id: String) -> Control:
	return lib.find_child("Cover_%s" % id, true, false) as Control

func _tile(ach: LauncherAchievementsScreen, key: String) -> Control:
	return ach.find_child("Tile_%s" % key.replace("/", "_"), true, false) as Control

func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event

## A key press as a keyboard delivers it: with the logical keycode and the character it types.
func _typed(code: Key, character: String) -> InputEventKey:
	var event := _key(code)
	event.keycode = code
	event.unicode = character.unicode_at(0)
	return event

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + label)
