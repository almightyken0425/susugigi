#!/usr/bin/env python3
"""有界讀取一行公開 QA 指令，不預讀下一行，也不依賴 Bash 的 timeout 退出碼。"""
import os
import re
import select
import sys
import time


def main():
    deadline = time.monotonic() + 1
    command = bytearray()
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([0], [], [], max(remaining, 0))[0]:
            return 1 if command else 42
        character = os.read(0, 1)
        if not character:
            return 1
        if character == b"\n":
            break
        command.extend(character)
        if len(command) > 100:
            return 1
    try:
        text = command.decode("ascii")
    except UnicodeDecodeError:
        return 1
    if re.fullmatch(r"(?:open-app|cold-reopen|prepare|inspect|r13-final|status|continue|finish|abort|"
                    r"case R[0-9]{2} [A-Z]{2}-[0-9]{2}|probe R[0-9]{2}:[0-9]{1,2})", text) is None:
        return 1
    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
