class_name Strings
extends RefCounted

## Entry point for every interface string (see docs/18-i18n.md): Strings.t(locale, key) for plain text, Strings.fmt(locale, key, args) for "%s" / "%d" format strings. The tables themselves live next to this file, one per area; today that is the console launcher's (launcher_strings.gd).

const LOCALES := ["zh", "en"]
const DEFAULT_LOCALE := "zh"

const LauncherTable := preload("res://i18n/launcher_strings.gd")

## The string for a key: the locale's own, else zh, else the key itself with a warning (visible during development).
static func t(locale: String, key: String) -> String:
	return LauncherTable.lookup(locale, key)

## A format string filled in: fmt("zh", "launcher.when.days_ago_fmt", [3]) is "3 天前".
static func fmt(locale: String, key: String, args: Array) -> String:
	return t(locale, key) % args
