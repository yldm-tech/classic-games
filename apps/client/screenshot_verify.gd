extends SceneTree

## Visual screenshot harness for the polished shell.
## Run (X11 + compatibility renderer, not part of `make ci`):
##   FORGEPLAY_SHOT_DIR=/tmp/fp-shots GODOT=... scripts/run-screenshot-verify.sh
## Captures phone chrome plus one desktop frame with seeded catalog data.

const AppStateScript := preload("res://shell/state/app_state.gd")
const AppRootT := preload("res://app/app_root.gd")
const CatalogT := preload("res://app/catalog_seed.gd")
const ApiResultT := preload("res://core/http/api_result.gd")
const TokensT := preload("res://shell/design_system/theme/tokens.gd")

const PHONE_SIZE := Vector2i(430, 932)
const DESKTOP_SIZE := Vector2i(1280, 800)

var _out_dir := ""
var _captured := 0
var _failed := 0
var _application: AppRoot

class FakeIdentityGateway:
	extends RefCounted
	func guest_login():
		return ApiResultT.success(200, {"token": "shot-guest", "user": {"id": "@koru", "nickname": "@koru"}})
	func logout():
		return ApiResultT.success(204, null)
	func refresh_token():
		return ApiResultT.success(200, {"token": "shot-guest"})

class FakeCatalogGateway:
	extends RefCounted
	func list_games(_query: Dictionary):
		return ApiResultT.success(200, {"items": _games(), "next_cursor": ""})
	func search_games(_q: String, _options: Dictionary):
		return ApiResultT.success(200, {"items": _games(), "next_cursor": ""})
	func ranking(kind: String, _options: Dictionary):
		return ApiResultT.success(200, {"items": _ranking(kind)})
	func game(game_id: String, _lang: String):
		return ApiResultT.success(200, CatalogT.by_id(game_id))
	func game_lineage(_id: String):
		return ApiResultT.success(200, {"items": []})
	func game_fork_tree(_id: String):
		return ApiResultT.success(200, {"items": []})
	func mod_lineage(_id: String):
		return ApiResultT.success(200, {"items": []})
	func user_profile(user_id: String, _lang: String):
		return ApiResultT.success(200, {
			"id": user_id, "bio": "Forging playable worlds", "joined": 2024,
			"works": 6, "plays": 12800, "forks": 340, "follows": 89,
			"level": 12, "points": 860,
		})
	func user_games(_user_id: String, _kind: String, _lang: String):
		return ApiResultT.success(200, {"items": _games().slice(0, 3)})
	func _games() -> Array:
		var items: Array = [CatalogT.FEATURED.duplicate(true)]
		for game: Dictionary in CatalogT.GAMES:
			items.append(game.duplicate(true))
		return items
	func _ranking(kind: String) -> Array:
		var rows: Array = CatalogT.RANKS.get(kind, CatalogT.RANKS.hot)
		var items: Array = []
		var rank := 1
		for row: Array in rows:
			var game := CatalogT.by_id(str(row[0])).duplicate(true)
			if game.is_empty():
				continue
			items.append({"game": game, "rank": rank, "delta": str(row[1])})
			rank += 1
		return items

class FakeCreationGateway:
	extends RefCounted
	func my_games(_lang: String):
		return ApiResultT.success(200, {"items": []})
	func drafts():
		return ApiResultT.success(200, {"items": []})
	func my_mods():
		return ApiResultT.success(200, {"items": []})
	func quota():
		return ApiResultT.success(200, {"used": 2, "remaining": 18, "limit": 20})

class FakeCommunityGateway:
	extends RefCounted
	func list_comments(_id: String):
		return ApiResultT.success(200, {"items": [
			{"author": "@mei", "content": "手感很弹", "time": "2m"},
			{"author": "@arc", "content": "二创了夜景赛道", "time": "1h"},
		]})
	func community(_id: String):
		return ApiResultT.success(200, {"my_rating": 0, "count": 12, "average": 4.6, "posts": []})
	func activity(_lang: String):
		return ApiResultT.success(200, {"items": [
			{"index": 0, "icon": "✦", "title": "作品过审", "body": "《熔岩冲浪》已上架", "time": "刚刚"},
			{"index": 1, "icon": "♡", "title": "@mei 赞了你", "body": "灰烬王国", "time": "12m"},
		]})
	func conversations(_lang: String):
		return ApiResultT.success(200, {"items": [
			{"handle": "@mei", "last_message": "今晚组队冲一把?", "time": "3m", "unread": 2, "online": true},
			{"handle": "@arc", "last_message": "fork 已推给你", "time": "1h", "unread": 0, "online": false},
		]})
	func conversation_messages(_handle: String):
		return ApiResultT.success(200, {"items": [{"text": "今晚组队冲一把?", "mine": false}]})
	func friend_suggestions(_lang: String):
		return ApiResultT.success(200, {"items": [{"handle": "@yuna"}, {"handle": "@talia"}]})
	func follow(_kind: String, _lang: String):
		return ApiResultT.success(200, {"items": [{"handle": "@mei"}, {"handle": "@arc"}]})
	func following(_id: String):
		return ApiResultT.success(200, {"items": [{"handle": "@mei"}]})
	func set_follow(_handle: String, following: bool):
		return ApiResultT.success(200, {"following": following})
	func add_friend(handle: String):
		return ApiResultT.success(201, {"handle": handle})
	func set_like(_id: String, liked: bool):
		return ApiResultT.success(200, {"liked": liked})
	func set_favorite(_id: String, favorite: bool):
		return ApiResultT.success(200, {"favorite": favorite})
	func favorites():
		return ApiResultT.success(200, {"items": []})
	func add_comment(_id: String, text: String):
		return ApiResultT.success(201, {"content": text})
	func rate_game(_id: String, value: int):
		return ApiResultT.success(200, {"my_rating": value, "count": 1, "average": float(value)})
	func create_post(_id: String, text: String):
		return ApiResultT.success(201, {"content": text})
	func send_message(_handle: String, text: String):
		return ApiResultT.success(201, {"items": [{"text": text, "mine": true}]})

class FakeEngagementGateway:
	extends RefCounted
	func history(_lang: String):
		return ApiResultT.success(200, {"groups": [{
			"label": "today",
			"items": [
				{"game": CatalogT.by_id("ember").duplicate(true), "minutes_played": 24},
				{"game": CatalogT.by_id("cinder").duplicate(true), "minutes_played": 11},
			],
		}]})
	func live(_lang: String):
		return ApiResultT.success(200, {"items": [
			{"streamer": "@mei", "title": "夜赛直播", "viewers": 1280, "game": CatalogT.by_id("cinder")},
			{"streamer": "@arc", "title": "策略开荒", "viewers": 640, "game": CatalogT.by_id("foundry")},
		]})
	func downloads(_lang: String):
		return ApiResultT.success(200, {"items": []})
	func update_download(_id: String):
		return ApiResultT.success(200, {})
	func remove_download(_id: String):
		return ApiResultT.success(200, {})
	func clear_history():
		return ApiResultT.success(200, {})
	func send_live_gift(_id: String):
		return ApiResultT.success(200, {"balance": 0})
	func create_room():
		return ApiResultT.success(201, {"id": "room", "members": []})
	func join_room(code: String):
		return ApiResultT.success(200, {"id": code, "members": []})
	func get_room(id: String):
		return ApiResultT.success(200, {"id": id, "members": []})
	func replay_leaderboard(_game_id: String):
		return ApiResultT.success(200, {"items": [
			{"handle": "@mei", "score": 12800},
			{"handle": "@arc", "score": 9600},
		]})
	func record_play(_game_id: String, _duration_ms: int):
		return ApiResultT.success(201, {})
	func submit_replay(_game_id: String, _duration_ms: int, _frames: Array):
		return ApiResultT.success(201, {"score": 0})

class FakeCommerceGateway:
	extends RefCounted
	func events(_lang: String):
		return ApiResultT.success(200, {"items": [
			{"id": "cup", "title": "周末创作杯", "ends_in": "2d"},
		]})
	func joined_events():
		return ApiResultT.success(200, {"event_ids": []})
	func withdrawals():
		return ApiResultT.success(200, {"items": []})
	func payment_orders():
		return ApiResultT.success(200, {"items": []})

class FakeOperationsGateway:
	extends RefCounted
	func track_event(_name: String, _session: String, _id: String = "", _depth: int = 0):
		return ApiResultT.success(204, null)
	func teen(_lang: String):
		return ApiResultT.success(200, {"enabled": false, "pin_placeholder": ""})
	func analytics_summary():
		return ApiResultT.failure_for_status(403, "FORBIDDEN", "admin only")
	func public_meta():
		return ApiResultT.success(200, {
			"environment": "development",
			"ai": {"mode": "stub"},
			"sms": false,
			"oauth_providers": [],
			"payments": false,
			"admin_configured": false,
		})

func _initialize() -> void:
	_out_dir = OS.get_environment("FORGEPLAY_SHOT_DIR")
	if _out_dir == "":
		_out_dir = OS.get_user_data_dir().path_join("screenshots")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_prepare_window(PHONE_SIZE)
	await _run()
	print("screenshot_verify: %d captured, %d failed dir=%s" % [_captured, _failed, _out_dir])
	_finish.call_deferred(0 if _failed == 0 else 1)

func _finish(exit_code: int) -> void:
	await process_frame
	for child in root.get_children():
		if child != _application:
			child.queue_free()
	if _application != null and is_instance_valid(_application):
		_application.queue_free()
	await process_frame
	await process_frame
	quit(exit_code)

func _run() -> void:
	var state: Node = AppStateScript.new()
	state.save_path = "user://forgeplay_screenshot.cfg"
	state.theme = TokensT.THEME_DARK
	state.locale = "zh"
	root.add_child(state)
	_application = AppRootT.new(state, "", {
		"identity": FakeIdentityGateway.new(),
		"catalog": FakeCatalogGateway.new(),
		"creation": FakeCreationGateway.new(),
		"community": FakeCommunityGateway.new(),
		"engagement": FakeEngagementGateway.new(),
		"commerce": FakeCommerceGateway.new(),
		"operations": FakeOperationsGateway.new(),
	})
	root.add_child(_application)
	_application.set_anchors_preset(Control.PRESET_FULL_RECT)
	_application.set_layout("phone")
	_application.router.resolve_orientation(true)
	await _wait_ready()
	_dismiss_update()
	await _wait_frames(2)
	if _application.home.skeleton:
		await _shot("02_home_skeleton")
	# Force the empty CTA regardless of in-flight refresh so the shot
	# actually shows HomeEmpty + empty_go_explore.
	_application.home.finish_loading()
	_application.home.bind_games([])
	_application.home.bind_trending([])
	_application.home.bind_history([])
	_application.home.bind_events([])
	await _wait_ready()
	await _shot("03_home_empty")
	_bind_catalog()
	await _wait_ready()
	await _shot("04_home_populated")
	_application.router.set_tab(1)
	await _wait_ready()
	await _shot("05_explore")
	_application.router.set_tab(2)
	await _wait_ready()
	await _shot("06_forge")
	_application.router.set_tab(3)
	await _wait_ready()
	# Messages refresh is async; wait until activity rows exist.
	await _wait_until(func() -> bool:
		return _application.messages.find_child("ActivityList", true, false) != null, 1.5)
	await _shot("07_messages")
	_application.messages.seg = 2
	_application.messages.rebuild()
	await _wait_ready()
	await _shot("08_messages_friends")
	_application.router.set_tab(4)
	await _wait_ready()
	await _wait_until(func() -> bool:
		return _application.profile.find_child("IdentityCard", true, false) != null, 1.5)
	await _shot("09_profile")
	_application.router.go("settings")
	await _wait_ready()
	await _shot("10_settings_dark")
	state.set_theme(TokensT.THEME_LIGHT)
	await _wait_ready()
	await _shot("11_settings_light")
	state.set_theme(TokensT.THEME_DARK)
	await _wait_ready()
	_application.router.open_game(CatalogT.by_id("ember"))
	await _wait_ready()
	await _shot("12_detail")
	await _shot_play_huds()
	_application.router.back()
	await _wait_ready()
	state.onboarded = false
	_application._sync()
	await _wait_ready()
	await _shot("13_onboarding")
	state.onboarded = true
	state.logout()
	await process_frame
	_application._sync()
	await _wait_ready()
	await _shot("14_auth")
	state.login("shot-guest", {"id": "@koru", "nickname": "@koru"})
	state.onboarded = true
	_application._sync()
	_dismiss_update()
	_bind_catalog()
	await _wait_ready()
	_prepare_window(DESKTOP_SIZE)
	_application.set_layout("desktop")
	_application.router.view = "tabs"
	_application.router.set_tab(0)
	_application._sync()
	await _wait_ready()
	await _shot("15_desktop_home")

func _shot_play_huds() -> void:
	_application.router.is_portrait = false
	_application.router.play(CatalogT.by_id("ember"))
	_application.router.enter_play()
	await _wait_ready()
	await _shot("16_play_shooter")
	var pause := _application.play_view.find_child("PauseButton", true, false)
	if pause is Button:
		(pause as Button).pressed.emit()
		await _wait_ready()
		await _shot("19_play_pause")
		var resume := _application.play_view.find_child("ResumeButton", true, false)
		if resume is Button:
			(resume as Button).pressed.emit()
			await _wait_ready()
	var survivor_dsl: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://runtime/survivor/baseline.dsl.json"))
	_application.router.play({"id": "survivor-shot", "runtime": "survivor@1.0.0", "dsl": survivor_dsl})
	_application.router.enter_play()
	await _wait_ready()
	await _shot("17_play_survivor")
	var td_dsl: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://runtime/tower_defense/baseline.dsl.json"))
	_application.router.play({"id": "td-shot", "runtime": "tower_defense@1.0.0", "dsl": td_dsl})
	_application.router.enter_play()
	await _wait_ready()
	await _shot("18_play_tower_defense")
	_application.play_view.finish_run()
	await _wait_ready()
	await _shot("20_play_result")
	_application.router.exit_play()
	_application._sync()
	await _wait_ready()

func _bind_catalog() -> void:
	var catalog := FakeCatalogGateway.new()
	var games: Array = catalog._games()
	var ranking: Array = catalog._ranking("hot")
	_application.home.bind_games(games)
	_application.home.bind_trending(ranking)
	_application.home.bind_history([{
		"items": [
			{"game": CatalogT.by_id("ember").duplicate(true), "minutes_played": 24},
			{"game": CatalogT.by_id("cinder").duplicate(true), "minutes_played": 11},
		],
	}])
	_application.home.bind_events([{"id": "cup", "title": "周末创作杯", "ends_in": "2d"}])
	_application.explore.bind_games(games)
	_application.explore.bind_ranking(0, ranking)
	_application.explore.bind_live([
		{"streamer": "@mei", "title": "夜赛直播", "viewers": 1280, "game": CatalogT.by_id("cinder")},
		{"streamer": "@arc", "title": "策略开荒", "viewers": 640, "game": CatalogT.by_id("foundry")},
	])
	_application.forge.bind_trending(ranking)

func _dismiss_update() -> void:
	var later := _application.find_child("LaterButton", true, false)
	if later is Button:
		(later as Button).pressed.emit()

func _prepare_window(size: Vector2i) -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(size)
	root.size = Vector2(size)

func _wait_ready() -> void:
	await process_frame
	await process_frame
	# Cover fade-in (Tokens.DUR_MED) plus one extra paint.
	await create_timer(0.28).timeout
	await RenderingServer.frame_post_draw

func _wait_frames(n: int) -> void:
	for i in n:
		await process_frame
	await RenderingServer.frame_post_draw

func _wait_until(pred: Callable, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if pred.call():
			break
		await process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var tex := root.get_viewport().get_texture()
	if tex == null:
		_fail_shot(name, "missing viewport texture")
		return
	var img := tex.get_image()
	if img == null or img.get_width() < 8 or img.get_height() < 8:
		_fail_shot(name, "empty image")
		return
	if _is_blank(img):
		_fail_shot(name, "blank image")
		return
	var path := _out_dir.path_join("%s.png" % name)
	var err := img.save_png(path)
	if err != OK:
		_fail_shot(name, "save failed %s" % err)
		return
	_captured += 1
	print("screenshot_verify captured %s %dx%d" % [path, img.get_width(), img.get_height()])

func _fail_shot(name: String, reason: String) -> void:
	_failed += 1
	push_error("screenshot_verify failed %s: %s" % [name, reason])

func _is_blank(img: Image) -> bool:
	var samples := [
		Vector2i(img.get_width() / 2, img.get_height() / 2),
		Vector2i(8, 8),
		Vector2i(img.get_width() - 9, img.get_height() - 9),
	]
	var first := img.get_pixelv(samples[0])
	for p: Vector2i in samples:
		var c := img.get_pixelv(p)
		if absf(c.r - first.r) > 0.02 or absf(c.g - first.g) > 0.02 or absf(c.b - first.b) > 0.02:
			return false
		if c.a > 0.05 and (c.r + c.g + c.b) > 0.08:
			return false
	return true
