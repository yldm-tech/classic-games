class_name AsyncContent
extends VBoxContainer

signal retry_requested

const EmptyStateScript:=preload("res://ui/patterns/empty_state.gd")
const Widgets:=preload("res://shell/design_system/components/widgets.gd")

var current_state:="ready"

func present(state:String,message:String,theme_name:String,retry_label:String="")->void:
	current_state=state;_clear();visible=state!="ready"
	if state=="ready":return
	if state=="loading":
		var indicator:=ProgressBar.new();indicator.name="LoadingIndicator";indicator.indeterminate=true;add_child(indicator)
		if message!="":add_child(Widgets.caption(message,theme_name,&"text_muted"))
		return
	var empty=EmptyStateScript.new();empty.configure(message,theme_name,retry_label);empty.retry_requested.connect(func():retry_requested.emit());add_child(empty)

func _clear()->void:
	for child:Node in get_children():remove_child(child);child.free()
