class_name Catalog
extends RefCounted

## 尚未迁入服务端运营域的应用种子内容：
## 9 款游戏的元数据,标题/简介按语言取 Strings.game_title/desc,封面在 assets/covers/。
## 发现页的「全部游戏/榜单」在服务端可达时由 AppRoot 注入真实数据覆盖；
## 首页「精选/继续玩」等运营位后端尚无对应域,先用种子内容呈现设计稿信息架构。

const GAMES := [
	{"id": "ember", "by": "@koru", "tone": "ember", "plays": 48200, "forks": 1400, "likes": 9300, "cat": "Racing"},
	{"id": "volt", "by": "@mei", "tone": "moss", "plays": 12900, "forks": 608, "likes": 2100, "badge": "ai", "cat": "Arcade"},
	{"id": "foundry", "by": "@arc", "tone": "plum", "plays": 8100, "forks": 312, "likes": 1800, "cat": "Strategy"},
	{"id": "null", "by": "@jin", "tone": "ocean", "plays": 5400, "forks": 97, "likes": 940, "cat": "Puzzle"},
	{"id": "cinder", "by": "@koru", "tone": "steel", "plays": 22000, "forks": 540, "likes": 4700, "badge": "live", "cat": "Arcade"},
	{"id": "ash", "by": "@yuna", "tone": "rust", "plays": 3300, "forks": 41, "likes": 620, "cat": "Puzzle"},
	{"id": "magma", "by": "@bo", "tone": "ember", "plays": 9800, "forks": 203, "likes": 1500, "cat": "Puzzle"},
	{"id": "echo", "by": "@ana", "tone": "ocean", "plays": 6700, "forks": 120, "likes": 1100, "badge": "ai", "cat": "Arcade"},
]

const FEATURED := {"id": "ashfall", "by": "@talia", "tone": "rust", "plays": 31000, "forks": 2100, "likes": 8800, "cat": "Strategy"}

## 首页「继续玩」:游戏 id + 关卡 + 进度百分比。
const CONTINUE := [
	{"id": "ember", "level": 4, "pct": 64},
	{"id": "cinder", "level": 2, "pct": 28},
]

const CAT_KEYS := ["All", "Racing", "Puzzle", "Arcade", "Strategy"]

## 榜单种子(发现页;hot/rising/fresh → 游戏 id + 排名变化)。
const RANKS := {
	"hot": [["ember", "—"], ["ashfall", "↑1"], ["cinder", "↓2"], ["volt", "↑3"], ["magma", "—"]],
	"rising": [["echo", "↑5"], ["volt", "↑3"], ["ash", "↑2"], ["null", "↑2"], ["foundry", "↑1"]],
	"fresh": [["ash", "new"], ["echo", "new"], ["null", "new"], ["foundry", "—"], ["magma", "—"]],
}

static func by_id(id: String) -> Dictionary:
	if FEATURED["id"] == id:
		return FEATURED
	for g: Dictionary in GAMES:
		if g["id"] == id:
			return g
	return {}
