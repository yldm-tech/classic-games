class_name PlatformBridge
extends RefCounted

## 五端原生能力的唯一入口。优先调用 ForgePlayPlatform 原生单例；Web 使用浏览器 API；
## 桌面使用系统 URL handler。返回 false 表示平台未接受动作，UI 不得伪报成功。

const NATIVE_SINGLETON := "ForgePlayPlatform"

static func capabilities() -> Dictionary:
	var native := _native()
	return {
		"share": native != null or OS.has_feature("web") or OS.get_name() in ["macOS", "Windows", "Linux"],
		"qr_scan": native != null and native.has_method("scan_qr"),
		"oauth": native != null and native.has_method("oauth_login"),
		"pick_file": native != null and native.has_method("pick_file"),
		"payment": payment_allowed() and native != null and native.has_method("start_payment"),
	}

static func payment_allowed(platform_name:String=OS.get_name())->bool:
	# 产品边界：手机端不提供充值、订阅或任何原生支付入口。
	return platform_name not in ["Android","iOS"]

static func share(channel: String, url: String, title: String) -> bool:
	var native := _native()
	if native != null and native.has_method("share"):
		return bool(native.call("share", {"channel": channel, "url": url, "title": title}))
	if OS.has_feature("web"):
		return _share_web(url, title)
	if channel == "copy":
		DisplayServer.clipboard_set(url)
		return true
	var target := build_share_url(channel, url, title)
	if target == "":
		# 桌面没有对应客户端协议时，复制链接是可验证的降级行为。
		DisplayServer.clipboard_set(url)
		return true
	return OS.shell_open(target) == OK

static func build_share_url(channel: String, url: String, title: String) -> String:
	var encoded_url := url.uri_encode()
	var encoded_title := title.uri_encode()
	match channel:
		"x":
			return "https://twitter.com/intent/tweet?text=%s&url=%s" % [encoded_title, encoded_url]
		"email", "messages":
			return "mailto:?subject=%s&body=%s" % [encoded_title, encoded_url]
		"line":
			return "https://social-plugins.line.me/lineit/share?url=%s" % encoded_url
		_:
			return ""

static func open_url(url:String)->bool:
	# 只允许明确的外部 URI scheme，避免把服务端/本地化内容意外变成任意命令或文件打开。
	if not (url.begins_with("https://") or url.begins_with("mailto:")): return false
	return OS.shell_open(url)==OK

static func scan_qr() -> String:
	var native := _native()
	if native == null or not native.has_method("scan_qr"):
		return ""
	var result: Variant = native.call("scan_qr")
	if typeof(result) == TYPE_STRING: return str(result).strip_edges()
	if typeof(result) == TYPE_DICTIONARY: return str((result as Dictionary).get("content", "")).strip_edges()
	return ""

static func oauth_login(provider: String) -> String:
	var native := _native()
	if native == null or not native.has_method("oauth_login"):
		return ""
	var result: Variant = native.call("oauth_login", provider)
	if typeof(result)==TYPE_STRING:return str(result)
	if typeof(result)==TYPE_DICTIONARY:return str((result as Dictionary).get("code",""))
	return ""

## 返回渠道侧订单/交易标识；空串表示未受理。原生插件不得只返回 true，
## 因为没有可关联标识就无法向服务端查询或验证最终支付结果。
static func start_payment(product_id:String, order_id:String)->String:
	if not payment_allowed():return ""
	var native:=_native()
	if native == null or not native.has_method("start_payment"): return ""
	var result: Variant = native.call("start_payment", {"product_id": product_id, "order_id": order_id})
	if typeof(result) == TYPE_DICTIONARY:
		return str((result as Dictionary).get("transaction_id", ""))
	if typeof(result) == TYPE_STRING:
		return str(result)
	return ""

static func cache_size_bytes() -> int:
	return _dir_size(OS.get_user_data_dir().path_join("cache"))

static func clear_cache() -> bool:
	var path := OS.get_user_data_dir().path_join("cache")
	if DirAccess.dir_exists_absolute(path) and not _remove_tree(path): return false
	return DirAccess.make_dir_recursive_absolute(path) == OK

static func _dir_size(path: String) -> int:
	var dir := DirAccess.open(path); if dir == null: return 0
	var total := 0; dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var child := path.path_join(name)
		total += _dir_size(child) if dir.current_is_dir() else FileAccess.get_size(child)
		name = dir.get_next()
	dir.list_dir_end(); return total

static func _remove_tree(path: String) -> bool:
	var dir := DirAccess.open(path); if dir == null: return true
	dir.list_dir_begin(); var name := dir.get_next()
	while name != "":
		var child := path.path_join(name)
		if dir.current_is_dir():
			if not _remove_tree(child): dir.list_dir_end(); return false
		elif DirAccess.remove_absolute(child) != OK: dir.list_dir_end(); return false
		name = dir.get_next()
	dir.list_dir_end(); return DirAccess.remove_absolute(path) == OK

static func _share_web(url: String, title: String) -> bool:
	if not ClassDB.class_exists("JavaScriptBridge"):
		return false
	# navigator.share 必须在点击事件的同步调用栈内触发；不等待 Promise。
	var script := "(() => { const d={title:%s,url:%s}; if(navigator.share){navigator.share(d).catch(()=>{});return true;} navigator.clipboard?.writeText(d.url);return true; })()" % [JSON.stringify(title), JSON.stringify(url)]
	return bool(JavaScriptBridge.eval(script, true))

static func _native() -> Object:
	if Engine.has_singleton(NATIVE_SINGLETON):
		return Engine.get_singleton(NATIVE_SINGLETON)
	return null
