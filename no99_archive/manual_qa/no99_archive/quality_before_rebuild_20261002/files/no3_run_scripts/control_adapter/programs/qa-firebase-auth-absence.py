#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import os
import pathlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile


QA_PROJECT_ID = "susugigi-qa"
QA_IDENTITY_HASH_PATTERN = re.compile(r"^[0-9a-f]{64}$")
QA_MAX_RESPONSE_BYTES = 4 * 1024 * 1024
QA_ENDPOINT_OVERRIDE_ENV = (
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
    "CLOUDSDK_API_ENDPOINT_OVERRIDES_FIRESTORE",
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
    "NODE_OPTIONS",
    "NODE_PATH",
    "SSLKEYLOGFILE",
    "DYLD_INSERT_LIBRARIES",
    "DYLD_LIBRARY_PATH",
    "LD_PRELOAD",
    "LD_LIBRARY_PATH",
    "BASH_XTRACEFD",
    "PS4",
)
QA_CHILD_CLEAR_ONLY_ENV = ("SHELLOPTS", "BASHOPTS")
QA_ENDPOINT_OVERRIDE_PREFIXES = (
    "CLOUDSDK_API_ENDPOINT_OVERRIDES_",
)
QA_FORBIDDEN_CONFIG_KEY_PARTS = (
    "proxy",
    "endpoint",
    "customca",
    "cacert",
    "cafile",
    "certfile",
    "certdir",
    "tokenhost",
)


class ProbeFailure(Exception):
    pass


class AuthIdentityPresent(ProbeFailure):
    pass


class AuthExportUnavailable(ProbeFailure):
    pass


class EndpointOverrideRejected(ProbeFailure):
    pass


def interrupt_probe(_signal_number: int, _frame: object) -> None:
    raise ProbeFailure


def install_signal_handlers() -> None:
    for signal_number in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        signal.signal(signal_number, interrupt_probe)


def read_identity_hash() -> str:
    identity_hash = sys.stdin.readline().rstrip("\r\n")
    if QA_IDENTITY_HASH_PATTERN.fullmatch(identity_hash) is None:
        raise ProbeFailure
    if sys.stdin.read(1):
        raise ProbeFailure
    return identity_hash


def safe_child_environment() -> dict[str, str]:
    environment = os.environ.copy()
    for name, value in environment.items():
        if not value:
            continue
        if name in QA_ENDPOINT_OVERRIDE_ENV \
            or any(name.startswith(prefix) for prefix in QA_ENDPOINT_OVERRIDE_PREFIXES):
            raise EndpointOverrideRejected
    for name in QA_ENDPOINT_OVERRIDE_ENV:
        environment.pop(name, None)
    for name in QA_CHILD_CLEAR_ONLY_ENV:
        environment.pop(name, None)
    return environment


def config_has_nonempty_leaf(value: object) -> bool:
    if isinstance(value, dict):
        return any(config_has_nonempty_leaf(child) for child in value.values())
    if isinstance(value, list):
        return any(config_has_nonempty_leaf(child) for child in value)
    return value is not None and value != ""


def config_contains_forbidden_override(value: object) -> bool:
    if isinstance(value, dict):
        for key, child in value.items():
            if not isinstance(key, str):
                raise EndpointOverrideRejected
            normalized_key = re.sub(r"[^a-z0-9]", "", key.lower())
            if any(part in normalized_key for part in QA_FORBIDDEN_CONFIG_KEY_PARTS) \
                and child not in (None, "", False, [], {}) \
                and config_has_nonempty_leaf(child):
                return True
            if config_contains_forbidden_override(child):
                return True
        return False
    if isinstance(value, list):
        return any(config_contains_forbidden_override(child) for child in value)
    return False


def validate_firebase_local_config() -> None:
    home = pathlib.Path.home()
    config_candidates = {
        home / ".config" / "configstore" / "firebase-tools.json",
        home / "Library" / "Preferences" / "configstore" / "firebase-tools.json",
    }
    xdg_config_home = os.environ.get("XDG_CONFIG_HOME")
    if xdg_config_home:
        config_candidates.add(
            pathlib.Path(xdg_config_home) / "configstore" / "firebase-tools.json"
        )
    for config_path in config_candidates:
        if not config_path.exists() and not config_path.is_symlink():
            continue
        try:
            config_stat = config_path.lstat()
            if config_path.is_symlink() \
                or not config_path.is_file() \
                or config_stat.st_size > QA_MAX_RESPONSE_BYTES:
                raise EndpointOverrideRejected
            payload = json.loads(config_path.read_bytes())
        except (json.JSONDecodeError, OSError, UnicodeError, ValueError) as error:
            raise EndpointOverrideRejected from error
        if not isinstance(payload, dict) \
            or config_contains_forbidden_override(payload):
            raise EndpointOverrideRejected
    npm_config = home / ".npmrc"
    if npm_config.exists() or npm_config.is_symlink():
        try:
            npm_stat = npm_config.lstat()
            if npm_config.is_symlink() \
                or not npm_config.is_file() \
                or npm_stat.st_size > 64 * 1024:
                raise EndpointOverrideRejected
            for raw_line in npm_config.read_text(encoding="utf-8").splitlines():
                line = raw_line.strip()
                if not line or line.startswith(("#", ";")) or "=" not in line:
                    continue
                key, configured_value = line.split("=", 1)
                normalized_key = re.sub(r"[^a-z0-9]", "", key.lower())
                if configured_value.strip() \
                    and any(
                        part in normalized_key
                        for part in ("proxy", "cafile", "certfile", "certdir")
                    ):
                    raise EndpointOverrideRejected
        except (OSError, UnicodeError) as error:
            raise EndpointOverrideRejected from error


def identity_match_count(payload: dict[str, object], identity_hash: str) -> int:
    return len(matching_anonymous_identity_uids(payload, identity_hash))


def matching_anonymous_identity_uids(
    payload: dict[str, object], identity_hash: str
) -> list[str]:
    users = payload.get("users", [])
    if not isinstance(users, list):
        raise ProbeFailure
    matching_uids: list[str] = []
    for user in users:
        if not isinstance(user, dict):
            raise ProbeFailure
        local_id = user.get("localId")
        if not isinstance(local_id, str):
            raise ProbeFailure
        candidate_hash = hashlib.sha256(local_id.encode("utf-8")).hexdigest()
        if candidate_hash == identity_hash:
            provider_data = user.get("providerUserInfo", [])
            if not isinstance(provider_data, list) or provider_data:
                raise ProbeFailure
            if any(
                field in user
                for field in ("email", "phoneNumber", "passwordHash", "salt")
            ):
                raise ProbeFailure
            matching_uids.append(local_id)
    return matching_uids


def firebase_auth_export(project: str) -> dict[str, object]:
    environment = safe_child_environment()
    validate_firebase_local_config()
    firebase_executable = shutil.which("firebase")
    if firebase_executable is None:
        raise AuthExportUnavailable
    with tempfile.TemporaryDirectory(prefix="qa-auth-export-") as temporary_root:
        os.chmod(temporary_root, 0o700)
        export_path = pathlib.Path(temporary_root) / "users.json"
        environment["CI"] = "true"
        environment["FIREBASE_CLI_DISABLE_UPDATE_CHECK"] = "true"
        try:
            result = subprocess.run(
                [
                    firebase_executable,
                    "--project",
                    project,
                    "--non-interactive",
                    "auth:export",
                    str(export_path),
                    "--format",
                    "json",
                ],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                env=environment,
                timeout=120,
                preexec_fn=lambda: os.umask(0o077),
            )
        except (OSError, subprocess.SubprocessError) as error:
            raise AuthExportUnavailable from error
        if result.returncode != 0:
            raise ProbeFailure
        try:
            export_stat = export_path.lstat()
        except OSError as error:
            raise ProbeFailure from error
        if export_path.is_symlink() or not export_path.is_file():
            raise ProbeFailure
        os.chmod(export_path, 0o600)
        if export_stat.st_size > QA_MAX_RESPONSE_BYTES:
            raise ProbeFailure
        try:
            payload = json.loads(export_path.read_bytes())
        except (json.JSONDecodeError, OSError, UnicodeError, ValueError) as error:
            raise ProbeFailure from error
    if not isinstance(payload, dict):
        raise ProbeFailure
    return payload


def verify_absent(project: str, identity_hash: str) -> bool:
    if project != QA_PROJECT_ID:
        raise ProbeFailure
    payload = firebase_auth_export(project)
    if identity_match_count(payload, identity_hash) != 0:
        raise AuthIdentityPresent
    return True


def resolve_exact_anonymous_uid(project: str, identity_hash: str) -> str:
    if project != QA_PROJECT_ID:
        raise ProbeFailure
    matching_uids = matching_anonymous_identity_uids(
        firebase_auth_export(project), identity_hash
    )
    if len(matching_uids) != 1:
        raise ProbeFailure
    return matching_uids[0]


def main() -> int:
    if len(sys.argv) not in (3, 4) or sys.argv[1] != "--project":
        print("QA_AUTH_ABSENCE_PROBE_FAILED", file=sys.stderr)
        return 2
    resolve_uid = len(sys.argv) == 4 and sys.argv[3] == "--resolve-exact-uid"
    if len(sys.argv) == 4 and not resolve_uid:
        print("QA_AUTH_ABSENCE_PROBE_FAILED", file=sys.stderr)
        return 2
    try:
        install_signal_handlers()
        identity_hash = read_identity_hash()
        if resolve_uid:
            print(resolve_exact_anonymous_uid(sys.argv[2], identity_hash))
            return 0
        verify_absent(sys.argv[2], identity_hash)
    except AuthIdentityPresent:
        print("QA_AUTH_IDENTITY_PRESENT", file=sys.stderr)
        return 1
    except EndpointOverrideRejected:
        print("QA_FIREBASE_ENDPOINT_OVERRIDE_REJECTED", file=sys.stderr)
        return 1
    except AuthExportUnavailable:
        error_code = (
            "QA_AUTH_IDENTITY_BIND_FAILED"
            if resolve_uid
            else "QA_AUTH_EXPORT_DEPENDENCY_UNAVAILABLE"
        )
        print(error_code, file=sys.stderr)
        return 1
    except ProbeFailure:
        error_code = (
            "QA_AUTH_IDENTITY_BIND_FAILED"
            if resolve_uid
            else "QA_AUTH_ABSENCE_PROBE_FAILED"
        )
        print(error_code, file=sys.stderr)
        return 1
    print("QA_AUTH_IDENTITY_ABSENT")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
