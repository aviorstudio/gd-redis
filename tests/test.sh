#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
GODOT="${GODOT_BIN:-godot}"
fixture_id=""
log_dir=$(mktemp -d)
cleanup() {
    if [ -n "$fixture_id" ]; then
        docker rm -f "$fixture_id" >/dev/null
    fi
    rm -rf "$log_dir"
}
trap cleanup EXIT
if [ -z "${REDIS_TEST_PORT:-}" ]; then
    fixture_id=$(docker run --rm -d -p 127.0.0.1::6379 \
        redis:7-alpine@sha256:ff02b58f971e7d7d156a1267e283fcbbeee91773b6aa36c49dac28ecfe28eadf \
        redis-server --appendonly no --save "")
    REDIS_TEST_PORT=$(docker port "$fixture_id" 6379/tcp | sed 's/.*://')
fi
export REDIS_TEST_PORT
for test in "$SCRIPT_DIR"/*_test.gd; do
    echo "Running $(basename "$test")..."
    log="$log_dir/$(basename "$test").log"
    if ! timeout 45 "$GODOT" --headless --path "$ROOT_DIR" --script "$test" >"$log" 2>&1; then
        cat "$log"
        exit 1
    fi
    cat "$log"
    if grep -Eq '(^|[[:space:]])(SCRIPT ERROR:|ERROR:|FAIL:)' "$log"; then
        exit 1
    fi
done
