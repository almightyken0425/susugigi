#!/bin/bash
# capability-probe.sh
# SessionStart hook
#
# 開 session 時實測回歸驗證手段的就緒狀態，缺項當場報、附修復指令。
# 對應規則：test_plan_writer 的 capability_profile「就緒探測表」。
#
# 為什麼要有：回歸計劃的手段條件寫在文件裡，但文件不會自己實測。
# 過去的失效樣態是排好整輪才在第一列撞牆——node_modules 被刪穿、CLI 沒裝。
# 本 hook 把那個撞牆時點提前到開 session 的第一秒。
#
# 噪音政策：全部就緒時完全靜默。只在有缺口時輸出，讓輸出恆為真警報。
# 探測一律零副作用：只做檔案系統存在性判定與 command -v，不安裝、不寫檔、不跑 build。
#
# Bypass：CODEX_SKIP_CAPABILITY_PROBE=1
# 相容別名：CLAUDE_SKIP_CAPABILITY_PROBE=1

HDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HDIR/lib/common.sh"

if [ "${CODEX_SKIP_CAPABILITY_PROBE:-${CLAUDE_SKIP_CAPABILITY_PROBE:-}}" = "1" ]; then
    exit 0
fi

INPUT=$(cat)
hook_init || exit 0

# Scope 只由產品註冊資料與 Git 身分決定。目錄名稱本身不代表 ai-company。
cwd="$HOOK_CWD"
[ -n "$cwd" ] || cwd=$(hook_norm_path "$(pwd)")
scope_helper="$HDIR/lib/company-context.py"
if command -v cygpath >/dev/null 2>&1; then
    scope_helper=$(cygpath -m "$scope_helper") || exit 0
fi
scope=$(PYTHONDONTWRITEBYTECODE=1 python3 -B "$scope_helper" capability "$cwd" 2>/dev/null) || exit 0
[ -n "$scope" ] || exit 0
case "$scope" in
    *$'\n'*)
        AICO=${scope%%$'\n'*}
        IMPL_ROOTS=${scope#*$'\n'}
        ;;
    *)
        AICO=$scope
        IMPL_ROOTS=""
        ;;
esac

gaps=""
add_gap() {
    if [ -n "$gaps" ]; then
        gaps="$gaps
- $1"
    else
        gaps="- $1"
    fi
}

# 1. jest 就緒：逐個有 package.json 的 impl 目錄，判 node_modules 內 jest 是否在位。
#    只看目錄存在性、不 spawn node——SessionStart 要秒回。
while IFS= read -r impl_root; do
    [ -n "$impl_root" ] || continue
    for pkg in "$impl_root/package.json" "$impl_root/functions/package.json"; do
        [ -f "$pkg" ] || continue
        d=$(dirname "$pkg")
        grep -q '"jest"' "$pkg" 2>/dev/null || continue
        label="${d#"$AICO"/}"
        if [ ! -d "$d/node_modules" ]; then
            add_gap "jest 不可跑：$label 無 node_modules。修：cd 該目錄跑 npm ci"
        elif [ ! -d "$d/node_modules/jest" ] || [ ! -d "$d/node_modules/@jest" ]; then
            add_gap "jest 不可跑：$label 的 node_modules 缺 jest 套件（常見於 worktree junction 被連帶刪穿）。修：cd 該目錄跑 npm ci --legacy-peer-deps"
        fi
    done
done <<EOF
$IMPL_ROOTS
EOF

# 2. 平台：manual-ui 與 qa-markers 需 Darwin。非 Mac 只是事實陳述、不是待補項，
#    所以只在存在其他缺口時才附帶一行，不單獨觸發輸出。
plat=$(uname -s 2>/dev/null)

# 3. firebase CLI：firestore-read 與 cloud-logging 的前提。
#    只在 Mac 上算缺口——Windows 不裝是既定決議（見各 Quality git 的能力側寫）。
if [ "$plat" = "Darwin" ] && ! command -v firebase >/dev/null 2>&1; then
    add_gap "firestore-read 與 cloud-logging 不可跑：firebase CLI 未安裝。修：npm i -g firebase-tools 後 firebase login"
fi

[ -n "$gaps" ] || exit 0

note=""
if [ "$plat" != "Darwin" ]; then
    note="
本機非 Mac：manual-ui 與 qa-markers 本來就不成立，手動場次一律在 Mac 側跑。"
fi

hook_ctx_add "[能力探測] 回歸驗證手段有缺口，開跑前先補：

$gaps
$note
權威狀態在各 Quality git 的 no1_capability_profile.md 就緒探測表。上面是本機實測結果。"

hook_emit SessionStart
exit 0
