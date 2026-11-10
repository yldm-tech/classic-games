class_name TeenGuard
extends RefCounted

## Client-side teen-mode gates. Server prefs are the source of truth for
## enabled/PIN; this only enforces the published duration and curfew rules
## so the settings copy is not a no-op. It is not an anti-tamper control.

const DAILY_LIMIT_SECS := 40 * 60
const CURFEW_START_HOUR := 22
const CURFEW_END_HOUR := 8

static func in_curfew(hour: int) -> bool:
	return hour >= CURFEW_START_HOUR or hour < CURFEW_END_HOUR

static func local_hour() -> int:
	return int(Time.get_datetime_dict_from_system().get("hour", 0))

static func local_day_key() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [int(dt.get("year", 1970)), int(dt.get("month", 1)), int(dt.get("day", 1))]

## Empty string means play is allowed; otherwise an i18n key for the block toast.
static func block_reason(enabled: bool, hour: int, played_today_secs: int) -> String:
	if not enabled:
		return ""
	if in_curfew(hour):
		return "teen_blocked_curfew"
	if played_today_secs >= DAILY_LIMIT_SECS:
		return "teen_blocked_limit"
	return ""
