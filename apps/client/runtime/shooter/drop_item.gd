class_name DropItem
extends Polygon2D

## 拾取信号:碰到玩家 HitArea(group player_hitbox)时发出;Runtime 负责接上 collect(),
## 因为 collect() 需要 runtime/player/weapon 三个节点引用,DropItem 自己不持有。

signal pickup_entered

const ShooterContent := preload("res://runtime/shooter/shooter_content.gd")
var kind := "coin"
var rate := 0.0

func configure(p_kind: String, p_rate: float) -> void:
	kind = p_kind; rate = clampf(p_rate, 0.0, 1.0)
	var spec: Array = ShooterContent.DROPS.get(kind, ShooterContent.DROPS["coin"])
	color = spec[0]; polygon = PackedVector2Array([Vector2(0,-9),Vector2(9,0),Vector2(0,9),Vector2(-9,0)])
	set_meta("type", kind); set_meta("rate", rate)
	var area := Area2D.new()
	area.name = "PickupArea"
	area.collision_layer = 0
	area.collision_mask = 1  # 玩家 HitArea 的 collision_layer(shooter_actor.gd)
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new(); circle.radius = 14.0
	collision.shape = circle
	area.add_child(collision)
	add_child(area)
	area.area_entered.connect(func(other: Area2D) -> void:
		if other.is_in_group("player_hitbox"): pickup_entered.emit())

func collect(runtime: Node, player: Node, weapon: Node) -> void:
	match kind:
		"heal": player.set_health(mini(999, int(player.get_meta("hp", 1)) + 25))
		"shield": player.set_meta("shield_hits", int(player.get_meta("shield_hits", 0)) + 1)
		"power": weapon.config["damage"] = mini(200, int(weapon.config.get("damage", 1)) + 10)
		"coin": runtime.set_meta("score", int(runtime.get_meta("score", 0)) + 500)
		"bomb":
			var enemies := runtime.get_node_or_null("Enemies")
			if enemies:
				for group in enemies.get_children():
					for enemy in group.get_children(): enemy.take_damage(99999)
	queue_free()
