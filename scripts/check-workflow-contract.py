#!/usr/bin/env python3
"""Check GDAM action inputs against immutable upstream contract snapshots."""

import hashlib
import pathlib
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[1]
ACTION_SHA = "6677226d9353df1d410f3e7f5075e13b3b7d5308"


def check(workflow):
    contracts = {
        name: yaml.safe_load(
            (ROOT / f"tests/fixtures/gdam-actions/{ACTION_SHA}/{name}.yml").read_text()
        )["inputs"]
        for name in ("publish",)
    }
    if hashlib.sha256((ROOT / f"tests/fixtures/gdam-actions/{ACTION_SHA}/publish.yml").read_bytes()).hexdigest() != "9b9de814668665eb77e34afab9929e9585b1f0047f9c31a8b05706447d27bd10":
        raise ValueError("immutable publishing metadata changed")
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
            if inputs.get("api-key") != "${{ secrets.GDAM_API_KEY }}":
                raise ValueError("publish: missing required inputs: api-key")
    if seen != set(contracts):
        raise ValueError("Release must exercise the verified publish contract")


def main():
    path = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / ".github/workflows/release.yml"
    try:
        check(yaml.safe_load(path.read_text()))
    except (ValueError, KeyError, TypeError, yaml.YAMLError) as error:
        print(f"FAIL workflow contract: {error}", file=sys.stderr)
        return 1
    print("PASS workflow contract: pinned Clerk GDAM publish inputs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
