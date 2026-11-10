class_name ShooterRuntime
extends RefCounted

## 把生效 DSL 构建成可见、可移动、带碰撞体的 Shooter 对象树。
##
## 根节点同时挂上摘要 meta(enemy_total 等),供 GameSession 回传 game_ended。

const ShooterWorld := preload("res://runtime/shooter/shooter_world.gd")

static func build(dsl: Dictionary) -> Node:
	var world: Node = ShooterWorld.new()
	world.configure(dsl)
	return world
