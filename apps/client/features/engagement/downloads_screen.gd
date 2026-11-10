class_name DownloadsScreen
extends ScreenBase

const ConfirmSheetScript:=preload("res://ui/patterns/confirm_sheet.gd")

## 下载管理:游戏包列表(更新/删除)、存储占用、空态。
## 条目只来自服务端下载状态。

signal game_opened(game: Dictionary)

# [游戏id, 大小MB, 是否有更新]
var entries: Array = []
## 服务端 /downloads 注入的游戏元数据(id → game dict)。
var _games_by_id: Dictionary = {}
var engagement: EngagementCoordinator
var _delete_id:=""
var _delete_pending:=false

func _init(p_state: Node, p_engagement: EngagementCoordinator = null) -> void:
	engagement = p_engagement
	super(p_state)

## AppRoot 首次展示时调用:拉 /downloads,把条目映射成 entries 形态(供更新/删除复用)。
func refresh() -> void:
	if engagement == null or not await engagement.load_downloads(state.locale): return
	_adopt_downloads(engagement.store.downloads)

func _adopt_downloads(items: Array) -> void:
	var new_entries: Array = []
	var by_id: Dictionary = {}
	for it: Dictionary in items:
		var game: Dictionary = it.get("game", {})
		var id: String = game.get("id", "")
		by_id[id] = game
		new_entries.append([id, int(it.get("size_mb", 0)), bool(it.get("has_update", false))])
	entries = new_entries
	_games_by_id = by_id
	rebuild()

## Resolve a download row's game. Missing metadata stays empty, never a seed title.
func _game_for(id: String) -> Dictionary:
	if _games_by_id.has(id):
		return _games_by_id[id]
	return {}

func _build() -> void:
	if entries.is_empty():
		content.add_child(empty_note(txt("dl_empty")))
		return

	var used := 0
	for e: Array in entries:
		used += int(e[1])
	var storage := Widgets.caption(txt_fmt("storage_fmt", ["%d MB" % used]), theme_name())
	storage.name = "StorageLabel"
	content.add_child(storage)

	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "DlList"
	if _delete_id!="":
		var confirm=ConfirmSheetScript.new();confirm.name="DownloadDeleteConfirm";confirm.configure(txt("dl_delete"),txt("dl_delete_desc"),txt("dl_delete"),txt("cancel"),theme_name())
		confirm.set_pending(_delete_pending)
		confirm.cancelled.connect(func():
			if _delete_pending:return
			_delete_id="";rebuild())
		confirm.confirmed.connect(func():
			if _delete_pending:return
			var deleting:=_delete_id;_delete_pending=true;rebuild()
			if engagement==null or not await engagement.remove_download(deleting):_delete_pending=false;_toast(txt("request_failed"));rebuild();return
			_delete_id="";_delete_pending=false
			_adopt_downloads(engagement.store.downloads);_toast(txt("dl_deleted_toast")))
		list.add_child(confirm)
	for i in entries.size():
		var e: Array = entries[i]
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
		col.add_child(Widgets.caption("%d MB" % int(e[1]), theme_name()))
		row.add_child(col)
		var game_id := str(e[0])
		var upd := Widgets.secondary_button(txt("dl_update") if e[2] else txt("dl_updated"), theme_name())
		upd.disabled = not e[2]
		upd.pressed.connect(func() -> void:
			if engagement == null:_toast(txt("request_failed"));return
			upd.disabled = true
			if not await engagement.update_download(game_id): upd.disabled = false; return
			_adopt_downloads(engagement.store.downloads); _toast(txt("dl_done_toast")))
		row.add_child(upd)
		var del := Widgets.secondary_button(txt("dl_delete"), theme_name())
		del.disabled=_delete_pending
		del.pressed.connect(func() -> void:_delete_id=game_id;rebuild())
		row.add_child(del)
		card.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				game_opened.emit(game))
		list.add_child(card)
	content.add_child(list)
