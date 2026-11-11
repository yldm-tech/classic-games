extends SceneTree

## Renders one launcher screen to a PNG at exactly 1920x1080 for visual checks. It needs a real renderer, so it is not part of `make ci`; run it through scripts/run-launcher-shot.sh.
##
## Environment:
##   LAUNCHER_SHOT_DIR      output directory (required)
##   LAUNCHER_SHOT_SCREEN   screen id to show, default "home"
##   LAUNCHER_SHOT_STATE    "played" (default) starts from a throwaway profile with a few recorded runs so the shelf, records and progress are populated; "fresh" starts from an empty profile
##   LAUNCHER_SHOT_ACTIONS  comma-separated LauncherInput action names without the "launcher_" prefix, dispatched in order before the capture (e.g. "down,menu")
##   LAUNCHER_SHOT_LOCALE   "zh" (default) or "en"
##   LAUNCHER_SHOT_NAME     file name without extension, default "<screen>-<state>"
##   LAUNCHER_SHOT_GAME     catalog game id passed to the screen as { "game": id }, default "shooter"
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

	var viewport := SubViewport.new()
	viewport.size = Vector2i(LauncherTokens.CANVAS)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var shell: LauncherRoot = (load(RootScene) as PackedScene).instantiate()
	shell.store = store
	viewport.add_child(shell)
	await process_frame
	(shell.screen(LauncherRoot.GAME) as LauncherGameScreen).pause_on_focus_loss = false
	if screen_id != "home":
		shell.go(StringName(screen_id), {"game": _env("LAUNCHER_SHOT_GAME", "shooter")})
	for action in _env("LAUNCHER_SHOT_ACTIONS", "").split(",", false):
		var step := action.strip_edges()
		if step.contains("="):
			await _run_step(shell, step.get_slice("=", 0), step.get_slice("=", 1))
			continue
		shell.dispatch(StringName("launcher_" + step))
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
	if saved != OK:
		push_error("could not write %s" % path)
		quit(1)
		return
	print("launcher_shot: wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])
	quit(0)

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
