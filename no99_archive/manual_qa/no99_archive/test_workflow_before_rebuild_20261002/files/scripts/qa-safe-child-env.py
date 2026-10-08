#!/usr/bin/env python3

from __future__ import annotations

import os
import pathlib
import shlex
import stat
import subprocess
import sys
import tempfile


QA_TRUSTED_SYSTEM_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"
QA_CORE_COMMANDS = {
    "bash": "/bin/bash",
    "env": "/usr/bin/env",
    "git": "/usr/bin/git",
    "plutil": "/usr/bin/plutil",
    "python3": "/usr/bin/python3",
    "shasum": "/usr/bin/shasum",
}
QA_ALLOWED_EXTERNAL_ROOTS = tuple(
    pathlib.Path(path)
    for path in (
        "/opt/homebrew",
        "/usr/local",
        "/opt/google-cloud-sdk",
        "/Library/Google/Cloud SDK",
    )
)
QA_EXTERNAL_CANDIDATES = {
    "firebase": (
        "/opt/homebrew/bin/firebase",
        "/usr/local/bin/firebase",
    ),
    "gcloud": (
        "/opt/homebrew/bin/gcloud",
        "/usr/local/bin/gcloud",
        "/opt/google-cloud-sdk/bin/gcloud",
        "/Library/Google/Cloud SDK/google-cloud-sdk/bin/gcloud",
    ),
    "node": (
        "/opt/homebrew/bin/node",
        "/usr/local/bin/node",
    ),
}


class GuardRejected(Exception):
    pass


QA_REJECTED_ENV = frozenset(
    {
        "FIREBASE_GOOGLE_URL",
        "FIREBASE_TOKEN_URL",
        "FIREBASE_AUTH_URL",
        "FIREBASE_AUTHPROXY_URL",
        "FIREBASE_AUTH_MANAGEMENT_URL",
        "FIREBASE_IDENTITY_URL",
        "FIREBASE_API_URL",
        "FIREBASE_AUTH_EMULATOR_HOST",
        "FIRESTORE_EMULATOR_HOST",
        "FIRESTORE_URL",
        "FIREBASE_EMULATOR_HUB",
        "CLOUDSDK_AUTH_TOKEN_HOST",
        "CLOUDSDK_CORE_API_ENDPOINT_OVERRIDES",
        "CLOUDSDK_PROXY_TYPE",
        "CLOUDSDK_PROXY_ADDRESS",
        "CLOUDSDK_PROXY_PORT",
        "CLOUDSDK_PROXY_USERNAME",
        "CLOUDSDK_PROXY_PASSWORD",
        "CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE",
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "ALL_PROXY",
        "NO_PROXY",
        "http_proxy",
        "https_proxy",
        "all_proxy",
        "no_proxy",
        "SSL_CERT_FILE",
        "SSL_CERT_DIR",
        "REQUESTS_CA_BUNDLE",
        "CURL_CA_BUNDLE",
        "NODE_EXTRA_CA_CERTS",
        "NODE_TLS_REJECT_UNAUTHORIZED",
        "npm_config_proxy",
        "npm_config_https_proxy",
        "npm_config_cafile",
        "NPM_CONFIG_USERCONFIG",
        "PYTHONPATH",
        "PYTHONHOME",
        "PYTHONSTARTUP",
        "PYTHONINSPECT",
        "PYTHONWARNINGS",
        "PYTHONBREAKPOINT",
        "PYTHONUSERBASE",
        "PYTHONEXECUTABLE",
        "PYTHONCASEOK",
        "PYTHONPLATLIBDIR",
        "PYTHONSAFEPATH",
        "GRPC_DEFAULT_SSL_ROOTS_FILE_PATH",
        "GOOGLE_API_USE_MTLS_ENDPOINT",
        "GOOGLE_API_USE_CLIENT_CERTIFICATE",
        "FIREBASE_CONFIG",
        "BASH_ENV",
        "ENV",
        "BASH_XTRACEFD",
        "PS4",
        "NODE_OPTIONS",
        "NODE_PATH",
        "SSLKEYLOGFILE",
        "DYLD_INSERT_LIBRARIES",
        "DYLD_LIBRARY_PATH",
        "LD_PRELOAD",
        "LD_LIBRARY_PATH",
    }
)
QA_CLEAR_ONLY_ENV = frozenset({"SHELLOPTS", "BASHOPTS"})


def is_rejected_name(name: str) -> bool:
    return name in QA_REJECTED_ENV \
        or name.startswith("BASH_FUNC_") \
        or name.startswith("CLOUDSDK_API_ENDPOINT_OVERRIDES_") \
        or name.startswith("FIREBASE_") and name.endswith("_URL")


def trusted_root_for(path: pathlib.Path) -> pathlib.Path:
    for root in QA_ALLOWED_EXTERNAL_ROOTS:
        try:
            path.relative_to(root)
        except ValueError:
            continue
        return root
    raise GuardRejected


def validate_owned_path(path: pathlib.Path, root: pathlib.Path) -> None:
    current = path
    allowed_owners = {0, os.geteuid()}
    while True:
        metadata = current.lstat()
        if stat.S_ISLNK(metadata.st_mode) \
            or metadata.st_uid not in allowed_owners \
            or metadata.st_mode & 0o022:
            raise GuardRejected
        if current == root:
            return
        if current.parent == current:
            raise GuardRejected
        current = current.parent


def resolve_external_tool(name: str) -> pathlib.Path | None:
    resolved_tool: pathlib.Path | None = None
    for candidate_text in QA_EXTERNAL_CANDIDATES[name]:
        candidate = pathlib.Path(candidate_text)
        if not candidate.exists() and not candidate.is_symlink():
            continue
        try:
            resolved = candidate.resolve(strict=True)
            root = trusted_root_for(resolved)
            metadata = resolved.lstat()
            if not stat.S_ISREG(metadata.st_mode) \
                or stat.S_ISLNK(metadata.st_mode) \
                or metadata.st_uid not in {0, os.geteuid()} \
                or metadata.st_mode & 0o022 \
                or not os.access(resolved, os.X_OK):
                raise GuardRejected
            validate_owned_path(resolved.parent, root)
            candidate_root = trusted_root_for(candidate)
            validate_owned_path(candidate.parent, candidate_root)
        except (OSError, RuntimeError, GuardRejected):
            raise GuardRejected from None
        if resolved_tool is not None and resolved_tool != resolved:
            raise GuardRejected
        resolved_tool = resolved
    return resolved_tool


def write_tool_proxy(directory: pathlib.Path, name: str, target: pathlib.Path) -> None:
    proxy = directory / name
    descriptor = os.open(proxy, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o700)
    with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
        stream.write("#!/bin/sh\n")
        stream.write(f"exec {shlex.quote(str(target))} \"$@\"\n")
    if proxy.is_symlink() or not proxy.is_file():
        raise GuardRejected


def materialize_external_tool_proxies(directory: pathlib.Path) -> bool:
    firebase = resolve_external_tool("firebase")
    gcloud = resolve_external_tool("gcloud")
    exposed = False
    if firebase is not None:
        node = resolve_external_tool("node")
        if node is None:
            raise GuardRejected
        write_tool_proxy(directory, "node", node)
        write_tool_proxy(directory, "firebase", firebase)
        exposed = True
    if gcloud is not None:
        write_tool_proxy(directory, "gcloud", gcloud)
        exposed = True
    return exposed


def resolve_child_command(command: str, proxy_directory: pathlib.Path) -> str:
    if command in QA_CORE_COMMANDS:
        return QA_CORE_COMMANDS[command]
    if command in QA_CORE_COMMANDS.values():
        return command
    if command in {"firebase", "gcloud"}:
        proxy = proxy_directory / command
        if proxy.is_file() and not proxy.is_symlink():
            return str(proxy)
    raise GuardRejected


def main(argv: list[str]) -> int:
    if len(argv) < 3 or argv[1] != "--" or not argv[2]:
        print("QA_RUNTIME_ENVIRONMENT_REJECTED", file=sys.stderr)
        return 2
    if os.environ.get("PATH") != QA_TRUSTED_SYSTEM_PATH:
        print("QA_RUNTIME_ENVIRONMENT_REJECTED", file=sys.stderr)
        return 1
    if any(
        is_rejected_name(name) and (value or name.startswith("BASH_FUNC_"))
        for name, value in os.environ.items()
    ):
        print("QA_RUNTIME_ENVIRONMENT_REJECTED", file=sys.stderr)
        return 1
    child_environment = os.environ.copy()
    for name in QA_REJECTED_ENV | QA_CLEAR_ONLY_ENV:
        child_environment.pop(name, None)
    for name in tuple(child_environment):
        if is_rejected_name(name):
            child_environment.pop(name, None)
    try:
        with tempfile.TemporaryDirectory(prefix="susugigi-qa-tools.") as root:
            proxy_directory = pathlib.Path(root)
            proxy_directory.chmod(0o700)
            if materialize_external_tool_proxies(proxy_directory):
                child_environment["PATH"] = \
                    f"{proxy_directory}:{QA_TRUSTED_SYSTEM_PATH}"
            else:
                child_environment["PATH"] = QA_TRUSTED_SYSTEM_PATH
            command = resolve_child_command(argv[2], proxy_directory)
            completed = subprocess.run(
                [command, *argv[3:]],
                env=child_environment,
                cwd=proxy_directory,
                check=False,
            )
            return completed.returncode
    except GuardRejected:
        print("QA_RUNTIME_TOOL_REJECTED", file=sys.stderr)
        return 1
    except OSError:
        print("QA_RUNTIME_CHILD_EXEC_FAILED", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
