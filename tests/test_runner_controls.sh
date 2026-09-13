#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
runner="$script_dir/run_tests.sh"; fixtures="$script_dir/runner_fixtures"; scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
expect_fail() {
  rm -f "$scratch"/*; cp "$fixtures/$1" "$scratch/$1"
  if GODOT_TEST_TIMEOUT_SECONDS=1 "$runner" "$scratch"; then echo "FAIL: gate accepted negative control $1" >&2; exit 1; fi
  echo "PASS gate rejected $1"
}
for fixture in runtime_error_zero_exit_test.gd assertion_overwritten_test.gd unreachable_assertion_test.gd parse_failure_test.gd timeout_test.gd; do expect_fail "$fixture"; done
rm -f "$scratch"/*
if GODOT_TEST_TIMEOUT_SECONDS=1 "$runner" "$scratch"; then echo "FAIL: gate accepted missing suite" >&2; exit 1; fi
echo "PASS gate rejected missing suite"
cp "$fixtures/pass_test.gd" "$scratch/pass_test.gd"
GODOT_TEST_TIMEOUT_SECONDS=2 "$runner" "$scratch"
echo "PASS gd-redis runner controls restored"
