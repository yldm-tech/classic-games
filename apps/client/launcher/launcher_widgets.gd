class_name LauncherWidgets
extends RefCounted

## Small factories for the launcher's recurring building blocks: styled text, boxes, rules, the section header, and placement helpers. The interactive widgets (focus row, tab, glyph hint, art card, tile) are the classes in LauncherControls.
##
## Sizes follow LauncherTokens and the 1920x1080 canvas.

const T := preload("res://launcher/launcher_tokens.gd")

# ---- small factories ----

## A single-style text label. `latin` picks the Latin label face (wide-spaced caps, numbers); otherwise the CJK body face.
static func text(content: String, size: int, weight: int = 400, color: Color = T.FG, spacing: float = 0.0, latin: bool = false) -> Label:
	var label := Label.new()
	label.text = content
	label.label_settings = T.label_settings(size, weight, color, spacing, latin)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## Restyle a label made by text() without rebuilding it.
static func restyle(label: Label, weight: int, color: Color, spacing: float = 0.0, latin: bool = false) -> void:
	label.label_settings = T.label_settings(label.label_settings.font_size, weight, color, spacing, latin)

static func hbox(gap: float = 0.0) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", roundi(gap))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box

static func vbox(gap: float = 0.0) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", roundi(gap))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box

## A flat coloured rectangle, e.g. a 1px rule: rule(T.fg(T.A_RULE)).
static func rule(color: Color, thickness: float = 1.0, vertical: bool = false) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.custom_minimum_size = Vector2(thickness, 0) if vertical else Vector2(0, thickness)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

## Section header: a spaced title followed by a hairline that fills the rest of the row.
static func section_header(title: String) -> HBoxContainer:
	var row := hbox(16)
	var label := text(title, T.SIZE_BODY, 500, T.fg(0.85), 4)
	label.name = "Title"
	row.add_child(label)
	var line := rule(T.fg(T.A_RULE))
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(line)
	return row

## Place a control at an absolute canvas rectangle. Pass a zero size component to keep the control's own minimum on that axis.
static func place(control: Control, at: Vector2, extent: Vector2 = Vector2.ZERO) -> Control:
	control.position = at
	if extent != Vector2.ZERO:
		control.size = extent
	return control

static func fill(control: Control) -> Control:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return control

static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

static func ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		ignore_mouse(child)
