#!/usr/bin/env python3

import os
import pathlib
import re
import shlex
import shutil
import subprocess
import tempfile
import unittest


CONTROL = pathlib.Path(__file__).resolve().parents[2]
CONTRACT_RENDERER = CONTROL / "scripts/render_qa_contract.py"
TRUSTED_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"


def runtime_functions():
    return "\n".join(re.findall(
        r"^[a-z_][a-z_0-9]*\(\) \{\n.*?^\}",
        subprocess.check_output(["python3", "-B", str(CONTRACT_RENDERER), "--quality-root", os.environ["QA_QUALITY_TEST_ROOT"]], text=True), re.MULTILINE | re.DOTALL,
    ))


def run_runtime(command, extra_env=None):
    environment = {"PATH": TRUSTED_PATH, "QA_TRUSTED_SYSTEM_PATH": TRUSTED_PATH}
    environment.update(extra_env or {})
    return subprocess.run(
        ["/bin/bash", "--noprofile", "--norc", "-c", runtime_functions() + "\n" + command],
        env=environment, capture_output=True, text=True, timeout=90,
    )


class RuntimeMaterializationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="qa-runtime-test-")
        self.root = pathlib.Path(self.temporary.name).resolve()
        self.runtime_temp = self.root / "temporary"
        self.runtime_temp.mkdir()
        self.repositories = {}
        self.identity = {"TMPDIR": str(self.runtime_temp)}
        for prefix, name in (("TRUSTED_CONTROL_PLANE", "trusted"),
                             ("CONTROL_PLANE", "control"), ("QUALITY", "quality")):
            repo = self.root / name
            repo.mkdir()
            self.git(repo, "init", "--template=", "-q")
            remote = "https://example.invalid/" + name + ".git"
            self.git(repo, "remote", "add", "origin", remote)
            (repo / "ordinary").write_text("original\n")
            if name == "trusted":
                (repo / "scripts").mkdir()
                shutil.copyfile(CONTROL / "scripts/qa-repo-snapshot.py",
                                repo / "scripts/qa-repo-snapshot.py")
            if name == "control":
                (repo / "scripts").mkdir()
                (repo / "manifests").mkdir()
                for helper in ('qa_adapter.py', 'qa-safe-child-env.py'):
                    shutil.copyfile(CONTROL / 'scripts' / helper, repo / 'scripts' / helper)
                shutil.copyfile(CONTROL / 'manifests/qa_adapters.json', repo / 'manifests/qa_adapters.json')
            if name == "quality":
                (repo / "no3_run_scripts").mkdir()
                shutil.copytree(pathlib.Path(os.environ['QA_QUALITY_TEST_ROOT']) / 'no3_run_scripts/control_adapter',
                                repo / 'no3_run_scripts/control_adapter', ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
                (repo / "no3_run_scripts/no1_fixture_golden.json").write_text("{}\n")
            self.git(repo, "add", ".")
            self.git(repo, "-c", "user.name=QA Fixture", "-c",
                     "user.email=qa@example.invalid", "commit", "-qm", "fixture")
            self.repositories[name] = repo
            self.identity.update({
                prefix + "_ROOT": str(repo), prefix + "_REPOSITORY": remote,
                prefix + "_IDENTITY_KIND": "clean",
                prefix + "_COMMIT": self.git(repo, "rev-parse", "HEAD").strip(),
                prefix + "_TREE": self.git(repo, "rev-parse", "HEAD^{tree}").strip(),
            })

    def tearDown(self):
        for root, directories, files in os.walk(self.root):
            os.chmod(root, 0o700)
            for name in files:
                if not (pathlib.Path(root) / name).is_symlink():
                    os.chmod(pathlib.Path(root) / name, 0o600)
        self.temporary.cleanup()

    def git(self, repo, *args):
        return subprocess.run(
            ["/usr/bin/git", "-C", str(repo), *args],
            env={"PATH": TRUSTED_PATH, "GIT_CONFIG_NOSYSTEM": "1",
                 "GIT_CONFIG_GLOBAL": os.devnull},
            capture_output=True, text=True, check=True,
        ).stdout

    def test_clean_environment_can_launch_the_real_child(self):
        result = run_runtime("qa_firebase_endpoint_safe_env /usr/bin/printf READY_TO_RUN")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "READY_TO_RUN")

    def test_private_runtime_accepts_a_platform_temporary_directory_alias(self):
        alias = self.root / "temporary-alias"
        alias.symlink_to(self.runtime_temp, target_is_directory=True)
        result = run_runtime(
            'materialize_session_runtime_snapshots && printf "%s" "$SESSION_RUNTIME_ROOT"',
            {**self.identity, "TMPDIR": str(alias)},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        runtime = pathlib.Path(result.stdout)
        self.assertEqual(runtime.parent, self.runtime_temp)
        self.assertEqual((runtime / "control/ordinary").read_text(), "original\n")
        self.assertFalse(os.access(runtime / "control/ordinary", os.W_OK))

    def snapshot_identity(self, name, prefix):
        digest = subprocess.run(
            ["/usr/bin/python3", "-I", str(CONTROL / "scripts/qa-repo-snapshot.py"),
             "--repo", str(self.repositories[name]), "--repository",
             self.identity[prefix + "_REPOSITORY"], "--schema",
             "control-plane-snapshot/v1" if name == "control" else "quality-snapshot/v1"],
            env={"PATH": TRUSTED_PATH}, capture_output=True, text=True, check=True,
        ).stdout.strip()
        self.identity.update({
            prefix + "_IDENTITY_KIND": "snapshot",
            prefix + "_BASE_COMMIT": self.identity[prefix + "_COMMIT"],
            prefix + "_BASE_TREE": self.identity[prefix + "_TREE"],
            prefix + "_SNAPSHOT_DIGEST": digest,
        })

    def test_staged_and_untracked_quality_files_keep_the_locked_snapshot(self):
        quality = self.repositories["quality"]
        (quality / "staged").write_text("staged version\n")
        self.git(quality, "add", "staged")
        (quality / "staged").write_text("working version\n")
        (quality / "untracked").write_text("not staged\n")
        self.snapshot_identity("quality", "QUALITY")
        original_index = (quality / ".git/index").read_bytes()
        result = run_runtime(
            'materialize_session_runtime_snapshots && printf "%s" "$SESSION_RUNTIME_ROOT"',
            self.identity,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        runtime = pathlib.Path(result.stdout)
        self.assertEqual((runtime / "quality/staged").read_text(), "working version\n")
        self.assertEqual((runtime / "quality/untracked").read_text(), "not staged\n")
        self.assertEqual((quality / ".git/index").read_bytes(), original_index)

    def test_candidate_configuration_cannot_execute_fsmonitor(self):
        sentinel = self.root / "fsmonitor-executed"
        monitor = self.root / "monitor"
        monitor.write_text("#!/bin/sh\nprintf ran > " + shlex.quote(str(sentinel)) + "\n")
        monitor.chmod(0o700)
        self.git(self.repositories["control"], "config", "core.fsmonitor", str(monitor))
        result = run_runtime("materialize_session_runtime_snapshots", self.identity)
        self.assertFalse(sentinel.exists(), "candidate fsmonitor executed before isolation")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_clean_snapshot_preserves_files_despite_archive_attributes(self):
        control = self.repositories["control"]
        (control / ".gitattributes").write_text("ordinary export-ignore\n")
        self.git(control, "add", ".gitattributes")
        self.git(control, "-c", "user.name=QA Fixture", "-c",
                 "user.email=qa@example.invalid", "commit", "-qm", "archive attributes")
        self.identity["CONTROL_PLANE_COMMIT"] = self.git(control, "rev-parse", "HEAD").strip()
        self.identity["CONTROL_PLANE_TREE"] = self.git(control, "rev-parse", "HEAD^{tree}").strip()
        result = run_runtime(
            'materialize_session_runtime_snapshots && printf "%s" "$SESSION_RUNTIME_ROOT"',
            self.identity,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((pathlib.Path(result.stdout) / "control/ordinary").is_file())

    def test_candidate_clean_filter_is_rejected_before_execution(self):
        control = self.repositories["control"]
        (control / ".gitattributes").write_text("ordinary filter=unsafe\n")
        self.git(control, "add", ".gitattributes")
        self.git(control, "-c", "user.name=QA Fixture", "-c",
                 "user.email=qa@example.invalid", "commit", "-qm", "filter attribute")
        self.identity["CONTROL_PLANE_COMMIT"] = self.git(control, "rev-parse", "HEAD").strip()
        self.identity["CONTROL_PLANE_TREE"] = self.git(control, "rev-parse", "HEAD^{tree}").strip()
        sentinel = self.root / "filter-executed"
        self.git(control, "config", "filter.unsafe.clean",
                 "printf ran > " + shlex.quote(str(sentinel)) + "; cat")
        (control / "ordinary").write_text("changed!\n")
        result = run_runtime("materialize_session_runtime_snapshots", self.identity)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(sentinel.exists(), "candidate clean filter executed")


if __name__ == "__main__":
    unittest.main()
