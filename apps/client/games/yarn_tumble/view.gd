extends Node2D

## Draws the world. Placeholder until the sprites are in.

var world: RefCounted

func setup(run_world: RefCounted, _locale: String) -> void:
	world = run_world

func notice(_event: Array) -> void:
	pass

func animate(_delta: float) -> void:
	queue_redraw()
