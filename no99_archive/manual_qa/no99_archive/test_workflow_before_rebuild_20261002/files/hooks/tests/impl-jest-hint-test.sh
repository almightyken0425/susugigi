#!/bin/bash
# impl-jest-hint-test.sh
# 鎖住 guard_multi_tier_sync 的 impl 分支測試點名（_mts_jest_hint）。
#
# 背景：impl 有近百支 jest 測試檔，卻沒有任何機制管它們。改完 code 跑不跑全靠當下
# 記得。guard 現在會在改 src/ 原始碼時點名同 stem 的測試檔、附可直接跑的指令。
#
# 這條的失效樣態全是安靜的：
#   - stem 後少了那個字面點 → currencyUtilsExtra.test.ts 被 currencyUtils.ts 誤認領
#   - 只掃單一副檔名 → .tsx 原始碼配 .ts 測試（或反過來）整批漏點
#   - 沒有測試檔時也出聲 → 每個 UI 檔都喊一次，訓練出無視
#   - 被塞進 _mts_scene_hint 的 Quality git 早退之後 → 沒有回歸計劃的 module 全啞
# 本檔就是那個會變紅的測試。
#
# 刻意不鎖精確支數（測試會長出來）。只鎖指令字串與「不只一支」。
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
HAT="$AICO/product/hatsuon/no5_product_development/no1_pronunciation_app"

payload() {
  printf '{"hook_event_name":"PostToolUse","tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s"}}' \
    "$AICO" "$1"
}

run() { printf '%s' "$(payload "$1")" | bash "$GUARD" 2>/dev/null; }

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

echo "=== 命中：點名測試並給可跑指令 ==="
has "單支 .ts 測試"        "$IMPL/src/contexts/preferenceNormalize.ts" "npx jest src/contexts/preferenceNormalize"
has "多支 .ts 測試"        "$IMPL/src/utils/currencyUtils.ts"          "npx jest src/utils/currencyUtils"
has "多支 .tsx 測試"       "$IMPL/src/contexts/AuthContext.tsx"        "npx jest src/contexts/AuthContext"
has "同目錄不同 stem"      "$IMPL/src/utils/dateMs.ts"                 "npx jest src/utils/dateMs"

echo "=== 支數要真的數，不是一律報一支 ==="
lacks "currencyUtils 非單支" "$IMPL/src/utils/currencyUtils.ts"        "有 1 支"
lacks "AuthContext 非單支"   "$IMPL/src/contexts/AuthContext.tsx"      "有 1 支"

echo "=== 沒有測試檔就閉嘴（與場次點名刻意相反）==="
lacks "無測試的 util"      "$IMPL/src/utils/sortOrder.ts"              "對應測試"
lacks "無測試的 context"   "$IMPL/src/contexts/DebugUnlockContext.tsx" "對應測試"

echo "=== stem 後那個字面點要防前綴誤配 ==="
lacks "currencyUtilsExtra 不被認領" "$IMPL/src/utils/currencyUtilsExtra.ts" "對應測試"
lacks "dateMsHelper 不被認領"       "$IMPL/src/utils/dateMsHelper.ts"       "對應測試"

echo "=== 改的是測試檔本身、或非 TS 原始碼，都不點名 ==="
lacks "改 .test.ts 本身"   "$IMPL/src/contexts/preferenceNormalize.test.ts" "對應測試"
lacks "改 .test.tsx 本身"  "$IMPL/src/contexts/UndoContext.test.tsx"        "對應測試"
lacks "改 .spec.ts 本身"   "$IMPL/src/utils/whatever.spec.ts"               "對應測試"
lacks "非 TS 檔"           "$IMPL/src/assets/logo.png"                      "對應測試"

echo "=== src/ 以外的 impl 檔零影響 ==="
lacks "package.json 不點名" "$IMPL/package.json"                       "對應測試"
has   "package.json 仍有原本提醒" "$IMPL/package.json"                  "Module Impl"

echo "=== 虛構 worktree 不再用資料夾名稱猜產品 ==="
lacks "未註冊 worktree 不點場次"      "$WT/src/services/quotaService.ts"  "受影響場次"
lacks "未註冊 worktree 不點測試"      "$WT/src/utils/currencyUtils.ts"     "對應測試"

echo "=== 場次點名與測試點名並存、互不吃掉 ==="
has "quotaService 有場次"  "$IMPL/src/services/quotaService.ts"        "受影響場次"
has "quotaService 有測試"  "$IMPL/src/services/quotaService.ts"        "npx jest src/services/quotaService"

echo "=== 非 impl 路徑零影響 ==="
SPEC="$AICO/product/susugigi/no3_product_specs/no2_accounting_app/no3_logics/no1_app_bootstrap_logic.md"
QUAL="$AICO/product/susugigi/no6_product_quality/no2_accounting_app/no1_capability_profile.md"
lacks "spec 檔不點測試"    "$SPEC"                                     "對應測試"
lacks "quality 檔不點測試" "$QUAL"                                     "對應測試"

echo "=== 無 Quality git 的 module 一樣要點名 ==="
# 測試點名不得依賴回歸計劃在場。Hatsuon 現無測試檔，臨時鋪一對探針再收掉。
# trap 保證中斷、失敗、正常結束都清乾淨——這是別人的 repo，不留渣。
PROBE_SRC="$HAT/src/__jestHintProbe.ts"
PROBE_TEST="$HAT/src/__jestHintProbe.someCase.test.ts"
probe_cleanup() { rm -f "$PROBE_SRC" "$PROBE_TEST"; }
trap probe_cleanup EXIT INT TERM

if [ -d "$HAT/src" ] && [ ! -e "$PROBE_SRC" ] && [ ! -e "$PROBE_TEST" ]; then
  : > "$PROBE_SRC"; : > "$PROBE_TEST"
  has   "Hatsuon 點名測試"   "$PROBE_SRC" "npx jest src/__jestHintProbe"
  lacks "Hatsuon 不點場次"   "$PROBE_SRC" "受影響場次"
  lacks "Hatsuon 不報未登記" "$PROBE_SRC" "未登記"
  probe_cleanup
else
  echo "  SKIP: Hatsuon 無 src/ 或探針檔名已被佔用，跳過本組三案"
fi

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
