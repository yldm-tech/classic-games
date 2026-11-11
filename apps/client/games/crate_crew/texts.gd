extends RefCounted

## Everything the game writes on the stage itself, in both languages: the names of the two squirrels (Fenn, russet with a teal scarf, and Tug, dark brown with an orange scarf), the hints, the banners. Scores, lives and the clock belong to the launcher's HUD. English is written in capitals: the lines are short signs on a workshop wall, and capitals keep them readable at a glance while the stage is moving.

const TEXT := {
	"hero_0": {"zh": "小枫", "en": "FENN"},
	"hero_1": {"zh": "大栗", "en": "TUG"},
	"hint_move": {"zh": "向右出发，跳过缺口", "en": "HEAD RIGHT AND JUMP THE GAPS"},
	"hint_lift": {"zh": "走到箱子旁，按「举起」", "en": "STAND BY A CRATE, PRESS LIFT"},
	"hint_throw": {"zh": "再按一次：扔出去", "en": "PRESS AGAIN TO THROW IT"},
	"hint_up": {"zh": "按住上再扔：向上砸", "en": "HOLD UP AND THROW: STRAIGHT UP"},
	"hint_hide": {"zh": "举着箱子按住下：躲起来", "en": "CARRYING A CRATE, HOLD DOWN TO HIDE"},
	"stage": {"zh": "第 %d 关", "en": "STAGE %d"},
	"clear": {"zh": "关卡完成", "en": "STAGE CLEAR"},
	"won": {"zh": "工坊恢复秩序", "en": "WORKSHOP BACK IN ORDER"},
	"continue": {"zh": "续关 · 还剩 %d 次", "en": "CONTINUE · %d LEFT"},
	"lost": {"zh": "今天到此为止", "en": "SHIFT OVER"},
	"boss_vacuum": {"zh": "吸尘巨兽", "en": "THE DUSTMAW"},
	"boss_crane": {"zh": "吊臂总管", "en": "THE OVERSEER"},
	"boss_tip_vacuum": {"zh": "趁它张嘴，把废料扔回去", "en": "THROW ITS SCRAP INTO ITS OPEN MOUTH"},
	"boss_tip_crane": {"zh": "等它睁眼出爪，再用螺母砸它", "en": "THROW THE NUTS WHEN ITS EYE OPENS"},
}

static func of(key: String, locale: String) -> String:
	var entry: Dictionary = TEXT.get(key, {})
	return str(entry.get("en" if locale == "en" else "zh", key))
