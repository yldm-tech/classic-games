class_name AchievementsScreen
extends ScreenBase

## 成就:列表(进度条 + 达成可领取,奖励入创作点)。

var claimed: Dictionary = {}
## /achievements 注入的成就列表(为空则回退 i18n 种子)。
var _data: Dictionary = {}
var commerce:CommerceCoordinator
func _init(p_state:Node,p_commerce:CommerceCoordinator=null)->void:commerce=p_commerce;super(p_state)

## 首次展示拉成就列表。
func refresh() -> void:
	if commerce!=null and await commerce.load_achievements(state.locale):
		_data = {"items":commerce.store.achievements}
		for a:Dictionary in _data.get("items",[]):
			if a.get("claimed",false): claimed[str(a.get("id",""))]=true
		rebuild()

## 成就归一为 [{name,desc,progress,target,reward}](后端 items 对象 或 种子 [name,desc,progress,target,reward])。
func _achievements() -> Array:
	if not _data.is_empty() and _data.get("items") is Array:
		var out: Array = []
		for a: Dictionary in _data["items"]:
			out.append({"id":str(a.get("id","")),"name": str(a.get("name", "")), "desc": str(a.get("desc", "")),
				"progress": int(a.get("progress", 0)), "target": int(a.get("target", 0)), "reward": int(a.get("reward", 0))})
		return out
	return []

func _build() -> void:
	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "AchList"
	var items: Array = _achievements()
	if items.is_empty():
		list.add_child(empty_note(txt("his_empty")))
	var i18n := preload("res://i18n/i18n.gd")
	for i in items.size():
		var a: Dictionary = items[i]
		var done: bool = a["progress"] >= a["target"]
		var claim_key:Variant=a.get("id",i)
		var card := Widgets.card(theme_name(), &"tint_volt" if done and not claimed.has(claim_key) else &"surface_card")
		var row := Widgets.hbox(Tokens.SPACE_3)
		card.add_child(row)
		var col := Widgets.vbox(Tokens.SPACE_1)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(Widgets.body(a["name"], theme_name()))
		col.add_child(Widgets.caption(a["desc"], theme_name()))
		var bar := ProgressBar.new()
		bar.max_value = a["target"]
		bar.value = a["progress"]
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 4)
		col.add_child(bar)
		col.add_child(Widgets.caption("%s %s/%s" % [txt("ach_progress"),
			i18n.format_number(int(a["progress"]), state.locale), i18n.format_number(int(a["target"]), state.locale)], theme_name()))
		row.add_child(col)
		if done:
			var idx: Variant = claim_key
			var reward := int(a["reward"])
			var claim := Widgets.secondary_button(txt("ach_claimed") if claimed.has(claim_key) else "%s +%d" % [txt("ach_claim"), reward], theme_name())
			claim.disabled = claimed.has(claim_key)
			claim.pressed.connect(func() -> void:
				if commerce==null:_toast(txt("request_failed"));return
				if not await commerce.claim_achievement(str(a.get("id",""))):return
				state.add_points(commerce.store.balance-state.points)
				claimed[idx] = true
				_toast(txt_fmt("ach_toast_fmt", [int(commerce.store.last_transaction.get("reward", reward))]))
				rebuild())
			row.add_child(claim)
		list.add_child(card)
	content.add_child(list)
