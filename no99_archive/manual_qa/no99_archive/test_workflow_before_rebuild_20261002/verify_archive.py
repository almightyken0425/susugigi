import hashlib
import json
from pathlib import Path
import os
import stat

root = Path(__file__).resolve().parent
manifest = json.loads((root / 'manifest.json').read_text())
expected_paths = set()
for entry in manifest['entries']:
    path = root / entry['archive_path']
    expected_paths.add(entry['archive_path'])
    data = os.fsencode(os.readlink(path)) if entry['kind'] == 'symlink' else path.read_bytes()
    assert path.is_symlink() == (entry['kind'] == 'symlink'), entry['source_path']
    assert hashlib.sha256(data).hexdigest() == entry['sha256'], entry['source_path']
    assert len(data) == entry['bytes'], entry['source_path']
    assert stat.S_IMODE(path.lstat().st_mode) == entry['mode'], entry['source_path']
actual_paths = {str(p.relative_to(root)) for p in (root / 'files').rglob('*') if p.is_file() or p.is_symlink()}
assert actual_paths == expected_paths, 'Unexpected or missing archived files'
print(f"PASS: {len(expected_paths)} archived files match hashes, modes, sizes and inventory")
