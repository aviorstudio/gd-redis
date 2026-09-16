#!/usr/bin/env python3
"""Check GDAM action inputs against immutable upstream contract snapshots."""

import pathlib
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[1]
ACTION_SHA = "d735444eb470194585def44521d5d91df2260e63"


def check(workflow):
    contracts = {
        name: yaml.safe_load(
            (ROOT / f"tests/fixtures/gdam-actions/{name}.yml").read_text()
        )["inputs"]
        for name in ("publish", "install")
    }
    seen = set()
    for job in workflow["jobs"].values():
        for step in job.get("steps", []):
            uses = step.get("uses", "")
            if not uses.startswith("aviorstudio/gdam-actions/"):
                continue
            action, _, revision = uses.removeprefix("aviorstudio/gdam-actions/").partition("@")
            if action not in contracts or revision != ACTION_SHA:
                raise ValueError(f"Unverified GDAM action contract: {uses}")
            inputs = step.get("with", {})
            unknown = set(inputs) - set(contracts[action])
            if unknown:
                raise ValueError(f"{action}: unsupported inputs: {', '.join(sorted(unknown))}")
            required = {
                key for key, definition in contracts[action].items()
                if definition.get("required") is True
            }
            missing = {key for key in required if not inputs.get(key)}
            if missing:
                raise ValueError(f"{action}: missing required inputs: {', '.join(sorted(missing))}")
            seen.add(action)
    if seen != set(contracts):
        raise ValueError("Release must exercise both install and publish contracts")


def main():
    path = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / ".github/workflows/release.yml"
    try:
        check(yaml.safe_load(path.read_text()))
    except (ValueError, KeyError, TypeError, yaml.YAMLError) as error:
        print(f"FAIL workflow contract: {error}", file=sys.stderr)
        return 1
    print("PASS workflow contract: pinned GDAM install and publish inputs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
