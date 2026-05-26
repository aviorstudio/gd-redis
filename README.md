# gd-redis

Connect to Redis from Godot 4 native or server builds using the RESP protocol over TCP.

Use this addon for tools, dedicated servers, local development utilities, or controlled backend-style Godot processes that need simple Redis commands.

## Installation

### Via gdam

`gdam install @aviorstudio/gd-redis`

### Manual

Copy `addon/` into `res://addons/@aviorstudio_gd-redis/` and enable the plugin.

## Quick Start

```gdscript
const RedisClientModule = preload("res://addons/@aviorstudio_gd-redis/src/redis_client_module.gd")

var redis := RedisClientModule.new()

if redis.connect_to_server("127.0.0.1", 6379):
	redis.set_value("example:key", "value", 60)
	var value: Variant = redis.get_value_or_null("example:key")
	print(value)
```

## Common Commands

- `connect_to_server(host, port, timeout_ms)`: connect synchronously.
- `connect_async(host, port, callback, timeout_ms)` and `poll_connect()`: connect without blocking startup.
- `set_value(key, value, ttl_seconds)`: run `SET`, optionally with an `EX` TTL.
- `get_value(key)`: run `GET`, returning an empty string for missing or empty values.
- `get_value_or_null(key)`: run `GET`, returning `null` for missing values.
- `del_key(key)`: run `DEL`.
- `scan_keys(pattern, count)`: iterate keys without using `KEYS`.
- `ping()`: check the connection.

## Dangerous Commands

`flushdb()` is disabled by default. Enable it only in tests or local tools:

```gdscript
redis.set_dangerous_commands_enabled(true)
redis.flushdb()
```

## Notes

- Most command methods are synchronous and wait for the TCP peer to respond.
- Avoid synchronous Redis operations in hot gameplay frames.
- Web exports cannot use raw TCP sockets.
- TLS and Redis Cluster are not currently supported.

## Testing

`./tests/test.sh`

## License

MIT
