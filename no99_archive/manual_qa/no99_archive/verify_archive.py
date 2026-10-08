"""Verify archived bytes without running archived tools or reading credentials."""
import hashlib
import json
from pathlib import Path
import stat

root = Path(__file__).resolve().parent
manifest = json.loads((root / "archive_manifest.json").read_text())
expected = set()
for entry in manifest["entries"]:
    relative = Path(entry["archive_path"])
    assert not relative.is_absolute() and ".." not in relative.parts, relative
    path = root / relative
    assert path.is_file() and not path.is_symlink(), relative
    data = path.read_bytes()
    assert hashlib.sha256(data).hexdigest() == entry["sha256"], relative
    assert len(data) == entry["bytes"], relative
    assert stat.S_IMODE(path.stat().st_mode) == entry["mode"], relative
    expected.add(relative.as_posix())

metadata = {"README.md", ".gitignore", "archive_manifest.json", "verify_archive.py"}
local_only = set(manifest["local_only_excluded"])
actual = {
    path.relative_to(root).as_posix()
    for path in root.rglob("*")
    if (path.is_file() or path.is_symlink())
    and "__pycache__" not in path.parts
    and path.name != ".DS_Store"
}
assert actual - metadata - local_only == expected, "Unexpected or missing archived files"
print(f"PASS: {len(expected)} archived files match {len(manifest['entries'])} source records")
