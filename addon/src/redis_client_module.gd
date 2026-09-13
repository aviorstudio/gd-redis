## Redis client module for GDScript using RESP protocol over TCP.
class_name RedisClientModule
extends RefCounted

const RedisResultType = preload("redis_result.gd")
const RespParser = preload("resp_parser.gd")
const MAX_COMMAND_BYTES := 8 * 1024 * 1024
const MAX_IO_BUFFER_BYTES := 16 * 1024 * 1024
const MAX_PENDING_REQUESTS := 64
const WRITE_DEADLINE_MS := 2000
const RESPONSE_DEADLINE_MS := 5000
const INACTIVITY_DEADLINE_MS := 2000

var _host: String = "127.0.0.1"
var _port: int = 6379
var _tcp: StreamPeerTCP = null
var _connected: bool = false
var _connecting: bool = false
var _connect_callback: Callable = Callable()
var _connect_deadline_ms: int = 0
var _dangerous_commands_enabled: bool = false
var _parser := RespParser.new()
var _pending: Array[Dictionary] = []
var _results: Dictionary[int, Variant] = {}
var _write_buffer := PackedByteArray()
var _write_offset: int = 0
var _write_deadline_ms: int = 0
var _last_progress_ms: int = 0
var _next_request_id: int = 1

## Connects to Redis. Returns true on success.
func connect_to_server(host: String = "127.0.0.1", port: int = 6379, timeout_ms: int = 3000) -> bool:
	_host = host
	_port = port
	disconnect_from_server()
	_tcp = StreamPeerTCP.new()
	var err: Error = _tcp.connect_to_host(_host, _port)
	if err != OK:
		_tcp = null
		return false
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		_tcp.poll()
		var status: StreamPeerTCP.Status = _tcp.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED:
			_tcp.set_no_delay(true)
			_connected = true
			return true
		if status == StreamPeerTCP.STATUS_ERROR:
			_tcp = null
			return false
		OS.delay_msec(5)
	_tcp.disconnect_from_host()
	_tcp = null
	return false

## Returns true when connected.
func is_connected_to_server() -> bool:
	if _tcp == null:
		_connected = false
		return false
	_tcp.poll()
	_connected = _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED
	return _connected

## Disconnects from Redis.
func disconnect_from_server() -> void:
	_fail_pending(RedisResultType.Status.DISCONNECTED, "Redis connection closed")
	if _tcp != null:
		_tcp.disconnect_from_host()
		_tcp = null
	_connected = false
	_reset_io()

## Async connection. Calls callback(success: bool) when resolved.
func connect_async(host: String, port: int, callback: Callable, timeout_ms: int = 3000) -> void:
	disconnect_from_server()
	_host = host
	_port = port
	_tcp = StreamPeerTCP.new()
	var err: Error = _tcp.connect_to_host(_host, _port)
	if err != OK:
		_tcp = null
		callback.call(false)
		return
	_connecting = true
	_connect_callback = callback
	_connect_deadline_ms = Time.get_ticks_msec() + timeout_ms

## Poll connection state. Call each frame until it returns true (resolved).
func poll_connect() -> bool:
	if not _connecting:
		return true
	if _tcp == null:
		_finish_connect(false)
		return true
	_tcp.poll()
	var status: StreamPeerTCP.Status = _tcp.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED:
		_tcp.set_no_delay(true)
		_connected = true
		_finish_connect(true)
		return true
	if status == StreamPeerTCP.STATUS_ERROR:
		_tcp = null
		_finish_connect(false)
		return true
	if Time.get_ticks_msec() >= _connect_deadline_ms:
		_tcp.disconnect_from_host()
		_tcp = null
		_finish_connect(false)
		return true
	return false

func _finish_connect(success: bool) -> void:
	_connecting = false
	var cb: Callable = _connect_callback
	_connect_callback = Callable()
	_connect_deadline_ms = 0
	if cb.is_valid():
		cb.call(success)

## SET key value EX ttl_seconds. Returns true on success.
func set_value(key: String, value: String, ttl_seconds: int = 0) -> bool:
	if not is_connected_to_server():
		return false
	var args: Array[String] = ["SET", key, value]
	if ttl_seconds > 0:
		args.append("EX")
		args.append(str(ttl_seconds))
	var result: Variant = execute_sync(args)
	return result.status == RedisResultType.Status.OK and result.value == "OK"

## GET key. Returns the value or empty string if not found.
func get_value(key: String) -> String:
	var value: Variant = get_value_or_null(key)
	return "" if value == null else str(value)

## GET key. Returns null when the key is missing.
func get_value_or_null(key: String) -> Variant:
	if not is_connected_to_server():
		return null
	var result: Variant = execute_sync(["GET", key])
	if result.status == RedisResultType.Status.NULL:
		return null
	if result.status != RedisResultType.Status.OK or not result.value is PackedByteArray:
		return null
	return (result.value as PackedByteArray).get_string_from_utf8()

## DEL key. Returns true if key was deleted.
func del_key(key: String) -> bool:
	if not is_connected_to_server():
		return false
	var result: Variant = execute_sync(["DEL", key])
	return result.status == RedisResultType.Status.OK and result.value is int and result.value > 0

## KEYS pattern. Returns matching keys.
func keys(pattern: String) -> Array[String]:
	if not is_connected_to_server():
		return []
	return _string_array(execute_sync(["KEYS", pattern]))

## SCAN pattern. Returns matching keys without blocking Redis like KEYS can.
func scan_keys(pattern: String, count: int = 100) -> Array[String]:
	if not is_connected_to_server():
		return []
	var cursor: String = "0"
	var results: Array[String] = []
	while true:
		var command_result: Variant = execute_sync(["SCAN", cursor, "MATCH", pattern, "COUNT", str(maxi(count, 1))])
		if command_result.status != RedisResultType.Status.OK or not command_result.value is Array:
			return results
		var response: Array = command_result.value
		if response.size() < 2:
			return results
		cursor = _value_to_string(response[0])
		var keys_value: Variant = response[1]
		if keys_value is Array:
			for key_value: Variant in keys_value:
				results.append(_value_to_string(key_value))
		if cursor == "0":
			return results
	return results

## PING. Returns true if server responds PONG.
func ping() -> bool:
	if not is_connected_to_server():
		return false
	var result: Variant = execute_sync(["PING"])
	return result.status == RedisResultType.Status.OK and result.value == "PONG"

## FLUSHDB. Clears current database. Returns true on success.
func flushdb() -> bool:
	if not _dangerous_commands_enabled:
		return false
	if not is_connected_to_server():
		return false
	var result: Variant = execute_sync(["FLUSHDB"])
	return result.status == RedisResultType.Status.OK and result.value == "OK"

## Enables destructive commands such as FLUSHDB. Keep disabled in game/server runtime code.
func set_dangerous_commands_enabled(enabled: bool) -> void:
	_dangerous_commands_enabled = enabled

# --- Incremental requests and RESP protocol ---

func request(args: Array) -> int:
	var request_id := _next_request_id
	_next_request_id += 1
	if _pending.size() + _results.size() >= MAX_PENDING_REQUESTS:
		return -1
	if not is_connected_to_server():
		_results[request_id] = RedisResultType.new(RedisResultType.Status.DISCONNECTED, null, "Redis is disconnected")
		return request_id
	var frame := _encode_command(args)
	if frame.is_empty() or frame.size() > MAX_COMMAND_BYTES or _write_buffer.size() - _write_offset + frame.size() > MAX_IO_BUFFER_BYTES:
		_results[request_id] = RedisResultType.new(RedisResultType.Status.LIMIT_EXCEEDED, null, "Command exceeds approved bounds")
		return request_id
	var now := Time.get_ticks_msec()
	if _write_offset > 0:
		_write_buffer = _write_buffer.slice(_write_offset)
		_write_offset = 0
	if _write_buffer.is_empty():
		_write_deadline_ms = now + WRITE_DEADLINE_MS
	_write_buffer.append_array(frame)
	_pending.append({"id": request_id, "deadline": now + RESPONSE_DEADLINE_MS})
	if _last_progress_ms == 0:
		_last_progress_ms = now
	return request_id

func poll_io() -> void:
	if _tcp == null or _pending.is_empty():
		return
	_tcp.poll()
	if _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_close_with_error(RedisResultType.Status.DISCONNECTED, "Redis disconnected mid-frame")
		return
	var now := Time.get_ticks_msec()
	if _write_offset < _write_buffer.size():
		var write_result: Array = _tcp.put_partial_data(_write_buffer.slice(_write_offset))
		if write_result[0] != OK:
			_close_with_error(RedisResultType.Status.DISCONNECTED, "Redis write failed")
			return
		var written: int = write_result[1]
		if written > 0:
			_write_offset += written
			_last_progress_ms = now
		if _write_offset < _write_buffer.size() and now >= _write_deadline_ms:
			_close_with_error(RedisResultType.Status.TIMEOUT, "Redis write deadline exceeded")
			return
	else:
		_write_buffer.clear()
		_write_offset = 0
	var available := _tcp.get_available_bytes()
	if available > 0:
		var read_result: Array = _tcp.get_partial_data(mini(available, MAX_IO_BUFFER_BYTES))
		if read_result[0] != OK:
			_close_with_error(RedisResultType.Status.DISCONNECTED, "Redis read failed")
			return
		var bytes: PackedByteArray = read_result[1]
		if not bytes.is_empty():
			_last_progress_ms = now
			if not _parser.feed(bytes):
				var status := RedisResultType.Status.LIMIT_EXCEEDED if _parser.is_limit_error() else RedisResultType.Status.PROTOCOL_ERROR
				_close_with_error(status, _parser.error_message())
				return
	while _parser.has_reply() and not _pending.is_empty():
		var pending: Dictionary = _pending.pop_front()
		_results[int(pending.id)] = _reply_result(_parser.take_reply())
	if _pending.is_empty():
		_last_progress_ms = 0
		return
	now = Time.get_ticks_msec()
	if now >= int(_pending[0].deadline):
		_close_with_error(RedisResultType.Status.TIMEOUT, "Redis response deadline exceeded")
	elif now - _last_progress_ms >= INACTIVITY_DEADLINE_MS:
		_close_with_error(RedisResultType.Status.TIMEOUT, "Redis response inactivity deadline exceeded")

func take_result(request_id: int) -> Variant:
	if not _results.has(request_id):
		return null
	var result: Variant = _results[request_id]
	_results.erase(request_id)
	return result

func cancel(request_id: int) -> bool:
	for pending in _pending:
		if int(pending.id) == request_id:
			_results[request_id] = RedisResultType.new(RedisResultType.Status.CANCELLED, null, "Redis request cancelled")
			_pending.erase(pending)
			_close_with_error(RedisResultType.Status.DISCONNECTED, "Connection closed after cancellation")
			return true
	return false

func execute_sync(args: Array) -> Variant:
	var request_id := request(args)
	while not _results.has(request_id):
		poll_io()
		OS.delay_msec(1)
	return take_result(request_id)

func _encode_command(args: Array) -> PackedByteArray:
	var frame := ("*%d\r\n" % args.size()).to_utf8_buffer()
	for arg in args:
		var bytes: PackedByteArray = arg if arg is PackedByteArray else str(arg).to_utf8_buffer()
		frame.append_array(("$%d\r\n" % bytes.size()).to_utf8_buffer())
		frame.append_array(bytes)
		frame.append_array("\r\n".to_utf8_buffer())
		if frame.size() > MAX_COMMAND_BYTES:
			return PackedByteArray()
	return frame

func _reply_result(reply: Dictionary) -> Variant:
	match str(reply.kind):
		"null": return RedisResultType.new(RedisResultType.Status.NULL)
		"error": return RedisResultType.new(RedisResultType.Status.REDIS_ERROR, null, str(reply.value))
		"array": return RedisResultType.new(RedisResultType.Status.OK, _decode_reply_array(reply.value))
		_: return RedisResultType.new(RedisResultType.Status.OK, reply.value)

func _decode_reply_array(entries: Array) -> Array:
	var result: Array = []
	for entry: Dictionary in entries:
		if entry.kind == "array": result.append(_decode_reply_array(entry.value))
		elif entry.kind == "null": result.append(null)
		else: result.append(entry.value)
	return result

func _string_array(result: Variant) -> Array[String]:
	var values: Array[String] = []
	if result.status != RedisResultType.Status.OK or not result.value is Array:
		return values
	for value in result.value:
		values.append(_value_to_string(value))
	return values

func _value_to_string(value: Variant) -> String:
	return (value as PackedByteArray).get_string_from_utf8() if value is PackedByteArray else str(value)

func _close_with_error(status: int, message: String) -> void:
	_fail_pending(status, message)
	if _tcp != null:
		_tcp.disconnect_from_host()
		_tcp = null
	_connected = false
	_reset_io()

func _fail_pending(status: int, message: String) -> void:
	for pending in _pending:
		var request_id := int(pending.id)
		if not _results.has(request_id):
			_results[request_id] = RedisResultType.new(status, null, message)
	_pending.clear()

func _reset_io() -> void:
	_parser.reset()
	_write_buffer.clear()
	_write_offset = 0
	_write_deadline_ms = 0
	_last_progress_ms = 0
