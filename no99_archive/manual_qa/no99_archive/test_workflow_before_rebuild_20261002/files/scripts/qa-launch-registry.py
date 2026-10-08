#!/usr/bin/env python3
"""Validate the locked QA checkout and register Metro in its private session directory."""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import socket
import stat
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "qa_server_launch_policy", ROOT / "hooks/lib/server-launch-policy.py"
)
policy = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = policy
spec.loader.exec_module(policy)


class Rejected(Exception):
    pass


def git(repo: Path, *args: str) -> str:
    return subprocess.check_output(
        ["/usr/bin/git", "-C", str(repo), *args],
        stderr=subprocess.DEVNULL, timeout=10,
    ).decode().strip()


def validate_target(repo: Path, commit: str, tree: str, registry) -> None:
    if not all(re.fullmatch(r"[0-9a-f]{40}", value) for value in (commit, tree)):
        raise Rejected("QA_METRO_TARGET_REJECTED")
    if repo != repo.resolve(strict=True) or not repo.is_dir():
        raise Rejected("QA_METRO_TARGET_REJECTED")
    resolution = registry.resolve_path(str(repo))
    if resolution.status != "resolved" or len(resolution.matches) != 1:
        raise Rejected("QA_METRO_TARGET_REJECTED")
    identity = resolution.matches[0]
    if (identity.product_id, identity.module_id, identity.layer_id) != (
        "SuSuGiGi", "no2_accounting_app", "impl"
    ) or str(repo) != identity.repo_root or identity.repo_root != identity.canonical_root:
        raise Rejected("QA_METRO_TARGET_REJECTED")
    if (git(repo, "branch", "--show-current")
            or git(repo, "status", "--porcelain")
            or git(repo, "rev-parse", "HEAD^{commit}") != commit
            or git(repo, "rev-parse", "HEAD^{tree}") != tree):
        raise Rejected("QA_METRO_TARGET_REJECTED")


def validate_runtime_directory(directory: Path) -> None:
    info = directory.lstat()
    if (directory != directory.resolve(strict=True)
            or directory.parent != Path(tempfile.gettempdir()).resolve()
            or not re.fullmatch(r"sim-review-stream\.[A-Za-z0-9_-]+", directory.name)
            or not stat.S_ISDIR(info.st_mode)
            or info.st_uid != os.geteuid()
            or stat.S_IMODE(info.st_mode) != 0o700):
        raise Rejected("QA_METRO_RUNTIME_DIRECTORY_REJECTED")


def require_port_available(port: int = 8081) -> None:
    sockets = []
    try:
        for family, address in ((socket.AF_INET, "0.0.0.0"), (socket.AF_INET6, "::")):
            server = socket.socket(family, socket.SOCK_STREAM)
            sockets.append(server)
            if family == socket.AF_INET6:
                server.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
            server.bind((address, port))
    except OSError as error:
        raise Rejected("QA_METRO_PORT_UNAVAILABLE") from error
    finally:
        for server in sockets:
            server.close()


def register(repo: Path, commit: str, tree: str, directory: Path, *, registry=None) -> Path:
    if any(name.startswith("GIT_") and name != "GIT_PAGER" and value
           for name, value in os.environ.items()):
        raise Rejected("QA_METRO_TARGET_REJECTED")
    if registry is None:
        registry = policy.ProductRegistry.load(
            ROOT / "data/products/products_registry.md",
            ROOT / "data/products/layer_manifest.yaml",
        )
    validate_target(repo, commit, tree, registry)
    validate_runtime_directory(directory)
    require_port_available()
    path = directory / "launch.json"
    payload = {"version": "0.0.1", "configurations": [{
        "name": "susugigi-qa-session", "directory": os.path.relpath(repo, directory),
        "runtimeExecutable": "npx",
        "runtimeArgs": ["react-native", "start", "--port", "8081"],
        "metroPort": 8081,
    }]}
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(payload, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        graph = {"cwd": str(repo), "commands": [{
            "cwd": str(repo),
            "effective_argv": ["react-native", "start", "--port", "8081"],
        }]}
        if policy.evaluate(graph, str(path), registry=registry).get("status") != "allowed":
            raise Rejected("QA_METRO_REGISTRATION_REJECTED")
        validate_target(repo, commit, tree, registry)
        return path
    except BaseException:
        path.unlink()
        raise


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--main-repo", required=True, type=Path)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--tree", required=True)
    parser.add_argument("--runtime-dir", required=True, type=Path)
    args = parser.parse_args()
    try:
        register(args.main_repo, args.commit, args.tree, args.runtime_dir)
        print("QA_METRO_REGISTRATION_VERIFIED")
        return 0
    except Rejected as error:
        print(str(error), file=sys.stderr)
    except (OSError, ValueError, subprocess.SubprocessError):
        print("QA_METRO_REGISTRATION_REJECTED", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
