class_name EmptyState
extends VBoxContainer

signal retry_requested

const Widgets:=preload("res://shell/design_system/components/widgets.gd")
const Tokens:=preload("res://shell/design_system/theme/tokens.gd")

func configure(message:String,theme_name:String,retry_label:String="",subtitle:String="")->void:
	_clear()
	alignment=BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation",Tokens.SPACE_3)
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var card:=Widgets.card(theme_name,&"surface_raised")
	card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var col:=Widgets.vbox(Tokens.SPACE_2)
	card.add_child(col)
	var label:=Widgets.body(message,theme_name,&"text_muted")
	label.name="EmptyMessage"
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(label)
	if subtitle!="":
		var sub:=Widgets.caption(subtitle,theme_name)
		sub.name="EmptySubtitle"
		sub.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(sub)
	add_child(card)
	if retry_label!="":
		var retry:=Widgets.secondary_button(retry_label,theme_name)
		retry.name="RetryButton"
		retry.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		retry.pressed.connect(func():retry_requested.emit())
		add_child(retry)

func _clear()->void:
	for child:Node in get_children():remove_child(child);child.free()
