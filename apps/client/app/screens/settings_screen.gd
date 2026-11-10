class_name SettingsScreen
extends ScreenBase

const PlatformBridge := preload("res://platform/platform.gd")
const AppVersionScript := preload("res://app/app_version.gd")

## Application-owned 设置页。「语言/外观」是真开关、即点即换；
## 账号安全/通知/隐私/青少年/黑名单/关于各有真实落点;清缓存即时反馈;退出登录走 AppState。

signal logged_out
signal account_requested
signal notif_requested
signal privacy_requested
signal teen_requested
signal blocklist_requested
signal about_requested
signal help_requested
signal edit_profile_requested
signal analytics_requested

func _build() -> void:
	content.add_child(Widgets.heading(txt("set_title"), 2, theme_name()))

	content.add_child(Widgets.caption(txt("settings_account"), theme_name()))
	# 账号行(整行可点进编辑资料,微信惯例)
	var me := nav_row(state.profile.get("name", ""), txt("edit_profile"), func() -> void: edit_profile_requested.emit())
	me.name = "MeRow"
	content.add_child(me)
	var acc := nav_row(txt("acc_title"), "", func() -> void: account_requested.emit())
	acc.name = "AccountRow"
	content.add_child(acc)
	var notif := nav_row(txt("np_title"), "", func() -> void: notif_requested.emit())
	notif.name = "NotifRow"
	content.add_child(notif)
	var privacy := nav_row(txt("pv_title"), "", func() -> void: privacy_requested.emit())
	privacy.name = "PrivacyRow"
	content.add_child(privacy)
	var teen := nav_row(txt("teen_title"), "", func() -> void: teen_requested.emit())
	teen.name = "TeenRow"
	content.add_child(teen)
	var blk := nav_row(txt("blk_title"), "", func() -> void: blocklist_requested.emit())
	blk.name = "BlocklistRow"
	content.add_child(blk)

	content.add_child(Widgets.caption(txt("settings_prefs"), theme_name()))

	# 语言:中文 / EN / 日本語 分段开关
	content.add_child(Widgets.caption(txt("set_lang"), theme_name()))
	var lang_seg := Widgets.segment(txt("lang_names"), Strings.LOCALES.find(state.locale), theme_name(), func(i: int) -> void:
		state.set_locale(Strings.LOCALES[i]))
	lang_seg.name = "LangSeg"
	content.add_child(lang_seg)

	# 外观:深色 / 浅色 分段开关
	content.add_child(Widgets.caption(txt("set_theme"), theme_name()))
	var theme_idx := 0 if state.theme == Tokens.THEME_DARK else 1
	var theme_seg := Widgets.segment(txt("theme_names"), theme_idx, theme_name(), func(i: int) -> void:
		state.set_theme(Tokens.THEME_DARK if i == 0 else Tokens.THEME_LIGHT))
	theme_seg.name = "ThemeSeg"
	content.add_child(theme_seg)

	content.add_child(Widgets.caption(txt("settings_support"), theme_name()))

	var bytes := PlatformBridge.cache_size_bytes()
	var cache_label := "%d MB" % ceili(bytes / 1048576.0) if bytes > 0 else "0 MB"
	var cache := nav_row(txt("set_cache"), cache_label, func() -> void:
		if PlatformBridge.clear_cache():
			_toast(txt_fmt("set_cache_toast_fmt", [cache_label])); rebuild())
	cache.name = "CacheRow"
	content.add_child(cache)
	var analytics := nav_row(txt("analytics_title"), "", func() -> void: analytics_requested.emit())
	analytics.name = "AnalyticsRow"
	content.add_child(analytics)
	var help := nav_row(txt("help_title"), "", func() -> void: help_requested.emit())
	help.name = "HelpRow"
	content.add_child(help)
	var about := nav_row(txt("set_about"), AppVersionScript.display(state.locale), func() -> void: about_requested.emit())
	about.name = "AboutRow"
	content.add_child(about)

	# 退出登录
	var logout := Widgets.danger_button(txt("logout"), theme_name())
	logout.name = "LogoutButton"
	logout.pressed.connect(func() -> void:
		state.logout()
		logged_out.emit())
	content.add_child(logout)
