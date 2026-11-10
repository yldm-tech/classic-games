class_name BlocklistScreen
extends ScreenBase

## 黑名单:列表 + 解除(清空显示空态)。
## 列表来自 /blocks;拿不到则回退种子 blocked。entries 统一存 [user_id, blocked_at] 对。

var entries: Array = []
var _seeded := false
var operations:OperationsCoordinator
func _init(p_state:Node,p_operations:OperationsCoordinator=null)->void:operations=p_operations;super(p_state)

func refresh() -> void:
	if operations == null:
		return
	if await operations.load_blocks():
		var items: Array = operations.store.blocks
		entries = []
		for it: Dictionary in items:
			entries.append([it.get("user_id", ""), it.get("blocked_at", "")])
		_seeded = true  # 服务端已给数据,不再回退种子(含空列表→空态)
		rebuild()

func invalidate_session()->void:
	entries=[];_seeded=false;super.invalidate_session()

func _build() -> void:
	if entries.is_empty():
		content.add_child(empty_note(txt("blk_empty")))
		return
	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "BlockList"
	for i in entries.size():
		var card := Widgets.card(theme_name())
		var row := Widgets.hbox(Tokens.SPACE_3)
		card.add_child(row)
		var col := Widgets.vbox(Tokens.SPACE_1)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(Widgets.body(entries[i][0], theme_name()))
		# 旧版本服务端或本地种子可能没有 blocked_at，兼容时不渲染空行。
		if str(entries[i][1]) != "":
			col.add_child(Widgets.caption(entries[i][1], theme_name()))
		row.add_child(col)
		var remove := Widgets.secondary_button(txt("blk_remove"), theme_name())
		var uid:=str(entries[i][0])
		remove.pressed.connect(func() -> void:
			if operations==null or uid=="":_toast(txt("request_failed"));return
			if not await operations.unblock_user(uid):_toast(txt("request_failed"));return
			entries=entries.filter(func(entry):return str(entry[0])!=uid)
			_toast(txt("blk_removed_toast"))
			rebuild())
		row.add_child(remove)
		list.add_child(card)
	content.add_child(list)
