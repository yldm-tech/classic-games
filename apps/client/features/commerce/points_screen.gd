class_name PointsScreen
extends ScreenBase

## 创作点明细:余额(接 AppState.points)+ 权威收支流水。

## /points 注入的创作点数据(为空则回退 i18n 种子)。
var _data: Dictionary = {}
var commerce:CommerceCoordinator
func _init(p_state:Node,p_commerce:CommerceCoordinator=null)->void:commerce=p_commerce;super(p_state)

## 首次展示拉创作点流水。
func refresh() -> void:
	if commerce!=null and await commerce.load_points():
		_data = commerce.store.points
		state.add_points(int(_data.get("balance", state.points)) - state.points)
		rebuild()

## 流水归一为 [{label,amount,when}](后端 ledger 对象 或 种子 [label,amount,when])。
func _ledger() -> Array:
	if not _data.is_empty() and _data.get("ledger") is Array:
		var out: Array = []
		for e: Dictionary in _data["ledger"]:
			out.append({"label": str(e.get("label", "")), "amount": int(e.get("amount", 0)), "when": str(e.get("when", ""))})
		return out
	return []

func _build() -> void:
	var card := Widgets.card(theme_name(), &"tint_ember")
	var col := Widgets.vbox(Tokens.SPACE_1)
	card.add_child(col)
	col.add_child(Widgets.caption(txt("points_balance"), theme_name()))
	var bal := Widgets.big_number(str(state.points), theme_name(), Tokens.FONT_DISPLAY)
	bal.name = "Balance"
	col.add_child(bal)
	content.add_child(card)

	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "LedgerList"
	for item: Dictionary in _ledger():
		var row_card := Widgets.card(theme_name())
		var row := Widgets.hbox(Tokens.SPACE_3)
		row_card.add_child(row)
		var label := Widgets.body(item["label"], theme_name())
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var n := int(item["amount"])
		var amount := Label.new()
		amount.text = ("+%d" % n) if n > 0 else str(n)
		amount.add_theme_font_size_override("font_size", Tokens.FONT_H5)
		amount.add_theme_color_override("font_color",
			Tokens.color(&"status_success" if n > 0 else &"status_danger", theme_name()))
		row.add_child(amount)
		row.add_child(Widgets.caption(item["when"], theme_name()))
		list.add_child(row_card)
	content.add_child(list)
