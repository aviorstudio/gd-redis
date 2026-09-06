extends SceneTree

const RedisClient = preload("res://addon/src/redis_client_module.gd")

func _init() -> void:
	var redis := RedisClient.new()
	var port := int(OS.get_environment("REDIS_TEST_PORT"))
	if port <= 0 or not redis.connect_to_server("127.0.0.1", port) or not redis.ping():
		push_error("Redis integration fixture must be available on REDIS_TEST_PORT")
		quit(1)
		return
	var key: String = "revik-utf8-test:" + str(OS.get_process_id())
	for value: String in ["ASCII state", "café", "盾と🦊", "Line\r\nNext", "", "é".repeat(40000)]:
		if not redis.set_value(key, value, 30) or redis.get_value_or_null(key) != value:
			push_error("UTF-8 Redis round trip failed (bytes=%d)" % value.to_utf8_buffer().size())
			redis.disconnect_from_server()
			quit(1)
			return
	var unicode_key: String = key + ":🦊"
	if not redis.set_value(unicode_key, "unicode key", 30) or redis.get_value(unicode_key) != "unicode key" or not redis.del_key(unicode_key):
		push_error("UTF-8 Redis key round trip failed")
		quit(1)
		return
	if not redis.del_key(key) or not redis.ping():
		push_error("Redis stream became unsynchronized")
		quit(1)
		return
	redis.disconnect_from_server()
	print("PASS Redis UTF-8 round trips")
	quit()
