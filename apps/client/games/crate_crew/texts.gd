extends RefCounted

## Everything the game writes on the stage itself, in both languages. Scores, lives and the clock belong to the launcher's HUD.

const TEXT := {
	"hint_move": {"zh": "向右出发，跳过缺口", "en": "Head right and jump the gaps"},
	"hint_lift": {"zh": "走到箱子旁，按「举起」", "en": "Stand by a crate, press Lift"},
	"hint_throw": {"zh": "再按一次：扔出去", "en": "Press again to throw it"},
	"hint_up": {"zh": "按住上再扔：向上砸", "en": "Hold Up and throw: straight up"},
	"hint_hide": {"zh": "举着箱子按住下：躲起来", "en": "Carrying a crate, hold Down to hide"},
	"stage": {"zh": "第 %d 关", "en": "STAGE %d"},
	"clear": {"zh": "关卡完成", "en": "STAGE CLEAR"},
	"won": {"zh": "工坊恢复秩序", "en": "WORKSHOP BACK IN ORDER"},
	"continue": {"zh": "续关 · 还剩 %d 次", "en": "CONTINUE · %d LEFT"},
	"lost": {"zh": "今天到此为止", "en": "SHIFT OVER"},
	"boss_vacuum": {"zh": "吸尘巨兽", "en": "THE DUSTMAW"},
	"boss_crane": {"zh": "吊臂总管", "en": "THE OVERSEER"},
	"boss_tip_vacuum": {"zh": "趁它张嘴，把废料扔回去", "en": "Throw its scrap back into its open mouth"},
	"boss_tip_crane": {"zh": "捡起螺母，向上砸它", "en": "Pick up the nuts and throw them up"},
}

static func of(key: String, locale: String) -> String:
	var entry: Dictionary = TEXT.get(key, {})
	return str(entry.get("en" if locale == "en" else "zh", key))
