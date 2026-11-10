class_name ConfirmSheet
extends VBoxContainer

signal confirmed
signal cancelled

const Widgets:=preload("res://shell/design_system/components/widgets.gd")
const Tokens:=preload("res://shell/design_system/theme/tokens.gd")
var _resolved:=false

func configure(title:String,description:String,confirm_label:String,cancel_label:String,theme_name:String)->void:
	_clear();_resolved=false
	var card:=Widgets.card(theme_name,&"tint_danger");var col:=Widgets.vbox(Tokens.SPACE_3);card.add_child(col);add_child(card)
	col.add_child(Widgets.heading(title,3,theme_name));col.add_child(Widgets.body(description,theme_name,&"text_secondary"))
	var confirm:=Widgets.danger_button(confirm_label,theme_name);confirm.name="ConfirmButton"
	var cancel:=Widgets.secondary_button(cancel_label,theme_name);cancel.name="CancelButton"
	confirm.pressed.connect(func():
		if _resolved:return
		_resolved=true;confirm.disabled=true;cancel.disabled=true;confirmed.emit())
	cancel.pressed.connect(func():
		if _resolved:return
		_resolved=true;confirm.disabled=true;cancel.disabled=true;cancelled.emit())
	col.add_child(confirm);col.add_child(cancel)

func set_pending(value:bool)->void:
	if not value:_resolved=false
	var confirm:=find_child("ConfirmButton",true,false) as Button;var cancel:=find_child("CancelButton",true,false) as Button
	if confirm!=null:confirm.disabled=value
	if cancel!=null:cancel.disabled=value

func _clear()->void:
	for child:Node in get_children():remove_child(child);child.free()
