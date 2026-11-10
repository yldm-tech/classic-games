class_name DesktopIntegration
extends Node

## 桌面原生菜单、DSL 文件交换与独立 Runtime 预览窗口。

signal dsl_imported(dsl: Dictionary)
signal export_requested
signal preview_requested

const RuntimeLoaderScript := preload("res://runtime/runtime_loader.gd")
const FILE_FILTER := "*.classic-games.json ; Classic Games DSL"

var _native_menu := RID()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _native_menu.is_valid():
		NativeMenu.free_menu(_native_menu)
		_native_menu = RID()

static func is_desktop(platform_name: String = OS.get_name()) -> bool:
	return platform_name in ["macOS", "Windows", "Linux"]

static func menu_actions() -> Array[String]:
	return ["import_dsl", "export_dsl", "preview_window"]

func install_native_menu() -> bool:
	if not is_desktop() or DisplayServer.get_name() == "headless" or not NativeMenu.has_feature(NativeMenu.FEATURE_GLOBAL_MENU):
		return false
	var main := NativeMenu.get_system_menu(NativeMenu.MAIN_MENU_ID)
	if not main.is_valid():
		return false
	_native_menu = NativeMenu.create_menu()
	NativeMenu.add_item(_native_menu, "Import DSL…", _on_menu_action, Callable(), "import_dsl", KEY_MASK_CMD_OR_CTRL | KEY_O)
	NativeMenu.add_item(_native_menu, "Export DSL…", _on_menu_action, Callable(), "export_dsl", KEY_MASK_CMD_OR_CTRL | KEY_S)
	NativeMenu.add_separator(_native_menu)
	NativeMenu.add_item(_native_menu, "Open Preview Window", _on_menu_action, Callable(), "preview_window", KEY_MASK_CMD_OR_CTRL | KEY_P)
	NativeMenu.add_submenu_item(main, "Classic Games", _native_menu)
	return true

func _on_menu_action(tag: Variant) -> void:
	match str(tag):
		"import_dsl": show_import_dialog()
		"export_dsl": export_requested.emit()
		"preview_window": preview_requested.emit()

func save_dsl(path: String, value: Dictionary) -> bool:
	if value.is_empty() or path.strip_edges() == "":
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "  ", true))
	file.close()
	return true

func load_dsl(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is not Dictionary:
		return {}
	var meta: Variant = parsed.get("meta")
	if meta is not Dictionary or str(meta.get("runtime", "")) == "" or str(meta.get("runtime_version", "")) == "":
		return {}
	var required: Array = {
		"shooter":["player", "enemies", "stage"],
		"survivor":["hero", "weapon", "waves", "progression", "stage"],
		"tower_defense":["stage", "path", "towers", "placements", "waves"],
	}.get(str(meta.get("runtime", "")), [])
	if required.is_empty(): return {}
	for key: String in required:
		if not parsed.has(key): return {}
	return parsed

func show_import_dialog() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray([FILE_FILTER])
	dialog.file_selected.connect(func(path: String) -> void:
		var value := load_dsl(path)
		if not value.is_empty(): dsl_imported.emit(value)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.7)

func show_export_dialog(value: Dictionary) -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray([FILE_FILTER])
	dialog.current_file = "classic-games-mod.classic-games.json"
	dialog.file_selected.connect(func(path: String) -> void:
		save_dsl(path, value)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.7)

func open_preview_window(runtime_ref: String, dsl: Dictionary) -> Window:
	var loader := RuntimeLoaderScript.new()
	var runtime: Node2D = loader.load_from_dsl(runtime_ref, dsl)
	if runtime == null:
		return null
	var window := Window.new()
	window.title = "Classic Games Preview — %s" % runtime_ref
	window.size = Vector2i(960, 540)
	window.min_size = Vector2i(640, 360)
	window.close_requested.connect(window.queue_free)
	runtime.position = Vector2(480, 270)
	window.add_child(runtime)
	add_child(window)
	window.show()
	return window
