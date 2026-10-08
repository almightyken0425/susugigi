#!/usr/bin/env python3

from __future__ import annotations

import pathlib
import re
import sys


IF_PATTERN = re.compile(r"^\s*#if\s+(.+?)\s*$")
ELSEIF_PATTERN = re.compile(r"^\s*#elseif\s+(.+?)\s*$")
ELSE_PATTERN = re.compile(r"^\s*#else\s*$")
ENDIF_PATTERN = re.compile(r"^\s*#endif\s*$")
GOOGLE_SIGN_IN_REFERENCE_PATTERN = re.compile(r"\b(?:GoogleSignIn|GIDSignIn)\b")


def qa_condition_possibilities(expression: str) -> tuple[bool, bool]:
    compact = re.sub(r"\s+", "", expression)
    if compact == "!QA":
        return False, True
    if compact == "QA":
        return True, False
    return True, True


def source_is_isolated(source: str) -> bool:
    stack: list[dict[str, bool]] = []
    qa_exposure_seen = False

    for line in source.splitlines():
        if match := IF_PATTERN.fullmatch(line):
            parent_active = stack[-1]["active"] if stack else True
            may_be_true, may_be_false = qa_condition_possibilities(match.group(1))
            active = parent_active and may_be_true
            stack.append(
                {
                    "active": active,
                    "remaining": parent_active and may_be_false,
                }
            )
            continue
        if match := ELSEIF_PATTERN.fullmatch(line):
            if not stack:
                return False
            frame = stack[-1]
            may_be_true, may_be_false = qa_condition_possibilities(match.group(1))
            frame["active"] = frame["remaining"] and may_be_true
            frame["remaining"] = frame["remaining"] and may_be_false
            continue
        if ELSE_PATTERN.fullmatch(line):
            if not stack:
                return False
            frame = stack[-1]
            frame["active"] = frame["remaining"]
            frame["remaining"] = False
            continue
        if ENDIF_PATTERN.fullmatch(line):
            if not stack:
                return False
            stack.pop()
            continue

        current_active = stack[-1]["active"] if stack else True
        if GOOGLE_SIGN_IN_REFERENCE_PATTERN.search(line):
            qa_exposure_seen = qa_exposure_seen or current_active

    return not stack and not qa_exposure_seen


def main() -> int:
    if len(sys.argv) != 2:
        return 2
    source_path = pathlib.Path(sys.argv[1])
    if source_path.is_symlink() or not source_path.is_file():
        return 1
    try:
        source = source_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        return 1
    return 0 if source_is_isolated(source) else 1


if __name__ == "__main__":
    raise SystemExit(main())
