class_name SurvivorRuntime
extends RefCounted

const SurvivorPlay := preload("res://runtime/survivor/survivor_play.gd")

static func build(dsl: Dictionary) -> Node:
	var run := SurvivorPlay.new()
	run.name = "SurvivorRuntime"
	run.configure(dsl)
	return run
