extends SceneTree

const Parser = preload("res://addon/src/resp_parser.gd")

func _init() -> void:
	_test_byte_fragmentation_unicode_binary_and_pipeline()
	_test_arbitrary_fragmentation_and_nested_array()
	_test_malformed_and_limit_controls()
	print("PASS gd-redis resp_parser_test")
	quit(0)

func _test_byte_fragmentation_unicode_binary_and_pipeline() -> void:
	var parser := Parser.new()
	var binary := PackedByteArray([0, 255, 13, 10, 128])
	var unicode := "盾と🦊".to_utf8_buffer()
	var frame := _bulk(unicode)
	frame.append_array(_bulk(binary))
	frame.append_array("+PONG\r\n".to_utf8_buffer())
	for byte in frame:
		_assert(parser.feed(PackedByteArray([byte])), "byte-fragmented frame rejected")
	var first := parser.take_reply()
	var second := parser.take_reply()
	var third := parser.take_reply()
	_assert(first.value == unicode, "Unicode bulk bytes changed")
	_assert(second.value == binary, "binary bulk bytes changed")
	_assert(third.value == "PONG" and not parser.has_reply(), "pipeline replies changed")

func _test_arbitrary_fragmentation_and_nested_array() -> void:
	var parser := Parser.new()
	var frame := "*2\r\n*2\r\n:1\r\n$3\r\nfoo\r\n$3\r\nbar\r\n".to_utf8_buffer()
	for split in [1, 4, 2, 7, 3, 9, 5, 99]:
		if frame.is_empty(): break
		var take: int = mini(split, frame.size())
		_assert(parser.feed(frame.slice(0, take)), "arbitrary fragment rejected")
		frame = frame.slice(take)
	_assert(parser.has_reply(), "nested fragmented array never completed")
	var reply := parser.take_reply()
	_assert(reply.kind == "array" and reply.value.size() == 2, "nested array shape changed")

func _test_malformed_and_limit_controls() -> void:
	for malformed in ["$x\r\n", "$-2\r\n", "*-2\r\n", "$3\r\nabcXX", "?wat\r\n"]:
		var parser := Parser.new()
		_assert(not parser.feed(malformed.to_utf8_buffer()) and parser.has_error(), "malformed frame accepted")
	var huge := Parser.new()
	_assert(not huge.feed("$8388609\r\n".to_utf8_buffer()) and huge.is_limit_error(), "huge bulk accepted")
	var nested := Parser.new()
	var frame := ""
	for _index in range(17): frame += "*1\r\n"
	frame += ":1\r\n"
	_assert(not nested.feed(frame.to_utf8_buffer()) and nested.is_limit_error(), "deep nesting accepted")
	var aggregate := Parser.new()
	_assert(not aggregate.feed("*4097\r\n".to_utf8_buffer()) and aggregate.is_limit_error(), "oversized aggregate accepted")
	var queue := Parser.new()
	_assert(not queue.feed("+OK\r\n".repeat(65).to_utf8_buffer()) and queue.is_limit_error(), "reply queue over 64 accepted")
	var buffer := Parser.new()
	var oversized_buffer := PackedByteArray()
	oversized_buffer.resize(Parser.MAX_BUFFER_BYTES + 1)
	_assert(not buffer.feed(oversized_buffer) and buffer.is_limit_error(), "buffer over 16 MiB accepted")
	var restored := Parser.new()
	_assert(restored.feed("$2\r\nok\r\n".to_utf8_buffer()) and restored.take_reply().value == "ok".to_utf8_buffer(), "restored parser failed")

func _bulk(value: PackedByteArray) -> PackedByteArray:
	var frame := ("$%d\r\n" % value.size()).to_utf8_buffer()
	frame.append_array(value)
	frame.append_array("\r\n".to_utf8_buffer())
	return frame

func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
