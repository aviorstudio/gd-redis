#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fixture_id=""
resp_fixture_pid=""
resp_fixture_log=""
cleanup() {
    if [ -n "$resp_fixture_pid" ]; then
        kill "$resp_fixture_pid" 2>/dev/null || true
        wait "$resp_fixture_pid" 2>/dev/null || true
    fi
    if [ -n "$fixture_id" ]; then
        docker rm -f "$fixture_id" >/dev/null
    fi
    if [ -n "$resp_fixture_log" ]; then rm -rf "$(dirname "$resp_fixture_log")"; fi
}
trap cleanup EXIT
if [ -z "${REDIS_TEST_PORT:-}" ]; then
    fixture_id=$(docker run --rm -d -p 127.0.0.1::6379 \
        redis:7-alpine@sha256:ff02b58f971e7d7d156a1267e283fcbbeee91773b6aa36c49dac28ecfe28eadf \
        redis-server --appendonly no --save "")
    REDIS_TEST_PORT=$(docker port "$fixture_id" 6379/tcp | sed 's/.*://')
fi
export REDIS_TEST_PORT
resp_fixture_dir="$(mktemp -d)"
resp_fixture_log="$resp_fixture_dir/server.log"
python3 "$SCRIPT_DIR/resp_fixture_server.py" "$resp_fixture_dir/port" >"$resp_fixture_log" 2>&1 &
resp_fixture_pid=$!
for _attempt in $(seq 1 100); do
    if [ -s "$resp_fixture_dir/port" ]; then break; fi
    if ! kill -0 "$resp_fixture_pid" 2>/dev/null; then cat "$resp_fixture_log"; exit 1; fi
    sleep 0.05
done
test -s "$resp_fixture_dir/port" || { cat "$resp_fixture_log"; exit 1; }
export RESP_TEST_PORT="$(cat "$resp_fixture_dir/port")"
"$SCRIPT_DIR/run_tests.sh" "$SCRIPT_DIR"
