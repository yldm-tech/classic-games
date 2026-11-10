extends SceneTree

func _initialize() -> void:
	var packed: PackedScene = load("res://main.tscn")
	var main := packed.instantiate()
	root.add_child(main)
	if not main.is_node_ready():
		await main.ready
	_verify.call_deferred(main)

func _verify(main: Node) -> void:
	var application := main.find_child("AppRoot", false, false)
	if application == null or application.router == null or application.identity == null:
		push_error("main scene did not assemble AppRoot")
		main.free()
		quit(1)
		return
	main.free()
	print("launch_test: 1 passed, 0 failed")
	quit(0)
