extends SceneTree

const AppRootScript := preload("res://app/app_root.gd")
const ScreenRegistryScript := preload("res://app/screen_registry.gd")
const ChromeControllerScript := preload("res://app/chrome/chrome_controller.gd")
const AppStateScript := preload("res://shell/state/app_state.gd")
const ApiResultScript := preload("res://core/http/api_result.gd")

class Gate:
	extends RefCounted
	signal released

class GatedEngagementGateway:
	extends RefCounted
	var history_gate := Gate.new()
	var cancelled:=false
	func history(_lang:String):
		await history_gate.released
		if cancelled:return ApiResultScript.offline("cancelled")
		return ApiResultScript.success(200,{"groups":[{"items":[{"game":{"id":"old-account"}}]}]})
	func cancel_all()->void: cancelled=true;history_gate.released.emit()

class LogoutGateway:
	extends RefCounted
	func logout(): return ApiResultScript.success(204,null)

var _passed := 0
var _failed := 0

func _initialize() -> void:
	await _test_app_root_owns_composition()
	await _test_logout_discards_stale_remote_refresh()
	_test_screen_registry_owns_creation_and_lookup()
	_test_chrome_controller_owns_breakpoints()
	_test_teen_guard_blocks_curfew_and_daily_limit()
	print("app_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

func _test_app_root_owns_composition() -> void:
	var state = AppStateScript.new()
	state.save_path = "user://app-root-test.cfg"
	state.authed = true
	state.token = "restored-token"
	state.onboarded = true
	var application = AppRootScript.new(state, "https://api.example.test",{"identity":LogoutGateway.new()})
	_check("app root is the single navigation and chrome root",application.router!=null and application._content!=null)
	_check("app root assembles identity slice", application.identity != null and application.identity_store != null)
	_check("app root assembles catalog slice", application.catalog != null and application.catalog_store != null)
	_check("app root assembles creation slice", application.creation != null and application.creation_store != null
		and application.creation_session != null and application.forge.coordinator == application.creation)
	_check("app root assembles community slice", application.community != null and application.community_store != null
		and application.messages.coordinator == application.community)
	_check("app root assembles engagement slice and runtime port", application.engagement != null and application.engagement_store != null
		and application._views["history"].screen.engagement == application.engagement
		and application.play_view.engagement_runtime == application.engagement_runtime)
	_check("app root assembles commerce slice", application.commerce != null and application.commerce_store != null
		and application._views["shop"].screen.commerce == application.commerce)
	_check("app root assembles operations slice", application.operations != null and application.operations_store != null
		and application._views["report"].screen.operations == application.operations)
	_check("creation screens come from feature factories", application.forge == application.screen_registry.build("creation.forge")
		and application.editor == application.screen_registry.build("creation.editor"))
	_check("community screens come from feature factories", application.messages == application.screen_registry.build("community.messages")
		and application.detail == application.screen_registry.build("catalog.detail"))
	_check("engagement screens come from feature factories", application._views["history"]["screen"] == application.screen_registry.build("engagement.history")
		and application._views["room"]["screen"] == application.screen_registry.build("engagement.room"))
	_check("commerce screens come from feature factories", application._views["shop"]["screen"] == application.screen_registry.build("commerce.shop")
		and application._views["avatar"]["screen"] == application.screen_registry.build("commerce.avatar"))
	_check("operations screens come from feature factories", application._views["report"]["screen"] == application.screen_registry.build("operations.report")
		and application._views["privacy"]["screen"] == application.screen_registry.build("operations.privacy"))
	_check("application and identity screens come from owned factories",application.auth==application.screen_registry.build("identity.auth") and application.settings==application.screen_registry.build("app.settings") and application.play_view==application.screen_registry.build("app.play"))
	_check("app root restores the shared transport token", application.identity_http._token == "restored-token")
	_check("identity screen receives composed coordinator", application.auth.identity == application.identity)
	_check("catalog screen receives composed coordinator", application.home.catalog == application.catalog)
	application.catalog_store.fail(ApiResultScript.offline("network down"))
	_check("catalog offline state reaches application routing", application.router.view == "offline")
	application.home._refreshed = true
	application._retry_offline()
	_check("offline retry invalidates catalog screen and returns", not application.home._refreshed and application.router.view == "tabs")
	application.messages._refreshed = true
	application.community_store.fail(ApiResultScript.offline("community down"))
	_check("community offline state reaches application routing", application.router.view == "offline")
	application._retry_offline()
	_check("offline retry invalidates community screens and returns", not application.messages._refreshed and application.router.view == "tabs")
	var engagement_history: HistoryScreen = application._views["history"]["screen"]
	engagement_history._refreshed = true
	application.engagement_store.fail(ApiResultScript.offline("engagement down"))
	_check("engagement offline state reaches application routing", application.router.view == "offline")
	application._retry_offline()
	_check("offline retry invalidates engagement screens and returns", not engagement_history._refreshed and application.router.view == "tabs")
	var commerce_shop: ShopScreen = application._views["shop"]["screen"]
	commerce_shop._refreshed = true
	application.commerce_store.fail(ApiResultScript.offline("commerce down"))
	_check("commerce offline state reaches application routing", application.router.view == "offline")
	application._retry_offline()
	_check("offline retry invalidates commerce screens and returns", not commerce_shop._refreshed and application.router.view == "tabs")
	var operations_notifications: NotifPrefScreen = application._views["notif"]["screen"]
	operations_notifications._refreshed = true
	application.operations_store.fail(ApiResultScript.offline("operations down"))
	_check("operations offline state reaches application routing", application.router.view == "offline")
	application._retry_offline()
	_check("offline retry invalidates operations screens and returns", not operations_notifications._refreshed and application.router.view == "tabs")
	var library_retries := {"old": 0, "current": 0}
	var old_generation: int = application.catalog_retry.remember_library(func() -> void: library_retries.old += 1)
	application.catalog_retry.remember_library(func() -> void: library_retries.current += 1)
	application.catalog_retry.complete_library(old_generation)
	application.router.go("library")
	application.router.go("offline")
	application._retry_offline()
	_check("stale catalog retry completion cannot clear the current retry", application.router.view == "library"
		and library_retries.old == 0 and library_retries.current == 1)
	var creator := application._views["creator"]["screen"] as CreatorScreen
	creator.handle = "creator-b"
	creator.following = false
	application._apply_creator_follow("creator-a", true)
	_check("stale follow response cannot update another creator", not creator.following)
	var old_screens:Array=[application.home,application.messages,application._views["downloads"].screen,application._views["history"].screen,application._views["shop"].screen,application._views["account"].screen]
	var old_stores:Array=[application.catalog_store,application.creation_store,application.community_store,application.engagement_store,application.commerce_store,application.operations_store]
	application.community_store.conversations=[{"id":"old-account"}];application.engagement_store.downloads=[{"id":"old-account"}];application.commerce_store.balance=999;application.operations_store.security={"phone_masked":"old-account"}
	state.logout()
	await process_frame
	_check("logout replaces every account-scoped store",old_stores.all(func(item):return not is_instance_valid(item)) and application.community_store.conversations.is_empty() and application.engagement_store.downloads.is_empty() and application.commerce_store.balance==0 and application.operations_store.security.is_empty())
	_check("logout disposes every account-scoped screen cache",old_screens.all(func(item):return not is_instance_valid(item)) and application.home!=old_screens[0] and application.messages!=old_screens[1])
	application.free()
	state.free()

func _test_logout_discards_stale_remote_refresh()->void:
	var state=AppStateScript.new();state.save_path="user://app-stale-session-test.cfg";state.authed=true;state.token="old-token";state.onboarded=true
	var gateway:=GatedEngagementGateway.new()
	var application=AppRootScript.new(state,"https://api.example.test",{"identity":LogoutGateway.new(),"engagement":gateway})
	root.add_child(application)
	var old_home:HomeScreen=application.home
	application._refresh_remote()
	state.logout()
	await process_frame
	await process_frame
	_check("stale account refresh cannot bind after logout",not is_instance_valid(old_home) and application.home._continue.is_empty())
	state.login("new-token",{"id":"new-account"});await process_frame
	_check("cancelled old account requests cannot strand the new account offline",application.router.view!="offline")
	application.free();state.free()

func _test_screen_registry_owns_creation_and_lookup() -> void:
	var registry = ScreenRegistryScript.new()
	var feature_creations := {"count": 0}
	registry.register_factory("catalog.home", func() -> Node:
		feature_creations.count += 1
		return Control.new())
	var feature_first := registry.build("catalog.home")
	var feature_second := registry.build("catalog.home")
	_check("registry owns feature factories",registry.has_factory("catalog.home") and feature_first == feature_second and feature_creations.count == 1)
	var creations := {"count": 0}
	var first = registry.create("settings", func() -> Control:
		creations.count += 1
		return Control.new(), "settings_title")
	var second = registry.create("settings", func() -> Control:
		creations.count += 1
		return Control.new(), "ignored")
	_check("registry creates each screen once", first == second and creations.count == 1)
	_check("registry owns route metadata", registry.screen("settings") == first and registry.title("settings") == "settings_title")
	registry.dispose_detached()
	_check("registry releases detached screens", not is_instance_valid(first))

func _test_chrome_controller_owns_breakpoints() -> void:
	var chrome = ChromeControllerScript.new()
	_check("phone breakpoint", chrome.mode_for_width(430.0) == "phone")
	_check("rail breakpoint", chrome.mode_for_width(834.0) == "rail")
	_check("desktop breakpoint", chrome.mode_for_width(1440.0) == "desktop")
	_check("unknown explicit mode is rejected", not chrome.set_mode("television"))
	_check("known explicit mode is accepted", chrome.set_mode("desktop") and chrome.mode == "desktop")

func _test_teen_guard_blocks_curfew_and_daily_limit() -> void:
	const Guard := preload("res://app/teen_guard.gd")
	_check("teen mode off never blocks", Guard.block_reason(false, 23, Guard.DAILY_LIMIT_SECS) == "")
	_check("teen curfew blocks late night", Guard.block_reason(true, 22, 0) == "teen_blocked_curfew")
	_check("teen curfew blocks early morning", Guard.block_reason(true, 7, 0) == "teen_blocked_curfew")
	_check("teen daytime allows play", Guard.block_reason(true, 15, 0) == "")
	_check("teen daily cap blocks", Guard.block_reason(true, 15, Guard.DAILY_LIMIT_SECS) == "teen_blocked_limit")
	const Version := preload("res://app/app_version.gd")
	_check("shipping version is 0.1.0 beta", Version.VERSION == "0.1.0" and "0.1.0" in Version.build_line())
	_check("app root does not auto-show demo update modal", _app_root_skips_demo_update())

func _app_root_skips_demo_update() -> bool:
	var state = AppStateScript.new()
	state.save_path = "user://app-no-demo-update.cfg"
	state.authed = true
	state.onboarded = true
	var application = AppRootScript.new(state, "", {"identity": LogoutGateway.new()})
	var skipped: bool = application.find_child("UpdateModal", true, false) == null
	application.free()
	state.free()
	return skipped

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + label)
