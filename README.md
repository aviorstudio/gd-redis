<!-- Generated from private documentation source. Do not edit directly. Source SHA256: 393bfc91b825b8954688c0136fca849263c049bd6cbb6334aae07de44f1f494f -->

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
- This release targets the deployment on a trusted Docker network; TLS,
  Redis AUTH/ACL setup, and Redis Cluster are not currently supported.
- Commands/bulk values are limited to 8 MiB, buffered input to 16 MiB, nesting
  to 16, aggregate RESP elements to 4,096, and pending requests/replies to 64.
  Protocol, limit, timeout, cancellation, and mid-frame disconnect failures close
  the connection so a later command cannot consume a stale reply.


## License

See `LICENSE`.

## Contributor commands

Install [mise](https://mise.jdx.dev/), then run:

```sh
make setup
make build
make test
```

`make help` lists the implemented commands offline. Mise pins SDK versions; the generated Makefile pins the shared cookbook. `make build` packages and verifies outputs, and `make test` runs the declared checks without rebuilding. Run `make build` again after changing source before packaged integration or browser tests. `make fmt` formats addon and test source; intentional invalid fixtures remain unchanged. `make clean` removes declared generated outputs.
