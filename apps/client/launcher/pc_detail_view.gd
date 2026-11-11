class_name LauncherPcDetailView
extends Control

## PC mode's page for one game: the hero (key art, title, tagline, the play / game menu / favourite / more buttons and the last-played line), a tab row with the record summary on its right, and under it either the overview tiles or the achievements.
##
## It draws what LauncherPcMode tells it to (`show_game`) and reports clicks through its signals; it changes no state itself. Everything about the player is read from the store: a game that was never played shows dashes and an empty overview instead of numbers.

signal play_pressed
signal menu_pressed
signal favorite_pressed
signal more_pressed
signal tab_picked(index: int)
signal only_locked_toggled
signal all_achievements_pressed

const T := preload("res://launcher/launcher_tokens.gd")
const W := preload("res://launcher/launcher_widgets.gd")
const C := preload("res://launcher/launcher_controls.gd")
const P := preload("res://launcher/pc_tokens.gd")
const PC := preload("res://launcher/pc_controls.gd")
const Lib := preload("res://launcher/pc_library.gd")

const TAB_OVERVIEW := 0
const TAB_ACHIEVEMENTS := 1
const TAB_KEYS: Array[String] = ["launcher.pc.tab.overview", "launcher.pc.tab.achievements"]
const TITLE_BOX_HEIGHT := 84.0

var shell: LauncherRoot
var game_id := ""

var _entry: Dictionary = {}

var _art: LauncherKeyArt
var _eyebrow: Label
var _title_box: Control
var _title: Label
var _tagline: Label
var _play: LauncherPcControls.Pill
var _menu: LauncherPcControls.Pill
var _favorite: LauncherPcControls.IconButton
var _more: LauncherPcControls.IconButton
var _record: Label
## Untyped so that focus_rows() hands LauncherPcMode plain arrays of widgets.
var _tabs: Array = []
var _summary: Dictionary = {}
var _scroll: ScrollContainer
var _content: VBoxContainer
var _only_locked: LauncherPcControls.Check
var _all_achievements: LauncherPcControls.Pill

func setup(p_shell: LauncherRoot) -> void:
	shell = p_shell
	name = "Detail"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := W.vbox(0)
	add_child(W.fill(column))
	column.add_child(_build_hero())
	column.add_child(_build_tab_row())
	_scroll = PC.Paint.scroll()
	_scroll.name = "Scroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", roundi(P.DETAIL_PADDING))
	margin.add_theme_constant_override("margin_right", roundi(P.DETAIL_PADDING))
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	_scroll.add_child(margin)
	_content = W.vbox(14)
	_content.name = "Content"
	margin.add_child(_content)

func _build_hero() -> Control:
	var hero := Control.new()
	hero.name = "Hero"
	hero.custom_minimum_size = Vector2(0, P.HERO_HEIGHT)
	hero.clip_contents = true
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art = LauncherKeyArt.new()
	_art.name = "Art"
	W.fill(_art)
	_art.offset_left = P.HERO_ART_LEFT
	hero.add_child(_art)
	var clear := Color(P.WINDOW_BG, 0.0)
	hero.add_child(W.fill(C.GradientRect.new([[0.0, P.WINDOW_BG], [0.27, P.WINDOW_BG], [0.4, Color(P.WINDOW_BG, 0.75)], [0.58, clear], [1.0, clear]], true)))
	var bottom := C.GradientRect.new([[0.0, clear], [1.0, P.WINDOW_BG]])
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -180
	hero.add_child(bottom)

	var text := W.vbox(0)
	text.name = "Text"
	text.anchor_top = 1.0
	text.anchor_bottom = 1.0
	text.offset_left = P.DETAIL_PADDING
	text.offset_right = P.DETAIL_PADDING + P.HERO_TEXT_WIDTH
	text.offset_top = -40
	text.offset_bottom = -40
	text.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hero.add_child(text)

	var eyebrow := W.hbox(12)
	var dash := W.rule(T.fg(T.A_MUTED))
	dash.custom_minimum_size = Vector2(32, 1)
	dash.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	eyebrow.add_child(dash)
	_eyebrow = W.text("", P.SIZE_LABEL, 600, T.fg(T.A_BODY), 4, true)
	_eyebrow.name = "Eyebrow"
	eyebrow.add_child(_eyebrow)
	text.add_child(eyebrow)
	text.add_child(_gap(14))
	_title_box = Control.new()
	_title_box.custom_minimum_size = Vector2(P.HERO_TEXT_WIDTH, TITLE_BOX_HEIGHT)
	_title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = Label.new()
	_title.name = "Title"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_box.add_child(_title)
	text.add_child(_title_box)
	text.add_child(_gap(14))
	_tagline = W.text("", P.SIZE_TAGLINE, 300, T.fg(0.88), 1)
	_tagline.name = "Tagline"
	text.add_child(_tagline)
	text.add_child(_gap(22))

	var buttons := W.hbox(10)
	buttons.name = "Buttons"
	text.add_child(buttons)
	_play = PC.Pill.new(shell.t("launcher.home.start"), PC.Pill.PRIMARY, P.BUTTON_HEIGHT, P.SIZE_BUTTON, 28.0, "play", 2.0)
	_play.name = "Play"
	_play.activated.connect(func() -> void: play_pressed.emit())
	buttons.add_child(_play)
	_menu = PC.Pill.new(shell.t("launcher.home.menu"), PC.Pill.OUTLINE, P.BUTTON_HEIGHT, P.SIZE_NAME, 20.0, "", 1.0)
	_menu.name = "GameMenu"
	_menu.activated.connect(func() -> void: menu_pressed.emit())
	buttons.add_child(_menu)
	_favorite = PC.IconButton.new("heart_line", P.BUTTON_HEIGHT, 18.0)
	_favorite.name = "Favorite"
	_favorite.activated.connect(func() -> void: favorite_pressed.emit())
	buttons.add_child(_favorite)
	_more = PC.IconButton.new("dots", P.BUTTON_HEIGHT, 18.0)
	_more.name = "More"
	_more.tooltip_text = shell.t("launcher.pc.more")
	_more.activated.connect(func() -> void: more_pressed.emit())
	buttons.add_child(_more)
	var record_gap := Control.new()
	record_gap.custom_minimum_size = Vector2(0, 0)
	record_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.add_child(record_gap)
	_record = W.text("", P.SIZE_TEXT, 400, T.fg(0.7))
	_record.name = "Record"
	_record.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buttons.add_child(_record)
	return hero

func _build_tab_row() -> Control:
	var bar := PanelContainer.new()
	bar.name = "TabRow"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = P.LINE
	style.border_width_bottom = 1
	style.content_margin_left = P.DETAIL_PADDING
	style.content_margin_right = P.DETAIL_PADDING
	bar.add_theme_stylebox_override("panel", style)
	var row := W.hbox(28)
	bar.add_child(row)
	for index in TAB_KEYS.size():
		var tab := _Tab.new(shell.t(TAB_KEYS[index]))
		tab.name = "Tab%d" % index
		tab.activated.connect(func() -> void: tab_picked.emit(index))
		row.add_child(tab)
		_tabs.append(tab)
	var summary := W.hbox(28)
	summary.name = "Summary"
	summary.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(summary)
	for key in ["best", "progress", "time"]:
		var pair := W.hbox(8)
		var caption := W.text(shell.t("launcher.pc.stat.%s" % key), P.SIZE_NOTE, 400, P.TEXT_MUTED)
		caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pair.add_child(caption)
		var value := W.text("", P.SIZE_NAME, 700, T.FG, 0, true)
		value.name = "Summary_%s" % key
		pair.add_child(value)
		summary.add_child(pair)
		_summary[key] = value
	return bar

func _gap(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer

# ---- rendering ----

## Show `entry` with the given tab open. `only_locked` hides the unlocked achievements on the achievements tab.
func show_game(entry: Dictionary, tab: int, only_locked: bool) -> void:
	var store := shell.store
	var locale := shell.locale
	_entry = entry
	game_id = str(entry["id"])
	var stats := store.stats(game_id)
	var played := int(stats["runs"]) > 0
	var favorite := store.is_favorite(game_id)
	var total := (entry.get("achievements", []) as Array).size()
	var unlocked := Lib.unlocked_count(entry, store)

	_art.game_id = game_id
	_eyebrow.text = "%s · %s" % [LauncherCatalog.text(entry, "genre", "en"), LauncherCatalog.players_label(entry)]
	_set_title(entry)
	_tagline.text = LauncherCatalog.text(entry, "tagline", locale)
	_favorite.set_icon("heart" if favorite else "heart_line", T.FAVORITE if favorite else T.FG)
	_favorite.tooltip_text = shell.t("launcher.home.remove_favorite" if favorite else "launcher.home.add_favorite")
	_record.text = shell.tf("launcher.pc.last_played_fmt", [LauncherFormat.when_time(int(stats["last_played"]), shell.now(), locale)]) if played else shell.t("launcher.home.never_played")

	(_summary["best"] as Label).text = LauncherFormat.score(int(stats["best_score"])) if played else shell.t("launcher.pc.stat.none")
	(_summary["progress"] as Label).text = "%d%%" % roundi(Lib.achievement_ratio(entry, store) * 100.0)
	(_summary["time"] as Label).text = LauncherFormat.play_time(float(stats["play_seconds"]), locale) if played else shell.t("launcher.pc.stat.none")
	for index in _tabs.size():
		(_tabs[index] as _Tab).set_selected(index == tab)

	W.clear(_content)
	_only_locked = null
	_all_achievements = null
	if tab == TAB_ACHIEVEMENTS:
		_fill_achievements(entry, unlocked, total, only_locked)
	else:
		_fill_overview(stats, played, unlocked, total)

func _set_title(entry: Dictionary) -> void:
	var content := LauncherCatalog.text(entry, "name", shell.locale)
	var font_size := P.SIZE_HERO
	var settings := T.label_settings(font_size, 900, LauncherCatalog.color(entry, "colors", "title"), 4)
	# Long names (the Latin ones) are scaled down to stay inside the text column.
	while font_size > 40 and settings.font.get_string_size(content, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > P.HERO_TEXT_WIDTH:
		font_size -= 4
	settings.font_size = font_size
	settings.shadow_color = LauncherCatalog.color(entry, "colors", "shadow", Color.BLACK)
	settings.shadow_offset = Vector2(0, 3)
	settings.shadow_size = 0
	settings.add_stacked_shadow()
	settings.set_stacked_shadow_offset(0, Vector2(0, 8))
	settings.set_stacked_shadow_color(0, Color(0, 0, 0, 0.35))
	settings.set_stacked_shadow_outline_size(0, 0)
	_title.label_settings = settings
	_title.text = content
	_title.reset_size()
	_title.position = Vector2(0, (TITLE_BOX_HEIGHT - _title.size.y) / 2.0)

func _fill_overview(stats: Dictionary, played: bool, unlocked: int, total: int) -> void:
	if not played:
		var empty := W.text(shell.t("launcher.pc.overview.empty"), P.SIZE_ROW, 400, P.TEXT_SOFT)
		empty.name = "OverviewEmpty"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(0, 40)
		_content.add_child(empty)
		return
	_content.add_child(_section("launcher.pc.overview.record"))
	var tiles := PC.Flow.new(P.STAT_MIN_WIDTH, 10.0, 10.0, P.STAT_HEIGHT, 6)
	tiles.name = "Stats"
	var locale := shell.locale
	var facts := [
		["best", LauncherFormat.score(int(stats["best_score"]))],
		["runs", str(int(stats["runs"]))],
		["clears", str(int(stats["clears"]))],
		["time", LauncherFormat.play_time(float(stats["play_seconds"]), locale)],
		["last", LauncherFormat.when_time(int(stats["last_played"]), shell.now(), locale)],
		["progress", "%d / %d" % [unlocked, total]],
	]
	for fact: Array in facts:
		var tile := PC.StatTile.new(shell.t("launcher.pc.stat.%s" % fact[0]), str(fact[1]))
		tile.name = "Stat_%s" % fact[0]
		tiles.add_child(tile)
	_content.add_child(tiles)
	_fill_recent_unlocks()

## The achievements of this game that were unlocked last, newest first, at most one row of them.
func _fill_recent_unlocks() -> void:
	var times := shell.store.achievements(game_id)
	var earned: Array = []
	var defined: Array = _entry.get("achievements", [])
	for index in defined.size():
		if times.has(defined[index]["id"]):
			earned.append([-int(times[defined[index]["id"]]), index])
	if earned.is_empty():
		return
	earned.sort()
	_content.add_child(_gap(8))
	_content.add_child(_section("launcher.pc.overview.recent_unlocks"))
	var cards := PC.Flow.new(P.ACHIEVEMENT_MIN_WIDTH, 10.0, 10.0, P.ACHIEVEMENT_HEIGHT, 4)
	cards.name = "RecentUnlocks"
	for item: Array in earned.slice(0, 4):
		cards.add_child(_achievement_card(defined[item[1]], times))
	_content.add_child(cards)

func _section(key: String) -> Label:
	return W.text(shell.t(key), P.SIZE_TEXT, 500, P.TEXT_SOFT, 3)

func _achievement_card(achievement: Dictionary, times: Dictionary) -> LauncherPcControls.AchievementCard:
	var id := str(achievement["id"])
	var done := times.has(id)
	var state := shell.tf("launcher.pc.ach.unlocked_fmt", [LauncherFormat.when_day(int(times[id]), shell.now(), shell.locale)]) if done else shell.t("launcher.pc.ach.locked")
	var card := PC.AchievementCard.new(str(achievement.get("icon", "star")), LauncherCatalog.text(achievement, "name", shell.locale), LauncherCatalog.text(achievement, "desc", shell.locale), state, done)
	card.name = "Achievement_%s" % id
	return card

func _fill_achievements(entry: Dictionary, unlocked: int, total: int, only_locked: bool) -> void:
	var header := W.hbox(16)
	header.name = "AchievementHeader"
	_content.add_child(header)
	var count := W.text("%d / %d" % [unlocked, total], P.SIZE_STAT, 800, T.FG, 0, true)
	count.name = "AchievementCount"
	header.add_child(count)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(240, 4)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := ColorRect.new()
	track.color = P.BORDER
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(W.fill(track))
	var fill := ColorRect.new()
	fill.color = T.FG
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.anchor_bottom = 1.0
	fill.anchor_right = float(unlocked) / float(total) if total > 0 else 0.0
	bar.add_child(fill)
	header.add_child(bar)
	_only_locked = PC.Check.new(shell.t("launcher.pc.ach.only_locked"))
	_only_locked.name = "OnlyLocked"
	_only_locked.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	_only_locked.set_checked(only_locked)
	_only_locked.activated.connect(func() -> void: only_locked_toggled.emit())
	header.add_child(_only_locked)
	_all_achievements = PC.Pill.new(shell.t("launcher.pc.ach.all"), PC.Pill.LINK, 30.0, P.SIZE_TEXT, 6.0)
	_all_achievements.name = "AllAchievements"
	_all_achievements.activated.connect(func() -> void: all_achievements_pressed.emit())
	header.add_child(_all_achievements)

	var times := shell.store.achievements(game_id)
	var cards := PC.Flow.new(P.ACHIEVEMENT_MIN_WIDTH, 10.0, 10.0, P.ACHIEVEMENT_HEIGHT, 4)
	cards.name = "Achievements"
	for achievement: Dictionary in entry.get("achievements", []):
		if only_locked and times.has(achievement["id"]):
			continue
		cards.add_child(_achievement_card(achievement, times))
	if cards.get_child_count() == 0:
		cards.free()
		var none := W.text(shell.t("launcher.pc.ach.none_locked"), P.SIZE_ROW, 400, P.TEXT_SOFT)
		none.name = "AchievementsEmpty"
		_content.add_child(none)
		return
	_content.add_child(cards)

# ---- for LauncherPcMode ----

## The buttons keyboard focus can visit, row by row from the top.
func focus_rows() -> Array:
	var rows: Array = [[_play, _menu, _favorite, _more], _tabs.duplicate()]
	if _only_locked != null:
		rows.append([_only_locked, _all_achievements])
	return rows

func more_button() -> Control:
	return _more

func scroll_area() -> ScrollContainer:
	return _scroll

## A tab of the detail page: selected = bold white text with a 2px underline.
class _Tab:
	extends LauncherPcControls.Clickable

	var selected := false

	var _label: Label

	func _init(title: String) -> void:
		super()
		custom_minimum_size = Vector2(0, LauncherPcTokens.TAB_HEIGHT)
		_label = LauncherWidgets.text(title, LauncherPcTokens.SIZE_ROW, 400, LauncherPcTokens.TEXT_MUTED, 2)
		_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(_label)

	func set_selected(on: bool) -> void:
		selected = on
		_restyle()

	func _restyle() -> void:
		var ink := LauncherTokens.FG if selected or hover else LauncherPcTokens.TEXT_MUTED
		_label.label_settings = LauncherTokens.label_settings(LauncherPcTokens.SIZE_ROW, 700 if selected else 400, ink, 2)
		queue_redraw()

	func _paint() -> void:
		if selected:
			draw_rect(Rect2(0, size.y - LauncherPcTokens.TAB_UNDERLINE, size.x, LauncherPcTokens.TAB_UNDERLINE), LauncherTokens.FG)
