#!/usr/bin/env python3

from __future__ import annotations

import json
import hashlib
import os
import pathlib
import re
import stat
import sys


QA_GOLDEN_SCHEMA = "susugigi.qa.fixture-golden/v1"
QA_GOLDEN_MAX_BYTES = 256 * 1024
QA_NAME_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
QA_R13_SQLITE_AGGREGATE_PATTERN = re.compile(
    r"^profile=r13_schedule_backfill "
    r"scheduleCount=(?P<schedule_count>[0-9]{1,7}) "
    r"liveInstanceCount=(?P<live_count>[0-9]{1,7}) "
    r"generatedCount=(?P<generated_count>[0-9]{1,7}) "
    r"distinctInstanceDateCount=(?P<distinct_count>[0-9]{1,7}) "
    r"tombstoneCount=(?P<tombstone_count>[0-9]{1,7}) "
    r"scheduleContract=(?P<schedule_contract>true|false) "
    r"dueSequenceValid=(?P<due_sequence_valid>true|false) "
    r"templateMatch=(?P<template_match>true|false)$"
)
QA_EXPECTED_TOP_LEVEL_KEYS = frozenset(
    {"schema", "scenes", "firestoreProfiles", "sqliteProfiles"}
)
QA_EXPECTED_SCENE_KEYS = frozenset({"r02_end", "r09_stale_schedule"})
QA_EXPECTED_SCENE_SIGNATURE_IDS = {
    "r02_end": {
        "accounts.signature": "accounting-accounts-v1",
        "categories.signature": "accounting-categories-v1",
        "transactions.signature": "r02-transactions-relative-date-v1",
        "transfers.signature": "empty-transfers-v1",
        "currency-rates.signature": "placeholder-jpy-twd-v1",
        "schedules.signature": "empty-schedules-v1",
    },
    "r09_stale_schedule": {
        "accounts.signature": "accounting-accounts-v1",
        "categories.signature": "accounting-categories-v1",
        "transactions.signature": "r09-stale-schedule-transactions-relative-date-v1",
        "transfers.signature": "r03-transfers-final-relative-date-v1",
        "currency-rates.signature": "placeholder-plus-4.4-4.5-bidirectional-v1",
        "schedules.signature": "daily-breakfast-stale-schedule-v1",
    },
}
QA_EXPECTED_SCENE_INDEPENDENT_PROFILE_IDS = {
    "r02_end": "r03_initial_backup",
    "r09_stale_schedule": "r13_schedule_backfill",
}
QA_EXPECTED_SQLITE_PROFILE_KEYS = frozenset(
    {"r08_original_language", "r13_schedule_backfill"}
)
QA_SCENE_OBJECT_KEYS = frozenset(
    {
        "fingerprint",
        "inspectCheckId",
        "requiredFactKeys",
        "expectedCounts",
        "signatureIds",
        "independentProfileId",
        "requiredRelations",
    }
)
QA_SQLITE_OBJECT_KEYS = frozenset(
    {
        "checkpointKey",
        "sceneId",
        "inspectCheckId",
        "requiredFactKeys",
        "expectedValues",
        "requiredRelations",
    }
)
QA_FIRESTORE_PROFILE_OBJECT_KEYS = frozenset(
    {
        "checkpointKey",
        "resourceKind",
        "sceneId",
        "inspectCheckId",
        "requiredFields",
        "expectedCounts",
        "requiredRelations",
    }
)
QA_EXPECTED_FIRESTORE_PROFILES = {
    "r01_anonymous_user": {
        "checkpointKey": "R01:11",
        "resourceKind": "user-document",
        "sceneId": None,
        "inspectCheckId": None,
        "requiredFields": {
            "provider": "anonymous",
            "email": None,
            "createdAt": "present-timestamp",
            "lastLoginAt": "present-timestamp",
            "updatedAt": "present-timestamp",
        },
        "expectedCounts": {"documents": 1},
        "requiredRelations": [
            "path-belongs-to-session-identity",
            "timestamp-baseline-is-private-shell-memory",
        ],
    },
    "r01_user_unchanged": {
        "checkpointKey": "R01:15",
        "resourceKind": "user-document",
        "sceneId": None,
        "inspectCheckId": None,
        "requiredFields": {
            "provider": "anonymous",
            "email": None,
            "createdAt": "present-timestamp",
            "lastLoginAt": "present-timestamp",
            "updatedAt": "present-timestamp",
        },
        "expectedCounts": {"documents": 1},
        "requiredRelations": [
            "path-belongs-to-session-identity",
            "identity-hash-equals-r01-ready",
            "created-at-equals-r01-bootstrap",
            "identity-digest-excludes-last-login-at-and-updated-at",
            "last-login-at-not-earlier-than-r01-11-private-baseline",
            "updated-at-not-earlier-than-r01-11-private-baseline",
            "preferences-are-out-of-scope",
        ],
    },
    "r03_initial_backup": {
        "checkpointKey": "R03:9",
        "resourceKind": "user-subcollections",
        "sceneId": "r02_end",
        "inspectCheckId": "accounting.fixture-summary",
        "requiredFields": {"breakfastAmount": 150},
        "expectedCounts": {
            "accounts": 3,
            "categories": 7,
            "transactions": 9,
            "transfers": 0,
            "currencyRates": 1,
            "schedules": 0,
        },
        "requiredRelations": [
            "path-belongs-to-session-identity",
            "result-facts-match-scene-golden",
            "sync-suspension-reason-is-qa-fixture-reset",
            "sync-suspended-through-prepare-and-inspect",
            "remote-subtree-absent-before-prepare",
            "watermark-null-before-initial-backup",
            "open-app-resumes-sync",
            "initial-backup-does-not-skip-for-device-cooldown",
            "initial-backup-marker-follows-open-app",
        ],
    },
    "r03_incremental_backup": {
        "checkpointKey": "R03:21",
        "resourceKind": "user-subcollection",
        "sceneId": None,
        "inspectCheckId": None,
        "requiredFields": {
            "incrementalNote": "增量備份",
            "incrementalAmount": 200,
            "sameCurrencyAmountFrom": 2000,
            "sameCurrencyAmountTo": 2000,
            "crossCurrencyAmountFrom": 1000,
            "crossCurrencyAmountTo": 4500,
        },
        "expectedCounts": {"transactions": 10, "transfers": 2},
        "requiredRelations": [
            "path-belongs-to-session-identity",
            "incremental-row-is-additive",
            "existing-r02-rows-remain",
            "transfer-pairs-match-r03-final",
            "transactions-have-zero-extra-live-rows",
            "transfers-have-zero-extra-live-rows",
        ],
    },
    "r03_updated_backup": {
        "checkpointKey": "R03:24",
        "resourceKind": "user-subcollection",
        "sceneId": None,
        "inspectCheckId": None,
        "requiredFields": {
            "incrementalNote": "增量備份已修改",
            "incrementalAmount": 275
        },
        "expectedCounts": {
            "transactions": 10,
            "transactionTombstones": 0,
            "transfers": 2
        },
        "requiredRelations": [
            "path-belongs-to-session-identity",
            "existing-r02-rows-remain",
            "transfer-pairs-match-r03-final",
            "updated-row-replaces-original-values",
            "transactions-have-zero-extra-live-rows"
        ]
    },
    "r03_deleted_backup": {
        "checkpointKey": "R03:27",
        "resourceKind": "user-subcollection",
        "sceneId": None,
        "inspectCheckId": None,
        "requiredFields": {
            "deletedNote": "增量備份已修改",
            "deletedAmount": 275,
            "deletedOn": "present-timestamp"
        },
        "expectedCounts": {
            "transactions": 9,
            "transactionTombstones": 1,
            "transfers": 2
        },
        "requiredRelations": [
            "path-belongs-to-session-identity",
            "existing-r02-rows-remain",
            "transfer-pairs-match-r03-final",
            "deleted-row-has-tombstone",
            "transactions-have-zero-extra-live-rows"
        ]
    },
    "r08_preferences_baseline": {
        "checkpointKey": "R08:15",
        "resourceKind": "user-document",
        "sceneId": None,
        "inspectCheckId": None,
        "requiredFields": {"updatedAt": "present-timestamp"},
        "expectedCounts": {"documents": 1},
        "requiredRelations": [
            "path-belongs-to-session-identity",
            "baseline-precedes-first-cs01-change",
            "timestamp-baseline-is-private-shell-memory",
        ],
    },
    "r08_preferences": {
        "checkpointKey": "R08:21",
        "resourceKind": "user-document",
        "sceneId": None,
        "inspectCheckId": None,
        "requiredFields": {"theme": "theme3", "currency": "USD"},
        "expectedCounts": {"documents": 1},
        "requiredRelations": [
            "path-belongs-to-session-identity",
            "language-equals-private-sqlite-baseline",
            "root-updated-at-is-later-than-r08-15-private-baseline",
            "backup-watermark-unchanged",
        ],
    },
}
QA_EXPECTED_SQLITE_PROFILES = {
    "r08_original_language": {
        "checkpointKey": "R08:8",
        "sceneId": None,
        "inspectCheckId": None,
        "requiredFactKeys": ["language"],
        "expectedValues": {
            "sourceTable": "settings",
            "sourceColumn": "language",
            "liveRowCount": 1,
        },
        "requiredRelations": [
            "canonical-qa-sqlite-only",
            "session-uid-from-stdin-only",
            "live-settings-row-exact-one",
            "captured-before-first-manual-language-change",
            "private-shell-memory-only",
        ],
    },
    "r13_schedule_backfill": {
        "checkpointKey": "R13:6",
        "sceneId": "r09_stale_schedule",
        "inspectCheckId": "accounting.schedule-backfill",
        "requiredFactKeys": [
            "schedule-backfill.anchor-valid",
            "schedule-backfill.schedule-count",
            "schedule-backfill.schedule-contract",
            "schedule-backfill.expected-start",
            "schedule-backfill.expected-sequence-valid",
            "schedule-backfill.sequence",
            "schedule-backfill.unique",
            "schedule-backfill.tombstone-count",
            "schedule-backfill.template-match",
            "schedule-backfill.generated-count",
        ],
        "expectedValues": {
            "scheduleCount": 1,
            "frequency": "DAILY",
            "interval": 1,
            "endOn": None,
            "isTransfer": False,
            "tombstoneCount": 0,
            "startMonthOffset": -1,
            "startDay": 5,
            "templateNote": "早餐",
            "templateCategoryName": "餐飲",
            "templateAccountName": "錢包",
            "templateAmount": 150,
        },
        "requiredRelations": [
            "global-session-identity-bound-before-prepare",
            "remote-subtree-absent-before-prepare",
            "canonical-qa-sqlite-only",
            "sync-suspension-reason-is-qa-fixture-reset",
            "due-dates-are-daily-and-inclusive-through-now",
            "schedule-fixture-semantics-match-quality-literals",
            "distinct-instance-date-count-equals-live-count",
            "generated-count-equals-live-count-minus-seed",
            "all-live-instances-match-quality-literals",
            "result-facts-match-sqlite-aggregation",
            "cleanup-uses-same-session-identity",
        ],
    }
}


class GoldenRejected(Exception):
    pass


def reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
    document: dict[str, object] = {}
    for key, value in pairs:
        if key in document:
            raise GoldenRejected
        document[key] = value
    return document


def parse_integer(value: str) -> int:
    if len(value.lstrip("-")) > 12:
        raise GoldenRejected
    return int(value)


def reject_float(_value: str) -> float:
    raise GoldenRejected


def decode_json(encoded: bytes) -> object:
    if len(encoded) > QA_GOLDEN_MAX_BYTES:
        raise GoldenRejected
    try:
        return json.loads(
            encoded.decode("utf-8"),
            object_pairs_hook=reject_duplicate_keys,
            parse_int=parse_integer,
            parse_float=reject_float,
            parse_constant=reject_float,
        )
    except (GoldenRejected, json.JSONDecodeError, UnicodeError, ValueError) as error:
        raise GoldenRejected from error


def read_locked_json(path_text: str) -> object:
    path = pathlib.Path(path_text)
    try:
        if path.is_symlink():
            raise GoldenRejected
        flags = os.O_RDONLY
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        descriptor = os.open(path, flags)
        try:
            metadata = os.fstat(descriptor)
            if not stat.S_ISREG(metadata.st_mode) or not 0 < metadata.st_size <= QA_GOLDEN_MAX_BYTES:
                raise GoldenRejected
            with os.fdopen(descriptor, "rb", closefd=False) as source:
                encoded = source.read(QA_GOLDEN_MAX_BYTES + 1)
        finally:
            os.close(descriptor)
    except (OSError, ValueError) as error:
        raise GoldenRejected from error
    return decode_json(encoded)


def read_stdin_json() -> object:
    try:
        encoded = sys.stdin.buffer.read(QA_GOLDEN_MAX_BYTES + 1)
    except OSError as error:
        raise GoldenRejected from error
    return decode_json(encoded)


def read_stdin_text() -> str:
    try:
        encoded = sys.stdin.buffer.read(QA_GOLDEN_MAX_BYTES + 1)
        if not encoded or len(encoded) > QA_GOLDEN_MAX_BYTES:
            raise GoldenRejected
        return encoded.decode("utf-8").rstrip("\n")
    except (OSError, UnicodeError) as error:
        raise GoldenRejected from error


def require_exact_keys(value: object, expected: frozenset[str]) -> dict[str, object]:
    if not isinstance(value, dict) or set(value) != expected:
        raise GoldenRejected
    return value


def require_name(value: object) -> str:
    if not isinstance(value, str) or QA_NAME_PATTERN.fullmatch(value) is None:
        raise GoldenRejected
    return value


def require_name_list(value: object) -> list[str]:
    if not isinstance(value, list) or not 1 <= len(value) <= 128:
        raise GoldenRejected
    names = [require_name(item) for item in value]
    if len(set(names)) != len(names):
        raise GoldenRejected
    return names


def require_bounded_scalar(value: object) -> None:
    if value is None or isinstance(value, bool):
        return
    if isinstance(value, int) and abs(value) <= 1_000_000_000_000:
        return
    if isinstance(value, str) and len(value) <= 256:
        return
    raise GoldenRejected


def require_scalar_map(value: object, maximum_items: int = 64) -> dict[str, object]:
    if not isinstance(value, dict) or not 1 <= len(value) <= maximum_items:
        raise GoldenRejected
    for key, item in value.items():
        require_name(key)
        require_bounded_scalar(item)
    return value


def require_count_map(value: object, expected_keys: frozenset[str] | None = None) -> None:
    count_map = require_scalar_map(value)
    if expected_keys is not None and set(count_map) != expected_keys:
        raise GoldenRejected
    for count in count_map.values():
        if isinstance(count, bool) or not isinstance(count, int) or not 0 <= count <= 1_000_000:
            raise GoldenRejected


def exact_literal_match(actual: object, expected: object) -> bool:
    if type(actual) is not type(expected):
        return False
    if isinstance(expected, dict):
        return set(actual) == set(expected) and all(
            exact_literal_match(actual[key], expected[key]) for key in expected
        )
    if isinstance(expected, list):
        return len(actual) == len(expected) and all(
            exact_literal_match(actual_item, expected_item)
            for actual_item, expected_item in zip(actual, expected)
        )
    return actual == expected


def validate_scenes(value: object) -> None:
    scenes = require_exact_keys(value, QA_EXPECTED_SCENE_KEYS)
    count_keys = frozenset(
        {
            "accounts",
            "categories",
            "transactions",
            "transfers",
            "currencyRates",
            "schedules",
            "tombstones",
            "currencyConfigs",
        }
    )
    signature_keys = frozenset(QA_EXPECTED_SCENE_SIGNATURE_IDS["r02_end"])
    for scene_id, untrusted_scene in scenes.items():
        scene = require_exact_keys(untrusted_scene, QA_SCENE_OBJECT_KEYS)
        fingerprint = require_name(scene["fingerprint"])
        if not fingerprint.startswith(f"{scene_id}:"):
            raise GoldenRejected
        if scene["inspectCheckId"] != "accounting.fixture-summary":
            raise GoldenRejected
        require_name_list(scene["requiredFactKeys"])
        require_count_map(scene["expectedCounts"], count_keys)
        signatures = require_scalar_map(scene["signatureIds"])
        if set(signatures) != signature_keys:
            raise GoldenRejected
        if signatures != QA_EXPECTED_SCENE_SIGNATURE_IDS[scene_id]:
            raise GoldenRejected
        if scene["independentProfileId"] \
            != QA_EXPECTED_SCENE_INDEPENDENT_PROFILE_IDS[scene_id]:
            raise GoldenRejected
        for signature_id in signatures.values():
            require_name(signature_id)
        relations = require_name_list(scene["requiredRelations"])
        if relations[0] != "remote-subtree-absent-before-prepare":
            raise GoldenRejected


def validate_sqlite_profiles(value: object) -> None:
    profiles = require_exact_keys(value, QA_EXPECTED_SQLITE_PROFILE_KEYS)
    if not exact_literal_match(profiles, QA_EXPECTED_SQLITE_PROFILES):
        raise GoldenRejected
    for profile_name in QA_EXPECTED_SQLITE_PROFILE_KEYS:
        profile = require_exact_keys(profiles[profile_name], QA_SQLITE_OBJECT_KEYS)
        require_name_list(profile["requiredFactKeys"])
        require_scalar_map(profile["expectedValues"])
        require_name_list(profile["requiredRelations"])


def validate_firestore_profiles(value: object) -> dict[str, object]:
    profiles = require_exact_keys(value, frozenset(QA_EXPECTED_FIRESTORE_PROFILES))
    for profile_name, expected in QA_EXPECTED_FIRESTORE_PROFILES.items():
        profile = require_exact_keys(
            profiles[profile_name], QA_FIRESTORE_PROFILE_OBJECT_KEYS
        )
        if profile != expected:
            raise GoldenRejected
    return profiles


def validate_golden(document: object) -> dict[str, object]:
    root = require_exact_keys(document, QA_EXPECTED_TOP_LEVEL_KEYS)
    if root["schema"] != QA_GOLDEN_SCHEMA:
        raise GoldenRejected
    validate_scenes(root["scenes"])
    validate_firestore_profiles(root["firestoreProfiles"])
    validate_sqlite_profiles(root["sqliteProfiles"])
    scenes = root["scenes"]
    independent_profiles = {
        **root["firestoreProfiles"],
        **root["sqliteProfiles"],
    }
    if not isinstance(scenes, dict) \
        or not isinstance(independent_profiles, dict) \
        or any(
            not isinstance(scene, dict)
            or scene.get("independentProfileId") not in independent_profiles
            for scene in scenes.values()
        ):
        raise GoldenRejected
    return root


def evidence_digest(value: str) -> str:
    return "sha256:" + hashlib.sha256(value.encode("utf-8")).hexdigest()


def validate_scene_prepare(
    root: dict[str, object], scene_id: str, prepared: object
) -> None:
    scenes = root["scenes"]
    if scene_id not in QA_EXPECTED_SCENE_KEYS or not isinstance(scenes, dict):
        raise GoldenRejected
    scene = scenes[scene_id]
    if not isinstance(scene, dict) or not isinstance(prepared, dict):
        raise GoldenRejected
    if set(prepared) != {"sceneId", "fingerprint"} \
        or prepared.get("sceneId") != scene_id \
        or prepared.get("fingerprint") != scene["fingerprint"]:
        raise GoldenRejected


def validate_evidence_scalar(value: object) -> None:
    if value is None or isinstance(value, bool):
        return
    if isinstance(value, int) and 0 <= value <= 1_000_000:
        return
    if isinstance(value, str) \
        and re.fullmatch(r"sha256:[0-9a-f]{64}", value) is not None:
        return
    raise GoldenRejected


def validate_scene_result(
    root: dict[str, object], scene_id: str, evidence: object
) -> None:
    scenes = root["scenes"]
    if scene_id not in QA_EXPECTED_SCENE_KEYS or not isinstance(scenes, dict):
        raise GoldenRejected
    scene = scenes[scene_id]
    if not isinstance(scene, dict) or not isinstance(evidence, dict):
        raise GoldenRejected
    independent_profile_id = scene.get("independentProfileId")
    independent_profiles = {
        **root["firestoreProfiles"],
        **root["sqliteProfiles"],
    }
    if independent_profile_id \
        != QA_EXPECTED_SCENE_INDEPENDENT_PROFILE_IDS[scene_id] \
        or independent_profile_id not in independent_profiles:
        raise GoldenRejected
    if set(evidence) != {"schema", "checkId", "verdict", "facts"} \
        or evidence.get("schema") != "qa.evidence/v1" \
        or evidence.get("checkId") != scene["inspectCheckId"] \
        or evidence.get("verdict") != "pass":
        raise GoldenRejected
    facts = evidence.get("facts")
    required_fact_keys = scene["requiredFactKeys"]
    if not isinstance(facts, list) or not isinstance(required_fact_keys, list) \
        or len(facts) != len(required_fact_keys):
        raise GoldenRejected

    expected_counts = scene["expectedCounts"]
    if not isinstance(expected_counts, dict):
        raise GoldenRejected
    count_facts = {
        "accounts.live-count": expected_counts["accounts"],
        "categories.live-count": expected_counts["categories"],
        "transactions.live-count": expected_counts["transactions"],
        "transfers.live-count": expected_counts["transfers"],
        "currency-rates.live-count": expected_counts["currencyRates"],
        "schedules.live-count": expected_counts["schedules"],
        "accounts.tombstone-count": 0,
        "categories.tombstone-count": 0,
        "transactions.tombstone-count": 0,
        "transfers.tombstone-count": 0,
        "currency-rates.tombstone-count": 0,
        "schedules.tombstone-count": 0,
        "currency-configs.count": expected_counts["currencyConfigs"],
    }
    digest_facts = {
        "settings.base-currency": evidence_digest("[901]"),
    }
    for expected_key, fact in zip(required_fact_keys, facts):
        if not isinstance(fact, dict) \
            or set(fact) != {"key", "actual", "expected", "pass"} \
            or fact.get("key") != expected_key \
            or fact.get("pass") is not True:
            raise GoldenRejected
        actual = fact.get("actual")
        expected = fact.get("expected")
        validate_evidence_scalar(actual)
        validate_evidence_scalar(expected)
        if type(actual) is not type(expected) or actual != expected:
            raise GoldenRejected
        if expected_key in count_facts and actual != count_facts[expected_key]:
            raise GoldenRejected
        if expected_key in digest_facts and actual != digest_facts[expected_key]:
            raise GoldenRejected
        if expected_key.endswith(".signature"):
            signature_ids = scene["signatureIds"]
            if not isinstance(actual, str) \
                or not isinstance(signature_ids, dict) \
                or signature_ids.get(expected_key) \
                    != QA_EXPECTED_SCENE_SIGNATURE_IDS[scene_id].get(expected_key):
                raise GoldenRejected
        elif expected_key not in count_facts \
            and expected_key not in digest_facts \
            and actual is not True:
            raise GoldenRejected


def validate_r13_candidate_result(
    root: dict[str, object], profile_name: str, evidence: object
) -> int:
    profiles = root["sqliteProfiles"]
    if profile_name != "r13_schedule_backfill" \
        or not isinstance(profiles, dict) \
        or not isinstance(evidence, dict):
        raise GoldenRejected
    profile = profiles[profile_name]
    if not isinstance(profile, dict) \
        or set(evidence) != {"schema", "checkId", "verdict", "facts"} \
        or evidence.get("schema") != "qa.evidence/v1" \
        or evidence.get("checkId") != profile["inspectCheckId"] \
        or evidence.get("verdict") != "pass":
        raise GoldenRejected
    facts = evidence.get("facts")
    required_fact_keys = profile["requiredFactKeys"]
    if not isinstance(facts, list) or not isinstance(required_fact_keys, list) \
        or len(facts) != len(required_fact_keys):
        raise GoldenRejected
    fixed_values = {
        "schedule-backfill.anchor-valid": True,
        "schedule-backfill.schedule-count": 1,
        "schedule-backfill.schedule-contract": True,
        "schedule-backfill.expected-sequence-valid": True,
        "schedule-backfill.tombstone-count": 0,
        "schedule-backfill.template-match": True,
    }
    digest_keys = {
        "schedule-backfill.expected-start",
        "schedule-backfill.sequence",
        "schedule-backfill.unique",
    }
    for expected_key, fact in zip(required_fact_keys, facts):
        if not isinstance(fact, dict) \
            or set(fact) != {"key", "actual", "expected", "pass"} \
            or fact.get("key") != expected_key \
            or fact.get("pass") is not True:
            raise GoldenRejected
        actual = fact.get("actual")
        expected = fact.get("expected")
        validate_evidence_scalar(actual)
        validate_evidence_scalar(expected)
        if type(actual) is not type(expected) or actual != expected:
            raise GoldenRejected
        if expected_key in fixed_values and actual != fixed_values[expected_key]:
            raise GoldenRejected
        if expected_key in digest_keys and not isinstance(actual, str):
            raise GoldenRejected
        if expected_key == "schedule-backfill.generated-count" \
            and (isinstance(actual, bool) or not isinstance(actual, int)):
            raise GoldenRejected
    generated_fact = facts[-1]
    if not isinstance(generated_fact, dict):
        raise GoldenRejected
    generated_count = generated_fact.get("actual")
    if isinstance(generated_count, bool) \
        or not isinstance(generated_count, int) \
        or not 0 <= generated_count <= 1_000_000:
        raise GoldenRejected
    return generated_count


def validate_r13_sqlite_result(
    root: dict[str, object], profile_name: str, aggregate: str
) -> int:
    profiles = root["sqliteProfiles"]
    if profile_name != "r13_schedule_backfill" \
        or not isinstance(profiles, dict) \
        or profile_name not in profiles:
        raise GoldenRejected
    matched = QA_R13_SQLITE_AGGREGATE_PATTERN.fullmatch(aggregate)
    if matched is None:
        raise GoldenRejected
    values = {
        key: parse_integer(value)
        for key, value in matched.groupdict().items()
        if key.endswith("count")
    }
    schedule_count = values["schedule_count"]
    live_count = values["live_count"]
    generated_count = values["generated_count"]
    distinct_count = values["distinct_count"]
    tombstone_count = values["tombstone_count"]
    if schedule_count != 1 \
        or live_count < 1 \
        or generated_count != live_count - 1 \
        or distinct_count != live_count \
        or tombstone_count != 0 \
        or matched.group("schedule_contract") != "true" \
        or matched.group("due_sequence_valid") != "true" \
        or matched.group("template_match") != "true":
        raise GoldenRejected
    return generated_count


def validate_selected_firestore_profile(
    root: dict[str, object], selected_profile: str
) -> None:
    profiles = root["firestoreProfiles"]
    if not isinstance(profiles, dict) or selected_profile not in profiles:
        raise GoldenRejected


def validate_selected_sqlite_profile(
    root: dict[str, object], selected_profile: str
) -> None:
    profiles = root["sqliteProfiles"]
    if not isinstance(profiles, dict) or selected_profile not in profiles:
        raise GoldenRejected


def main(argv: list[str]) -> int:
    try:
        if len(argv) != 5 or argv[1] != "--golden":
            raise GoldenRejected
        operation = argv[3]
        selected_value = argv[4]
        if operation not in {
            "--firestore-profile",
            "--sqlite-profile",
            "--scene-prepare",
            "--scene-result",
            "--r13-candidate-result",
            "--r13-sqlite-result",
        }:
            raise GoldenRejected
        root = validate_golden(read_locked_json(argv[2]))
        if operation == "--firestore-profile":
            if selected_value not in QA_EXPECTED_FIRESTORE_PROFILES:
                raise GoldenRejected
            validate_selected_firestore_profile(root, selected_value)
            success_verdict = "QA_QUALITY_FIRESTORE_PROFILE_MATCH"
        elif operation == "--sqlite-profile":
            if selected_value not in QA_EXPECTED_SQLITE_PROFILES:
                raise GoldenRejected
            validate_selected_sqlite_profile(root, selected_value)
            success_verdict = "QA_QUALITY_SQLITE_PROFILE_MATCH"
        elif operation == "--scene-prepare":
            validate_scene_prepare(root, selected_value, read_stdin_json())
            success_verdict = "QA_QUALITY_SCENE_PREPARE_MATCH"
        elif operation == "--scene-result":
            validate_scene_result(root, selected_value, read_stdin_json())
            success_verdict = "QA_QUALITY_SCENE_RESULT_MATCH"
        elif operation == "--r13-candidate-result":
            generated_count = validate_r13_candidate_result(
                root, selected_value, read_stdin_json()
            )
            success_verdict = f"QA_QUALITY_R13_CANDIDATE generated={generated_count}"
        else:
            generated_count = validate_r13_sqlite_result(
                root, selected_value, read_stdin_text()
            )
            success_verdict = f"QA_QUALITY_R13_SQLITE generated={generated_count}"
    except GoldenRejected:
        print("QA_QUALITY_GOLDEN_REJECTED", file=sys.stderr)
        return 1
    print(success_verdict)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
