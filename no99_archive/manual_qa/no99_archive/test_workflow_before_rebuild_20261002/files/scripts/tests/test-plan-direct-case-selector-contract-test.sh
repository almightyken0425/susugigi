#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GENERATION="$TEST_ROOT/references/quality/generation_procedure.md"
PLAN_FORMAT="$TEST_ROOT/references/quality/plan_format.md"

PASS=0
FAIL=0

has_literal() {
  local name="$1"
  local file="$2"
  local literal="$3"

  if grep -Fq -- "$literal" "$file"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL $name"
    echo "    missing: $literal"
  fi
}

echo "=== Direct-case selector authority ==="
has_literal "路徑映射表定義第三欄" "$PLAN_FORMAT" '| impl 路徑前綴 | 區碼 | 直接測項 |'
has_literal "第三欄只接受 exact case ID" "$PLAN_FORMAT" '直接測項只接受既有 case ID 的完整值。'
has_literal "第三欄多值分隔" "$PLAN_FORMAT" '多個直接測項使用頓號分隔。'
has_literal "第三欄必須驗存在" "$PLAN_FORMAT" '每個直接測項都必須存在於測項總表。'
has_literal "全部空第三欄才粗篩" "$PLAN_FORMAT" '全部命中列的直接測項皆為空時使用區碼粗篩。'
has_literal "路徑前綴允許重疊" "$PLAN_FORMAT" '同一路徑可命中多個路徑映射列。'
has_literal "多列 direct 聯集" "$PLAN_FORMAT" '多個命中列的直接測項取精確聯集並排序去重。'
has_literal "direct 跨列優先" "$PLAN_FORMAT" '任一命中列有直接測項時，忽略所有命中列的區碼粗篩。'

has_literal "direct case 優先" "$GENERATION" '路徑映射命中直接測項時優先精確選案。'
has_literal "direct case 驗存在" "$GENERATION" '每個直接測項必須先驗證 case ID 存在。'
has_literal "direct case 展開依賴" "$GENERATION" '精確選案後展開必要前置鏈。'
has_literal "direct case 缺漏 fail closed" "$GENERATION" '任一直接測項不存在時 selector 停止。'
has_literal "selector 收集所有映射列" "$GENERATION" '每個差異路徑必須收集所有命中的映射列。'
has_literal "selector 多列 direct 聯集" "$GENERATION" '多個命中列的直接測項取精確聯集並排序去重。'
has_literal "selector direct 跨列優先" "$GENERATION" '任一命中列有直接測項時，忽略所有命中列的區碼粗篩。'
has_literal "selector 全空才 fallback" "$GENERATION" '只有全部命中列的直接測項皆為空時，才使用區碼粗篩。'

echo "=== Scene carrier and partial-block authority ==="
has_literal "場次同時讀測項與已驗" "$PLAN_FORMAT" '場次承載關係同時讀取 CSV 的 `測項` 與 `已驗` 欄。'
has_literal "零承載場次 fail closed" "$PLAN_FORMAT" '測項沒有承載場次時必須停止。'
has_literal "阻斷場次不擴大" "$PLAN_FORMAT" '阻斷場次只記錄 `blocked`，不得阻斷同一選集的安全場次。'
has_literal "tier 可部分受阻" "$PLAN_FORMAT" '任一 tier 可同時展開安全場次與阻斷場次。'
has_literal "selector 展開完整承載關係" "$GENERATION" '選完 case 後展開每個 case 的全部承載場次。'
has_literal "selector 分流安全場次" "$GENERATION" '安全場次繼續進入 runtime route。'
has_literal "selector 分流阻斷場次" "$GENERATION" '阻斷場次只產生 `blocked` 結果。'
has_literal "selector 零場次停止" "$GENERATION" '任一 selected case 沒有承載場次時停止。'

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
