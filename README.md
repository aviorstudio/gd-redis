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

## Repository Layout

- `addon/`: Godot plugin source packaged for GDAM and manual installation.
- `addon/plugin.cfg`: plugin name, version, description, and entry script.
- `addon/src/`: reusable GDScript modules.
- `tests/`: Godot test project/scripts for addon behavior.
- `.github/workflows/ci.yml`: validates package shape and runs tests.
- `.github/workflows/release.yml`: creates GitHub release ZIPs and publishes to GDAM.

## Versioning And Releases

The version in `addon/plugin.cfg` is the addon package version. Releases are created from `main` with the manual release workflow and plain semver tags like `v0.0.1`; the workflow verifies `plugin.cfg`, builds `@aviorstudio_gd-redis.zip`, and publishes `@aviorstudio/gd-redis` to GDAM.

## Testing

Run locally with:

```sh
./tests/test.sh
```

CI runs the same test script when available.

## License

MIT

## Tests

Run `./tests/test.sh` with Godot and Docker installed. The suite starts a pinned,
disposable Redis container on a random loopback port and removes it on exit.
To use an existing local test Redis, set `REDIS_TEST_PORT`; the integration test
uses only unique keys with a 30-second TTL and never flushes the database.
Tests cover ASCII, accented text, CJK, emoji, CRLF, empty/large values, Unicode
keys, and subsequent commands on the same connection. RESP bulk lengths count
UTF-8 bytes, as required by the
[Redis protocol](https://redis.io/docs/latest/develop/reference/protocol-spec/#bulk-strings).
