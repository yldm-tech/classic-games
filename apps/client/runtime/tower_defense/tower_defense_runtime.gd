class_name TowerDefenseRuntime
extends RefCounted

const TowerDefensePlay := preload("res://runtime/tower_defense/tower_defense_play.gd")

static func build(dsl: Dictionary) -> Node:
	var run := TowerDefensePlay.new()
	run.name = "TowerDefenseRuntime"
	run.configure(dsl)
	return run
