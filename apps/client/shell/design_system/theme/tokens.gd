class_name Tokens
extends RefCounted

## 设计 token 单一来源(誊自原型 _ds/tokens/*.css,见 docs/19-design-system.md)。
## 颜色按语义名取值、深浅两套;间距/圆角/字号/时长为常量刻度。
## UI 一律引用这里,不散落硬编码——否则主题切换与整体调色不可控。

const THEME_DARK := "dark"
const THEME_LIGHT := "light"

# ── 基础色阶(品牌,两主题共用) ──────────────────────────────
const EMBER_400 := Color("#FF6B33")
const EMBER_500 := Color("#FF4D1A") # core brand
const EMBER_600 := Color("#E83A0B")
const EMBER_700 := Color("#BF2D06")
const VOLT_300 := Color("#D6FF66")
const VOLT_400 := Color("#C8FF3D")  # core AI accent
const VOLT_500 := Color("#A8E61A")
const VOLT_600 := Color("#84BF0A")

# ── 语义色(深色为默认,对照 colors.css :root / [data-theme=light]) ──
static var DARK := {
	&"bg_app": Color("#0F0D0E"),
	&"bg_sunken": Color("#0A0809"),
	&"surface_card": Color("#1C1819"),
	&"surface_raised": Color("#252021"),
	&"surface_input": Color("#161314"),
	&"text_primary": Color("#F2EDEC"),
	&"text_secondary": Color("#B3A9AA"),
	&"text_muted": Color("#6B6162"),
	&"text_on_primary": Color("#FFFFFF"),
	&"text_on_volt": Color("#1A2403"),
	&"accent_primary": EMBER_500,
	&"accent_primary_hover": EMBER_400,
	&"accent_primary_press": EMBER_600,
	&"accent_ai": VOLT_400,
	&"accent_ai_hover": VOLT_300,
	&"accent_ai_press": VOLT_500,
	&"status_success": Color("#2EE676"),
	&"status_warning": Color("#FFC24D"),
	&"status_danger": Color("#FF3B5C"),
	&"status_info": Color("#4DA3FF"),
	&"border_subtle": Color(Color("#F2EDEC"), 0.08),
	&"border_default": Color(Color("#F2EDEC"), 0.14),
	&"border_strong": Color(Color("#F2EDEC"), 0.24),
	&"border_focus": EMBER_500,
	&"tint_ember": Color(Color("#FF4D1A"), 0.14),
	&"tint_volt": Color(Color("#C8FF3D"), 0.12),
	&"tint_success": Color(Color("#2EE676"), 0.14),
	&"tint_danger": Color(Color("#FF3B5C"), 0.14),
}

static var LIGHT := {
	&"bg_app": Color("#FBF8F6"),
	&"bg_sunken": Color("#F1ECE9"),
	&"surface_card": Color("#FFFFFF"),
	&"surface_raised": Color("#FFFFFF"),
	&"surface_input": Color("#F4F0ED"),
	&"text_primary": Color("#1C1819"),
	&"text_secondary": Color("#574F50"),
	&"text_muted": Color("#8E8384"),
	&"text_on_primary": Color("#FFFFFF"),
	&"text_on_volt": Color("#1A2403"),
	&"accent_primary": EMBER_600,
	&"accent_primary_hover": EMBER_500,
	&"accent_primary_press": EMBER_700,
	&"accent_ai": VOLT_500,
	&"accent_ai_hover": VOLT_400,
	&"accent_ai_press": VOLT_600,
	&"status_success": Color("#18A04C"),
	&"status_warning": Color("#C78A14"),
	&"status_danger": Color("#D11A3C"),
	&"status_info": Color("#4DA3FF"),
	&"border_subtle": Color(Color("#1C1819"), 0.07),
	&"border_default": Color(Color("#1C1819"), 0.12),
	&"border_strong": Color(Color("#1C1819"), 0.22),
	&"border_focus": EMBER_500,
	&"tint_ember": Color(Color("#E83A0B"), 0.10),
	&"tint_volt": Color(Color("#84BF0A"), 0.12),
	&"tint_success": Color(Color("#18A04C"), 0.12),
	&"tint_danger": Color(Color("#D11A3C"), 0.10),
}

## 语义色取值。未知 token 名给品红并告警(开发期显眼,不静默)。
static func color(token: StringName, theme: String = THEME_DARK) -> Color:
	var table: Dictionary = LIGHT if theme == THEME_LIGHT else DARK
	if not table.has(token):
		push_warning("未知颜色 token: %s" % token)
		return Color.MAGENTA
	return table[token]

# ── 间距(4px 基准,spacing.css) ─────────────────────────────
const SPACE_1 := 4
const SPACE_2 := 8
const SPACE_3 := 12
const SPACE_4 := 16
const SPACE_5 := 20
const SPACE_6 := 24
const SPACE_8 := 32
const SPACE_10 := 40
const SPACE_12 := 48
const SPACE_16 := 64
const GUTTER := 16
const HIT_MIN := 44

# ── 圆角 ──────────────────────────────────────────────────
const RADIUS_XS := 6   # tags, badges
const RADIUS_SM := 10  # inputs, chips
const RADIUS_MD := 14  # buttons
const RADIUS_LG := 18  # cards
const RADIUS_XL := 24  # sheets, modals
const RADIUS_PILL := 999

# ── 字号(typography.css,移动优先 px) ───────────────────────
const FONT_DISPLAY := 36
const FONT_H1 := 28
const FONT_H2 := 22
const FONT_H3 := 18
const FONT_H4 := 16
const FONT_H5 := 14
const FONT_BODY := 14
const FONT_BODY_SM := 13
const FONT_CAPTION := 12
const FONT_MICRO := 10  # badges, tab labels
const FONT_MONO := 13
const FONT_MONO_SM := 11

# ── 动效(motion,秒;原型规定不慢于 400ms) ────────────────────
const DUR_FAST := 0.12
const DUR_MED := 0.22
const DUR_SLOW := 0.36
