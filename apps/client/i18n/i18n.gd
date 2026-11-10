class_name I18n
extends RefCounted

## 多语言工具(见 docs/18-i18n.md)。当前实现数字本地化格式:
## 中文用 万/亿,英日用 k/M;阈值以下原样(中文不加千分位逗号:2100 而非 2,100)。

static func format_number(n: int, locale: String) -> String:
	var a := absi(n)
	if locale == "zh":
		if a >= 100000000:
			return _trim(float(n) / 1e8) + "亿"
		if a >= 10000:
			return _trim(float(n) / 1e4) + "万"
		return str(n)
	# en / ja
	if a >= 1000000:
		return _trim(float(n) / 1e6) + "M"
	if a >= 1000:
		return _trim(float(n) / 1e3) + "k"
	return str(n)

## 保留 1 位小数,去掉无意义的 .0(4.0万 → 4万)。
static func _trim(v: float) -> String:
	var s := "%.1f" % v
	if s.ends_with(".0"):
		s = s.substr(0, s.length() - 2)
	return s
