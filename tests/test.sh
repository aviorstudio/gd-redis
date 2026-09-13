#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fixture_id=""
cleanup() {
    if [ -n "$fixture_id" ]; then
        docker rm -f "$fixture_id" >/dev/null
    fi
}
trap cleanup EXIT
if [ -z "${REDIS_TEST_PORT:-}" ]; then
    fixture_id=$(docker run --rm -d -p 127.0.0.1::6379 \
        redis:7-alpine@sha256:ff02b58f971e7d7d156a1267e283fcbbeee91773b6aa36c49dac28ecfe28eadf \
        redis-server --appendonly no --save "")
    REDIS_TEST_PORT=$(docker port "$fixture_id" 6379/tcp | sed 's/.*://')
fi
export REDIS_TEST_PORT
"$SCRIPT_DIR/run_tests.sh" "$SCRIPT_DIR"
