class_name AppVersion
extends RefCounted

## Single display version for About / Settings. Keep this the only shipping
## version string so chrome cannot advertise a fake "new update".

const VERSION := "0.1.0"
const CHANNEL := "beta"

static func display(locale: String = "zh") -> String:
	match locale:
		"en":
			return "Version %s (%s)" % [VERSION, CHANNEL]
		"ja":
			return "バージョン %s (ベータ)" % VERSION
		_:
			return "版本 %s (内测)" % VERSION

static func build_line() -> String:
	return "Build %s" % VERSION
