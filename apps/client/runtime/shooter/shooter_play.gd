class_name ShooterPlay
extends RefCounted

## Shooter 玩法规则的逻辑模型(见 docs/01-vision.md 的可玩游戏:计分、按住A加速倍率、B护盾、结算)。
## 这是可 headless 断言的游戏规则层——计分/伤害/护盾/结算判定都是纯逻辑;
## 「按钮发光、分数实跳动画」等视觉表现需真机/人眼验证,不在此处。

const KILL_POINTS := 100

var score := 0
var hp := 100
var cleared := false

var _boost := false   # 按住 A:分数加倍
var _shield := false  # B:吸收下一次伤害

func _init(start_hp: int = 100) -> void:
	hp = start_hp

func set_boost(on: bool) -> void:
	_boost = on

## 用一次护盾(B 键)。
func activate_shield() -> void:
	_shield = true

## 击杀一个敌人 → 加分(加速时翻倍)。
func on_kill() -> void:
	score += KILL_POINTS * (2 if _boost else 1)

## 受击 → 护盾优先吸收(消耗一次),否则扣血。
func on_hit(dmg: int) -> void:
	if _shield:
		_shield = false
		return
	hp = max(0, hp - dmg)

func is_dead() -> bool:
	return hp <= 0

## 结算:存活即通关;返回 { score, cleared, new_record }。
func finish(best_score: int) -> Dictionary:
	cleared = hp > 0
	return {"score": score, "cleared": cleared, "new_record": score > best_score}
