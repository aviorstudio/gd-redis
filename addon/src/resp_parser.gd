class_name RedisRespParser
extends RefCounted

const MAX_BULK_BYTES := 8 * 1024 * 1024
const MAX_BUFFER_BYTES := 16 * 1024 * 1024
const MAX_DEPTH := 16
const MAX_AGGREGATE_ELEMENTS := 4096
const MAX_QUEUED_REPLIES := 64

var _buffer := PackedByteArray()
var _replies: Array[Dictionary] = []
var _error: String = ""
var _limit_error: bool = false

func feed(bytes: PackedByteArray) -> bool:
	if has_error():
		return false
	if _buffer.size() + bytes.size() > MAX_BUFFER_BYTES:
		_fail("RESP buffer exceeds 16 MiB", true)
		return false
	_buffer.append_array(bytes)
	while not _buffer.is_empty():
		var aggregate := {"count": 0}
		var parsed: Dictionary = _parse_value(0, 0, aggregate)
		match int(parsed.state):
			0:
				return true
			1:
				if _replies.size() >= MAX_QUEUED_REPLIES:
					_fail("RESP reply queue exceeds 64", true)
					return false
				_replies.append(parsed.value)
				_buffer = _buffer.slice(int(parsed.next))
			_:
				_fail(str(parsed.message), bool(parsed.get("limit", false)))
				return false
	return true

func has_reply() -> bool:
	return not _replies.is_empty()

func take_reply() -> Dictionary:
	return {} if _replies.is_empty() else _replies.pop_front()

func has_error() -> bool:
	return not _error.is_empty()

func error_message() -> String:
	return _error

func is_limit_error() -> bool:
	return _limit_error

func reset() -> void:
	_buffer.clear()
	_replies.clear()
	_error = ""
	_limit_error = false

func _parse_value(offset: int, depth: int, aggregate: Dictionary) -> Dictionary:
	if depth > MAX_DEPTH:
		return _parse_error("RESP nesting exceeds 16", true)
	if offset >= _buffer.size():
		return {"state": 0}
	aggregate.count += 1
	if aggregate.count > MAX_AGGREGATE_ELEMENTS:
		return _parse_error("RESP aggregate exceeds 4096 elements", true)
	var prefix: int = _buffer[offset]
	var line_end: int = _find_crlf(offset + 1)
	if line_end == -1:
		return {"state": 0}
	var payload_bytes: PackedByteArray = _buffer.slice(offset + 1, line_end)
	var payload: String = payload_bytes.get_string_from_utf8()
	var next: int = line_end + 2
	match prefix:
		43: # +
			return _complete(next, {"kind": "simple", "value": payload})
		45: # -
			return _complete(next, {"kind": "error", "value": payload})
		58: # :
			var integer := _parse_decimal(payload, false)
			if not integer.ok:
				return _parse_error("Malformed RESP integer")
			return _complete(next, {"kind": "integer", "value": integer.value})
		36: # $
			var bulk_length := _parse_decimal(payload, true)
			if not bulk_length.ok:
				return _parse_error("Malformed RESP bulk length")
			var length: int = bulk_length.value
			if length == -1:
				return _complete(next, {"kind": "null", "value": null})
			if length < -1:
				return _parse_error("Invalid negative RESP bulk length")
			if length > MAX_BULK_BYTES:
				return _parse_error("RESP bulk exceeds 8 MiB", true)
			if next + length + 2 > _buffer.size():
				return {"state": 0}
			if _buffer[next + length] != 13 or _buffer[next + length + 1] != 10:
				return _parse_error("RESP bulk missing CRLF")
			return _complete(next + length + 2, {"kind": "bulk", "value": _buffer.slice(next, next + length)})
		42: # *
			var array_length := _parse_decimal(payload, true)
			if not array_length.ok:
				return _parse_error("Malformed RESP array length")
			var count: int = array_length.value
			if count == -1:
				return _complete(next, {"kind": "null", "value": null})
			if count < -1:
				return _parse_error("Invalid negative RESP array length")
			if count > MAX_AGGREGATE_ELEMENTS:
				return _parse_error("RESP array exceeds 4096 elements", true)
			var values: Array[Dictionary] = []
			var cursor := next
			for _index in range(count):
				var child := _parse_value(cursor, depth + 1, aggregate)
				if int(child.state) != 1:
					return child
				values.append(child.value)
				cursor = child.next
			return _complete(cursor, {"kind": "array", "value": values})
		_:
			return _parse_error("Unknown RESP type byte")

func _find_crlf(start: int) -> int:
	for index in range(start, _buffer.size() - 1):
		if _buffer[index] == 13 and _buffer[index + 1] == 10:
			return index
	return -1

func _parse_decimal(text: String, allow_negative_one: bool) -> Dictionary:
	if text.is_empty():
		return {"ok": false}
	var start := 0
	if text[0] == "-":
		if not allow_negative_one:
			start = 1
		else:
			start = 1
	if start == text.length():
		return {"ok": false}
	for index in range(start, text.length()):
		var code := text.unicode_at(index)
		if code < 48 or code > 57:
			return {"ok": false}
	return {"ok": true, "value": int(text)}

func _complete(next: int, value: Dictionary) -> Dictionary:
	return {"state": 1, "next": next, "value": value}

func _parse_error(message: String, limit: bool = false) -> Dictionary:
	return {"state": 2, "message": message, "limit": limit}

func _fail(message: String, limit: bool = false) -> void:
	_error = message
	_limit_error = limit
