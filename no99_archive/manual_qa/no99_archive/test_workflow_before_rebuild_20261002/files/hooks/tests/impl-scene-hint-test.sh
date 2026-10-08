#!/bin/bash
# impl-scene-hint-test.sh
# 鎖住 guard_multi_tier_sync 的 impl 分支場次點名（_mts_scene_hint）。
#
# 背景：改 impl 時，guard 會查該 module 計劃索引的「路徑映射表」，點名這次動到哪一冊、
# 哪幾場。這條的價值全在準確——點錯冊比不點還糟，而它的失效樣態全是安靜的：
#   - 路徑被小寫化後比不上駝峰前綴 → 每次都誤報「未登記」，久了沒人看
#   - 表內前綴自帶結尾星號，比對時被當字面字元 → 同上
#   - 場次串接用 tr 接全形頓號 → 逐 byte 替換、輸出亂碼
# 三個都真的踩過。本檔就是那個會變紅的測試。
#
# 受測對象相對本檔定位，從哪個 worktree 跑就測哪一份。

set -u
H=$(cd "$(dirname "$0")/.." && pwd)
if [ "${CODEX_HINT_FIXTURE_ACTIVE:-}" != 1 ]; then
  exec python3 -B "$H/tests/hint_fixture.py" "$0"
fi
GUARD="$H/multi-tier-sync-guard.sh"
PASS=0; FAIL=0

AICO="$HOME/Doc/ai-company"
IMPL="$AICO/product/susugigi/no5_product_development/no2_accounting_app"
WT="$HOME/Doc/ai-company-worktrees/probe/impl-no2-accounting-app"

payload() {
  printf '{"hook_event_name":"PostToolUse","tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s"}}' \
    "$AICO" "$1"
}

run() { printf '%s' "$(payload "$1")" | bash "$GUARD" 2>/dev/null; }

# 斷言輸出「含」某字串
has() {
  local name="$1" path="$2" needle="$3" out
  out=$(run "$path")
  if printf '%s' "$out" | grep -qF "${needle}"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); echo "  FAIL [HAS] $name — 輸出不含「${needle}」"
    echo "    got: $(printf '%s' "$out" | tail -c 200)"
  fi
}

# 斷言輸出「不含」某字串
lacks() {
  local name="$1" path="$2" needle="$3" out
  out=$(run "$path")
  if printf '%s' "$out" | grep -qF "${needle}"; then
    FAIL=$((FAIL+1)); echo "  FAIL [LACKS] $name — 輸出不該含「${needle}」"
    echo "    got: $(printf '%s' "$out" | tail -c 200)"
  else
    PASS=$((PASS+1))
  fi
}

echo "=== 命中：點名區碼與場次 ==="
has "quotaService → CS 冊"       "$IMPL/src/services/quotaService.ts"        "CS 冊"
has "quotaService → R08"          "$IMPL/src/services/quotaService.ts"        "R08"
has "quotaService → R03"          "$IMPL/src/services/quotaService.ts"        "R03"
has "HomeScreen → HD 冊"          "$IMPL/src/screens/Home/HomeScreen.tsx"     "HD 冊"
has "schema.ts → LD 冊"           "$IMPL/src/database/schema.ts"              "LD 冊"
has "AuthContext → AU 冊"         "$IMPL/src/contexts/AuthContext.tsx"        "AU 冊"

echo "=== 場次分隔符不得亂碼（曾被 tr 逐 byte 切壞）==="
has "場次以全形頓號相接"          "$IMPL/src/services/quotaService.ts"        "R00、R03"
lacks "無替換字元"                "$IMPL/src/services/quotaService.ts"        "�"

echo "=== 未登記路徑要出聲 ==="
has "未登記路徑點名"              "$IMPL/src/utils/notInTheMapAtAll.ts"       "未登記"
lacks "未登記時不亂點冊"          "$IMPL/src/utils/notInTheMapAtAll.ts"       "冊，受影響場次"

echo "=== 虛構 worktree 不再用資料夾名稱猜產品 ==="
lacks "未註冊 worktree 不點冊"    "$WT/src/services/quotaService.ts"          "冊，受影響場次"
lacks "未註冊 worktree 不猜產品"  "$WT/src/services/quotaService.ts"          "SuSuGiGi"

echo "=== 無 Quality git 的 module 不受影響 ==="
HAT="$AICO/product/hatsuon/no5_product_development/no1_pronunciation_app"
lacks "Hatsuon 不點場次"          "$HAT/src/services/whatever.ts"             "受影響場次"
lacks "Hatsuon 不報未登記"        "$HAT/src/services/whatever.ts"             "未登記"
has   "Hatsuon 仍有原本提醒"      "$HAT/src/services/whatever.ts"             "Module Impl"

echo "=== 非 impl 路徑零影響 ==="
SPEC="$AICO/product/susugigi/no3_product_specs/no2_accounting_app/no3_logics/no1_app_bootstrap_logic.md"
QUAL="$AICO/product/susugigi/no6_product_quality/no2_accounting_app/no1_capability_profile.md"
lacks "spec 檔不點場次"           "$SPEC"                                     "受影響場次"
lacks "quality 檔不點場次"        "$QUAL"                                     "受影響場次"
has   "spec 檔仍有原本提醒"       "$SPEC"                                     "Module Spec"
has   "quality 檔仍有原本提醒"    "$QUAL"                                     "Module Quality"

echo "=== 直接測項欄精準點名 ==="
SCENE_POLICY="$H/lib/contextual-guard-policy.py"
DIRECT_TMP="$(mktemp -d)"
DIRECT_HOME="$DIRECT_TMP/home"
DIRECT_QUALITY="$DIRECT_HOME/Doc/ai-company/product/susugigi/no6_product_quality/no2_accounting_app"
mkdir -p "$DIRECT_QUALITY/no2_regression_plan" "$DIRECT_QUALITY/no3_run_scripts"
trap 'rm -rf "$DIRECT_TMP"' EXIT INT TERM

cat > "$DIRECT_QUALITY/no2_regression_plan/no0_index.md" <<'INDEX'
## 路徑映射表

| impl 路徑前綴 | 區碼 | 直接測項 |
| --- | --- | --- |
| `src/services/localDbService*` | LD | |
| `src/services/localDbService.qaReset.test.ts` | QA | `CS-02`、`HD-07`、`RC-06` |
| `src/qa/` | QA | `CS-02` |
| `src/qa/registerQaRuntime.ts` | QA | `HD-07`、`RC-06` |
| `index.qa.js`、`ios/scripts/select-firebase-config.sh`、`ios/SuSuGiGiApp/BuildEnvironmentModule.m` | QA | `CS-02`、`HD-07`、`RC-06` |
| `src/services/coarseOnly*` | LD | |
INDEX

cat > "$DIRECT_QUALITY/no3_run_scripts/no5_r03_direct.csv" <<'CSV'
序,測項
1,CS-02
CSV
cat > "$DIRECT_QUALITY/no3_run_scripts/no8_r06_direct.csv" <<'CSV'
序,測項
1,HD-07
CSV
cat > "$DIRECT_QUALITY/no3_run_scripts/no9_r07_direct.csv" <<'CSV'
序,測項
1,RC-06
CSV
cat > "$DIRECT_QUALITY/no3_run_scripts/no99_r99_broad.csv" <<'CSV'
序,測項
1,CS-99
2,HD-99
3,RC-99
CSV
cat > "$DIRECT_QUALITY/no3_run_scripts/no10_r08_case_prefix.csv" <<'CSV'
序,測項,說明
1,CS-020,不得誤命中 CS-02
CSV
cat > "$DIRECT_QUALITY/no3_run_scripts/no11_r09_description_only.csv" <<'CSV'
序,測項,說明
1,,說明欄提到 CS-02 不代表本列測項
CSV
cat > "$DIRECT_QUALITY/no3_run_scripts/no12_r10_coarse_fallback.csv" <<'CSV'
序,測項
1,LD-01
CSV
cat > "$DIRECT_QUALITY/no3_run_scripts/no16_r14_verified.csv" <<'CSV'
序,測項,已驗
1,,CS-02 由已驗欄承載
CSV

direct_hint() {
  python3 -B - "$SCENE_POLICY" "$DIRECT_HOME" "$1" <<'PY'
import os
from pathlib import Path
import runpy
import sys
from types import SimpleNamespace

policy, fixture_home, target = sys.argv[1:]
namespace = runpy.run_path(policy)
root = Path(fixture_home)
canonical = root / "Doc/ai-company/product/susugigi/no5_product_development/no2_accounting_app"
quality = root / "Doc/ai-company/product/susugigi/no6_product_quality/no2_accounting_app"
target_path = Path(target)
if target_path.is_relative_to(canonical):
    repo = canonical
else:
    topic = root / "Doc/ai-company-worktrees/topic"
    repo = topic / target_path.relative_to(topic).parts[0]

class Registry:
    def quality_repository_record(self, product, module):
        return SimpleNamespace(canonical_root=str(quality), worktree_prefix="quality")

    def worktree_label(self, product, module, layer):
        return "quality-no2-accounting-app"

    def resolve_path(self, candidate, expected_layer):
        if os.environ.get("DIRECT_REJECT_TOPIC") == "1":
            return SimpleNamespace(status="unregistered", matches=())
        return SimpleNamespace(status="resolved", matches=(
            SimpleNamespace(product_id="susugigi", module_id="no2_accounting_app", repo_root=str(candidate)),
        ))

print(namespace["_scene_hint"](Registry(), {
    "product_id": "susugigi",
    "module_id": "no2_accounting_app",
    "relative_path": target_path.relative_to(repo).as_posix(),
    "repo_root": str(repo),
    "canonical_root": str(canonical),
}))
PY
}

direct_has() {
  local name="$1" path="$2" needle="$3" out
  out=$(direct_hint "$path")
  if printf '%s' "$out" | grep -qF "$needle"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1)); echo "  FAIL [DIRECT HAS] $name — 輸出不含「${needle}」"
    echo "    got: $out"
  fi
}

direct_lacks() {
  local name="$1" path="$2" needle="$3" out
  out=$(direct_hint "$path")
  if printf '%s' "$out" | grep -qF "$needle"; then
    FAIL=$((FAIL + 1)); echo "  FAIL [DIRECT LACKS] $name — 輸出不該含「${needle}」"
    echo "    got: $out"
  else
    PASS=$((PASS + 1))
  fi
}

DIRECT_MAIN="$DIRECT_HOME/Doc/ai-company/product/susugigi/no5_product_development/no2_accounting_app"
DIRECT_WORKTREE="$DIRECT_HOME/Doc/ai-company-worktrees/topic/impl-no2-accounting-app"

direct_has "src/qa 精準測項" "$DIRECT_MAIN/src/qa/registerQaRuntime.ts" "CS-02、HD-07、RC-06"
direct_has "src/qa 場次聯集" "$DIRECT_MAIN/src/qa/registerQaRuntime.ts" "R03、R06、R07"
direct_has "direct case 同時掃已驗欄" "$DIRECT_MAIN/src/qa/registerQaRuntime.ts" "R14"
direct_lacks "src/qa 不放大整冊" "$DIRECT_MAIN/src/qa/registerQaRuntime.ts" "R99"
direct_has "多個 direct 列取精確聯集" "$DIRECT_MAIN/src/qa/registerQaRuntime.ts" "CS-02、HD-07、RC-06"
direct_has "實檔重疊時 direct 優先" "$DIRECT_MAIN/src/services/localDbService.qaReset.test.ts" "CS-02、HD-07、RC-06"
direct_has "實檔重疊時場次取 direct 聯集" "$DIRECT_MAIN/src/services/localDbService.qaReset.test.ts" "R03、R06、R07"
direct_lacks "實檔重疊不落較早粗篩" "$DIRECT_MAIN/src/services/localDbService.qaReset.test.ts" "LD 冊"
direct_lacks "實檔重疊不放大粗篩場次" "$DIRECT_MAIN/src/services/localDbService.qaReset.test.ts" "R10"
direct_has "全部 direct 空白才走粗篩" "$DIRECT_MAIN/src/services/coarseOnlyService.ts" "LD 冊"
direct_has "粗篩 fallback 場次" "$DIRECT_MAIN/src/services/coarseOnlyService.ts" "R10"
direct_has "iOS script 精準測項" "$DIRECT_WORKTREE/ios/scripts/select-firebase-config.sh" "CS-02、HD-07、RC-06"
direct_has "iOS script 場次聯集" "$DIRECT_WORKTREE/ios/scripts/select-firebase-config.sh" "R03、R06、R07"
direct_has "QA entry 精準測項" "$DIRECT_MAIN/index.qa.js" "CS-02、HD-07、RC-06"
direct_has "QA entry 場次聯集" "$DIRECT_MAIN/index.qa.js" "R03、R06、R07"
direct_lacks "QA entry 不誤命中 CS-020" "$DIRECT_MAIN/index.qa.js" "R08"
direct_lacks "QA entry 不掃說明欄" "$DIRECT_MAIN/index.qa.js" "R09"
direct_has "iOS build environment 精準測項" "$DIRECT_WORKTREE/ios/SuSuGiGiApp/BuildEnvironmentModule.m" "CS-02、HD-07、RC-06"
direct_has "iOS build environment 場次聯集" "$DIRECT_WORKTREE/ios/SuSuGiGiApp/BuildEnvironmentModule.m" "R03、R06、R07"

echo "=== coarse mapping 零場次要出聲 ==="
printf '%s\n' '| `src/services/noScene*` | XX | |' >> "$DIRECT_QUALITY/no2_regression_plan/no0_index.md"
direct_has "coarse mapping 零場次" "$DIRECT_MAIN/src/services/noSceneService.ts" "未找到承載場次"

echo "=== 同 topic Quality worktree 優先 ==="
DIRECT_TOPIC_QUALITY="$DIRECT_HOME/Doc/ai-company-worktrees/topic/quality-no2-accounting-app"
mkdir -p "$DIRECT_TOPIC_QUALITY/no2_regression_plan" "$DIRECT_TOPIC_QUALITY/no3_run_scripts"
cat > "$DIRECT_TOPIC_QUALITY/no2_regression_plan/no0_index.md" <<'TOPIC_INDEX'
## 路徑映射表

| impl 路徑前綴 | 區碼 | 直接測項 |
| --- | --- | --- |
| `src/services/topicOnly*` | QA | `ZZ-01` |
TOPIC_INDEX
cat > "$DIRECT_TOPIC_QUALITY/no3_run_scripts/no16_r14_topic.csv" <<'TOPIC_CSV'
序,測項,已驗
1,ZZ-01,
TOPIC_CSV
direct_has "同 topic Quality worktree 的直接測項" "$DIRECT_WORKTREE/src/services/topicOnlyService.ts" "ZZ-01"
direct_has "同 topic Quality worktree 的場次" "$DIRECT_WORKTREE/src/services/topicOnlyService.ts" "R14"

direct_has "legacy worktree 仍命中 canonical Quality" "$DIRECT_HOME/Doc/ai-company-worktrees/topic/impl-no2_accounting_app/src/services/topicOnlyService.ts" "ZZ-01"
DIRECT_REJECT_TOPIC=1 direct_lacks "未註冊同名目錄不採用" "$DIRECT_WORKTREE/src/services/topicOnlyService.ts" "ZZ-01"
DIRECT_REJECT_TOPIC=1 direct_has "未註冊同名目錄回查主 Quality" "$DIRECT_WORKTREE/src/services/topicOnlyService.ts" "未登記"

rm -rf "$DIRECT_TMP"
trap - EXIT INT TERM

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
