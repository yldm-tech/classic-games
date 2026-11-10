class_name ChromeController
extends RefCounted

const PHONE := "phone"
const RAIL := "rail"
const DESKTOP := "desktop"
const RAIL_MIN_WIDTH := 700.0
const DESKTOP_MIN_WIDTH := 1100.0

var mode := PHONE

func mode_for_width(width: float) -> String:
	if width >= DESKTOP_MIN_WIDTH:
		return DESKTOP
	if width >= RAIL_MIN_WIDTH:
		return RAIL
	return PHONE

func set_mode(value: String) -> bool:
	if value not in [PHONE, RAIL, DESKTOP]:
		return false
	mode = value
	return true
