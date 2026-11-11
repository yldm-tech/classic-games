extends RefCounted

## Everything the game itself writes on the stage, in both languages. Score, flame and lives belong to the launcher's HUD.

const TEXT := {
	"stage": {"zh": "第 %s 幕", "en": "STAGE %s"},
	"checkpoint": {"zh": "灯已点亮", "en": "LAMP LIT"},
	"stage_clear": {"zh": "烽火已燃", "en": "BEACON LIT"},
	"flame_bonus": {"zh": "余焰奖励 %d", "en": "FLAME BONUS %d"},
	"boss_toad": {"zh": "熔蟾 · 玛格莫", "en": "MAGMAW THE SLAG TOAD"},
	"boss_owl": {"zh": "霜枭 · 莱姆翼", "en": "RIMEWING THE FROST OWL"},
	"boss_down": {"zh": "首领倒下", "en": "GUARDIAN DOWN"},
	"continue": {"zh": "重燃灯芯 · 剩余续关 %d", "en": "RELIT · CONTINUES LEFT %d"},
	"game_over": {"zh": "灯火熄灭", "en": "THE FLAME IS OUT"},
	"victory": {"zh": "长夜有光", "en": "THE NIGHT HAS A LIGHT"},
	"victory_sub": {"zh": "两片荒境的烽火都已点燃", "en": "Both beacons burn again"},
	"mount": {"zh": "炭角羊来了！", "en": "ASHHORN ANSWERS!"},
	"one_up": {"zh": "生命 +1", "en": "1UP"},
	"hint_throw": {"zh": "按住上再投掷，火星飞得更高", "en": "Hold up while throwing to lob the spark"},
}

static func of(key: String, locale: String) -> String:
	var entry: Dictionary = TEXT.get(key, {})
	return str(entry.get(locale, entry.get("en", key)))
