#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import signal
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request


QA_PROJECT_ID = "susugigi-qa"
QA_UID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{1,128}$")
QA_DIGEST_PATTERN = re.compile(r"^[0-9a-f]{64}$")
QA_R01_BASELINE_PATTERN = re.compile(
    r"^QA_FIRESTORE_R01_USER_MATCH sha256:(?P<digest>[0-9a-f]{64}) "
    r"lastLoginAt:(?P<last_login_at>[0-9]{13}) updatedAt:(?P<updated_at>[0-9]{13})$"
)
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
QA_SEMANTIC_PROFILES = frozenset(
    {
        "fixture-subtree-absent",
        "r01-user-anonymous",
        "r01-user-unchanged",
        "r03-incremental-backup",
        "r03-updated-backup",
        "r03-deleted-backup",
        "r03-initial-backup",
        "r08-preferences",
        "r08-preferences-baseline",
    }
)
QA_FIXTURE_COLLECTIONS = (
    "accounts",
    "categories",
    "transactions",
    "transfers",
    "currency_rates",
    "schedules",
)
QA_MAX_RESPONSE_BYTES = 4 * 1024 * 1024


class ProbeFailure(Exception):
    pass


class CredentialProviderUnavailable(ProbeFailure):
    pass


class EndpointOverrideRejected(ProbeFailure):
    pass


class RejectRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(
        self,
        _request: urllib.request.Request,
        _file_pointer: object,
        _code: int,
        _message: str,
        _headers: object,
        _new_url: str,
    ) -> None:
        return None


def interrupt_probe(_signal_number: int, _frame: object) -> None:
    raise ProbeFailure


def install_signal_handlers() -> None:
    for signal_number in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        signal.signal(signal_number, interrupt_probe)


def read_session_uid() -> str:
    session_uid = sys.stdin.readline().rstrip("\r\n")
    if QA_UID_PATTERN.fullmatch(session_uid) is None:
        raise ProbeFailure
    if sys.stdin.read(1):
        raise ProbeFailure
    return session_uid


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


def validate_gcloud_local_config(
    gcloud_executable: str,
    environment: dict[str, str],
) -> None:
    try:
        result = subprocess.run(
            [gcloud_executable, "config", "list", "--all", "--format=json"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=environment,
            text=False,
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise CredentialProviderUnavailable from error
    if result.returncode != 0 or len(result.stdout) > 1024 * 1024:
        raise CredentialProviderUnavailable
    try:
        payload = json.loads(result.stdout)
    except (json.JSONDecodeError, UnicodeError, ValueError) as error:
        raise CredentialProviderUnavailable from error
    if not isinstance(payload, dict):
        raise CredentialProviderUnavailable
    if config_contains_forbidden_override(payload):
        raise EndpointOverrideRejected


def resolve_resource_path(template: str, session_uid: str) -> str:
    allowed_templates = {
        "users/{QA_SESSION_UID}",
        *(f"users/{{QA_SESSION_UID}}/{name}" for name in QA_FIXTURE_COLLECTIONS),
    }
    if template not in allowed_templates:
        raise ProbeFailure
    return template.replace("{QA_SESSION_UID}", session_uid)


def access_token() -> str:
    environment = safe_child_environment()
    gcloud_executable = shutil.which("gcloud")
    if gcloud_executable is None:
        raise CredentialProviderUnavailable
    validate_gcloud_local_config(gcloud_executable, environment)
    try:
        result = subprocess.run(
            [gcloud_executable, "auth", "print-access-token"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=environment,
            text=False,
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise ProbeFailure from error
    if result.returncode != 0:
        raise ProbeFailure
    token_bytes = result.stdout.strip()
    if not 20 <= len(token_bytes) <= 4096 \
        or any(character in b" \t\r\n\v\f" for character in token_bytes):
        raise ProbeFailure
    try:
        return token_bytes.decode("ascii")
    except UnicodeError as error:
        raise ProbeFailure from error


def request_json(url: str, token: str) -> tuple[int, object | None]:
    safe_child_environment()
    parsed_url = urllib.parse.urlsplit(url)
    if parsed_url.scheme != "https" \
        or parsed_url.hostname != "firestore.googleapis.com" \
        or parsed_url.port is not None \
        or parsed_url.username is not None \
        or parsed_url.password is not None:
        raise ProbeFailure
    request = urllib.request.Request(
        url,
        headers={"Authorization": f"Bearer {token}"},
        method="GET",
    )
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        RejectRedirectHandler(),
    )
    try:
        with opener.open(request, timeout=30) as response:
            response_bytes = response.read(QA_MAX_RESPONSE_BYTES + 1)
            status = response.status
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return 404, None
        raise ProbeFailure from error
    except (OSError, urllib.error.URLError) as error:
        raise ProbeFailure from error
    if len(response_bytes) > QA_MAX_RESPONSE_BYTES:
        raise ProbeFailure
    try:
        return status, json.loads(response_bytes)
    except (json.JSONDecodeError, UnicodeError, ValueError) as error:
        raise ProbeFailure from error


def normalized_payload(value: object, session_uid: str) -> object:
    if isinstance(value, dict):
        return {
            key: normalized_payload(child, session_uid)
            for key, child in sorted(value.items())
        }
    if isinstance(value, list):
        return [normalized_payload(child, session_uid) for child in value]
    if isinstance(value, str):
        return value.replace(session_uid, "[QA_SESSION_UID]")
    return value


def payload_digest(value: object, session_uid: str) -> str:
    canonical = json.dumps(
        normalized_payload(value, session_uid),
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def document_url(project: str, resource_path: str) -> str:
    encoded_path = "/".join(
        urllib.parse.quote(segment, safe="") for segment in resource_path.split("/")
    )
    return (
        "https://firestore.googleapis.com/v1/projects/"
        f"{project}/databases/(default)/documents/{encoded_path}"
    )


def collection_url(project: str, resource_path: str) -> str:
    return document_url(project, resource_path) + "?pageSize=1000"


def decode_firestore_value(value: object, depth: int = 0) -> object:
    if depth > 8 or not isinstance(value, dict) or len(value) != 1:
        raise ProbeFailure
    value_type, encoded = next(iter(value.items()))
    if value_type == "nullValue":
        if encoded is not None:
            raise ProbeFailure
        return None
    if value_type == "booleanValue":
        if not isinstance(encoded, bool):
            raise ProbeFailure
        return encoded
    if value_type == "integerValue":
        if not isinstance(encoded, str) or re.fullmatch(r"-?[0-9]{1,16}", encoded) is None:
            raise ProbeFailure
        integer = int(encoded)
        if abs(integer) > 9_007_199_254_740_991:
            raise ProbeFailure
        return integer
    if value_type == "doubleValue":
        if not isinstance(encoded, (int, float)) or isinstance(encoded, bool):
            raise ProbeFailure
        decoded_double = float(encoded)
        if not math.isfinite(decoded_double):
            raise ProbeFailure
        return decoded_double
    if value_type in {"stringValue", "timestampValue"}:
        if not isinstance(encoded, str) or len(encoded) > 4096:
            raise ProbeFailure
        return encoded
    if value_type == "mapValue":
        if not isinstance(encoded, dict):
            raise ProbeFailure
        fields = encoded.get("fields", {})
        if set(encoded) - {"fields"} or not isinstance(fields, dict) or len(fields) > 128:
            raise ProbeFailure
        if any(not isinstance(key, str) or len(key) > 128 for key in fields):
            raise ProbeFailure
        return {
            key: decode_firestore_value(child, depth + 1)
            for key, child in sorted(fields.items())
        }
    if value_type == "arrayValue":
        if not isinstance(encoded, dict):
            raise ProbeFailure
        values = encoded.get("values", [])
        if set(encoded) - {"values"} or not isinstance(values, list) or len(values) > 1000:
            raise ProbeFailure
        return [decode_firestore_value(child, depth + 1) for child in values]
    raise ProbeFailure


def decoded_document(payload: object, expected_resource_path: str) -> dict[str, object]:
    if not isinstance(payload, dict):
        raise ProbeFailure
    expected_name = (
        f"projects/{QA_PROJECT_ID}/databases/(default)/documents/"
        f"{expected_resource_path}"
    )
    if payload.get("name") != expected_name:
        raise ProbeFailure
    fields = payload.get("fields")
    if not isinstance(fields, dict) or len(fields) > 256:
        raise ProbeFailure
    decoded: dict[str, object] = {}
    for key, value in fields.items():
        if not isinstance(key, str) or len(key) > 128:
            raise ProbeFailure
        decoded[key] = decode_firestore_value(value)
    return decoded


def decoded_collection(payload: object, expected_resource_path: str) -> list[dict[str, object]]:
    if not isinstance(payload, dict) or payload.get("nextPageToken"):
        raise ProbeFailure
    if set(payload) - {"documents", "nextPageToken"}:
        raise ProbeFailure
    documents = payload.get("documents", [])
    if not isinstance(documents, list) or len(documents) > 1000:
        raise ProbeFailure
    prefix = (
        f"projects/{QA_PROJECT_ID}/databases/(default)/documents/"
        f"{expected_resource_path}/"
    )
    decoded: list[dict[str, object]] = []
    for document in documents:
        if not isinstance(document, dict):
            raise ProbeFailure
        name = document.get("name")
        if not isinstance(name, str) or not name.startswith(prefix):
            raise ProbeFailure
        document_id = name[len(prefix):]
        if not document_id or "/" in document_id:
            raise ProbeFailure
        decoded.append(decoded_document(document, f"{expected_resource_path}/{document_id}"))
    return decoded


def fetch_document(project: str, resource_path: str, token: str) -> dict[str, object] | None:
    status, payload = request_json(document_url(project, resource_path), token)
    if status == 404:
        return None
    if status != 200:
        raise ProbeFailure
    return decoded_document(payload, resource_path)


def fetch_collection(project: str, resource_path: str, token: str) -> list[dict[str, object]]:
    status, payload = request_json(collection_url(project, resource_path), token)
    if status != 200:
        raise ProbeFailure
    return decoded_collection(payload, resource_path)


def require_live_session_documents(documents: list[dict[str, object]], session_uid: str) -> None:
    for document in documents:
        if "userId" not in document \
            or "deletedOn" not in document \
            or document.get("userId") != session_uid \
            or document.get("deletedOn") is not None:
            raise ProbeFailure


def semantic_user_digest(document: dict[str, object], session_uid: str) -> str:
    if not {"uid", "provider", "email", "createdAt"}.issubset(document):
        raise ProbeFailure
    identity_invariant = {
        "uid": document["uid"],
        "provider": document["provider"],
        "email": document["email"],
        "createdAt": document["createdAt"],
    }
    canonical = json.dumps(
        normalized_payload(identity_invariant, session_uid),
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def require_qa_timestamp(value: object) -> int:
    if isinstance(value, bool) \
        or not isinstance(value, int) \
        or not 1_000_000_000_000 <= value <= 9_000_000_000_000:
        raise ProbeFailure
    return value


def evaluate_r03_initial_backup(session_uid: str, token: str) -> None:
    collections = {
        name: fetch_collection(
            QA_PROJECT_ID, f"users/{session_uid}/{name}", token
        )
        for name in QA_FIXTURE_COLLECTIONS
    }
    if {name: len(rows) for name, rows in collections.items()} != {
        "accounts": 3,
        "categories": 7,
        "transactions": 9,
        "transfers": 0,
        "currency_rates": 1,
        "schedules": 0,
    }:
        raise ProbeFailure
    for documents in collections.values():
        require_live_session_documents(documents, session_uid)
    expected_accounts = {"錢包": 901, "銀行": 901, "日幣帳戶": 392}
    if {row.get("name"): row.get("currencyId") for row in collections["accounts"]} \
        != expected_accounts:
        raise ProbeFailure
    expected_categories = {
        "餐飲": "expense",
        "交通": "expense",
        "娛樂": "expense",
        "購物": "expense",
        "醫療": "expense",
        "薪資": "income",
        "獎金": "income",
    }
    if {row.get("name"): row.get("type") for row in collections["categories"]} \
        != expected_categories:
        raise ProbeFailure
    expected_transactions = {
        "早餐改過": -1_500_000,
        "薪資入帳": 500_000_000,
        "獎金入帳": 50_000_000,
        "計程車": -3_500_000,
        "電影": -3_000_000,
        "網購": -15_000_000,
        "診所": -5_000_000,
        "露營裝備": -35_000_000,
        "露營餐費": -8_000_000,
    }
    if {row.get("note"): row.get("amountCents") for row in collections["transactions"]} \
        != expected_transactions:
        raise ProbeFailure
    account_ids = {row.get("id") for row in collections["accounts"]}
    category_ids = {row.get("id") for row in collections["categories"]}
    if any(
        row.get("accountId") not in account_ids or row.get("categoryId") not in category_ids
        for row in collections["transactions"]
    ):
        raise ProbeFailure
    rate = collections["currency_rates"][0]
    if (
        rate.get("currencyFromId"),
        rate.get("currencyToId"),
        rate.get("rate"),
    ) != (392, 901, 1):
        raise ProbeFailure


def evaluate_r03_incremental_backup(session_uid: str, token: str, stage: str = "added") -> None:
    if stage not in {"added", "updated", "deleted"}:
        raise ProbeFailure
    transactions = fetch_collection(
        QA_PROJECT_ID, f"users/{session_uid}/transactions", token
    )
    if len(transactions) != 10 or any(
        row.get("userId") != session_uid or "deletedOn" not in row
        for row in transactions
    ):
        raise ProbeFailure
    deleted = [row for row in transactions if row.get("deletedOn") is not None]
    if stage == "deleted":
        if len(deleted) != 1 or deleted[0].get("note") != "增量備份已修改" \
                or deleted[0].get("amountCents") != -2_750_000:
            raise ProbeFailure
        require_qa_timestamp(deleted[0].get("deletedOn"))
    elif deleted:
        raise ProbeFailure
    live_transactions = [
        row for row in transactions
        if row.get("deletedOn") is None and row.get("userId") == session_uid
    ]
    expected_transactions = {
        "早餐改過": -1_500_000,
        "薪資入帳": 500_000_000,
        "獎金入帳": 50_000_000,
        "計程車": -3_500_000,
        "電影": -3_000_000,
        "網購": -15_000_000,
        "診所": -5_000_000,
        "露營裝備": -35_000_000,
        "露營餐費": -8_000_000,
        "增量備份": -2_000_000,
    }
    if stage != "added":
        del expected_transactions["增量備份"]
        if stage == "updated":
            expected_transactions["增量備份已修改"] = -2_750_000
    if len(live_transactions) != len(expected_transactions) \
        or {row.get("note"): row.get("amountCents") for row in live_transactions} \
        != expected_transactions:
        raise ProbeFailure
    transfers = fetch_collection(
        QA_PROJECT_ID, f"users/{session_uid}/transfers", token
    )
    require_live_session_documents(transfers, session_uid)
    live_transfers = [
        row for row in transfers
        if row.get("deletedOn") is None and row.get("userId") == session_uid
    ]
    transfer_amounts = {
        (
            row.get("amountFromCents"),
            row.get("amountToCents"),
            row.get("impliedRateScaled"),
        )
        for row in live_transfers
    }
    if len(live_transfers) != 2 or transfer_amounts != {
        (20_000_000, 20_000_000, None),
        (10_000_000, 45_000_000, 4.5),
    }:
        raise ProbeFailure


def run_semantic_profile(
    profile: str,
    session_uid: str,
    token: str,
    expected_sha256: str,
    expected_language: str = "",
    minimum_updated_at: int | None = None,
    minimum_last_login_at: int | None = None,
) -> str:
    if profile not in QA_SEMANTIC_PROFILES:
        raise ProbeFailure
    if profile == "fixture-subtree-absent":
        if fetch_document(QA_PROJECT_ID, f"users/{session_uid}", token) is not None:
            raise ProbeFailure
        for collection_name in QA_FIXTURE_COLLECTIONS:
            if fetch_collection(
                QA_PROJECT_ID,
                f"users/{session_uid}/{collection_name}",
                token,
            ):
                raise ProbeFailure
        return "QA_FIRESTORE_FIXTURE_SUBTREE_ABSENT"
    if profile in {
        "r01-user-anonymous",
        "r01-user-unchanged",
        "r08-preferences",
        "r08-preferences-baseline",
    }:
        user_document = fetch_document(
            QA_PROJECT_ID, f"users/{session_uid}", token
        )
        if user_document is None:
            raise ProbeFailure
        if profile == "r01-user-anonymous":
            if user_document.get("uid") != session_uid \
                or user_document.get("provider") != "anonymous" \
                or "email" not in user_document \
                or user_document.get("email") is not None \
                or "createdAt" not in user_document:
                raise ProbeFailure
            last_login_at = require_qa_timestamp(user_document.get("lastLoginAt"))
            updated_at = require_qa_timestamp(user_document.get("updatedAt"))
            return (
                "QA_FIRESTORE_R01_USER_MATCH sha256:"
                f"{semantic_user_digest(user_document, session_uid)} "
                f"lastLoginAt:{last_login_at} updatedAt:{updated_at}"
            )
        if profile == "r01-user-unchanged":
            if QA_DIGEST_PATTERN.fullmatch(expected_sha256) is None \
                or semantic_user_digest(user_document, session_uid) != expected_sha256 \
                or minimum_last_login_at is None \
                or minimum_updated_at is None \
                or require_qa_timestamp(user_document.get("lastLoginAt")) \
                    < minimum_last_login_at \
                or require_qa_timestamp(user_document.get("updatedAt")) \
                    < minimum_updated_at:
                raise ProbeFailure
            return "QA_FIRESTORE_R01_USER_UNCHANGED"
        preferences = user_document.get("preferences")
        updated_at = user_document.get("updatedAt")
        if profile == "r08-preferences-baseline":
            if not isinstance(updated_at, int) \
                or not 1_000_000_000_000 <= updated_at <= 9_000_000_000_000:
                raise ProbeFailure
            return f"QA_FIRESTORE_R08_BASELINE updatedAt:{updated_at}"
        if not isinstance(preferences, dict) \
            or preferences.get("theme") != "theme3" \
            or preferences.get("currency") != "USD" \
            or preferences.get("language") != expected_language \
            or re.fullmatch(r"[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*", expected_language) is None \
            or not isinstance(updated_at, int) \
            or minimum_updated_at is None \
            or not 1_000_000_000_000 <= minimum_updated_at < updated_at <= 9_000_000_000_000:
            raise ProbeFailure
        return "QA_FIRESTORE_R08_PREFERENCES_MATCH"
    if profile == "r03-initial-backup":
        evaluate_r03_initial_backup(session_uid, token)
        return "QA_FIRESTORE_R03_INITIAL_BACKUP_MATCH"
    if profile == "r03-updated-backup":
        evaluate_r03_incremental_backup(session_uid, token, "updated")
        return "QA_FIRESTORE_R03_UPDATED_BACKUP_MATCH"
    if profile == "r03-deleted-backup":
        evaluate_r03_incremental_backup(session_uid, token, "deleted")
        return "QA_FIRESTORE_R03_DELETED_BACKUP_MATCH"
    evaluate_r03_incremental_backup(session_uid, token)
    return "QA_FIRESTORE_R03_INCREMENTAL_BACKUP_MATCH"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--project", required=True)
    parser.add_argument("--profile", choices=sorted(QA_SEMANTIC_PROFILES), required=True)
    parser.add_argument("--expected-sha256")
    parser.add_argument("--expected-language")
    parser.add_argument("--minimum-updated-at", type=int)
    parser.add_argument("--minimum-last-login-at", type=int)
    arguments = parser.parse_args()
    if arguments.project != QA_PROJECT_ID:
        raise ProbeFailure
    if arguments.expected_sha256 is not None and QA_DIGEST_PATTERN.fullmatch(
        arguments.expected_sha256
    ) is None:
        raise ProbeFailure
    if arguments.profile == "r01-user-unchanged":
        if arguments.expected_sha256 is None \
            or arguments.minimum_last_login_at is None \
            or arguments.minimum_updated_at is None \
            or not 1_000_000_000_000 \
                <= arguments.minimum_last_login_at \
                <= 9_000_000_000_000 \
            or not 1_000_000_000_000 \
                <= arguments.minimum_updated_at \
                <= 9_000_000_000_000:
            raise ProbeFailure
    elif arguments.expected_sha256 is not None \
        or arguments.minimum_last_login_at is not None:
        raise ProbeFailure
    if arguments.profile == "r08-preferences":
        if arguments.expected_language is None \
            or re.fullmatch(
                r"[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*",
                arguments.expected_language,
            ) is None \
            or arguments.minimum_updated_at is None \
            or not 1_000_000_000_000 <= arguments.minimum_updated_at <= 9_000_000_000_000:
            raise ProbeFailure
    elif arguments.profile != "r01-user-unchanged" \
        and (arguments.expected_language is not None \
             or arguments.minimum_updated_at is not None):
        raise ProbeFailure
    return arguments


def run_probe(arguments: argparse.Namespace, session_uid: str) -> str:
    token = access_token()
    return run_semantic_profile(
        arguments.profile,
        session_uid,
        token,
        arguments.expected_sha256 or "",
        arguments.expected_language or "",
        arguments.minimum_updated_at,
        arguments.minimum_last_login_at,
    )


def main() -> int:
    try:
        install_signal_handlers()
        arguments = parse_arguments()
        session_uid = read_session_uid()
        verdict = run_probe(arguments, session_uid)
    except CredentialProviderUnavailable:
        print("QA_FIRESTORE_AUTH_PROVIDER_UNAVAILABLE", file=sys.stderr)
        return 1
    except EndpointOverrideRejected:
        print("QA_FIREBASE_ENDPOINT_OVERRIDE_REJECTED", file=sys.stderr)
        return 1
    except ProbeFailure:
        print("QA_FIRESTORE_PROBE_FAILED", file=sys.stderr)
        return 1
    print(verdict)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
