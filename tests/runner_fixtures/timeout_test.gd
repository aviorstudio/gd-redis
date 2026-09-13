extends SceneTree
func _initialize() -> void:
	await create_timer(60.0).timeout
	print("PASS gd-redis timeout_test")
	quit(0)
