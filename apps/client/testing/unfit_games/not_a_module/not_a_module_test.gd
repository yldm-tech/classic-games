extends SceneTree
## Present so that this directory's only problem is the one it is named after. Never run: the test runner only looks under games/ and testing/games/.

func _initialize() -> void:
	print("not_a_module_test: 0 passed, 0 failed")
	quit.call_deferred(0)
