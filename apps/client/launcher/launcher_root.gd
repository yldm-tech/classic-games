class_name LauncherRoot
extends Control

## The console launcher's shell and composition root: backdrop layers, the game stage, the screen registry and switching, the top navigation with its clock, the toast, and input routing. It is the main scene (launcher/launcher.tscn).
##
## Screens are LauncherScreen subclasses registered by id in SCREENS (or with register_screen before the id is first shown). Everything a screen needs from the shell is on this object: store, locale and t()/tf(), go()/go_back(), toast(), refresh_backdrop(), game_host and now().
## The launcher is fully local: it reads and writes LauncherStore and starts games through LauncherGameHost. It makes no network calls.

signal screen_changed(id: StringName)
signal mode_changed(mode: StringName)

const T := preload("res://launcher/launcher_tokens.gd")
const W := preload("res://launcher/launcher_widgets.gd")
const C := preload("res://launcher/launcher_controls.gd")
const In := preload("res://launcher/launcher_input.gd")
const Strings := preload("res://i18n/strings.gd")

const HOME_SCREEN := "res://launcher/home_screen.gd"
const GAME_SCREEN := "res://launcher/game_screen.gd"
const SETTINGS_SCREEN := "res://launcher/settings_screen.gd"
const UNAVAILABLE_SCREEN := "res://launcher/unavailable_screen.gd"

const HOME := &"home"
const LIBRARY := &"library"
const ACHIEVEMENTS := &"achievements"
const SETTINGS := &"settings"
const MENU := &"menu"
const GAME := &"game"
const PAUSE := &"pause"

## Screen id -> script path. A screen that is not built yet is served by the unavailable screen, which says so; point its entry at the real script when that screen lands. Paths rather than preloads, because every screen script refers back to LauncherRoot.
const SCREENS := {
	HOME: HOME_SCREEN,
	LIBRARY: UNAVAILABLE_SCREEN,
	ACHIEVEMENTS: UNAVAILABLE_SCREEN,
	SETTINGS: SETTINGS_SCREEN,
	MENU: UNAVAILABLE_SCREEN,
	GAME: GAME_SCREEN,
	PAUSE: UNAVAILABLE_SCREEN,
}
## The top-level tabs, in order. LB/RB and LT/RT cycle through these.
const NAV_TABS: Array[StringName] = [HOME, LIBRARY, ACHIEVEMENTS, SETTINGS]

const MODE_CONSOLE := &"console"
const MODE_PC := &"pc"
## Seconds the View button must be held to toggle PC mode.
const VIEW_HOLD_SECONDS := 0.8
## Where the hero key art starts; the left part of the canvas stays clear for text.
const HERO_ART_LEFT := 300.0

## Inject before the node enters the tree to use a different file (tests do); otherwise the default user:// store is loaded.
var store: LauncherStore
var game_host: LauncherGameHost
var locale := Strings.DEFAULT_LOCALE
var mode := MODE_CONSOLE
## Returns the current unix time. Tests replace it to fix the clock.
var now_provider := func() -> int: return int(Time.get_unix_time_from_system())

var _registry: Dictionary = SCREENS.duplicate()
var _instances: Dictionary = {}
var _current: LauncherScreen
var _history: Array[StringName] = []
var _screen_tween: Tween
var _backdrop_tween: Tween
var _hero_art: LauncherKeyArt
var _blur_art: LauncherKeyArt
var _blur_viewport: SubViewport
var _blur_rect: TextureRect
var _screens: Control
var _nav: Control
var _overlays: Control
var _overlay: Control
var _nav_tabs: Dictionary = {}
var _clock_label: Label
var _gamepad_icon: Control
var _toast: PanelContainer
var _toast_label: Label
var _toast_undo: LauncherControls.Pressable
var _toast_timer: Timer
var _undo: Callable
var _pc_script: GDScript
var _pc_node: Control
var _console_layers: Array[Control] = []
var _axis_held: Dictionary = {}
var _view_held := -1.0
## The direction a gamepad is holding (&"" for none) and the seconds until it fires again.
var _repeat_action := &""
var _repeat_wait := 0.0

func _ready() -> void:
	name = "LauncherRoot"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if store == null:
		store = LauncherStore.new()
		store.load_from_disk()
	locale = _stored_locale()
	In.apply_bindings(store.bindings())
	LauncherSettings.apply_all(store, LauncherSettings.drives_window(self))
	_build_layers()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	go(HOME)

func _exit_tree() -> void:
	if Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.disconnect(_on_joy_connection_changed)
	T.release_fonts()

# ---- services for screens ----

func t(key: String) -> String:
	return str(Strings.t(locale, key))

func tf(key: String, args: Array) -> String:
	return Strings.fmt(locale, key, args)

func now() -> int:
	return now_provider.call()

## Change the interface language ("zh" or "en"), remember it, and rebuild every screen in it.
func set_locale(value: String) -> void:
	if value == locale or not value in Strings.LOCALES:
		return
	locale = value
	store.set_setting("lang", value)
	var shown := current_id()
	if _current != null:
		_current.on_exit()
		_current = null
	for id in _instances:
		(_instances[id] as Node).queue_free()
	_instances.clear()
	_build_nav()
	_show(shown, {}, false)

func _stored_locale() -> String:
	var stored := str(store.setting("lang", Strings.DEFAULT_LOCALE))
	return stored if stored in Strings.LOCALES else Strings.DEFAULT_LOCALE

# ---- screens ----

## Register or replace the script behind a screen id. Call before that id is first shown.
func register_screen(id: StringName, script: GDScript) -> void:
	_registry[id] = script
	if _instances.has(id) and _instances[id] != _current:
		(_instances[id] as Node).queue_free()
		_instances.erase(id)

## The instance of a screen, created on first use.
func screen(id: StringName) -> LauncherScreen:
	if not _instances.has(id):
		var source: Variant = _registry[id]
		var script: GDScript = source if source is GDScript else load(str(source))
		var instance: LauncherScreen = script.new()
		instance.visible = false
		_screens.add_child(instance)
		instance.setup(self, id)
		_instances[id] = instance
	return _instances[id]

func current_id() -> StringName:
	return _current.screen_id if _current != null else &""

func current_screen() -> LauncherScreen:
	return _current

## Show a screen. `args` goes to its on_enter. Going to a top-level tab clears the back history; going anywhere else remembers where you came from for go_back().
func go(id: StringName, args: Dictionary = {}) -> void:
	if not _registry.has(id):
		push_error("launcher: unknown screen %s" % id)
		return
	if id in NAV_TABS:
		_history.clear()
	elif _current != null and _current.screen_id != id:
		_history.append(_current.screen_id)
	_show(id, args, true)

## Return to the screen this one was opened from, or to Home when there is none.
func go_back() -> void:
	var target := HOME
	if not _history.is_empty():
		target = _history.pop_back()
	if target in NAV_TABS:
		_history.clear()
	_show(target, {}, true)

func _show(id: StringName, args: Dictionary, animate: bool) -> void:
	var next := screen(id)
	if _current != null and _current != next:
		_current.on_exit()
		_current.visible = false
	hide_overlay()
	_current = next
	next.visible = true
	next.on_enter(args)
	if _screen_tween != null:
		_screen_tween.kill()
	if animate:
		next.modulate.a = 0.0
		_screen_tween = create_tween()
		_screen_tween.tween_property(next, "modulate:a", 1.0, T.FADE_SCREEN).set_ease(Tween.EASE_OUT)
	else:
		next.modulate.a = 1.0
	_sync_nav()
	refresh_backdrop()
	screen_changed.emit(id)

func _cycle_tab(step: int) -> void:
	var index := maxi(0, NAV_TABS.find(current_id()))
	go(NAV_TABS[posmod(index + step, NAV_TABS.size())])

# ---- overlay ----

## Mount a modal layer (a side panel, a dialog) above the screens and the top navigation, so it can dim and cover both. One at a time: showing another replaces it, and changing screen removes it. The screen that opened it still receives every action and decides what they do while it is open.
func show_overlay(overlay: Control) -> void:
	hide_overlay()
	_overlay = overlay
	_overlays.add_child(W.fill(overlay))

func hide_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlays.remove_child(_overlay)
		_overlay.queue_free()
	_overlay = null

func has_overlay() -> bool:
	return is_instance_valid(_overlay)

# ---- backdrop ----

## Re-read the current screen's backdrop() and cross-fade the layers to match.
func refresh_backdrop() -> void:
	var wanted: Dictionary = _current.backdrop() if _current != null and mode == MODE_CONSOLE else {"layer": &"none", "game": ""}
	var layer: StringName = wanted.get("layer", &"none")
	var game := str(wanted.get("game", ""))
	if layer == &"hero" and _hero_art.game_id != game:
		_hero_art.game_id = game
		_hero_art.modulate.a = minf(_hero_art.modulate.a, 0.35)
	if layer == &"blur" and _blur_art.game_id != game:
		_blur_art.game_id = game
		_blur_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	game_host.visible = layer == &"game"
	if _backdrop_tween != null:
		_backdrop_tween.kill()
	_backdrop_tween = create_tween().set_parallel(true)
	_backdrop_tween.tween_property(_hero_art, "modulate:a", 1.0 if layer == &"hero" else 0.0, T.FADE_BACKDROP)
	_backdrop_tween.tween_property(_blur_rect, "modulate:a", 1.0 if layer == &"blur" else 0.0, T.FADE_BACKDROP)

## The layer currently requested by the screen, for tests and screens that care.
func backdrop_layer() -> StringName:
	return (_current.backdrop() as Dictionary).get("layer", &"none") if _current != null else &"none"

# ---- toast ----

## Show a message for a few seconds. With `undo`, the toast offers an undo button (also the X button while it is visible) that calls it.
func toast(message: String, undo: Callable = Callable()) -> void:
	_undo = undo
	_toast_label.text = message
	_toast_undo.visible = undo.is_valid()
	_toast.visible = true
	_toast.reset_size()
	_toast.position = Vector2((T.CANVAS.x - _toast.size.x) / 2.0, 120.0)
	_toast_timer.start(T.TOAST_SECONDS)

func dismiss_toast() -> void:
	_toast.visible = false
	_undo = Callable()
	_toast_timer.stop()

func toast_text() -> String:
	return _toast_label.text if _toast.visible else ""

func can_undo() -> bool:
	return _toast.visible and _undo.is_valid()

## Run the pending undo, if any, and close the toast.
func undo() -> void:
	var action := _undo
	dismiss_toast()
	if action.is_valid():
		action.call()

# ---- PC mode hook ----

## Register the PC-mode root (a Control script). It is instantiated the first time PC mode is entered, receives `shell` through a `setup(shell: LauncherRoot)` method when it has one, and gets every action through `handle_action(action) -> bool` while PC mode is on.
func register_pc_mode(script: GDScript) -> void:
	_pc_script = script

## Switch between console and PC mode (F11, or holding View). Until a PC mode is registered this only says that it is not available.
func toggle_pc_mode() -> void:
	if _pc_script == null:
		toast(t("launcher.pc_mode.unavailable"))
		return
	mode = MODE_PC if mode == MODE_CONSOLE else MODE_CONSOLE
	if mode == MODE_PC and _pc_node == null:
		_pc_node = _pc_script.new()
		_pc_node.name = "PcMode"
		add_child(_pc_node)
		move_child(_pc_node, _toast.get_index())
		if _pc_node.has_method("setup"):
			_pc_node.call("setup", self)
	if _pc_node != null:
		_pc_node.visible = mode == MODE_PC
	for layer in _console_layers:
		layer.visible = mode == MODE_CONSOLE
	_sync_nav()
	refresh_backdrop()
	mode_changed.emit(mode)

# ---- input ----

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		_route_axis(event)
		return
	var action := In.pressed_action(event)
	if action != &"":
		get_viewport().set_input_as_handled()
		if action == In.VIEW:
			_view_held = 0.0
		if event is InputEventJoypadButton:
			_start_repeat(action)
		dispatch(action)
	else:
		var released := In.released_action(event)
		if released == In.VIEW:
			_view_held = -1.0
		if event is InputEventJoypadButton:
			_stop_repeat(released)

## A stick or trigger counts as one press when it crosses the deadzone, not once per motion event.
func _route_axis(event: InputEventJoypadMotion) -> void:
	# Matched by axis alone (no exact match): an exact match also compares the sign, and a stick that settles on exactly 0 has the sign of the positive direction only, so Up and Left would never be seen to be released.
	for action in In.ALL:
		if not InputMap.event_is_action(event, action, false):
			continue
		var held := event.is_action_pressed(action, true, false)
		if held and not _axis_held.get(action, false):
			_axis_held[action] = true
			_start_repeat(action)
			dispatch(action)
		elif not held and _axis_held.get(action, false):
			_axis_held[action] = false
			_stop_repeat(action)

## A direction pressed on the d-pad or a stick starts repeating after In.REPEAT_DELAY; _process fires it every In.REPEAT_INTERVAL until it is released. Keyboard keys repeat through the OS's own echo events instead.
func _start_repeat(action: StringName) -> void:
	if action in In.REPEATING:
		_repeat_action = action
		_repeat_wait = In.REPEAT_DELAY

func _stop_repeat(action: StringName) -> void:
	if action == _repeat_action:
		_repeat_action = &""

func _notification(what: int) -> void:
	# A release that happens while the window is not focused never arrives, so a held direction must not keep firing.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_repeat_action = &""

func _process(delta: float) -> void:
	if _view_held >= 0.0:
		_view_held += delta
		if _view_held >= VIEW_HOLD_SECONDS:
			_view_held = -1.0
			toggle_pc_mode()
	if _repeat_action != &"":
		_repeat_wait -= delta
		# At most one repeat per frame, so a long frame cannot turn into a burst of moves.
		if _repeat_wait <= 0.0:
			_repeat_wait = In.REPEAT_INTERVAL
			dispatch(_repeat_action)

## The single entry point for input: every key, gamepad press and footer-hint click arrives here as a LauncherInput action. Order: PC-mode toggle, PC mode's own handler, toast undo, the current screen, then the shell defaults (tab switching and back).
func dispatch(action: StringName) -> void:
	if action == In.PC_MODE:
		toggle_pc_mode()
		return
	if mode == MODE_PC:
		if _pc_node != null and _pc_node.has_method("handle_action"):
			_pc_node.call("handle_action", action)
		return
	if action == In.X and can_undo():
		undo()
		return
	if _current == null or _current.handle_action(action):
		return
	match action:
		In.LB, In.LT:
			if _current.shows_nav():
				_cycle_tab(-1)
		In.RB, In.RT:
			if _current.shows_nav():
				_cycle_tab(1)
		In.BACK:
			if current_id() != HOME:
				go_back()

# ---- construction ----

func _build_layers() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.color = T.BG
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(W.fill(background))

	_hero_art = LauncherKeyArt.new()
	_hero_art.name = "HeroArt"
	_hero_art.position = Vector2(HERO_ART_LEFT, 0)
	_hero_art.size = Vector2(T.CANVAS.x - HERO_ART_LEFT, T.CANVAS.y)
	_hero_art.modulate.a = 0.0
	add_child(_hero_art)

	# Blur layer: the key art rendered small and blown up four times, then softened, as the backdrop of the list-like screens.
	_blur_viewport = SubViewport.new()
	_blur_viewport.name = "BlurViewport"
	_blur_viewport.size = Vector2i(520, 310)
	_blur_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_blur_viewport)
	_blur_art = LauncherKeyArt.new()
	_blur_art.size = Vector2(520, 310)
	_blur_viewport.add_child(_blur_art)
	_blur_rect = TextureRect.new()
	_blur_rect.name = "BlurArt"
	_blur_rect.texture = _blur_viewport.get_texture()
	_blur_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_blur_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_blur_rect.position = Vector2(-80, -80)
	_blur_rect.size = Vector2(2080, 1240)
	_blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur_rect.modulate.a = 0.0
	_blur_rect.material = _blur_material()
	add_child(_blur_rect)

	game_host = LauncherGameHost.new()
	game_host.store = store
	game_host.now_provider = func() -> int: return now()
	game_host.visible = false
	add_child(game_host)

	_screens = Control.new()
	_screens.name = "Screens"
	_screens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(W.fill(_screens))

	_nav = Control.new()
	_nav.name = "Nav"
	_nav.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(W.fill(_nav))
	_build_nav()

	_overlays = Control.new()
	_overlays.name = "Overlays"
	_overlays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(W.fill(_overlays))

	_console_layers = [_hero_art, _blur_rect, _screens, _nav, _overlays]
	_build_toast()

	var clock := Timer.new()
	clock.name = "Clock"
	clock.wait_time = 1.0
	clock.autostart = true
	clock.timeout.connect(_tick_clock)
	add_child(clock)

func _blur_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
// 6 source pixels of blur on the 520x310 key art, slightly desaturated (the design's blur(6px) saturate(.9) before the 4x scale).
void fragment() {
	vec3 sum = vec3(0.0);
	float total = 0.0;
	for (int x = -4; x <= 4; x++) {
		for (int y = -4; y <= 4; y++) {
			vec2 offset = vec2(float(x), float(y)) * 1.5;
			float weight = exp(-dot(offset, offset) / 36.0);
			sum += texture(TEXTURE, UV + offset * TEXTURE_PIXEL_SIZE).rgb * weight;
			total += weight;
		}
	}
	vec3 color = sum / total;
	float grey = dot(color, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(vec3(grey), color, 0.9), COLOR.a);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material

func _build_nav() -> void:
	W.clear(_nav)
	_nav_tabs.clear()
	var header := W.hbox(40)
	header.name = "Header"
	header.position = Vector2(T.MARGIN, T.NAV_TOP)
	header.size = Vector2(T.CANVAS.x - T.MARGIN * 2.0, T.NAV_HEIGHT)
	_nav.add_child(header)

	var brand := C.Pressable.new()
	brand.name = "Brand"
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var brand_row := W.hbox(14)
	brand.add_child(brand_row)
	brand_row.add_child(W.text(t("launcher.brand"), T.SIZE_BRAND, 900, T.FG, 6))
	var latin := W.text(t("launcher.brand_latin"), T.SIZE_MICRO, 600, T.fg(T.A_MUTED), 4, true)
	latin.size_flags_vertical = Control.SIZE_SHRINK_END
	var latin_lift := MarginContainer.new()
	latin_lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	latin_lift.add_theme_constant_override("margin_bottom", 5)
	latin_lift.add_child(latin)
	brand_row.add_child(latin_lift)
	brand.activated.connect(func() -> void: go(HOME))
	header.add_child(brand)

	var tabs := W.hbox(6)
	tabs.name = "Tabs"
	header.add_child(tabs)
	tabs.add_child(_nav_glyph(In.LT, 0, 10, -1))
	for id in NAV_TABS:
		var tab := C.Tab.new(t("launcher.nav.%s" % id))
		tab.name = "Tab_%s" % id
		tab.activated.connect(func() -> void: go(id))
		tabs.add_child(tab)
		_nav_tabs[id] = tab
	tabs.add_child(_nav_glyph(In.RT, 10, 0, 1))

	var right := W.hbox(22)
	right.name = "Status"
	right.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	header.add_child(right)
	var pc := _PcButton.new()
	pc.name = "PcModeButton"
	pc.tooltip_text = t("launcher.nav.pc_mode")
	pc.activated.connect(toggle_pc_mode)
	right.add_child(pc)
	var separator := W.rule(T.fg(0.25), 1.0, true)
	separator.custom_minimum_size = Vector2(1, 20)
	separator.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_child(separator)
	_gamepad_icon = C.Icon.new("gamepad", 22.0, T.fg(0.85))
	_gamepad_icon.name = "Gamepad"
	right.add_child(_gamepad_icon)
	_clock_label = W.text("", T.SIZE_BODY, 500, T.fg(0.85), 0, true)
	_clock_label.name = "ClockLabel"
	_clock_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_child(_clock_label)
	_tick_clock()
	_on_joy_connection_changed(0, false)
	_sync_nav()

func _nav_glyph(action: StringName, left: int, right: int, step: int) -> Control:
	var button := C.Pressable.new()
	button.name = "Glyph_%s" % String(action).trim_prefix("launcher_")
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_constant_override("margin_left", left)
	button.add_theme_constant_override("margin_right", right)
	button.add_child(C.Glyph.new(action))
	button.activated.connect(func() -> void: _cycle_tab(step))
	return button

func _sync_nav() -> void:
	if _nav == null:
		return
	_nav.visible = mode == MODE_CONSOLE and _current != null and _current.shows_nav()
	for id in _nav_tabs:
		(_nav_tabs[id] as LauncherControls.Tab).set_selected(id == current_id())

func _tick_clock() -> void:
	var time := Time.get_time_dict_from_system()
	_clock_label.text = LauncherSettings.clock_text(int(time["hour"]), int(time["minute"]), bool(LauncherSettings.value(store, LauncherSettings.CLOCK_24H)), locale)

func clock_text() -> String:
	return _clock_label.text

## Redraw the clock now, e.g. after the 12/24-hour setting changed.
func refresh_clock() -> void:
	_tick_clock()

func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_repeat_action = &""
	var count := Input.get_connected_joypads().size()
	_gamepad_icon.visible = count > 0
	_gamepad_icon.tooltip_text = tf("launcher.nav.gamepads_fmt", [count])

func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.name = "Toast"
	_toast.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = T.TOAST_BG
	style.border_color = T.fg(0.2)
	style.set_border_width_all(1)
	style.set_corner_radius_all(roundi(T.RADIUS))
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 50
	style.shadow_offset = Vector2(0, 20)
	style.content_margin_left = 24
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	_toast.add_theme_stylebox_override("panel", style)
	add_child(_toast)
	var row := W.hbox(20)
	_toast.add_child(row)
	_toast_label = W.text("", T.SIZE_TOAST, 400, T.FG, 1)
	_toast_label.name = "Message"
	_toast_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_toast_label)
	_toast_undo = _UndoButton.new(t("launcher.common.undo"))
	_toast_undo.name = "Undo"
	_toast_undo.activated.connect(undo)
	row.add_child(_toast_undo)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(dismiss_toast)
	add_child(_toast_timer)

## Round outlined button with the monitor icon, top right of the navigation.
class _PcButton:
	extends LauncherControls.Pressable

	func _init() -> void:
		super()
		custom_minimum_size = Vector2(44, 44)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var icon := LauncherControls.Icon.new("monitor", 20.0)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		add_child(icon)

	func _draw() -> void:
		draw_arc(size / 2.0, 21.5, 0.0, TAU, 64, LauncherTokens.fg(0.3), 1.0, true)

## Outlined toast button: the X glyph and the word "undo".
class _UndoButton:
	extends LauncherControls.Pressable

	func _init(caption: String) -> void:
		super()
		custom_minimum_size = Vector2(0, 36)
		set_padding(10, 0, 14, 0)
		var row := LauncherWidgets.hbox(8)
		add_child(row)
		row.add_child(LauncherControls.Glyph.new(LauncherInput.X))
		var label := LauncherWidgets.text(caption, LauncherTokens.SIZE_SUB)
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label)

	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0)
		box.border_color = LauncherTokens.fg(0.5)
		box.set_border_width_all(1)
		box.set_corner_radius_all(roundi(LauncherTokens.RADIUS))
		draw_style_box(box, Rect2(Vector2.ZERO, size))
