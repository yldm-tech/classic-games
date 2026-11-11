class_name LauncherPcTokens
extends RefCounted

## Design tokens that only PC mode uses, on top of LauncherTokens: the flat desktop palette and the measures of the title strip, sidebar, toolbar, grid and menus. Everything is authored for the same 1920x1080 canvas.

# ---- colour ----

const WINDOW_BG := Color("07090F")
const LINE := Color("161A26")
const BORDER := Color("222736")
const BORDER_STRONG := Color("2A2F40")
const BORDER_HOVER := Color("3A3F50")
const FIELD_BG := Color("0B0E16")
const MENU_BG := Color("10131D")
const LOCKED_BG := Color("1A1E2A")
const TEXT_MUTED := Color("8A90A0")
const TEXT_SOFT := Color("A3A8B5")
const TEXT_BODY := Color("DDE1EA")
const ACCENT := Color("9DBBFF")
const OK := Color("3DDC97")

## Fill of a selected sidebar row and of the row under the pointer.
const A_SELECTED := 0.09
const A_HOVER := 0.05
const A_PRESSED := 0.14

# ---- measures ----

const TITLE_HEIGHT := 40.0
const STATUS_HEIGHT := 30.0
const SIDEBAR_WIDTH := 272.0
const SIDEBAR_PADDING := Vector2(12, 16)
const SIDE_ROW_HEIGHT := 36.0
const SIDE_BAR := 3.0
const SEARCH_HEIGHT := 38.0
const THUMB_SIZE := Vector2(72, 41)
const LIST_THUMB_SIZE := Vector2(112, 63)
const HERO_HEIGHT := 450.0
## Where the hero key art starts inside the detail view; the text column sits on the clear part to its left.
const HERO_ART_LEFT := 360.0
const HERO_TEXT_WIDTH := 680.0
const DETAIL_PADDING := 48.0
const TAB_HEIGHT := 46.0
const TAB_UNDERLINE := 2.0
const BUTTON_HEIGHT := 48.0
const LIBRARY_PADDING := 40.0
const CONTROL_HEIGHT := 40.0
const CHIP_HEIGHT := 32.0
const GRID_GAP := 20.0
## A grid card is never narrower than this; the number of columns follows from the width that is available.
const CARD_MIN_WIDTH := 340.0
const CARD_TEXT_HEIGHT := 52.0
const LIST_ROW_HEIGHT := 79.0
const LIST_GAP := 4.0
const ACHIEVEMENT_MIN_WIDTH := 300.0
const ACHIEVEMENT_HEIGHT := 76.0
const STAT_MIN_WIDTH := 220.0
const STAT_HEIGHT := 90.0
const MENU_WIDTH := 240.0
const MENU_ROW_HEIGHT := 38.0
const SCROLLBAR_WIDTH := 10.0
const FOCUS_RING := 2.0

# ---- type ----

const SIZE_HERO := 84
const SIZE_SHELF_TITLE := 26
const SIZE_STAT := 22
const SIZE_TAGLINE := 17
const SIZE_BUTTON := 16
const SIZE_NAME := 15
const SIZE_ROW := 14
const SIZE_TEXT := 13
const SIZE_NOTE := 12
const SIZE_LABEL := 11
const SIZE_KEYCAP := 10
