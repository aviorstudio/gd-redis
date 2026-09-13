class_name RedisResult
extends RefCounted

enum Status {
	OK,
	NULL,
	REDIS_ERROR,
	TIMEOUT,
	DISCONNECTED,
	PROTOCOL_ERROR,
	LIMIT_EXCEEDED,
	CANCELLED,
}

var status: Status
var value: Variant
var message: String

func _init(result_status: Status, result_value: Variant = null, result_message: String = "") -> void:
	status = result_status
	value = result_value
	message = result_message

func is_ok() -> bool:
	return status == Status.OK or status == Status.NULL
