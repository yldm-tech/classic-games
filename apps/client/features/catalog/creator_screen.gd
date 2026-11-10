class_name CreatorScreen
extends ScreenBase

## 创作者主页:头卡(handle/关注按钮)+ 作品/粉丝/获赞 + TA 的作品。

signal game_opened(game: Dictionary)
signal follow_requested(handle: String, following: bool)

var handle := ""
var following := false
var catalog: CatalogCoordinator
var community: Variant
## Stats and works come from /users/:handle. Empty until the server answers.
var _profile: Dictionary = {}
var _works: Array = []

func _init(p_state: Node, p_catalog: CatalogCoordinator = null, p_community: Variant = null) -> void:
	catalog = p_catalog
	community = p_community
	super(p_state)

func set_creator(p_handle: String) -> void:
	handle = p_handle
	following = false
	# Switching creators drops the previous profile so we never flash someone else's stats.
	_profile = {}
	_works = []
	rebuild()
	# set_creator 可能在首次展示后再调(换人),此处也补一次拉取(_refreshed 只触发一次 refresh)。
	_fetch()

## AppRoot 首次展示时调用;用当前 handle 拉数据。
func refresh() -> void:
	await _fetch()

## Load profile stats and works for the current handle.
func _fetch() -> void:
	if catalog == null:
		return
	var who := handle
	var profile_loaded: bool = await catalog.load_profile(who, state.locale)
	var profile := catalog.store.profile.duplicate(true) if profile_loaded else {}
	var games_loaded: bool = await catalog.load_user_games(who, "works", state.locale)
	var games := catalog.store.profile_games.duplicate(true) if games_loaded else []
	# 异步期间用户可能又切了创作者,过期响应丢弃。
	if who != handle:
		return
	var changed := false
	if profile_loaded:
		_profile = profile
		changed = true
	if games_loaded:
		if not games.is_empty():
			_works = games
			changed = true
	if community != null and community.has_method("load_follow_lists"):
		await community.load_follow_lists(state.locale)
		if who != handle:
			return
		var next_following: bool = community.is_following(handle) if community.has_method("is_following") else false
		if next_following != following:
			following = next_following
			changed = true
	if changed:
		rebuild()

func _build() -> void:
	if handle.strip_edges() == "":
		content.add_child(empty_note(txt("works_empty")))
		return
	var card := Widgets.card(theme_name())
	card.name = "CreatorCard"
	var row := Widgets.hbox(Tokens.SPACE_3)
	card.add_child(row)
	row.add_child(Widgets.avatar(handle, theme_name(), 56))
	var col := Widgets.vbox(Tokens.SPACE_1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_lbl := Widgets.heading(handle, 2, theme_name())
	name_lbl.name = "CreatorName"
	col.add_child(name_lbl)
	row.add_child(col)
	var follow := Widgets.secondary_button(txt("following"), theme_name()) if following \
		else Widgets.primary_button(txt("follow"), theme_name())
	follow.name = "FollowButton"
	follow.pressed.connect(func() -> void: follow_requested.emit(handle, not following))
	row.add_child(follow)
	content.add_child(card)

	var grid := GridContainer.new()
	grid.name = "StatsGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", Tokens.SPACE_2)
	var i18n := preload("res://i18n/i18n.gd")
	var labels: Array = txt("creator_stats")
	var values: Array = [int(_profile.get("works", 0)), int(_profile.get("follows", 0)), int(_profile.get("likes", 0))]
	for i in labels.size():
		grid.add_child(Widgets.kpi_card(i18n.format_number(values[i], state.locale), str(labels[i]), theme_name()))
	content.add_child(grid)

	content.add_child(Widgets.heading(txt("creator_works"), 3, theme_name()))
	var works := GridContainer.new()
	works.name = "WorksGrid"
	works.columns = card_cols
	works.add_theme_constant_override("h_separation", Tokens.SPACE_3)
	works.add_theme_constant_override("v_separation", Tokens.SPACE_3)
	var pool: Array = _works
	for g: Dictionary in pool:
		works.add_child(GameCard.build(g, state.locale, theme_name(), func(gg: Dictionary) -> void: game_opened.emit(gg)))
	if pool.is_empty():
		works.add_child(empty_note(txt("works_empty")))
	content.add_child(works)

func set_following(value: bool) -> void:
	following = value
	if following:
		_toast(txt_fmt("toast_followed_fmt", [handle]))
	rebuild()
