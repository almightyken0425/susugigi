#!/usr/bin/env python3

from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
import pathlib
import stat
import subprocess
import sys
import tempfile


SCHEMAS = frozenset({"control-plane-snapshot/v1", "quality-snapshot/v1"})


class SnapshotFailure(Exception):
    pass


class SnapshotArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise SnapshotFailure


def git_command(*arguments: str, input_bytes: bytes | None = None) -> bytes:
    environment = {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "LC_ALL": "C",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_NO_LAZY_FETCH": "1",
        "GIT_ALLOW_PROTOCOL": "",
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_OPTIONAL_LOCKS": "0",
    }
    try:
        return subprocess.run(
            [
                "/usr/bin/git",
                "-c", "core.fsmonitor=false",
                "-c", "core.untrackedCache=false",
                "-c", "core.excludesFile=" + os.devnull,
                "-c", "core.attributesFile=" + os.devnull,
                *arguments,
            ],
            env=environment,
            input=input_bytes,
            check=True,
            capture_output=True,
            timeout=30,
        ).stdout
    except (OSError, subprocess.SubprocessError) as error:
        raise SnapshotFailure from error


def git(repo: pathlib.Path, *arguments: str) -> bytes:
    return git_command(
        "-C", os.fspath(repo), "--work-tree=" + os.fspath(repo), *arguments,
    )


def full_sha(repo: pathlib.Path, revision: str) -> str:
    value = git(repo, "rev-parse", revision).decode("ascii").strip()
    if len(value) != 40 or any(character not in "0123456789abcdef" for character in value):
        raise SnapshotFailure
    return value


def utf16_key(value: str) -> bytes:
    return value.encode("utf-16-be", "surrogatepass")


def stable_file_metadata(file_stat: os.stat_result) -> tuple[int, ...]:
    return (
        file_stat.st_dev, file_stat.st_ino, file_stat.st_mode,
        file_stat.st_nlink, file_stat.st_size,
        file_stat.st_mtime_ns, file_stat.st_ctime_ns,
    )


def same_entry(descriptor: int, parent: int, name: str) -> None:
    opened = os.fstat(descriptor)
    named = os.stat(name, dir_fd=parent, follow_symlinks=False)
    if stable_file_metadata(opened) != stable_file_metadata(named):
        raise SnapshotFailure


@contextmanager
def directory_handle(path: pathlib.Path):
    if ".." in path.parts:
        raise SnapshotFailure
    absolute = path.absolute()
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    descriptors = [os.open("/", flags)]
    links = []
    try:
        for part in absolute.parts[1:]:
            parent = descriptors[-1]
            child = os.open(part, flags, dir_fd=parent)
            descriptors.append(child)
            links.append((parent, part, child))
        yield descriptors[-1]
        for parent, name, child in reversed(links):
            same_entry(child, parent, name)
    finally:
        for descriptor in reversed(descriptors):
            os.close(descriptor)


@contextmanager
def regular_handle(parent: int, name: str):
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC
    descriptor = os.open(name, flags, dir_fd=parent)
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            raise SnapshotFailure
        same_entry(descriptor, parent, name)
        yield descriptor, before
        if stable_file_metadata(before) != stable_file_metadata(os.fstat(descriptor)):
            raise SnapshotFailure
        same_entry(descriptor, parent, name)
    finally:
        os.close(descriptor)


def read_regular_at(parent: int, name: str) -> tuple[dict[str, object], bytes, tuple[int, ...]]:
    with regular_handle(parent, name) as (descriptor, before):
        chunks = []
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        content = b"".join(chunks)
        record = {
            "type": "regular",
            "mode": format(stat.S_IMODE(before.st_mode), "04o"),
            "linkCount": before.st_nlink,
            "contentDigest": hashlib.sha256(content).hexdigest(),
        }
    return record, content, stable_file_metadata(before)


def regular_file_record(path: pathlib.Path) -> dict[str, object]:
    with directory_handle(path.parent) as parent:
        record, _, _ = read_regular_at(parent, path.name)
    return record


def tree_manifest(root: pathlib.Path) -> str:
    records: list[dict[str, object]] = []

    def walk(descriptor: int, relative_path: str) -> None:
        before = os.fstat(descriptor)
        records.append({
            "path": relative_path,
            "type": "directory",
            "mode": format(stat.S_IMODE(before.st_mode), "04o"),
            "linkCount": before.st_nlink,
        })
        for name in sorted(os.listdir(descriptor), key=utf16_key):
            relative = name if relative_path == "." else f"{relative_path}/{name}"
            metadata = os.stat(name, dir_fd=descriptor, follow_symlinks=False)
            if stat.S_ISDIR(metadata.st_mode):
                child = os.open(
                    name,
                    os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                    dir_fd=descriptor,
                )
                try:
                    if stable_file_metadata(metadata) != stable_file_metadata(os.fstat(child)):
                        raise SnapshotFailure
                    walk(child, relative)
                    same_entry(child, descriptor, name)
                finally:
                    os.close(child)
            elif stat.S_ISREG(metadata.st_mode):
                record, _, _ = read_regular_at(descriptor, name)
                record["path"] = relative
                records.append(record)
            else:
                raise SnapshotFailure
        if stable_file_metadata(before) != stable_file_metadata(os.fstat(descriptor)):
            raise SnapshotFailure

    try:
        with directory_handle(root) as descriptor:
            walk(descriptor, ".")
    except OSError as error:
        raise SnapshotFailure from error
    canonical = json.dumps(
        records, ensure_ascii=False, separators=(",", ":"), sort_keys=True,
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def copy_regular_file(source: pathlib.Path, destination: pathlib.Path) -> None:
    try:
        with directory_handle(source.parent) as source_parent:
            with regular_handle(source_parent, source.name) as (source_fd, before):
                with directory_handle(destination.parent) as destination_parent:
                    destination_fd = os.open(
                        destination.name,
                        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                        stat.S_IMODE(before.st_mode),
                        dir_fd=destination_parent,
                    )
                    try:
                        while True:
                            chunk = os.read(source_fd, 1024 * 1024)
                            if not chunk:
                                break
                            offset = 0
                            while offset < len(chunk):
                                written = os.write(destination_fd, chunk[offset:])
                                if written <= 0:
                                    raise SnapshotFailure
                                offset += written
                        os.fchmod(destination_fd, stat.S_IMODE(before.st_mode))
                        copied = os.fstat(destination_fd)
                        if not stat.S_ISREG(copied.st_mode) \
                            or copied.st_nlink != 1 \
                            or copied.st_size != before.st_size:
                            raise SnapshotFailure
                        same_entry(destination_fd, destination_parent, destination.name)
                    finally:
                        os.close(destination_fd)
    except OSError as error:
        raise SnapshotFailure from error


def source_state(repo: pathlib.Path) -> tuple[str, str, bytes, bytes]:
    return (
        full_sha(repo, "HEAD^{commit}"),
        full_sha(repo, "HEAD^{tree}"),
        git(repo, "ls-files", "--stage", "-z"),
        git(repo, "ls-files", "--others", "--exclude-standard", "-z"),
    )


def source_paths(state: tuple[str, str, bytes, bytes]) -> tuple[set[str], set[str]]:
    tracked = set()
    for entry in state[2].split(b"\0"):
        if not entry:
            continue
        fields, raw_path = entry.split(b"\t", 1)
        mode, object_id, stage = fields.split()
        if mode not in {b"100644", b"100755"} or stage != b"0":
            raise SnapshotFailure
        if len(object_id) != 40 or any(byte not in b"0123456789abcdef" for byte in object_id):
            raise SnapshotFailure
        path = raw_path.decode("utf-8")
        if path in tracked:
            raise SnapshotFailure
        tracked.add(path)
    untracked = {path.decode("utf-8") for path in state[3].split(b"\0") if path}
    for path in tracked | untracked:
        parts = pathlib.PurePosixPath(path)
        if not path or parts.is_absolute() or ".." in parts.parts or ".git" in parts.parts:
            raise SnapshotFailure
    return tracked, untracked


def read_source(repo: pathlib.Path, path: str):
    candidate = repo / path
    with directory_handle(candidate.parent) as parent:
        return read_regular_at(parent, candidate.name)


def snapshot_payload(repo: pathlib.Path, repository: str, schema: str) -> dict[str, object]:
    if not repository or schema not in SCHEMAS:
        raise SnapshotFailure
    repo = repo.absolute()
    with directory_handle(repo):
        before = source_state(repo)
        tracked, untracked = source_paths(before)
        objects = git(repo, "rev-parse", "--path-format=absolute", "--git-path", "objects")
        objects_path = pathlib.Path(objects.decode("utf-8").strip()).resolve(strict=True)
        if "\n" in str(objects_path) or "\r" in str(objects_path):
            raise SnapshotFailure
        records = {}
        signatures = {}
        with tempfile.TemporaryDirectory(prefix="qa-verifier-index-") as temporary:
            isolated = pathlib.Path(temporary).resolve() / "git"
            git_command("init", "--bare", "--template=", "-q", str(isolated))
            (isolated / "objects/info/alternates").write_text(
                str(objects_path) + "\n", encoding="utf-8",
            )
            (isolated / "info").mkdir()
            (isolated / "info/attributes").write_text(
                "* !diff -filter -working-tree-encoding -text -ident\n",
                encoding="utf-8",
            )
            index_entries = []
            for path in sorted(tracked | untracked, key=utf16_key):
                try:
                    record, content, signature = read_source(repo, path)
                except FileNotFoundError:
                    if path in tracked:
                        signatures[path] = None
                        continue
                    raise SnapshotFailure from None
                records[path] = record
                signatures[path] = signature
                if path in tracked:
                    blob = git_command(
                        "--git-dir=" + str(isolated),
                        "hash-object", "-w", "--stdin", "--no-filters",
                        input_bytes=content,
                    ).strip()
                    mode = b"100755" if int(record["mode"], 8) & 0o111 else b"100644"
                    index_entries.append(mode + b" " + blob + b"\t" + path.encode("utf-8") + b"\0")
            git_command(
                "--git-dir=" + str(isolated), "update-index", "-z", "--index-info",
                input_bytes=b"".join(index_entries),
            )
            tracked_patch = git_command(
                "--git-dir=" + str(isolated),
                "diff", "--cached", "--binary", "--full-index", "--no-color",
                "--no-ext-diff", "--no-textconv", "--find-renames=50%", "-l1000",
                "--diff-algorithm=myers", "--indent-heuristic", "--unified=3",
                "--inter-hunk-context=0", "--src-prefix=a/", "--dst-prefix=b/",
                "--no-relative", before[0], "--",
            )
        if source_state(repo) != before:
            raise SnapshotFailure
        for path, signature in signatures.items():
            try:
                record, _, current_signature = read_source(repo, path)
            except FileNotFoundError:
                if signature is None:
                    continue
                raise SnapshotFailure from None
            if signature is None or current_signature != signature or record != records[path]:
                raise SnapshotFailure
        untracked_entries = [
            {"path": path, **records[path]}
            for path in sorted(untracked, key=utf16_key)
        ]
        return {
            "schema": schema,
            "repository": repository,
            "baseCommit": before[0],
            "baseTree": before[1],
            "trackedPatchDigest": hashlib.sha256(tracked_patch).hexdigest(),
            "untrackedEntries": untracked_entries,
        }


def main() -> int:
    parser = SnapshotArgumentParser(add_help=False, allow_abbrev=False)
    parser.add_argument("--repo")
    parser.add_argument("--repository")
    parser.add_argument("--schema", choices=sorted(SCHEMAS))
    parser.add_argument("--tree-manifest")
    parser.add_argument("--copy-regular-file", nargs=2)
    try:
        arguments = parser.parse_args()
        if arguments.tree_manifest is not None:
            if any(
                value is not None
                for value in (
                    arguments.repo,
                    arguments.repository,
                    arguments.schema,
                    arguments.copy_regular_file,
                )
            ):
                raise SnapshotFailure
            print(tree_manifest(pathlib.Path(arguments.tree_manifest)))
            return 0
        if arguments.copy_regular_file is not None:
            if any(
                value is not None
                for value in (
                    arguments.repo,
                    arguments.repository,
                    arguments.schema,
                    arguments.tree_manifest,
                )
            ):
                raise SnapshotFailure
            copy_regular_file(
                pathlib.Path(arguments.copy_regular_file[0]),
                pathlib.Path(arguments.copy_regular_file[1]),
            )
            return 0
        if arguments.repo is None \
            or arguments.repository is None \
            or arguments.schema is None:
            raise SnapshotFailure
        repository_path = pathlib.Path(arguments.repo)
        if repository_path.is_symlink():
            raise SnapshotFailure
        payload = snapshot_payload(
            repository_path,
            arguments.repository,
            arguments.schema,
        )
        canonical = json.dumps(
            payload,
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
        ).encode("utf-8")
    except (OSError, ValueError, RecursionError, SnapshotFailure):
        print("QA_REPO_SNAPSHOT_FAILED", file=sys.stderr)
        return 1
    print(hashlib.sha256(canonical).hexdigest())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
