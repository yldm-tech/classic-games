class_name LauncherScreen
extends Control

## Base class of every launcher screen (home, library, achievements, settings, menu, game, pause).
##
## Lifecycle: LauncherRoot creates one instance per screen id the first time it is shown, calls setup() once (which calls build()), then on_enter(args) every time the screen becomes current and on_exit() when it stops being current. Instances are kept, so a screen keeps its state between visits and must refresh what it shows in on_enter.
##
## Input: a screen never reads InputEvents. LauncherRoot turns every key and gamepad press into a LauncherInput action name and calls handle_action; return true when the screen used it. What a screen leaves unhandled falls back to the shell: LB/RB/LT/RT switch the top-level tab and B goes back.
##
## Focus: the screen owns its focus state (an index, a zone name) and restyles its widgets with set_focused / set_selected. Mouse hover moves that same focus and a click activates, by connecting the widgets' `hovered` and `activated` signals.
##
## Footer: set_footer([[action, caption], ...]) draws the glyph hints. Clicking a hint calls handle_action with its action, so the hint and the real button cannot drift apart.

const T := preload("res://launcher/launcher_tokens.gd")
const W := preload("res://launcher/launcher_widgets.gd")
const C := preload("res://launcher/launcher_controls.gd")
const In := preload("res://launcher/launcher_input.gd")

var shell: LauncherRoot
var screen_id: StringName

var _footer: HBoxContainer

func setup(p_shell: LauncherRoot, p_id: StringName) -> void:
	shell = p_shell
	screen_id = p_id
	name = String(p_id).capitalize().replace(" ", "") + "Screen"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build()

## Create the screen's nodes. Called once.
func build() -> void:
	pass

## The screen became current. `args` is whatever the caller passed to LauncherRoot.go.
func on_enter(_args: Dictionary) -> void:
	pass

## The screen stopped being current.
func on_exit() -> void:
	pass

## Handle one LauncherInput action. Return true when it was used.
func handle_action(_action: StringName) -> bool:
	return false

## Whether the top navigation (brand, tabs, clock) is shown over this screen.
func shows_nav() -> bool:
	return true

## What the shell draws behind this screen: { "layer": &"hero" | &"blur" | &"game" | &"none", "game": game id }.
## "hero" is the game's key art filling the canvas from x = 300, "blur" the same art blown up and blurred, "game" the live game stage. Call shell.refresh_backdrop() after the answer changes.
func backdrop() -> Dictionary:
	return {"layer": &"none", "game": ""}

func t(key: String) -> String:
	return shell.t(key)

func tf(key: String, args: Array) -> String:
	return shell.tf(key, args)

## Replace the footer hints. Each hint is [action, caption]; they are laid out right-aligned on the footer line in the given order.
func set_footer(hints: Array) -> void:
	if _footer == null:
		_footer = W.hbox(12)
		_footer.name = "Footer"
		_footer.alignment = BoxContainer.ALIGNMENT_END
		_footer.position = Vector2(T.MARGIN, T.CANVAS.y - T.FOOTER_BOTTOM - T.FOOTER_HEIGHT)
		_footer.size = Vector2(T.CANVAS.x - T.MARGIN * 2.0, T.FOOTER_HEIGHT)
		add_child(_footer)
	W.clear(_footer)
	for hint: Array in hints:
		var action: StringName = hint[0]
		var widget := C.GlyphHint.new(action, str(hint[1]))
		widget.name = "Hint_" + String(action).trim_prefix("launcher_")
		widget.activated.connect(func() -> void: shell.dispatch(action))
		_footer.add_child(widget)

## Captions of the current footer hints, in order.
func footer_captions() -> PackedStringArray:
	var out := PackedStringArray()
	if _footer != null:
		for hint in _footer.get_children():
			out.append((hint as LauncherControls.GlyphHint).caption())
	return out
