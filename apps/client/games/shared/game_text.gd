class_name GameText
extends RefCounted

## Text for a game module. The repository ships no font files, so text is set in a system face: the same families the launcher uses, CJK first, with the system's fallback for anything they lack. One GameText per game, created once and kept (a CJK font file is tens of megabytes; never build one per frame):
##
##   var text := GameText.new()
##   func _draw() -> void:
##       text.draw(self, Vector2(240, 40), "第 3 关" if locale == "zh" else "STAGE 3", 14, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
##
## Sizes are in stage pixels. On a stage that is not pixel art the glyphs are rasterised at the resolution of the canvas (a size of 14 on a 480x270 stage is 56 canvas pixels tall and exactly as smooth as the launcher's own text). On a pixel-art stage text is enlarged with the stage into blocks; that is the look of that mode.

const CJK_FAMILIES: PackedStringArray = ["Noto Sans SC", "Noto Sans CJK SC", "Source Han Sans SC", "PingFang SC", "Microsoft YaHei", "sans-serif"]
const LATIN_FAMILIES: PackedStringArray = ["Inter", "SF Pro Text", "SF Pro", "Helvetica Neue", "Segoe UI", "sans-serif"]

var _fonts: Dictionary = {}

## The font of a weight (CSS weights: 400 regular, 600 semibold, 800 heavy). `latin` puts the Latin families first, for digits and English display text.
func font(weight: int = 600, latin: bool = false) -> Font:
	var key := "%s:%d" % ["latin" if latin else "cjk", weight]
	if _fonts.has(key):
		return _fonts[key]
	var face := SystemFont.new()
	face.font_names = (LATIN_FAMILIES + CJK_FAMILIES) if latin else CJK_FAMILIES
	face.font_weight = weight
	face.allow_system_fallback = true
	face.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	face.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	_fonts[key] = face
	return face

## Draw one line with its baseline at `at`. Call it from the _draw() of `canvas`. Without a `width` the text is aligned on the point itself: it starts there, is centred on it or ends there. With a `width` it is aligned inside the box that starts at `at` and is that wide, as CanvasItem.draw_string does. An `outline` in stage pixels is drawn first, under the text. Font sizes are whole numbers, so `size` is rounded.
func draw(canvas: CanvasItem, at: Vector2, text: String, size: float, color: Color = Color.WHITE, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, weight: int = 600, outline: float = 0.0, outline_color: Color = Color.BLACK) -> void:
	var face := font(weight)
	var whole := maxi(1, roundi(size))
	var origin := at
	if width <= 0.0 and align != HORIZONTAL_ALIGNMENT_LEFT:
		var extent := face.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, whole).x
		origin.x -= extent * (0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else 1.0)
		align = HORIZONTAL_ALIGNMENT_LEFT
	if outline > 0.0:
		canvas.draw_string_outline(face, origin, text, align, width, whole, maxi(1, roundi(outline * 2.0)), outline_color)
	canvas.draw_string(face, origin, text, align, width, whole, color)

## Size of a line of text in stage pixels.
func measure(text: String, size: float, weight: int = 600) -> Vector2:
	return font(weight).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, maxi(1, roundi(size)))
