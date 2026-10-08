#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("qa_launch_registry", ROOT / "scripts/qa-launch-registry.py")
runtime = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = runtime
spec.loader.exec_module(runtime)


def git(repo, *args):
    return subprocess.check_output(
        ["git", "-C", str(repo), *args], stderr=subprocess.DEVNULL
    ).decode().strip()


def init(repo, remote, ignores=""):
    repo.mkdir(parents=True)
    git(repo, "init", "-q", "-b", "main")
    git(repo, "config", "user.name", "QA Fixture")
    git(repo, "config", "user.email", "qa@example.invalid")
    git(repo, "config", "commit.gpgsign", "false")
    git(repo, "remote", "add", "origin", remote)
    (repo / ".gitignore").write_text(ignores)
    (repo / "README.md").write_text("fixture\n")
    git(repo, "add", ".")
    git(repo, "commit", "-qm", "fixture")


class RegistryTest(unittest.TestCase):
    def setUp(self):
        self.fixture = tempfile.TemporaryDirectory(prefix="qa_registry_test.")
        self.addCleanup(self.fixture.cleanup)
        self.root = Path(self.fixture.name).resolve()
        self.company = self.root / "company"
        self.product = self.company / "product/susugigi"
        self.repo = self.product / "no5_product_development/no2_accounting_app"
        init(self.company, "https://example.invalid/company.git", "product/\n")
        init(self.product, "https://github.com/almightyken0425/susugigi.git", "no5_product_development/\n")
        init(self.repo, "https://github.com/almightyken0425/susugigi-impl-no2-accounting-app.git")
        self.commit = git(self.repo, "rev-parse", "HEAD")
        self.tree = git(self.repo, "rev-parse", "HEAD^{tree}")
        git(self.repo, "checkout", "--detach", "-q")
        registry_file = self.root / "registry.md"
        registry_file.write_text((ROOT / "data/products/products_registry.md").read_text().replace(
            "~/Doc/ai-company", str(self.company)
        ))
        self.registry = runtime.policy.ProductRegistry.load(
            registry_file, ROOT / "data/products/layer_manifest.yaml"
        )
        self.scratch = tempfile.TemporaryDirectory(prefix="sim-review-stream.")
        self.addCleanup(self.scratch.cleanup)
        self.directory = Path(self.scratch.name).resolve()
        self.port_check = patch.object(runtime, "require_port_available")
        self.port_check.start()
        self.addCleanup(self.port_check.stop)

    def register(self, **overrides):
        args = dict(repo=self.repo, commit=self.commit, tree=self.tree,
                    directory=self.directory, registry=self.registry)
        args.update(overrides)
        return runtime.register(**args)

    def test_private_registration_preserves_tracked_launch_file(self):
        canonical = self.company / ".codex/launch.json"
        canonical.parent.mkdir()
        original = b'{"configurations":[{"name":"design","metroPort":8081}]}\n'
        canonical.write_bytes(original)
        git(self.company, "add", ".codex/launch.json")
        git(self.company, "commit", "-qm", "existing launch registry")
        result = self.register()
        entry = json.loads(result.read_text())["configurations"][0]
        self.assertEqual((result.parent / entry["directory"]).resolve(), self.repo)
        self.assertFalse(Path(entry["directory"]).is_absolute())
        self.assertEqual(entry["metroPort"], 8081)
        self.assertEqual(canonical.read_bytes(), original)
        self.assertEqual(git(self.company, "status", "--porcelain"), "")
        self.assertEqual(result.stat().st_mode & 0o777, 0o600)

    def test_rejects_named_branch(self):
        git(self.repo, "checkout", "main", "-q")
        with self.assertRaisesRegex(runtime.Rejected, "TARGET"):
            self.register()
        self.assertFalse((self.directory / "launch.json").exists())

    def test_rejects_dirty_checkout_and_wrong_revision(self):
        (self.repo / "README.md").write_text("changed\n")
        with self.assertRaises(runtime.Rejected):
            self.register()
        git(self.repo, "checkout", "--", "README.md")
        for overrides in (dict(commit="0"*40), dict(tree="0"*40), dict(commit="HEAD")):
            with self.subTest(overrides=overrides), self.assertRaises(runtime.Rejected):
                self.register(**overrides)

    def test_rejects_linked_worktree_and_external_clone(self):
        linked = self.root / "linked"
        git(self.repo, "worktree", "add", "--detach", str(linked), self.commit)
        with self.assertRaises(runtime.Rejected):
            self.register(repo=linked)
        clone = self.root / "clone"
        subprocess.run(["git", "clone", "-q", str(self.repo), str(clone)], check=True)
        git(clone, "remote", "set-url", "origin", git(self.repo, "remote", "get-url", "origin"))
        with self.assertRaises(runtime.Rejected):
            self.register(repo=clone)

    def test_rejects_changed_remote(self):
        git(self.repo, "remote", "set-url", "origin", "https://example.invalid/imposter.git")
        with self.assertRaises(runtime.Rejected):
            self.register()

    def test_rejects_git_environment_override(self):
        with patch.dict(os.environ, {"GIT_WORK_TREE": str(self.repo)}):
            with self.assertRaises(runtime.Rejected):
                self.register()
        self.assertFalse((self.directory / "launch.json").exists())

    def test_rejects_repo_output_symlink_and_shared_directory(self):
        inside = self.repo / "sim-review-stream.owned"
        inside.mkdir(mode=0o700)
        with self.assertRaises(runtime.Rejected):
            self.register(directory=inside)
        alias = self.root / "alias"
        alias.symlink_to(self.directory)
        with self.assertRaises(runtime.Rejected):
            self.register(directory=alias)
        self.directory.chmod(0o755)
        with self.assertRaises(runtime.Rejected):
            self.register()

    def test_existing_file_and_symlink_are_never_overwritten(self):
        target = self.directory / "launch.json"
        target.write_bytes(b"preserve")
        with self.assertRaises(FileExistsError):
            self.register()
        self.assertEqual(target.read_bytes(), b"preserve")
        target.unlink()
        other = self.root / "other.json"
        other.write_bytes(b"other")
        target.symlink_to(other)
        with self.assertRaises(FileExistsError):
            self.register()
        self.assertEqual(other.read_bytes(), b"other")

    def test_policy_failure_removes_only_new_registration(self):
        sentinel = self.directory / "unrelated"
        sentinel.write_bytes(b"keep")
        with patch.object(runtime.policy, "evaluate", return_value={"status":"denied"}):
            with self.assertRaises(runtime.Rejected):
                self.register()
        self.assertFalse((self.directory / "launch.json").exists())
        self.assertEqual(sentinel.read_bytes(), b"keep")

    def test_second_identity_check_failure_removes_registration(self):
        real_check = runtime.validate_target
        calls = []
        def change_after_validation(*args):
            calls.append(1)
            if len(calls) == 2:
                (self.repo / "README.md").write_text("changed during registration")
            return real_check(*args)
        with patch.object(runtime, "validate_target", side_effect=change_after_validation):
            with self.assertRaises(runtime.Rejected):
                self.register()
        self.assertFalse((self.directory / "launch.json").exists())

    def test_port_conflict_precedes_file_creation(self):
        with patch.object(runtime, "require_port_available", side_effect=runtime.Rejected("QA_METRO_PORT_UNAVAILABLE")):
            with self.assertRaisesRegex(runtime.Rejected, "PORT"):
                self.register()
        self.assertFalse((self.directory / "launch.json").exists())


class RuntimeEnvironmentTest(unittest.TestCase):
    def test_port_in_use_is_rejected_without_stopping_listener(self):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            port = listener.getsockname()[1]
            with self.assertRaisesRegex(runtime.Rejected, "PORT"):
                runtime.require_port_available(port)
            with socket.create_connection(("127.0.0.1", port), timeout=1):
                pass

    def test_child_diagnostics_stay_in_disposable_directory(self):
        safe_spec = importlib.util.spec_from_file_location("safe_child", ROOT / "scripts/qa-safe-child-env.py")
        safe = importlib.util.module_from_spec(safe_spec)
        safe_spec.loader.exec_module(safe)
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "observed.json"
            code = ("import pathlib,json; p=pathlib.Path.cwd(); "
                    "(p/'firepit-log.txt').write_text('diagnostic'); "
                    f"pathlib.Path({str(output)!r}).write_text(json.dumps(str(p)))")
            with patch.dict(os.environ, {"PATH":safe.QA_TRUSTED_SYSTEM_PATH}, clear=True), \
                    patch.object(safe, "materialize_external_tool_proxies", return_value=False):
                self.assertEqual(safe.main(["safe", "--", "/usr/bin/python3", "-I", "-c", code]), 0)
            child_cwd = Path(json.loads(output.read_text()))
            self.assertTrue(child_cwd.name.startswith("susugigi-qa-tools."))
            self.assertFalse(child_cwd.exists())


if __name__ == "__main__":
    unittest.main()
