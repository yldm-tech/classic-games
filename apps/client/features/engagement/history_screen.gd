class_name HistoryScreen
extends ScreenBase

## 最近玩过:按天分组、清空 → 空态；登录后展示服务端记录的真实游玩历史。

signal game_opened(game: Dictionary)
signal play_requested(game: Dictionary)

# 组下标(今天/昨天/更早)→ [游戏id, 玩了n分钟]
var groups: Array = [[], [], []]
## 服务端 group 字符串 → groups 下标(他端口径,本地化标签仍走 his_groups)。
const GROUP_INDEX := {"today": 0, "yesterday": 1, "earlier": 2}
## 服务端 /history 注入的游戏元数据(id → game dict)。
var _games_by_id: Dictionary = {}
var engagement: EngagementCoordinator

func _init(p_state: Node, p_engagement: EngagementCoordinator = null) -> void:
	engagement = p_engagement
	super(p_state)

## AppRoot 首次展示时调用:拉 /history,把分组映射成 groups 形态(保留清空行为)。
func refresh() -> void:
	if engagement == null or not await engagement.load_history(state.locale): return
	var server_groups: Array = engagement.store.history_groups
	var new_groups: Array = [[], [], []]
	var by_id: Dictionary = {}
	for g: Dictionary in server_groups:
		var gi: int = GROUP_INDEX.get(g.get("group", ""), -1)
		if gi < 0:
			continue
		for it: Dictionary in g.get("items", []):
			var game: Dictionary = it.get("game", {})
			var id: String = game.get("id", "")
			by_id[id] = game
			new_groups[gi].append([id, int(it.get("minutes_played", 0))])
	groups = new_groups
	_games_by_id = by_id
	rebuild()

## Resolve a history row's game. Missing metadata stays empty, never a seed title.
func _game_for(id: String) -> Dictionary:
	if _games_by_id.has(id):
		return _games_by_id[id]
	return {}

func clear_all() -> void:
	if engagement == null:_toast(txt("request_failed"));return
	if not await engagement.clear_history(): return
	groups = [[], [], []]; _toast(txt("his_cleared_toast")); rebuild()

func _build() -> void:
	var total := 0
	for g: Array in groups:
		total += g.size()
	if total == 0:
		content.add_child(empty_note(txt("his_empty"), txt("empty_go_explore")))
		return

	var head := Widgets.hbox()
	head.add_child(Widgets.spacer())
	var clear := Widgets.secondary_button(txt("his_clear"), theme_name())
	clear.name = "ClearButton"
	clear.disabled = engagement != null and engagement.store.history_pending
	clear.pressed.connect(clear_all)
	head.add_child(clear)
	content.add_child(head)

	var titles: Array = txt("his_groups")
	for gi in groups.size():
		if groups[gi].is_empty():
			continue
		content.add_child(Widgets.caption(titles[gi], theme_name()))
		var list := Widgets.vbox(Tokens.SPACE_2)
		list.name = "Group%d" % gi
		for e: Array in groups[gi]:
			var game := _game_for(e[0])
			var card := Widgets.card(theme_name())
			var row := Widgets.hbox(Tokens.SPACE_3)
			card.add_child(row)
			var cov := GameCard.cover(game, 44)
			cov.custom_minimum_size = Vector2(44, 44)
			row.add_child(cov)
			var col := Widgets.vbox(Tokens.SPACE_1)
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.add_child(Widgets.body(GameCard.title_of(game, state.locale), theme_name()))
			col.add_child(Widgets.caption(txt_fmt("played_fmt", [int(e[1])]), theme_name()))
			row.add_child(col)
			var play := Widgets.primary_button("▶", theme_name())
			play.custom_minimum_size = Vector2(Tokens.HIT_MIN, Tokens.HIT_MIN)
			play.size_flags_vertical = Control.SIZE_SHRINK_CENTER  # 否则被行高纵向拉成竖条
			play.pressed.connect(func() -> void: play_requested.emit(game))
			row.add_child(play)
			card.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					game_opened.emit(game))
			list.add_child(card)
		content.add_child(list)
