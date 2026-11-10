extends Node

## 全局唯一数据源(autoload 单例 AppState):会话、当前用户、未读数、主题、语言、创作点。
## 信号驱动 UI 更新,避免散落状态不一致(见 docs/16-client-architecture.md)。
## UI 只读这里 + 监听信号;写入集中在此,不在各 screen 里散开。
## profile/onboarded/token 持久化到 user://(对照原型 localStorage 行为)。

signal session_changed
signal theme_changed(theme_name: String)
signal locale_changed(locale: String)
signal unread_changed(count: int)
signal points_changed(balance: int)

const Tokens := preload("res://shell/design_system/theme/tokens.gd")
const Strings := preload("res://i18n/strings.gd")

## 每账号状态的默认值(声明与 logout 复位共用,避免漂移)。
const DEFAULT_POINTS := 0
const DEFAULT_PROFILE := {"name": "@guest", "bio": "", "gender": 2, "region": "", "tone": "ember"}

## 持久化路径;测试注入临时路径避免污染真实存档。
var save_path := "user://classic-games.cfg"

var authed := false
var token := ""
var onboarded := false
var profile := DEFAULT_PROFILE.duplicate(true)
var theme := Tokens.THEME_DARK
var locale := Strings.DEFAULT_LOCALE
var points := DEFAULT_POINTS  # 创作点余额(签到/任务/商城/成就共用)
var member := false      # Classic Games+ 会员
var search_recents: Array = []
var teen_enabled := false
var teen_day := ""
var teen_play_secs := 0

# 动态未读:点开一条消一条(read 集合按通知下标)。总数随实际通知条数走,
# 未拿到权威通知前为 0；MessagesScreen 拉到 /activity 后校正。
var activity_total := 0
var _read: Dictionary = {}

## 通知总数随实际数据校正(MessagesScreen 加载 /activity 后调用)。
func set_activity_total(n: int) -> void:
	if n >= 0 and n != activity_total:
		activity_total = n
		unread_changed.emit(unread())

func login(p_token: String = "", user: Dictionary = {}) -> void:
	authed = true
	token = p_token
	if user.has("id"):
		profile["id"] = str(user["id"])
	if user.has("nickname") and user["nickname"] != "":
		profile["name"] = user["nickname"]
	persist()
	session_changed.emit()

func logout() -> void:
	if authed:
		authed = false
		token = ""
		# 清掉上一账号的会话内状态,避免泄露到下一账号(含落盘):
		# 未读已读集、通知总数、会员态,以及创作点余额与资料(昵称/简介/性别/地区/色调)。
		# 登录只会从服务端覆盖昵称,其余字段不复位就会串号;余额更是能在商城里花掉别人的。
		_read.clear()
		activity_total = 0
		member = false
		points = DEFAULT_POINTS
		profile = DEFAULT_PROFILE.duplicate(true)
		search_recents.clear()
		teen_enabled = false
		teen_day = ""
		teen_play_secs = 0
		persist()
		points_changed.emit(points)
		unread_changed.emit(unread())
		session_changed.emit()

func finish_onboarding() -> void:
	onboarded = true
	persist()

func save_profile(p: Dictionary) -> void:
	profile.merge(p, true)
	persist()
	session_changed.emit()

## 设置主题(深/浅)。设置页「外观」必须是真开关(原型教训,docs/19)。
func set_theme(value: String) -> void:
	if value != theme and (value == Tokens.THEME_DARK or value == Tokens.THEME_LIGHT):
		theme = value
		persist()
		theme_changed.emit(theme)

## 运行时切换语言,UI 监听信号即时重渲(docs/18-i18n)。
func set_locale(value: String) -> void:
	if value != locale and value in Strings.LOCALES:
		locale = value
		persist()
		locale_changed.emit(locale)

## 记住最近搜索(去重、最多 8 条,落盘)。
func remember_search(query: String) -> void:
	query = query.strip_edges()
	if query == "":
		return
	search_recents.erase(query)
	search_recents.push_front(query)
	if search_recents.size() > 8:
		search_recents = search_recents.slice(0, 8)
	persist()

func clear_search_recents() -> void:
	if search_recents.is_empty():
		return
	search_recents.clear()
	persist()

## 创作点增减(负数为消费;余额不会扣成负)。
func add_points(delta: int) -> void:
	points = maxi(0, points + delta)
	points_changed.emit(points)

## 把第 index 条通知标为已读(幂等)。
func mark_read(index: int) -> void:
	if index >= 0 and index < activity_total and not _read.has(index):
		_read[index] = true
		unread_changed.emit(unread())

func is_read(index: int) -> bool:
	return _read.has(index)

func unread() -> int:
	return maxi(0, activity_total - _read.size())

func set_teen_enabled(value: bool) -> void:
	if teen_enabled == value:
		return
	teen_enabled = value
	persist()

func teen_play_seconds_today() -> int:
	_roll_teen_day()
	return teen_play_secs

func add_teen_play_seconds(seconds: int) -> void:
	if seconds <= 0:
		return
	_roll_teen_day()
	teen_play_secs += seconds
	persist()

func _roll_teen_day() -> void:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	var today := "%04d-%02d-%02d" % [int(dt.get("year", 1970)), int(dt.get("month", 1)), int(dt.get("day", 1))]
	if teen_day == today:
		return
	teen_day = today
	teen_play_secs = 0

# ── 持久化(profile / onboarded / token,对照原型 localStorage) ──
func persist() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("session", "authed", authed)
	cfg.set_value("session", "token", token)
	cfg.set_value("session", "onboarded", onboarded)
	cfg.set_value("user", "profile", profile)
	cfg.set_value("user", "points", points)
	cfg.set_value("user", "member", member)
	cfg.set_value("prefs", "theme", theme)
	cfg.set_value("prefs", "locale", locale)
	cfg.set_value("prefs", "search_recents", search_recents)
	cfg.set_value("prefs", "teen_enabled", teen_enabled)
	cfg.set_value("prefs", "teen_day", teen_day)
	cfg.set_value("prefs", "teen_play_secs", teen_play_secs)
	cfg.save(save_path)

func restore() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	authed = cfg.get_value("session", "authed", false)
	token = cfg.get_value("session", "token", "")
	onboarded = cfg.get_value("session", "onboarded", false)
	var saved: Dictionary = cfg.get_value("user", "profile", {})
	profile.merge(saved, true)
	points = cfg.get_value("user", "points", points)
	member = cfg.get_value("user", "member", member)
	var saved_theme: String = str(cfg.get_value("prefs", "theme", theme))
	if saved_theme == Tokens.THEME_DARK or saved_theme == Tokens.THEME_LIGHT:
		theme = saved_theme
	var saved_locale: String = str(cfg.get_value("prefs", "locale", locale))
	if saved_locale in Strings.LOCALES:
		locale = saved_locale
	var recents: Variant = cfg.get_value("prefs", "search_recents", [])
	search_recents = recents.duplicate() if recents is Array else []
	teen_enabled = bool(cfg.get_value("prefs", "teen_enabled", false))
	teen_day = str(cfg.get_value("prefs", "teen_day", ""))
	teen_play_secs = int(cfg.get_value("prefs", "teen_play_secs", 0))
	_roll_teen_day()
