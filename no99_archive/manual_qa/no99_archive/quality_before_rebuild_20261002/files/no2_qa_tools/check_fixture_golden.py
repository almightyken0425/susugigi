#!/usr/bin/env python3

import csv
import json
import re
import sys
from pathlib import Path


FIXTURE_FACT_KEYS = [
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

EXPECTED = {
    "schema": "susugigi.qa.fixture-golden/v1",
    "scenes": {
        "r02_end": {
            "fingerprint": "r02_end:a3:c7:t9:f0:s0:v1",
            "inspectCheckId": "accounting.fixture-summary",
            "requiredFactKeys": FIXTURE_FACT_KEYS,
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
            "signatureIds": {
                "accounts.signature": "accounting-accounts-v1",
                "categories.signature": "accounting-categories-v1",
                "transactions.signature": "r02-transactions-relative-date-v1",
                "transfers.signature": "empty-transfers-v1",
                "currency-rates.signature": "placeholder-jpy-twd-v1",
                "schedules.signature": "empty-schedules-v1",
            },
            "independentProfileId": "r03_initial_backup",
            "requiredRelations": [
                "remote-subtree-absent-before-prepare",
                "all-rows-belong-to-session-identity",
                "base-currency-is-901",
                "all-references-resolve",
                "schedule-instance-dates-are-unique",
                "rate-history-order-is-valid",
                "candidate-signatures-are-consistency-only",
                "final-verdict-requires-independent-profile",
            ],
        },
        "r09_stale_schedule": {
            "fingerprint": "r09_stale_schedule:a3:c7:t9:f2:s1:v1",
            "inspectCheckId": "accounting.fixture-summary",
            "requiredFactKeys": FIXTURE_FACT_KEYS,
            "expectedCounts": {
                "accounts": 3,
                "categories": 7,
                "transactions": 9,
                "transfers": 2,
                "currencyRates": 5,
                "schedules": 1,
                "tombstones": 0,
                "currencyConfigs": 0,
            },
            "signatureIds": {
                "accounts.signature": "accounting-accounts-v1",
                "categories.signature": "accounting-categories-v1",
                "transactions.signature": "r09-stale-schedule-transactions-relative-date-v1",
                "transfers.signature": "r03-transfers-final-relative-date-v1",
                "currency-rates.signature": "placeholder-plus-4.4-4.5-bidirectional-v1",
                "schedules.signature": "daily-breakfast-stale-schedule-v1",
            },
            "independentProfileId": "r13_schedule_backfill",
            "requiredRelations": [
                "remote-subtree-absent-before-prepare",
                "all-rows-belong-to-session-identity",
                "base-currency-is-901",
                "all-references-resolve",
                "schedule-instance-dates-are-unique",
                "rate-4.5-is-newer-than-4.4",
                "stale-schedule-has-only-start-instance",
                "candidate-signatures-are-consistency-only",
                "final-verdict-requires-independent-profile",
            ],
        },
    },
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
                "startMonthOffset": -1,
                "startDay": 5,
                "endOn": None,
                "isTransfer": False,
                "templateNote": "早餐",
                "templateCategoryName": "餐飲",
                "templateAccountName": "錢包",
                "templateAmount": 150,
                "tombstoneCount": 0,
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


def load_text(path, encoding="utf-8"):
    try:
        return path.read_text(encoding=encoding)
    except (OSError, UnicodeError):
        return ""


def compare_exact(actual, expected, path, errors):
    if isinstance(expected, dict):
        if not isinstance(actual, dict) or set(actual) != set(expected):
            errors.add(f"Quality golden {path} exact keys 不符")
            return
        for key in expected:
            compare_exact(actual[key], expected[key], f"{path}.{key}", errors)
        return
    if isinstance(expected, list):
        if actual != expected:
            errors.add(f"Quality golden {path} literal 不符")
        return
    if actual != expected:
        if path.endswith(".fingerprint"):
            errors.add("Quality golden 與固定 scene fingerprint 不一致")
        else:
            errors.add(f"Quality golden {path} literal 不符")


def walk_strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, list):
        for item in value:
            yield from walk_strings(item)
    elif isinstance(value, dict):
        for key, item in value.items():
            yield key
            yield from walk_strings(item)


def read_firestore_rows(path):
    rows = []
    try:
        with path.open(encoding="utf-8-sig", newline="") as handle:
            for row in csv.DictReader(handle):
                if row.get("手段") == "firestore-read":
                    rows.append(row.get("序", ""))
    except (OSError, UnicodeError, csv.Error):
        pass
    return rows


def read_csv_rows(path):
    try:
        with path.open(encoding="utf-8-sig", newline="") as handle:
            return list(csv.DictReader(handle))
    except (OSError, UnicodeError, csv.Error):
        return []


def main(argv):
    if len(argv) != 12:
        print("Quality golden checker 呼叫參數不完整")
        return 0

    (
        golden_path,
        fixtures_path,
        r01_csv_path,
        r03_runbook_path,
        r03_csv_path,
        r08_csv_path,
        r13_runbook_path,
        r13_csv_path,
        app_harness_path,
        regression_fixture_path,
        db_probe_path,
    ) = map(Path, argv[1:])
    errors = set()

    if not golden_path.is_file():
        print("Quality golden 不存在")
        return 0
    try:
        golden = json.loads(golden_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        print("Quality golden 不是合法 UTF-8 JSON")
        return 0

    compare_exact(golden, EXPECTED, "root", errors)

    for value in walk_strings(golden):
        if re.search(r"(?:^|[ :=])/(?:Users|home|private|tmp)/", value):
            errors.add("Quality golden 不得含 OS 絕對路徑")
        if re.search(r"[A-Za-z]:\\\\", value):
            errors.add("Quality golden 不得含 OS 絕對路徑")
        if re.search(
            r"(?:bootstrap|dispose|inspect|open-app|prepare)-[0-9a-f]{32}",
            value,
        ):
            errors.add("Quality golden 不得含隨機 requestId")
        if "QA_SESSION_UID" in value:
            errors.add("Quality golden 不得含 session raw UID 變數")
        if re.search(r"\b(?:SELECT|INSERT|UPDATE|DELETE)\b", value):
            errors.add("Quality golden 不得承載 SQL")

    fixture_text = load_text(fixtures_path)
    fixture_snippets = [
        "`r02_end` 建置 R02 終點",
        "主要貨幣為 TWD 901",
        "`r09_stale_schedule` 建置過期排程",
        "排程頻率為 DAILY",
        "排程起始日為上月 5 日",
        "排程備註為早餐",
        "排程類別為餐飲",
        "排程帳戶為錢包",
        "排程金額為 150",
        "seed 當下只有起始實例",
        "正向與反向匯率成對",
        "4.5 的 updatedOn 較晚",
        "schedule-backfill 驗 generated count",
        "`signatureIds` 以 exact fact key 對應固定 rule id，只作 candidate consistency evidence",
        "R03 incremental golden 固定驗 2000→2000 與 1000→4500 兩組 live transfers",
        "R03 incremental golden 固定驗十筆 live transactions、兩筆 live transfers 與兩路零額外 live row",
    ]
    if any(snippet not in fixture_text for snippet in fixture_snippets):
        errors.add("Quality golden 與 fixture 權威不一致")

    for path in (
        r03_runbook_path,
        r03_csv_path,
        r13_runbook_path,
        r13_csv_path,
    ):
        if "no1_fixture_golden.json" not in load_text(path, "utf-8-sig"):
            errors.add("R03/R13 未逐檔引用 Quality golden")
            break

    safe_mapping = {
        r01_csv_path: {"11": "r01_anonymous_user", "15": "r01_user_unchanged"},
        r03_csv_path: {"9": "r03_initial_backup", "21": "r03_incremental_backup", "24": "r03_updated_backup", "27": "r03_deleted_backup"},
        r08_csv_path: {
            "15": "r08_preferences_baseline",
            "21": "r08_preferences",
        },
    }
    seen = {}
    for csv_path, mapping in safe_mapping.items():
        for sequence in read_firestore_rows(csv_path):
            profile_id = mapping.get(sequence)
            if profile_id is None:
                errors.add("安全 firestore-read checkpoint 缺唯一 golden profile")
                continue
            seen[profile_id] = seen.get(profile_id, 0) + 1
    if any(seen.get(profile_id) != 1 for profile_id in EXPECTED["firestoreProfiles"]):
        errors.add("安全 firestore-read checkpoint 與 golden profile 非一對一")

    r08_profile_rows = [
        row
        for row in read_csv_rows(r08_csv_path)
        if row.get("序") == "8"
        and row.get("手段") == "sqlite-local"
        and "profile r08_original_language" in row.get("動作", "")
    ]
    if len(r08_profile_rows) != 1:
        errors.add("R08 original language checkpoint 缺唯一 SQLite golden profile")
    elif not all(
        snippet in r08_profile_rows[0].get("動作", "")
        for snippet in (
            "--session-uid-stdin",
            "command substitution",
            "不另寫檔",
        )
    ):
        errors.add("R08 original language profile 未鎖 stdin 與 private memory capture")

    firestore_profiles = golden.get("firestoreProfiles", {})
    sqlite_profiles = golden.get("sqliteProfiles", {})
    if isinstance(firestore_profiles, dict):
        for profile in firestore_profiles.values():
            if isinstance(profile, dict) and str(profile.get("checkpointKey", "")).startswith(
                ("R10:", "R11:", "R12:")
            ):
                errors.add("永久 blocked 場次不得有 executable Firestore profile")

    independent_profiles = set()
    if isinstance(firestore_profiles, dict):
        independent_profiles.update(firestore_profiles)
    if isinstance(sqlite_profiles, dict):
        independent_profiles.update(sqlite_profiles)
    scenes = golden.get("scenes", {})
    if isinstance(scenes, dict):
        for scene in scenes.values():
            if not isinstance(scene, dict):
                continue
            fact_keys = scene.get("requiredFactKeys", [])
            signature_ids = scene.get("signatureIds", {})
            expected_signature_keys = {
                value
                for value in fact_keys
                if isinstance(value, str) and value.endswith(".signature")
            }
            if not isinstance(signature_ids, dict) or set(signature_ids) != expected_signature_keys:
                errors.add("scene signatureIds 未以 exact fact key 鎖定 evaluator rule")
            if scene.get("independentProfileId") not in independent_profiles:
                errors.add("candidate signature 缺 final 獨立 Firestore 或 SQLite profile")

    app_harness_text = load_text(app_harness_path)
    if app_harness_text:
        for scene in EXPECTED["scenes"].values():
            if scene["fingerprint"] not in app_harness_text:
                errors.add("Impl scene fingerprint 與 Quality golden 不一致")
                break

    regression_fixture_text = load_text(regression_fixture_path)
    fixture_semantic_snippets = (
        "note: '早餐'",
        "category: '餐飲'",
        "account: '錢包'",
        "amount: 150",
        "frequency: 'DAILY'",
        "interval: 1",
        "startMonthOffset: -1",
        "startDay: 5",
    )
    if any(
        snippet not in regression_fixture_text
        for snippet in fixture_semantic_snippets
    ):
        errors.add("Impl R13 fixture semantics 與 Quality golden 不一致")

    db_probe_text = load_text(db_probe_path)
    db_probe_semantic_snippets = (
        "name = '錢包'",
        "name = '餐飲'",
        "type = 'expense'",
        "target_schedule.template_amount = -1500000",
        "target_schedule.template_note = '早餐'",
        "date('now', 'localtime', 'start of month', '-1 month', '+4 days')",
        "OR amount != -1500000",
        "OR note IS NOT '早餐'",
    )
    if any(snippet not in db_probe_text for snippet in db_probe_semantic_snippets):
        errors.add("R13 SQLite profile 未鎖 Quality fixture semantics")

    print("\n".join(sorted(errors)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
