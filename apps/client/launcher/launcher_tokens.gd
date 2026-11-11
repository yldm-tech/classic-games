class_name LauncherTokens
extends RefCounted

## Design tokens of the console launcher. Every number here is authored for the fixed 1920x1080 canvas (project.godot scales it with canvas_items), so screens position things in canvas pixels and never read the window size.

const CANVAS := Vector2(1920, 1080)

# ---- colour ----

const BG := Color("05070D")
const FG := Color("F4F5F8")
## Scrim base used by the gradients that sit between key art and text.
const DEEP := Color(3.0 / 255.0, 4.0 / 255.0, 8.0 / 255.0)
const PANEL := Color("0A0C14")
const CARD_BG := Color("0B0E16")
const TOAST_BG := Color(12.0 / 255.0, 14.0 / 255.0, 22.0 / 255.0, 0.95)
const FAVORITE := Color("FF6B7A")
const DANGER := Color("FF6B7A")
const DIALOG_BG := Color("0C0E16")

## Foreground alpha steps. Use these names instead of ad-hoc alphas so the hierarchy stays the same on every screen.
const A_STRONG := 0.9
const A_BODY := 0.75
const A_MUTED := 0.6
const A_FAINT := 0.55
const A_RULE := 0.18
const A_HAIRLINE := 0.12
## Unfocused row label and unfocused row caption.
const A_ROW_IDLE := 0.62
const A_SUB_IDLE := 0.4
## Start alpha of the focused-row gradient (it fades to 0 on the right).
const A_FOCUS_FILL := 0.16

static func fg(alpha: float = 1.0) -> Color:
	return Color(FG.r, FG.g, FG.b, alpha)

static func deep(alpha: float = 1.0) -> Color:
	return Color(DEEP.r, DEEP.g, DEEP.b, alpha)

static func bg(alpha: float = 1.0) -> Color:
	return Color(BG.r, BG.g, BG.b, alpha)

# ---- spacing and shape ----

const MARGIN := 120.0
const RADIUS := 4.0
const NAV_TOP := 40.0
const NAV_HEIGHT := 56.0
const FOOTER_BOTTOM := 32.0
const FOOTER_HEIGHT := 44.0
const FOCUS_BAR := 4.0
const TAB_UNDERLINE := 3.0
const ROW_HEIGHT := 60.0
const ROW_PADDING := 24.0
const GLYPH_SIZE := 28.0
const CARD_SIZE := Vector2(240, 135)
const CARD_SIZE_SELECTED := Vector2(336, 189)
const CARD_RING := 3.0
const CARD_RING_OFFSET := 3.0
const SIDE_PANEL_WIDTH := 560.0
## Settings rows, the modal dialog and its buttons.
const SETTING_ROW_HEIGHT := 72.0
const SWITCH_SIZE := Vector2(56, 30)
const SEGMENT_SIZE := Vector2(22, 10)
const BUTTON_HEIGHT := 44.0
const DIALOG_WIDTH := 640.0
const DIALOG_BUTTON_HEIGHT := 52.0

# ---- motion ----

const FADE_SCREEN := 0.3
const FADE_BACKDROP := 0.4
const FADE_ROW := 0.15
const RESIZE_CARD := 0.25
const TOAST_SECONDS := 3.0

# ---- type ----

## Font sizes of the recurring text roles.
const SIZE_HERO := 128
const SIZE_PANEL_TITLE := 40
const SIZE_ROW := 26
const SIZE_PANEL_ROW := 22
const SIZE_TAGLINE := 22
const SIZE_BRAND := 20
const SIZE_NAV := 18
const SIZE_HERO_LATIN := 18
const SIZE_TOAST := 16
const SIZE_BODY := 15
const SIZE_SUB := 14
const SIZE_SMALL := 12
const SIZE_MICRO := 11
const SIZE_DIALOG_TITLE := 28
const SIZE_HELP_TITLE := 24
const SIZE_SETTING_ROW := 20
const SIZE_SETTING_VALUE := 19
const SIZE_HELP := 17

## The repository ships no font files, so both faces are resolved from the system at run time. The first installed family in each list wins.
const CJK_FAMILIES: PackedStringArray = ["Noto Sans SC", "Noto Sans CJK SC", "Source Han Sans SC", "PingFang SC", "Microsoft YaHei", "sans-serif"]
const LATIN_FAMILIES: PackedStringArray = ["Inter", "SF Pro Text", "SF Pro", "Helvetica Neue", "Segoe UI", "sans-serif"]

## Fonts are cached per (face, weight, spacing): a SystemFont loads the whole font file, and the CJK collections are tens of megabytes.
static var _fonts: Dictionary = {}

## A font for the given face. weight is the CSS weight (100-900) and spacing the CSS letter-spacing in canvas pixels.
static func font(weight: int = 400, spacing: float = 0.0, latin: bool = false) -> Font:
	var key := "%s:%d:%.1f" % ["latin" if latin else "cjk", weight, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var base_key := "%s:%d" % ["latin" if latin else "cjk", weight]
	var base: SystemFont = _fonts.get(base_key)
	if base == null:
		base = SystemFont.new()
		base.font_names = (LATIN_FAMILIES + CJK_FAMILIES) if latin else CJK_FAMILIES
		base.font_weight = weight
		base.allow_system_fallback = true
		base.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		_fonts[base_key] = base
	var variation := FontVariation.new()
	variation.base_font = base
	variation.spacing_glyph = roundi(spacing)
	# System CJK faces usually stop at semibold. Synthetic emboldening keeps the heavy display weights of the design readable as heavy when the installed face has no real 800/900 cut.
	if weight >= 800 and not latin and not _has_heavy_cjk():
		variation.variation_embolden = 0.55 if weight >= 900 else 0.4
	_fonts[key] = variation
	return variation

static func _has_heavy_cjk() -> bool:
	for family in ["Noto Sans SC", "Noto Sans CJK SC", "Source Han Sans SC"]:
		if OS.get_system_font_path(family, 900) != "":
			return true
	return false

## Drop the font cache. LauncherRoot calls this when it leaves the tree so no font resource outlives the launcher.
static func release_fonts() -> void:
	_fonts.clear()

static func label_settings(size: int, weight: int = 400, color: Color = FG, spacing: float = 0.0, latin: bool = false) -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font = font(weight, spacing, latin)
	settings.font_size = size
	settings.font_color = color
	return settings

# ---- library and achievements ----

## Scrims over the blurred key art behind the library and the achievements screen.
const A_SCRIM_LIBRARY := 0.78
const A_SCRIM_ACHIEVEMENTS := 0.84
## Library cover: 16:9 art, four to a row inside the page margins. Selected = ring plus a slight scale, idle = dimmed.
const COVER_SIZE := Vector2(376, 212)
const COVER_GAP := Vector2(32, 36)
const COVER_SCALE := 1.06
const COVER_RING_OFFSET := 4.0
const A_COVER_IDLE := 0.7
const FADE_COVER := 0.2
const SIZE_TOTAL := 56
const SIZE_DETAIL_TITLE := 48
const SIZE_ACHIEVEMENT_TITLE := 34
const SIZE_SEARCH_FIELD := 30
const SIZE_CATEGORY_TAB := 22
const SIZE_STAT_VALUE := 20
const SIZE_COVER_NAME := 19
const SIZE_ACHIEVEMENT_NAME := 17
const SIZE_STAT_LABEL := 13
