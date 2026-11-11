extends SceneTree

## Renders one launcher screen to a PNG at exactly 1920x1080 for visual checks. It needs a real renderer, so it is not part of `make ci`; run it through scripts/run-launcher-shot.sh.
##
## Environment:
##   LAUNCHER_SHOT_DIR      output directory (required)
##   LAUNCHER_SHOT_SCREEN   screen id to show, default "home"
##   LAUNCHER_SHOT_STATE    "played" (default) starts from a throwaway profile with a few recorded runs so the shelf, records and progress are populated; "fresh" starts from an empty profile
##   LAUNCHER_SHOT_ACTIONS  comma-separated LauncherInput action names without the "launcher_" prefix, dispatched in order before the capture (e.g. "down,menu")
##   LAUNCHER_SHOT_LOCALE   "zh" (default) or "en"
##   LAUNCHER_SHOT_KEYS     comma-separated key names (as OS.find_keycode_from_string reads them, e.g. "J,Space") pressed as real key events after the actions, for states only a raw key reaches (the key of a rebinding)
##   LAUNCHER_SHOT_NAME     file name without extension, default "<screen>-<state>"
##   LAUNCHER_SHOT_LIBRARY_EXTRA  number of synthetic entries to add to the library's grid, to look at it with more rows than the catalog fills (they have no art and exist only in this render)
##   LAUNCHER_SHOT_MODE     "pc" switches to PC mode before the actions are dispatched
##   LAUNCHER_SHOT_PC       semicolon-separated steps applied to PC mode after the actions: view=library, layout=list, sort=recent, category=favorites, genre=<English genre>, tab=1, locked, select=<game id>, query=<text>, search (focus the field), many=<n> (n synthetic games on top of the catalog), width=<canvas px> (narrower PC area, to check reflow), hover=<game id>, zone=<search|sidebar|main> (move keyboard focus there and show the ring), menu (the selected game's menu), sort_menu
##   LAUNCHER_SHOT_GAME     catalog game id passed to the screen as { "game": id }, default "shooter" (the first game of the catalog when there is no such id)
##   LAUNCHER_SHOT_GAMES_ROOT  games directory the catalog reads instead of the shipped one (the test fixture games live in the testing directory's games folder)
##   LAUNCHER_SHOT_PLAYERS  player count the game starts with (1 or 2), for a game module that seats two
##   LAUNCHER_SHOT_SEED     seed handed to a game module, default 1, so a capture can be repeated exactly
##   LAUNCHER_SHOT_INPUT    scripted per-player input for a game module, run after the actions: semicolon-separated segments "SECONDS:P1 CONTROLS/P2 CONTROLS", controls joined by "+" (up down left right a b x y l r), e.g. "1.5:right+a/left;0.5:/a;1:" holds right and A for player one and left for player two for 1.5 game seconds, then only player two's A for 0.5, then nothing for 1. Seconds are game seconds, so "scale=N" in the actions shortens the wait
##
## Besides action names, LAUNCHER_SHOT_ACTIONS accepts steps that let a live game reach a state worth capturing: "wait=SECONDS" (real seconds), "scale=N" (Engine.time_scale), "press=ACTION" / "release=ACTION" (hold or let go of a launcher action, for what the game screen polls) and "cursor=X:Y" (put the game screen's tower cursor at a stage position).
##
## The launcher is mounted in a SubViewport of the canvas size, so the PNG does not depend on the size of the window or the display. The profile lives in its own file and never touches the player's real one.

const RootScene := "res://launcher/launcher.tscn"
const STORE_PATH := "user://launcher-shot.json"

func _initialize() -> void:
	var out_dir := OS.get_environment("LAUNCHER_SHOT_DIR")
	if out_dir == "":
		push_error("LAUNCHER_SHOT_DIR is not set")
		quit(2)
		return
	var screen_id := _env("LAUNCHER_SHOT_SCREEN", "home")
	var state := _env("LAUNCHER_SHOT_STATE", "played")
	var locale := _env("LAUNCHER_SHOT_LOCALE", "zh")
	var file_name := _env("LAUNCHER_SHOT_NAME", "%s-%s" % [screen_id, state])

	if FileAccess.file_exists(STORE_PATH):
		DirAccess.remove_absolute(STORE_PATH)
	var store := LauncherStore.new(STORE_PATH)
	store.load_from_disk()
	var now := int(Time.get_unix_time_from_system())
	if state == "played":
		store.record_run("survivor", {"score": 240, "play_seconds": 412.0, "cleared": false}, now - 3 * 86400)
		store.unlock("survivor", "first_watch", now - 3 * 86400)
		store.record_run("tower_defense", {"score": 2130, "play_seconds": 655.0, "cleared": true}, now - 86400)
		store.unlock("tower_defense", "first_defense", now - 86400)
		store.unlock("tower_defense", "gate_held", now - 86400)
		store.record_run("shooter", {"score": 1800, "play_seconds": 388.0, "cleared": false}, now - 1800)
		store.unlock("shooter", "first_sortie", now - 1800)
		store.set_favorite("shooter", true)
	store.set_setting("lang", locale)

	var games_root := _env("LAUNCHER_SHOT_GAMES_ROOT", "")
	if games_root != "":
		LauncherCatalog.use_root(games_root)
	var game_id := _env("LAUNCHER_SHOT_GAME", "shooter")
	if not LauncherCatalog.has(game_id):
		game_id = LauncherCatalog.first_id()
	var player_count := int(_env("LAUNCHER_SHOT_PLAYERS", "0"))
	if player_count > 0:
		store.set_setting(LauncherGameGuide.players_key(game_id), player_count)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(LauncherTokens.CANVAS)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var shell: LauncherRoot = (load(RootScene) as PackedScene).instantiate()
	shell.store = store
	viewport.add_child(shell)
	await process_frame
	shell.game_host.run_seed = int(_env("LAUNCHER_SHOT_SEED", "1"))
	var extra := int(_env("LAUNCHER_SHOT_LIBRARY_EXTRA", "0"))
	if extra > 0:
		var crowded: Array[Dictionary] = []
		crowded.assign(LauncherCatalog.all())
		for index in extra:
			var sample: Dictionary = LauncherCatalog.all()[index % LauncherCatalog.all().size()].duplicate(true)
			sample["id"] = "sample_%02d" % index
			sample["name"] = {"zh": "样例条目 %02d" % (index + 1), "en": "SAMPLE ENTRY %02d" % (index + 1)}
			sample["initials"] = "yltm"
			crowded.append(sample)
		(shell.screen(LauncherRoot.LIBRARY) as LauncherLibraryScreen).set_entries(crowded)
	(shell.screen(LauncherRoot.GAME) as LauncherGameScreen).pause_on_focus_loss = false
	if screen_id != "home":
		shell.go(StringName(screen_id), {"game": game_id})
	if _env("LAUNCHER_SHOT_MODE", "console") == "pc":
		shell.toggle_pc_mode()
		await process_frame
	for action in _env("LAUNCHER_SHOT_ACTIONS", "").split(",", false):
		var step := action.strip_edges()
		if step.contains("="):
			await _run_step(shell, step.get_slice("=", 0), step.get_slice("=", 1))
			continue
		shell.dispatch(StringName("launcher_" + step))
		await process_frame
	await _play_input(shell, _env("LAUNCHER_SHOT_INPUT", ""))
	for key_name in _env("LAUNCHER_SHOT_KEYS", "").split(",", false):
		var key := InputEventKey.new()
		key.physical_keycode = OS.find_keycode_from_string(key_name.strip_edges())
		key.pressed = true
		viewport.push_input(key)
		await process_frame
	var pc := shell.find_child("PcMode", false, false) as LauncherPcMode
	if pc != null:
		for step in _env("LAUNCHER_SHOT_PC", "").split(";", false):
			_pc_step(pc, step.strip_edges())
			await process_frame
			await process_frame
	Engine.time_scale = 1.0
	# Let the screen fade, the backdrop cross-fade and the card resize finish.
	await create_timer(1.2).timeout
	# A window that is covered, minimised or on another desktop is never drawn, so waiting for frame_post_draw would hang there. Force the frames instead: one for the nested viewports (blur, game stage), one for the canvas that shows them.
	RenderingServer.force_draw()
	RenderingServer.force_draw()
	var image := viewport.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path := out_dir.path_join(file_name + ".png")
	var saved := image.save_png(path)
	shell.free()
	viewport.free()
	DirAccess.remove_absolute(STORE_PATH)
	# A runtime's music player was freed while playing; the audio thread lets go of its stream a moment later, and quitting before that is reported as leaked instances.
	await create_timer(0.2).timeout
	if saved != OK:
		push_error("could not write %s" % path)
		quit(1)
		return
	print("launcher_shot: wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])
	quit(0)

## Play a LAUNCHER_SHOT_INPUT script on the game module that is live: each segment sets which controls each player holds, then lets that many game seconds pass. Everything is let go at the end.
func _play_input(shell: LauncherRoot, script_text: String) -> void:
	var host := shell.game_host
	for segment in script_text.split(";", false):
		var seconds := segment.get_slice(":", 0).to_float()
		var held := segment.get_slice(":", 1).split("/") if segment.contains(":") else PackedStringArray()
		for slot in GameSession.MAX_PLAYERS:
			var wanted := held[slot].split("+", false) if slot < held.size() else PackedStringArray()
			for control in GameSession.CONTROLS:
				host.set_control(slot, control, 1.0 if wanted.has(String(control)) else 0.0)
		if seconds > 0.0:
			await create_timer(seconds, true, false, false).timeout
	if script_text != "":
		host.release_controls()
		await process_frame

func _pc_step(pc: LauncherPcMode, step: String) -> void:
	var value := step.get_slice("=", 1) if step.contains("=") else ""
	match step.get_slice("=", 0):
		"view": pc.set_view(StringName(value))
		"layout": pc.set_layout(StringName(value))
		"sort": pc.set_sort(StringName(value))
		"category": pc.set_category(StringName(value))
		"genre": pc.set_genre(value)
		"tab": pc.set_tab(int(value))
		"locked": pc._detail.only_locked_toggled.emit()
		"select": pc.select(value)
		"query": pc.set_query(value)
		"search": pc.focus_search()
		"many": pc.set_entries(_many(int(value)))
		"width":
			pc.anchor_right = 0.0
			pc.offset_right = float(value)
		"hover": (pc._library.item(value) as LauncherPcControls.Clickable)._on_pointer(true)
		"zone":
			pc.focus_visible = true
			pc._enter_zone(StringName(value))
		"menu": pc.handle_action(LauncherInput.MENU)
		"sort_menu": pc.open_sort_menu()

## The catalog plus `count` copies of its games under new ids and numbered names, to see the PC library with more games than exist. The copies have no key art and cannot be started.
func _many(count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = LauncherCatalog.all().duplicate()
	var real := LauncherCatalog.all()
	for index in count:
		var copy: Dictionary = real[index % real.size()].duplicate(true)
		copy["id"] = "%s_%02d" % [copy["id"], index + 2]
		copy["name"] = {"zh": "%s %d" % [copy["name"]["zh"], index + 2], "en": "%s %d" % [copy["name"]["en"], index + 2]}
		out.append(copy)
	return out

func _run_step(shell: LauncherRoot, kind: String, value: String) -> void:
	match kind:
		"wait":
			await create_timer(value.to_float(), true, false, true).timeout
		"scale":
			Engine.time_scale = value.to_float()
		"press":
			Input.action_press(StringName("launcher_" + value))
		"release":
			Input.action_release(StringName("launcher_" + value))
		"cursor":
			var game := shell.current_screen() as LauncherGameScreen
			if game != null:
				game.cursor_at = Vector2(value.get_slice(":", 0).to_float(), value.get_slice(":", 1).to_float())
	await process_frame

func _env(name: String, fallback: String) -> String:
	var value := OS.get_environment(name)
	return value if value != "" else fallback
