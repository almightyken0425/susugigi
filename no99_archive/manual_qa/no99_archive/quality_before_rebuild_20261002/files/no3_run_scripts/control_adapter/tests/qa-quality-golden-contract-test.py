#!/usr/bin/env python3

import copy
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile


CONTROL_ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = CONTROL_ROOT / "programs/qa-quality-golden.py"


def fixture() -> dict[str, object]:
    scene_fact_keys = [
        "scope.user",
        "settings.base-currency",
        "accounts.live-count",
        "accounts.tombstone-count",
        "accounts.signature",
        "categories.live-count",
        "categories.tombstone-count",
        "categories.signature",
        "transactions.live-count",
        "transactions.tombstone-count",
        "transactions.signature",
        "transfers.live-count",
        "transfers.tombstone-count",
        "transfers.signature",
        "currency-rates.live-count",
        "currency-rates.tombstone-count",
        "currency-rates.signature",
        "currency-rates.history-order",
        "schedules.live-count",
        "schedules.tombstone-count",
        "schedules.signature",
        "schedule-instances.valid",
        "references.valid",
        "currency-configs.count",
    ]
    signature_ids = {
        "accounts.signature": "accounting-accounts-v1",
        "categories.signature": "accounting-categories-v1",
        "transactions.signature": "r02-transactions-relative-date-v1",
        "transfers.signature": "empty-transfers-v1",
        "currency-rates.signature": "placeholder-jpy-twd-v1",
        "schedules.signature": "empty-schedules-v1",
    }
    relations = [
        "remote-subtree-absent-before-prepare",
        "all-rows-belong-to-session-identity",
        "base-currency-is-901",
        "all-references-resolve",
        "schedule-instance-dates-are-unique",
        "rate-history-order-is-valid",
        "candidate-signatures-are-consistency-only",
        "final-verdict-requires-independent-profile",
    ]
    r02_scene = {
        "fingerprint": "r02_end:a3:c7:t9:f0:s0:v1",
        "inspectCheckId": "accounting.fixture-summary",
        "requiredFactKeys": scene_fact_keys,
        "expectedCounts": {
            "accounts": 3,
            "categories": 7,
            "transactions": 9,
            "transfers": 0,
            "currencyRates": 1,
            "schedules": 0,
            "tombstones": 0,
            "currencyConfigs": 0,
        },
        "signatureIds": signature_ids,
        "independentProfileId": "r03_initial_backup",
        "requiredRelations": relations,
    }
    r09_scene = copy.deepcopy(r02_scene)
    r09_scene["fingerprint"] = "r09_stale_schedule:a3:c7:t9:f2:s1:v1"
    r09_scene["expectedCounts"].update(
        {"transfers": 2, "currencyRates": 5, "schedules": 1}
    )
    r09_scene["signatureIds"].update(
        {
            "transactions.signature": "r09-stale-schedule-transactions-relative-date-v1",
            "transfers.signature": "r03-transfers-final-relative-date-v1",
            "currency-rates.signature": "placeholder-plus-4.4-4.5-bidirectional-v1",
            "schedules.signature": "daily-breakfast-stale-schedule-v1",
        }
    )
    r09_scene["independentProfileId"] = "r13_schedule_backfill"
    r09_scene["requiredRelations"] = [
        "remote-subtree-absent-before-prepare",
        "all-rows-belong-to-session-identity",
        "base-currency-is-901",
        "all-references-resolve",
        "schedule-instance-dates-are-unique",
        "rate-4.5-is-newer-than-4.4",
        "stale-schedule-has-only-start-instance",
        "candidate-signatures-are-consistency-only",
        "final-verdict-requires-independent-profile",
    ]
    return {
        "schema": "susugigi.qa.fixture-golden/v1",
        "scenes": {"r02_end": r02_scene, "r09_stale_schedule": r09_scene},
        "firestoreProfiles": {
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
        },
        "sqliteProfiles": {
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
        },
    }


def invoke_command(
    golden: dict[str, object],
    arguments: list[str],
    input_text: str = "",
) -> subprocess.CompletedProcess[str]:
    with tempfile.TemporaryDirectory(prefix="qa-quality-golden-test-") as root:
        golden_path = pathlib.Path(root) / "golden.json"
        golden_path.write_text(json.dumps(golden, ensure_ascii=False), encoding="utf-8")
        os.chmod(golden_path, 0o600)
        return subprocess.run(
            [
                sys.executable,
                str(HELPER),
                "--golden",
                str(golden_path),
                *arguments,
            ],
            check=False,
            capture_output=True,
            text=True,
            input=input_text,
        )


def invoke(golden: dict[str, object], profile: str) -> subprocess.CompletedProcess[str]:
    return invoke_command(golden, ["--firestore-profile", profile])


valid = fixture()
for profile_name in valid["firestoreProfiles"]:
    result = invoke(valid, profile_name)
    assert result.returncode == 0, result.stderr
    assert result.stdout == "QA_QUALITY_FIRESTORE_PROFILE_MATCH\n"
    assert result.stderr == ""

for profile_name in valid["sqliteProfiles"]:
    result = invoke_command(valid, ["--sqlite-profile", profile_name])
    assert result.returncode == 0, result.stderr
    assert result.stdout == "QA_QUALITY_SQLITE_PROFILE_MATCH\n"
    assert result.stderr == ""

r13_expected_values = valid["sqliteProfiles"]["r13_schedule_backfill"][
    "expectedValues"
]
for field_name in (
    "startMonthOffset",
    "startDay",
    "templateNote",
    "templateCategoryName",
    "templateAccountName",
    "templateAmount",
):
    drifted = copy.deepcopy(valid)
    value = r13_expected_values[field_name]
    drifted_value = value + 1 if isinstance(value, int) else value + "-drift"
    drifted["sqliteProfiles"]["r13_schedule_backfill"]["expectedValues"][
        field_name
    ] = drifted_value
    result = invoke_command(
        drifted,
        ["--sqlite-profile", "r13_schedule_backfill"],
    )
    assert result.returncode == 1
    assert result.stdout == ""
    assert result.stderr == "QA_QUALITY_GOLDEN_REJECTED\n"

scene = valid["scenes"]["r02_end"]
scene_counts = scene["expectedCounts"]
count_fact_values = {
    "accounts.live-count": scene_counts["accounts"],
    "categories.live-count": scene_counts["categories"],
    "transactions.live-count": scene_counts["transactions"],
    "transfers.live-count": scene_counts["transfers"],
    "currency-rates.live-count": scene_counts["currencyRates"],
    "schedules.live-count": scene_counts["schedules"],
    "accounts.tombstone-count": 0,
    "categories.tombstone-count": 0,
    "transactions.tombstone-count": 0,
    "transfers.tombstone-count": 0,
    "currency-rates.tombstone-count": 0,
    "schedules.tombstone-count": 0,
    "currency-configs.count": scene_counts["currencyConfigs"],
}


def digest(value: str) -> str:
    return "sha256:" + hashlib.sha256(value.encode("utf-8")).hexdigest()


facts = []
for fact_key in scene["requiredFactKeys"]:
    if fact_key in count_fact_values:
        fact_value = count_fact_values[fact_key]
    elif fact_key == "settings.base-currency":
        fact_value = digest("[901]")
    elif fact_key.endswith(".signature"):
        fact_value = digest(f"safe-{fact_key}")
    else:
        fact_value = True
    facts.append(
        {"key": fact_key, "actual": fact_value, "expected": fact_value, "pass": True}
    )

evidence = {
    "schema": "qa.evidence/v1",
    "checkId": "accounting.fixture-summary",
    "verdict": "pass",
    "facts": facts,
}
result = invoke_command(
    valid,
    ["--scene-result", "r02_end"],
    json.dumps(evidence, ensure_ascii=False),
)
assert result.returncode == 0, result.stderr
assert result.stdout == "QA_QUALITY_SCENE_RESULT_MATCH\n"
assert result.stderr == ""

prepared = {"sceneId": "r02_end", "fingerprint": scene["fingerprint"]}
result = invoke_command(
    valid,
    ["--scene-prepare", "r02_end"],
    json.dumps(prepared, ensure_ascii=False),
)
assert result.returncode == 0, result.stderr
assert result.stdout == "QA_QUALITY_SCENE_PREPARE_MATCH\n"
assert result.stderr == ""

wrong_count_evidence = copy.deepcopy(evidence)
wrong_count_evidence["facts"][2]["actual"] = 999
missing_fact_evidence = copy.deepcopy(evidence)
missing_fact_evidence["facts"].pop()
false_fact_evidence = copy.deepcopy(evidence)
false_fact_evidence["facts"][0]["pass"] = False
for rejected_evidence in (
    wrong_count_evidence,
    missing_fact_evidence,
    false_fact_evidence,
):
    result = invoke_command(
        valid,
        ["--scene-result", "r02_end"],
        json.dumps(rejected_evidence, ensure_ascii=False),
    )
    assert result.returncode != 0
    assert result.stdout == ""
    assert result.stderr == "QA_QUALITY_GOLDEN_REJECTED\n"

wrong_prepared = dict(prepared)
wrong_prepared["fingerprint"] = "r02_end:forged"
result = invoke_command(
    valid,
    ["--scene-prepare", "r02_end"],
    json.dumps(wrong_prepared),
)
assert result.returncode != 0
assert result.stdout == ""
assert result.stderr == "QA_QUALITY_GOLDEN_REJECTED\n"

sqlite_profile = valid["sqliteProfiles"]["r13_schedule_backfill"]
sqlite_values = {
    "schedule-backfill.anchor-valid": True,
    "schedule-backfill.schedule-count": 1,
    "schedule-backfill.schedule-contract": True,
    "schedule-backfill.expected-start": digest("1700000000000"),
    "schedule-backfill.expected-sequence-valid": True,
    "schedule-backfill.sequence": digest("[1700000000000]"),
    "schedule-backfill.unique": digest("1"),
    "schedule-backfill.tombstone-count": 0,
    "schedule-backfill.template-match": True,
    "schedule-backfill.generated-count": 0,
}
sqlite_evidence = {
    "schema": "qa.evidence/v1",
    "checkId": "accounting.schedule-backfill",
    "verdict": "pass",
    "facts": [
        {
            "key": fact_key,
            "actual": sqlite_values[fact_key],
            "expected": sqlite_values[fact_key],
            "pass": True,
        }
        for fact_key in sqlite_profile["requiredFactKeys"]
    ],
}
result = invoke_command(
    valid,
    ["--r13-candidate-result", "r13_schedule_backfill"],
    json.dumps(sqlite_evidence),
)
assert result.returncode == 0, result.stderr
assert result.stdout == "QA_QUALITY_R13_CANDIDATE generated=0\n"
assert result.stderr == ""
wrong_sqlite_evidence = copy.deepcopy(sqlite_evidence)
wrong_sqlite_evidence["facts"][1]["actual"] = 2
result = invoke_command(
    valid,
    ["--r13-candidate-result", "r13_schedule_backfill"],
    json.dumps(wrong_sqlite_evidence),
)
assert result.returncode != 0
assert result.stdout == ""
assert result.stderr == "QA_QUALITY_GOLDEN_REJECTED\n"

sqlite_aggregate = (
    "profile=r13_schedule_backfill scheduleCount=1 liveInstanceCount=3 "
    "generatedCount=2 distinctInstanceDateCount=3 tombstoneCount=0 "
    "scheduleContract=true dueSequenceValid=true templateMatch=true"
)
result = invoke_command(
    valid,
    ["--r13-sqlite-result", "r13_schedule_backfill"],
    sqlite_aggregate,
)
assert result.returncode == 0, result.stderr
assert result.stdout == "QA_QUALITY_R13_SQLITE generated=2\n"
assert result.stderr == ""
for rejected_aggregate in (
    sqlite_aggregate.replace("distinctInstanceDateCount=3", "distinctInstanceDateCount=2"),
    sqlite_aggregate.replace("tombstoneCount=0", "tombstoneCount=1"),
    sqlite_aggregate.replace("templateMatch=true", "templateMatch=false"),
    sqlite_aggregate + " rawUid=qa-session-user",
):
    result = invoke_command(
        valid,
        ["--r13-sqlite-result", "r13_schedule_backfill"],
        rejected_aggregate,
    )
    assert result.returncode != 0
    assert result.stdout == ""
    assert result.stderr == "QA_QUALITY_GOLDEN_REJECTED\n"

mutations = []
wrong_checkpoint = copy.deepcopy(valid)
wrong_checkpoint["firestoreProfiles"]["r03_initial_backup"]["checkpointKey"] = "R03:999"
mutations.append(wrong_checkpoint)
extra_profile_field = copy.deepcopy(valid)
extra_profile_field["firestoreProfiles"]["r08_preferences"]["rawUid"] = "secret-user"
mutations.append(extra_profile_field)
missing_profile = copy.deepcopy(valid)
del missing_profile["firestoreProfiles"]["r01_user_unchanged"]
mutations.append(missing_profile)
forged_signature_rule = copy.deepcopy(valid)
forged_signature_rule["scenes"]["r02_end"]["signatureIds"][
    "accounts.signature"
] = "candidate-self-reported-v1"
mutations.append(forged_signature_rule)
wrong_independent_profile = copy.deepcopy(valid)
wrong_independent_profile["scenes"]["r02_end"][
    "independentProfileId"
] = "r13_schedule_backfill"
mutations.append(wrong_independent_profile)
missing_independent_profile = copy.deepcopy(valid)
del missing_independent_profile["scenes"]["r09_stale_schedule"][
    "independentProfileId"
]
mutations.append(missing_independent_profile)
extra_top_level = copy.deepcopy(valid)
extra_top_level["command"] = "__import__('os').system('false')"
mutations.append(extra_top_level)
wrong_schema = copy.deepcopy(valid)
wrong_schema["schema"] = "susugigi.qa.fixture-golden/v2"
mutations.append(wrong_schema)

for mutation in mutations:
    result = invoke(mutation, "r03_initial_backup")
    assert result.returncode != 0
    assert result.stdout == ""
    assert result.stderr == "QA_QUALITY_GOLDEN_REJECTED\n"
    assert "secret-user" not in result.stderr
    assert "__import__" not in result.stderr

with tempfile.TemporaryDirectory(prefix="qa-quality-golden-symlink-test-") as root:
    root_path = pathlib.Path(root)
    real_path = root_path / "real.json"
    link_path = root_path / "golden.json"
    real_path.write_text(json.dumps(valid), encoding="utf-8")
    link_path.symlink_to(real_path)
    result = subprocess.run(
        [
            sys.executable,
            str(HELPER),
            "--golden",
            str(link_path),
            "--firestore-profile",
            "r03_initial_backup",
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0
    assert result.stdout == ""
    assert result.stderr == "QA_QUALITY_GOLDEN_REJECTED\n"

print("qa-quality golden contract tests passed")
