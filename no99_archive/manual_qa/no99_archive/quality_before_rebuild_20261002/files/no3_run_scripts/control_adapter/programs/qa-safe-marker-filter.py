#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import math
import re
import sys
from pathlib import Path


SAFE_GOLDEN_FAMILIES = frozenset(
    {
        "QA ANALYTICS",
        "QA BACKUP",
        "QA BOOT",
        "QA DBQ",
        "QA FINDING",
        "QA FOCUS",
        "QA PAYWALL",
        "QA PREF",
        "QA PREMIUM",
        "QA QUOTA",
        "QA RCACHE",
        "QA RELEASE",
        "QA SCHED",
        "QA SEED",
        "QA UNDO",
        "QA VALID",
    }
)
RUNTIME_SCHEMA = "qa.runtime/v1"
RUNTIME_MARKER_REJECTION_SENTINEL = "QA RUNTIME MARKER REJECTED"
RUNTIME_MARKER_PREFIX_PATTERN = re.compile(r"QA (READY|RESULT)(?=\s|\{|$)")
NATIVE_DIAGNOSTIC_PATTERN = re.compile(r"QA NATIVE [A-Z_]+")
SAFE_NATIVE_DIAGNOSTICS = frozenset(
    {
        "QA NATIVE FIREBASE_CONFIG_VALID",
        "QA NATIVE REACT_START_RETURNED",
        "QA NATIVE BUNDLE_URL_UNAVAILABLE",
        "QA NATIVE BUNDLE_INDEX_QA_LOCALHOST",
        "QA NATIVE BUNDLE_INDEX_QA_NONCANONICAL",
        "QA NATIVE MARKER_BRIDGE_CALLED",
        "QA NATIVE LOCAL_STOREKIT_READY",
        "QA NATIVE LOCAL_STOREKIT_CLEANED",
        "QA NATIVE LOCAL_STOREKIT_EXPIRED",
        "QA NATIVE LOCAL_STOREKIT_ACTION_FAILED",
        "QA NATIVE FIRST_LAUNCH_EMPTY_IDENTITY",
        "QA NATIVE AUTH_NETWORK_BLOCKED",
        "QA NATIVE AUTH_NETWORK_RESTORED",
    }
)
REQUEST_ID_PATTERN = re.compile(
    r"^(?:bootstrap|dispose|first-launch|inspect|open-app|prepare)-[0-9a-f]{32}$"
)
IDENTITY_HASH_PATTERN = re.compile(r"^[0-9a-f]{64}$")
SAFE_ERROR_PATTERN = re.compile(r"^QA_[A-Z0-9_]+$")
RUN_ID_PATTERN = re.compile(r"^qa-[0-9a-z]{8,10}-[1-9][0-9]{0,8}$")
SAFE_INTEGER_PATTERN = re.compile(r"^-?(?:0|[1-9][0-9]{0,15})$")
SCENE_FINGERPRINTS = {
    "r02_end": "r02_end:a3:c7:t9:f0:s0:v1",
    "r06_large_history": "r06_large_history:t20000:f400:v1",
    "r06_large_history_cleanup": "r06_large_history_cleanup:t0:f0:v1",
    "r09_stale_schedule": "r09_stale_schedule:a3:c7:t9:f2:s1:v1",
}
CHECK_FACT_KEYS = {
    "accounting.fixture-summary": frozenset(
        {
            "accounts.live-count",
            "accounts.signature",
            "accounts.tombstone-count",
            "categories.live-count",
            "categories.signature",
            "categories.tombstone-count",
            "currency-configs.count",
            "currency-rates.history-order",
            "currency-rates.live-count",
            "currency-rates.signature",
            "currency-rates.tombstone-count",
            "references.valid",
            "schedule-instances.valid",
            "schedules.live-count",
            "schedules.signature",
            "schedules.tombstone-count",
            "scope.user",
            "settings.base-currency",
            "transactions.live-count",
            "transactions.signature",
            "transactions.tombstone-count",
            "transfers.live-count",
            "transfers.signature",
            "transfers.tombstone-count",
        }
    ),
    "accounting.schedule-backfill": frozenset(
        {
            "schedule-backfill.anchor-valid",
            "schedule-backfill.expected-sequence-valid",
            "schedule-backfill.expected-start",
            "schedule-backfill.generated-count",
            "schedule-backfill.schedule-contract",
            "schedule-backfill.schedule-count",
            "schedule-backfill.sequence",
            "schedule-backfill.template-match",
            "schedule-backfill.tombstone-count",
            "schedule-backfill.unique",
        }
    ),
    "accounting.large-history-overlay": frozenset(
        {
            "dateSpanDays",
            "expenseTotal",
            "expenseTransactionCount",
            "incomeTotal",
            "incomeTransactionCount",
            "incomingTransferCount",
            "newestDate",
            "oldestDate",
            "outgoingTransferCount",
            "periodBalance",
            "recordCount",
            "sameCurrencyAccountPair",
            "transactionAccountShapeValid",
            "transactionAmountShapeValid",
            "transactionCategoryShapeValid",
            "transactionCount",
            "transactionDateShapeValid",
            "transferAmountShapeValid",
            "transferCount",
            "transferDateShapeValid",
            "transferDateSpanDays",
            "transferDirectionShapeValid",
            "transferNewestDate",
            "transferOldestDate",
        }
    ),
}
SAFE_OPERATION_ERRORS = {
    "bootstrap": frozenset(
        {
            "QA_ANONYMOUS_BOOTSTRAP_FAILED",
            "QA_ANONYMOUS_PROVIDER_DISABLED",
            "QA_AUTH_RESTORE_FAILED",
            "QA_AUTH_RESTORE_TIMEOUT",
            "QA_BOOTSTRAP_ENTRY_SELECTION_LOAD_FAILED",
            "QA_BOOTSTRAP_ENTRY_LOAD_FAILED",
            "QA_BOOTSTRAP_ENVIRONMENT_LOAD_FAILED",
            "QA_BOOTSTRAP_IDENTITY_MODULE_LOAD_FAILED",
            "QA_BOOTSTRAP_LAUNCH_PLAN_LOAD_FAILED",
            "QA_BOOTSTRAP_LAUNCH_PLAN_RESOLUTION_FAILED",
            "QA_DISPOSABLE_ANONYMOUS_REQUIRED",
            "QA_FIREBASE_AUTH_CONFIG_REJECTED",
            "QA_FIREBASE_AUTH_NETWORK_FAILED",
            "QA_SESSION_PROOF_CLEAR_FAILED",
            "QA_SESSION_PROOF_WRITE_FAILED",
            "QA_SESSION_PROOF_WRITE_FAILED_IDENTITY_REMAINS",
            "QA_STALE_ANONYMOUS_DISPOSAL_FAILED",
        }
    ),
    "dispose": frozenset(
        {
            "QA_AUTH_RESTORE_TIMEOUT",
            "QA_DISPOSABLE_ANONYMOUS_REQUIRED",
            "QA_DISPOSAL_PROOF_CLEAR_FAILED",
            "QA_DISPOSAL_PROOF_STATE_FAILED",
            "QA_DISPOSAL_SESSION_PROOF_REJECTED",
            "QA_IDENTITY_DELETE_FAILED",
            "QA_IDENTITY_DELETE_NOT_CONFIRMED",
        }
    ),
    "inspect": frozenset(
        {
            "QA_AUTH_REQUIRED",
            "QA_DISABLED",
            "QA_DISPOSABLE_ANONYMOUS_REQUIRED",
            "QA_INVALID_LAUNCH_REQUEST",
            "QA_OPERATION_FAILED",
            "QA_SESSION_STALE",
        }
    ),
    "launch": frozenset(
        {
            "QA_FIRST_LAUNCH_AUTH_RESTORE_FAILED",
            "QA_FIRST_LAUNCH_IDENTITY_NOT_EMPTY",
            "QA_FIRST_LAUNCH_NATIVE_PREPARE_FAILED",
            "QA_FIRST_LAUNCH_DATABASE_NOT_EMPTY",
            "QA_FIRST_LAUNCH_APP_LOAD_FAILED",
            "QA_AUTH_REQUIRED",
            "QA_INVALID_LAUNCH_PLAN",
            "QA_INVALID_OPERATION_PLAN",
            "QA_LAUNCH_FAILED",
            "QA_OPERATION_AUTH_GUARD_FAILED",
            "QA_OPERATION_AUTH_REQUIRED",
            "QA_OPERATION_AUTH_RESTORE_TIMEOUT",
            "QA_OPERATION_GATE_FAILED",
            "QA_OPERATION_IDENTITY_MISMATCH",
            "QA_OPERATION_SESSION_PROOF_REJECTED",
        }
    ),
    "prepare": frozenset(
        {
            "QA_AUTH_REQUIRED",
            "QA_DISABLED",
            "QA_DISPOSABLE_ANONYMOUS_REQUIRED",
            "QA_INVALID_LAUNCH_REQUEST",
            "QA_OPERATION_FAILED",
            "QA_SESSION_STALE",
        }
    ),
}
NESTED_FAILURES = {
    "inspect": ("EVIDENCE_FAILURE", True),
    "prepare": ("PREPARE_FAILED", False),
}
FORBIDDEN_KEY_NAMES = frozenset(
    {
        "accesstoken",
        "firebaseuid",
        "identityhash",
        "qasessiontoken",
        "qasessionuid",
        "rawuid",
        "refreshtoken",
        "sessiontoken",
        "token",
        "uid",
        "userid",
        "useruid",
    }
)
FORBIDDEN_TEXT_PATTERN = re.compile(
    r"(?i)(?:^|[\s,;{[(])(?:uid|user[_-]?id|firebase[_-]?uid|raw[_-]?uid|"
    r"qa_session_uid|session[_-]?token|qa_session_token|access[_-]?token|"
    r"refresh[_-]?token|identityHash)\s*[:=]|"
    r"/(?:users|entitlements|accountDeletions|txnIndex)/[^/\s]+"
)
CONSOLE_CALL_START_PATTERN = re.compile(
    r"\bconsole\.(?:error|info|log|warn)\s*\("
)
SOURCE_FORBIDDEN_IDENTITY_PATTERN = re.compile(
    r"(?i)(?:\.\s*uid\b|\b(?:uid|actualUid|userId|firebaseUid|rawUid|qaSessionUid|"
    r"QA_SESSION_UID|sessionToken|qaSessionToken|QA_SESSION_TOKEN)\b)"
)
SOURCE_EXTENSIONS = frozenset({".js", ".jsx", ".m", ".mm", ".swift", ".ts", ".tsx"})
GOLDEN_FAMILY_EVENTS = {
    "QA ANALYTICS": frozenset(),
    "QA BACKUP": frozenset(
        {"batch", "cooldownStamp", "done", "error", "mode", "probe", "skip", "start"}
    ),
    "QA BOOT": frozenset({"anonymous", "delegate", "resolve", "signIn", "start"}),
    "QA DBQ": frozenset({"single"}),
    "QA FINDING": frozenset(),
    "QA FOCUS": frozenset({"start", "visible"}),
    "QA PAYWALL": frozenset({"overflow"}),
    "QA PREF": frozenset({"error", "skip", "upload"}),
    "QA PREMIUM": frozenset({"loaded", "reconcile", "resolve"}),
    "QA QUOTA": frozenset({"add", "exempt", "gate", "reset"}),
    "QA RCACHE": frozenset({"clear", "summary"}),
    "QA RELEASE": frozenset(),
    "QA SCHED": frozenset({"backfill"}),
    "QA SEED": frozenset(),
    "QA UNDO": frozenset({"done"}),
    "QA VALID": frozenset({"reject"}),
}
GOLDEN_FAMILY_FIELDS = {
    "QA ANALYTICS": frozenset({"event", "name", "requested", "result", "source", "value"}),
    "QA BACKUP": frozenset(
        {
            "batch",
            "code",
            "collection",
            "count",
            "identity",
            "lastSyncedAt",
            "mode",
            "reads",
            "reason",
            "reasons",
            "recovered",
            "remoteHasData",
            "sinceLastMs",
            "stampMs",
            "storage",
            "uploaded",
        }
    ),
    "QA BOOT": frozenset({"landing", "premiumLoaded", "task", "trigger"}),
    "QA DBQ": frozenset({"entity", "found"}),
    "QA FINDING": frozenset(),
    "QA FOCUS": frozenset({"animationMs", "elapsedMs", "mode", "offset"}),
    "QA PAYWALL": frozenset({"content", "lang", "page"}),
    "QA PREF": frozenset({"code", "fields", "lastSyncedAt", "reason", "uiBlocked"}),
    "QA PREMIUM": frozenset({"loaded", "path", "reason", "source", "tier", "triggered"}),
    "QA QUOTA": frozenset({"added", "allowed", "kind", "limit", "todayTotal", "utcDay"}),
    "QA RCACHE": frozenset({"details", "hit", "key", "reason", "summaries"}),
    "QA RELEASE": frozenset(
        {"accounts", "build", "categories", "event", "platform", "result", "version"}
    ),
    "QA SCHED": frozenset({"fromMs", "generated", "scheduleId", "toMs"}),
    "QA SEED": frozenset({"scene", "scheduleInstances", "startOn"}),
    "QA UNDO": frozenset({"action", "cacheCleared"}),
    "QA VALID": frozenset({"op", "reason"}),
}
GOLDEN_COUNT_FIELD_BOUNDS = {
    "accounts": (0, 1_000_000),
    "added": (0, 1_000_000),
    "batch": (0, 1_000_000),
    "categories": (0, 1_000_000),
    "content": (0, 1_000_000),
    "count": (0, 1_000_000),
    "details": (0, 1_000_000),
    "generated": (0, 1_000_000),
    "limit": (0, 1_000_000),
    "page": (0, 1_000_000),
    "reads": (0, 1_000_000),
    "recovered": (0, 1_000_000),
    "requested": (0, 1_000_000),
    "scheduleInstances": (0, 1_000_000),
    "summaries": (0, 1_000_000),
    "todayTotal": (0, 1_000_000),
    "uploaded": (0, 1_000_000),
}
GOLDEN_TIMESTAMP_FIELD_BOUNDS = {
    "fromMs": (0, 9_999_999_999_999_999),
    "lastSyncedAt": (0, 9_999_999_999_999_999),
    "stampMs": (0, 9_999_999_999_999_999),
    "toMs": (0, 9_999_999_999_999_999),
}
EVIDENCE_COUNT_KEY_PATTERN = re.compile(
    r"(?:^|[.-])(?:count|dateSpanDays|recordCount|tombstone-count)$"
)
EVIDENCE_TIMESTAMP_KEYS = frozenset(
    {
        "newestDate",
        "oldestDate",
        "transferNewestDate",
        "transferOldestDate",
    }
)
SAFE_GOLDEN_ENUM_VALUES = frozenset(
    {
        "LEVEL_0",
        "account",
        "account_deletion",
        "bootstrap",
        "category",
        "collection",
        "cooldown",
        "createTransaction",
        "createTransfer",
        "created",
        "device",
        "disabled",
        "enabled",
        "expense",
        "false",
        "fallback-timeout",
        "foreground",
        "full_delta",
        "income",
        "incremental",
        "inflight",
        "initial",
        "initial_data",
        "invalid_currency",
        "ios",
        "launch",
        "missing_field",
        "no_user",
        "non_positive",
        "null",
        "offline",
        "out_of_range",
        "paywall_viewed",
        "preference",
        "prompt",
        "quota",
        "read",
        "reentry",
        "refreshStatus",
        "runBackup",
        "same_account",
        "saved",
        "selected",
        "sent",
        "session-bound",
        "setting",
        "shown",
        "storekit",
        "suspended",
        "theme,language,currency",
        "true",
        "unchanged",
        "unknown",
        "untouched",
        "updateTransaction",
        "updateTransfer",
        "updated",
        "zero_amount",
    }
)
GOLDEN_FIELD_PATTERN = re.compile(r"^[A-Za-z][A-Za-z0-9_-]*=[^\s]+$")


def normalized_key(value: object) -> str:
    return re.sub(r"[^a-z0-9]", "", str(value).lower())


def contains_forbidden_identity(value: object) -> bool:
    if isinstance(value, dict):
        for key, child in value.items():
            if normalized_key(key) in FORBIDDEN_KEY_NAMES:
                return True
            if contains_forbidden_identity(child):
                return True
        return False
    if isinstance(value, list):
        return any(contains_forbidden_identity(child) for child in value)
    if isinstance(value, str):
        return FORBIDDEN_TEXT_PATTERN.search(value) is not None
    return False


def parse_runtime_payload(line: str, prefix: str) -> dict[str, object] | None:
    marker_offset = line.find(prefix)
    if marker_offset < 0:
        return None
    payload_text = line[marker_offset + len(prefix) :].strip()
    try:
        payload = json.loads(payload_text)
    except (json.JSONDecodeError, UnicodeError, ValueError):
        return None
    if not isinstance(payload, dict):
        return None
    return payload


def valid_request_id(value: object, allow_invalid: bool = False) -> bool:
    if not isinstance(value, str):
        return False
    if allow_invalid and value == "invalid":
        return True
    return REQUEST_ID_PATTERN.fullmatch(value) is not None


def deterministic_digest(value: str) -> str:
    return "sha256:" + hashlib.sha256(value.encode("utf-8")).hexdigest()


def safe_run_id(value: object) -> bool:
    return isinstance(value, str) and RUN_ID_PATTERN.fullmatch(value) is not None


def normalized_evidence_scalar(value: object, fact_key: str) -> object | None:
    if value is None or isinstance(value, bool):
        return value
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if isinstance(value, float) and not math.isfinite(value):
            return None
        if EVIDENCE_COUNT_KEY_PATTERN.search(fact_key) is not None:
            if isinstance(value, int) and 0 <= value <= 1_000_000:
                return value
        elif fact_key in EVIDENCE_TIMESTAMP_KEYS:
            if isinstance(value, int) and 0 <= value <= 9_999_999_999_999_999:
                return value
        return deterministic_digest(
            json.dumps(value, ensure_ascii=False, separators=(",", ":"))
        )
    if isinstance(value, str):
        return deterministic_digest(value)
    return None


def normalized_inspect_result(result: object, check_id: str) -> dict[str, object] | None:
    if not isinstance(result, dict) or not safe_run_id(result.get("runId")):
        return None
    if result.get("ok") is False:
        expected_code, expected_recoverable = NESTED_FAILURES["inspect"]
        if set(result) != {"ok", "runId", "code", "recoverable"}:
            return None
        if result.get("code") != expected_code or result.get("recoverable") is not expected_recoverable:
            return None
        return {
            "ok": False,
            "runId": result["runId"],
            "code": expected_code,
            "recoverable": expected_recoverable,
        }
    if result.get("ok") is not True or set(result) != {"ok", "runId", "value"}:
        return None
    evidence = result.get("value")
    if not isinstance(evidence, dict) or set(evidence) != {
        "schema",
        "checkId",
        "verdict",
        "facts",
    }:
        return None
    if evidence.get("schema") != "qa.evidence/v1" or evidence.get("checkId") != check_id:
        return None
    if evidence.get("verdict") not in {"pass", "fail"}:
        return None
    facts = evidence.get("facts")
    if not isinstance(facts, list) or len(facts) > 128:
        return None
    allowed_fact_keys = CHECK_FACT_KEYS[check_id]
    normalized_facts: list[dict[str, object]] = []
    for fact in facts:
        if not isinstance(fact, dict) or not {"key", "actual"}.issubset(fact):
            return None
        if not set(fact).issubset({"key", "actual", "expected", "pass"}):
            return None
        fact_key = fact.get("key")
        if not isinstance(fact_key, str) or fact_key not in allowed_fact_keys:
            return None
        normalized_actual = normalized_evidence_scalar(fact.get("actual"), fact_key)
        if normalized_actual is None and fact.get("actual") is not None:
            return None
        normalized_fact: dict[str, object] = {
            "key": fact_key,
            "actual": normalized_actual,
        }
        if "expected" in fact:
            normalized_expected = normalized_evidence_scalar(fact.get("expected"), fact_key)
            if normalized_expected is None and fact.get("expected") is not None:
                return None
            normalized_fact["expected"] = normalized_expected
        if "pass" in fact:
            if not isinstance(fact.get("pass"), bool):
                return None
            normalized_fact["pass"] = fact["pass"]
        normalized_facts.append(normalized_fact)
    return {
        "ok": True,
        "runId": result["runId"],
        "value": {
            "schema": "qa.evidence/v1",
            "checkId": check_id,
            "verdict": evidence["verdict"],
            "facts": normalized_facts,
        },
    }


def normalized_prepare_result(result: object, scene_id: str) -> dict[str, object] | None:
    if not isinstance(result, dict) or not safe_run_id(result.get("runId")):
        return None
    if result.get("ok") is False:
        expected_code, expected_recoverable = NESTED_FAILURES["prepare"]
        if set(result) != {"ok", "runId", "code", "recoverable"}:
            return None
        if result.get("code") != expected_code or result.get("recoverable") is not expected_recoverable:
            return None
        return {
            "ok": False,
            "runId": result["runId"],
            "code": expected_code,
            "recoverable": expected_recoverable,
        }
    if result.get("ok") is not True or set(result) != {"ok", "runId", "value"}:
        return None
    prepared = result.get("value")
    if not isinstance(prepared, dict) or set(prepared) != {"sceneId", "fingerprint"}:
        return None
    if prepared.get("sceneId") != scene_id:
        return None
    if prepared.get("fingerprint") != SCENE_FINGERPRINTS[scene_id]:
        return None
    return {
        "ok": True,
        "runId": result["runId"],
        "value": {
            "sceneId": scene_id,
            "fingerprint": SCENE_FINGERPRINTS[scene_id],
        },
    }


def normalized_dispose_result(result: object) -> dict[str, object] | None:
    if not isinstance(result, dict) or set(result) != {"ok", "value"}:
        return None
    value = result.get("value")
    if result.get("ok") is not True or not isinstance(value, dict):
        return None
    if set(value) != {"identityMode", "authDeleted"}:
        return None
    if value.get("identityMode") != "disposable-anonymous" or value.get("authDeleted") is not True:
        return None
    return {
        "ok": True,
        "value": {
            "identityMode": "disposable-anonymous",
            "authDeleted": True,
        },
    }


def safe_ready_line(line: str) -> str | None:
    prefix = "QA READY "
    payload = parse_runtime_payload(line, prefix)
    if payload is None:
        return None
    allowed_keys = {
        "schema",
        "requestId",
        "state",
        "identityMode",
        "isAnonymous",
        "identityHash",
    }
    if set(payload) != allowed_keys:
        return None
    if payload.get("schema") != RUNTIME_SCHEMA or payload.get("state") != "ready":
        return None
    if payload.get("identityMode") != "disposable-anonymous":
        return None
    if payload.get("isAnonymous") is not True:
        return None
    request_id = payload.get("requestId")
    identity_hash = payload.get("identityHash")
    if not valid_request_id(request_id):
        return None
    if not isinstance(identity_hash, str) or IDENTITY_HASH_PATTERN.fullmatch(identity_hash) is None:
        return None
    return prefix + json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def contains_ready_identity_digest(value: object, ready_identity_hash: str | None) -> bool:
    if ready_identity_hash is None:
        return False
    identity_digest = "sha256:" + ready_identity_hash
    if isinstance(value, dict):
        return any(
            contains_ready_identity_digest(child, ready_identity_hash)
            for child in value.values()
        )
    if isinstance(value, list):
        return any(
            contains_ready_identity_digest(child, ready_identity_hash)
            for child in value
        )
    return isinstance(value, str) and identity_digest in value


def safe_result_line(line: str, ready_identity_hash: str | None = None) -> str | None:
    prefix = "QA RESULT "
    payload = parse_runtime_payload(line, prefix)
    if payload is None:
        return None
    base_keys = {"schema", "requestId", "operation", "value"}
    if frozenset(payload) not in {
        frozenset(base_keys | {"result"}),
        frozenset(base_keys | {"error"}),
    }:
        return None
    if payload.get("schema") != RUNTIME_SCHEMA:
        return None
    request_id = payload.get("requestId")
    operation = payload.get("operation")
    value = payload.get("value")
    if not isinstance(operation, str) or operation not in SAFE_OPERATION_ERRORS:
        return None
    if not valid_request_id(request_id, allow_invalid=operation == "launch"):
        return None
    if operation == "launch" and value is not None:
        return None
    if operation in {"bootstrap", "dispose"} and value != "identity":
        return None
    if operation == "prepare" and value not in SCENE_FINGERPRINTS:
        return None
    if operation == "inspect" and value not in CHECK_FACT_KEYS:
        return None
    if "error" in payload:
        error = payload.get("error")
        if not isinstance(error, str) or error not in SAFE_OPERATION_ERRORS[operation]:
            return None
        normalized_payload = {
            "schema": RUNTIME_SCHEMA,
            "requestId": request_id,
            "operation": operation,
            "value": value,
            "error": error,
        }
        return prefix + json.dumps(normalized_payload, ensure_ascii=False, separators=(",", ":"))
    if operation == "dispose":
        normalized_result = normalized_dispose_result(payload.get("result"))
    elif operation == "inspect":
        normalized_result = normalized_inspect_result(payload.get("result"), value)
    elif operation == "prepare":
        normalized_result = normalized_prepare_result(payload.get("result"), value)
    else:
        normalized_result = None
    if normalized_result is None:
        return None
    normalized_payload = {
        "schema": RUNTIME_SCHEMA,
        "requestId": request_id,
        "operation": operation,
        "value": value,
        "result": normalized_result,
    }
    if contains_forbidden_identity(normalized_payload):
        return None
    if contains_ready_identity_digest(normalized_payload, ready_identity_hash):
        return None
    return prefix + json.dumps(normalized_payload, ensure_ascii=False, separators=(",", ":"))


def normalized_golden_value(field: str, value: str) -> str | None:
    if len(value) > 512:
        return None
    if value in SAFE_GOLDEN_ENUM_VALUES:
        return value
    if field in GOLDEN_COUNT_FIELD_BOUNDS and SAFE_INTEGER_PATTERN.fullmatch(value):
        lower_bound, upper_bound = GOLDEN_COUNT_FIELD_BOUNDS[field]
        parsed_value = int(value)
        if lower_bound <= parsed_value <= upper_bound:
            return value
    if field in GOLDEN_TIMESTAMP_FIELD_BOUNDS and SAFE_INTEGER_PATTERN.fullmatch(value):
        lower_bound, upper_bound = GOLDEN_TIMESTAMP_FIELD_BOUNDS[field]
        parsed_value = int(value)
        if lower_bound <= parsed_value <= upper_bound:
            return value
    return deterministic_digest(value)


def safe_golden_line(
    line: str,
    allowed_families: frozenset[str],
    ready_identity_hash: str | None = None,
    emit_identity_collision_sentinel: bool = False,
) -> str | None:
    for family in sorted(allowed_families, key=len, reverse=True):
        marker_offset = line.find(family)
        if marker_offset < 0:
            continue
        marker = line[marker_offset:].rstrip("\r\n")
        if marker != family and not marker.startswith(family + " "):
            continue
        if len(marker) > 8192 or any(ord(character) < 32 for character in marker):
            return None
        if FORBIDDEN_TEXT_PATTERN.search(marker) is not None:
            return None
        marker_tokens = marker[len(family) :].strip().split()
        normalized_tokens: list[str] = []
        for marker_token in marker_tokens:
            if "=" not in marker_token:
                if marker_token not in GOLDEN_FAMILY_EVENTS[family]:
                    return None
                normalized_tokens.append(marker_token)
                continue
            if GOLDEN_FIELD_PATTERN.fullmatch(marker_token) is None:
                return None
            marker_key, marker_value = marker_token.split("=", 1)
            if marker_key not in GOLDEN_FAMILY_FIELDS[family]:
                return None
            normalized_marker_value = normalized_golden_value(marker_key, marker_value)
            if normalized_marker_value is None:
                return None
            normalized_tokens.append(f"{marker_key}={normalized_marker_value}")
        normalized_marker = family + (
            " " + " ".join(normalized_tokens) if normalized_tokens else ""
        )
        if contains_ready_identity_digest(normalized_marker, ready_identity_hash):
            if emit_identity_collision_sentinel:
                return RUNTIME_MARKER_REJECTION_SENTINEL
            return None
        return normalized_marker
    return None


def contains_selected_golden_marker(
    line: str,
    allowed_families: frozenset[str],
) -> bool:
    for family in allowed_families:
        marker_offset = line.find(family)
        if marker_offset < 0:
            continue
        marker = line[marker_offset:].rstrip("\r\n")
        if marker == family or marker.startswith(family + " "):
            return True
    return False


def safe_pre_ready_failure_result(safe_line: str) -> bool:
    prefix = "QA RESULT "
    if not safe_line.startswith(prefix):
        return False
    try:
        payload = json.loads(safe_line[len(prefix) :])
    except (json.JSONDecodeError, UnicodeError):
        return False
    return (
        isinstance(payload, dict)
        and "error" in payload
        and "result" not in payload
        and payload.get("operation") in {"bootstrap", "launch", "dispose"}
    )


def filter_stream(allowed_families: frozenset[str], first_launch: bool = False) -> int:
    ready_identity_hash: str | None = None
    empty_identity_observed = False
    for line in sys.stdin:
        runtime_markers = RUNTIME_MARKER_PREFIX_PATTERN.findall(line)
        native_diagnostics = NATIVE_DIAGNOSTIC_PATTERN.findall(line)
        if len(runtime_markers) + len(native_diagnostics) > 1:
            safe_line = RUNTIME_MARKER_REJECTION_SENTINEL
        elif native_diagnostics:
            candidate = native_diagnostics[0]
            if first_launch and candidate == "QA NATIVE FIRST_LAUNCH_EMPTY_IDENTITY":
                empty_identity_observed = True
            safe_line = (
                candidate
                if candidate in SAFE_NATIVE_DIAGNOSTICS
                else RUNTIME_MARKER_REJECTION_SENTINEL
            )
        elif runtime_markers == ["READY"]:
            safe_line = safe_ready_line(line)
            if safe_line is None:
                safe_line = RUNTIME_MARKER_REJECTION_SENTINEL
            else:
                ready_payload = json.loads(safe_line[len("QA READY ") :])
                candidate_identity_hash = ready_payload["identityHash"]
                if ready_identity_hash is None:
                    ready_identity_hash = candidate_identity_hash
                elif candidate_identity_hash != ready_identity_hash:
                    safe_line = RUNTIME_MARKER_REJECTION_SENTINEL
        elif runtime_markers == ["RESULT"]:
            safe_line = safe_result_line(line, ready_identity_hash)
            if safe_line is None:
                safe_line = RUNTIME_MARKER_REJECTION_SENTINEL
            elif ready_identity_hash is None and not safe_pre_ready_failure_result(safe_line):
                safe_line = RUNTIME_MARKER_REJECTION_SENTINEL
        else:
            golden_marker_present = contains_selected_golden_marker(
                line,
                allowed_families,
            )
            safe_line = safe_golden_line(
                line,
                allowed_families,
                ready_identity_hash,
                emit_identity_collision_sentinel=True,
            )
            allowed_initial_attempt = (first_launch and empty_identity_observed
                                       and safe_line == "QA BOOT anonymous signIn start")
            if golden_marker_present and (safe_line is None or
                    (ready_identity_hash is None and not allowed_initial_attempt)):
                safe_line = RUNTIME_MARKER_REJECTION_SENTINEL
        if safe_line is not None:
            sys.stdout.write(safe_line + "\n")
            sys.stdout.flush()
    return 0


def normalized_expected_marker(marker: str) -> str | None:
    matching_families = [
        family
        for family in SAFE_GOLDEN_FAMILIES
        if marker == family or marker.startswith(family + " ")
    ]
    if len(matching_families) != 1:
        return None
    return safe_golden_line(marker, frozenset(matching_families))


def source_files(source_root: Path):
    if source_root.is_file():
        yield source_root
        return
    for path in source_root.rglob("*"):
        if path.is_file() and path.suffix in SOURCE_EXTENSIONS:
            yield path


def console_calls(source_text: str):
    for start_match in CONSOLE_CALL_START_PATTERN.finditer(source_text):
        call_start = start_match.start()
        cursor = start_match.end()
        parenthesis_depth = 1
        quote = ""
        escaped = False
        while cursor < len(source_text) and parenthesis_depth > 0:
            character = source_text[cursor]
            if quote:
                if escaped:
                    escaped = False
                elif character == "\\":
                    escaped = True
                elif character == quote:
                    quote = ""
            elif character in {"'", '"', "`"}:
                quote = character
            elif character == "(":
                parenthesis_depth += 1
            elif character == ")":
                parenthesis_depth -= 1
            cursor += 1
        if parenthesis_depth == 0:
            yield source_text[call_start:cursor]


def skip_quoted_literal(source_text: str, start: int, quote: str) -> int:
    cursor = start + 1
    escaped = False
    while cursor < len(source_text):
        character = source_text[cursor]
        if escaped:
            escaped = False
        elif character == "\\":
            escaped = True
        elif character == quote:
            return cursor + 1
        cursor += 1
    return len(source_text)


def find_matching_expression_brace(source_text: str, start: int) -> int | None:
    cursor = start
    brace_depth = 1
    while cursor < len(source_text):
        character = source_text[cursor]
        if character in {"'", '"'}:
            cursor = skip_quoted_literal(source_text, cursor, character)
            continue
        if character == "`":
            cursor = skip_template_literal(source_text, cursor)
            continue
        if character == "{":
            brace_depth += 1
        elif character == "}":
            brace_depth -= 1
            if brace_depth == 0:
                return cursor
        cursor += 1
    return None


def skip_template_literal(source_text: str, start: int) -> int:
    cursor = start + 1
    escaped = False
    while cursor < len(source_text):
        character = source_text[cursor]
        if escaped:
            escaped = False
            cursor += 1
            continue
        if character == "\\":
            escaped = True
            cursor += 1
            continue
        if character == "`":
            return cursor + 1
        if character == "$" and cursor + 1 < len(source_text) and source_text[cursor + 1] == "{":
            expression_end = find_matching_expression_brace(source_text, cursor + 2)
            if expression_end is None:
                return len(source_text)
            cursor = expression_end + 1
            continue
        cursor += 1
    return len(source_text)


def source_expression_text(source_text: str) -> str:
    expressions: list[str] = []
    cursor = 0
    while cursor < len(source_text):
        character = source_text[cursor]
        if character in {"'", '"'}:
            cursor = skip_quoted_literal(source_text, cursor, character)
            expressions.append(" ")
            continue
        if character == "`":
            cursor += 1
            escaped = False
            while cursor < len(source_text):
                template_character = source_text[cursor]
                if escaped:
                    escaped = False
                    cursor += 1
                    continue
                if template_character == "\\":
                    escaped = True
                    cursor += 1
                    continue
                if template_character == "`":
                    cursor += 1
                    break
                if (
                    template_character == "$"
                    and cursor + 1 < len(source_text)
                    and source_text[cursor + 1] == "{"
                ):
                    expression_end = find_matching_expression_brace(source_text, cursor + 2)
                    if expression_end is None:
                        return ""
                    expressions.append(source_expression_text(source_text[cursor + 2 : expression_end]))
                    cursor = expression_end + 1
                    continue
                cursor += 1
            expressions.append(" ")
            continue
        expressions.append(character)
        cursor += 1
    return "".join(expressions)


def scan_source(source_root: Path) -> int:
    if not source_root.exists():
        return 2
    for path in source_files(source_root):
        try:
            source_text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            return 2
        for console_call in console_calls(source_text):
            if SOURCE_FORBIDDEN_IDENTITY_PATTERN.search(source_expression_text(console_call)) is not None:
                return 1
    return 0


def parse_arguments(arguments: list[str]) -> tuple[frozenset[str], Path | None, bool] | None:
    allowed_families: set[str] = set()
    source_root: Path | None = None
    first_launch = False
    index = 0
    while index < len(arguments):
        argument = arguments[index]
        if argument not in {"--allow-golden-marker", "--scan-source", "--allow-first-launch"} or index + 1 >= len(arguments):
            return None
        value = arguments[index + 1]
        if argument == "--allow-golden-marker":
            if value not in SAFE_GOLDEN_FAMILIES or source_root is not None:
                return None
            allowed_families.add(value)
        elif argument == "--allow-first-launch":
            if first_launch or value != "true" or source_root is not None:
                return None
            first_launch = True
        else:
            if source_root is not None or allowed_families or first_launch:
                return None
            source_root = Path(value)
        index += 2
    return frozenset(allowed_families), source_root, first_launch


def main() -> int:
    if len(sys.argv) == 3 and sys.argv[1] == "--normalize-expected-marker":
        normalized_marker = normalized_expected_marker(sys.argv[2])
        if normalized_marker is None:
            return 1
        sys.stdout.write(normalized_marker + "\n")
        return 0
    parsed_arguments = parse_arguments(sys.argv[1:])
    if parsed_arguments is None:
        return 2
    allowed_families, source_root, first_launch = parsed_arguments
    if source_root is not None:
        return scan_source(source_root)
    return filter_stream(allowed_families, first_launch)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        raise SystemExit(0)
