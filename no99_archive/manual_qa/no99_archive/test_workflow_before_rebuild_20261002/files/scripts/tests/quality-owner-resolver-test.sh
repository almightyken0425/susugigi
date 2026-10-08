#!/bin/bash

set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
RESOLVER="$ROOT/scripts/quality_owner_resolver.py"
REGISTRY="$ROOT/data/products/products_registry.md"
MANIFEST="$ROOT/data/products/layer_manifest.yaml"
TEMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TEMP_ROOT"' EXIT

FAILURES=0
PASSES=0

assert_resolves() {
  product=$1
  module=$2
  expected=$3
  actual=$(python3 "$RESOLVER" --registry "$REGISTRY" --product "$product" --module "$module" 2>/dev/null) || {
    echo "FAIL: $product/$module 無法解析"
    FAILURES=$((FAILURES + 1))
    return
  }
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: $product/$module 得到 $actual"
    FAILURES=$((FAILURES + 1))
    return
  fi
  echo "PASS: $product/$module -> $expected"
  PASSES=$((PASSES + 1))
}

make_fixture() {
  name=$1
  old=$2
  new=$3
  FIXTURE="$TEMP_ROOT/$name.md"
  python3 - "$REGISTRY" "$FIXTURE" "$old" "$new" <<'PY'
import sys

source_path, target_path, old, new = sys.argv[1:]
with open(source_path, encoding="utf-8") as handle:
    source = handle.read()
if source.count(old) != 1:
    raise SystemExit("fixture source must occur exactly once")
with open(target_path, "w", encoding="utf-8") as handle:
    handle.write(source.replace(old, new, 1))
PY
}

assert_rejects() {
  label=$1
  registry=$2
  product=$3
  module=$4
  expected=$5
  output=$(python3 "$RESOLVER" --registry "$registry" --manifest "$MANIFEST" --product "$product" --module "$module" 2>&1)
  status=$?
  if [ "$status" -eq 0 ]; then
    echo "FAIL: $label 未拒絕"
    FAILURES=$((FAILURES + 1))
    return
  fi
  if ! printf '%s\n' "$output" | grep -F "$expected" >/dev/null; then
    echo "FAIL: $label 訊息不符"
    echo "$output"
    FAILURES=$((FAILURES + 1))
    return
  fi
  echo "PASS: $label"
  PASSES=$((PASSES + 1))
}

assert_context() {
  label=$1
  product=$2
  module=$3
  expected_owner=$4
  expected_path=$5
  expected_sources=$6
  output=$(python3 "$RESOLVER" --registry "$REGISTRY" --manifest "$MANIFEST" --product "$product" --module "$module" --json 2>/dev/null) || {
    echo "FAIL: $label 無法解析 context"
    FAILURES=$((FAILURES + 1))
    return
  }
  if ! python3 - "$output" "$expected_owner" "$expected_path" "$expected_sources" <<'PY'
import json
import os
import sys

context = json.loads(sys.argv[1])
expected_path = None if sys.argv[3] == "null" else sys.argv[3]
if expected_path is not None:
    expected_path = os.path.normpath(os.path.expanduser(expected_path))
expected_sources = sys.argv[4].split(",") if sys.argv[4] else []
assert context == {
    "owner": sys.argv[2],
    "quality_path": expected_path,
    "source_modules": expected_sources,
}
PY
  then
    echo "FAIL: $label context 不符"
    echo "$output"
    FAILURES=$((FAILURES + 1))
    return
  fi
  echo "PASS: $label context"
  PASSES=$((PASSES + 1))
}

assert_default_resolves() {
  actual=$(python3 "$RESOLVER" --product SuSuGiGi --module no3_cloud_functions 2>/dev/null) || {
    echo "FAIL: default-entry 無法解析"
    FAILURES=$((FAILURES + 1))
    return
  }
  if [ "$actual" != "SuSuGiGi/no2_accounting_app" ]; then
    echo "FAIL: default-entry 得到 $actual"
    FAILURES=$((FAILURES + 1))
    return
  fi
  echo "PASS: default-entry"
  PASSES=$((PASSES + 1))
}

assert_import_context() {
  if ! PYTHONPATH="$ROOT/scripts" python3 - "$REGISTRY" "$MANIFEST" <<'PY'
import sys

from quality_owner_resolver import (
    RegistryError,
    load_manifest,
    load_registry,
    resolve_quality_context,
    resolve_quality_owner,
)

registry = load_registry(sys.argv[1])
manifest = load_manifest(sys.argv[2])
context = resolve_quality_context(registry, "SuSuGiGi", "no3_cloud_functions", manifest)
assert context["owner"] == "SuSuGiGi/no2_accounting_app"
assert context["source_modules"] == [
    "SuSuGiGi/no2_accounting_app",
    "SuSuGiGi/no3_cloud_functions",
]
assert resolve_quality_owner(
    registry,
    "SuSuGiGi",
    "no3_cloud_functions",
    manifest,
) == "SuSuGiGi/no2_accounting_app"

try:
    resolve_quality_owner(registry, "SuSuGiGi", "no3_cloud_functions")
except TypeError:
    pass
else:
    raise AssertionError("resolve_quality_owner must require a manifest")

for product in registry["products"]:
    if product["id"] != "Hatsuon":
        continue
    product["modules"][0].pop("quality_owner")
    break
try:
    resolve_quality_owner(
        registry,
        "SuSuGiGi",
        "no3_cloud_functions",
        manifest,
    )
except RegistryError as error:
    assert "missing quality_owner" in str(error)
else:
    raise AssertionError("resolve_quality_owner must validate the complete registry")
PY
  then
    echo "FAIL: import-context"
    FAILURES=$((FAILURES + 1))
    return
  fi
  echo "PASS: import-context"
  PASSES=$((PASSES + 1))
}

assert_resolves SuSuGiGi no2_accounting_app SuSuGiGi/no2_accounting_app
assert_resolves SuSuGiGi no3_cloud_functions SuSuGiGi/no2_accounting_app
assert_resolves Hatsuon no1_pronunciation_app none
assert_default_resolves
assert_import_context
assert_context accounting-context SuSuGiGi no2_accounting_app SuSuGiGi/no2_accounting_app '~/Doc/ai-company/product/susugigi/no6_product_quality/no2_accounting_app' "SuSuGiGi/no2_accounting_app,SuSuGiGi/no3_cloud_functions"
assert_context none-context Hatsuon no1_pronunciation_app none null "Hatsuon/no1_pronunciation_app"

make_fixture missing-owner $'        quality_owner: none\n        layers_remove: [design, impl, quality, release]' $'        layers_remove: [design, impl, quality, release]' || exit 1
assert_rejects missing-owner "$FIXTURE" SuSuGiGi no1_user_management "missing quality_owner"

make_fixture list-owner $'      - id: no2_accounting_app\n        display: Accounting App\n        quality_owner: SuSuGiGi/no2_accounting_app' $'      - id: no2_accounting_app\n        display: Accounting App\n        quality_owner: [SuSuGiGi/no2_accounting_app]' || exit 1
assert_rejects list-owner "$FIXTURE" SuSuGiGi no2_accounting_app "must be a scalar"

make_fixture duplicate-owner $'      - id: no2_accounting_app\n        display: Accounting App\n        quality_owner: SuSuGiGi/no2_accounting_app' $'      - id: no2_accounting_app\n        display: Accounting App\n        quality_owner: SuSuGiGi/no2_accounting_app\n        quality_owner: SuSuGiGi/no2_accounting_app' || exit 1
assert_rejects duplicate-owner "$FIXTURE" SuSuGiGi no2_accounting_app "duplicate key quality_owner"

make_fixture malformed-owner $'      - id: no2_accounting_app\n        display: Accounting App\n        quality_owner: SuSuGiGi/no2_accounting_app' $'      - id: no2_accounting_app\n        display: Accounting App\n        quality_owner: SuSuGiGi' || exit 1
assert_rejects malformed-owner "$FIXTURE" SuSuGiGi no2_accounting_app "must use Product/module"

make_fixture dangling-owner $'        quality_owner: SuSuGiGi/no2_accounting_app\n        layers_remove: [design, quality, release]' $'        quality_owner: SuSuGiGi/no9_missing\n        layers_remove: [design, quality, release]' || exit 1
assert_rejects dangling-owner "$FIXTURE" SuSuGiGi no3_cloud_functions "references missing quality owner"

make_fixture cross-product-owner $'      - id: no1_pronunciation_app\n        display: Pronunciation App\n        quality_owner: none' $'      - id: no1_pronunciation_app\n        display: Pronunciation App\n        quality_owner: SuSuGiGi/no2_accounting_app' || exit 1
assert_rejects cross-product-owner "$FIXTURE" Hatsuon no1_pronunciation_app "must stay within product"

make_fixture owner-without-quality-layer $'        quality_owner: SuSuGiGi/no2_accounting_app\n        layers_remove: [design, quality, release]' $'        quality_owner: SuSuGiGi/no1_user_management\n        layers_remove: [design, quality, release]' || exit 1
assert_rejects owner-without-quality-layer "$FIXTURE" SuSuGiGi no3_cloud_functions "has no quality layer"

make_fixture owner-without-quality-repo "          quality: { remote: https://github.com/almightyken0425/susugigi-quality-no2-accounting-app.git, private: true }" "          quality_missing: { remote: https://github.com/almightyken0425/susugigi-quality-no2-accounting-app.git, private: true }" || exit 1
assert_rejects owner-without-quality-repo "$FIXTURE" SuSuGiGi no2_accounting_app "has no repos.quality remote"

make_fixture self-owned-mismatch $'      - id: no2_accounting_app\n        display: Accounting App\n        quality_owner: SuSuGiGi/no2_accounting_app' $'      - id: no2_accounting_app\n        display: Accounting App\n        quality_owner: SuSuGiGi/no3_cloud_functions' || exit 1
assert_rejects self-owned-mismatch "$FIXTURE" SuSuGiGi no2_accounting_app "owns a quality repo and must reference itself"

make_fixture source-quality-layer-cross-owner '        layers_remove: [design, quality, release]' '        layers_remove: [design, release]' || exit 1
assert_rejects source-quality-layer-cross-owner "$FIXTURE" SuSuGiGi no3_cloud_functions "has quality layer and must reference itself"

make_fixture duplicate-flow-remote '          quality: { remote: https://github.com/almightyken0425/susugigi-quality-no2-accounting-app.git, private: true }' '          quality: { remote: https://github.com/almightyken0425/susugigi-quality-no2-accounting-app.git, remote: duplicate, private: true }' || exit 1
assert_rejects duplicate-flow-remote "$FIXTURE" SuSuGiGi no2_accounting_app "duplicate key remote"

make_fixture blank-quality-remote '          quality: { remote: https://github.com/almightyken0425/susugigi-quality-no2-accounting-app.git, private: true }' '          quality: { remote: "   ", private: true }' || exit 1
assert_rejects blank-quality-remote "$FIXTURE" SuSuGiGi no2_accounting_app "has no repos.quality remote"

make_fixture boolean-quality-remote '          quality: { remote: https://github.com/almightyken0425/susugigi-quality-no2-accounting-app.git, private: true }' '          quality: { remote: true, private: true }' || exit 1
assert_rejects boolean-quality-remote "$FIXTURE" SuSuGiGi no2_accounting_app "has no repos.quality remote"

assert_rejects missing-query "$REGISTRY" SuSuGiGi no9_missing "module not found"

if [ "$FAILURES" -ne 0 ]; then
  echo "Results: $FAILURES failed"
  exit 1
fi

echo "Results: $PASSES passed, 0 failed"
