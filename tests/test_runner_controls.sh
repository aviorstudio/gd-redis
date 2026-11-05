#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
runner="${TOOLS_ROOT:?Pinned cookbook required}/helpers/godot-test.py"; fixtures="$script_dir/runner_fixtures"; scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
expect_fail() {
  rm -f "$scratch"/*; cp "$fixtures/$1" "$scratch/$1"
  if python3 "$runner" --project "$script_dir/.." --directory "$scratch" --sentinel-prefix "PASS gd-redis" --timeout 1; then echo "FAIL: gate accepted negative control $1" >&2; exit 1; fi
  echo "PASS gate rejected $1"
}
for fixture in runtime_error_zero_exit_test.gd assertion_overwritten_test.gd unreachable_assertion_test.gd parse_failure_test.gd timeout_test.gd; do expect_fail "$fixture"; done
rm -f "$scratch"/*
if python3 "$runner" --project "$script_dir/.." --directory "$scratch" --sentinel-prefix "PASS gd-redis" --timeout 1; then echo "FAIL: gate accepted missing suite" >&2; exit 1; fi
echo "PASS gate rejected missing suite"
cp "$fixtures/pass_test.gd" "$scratch/pass_test.gd"
python3 "$runner" --project "$script_dir/.." --directory "$scratch" --sentinel-prefix "PASS gd-redis" --timeout 2
echo "PASS gd-redis runner controls restored"
