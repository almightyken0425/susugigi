#!/usr/bin/env python3
"""Read-only audit view. Never use this output as an executable runner."""
from pathlib import Path
import re
import sys
import argparse
from qa_adapter import check, PROFILE, regular_path

ROOT = Path(__file__).resolve().parents[1]


def render(quality_root, role='test-ios'):
    binding = check(ROOT, PROFILE, quality_root)
    adapter_root = quality_root / binding['adapter_root']
    contract = (adapter_root / 'handoff_contract.md').read_text() + '\n' + (adapter_root / 'identity_contract.md').read_text()
    if role == 'test-run':
        return (ROOT / 'references/quality/test_execution.md').read_text() + '\n' + contract
    source = adapter_root / 'ios_runbook.md'
    def expand(match):
        relative = Path(match[1])
        if relative.parts[0] != 'ios_runtime':
            raise ValueError('invalid_section')
        path = regular_path(adapter_root, relative)
        return '```bash\n' + path.read_text().rstrip() + '\n```'
    return contract + '\n' + re.sub(r'\[執行區塊\]\(([^)]+)\)。\n在同一個已鎖定且持續存活的 runner shell 內載入。不可拆成獨立 shell。', expand, source.read_text())


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--role', choices=['test-ios', 'test-run'], default='test-ios')
    parser.add_argument('--quality-root', required=True, type=Path)
    args = parser.parse_args()
    sys.stdout.write(render(args.quality_root, args.role))
