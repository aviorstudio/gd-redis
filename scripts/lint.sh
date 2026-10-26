#!/usr/bin/env bash
set -euo pipefail
export RUNNER_TEMP="${RUNNER_TEMP:-$PWD/.artifacts/tmp}"
mkdir -p "$RUNNER_TEMP"
set -euo pipefail
python3 -m venv "$RUNNER_TEMP/gd-redis-workflow-contract"
python="$RUNNER_TEMP/gd-redis-workflow-contract/bin/python"
"$python" -m pip install --require-hashes -r tests/workflow-contract-requirements.txt
"$python" scripts/check-workflow-contract.py
"$python" -m unittest discover -s tests -p 'test_workflow_contract.py' -v

set -euo pipefail
test -f addon/plugin.cfg
