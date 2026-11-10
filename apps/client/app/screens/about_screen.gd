class_name AboutScreen
extends ScreenBase

## Application-owned 关于页：品牌、版本与外部政策链接。

const PlatformBridge:=preload("res://platform/platform.gd")
const AppVersionScript:=preload("res://app/app_version.gd")
var url_opener:Callable=PlatformBridge.open_url
var operations:OperationsCoordinator
var _meta:Dictionary={}

func _init(p_state:Node,p_operations:OperationsCoordinator=null)->void:
	operations=p_operations
	super(p_state)

func refresh()->void:
	if operations==null:
		return
	if await operations.load_meta():
		_meta=operations.store.meta.duplicate(true)
	rebuild()

func _build() -> void:
	var logo := Widgets.heading("Classic Games", 1, theme_name())
	logo.add_theme_color_override("font_color", Tokens.color(&"accent_primary", theme_name()))
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(logo)
	var tag := Widgets.body(txt("about_tagline"), theme_name(), &"text_secondary")
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(tag)
	var build := Widgets.caption(AppVersionScript.build_line(), theme_name())
	build.name = "BuildLabel"
	build.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(build)

	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "LinkList"
	var labels:Array=txt("about_links")
	for i in labels.size():
		var link:String=labels[i]
		var l := link
		var url:String=ExternalLinks.ABOUT[i]
		var row:=nav_row(l, "", func() -> void:
			if not url_opener.is_valid() or not bool(url_opener.call(url)): _toast(txt("request_failed")))
		row.name="AboutLink%d"%i
		list.add_child(row)
	content.add_child(list)
	_build_capabilities()

	var copyright := Widgets.caption(txt("about_copyright"), theme_name())
	copyright.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(copyright)

func _build_capabilities() -> void:
	if _meta.is_empty():
		return
	content.add_child(Widgets.caption(txt("cap_title"), theme_name()))
	var list := Widgets.vbox(Tokens.SPACE_2)
	list.name = "CapabilityList"
	var ai: Dictionary = _meta.get("ai", {}) if _meta.get("ai", {}) is Dictionary else {}
	list.add_child(Widgets.body(txt("cap_ai_live") if str(ai.get("mode", "stub")) == "live" else txt("cap_ai_stub"), theme_name()))
	list.add_child(Widgets.body(txt("cap_sms_on") if bool(_meta.get("sms", false)) else txt("cap_sms_off"), theme_name()))
	var providers: Array = _meta.get("oauth_providers", []) if _meta.get("oauth_providers", []) is Array else []
	if providers.is_empty():
		list.add_child(Widgets.body(txt("cap_oauth_none"), theme_name()))
	else:
		list.add_child(Widgets.body(txt_fmt("cap_oauth_fmt", [", ".join(providers)]), theme_name()))
	list.add_child(Widgets.body(txt("cap_pay_on") if bool(_meta.get("payments", false)) else txt("cap_pay_off"), theme_name()))
	list.add_child(Widgets.body(txt("cap_admin_on") if bool(_meta.get("admin_configured", false)) else txt("cap_admin_off"), theme_name()))
	content.add_child(list)
