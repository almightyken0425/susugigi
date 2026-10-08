#!/usr/bin/env python3
"""從鎖定的公開 payload 解析選中 case，不接受任意命令或身分。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys


def resolve(data, scene, case):
    if (scene not in {"R01", "R02", "R03", "R04", "R05", "R06", "R07", "R08", "R13", "R14", "R15"}
            or not re.fullmatch(r"[A-Z]{2}-[0-9]{2}", case)
            or scene not in data["sceneIds"] or case not in data["caseIds"]):
        raise ValueError()
    rows = data["expectedEvidence"][scene]
    if not any(re.search(r"(?<![A-Z0-9-])" + re.escape(case) + r"(?![A-Z0-9-])",
                         row.get("測項", "") + " " + row.get("已驗", "")) for row in rows):
        raise ValueError()
    seed, inspect = "none", "none"
    seen = set()
    for operation in data["qaLaunchArguments"][case]:
        if not isinstance(operation, list) or len(operation) != 2 or operation[0] in seen:
            raise ValueError()
        seen.add(operation[0])
        if operation[0] == "--qa-prepare" and operation[1] in {
                "r02_end", "r09_stale_schedule", "r06_large_history", "r06_large_history_cleanup"}:
            seed = operation[1]
        elif operation[0] == "--qa-inspect" and operation[1] in {
                "accounting.fixture-summary", "accounting.large-history-overlay", "accounting.schedule-backfill"}:
            inspect = operation[1]
        elif operation == ["--qa-first-launch", "true"]:
            if scene != "R14" or case != "AU-02":
                raise ValueError()
        elif operation != ["--qa-open-app", "true"]:
            raise ValueError()
    if "--qa-open-app" in seen and len(seen) != 1:
        raise ValueError()
    if "--qa-first-launch" in seen and len(seen) != 1:
        raise ValueError()
    if scene == "R14" and seen != {"--qa-first-launch"}:
        raise ValueError()
    if not seen:
        raise ValueError()
    return seed, inspect


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--payload", required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--scene", required=True)
    parser.add_argument("--case", required=True)
    parser.add_argument("--checkpoint")
    args = parser.parse_args()
    try:
        fd = os.open(args.payload, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(fd, "rb") as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_size > 4 * 1048576:
                raise ValueError()
            raw = stream.read(4 * 1048576 + 1)
        if hashlib.sha256(raw).hexdigest() != args.sha256:
            raise ValueError()
        data = json.loads(raw)
        if (data["qaFirebaseProjectId"] != "susugigi-qa"
                or data["qaBundleId"] != "com.almightyken0425.susugigiapp.qa"
                or data["confirmedTestType"] != "feature"):
            raise ValueError()
        seed, inspect = resolve(data, args.scene, args.case)
        if args.checkpoint:
            matches = [entry for name in ("firestoreCheckpointMap", "sqliteCheckpointMap")
                       for entry in data[name] if entry["checkpoint"] == args.checkpoint
                       and entry["caseId"] == args.case and entry["sceneId"] == args.scene]
            if len(matches) != 1:
                raise ValueError()
        print(seed + "\t" + inspect)
        return 0
    except (OSError, ValueError, KeyError, TypeError):
        print("QA_SESSION_SELECTION_REJECTED", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
