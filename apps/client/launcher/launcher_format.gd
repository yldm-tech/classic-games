class_name LauncherFormat
extends RefCounted

## Display formatting shared by launcher screens. Every function is pure: the current time is passed in, never read here.

const Strings := preload("res://i18n/strings.gd")

## 128450 -> "128,450".
static func score(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out

## Total play time: "3h 12m", "5m", or the "under a minute" string for anything shorter.
static func play_time(seconds: float, locale: String) -> String:
	var minutes := int(seconds / 60.0)
	if minutes >= 60:
		return Strings.fmt(locale, "launcher.time.hours_minutes_fmt", [minutes / 60, minutes % 60])
	if minutes >= 1:
		return Strings.fmt(locale, "launcher.time.minutes_fmt", [minutes])
	return str(Strings.t(locale, "launcher.time.under_minute"))

## Elapsed run time as "MM:SS".
static func clock(seconds: float) -> String:
	var total := maxi(0, int(seconds))
	return "%02d:%02d" % [total / 60, total % 60]

## How long ago a game was played, by local calendar day: today, yesterday, "N days ago", or the "new" string when it never was (last_played == 0). Both arguments are unix seconds.
static func when_day(last_played: int, now: int, locale: String) -> String:
	if last_played <= 0:
		return str(Strings.t(locale, "launcher.when.never"))
	var days := _local_day(now) - _local_day(last_played)
	if days <= 0:
		return str(Strings.t(locale, "launcher.when.today"))
	if days == 1:
		return str(Strings.t(locale, "launcher.when.yesterday"))
	return Strings.fmt(locale, "launcher.when.days_ago_fmt", [days])

## when_day plus the local time of day, e.g. "今天 18:02".
static func when_time(last_played: int, now: int, locale: String) -> String:
	if last_played <= 0:
		return when_day(last_played, now, locale)
	var local := Time.get_datetime_dict_from_unix_time(last_played + _utc_offset_seconds())
	return "%s %02d:%02d" % [when_day(last_played, now, locale), int(local["hour"]), int(local["minute"])]

static func _utc_offset_seconds() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60

static func _local_day(unix: int) -> int:
	return floori(float(unix + _utc_offset_seconds()) / 86400.0)
