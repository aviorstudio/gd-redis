extends SceneTree

const RedisClientModule = preload("res://addon/src/redis_client_module.gd")

func _init() -> void:
	_test_disconnected_operations_are_safe()
	_test_dangerous_commands_disabled_by_default()
	print("PASS gd-redis redis_client_module_test")
	quit()

func _test_disconnected_operations_are_safe() -> void:
	var redis := RedisClientModule.new()
	_assert(redis.get_value("missing") == "", "disconnected get_value should return empty string")
	_assert(redis.get_value_or_null("missing") == null, "disconnected get_value_or_null should return null")
	_assert(redis.scan_keys("*").is_empty(), "disconnected scan_keys should return empty array")
	_assert(not redis.del_key("missing"), "disconnected del_key should return false")

func _test_dangerous_commands_disabled_by_default() -> void:
	var redis := RedisClientModule.new()
	_assert(not redis.flushdb(), "flushdb should be disabled by default")
	redis.set_dangerous_commands_enabled(true)
	_assert(not redis.flushdb(), "enabled flushdb should still fail while disconnected")

func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
