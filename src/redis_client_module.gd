## Redis client module for GDScript using RESP protocol over TCP.
class_name RedisClientModule
extends RefCounted

var _host: String = "127.0.0.1"
var _port: int = 4003
var _tcp: StreamPeerTCP = null
var _connected: bool = false

## Connects to Redis. Returns true on success.
func connect_to_server(host: String = "127.0.0.1", port: int = 4003, timeout_ms: int = 3000) -> bool:
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
	if _tcp != null:
		_tcp.disconnect_from_host()
		_tcp = null
	_connected = false

## SET key value EX ttl_seconds. Returns true on success.
func set_value(key: String, value: String, ttl_seconds: int = 0) -> bool:
	if not is_connected_to_server():
		return false
	var args: Array[String] = ["SET", key, value]
	if ttl_seconds > 0:
		args.append("EX")
		args.append(str(ttl_seconds))
	_send_command(args)
	var response: String = _read_line()
	return response == "+OK"

## GET key. Returns the value or empty string if not found.
func get_value(key: String) -> String:
	if not is_connected_to_server():
		return ""
	_send_command(["GET", key])
	return _read_bulk_string()

## DEL key. Returns true if key was deleted.
func del_key(key: String) -> bool:
	if not is_connected_to_server():
		return false
	_send_command(["DEL", key])
	var response: String = _read_line()
	return response.begins_with(":") and int(response.substr(1)) > 0

## KEYS pattern. Returns matching keys.
func keys(pattern: String) -> Array[String]:
	if not is_connected_to_server():
		return []
	_send_command(["KEYS", pattern])
	return _read_array()

## PING. Returns true if server responds PONG.
func ping() -> bool:
	if not is_connected_to_server():
		return false
	_send_command(["PING"])
	var response: String = _read_line()
	return response == "+PONG"

## FLUSHDB. Clears current database. Returns true on success.
func flushdb() -> bool:
	if not is_connected_to_server():
		return false
	_send_command(["FLUSHDB"])
	var response: String = _read_line()
	return response == "+OK"

# --- RESP Protocol ---

func _send_command(args: Array) -> void:
	var cmd: String = "*%d\r\n" % args.size()
	for arg in args:
		var s: String = str(arg)
		cmd += "$%d\r\n%s\r\n" % [s.length(), s]
	_tcp.put_data(cmd.to_utf8_buffer())

func _read_line() -> String:
	var result: String = ""
	var deadline: int = Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		_tcp.poll()
		if _tcp.get_available_bytes() > 0:
			break
		OS.delay_msec(1)
	while _tcp.get_available_bytes() > 0:
		var byte_arr: Array = _tcp.get_data(1)
		if byte_arr[0] != OK:
			break
		var byte_val: int = (byte_arr[1] as PackedByteArray)[0]
		if byte_val == 13: # \r
			_tcp.get_data(1) # consume \n
			break
		result += char(byte_val)
	return result

func _read_bulk_string() -> String:
	var header: String = _read_line()
	if header.begins_with("$-1"):
		return ""
	if not header.begins_with("$"):
		return ""
	var length: int = int(header.substr(1))
	if length <= 0:
		_read_line() # consume empty \r\n
		return ""
	var data_result: Array = _tcp.get_data(length)
	if data_result[0] != OK:
		return ""
	_tcp.get_data(2) # consume \r\n
	return (data_result[1] as PackedByteArray).get_string_from_utf8()

func _read_array() -> Array[String]:
	var header: String = _read_line()
	if not header.begins_with("*"):
		return []
	var count: int = int(header.substr(1))
	if count <= 0:
		return []
	var results: Array[String] = []
	for i in range(count):
		results.append(_read_bulk_string())
	return results
