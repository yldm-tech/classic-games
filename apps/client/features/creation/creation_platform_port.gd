class_name CreationPlatformPort
extends Node

signal document_imported(document: Dictionary)

const DesktopIntegrationScript := preload("res://platform/desktop_integration.gd")

var session: CreationSessionPort
var desktop: Node

func _init(p_session: CreationSessionPort) -> void:
	session = p_session
	if DesktopIntegrationScript.is_desktop():
		desktop = DesktopIntegrationScript.new()
		desktop.dsl_imported.connect(func(document: Dictionary) -> void: document_imported.emit(document))
		desktop.export_requested.connect(export_document)
		desktop.preview_requested.connect(preview_document)
		add_child(desktop)
		desktop.call_deferred("install_native_menu")

func request_import() -> bool:
	if desktop == null: return false
	desktop.call("show_import_dialog")
	return true

func export_document() -> bool:
	if desktop == null: return false
	desktop.call("show_export_dialog", session.current())
	return true

func preview_document() -> bool:
	if desktop == null: return false
	var runtime_ref: String = str(session.call("runtime_ref")) if session.has_method("runtime_ref") else ""
	desktop.call("open_preview_window", runtime_ref, session.current())
	return true
