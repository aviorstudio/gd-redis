# gd-redis

Minimal Redis client for Godot 4 using RESP over TCP.

This addon is intentionally a low-level Redis helper. It does not own app persistence policy, cache invalidation, matchmaking recovery, or game-specific key naming.

## Installation

### Via gdpm
`gdpm install @aviorstudio/gd-redis`

### Manual
Copy this directory into `addons/@aviorstudio_gd-redis/` and enable the plugin.

## Quick Start

```gdscript
const RedisClientModule = preload("res://addons/@aviorstudio_gd-redis/src/redis_client_module.gd")

var redis := RedisClientModule.new()
if redis.connect_to_server("127.0.0.1", 6379):
	redis.set_value("example:key", "value", 60)
	var value: String = redis.get_value("example:key")
```

## API Reference

- `connect_to_server(host, port, timeout_ms)`: blocking connection helper.
- `connect_async(host, port, callback, timeout_ms)` plus `poll_connect()`: non-blocking connection setup.
- `set_value(key, value, ttl_seconds)`: `SET`, optionally with `EX` TTL.
- `get_value(key)`: `GET`, returning an empty string for missing values or empty stored values.
- `get_value_or_null(key)`: `GET`, returning `null` for missing values.
- `del_key(key)`: `DEL`.
- `scan_keys(pattern, count)`: incremental `SCAN` wrapper that avoids `KEYS` for production-style discovery.
- `keys(pattern)`: direct `KEYS`; useful for local tools only.
- `ping()`: `PING`.
- `flushdb()`: disabled unless dangerous commands are explicitly enabled.

## Blocking Behavior

Most command methods are synchronous and poll the TCP peer while waiting for a response. Use them from server/headless code, tooling, or controlled lifecycle points. Avoid calling synchronous Redis operations in hot gameplay frames.

## Dangerous Commands

`flushdb()` is disabled by default. Enable it only in test or local tooling code:

```gdscript
redis.set_dangerous_commands_enabled(true)
redis.flushdb()
```

## Scope Boundary

- In scope: minimal RESP command helpers and typed convenience methods.
- Out of scope: cache policy, game key schemas, matchmaking recovery, TLS, and production Redis cluster management.

## Compatibility

- Godot 4.x native/server builds.
- Web exports cannot use raw TCP sockets.
- TLS and Redis Cluster are not currently supported.

## Testing

`./tests/test.sh`

## License

MIT
