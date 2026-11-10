class_name StudioScreen
extends ScreenBase

## 创作中心:作品列表(已上线/审核中/草稿 + 曝光/进入/二创三栏)+ 编辑/数据/下架 + 发布新作。
## 作品只来自鉴权后的服务端「我的作品」列表，不展示伪造统计或种子作品。

signal edit_requested(work: Dictionary)
signal publish_requested
signal earnings_requested
signal review_requested(work: Dictionary)
signal game_opened(game: Dictionary)

const WORKSPACE_MUTATIONS := [
	"save_draft", "update_draft", "submit_for_review", "publish_game",
	"publish_draft", "fork_mod", "fork_game", "load_work", "delist",
	"resubmit", "decide", "review_queue"]

var works: Array = []
var _review_queue: Array = []
var coordinator: CreationCoordinator

func _init(p_state: Node, p_coordinator: CreationCoordinator = null) -> void:
	coordinator = p_coordinator
	if coordinator != null: coordinator.store.changed.connect(_on_creation_changed)
	super(p_state)

func refresh() -> void:
	if coordinator == null or not await coordinator.load_workspace(state.locale):
		_refreshed = false
		return
	_review_queue = []
	if await coordinator.load_review_queue():
		_review_queue = coordinator.store.review_queue.duplicate(true)
	set_works(coordinator.store.workspace_games, coordinator.store.workspace_drafts)
	_refreshed = true

func _on_creation_changed() -> void:
	if coordinator.store.status == "ready" and coordinator.store.operation in WORKSPACE_MUTATIONS:
		_refreshed = false

func set_works(items: Array, drafts: Array = []) -> void:
	works = items.duplicate(true)
	for source: Dictionary in drafts:
		var draft := source.duplicate(true)
		draft["status"] = "draft"
		draft["title"] = str(draft.get("title", "Draft %s" % str(draft.get("id", ""))))
		draft["plays"] = 0
		draft["forks"] = 0
		works.append(draft)
	rebuild()

func _status_index(status: String) -> int:
	match status:
		"published": return 0
		"reviewing": return 1
		_: return 2

func _build() -> void:
	var head := Widgets.hbox()
	head.add_child(Widgets.spacer())
	var new_btn := Widgets.primary_button(txt("st_new"), theme_name())
	new_btn.name = "NewButton"
	new_btn.pressed.connect(func() -> void: publish_requested.emit())
	head.add_child(new_btn)
	var ea_btn := Widgets.secondary_button(txt("ea_title"), theme_name())
	ea_btn.name = "EarningsButton"
	ea_btn.pressed.connect(func() -> void: earnings_requested.emit())
	head.add_child(ea_btn)
	content.add_child(head)

	if not _review_queue.is_empty():
		content.add_child(Widgets.heading(txt("st_queue"), 3, theme_name()))
		var queue := Widgets.vbox(Tokens.SPACE_2)
		queue.name = "ModerationQueue"
		for item: Dictionary in _review_queue:
			queue.add_child(_queue_card(item))
		content.add_child(queue)

	var list := Widgets.vbox(Tokens.SPACE_3)
	list.name = "WorkList"
	if works.is_empty():
		list.add_child(empty_note(txt("works_empty")))
		content.add_child(list)
		return
	var statuses: Array = txt("st_statuses")
	var cols: Array = txt("st_cols")
	var i18n := preload("res://i18n/i18n.gd")
	for game: Dictionary in works:
		var status := _status_index(str(game.get("status", "")))
		var card := Widgets.card(theme_name())
		var col := Widgets.vbox(Tokens.SPACE_2)
		card.add_child(col)
		var top := Widgets.hbox(Tokens.SPACE_3)
		var cov := GameCard.cover(game, 44)
		cov.custom_minimum_size = Vector2(44, 44)
		top.add_child(cov)
		var title := Widgets.body(GameCard.title_of(game, state.locale), theme_name())
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(title)
		top.add_child(Widgets.badge(statuses[status], theme_name(), status == 1))
		col.add_child(top)
		var stats := Widgets.hbox(Tokens.SPACE_4)
		var metrics := [int(game.get("views", 0)), int(game.get("plays", 0)), int(game.get("forks", 0))]
		for k in 3:
			stats.add_child(Widgets.caption("%s %s" % [cols[k], i18n.format_number(metrics[k], state.locale)], theme_name()))
		col.add_child(stats)
		var actions := Widgets.hbox(Tokens.SPACE_2)
		var work := game
		var edit := Widgets.secondary_button(txt("st_edit"), theme_name())
		edit.name = "EditButton"
		edit.pressed.connect(func() -> void: _edit(work))
		actions.add_child(edit)
		if status == 0:
			var data := Widgets.secondary_button(txt("st_data"), theme_name())
			data.pressed.connect(func() -> void: game_opened.emit(game))
			actions.add_child(data)
			var off := Widgets.secondary_button(txt("st_offline"), theme_name())
			off.pressed.connect(func() -> void:
				off.disabled = true
				if coordinator != null and await coordinator.delist(str(work.get("id", ""))):
					work["status"] = "delisted"
					_toast(txt("st_off_toast"))
					rebuild()
				else:
					off.disabled = false
					_toast(txt("request_failed")))
			actions.add_child(off)
		elif status == 1:
			var rev := Widgets.secondary_button(txt("rev_title"), theme_name())
			rev.name = "ReviewButton"
			rev.pressed.connect(func() -> void: review_requested.emit({"id": work.get("id", "")}))
			actions.add_child(rev)
		col.add_child(actions)
		list.add_child(card)
	content.add_child(list)

func _queue_card(item: Dictionary) -> Control:
	var game_id := str(item.get("id", ""))
	var card := Widgets.card(theme_name(), &"surface_raised")
	card.name = "Queue_%s" % game_id
	var col := Widgets.vbox(Tokens.SPACE_2)
	card.add_child(col)
	col.add_child(Widgets.body(GameCard.title_of(item, state.locale) if item.has("title") else game_id, theme_name()))
	var actions := Widgets.hbox(Tokens.SPACE_2)
	var approve := Widgets.primary_button(txt("mq_approve"), theme_name())
	approve.name = "QueueApprove_%s" % game_id
	approve.pressed.connect(func() -> void:
		if coordinator == null: return
		if await coordinator.decide(game_id, true):
			_review_queue = _review_queue.filter(func(row): return str(row.get("id", "")) != game_id)
			rebuild())
	actions.add_child(approve)
	var reject := Widgets.danger_button(txt("mq_reject"), theme_name())
	reject.name = "QueueReject_%s" % game_id
	reject.pressed.connect(func() -> void:
		if coordinator == null: return
		if await coordinator.decide(game_id, false):
			_review_queue = _review_queue.filter(func(row): return str(row.get("id", "")) != game_id)
			rebuild())
	actions.add_child(reject)
	col.add_child(actions)
	return card

func _edit(work: Dictionary) -> void:
	if coordinator != null and await coordinator.load_work(work):
		edit_requested.emit(work)
	else:
		_toast(txt("forge_failed"))
