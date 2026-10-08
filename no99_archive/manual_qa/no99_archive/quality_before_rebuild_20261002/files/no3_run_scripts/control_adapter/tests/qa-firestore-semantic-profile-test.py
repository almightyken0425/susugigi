#!/usr/bin/env python3

import importlib.util
import pathlib
import subprocess
import sys


CONTROL_ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "qa_firestore_read", CONTROL_ROOT / "programs/qa-firestore-read.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)
UID = "qa-session-user"


def typed(value):
    if value is None:
        return {"nullValue": None}
    if isinstance(value, bool):
        return {"booleanValue": value}
    if isinstance(value, int):
        return {"integerValue": str(value)}
    if isinstance(value, float):
        return {"doubleValue": value}
    if isinstance(value, str):
        return {"stringValue": value}
    if isinstance(value, dict):
        return {"mapValue": {"fields": {key: typed(child) for key, child in value.items()}}}
    raise TypeError(value)


def document(collection, document_id, **fields):
    return {
        "name": (
            "projects/susugigi-qa/databases/(default)/documents/"
            f"users/{UID}/{collection}/{document_id}"
        ),
        "fields": {key: typed(value) for key, value in fields.items()},
    }


accounts = [
    document("accounts", "a1", id="a1", userId=UID, name="錢包", currencyId=901, deletedOn=None),
    document("accounts", "a2", id="a2", userId=UID, name="銀行", currencyId=901, deletedOn=None),
    document("accounts", "a3", id="a3", userId=UID, name="日幣帳戶", currencyId=392, deletedOn=None),
]
category_rows = [
    ("餐飲", "expense"),
    ("交通", "expense"),
    ("娛樂", "expense"),
    ("購物", "expense"),
    ("醫療", "expense"),
    ("薪資", "income"),
    ("獎金", "income"),
]
categories = [
    document(
        "categories",
        f"c{index}",
        id=f"c{index}",
        userId=UID,
        name=name,
        type=category_type,
        deletedOn=None,
    )
    for index, (name, category_type) in enumerate(category_rows, 1)
]
transaction_rows = [
    ("早餐改過", -1_500_000),
    ("薪資入帳", 500_000_000),
    ("獎金入帳", 50_000_000),
    ("計程車", -3_500_000),
    ("電影", -3_000_000),
    ("網購", -15_000_000),
    ("診所", -5_000_000),
    ("露營裝備", -35_000_000),
    ("露營餐費", -8_000_000),
]
transactions = [
    document(
        "transactions",
        f"t{index}",
        id=f"t{index}",
        userId=UID,
        accountId="a1",
        categoryId="c1",
        note=note,
        amountCents=amount,
        deletedOn=None,
    )
    for index, (note, amount) in enumerate(transaction_rows, 1)
]
collections = {
    "accounts": {"documents": accounts},
    "categories": {"documents": categories},
    "transactions": {"documents": transactions},
    "transfers": {"documents": []},
    "currency_rates": {
        "documents": [
            document(
                "currency_rates",
                "cr1",
                id="cr1",
                userId=UID,
                currencyFromId=392,
                currencyToId=901,
                rate=1,
                deletedOn=None,
            )
        ]
    },
    "schedules": {"documents": []},
}


def collection_request(url, _token):
    for name, payload in collections.items():
        if f"/{name}?pageSize=1000" in url:
            return 200, payload
    raise AssertionError(url)


MODULE.request_json = collection_request
assert MODULE.run_semantic_profile("r03-initial-backup", UID, "token", "") \
    == "QA_FIRESTORE_R03_INITIAL_BACKUP_MATCH"

bad_transactions = list(transactions)
bad_transactions[0] = document(
    "transactions",
    "t1",
    id="t1",
    userId=UID,
    accountId="a1",
    categoryId="c1",
    note="早餐改過",
    amountCents=-1_230_000,
    deletedOn=None,
)
collections["transactions"] = {"documents": bad_transactions}
try:
    MODULE.run_semantic_profile("r03-initial-backup", UID, "token", "")
except MODULE.ProbeFailure:
    pass
else:
    raise AssertionError("wrong breakfast amount accepted")
collections["transactions"] = {"documents": transactions}

incremental_transactions = list(transactions) + [
    document(
        "transactions",
        "t10",
        id="t10",
        userId=UID,
        accountId="a1",
        categoryId="c1",
        note="增量備份",
        amountCents=-2_000_000,
        deletedOn=None,
    )
]
collections["transactions"] = {"documents": incremental_transactions}
collections["transfers"] = {
    "documents": [
        document(
            "transfers",
            "x1",
            id="x1",
            userId=UID,
            amountFromCents=20_000_000,
            amountToCents=20_000_000,
            impliedRateScaled=None,
            deletedOn=None,
        ),
        document(
            "transfers",
            "x2",
            id="x2",
            userId=UID,
            amountFromCents=10_000_000,
            amountToCents=45_000_000,
            impliedRateScaled=4.5,
            deletedOn=None,
        ),
    ]
}
assert MODULE.run_semantic_profile("r03-incremental-backup", UID, "token", "") \
    == "QA_FIRESTORE_R03_INCREMENTAL_BACKUP_MATCH"


def changed_transaction(amount=-2_750_000, note="增量備份已修改", deleted_on=None, user=UID):
    return document(
        "transactions", "t10", id="t10", userId=user, accountId="a1", categoryId="c1",
        note=note, amountCents=amount, deletedOn=deleted_on,
    )


def reject_profile(profile, rows):
    collections["transactions"] = {"documents": rows}
    try:
        MODULE.run_semantic_profile(profile, UID, "token", "")
    except MODULE.ProbeFailure:
        return
    raise AssertionError("invalid edit/delete evidence accepted")


collections["transactions"] = {"documents": transactions + [changed_transaction()]}
assert MODULE.run_semantic_profile("r03-updated-backup", UID, "token", "") \
    == "QA_FIRESTORE_R03_UPDATED_BACKUP_MATCH"
reject_profile("r03-updated-backup", incremental_transactions)
reject_profile("r03-updated-backup", transactions + [changed_transaction(amount=-2_000_000)])
reject_profile("r03-updated-backup", transactions + [changed_transaction(note="增量備份")])
reject_profile("r03-updated-backup", transactions + [changed_transaction(user="another-user")])
reject_profile("r03-updated-backup", transactions + [changed_transaction(), changed_transaction()])
reject_profile("r03-updated-backup", bad_transactions + [changed_transaction()])
deleted_transaction = changed_transaction(deleted_on=1790765000000)
collections["transactions"] = {"documents": transactions + [deleted_transaction]}
assert MODULE.run_semantic_profile("r03-deleted-backup", UID, "token", "") \
    == "QA_FIRESTORE_R03_DELETED_BACKUP_MATCH"
reject_profile("r03-deleted-backup", transactions)
reject_profile("r03-deleted-backup", transactions + [changed_transaction()])
reject_profile("r03-deleted-backup", transactions + [changed_transaction(deleted_on=True)])
reject_profile("r03-deleted-backup", transactions + [changed_transaction(deleted_on=0)])
reject_profile("r03-deleted-backup", transactions + [changed_transaction(deleted_on="yesterday")])
reject_profile("r03-deleted-backup", transactions + [changed_transaction(note="other", deleted_on=1790765000000)])
reject_profile("r03-deleted-backup", bad_transactions + [deleted_transaction])
reject_profile("r03-deleted-backup", transactions + [deleted_transaction, deleted_transaction])
collections["transactions"] = {"documents": incremental_transactions}

missing_deleted_on_transfer = document(
    "transfers",
    "x2",
    id="x2",
    userId=UID,
    amountFromCents=10_000_000,
    amountToCents=45_000_000,
    impliedRateScaled=4.5,
)
collections["transfers"] = {
    "documents": [collections["transfers"]["documents"][0], missing_deleted_on_transfer]
}
try:
    MODULE.run_semantic_profile("r03-incremental-backup", UID, "token", "")
except MODULE.ProbeFailure:
    pass
else:
    raise AssertionError("transfer without explicit deletedOn accepted")
collections["transfers"] = {
    "documents": [
        document(
            "transfers",
            "x1",
            id="x1",
            userId=UID,
            amountFromCents=20_000_000,
            amountToCents=20_000_000,
            impliedRateScaled=None,
            deletedOn=None,
        ),
        document(
            "transfers",
            "x2",
            id="x2",
            userId=UID,
            amountFromCents=10_000_000,
            amountToCents=45_000_000,
            impliedRateScaled=4.5,
            deletedOn=None,
        ),
    ]
}
collections["transactions"] = {"documents": transactions}
try:
    MODULE.run_semantic_profile("r03-incremental-backup", UID, "token", "")
except MODULE.ProbeFailure:
    pass
else:
    raise AssertionError("missing incremental transaction accepted")
collections["transactions"] = {
    "documents": incremental_transactions + [
        document(
            "transactions",
            "unexpected",
            id="unexpected",
            userId=UID,
            accountId="a1",
            categoryId="c1",
            note="unexpected live row",
            amountCents=-1,
            deletedOn=None,
        )
    ]
}
try:
    MODULE.run_semantic_profile("r03-incremental-backup", UID, "token", "")
except MODULE.ProbeFailure:
    pass
else:
    raise AssertionError("unexpected live incremental row accepted")

user_payload = {
    "name": "projects/susugigi-qa/databases/(default)/documents/users/qa-session-user",
    "fields": {
        "uid": typed(UID),
        "provider": typed("anonymous"),
        "email": typed(None),
        "createdAt": typed(1_699_000_000_000),
        "lastLoginAt": typed(1_699_500_000_000),
        "updatedAt": typed(1_700_000_000_000),
        "preferences": typed({"theme": "theme1", "language": "zh-Hant", "currency": "TWD"}),
    },
}
MODULE.request_json = lambda _url, _token: (200, user_payload)
r01_verdict = MODULE.run_semantic_profile("r01-user-anonymous", UID, "token", "")
assert r01_verdict.startswith("QA_FIRESTORE_R01_USER_MATCH sha256:")
r01_match = MODULE.QA_R01_BASELINE_PATTERN.fullmatch(r01_verdict)
assert r01_match is not None
r01_digest = r01_match.group("digest")
assert len(r01_digest) == 64
assert MODULE.run_semantic_profile(
    "r01-user-unchanged",
    UID,
    "token",
    r01_digest,
    minimum_updated_at=1_700_000_000_000,
    minimum_last_login_at=1_699_500_000_000,
) \
    == "QA_FIRESTORE_R01_USER_UNCHANGED"
metadata_advanced_payload = dict(user_payload)
metadata_advanced_payload["fields"] = dict(user_payload["fields"])
metadata_advanced_payload["fields"]["lastLoginAt"] = typed(1_699_500_000_001)
metadata_advanced_payload["fields"]["updatedAt"] = typed(1_700_000_000_001)
MODULE.request_json = lambda _url, _token: (200, metadata_advanced_payload)
assert MODULE.run_semantic_profile(
    "r01-user-unchanged",
    UID,
    "token",
    r01_digest,
    minimum_updated_at=1_700_000_000_000,
    minimum_last_login_at=1_699_500_000_000,
) == "QA_FIRESTORE_R01_USER_UNCHANGED"
metadata_rewound_payload = dict(user_payload)
metadata_rewound_payload["fields"] = dict(user_payload["fields"])
metadata_rewound_payload["fields"]["lastLoginAt"] = typed(1_699_499_999_999)
MODULE.request_json = lambda _url, _token: (200, metadata_rewound_payload)
try:
    MODULE.run_semantic_profile(
        "r01-user-unchanged",
        UID,
        "token",
        r01_digest,
        minimum_updated_at=1_700_000_000_000,
        minimum_last_login_at=1_699_500_000_000,
    )
except MODULE.ProbeFailure:
    pass
else:
    raise AssertionError("rewound R01 metadata accepted")
changed_user_payload = dict(user_payload)
changed_user_payload["fields"] = dict(user_payload["fields"])
changed_user_payload["fields"]["createdAt"] = typed(1_699_000_000_001)
MODULE.request_json = lambda _url, _token: (200, changed_user_payload)
try:
    MODULE.run_semantic_profile(
        "r01-user-unchanged",
        UID,
        "token",
        r01_digest,
        minimum_updated_at=1_700_000_000_000,
        minimum_last_login_at=1_699_500_000_000,
    )
except MODULE.ProbeFailure:
    pass
else:
    raise AssertionError("changed R01 user document accepted")

r08_payload = dict(user_payload)
r08_payload["fields"] = dict(user_payload["fields"])
r08_payload["fields"]["preferences"] = typed(
    {"theme": "theme3", "language": "zh-Hant", "currency": "USD"}
)
MODULE.request_json = lambda _url, _token: (200, r08_payload)
baseline_verdict = MODULE.run_semantic_profile(
    "r08-preferences-baseline", UID, "token", ""
)
assert baseline_verdict == "QA_FIRESTORE_R08_BASELINE updatedAt:1700000000000"
r08_payload["fields"]["updatedAt"] = typed(1_700_000_000_001)
assert MODULE.run_semantic_profile(
    "r08-preferences",
    UID,
    "token",
    "",
    expected_language="zh-Hant",
    minimum_updated_at=1_700_000_000_000,
) \
    == "QA_FIRESTORE_R08_PREFERENCES_MATCH"
r08_payload["fields"]["preferences"] = typed(
    {"theme": "theme2", "language": "zh-Hant", "currency": "USD"}
)
try:
    MODULE.run_semantic_profile(
        "r08-preferences",
        UID,
        "token",
        "",
        expected_language="zh-Hant",
        minimum_updated_at=1_700_000_000_000,
    )
except MODULE.ProbeFailure:
    pass
else:
    raise AssertionError("wrong R08 theme accepted")

missing_deleted_on = dict(accounts[0])
missing_deleted_on["fields"] = dict(accounts[0]["fields"])
del missing_deleted_on["fields"]["deletedOn"]
try:
    MODULE.require_live_session_documents(
        [MODULE.decoded_document(missing_deleted_on, f"users/{UID}/accounts/a1")], UID
    )
except MODULE.ProbeFailure:
    pass
else:
    raise AssertionError("document without deletedOn accepted as live")


def absent_request(url, _token):
    if "/documents/users/qa-session-user/" in url:
        return 200, {"documents": []}
    if url.endswith("/documents/users/qa-session-user"):
        return 404, None
    raise AssertionError(url)


MODULE.request_json = absent_request
assert MODULE.run_semantic_profile("fixture-subtree-absent", UID, "token", "") \
    == "QA_FIRESTORE_FIXTURE_SUBTREE_ABSENT"
MODULE.request_json = lambda _url, _token: (200, user_payload)
try:
    MODULE.run_semantic_profile("fixture-subtree-absent", UID, "token", "")
except MODULE.ProbeFailure:
    pass
else:
    raise AssertionError("remaining fixture user document accepted")

# Exercise the complete shell mapping and driver boundary too. A semantic
# profile can be correct while its new checkpoint is absent from the driver.
driver_test = r'''
source "$1"
QA_FIREBASE_PROJECT_ID=susugigi-qa
QA_SESSION_UID=qa-test-user
QA_CURRENT_SCENE_ID=R03
QA_CURRENT_CASE_ID=CS-03
QA_CURRENT_CHECKPOINT_KEY="$2"
FIRESTORE_READ_REQUIRED=1
SESSION_QUALITY_ROOT=/fixture/quality
require_runtime_marker_session_clean() { return 0; }
require_session_runtime_snapshots_current() { return 0; }
require_locked_quality_firestore_profile() { return 0; }
run_session_snapshot_command() {
  local uid=""
  IFS= read -r uid
  [ "$uid" = qa-test-user ] || return 1
  [ "$#" -eq 7 ] && [ "$4" = --project ] && [ "$5" = susugigi-qa ] \
    && [ "$6" = --profile ] && [ "$7" = "$EXPECTED_PROFILE" ] || return 1
  printf '%s\n' "$EXPECTED_VERDICT"
}
EXPECTED_PROFILE="$3"
EXPECTED_VERDICT="$4"
run_qa_firestore_read
'''
for row, suffix in (("21", "incremental"), ("24", "updated"), ("27", "deleted")):
    verdict = f"QA_FIRESTORE_R03_{suffix.upper()}_BACKUP_MATCH"
    result = subprocess.run(
        ["/bin/bash", "-c", driver_test, "test",
         str(CONTROL_ROOT / "ios_runtime/firestore_binding_1.sh"),
         f"R03:{row}", f"r03-{suffix}-backup", verdict],
        text=True, capture_output=True, timeout=5,
    )
    assert result.returncode == 0, (row, result.stderr)
    assert result.stdout.strip() == verdict, (row, result.stdout)

result = subprocess.run(
    ["/bin/bash", "-c", driver_test, "test",
     str(CONTROL_ROOT / "ios_runtime/firestore_binding_1.sh"),
     "R03:999", "r03-updated-backup", "QA_FIRESTORE_R03_UPDATED_BACKUP_MATCH"],
    text=True, capture_output=True, timeout=5,
)
assert result.returncode != 0
assert "QA_FIRESTORE_CHECKPOINT_MISMATCH" in result.stderr

print("qa-firestore semantic profile and driver tests passed")
