class_name AvatarScreen
extends ScreenBase

## 形象装扮:头像框选色 + 角色/座驾/特效三类装备(未拥有锁态 → 商城)。

var frame_tone := "ember"
var equipped: Dictionary = {}
## /avatar 注入的装扮目录(为空则回退 i18n 种子)。
var _data: Dictionary = {}
var commerce:CommerceCoordinator
var profile_updater:=Callable()
func _init(p_state:Node,p_commerce:CommerceCoordinator=null,p_profile_updater:=Callable())->void:
	commerce=p_commerce;profile_updater=p_profile_updater;super(p_state)

## 首次展示拉形象装扮目录(角色/座驾/特效)。
func refresh() -> void:
	if commerce!=null and await commerce.load_avatar(state.locale):
		# 种子→后端目录切换时 id 体系变(种子 c0/c0_i0 → 后端真实 id),
		# 清掉按种子 id 记的旧装备态,避免残留死键(equipped 本就不持久化,清空最干净)。
		equipped.clear()
		_data = {"items":commerce.store.avatar_items}
		for c:Dictionary in _data.get("items",[]):
			for it:Dictionary in c.get("items",[]):
				if it.get("equipped",false): equipped[str(c.get("id",""))]=str(it.get("id",""))
		rebuild()

## 装扮目录归一为 [{name, items:[{name,tone,owned}]}]。
## 后端 items=[{id,name,items:[{id,name,tone,owned}]}];种子 av_cats=[[name, [[name,tone,owned]...]]...]。
func _categories() -> Array:
	# 每个分类/项目都带「与语言无关的稳定 id」(后端用服务端 id,种子用下标),
	# equipped 按 id 记,切语言/服务端改本地化名时装备态不丢。
	if not _data.is_empty() and _data.get("items") is Array:
		var out: Array = []
		var cats: Array = _data["items"]
		for ci in cats.size():
			var c: Dictionary = cats[ci]
			var its: Array = []
			if c.get("items") is Array:
				var citems: Array = c["items"]
				for ii in citems.size():
					var it: Dictionary = citems[ii]
					its.append({"id": str(it.get("id", "i%d" % ii)), "name": str(it.get("name", "")), "tone": str(it.get("tone", "")), "owned": bool(it.get("owned", false))})
			out.append({"id": str(c.get("id", "c%d" % ci)), "name": str(c.get("name", "")), "items": its})
		return out
	return []

func _build() -> void:
	# 预览 + 头像框
	var preview := Widgets.card(theme_name())
	preview.name = "PreviewCard"
	var pc := Widgets.vbox(Tokens.SPACE_2)
	preview.add_child(pc)
	var avatar := Widgets.big_number(String(state.profile.get("name", "@guest")).trim_prefix("@").left(1).to_upper(), theme_name(), Tokens.FONT_DISPLAY)
	avatar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar.add_theme_color_override("font_color", GameCard.TONES.get(frame_tone, Color.WHITE).lightened(0.6))
	pc.add_child(avatar)
	pc.add_child(Widgets.caption(txt("av_frame"), theme_name()))
	var tones := Widgets.hbox(Tokens.SPACE_2)
	tones.name = "FrameRow"
	for tone: String in GameCard.TONES:
		var b := Button.new()
		b.custom_minimum_size = Vector2(36, 36)
		var sb := StyleBoxFlat.new()
		sb.bg_color = GameCard.TONES[tone]
		sb.set_corner_radius_all(Tokens.RADIUS_PILL)
		if tone == frame_tone:
			sb.border_color = Tokens.color(&"accent_primary", theme_name())
			sb.set_border_width_all(2)
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, sb)
		var t := tone
		b.pressed.connect(func() -> void:
			frame_tone = t
			rebuild())
		tones.add_child(b)
	pc.add_child(tones)
	content.add_child(preview)

	# 三类装备
	var categories := _categories()
	if categories.is_empty():
		var empty := empty_note(txt("his_empty"))
		empty.name = "CatalogEmpty"
		content.add_child(empty)
	for cat: Dictionary in categories:
		content.add_child(Widgets.caption(cat["name"], theme_name()))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", Tokens.SPACE_2)
		grid.add_theme_constant_override("v_separation", Tokens.SPACE_2)
		for item: Dictionary in cat["items"]:
			var item_name: String = item["name"]
			var item_id: String = str(item["id"])
			var has_it: bool = item["owned"]
			var is_on: bool = equipped.get(cat["id"], "") == item_id
			var card := Widgets.card(theme_name(), &"tint_ember" if is_on else &"surface_card")
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var cc := Widgets.vbox(Tokens.SPACE_1)
			card.add_child(cc)
			var swatch := ColorRect.new()
			swatch.color = GameCard.TONES.get(item["tone"], Color.GRAY)
			swatch.custom_minimum_size = Vector2(0, 36)
			cc.add_child(swatch)
			cc.add_child(Widgets.body(item_name, theme_name()))
			cc.add_child(Widgets.caption(txt("av_equipped") if is_on else (txt("av_owned") if has_it else "🔒"), theme_name()))
			var cat_id: String = str(cat["id"])
			card.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					if not has_it:
						_toast(txt("av_locked_toast"))
						return
					if commerce==null:_toast(txt("request_failed"));return
					if not await commerce.equip_avatar(cat_id,item_id):return
					equipped[cat_id] = item_id
					rebuild())
			grid.add_child(card)
		content.add_child(grid)

	var save := Widgets.primary_button(txt("av_save"), theme_name())
	save.name = "SaveButton"
	save.pressed.connect(func() -> void:
		if not profile_updater.is_valid():_toast(txt("request_failed"));return
		var payload:Dictionary=state.profile.duplicate(true);payload["tone"]=frame_tone
		var result=await profile_updater.call(payload)
		if result.ok and result.data is Dictionary:state.save_profile(result.data);_toast(txt("av_saved_toast"))
		else:_toast(txt("request_failed")))
	content.add_child(save)
