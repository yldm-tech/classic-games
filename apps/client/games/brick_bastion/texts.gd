extends RefCounted

## Everything Brick Bastion writes on its own stage, in both languages. The HUD's labels come from the manifest; these are the banners, the tally and the side panels.

const TEXT := {
	"sector": {"zh": "防区 %d / %d", "en": "SECTOR %d / %d"},
	"ready": {"zh": "守住信标", "en": "HOLD THE BEACON"},
	"warning": {"zh": "警报", "en": "WARNING"},
	"boss_inbound": {"zh": "首领正在逼近", "en": "BOSS INBOUND"},
	"cleared": {"zh": "防区守住了", "en": "SECTOR HELD"},
	"tally": {"zh": "战果", "en": "TALLY"},
	"bonus": {"zh": "信标奖励", "en": "BEACON BONUS"},
	"total": {"zh": "总分", "en": "TOTAL"},
	"next": {"zh": "按开炮键继续", "en": "PRESS FIRE TO GO ON"},
	"won": {"zh": "信标长明", "en": "THE BEACON STANDS"},
	"won_sub": {"zh": "六个防区全部守住", "en": "ALL SIX SECTORS HELD"},
	"lost_core": {"zh": "信标熄灭了", "en": "THE BEACON IS DARK"},
	"lost_rovers": {"zh": "哨车全部损毁", "en": "ALL ROVERS LOST"},
	"relief": {"zh": "后备车组接防 · 本防区重来", "en": "RESERVE CREW TAKES OVER"},
	"relief_boss": {"zh": "后备车组接防 · 再战首领", "en": "RESERVE CREW · BACK TO THE BOSS"},
	"crews": {"zh": "后备车组 ×%d", "en": "RESERVE x%d"},
	"reserve": {"zh": "敌军编队", "en": "INBOUND"},
	"supplies": {"zh": "补给芯片", "en": "SUPPLY CHIPS"},
	"frozen": {"zh": "凝滞", "en": "STASIS"},
	"fortified": {"zh": "加固", "en": "FORTIFIED"},
	"enraged": {"zh": "首领暴怒", "en": "BOSS ENRAGED"},
	"out": {"zh": "待援", "en": "OUT"},
	"crusher": {"zh": "碾城者", "en": "RAMPART CRUSHER"},
	"dreadnought": {"zh": "熔炉无畏舰", "en": "FORGE DREADNOUGHT"},
	"chip_coil": {"zh": "火力升级", "en": "FIREPOWER UP"},
	"chip_aegis": {"zh": "护盾展开", "en": "SHIELD UP"},
	"chip_stasis": {"zh": "敌车凝滞", "en": "RAIDERS STALLED"},
	"chip_mason": {"zh": "信标加固", "en": "BEACON FORTIFIED"},
	"chip_surge": {"zh": "全场震荡", "en": "SURGE"},
	"chip_spare": {"zh": "哨车 +1", "en": "ROVER +1"},
	"legend_coil": {"zh": "火力", "en": "GUN+"},
	"legend_aegis": {"zh": "护盾", "en": "WARD"},
	"legend_stasis": {"zh": "凝滞", "en": "HALT"},
	"legend_mason": {"zh": "加固", "en": "WALL"},
	"legend_surge": {"zh": "震荡", "en": "BOOM"},
	"legend_spare": {"zh": "哨车", "en": "CAR+"},
}

static func of(key: String, locale: String) -> String:
	var entry: Dictionary = TEXT.get(key, {})
	return str(entry.get(locale, entry.get("en", key)))

## Problems of the table: an entry without both languages.
static func problems() -> PackedStringArray:
	var out := PackedStringArray()
	for key: String in TEXT:
		for locale in ["zh", "en"]:
			if str((TEXT[key] as Dictionary).get(locale, "")).strip_edges() == "":
				out.append("%s: no %s text" % [key, locale])
	return out
