extends SceneTree

const RedisClient = preload("res://addon/src/redis_client_module.gd")
const Result = preload("res://addon/src/redis_result.gd")

func _init() -> void:
	_test_fragmented_binary_reply()
	_test_pipeline_and_binary_roundtrip()
	_test_malformed_disconnect_timeout_and_cancel()
	print("PASS gd-redis redis_deadline_integration_test")
	quit(0)

func _test_fragmented_binary_reply() -> void:
	var redis: Variant = _fixture_client()
	var result: Variant = _await(redis, redis.request(["FRAGMENT"]), 6000)
	_assert(result != null and result.status == Result.Status.OK, "fragmented reply failed")
	_assert(result.value == PackedByteArray([0, 255, 65, 13, 10, 66, 128, 90]), "binary reply changed")
	redis.disconnect_from_server()

func _test_pipeline_and_binary_roundtrip() -> void:
	var redis := RedisClient.new()
	_assert(redis.connect_to_server("127.0.0.1", int(OS.get_environment("REDIS_TEST_PORT"))), "Redis fixture unavailable")
	var ids: Array[int] = [redis.request(["PING"]), redis.request(["PING"]), redis.request(["PING"])]
	for request_id in ids:
		var result: Variant = _await(redis, request_id, 6000)
		_assert(result != null and result.status == Result.Status.OK and result.value == "PONG", "pipeline reply mismatch")
	var key := "gd-redis-binary:%s" % OS.get_process_id()
	var binary := PackedByteArray([0, 255, 13, 10, 128, 65])
	_assert(_await(redis, redis.request(["SET", key, binary, "EX", "30"]), 6000).status == Result.Status.OK, "binary SET failed")
	var get_result: Variant = _await(redis, redis.request(["GET", key]), 6000)
	_assert(get_result.status == Result.Status.OK and get_result.value == binary, "binary Redis roundtrip changed")
	var pending_ids: Array[int] = []
	for _index in range(64): pending_ids.append(redis.request(["PING"]))
	var rejected_id := redis.request(["PING"])
	_assert(rejected_id == -1, "pending request bound over 64 accepted")
	for pending_id in pending_ids:
		_assert(_await(redis, pending_id, 6000).status == Result.Status.OK, "bounded pending request failed")
	var huge := PackedByteArray()
	huge.resize(8 * 1024 * 1024)
	var huge_result: Variant = redis.take_result(redis.request(["SET", key, huge]))
	_assert(huge_result != null and huge_result.status == Result.Status.LIMIT_EXCEEDED, "command over 8 MiB accepted")
	redis.del_key(key)
	redis.disconnect_from_server()

func _test_malformed_disconnect_timeout_and_cancel() -> void:
	var malformed: Variant = _fixture_client()
	var malformed_result: Variant = _await(malformed, malformed.request(["MALFORMED"]), 6000)
	_assert(malformed_result.status == Result.Status.PROTOCOL_ERROR and not malformed.is_connected_to_server(), "malformed reply did not close")
	var auth_error: Variant = _fixture_client()
	var auth_result: Variant = _await(auth_error, auth_error.request(["AUTHERR"]), 6000)
	_assert(auth_result.status == Result.Status.REDIS_ERROR and "NOAUTH" in auth_result.message, "Redis auth error not typed")
	auth_error.disconnect_from_server()
	var disconnected: Variant = _fixture_client()
	var disconnect_result: Variant = _await(disconnected, disconnected.request(["DISCONNECT"]), 6000)
	_assert(disconnect_result.status == Result.Status.DISCONNECTED and not disconnected.is_connected_to_server(), "mid-frame disconnect not reported")
	var slow: Variant = _fixture_client()
	var started := Time.get_ticks_msec()
	var absolute_result: Variant = _await(slow, slow.request(["SLOW"]), 6000)
	var elapsed := Time.get_ticks_msec() - started
	_assert(absolute_result.status == Result.Status.TIMEOUT and elapsed >= 4800 and elapsed <= 5500, "absolute deadline outside approved boundary")
	var stalled: Variant = _fixture_client()
	started = Time.get_ticks_msec()
	var timeout_result: Variant = _await(stalled, stalled.request(["STALL"]), 6000)
	elapsed = Time.get_ticks_msec() - started
	_assert(timeout_result.status == Result.Status.TIMEOUT and elapsed >= 1900 and elapsed <= 5500, "inactivity deadline outside approved boundary")
	var cancelled: Variant = _fixture_client()
	var request_id: int = cancelled.request(["STALL"])
	_assert(cancelled.cancel(request_id), "cancel rejected")
	var cancel_result: Variant = cancelled.take_result(request_id)
	_assert(cancel_result.status == Result.Status.CANCELLED and not cancelled.is_connected_to_server(), "cancel did not close safely")
	var blocked_write: Variant = _fixture_client()
	var payload := PackedByteArray()
	payload.resize(7 * 1024 * 1024)
	started = Time.get_ticks_msec()
	var write_result: Variant = _await(blocked_write, blocked_write.request(["BLACKHOLE", payload]), 6000)
	elapsed = Time.get_ticks_msec() - started
	_assert(write_result.status == Result.Status.TIMEOUT and "write" in write_result.message.to_lower() and elapsed >= 1900 and elapsed <= 5500, "write deadline outside approved boundary")

func _fixture_client() -> Variant:
	var redis := RedisClient.new()
	_assert(redis.connect_to_server("127.0.0.1", int(OS.get_environment("RESP_TEST_PORT"))), "RESP fixture unavailable")
	return redis

func _await(redis: Variant, request_id: int, timeout_ms: int) -> Variant:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		redis.poll_io()
		var result: Variant = redis.take_result(request_id)
		if result != null:
			return result
		OS.delay_msec(1)
	return null

func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
