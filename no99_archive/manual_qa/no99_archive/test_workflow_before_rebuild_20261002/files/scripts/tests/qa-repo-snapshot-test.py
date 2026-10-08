#!/usr/bin/env python3

from __future__ import annotations

import os
import pathlib
import socket
import stat
import subprocess
import sys
import tempfile
import unittest


VERIFIER = pathlib.Path(__file__).resolve().parents[1] / "qa-repo-snapshot.py"
GIT = "/usr/bin/git"


class SnapshotCliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="qa-verifier-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name).resolve()
        self.repo = self.root / "repository"
        self.repo.mkdir()
        self.environment = {
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LC_ALL": "C",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_AUTHOR_NAME": "QA Verifier Test",
            "GIT_AUTHOR_EMAIL": "qa-verifier@example.invalid",
            "GIT_COMMITTER_NAME": "QA Verifier Test",
            "GIT_COMMITTER_EMAIL": "qa-verifier@example.invalid",
            "GIT_AUTHOR_DATE": "2026-01-01T00:00:00+00:00",
            "GIT_COMMITTER_DATE": "2026-01-01T00:00:00+00:00",
        }
        self.git("init", "-q", "--template=", "--initial-branch=main")
        (self.repo / "tracked.txt").write_bytes(b"tracked\n")
        self.git("add", "tracked.txt")
        self.git("commit", "-qm", "fixture")

    def git(self, *arguments: str) -> bytes:
        return subprocess.run(
            [GIT, "-C", str(self.repo), *arguments],
            env=self.environment,
            check=True,
            capture_output=True,
            timeout=10,
        ).stdout

    def invoke(self, *arguments: str, extra_environment=None) -> subprocess.CompletedProcess[bytes]:
        return subprocess.run(
            [sys.executable, "-I", str(VERIFIER), *map(str, arguments)],
            env={**self.environment, **(extra_environment or {})},
            capture_output=True,
            timeout=10,
        )

    def digest(self, *arguments: str) -> bytes:
        result = self.invoke(*arguments)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertRegex(result.stdout, rb"\A[0-9a-f]{64}\n\Z")
        self.assertEqual(result.stderr, b"")
        return result.stdout

    def repository_digest(self) -> bytes:
        return self.digest(
            "--repo", self.repo,
            "--repository", "fixture",
            "--schema", "quality-snapshot/v1",
        )

    def assert_rejected(self, *arguments: str) -> None:
        result = self.invoke(*arguments)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, b"")
        self.assertEqual(result.stderr, b"QA_REPO_SNAPSHOT_FAILED\n")

    def test_clean_repository_keeps_v1_reference_digest(self) -> None:
        self.assertEqual(
            self.repository_digest(),
            b"2ba6a7840f01ac2473aadb2b2fef1ea792e81c5c0fdecf25f074a3e3018e40d7\n",
        )

    def test_staged_rename_keeps_v1_reference_digest(self) -> None:
        self.git("mv", "tracked.txt", "renamed.txt")
        self.assertEqual(
            self.repository_digest(),
            b"a8b46067553d1bd66b539b45a1d684b6dd0fae25cd8378c4ae93ed885ceb395e\n",
        )

    def test_invalid_arguments_do_not_echo_supplied_values(self) -> None:
        for arguments in (
            ("--unknown-private-argument",),
            ("--repo",),
            ("--schema", "private-invalid-value"),
            ("--copy-regular-file", "private-incomplete-source"),
        ):
            with self.subTest(arguments=arguments):
                self.assert_rejected(*arguments)

    def test_repository_fingerprint_is_stable_and_detects_tracked_changes(self) -> None:
        baseline = self.repository_digest()
        self.assertEqual(self.repository_digest(), baseline)
        (self.repo / "tracked.txt").write_bytes(b"changed\n")
        self.assertNotEqual(self.repository_digest(), baseline)

    def test_copy_refuses_existing_destination_without_deleting_it(self) -> None:
        source = self.root / "source.bin"
        destination = self.root / "destination.bin"
        source.write_bytes(b"source\x00bytes")
        destination.write_bytes(b"keep existing bytes")
        result = self.invoke("--copy-regular-file", source, destination)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(destination.exists(), "existing destination was deleted")
        self.assertEqual(destination.read_bytes(), b"keep existing bytes")
        self.assertEqual(source.read_bytes(), b"source\x00bytes")

    def test_all_entry_points_reject_symlinked_parent_directories(self) -> None:
        alias = self.root / "alias"
        alias.symlink_to(self.repo, target_is_directory=True)
        nested = self.repo / "nested"
        nested.mkdir()
        source = nested / "source.bin"
        source.write_bytes(b"safe bytes")
        cases = (
            ("--tree-manifest", alias / "nested"),
            ("--copy-regular-file", alias / "nested/source.bin", self.root / "copy.bin"),
            ("--copy-regular-file", source, alias / "nested/copy.bin"),
        )
        for arguments in cases:
            with self.subTest(arguments=arguments):
                result = self.invoke(*arguments)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, b"")
                self.assertEqual(result.stderr, b"QA_REPO_SNAPSHOT_FAILED\n")
        self.assertFalse((nested / "copy.bin").exists())

    def test_copy_rejects_fifo_without_waiting_for_a_writer(self) -> None:
        fifo = self.root / "fifo"
        os.mkfifo(fifo)
        result = self.invoke("--copy-regular-file", fifo, self.root / "copy.bin")
        self.assertEqual(result.returncode, 1)
        self.assertFalse((self.root / "copy.bin").exists())

    def test_index_flags_cannot_hide_tracked_byte_changes(self) -> None:
        for flag in ("assume-unchanged", "skip-worktree"):
            with self.subTest(flag=flag):
                tracked = self.repo / "tracked.txt"
                tracked.write_bytes(b"tracked\n")
                baseline = self.repository_digest()
                self.git("update-index", "--" + flag, "tracked.txt")
                tracked.write_bytes(b"hidden modification\n")
                self.assertNotEqual(self.repository_digest(), baseline)
                self.git("update-index", "--no-" + flag, "tracked.txt")

    def test_attributes_cannot_hide_raw_byte_changes(self) -> None:
        (self.repo / ".gitattributes").write_bytes(b"tracked.txt text eol=lf\n")
        baseline = self.repository_digest()
        (self.repo / "tracked.txt").write_bytes(b"tracked\r\n")
        self.assertNotEqual(self.repository_digest(), baseline)

    def test_candidate_clean_filter_is_never_executed(self) -> None:
        marker = self.root / "filter-executed"
        (self.repo / ".gitattributes").write_bytes(b"tracked.txt filter=qa-probe\n")
        self.git("config", "filter.qa-probe.clean", f"touch '{marker}'; cat")
        self.repository_digest()
        self.assertFalse(marker.exists())

    def test_candidate_fsmonitor_is_never_executed(self) -> None:
        marker = self.root / "fsmonitor-executed"
        self.git("config", "core.fsmonitor", f"touch '{marker}'")
        self.repository_digest()
        self.assertFalse(marker.exists())

    def test_path_cannot_replace_git(self) -> None:
        baseline = self.repository_digest()
        fake_bin = self.root / "bin"
        fake_bin.mkdir()
        marker = self.root / "fake-git-executed"
        fake_git = fake_bin / "git"
        fake_git.write_text(f"#!/bin/sh\n/usr/bin/touch '{marker}'\nexit 1\n")
        fake_git.chmod(0o700)
        result = self.invoke(
            "--repo", self.repo, "--repository", "fixture",
            "--schema", "quality-snapshot/v1",
            extra_environment={"PATH": str(fake_bin)},
        )
        self.assertFalse(marker.exists())
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, baseline)

    def test_copy_preserves_binary_bytes_and_mode(self) -> None:
        source = self.root / "source.bin"
        destination = self.root / "copy.bin"
        content = bytes(range(256)) * 8193
        source.write_bytes(content)
        source.chmod(0o750)
        result = self.invoke("--copy-regular-file", source, destination)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b"")
        self.assertEqual(destination.read_bytes(), content)
        self.assertEqual(stat.S_IMODE(destination.stat().st_mode), 0o750)
        self.assertEqual(destination.stat().st_nlink, 1)
        self.assertNotEqual(source.stat().st_ino, destination.stat().st_ino)

    def test_copy_to_same_file_preserves_source(self) -> None:
        source = self.repo / "tracked.txt"
        self.assert_rejected("--copy-regular-file", source, source)
        self.assertEqual(source.read_bytes(), b"tracked\n")

    def test_copy_preserves_existing_symlink_and_fifo(self) -> None:
        source = self.repo / "tracked.txt"
        destination = self.root / "destination"
        destination.symlink_to(source)
        self.assert_rejected("--copy-regular-file", source, destination)
        self.assertTrue(destination.is_symlink())
        destination.unlink()
        os.mkfifo(destination)
        self.assert_rejected("--copy-regular-file", source, destination)
        self.assertTrue(stat.S_ISFIFO(destination.lstat().st_mode))

    def test_copy_rejects_nonregular_source(self) -> None:
        source = self.repo / "tracked.txt"
        linked = self.root / "linked"
        destination = self.root / "copy.bin"
        linked.symlink_to(source)
        self.assert_rejected("--copy-regular-file", linked, destination)
        linked.unlink()
        os.link(source, linked)
        self.assert_rejected("--copy-regular-file", linked, destination)
        linked.unlink()
        self.assert_rejected("--copy-regular-file", self.repo, destination)
        self.assertFalse(destination.exists())

    def test_tree_fingerprint_is_stable_and_tracks_empty_directories(self) -> None:
        baseline = self.digest("--tree-manifest", self.repo)
        self.assertEqual(self.digest("--tree-manifest", self.repo), baseline)
        (self.repo / "empty").mkdir()
        self.assertNotEqual(self.digest("--tree-manifest", self.repo), baseline)

    def test_tree_fingerprint_tracks_content_and_permissions(self) -> None:
        tree = self.root / "tree"
        tree.mkdir()
        data = tree / "data.bin"
        data.write_bytes(b"original\x00bytes")
        baseline = self.digest("--tree-manifest", tree)
        data.write_bytes(b"modified\x00bytes")
        self.assertNotEqual(self.digest("--tree-manifest", tree), baseline)
        content_changed = self.digest("--tree-manifest", tree)
        data.chmod(0o700)
        self.assertNotEqual(self.digest("--tree-manifest", tree), content_changed)

    def test_tree_rejects_symlink_hardlink_fifo_and_socket(self) -> None:
        tree = self.root / "tree"
        tree.mkdir()
        source = self.repo / "tracked.txt"
        entry = tree / "entry"
        entry.symlink_to(source)
        self.assert_rejected("--tree-manifest", tree)
        entry.unlink()
        os.link(source, entry)
        self.assert_rejected("--tree-manifest", tree)
        entry.unlink()
        os.mkfifo(entry)
        self.assert_rejected("--tree-manifest", tree)
        entry.unlink()
        with socket.socket(socket.AF_UNIX) as server:
            server.bind(str(entry))
            self.assert_rejected("--tree-manifest", tree)

    def test_repository_rejects_parent_alias_and_symlinked_tracked_directory(self) -> None:
        alias = self.root / "alias"
        alias.symlink_to(self.root, target_is_directory=True)
        self.assert_rejected(
            "--repo", alias / "repository", "--repository", "fixture",
            "--schema", "quality-snapshot/v1",
        )
        folder = self.repo / "folder"
        folder.mkdir()
        (folder / "nested.txt").write_bytes(b"nested")
        self.git("add", "folder/nested.txt")
        folder.rename(self.root / "original-folder")
        folder.symlink_to(self.root / "original-folder", target_is_directory=True)
        self.assert_rejected(
            "--repo", self.repo, "--repository", "fixture",
            "--schema", "quality-snapshot/v1",
        )

    def test_untracked_content_and_permissions_change_fingerprint(self) -> None:
        baseline = self.repository_digest()
        untracked = self.repo / "untracked.bin"
        untracked.write_bytes(b"untracked\x00bytes")
        first = self.repository_digest()
        self.assertNotEqual(first, baseline)
        untracked.write_bytes(b"different\x00bytes")
        second = self.repository_digest()
        self.assertNotEqual(first, second)
        untracked.chmod(0o700)
        self.assertNotEqual(second, self.repository_digest())

    def test_ignored_private_files_are_not_in_snapshot(self) -> None:
        (self.repo / ".gitignore").write_bytes(b"private.bin\n")
        baseline = self.repository_digest()
        (self.repo / "private.bin").write_bytes(b"private fixture bytes")
        self.assertEqual(self.repository_digest(), baseline)

    def test_staged_and_intent_to_add_files_are_fingerprinted(self) -> None:
        baseline = self.repository_digest()
        staged = self.repo / "staged.bin"
        staged.write_bytes(b"staged\x00bytes")
        self.git("add", "staged.bin")
        first = self.repository_digest()
        self.assertNotEqual(first, baseline)
        staged.write_bytes(b"new working bytes")
        self.assertNotEqual(self.repository_digest(), first)
        intent = self.repo / "intent.txt"
        intent.write_bytes(b"intent to add")
        self.git("add", "--intent-to-add", "intent.txt")
        first = self.repository_digest()
        intent.write_bytes(b"modified intent")
        self.assertNotEqual(self.repository_digest(), first)

    def test_tracked_deletion_is_fingerprinted(self) -> None:
        baseline = self.repository_digest()
        self.git("rm", "-q", "tracked.txt")
        self.assertNotEqual(self.repository_digest(), baseline)

    def test_filemode_false_cannot_hide_executable_bit(self) -> None:
        self.git("config", "core.filemode", "false")
        baseline = self.repository_digest()
        (self.repo / "tracked.txt").chmod(0o755)
        self.assertNotEqual(self.repository_digest(), baseline)

    def test_diff_configuration_does_not_change_fingerprint(self) -> None:
        (self.repo / "tracked.txt").write_bytes(b"changed\n")
        baseline = self.repository_digest()
        self.git("config", "diff.noprefix", "true")
        self.git("config", "diff.algorithm", "histogram")
        self.assertEqual(self.repository_digest(), baseline)

    def test_inherited_git_configuration_and_worktree_are_ignored(self) -> None:
        baseline = self.repository_digest()
        marker = self.root / "environment-executed"
        result = self.invoke(
            "--repo", self.repo, "--repository", "fixture",
            "--schema", "quality-snapshot/v1",
            extra_environment={
                "GIT_CONFIG_COUNT": "1",
                "GIT_CONFIG_KEY_0": "core.fsmonitor",
                "GIT_CONFIG_VALUE_0": f"touch '{marker}'",
                "GIT_DIR": str(self.root / "does-not-exist"),
                "GIT_WORK_TREE": str(self.root),
                "GIT_INDEX_FILE": str(self.root / "injected-index"),
            },
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, baseline)
        self.assertFalse(marker.exists())
        self.assertFalse((self.root / "injected-index").exists())

    def test_repository_and_schema_are_bound_into_fingerprint(self) -> None:
        baseline = self.repository_digest()
        for repository, schema in (
            ("different", "quality-snapshot/v1"),
            ("fixture", "control-plane-snapshot/v1"),
        ):
            self.assertNotEqual(
                self.digest("--repo", self.repo, "--repository", repository, "--schema", schema),
                baseline,
            )

    def test_non_repository_and_missing_inputs_are_rejected(self) -> None:
        self.assert_rejected("--repo", self.root, "--repository", "fixture", "--schema", "quality-snapshot/v1")
        self.assert_rejected("--tree-manifest", self.root / "missing")
        self.assert_rejected("--copy-regular-file", self.root / "missing", self.root / "copy")
        self.assert_rejected("--tree-manifest", self.repo, "--repository", "fixture")
        self.assert_rejected()

    def test_missing_object_never_fetches_or_writes_source_objects(self) -> None:
        donor = self.root / "donor"
        self.git("clone", "--no-hardlinks", "--template=", "-q", str(self.repo), str(donor))
        head = self.git("rev-parse", "HEAD").decode().strip()
        commit_object = self.repo / ".git/objects" / head[:2] / head[2:]
        self.assertTrue(commit_object.is_file())
        commit_object.unlink()
        self.git("config", "remote.origin.url", str(donor))
        self.git("config", "remote.origin.promisor", "true")
        self.git("config", "extensions.partialClone", "origin")
        self.git("config", "protocol.allow", "never")
        self.git("config", "protocol.file.allow", "always")
        packs = self.repo / ".git/objects/pack"
        before = sorted(packs.iterdir())
        self.assert_rejected(
            "--repo", self.repo, "--repository", "fixture",
            "--schema", "quality-snapshot/v1",
        )
        self.assertEqual(sorted(packs.iterdir()), before)
        self.assertFalse(commit_object.exists())


if __name__ == "__main__":
    unittest.main()
