#!/usr/bin/env bash

set -euo pipefail

TEST_SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_CONTROL_ROOT="$(cd "$TEST_SCRIPT_DIR/../.." && pwd)"
TEST_TEMP_ROOT="$(mktemp -d)"
TEST_TEMP_ROOT="$(cd "$TEST_TEMP_ROOT" && pwd -P)"
export GIT_CONFIG_GLOBAL="$TEST_TEMP_ROOT/gitconfig"

cleanup_quality_alignment_audit_test() {
  rm -rf "$TEST_TEMP_ROOT"
}

trap cleanup_quality_alignment_audit_test EXIT HUP INT TERM

git_fixture_init() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init --quiet --initial-branch=main
  git -C "$repo" config user.name 'Quality Audit Test'
  git -C "$repo" config user.email 'quality-audit@example.invalid'
}

git_fixture_commit() {
  local repo="$1"
  local message="$2"
  git -C "$repo" add .
  git -C "$repo" commit --quiet -m "$message"
}

write_registry() {
  local registry="$1"
  local product_root="$2"
  mkdir -p "$(dirname "$registry")"
  {
    printf '# Test registry\n\n```yaml\n'
    printf 'products:\n'
    printf '  - id: TestProduct\n'
    printf '    profile: full_app\n'
    printf '    repo:\n'
    printf '      path: %s\n' "$product_root"
    printf '    modules:\n'
    printf '      - id: no1_app\n'
    printf '        layers_remove: [quality]\n'
    printf '        quality_owner: TestProduct/no1_quality\n'
    printf '        repos:\n'
    printf '          impl: { remote: fixture-impl }\n'
    printf '      - id: no1_quality\n'
    printf '        quality_owner: TestProduct/no1_quality\n'
    printf '        repos:\n'
    printf '          quality: { remote: fixture-quality }\n'
    printf '```\n'
  } > "$registry"
}

write_self_owned_registry() {
  local registry="$1"
  local product_root="$2"
  local include_spec="${3:-false}"
  mkdir -p "$(dirname "$registry")"
  {
    printf '# Test registry\n\n```yaml\n'
    printf 'products:\n'
    printf '  - id: TestProduct\n'
    printf '    profile: full_app\n'
    printf '    repo:\n'
    printf '      path: %s\n' "$product_root"
    printf '    modules:\n'
    printf '      - id: no1_app\n'
    printf '        quality_owner: TestProduct/no1_app\n'
    printf '        repos:\n'
    if [ "$include_spec" = true ]; then
      printf '          spec: { remote: fixture-spec }\n'
    fi
    printf '          impl: { remote: fixture-impl }\n'
    printf '          quality: { remote: fixture-quality }\n'
    printf '```\n'
  } > "$registry"
}

write_manifest() {
  local manifest="$1"
  {
    printf 'layers:\n'
    printf '  - id: spec\n'
    printf '    dir: no3_product_specs\n'
    printf '  - id: impl\n'
    printf '    dir: no5_product_development\n'
    printf '  - id: quality\n'
    printf '    dir: no6_product_quality\n'
    printf 'profiles:\n'
    printf '  - id: full_app\n'
    printf '    module_layers: [spec, impl, quality]\n'
  } > "$manifest"
}

write_quality_plan() {
  local plan="$1"
  local source_commit="$2"
  local source_tree="$3"
  local mapping_pattern="${4:-src/}"
  local mapping_columns="${5:-3}"
  local source_module="${6:-no1_app}"
  local spec_commit="${7:-}"
  local spec_tree="${8:-}"
  mkdir -p "$(dirname "$plan")"
  {
    printf '# Regression plan\n\n'
    printf '## 生成基線表\n\n'
    printf '| 上游 repo | commit | tree | 同步日期 |\n'
    printf '| --- | --- | --- | --- |\n'
    printf '| `no5_product_development/%s` | `%s` | `%s` | 2026-08-28 |\n' "$source_module" "$source_commit" "$source_tree"
    if [ -n "$spec_commit" ]; then
      printf '| `no3_product_specs/%s` | `%s` | `%s` | 2026-08-28 |\n' "$source_module" "$spec_commit" "$spec_tree"
    fi
    printf '\n## 路徑映射表\n\n'
    if [ "$mapping_columns" -eq 2 ]; then
      printf '| impl 路徑前綴 | 區碼 |\n'
      printf '| --- | --- |\n'
      printf '| `%s` | APP |\n' "$mapping_pattern"
    else
      printf '| impl 路徑前綴 | 區碼 | 直接測項 |\n'
      printf '| --- | --- | --- |\n'
      printf '| `%s` | APP | |\n' "$mapping_pattern"
    fi
  } > "$plan"
}

run_audit() {
  local registry="$1"
  local manifest="$2"
  local product="$3"
  local module="$4"
  local topic_branch="$5"
  local base_ref="$6"

  python3 "$TEST_CONTROL_ROOT/scripts/quality_alignment_audit.py" \
    --registry "$registry" \
    --layer-manifest "$manifest" \
    --product "$product" \
    --module "$module" \
    --topic-branch "$topic_branch" \
    --base-ref "$base_ref"
}

assert_matching_worktree_collects_all_change_kinds() {
  local case_root="$TEST_TEMP_ROOT/matching-worktree"
  local product_root="$case_root/product/TestProduct"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_app"
  local topic_root="$case_root/worktrees/topic"
  local impl_worktree="$topic_root/impl-no1_app"
  local quality_worktree="$topic_root/quality-no1_quality"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  local baseline_commit
  local baseline_tree
  baseline_commit="$(git -C "$impl_repo" rev-parse HEAD)"
  baseline_tree="$(git -C "$impl_repo" show -s --format=%T HEAD)"

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$baseline_commit" \
    "$baseline_tree"
  mkdir -p "$quality_repo/notes"
  printf 'quality base\n' > "$quality_repo/notes/base.txt"
  git_fixture_commit "$quality_repo" 'quality baseline'

  mkdir -p "$topic_root"
  git -C "$impl_repo" worktree add --quiet -b feat/topic "$impl_worktree" main
  mkdir -p "$impl_worktree/src"
  printf 'export const committed = true;\n' > "$impl_worktree/src/committed.ts"
  git_fixture_commit "$impl_worktree" 'topic committed change'
  printf 'export const staged = true;\n' > "$impl_worktree/src/staged.ts"
  git -C "$impl_worktree" add src/staged.ts
  printf 'export const base = 2;\n' > "$impl_worktree/src/base.ts"
  printf 'export const untracked = true;\n' > "$impl_worktree/src/untracked.ts"

  git -C "$quality_repo" worktree add --quiet -b feat/topic "$quality_worktree" main
  mkdir -p "$quality_worktree/notes"
  printf 'quality committed\n' > "$quality_worktree/notes/committed.txt"
  git_fixture_commit "$quality_worktree" 'quality topic change'
  printf 'quality staged\n' > "$quality_worktree/notes/staged.txt"
  git -C "$quality_worktree" add notes/staged.txt
  printf 'quality base changed\n' > "$quality_worktree/notes/base.txt"
  printf 'quality untracked\n' > "$quality_worktree/notes/untracked.txt"

  write_self_owned_registry "$registry" "$product_root"
  write_manifest "$manifest"

  local output
  local rc
  set +e
  output="$(run_audit \
    "$registry" \
    "$manifest" \
    TestProduct \
    no1_app \
    feat/topic \
    main 2>&1)"
  rc=$?
  set -e

  [ "$rc" -eq 1 ]
  AUDIT_OUTPUT="$output" \
    EXPECTED_IMPL_WORKTREE="$impl_worktree" \
    EXPECTED_QUALITY_WORKTREE="$quality_worktree" \
    python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["schema_version"] == 1
assert result["status"] == "QUALITY_REFRESH_REQUIRED"
assert result["product"] == "TestProduct"
assert result["source_module"] == "no1_app"
assert result["owner"] == "TestProduct/no1_app"
assert result["impl_candidate"] == {
    "kind": "worktree",
    "path": os.environ["EXPECTED_IMPL_WORKTREE"],
    "ref": "feat/topic",
}
assert result["quality_candidate"] == {
    "kind": "worktree",
    "path": os.environ["EXPECTED_QUALITY_WORKTREE"],
    "ref": "feat/topic",
}
assert result["impl_changes"]["committed"] == ["src/committed.ts"]
assert result["impl_changes"]["staged"] == ["src/staged.ts"]
assert result["impl_changes"]["unstaged"] == ["src/base.ts"]
assert result["impl_changes"]["untracked"] == ["src/untracked.ts"]
assert result["impl_changes"]["changed_paths"] == [
    "src/base.ts",
    "src/committed.ts",
    "src/staged.ts",
    "src/untracked.ts",
]
assert result["quality_changes"]["committed"] == ["notes/committed.txt"]
assert result["quality_changes"]["staged"] == ["notes/staged.txt"]
assert result["quality_changes"]["unstaged"] == ["notes/base.txt"]
assert result["quality_changes"]["untracked"] == ["notes/untracked.txt"]
assert result["quality_changes"]["changed_paths"] == [
    "notes/base.txt",
    "notes/committed.txt",
    "notes/staged.txt",
    "notes/untracked.txt",
]
assert isinstance(result["diagnostics"], list)
'
}

assert_same_name_branch_is_a_candidate() {
  local case_root="$TEST_TEMP_ROOT/branch-candidate"
  local product_root="$case_root/product/TestProduct"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_app"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  local baseline_commit
  local baseline_tree
  baseline_commit="$(git -C "$impl_repo" rev-parse HEAD)"
  baseline_tree="$(git -C "$impl_repo" show -s --format=%T HEAD)"
  git -C "$impl_repo" switch --quiet -c feat/topic
  printf 'export const topic = true;\n' > "$impl_repo/src/topic.ts"
  git_fixture_commit "$impl_repo" 'impl topic'
  local topic_commit
  local topic_tree
  topic_commit="$(git -C "$impl_repo" rev-parse HEAD)"
  topic_tree="$(git -C "$impl_repo" show -s --format=%T HEAD)"
  git -C "$impl_repo" switch --quiet main

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$baseline_commit" \
    "$baseline_tree" \
    'old-only/' \
    2
  git_fixture_commit "$quality_repo" 'quality baseline'
  git -C "$quality_repo" switch --quiet -c feat/topic
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$topic_commit" \
    "$topic_tree" \
    'src/' \
    2
  git_fixture_commit "$quality_repo" 'quality covers topic'
  git -C "$quality_repo" switch --quiet main

  write_self_owned_registry "$registry" "$product_root"
  write_manifest "$manifest"

  local output
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  AUDIT_OUTPUT="$output" \
    EXPECTED_IMPL_REPO="$impl_repo" \
    EXPECTED_QUALITY_REPO="$quality_repo" \
    python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_OK"
assert result["impl_candidate"] == {
    "kind": "branch",
    "path": os.environ["EXPECTED_IMPL_REPO"],
    "ref": "feat/topic",
}
assert result["quality_candidate"] == {
    "kind": "branch",
    "path": os.environ["EXPECTED_QUALITY_REPO"],
    "ref": "feat/topic",
}
assert result["impl_changes"]["committed"] == ["src/topic.ts"]
'
}

assert_worktree_head_is_the_candidate_commit() {
  local case_root="$TEST_TEMP_ROOT/worktree-head"
  local product_root="$case_root/product/TestProduct"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_app"
  local topic_root="$case_root/worktrees/topic"
  local impl_worktree="$topic_root/impl-no1_app"
  local quality_worktree="$topic_root/quality-no1_quality"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  mkdir -p "$topic_root"
  git -C "$impl_repo" worktree add --quiet -b feat/topic "$impl_worktree" main
  printf 'export const topic = true;\n' > "$impl_worktree/src/topic.ts"
  git_fixture_commit "$impl_worktree" 'impl topic'
  local topic_commit
  local topic_tree
  topic_commit="$(git -C "$impl_worktree" rev-parse HEAD)"
  topic_tree="$(git -C "$impl_worktree" show -s --format=%T HEAD)"
  git -C "$impl_repo" update-ref refs/remotes/origin/feat/topic main

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$topic_commit" \
    "$topic_tree"
  git_fixture_commit "$quality_repo" 'quality covers topic'
  git -C "$quality_repo" worktree add --quiet -b feat/topic "$quality_worktree" main

  write_self_owned_registry "$registry" "$product_root"
  write_manifest "$manifest"

  local output
  local rc
  set +e
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  rc=$?
  set -e
  [ "$rc" -eq 0 ]
  AUDIT_OUTPUT="$output" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_OK", result
'
}

write_single_module_registry() {
  local registry="$1"
  local product_root="$2"
  local owner="$3"
  mkdir -p "$(dirname "$registry")"
  {
    printf '# Test registry\n\n```yaml\n'
    printf 'products:\n'
    printf '  - id: TestProduct\n'
    printf '    profile: full_app\n'
    printf '    repo:\n'
    printf '      path: %s\n' "$product_root"
    printf '    modules:\n'
    printf '      - id: no1_app\n'
    printf '        layers_remove: [quality]\n'
    printf '        quality_owner: %s\n' "$owner"
    printf '        repos:\n'
    printf '          impl: { remote: fixture-impl }\n'
    printf '```\n'
  } > "$registry"
}

assert_none_owner_is_not_applicable() {
  local case_root="$TEST_TEMP_ROOT/not-applicable"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"
  write_single_module_registry "$registry" "$case_root/product/TestProduct" none
  write_manifest "$manifest"

  local output
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  AUDIT_OUTPUT="$output" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_NOT_APPLICABLE"
assert result["owner"] == "none"
assert result["diagnostics"] == []
'
}

assert_invalid_owner_fails_closed() {
  local case_root="$TEST_TEMP_ROOT/invalid-owner"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"
  write_single_module_registry \
    "$registry" \
    "$case_root/product/TestProduct" \
    MissingProduct/no9_missing
  write_manifest "$manifest"

  local output
  local rc
  set +e
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  AUDIT_OUTPUT="$output" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_OWNER_INVALID"
assert result["owner"] is None
assert result["diagnostics"]
'
}

assert_missing_topic_does_not_fall_back_to_main() {
  local case_root="$TEST_TEMP_ROOT/missing-topic"
  local product_root="$case_root/product/TestProduct"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_quality"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  local baseline_commit
  local baseline_tree
  baseline_commit="$(git -C "$impl_repo" rev-parse HEAD)"
  baseline_tree="$(git -C "$impl_repo" show -s --format=%T HEAD)"

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$baseline_commit" \
    "$baseline_tree"
  git_fixture_commit "$quality_repo" 'quality baseline'
  write_registry "$registry" "$product_root"
  write_manifest "$manifest"

  local output
  local rc
  set +e
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/absent main)"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  AUDIT_OUTPUT="$output" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_REFRESH_REQUIRED"
assert result["impl_candidate"]["kind"] == "missing"
assert result["quality_candidate"]["kind"] == "missing"
assert result["impl_candidate"]["ref"] == "feat/absent"
assert result["impl_changes"]["changed_paths"] == []
assert "source topic branch is missing" in result["diagnostics"]
'
}

assert_baseline_invalid_variant() {
  local variant="$1"
  local case_root="$TEST_TEMP_ROOT/baseline-$variant"
  local product_root="$case_root/product/TestProduct"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_quality"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  local main_commit
  local main_tree
  main_commit="$(git -C "$impl_repo" rev-parse HEAD)"
  main_tree="$(git -C "$impl_repo" show -s --format=%T HEAD)"

  local baseline_commit="$main_commit"
  local baseline_tree="$main_tree"
  local source_module=no1_app
  if [ "$variant" = non-ancestor ]; then
    git -C "$impl_repo" switch --quiet -c side
    printf 'export const side = true;\n' > "$impl_repo/src/side.ts"
    git_fixture_commit "$impl_repo" 'side change'
    baseline_commit="$(git -C "$impl_repo" rev-parse HEAD)"
    baseline_tree="$(git -C "$impl_repo" show -s --format=%T HEAD)"
    git -C "$impl_repo" switch --quiet main
  fi

  git -C "$impl_repo" switch --quiet -c feat/topic
  printf 'export const topic = true;\n' > "$impl_repo/src/topic.ts"
  git_fixture_commit "$impl_repo" 'topic change'
  git -C "$impl_repo" switch --quiet main

  case "$variant" in
    missing-row)
      source_module=no9_other
      ;;
    missing-object)
      baseline_commit=0000000000000000000000000000000000000001
      ;;
    tree-mismatch)
      baseline_tree=0000000000000000000000000000000000000001
      ;;
  esac

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$baseline_commit" \
    "$baseline_tree" \
    'src/' \
    3 \
    "$source_module"
  git_fixture_commit "$quality_repo" 'quality candidate'
  git -C "$quality_repo" branch feat/topic
  write_registry "$registry" "$product_root"
  write_manifest "$manifest"

  local output
  local rc
  set +e
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  AUDIT_OUTPUT="$output" VARIANT="$variant" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_BASELINE_INVALID", (os.environ["VARIANT"], result)
assert result["diagnostics"]
'
}

assert_unmapped_path_is_a_mapping_gap() {
  local case_root="$TEST_TEMP_ROOT/mapping-gap"
  local product_root="$case_root/product/TestProduct"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_quality"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  local baseline_commit
  local baseline_tree
  baseline_commit="$(git -C "$impl_repo" rev-parse HEAD)"
  baseline_tree="$(git -C "$impl_repo" show -s --format=%T HEAD)"
  git -C "$impl_repo" switch --quiet -c feat/topic
  printf 'export const unmapped = true;\n' > "$impl_repo/src/unmapped.ts"
  git_fixture_commit "$impl_repo" 'unmapped topic change'
  git -C "$impl_repo" switch --quiet main

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$baseline_commit" \
    "$baseline_tree" \
    'docs/' \
    3
  git_fixture_commit "$quality_repo" 'quality baseline'
  git -C "$quality_repo" branch feat/topic
  write_registry "$registry" "$product_root"
  write_manifest "$manifest"

  local output
  local rc
  set +e
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  AUDIT_OUTPUT="$output" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_MAPPING_GAP"
assert result["changed_paths"] == ["src/unmapped.ts"]
assert result["diagnostics"] == ["unmapped source path: src/unmapped.ts"]
'
}

assert_divergent_quality_candidate_invalidates_baseline() {
  local case_root="$TEST_TEMP_ROOT/divergent-quality"
  local product_root="$case_root/product/TestProduct"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_quality"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  git -C "$impl_repo" switch --quiet -c feat/topic
  printf 'export const topic = true;\n' > "$impl_repo/src/topic.ts"
  git_fixture_commit "$impl_repo" 'impl topic'
  local topic_commit
  local topic_tree
  topic_commit="$(git -C "$impl_repo" rev-parse HEAD)"
  topic_tree="$(git -C "$impl_repo" show -s --format=%T HEAD)"
  git -C "$impl_repo" switch --quiet main

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$topic_commit" \
    "$topic_tree"
  git_fixture_commit "$quality_repo" 'quality plan'
  local quality_tree
  local quality_topic_commit
  quality_tree="$(git -C "$quality_repo" show -s --format=%T HEAD)"
  quality_topic_commit="$(printf 'divergent quality topic\n' | git -C "$quality_repo" commit-tree "$quality_tree")"
  git -C "$quality_repo" branch feat/topic "$quality_topic_commit"

  write_registry "$registry" "$product_root"
  write_manifest "$manifest"

  local output
  local rc
  set +e
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  AUDIT_OUTPUT="$output" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_BASELINE_INVALID", result
assert "quality base ref is not an ancestor of quality candidate" in result["diagnostics"]
'
}

assert_path_with_spaces_survives_nul_protocol() {
  local case_root="$TEST_TEMP_ROOT/path-with-spaces"
  local product_root="$case_root/product/TestProduct"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_app"
  local topic_root="$case_root/worktrees/topic"
  local impl_worktree="$topic_root/impl-no1_app"
  local quality_worktree="$topic_root/quality-no1_quality"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  local baseline_commit
  local baseline_tree
  baseline_commit="$(git -C "$impl_repo" rev-parse HEAD)"
  baseline_tree="$(git -C "$impl_repo" show -s --format=%T HEAD)"

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$baseline_commit" \
    "$baseline_tree"
  git_fixture_commit "$quality_repo" 'quality baseline'

  mkdir -p "$topic_root"
  git -C "$impl_repo" worktree add --quiet -b feat/topic "$impl_worktree" main
  printf 'export const spaced = true;\n' > "$impl_worktree/src/file with spaces.ts"
  git -C "$quality_repo" worktree add --quiet -b feat/topic "$quality_worktree" main
  write_self_owned_registry "$registry" "$product_root"
  write_manifest "$manifest"

  local output
  local rc
  set +e
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  AUDIT_OUTPUT="$output" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_REFRESH_REQUIRED"
assert result["impl_changes"]["untracked"] == ["src/file with spaces.ts"]
assert result["changed_paths"] == ["src/file with spaces.ts"]
'
}

assert_committed_rename_includes_both_paths() {
  local case_root="$TEST_TEMP_ROOT/committed-rename"
  local product_root="$case_root/product/TestProduct"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_quality"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const renamed = true;\n' > "$impl_repo/src/old name.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  git -C "$impl_repo" switch --quiet -c feat/topic
  git -C "$impl_repo" mv 'src/old name.ts' 'src/new name.ts'
  git_fixture_commit "$impl_repo" 'rename source path'
  local topic_commit
  local topic_tree
  topic_commit="$(git -C "$impl_repo" rev-parse HEAD)"
  topic_tree="$(git -C "$impl_repo" show -s --format=%T HEAD)"
  git -C "$impl_repo" switch --quiet main

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$topic_commit" \
    "$topic_tree" \
    'src/new name.ts' \
    2
  git_fixture_commit "$quality_repo" 'quality candidate'
  git -C "$quality_repo" branch feat/topic
  write_registry "$registry" "$product_root"
  write_manifest "$manifest"

  local output
  local rc
  set +e
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  AUDIT_OUTPUT="$output" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_MAPPING_GAP", result
assert result["impl_changes"]["committed"] == [
    "src/new name.ts",
    "src/old name.ts",
]
assert result["changed_paths"] == ["src/new name.ts", "src/old name.ts"]
assert result["diagnostics"] == ["unmapped source path: src/old name.ts"]
'
}

assert_installed_symlink_uses_resolver_defaults() {
  local case_root="$TEST_TEMP_ROOT/installed-symlink"
  local installed_home="$case_root/home"
  mkdir -p "$installed_home/.codex"
  ln -s "$TEST_CONTROL_ROOT/scripts" "$installed_home/.codex/scripts"

  local output
  output="$(HOME="$installed_home" python3 \
    "$installed_home/.codex/scripts/quality_alignment_audit.py" \
    --product Hatsuon \
    --module no1_pronunciation_app \
    --topic-branch feat/installed-probe \
    --base-ref main)"
  AUDIT_OUTPUT="$output" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_NOT_APPLICABLE", result
assert result["product"] == "Hatsuon"
assert result["source_module"] == "no1_pronunciation_app"
assert result["owner"] == "none"
assert result["diagnostics"] == []
'
}

assert_worktree_path_with_newline_uses_nul_protocol() {
  local case_root="$TEST_TEMP_ROOT/worktree-newline"
  local product_root="$case_root/product/TestProduct"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_app"
  local topic_root="$case_root/worktrees/topic"
  local impl_worktree="$topic_root/impl"$'\n'"no1_app"
  local quality_worktree="$topic_root/quality"$'\n'"no1_quality"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  mkdir -p "$topic_root"
  git -C "$impl_repo" worktree add --quiet -b feat/topic "$impl_worktree" main
  printf 'export const topic = true;\n' > "$impl_worktree/src/topic.ts"
  git_fixture_commit "$impl_worktree" 'impl topic'
  local topic_commit
  local topic_tree
  topic_commit="$(git -C "$impl_worktree" rev-parse HEAD)"
  topic_tree="$(git -C "$impl_worktree" show -s --format=%T HEAD)"

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$topic_commit" \
    "$topic_tree"
  git_fixture_commit "$quality_repo" 'quality covers topic'
  git -C "$quality_repo" worktree add --quiet -b feat/topic "$quality_worktree" main
  write_self_owned_registry "$registry" "$product_root"
  write_manifest "$manifest"

  local output
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  AUDIT_OUTPUT="$output" \
    EXPECTED_IMPL_WORKTREE="$impl_worktree" \
    EXPECTED_QUALITY_WORKTREE="$quality_worktree" \
    python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_OK", result
assert result["impl_candidate"] == {
    "kind": "worktree",
    "path": os.environ["EXPECTED_IMPL_WORKTREE"],
    "ref": "feat/topic",
}
assert result["quality_candidate"] == {
    "kind": "worktree",
    "path": os.environ["EXPECTED_QUALITY_WORKTREE"],
    "ref": "feat/topic",
}
'
}

assert_invalid_utf8_filename_produces_valid_json() {
  local case_root="$TEST_TEMP_ROOT/invalid-utf8"
  local product_root="$case_root/product/TestProduct"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_app"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"
  local output_file="$case_root/audit.json"
  local fixture_index="$case_root/fixture.index"
  local invalid_relative_path=$'src/invalid-\xff.ts'

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  local baseline_commit
  local baseline_tree
  baseline_commit="$(git -C "$impl_repo" rev-parse HEAD)"
  baseline_tree="$(git -C "$impl_repo" show -s --format=%T HEAD)"
  local invalid_blob
  local topic_tree
  local topic_commit
  invalid_blob="$(printf 'export const invalid = true;\n' | git -C "$impl_repo" hash-object -w --stdin)"
  GIT_INDEX_FILE="$fixture_index" git -C "$impl_repo" read-tree main
  printf '100644 %s\t%s\0' "$invalid_blob" "$invalid_relative_path" | \
    GIT_INDEX_FILE="$fixture_index" git -C "$impl_repo" update-index -z --index-info
  topic_tree="$(GIT_INDEX_FILE="$fixture_index" git -C "$impl_repo" write-tree)"
  topic_commit="$(printf 'invalid utf8 topic\n' | git -C "$impl_repo" commit-tree "$topic_tree" -p main)"
  git -C "$impl_repo" branch feat/topic "$topic_commit"

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$baseline_commit" \
    "$baseline_tree"
  git_fixture_commit "$quality_repo" 'quality baseline'
  git -C "$quality_repo" branch feat/topic
  write_self_owned_registry "$registry" "$product_root"
  write_manifest "$manifest"

  local rc
  set +e
  run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main > "$output_file"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  AUDIT_OUTPUT_FILE="$output_file" python3 -c '
import json
import os
from pathlib import Path

raw = Path(os.environ["AUDIT_OUTPUT_FILE"]).read_bytes()
text = raw.decode("utf-8", "strict")
result = json.loads(text)
expected = b"src/invalid-\xff.ts".decode("utf-8", "surrogateescape")
assert result["status"] == "QUALITY_REFRESH_REQUIRED"
assert result["impl_changes"]["committed"] == [expected]
assert result["changed_paths"] == [expected]
'
}

assert_duplicate_baseline_row_fails_closed() {
  local case_root="$TEST_TEMP_ROOT/duplicate-baseline"
  local product_root="$case_root/product/TestProduct"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_quality"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  git -C "$impl_repo" switch --quiet -c feat/topic
  printf 'export const topic = true;\n' > "$impl_repo/src/topic.ts"
  git_fixture_commit "$impl_repo" 'impl topic'
  local topic_commit
  local topic_tree
  topic_commit="$(git -C "$impl_repo" rev-parse HEAD)"
  topic_tree="$(git -C "$impl_repo" show -s --format=%T HEAD)"
  git -C "$impl_repo" switch --quiet main

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$topic_commit" \
    "$topic_tree"
  {
    printf '\n## Duplicate baseline\n\n'
    printf '| 上游 repo | commit | tree | 同步日期 |\n'
    printf '| --- | --- | --- | --- |\n'
    printf '| `no5_product_development/no1_app` | `%s` | `%s` | 2026-08-28 |\n' \
      "$topic_commit" \
      "$topic_tree"
  } >> "$quality_repo/no2_regression_plan/no0_index.md"
  git_fixture_commit "$quality_repo" 'duplicate quality baseline'
  git -C "$quality_repo" branch feat/topic
  write_registry "$registry" "$product_root"
  write_manifest "$manifest"

  local output
  local rc
  set +e
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  AUDIT_OUTPUT="$output" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_BASELINE_INVALID", result
assert result["diagnostics"] == [
    "duplicate baseline row for upstream repo: no5_product_development/no1_app"
]
'
}

assert_annotated_tag_object_is_not_a_baseline_commit() {
  local case_root="$TEST_TEMP_ROOT/tag-baseline"
  local product_root="$case_root/product/TestProduct"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_quality"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  git -C "$impl_repo" switch --quiet -c feat/topic
  printf 'export const topic = true;\n' > "$impl_repo/src/topic.ts"
  git_fixture_commit "$impl_repo" 'impl topic'
  local topic_tree
  local tag_object
  topic_tree="$(git -C "$impl_repo" show -s --format=%T HEAD)"
  git -C "$impl_repo" tag -a baseline-tag -m 'annotated baseline tag' HEAD
  tag_object="$(git -C "$impl_repo" rev-parse 'baseline-tag^{tag}')"
  git -C "$impl_repo" switch --quiet main

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$tag_object" \
    "$topic_tree"
  git_fixture_commit "$quality_repo" 'tag object baseline'
  git -C "$quality_repo" branch feat/topic
  write_registry "$registry" "$product_root"
  write_manifest "$manifest"

  local output
  local rc
  set +e
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  AUDIT_OUTPUT="$output" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_BASELINE_INVALID", result
assert result["diagnostics"] == [
    "baseline commit hash is not a native commit object"
]
'
}

assert_missing_repo_is_a_baseline_failure() {
  local missing_layer="$1"
  local case_root="$TEST_TEMP_ROOT/missing-repo-$missing_layer"
  local product_root="$case_root/product/TestProduct"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_quality"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  if [ "$missing_layer" != source ]; then
    git_fixture_init "$impl_repo"
    mkdir -p "$impl_repo/src"
    printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
    git_fixture_commit "$impl_repo" 'impl baseline'
  fi
  if [ "$missing_layer" != quality ]; then
    git_fixture_init "$quality_repo"
    mkdir -p "$quality_repo/no2_regression_plan"
    printf '# unused fixture\n' > "$quality_repo/no2_regression_plan/no0_index.md"
    git_fixture_commit "$quality_repo" 'quality baseline'
  fi
  write_registry "$registry" "$product_root"
  write_manifest "$manifest"

  local output
  local rc
  set +e
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  AUDIT_OUTPUT="$output" MISSING_LAYER="$missing_layer" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_BASELINE_INVALID", result
assert result["owner"] == "TestProduct/no1_quality"
expected = "source impl repo is missing" if os.environ["MISSING_LAYER"] == "source" else "quality owner repo is missing"
assert any(message.startswith(expected) for message in result["diagnostics"])
'
}

assert_malformed_config_returns_single_json() {
  local malformed_kind="$1"
  local case_root="$TEST_TEMP_ROOT/malformed-$malformed_kind"
  local product_root="$case_root/product/TestProduct"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"
  local stdout_file="$case_root/stdout.json"
  local stderr_file="$case_root/stderr.txt"
  mkdir -p "$case_root"

  if [ "$malformed_kind" = registry ]; then
    {
      printf '# Malformed registry\n\n```yaml\n'
      printf 'products: malformed\n'
      printf '```\n'
    } > "$registry"
    write_manifest "$manifest"
  else
    write_registry "$registry" "$product_root"
    {
      printf 'layers: malformed\n'
      printf 'profiles: malformed\n'
    } > "$manifest"
  fi

  local rc
  set +e
  run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main \
    > "$stdout_file" \
    2> "$stderr_file"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  [ ! -s "$stderr_file" ]
  AUDIT_STDOUT_FILE="$stdout_file" python3 -c '
import json
import os
from pathlib import Path

raw = Path(os.environ["AUDIT_STDOUT_FILE"]).read_bytes()
text = raw.decode("utf-8", "strict")
result = json.loads(text)
assert result["status"] == "QUALITY_OWNER_INVALID", result
assert result["owner"] is None
assert result["diagnostics"]
'
}

assert_candidate_git_error_is_a_baseline_failure() {
  local case_root="$TEST_TEMP_ROOT/candidate-git-error"
  local product_root="$case_root/product/TestProduct"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_quality"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  mkdir -p "$impl_repo/.git"
  git_fixture_init "$quality_repo"
  mkdir -p "$quality_repo/no2_regression_plan"
  printf '# unused fixture\n' > "$quality_repo/no2_regression_plan/no0_index.md"
  git_fixture_commit "$quality_repo" 'quality baseline'
  write_registry "$registry" "$product_root"
  write_manifest "$manifest"

  local output
  local rc
  set +e
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  AUDIT_OUTPUT="$output" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_BASELINE_INVALID", result
assert result["owner"] == "TestProduct/no1_quality"
assert any(message.startswith("git worktree failed") for message in result["diagnostics"])
'
}

assert_remote_only_ref_is_a_branch_candidate() {
  local case_root="$TEST_TEMP_ROOT/remote-only"
  local product_root="$case_root/product/TestProduct"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_app"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  git -C "$impl_repo" switch --quiet -c feat/topic
  printf 'export const remote = true;\n' > "$impl_repo/src/remote.ts"
  git_fixture_commit "$impl_repo" 'remote topic'
  local topic_commit
  local topic_tree
  topic_commit="$(git -C "$impl_repo" rev-parse HEAD)"
  topic_tree="$(git -C "$impl_repo" show -s --format=%T HEAD)"
  git -C "$impl_repo" switch --quiet main
  git -C "$impl_repo" update-ref refs/remotes/origin/feat/topic "$topic_commit"
  git -C "$impl_repo" branch -D feat/topic >/dev/null

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$(git -C "$impl_repo" rev-parse main)" \
    "$(git -C "$impl_repo" show -s --format=%T main)"
  git_fixture_commit "$quality_repo" 'quality baseline'
  git -C "$quality_repo" switch --quiet -c feat/topic
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$topic_commit" \
    "$topic_tree"
  git_fixture_commit "$quality_repo" 'quality remote topic'
  local quality_topic_commit
  quality_topic_commit="$(git -C "$quality_repo" rev-parse HEAD)"
  git -C "$quality_repo" switch --quiet main
  git -C "$quality_repo" update-ref refs/remotes/origin/feat/topic "$quality_topic_commit"
  git -C "$quality_repo" branch -D feat/topic >/dev/null
  write_self_owned_registry "$registry" "$product_root"
  write_manifest "$manifest"

  local output
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  AUDIT_OUTPUT="$output" \
    EXPECTED_IMPL_REPO="$impl_repo" \
    EXPECTED_QUALITY_REPO="$quality_repo" \
    python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_OK", result
assert result["impl_candidate"] == {
    "kind": "branch",
    "path": os.environ["EXPECTED_IMPL_REPO"],
    "ref": "origin/feat/topic",
}
assert result["quality_candidate"] == {
    "kind": "branch",
    "path": os.environ["EXPECTED_QUALITY_REPO"],
    "ref": "origin/feat/topic",
}
assert result["changed_paths"] == ["src/remote.ts"]
'
}

assert_staged_rename_includes_both_paths() {
  local case_root="$TEST_TEMP_ROOT/staged-rename"
  local product_root="$case_root/product/TestProduct"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_quality"
  local topic_root="$case_root/worktrees/topic"
  local impl_worktree="$topic_root/impl-no1_app"
  local quality_worktree="$topic_root/quality-no1_quality"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const stagedRename = true;\n' > "$impl_repo/src/staged-old.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  local baseline_commit
  local baseline_tree
  baseline_commit="$(git -C "$impl_repo" rev-parse HEAD)"
  baseline_tree="$(git -C "$impl_repo" show -s --format=%T HEAD)"

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$baseline_commit" \
    "$baseline_tree" \
    'src/staged-new.ts' \
    2
  git_fixture_commit "$quality_repo" 'quality baseline'

  mkdir -p "$topic_root"
  git -C "$impl_repo" worktree add --quiet -b feat/topic "$impl_worktree" main
  git -C "$impl_worktree" mv src/staged-old.ts src/staged-new.ts
  git -C "$quality_repo" worktree add --quiet -b feat/topic "$quality_worktree" main
  write_registry "$registry" "$product_root"
  write_manifest "$manifest"

  local output
  local rc
  set +e
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  AUDIT_OUTPUT="$output" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_MAPPING_GAP", result
assert result["impl_changes"]["staged"] == [
    "src/staged-new.ts",
    "src/staged-old.ts",
]
assert result["changed_paths"] == ["src/staged-new.ts", "src/staged-old.ts"]
assert result["diagnostics"] == ["unmapped source path: src/staged-old.ts"]
'
}

assert_local_and_origin_topic_mismatch_fails_closed() {
  local relation
  for relation in local-ahead origin-ahead diverged; do
    local case_root="$TEST_TEMP_ROOT/topic-mismatch-$relation"
    local product_root="$case_root/product/TestProduct"
    local impl_repo="$product_root/no5_product_development/no1_app"
    local quality_repo="$product_root/no6_product_quality/no1_quality"
    local registry="$case_root/products_registry.md"
    local manifest="$case_root/layer_manifest.yaml"

    git_fixture_init "$impl_repo"
    mkdir -p "$impl_repo/src"
    printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
    git_fixture_commit "$impl_repo" 'impl baseline'
    local base_commit
    base_commit="$(git -C "$impl_repo" rev-parse HEAD)"
    git -C "$impl_repo" branch feat/topic main

    local local_commit="$base_commit"
    local origin_commit="$base_commit"
    if [ "$relation" != origin-ahead ]; then
      git -C "$impl_repo" switch --quiet feat/topic
      printf 'export const local = true;\n' > "$impl_repo/src/local.ts"
      git_fixture_commit "$impl_repo" 'local topic'
      local_commit="$(git -C "$impl_repo" rev-parse HEAD)"
      git -C "$impl_repo" switch --quiet main
    fi
    if [ "$relation" != local-ahead ]; then
      git -C "$impl_repo" switch --quiet -c origin-topic main
      printf 'export const origin = true;\n' > "$impl_repo/src/origin.ts"
      git_fixture_commit "$impl_repo" 'origin topic'
      origin_commit="$(git -C "$impl_repo" rev-parse HEAD)"
      git -C "$impl_repo" switch --quiet main
      git -C "$impl_repo" branch -D origin-topic >/dev/null
    fi
    git -C "$impl_repo" update-ref refs/heads/feat/topic "$local_commit"
    git -C "$impl_repo" update-ref refs/remotes/origin/feat/topic "$origin_commit"

    git_fixture_init "$quality_repo"
    printf 'quality fixture\n' > "$quality_repo/README.md"
    git_fixture_commit "$quality_repo" 'quality baseline'
    write_registry "$registry" "$product_root"
    write_manifest "$manifest"

    local output
    local rc
    set +e
    output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
    rc=$?
    set -e
    [ "$rc" -eq 1 ]
    AUDIT_OUTPUT="$output" EXPECTED_RELATION="$relation" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_BASELINE_INVALID", result
expected = os.environ["EXPECTED_RELATION"].replace("-", " ")
assert any(expected in message for message in result["diagnostics"]), result
'
  done
}

assert_shared_owner_requires_repo_aware_mapping() {
  local case_root="$TEST_TEMP_ROOT/shared-owner"
  local product_root="$case_root/product/TestProduct"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_quality"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  local baseline_commit
  local baseline_tree
  baseline_commit="$(git -C "$impl_repo" rev-parse HEAD)"
  baseline_tree="$(git -C "$impl_repo" show -s --format=%T HEAD)"
  git -C "$impl_repo" branch feat/topic main

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$baseline_commit" \
    "$baseline_tree"
  git_fixture_commit "$quality_repo" 'quality baseline'
  git -C "$quality_repo" branch feat/topic main
  write_registry "$registry" "$product_root"
  write_manifest "$manifest"

  local output
  local rc
  set +e
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  AUDIT_OUTPUT="$output" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_MAPPING_GAP", result
assert any("shared quality owner requires repo-aware mapping" in message for message in result["diagnostics"]), result
'
}

assert_spec_without_topic_uses_explicit_base_baseline() {
  local case_root="$TEST_TEMP_ROOT/spec-base-baseline"
  local product_root="$case_root/product/TestProduct"
  local spec_repo="$product_root/no3_product_specs/no1_app"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_app"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  git_fixture_init "$spec_repo"
  printf 'old spec\n' > "$spec_repo/spec.md"
  git_fixture_commit "$spec_repo" 'old spec baseline'
  local stale_spec_commit
  local stale_spec_tree
  stale_spec_commit="$(git -C "$spec_repo" rev-parse HEAD)"
  stale_spec_tree="$(git -C "$spec_repo" show -s --format=%T HEAD)"
  printf 'current spec\n' > "$spec_repo/spec.md"
  git_fixture_commit "$spec_repo" 'current spec baseline'

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  local impl_commit
  local impl_tree
  impl_commit="$(git -C "$impl_repo" rev-parse HEAD)"
  impl_tree="$(git -C "$impl_repo" show -s --format=%T HEAD)"
  git -C "$impl_repo" branch feat/topic main

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$impl_commit" \
    "$impl_tree" \
    'src/' \
    3 \
    no1_app \
    "$stale_spec_commit" \
    "$stale_spec_tree"
  git_fixture_commit "$quality_repo" 'quality baseline'
  git -C "$quality_repo" branch feat/topic main
  write_self_owned_registry "$registry" "$product_root" true
  write_manifest "$manifest"

  local output
  local rc
  set +e
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  AUDIT_OUTPUT="$output" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_BASELINE_INVALID", result
assert result["spec_candidate"]["kind"] == "missing", result
assert result["spec_changes"]["changed_paths"] == [], result
assert any("spec baseline does not match explicit base ref" in message for message in result["diagnostics"]), result
'
}

assert_spec_topic_diff_requires_refresh() {
  local case_root="$TEST_TEMP_ROOT/spec-topic-diff"
  local product_root="$case_root/product/TestProduct"
  local spec_repo="$product_root/no3_product_specs/no1_app"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_app"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  git_fixture_init "$spec_repo"
  printf 'base spec\n' > "$spec_repo/spec.md"
  git_fixture_commit "$spec_repo" 'spec baseline'
  local spec_base_commit
  local spec_base_tree
  spec_base_commit="$(git -C "$spec_repo" rev-parse HEAD)"
  spec_base_tree="$(git -C "$spec_repo" show -s --format=%T HEAD)"
  git -C "$spec_repo" switch --quiet -c feat/topic
  printf 'topic spec\n' > "$spec_repo/topic.md"
  git_fixture_commit "$spec_repo" 'spec topic'
  git -C "$spec_repo" switch --quiet main

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  local impl_commit
  local impl_tree
  impl_commit="$(git -C "$impl_repo" rev-parse HEAD)"
  impl_tree="$(git -C "$impl_repo" show -s --format=%T HEAD)"
  git -C "$impl_repo" branch feat/topic main

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$impl_commit" \
    "$impl_tree" \
    'src/' \
    3 \
    no1_app \
    "$spec_base_commit" \
    "$spec_base_tree"
  git_fixture_commit "$quality_repo" 'quality baseline'
  git -C "$quality_repo" branch feat/topic main
  write_self_owned_registry "$registry" "$product_root" true
  write_manifest "$manifest"

  local output
  local rc
  set +e
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  AUDIT_OUTPUT="$output" EXPECTED_SPEC_REPO="$spec_repo" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_REFRESH_REQUIRED", result
assert result["spec_candidate"] == {
    "kind": "branch",
    "path": os.environ["EXPECTED_SPEC_REPO"],
    "ref": "feat/topic",
}
assert result["spec_changes"]["committed"] == ["topic.md"], result
assert any("source spec topic contains changes" in message for message in result["diagnostics"]), result
'
}

assert_spec_topic_without_diff_accepts_matching_baseline() {
  local case_root="$TEST_TEMP_ROOT/spec-topic-no-diff"
  local product_root="$case_root/product/TestProduct"
  local spec_repo="$product_root/no3_product_specs/no1_app"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_app"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  git_fixture_init "$spec_repo"
  printf 'base spec\n' > "$spec_repo/spec.md"
  git_fixture_commit "$spec_repo" 'spec baseline'
  local spec_commit
  local spec_tree
  spec_commit="$(git -C "$spec_repo" rev-parse HEAD)"
  spec_tree="$(git -C "$spec_repo" show -s --format=%T HEAD)"
  git -C "$spec_repo" branch feat/topic main

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  local impl_commit
  local impl_tree
  impl_commit="$(git -C "$impl_repo" rev-parse HEAD)"
  impl_tree="$(git -C "$impl_repo" show -s --format=%T HEAD)"
  git -C "$impl_repo" branch feat/topic main

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$impl_commit" \
    "$impl_tree" \
    'src/' \
    3 \
    no1_app \
    "$spec_commit" \
    "$spec_tree"
  git_fixture_commit "$quality_repo" 'quality baseline'
  git -C "$quality_repo" branch feat/topic main
  write_self_owned_registry "$registry" "$product_root" true
  write_manifest "$manifest"

  local output
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  AUDIT_OUTPUT="$output" EXPECTED_SPEC_REPO="$spec_repo" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_OK", result
assert result["spec_candidate"] == {
    "kind": "branch",
    "path": os.environ["EXPECTED_SPEC_REPO"],
    "ref": "feat/topic",
}
assert result["spec_changes"]["changed_paths"] == [], result
'
}

assert_matching_worktree_rejects_origin_ahead_or_diverged() {
  local relation
  for relation in origin-ahead diverged; do
    local case_root="$TEST_TEMP_ROOT/worktree-origin-$relation"
    local product_root="$case_root/product/TestProduct"
    local impl_repo="$product_root/no5_product_development/no1_app"
    local quality_repo="$product_root/no6_product_quality/no1_quality"
    local impl_worktree="$case_root/worktrees/impl-no1_app"
    local registry="$case_root/products_registry.md"
    local manifest="$case_root/layer_manifest.yaml"

    git_fixture_init "$impl_repo"
    mkdir -p "$impl_repo/src"
    printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
    git_fixture_commit "$impl_repo" 'impl baseline'
    mkdir -p "$(dirname "$impl_worktree")"
    git -C "$impl_repo" worktree add --quiet -b feat/topic "$impl_worktree" main
    if [ "$relation" = diverged ]; then
      printf 'export const local = true;\n' > "$impl_worktree/src/local.ts"
      git_fixture_commit "$impl_worktree" 'local topic'
    fi

    git -C "$impl_repo" switch --quiet -c origin-topic main
    printf 'export const origin = true;\n' > "$impl_repo/src/origin.ts"
    git_fixture_commit "$impl_repo" 'origin topic'
    local origin_commit
    origin_commit="$(git -C "$impl_repo" rev-parse HEAD)"
    git -C "$impl_repo" switch --quiet main
    git -C "$impl_repo" branch -D origin-topic >/dev/null
    git -C "$impl_repo" update-ref refs/remotes/origin/feat/topic "$origin_commit"

    git_fixture_init "$quality_repo"
    printf 'quality fixture\n' > "$quality_repo/README.md"
    git_fixture_commit "$quality_repo" 'quality baseline'
    write_registry "$registry" "$product_root"
    write_manifest "$manifest"

    local output
    local rc
    set +e
    output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
    rc=$?
    set -e
    [ "$rc" -eq 1 ]
    AUDIT_OUTPUT="$output" EXPECTED_RELATION="$relation" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_BASELINE_INVALID", result
expected = os.environ["EXPECTED_RELATION"].replace("-", " ")
assert any(expected in message for message in result["diagnostics"]), result
'
  done
}

assert_local_ahead_dirty_worktree_is_allowed() {
  local case_root="$TEST_TEMP_ROOT/worktree-origin-local-ahead"
  local product_root="$case_root/product/TestProduct"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_app"
  local impl_worktree="$case_root/worktrees/impl-no1_app"
  local quality_worktree="$case_root/worktrees/quality-no1_app"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  local base_commit
  base_commit="$(git -C "$impl_repo" rev-parse HEAD)"
  mkdir -p "$(dirname "$impl_worktree")"
  git -C "$impl_repo" worktree add --quiet -b feat/topic "$impl_worktree" main
  printf 'export const topic = true;\n' > "$impl_worktree/src/topic.ts"
  git_fixture_commit "$impl_worktree" 'local topic'
  local topic_commit
  local topic_tree
  topic_commit="$(git -C "$impl_worktree" rev-parse HEAD)"
  topic_tree="$(git -C "$impl_worktree" show -s --format=%T HEAD)"
  printf 'export const dirty = true;\n' > "$impl_worktree/src/dirty.ts"
  git -C "$impl_repo" update-ref refs/remotes/origin/feat/topic "$base_commit"

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$topic_commit" \
    "$topic_tree"
  git_fixture_commit "$quality_repo" 'quality baseline'
  git -C "$quality_repo" worktree add --quiet -b feat/topic "$quality_worktree" main
  write_self_owned_registry "$registry" "$product_root"
  write_manifest "$manifest"

  local output
  local rc
  set +e
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  AUDIT_OUTPUT="$output" EXPECTED_WORKTREE="$impl_worktree" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_REFRESH_REQUIRED", result
assert result["impl_candidate"] == {
    "kind": "worktree",
    "path": os.environ["EXPECTED_WORKTREE"],
    "ref": "feat/topic",
}
assert result["impl_changes"]["untracked"] == ["src/dirty.ts"], result
assert not any("origin ahead" in message or "diverged" in message for message in result["diagnostics"]), result
'
}

assert_same_name_tag_cannot_shadow_branch_snapshot() {
  local case_root="$TEST_TEMP_ROOT/canonical-branch-ref"
  local product_root="$case_root/product/TestProduct"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_app"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  local base_commit
  local base_tree
  base_commit="$(git -C "$impl_repo" rev-parse HEAD)"
  base_tree="$(git -C "$impl_repo" show -s --format=%T HEAD)"
  git -C "$impl_repo" switch --quiet -c feat/topic
  printf 'export const topic = true;\n' > "$impl_repo/src/topic.ts"
  git_fixture_commit "$impl_repo" 'impl topic'
  local topic_commit
  local topic_tree
  topic_commit="$(git -C "$impl_repo" rev-parse HEAD)"
  topic_tree="$(git -C "$impl_repo" show -s --format=%T HEAD)"
  git -C "$impl_repo" switch --quiet main
  git -C "$impl_repo" tag feat/topic "$base_commit"

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$base_commit" \
    "$base_tree" \
    'old-only/'
  git_fixture_commit "$quality_repo" 'quality baseline'
  local quality_base_commit
  quality_base_commit="$(git -C "$quality_repo" rev-parse HEAD)"
  git -C "$quality_repo" switch --quiet -c feat/topic
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$topic_commit" \
    "$topic_tree" \
    'src/'
  git_fixture_commit "$quality_repo" 'quality topic'
  git -C "$quality_repo" switch --quiet main
  git -C "$quality_repo" tag feat/topic "$quality_base_commit"
  write_self_owned_registry "$registry" "$product_root"
  write_manifest "$manifest"

  local output
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  AUDIT_OUTPUT="$output" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_OK", result
assert result["impl_changes"]["committed"] == ["src/topic.ts"], result
assert result["changed_paths"] == ["src/topic.ts"], result
'
}

assert_short_base_ref_ignores_same_name_tag() {
  local case_root="$TEST_TEMP_ROOT/base-ref-tag-shadow"
  local product_root="$case_root/product/TestProduct"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_app"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  git -C "$impl_repo" switch --quiet -c feat/topic
  printf 'export const topic = true;\n' > "$impl_repo/src/topic.ts"
  git_fixture_commit "$impl_repo" 'impl topic'
  local topic_commit
  local topic_tree
  topic_commit="$(git -C "$impl_repo" rev-parse HEAD)"
  topic_tree="$(git -C "$impl_repo" show -s --format=%T HEAD)"
  git -C "$impl_repo" switch --quiet main
  git -C "$impl_repo" tag main "$topic_commit"

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$(git -C "$impl_repo" rev-parse refs/heads/main)" \
    "$(git -C "$impl_repo" show -s --format=%T refs/heads/main)" \
    'old-only/'
  git_fixture_commit "$quality_repo" 'quality baseline'
  git -C "$quality_repo" switch --quiet -c feat/topic
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$topic_commit" \
    "$topic_tree" \
    'src/'
  git_fixture_commit "$quality_repo" 'quality topic'
  local quality_topic_commit
  quality_topic_commit="$(git -C "$quality_repo" rev-parse HEAD)"
  git -C "$quality_repo" switch --quiet main
  git -C "$quality_repo" tag main "$quality_topic_commit"
  write_self_owned_registry "$registry" "$product_root"
  write_manifest "$manifest"

  local output
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  AUDIT_OUTPUT="$output" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_OK", result
assert result["impl_changes"]["committed"] == ["src/topic.ts"], result
assert result["changed_paths"] == ["src/topic.ts"], result
'
}

assert_short_base_ref_local_origin_mismatch_fails_closed() {
  local case_root="$TEST_TEMP_ROOT/base-ref-local-origin-mismatch"
  local product_root="$case_root/product/TestProduct"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_app"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  local local_main_commit
  local local_main_tree
  local_main_commit="$(git -C "$impl_repo" rev-parse refs/heads/main)"
  local_main_tree="$(git -C "$impl_repo" show -s --format=%T refs/heads/main)"
  git -C "$impl_repo" branch feat/topic main
  git -C "$impl_repo" switch --quiet -c remote-main main
  printf 'export const remote = true;\n' > "$impl_repo/src/remote.ts"
  git_fixture_commit "$impl_repo" 'remote main'
  local remote_main_commit
  remote_main_commit="$(git -C "$impl_repo" rev-parse HEAD)"
  git -C "$impl_repo" switch --quiet main
  git -C "$impl_repo" branch -D remote-main >/dev/null
  git -C "$impl_repo" update-ref refs/remotes/origin/main "$remote_main_commit"

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$local_main_commit" \
    "$local_main_tree"
  git_fixture_commit "$quality_repo" 'quality baseline'
  git -C "$quality_repo" branch feat/topic main
  write_self_owned_registry "$registry" "$product_root"
  write_manifest "$manifest"

  local output
  local rc
  set +e
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic main)"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  AUDIT_OUTPUT="$output" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_BASELINE_INVALID", result
assert any("source base ref main local and origin refs differ" in message for message in result["diagnostics"]), result
'
}

assert_explicit_tag_base_ref_is_accepted() {
  local case_root="$TEST_TEMP_ROOT/base-ref-explicit-tag"
  local product_root="$case_root/product/TestProduct"
  local impl_repo="$product_root/no5_product_development/no1_app"
  local quality_repo="$product_root/no6_product_quality/no1_app"
  local registry="$case_root/products_registry.md"
  local manifest="$case_root/layer_manifest.yaml"

  git_fixture_init "$impl_repo"
  mkdir -p "$impl_repo/src"
  printf 'export const base = 1;\n' > "$impl_repo/src/base.ts"
  git_fixture_commit "$impl_repo" 'impl baseline'
  git -C "$impl_repo" tag audit-base HEAD
  git -C "$impl_repo" switch --quiet -c feat/topic
  printf 'export const topic = true;\n' > "$impl_repo/src/topic.ts"
  git_fixture_commit "$impl_repo" 'impl topic'
  local topic_commit
  local topic_tree
  topic_commit="$(git -C "$impl_repo" rev-parse HEAD)"
  topic_tree="$(git -C "$impl_repo" show -s --format=%T HEAD)"
  git -C "$impl_repo" switch --quiet main

  git_fixture_init "$quality_repo"
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$(git -C "$impl_repo" rev-parse refs/tags/audit-base^{commit})" \
    "$(git -C "$impl_repo" show -s --format=%T refs/tags/audit-base^{commit})" \
    'old-only/'
  git_fixture_commit "$quality_repo" 'quality baseline'
  git -C "$quality_repo" tag audit-base HEAD
  git -C "$quality_repo" switch --quiet -c feat/topic
  write_quality_plan \
    "$quality_repo/no2_regression_plan/no0_index.md" \
    "$topic_commit" \
    "$topic_tree" \
    'src/'
  git_fixture_commit "$quality_repo" 'quality topic'
  git -C "$quality_repo" switch --quiet main
  write_self_owned_registry "$registry" "$product_root"
  write_manifest "$manifest"

  local output
  output="$(run_audit "$registry" "$manifest" TestProduct no1_app feat/topic refs/tags/audit-base)"
  AUDIT_OUTPUT="$output" python3 -c '
import json
import os

result = json.loads(os.environ["AUDIT_OUTPUT"])
assert result["status"] == "QUALITY_OK", result
assert result["impl_changes"]["committed"] == ["src/topic.ts"], result
'
}

assert_matching_worktree_collects_all_change_kinds
assert_same_name_branch_is_a_candidate
assert_worktree_head_is_the_candidate_commit
assert_none_owner_is_not_applicable
assert_invalid_owner_fails_closed
assert_missing_topic_does_not_fall_back_to_main
assert_baseline_invalid_variant missing-row
assert_baseline_invalid_variant missing-object
assert_baseline_invalid_variant tree-mismatch
assert_baseline_invalid_variant non-ancestor
assert_unmapped_path_is_a_mapping_gap
assert_divergent_quality_candidate_invalidates_baseline
assert_path_with_spaces_survives_nul_protocol
assert_committed_rename_includes_both_paths
assert_installed_symlink_uses_resolver_defaults
assert_worktree_path_with_newline_uses_nul_protocol
assert_invalid_utf8_filename_produces_valid_json
assert_duplicate_baseline_row_fails_closed
assert_annotated_tag_object_is_not_a_baseline_commit
assert_missing_repo_is_a_baseline_failure source
assert_missing_repo_is_a_baseline_failure quality
assert_malformed_config_returns_single_json registry
assert_malformed_config_returns_single_json manifest
assert_candidate_git_error_is_a_baseline_failure
assert_remote_only_ref_is_a_branch_candidate
assert_staged_rename_includes_both_paths
assert_local_and_origin_topic_mismatch_fails_closed
assert_shared_owner_requires_repo_aware_mapping
assert_spec_without_topic_uses_explicit_base_baseline
assert_spec_topic_diff_requires_refresh
assert_spec_topic_without_diff_accepts_matching_baseline
assert_matching_worktree_rejects_origin_ahead_or_diverged
assert_local_ahead_dirty_worktree_is_allowed
assert_same_name_tag_cannot_shadow_branch_snapshot
assert_short_base_ref_ignores_same_name_tag
assert_short_base_ref_local_origin_mismatch_fails_closed
assert_explicit_tag_base_ref_is_accepted

printf 'quality alignment audit tests passed\n'
