extends SceneTree

const ApiResultScript := preload("res://core/http/api_result.gd")
const CatalogApiScript := preload("res://features/catalog/catalog_api.gd")
const CatalogStoreScript := preload("res://features/catalog/catalog_store.gd")
const CatalogCoordinatorScript := preload("res://features/catalog/catalog_coordinator.gd")
const HomeScreenScript := preload("res://features/catalog/home_screen.gd")
const ExploreScreenScript := preload("res://features/catalog/explore_screen.gd")
const SearchScreenScript := preload("res://features/catalog/search_screen.gd")
const ProfileScreenScript := preload("res://features/catalog/profile_screen.gd")
const CreatorScreenScript := preload("res://features/catalog/creator_screen.gd")
const AppStateScript := preload("res://shell/state/app_state.gd")

class Gate:
	extends RefCounted
	signal released

class FakeTransport:
	extends RefCounted
	var requests: Array[Dictionary] = []

	func request(method: int, path: String, body: Variant = null):
		requests.append({"method": method, "path": path, "body": body})
		return ApiResultScript.success(200, {})

class FakeCatalogGateway:
	extends RefCounted
	var list_requests: Array[Dictionary] = []
	var list_results: Array = []
	var list_gates: Array = []
	var search_requests: Array[Dictionary] = []
	var search_results: Array = []
	var search_gates: Array = []
	var detail_result = ApiResultScript.success(200, {"id": "game-1"})
	var lineage_result = ApiResultScript.success(200, {"items": [{"id": "mod-root"}]})
	var tree_result = ApiResultScript.success(200, {"root": {"id": "mod-root"}})
	var mod_lineage_result = ApiResultScript.success(200, {"items": [{"id": "mod-1"}]})
	var ranking_result = ApiResultScript.success(200, {"items": [{"game": {"id": "ranked"}}]})
	var profile_result = ApiResultScript.success(200, {"id": "user-1"})
	var user_games_result = ApiResultScript.success(200, {"items": [{"id": "owned"}]})

	func list_games(query: Dictionary):
		var index := list_requests.size()
		list_requests.append(query.duplicate(true))
		if index < list_gates.size() and list_gates[index] != null:
			await list_gates[index].released
		return list_results[index] if index < list_results.size() else ApiResultScript.success(200, {"items": [], "next_cursor": ""})

	func search_games(query: String, options: Dictionary):
		var index := search_requests.size()
		search_requests.append({"query": query, "options": options.duplicate(true)})
		if index < search_gates.size() and search_gates[index] != null:
			await search_gates[index].released
		return search_results[index] if index < search_results.size() else ApiResultScript.success(200, {"items": [], "next_cursor": ""})

	func game(game_id: String, lang: String):
		return detail_result

	func game_lineage(game_id: String):
		return lineage_result

	func game_fork_tree(game_id: String):
		return tree_result

	func mod_lineage(mod_id: String):
		return mod_lineage_result

	func ranking(kind: String, options: Dictionary):
		return ranking_result

	func user_profile(user_id: String, lang: String):
		return profile_result

	func user_games(user_id: String, kind: String, lang: String):
		return user_games_result

var _passed := 0
var _failed := 0

func _initialize() -> void:
	await _test_gateway_owns_catalog_paths()
	await _test_initial_and_cursor_paging()
	await _test_duplicate_paging_is_rejected()
	await _test_screen_owned_page_queries()
	await _test_independent_screen_initial_collections()
	await _test_stale_initial_screen_refresh_is_ignored()
	await _test_stale_screen_page_is_ignored()
	await _test_stale_search_response_is_ignored()
	await _test_collection_states_are_distinct()
	await _test_resource_queries_populate_owned_state()
	await _test_catalog_screens_delegate_to_coordinator()
	await _test_explore_filters_are_sent_to_gateway()
	print("catalog_test: %d passed, %d failed" % [_passed, _failed])
	quit.call_deferred(0 if _failed == 0 else 1)

func _test_gateway_owns_catalog_paths() -> void:
	var transport := FakeTransport.new()
	var api = CatalogApiScript.new(transport)
	await api.list_games({"lang": "ja", "sort": "hot", "runtime": "shooter", "category": "arcade", "cursor": "c 1", "limit": 12})
	await api.search_games("cat game", {"lang": "en", "category": "cute", "ai": "true"})
	await api.game("game/1", "zh")
	await api.ranking("rising", {"lang": "zh", "runtime": "shooter", "category": "arcade", "limit": 10})
	await api.user_profile("user/1", "ja")
	await api.user_games("user/1", "forks", "en")
	await api.game_lineage("game/1")
	await api.game_fork_tree("game/1")
	await api.mod_lineage("mod/1")
	var paths: Array = transport.requests.map(func(entry: Dictionary): return entry.path)
	_check("catalog gateway owns list query", paths[0] == "/api/v1/games?lang=ja&sort=hot&runtime=shooter&category=arcade&cursor=c%201&limit=12")
	_check("catalog gateway owns search query", paths[1] == "/api/v1/games?q=cat%20game&lang=en&category=cute&ai=true")
	_check("catalog gateway owns detail and ranking", paths[2] == "/api/v1/games/game%2F1?lang=zh" and paths[3] == "/api/v1/ranking?type=rising&lang=zh&runtime=shooter&category=arcade&limit=10")
	_check("catalog gateway owns profile paths", paths[4] == "/api/v1/users/user%2F1/profile?lang=ja" and paths[5] == "/api/v1/users/user%2F1/games?type=forks&lang=en")
	_check("catalog gateway owns lineage paths", paths.slice(6) == [
		"/api/v1/games/game%2F1/lineage",
		"/api/v1/games/game%2F1/fork-tree",
		"/api/v1/mods/mod%2F1/lineage",
	])
	await api.list_games({"lang": "zh", "ai": "true"})
	_check("catalog gateway owns ai filter", transport.requests.back().path == "/api/v1/games?lang=zh&ai=true")

func _test_initial_and_cursor_paging() -> void:
	var fixture := _fixture()
	fixture.gateway.list_results = [
		ApiResultScript.success(200, {"items": [{"id": "game-1"}], "next_cursor": "page-2"}),
		ApiResultScript.success(200, {"items": [{"id": "game-1"}, {"id": "game-2"}], "next_cursor": ""}),
	]
	var loaded: bool = await fixture.coordinator.load_games({"lang": "zh", "sort": "hot"})
	_check("initial list becomes ready", loaded and fixture.store.status == "ready" and fixture.store.items.size() == 1)
	_check("initial list stores cursor", fixture.store.next_cursor == "page-2")
	var paged: bool = await fixture.coordinator.load_next_page()
	_check("next page appends unique games", paged and fixture.store.items.map(func(game: Dictionary): return game.id) == ["game-1", "game-2"])
	_check("paging sends prior cursor", fixture.gateway.list_requests[1].cursor == "page-2")
	fixture.free_all.call()

func _test_duplicate_paging_is_rejected() -> void:
	var fixture := _fixture()
	var gate := Gate.new()
	fixture.gateway.list_results = [
		ApiResultScript.success(200, {"items": [{"id": "game-1"}], "next_cursor": "page-2"}),
		ApiResultScript.success(200, {"items": [{"id": "game-2"}], "next_cursor": ""}),
	]
	fixture.gateway.list_gates = [null, gate]
	await fixture.coordinator.load_games({"lang": "zh"})
	fixture.coordinator.load_next_page()
	var duplicate: bool = await fixture.coordinator.load_next_page()
	_check("duplicate pagination is rejected", not duplicate and fixture.gateway.list_requests.size() == 2)
	gate.released.emit()
	await process_frame
	fixture.free_all.call()

func _test_screen_owned_page_queries()->void:
	var fixture:=_fixture();fixture.gateway.list_results=[ApiResultScript.success(200,{"items":[{"id":"explore-2"}],"next_cursor":""})];fixture.gateway.search_results=[ApiResultScript.success(200,{"items":[{"id":"search-2"}],"next_cursor":""})]
	var explore_page:Dictionary=await fixture.coordinator.load_page({"lang":"ja"},"explore-cursor");var search_page:Dictionary=await fixture.coordinator.load_page({"q":"cats","lang":"en"},"search-cursor")
	_check("screen-owned pagination keeps independent queries",explore_page.items[0].id=="explore-2" and search_page.items[0].id=="search-2" and fixture.gateway.list_requests[0].cursor=="explore-cursor" and fixture.gateway.search_requests[0].options.cursor=="search-cursor")
	fixture.free_all.call()

func _test_independent_screen_initial_collections()->void:
	var fixture:=_fixture();var old_gate:=Gate.new()
	fixture.gateway.list_gates=[old_gate,null]
	fixture.gateway.list_results=[
		ApiResultScript.success(200,{"items":[{"id":"explore-old","title":"Explore"}],"next_cursor":""}),
		ApiResultScript.success(200,{"items":[{"id":"search-new","title":"Search"}],"next_cursor":""}),
	]
	var state=AppStateScript.new();state.save_path="user://catalog-independent-initial.cfg"
	var explore=ExploreScreenScript.new(state,fixture.coordinator);var search=SearchScreenScript.new(state,fixture.coordinator)
	root.add_child(explore);root.add_child(search)
	explore.refresh();await process_frame
	await search.refresh()
	old_gate.released.emit();await process_frame;await process_frame
	_check("initial collections are owned independently across screens",explore._server_games[0].id=="explore-old" and search._server_games[0].id=="search-new")
	explore.free();search.free();state.free();fixture.free_all.call()

func _test_stale_initial_screen_refresh_is_ignored()->void:
	var state=AppStateScript.new();state.save_path="user://catalog-stale-initial.cfg"
	var explore_fixture:=_fixture();var explore_old:=Gate.new();var explore_new:=Gate.new()
	explore_fixture.gateway.list_gates=[explore_old,explore_new]
	explore_fixture.gateway.list_results=[ApiResultScript.success(200,{"items":[{"id":"explore-old"}],"next_cursor":""}),ApiResultScript.success(200,{"items":[{"id":"explore-new"}],"next_cursor":""})]
	var explore=ExploreScreenScript.new(state,explore_fixture.coordinator);root.add_child(explore)
	explore.refresh();await process_frame;explore.refresh();await process_frame;explore_new.released.emit();await process_frame;await process_frame;explore_old.released.emit();await process_frame;await process_frame
	_check("latest Explore initial refresh wins",explore._server_games[0].id=="explore-new")
	explore.free();explore_fixture.free_all.call()

	var search_fixture:=_fixture();var search_old:=Gate.new();var search_new:=Gate.new()
	search_fixture.gateway.list_gates=[search_old,search_new]
	search_fixture.gateway.list_results=[ApiResultScript.success(200,{"items":[{"id":"search-old"}],"next_cursor":""}),ApiResultScript.success(200,{"items":[{"id":"search-new"}],"next_cursor":""})]
	var search=SearchScreenScript.new(state,search_fixture.coordinator);root.add_child(search)
	search.refresh();await process_frame;search.refresh();await process_frame;search_new.released.emit();await process_frame;search_old.released.emit();await process_frame;await process_frame
	_check("latest Search initial refresh wins",search._server_games[0].id=="search-new")
	search.free();search_fixture.free_all.call();state.free()

func _test_stale_screen_page_is_ignored()->void:
	var fixture:=_fixture();var gate:=Gate.new();fixture.gateway.list_gates=[null,gate,null];fixture.gateway.list_results=[ApiResultScript.success(200,{"items":[{"id":"old-base","title":"Old"}],"next_cursor":"old-next"}),ApiResultScript.success(200,{"items":[{"id":"stale-page","title":"Stale"}],"next_cursor":""}),ApiResultScript.success(200,{"items":[{"id":"new-base","title":"New"}],"next_cursor":""})]
	var state=AppStateScript.new();state.save_path="user://catalog-stale-page.cfg";var explore=ExploreScreenScript.new(state,fixture.coordinator);root.add_child(explore);await explore.refresh();(explore.find_child("LoadMoreButton",true,false) as Button).pressed.emit();await process_frame;await explore.refresh();gate.released.emit();await process_frame
	_check("stale screen page cannot append into a refreshed collection",explore._server_games.map(func(item):return item.id)==["new-base"])
	explore.free();state.free();fixture.free_all.call()

func _test_stale_search_response_is_ignored() -> void:
	var fixture := _fixture()
	var old_gate := Gate.new()
	var new_gate := Gate.new()
	fixture.gateway.search_gates = [old_gate, new_gate]
	fixture.gateway.search_results = [
		ApiResultScript.success(200, {"items": [{"id": "old"}], "next_cursor": ""}),
		ApiResultScript.success(200, {"items": [{"id": "new"}], "next_cursor": ""}),
	]
	fixture.coordinator.search("  Cats  ", {"lang": "en"})
	fixture.coordinator.search("Dogs", {"lang": "en"})
	new_gate.released.emit()
	await process_frame
	_check("search query is normalized", fixture.gateway.search_requests[0].query == "Cats")
	_check("latest search result wins", fixture.store.items[0].id == "new" and fixture.store.query.q == "Dogs")
	old_gate.released.emit()
	await process_frame
	_check("stale search cannot overwrite state", fixture.store.items[0].id == "new")
	fixture.free_all.call()

func _test_collection_states_are_distinct() -> void:
	var cases := [
		[ApiResultScript.success(200, {"items": [], "next_cursor": ""}), "empty"],
		[ApiResultScript.offline("network down"), "offline"],
		[ApiResultScript.failure_for_status(422, "BAD_FILTER", "bad filter"), "validation_error"],
		[ApiResultScript.failure_for_status(401, "LOGIN_REQUIRED", "login"), "unauthorized"],
	]
	for test_case: Array in cases:
		var fixture := _fixture()
		fixture.gateway.list_results = [test_case[0]]
		var accepted: bool = await fixture.coordinator.load_games({"lang": "zh"})
		_check("%s result has distinct collection state" % test_case[1], fixture.store.status == test_case[1])
		_check("%s result reports acceptance correctly" % test_case[1], accepted == (test_case[1] == "empty"))
		fixture.free_all.call()

func _test_resource_queries_populate_owned_state() -> void:
	var fixture := _fixture()
	var detail_ok: bool = await fixture.coordinator.load_game("game-1", "zh")
	var lineage_ok: bool = await fixture.coordinator.load_game_lineage("game-1")
	var tree_ok: bool = await fixture.coordinator.load_game_fork_tree("game-1")
	var mod_ok: bool = await fixture.coordinator.load_mod_lineage("mod-1")
	var ranking_ok: bool = await fixture.coordinator.load_ranking("hot", {"lang": "zh"})
	var profile_ok: bool = await fixture.coordinator.load_profile("user-1", "zh")
	var games_ok: bool = await fixture.coordinator.load_user_games("user-1", "works", "zh")
	_check("resource queries succeed", detail_ok and lineage_ok and tree_ok and mod_ok and ranking_ok and profile_ok and games_ok)
	_check("detail and lineage state are owned", fixture.store.detail.id == "game-1" and fixture.store.game_lineage[0].id == "mod-root" and fixture.store.fork_tree.root.id == "mod-root")
	_check("ranking and profile state are owned", fixture.store.ranking[0].game.id == "ranked" and fixture.store.profile.id == "user-1" and fixture.store.profile_games[0].id == "owned")
	fixture.free_all.call()

func _test_catalog_screens_delegate_to_coordinator() -> void:
	var fixture := _fixture()
	fixture.gateway.list_results = [
		ApiResultScript.success(200, {"items": [{"id": "home-game", "title": "Home Game"}], "next_cursor": ""}),
		ApiResultScript.success(200, {"items": [{"id": "explore-game", "title": "Explore Game"}], "next_cursor": "explore-next"}),
		ApiResultScript.success(200, {"items": [{"id": "explore-page-2", "title": "Explore Page 2"}], "next_cursor": ""}),
		ApiResultScript.success(200, {"items": [{"id": "search-base", "title": "Search Base"}], "next_cursor": ""}),
	]
	fixture.gateway.search_results = [
		ApiResultScript.success(200, {"items": [{"id": "search-hit", "title": "Search Hit"}], "next_cursor": ""}),
		ApiResultScript.offline("network down"),
		ApiResultScript.success(200, {"items": [{"id": "retry-hit", "title": "Retry Hit"}], "next_cursor": ""}),
	]
	var state = AppStateScript.new()
	state.save_path = "user://catalog-screen-test.cfg"
	var home = HomeScreenScript.new(state, fixture.coordinator)
	root.add_child(home)
	var home_trending := {"value": []}
	home.trending_loaded.connect(func(items: Array) -> void: home_trending.value = items)
	await home.refresh()
	_check("home screen renders coordinator games", home.find_child("HeroTitle", true, false).text == "Home Game")
	_check("home normalizes ranked games for cross-feature consumers", home_trending.value[0].id == "ranked")
	var explore = ExploreScreenScript.new(state, fixture.coordinator)
	root.add_child(explore)
	await explore.refresh()
	_check("explore screen renders coordinator games", explore.find_child("GamesGrid", true, false).get_child_count() == 1)
	(explore.find_child("LoadMoreButton",true,false) as Button).pressed.emit();await process_frame
	_check("explore pagination appends through its screen-owned cursor",explore.find_child("GamesGrid",true,false).get_child_count()==2 and fixture.gateway.list_requests[2].cursor=="explore-next")
	var search = SearchScreenScript.new(state, fixture.coordinator)
	root.add_child(search)
	await search.refresh()
	(search.find_child("SearchInput", true, false) as LineEdit).text_changed.emit("  comet  ")
	await process_frame
	_check("search screen delegates normalized intent", fixture.gateway.search_requests.back().query == "comet")
	_check("search screen renders coordinator results", search.find_child("ResultList", true, false).get_child_count() == 1)
	(search.find_child("SearchInput", true, false) as LineEdit).text_changed.emit("retry me")
	await process_frame
	_check("offline search keeps its current intent",search._async_state=="offline" and search._query=="retry me")
	await search.retry_current()
	_check("search retry replays the same query", fixture.gateway.search_requests.slice(-2).map(func(request: Dictionary): return request.query) == ["retry me", "retry me"])
	_check("search retry renders the recovered response", search.find_child("ResultList", true, false).get_child_count() == 1)
	var profile = ProfileScreenScript.new(state, fixture.coordinator)
	root.add_child(profile)
	await profile.refresh()
	_check("profile screen reads catalog profile", profile._server.id == "user-1" and profile._segment_games[0][0].id == "owned")
	var creator = CreatorScreenScript.new(state, fixture.coordinator)
	root.add_child(creator)
	creator.set_creator("user-1")
	await process_frame
	var follow_intent := {"value": []}
	creator.follow_requested.connect(func(handle: String, following: bool) -> void: follow_intent.value = [handle, following])
	(creator.find_child("FollowButton", true, false) as Button).pressed.emit()
	_check("creator follow is a cross-feature intent", follow_intent.value == ["user-1", true])
	for screen: Node in [home, explore, search, profile, creator]:
		screen.free()
	state.free()
	fixture.free_all.call()

func _test_explore_filters_are_sent_to_gateway() -> void:
	var fixture := _fixture()
	fixture.gateway.list_results = [
		ApiResultScript.success(200, {"items": [{"id": "all", "title": "All"}], "next_cursor": ""}),
		ApiResultScript.success(200, {"items": [{"id": "racing", "title": "Racing"}], "next_cursor": ""}),
		ApiResultScript.success(200, {"items": [{"id": "ai", "title": "AI"}], "next_cursor": ""}),
	]
	var state = AppStateScript.new()
	state.save_path = "user://catalog-filter-test.cfg"
	var explore = ExploreScreenScript.new(state, fixture.coordinator)
	root.add_child(explore)
	await explore.refresh()
	(explore.find_child("CatChips", true, false).get_child(1) as Button).pressed.emit()
	await process_frame
	await process_frame
	_check("explore category filter is sent to catalog", fixture.gateway.list_requests.size() >= 2
		and str(fixture.gateway.list_requests.back().get("category", "")) == "racing")
	var chips := explore.find_child("CatChips", true, false)
	(chips.get_child(chips.get_child_count() - 1) as Button).pressed.emit()
	await process_frame
	await process_frame
	_check("explore ai filter is sent with the active category", str(fixture.gateway.list_requests.back().get("ai", "")) == "true"
		and str(fixture.gateway.list_requests.back().get("category", "")) == "racing")
	explore.free(); state.free(); fixture.free_all.call()

func _fixture() -> Dictionary:
	var gateway := FakeCatalogGateway.new()
	var store = CatalogStoreScript.new()
	var coordinator = CatalogCoordinatorScript.new(gateway, store)
	return {
		"gateway": gateway,
		"store": store,
		"coordinator": coordinator,
		"free_all": func() -> void:
			coordinator.free()
			store.free(),
	}

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + label)
