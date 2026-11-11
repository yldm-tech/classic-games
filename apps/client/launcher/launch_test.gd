extends SceneTree

## Boots the project's configured main scene, waits for it to be ready, and checks that it is the assembled launcher. It uses its own profile file so it never reads or moves the player's real one.

const STORE_PATH := "user://launch-test.json"

func _initialize() -> void:
	var main_scene := str(ProjectSettings.get_setting("application/run/main_scene"))
	var packed: PackedScene = load(main_scene)
	var main := packed.instantiate()
	if main is LauncherRoot:
		(main as LauncherRoot).store = LauncherStore.new(STORE_PATH)
	root.add_child(main)
	if not main.is_node_ready():
		await main.ready
	_verify.call_deferred(main)

func _verify(main: Node) -> void:
	var shell := main as LauncherRoot
	var assembled := shell != null and shell.store != null and shell.game_host != null and shell.current_id() == LauncherRoot.HOME and shell.current_screen() is LauncherHomeScreen
	main.free()
	if FileAccess.file_exists(STORE_PATH):
		DirAccess.remove_absolute(STORE_PATH)
	if not assembled:
		push_error("main scene did not assemble the launcher")
		quit(1)
		return
	print("launch_test: 1 passed, 0 failed")
	quit(0)
