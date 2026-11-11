class_name LauncherHomeScreen
extends LauncherScreen

## Home: the hero of the selected game with its three menu rows, the "recently played" shelf, the "all games" tile, and the options side panel.
##
## Everything shown about a game comes from LauncherStore: the shelf lists the games that were really played (most recent first), the caption under the start row is the real last-played time and best score, and the thin progress bars are the share of that game's achievements that are unlocked. With nothing played yet the shelf says so.
##
## Focus model (the pattern other screens follow): `zone` says which group has focus and an index says which item in it. Up/Down move through the menu rows; Left/Right change the selected game and, past the last one, move onto the "all games" tile; the options panel is its own zone while it is open. Mouse hover and click drive the same state.

const ZONE_MENU := &"menu"
const ZONE_TILE := &"tile"
const ZONE_PANEL := &"panel"

const ROW_START := 0
const ROW_MENU := 1
const ROW_ACHIEVEMENTS := 2

const HERO_WIDTH := 820.0
const TITLE_BOX_HEIGHT := 122.0

var hero_id := ""
var zone := ZONE_MENU
var row := ROW_START
var panel_row := 0

var _eyebrow: Label
var _favorite_tag: Control
var _title_box: Control
var _title: Label
var _title_glow: _Glow
var _latin: Label
var _latin_gap: Control
var _tagline: Label
var _rows: Array[LauncherControls.FocusRow] = []
var _shelf_row: HBoxContainer
var _shelf_ids: Array[String] = []
var _shelf_built := false
var _cards: Dictionary = {}
var _tile: LauncherControls.Tile
var _empty: Label
var _panel: Control
var _panel_rows: Array[LauncherControls.FocusRow] = []
var _panel_actions: Array[Callable] = []

func build() -> void:
	add_child(W.fill(C.GradientRect.new([[0.0, T.BG], [0.16, T.BG], [0.28, T.bg(0.85)], [0.42, T.bg(0.35)], [0.54, T.bg(0.0)], [1.0, T.bg(0.0)]], true)))
	var top := C.GradientRect.new([[0.0, T.deep(0.7)], [1.0, T.deep(0.0)]])
	top.position = Vector2.ZERO
	top.size = Vector2(T.CANVAS.x, 180)
	add_child(top)
	var bottom := C.GradientRect.new([[0.0, T.deep(0.0)], [0.55, T.deep(0.72)], [1.0, T.deep(0.96)]])
	bottom.position = Vector2(0, T.CANVAS.y - 440)
	bottom.size = Vector2(T.CANVAS.x, 440)
	add_child(bottom)
	_build_hero()
	_build_shelf()
	shell.store.changed.connect(func(_section: StringName) -> void:
		if visible:
			_refresh())

func _build_hero() -> void:
	var hero := W.vbox(0)
	hero.name = "Hero"
	hero.position = Vector2(T.MARGIN, 190)
	hero.custom_minimum_size = Vector2(HERO_WIDTH, 0)
	add_child(hero)

	var eyebrow := W.hbox(14)
	eyebrow.name = "Eyebrow"
	var dash := W.rule(T.fg(T.A_MUTED))
	dash.custom_minimum_size = Vector2(40, 1)
	dash.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	eyebrow.add_child(dash)
	_eyebrow = W.text("", T.SIZE_SMALL, 600, T.fg(T.A_BODY), 5, true)
	_eyebrow.name = "Meta"
	eyebrow.add_child(_eyebrow)
	var tag := W.hbox(6)
	tag.name = "FavoriteTag"
	tag.add_child(C.Icon.new("heart", 14.0, T.FAVORITE))
	tag.add_child(W.text(t("launcher.common.favorite"), T.SIZE_SMALL, 600, T.FAVORITE, 3, true))
	_favorite_tag = tag
	eyebrow.add_child(tag)
	hero.add_child(eyebrow)

	hero.add_child(_gap(22))
	_title_box = Control.new()
	_title_box.name = "TitleBox"
	_title_box.custom_minimum_size = Vector2(HERO_WIDTH, TITLE_BOX_HEIGHT)
	_title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_glow = _Glow.new()
	_title_box.add_child(_title_glow)
	_title = Label.new()
	_title.name = "Title"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_box.add_child(_title)
	hero.add_child(_title_box)

	_latin_gap = _gap(18)
	hero.add_child(_latin_gap)
	_latin = W.text("", T.SIZE_HERO_LATIN, 800, T.FG, 14, true)
	_latin.name = "LatinName"
	hero.add_child(_latin)

	hero.add_child(_gap(22))
	_tagline = W.text("", T.SIZE_TAGLINE, 300, T.fg(0.88), 1)
	_tagline.name = "Tagline"
	hero.add_child(_tagline)

	hero.add_child(_gap(36))
	var menu := W.vbox(2)
	menu.name = "Menu"
	menu.custom_minimum_size = Vector2(620, 0)
	menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hero.add_child(menu)
	for index in 3:
		var item := C.FocusRow.new("")
		item.name = "Row%d" % index
		item.hovered.connect(func() -> void: _focus_row(index))
		item.activated.connect(func() -> void:
			_focus_row(index)
			_activate_row())
		menu.add_child(item)
		_rows.append(item)

func _build_shelf() -> void:
	var shelf := W.vbox(18)
	shelf.name = "Shelf"
	shelf.anchor_left = 0.0
	shelf.anchor_right = 1.0
	shelf.anchor_top = 1.0
	shelf.anchor_bottom = 1.0
	shelf.offset_left = T.MARGIN
	shelf.offset_right = -T.MARGIN
	shelf.offset_bottom = -104
	shelf.offset_top = -104
	shelf.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(shelf)
	shelf.add_child(W.section_header(t("launcher.home.recents")))
	_shelf_row = W.hbox(20)
	_shelf_row.name = "Row"
	shelf.add_child(_shelf_row)

func _gap(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer

# ---- lifecycle ----

func on_enter(args: Dictionary) -> void:
	if args.has("game") and LauncherCatalog.has(str(args["game"])):
		hero_id = str(args["game"])
	_close_panel()
	zone = ZONE_MENU
	row = ROW_START
	_refresh(false)

func on_exit() -> void:
	_close_panel()

func backdrop() -> Dictionary:
	return {"layer": &"hero", "game": hero_id}

# ---- data ----

## Played games that the catalog still has, most recent first.
func recent_ids() -> Array[String]:
	var out: Array[String] = []
	for id in shell.store.recents():
		if LauncherCatalog.has(id):
			out.append(id)
	return out

## Every game Left/Right can reach: the recents in shelf order, then the rest of the catalog. The second part has no card on the shelf (it only lists what was played) but must stay reachable, because Home is where a first game is started.
func selectable_ids() -> Array[String]:
	var out := recent_ids()
	for id in LauncherCatalog.ids():
		if not out.has(id):
			out.append(id)
	return out

## Share of a game's achievements that are unlocked, 0..1.
func achievement_ratio(game_id: String) -> float:
	var defined: Array = LauncherCatalog.by_id(game_id).get("achievements", [])
	if defined.is_empty():
		return 0.0
	var unlocked := shell.store.achievements(game_id)
	var count := 0
	for achievement: Dictionary in defined:
		if unlocked.has(achievement["id"]):
			count += 1
	return float(count) / float(defined.size())

func _unlocked_total() -> int:
	var count := 0
	for game in LauncherCatalog.all():
		var unlocked := shell.store.achievements(str(game["id"]))
		for achievement: Dictionary in game["achievements"]:
			if unlocked.has(achievement["id"]):
				count += 1
	return count

## "Not played yet", or the real last-played time and best score.
func _record_line(game_id: String) -> String:
	var stats := shell.store.stats(game_id)
	if int(stats["runs"]) == 0:
		return t("launcher.home.never_played")
	return tf("launcher.home.last_played_fmt", [LauncherFormat.when_time(int(stats["last_played"]), shell.now(), shell.locale), LauncherFormat.score(int(stats["best_score"]))])

# ---- rendering ----

func _refresh(animate: bool = true) -> void:
	var selectable := selectable_ids()
	if not selectable.has(hero_id):
		hero_id = selectable[0]
	var entry := LauncherCatalog.by_id(hero_id)
	var store := shell.store
	var favorite := store.is_favorite(hero_id)

	_eyebrow.text = "%s · %s" % [LauncherCatalog.text(entry, "genre", "en"), LauncherCatalog.players_label(entry)]
	_favorite_tag.visible = favorite
	_set_title(entry)
	_latin.text = LauncherCatalog.text(entry, "name", "en")
	W.restyle(_latin, 800, LauncherCatalog.color(entry, "colors", "title"), 14, true)
	# In English the title already is the Latin name, so the subtitle would only repeat it.
	_latin.visible = shell.locale != "en"
	_latin_gap.visible = _latin.visible
	_tagline.text = LauncherCatalog.text(entry, "tagline", shell.locale)

	_rows[ROW_START].set_text(t("launcher.home.start"), _record_line(hero_id))
	_rows[ROW_START].set_progress(achievement_ratio(hero_id))
	_rows[ROW_MENU].set_text(t("launcher.home.menu"), t("launcher.home.menu_sub"))
	_rows[ROW_ACHIEVEMENTS].set_text(t("launcher.home.achievements"), tf("launcher.home.achievements_sub_fmt", [_unlocked_total(), LauncherCatalog.achievement_total()]))
	for index in _rows.size():
		_rows[index].set_focused(zone == ZONE_MENU and index == row, animate)

	_sync_shelf(animate)
	set_footer([
		[In.ACCEPT, t("launcher.home.hint_start")],
		[In.Y, t("launcher.home.remove_favorite" if favorite else "launcher.home.add_favorite")],
		[In.MENU, t("launcher.home.hint_options")],
	])
	if _panel != null:
		_build_panel()
	shell.refresh_backdrop()

func _set_title(entry: Dictionary) -> void:
	var content := LauncherCatalog.text(entry, "name", shell.locale)
	var color := LauncherCatalog.color(entry, "colors", "title")
	var shadow := LauncherCatalog.color(entry, "colors", "shadow", Color.BLACK)
	var font_size := T.SIZE_HERO
	var settings := T.label_settings(font_size, 900, color, 6)
	# Long names (the Latin ones) are scaled down to stay inside the hero column.
	while font_size > 48 and settings.font.get_string_size(content, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > HERO_WIDTH:
		font_size -= 4
	settings.font_size = font_size
	settings.shadow_color = shadow
	settings.shadow_offset = Vector2(0, 4)
	settings.shadow_size = 0
	settings.add_stacked_shadow()
	settings.set_stacked_shadow_offset(0, Vector2(0, 10))
	settings.set_stacked_shadow_color(0, Color(0, 0, 0, 0.35))
	settings.set_stacked_shadow_outline_size(0, 0)
	_title.label_settings = settings
	_title.text = content
	_title.reset_size()
	_title.position = Vector2(0, (TITLE_BOX_HEIGHT - _title.size.y) / 2.0)
	_title_glow.color = LauncherCatalog.color(entry, "colors", "glow")
	_title_glow.position = Vector2(-80, -50)
	_title_glow.size = Vector2(_title.size.x + 160, TITLE_BOX_HEIGHT + 100)
	_title_glow.queue_redraw()

func _sync_shelf(animate: bool) -> void:
	var recents := recent_ids()
	if recents != _shelf_ids or not _shelf_built:
		_shelf_ids = recents
		_shelf_built = true
		_cards.clear()
		W.clear(_shelf_row)
		_empty = null
		for id in recents:
			var card := C.ArtCard.new(id)
			card.name = "Card_%s" % id
			card.activated.connect(func() -> void: _pick(id))
			_shelf_row.add_child(card)
			_cards[id] = card
		if recents.is_empty():
			_empty = W.text(t("launcher.home.recents_empty"), T.SIZE_BODY, 400, T.fg(T.A_MUTED), 1)
			_empty.name = "Empty"
			_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_empty.custom_minimum_size = Vector2(520, T.CARD_SIZE.y)
			_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_empty.size_flags_vertical = Control.SIZE_SHRINK_END
			var holder := W.vbox(12)
			holder.size_flags_vertical = Control.SIZE_SHRINK_END
			holder.add_child(_empty)
			holder.add_child(W.text(" ", T.SIZE_SMALL))
			_shelf_row.add_child(holder)
		_tile = C.Tile.new("grid", t("launcher.home.all_games"), tf("launcher.home.all_games_sub_fmt", [LauncherCatalog.all().size()]))
		_tile.name = "AllGames"
		_tile.activated.connect(func() -> void: shell.go(LauncherRoot.LIBRARY))
		_shelf_row.add_child(_tile)
		animate = false
	for id: String in _cards:
		var card: LauncherControls.ArtCard = _cards[id]
		var stats := shell.store.stats(id)
		card.set_caption(LauncherCatalog.text(LauncherCatalog.by_id(id), "name", shell.locale), LauncherFormat.when_day(int(stats["last_played"]), shell.now(), shell.locale))
		card.set_progress(achievement_ratio(id))
		card.set_favorite(shell.store.is_favorite(id))
		card.set_selected(id == hero_id, animate)
	_tile.set_focused(zone == ZONE_TILE)

# ---- focus and actions ----

func handle_action(action: StringName) -> bool:
	if zone == ZONE_PANEL:
		return _panel_action(action)
	match action:
		In.UP:
			if zone == ZONE_TILE:
				zone = ZONE_MENU
			else:
				row = maxi(0, row - 1)
		In.DOWN:
			if zone == ZONE_TILE:
				zone = ZONE_MENU
			else:
				row = mini(_rows.size() - 1, row + 1)
		In.LEFT:
			_step_game(-1)
		In.RIGHT:
			_step_game(1)
		In.ACCEPT:
			if zone == ZONE_TILE:
				shell.go(LauncherRoot.LIBRARY)
			else:
				_activate_row()
			return true
		In.Y:
			_toggle_favorite()
			return true
		In.MENU:
			_open_panel()
			return true
		_:
			return false
	_refresh()
	return true

func _step_game(step: int) -> void:
	var selectable := selectable_ids()
	if zone == ZONE_TILE:
		if step < 0:
			zone = ZONE_MENU
		return
	var index := selectable.find(hero_id) + step
	if index >= selectable.size():
		zone = ZONE_TILE
	elif index >= 0:
		hero_id = selectable[index]
		row = ROW_START

func _pick(game_id: String) -> void:
	hero_id = game_id
	zone = ZONE_MENU
	row = ROW_START
	_refresh()

func _focus_row(index: int) -> void:
	if zone == ZONE_PANEL or (zone == ZONE_MENU and row == index):
		return
	zone = ZONE_MENU
	row = index
	_refresh()

func _activate_row() -> void:
	match row:
		ROW_START:
			start_game()
		ROW_MENU:
			shell.go(LauncherRoot.MENU, {"game": hero_id})
		ROW_ACHIEVEMENTS:
			shell.go(LauncherRoot.ACHIEVEMENTS, {"game": hero_id})

## Launch the selected game.
func start_game() -> void:
	shell.go(LauncherRoot.GAME, {"game": hero_id})

func _toggle_favorite() -> void:
	var game_id := hero_id
	var was := shell.store.is_favorite(game_id)
	var title := LauncherCatalog.text(LauncherCatalog.by_id(game_id), "name", shell.locale)
	shell.store.set_favorite(game_id, not was)
	shell.toast(tf("launcher.home.unfavorited_fmt" if was else "launcher.home.favorited_fmt", [title]), func() -> void: shell.store.set_favorite(game_id, was))

func _remove_recent() -> void:
	var game_id := hero_id
	var title := LauncherCatalog.text(LauncherCatalog.by_id(game_id), "name", shell.locale)
	var index := shell.store.remove_recent(game_id)
	if index < 0:
		return
	_close_panel()
	hero_id = ""
	_refresh()
	shell.toast(tf("launcher.home.removed_recent_fmt", [title]), func() -> void:
		shell.store.restore_recent(game_id, index)
		hero_id = game_id
		_refresh())

# ---- options panel ----

func is_panel_open() -> bool:
	return _panel != null

func _open_panel() -> void:
	zone = ZONE_PANEL
	panel_row = 0
	_build_panel()

func _close_panel() -> void:
	if _panel != null:
		shell.hide_overlay()
		_panel = null
	_panel_rows.clear()
	_panel_actions.clear()
	if zone == ZONE_PANEL:
		zone = ZONE_MENU

func _build_panel() -> void:
	_panel_rows.clear()
	_panel_actions.clear()
	_panel = Control.new()
	_panel.name = "OptionsPanel"
	# Mounted on the shell's overlay layer so the panel and its scrim also cover the top navigation.
	shell.show_overlay(_panel)
	var scrim := _Scrim.new()
	scrim.name = "Scrim"
	scrim.activated.connect(func() -> void:
		_close_panel()
		_refresh())
	_panel.add_child(W.fill(scrim))

	var aside := PanelContainer.new()
	aside.name = "Aside"
	var style := StyleBoxFlat.new()
	style.bg_color = T.PANEL
	style.border_color = T.fg(T.A_HAIRLINE)
	style.border_width_left = 1
	style.content_margin_left = 56
	style.content_margin_right = 56
	style.content_margin_top = 64
	style.content_margin_bottom = 64
	aside.add_theme_stylebox_override("panel", style)
	aside.position = Vector2(T.CANVAS.x - T.SIDE_PANEL_WIDTH, 0)
	aside.size = Vector2(T.SIDE_PANEL_WIDTH, T.CANVAS.y)
	_panel.add_child(aside)
	var column := W.vbox(6)
	aside.add_child(column)
	var entry := LauncherCatalog.by_id(hero_id)
	column.add_child(W.text(t("launcher.home.options"), T.SIZE_SMALL, 600, T.fg(T.A_MUTED), 5, true))
	column.add_child(_gap(2))
	var heading := W.text(LauncherCatalog.text(entry, "name", shell.locale), T.SIZE_PANEL_TITLE, 900, T.FG, 4)
	heading.name = "Heading"
	column.add_child(heading)
	column.add_child(W.text(_record_line(hero_id), T.SIZE_SUB, 400, T.fg(T.A_MUTED)))
	column.add_child(_gap(22))

	var favorite := shell.store.is_favorite(hero_id)
	_add_panel_row(column, t("launcher.home.remove_favorite" if favorite else "launcher.home.add_favorite"), _toggle_favorite)
	_add_panel_row(column, t("launcher.home.menu"), func() -> void: shell.go(LauncherRoot.MENU, {"game": hero_id}))
	_add_panel_row(column, t("launcher.home.view_achievements"), func() -> void: shell.go(LauncherRoot.ACHIEVEMENTS, {"game": hero_id}))
	if recent_ids().has(hero_id):
		_add_panel_row(column, t("launcher.home.remove_recent"), _remove_recent)
	var divider := MarginContainer.new()
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.add_theme_constant_override("margin_top", 14)
	divider.add_theme_constant_override("margin_bottom", 14)
	divider.add_child(W.rule(T.fg(0.14)))
	column.add_child(divider)
	_add_panel_row(column, t("launcher.nav.pc_mode"), shell.toggle_pc_mode).set_trailing(t("launcher.home.pc_mode_hint"))
	_add_panel_row(column, t("launcher.home.settings"), func() -> void: shell.go(LauncherRoot.SETTINGS))

	var close := C.GlyphHint.new(In.BACK, t("launcher.common.close"))
	close.name = "Close"
	close.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	close.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	close.activated.connect(func() -> void: shell.dispatch(In.BACK))
	column.add_child(close)
	panel_row = clampi(panel_row, 0, _panel_rows.size() - 1)
	_sync_panel_focus(false)

func _add_panel_row(column: Control, label: String, action: Callable) -> LauncherControls.FocusRow:
	var index := _panel_rows.size()
	var item := C.FocusRow.new(label, "", T.SIZE_PANEL_ROW, 56)
	item.name = "PanelRow%d" % index
	item.flat_fill = true
	item.set_focused(false, false)
	item.hovered.connect(func() -> void:
		panel_row = index
		_sync_panel_focus(true))
	item.activated.connect(func() -> void:
		panel_row = index
		action.call())
	column.add_child(item)
	_panel_rows.append(item)
	_panel_actions.append(action)
	return item

func _sync_panel_focus(animate: bool) -> void:
	for index in _panel_rows.size():
		_panel_rows[index].set_focused(index == panel_row, animate)

func _panel_action(action: StringName) -> bool:
	match action:
		In.UP:
			panel_row = posmod(panel_row - 1, _panel_rows.size())
			_sync_panel_focus(true)
		In.DOWN:
			panel_row = posmod(panel_row + 1, _panel_rows.size())
			_sync_panel_focus(true)
		In.ACCEPT:
			_panel_actions[panel_row].call()
		In.BACK, In.MENU:
			_close_panel()
			_refresh()
	# The panel is modal: nothing falls through to the shell while it is open.
	return true

func panel_labels() -> PackedStringArray:
	var out := PackedStringArray()
	for item in _panel_rows:
		out.append(item.label_text())
	return out

## Dimmed click-away area behind the options panel.
class _Scrim:
	extends LauncherControls.Pressable

	func _init() -> void:
		super()
		mouse_default_cursor_shape = Control.CURSOR_ARROW

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), LauncherTokens.deep(0.55))

## Soft light behind the hero title, standing in for the design's wide text glow.
class _Glow:
	extends Control

	var color := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var center := size / 2.0
		var inner := Color(color, 0.2)
		var outer := Color(color, 0.0)
		var segments := 48
		for i in segments:
			var a := Vector2.from_angle(TAU * float(i) / segments) * center
			var b := Vector2.from_angle(TAU * float(i + 1) / segments) * center
			draw_polygon(PackedVector2Array([center, center + a, center + b]), PackedColorArray([inner, outer, outer]))
