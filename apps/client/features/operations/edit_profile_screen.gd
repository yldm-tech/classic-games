class_name EditProfileScreen
extends ScreenBase

## 编辑资料只有服务端确认后才写入 AppState，避免网络失败时制造“已保存”假象。

var _name: LineEdit
var _bio: TextEdit
var _gender := 2
var _tone := "ember"
var _region := ""
var _name_text := ""  # 编辑中的名字,跨 in-screen rebuild(改色/性别)保留,避免被清空
var _bio_text := ""   # 编辑中的简介,同上
var _loaded := false
var operations:OperationsCoordinator
func _init(p_state:Node,p_operations:OperationsCoordinator=null)->void:operations=p_operations;super(p_state)

## 每次进入(含从头像页导航回来)从最新 profile 重载:避免用陈旧的内存 tone/gender 覆盖头像页的改动;
## 名字/简介也复位为已保存值。screen 实例常驻复用,故走 _enter_tree 而非一次性的 refresh()。
func _enter_tree() -> void:
	_reload_from_profile()
	rebuild()

func invalidate_session()->void:
	_loaded=false;_name_text="";_bio_text="";_gender=2;_tone="ember";_region="";super.invalidate_session()

func _reload_from_profile() -> void:
	_gender = int(state.profile.get("gender", 2))
	_tone = str(state.profile.get("tone", "ember"))
	_name_text = str(state.profile.get("name", ""))
	_bio_text = str(state.profile.get("bio", ""))
	_region = str(state.profile.get("region", ""))
	_loaded = true

## 改色/性别触发的 in-screen rebuild 前,把当前输入存进内存,rebuild 后回填,不丢未保存内容。
func _stash_inputs() -> void:
	if _name != null and is_instance_valid(_name):
		_name_text = _name.text
	if _bio != null and is_instance_valid(_bio):
		_bio_text = _bio.text

func _build() -> void:
	if not _loaded:
		_reload_from_profile()

	content.add_child(Widgets.caption(txt("ep_avatar"), theme_name()))
	var tones := Widgets.hbox(Tokens.SPACE_2)
	tones.name = "ToneRow"
	for tone: String in GameCard.TONES:
		var b := Button.new()
		b.custom_minimum_size = Vector2(40, 40)
		var sb := StyleBoxFlat.new()
		sb.bg_color = GameCard.TONES[tone]
		sb.set_corner_radius_all(Tokens.RADIUS_PILL)
		if tone == _tone:
			sb.border_color = Tokens.color(&"accent_primary", theme_name())
			sb.set_border_width_all(2)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		var t := tone
		b.pressed.connect(func() -> void:
			_stash_inputs()
			_tone = t
			rebuild())
		tones.add_child(b)
	content.add_child(tones)

	content.add_child(Widgets.caption(txt("ep_name"), theme_name()))
	_name = LineEdit.new()
	_name.name = "NameEdit"
	_name.text = _name_text  # 内存中的编辑值(改色/性别 rebuild 时保留),非每次都读 profile
	content.add_child(_name)

	content.add_child(Widgets.caption(txt("ep_bio"), theme_name()))
	_bio = TextEdit.new()
	_bio.name = "BioEdit"
	_bio.text = _bio_text
	_bio.placeholder_text = txt("ep_bio_ph")
	_bio.custom_minimum_size = Vector2(0, 72)
	content.add_child(_bio)

	content.add_child(Widgets.caption(txt("ep_gender"), theme_name()))
	var seg := Widgets.segment(txt("genders"), _gender, theme_name(), func(i: int) -> void:
		_stash_inputs()
		_gender = i
		rebuild())
	seg.name = "GenderSeg"
	content.add_child(seg)

	content.add_child(Widgets.caption(txt("ep_region"),theme_name()))
	var region:=OptionButton.new();region.name="RegionSelect"
	var regions:Array=["Shanghai","Tokyo","Singapore","London","New York"]
	for item:String in regions:region.add_item(item)
	var selected:=regions.find(_region);region.select(selected if selected>=0 else 0);_region=region.get_item_text(region.selected)
	region.item_selected.connect(func(i:int)->void:_region=region.get_item_text(i))
	content.add_child(region)

	var save := Widgets.primary_button(txt("ep_save"), theme_name())
	save.name = "SaveButton"
	save.pressed.connect(func() -> void:
		var payload := {
			"name": _name.text.strip_edges(), "bio": _bio.text.strip_edges(),
			"gender": _gender, "tone": _tone, "region": _region,
		}
		if operations == null:
			_toast(txt("request_failed"))
			return
		save.disabled = true
		var saved:=await operations.update_profile(payload)
		save.disabled = false
		if saved:
			state.save_profile(operations.store.profile)
			_toast(txt("toast_saved"))
		else:
			_toast(txt("request_failed")))
	content.add_child(save)
