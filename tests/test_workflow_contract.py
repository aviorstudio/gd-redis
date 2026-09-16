"""Negative/restored controls use the actual release workflow, never publish."""

import copy
import importlib.util
import pathlib
import subprocess
import sys
import tempfile
import unittest

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/check-workflow-contract.py"
spec = importlib.util.spec_from_file_location("workflow_contract", SCRIPT)
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)


class WorkflowContractTests(unittest.TestCase):
    def setUp(self):
        self.workflow = yaml.safe_load((ROOT / ".github/workflows/release.yml").read_text())

    def step(self, action, workflow=None):
        return next(
            step
            for job in (workflow or self.workflow)["jobs"].values()
            for step in job.get("steps", [])
            if step.get("uses", "").startswith(f"aviorstudio/gdam-actions/{action}@")
        )

    def run_gate(self, workflow, expected):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "release.yml"
            path.write_text(yaml.safe_dump(workflow))
            result = subprocess.run(
                [sys.executable, str(SCRIPT), str(path)],
                capture_output=True, text=True, timeout=10,
            )
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def test_old_fixed_and_reinjected_version(self):
        old = copy.deepcopy(self.workflow)
        self.step("publish", old)["with"]["version"] = "${{ steps.release.outputs.version }}"
        self.assertIn("publish: unsupported inputs: version", self.run_gate(old, 1))
        self.run_gate(self.workflow, 0)
        self.assertIn("publish: unsupported inputs: version", self.run_gate(old, 1))
        self.run_gate(self.workflow, 0)

    def test_install_version_is_valid(self):
        self.assertEqual(self.step("install")["with"]["version"], "v0.0.8")
        contract.check(self.workflow)

    def test_unknown_inputs_fail_on_either_action(self):
        for action in ("publish", "install"):
            with self.subTest(action=action):
                workflow = copy.deepcopy(self.workflow)
                self.step(action, workflow)["with"]["typo"] = "value"
                self.assertIn("unsupported inputs: typo", self.run_gate(workflow, 1))

    def test_required_publish_inputs_fail_closed(self):
        for name in ("tag", "secret-key"):
            with self.subTest(name=name):
                workflow = copy.deepcopy(self.workflow)
                del self.step("publish", workflow)["with"][name]
                self.assertIn("missing required inputs", self.run_gate(workflow, 1))

    def test_new_action_revision_requires_contract_update(self):
        self.step("publish")["uses"] = "aviorstudio/gdam-actions/publish@main"
        self.assertIn("Unverified GDAM action contract", self.run_gate(self.workflow, 1))

    def test_missing_publish_is_not_silently_skipped(self):
        self.step("publish")["uses"] = "unrelated/action@main"
        self.assertIn("both install and publish", self.run_gate(self.workflow, 1))


if __name__ == "__main__":
    unittest.main()
