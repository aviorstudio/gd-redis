<!-- Generated from private documentation source. Do not edit directly. Source SHA256: be2c32c78f8666f5ac1116844bfa537187f25d74616b2df2e21319a71f91f9de -->

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
- `request(args)`, `poll_io()`, `take_result(id)`, and `cancel(id)`: submit
  bounded non-blocking commands and consume typed `RedisResult` outcomes.

Bulk replies remain `PackedByteArray` through the incremental API so binary data
is not decoded or changed. The convenience string methods decode bulk bytes as
UTF-8 for existing server/tooling consumers.

## Dangerous Commands

`flushdb()` is disabled by default. Enable it only in tests or local tools:

```gdscript
redis.set_dangerous_commands_enabled(true)
redis.flushdb()
```

## Notes

- Convenience command methods are synchronous wrappers over bounded incremental
  I/O. Connect, write, inactivity, and absolute-response deadlines are 3, 2, 2,
  and 5 seconds respectively.
- Avoid synchronous Redis operations in hot gameplay frames.
- Web exports cannot use raw TCP sockets.
- This release targets the confirmed private Docker-network deployment; TLS,
  Redis AUTH/ACL setup, and Redis Cluster are not currently supported.
- Commands/bulk values are limited to 8 MiB, buffered input to 16 MiB, nesting
  to 16, aggregate RESP elements to 4,096, and pending requests/replies to 64.
  Protocol, limit, timeout, cancellation, and mid-frame disconnect failures close
  the connection so a later command cannot consume a stale reply.


## License

See `LICENSE`.

## Standard developer commands

Run `make install` to install the checksum-pinned engineering release and exact Godot engine into checkout-owned output. Run `make check` for the existing package, behavioral and editor-lifecycle gates in order. `make build` creates the package; `make test` runs the behavioral gates, and `make artifact-smoke` checks the built package in the editor. `make clean` removes generated output. Development happens in a consuming Godot project, so standalone dev/stop are unsupported.
