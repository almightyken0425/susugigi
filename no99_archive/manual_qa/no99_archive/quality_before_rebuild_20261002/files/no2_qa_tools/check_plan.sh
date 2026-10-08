#!/bin/bash
# check_plan.sh — 回歸測試計劃的唯讀對帳檢核器。
#
# 只讀不寫。不產生、不修改任何計劃檔，也不推導任何內容。它做的事是把
# `test_plan_writer` 場次腳本格式裡那組 grep 配方變成可重跑的一支指令，
# 讓「對帳」從每次手工複製貼上六段 shell，變成跑一次看綠燈。
#
# 為什麼需要：241 個檢查點的雙向比對靠人工複製配方跑，最大的風險不是跑錯，
# 是「這次沒跑」。而漂移的失效樣態全是安靜的——腳本引句被改一個字、
# 測試檔改名、marker 命名空間不存在，全都不會有人發現，直到執行當場撞牆。
#
# 用法：
#   bash no2_qa_tools/check_plan.sh                 # 在 quality git 根目錄跑
#   bash no2_qa_tools/check_plan.sh --impl <path>   # 指定 app impl 路徑
#   bash no2_qa_tools/check_plan.sh --backend <path> # 指定後端 functions 路徑
#   bash no2_qa_tools/check_plan.sh --selftest      # 驗檢核器自己抓不抓得到問題
#
# 退出碼：0 全過；1 有失配；2 用法或路徑錯誤。

set -u

PLAN_DIR="no2_regression_plan"
SCRIPT_DIR="no3_run_scripts"
IMPL=""
BACKEND=""
RUNTIME_CONTROL=""
PROFILE="no1_capability_profile.md"
SELFTEST=0
FAIL_LOG=""
SELFTEST_WORKER=""
SELFTEST_BARRIER=""
CANONICAL_QA_FIREBASE_CONFIG_SHA256="8a349abb287abc45a2e4ad868d1fd93b373f4f878fe03aa4e805e97c31ac489f"

while [ $# -gt 0 ]; do
    case "$1" in
        --impl) IMPL="${2:-}"; shift 2 ;;
        --backend) BACKEND="${2:-}"; shift 2 ;;
        --runtime-control) RUNTIME_CONTROL="${2:-}"; shift 2 ;;
        --selftest) SELFTEST=1; shift ;;
        --selftest-worker)
            SELFTEST_WORKER="${2:-}"
            SELFTEST_BARRIER="${3:-}"
            shift 3
            ;;
        *) echo "未知參數：$1"; exit 2 ;;
    esac
done

CHECK_TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/susugigi-check-plan.XXXXXX") || {
    echo "無法建立私有 scratch 目錄"
    exit 2
}
CHECK_TMP_PREFIX="$CHECK_TMP_ROOT/cp"
trap 'rm -rf "$CHECK_TMP_ROOT"' EXIT HUP INT TERM

fail_count=0
note() { printf '%s\n' "$*"; }
pass() { printf '  ✓ %s\n' "$*"; }
fail() {
    printf '  ✗ %s\n' "$*"
    if [ -n "$FAIL_LOG" ]; then
        printf '%s\n' "$*" >> "$FAIL_LOG"
    fi
    fail_count=$((fail_count + 1))
}

if [ -n "$SELFTEST_WORKER" ]; then
    [ -d "$SELFTEST_BARRIER" ] || exit 2
    printf '%s\n' "$SELFTEST_WORKER" > "${CHECK_TMP_PREFIX}_parallel_sentinel.txt"
    : > "$SELFTEST_BARRIER/$SELFTEST_WORKER.ready"
    attempts=0
    while [ "$(find "$SELFTEST_BARRIER" -type f -name '*.ready' | wc -l | tr -d ' ')" -lt 2 ]; do
        attempts=$((attempts + 1))
        [ "$attempts" -lt 200 ] || exit 1
        sleep 0.01
    done
    actual_worker=$(sed -n '1p' "${CHECK_TMP_PREFIX}_parallel_sentinel.txt")
    if [ "$actual_worker" != "$SELFTEST_WORKER" ]; then
        printf 'selftest parallel scratch collision：%s 讀到 %s\n' "$SELFTEST_WORKER" "$actual_worker"
        exit 1
    fi
    exit 0
fi

# ── 抽取：兩側清單 ──
# 已驗欄為第八欄，多值以全形分號連接。分號切分一律 sed，禁用 tr——
# tr 逐 byte 處理，會把全形逗號一併切斷、產出截斷字串與亂碼。
extract_verified() {
    awk -F, 'FNR>1{print $8}' "$1"/no*_r*.csv 2>/dev/null \
        | sed 's/；/\n/g; s/^ *//; s/ *$//' \
        | grep -E "^[A-Z]{2}-[0-9]+" | sort -u
}

# 分冊側同樣切在第一個分號前——引句規則就是這樣取的，兩側不同樣正規化
# 會讓含分號的斷言正反向各誤報一筆。
extract_assertions() {
    awk '/^## [A-Z]{2}-[0-9]+/{id=$2}
         /^    - \*\*/{a=$0; sub(/^    - \*\*/,"",a); sub(/\*\*$/,"",a); print id" "a}' \
        "$1"/no[0-9]*.md 2>/dev/null | sed 's/；.*//' | sort -u
}

# 覆蓋例外表的檢查點欄。表頭與分隔列排除。
extract_exceptions() {
    awk '/^## 覆蓋例外表/{inTable=1; next}
         inTable && /^## /{inTable=0}
         inTable && /^\| /{
             if ($0 ~ /^\| 檢查點/ || $0 ~ /^\| ---/) next
             line=$0; sub(/^\| /,"",line); sub(/ \|.*$/,"",line); print line
         }' "$1/no0_index.md" 2>/dev/null | sed 's/^ *//; s/ *$//' | grep -v '^$' | sort -u
}

extract_capabilities() {
    awk -F'|' '
        /^## 手段表/{inTable=1; next}
        inTable && /^## /{inTable=0}
        inTable && /^\|/{
            id=$2; status=$4; requirement=$5
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", status)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", requirement)
            gsub(/`/, "", id)
            if (id == "手段 id") {
                schema=(requirement == "操作需求" ? "neutral" : (requirement == "執行者" ? "legacy" : "invalid"))
                next
            }
            if (id == "" || id ~ /^---/) next
            print id "|" status "|" requirement "|" schema
        }' "$1"
}

extract_metadata() {
    awk '
        /^## [A-Z][A-Z]-[0-9][0-9] /{
            caseId=$2
            print FILENAME "|" FNR "|" caseId "|__case__|1"
        }
        /^- \*\*QA metadata:\*\*/{
            print FILENAME "|" FNR "|" caseId "|__block__|1"
            next
        }
        /^    - (feature_links|risk_tags|capabilities|tier|runtime_route|driver|seed|inspect|evidence): /{
            line=$0
            sub(/^    - /, "", line)
            key=line
            sub(/:.*/, "", key)
            value=line
            sub(/^[^:]+:[[:space:]]*/, "", value)
            print FILENAME "|" FNR "|" caseId "|" key "|" value
        }' "$1"/no[0-9]*.md 2>/dev/null
}

extract_baselines() {
    awk -F'|' '
        /^## 生成基線表/{inTable=1; next}
        inTable && /^## /{inTable=0}
        inTable && /^\| `/{
            repo=$2; commit=$3; tree=$4; date=$5
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", repo)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", commit)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", tree)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", date)
            gsub(/`/, "", repo)
            gsub(/`/, "", commit)
            gsub(/`/, "", tree)
            print repo "|" commit "|" tree "|" date
        }' "$1/no0_index.md" 2>/dev/null
}

extract_direct_case_mappings() {
    awk -F'|' '
        /^## 路徑映射表/{inTable=1; next}
        inTable && /^## /{inTable=0}
        inTable && /^\|/{
            paths=$2
            area=$3
            direct=$4
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", paths)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", area)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", direct)
            gsub(/`/, "", paths)
            gsub(/`/, "", area)
            gsub(/`/, "", direct)
            if (paths == "" || paths == "impl 路徑前綴" || paths ~ /^---/) next
            print paths "|" area "|" direct
        }' "$1/no0_index.md" 2>/dev/null
}

extract_plan_method_rows() {
    awk '
        function emit() {
            if (pending) print file "|" lineNo "|" verifier "|" method "|" schema "|" timing
            pending=0
        }
        FNR == 1 || /^## / || /^    - \*\*/ { emit() }
        /^        - 層: /{
            emit()
            schema=($0 ~ /驗證者:/ ? "legacy" : "neutral")
            verifier=""
            if (schema == "legacy") {
                verifier=$0
                sub(/^.*驗證者: /, "", verifier)
                sub(/ ／ 手段: .*$/, "", verifier)
            }
            method=$0
            sub(/^.*手段: /, "", method)
            sub(/[[:space:]]*$/, "", method)
            pending=1; file=FILENAME; lineNo=FNR; timing=""
        }
        /^        - 取證時點: / {
            timing=$0
            sub(/^        - 取證時點:[[:space:]]*/, "", timing)
            sub(/[[:space:]]*$/, "", timing)
        }
        END { emit() }' "$1"/no[0-9]*.md 2>/dev/null
}

extract_csv_rows() {
    awk -v bom="$(printf '\357\273\277')" -F, '
        FNR == 1 {
            header=$0
            sub("^" bom, "", header)
            sub(/\r$/, "", header)
            schema=(header == "序,測項,類型,動作,預期,取證時點,手段,已驗,說明" ? "neutral" : (header == "序,測項,類型,動作,預期,驗證者,手段,已驗,說明" ? "legacy" : "invalid"))
        }
        FNR > 1 && NF > 1{
            type=$3; verifier=$6; method=$7
            sub(/\r$/, "", type)
            sub(/\r$/, "", verifier)
            sub(/\r$/, "", method)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", verifier)
            print FILENAME "|" FNR "|" type "|" verifier "|" method "|" NF "|" schema
        }' "$1"/no*_r*.csv 2>/dev/null
}

extract_run_cases() {
    awk -F'|' '
        /^## 場次總表/{inTable=1; next}
        inTable && /^## /{inTable=0}
        inTable && /^\| R[0-9][0-9] /{
            run=$2
            cases=$4
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", run)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", cases)
            sub(/[[:space:]].*$/, "", run)
            gsub(/`/, "", cases)
            gsub(/ 前段/, "", cases)
            count=split(cases, list, "、")
            for (i=1; i<=count; i++) {
                if (list[i] ~ /^[A-Z][A-Z]-[0-9][0-9]$/) {
                    print run "|" list[i]
                }
            }
        }' "$1/no0_index.md" 2>/dev/null
}

check_profile_and_baseline() {
    local profile="$1" plan="$2"

    if [ ! -f "$profile" ]; then
        fail "能力側寫不存在：$profile"
        : > "${CHECK_TMP_PREFIX}_caps.txt"
        return
    fi

    extract_capabilities "$profile" > "${CHECK_TMP_PREFIX}_caps.txt"
    if [ ! -s "${CHECK_TMP_PREFIX}_caps.txt" ]; then
        fail "能力表抽不到手段"
    fi

    local duplicate
    duplicate=$(cut -d'|' -f1 "${CHECK_TMP_PREFIX}_caps.txt" | sort | uniq -d)
    if [ -n "$duplicate" ]; then
        fail "能力表手段 id 重複：$duplicate"
    fi

    local id status requirement schema
    while IFS='|' read -r id status requirement schema; do
        case "$status" in
            可用|受阻) ;;
            *) fail "能力表狀態非法：$id=$status" ;;
        esac
        case "$schema" in
            neutral)
                case "$requirement" in
                    ui|device-ui|tool) ;;
                    unavailable) [ "$status" = 受阻 ] || fail "無可用路徑的能力不得宣告可用：$id" ;;
                    *) fail "能力表操作需求非法：$id=$requirement" ;;
                esac
                [ "$id" != manual-ui ] || [ "$requirement" = ui ] || fail "manual-ui 操作需求必須為 ui"
                [ "$id" != manual-device ] || [ "$requirement" = device-ui ] || fail "manual-device 操作需求必須為 device-ui"
                ;;
            legacy)
                case "$requirement" in
                    使用者|Claude|無) ;;
                    *) fail "舊能力表執行者非法：$id=$requirement" ;;
                esac
                ;;
            *) fail "能力表缺少合法操作需求或舊執行者表頭：$id" ;;
        esac
    done < "${CHECK_TMP_PREFIX}_caps.txt"

    for id in manual-device qa-command qa-probe; do
        if ! cut -d'|' -f1 "${CHECK_TMP_PREFIX}_caps.txt" | grep -qxF "$id"; then
            fail "能力表缺少 $id"
        fi
    done

    extract_baselines "$plan" > "${CHECK_TMP_PREFIX}_baselines.txt"
    if [ ! -s "${CHECK_TMP_PREFIX}_baselines.txt" ]; then
        fail "生成基線表抽不到資料"
        return
    fi

    local repo commit tree date
    while IFS='|' read -r repo commit tree date; do
        if ! printf '%s' "$commit" | grep -Eq '^[0-9a-f]{40}$'; then
            fail "基線 commit 不是 full SHA：$repo=$commit"
        fi
        if ! printf '%s' "$tree" | grep -Eq '^[0-9a-f]{40}$'; then
            fail "基線 tree 不是 full SHA：$repo=$tree"
        fi
        [ -n "$date" ] || fail "基線同步日期為空：$repo"
    done < "${CHECK_TMP_PREFIX}_baselines.txt"
}

meta_value() {
    awk -F'|' -v case_id="$1" -v key="$2" '
        $3 == case_id && $4 == key {print $5; exit}
    ' "${CHECK_TMP_PREFIX}_meta.txt" | sed 's/`//g'
}

meta_has_cap() {
    printf '%s' "$1" | sed 's/、/\n/g' | grep -qxF "$2"
}

check_metadata_schema() {
    check_metadata_schema_fast "$1"
}

mapping_pattern_matches() {
    local target="$1" pattern="$2"
    case "$pattern" in
        */)
            case "$target" in
                "$pattern"*) return 0 ;;
            esac
            ;;
        *)
            case "$target" in
                $pattern) return 0 ;;
            esac
            ;;
    esac
    return 1
}

collect_mapping_matches() {
    local target="$1" mappings="$2" output="$3"
    local paths area direct pattern matched
    : > "$output"
    while IFS='|' read -r paths area direct; do
        matched=0
        printf '%s\n' "$paths" | sed 's/、/\
/g; s/^[[:space:]]*//; s/[[:space:]]*$//' \
            > "${CHECK_TMP_PREFIX}_mapping_patterns.txt"
        while IFS= read -r pattern; do
            if mapping_pattern_matches "$target" "$pattern"; then
                matched=1
                break
            fi
        done < "${CHECK_TMP_PREFIX}_mapping_patterns.txt"
        if [ "$matched" -eq 1 ]; then
            printf '%s|%s|%s\n' "$paths" "$area" "$direct" >> "$output"
        fi
    done < "$mappings"
}

write_direct_case_tokens() {
    awk -F'|' '
        $3 != "" {
            count=split($3, cases, "、")
            for (i=1; i<=count; i++) {
                token=cases[i]
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", token)
                if (token != "") print token
            }
        }' "$1"
}

write_direct_case_set() {
    write_direct_case_tokens "$1" |
        awk '/^[A-Z][A-Z]-[0-9][0-9]$/' |
        sort -u > "$2"
}

assert_direct_case_set() {
    local target="$1" expected="$2" label="$3" require_overlap="$4"
    local matches="${CHECK_TMP_PREFIX}_mapping_matches.txt"
    local actual="${CHECK_TMP_PREFIX}_actual_direct_cases.txt"
    local match_count direct_count
    collect_mapping_matches "$target" "${CHECK_TMP_PREFIX}_direct_mappings.txt" "$matches"
    match_count=$(wc -l < "$matches" | tr -d ' ')
    direct_count=$(awk -F'|' '$3 != "" {count++} END {print count + 0}' "$matches")

    [ "$match_count" -gt 0 ] || fail "$label 沒有任何路徑映射"
    [ "$direct_count" -gt 0 ] || fail "$label 被 coarse mapping shadow"
    if [ "$require_overlap" -eq 1 ] && [ "$match_count" -lt 2 ]; then
        fail "$label 缺 coarse 與 direct overlap"
    fi

    write_direct_case_set "$matches" "$actual"
    if ! diff -q "$expected" "$actual" >/dev/null 2>&1; then
        fail "$label 的 direct-priority 測項集合不符"
    fi
}

assert_coarse_only_mapping() {
    local target="$1" label="$2"
    local matches="${CHECK_TMP_PREFIX}_mapping_matches.txt"
    local match_count direct_count
    collect_mapping_matches "$target" "${CHECK_TMP_PREFIX}_direct_mappings.txt" "$matches"
    match_count=$(wc -l < "$matches" | tr -d ' ')
    direct_count=$(awk -F'|' '$3 != "" {count++} END {print count + 0}' "$matches")

    [ "$match_count" -gt 0 ] || fail "$label 沒有 coarse mapping"
    [ "$direct_count" -eq 0 ] || fail "$label 必須維持 coarse-only"
}

check_direct_case_mapping() {
    local plan="$1"
    extract_direct_case_mappings "$plan" > "${CHECK_TMP_PREFIX}_direct_mappings.txt"
    awk -F'|' '$4 == "__block__" {print $3}' "${CHECK_TMP_PREFIX}_meta.txt" | sort -u > "${CHECK_TMP_PREFIX}_case_ids.txt"

    if [ ! -s "${CHECK_TMP_PREFIX}_direct_mappings.txt" ]; then
        fail "路徑映射表缺直接測項欄"
        return
    fi

    write_direct_case_tokens "${CHECK_TMP_PREFIX}_direct_mappings.txt" \
        > "${CHECK_TMP_PREFIX}_direct_case_tokens.txt"
    local case_id
    while IFS= read -r case_id; do
        if ! printf '%s' "$case_id" | grep -Eq '^[A-Z][A-Z]-[0-9][0-9]$'; then
            fail "直接測項格式非法：$case_id"
        fi
    done < "${CHECK_TMP_PREFIX}_direct_case_tokens.txt"

    write_direct_case_set "${CHECK_TMP_PREFIX}_direct_mappings.txt" "${CHECK_TMP_PREFIX}_direct_case_ids.txt"
    while IFS= read -r case_id; do
        grep -qxF "$case_id" "${CHECK_TMP_PREFIX}_case_ids.txt" || fail "直接測項不存在：$case_id"
    done < "${CHECK_TMP_PREFIX}_direct_case_ids.txt"

    printf '%s\n' CS-02 HD-07 RC-06 | sort > "${CHECK_TMP_PREFIX}_expected_qa_direct_cases.txt"
    printf '%s\n' AU-01 AU-03 CS-02 | sort \
        > "${CHECK_TMP_PREFIX}_expected_qa_bootstrap_direct_cases.txt"
    printf '%s\n' AS-07 CF-03 | sort \
        > "${CHECK_TMP_PREFIX}_expected_qa_disposal_direct_cases.txt"
    printf '%s\n' AU-01 AU-03 AS-07 CF-03 CS-02 HD-07 RC-06 | sort \
        > "${CHECK_TMP_PREFIX}_expected_qa_lifecycle_direct_cases.txt"
    printf '%s\n' AU-01 AU-02 AU-03 AS-03 AS-08 CS-02 CS-03 HD-07 RC-06 | sort \
        > "${CHECK_TMP_PREFIX}_expected_auth_direct_cases.txt"
    printf '%s\n' AU-01 AU-03 CS-02 RC-06 | sort \
        > "${CHECK_TMP_PREFIX}_expected_recurring_guard_direct_cases.txt"
    printf '%s\n' AU-01 AU-03 CS-02 CS-03 | sort \
        > "${CHECK_TMP_PREFIX}_expected_initial_data_direct_cases.txt"
    printf '%s\n' AU-01 AU-03 CS-01 CS-02 CS-03 | sort \
        > "${CHECK_TMP_PREFIX}_expected_user_service_direct_cases.txt"
    printf '%s\n' CS-02 CS-03 | sort \
        > "${CHECK_TMP_PREFIX}_expected_sync_engine_direct_cases.txt"
    printf '%s\n' CS-03 PM-02 PM-03 PM-05 | sort \
        > "${CHECK_TMP_PREFIX}_expected_premium_backup_direct_cases.txt"

    assert_direct_case_set 'App.tsx' \
        "${CHECK_TMP_PREFIX}_expected_auth_direct_cases.txt" 'App.tsx' 1
    assert_direct_case_set 'src/contexts/AuthContext.tsx' \
        "${CHECK_TMP_PREFIX}_expected_auth_direct_cases.txt" 'src/contexts/AuthContext*' 1
    assert_direct_case_set 'src/contexts/AuthContext.anonymousBootstrap.test.tsx' \
        "${CHECK_TMP_PREFIX}_expected_auth_direct_cases.txt" 'src/contexts/AuthContext* test' 1
    assert_direct_case_set 'src/services/recurringLogic.ts' \
        "${CHECK_TMP_PREFIX}_expected_recurring_guard_direct_cases.txt" 'recurringLogic implementation' 1
    assert_direct_case_set 'src/services/recurringLogic.test.ts' \
        "${CHECK_TMP_PREFIX}_expected_recurring_guard_direct_cases.txt" 'recurringLogic test' 1
    assert_direct_case_set 'src/services/localDbService.qaReset.test.ts' \
        "${CHECK_TMP_PREFIX}_expected_qa_direct_cases.txt" 'localDbService QA reset overlap' 1

    assert_direct_case_set 'src/database/helpers/createInitialUserData.ts' \
        "${CHECK_TMP_PREFIX}_expected_initial_data_direct_cases.txt" 'createInitialUserData implementation' 1
    assert_direct_case_set 'src/database/helpers/createInitialUserData.test.ts' \
        "${CHECK_TMP_PREFIX}_expected_initial_data_direct_cases.txt" 'createInitialUserData test' 1
    assert_direct_case_set 'src/services/userService.ts' \
        "${CHECK_TMP_PREFIX}_expected_user_service_direct_cases.txt" 'userService implementation' 1
    assert_direct_case_set 'src/services/userService.test.ts' \
        "${CHECK_TMP_PREFIX}_expected_user_service_direct_cases.txt" 'userService test' 1
    assert_direct_case_set 'src/services/syncEngine.ts' \
        "${CHECK_TMP_PREFIX}_expected_sync_engine_direct_cases.txt" 'syncEngine implementation' 1
    assert_direct_case_set 'src/services/syncEngine.test.ts' \
        "${CHECK_TMP_PREFIX}_expected_sync_engine_direct_cases.txt" 'syncEngine test' 1
    assert_direct_case_set 'src/services/runBackup.ts' \
        "${CHECK_TMP_PREFIX}_expected_sync_engine_direct_cases.txt" 'runBackup implementation' 1
    assert_direct_case_set 'src/services/runBackup.test.ts' \
        "${CHECK_TMP_PREFIX}_expected_sync_engine_direct_cases.txt" 'runBackup test' 1
    assert_direct_case_set 'src/contexts/PremiumContext.tsx' \
        "${CHECK_TMP_PREFIX}_expected_premium_backup_direct_cases.txt" 'PremiumContext implementation' 1
    assert_direct_case_set 'src/contexts/PremiumContext.storeKit.test.tsx' \
        "${CHECK_TMP_PREFIX}_expected_premium_backup_direct_cases.txt" 'PremiumContext storeKit test' 1

    assert_coarse_only_mapping 'src/qa/futureUnmappedQaModule.ts' 'src/qa/ broad mapping'

    assert_direct_case_set 'src/qa/anonymousIdentityBootstrap.ts' \
        "${CHECK_TMP_PREFIX}_expected_qa_bootstrap_direct_cases.txt" 'QA bootstrap implementation' 1
    assert_direct_case_set 'src/qa/anonymousIdentityBootstrap.test.ts' \
        "${CHECK_TMP_PREFIX}_expected_qa_bootstrap_direct_cases.txt" 'QA bootstrap test' 1
    assert_direct_case_set 'src/services/firebase.ts' \
        "${CHECK_TMP_PREFIX}_expected_qa_bootstrap_direct_cases.txt" 'Firebase Auth service' 1
    assert_direct_case_set 'src/qa/anonymousIdentityDisposal.ts' \
        "${CHECK_TMP_PREFIX}_expected_qa_disposal_direct_cases.txt" 'QA disposal implementation' 1
    assert_direct_case_set 'src/qa/anonymousIdentityDisposal.test.ts' \
        "${CHECK_TMP_PREFIX}_expected_qa_disposal_direct_cases.txt" 'QA disposal test' 1
    assert_direct_case_set 'src/qa/qaSessionProof.ts' \
        "${CHECK_TMP_PREFIX}_expected_qa_lifecycle_direct_cases.txt" 'QA session proof implementation' 1
    assert_direct_case_set 'src/qa/qaSessionProof.test.ts' \
        "${CHECK_TMP_PREFIX}_expected_qa_lifecycle_direct_cases.txt" 'QA session proof test' 1
    assert_direct_case_set 'src/qa/nativeQaBuildIsolation.test.ts' \
        "${CHECK_TMP_PREFIX}_expected_qa_lifecycle_direct_cases.txt" 'QA native proof test' 1
    local storekit_cases="${CHECK_TMP_PREFIX}_expected_storekit_cases.txt"
    printf '%s\n' PM-06 PM-07 PM-08 PM-09 > "$storekit_cases"
    cat "${CHECK_TMP_PREFIX}_expected_qa_lifecycle_direct_cases.txt" "$storekit_cases" | sort -u \
        > "${CHECK_TMP_PREFIX}_expected_qa_lifecycle_storekit_cases.txt"
    cat "${CHECK_TMP_PREFIX}_expected_qa_direct_cases.txt" "$storekit_cases" | sort -u \
        > "${CHECK_TMP_PREFIX}_expected_qa_storekit_cases.txt"
    assert_direct_case_set 'ios/SuSuGiGiApp/BuildEnvironmentModule.m' \
        "${CHECK_TMP_PREFIX}_expected_qa_lifecycle_storekit_cases.txt" 'QA native proof implementation' 0
    assert_direct_case_set 'src/qa/QaApp.tsx' \
        "${CHECK_TMP_PREFIX}_expected_qa_storekit_cases.txt" 'src/qa/QaApp.tsx' 1
    assert_direct_case_set 'ios/SuSuGiGiApp/AppDelegate.swift' \
        "${CHECK_TMP_PREFIX}_expected_qa_storekit_cases.txt" 'ios/SuSuGiGiApp/AppDelegate.swift' 0

    local operation_path
    for operation_path in \
        'src/qa/QaRuntimeBridge.tsx' \
        'src/qa/QaRuntimeBridge.test.ts' \
        'src/qa/appQaHarness.test.ts' \
        'src/qa/enabledQaHarness.ts' \
        'src/qa/enabledQaHarness.test.ts' \
        'src/qa/interface.ts' \
        'src/qa/QaOperationGateApp.tsx' \
        'src/qa/qaOperationAuthorization.ts' \
        'src/qa/qaOperationAuthorization.test.ts' \
        'src/qa/qaAuthGuard.ts' \
        'src/qa/qaAuthGuard.test.ts' \
        'src/qa/registerQaRuntime.ts' \
        'src/qa/registerQaRuntime.test.ts'; do
        assert_direct_case_set "$operation_path" \
            "${CHECK_TMP_PREFIX}_expected_qa_direct_cases.txt" "$operation_path" 1
    done

    local lifecycle_path lifecycle_overlap
    for lifecycle_path in \
        'index.qa.js' \
        'src/qa/qaLaunchPlan.ts' \
        'src/qa/qaLaunchPlan.test.ts' \
        'src/qa/nativeQaLaunchPlan.ts' \
        'src/qa/nativeQaLaunchPlan.test.ts' \
        'src/qa/qaEntrySelection.ts' \
        'src/qa/qaEntrySelection.test.ts' \
        'src/qa/invalidQaLaunch.ts' \
        'src/qa/qaNativeMarkerForwarding.ts' \
        'src/qa/qaNativeMarkerForwarding.test.ts' \
        'src/qa/buildEntryIsolation.test.ts' \
        'src/qa/firebaseConfigSelection.test.ts' \
        'src/qa/productionModuleGraph.ts' \
        'src/qa/productionModuleGraphIsolation.test.ts'; do
        lifecycle_overlap=1
        [ "$lifecycle_path" = 'index.qa.js' ] && lifecycle_overlap=0
        assert_direct_case_set "$lifecycle_path" \
            "${CHECK_TMP_PREFIX}_expected_qa_lifecycle_direct_cases.txt" "$lifecycle_path" "$lifecycle_overlap"
    done

    local path
    for path in \
        '.gitignore' \
        'src/utils/buildEnvironment.ts' \
        'src/utils/buildEnvironment.test.ts' \
        'ios/scripts/select-firebase-config.sh' \
        'ios/SuSuGiGiApp/Info.plist' \
        'src/services/appCheck.ts'; do
        assert_direct_case_set "$path" \
            "${CHECK_TMP_PREFIX}_expected_qa_direct_cases.txt" "$path" 0
    done
    for path in 'ios/SwishLocal.storekit' 'ios/STOREKIT_TESTING.md' \
        'ios/scripts/select-storekit-config.sh' 'src/qa/qaLocalStoreKitMenu.ts' \
        'ios/SuSuGiGiApp.xcodeproj/xcshareddata/xcschemes/SuSuGiGiApp-QA-StoreKit.xcscheme'; do
        assert_direct_case_set "$path" "$storekit_cases" "$path" 0
    done
    cat "${CHECK_TMP_PREFIX}_expected_qa_direct_cases.txt" "$storekit_cases" | sort -u \
        > "${CHECK_TMP_PREFIX}_expected_project_cases.txt"
    assert_direct_case_set 'ios/SuSuGiGiApp.xcodeproj/project.pbxproj' \
        "${CHECK_TMP_PREFIX}_expected_project_cases.txt" 'ios/SuSuGiGiApp.xcodeproj/project.pbxproj' 0
}


check_metadata_schema_fast() {
    local plan="$1"
    extract_metadata "$plan" > "${CHECK_TMP_PREFIX}_meta.txt"
    if [ ! -s "${CHECK_TMP_PREFIX}_meta.txt" ]; then
        fail "找不到任何 QA metadata"
        return
    fi

    awk -F'|' '
        NR == FNR {
            capStatus[$1]=$2
            next
        }
        {
            caseId=$3
            key=$4
            value=$5
            gsub(/`/, "", value)
            if (key == "__case__") {
                allCases[caseId]=1
                next
            }
            if (key == "__block__") {
                blocks[caseId]++
                blockCases[caseId]=1
                next
            }
            fieldCases[caseId]=1
            counts[caseId SUBSEP key]++
            values[caseId SUBSEP key]=value
        }
        END {
            split("feature_links risk_tags capabilities tier runtime_route driver seed inspect evidence", required, " ")
            caseCount=0
            metadataCount=0

            for (caseId in fieldCases) {
                if (!(caseId in blockCases)) {
                    print caseId " 的 metadata 欄位缺 QA metadata block"
                }
            }

            for (caseId in allCases) {
                caseCount++
                if (!(caseId in blockCases)) {
                    print caseId " 缺 QA metadata"
                    continue
                }
                metadataCount++
                complete=1
                if (blocks[caseId] != 1) {
                    print caseId " 的 QA metadata block 數量為 " blocks[caseId]
                    complete=0
                }
                for (i=1; i<=9; i++) {
                    key=required[i]
                    count=counts[caseId SUBSEP key] + 0
                    if (count != 1) {
                        print caseId " 的 " key " 欄數量為 " count
                        complete=0
                    }
                }
                if (!complete) {
                    continue
                }

                features=values[caseId SUBSEP "feature_links"]
                risks=values[caseId SUBSEP "risk_tags"]
                capValue=values[caseId SUBSEP "capabilities"]
                tier=values[caseId SUBSEP "tier"]
                route=values[caseId SUBSEP "runtime_route"]
                driver=values[caseId SUBSEP "driver"]
                seed=values[caseId SUBSEP "seed"]
                inspect=values[caseId SUBSEP "inspect"]
                evidence=values[caseId SUBSEP "evidence"]

                if (features == "") print caseId " 的 feature_links 為空"
                if (risks == "") print caseId " 的 risk_tags 為空"
                if (capValue == "") print caseId " 的 capabilities 為空"
                if (evidence == "") print caseId " 的 evidence 為空"

                delete caseCaps
                capCount=split(capValue, capList, "、")
                for (i=1; i<=capCount; i++) {
                    cap=capList[i]
                    caseCaps[cap]=1
                    if (!(cap in capStatus)) print caseId " 引用未知 capability：" cap
                }

                if (tier == "core" || tier == "standard" || tier == "extended") {
                    tierCount[tier]++
                } else {
                    print caseId " 的 tier 非允許值：" tier
                }

                routeValid=(route == "none" || route == "simulator" || route == "physical-device" || route == "simulator-or-physical-device")
                driverValid=(driver == "none" || driver == "sim-review" || driver == "game-test")
                if (!routeValid) print caseId " 的 runtime_route 非允許值：" route
                if (!driverValid) print caseId " 的 driver 非允許值：" driver
                if (routeValid && driverValid) {
                    expectedDriver=(route == "none" ? "none" : (route == "simulator" ? "sim-review" : "game-test"))
                    if (driver != expectedDriver) {
                        print caseId " 的 runtime 配對非法：" route " + " driver
                    }
                }
                if (route == "physical-device" && !("manual-device" in caseCaps)) {
                    print caseId " 的 physical-device 缺 manual-device"
                }

                if (seed != "none" && seed != "r02_end" && seed != "r06_large_history" && seed != "r06_large_history_cleanup" && seed != "r09_stale_schedule") {
                    print caseId " 的 seed 非允許場景：" seed
                } else if (seed != "none" && !("qa-command" in caseCaps)) {
                    print caseId " 的 seed 缺 qa-command"
                }

                if (inspect != "none" && inspect != "accounting.fixture-summary" && inspect != "accounting.large-history-overlay" && inspect != "accounting.schedule-backfill") {
                    print caseId " 的 inspect 非允許檢查：" inspect
                } else if (inspect != "none" && !("qa-probe" in caseCaps)) {
                    print caseId " 的 inspect 缺 qa-probe"
                }

                evidenceCount=split(evidence, evidenceList, "、")
                for (i=1; i<=evidenceCount; i++) {
                    source=evidenceList[i]
                    sub(/:.*/, "", source)
                    if (!(source in caseCaps)) print caseId " 的 evidence 缺 capability：" source
                }
            }

            if (caseCount == 0) print "找不到任何測項"
            if (metadataCount != caseCount) {
                print "metadata 案例數 " metadataCount " 不等於測項數 " caseCount
            }
            if (tierCount["core"] == 0) print "沒有 tier core 案例"
            if (tierCount["standard"] == 0) print "沒有 tier standard 案例"
            if (tierCount["extended"] == 0) print "沒有 tier extended 案例"
        }' "${CHECK_TMP_PREFIX}_caps.txt" "${CHECK_TMP_PREFIX}_meta.txt" > "${CHECK_TMP_PREFIX}_meta_errors.txt"
    local awk_status=$?
    if [ "$awk_status" -ne 0 ]; then
        fail "metadata schema parser 執行失敗"
        return
    fi

    local error
    while IFS= read -r error; do
        [ -n "$error" ] && fail "$error"
    done < "${CHECK_TMP_PREFIX}_meta_errors.txt"
}


check_method_compatibility() {
    local plan="$1" script="$2"
    extract_plan_method_rows "$plan" > "${CHECK_TMP_PREFIX}_plan_methods.txt"
    extract_csv_rows "$script" > "${CHECK_TMP_PREFIX}_csv_rows.txt"

    awk -F'|' '
        NR == FNR {
            status[$1]=$2
            next
        }
        {
            location=$1 ":" $2
            verifier=$3
            method=$4
            if (!(method in status)) {
                print location " 引用未知手段 " method
                next
            }
            if ($5 == "legacy" && verifier != "使用者" && verifier != "Claude" && verifier != "無") {
                print location " 的舊驗證者非法：" verifier
            }
            if ($5 == "neutral" && ($6 == "" || $6 ~ /^(使用者|Claude|Codex|AI|我|你)$/)) {
                print location " 缺少有效取證時點"
            }
        }' "${CHECK_TMP_PREFIX}_caps.txt" "${CHECK_TMP_PREFIX}_plan_methods.txt" > "${CHECK_TMP_PREFIX}_method_errors.txt"

    awk -F'|' '
        NR == FNR {
            status[$1]=$2
            next
        }
        {
            location=$1 ":" $2
            verifier=$4
            method=$5
            if (!(method in status)) {
                print location " 引用未知手段 " method
                next
            }
            if ($7 == "legacy" && verifier != "使用者" && verifier != "Claude" && verifier != "無") {
                print location " 的舊驗證者非法：" verifier
            }
        }' "${CHECK_TMP_PREFIX}_caps.txt" "${CHECK_TMP_PREFIX}_csv_rows.txt" >> "${CHECK_TMP_PREFIX}_method_errors.txt"

    local error
    while IFS= read -r error; do
        [ -n "$error" ] && fail "$error"
    done < "${CHECK_TMP_PREFIX}_method_errors.txt"
}

check_readiness_provider_contract() {
    local plan="$1" script="$2"
    local errors="${CHECK_TMP_PREFIX}_readiness_provider_errors.txt"

    awk '
        {
            lower=tolower($0)
            invalid=0
            if (lower ~ /firebase cli.*或.*gcloud/ ||
                lower ~ /gcloud.*或.*firebase cli/) {
                invalid=1
            }
            if (lower ~ /(firestore-read|cloud-logging|qa-cleanup).*firebase cli/ ||
                lower ~ /firebase cli.*(firestore-read|cloud-logging|qa-cleanup)/) {
                invalid=1
            }
            if ((lower ~ /firestore-read.*條件/ || lower ~ /條件.*firestore-read/) &&
                $0 !~ /gcloud Firestore OAuth/) {
                invalid=1
            }
            if ((lower ~ /cloud-logging.*條件/ || lower ~ /條件.*cloud-logging/) &&
                $0 !~ /gcloud OAuth/) {
                invalid=1
            }
            if (invalid) {
                print FILENAME ":" FNR ":" $0
            }
        }
    ' "$plan"/no*.md "$script"/no*.md "$script"/no*.csv \
        > "$errors" 2>/dev/null

    if [ -s "$errors" ]; then
        fail "readiness 契約不得把 Firebase CLI 與 gcloud OAuth 寫成替代關係"
        sed 's/^/      /' "$errors"
    fi
}

check_csv_schema() {
    local script="$1"
    [ -f "${CHECK_TMP_PREFIX}_csv_rows.txt" ] || extract_csv_rows "$script" > "${CHECK_TMP_PREFIX}_csv_rows.txt"

    local file line type verifier method fields schema header
    for file in "$script"/no*_r*.csv; do
        [ -f "$file" ] || continue
        header=$(head -n 1 "$file" | sed $'s/^\xef\xbb\xbf//; s/\r$//')
        case "$header" in
            序,測項,類型,動作,預期,取證時點,手段,已驗,說明|序,測項,類型,動作,預期,驗證者,手段,已驗,說明) ;;
            *) fail "$file CSV 表頭非法" ;;
        esac
    done
    while IFS='|' read -r file line type verifier method fields schema; do
        if [ "$fields" -ne 9 ]; then
            fail "$file:$line 欄數為 ${fields}，應為 9"
        fi
        case "$type" in
            操作|建置|還原|取證) ;;
            Claude節點) [ "$schema" = legacy ] || fail "$file:$line 新格式不得使用 Claude節點" ;;
            *) fail "$file:$line 使用非法 type $type" ;;
        esac
        if [ "$schema" = neutral ]; then
            case "$verifier" in
                ''|使用者|Claude|Codex|AI|我|你) fail "$file:$line 缺少有效取證時點" ;;
            esac
        fi
    done < "${CHECK_TMP_PREFIX}_csv_rows.txt"
}

check_run_route_contract() {
    local script="$1"
    local run_cases="${CHECK_TMP_PREFIX}_run_cases.txt"
    local route_errors="${CHECK_TMP_PREFIX}_run_route_errors.txt"
    extract_run_cases "$script" > "$run_cases"
    if [ ! -s "$run_cases" ]; then
        fail "場次總表抽不到 case route"
        return
    fi

    local run case_id expected actual
    : > "$route_errors"
    while IFS='|' read -r run case_id; do
        case "$run" in
            R01|R02|R03|R04|R05|R06|R07|R08|R13) expected="simulator-or-physical-device" ;;
            R10|R11|R12) expected="none" ;;
            R15) expected="simulator" ;;
            R14) continue ;;
            *) printf '%s\n' "未知 App 場次：$run" >> "$route_errors"; continue ;;
        esac
        actual=$(meta_value "$case_id" runtime_route)
        if [ "$actual" != "$expected" ]; then
            printf '%s\n' "${run} 的 ${case_id} 應為 ${expected}，實際為 ${actual}" >> "$route_errors"
        fi
    done < "$run_cases"

    local metadata_count run_case_count
    metadata_count=$(awk -F'|' '$4 == "__block__" {print $3}' "${CHECK_TMP_PREFIX}_meta.txt" | sort -u | wc -l)
    run_case_count=$(cut -d'|' -f2 "$run_cases" | sort -u | wc -l)
    if [ "$run_case_count" -ne "$metadata_count" ]; then
        printf '%s\n' "場次 route 涵蓋 $run_case_count 案，metadata 為 $metadata_count 案" >> "$route_errors"
    fi

    local index="$script/no0_index.md"
    grep -Fq '| `no-physical-requirement` | `simulator` | `game-test` | `sim-review` |' "$index" || \
        printf '%s\n' "缺少 flexible 轉 simulator 的 session 規則" >> "$route_errors"
    grep -Fq '| `physical-in-selection-or-prerequisite` | `physical-device` | `game-test` | `none` |' "$index" || \
        printf '%s\n' "缺少選集或前置鏈轉實機的 session 規則" >> "$route_errors"
    grep -Fq '| `selection-contains-blocked-scenes` | `partial-blocked` | `game-test` | `per-safe-scene` | 阻斷場次不取得裝置 |' "$index" || \
        printf '%s\n' "缺少 R10–R12 first-operation structured block route" >> "$route_errors"
    grep -Fq '| `extended` | `partial-blocked` | `game-test` | `per-safe-scene` | 安全場次沿用單一裝置 |' "$index" || \
        printf '%s\n' "缺少 extended App Check isolation block route" >> "$route_errors"
    grep -Fq 'session 開始後禁止切換裝置類型' "$index" || \
        printf '%s\n' "缺少 session 裝置不可切換規則" >> "$route_errors"

    local r13_prerequisite
    r13_prerequisite=$(awk -F'|' '
        $2 ~ /R13 補產生驗證/ {
            value=$5
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            print value
            exit
        }' "$index")
    [ "$r13_prerequisite" = "無" ] || \
        printf '%s\n' "R13 必須保持鏈外，前置場次應為無" >> "$route_errors"

    grep -RFq --include='*.md' 'Mac 加 simulator' "$script" && \
        printf '%s\n' "flexible 場次仍固定 Mac 加 simulator" >> "$route_errors"
    grep -RFq --include='*.csv' 'simulator 恢復連網' "$script" && \
        printf '%s\n' "場次步驟仍固定 simulator" >> "$route_errors"
    grep -RFq --include='*.csv' '另以僅存在本機的 simulator' "$script" && \
        printf '%s\n' "R06 仍切換到 sidecar simulator" >> "$route_errors"
    grep -RFq --include='*.csv' '回到狀態鏈裝置' "$script" && \
        printf '%s\n' "R06 仍切換狀態鏈裝置" >> "$route_errors"
    grep -RFq --include='*.csv' 'sim-review 導出的 Metro log' "$script" && \
        printf '%s\n' "physical-device 場次仍依賴 sim-review log" >> "$route_errors"

    local hd07_seed hd07_inspect hd07_caps
    hd07_seed=$(meta_value "HD-07" seed)
    hd07_inspect=$(meta_value "HD-07" inspect)
    hd07_caps=$(meta_value "HD-07" capabilities)
    [ "$hd07_seed" = "r06_large_history" ] || \
        printf '%s\n' "HD-07 seed 必須為 r06_large_history" >> "$route_errors"
    [ "$hd07_inspect" = "accounting.large-history-overlay" ] || \
        printf '%s\n' "HD-07 inspect 必須為 accounting.large-history-overlay" >> "$route_errors"
    printf '%s' "$hd07_caps" | grep -Fq 'qa-command' || \
        printf '%s\n' "HD-07 capabilities 缺 qa-command" >> "$route_errors"
    printf '%s' "$hd07_caps" | grep -Fq 'qa-probe' || \
        printf '%s\n' "HD-07 capabilities 缺 qa-probe" >> "$route_errors"

    local r06="$script/no8_r06_dashboard.csv"
    if [ ! -f "$r06" ]; then
        printf '%s\n' "缺少 R06 CSV" >> "$route_errors"
    else
        local offline_line sim_load_line device_load_line probe_line sim_cleanup_line device_cleanup_line online_line
        offline_line=$(grep -nF '離線確認完成後才可 Load overlay' "$r06" | head -n1 | cut -d: -f1)
        sim_load_line=$(grep -nF 'prepare r06_large_history,' "$r06" | head -n1 | cut -d: -f1)
        device_load_line=$(grep -nF '點 Load R06 large history,' "$r06" | head -n1 | cut -d: -f1)
        probe_line=$(grep -nF 'inspect accounting.large-history-overlay' "$r06" | head -n1 | cut -d: -f1)
        sim_cleanup_line=$(grep -nF 'prepare r06_large_history_cleanup' "$r06" | head -n1 | cut -d: -f1)
        device_cleanup_line=$(grep -nF '點 Remove R06 large history,' "$r06" | head -n1 | cut -d: -f1)
        online_line=$(grep -nF '恢復 session 鎖定裝置的網路' "$r06" | head -n1 | cut -d: -f1)

        [ -n "$offline_line" ] || printf '%s\n' "R06 缺 Load 前離線確認" >> "$route_errors"
        [ -n "$sim_load_line" ] || printf '%s\n' "R06 缺 simulator Load command" >> "$route_errors"
        [ -n "$device_load_line" ] || printf '%s\n' "R06 缺實機 Load 按鈕" >> "$route_errors"
        [ -n "$probe_line" ] || printf '%s\n' "R06 缺 overlay inspect" >> "$route_errors"
        [ -n "$sim_cleanup_line" ] || printf '%s\n' "R06 缺 simulator cleanup command" >> "$route_errors"
        [ -n "$device_cleanup_line" ] || printf '%s\n' "R06 缺實機 Remove 按鈕" >> "$route_errors"
        [ -n "$online_line" ] || printf '%s\n' "R06 缺 cleanup 後恢復網路" >> "$route_errors"

        if [ -n "$offline_line" ] && [ -n "$sim_load_line" ] && [ "$offline_line" -ge "$sim_load_line" ]; then
            printf '%s\n' "R06 simulator Load 發生在離線確認前" >> "$route_errors"
        fi
        if [ -n "$offline_line" ] && [ -n "$device_load_line" ] && [ "$offline_line" -ge "$device_load_line" ]; then
            printf '%s\n' "R06 實機 Load 發生在離線確認前" >> "$route_errors"
        fi
        if [ -n "$sim_load_line" ] && [ -n "$probe_line" ] && [ "$sim_load_line" -ge "$probe_line" ]; then
            printf '%s\n' "R06 overlay inspect 發生在 simulator Load 前" >> "$route_errors"
        fi
        if [ -n "$device_load_line" ] && [ -n "$probe_line" ] && [ "$device_load_line" -ge "$probe_line" ]; then
            printf '%s\n' "R06 overlay inspect 發生在實機 Load 前" >> "$route_errors"
        fi
        if [ -n "$probe_line" ] && [ -n "$sim_cleanup_line" ] && [ "$probe_line" -ge "$sim_cleanup_line" ]; then
            printf '%s\n' "R06 simulator cleanup 發生在 inspect 前" >> "$route_errors"
        fi
        if [ -n "$probe_line" ] && [ -n "$device_cleanup_line" ] && [ "$probe_line" -ge "$device_cleanup_line" ]; then
            printf '%s\n' "R06 實機 cleanup 發生在 inspect 前" >> "$route_errors"
        fi
        if [ -n "$sim_cleanup_line" ] && [ -n "$online_line" ] && [ "$sim_cleanup_line" -ge "$online_line" ]; then
            printf '%s\n' "R06 simulator cleanup 未先於恢復網路" >> "$route_errors"
        fi
        if [ -n "$device_cleanup_line" ] && [ -n "$online_line" ] && [ "$device_cleanup_line" -ge "$online_line" ]; then
            printf '%s\n' "R06 實機 cleanup 未先於恢復網路" >> "$route_errors"
        fi

        awk -F, '$1 == "19" && index($4, "離線探測") {found=1} END {exit found ? 0 : 1}' "$r06" || \
            printf '%s\n' "R06 overlay 建置第一步必須是離線探測" >> "$route_errors"
        awk -F, '$1 == "22" && index($9, "只在 simulator route 執行") {found=1} END {exit found ? 0 : 1}' "$r06" || \
            printf '%s\n' "R06 overlay inspect 只准 simulator route 執行" >> "$route_errors"
    fi

    grep -RFq --include='*.md' --include='*.csv' '保存狀態鏈資料' "$script" && \
        printf '%s\n' "R06 仍含保存狀態鏈的不可執行描述" >> "$route_errors"
    grep -RFq --include='*.md' --include='*.csv' '本機大型資料副本' "$script" && \
        printf '%s\n' "R06 仍含本機大型資料副本描述" >> "$route_errors"
    grep -RFq --include='*.md' --include='*.csv' '還原狀態鏈資料' "$script" && \
        printf '%s\n' "R06 仍含還原狀態鏈的不可執行描述" >> "$route_errors"

    local error
    while IFS= read -r error; do
        [ -n "$error" ] && fail "$error"
    done < <(sort -u "$route_errors")
}

profile_payload_value() {
    awk -v key="$1" '
        {
            token=key "="
            start=index($0, token)
            if (start > 0) {
                value=substr($0, start + length(token))
                sub(/`.*/, "", value)
                gsub(/[[:space:]]+$/, "", value)
                print value
                exit
            }
        }' "$2"
}

plist_value() {
    awk -v key="$2" '
        $0 ~ "<key>" key "</key>" {
            getline
            gsub(/.*<string>|<\/string>.*/, "")
            print
            exit
        }' "$1"
}

file_sha256() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
        return
    fi
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
        return
    fi
    return 2
}

check_qa_firebase_config_digest() {
    local file="$1" expected="$2" label="$3" actual
    actual=$(file_sha256 "$file") || {
        fail "$label 無可用的 SHA-256 工具"
        return
    }
    [ "$actual" = "$expected" ] || fail "$label SHA-256 不符"
}

xcode_firebase_phase_order_ok() {
    awk '
        /buildPhases = \(/ {
            active=1
            resources=0
            selector=0
            rnfb=0
            next
        }
        active && /\);/ {
            if (resources && selector && rnfb && resources < selector && selector < rnfb) {
                found=1
            }
            active=0
            next
        }
        active && /\/\* Resources \*\// {resources=NR}
        active && /\/\* Select Firebase Configuration \*\// {selector=NR}
        active && /\/\* \[CP-User\] \[RNFB\] Core Configuration \*\// {rnfb=NR}
        END {exit found ? 0 : 1}
    ' "$1"
}

test_block_has() {
    local file="$1" title="$2" needle="$3"
    [ -f "$file" ] || return 1
    awk -v title="$title" -v needle="$needle" '
        index($0, title) {
            active=1
            match($0, /^[[:space:]]*/)
            blockIndent=RLENGTH
        }
        active && index($0, needle) {
            found=1
        }
        active && /^[[:space:]]*\}\);[[:space:]]*$/ {
            match($0, /^[[:space:]]*/)
            if (RLENGTH == blockIndent) {
                closed=1
                exit
            }
        }
        END {
            exit !(active && closed && found)
        }' "$file"
}

test_block_has_in_order() {
    local file="$1" title="$2"
    shift 2
    local block_file="${CHECK_TMP_PREFIX}_ordered_test_block.txt"
    local cursor=0 needle next_line
    [ -f "$file" ] || return 1
    awk -v title="$title" '
        index($0, title) {
            active=1
            match($0, /^[[:space:]]*/)
            blockIndent=RLENGTH
        }
        active {print}
        active && /^[[:space:]]*\}\);[[:space:]]*$/ {
            match($0, /^[[:space:]]*/)
            if (RLENGTH == blockIndent) exit
        }
    ' "$file" > "$block_file"
    [ -s "$block_file" ] || return 1
    for needle in "$@"; do
        next_line=$(awk -v after="$cursor" -v needle="$needle" '
            NR > after && index($0, needle) {print NR; exit}
        ' "$block_file")
        [ -n "$next_line" ] || return 1
        cursor="$next_line"
    done
}

write_ts_type_property_set() {
    local file="$1" type_name="$2" output="$3"
    awk -v declaration="export type ${type_name}" '
        index($0, declaration) {active=1}
        active {print}
        active && /^[[:space:]]*};[[:space:]]*$/ {exit}
    ' "$file" 2>/dev/null |
        sed -En 's/^[[:space:]]*(readonly[[:space:]]+)?([A-Za-z][A-Za-z0-9]*)(\?)?:.*/\2/p' |
        sort -u > "$output"
}

assert_ts_type_property_set() {
    local file="$1" type_name="$2" expected="$3" label="$4"
    local actual="${CHECK_TMP_PREFIX}_${type_name}_properties.txt"
    write_ts_type_property_set "$file" "$type_name" "$actual"
    if ! diff -q "$expected" "$actual" >/dev/null 2>&1; then
        fail "$label exact schema 欄位不符"
    fi
}

write_qa_ready_property_set() {
    local file="$1" output="$2"
    awk '
        index($0, "QA READY") && index($0, "JSON.stringify({") {
            active=1
            next
        }
        active && /^[[:space:]]*}[)][}]`/ {exit}
        active {
            line=$0
            sub(/^[[:space:]]*/, "", line)
            if (match(line, /^[A-Za-z][A-Za-z0-9]*/)) {
                print substr(line, RSTART, RLENGTH)
            }
        }
    ' "$file" 2>/dev/null | sort -u > "$output"
}

assert_qa_ready_property_set() {
    local file="$1" expected="$2" label="$3"
    local actual="${CHECK_TMP_PREFIX}_ready_properties.txt"
    write_qa_ready_property_set "$file" "$actual"
    if ! diff -q "$expected" "$actual" >/dev/null 2>&1; then
        fail "$label READY producer exact keys 不符"
    fi
}

write_ts_string_set() {
    local file="$1" variable="$2" output="$3"
    awk -v declaration="const ${variable} = new Set([" '
        index($0, declaration) {active=1; next}
        active && /^[[:space:]]*][)][;]/ {exit}
        active && match($0, /\047[A-Z0-9_]+\047/) {
            print substr($0, RSTART + 1, RLENGTH - 2)
        }
    ' "$file" 2>/dev/null | sort -u > "$output"
}

assert_ts_string_set() {
    local file="$1" variable="$2" expected="$3" label="$4"
    local actual="${CHECK_TMP_PREFIX}_${variable}.txt"
    write_ts_string_set "$file" "$variable" "$actual"
    if ! diff -q "$expected" "$actual" >/dev/null 2>&1; then
        fail "$label exact allowlist 不符"
    fi
}

console_raw_uid_locations() {
    awk '
        function hasRawUid(statement, scrub) {
            if (statement ~ /\$\{[[:space:]]*(uid|[A-Za-z_][A-Za-z0-9_]*([.]|[?][.])uid)[[:space:]]*\}/) {
                return 1
            }
            scrub=statement
            gsub(/"[^"]*"/, "", scrub)
            gsub(/\047[^\047]*\047/, "", scrub)
            gsub(/`[^`]*`/, "", scrub)
            return scrub ~ /(^|[^A-Za-z0-9_])(uid|[A-Za-z_][A-Za-z0-9_]*([.]|[?][.])uid)([^A-Za-z0-9_]|$)/
        }
        !active && /console[.](log|info|warn|error)[(]/ {
            active=1
            start=NR
            statement=$0
        }
        active && NR != start {
            statement=statement "\n" $0
        }
        active && /[)][[:space:]]*;/ {
            if (hasRawUid(statement)) {
                print start
                found=1
            }
            active=0
            statement=""
        }
        END {
            if (active && hasRawUid(statement)) {
                print start
                found=1
            }
            exit found ? 0 : 1
        }
    ' "$1"
}

check_fixture_golden_contract() {
    local script="$1" impl="$2"
    local quality_root golden_checker golden_error
    quality_root=$(cd "$script/.." && pwd)
    golden_checker="$quality_root/no2_qa_tools/check_fixture_golden.py"
    if [ ! -f "$golden_checker" ]; then
        fail "Quality golden checker 不存在"
        return
    fi
    while IFS= read -r golden_error; do
        [ -z "$golden_error" ] || fail "$golden_error"
    done < <(python3 "$golden_checker" \
        "$script/no1_fixture_golden.json" \
        "$script/no1_fixtures.md" \
        "$script/no3_r01_bootstrap_identity.csv" \
        "$script/no5_r03_backup_export.md" \
        "$script/no5_r03_backup_export.csv" \
        "$script/no10_r08_preference_sync.csv" \
        "$script/no15_r13_backfill_verification.md" \
        "$script/no15_r13_backfill_verification.csv" \
        "$impl/src/qa/appQaHarness.ts" \
        "$impl/src/services/regressionFixture.ts" \
        "$quality_root/no2_qa_tools/query_local_db.sh")
}

check_qa_oauth_routes() {
    python3 -I - "$1" <<'PY'
import pathlib
import re
import sys

PRODUCTION = 'com.googleusercontent.apps.515173750154-4fftspgi257ovtom1cf3hrdbaslpr3km'
QA = 'com.almightyken0425.susugigiapp.qa'
EXPECTED = {'Debug': PRODUCTION, 'Release': PRODUCTION, 'Debug-QA': QA, 'Release-QA': QA}


def scalar(body, key):
    matches = re.findall(
        r'^[ \t]*' + re.escape(key) + r'[ \t]*=[ \t]*(?:"([^"\\\r\n]+)"|([A-Za-z0-9_.-]+))[ \t]*;[ \t]*$',
        body, re.M,
    )
    return (matches[0][0] or matches[0][1]) if len(matches) == 1 else None


def isolated(project):
    seen = set()
    configurations = re.finditer(
        r'^([ \t]*)[A-Fa-f0-9]{24}[ \t]+/\*[^\r\n]*\*/[ \t]*=[ \t]*\{\r?\n[ \t]*isa[ \t]*=[ \t]*XCBuildConfiguration[ \t]*;([\s\S]*?)^\1\};',
        project, re.M,
    )
    for configuration in configurations:
        body = configuration.group(2)
        if 'APP_URL_SCHEME' not in body:
            continue
        settings = re.findall(r'^([ \t]*)buildSettings[ \t]*=[ \t]*\{([\s\S]*?)^\1\};', body, re.M)
        name = scalar(body, 'name')
        if name not in EXPECTED or name in seen or len(settings) != 1:
            return False
        if scalar(settings[0][1], 'APP_URL_SCHEME') != EXPECTED[name]:
            return False
        seen.add(name)
    return len(seen) == 4 and len(re.findall(r'\bAPP_URL_SCHEME\b', project)) == 4


if sys.argv[1] == '--selftest':
    def fixture(quoted=True, swapped=False):
        rows = [('Debug', QA if swapped else PRODUCTION), ('Release', PRODUCTION),
                ('Debug-QA', PRODUCTION if swapped else QA), ('Release-QA', QA)]
        blocks = []
        for index, (name, route) in enumerate(rows):
            value = '"' + route + '"' if quoted else route
            blocks.append('\t\t%024d /* config */ = {\n\t\t\tisa = XCBuildConfiguration;\n'
                          '\t\t\tbuildSettings = {\n\t\t\t\tAPP_URL_SCHEME = %s;\n\t\t\t};\n'
                          '\t\t\tname = "%s";\n\t\t};' % (index, value, name))
        return '\n'.join(blocks)

    valid = fixture()
    cases = [(valid, True), (fixture(False), True), (fixture(True, True), False),
             (valid.replace(QA, 'com.example.wrong.qa', 1), False),
             (re.sub(r'^.*APP_URL_SCHEME.*\n', '', valid, count=1, flags=re.M), False),
             (re.sub(r'(^.*APP_URL_SCHEME.*$)', r'\1\n\1', valid, count=1, flags=re.M), False),
             (valid.replace('name = "Release-QA";', 'name = "Debug-QA";'), False),
             (valid.replace('APP_URL_SCHEME = "', 'APP_URL_SCHEME = ', 1), False),
             (valid.replace('APP_URL_SCHEME =', '"APP_URL_SCHEME[sdk=iphoneos*]" =', 1), False),
             (valid.replace('com.googleusercontent.apps.', 'comXgoogleusercontentXappsX', 1), False),
             (valid + '\nAPP_URL_SCHEME = com.example.extra;', False)]
    if not all(isolated(value) == expected for value, expected in cases):
        sys.exit('QA_URL_ROUTE_SELFTEST_FAILED')
    print('QA_URL_ROUTE_SELFTEST_PASS cases=' + str(len(cases)))
else:
    try:
        sys.exit(0 if isolated(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')) else 1)
    except (OSError, UnicodeError, ValueError):
        sys.exit(1)
PY
}

check_qa_runtime_readiness() {
    local impl="$1" profile="$2"

    if [ -z "$impl" ] || [ ! -d "$impl/src" ]; then
        note "  － 略過，未提供可用的 impl 路徑"
        return
    fi

    local qa_scheme qa_mode qa_bundle_id qa_firebase_project_id qa_google_app_id
    local qa_firebase_config_sha256
    local qa_identity_mode
    local production_firebase_project_id production_bundle_id
    qa_scheme=$(profile_payload_value qaScheme "$profile")
    qa_mode=$(profile_payload_value qaMode "$profile")
    qa_bundle_id=$(profile_payload_value qaBundleId "$profile")
    qa_firebase_project_id=$(profile_payload_value qaFirebaseProjectId "$profile")
    qa_google_app_id=$(profile_payload_value qaGoogleAppId "$profile")
    qa_firebase_config_sha256=$(profile_payload_value qaFirebaseConfigSha256 "$profile")
    qa_identity_mode=$(profile_payload_value qaIdentityMode "$profile")
    production_firebase_project_id=$(profile_payload_value productionFirebaseProjectId "$profile")
    production_bundle_id=$(profile_payload_value productionBundleId "$profile")

    [ "$qa_scheme" = "SuSuGiGiApp-QA" ] || fail "qaScheme 必須為 SuSuGiGiApp-QA"
    [ "$qa_mode" = "Debug-QA" ] || fail "qaMode 必須為 Debug-QA"
    [ "$qa_bundle_id" = "com.almightyken0425.susugigiapp.qa" ] || fail "qaBundleId 不符 App QA 身分"
    [ "$qa_firebase_project_id" = "susugigi-qa" ] || fail "qaFirebaseProjectId 必須為 susugigi-qa"
    [ "$qa_google_app_id" = "1:352034825841:ios:40c5c3bcfa630b4a6a1dd0" ] || fail "qaGoogleAppId 不符 QA Firebase App"
    [ "$qa_firebase_config_sha256" = "$CANONICAL_QA_FIREBASE_CONFIG_SHA256" ] || \
        fail "qaFirebaseConfigSha256 必須為 canonical QA config SHA-256"
    [ "$qa_identity_mode" = "disposable-anonymous" ] || fail "qaIdentityMode 必須為 disposable-anonymous"
    [ "$production_firebase_project_id" = "susugigi-c4fb1" ] || fail "productionFirebaseProjectId 不符 Production Firebase"
    [ "$production_bundle_id" = "com.almightyken0425.susugigiapp" ] || fail "productionBundleId 不符 Production App"

    local scheme="$impl/ios/SuSuGiGiApp.xcodeproj/xcshareddata/xcschemes/$qa_scheme.xcscheme"
    local project="$impl/ios/SuSuGiGiApp.xcodeproj/project.pbxproj"
    local native="$impl/ios/SuSuGiGiApp/BuildEnvironmentModule.m"
    local runtime="$impl/src/qa/registerQaRuntime.ts"
    local runtime_test="$impl/src/qa/registerQaRuntime.test.ts"
    local enabled_harness="$impl/src/qa/enabledQaHarness.ts"
    local enabled_harness_test="$impl/src/qa/enabledQaHarness.test.ts"
    local app_harness_test="$impl/src/qa/appQaHarness.test.ts"
    local bridge="$impl/src/qa/QaRuntimeBridge.tsx"
    local bridge_test="$impl/src/qa/QaRuntimeBridge.test.ts"
    local interface="$impl/src/qa/interface.ts"
    local harness="$impl/src/qa/accountingQaHarness.ts"
    local overlay="$impl/src/qa/largeHistoryOverlay.ts"
    local overlay_test="$impl/src/qa/largeHistoryOverlay.test.ts"
    local overlay_real_db_test="$impl/src/qa/largeHistoryOverlay.realDb.test.ts"
    local overlay_production_test="$impl/src/qa/largeHistoryOverlay.production.test.ts"
    local sync_engine="$impl/src/services/syncEngine.ts"
    local sync_engine_test="$impl/src/services/syncEngine.test.ts"
    local run_backup="$impl/src/services/runBackup.ts"
    local run_backup_test="$impl/src/services/runBackup.test.ts"
    local user_service="$impl/src/services/userService.ts"
    local user_service_test="$impl/src/services/userService.test.ts"
    local initial_data="$impl/src/database/helpers/createInitialUserData.ts"
    local initial_data_test="$impl/src/database/helpers/createInitialUserData.test.ts"
    local recurring_logic="$impl/src/services/recurringLogic.ts"
    local recurring_logic_test="$impl/src/services/recurringLogic.test.ts"
    local premium_context="$impl/src/contexts/PremiumContext.tsx"
    local premium_context_test="$impl/src/contexts/PremiumContext.storeKit.test.tsx"
    local local_only_policy="$impl/src/services/localOnlyBackupPolicy.ts"
    local debug_ui="$impl/src/screens/Settings/MockDataSettingsScreen.tsx"
    local qa_app="$impl/src/qa/QaApp.tsx"
    local qa_entry="$impl/index.qa.js"
    local qa_launch_plan="$impl/src/qa/qaLaunchPlan.ts"
    local qa_entry_selection="$impl/src/qa/qaEntrySelection.ts"
    local operation_gate="$impl/src/qa/QaOperationGateApp.tsx"
    local operation_authorization="$impl/src/qa/qaOperationAuthorization.ts"
    local operation_authorization_test="$impl/src/qa/qaOperationAuthorization.test.ts"
    local invalid_launch_result="$impl/src/qa/invalidQaLaunch.ts"
    local qa_launch_plan_test="$impl/src/qa/qaLaunchPlan.test.ts"
    local session_proof="$impl/src/qa/qaSessionProof.ts"
    local session_proof_test="$impl/src/qa/qaSessionProof.test.ts"
    local disposal="$impl/src/qa/anonymousIdentityDisposal.ts"
    local disposal_test="$impl/src/qa/anonymousIdentityDisposal.test.ts"
    local bootstrap="$impl/src/qa/anonymousIdentityBootstrap.ts"
    local bootstrap_test="$impl/src/qa/anonymousIdentityBootstrap.test.ts"
    local app_check="$impl/src/services/appCheck.ts"
    local info_plist="$impl/ios/SuSuGiGiApp/Info.plist"
    local app_delegate="$impl/ios/SuSuGiGiApp/AppDelegate.swift"
    local native_isolation_test="$impl/src/qa/nativeQaBuildIsolation.test.ts"
    local auth_context="$impl/src/contexts/AuthContext.tsx"
    local auth_context_test="$impl/src/contexts/AuthContext.anonymousBootstrap.test.tsx"
    local production_entry="$impl/index.js"
    local production_graph="$impl/src/qa/productionModuleGraph.ts"
    local production_isolation="$impl/src/qa/productionModuleGraphIsolation.test.ts"
    local r06_ui_isolation="$impl/src/qa/r06UiIsolation.test.ts"
    local firebase="$impl/ios/GoogleService-Info-QA.plist"
    local prod_firebase="$impl/ios/GoogleService-Info.plist"
    local selector="$impl/ios/scripts/select-firebase-config.sh"
    local quality_root db_probe run_docs auth_plan
    quality_root=$(cd "$(dirname "$profile")" && pwd)
    db_probe="$quality_root/no2_qa_tools/query_local_db.sh"
    local fixture_cleanup="$quality_root/no2_qa_tools/cleanup_qa_fixtures.sh"
    local fixture_cleanup_test="$quality_root/no2_qa_tools/tests/cleanup_qa_fixtures_test.sh"
    local fixture_delete_transport="$quality_root/no2_qa_tools/delete_qa_fixture_subtree.py"
    local fixture_delete_transport_test="$quality_root/no2_qa_tools/tests/delete_qa_fixture_subtree_test.py"
    run_docs="$quality_root/no3_run_scripts"
    auth_plan="$quality_root/no2_regression_plan/no1_auth_bootstrap.md"
    local run_index="$run_docs/no0_index.md"
    local r01_runbook="$run_docs/no3_r01_bootstrap_identity.md"
    local r01_csv="$run_docs/no3_r01_bootstrap_identity.csv"
    local r02_runbook="$run_docs/no4_r02_entity_recording.md"
    local r02_csv="$run_docs/no4_r02_entity_recording.csv"
    local r03_runbook="$run_docs/no5_r03_backup_export.md"
    local r03_csv="$run_docs/no5_r03_backup_export.csv"
    local r08_runbook="$run_docs/no10_r08_preference_sync.md"
    local r08_csv="$run_docs/no10_r08_preference_sync.csv"
    local r10_runbook="$run_docs/no12_r10_payment_backend.md"
    local r11_runbook="$run_docs/no13_r11_subscription_lifecycle.md"
    local r12_runbook="$run_docs/no14_r12_teardown_rebirth.md"
    local r12_csv="$run_docs/no14_r12_teardown_rebirth.csv"
    local r13_runbook="$run_docs/no15_r13_backfill_verification.md"
    local r13_csv="$run_docs/no15_r13_backfill_verification.csv"
    local r14_runbook="$run_docs/no16_r14_pre_identity_offline_launch.md"
    local id status executor

    [ -f "$scheme" ] || fail "QA scheme 不存在"
    [ -f "$project" ] || fail "Xcode project 不存在"
    [ -f "$native" ] || fail "BuildEnvironmentModule 不存在"
    [ -f "$runtime" ] || fail "QA runtime 不存在"
    [ -f "$runtime_test" ] || fail "QA runtime 測試不存在"
    [ -f "$enabled_harness" ] || fail "QA enabled harness 不存在"
    [ -f "$enabled_harness_test" ] || fail "QA enabled harness 測試不存在"
    [ -f "$app_harness_test" ] || fail "QA app harness 測試不存在"
    [ -f "$bridge" ] || fail "QA runtime bridge 不存在"
    [ -f "$bridge_test" ] || fail "QA runtime bridge 測試不存在"
    [ -f "$interface" ] || fail "QA runtime interface 不存在"
    [ -f "$harness" ] || fail "Accounting QA harness 不存在"
    [ -f "$overlay" ] || fail "large history overlay 不存在"
    [ -f "$overlay_test" ] || fail "large history overlay 測試不存在"
    [ -f "$overlay_real_db_test" ] || fail "large history real DB 測試不存在"
    [ -f "$overlay_production_test" ] || fail "overlay Production 隔離測試不存在"
    [ -f "$sync_engine" ] || fail "syncEngine 不存在"
    [ -f "$sync_engine_test" ] || fail "syncEngine 測試不存在"
    [ -f "$run_backup" ] || fail "runBackup 不存在"
    [ -f "$run_backup_test" ] || fail "runBackup 測試不存在"
    [ -f "$user_service" ] || fail "userService 不存在"
    [ -f "$user_service_test" ] || fail "userService 測試不存在"
    [ -f "$initial_data" ] || fail "createInitialUserData 不存在"
    [ -f "$initial_data_test" ] || fail "createInitialUserData 測試不存在"
    [ -f "$recurring_logic" ] || fail "recurringLogic 不存在"
    [ -f "$recurring_logic_test" ] || fail "recurringLogic 測試不存在"
    [ -f "$premium_context" ] || fail "PremiumContext 不存在"
    [ -f "$premium_context_test" ] || fail "PremiumContext 測試不存在"
    [ -f "$local_only_policy" ] || fail "local-only backup policy 不存在"
    [ -f "$debug_ui" ] || fail "QA Debug UI 不存在"
    [ -f "$qa_app" ] || fail "QA App graph 不存在"
    [ -f "$qa_launch_plan" ] || fail "QA launch plan 不存在"
    [ -f "$qa_entry_selection" ] || fail "QA entry selector 不存在"
    [ -f "$operation_gate" ] || fail "QA operation gate 不存在"
    [ -f "$operation_authorization" ] || fail "QA operation authorization 不存在"
    [ -f "$operation_authorization_test" ] || fail "QA operation authorization 測試不存在"
    [ -f "$invalid_launch_result" ] || fail "QA invalid launch RESULT formatter 不存在"
    [ -f "$disposal" ] || fail "QA identity disposal 實作不存在"
    [ -f "$disposal_test" ] || fail "QA identity disposal 測試不存在"
    [ -f "$bootstrap" ] || fail "QA identity bootstrap 實作不存在"
    [ -f "$session_proof" ] || fail "QA session proof wrapper 不存在"
    [ -f "$session_proof_test" ] || fail "QA session proof wrapper 測試不存在"
    [ -f "$app_check" ] || fail "App Check 實作不存在"
    [ -f "$info_plist" ] || fail "iOS Info.plist 不存在"
    [ -f "$app_delegate" ] || fail "AppDelegate 不存在"
    [ -f "$native_isolation_test" ] || fail "native QA isolation 測試不存在"
    [ -f "$auth_context" ] || fail "AuthContext 不存在"
    [ -f "$auth_context_test" ] || fail "AuthContext QA guard 測試不存在"
    [ -f "$production_entry" ] || fail "Production entry 不存在"
    [ -f "$production_graph" ] || fail "Production module graph scanner 不存在"
    [ -f "$production_isolation" ] || fail "Production module graph isolation 測試不存在"
    [ -f "$r06_ui_isolation" ] || fail "R06 UI isolation 測試不存在"
    [ -f "$fixture_cleanup" ] || fail "QA fixture cleanup helper 不存在"
    [ -f "$fixture_cleanup_test" ] || fail "QA fixture cleanup stub test 不存在"
    [ -f "$fixture_delete_transport" ] || fail "QA fixture delete transport 不存在"
    [ -f "$fixture_delete_transport_test" ] || fail "QA fixture delete transport test 不存在"
    if [ -f "$fixture_cleanup" ]; then
        local cleanup_override cleanup_override_contract_ok=1
        for cleanup_override in \
            FIRESTORE_EMULATOR_HOST FIRESTORE_URL FIREBASE_EMULATOR_HUB \
            FIREBASE_AUTH_EMULATOR_HOST FIREBASE_AUTH_URL FIREBASE_AUTHPROXY_URL \
            FIREBASE_AUTH_MANAGEMENT_URL FIREBASE_IDENTITY_URL FIREBASE_API_URL \
            FIREBASE_GOOGLE_URL FIREBASE_TOKEN_URL \
            CLOUDSDK_API_ENDPOINT_OVERRIDES_AUTH CLOUDSDK_API_ENDPOINT_OVERRIDES_FIRESTORE \
            CLOUDSDK_PROXY_TYPE CLOUDSDK_PROXY_ADDRESS CLOUDSDK_PROXY_PORT \
            CLOUDSDK_PROXY_USERNAME CLOUDSDK_PROXY_PASSWORD \
            CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE CLOUDSDK_AUTH_TOKEN_HOST \
            CLOUDSDK_CONFIG CLOUDSDK_ACTIVE_CONFIG_NAME GCE_METADATA_HOST GCE_METADATA_ROOT \
            GOOGLE_API_USE_MTLS_ENDPOINT SSL_CERT_FILE SSL_CERT_DIR SSLKEYLOGFILE REQUESTS_CA_BUNDLE \
            CURL_CA_BUNDLE NODE_EXTRA_CA_CERTS GRPC_DEFAULT_SSL_ROOTS_FILE_PATH \
            PYTHONPATH PYTHONHOME PYTHONSTARTUP PYTHONINSPECT PYTHONBREAKPOINT \
            BASH_ENV ENV SHELLOPTS BASHOPTS BASH_XTRACEFD PS4 \
            DYLD_INSERT_LIBRARIES DYLD_LIBRARY_PATH LD_PRELOAD LD_LIBRARY_PATH \
            HTTP_PROXY HTTPS_PROXY ALL_PROXY \
            http_proxy https_proxy all_proxy NO_PROXY no_proxy; do
            rg -Fq "$cleanup_override" "$fixture_cleanup" 2>/dev/null || cleanup_override_contract_ok=0
            rg -Fq -- "-u $cleanup_override" "$fixture_cleanup" 2>/dev/null || cleanup_override_contract_ok=0
        done
        [ "$cleanup_override_contract_ok" -eq 1 ] || \
            fail "QA fixture cleanup 未完整拒絕並移除 endpoint、proxy、CA、loader、shell 與 Python overrides"
        if rg -Fq 'firebase firestore:delete' "$fixture_cleanup" 2>/dev/null || \
           rg -Fq 'users/$session_uid' "$fixture_cleanup" 2>/dev/null || \
           ! rg -Fq '"$SYSTEM_PYTHON" -I "$DELETE_HELPER"' "$fixture_cleanup" 2>/dev/null || \
           ! rg -Fq -- '--session-uid-stdin' "$fixture_cleanup" 2>/dev/null; then
            fail "QA fixture cleanup 未使用 stdin-only checked-in transport"
        fi
    fi
    if [ -f "$fixture_cleanup_test" ]; then
        for id in \
            FIRESTORE_EMULATOR_HOST FIRESTORE_URL FIREBASE_EMULATOR_HUB \
            FIREBASE_AUTH_EMULATOR_HOST FIREBASE_AUTH_URL FIREBASE_AUTHPROXY_URL \
            FIREBASE_AUTH_MANAGEMENT_URL FIREBASE_IDENTITY_URL FIREBASE_API_URL \
            FIREBASE_GOOGLE_URL FIREBASE_TOKEN_URL \
            CLOUDSDK_API_ENDPOINT_OVERRIDES_AUTH CLOUDSDK_API_ENDPOINT_OVERRIDES_FIRESTORE \
            CLOUDSDK_PROXY_ADDRESS CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE \
            SSL_CERT_FILE SSLKEYLOGFILE REQUESTS_CA_BUNDLE CURL_CA_BUNDLE PYTHONPATH PYTHONHOME \
            BASH_ENV ENV SHELLOPTS BASHOPTS BASH_XTRACEFD PS4 \
            DYLD_INSERT_LIBRARIES DYLD_LIBRARY_PATH LD_PRELOAD LD_LIBRARY_PATH \
            HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY no_proxy; do
            rg -Fq "$id" "$fixture_cleanup_test" 2>/dev/null || \
                fail "QA fixture cleanup stub test 未涵蓋 $id"
        done
        if ! rg -Fq '[ ! -s "$STUB_LOG" ]' "$fixture_cleanup_test" 2>/dev/null || \
           ! rg -Fq "'QA fixture cleanup rejected'" "$fixture_cleanup_test" 2>/dev/null || \
           ! rg -Fq 'assert_no_uid_or_raw_response "$override_name 拒絕"' "$fixture_cleanup_test" 2>/dev/null; then
            fail "QA fixture cleanup override test 未鎖零 CLI、固定錯誤與 UID 隔離"
        fi
    fi
    if [ -f "$fixture_delete_transport" ] && [ -f "$fixture_delete_transport_test" ]; then
        for transport_contract in \
            'FIRESTORE_ORIGIN = "https://firestore.googleapis.com"' \
            'class RejectRedirectHandler' \
            'urllib.request.ProxyHandler({})' \
            'def assert_safe_gcloud_config' \
            'MAX_PAGE_COUNT = 1000' \
            'MAX_RESPONSE_BYTES = 4 * 1024 * 1024' \
            'response.read(MAX_RESPONSE_BYTES + 1)' \
            'stdout=subprocess.PIPE' \
            'stderr=subprocess.DEVNULL' \
            '"showMissing": "true"' \
            'page_token in seen_page_tokens' \
            'value in seen_collection_ids' \
            'name in seen_document_names' \
            'value not in ALLOWED_ROOT_COLLECTIONS' \
            'transport.list_collection_ids(child_name, token)' \
            'len(statuses) != len(batch)' \
            'transport.batch_delete([root], token)'; do
            rg -Fq "$transport_contract" "$fixture_delete_transport" 2>/dev/null || \
                fail "QA fixture delete transport 缺安全契約：$transport_contract"
        done
        for transport_test_contract in \
            'unknown_seventh_collection_fails_before_any_delete' \
            'nested_collection_fails_before_any_delete' \
            'batch_delete_rejects_any_missing_or_nonzero_status' \
            'redirect_handler_never_follows_location' \
            'proxy_override_rejects_before_oauth' \
            'repeated_collection_page_token_fails_closed' \
            'duplicate_collection_id_across_pages_fails_closed' \
            'document_pagination_has_finite_upper_bound' \
            'duplicate_document_name_across_pages_fails_closed' \
            'unsafe_gcloud_config_rejects_before_subprocess' \
            'response_body_over_limit_fails_closed_after_bounded_read' \
            'gcloud_token_provider_discards_child_stderr'; do
            rg -Fq "$transport_test_contract" "$fixture_delete_transport_test" 2>/dev/null || \
                fail "QA fixture delete transport test 缺負向樣本：$transport_test_contract"
        done
    fi
    local cleanup_contract
    for cleanup_contract in \
        '最外層 shell 必須是 Control 提供的 trusted launcher' \
        'Control 必須在 spawn bash 前拒絕並清除 `BASH_ENV` 與 `ENV`' \
        'Control 必須在 spawn bash 前清除 `SHELLOPTS`、`BASHOPTS`、`BASH_XTRACEFD` 與 `PS4`' \
        'malicious `BASH_ENV` sentinel 整合測試必須證明 sentinel 零執行、helper 零呼叫與 UID 零洩漏' \
        'helper 內部檢查不是 shell startup injection 的安全邊界' \
        'helper 只准把 raw uid 經 stdin 傳給 checked-in OAuth REST transport' \
        'REST host 固定為 `https://firestore.googleapis.com`' \
        'transport 必須拒絕 redirect 並停用 proxy handler' \
        'transport 每次 response 最多讀四 MiB 加一 byte，超過四 MiB 必須 fail-closed' \
        'root collection ids 可為六個固定 id 的子集，支援冪等與 partial cleanup，不要求六者同時存在' \
        '出現未知第七 collection 或任一 nested collection 時必須在刪除前 fail-closed' \
        'pagination 必須有固定頁數上限，重複 page token、collection id 或 document name 一律 fail-closed' \
        'transport 必須逐筆驗證 delete status，全部 child 成功後才可刪 users root' \
        'Control 必須以同一個 shell-memory `QA_SESSION_UID` 執行 users 文件、六個子集合與 root collection ids 的 post-delete absent probes' \
        'gcloud Firestore OAuth provider 缺少時整體 cleanup 狀態固定失敗' \
        'gcloud Firestore OAuth provider 缺少或 Firestore cleanup 失敗時仍必須繼續 Firebase Auth disposal' \
        'session 最終結果必須聚合 Firestore cleanup 與 Auth disposal' \
        '任一結果失敗時 session cleanup 整體 fail-closed'; do
        grep -Fq "$cleanup_contract" "$profile" 2>/dev/null || \
            fail "能力側寫缺 cleanup 聚合契約：$cleanup_contract"
    done
    if ! grep -Fq '| qa-cleanup |' "$profile" 2>/dev/null || \
       ! grep -Fq 'gcloud Firestore OAuth 可取得 access token' "$profile" 2>/dev/null || \
       ! grep -Fq 'Control 必須同 UID 執行 post-delete absent probes' "$profile" 2>/dev/null; then
        fail "能力側寫缺 qa-cleanup Control post-delete 能力"
    fi
    if ! grep -Fq 'Firebase CLI Auth 只供 Auth export、exact UID 與 absence control' "$profile" 2>/dev/null || \
       ! grep -Fq 'gcloud Firestore OAuth 供 Firestore REST read 與 fixture cleanup' "$profile" 2>/dev/null || \
       ! grep -Fq 'Firebase CLI Auth 與 gcloud Firestore OAuth 的 readiness 不得互相推定' "$profile" 2>/dev/null; then
        fail "能力側寫未拆分 Firebase CLI Auth 與 gcloud Firestore OAuth readiness"
    fi
    [ -f "$selector" ] || fail "Firebase config selector 不存在"
    [ -f "$db_probe" ] || fail "QA SQLite probe 不存在"

    if [ -f "$scheme" ] && [ -n "$qa_mode" ]; then
        rg -Fq "buildConfiguration = \"$qa_mode\"" "$scheme" 2>/dev/null || fail "QA scheme 未使用 $qa_mode"
    fi
    if [ -f "$project" ] && [ -n "$qa_bundle_id" ]; then
        rg -Fq "PRODUCT_BUNDLE_IDENTIFIER = $qa_bundle_id;" "$project" 2>/dev/null || fail "Impl QA bundle id 不符 $qa_bundle_id"
    fi
    if [ -f "$project" ]; then
        if rg -Fq 'GoogleService-Info.plist in Resources' "$project" 2>/dev/null; then
            fail "Production GoogleService-Info.plist 不得固定列入 Resources"
        fi
        xcode_firebase_phase_order_ok "$project" || fail "Xcode Firebase phase 順序錯誤"
    fi
    if [ -f "$selector" ]; then
        grep -Fq 'source_plist="$project_dir/GoogleService-Info-QA.plist"' "$selector" || \
            fail "Firebase selector QA source 必須為 ios/GoogleService-Info-QA.plist"
        grep -Fq 'source_plist="$project_dir/GoogleService-Info.plist"' "$selector" || \
            fail "Firebase selector Production source 必須為 ios/GoogleService-Info.plist"
    fi

    for flag in --qa-request-id --qa-open-app --qa-prepare --qa-inspect --qa-dispose-identity; do
        rg -q -- "$flag" "$native" 2>/dev/null || fail "native launch flag 不存在：$flag"
    done
    if ! rg -Fq 'environment[@"SUSUGIGI_QA_SESSION_TOKEN"]' "$native" 2>/dev/null || \
       rg -Fq -- '--qa-session-token' "$native" 2>/dev/null || \
       ! test_block_has "$native_isolation_test" \
        'session token 只從 process environment 載入' \
        "expect(nativeModule).not.toContain('--qa-session-token')"; then
        fail "QA session token 未使用 process environment secret seam"
    fi
    rg -Fq 'const sessionTokenPattern = /^[a-f0-9]{64}$/;' "$qa_launch_plan" 2>/dev/null || \
        fail "QA session token 未限制為 64-hex secret"
    if ! rg -Fq 'const requestIdPattern = /^(?:bootstrap|dispose|first-launch|inspect|open-app|prepare)-[a-f0-9]{32}$/;' "$qa_launch_plan" 2>/dev/null && \
       ! rg -Fq 'const requestIdPattern = /^(?:bootstrap|dispose|first-launch|inspect|open-app|prepare)-[0-9a-f]{32}$/;' "$qa_launch_plan" 2>/dev/null; then
        fail "QA requestId 未限制為 operation prefix 加 32-lowerhex"
    fi
    if ! rg -Fq 'function expectedRequestIdPrefix(input: QaLaunchPlanInput): string' "$qa_launch_plan" 2>/dev/null || \
       ! rg -Fq '!input.requestId.startsWith(`${expectedRequestIdPrefix(input)}-`)' "$qa_launch_plan" 2>/dev/null; then
        fail "QA requestId prefix 未與 launch kind 綁定"
    fi
    rg -Fq 'operationCount > 1' "$qa_launch_plan" 2>/dev/null || \
        fail "QA launch plan 未拒絕多 operation"
    rg -Fq "requestId: requestId('prepare', 'b')" "$qa_launch_plan_test" 2>/dev/null || \
        fail "QA launch plan 缺 prepare 與 inspect 互斥測試"
    rg -Fq "requestId: requestId('open-app', 'a')" "$qa_launch_plan_test" 2>/dev/null || \
        fail "QA launch plan 缺 open-app 互斥測試"
    if ! rg -q 'requestId: .*prepare-.*A.*repeat[(]32[)]' "$qa_launch_plan_test" 2>/dev/null || \
       ! rg -Fq "requestId: 'prepare-short'" "$qa_launch_plan_test" 2>/dev/null || \
       ! rg -Fq "requestId: requestId('inspect', '9'), sessionToken, prepareScene: 'r02_end'" "$qa_launch_plan_test" 2>/dev/null; then
        fail "QA requestId malformed 與 prefix mismatch 負向測試不完整"
    fi
    for proof_contract in \
        '@"tokenHash"' \
        '@"uidHash"' \
        'NSString *tokenHash = QaSha256(token)' \
        'NSString *uidHash = QaSha256(uid)' \
        'QaSessionProofTTL = 8.0 * 60.0 * 60.0' \
        '!isfinite(expiresAt.doubleValue)' \
        'expiresAt.doubleValue <= 0.0' \
        'expiresAt.doubleValue > NSDate.date.timeIntervalSince1970 + QaSessionProofTTL' \
        'consumeQaSessionProof' \
        'QaBindingHash(operationBinding)' \
        'QaContainsHash(consumedRequestHashes, requestHash)' \
        'updatedProof[@"expiresAt"] = @(NSDate.date.timeIntervalSince1970 + QaSessionProofTTL)'; do
        rg -Fq "$proof_contract" "$native" 2>/dev/null || \
            fail "native session proof 缺契約：$proof_contract"
    done
    local proof_allowed_keys_block="${CHECK_TMP_PREFIX}_proof_allowed_keys.txt"
    local proof_actual_keys="${CHECK_TMP_PREFIX}_proof_actual_keys.txt"
    local proof_expected_keys="${CHECK_TMP_PREFIX}_proof_expected_keys.txt"
    awk '
        /^static NSSet<NSString \*> \*QaProofAllowedKeys\(void\)/ {capture=1}
        capture {print}
        capture && /^}/ {exit}
    ' "$native" > "$proof_allowed_keys_block"
    grep -oE '@"[A-Za-z][A-Za-z0-9]*"' "$proof_allowed_keys_block" 2>/dev/null | \
        sed 's/^@"//; s/"$//' | sort -u > "$proof_actual_keys"
    printf '%s\n' \
        consumedBindings consumedRequestHashes expiresAt state tokenHash uidHash | \
        sort > "$proof_expected_keys"
    if ! diff -q "$proof_expected_keys" "$proof_actual_keys" >/dev/null 2>&1; then
        fail "native session proof persisted key set 不等於 exact 六 keys"
    fi
    local proof_shape_block="${CHECK_TMP_PREFIX}_proof_shape.txt"
    awk '
        /^static BOOL QaProofHasValidShape\(NSDictionary \*proof\)/ {capture=1}
        capture && /^static NSDictionary \*QaReadProof\(void\)/ {exit}
        capture {print}
    ' "$native" > "$proof_shape_block"
    local proof_key_equality_line proof_first_field_line
    proof_key_equality_line=$(grep -nF '[actualKeys isEqualToSet:QaProofAllowedKeys()]' \
        "$proof_shape_block" 2>/dev/null | head -1 | cut -d: -f1)
    proof_first_field_line=$(grep -nF 'proof[@"tokenHash"]' \
        "$proof_shape_block" 2>/dev/null | head -1 | cut -d: -f1)
    if ! rg -Fq 'NSSet *actualKeys = [NSSet setWithArray:proof.allKeys];' "$proof_shape_block" 2>/dev/null || \
       [ -z "$proof_key_equality_line" ] || \
       [ -z "$proof_first_field_line" ] || \
       [ "$proof_key_equality_line" -ge "$proof_first_field_line" ]; then
        fail "native session proof 未在欄位讀取前拒絕額外 key"
    fi
    local proof_exact_key_test_missing=0
    for proof_exact_key_test_contract in \
        'QaProofAllowedKeys' \
        '[actualKeys isEqualToSet:QaProofAllowedKeys()]' \
        'proof.allKeys' \
        "shape.indexOf('isEqualToSet')" \
        '@"consumedRequestHashes"' \
        '@"(?:token|uid)"'; do
        if ! test_block_has "$native_isolation_test" \
            'persisted session proof 只接受 exact 六欄，拒絕額外 raw 或舊欄位' \
            "$proof_exact_key_test_contract"; then
            proof_exact_key_test_missing=1
        fi
    done
    if [ "$proof_exact_key_test_missing" -eq 1 ]; then
        fail "native session proof exact-key 負向 source test 不完整"
    fi
    local proof_hash_shape_contract_missing=0
    for hash_shape_contract in \
        'static BOOL QaIsLowerHexSha256(NSString *value)' \
        'value.length != 64' \
        'characterSetWithCharactersInString:@"0123456789abcdef"' \
        '!QaIsLowerHexSha256(tokenHash)' \
        '!QaIsLowerHexSha256(uidHash)' \
        '!QaIsLowerHexSha256(bindingHash)' \
        '!QaIsLowerHexSha256(requestHash)'; do
        if ! rg -Fq "$hash_shape_contract" "$native" 2>/dev/null; then
            proof_hash_shape_contract_missing=1
        fi
    done
    if [ "$proof_hash_shape_contract_missing" -eq 1 ]; then
        fail "native session proof persisted hash 缺 64-lowerhex 共用 shape gate"
    fi
    local proof_hash_shape_test_missing=0
    for hash_shape_test_contract in \
        'QaIsLowerHexSha256' \
        'characterSetWithCharactersInString:@"0123456789abcdef"' \
        '!QaIsLowerHexSha256(tokenHash)' \
        '!QaIsLowerHexSha256(uidHash)' \
        '!QaIsLowerHexSha256(bindingHash)' \
        '!QaIsLowerHexSha256(requestHash)'; do
        if ! test_block_has "$native_isolation_test" \
            'session proof 只存 SHA-256 並以 constant-time 比對' \
            "$hash_shape_test_contract"; then
            proof_hash_shape_test_missing=1
        fi
    done
    if [ "$proof_hash_shape_test_missing" -eq 1 ]; then
        fail "native session proof persisted hash shape 負向 source test 不完整"
    fi
    if ! test_block_has "$native_isolation_test" \
        'session proof 限制 TTL 與 consumed binding replay set' \
        '!isfinite(expiresAt.doubleValue)' || \
       ! test_block_has "$native_isolation_test" \
        'session proof 限制 TTL 與 consumed binding replay set' \
        'expiresAt.doubleValue <= 0.0' || \
       ! test_block_has "$native_isolation_test" \
        'session proof 限制 TTL 與 consumed binding replay set' \
        'expiresAt.doubleValue > NSDate.date.timeIntervalSince1970 + QaSessionProofTTL'; then
        fail "native session proof 非有限或非正 expiry 測試不存在"
    fi
    if rg -q 'setObject:[[:space:]]*(token|uid)' "$native" 2>/dev/null; then
        fail "native session proof 不得保存 raw token 或 uid"
    fi
    rg -Fq 'consumeQaSessionProof' "$operation_authorization" 2>/dev/null || \
        fail "QA operation 未消耗 session proof"
    rg -Fq 'operations.length !== 1' "$operation_authorization" 2>/dev/null || \
        fail "QA operation authorization 未拒絕多 operation"
    rg -Fq "plan.openApp ? 'open-app:true' : null" "$operation_authorization" 2>/dev/null || \
        fail "open-app 未綁定 exact operation value"
    if rg -q '__SUSUGIGI_QA__[[:space:]]*=' "$runtime" 2>/dev/null; then
        fail "QA runtime 不得發布 global adapter"
    fi
    if ! test_block_has "$runtime_test" \
        'launch-driven runtime 不發布 global adapter' \
        '__SUSUGIGI_QA__).toBeUndefined()' || \
       ! test_block_has "$bridge_test" \
        'open-app plan 只建立 READY，不暴露或執行 prepare／inspect' \
        'expect(runtime.prepare).not.toHaveBeenCalled()' || \
       ! test_block_has "$bridge_test" \
        'open-app plan 只建立 READY，不暴露或執行 prepare／inspect' \
        'expect(runtime.inspect).not.toHaveBeenCalled()' || \
       ! test_block_has "$bridge_test" \
        'open-app plan 只建立 READY，不暴露或執行 prepare／inspect' \
        '__SUSUGIGI_QA__).toBeUndefined()'; then
        fail "open-app global absence 與零 operation 測試不完整"
    fi
    if ! test_block_has "$native_isolation_test" \
        '同 requestId 即使換 operation payload 仍拒絕 replay' \
        'QaContainsHash(consumedRequestHashes, requestHash)' || \
       ! test_block_has "$native_isolation_test" \
        '同 requestId 即使換 operation payload 仍拒絕 replay' \
        '[consumedRequestHashes arrayByAddingObject:requestHash]'; then
        fail "operation root A→B 或 replay 防護測試不完整"
    fi
    if ! awk '
        /authorizeQaOperation\(plan\)/ {authorized=NR}
        /require\('\''[.]\/QaApp'\''\)/ {mounted=NR}
        END {exit !(authorized > 0 && mounted > authorized)}
    ' "$operation_gate" 2>/dev/null; then
        fail "QA App 必須在 operation proof 授權後才掛載"
    fi
    rg -Fq 'qaAuthGuardTerminalBlocked.current = true' "$auth_context" 2>/dev/null || \
        fail "AuthProvider 缺 QA terminal latch"
    rg -Fq 'QA strict guard mismatch 後即使 expected UID 到達也永久 blocked' "$auth_context_test" 2>/dev/null || \
        fail "AuthProvider terminal latch 測試不存在"
    rg -Fq 'expect(mockHandlePostAuth).not.toHaveBeenCalled()' "$auth_context_test" 2>/dev/null || \
        fail "AuthProvider terminal latch 測試未鎖 post-auth"
    local epoch_invalidation_count
    epoch_invalidation_count=$(rg -Fc 'qaAuthIdentityEpochRef.current += 1;' "$auth_context" 2>/dev/null || true)
    if ! rg -Fq 'const qaAuthIdentityEpochRef = useRef(0);' "$auth_context" 2>/dev/null || \
       [ "${epoch_invalidation_count:-0}" -lt 2 ] || \
       ! rg -Fq 'validationEpoch !== qaAuthIdentityEpochRef.current' "$auth_context" 2>/dev/null || \
       ! rg -Fq 'qaAuthIdentityEpochRef.current === validationEpoch' "$auth_context" 2>/dev/null; then
        fail "AuthProvider 缺同步 identity epoch invalidation"
    fi
    if ! rg -Fq 'await handlePostAuth(authUser.uid, authUser, isCurrent);' "$auth_context" 2>/dev/null || \
       ! rg -Fq 'await startPostAuth(authUser, isCurrentAuthIdentity);' "$auth_context" 2>/dev/null; then
        fail "AuthProvider 未將 identity guard 傳入 post-auth"
    fi
    local auth_race_test_title auth_race_test_missing=0
    for auth_race_test_title in \
        'QA valid post-auth 尚未收斂時遇到不同 UID，舊流程不得繼續 setUser、補排程或備份' \
        'QA valid post-auth 尚未收斂時遇到 null，舊流程不得繼續 setUser、補排程或備份' \
        'QA valid post-auth 尚未收斂時同 UID 變成非匿名，也同步失效舊流程'; do
        for auth_race_assertion in \
            'expect(mockFindLocalUser).not.toHaveBeenCalled()' \
            'expect(lastAuthState?.user).toBeNull()' \
            'expect(mockGenerateMissingInstances).not.toHaveBeenCalled()' \
            'expect(mockRunBackup).not.toHaveBeenCalled()'; do
            if ! test_block_has "$auth_context_test" \
                "$auth_race_test_title" \
                "$auth_race_assertion"; then
                auth_race_test_missing=1
            fi
        done
    done
    if [ "$auth_race_test_missing" -eq 1 ]; then
        fail "AuthProvider auth race 負向測試未鎖 stale setUser、排程與備份"
    fi
    if ! rg -Fq 'await generateMissingInstances(finalUser.id, isCurrent);' "$auth_context" 2>/dev/null; then
        fail "AuthProvider 未將 identity guard 傳入 recurring backfill"
    fi
    if ! rg -Uq '(?s)export type RecurringIdentityGuard = \(\) => boolean;.*?export function generateMissingInstances\([[:space:]]*userId: string,[[:space:]]*isCurrent[?]: RecurringIdentityGuard,[[:space:]]*\): Promise<void>' "$recurring_logic" 2>/dev/null || \
       ! rg -Uq '(?s)type InFlightBackfill = \{.*?guards: Set<RecurringIdentityGuard>;.*?promise: Promise<void>;.*?\};' "$recurring_logic" 2>/dev/null || \
       ! rg -Uq '(?s)if \(isCurrent && !isRecurringIdentityGuardCurrent\(isCurrent\)\) \{.*?return Promise[.]resolve\(\);.*?\}' "$recurring_logic" 2>/dev/null || \
       ! rg -Uq '(?s)const existing = inFlightByUser[.]get\(userId\);.*?if \(existing\) \{.*?existing[.]guards[.]add\(isCurrent\);.*?return existing[.]promise;' "$recurring_logic" 2>/dev/null || \
       ! rg -Uq '(?s)const compositeGuard = \(\) => areRecurringIdentityGuardsCurrent\(guards\);.*?doGenerateMissingInstances\(userId, compositeGuard\)' "$recurring_logic" 2>/dev/null || \
       ! rg -Uq '(?s)const isRecurringIdentityGuardCurrent.*?try \{.*?return guard\(\);.*?\} catch \{.*?return false;' "$recurring_logic" 2>/dev/null || \
       ! rg -Fq 'await generateMissingInstances(data.userId);' "$recurring_logic" 2>/dev/null; then
        fail "recurringLogic 缺 optional stale identity guard 與 dynamic in-flight aggregation"
    fi
    if ! awk '
        function trim(value) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            return value
        }
        /^async function doGenerateMissingInstances\(/ {active=1}
        active {
            line=$0
            normalized=trim(line)
            if (needsGuard) {
                if (normalized == "") {next}
                if (normalized != "if (!isCurrent()) { return; }") {bad=1}
                needsGuard=0
            }
            if (awaitOpen) {
                if (index(line, ";") > 0) {
                    awaitOpen=0
                    needsGuard=1
                }
                next
            }
            if (index(line, "await ") > 0) {
                awaitCount++
                if (index(line, ";") > 0) {needsGuard=1}
                else {awaitOpen=1}
            }
        }
        END {exit !(active && awaitCount > 0 && !bad && !awaitOpen && !needsGuard)}
    ' "$recurring_logic" 2>/dev/null || \
       ! rg -Uq '(?s)if \(!isCurrent\(\)\) \{ return; \}[[:space:]]*await createTransfer\(' "$recurring_logic" 2>/dev/null || \
       ! rg -Uq '(?s)if \(!isCurrent\(\)\) \{ return; \}[[:space:]]*await createTransaction\(' "$recurring_logic" 2>/dev/null; then
        fail "recurringLogic 未在每個 await 後與 transaction/transfer create 前後重驗 identity"
    fi
    local recurring_guard_test_missing=0
    for recurring_guard_contract in \
        '既有 unguarded run 加入 guarded caller 後，UID flip 讓 pending write 結束即停止|expect(createTransactionMock).toHaveBeenCalledTimes(1)|expect(stores.transactions).toHaveLength(2)' \
        'guard 已失效才加入既有 unguarded run 時只 no-op，不取消合法 backfill|expect(createTransactionMock).toHaveBeenCalledTimes(4)|expect(stores.transactions).toHaveLength(5)' \
        'guarded transfer backfill 遇到 null flip，pending write 結束後零後續 write|expect(createTransferMock).toHaveBeenCalledTimes(1)|expect(stores.transfers).toHaveLength(2)'; do
        IFS='|' read -r recurring_guard_title recurring_guard_assertion_a recurring_guard_assertion_b <<EOF
$recurring_guard_contract
EOF
        if ! test_block_has "$recurring_logic_test" "$recurring_guard_title" "$recurring_guard_assertion_a" || \
           ! test_block_has "$recurring_logic_test" "$recurring_guard_title" "$recurring_guard_assertion_b"; then
            recurring_guard_test_missing=1
        fi
    done
    if [ "$recurring_guard_test_missing" -eq 1 ]; then
        fail "recurringLogic identity flip 負向測試未鎖零後續本地寫入"
    fi
    local auth_recurring_test_missing=0
    for auth_recurring_title in \
        'QA recurring backfill pending 時遇到不同 UID，傳入 guard 失效且不再備份' \
        'QA recurring backfill pending 時遇到 null，傳入 guard 失效且不再備份'; do
        for auth_recurring_assertion in \
            'expect(recurringGuard()).toBe(true)' \
            'expect(recurringGuard()).toBe(false)' \
            'expect(mockRunBackup).not.toHaveBeenCalled()' \
            'expect(lastAuthState?.user).toBeNull()'; do
            if ! test_block_has "$auth_context_test" \
                "$auth_recurring_title" \
                "$auth_recurring_assertion"; then
                auth_recurring_test_missing=1
            fi
        done
    done
    if [ "$auth_recurring_test_missing" -eq 1 ]; then
        fail "AuthProvider recurring identity flip 負向測試不完整"
    fi
    local post_auth_guard_count
    post_auth_guard_count=$(rg -Fc 'const guard = isCurrent ?? alwaysCurrentAuthIdentity;' "$user_service" 2>/dev/null || true)
    if [ "${post_auth_guard_count:-0}" -lt 3 ] || \
       ! rg -Uq '(?s)createInitialUserData\(.*?guard\)' "$user_service" 2>/dev/null || \
       ! rg -Uq '(?s)syncUserToFirestore\(.*?guard\)' "$user_service" 2>/dev/null || \
       ! rg -Uq '(?s)initializeNewUser\(.*?guard\)' "$user_service" 2>/dev/null; then
        fail "post-auth 未將 isCurrent guard 傳過本地 seed 與 Firestore write stage"
    fi
    local initial_data_guard_count
    initial_data_guard_count=$(rg -Fc 'if (!isCurrent()) {return;}' "$initial_data" 2>/dev/null || true)
    if ! rg -Fq 'isCurrent: () => boolean = () => true' "$initial_data" 2>/dev/null || \
       [ "${initial_data_guard_count:-0}" -lt 4 ]; then
        fail "createInitialUserData 缺 stale identity write guard"
    fi
    if ! test_block_has "$initial_data_test" \
        '身分在進入前已失效，不得開 transaction 或解析任何 seed table' \
        'expect(dbMock.__state.requestedTables).toHaveLength(0)' || \
       ! test_block_has "$initial_data_test" \
        'count probe 期間身分失效，不得繼續建立 account 或 category' \
        'expect(dbMock.__state.created.accounts).toHaveLength(0)' || \
       ! test_block_has "$initial_data_test" \
        'count probe 期間身分失效，不得繼續建立 account 或 category' \
        'expect(dbMock.__state.created.categories).toHaveLength(0)'; then
        fail "createInitialUserData stale identity 負向測試不完整"
    fi
    if ! test_block_has "$user_service_test" \
        'Firestore existence read 尚未完成就失效，不得進入任何本地或雲端寫入' \
        'expect(createInitialUserData).not.toHaveBeenCalled()' || \
       ! test_block_has "$user_service_test" \
        'Firestore existence read 尚未完成就失效，不得進入任何本地或雲端寫入' \
        'expect(firestoreMock.__doc.set).not.toHaveBeenCalled()' || \
       ! test_block_has "$user_service_test" \
        'Firestore existence read 尚未完成就失效，不得進入任何本地或雲端寫入' \
        'expect(firestoreMock.__doc.update).not.toHaveBeenCalled()' || \
       ! test_block_has "$user_service_test" \
        '本地使用者查詢尚未完成就失效，不得開始 user、Settings 或 seed 寫入' \
        'expect(dbMock.__stores.users.size).toBe(0)' || \
       ! test_block_has "$user_service_test" \
        '本地偏好讀取尚未完成就失效，不得排入 Firestore set 或 update' \
        'expect(firestoreMock.__doc.set).not.toHaveBeenCalled()' || \
       ! test_block_has "$user_service_test" \
        'create 排入後身分失效，拒絕失敗回呼再發 fallback update' \
        'expect(firestoreMock.__doc.update).not.toHaveBeenCalled()'; then
        fail "post-auth stale identity 負向測試未鎖 local 或 Firestore orphan prevention"
    fi
    if ! rg -Uq '(?s)const qaBackupIdentityGuardRef = useRef<BackupIdentityGuard \| undefined>\(.*?undefined,.*?\);' "$auth_context" 2>/dev/null || \
       ! rg -Uq '(?s)qaBackupIdentityGuardRef[.]current = \{.*?expectedUid: validatedUid,.*?isCurrent: isCurrentAuthIdentity' "$auth_context" 2>/dev/null || \
       ! rg -Uq '(?s)runBackup\(qaAuthGuard.*?expectedUid: authUser[.]uid, isCurrent' "$auth_context" 2>/dev/null; then
        fail "AuthProvider 未把當輪 UID 與 epoch guard 綁入 background backup"
    fi
    if ! test_block_has "$auth_context_test" \
        'QA strict guard 首次就是 expected UID hash 才進入 post-auth' \
        "expectedUid: 'guarded-anon'" || \
       ! test_block_has "$auth_context_test" \
        'QA strict guard 首次就是 expected UID hash 才進入 post-auth' \
        'isCurrent: expect.any(Function)'; then
        fail "AuthProvider background backup guard 測試不存在"
    fi
    if ! rg -Fq 'export type BackupIdentityGuard = SyncIdentityGuard;' "$run_backup" 2>/dev/null || \
       ! rg -Uq '(?s)export function runBackup\(.*?guard[?]: BackupIdentityGuard,.*?loadSyncEngine: SyncEngineLoader.*?\): void' "$run_backup" 2>/dev/null || \
       ! rg -Fq 'currentUser?.uid === guard.expectedUid' "$run_backup" 2>/dev/null || \
       ! rg -Fq 'currentUser.isAnonymous === true' "$run_backup" 2>/dev/null || \
       ! rg -Uq '(?s)loadSyncEngine\(\)[.]then.*?if \(!isIdentityCurrent\(guard\)\) \{return;\}.*?syncEngine[.]sync\(guard\)' "$run_backup" 2>/dev/null; then
        fail "runBackup 未在 dynamic import settle 後驗 UID、匿名狀態與 epoch guard"
    fi
    if ! test_block_has "$run_backup_test" \
        'dynamic import settle 前 epoch 失效，不得呼叫 syncEngine' \
        'expect(mockSync).not.toHaveBeenCalled()' || \
       ! test_block_has "$run_backup_test" \
        'dynamic import settle 前 Firebase UID 改變，不得呼叫 syncEngine' \
        'expect(mockSync).not.toHaveBeenCalled()' || \
       ! test_block_has "$run_backup_test" \
        '同一匿名身分仍有效時把完整 guard 傳給 syncEngine' \
        'expect(mockSync).toHaveBeenCalledWith(guard)' || \
       ! test_block_has "$run_backup_test" \
        'Production 未提供 guard 時維持既有 fire-and-forget 委派' \
        'expect(mockSync).toHaveBeenCalledWith(undefined)'; then
        fail "runBackup identity-bound delegation 負向測試不完整"
    fi
    if ! rg -Uq '(?s)export type SyncIdentityGuard = Readonly<\{.*?expectedUid: string;.*?isCurrent\(\): boolean;' "$sync_engine" 2>/dev/null || \
       ! rg -Fq 'function assertSyncIdentity(guard?: SyncIdentityGuard): void' "$sync_engine" 2>/dev/null || \
       ! rg -Fq 'authUser?.uid === guard.expectedUid' "$sync_engine" 2>/dev/null || \
       ! rg -Fq 'authUser.isAnonymous === true' "$sync_engine" 2>/dev/null || \
       ! rg -Uq '(?s)async function awaitForSyncIdentity.*?assertSyncIdentity\(guard\);.*?const result = await operation\(\);.*?assertSyncIdentity\(guard\);' "$sync_engine" 2>/dev/null || \
       ! rg -Uq '(?s)async function pushBatches.*?assertSyncIdentity\(identityGuard\);.*?writeBatch\(db\).*?assertSyncIdentity\(identityGuard\);.*?batch[.]set' "$sync_engine" 2>/dev/null || \
       ! rg -Uq '(?s)batch[.]commit\(\).*?identityGuard' "$sync_engine" 2>/dev/null; then
        fail "syncEngine 未在 await 與 Firestore batch 邊界重驗 expected UID guard"
    fi
    local sync_guard_test_missing=0
    for sync_guard_test_title in \
        'QA guard 在 quota await 期間失效，不得讀本地資料或建立 Firestore batch' \
        'QA guard 在 local snapshot await 期間失效，不得排入任何 Firestore write' \
        'QA guard 在 batch 建立邊界失效，第一筆 set 前即 fail-closed'; do
        if ! test_block_has "$sync_engine_test" \
            "$sync_guard_test_title" \
            'expect(fsMock.__batchSet).not.toHaveBeenCalled()' || \
           ! test_block_has "$sync_engine_test" \
            "$sync_guard_test_title" \
            'expect(fsMock.__batchCommit).not.toHaveBeenCalled()'; then
            sync_guard_test_missing=1
        fi
    done
    if [ "$sync_guard_test_missing" -eq 1 ]; then
        fail "syncEngine identity flip 負向測試未鎖 Firestore batch 零寫入"
    fi
    if ! rg -Fq 'const { user, qaBackupIdentityGuard } = useAuth();' "$premium_context" 2>/dev/null || \
       ! rg -Fq 'runBackup(qaBackupIdentityGuard);' "$premium_context" 2>/dev/null || \
       ! test_block_has "$premium_context_test" \
        '前景 trigger 把 AuthProvider 的 QA identity guard 原樣傳給 backup' \
        'expect(mockRunBackup).toHaveBeenCalledWith(guard)'; then
        fail "Premium foreground backup 未沿用 AuthProvider session guard"
    fi
    if ! rg -Fq 'const effectiveUserId = isLoading ? null : userId;' "$bridge" 2>/dev/null || \
       ! rg -Uq '(?s)bindingSession[.]current[.]next\(.*?isLoading \|\| resolution[.]error !== null' "$bridge" 2>/dev/null || \
       ! rg -Uq '(?s)if \(isLoading\) \{.*?return;.*?\}' "$bridge" 2>/dev/null; then
        fail "QA runtime bridge 未以 AuthProvider isLoading 阻擋 READY binding"
    fi
    if ! test_block_has "$bridge_test" \
        'auth post-processing 尚未完成時不綁定，完成後只綁定一次' \
        "session.next('user-a', plan, true)).toBeNull()" || \
       ! test_block_has "$bridge_test" \
        'auth post-processing 尚未完成時不綁定，完成後只綁定一次' \
        "session.next('user-a', plan, false)).toBeNull()" || \
       ! rg -Uq '(?s)await startPostAuth\(authUser, isCurrentAuthIdentity\);.*?if \(!isCurrentAuthIdentity\(\)\) \{ return; \}.*?setIsLoading\(false\);' "$auth_context" 2>/dev/null; then
        fail "post-auth settled-by-construction 測試或 isLoading 收斂順序不完整"
    fi

    printf '%s\n' code ok recoverable runId value | sort \
        > "${CHECK_TMP_PREFIX}_expected_QaResult_properties.txt"
    printf '%s\n' fingerprint sceneId | sort \
        > "${CHECK_TMP_PREFIX}_expected_QaPrepared_properties.txt"
    printf '%s\n' actual checkId expected facts key pass schema verdict | sort \
        > "${CHECK_TMP_PREFIX}_expected_QaEvidence_properties.txt"
    assert_ts_type_property_set "$interface" QaResult \
        "${CHECK_TMP_PREFIX}_expected_QaResult_properties.txt" 'QaResult producer'
    assert_ts_type_property_set "$interface" QaPrepared \
        "${CHECK_TMP_PREFIX}_expected_QaPrepared_properties.txt" 'QaPrepared producer'
    assert_ts_type_property_set "$interface" QaEvidence \
        "${CHECK_TMP_PREFIX}_expected_QaEvidence_properties.txt" 'QaEvidence producer'
    if ! rg -Fq 'readonly actual: string | number | boolean | null;' "$interface" 2>/dev/null || \
       ! rg -Fq 'readonly expected?: string | number | boolean | null;' "$interface" 2>/dev/null || \
       rg -q 'readonly error[?]?:|readonly actual:.*(unknown|any|object)|readonly expected[?]?:.*(unknown|any|object)' "$interface" 2>/dev/null; then
        fail "QA producer exact schema 允許 exception 或任意 nested evidence"
    fi
    if ! test_block_has "$enabled_harness_test" \
        'prepare 失敗結果不得攜帶 raw uid 或任意 exception message' \
        "code: 'PREPARE_FAILED'" || \
       ! test_block_has "$enabled_harness_test" \
        'prepare 失敗結果不得攜帶 raw uid 或任意 exception message' \
        'recoverable: false' || \
       ! test_block_has "$enabled_harness_test" \
        'inspect 失敗只回固定 code，不攜帶 raw uid 或 exception message' \
        "code: 'EVIDENCE_FAILURE'" || \
       ! test_block_has "$enabled_harness_test" \
        'inspect 失敗只回固定 code，不攜帶 raw uid 或 exception message' \
        'recoverable: true'; then
        fail "prepare 與 inspect exact failure schema 負向測試不完整"
    fi
    printf '%s\n' identityHash identityMode isAnonymous requestId schema state | sort \
        > "${CHECK_TMP_PREFIX}_expected_ready_properties.txt"
    assert_qa_ready_property_set "$runtime" \
        "${CHECK_TMP_PREFIX}_expected_ready_properties.txt" 'QA operation'
    assert_qa_ready_property_set "$bootstrap" \
        "${CHECK_TMP_PREFIX}_expected_ready_properties.txt" 'QA bootstrap'
    rg -q 'QA READY' "$runtime" 2>/dev/null || fail "QA READY 不存在"
    rg -Fq 'currentUser?.isAnonymous !== true' "$runtime" 2>/dev/null || \
        fail "QA runtime 未以 Firebase anonymous user fail-closed"
    rg -Fq 'isAnonymous: true' "$runtime" 2>/dev/null || \
        fail "QA READY 缺 isAnonymous=true"
    rg -Fq "identityMode: 'disposable-anonymous'" "$runtime" 2>/dev/null || \
        fail "QA READY 缺 identityMode=disposable-anonymous"
    rg -Fq 'if (!/^[a-f0-9]{64}$/.test(identityHash)) {' "$runtime" 2>/dev/null || \
        fail "QA operation READY identityHash 未驗 64-lowerhex"
    if ! awk '
        /QA READY/ {active=1}
        active && /^[[:space:]]*identityHash,[[:space:]]*$/ {found=1}
        active && /^[[:space:]]*[)][;][[:space:]]*$/ {exit}
        END {exit !found}
    ' "$runtime" 2>/dev/null; then
        fail "QA operation READY 未直接輸出 identityHash"
    fi
    if ! test_block_has "$runtime_test" \
        'identity hash 格式不合法時不得建立 runtime 或輸出 READY' \
        'QA_OPERATION_IDENTITY_HASH_INVALID' || \
       ! test_block_has "$runtime_test" \
        'identity hash 格式不合法時不得建立 runtime 或輸出 READY' \
        "not.toContain('QA READY')"; then
        fail "QA operation READY invalid identityHash 測試未拒絕 runtime 與 READY"
    fi
    if ! test_block_has "$runtime_test" \
        '使用 AuthProvider 已確認的 user 建立 runtime' \
        'expect(ready).toEqual({' || \
       ! test_block_has "$runtime_test" \
        '使用 AuthProvider 已確認的 user 建立 runtime' \
        'expect(Object.keys(ready).sort()).toEqual([' || \
       ! test_block_has "$runtime_test" \
        '使用 AuthProvider 已確認的 user 建立 runtime' \
        "not.toContain('auth-ready-user')"; then
        fail "QA operation READY exact-object 測試未鎖六 keys 與 raw uid 隔離"
    fi
    printf '%s\n' \
        QA_AUTH_REQUIRED \
        QA_DISABLED \
        QA_DISPOSABLE_ANONYMOUS_REQUIRED \
        QA_INVALID_LAUNCH_REQUEST \
        QA_OPERATION_FAILED \
        QA_SESSION_STALE | sort \
        > "${CHECK_TMP_PREFIX}_expected_operation_error_codes.txt"
    printf '%s\n' \
        QA_AUTH_REQUIRED \
        QA_INVALID_LAUNCH_PLAN \
        QA_INVALID_OPERATION_PLAN \
        QA_LAUNCH_FAILED \
        QA_OPERATION_AUTH_GUARD_FAILED \
        QA_OPERATION_AUTH_REQUIRED \
        QA_OPERATION_AUTH_RESTORE_TIMEOUT \
        QA_OPERATION_GATE_FAILED \
        QA_OPERATION_IDENTITY_MISMATCH \
        QA_OPERATION_SESSION_PROOF_REJECTED | sort \
        > "${CHECK_TMP_PREFIX}_expected_launch_error_codes.txt"
    assert_ts_string_set "$runtime" operationErrorCodes \
        "${CHECK_TMP_PREFIX}_expected_operation_error_codes.txt" \
        'prepare 與 inspect error'
    assert_ts_string_set "$runtime" launchErrorCodes \
        "${CHECK_TMP_PREFIX}_expected_launch_error_codes.txt" \
        'launch error'
    if ! rg -Fq "type QaReportedOperation = 'prepare' | 'inspect' | 'launch';" "$runtime" 2>/dev/null || \
       ! rg -Fq 'prepare: operationErrorCodes' "$runtime" 2>/dev/null || \
       ! rg -Fq 'inspect: operationErrorCodes' "$runtime" 2>/dev/null || \
       ! rg -Fq 'launch: launchErrorCodes' "$runtime" 2>/dev/null || \
       ! rg -Fq 'return errorCodesByOperation[operation].has(candidate)' "$runtime" 2>/dev/null || \
       ! rg -Fq "? 'QA_LAUNCH_FAILED'" "$runtime" 2>/dev/null || \
       ! rg -Fq ": 'QA_OPERATION_FAILED'" "$runtime" 2>/dev/null || \
       ! rg -Fq 'error: safeQaRuntimeErrorCode(error, operation)' "$runtime" 2>/dev/null; then
        fail "QA RESULT error allowlist 未依 operation exact 分流"
    fi
    if ! test_block_has "$runtime_test" \
        'RESULT error 只保留固定 QA code，不輸出 raw uid' \
        "new Error('QA_INVALID_LAUNCH_REQUEST')" || \
       ! test_block_has "$runtime_test" \
        'RESULT error 只保留固定 QA code，不輸出 raw uid' \
        "toBe('QA_OPERATION_FAILED')" || \
       ! test_block_has "$runtime_test" \
        'RESULT error 只保留固定 QA code，不輸出 raw uid' \
        "toBe('QA_OPERATION_AUTH_REQUIRED')" || \
       ! test_block_has "$runtime_test" \
        'RESULT error 只保留固定 QA code，不輸出 raw uid' \
        "new Error('QA_UNREGISTERED_BUT_WELL_FORMED')" || \
       ! test_block_has "$runtime_test" \
        'RESULT error 只保留固定 QA code，不輸出 raw uid' \
        "toBe('QA_LAUNCH_FAILED')"; then
        fail "QA RESULT error fallback 未拒絕跨 operation 或未登錄 QA code"
    fi
    if rg -q '^[[:space:]]*error:' "$enabled_harness" 2>/dev/null; then
        fail "QA nested RESULT 不得回傳 exception message"
    fi
    if ! test_block_has "$enabled_harness_test" \
        'prepare 失敗結果不得攜帶 raw uid 或任意 exception message' \
        'not.toContain(' || \
       ! test_block_has "$enabled_harness_test" \
        'prepare 失敗結果不得攜帶 raw uid 或任意 exception message' \
        'raw-uid-must-not-appear'; then
        fail "QA nested RESULT raw uid 隔離測試不存在"
    fi
    if rg -Fq "error: 'QA fixture verification failed'" "$app_harness_test" 2>/dev/null; then
        fail "QA app harness 測試仍期待 raw exception message"
    fi
    if console_raw_uid_locations "$user_service" \
        > "${CHECK_TMP_PREFIX}_user_service_raw_uid_logs.txt" 2>/dev/null; then
        fail "userService console 不得直接輸出 raw uid 或 user.uid"
    fi
    if console_raw_uid_locations "$sync_engine" \
        > "${CHECK_TMP_PREFIX}_sync_engine_raw_uid_logs.txt" 2>/dev/null; then
        fail "syncEngine console 不得直接輸出 raw uid 或 user.uid"
    fi
    if ! test_block_has "$user_service_test" \
        'uploadPreferences 的可見 log 不得包含 raw UID' \
        'not.toContain(rawUid)'; then
        fail "userService raw uid log 隔離測試不存在"
    fi
    if ! test_block_has "$sync_engine_test" \
        'backup markers 不輸出 Firebase raw uid' \
        'not.toContain(sensitiveUid)'; then
        fail "syncEngine raw uid log 隔離測試不存在"
    fi
    rg -Fq 'identityHash' "$bootstrap" 2>/dev/null || \
        fail "QA READY 缺 identityHash"
    if ! rg -Fq 'proofEstablishment = await establishDisposableIdentityProof(' "$bootstrap" 2>/dev/null || \
       ! rg -Fq 'dependencies.establishSessionProof ?? establishQaSessionProof' "$bootstrap" 2>/dev/null || \
       ! rg -Fq 'proof = await establish(sessionToken, user.uid)' "$bootstrap" 2>/dev/null; then
        fail "QA READY identityHash 未取自 native session proof"
    fi
    if ! rg -Fq '!/^[a-f0-9]{64}$/.test(' "$bootstrap" 2>/dev/null || \
       ! rg -Fq 'proofEstablishment.expectedUidHash' "$bootstrap" 2>/dev/null; then
        fail "QA READY identityHash 未驗 native proof 64-lowerhex"
    fi
    rg -Fq 'identityHash: proofEstablishment.expectedUidHash' "$bootstrap" 2>/dev/null || \
        fail "QA READY identityHash 未直接採用 native proof expectedUidHash"
    rg -Fq 'identityHash' "$bootstrap_test" 2>/dev/null || \
        fail "QA READY identityHash 測試不存在"
    if ! test_block_has "$bootstrap_test" \
        'proof 回傳的 identity hash 不合法時保留清理憑證且不得 READY' \
        "expectedUidHash: 'not-a-sha256'" || \
       ! test_block_has "$bootstrap_test" \
        'proof 回傳的 identity hash 不合法時保留清理憑證且不得 READY' \
        'expect(deleteCreatedThroughNative).not.toHaveBeenCalled()' || \
       ! test_block_has "$bootstrap_test" \
        'proof 回傳的 identity hash 不合法時保留清理憑證且不得 READY' \
        "expect(output).not.toContain('QA READY ')"; then
        fail "QA READY invalid identityHash 測試未保留清理權限並拒絕 READY"
    fi
    rg -Fq "expect(readyLog).not.toContain('auth-ready-user')" "$runtime_test" 2>/dev/null || \
        fail "QA READY 匿名證據測試不得包含 uid"
    rg -Fq '接受帶 session token 的 READY bootstrap 與獨占 disposal' "$qa_launch_plan_test" 2>/dev/null || \
        fail "QA token-bound bootstrap 測試不存在"
    if ! rg -Fq 'resolveQaEntryKind' "$qa_entry" 2>/dev/null || \
       ! rg -Fq 'disposePersistedAnonymousIdentity' "$qa_entry" 2>/dev/null || \
       ! rg -Fq 'disposeIdentity' "$qa_entry_selection" 2>/dev/null; then
        fail "QA entry 未以 disposal plan 啟動 isolated lifecycle"
    fi
    if ! rg -Fq 'formatInvalidQaLaunchResult' "$qa_entry" 2>/dev/null || \
       ! rg -Fq "return 'invalid'" "$qa_entry_selection" 2>/dev/null || \
       rg -q 'QaInvalidLaunchApp' "$qa_entry" 2>/dev/null; then
        fail "QA invalid launch 未切 immediate fail-closed lifecycle"
    fi
    if ! rg -Fq 'bootstrapDisposableAnonymousIdentity' "$qa_entry" 2>/dev/null || \
       ! rg -Fq "return 'identity-bootstrap'" "$qa_entry_selection" 2>/dev/null; then
        fail "QA token-bound zero-operation 未啟動 isolated bootstrap lifecycle"
    fi
    if rg -q 'QaIdentityBootstrapApp|QaIdentityDisposalApp|QaInvalidLaunchApp' "$qa_entry" 2>/dev/null || \
       rg -q 'React[.]useEffect|AuthProvider' "$qa_entry" 2>/dev/null; then
        fail "QA identity lifecycle 不得依賴 React root 或 AuthProvider"
    fi
    if ! rg -Fq 'QA READY' "$bootstrap" 2>/dev/null || \
       ! rg -Fq 'isAnonymous: true' "$bootstrap" 2>/dev/null || \
       ! rg -Fq "identityMode: 'disposable-anonymous'" "$bootstrap" 2>/dev/null; then
        fail "QA bootstrap READY 契約不存在"
    fi
    rg -Fq 'clearQaSessionProof' "$bootstrap" 2>/dev/null || \
        fail "QA bootstrap 未先清除 stale session proof"
    rg -Fq 'establishQaSessionProof' "$bootstrap" 2>/dev/null || \
        fail "QA bootstrap 未建立 token 與 uid proof"
    rg -Fq 'not.toContain(sessionToken)' "$bootstrap_test" 2>/dev/null || \
        fail "QA bootstrap log 未鎖 secret token 隔離"
    if rg -q 'database|handlePostAuth|runBackup|generateMissingInstances' "$bootstrap" "$qa_entry" 2>/dev/null; then
        fail "QA bootstrap lifecycle 不得啟動 DB 或 sync"
    fi
    if ! rg -Fq "not.toContain(" "$bootstrap_test" 2>/dev/null || \
       ! rg -Fq 'must-not-appear' "$bootstrap_test" 2>/dev/null; then
        fail "QA bootstrap READY 洩漏測試不存在"
    fi
    if rg -Fq 'Promise.race' "$bootstrap" 2>/dev/null; then
        fail "QA bootstrap 不得以 Promise.race 包裝匿名身分建立"
    fi
    if ! rg -Fq 'dependencies.deleteAnonymousIdentity ?? deleteQaAnonymousIdentity' "$bootstrap" 2>/dev/null || \
       ! test_block_has "$bootstrap_test" \
        'persisted anonymous user 必須先刪除，再建立本 session 新身分' \
        "'delete-native'," || \
       ! test_block_has "$bootstrap_test" \
        'persisted anonymous user 必須先刪除，再建立本 session 新身分' \
        "'create',"; then
        fail "QA bootstrap 必須刪除 persisted anonymous user 後再建立"
    fi
    if ! rg -Fq 'QA_STALE_ANONYMOUS_DISPOSAL_FAILED' "$bootstrap_test" 2>/dev/null || \
       ! rg -Fq 'createAnonymous).not.toHaveBeenCalled()' "$bootstrap_test" 2>/dev/null; then
        fail "QA bootstrap stale identity 刪除失敗測試不存在"
    fi
    if ! rg -Fq 'const authCleared = await deleteAnonymousIdentity(' "$bootstrap" 2>/dev/null || \
       ! rg -Fq 'if (!authCleared)' "$bootstrap" 2>/dev/null || \
       ! test_block_has "$native_isolation_test" \
        'bootstrap 清理也只刪除原生捕捉的精確匿名 user' \
        'QaCapturedUserMatchesUid(capturedUser, uid)' || \
       ! test_block_has "$native_isolation_test" \
        'bootstrap 清理也只刪除原生捕捉的精確匿名 user' \
        '[capturedUser deleteWithCompletion:'; then
        fail "QA bootstrap stale delete 未確認 Auth current user 已收斂為 null"
    fi
    if ! test_block_has "$bootstrap_test" \
        '原生精確刪除未確認 Auth 清空時不得建立新身分' \
        'deleteAnonymousIdentity = jest.fn(async () => false)' || \
       ! test_block_has "$bootstrap_test" \
        '原生精確刪除未確認 Auth 清空時不得建立新身分' \
        'expect(createAnonymous).not.toHaveBeenCalled()' || \
       ! test_block_has "$bootstrap_test" \
        '原生精確刪除未確認 Auth 清空時不得建立新身分' \
        "expect(output).not.toContain('QA READY ')"; then
        fail "QA bootstrap stale delete resolve 但 current remains 負向測試不存在"
    fi
    if rg -Fq './src/services/appCheck' "$qa_entry" 2>/dev/null || \
       rg -Fq 'initializeAppCheck' "$qa_entry" 2>/dev/null; then
        fail "QA entry 不得載入 AppCheck"
    fi
    if rg -Fq '.getToken(' "$app_check" 2>/dev/null || \
       rg -qi 'console[.](log|info|warn|error)[(][^)]*token' "$app_check" 2>/dev/null; then
        fail "App Check 初始化不得取得或輸出 token"
    fi
    if ! awk '
        /^#if !QA$/ {guarded=1; next}
        /^#endif$/ {guarded=0; next}
        guarded && /RNFBAppCheckModule[.]sharedInstance[(][)]/ {registered=1}
        END {exit !registered}
    ' "$app_delegate" 2>/dev/null; then
        fail "QA build 不得註冊 RNFBAppCheck provider"
    fi
    local app_check_registration_count
    app_check_registration_count=$(grep -Fc 'RNFBAppCheckModule.sharedInstance()' "$app_delegate" 2>/dev/null || true)
    [ "${app_check_registration_count:-0}" -eq 1 ] || \
        fail "RNFBAppCheck provider registration 必須只存在於單一非 QA guard"
    if ! grep -Fq '$(APP_URL_SCHEME)' "$info_plist" 2>/dev/null || \
       grep -Fq 'com.googleusercontent.apps.515173750154-4fftspgi257ovtom1cf3hrdbaslpr3km' "$info_plist" 2>/dev/null || \
       ! check_qa_oauth_routes "$project"; then
        fail "QA OAuth route 未依 build configuration 隔離"
    fi
    if ! awk '
        /^#if !QA$/ { guarded=1; next }
        /^#endif$/ { guarded=0; next }
        guarded && /import GoogleSignIn/ { guardedImport=1 }
        guarded && /GIDSignIn[.]sharedInstance[.]handle[(]url[)]/ { guardedHandler=1 }
        END { exit !(guardedImport && guardedHandler) }
    ' "$app_delegate" 2>/dev/null; then
        fail "QA GoogleSignIn handler 未從 QA build 排除"
    fi
    for invalid_contract in \
        "requestId: 'invalid'" \
        "operation: 'launch'" \
        "value: null" \
        "error: 'QA_INVALID_LAUNCH_PLAN'"; do
        rg -Fq "$invalid_contract" "$invalid_launch_result" 2>/dev/null || \
            fail "QA invalid launch RESULT 契約缺少：$invalid_contract"
    done
    if ! rg -Fq 'disposePersistedAnonymousIdentity' "$qa_entry" 2>/dev/null || \
       rg -q 'QaIdentityDisposalApp|AuthProvider' "$qa_entry" 2>/dev/null; then
        fail "QA identity disposal lifecycle 不得掛載 Production App 或 AuthProvider"
    fi
    rg -Fq "operation: 'dispose'" "$disposal" 2>/dev/null || \
        fail "disposal RESULT 缺 operation=dispose 契約"
    rg -Fq 'authDeleted: true' "$disposal" 2>/dev/null || \
        fail "disposal RESULT 缺 authDeleted=true 契約"
    if ! rg -Fq 'dependencies.disposeAnonymousIdentity ?? disposeQaAnonymousIdentity' "$disposal" 2>/dev/null || \
       ! test_block_has "$native_isolation_test" \
        'disposal 原子核對 proof 與當前匿名身分並刪除捕捉的 user' \
        '[capturedUser deleteWithCompletion:'; then
        fail "disposal 未刪除 Firebase Auth user"
    fi
    rg -Fq 'user !== null && user.isAnonymous !== true' "$disposal" 2>/dev/null || \
        fail "disposal 未限制匿名 Firebase Auth user"
    if ! rg -Fq 'const nativeResult = await disposeAnonymousIdentity(' "$disposal" 2>/dev/null || \
       ! test_block_has "$disposal_test" \
        'proof 與精確帳號刪除由單一原生串行入口完成' \
        'expect(disposeAnonymousIdentity).toHaveBeenCalledWith('; then
        fail "disposal 未以 token 與 uid begin proof"
    fi
    if ! rg -Fq 'nativeResult.authDeleted !== true' "$disposal" 2>/dev/null || \
       ! test_block_has "$native_isolation_test" \
        'disposal 原子核對 proof 與當前匿名身分並刪除捕捉的 user' \
        'QaCapturedUserMatchesUid(capturedUser, uid)' || \
       ! test_block_has "$native_isolation_test" \
        'disposal 原子核對 proof 與當前匿名身分並刪除捕捉的 user' \
        'QaPersistProof(nil)'; then
        fail "disposal 未確認 Firebase Auth current user 為 null"
    fi
    rg -Fq 'QA_IDENTITY_DELETE_NOT_CONFIRMED' "$disposal" 2>/dev/null || \
        fail "disposal 缺 delete confirmation fail-closed"
    rg -Fq 'nativeResult.proofCleared !== true' "$disposal" 2>/dev/null || \
        fail "disposal 未在刪除確認後完成 proof"
    test_block_has "$disposal_test" \
        'proof 與精確帳號刪除由單一原生串行入口完成' \
        'authDeleted: true' || \
        fail "disposal 測試未鎖 begin-delete-confirm-complete 順序"
    test_block_has "$disposal_test" \
        '原生刪除後 Auth 未確認清空時不得成功' \
        "rejects.toThrow('QA_IDENTITY_DELETE_NOT_CONFIRMED')" || \
        fail "disposal 測試未鎖 delete confirmation"
    rg -Fq 'not.toContain(sessionToken)' "$disposal_test" 2>/dev/null || \
        fail "disposal log 未鎖 secret token 隔離"
    for disposal_proof_contract in \
        'QaProofAuthorizes(proof, token, uid, YES)' \
        '[state isEqualToString:QaSessionStateActive]' \
        '[state isEqualToString:QaSessionStateDisposing]' \
        'QaPersistProof(nil)'; do
        rg -Fq "$disposal_proof_contract" "$native" 2>/dev/null || \
            fail "native disposal proof 缺契約：$disposal_proof_contract"
    done
    if ! rg -Fq "not.toContain(" "$disposal_test" 2>/dev/null || \
       ! rg -Fq 'must-not-appear' "$disposal_test" 2>/dev/null; then
        fail "disposal RESULT 不得包含 uid 的測試不存在"
    fi
    rg -q 'QA RESULT' "$runtime" "$bridge" 2>/dev/null || fail "QA RESULT 不存在"
    rg -q 'qa.runtime/v1' "$runtime" "$bridge" 2>/dev/null || fail "qa.runtime/v1 不存在"
    rg -Fq "runAndReport(requestId, 'prepare', sceneId" "$runtime" 2>/dev/null || fail "prepare RESULT value 未綁定 requested scene"
    rg -Fq "runAndReport(requestId, 'inspect', checkId" "$runtime" 2>/dev/null || fail "inspect RESULT value 未綁定 requested check"
    rg -Fq 'readonly value: T;' "$interface" 2>/dev/null || fail "QaResult 缺 result.value"
    rg -Fq 'readonly sceneId: QaSceneId;' "$interface" 2>/dev/null || fail "QaPrepared 缺 sceneId"
    rg -Fq 'readonly checkId: QaCheckId;' "$interface" 2>/dev/null || fail "inspect evidence 缺 checkId"
    grep -Fq 'prepare 與 inspect 的 top-level value 必須等於 requested scene 或 check' "$profile" || fail "能力側寫缺 RESULT top-level value 契約"
    grep -Fq 'prepare 的 `result.value.sceneId` 必須等於 requested scene' "$profile" || fail "能力側寫缺 prepare result.value 契約"
    grep -Fq 'inspect 的 `result.value.schema` 必須為 `qa.evidence/v1`' "$profile" || fail "能力側寫缺 inspect result.value.schema 契約"
    grep -Fq 'inspect 的 `result.value.checkId` 必須等於 requested check' "$profile" || fail "能力側寫缺 inspect result.value 契約"
    local exact_result_profile_missing=0
    for exact_result_profile_contract in \
        'RESULT 套用 operation-specific exact schema' \
        'RESULT 頂層必須且只能含 `result` 或 `error` 其中一項' \
        'prepare 成功 result 只准 `ok`、`runId` 與 `value`' \
        'prepare 成功 value 只准 `sceneId` 與 `fingerprint`' \
        'inspect 成功 result 只准 `ok`、`runId` 與 `value`' \
        'inspect 成功 value 只准 `schema`、`checkId`、`verdict` 與 `facts`' \
        'prepare 與 inspect 的內層失敗只准 `ok`、`runId`、`code` 與 `recoverable`' \
        'evidence fact 不得包含任意巢狀物件' \
        'disk 前 marker filter 必須先驗 operation-specific exact schema' \
        'evidence 的字串 actual 與 expected 必須在 disk 前轉為 deterministic SHA-256 digest' \
        'evidence 的 bare Firebase uid 不得進入可見 log 或持久工件'; do
        if ! grep -Fq "$exact_result_profile_contract" "$profile"; then
            exact_result_profile_missing=1
        fi
    done
    if [ "$exact_result_profile_missing" -eq 1 ]; then
        fail "能力側寫缺 operation-specific RESULT 與 evidence disk-safe exact schema"
    fi
    local result_top_level_contract_missing=0
    for result_top_level_contract in \
        'RESULT 頂層的四個 base keys 為 `schema`、`requestId`、`operation` 與 `value`' \
        '成功 RESULT 頂層必須且只能含四個 base keys 與 `result`' \
        '失敗 RESULT 頂層必須且只能含四個 base keys 與 `error`'; do
        if ! grep -Fq "$result_top_level_contract" "$profile"; then
            result_top_level_contract_missing=1
        fi
    done
    if [ "$result_top_level_contract_missing" -eq 1 ]; then
        fail "RESULT 頂層 exact key set 契約不完整"
    fi
    local bootstrap_error_codes_expected="${CHECK_TMP_PREFIX}_bootstrap_error_codes_expected.txt"
    local bootstrap_error_codes_actual="${CHECK_TMP_PREFIX}_bootstrap_error_codes_actual.txt"
    local dispose_error_codes_expected="${CHECK_TMP_PREFIX}_dispose_error_codes_expected.txt"
    local dispose_error_codes_actual="${CHECK_TMP_PREFIX}_dispose_error_codes_actual.txt"
    printf '%s\n' \
        QA_ANONYMOUS_BOOTSTRAP_FAILED \
        QA_ANONYMOUS_PROVIDER_DISABLED \
        QA_AUTH_RESTORE_FAILED \
        QA_AUTH_RESTORE_TIMEOUT \
        QA_BOOTSTRAP_ENTRY_SELECTION_LOAD_FAILED \
        QA_BOOTSTRAP_ENTRY_LOAD_FAILED \
        QA_BOOTSTRAP_ENVIRONMENT_LOAD_FAILED \
        QA_BOOTSTRAP_IDENTITY_MODULE_LOAD_FAILED \
        QA_BOOTSTRAP_LAUNCH_PLAN_LOAD_FAILED \
        QA_BOOTSTRAP_LAUNCH_PLAN_RESOLUTION_FAILED \
        QA_DISPOSABLE_ANONYMOUS_REQUIRED \
        QA_FIREBASE_AUTH_CONFIG_REJECTED \
        QA_FIREBASE_AUTH_NETWORK_FAILED \
        QA_SESSION_PROOF_CLEAR_FAILED \
        QA_SESSION_PROOF_WRITE_FAILED \
        QA_SESSION_PROOF_WRITE_FAILED_IDENTITY_REMAINS \
        QA_STALE_ANONYMOUS_DISPOSAL_FAILED | LC_ALL=C sort > "$bootstrap_error_codes_expected"
    {
        rg -o 'QA_[A-Z0-9_]+' "$bootstrap" 2>/dev/null
        rg -o 'QA_BOOTSTRAP_[A-Z0-9_]+' "$qa_entry" 2>/dev/null
    } | LC_ALL=C sort -u > "$bootstrap_error_codes_actual"
    if ! grep -Fq 'bootstrap 的外層 error allowlist 固定為 `QA_ANONYMOUS_BOOTSTRAP_FAILED`、`QA_ANONYMOUS_PROVIDER_DISABLED`、`QA_AUTH_RESTORE_FAILED`、`QA_AUTH_RESTORE_TIMEOUT`、`QA_BOOTSTRAP_ENTRY_LOAD_FAILED`、`QA_BOOTSTRAP_ENTRY_SELECTION_LOAD_FAILED`、`QA_BOOTSTRAP_ENVIRONMENT_LOAD_FAILED`、`QA_BOOTSTRAP_IDENTITY_MODULE_LOAD_FAILED`、`QA_BOOTSTRAP_LAUNCH_PLAN_LOAD_FAILED`、`QA_BOOTSTRAP_LAUNCH_PLAN_RESOLUTION_FAILED`、`QA_DISPOSABLE_ANONYMOUS_REQUIRED`、`QA_FIREBASE_AUTH_CONFIG_REJECTED`、`QA_FIREBASE_AUTH_NETWORK_FAILED`、`QA_SESSION_PROOF_CLEAR_FAILED`、`QA_SESSION_PROOF_WRITE_FAILED`、`QA_SESSION_PROOF_WRITE_FAILED_IDENTITY_REMAINS`、`QA_STALE_ANONYMOUS_DISPOSAL_FAILED`' "$profile" || \
       ! diff -q "$bootstrap_error_codes_expected" "$bootstrap_error_codes_actual" >/dev/null 2>&1; then
        fail "bootstrap RESULT error allowlist 契約不完整"
    fi
    printf '%s\n' \
        QA_AUTH_RESTORE_TIMEOUT \
        QA_DISPOSABLE_ANONYMOUS_REQUIRED \
        QA_DISPOSAL_PROOF_CLEAR_FAILED \
        QA_DISPOSAL_PROOF_STATE_FAILED \
        QA_DISPOSAL_SESSION_PROOF_REJECTED \
        QA_IDENTITY_DELETE_FAILED \
        QA_IDENTITY_DELETE_NOT_CONFIRMED | LC_ALL=C sort > "$dispose_error_codes_expected"
    rg -o 'QA_[A-Z0-9_]+' "$disposal" 2>/dev/null | LC_ALL=C sort -u > "$dispose_error_codes_actual"
    if ! grep -Fq 'dispose 的外層 error allowlist 固定為 `QA_AUTH_RESTORE_TIMEOUT`、`QA_DISPOSABLE_ANONYMOUS_REQUIRED`、`QA_DISPOSAL_PROOF_CLEAR_FAILED`、`QA_DISPOSAL_PROOF_STATE_FAILED`、`QA_DISPOSAL_SESSION_PROOF_REJECTED`、`QA_IDENTITY_DELETE_FAILED`、`QA_IDENTITY_DELETE_NOT_CONFIRMED`' "$profile" || \
       ! diff -q "$dispose_error_codes_expected" "$dispose_error_codes_actual" >/dev/null 2>&1; then
        fail "dispose RESULT error allowlist 契約不完整"
    fi
    grep -Fq 'READY 頂層必須且只能含 `schema`、`requestId`、`state`、`isAnonymous`、`identityMode` 與 `identityHash`' "$profile" || \
        fail "能力側寫缺 READY exact 六 keys 契約"
    local error_allowlist_profile_missing=0
    for error_allowlist_profile_contract in \
        'prepare 與 inspect 的外層 error allowlist 固定為 `QA_AUTH_REQUIRED`、`QA_DISABLED`、`QA_DISPOSABLE_ANONYMOUS_REQUIRED`、`QA_INVALID_LAUNCH_REQUEST`、`QA_OPERATION_FAILED`、`QA_SESSION_STALE`' \
        'launch 的外層 error allowlist 固定為 `QA_AUTH_REQUIRED`、`QA_INVALID_LAUNCH_PLAN`、`QA_INVALID_OPERATION_PLAN`、`QA_LAUNCH_FAILED`、`QA_OPERATION_AUTH_GUARD_FAILED`、`QA_OPERATION_AUTH_REQUIRED`、`QA_OPERATION_AUTH_RESTORE_TIMEOUT`、`QA_OPERATION_GATE_FAILED`、`QA_OPERATION_IDENTITY_MISMATCH`、`QA_OPERATION_SESSION_PROOF_REJECTED`' \
        'prepare 與 inspect 遇到其他 code 時固定回傳 `QA_OPERATION_FAILED`' \
        'launch 遇到其他 code 時固定回傳 `QA_LAUNCH_FAILED`' \
        '任一 operation 不得接收其他 operation 的專屬 code'; do
        if ! grep -Fq "$error_allowlist_profile_contract" "$profile"; then
            error_allowlist_profile_missing=1
        fi
    done
    if [ "$error_allowlist_profile_missing" -eq 1 ]; then
        fail "能力側寫缺 RESULT error operation exact allowlist 契約"
    fi
    grep -Fq 'READY 的 `isAnonymous` 必須為 `true`' "$profile" || fail "能力側寫缺 READY anonymous 契約"
    grep -Fq 'READY 的 `identityMode` 必須為 `disposable-anonymous`' "$profile" || fail "能力側寫缺 READY identityMode 契約"
    grep -Fq 'READY 的 `identityHash` 必須為六十四字元小寫十六進位' "$profile" || \
        fail "能力側寫缺 READY identityHash 契約"
    grep -Fq 'READY 不得包含 Firebase uid' "$profile" || fail "能力側寫缺 READY uid 隔離契約"
    grep -Fq 'bootstrap launch 只傳 requestId 與 secret token' "$profile" || \
        fail "能力側寫缺 token-bound 零 operation bootstrap 契約"
    grep -Fq '每個 session 產生一組六十四字元小寫十六進位 secret token' "$profile" || \
        fail "能力側寫缺 64-hex session token 契約"
    if ! grep -Fq 'secret token 只從 process environment 的 `SUSUGIGI_QA_SESSION_TOKEN` 載入' "$profile" || \
       ! grep -Fq 'secret token 不得出現在 process arguments' "$profile"; then
        fail "能力側寫缺 process environment secret seam"
    fi
    grep -Fq 'proof 只保存 token hash 與 Firebase uid hash' "$profile" || \
        fail "能力側寫缺 token 與 uid hash proof 契約"
    grep -Fq 'persisted proof 的 key set 必須恰為 `tokenHash`、`uidHash`、`expiresAt`、`state`、`consumedBindings`、`consumedRequestHashes`' "$profile" || \
        fail "能力側寫缺 persisted proof exact-key 契約"
    grep -Fq 'persisted proof 必須在讀取任何欄位前拒絕 raw token、raw uid、未知 key 或舊版額外 key' "$profile" || \
        fail "能力側寫缺 persisted proof unknown-key fail-closed 契約"
    grep -Fq 'proof 初始有效期為八小時' "$profile" || \
        fail "能力側寫缺八小時 proof TTL"
    grep -Fq 'persisted proof 的 `expiresAt` 不得晚於目前時間加八小時' "$profile" || \
        fail "能力側寫缺 proof future-expiry upper bound"
    grep -Fq '每次成功 operation consume 將有效期滑動八小時' "$profile" || \
        fail "能力側寫缺 operation consume sliding TTL"
    grep -Fq 'operation consume 原子綁定 requestId 與 operation payload' "$profile" || \
        fail "能力側寫缺 operation binding consume 契約"
    grep -Fq 'AuthProvider 遇到 null 或 uid hash 不符時永久鎖住該 root' "$profile" || \
        fail "能力側寫缺 AuthProvider terminal latch"
    grep -Fq 'terminal latch 後不得匿名重生或執行 post-auth' "$profile" || \
        fail "能力側寫缺 terminal latch 後續阻斷"
    local recurring_identity_profile_missing=0
    for recurring_identity_profile_contract in \
        'AuthProvider 必須將當輪 `isCurrent` 傳入 QA recurring backfill' \
        'Production 未提供 `isCurrent` 時必須維持既有 recurring backfill 行為' \
        'recurring backfill 入口已失效時必須零副作用返回' \
        'recurring backfill 必須在每個 await 後重驗 `isCurrent`' \
        'recurring backfill 必須在 transaction 與 transfer create 前後重驗 `isCurrent`' \
        'guarded caller 加入既有 unguarded in-flight 時必須動態合併 guard' \
        'recurring backfill pending 期間遇到 null 或不同 uid 時不得再產生本地寫入'; do
        if ! grep -Fq "$recurring_identity_profile_contract" "$profile"; then
            recurring_identity_profile_missing=1
        fi
    done
    if [ "$recurring_identity_profile_missing" -eq 1 ]; then
        fail "能力側寫缺 recurring stale identity write guard 契約"
    fi
    if ! grep -Fq 'launch-driven runtime 不得發布 `globalThis.__SUSUGIGI_QA__`' "$profile" || \
       ! grep -Fq 'open-app 只可輸出 READY，不得暴露或執行 prepare、inspect' "$profile"; then
        fail "能力側寫缺 open-app global 隔離契約"
    fi
    if ! grep -Fq 'operation root 只可執行已消耗 proof 綁定的 exact operation 與 value' "$profile" || \
       ! grep -Fq 'operation root 不得以 global adapter 執行第二種 operation 或重放已消耗 operation' "$profile"; then
        fail "能力側寫缺 operation exact-binding anti-replay 契約"
    fi
    grep -Fq '每次 launch 恰為 bootstrap、first-launch、open-app、prepare、inspect 或 dispose' "$profile" || \
        fail "能力側寫缺 launch operation exclusivity"
    if ! grep -Fq 'requestId 必須符合 `(?:bootstrap|dispose|first-launch|inspect|open-app|prepare)-[0-9a-f]{32}`' "$profile" || \
       ! grep -Fq 'requestId 的 operation prefix 必須與本次 launch kind 完全相同' "$profile"; then
        fail "能力側寫缺 requestId exact grammar 與 launch kind 綁定"
    fi
    grep -Fq '殘留匿名身分刪除 resolve 後，必須確認 Auth current user 為 null，才可建立本 session 新身分' "$profile" || \
        fail "能力側寫缺 bootstrap stale delete current-null confirmation"
    grep -Fq 'prepare 與 inspect 不得同次 launch' "$profile" || \
        fail "能力側寫仍允許 prepare 與 inspect 同次 launch"
    grep -Fq 'READY 成立後，只在當次 session 暫時提升 `qa-command` 與 `qa-probe`' "$profile" || \
        fail "能力側寫缺 session-only promotion 契約"
    grep -Fq 'disposal 可接受已過期 proof' "$profile" || \
        fail "能力側寫缺 expired proof disposal 契約"
    grep -Fq 'disposal complete 只清除相同 token 與 uid 的 disposing proof' "$profile" || \
        fail "能力側寫缺 disposal token uid state 契約"
    grep -Fq 'disposal 失敗時整場失敗' "$profile" || fail "能力側寫缺 disposal fail-closed 契約"
    grep -Fq '除 `qa-command` 與 `qa-probe` 的 session bootstrap 例外外' "$profile" || \
        fail "能力側寫總則缺 bootstrappable 例外"
    grep -Fq '受阻時不得啟動測項 operation runtime' "$profile" || \
        fail "能力側寫總則未禁止受阻 operation runtime"
    grep -Fq 'qa-command 與 qa-probe 只在同 requestId 與 session proof 的匿名 READY 成立後取得當次 promotion' \
        "$plan/no3_home_dashboard.md" 2>/dev/null || fail "HD-07 前置未綁定 session promotion"
    if grep -RFq --include='*.md' '解除阻斷' "$run_docs" 2>/dev/null; then
        fail "場次文件不得宣稱永久解除 qa-command 或 qa-probe 阻斷"
    fi
    local firestore_binding_contract
    for firestore_binding_contract in \
        'bootstrap READY 只保存 `identityHash`，不得在 isolated bootstrap lifecycle 查 SQLite' \
        'cleanup 或首次手動變更前，可先以 Firebase CLI Auth export 將 exact-one uid hash 綁定 READY `identityHash`' \
        '需要執行 App 資料後，必須再以 canonical QA SQLite `users.id` exact-one 交叉驗證同一 `QA_SESSION_UID`' \
        'Auth export、READY 與 SQLite 任一身分不符時必須 fail-closed' \
        '沒有 seed 或 inspect 時必須先執行 token-bound open-app' \
        '首次 firestore-read 前必須完成 Auth export exact-one bind；App 資料已建立時還必須完成 SQLite exact-one 交叉驗證' \
        'SQLite 候選只准由 command substitution 捕獲' \
        'SQLite 候選不得直接輸出、寫入 log 或寫入 session 報告' \
        '候選 hash 必須與 `identityHash` exact-one match' \
        '零筆 match 必須 fail-closed' \
        '多筆 match 必須 fail-closed' \
        '零筆 match 不得重試或改用猜測' \
        '命中的 raw uid 只准留在 shell memory 的 `QA_SESSION_UID`' \
        '所有 firestore-read resource path 必須由 `QA_SESSION_UID` 衍生' \
        '禁止依 newest 文件推定身分' \
        '禁止依任意文件推定身分' \
        'log、session 報告與持久工件不得包含 raw uid' \
        'Firestore REST 原始回應必須以 bounded Python process memory parse 讀取' \
        'Firestore REST 原始回應不得進 shell memory 或落盤' \
        'shell 只准接收 allowlisted scalar、baseline 或 profile verdict' \
        '不得直接輸出 Firestore REST 原始回應' \
        '可見證據中的 uid 一律遮罩為固定字串 `[QA_SESSION_UID]`' \
        'disposal 不代表 Firestore 測試資料已清除'; do
        grep -Fq "$firestore_binding_contract" "$profile" 2>/dev/null || \
            fail "能力側寫缺 Firestore 身分綁定：$firestore_binding_contract"
    done
    for firestore_binding_contract in \
        'bootstrap READY 只保存 `identityHash`' \
        'cleanup 或首次手動變更前，可先以 Firebase CLI Auth export 將 exact-one uid hash 綁定 READY `identityHash`' \
        '需要執行 App 資料後，必須再以 canonical QA SQLite `users.id` exact-one 交叉驗證同一 `QA_SESSION_UID`' \
        '首次 firestore-read 前列舉 canonical QA SQLite 的 `users.id`' \
        "SELECT id FROM users WHERE _status != 'deleted' ORDER BY id;" \
        'SQLite 候選只由 command substitution 捕獲' \
        'SQLite 候選不得輸出、寫入 log 或寫入 session 報告' \
        '候選 hash 必須與 READY `identityHash` exact-one match' \
        '零筆 match 立即停止' \
        '多筆 match 立即停止' \
        '零筆 match 不重試或改用猜測' \
        'raw uid 只留在 shell memory 的 `QA_SESSION_UID`' \
        'R03 的 Firestore resource path 全由 `QA_SESSION_UID` 衍生' \
        '禁止選 newest 文件' \
        '禁止選任意文件' \
        '禁止輸出或回報 raw uid' \
        'Firestore REST 原始回應以 bounded Python process memory parse 讀取' \
        'Firestore REST 原始回應不得進 shell memory 或落盤' \
        'shell 只接收 allowlisted profile verdict' \
        '不直接輸出 Firestore REST 原始回應' \
        '可見證據中的 uid 固定遮罩為 `[QA_SESSION_UID]`' \
        'disposal 不代表 Firestore 孤兒資料已清除'; do
        grep -Fq "$firestore_binding_contract" "$r03_runbook" 2>/dev/null || \
            fail "R03 缺 Firestore 身分綁定：$firestore_binding_contract"
    done
    if [ "$(meta_value "CS-02" seed)" != "r02_end" ] || \
       ! grep -Fq '`prepare r02_end`' "$r03_runbook" 2>/dev/null; then
        fail "CS-02 metadata 與 R03 runbook seed 不一致"
    fi
    if [ "$(meta_value "CS-02" inspect)" != "accounting.fixture-summary" ] || \
       ! grep -Fq '`inspect accounting.fixture-summary`' "$r03_runbook" 2>/dev/null; then
        fail "CS-02 metadata 與 R03 runbook inspect 不一致"
    fi
    grep -Fq 'users/${QA_SESSION_UID}/accounts、users/${QA_SESSION_UID}/categories、users/${QA_SESSION_UID}/transactions、users/${QA_SESSION_UID}/transfers、users/${QA_SESSION_UID}/currency_rates、users/${QA_SESSION_UID}/schedules' \
        "$r03_csv" 2>/dev/null || \
        fail "R03 CSV 初次備份 probe 未綁定 QA_SESSION_UID 六個 resource path"
    grep -Fq 'firestore-read 分別精確查 users/${QA_SESSION_UID}/transactions 與 users/${QA_SESSION_UID}/transfers' \
        "$r03_csv" 2>/dev/null || \
        fail "R03 CSV 增量備份 probe 未綁定 QA_SESSION_UID transactions 與 transfers path"
    local r03_firestore_row_count r03_probe_action
    r03_firestore_row_count=$(awk -F',' '$7 == "firestore-read" {count++} END {print count + 0}' \
        "$r03_csv" 2>/dev/null)
    [ "${r03_firestore_row_count:-0}" -eq 4 ] || \
        fail "R03 CSV firestore-read 列數必須恰為四"
    while IFS= read -r r03_probe_action; do
        case "$r03_probe_action" in
            *'users/${QA_SESSION_UID}/'*) ;;
            *) fail "R03 CSV firestore-read 未由 QA_SESSION_UID 衍生 resource path" ;;
        esac
        if [[ "$r03_probe_action" != *'原始回應'* ]] || \
           [[ "$r03_probe_action" != *'bounded Python process memory'* ]] || \
           [[ "$r03_probe_action" != *'不落盤'* ]] || \
           [[ "$r03_probe_action" != *'shell 只接收 allowlisted profile verdict'* ]] || \
           [[ "$r03_probe_action" == *'暫存'* ]]; then
            fail "R03 CSV firestore-read 原始回應未隔離於 bounded process memory"
        fi
        case "$r03_probe_action" in
            *'[QA_SESSION_UID]'*) ;;
            *) fail "R03 CSV firestore-read 可見證據未遮罩 uid" ;;
        esac
    done < <(awk -F',' '$7 == "firestore-read" {print $4}' "$r03_csv" 2>/dev/null)

    local firestore_csv firestore_action firestore_csv_name
    local firestore_missing_exact_path=0
    local firestore_ambiguous_scope=0
    local firestore_missing_output_isolation=0
    local firestore_txn_index_unbound=0
    while IFS= read -r firestore_csv; do
        firestore_csv_name=$(basename "$firestore_csv")
        while IFS= read -r firestore_action; do
            case "$firestore_action" in
                *'/${QA_SESSION_UID}'*) ;;
                *) firestore_missing_exact_path=1 ;;
            esac
            case "$firestore_action" in
                *'collection-wide'*|*'newest'*|*'最新一筆'*|*'最新文件'*|*'任意文件'*|*'該 uid'*|*'該 UID'*|*'查 users 集合'*|*'查 transactions 集合'*|*'查 entitlements 集合'*|*'查 txnIndex 集合'*)
                    firestore_ambiguous_scope=1
                    ;;
            esac
            case "$firestore_csv_name" in
                no12_r10_payment_backend.csv|no13_r11_subscription_lifecycle.csv|no14_r12_teardown_rebirth.csv)
                    if [[ "$firestore_action" != *'原始回應'* ]] || \
                       [[ "$firestore_action" != *'暫存'* ]] || \
                       [[ "$firestore_action" != *'[QA_SESSION_UID]'* ]] || \
                       [[ "$firestore_action" != *'刪除暫存'* ]]; then
                        firestore_missing_output_isolation=1
                    fi
                    ;;
                *)
                    if [[ "$firestore_action" != *'原始回應'* ]] || \
                       [[ "$firestore_action" != *'bounded Python process memory'* ]] || \
                       [[ "$firestore_action" != *'不落盤'* ]] || \
                       [[ "$firestore_action" != *'shell 只'* ]] || \
                       [[ "$firestore_action" != *'[QA_SESSION_UID]'* ]] || \
                       [[ "$firestore_action" == *'暫存'* ]]; then
                        firestore_missing_output_isolation=1
                    fi
                    ;;
            esac
            if [[ "$firestore_action" == *txnIndex* ]] && { \
               [[ "$firestore_action" != *'run_qa_txn_index_exact_doc_probe'* ]] || \
               ! rg -Fq 'capture_qa_original_transaction_id_from_session_entitlement' "$firestore_csv" 2>/dev/null || \
               ! rg -Fq 'entitlements/${QA_SESSION_UID}' "$firestore_csv" 2>/dev/null || \
               ! rg -Fq 'QA_ORIGINAL_TRANSACTION_ID_PROVENANCE=session-entitlement-exact-doc' "$firestore_csv" 2>/dev/null || \
               ! rg -Fq 'QA_ORIGINAL_TRANSACTION_OWNER_HASH=READY identityHash' "$firestore_csv" 2>/dev/null || \
               ! rg -Fq 'ID 必須是 5 至 32 位十進位數字' "$firestore_csv" 2>/dev/null || \
               ! rg -Fq '不記錄 transaction ID' "$firestore_csv" 2>/dev/null; \
            }; then
                firestore_txn_index_unbound=1
            fi
            if [[ "$firestore_action" == *txnIndex* ]]; then
                case "$firestore_action" in
                    *'單一 present mode'*)
                        [[ "$firestore_action" == *'owner uid SHA-256 同時等於 READY identityHash 與 capture owner hash'* ]] || \
                            firestore_txn_index_unbound=1
                        ;;
                    *'單一 absent mode'*)
                        if [[ "$firestore_action" != *'canonical exact-document not-found'* ]] || \
                           [[ "$firestore_action" != *'不宣稱 owner uid 已驗'* ]]; then
                            firestore_txn_index_unbound=1
                        fi
                        ;;
                    *) firestore_txn_index_unbound=1 ;;
                esac
            fi
        done < <(awk -F',' '$7 == "firestore-read" {print $4}' "$firestore_csv" 2>/dev/null)
    done < <(find "$run_docs" -maxdepth 1 -type f -name '*.csv' -print | sort)
    [ "$firestore_missing_exact_path" -eq 0 ] || \
        fail '場次 CSV firestore-read 未綁定 /${QA_SESSION_UID} exact path'
    [ "$firestore_ambiguous_scope" -eq 0 ] || \
        fail "場次 CSV firestore-read 使用 collection-wide、newest 或模糊 uid"
    [ "$firestore_missing_output_isolation" -eq 0 ] || \
        fail "場次 CSV firestore-read 未依場次隔離 raw response 或遮罩 uid"
    [ "$firestore_txn_index_unbound" -eq 0 ] || \
        fail "場次 CSV txnIndex probe 未由 session entitlement 衍生 exact path"
    local txn_index_contract
    for txn_index_contract in \
        '`txnIndex` exact-doc 是唯一可不直接含 `QA_SESSION_UID` 的 firestore-read path' \
        '`QA_ORIGINAL_TRANSACTION_ID` 只能由 `entitlements/${QA_SESSION_UID}` 的 exact-doc response 擷取' \
        '`QA_ORIGINAL_TRANSACTION_ID` 與 provenance 只准留在 shell memory' \
        '`QA_ORIGINAL_TRANSACTION_ID` 必須符合 `^[0-9]{5,32}$`' \
        '`QA_ORIGINAL_TRANSACTION_ID_PROVENANCE` 必須為 `session-entitlement-exact-doc`' \
        'capture 完成時 `QA_ORIGINAL_TRANSACTION_OWNER_HASH` 必須等於 READY identityHash' \
        'txnIndex probe 只准呼叫 `run_qa_txn_index_exact_doc_probe`' \
        'txnIndex wrapper 只接受單一 `present` 或 `absent` mode' \
        'txnIndex wrapper 不接受 caller 提供 resource path' \
        '`present` 必須讓 owner uid SHA-256 同時等於 READY identityHash 與 `QA_ORIGINAL_TRANSACTION_OWNER_HASH`' \
        '`absent` 只接受 canonical exact-document not-found，且不得宣稱 owner uid 已驗' \
        'txnIndex document id、owner raw uid 與 provenance 不得進入 log、可見證據或持久工件'; do
        grep -Fq "$txn_index_contract" "$profile" 2>/dev/null || \
            fail "能力側寫缺 txnIndex typed exact-doc 契約"
    done
    if ! rg -Fq 'capture_qa_original_transaction_id_from_session_entitlement' "$run_docs/no12_r10_payment_backend.csv" 2>/dev/null || \
       ! rg -Fq 'run_qa_txn_index_exact_doc_probe' "$run_docs/no12_r10_payment_backend.csv" 2>/dev/null || \
       ! rg -Fq 'QA_ORIGINAL_TRANSACTION_OWNER_HASH=READY identityHash' "$run_docs/no12_r10_payment_backend.csv" 2>/dev/null || \
       ! rg -Fq '單一 present mode' "$run_docs/no12_r10_payment_backend.csv" 2>/dev/null || \
       ! rg -Fq 'owner uid SHA-256 同時等於 READY identityHash 與 capture owner hash' "$run_docs/no12_r10_payment_backend.csv" 2>/dev/null; then
        fail "R10 txnIndex probe 未鎖 typed provenance 與 owner hash"
    fi
    if ! rg -Fq 'run_qa_txn_index_exact_doc_probe' "$r12_csv" 2>/dev/null || \
       ! rg -Fq '單一 absent mode' "$r12_csv" 2>/dev/null || \
       ! rg -Fq 'canonical exact-document not-found' "$r12_csv" 2>/dev/null || \
       ! rg -Fq '不宣稱 owner uid 已驗' "$r12_csv" 2>/dev/null; then
        fail "R12 txnIndex absent probe 未鎖 typed not-found"
    fi

    local app_check_block_profile_contract
    for app_check_block_profile_contract in \
        'QA App 不載入或註冊 App Check' \
        'R10 的 verifyTransaction 與 txnIndex route、R11 的 subscription route、R12 的 deleteUserAccount 都要求 App Check' \
        'R10、R11 與 R12 的結構化狀態固定為 `blocked`' \
        'R10、R11 與 R12 的固定阻斷代碼為 `qa-app-check-isolation-unavailable`' \
        'R10、R11 與 R12 不提供 physical-device、simulator 或 manual 執行 route' \
        'game-test 必須在各阻斷場次的第一個 operation 前記錄 `blocked`' \
        '阻斷場次不得中止同一選集的安全場次' \
        '同時含兩類場次時結果為 `partial-blocked`'; do
        grep -Fq "$app_check_block_profile_contract" "$profile" 2>/dev/null || \
            fail "能力側寫缺 R10–R12 App Check isolation structured block"
    done
    if ! grep -Fq -- '- **caseId:** `R14`' "$r14_runbook" 2>/dev/null || \
       ! grep -Fq -- '- **runtime_route:** `simulator`' "$r14_runbook" 2>/dev/null || \
       ! grep -Fq -- '--qa-first-launch true' "$r14_runbook" 2>/dev/null || \
       ! grep -Fq '清理接手回條' "$r14_runbook" 2>/dev/null || \
       ! grep -Fq 'readQaFirstLaunchRelease' "$impl/src/qa/QaFirstLaunchApp.tsx" 2>/dev/null || \
       ! grep -Fq 'first-launch:true' "$impl/src/qa/qaFirstLaunchSession.ts" 2>/dev/null; then
        fail "R14 first-launch 清理接手契約不符"
    fi
    if ! grep -Fq '| `core` | `partial-blocked` | R10、R12 | 照常執行 |' "$run_index" 2>/dev/null; then
        fail "core tier 缺部分阻斷展開"
    fi
    if ! grep -Fq '| `standard` | `partial-blocked` | R10、R12 | 照常執行 |' "$run_index" 2>/dev/null; then
        fail "standard tier 缺部分阻斷展開"
    fi
    local r15_runbook="$script/no17_r15_local_storekit.md"
    if ! grep -Fq -- '- **caseId:** `R15`' "$r15_runbook" 2>/dev/null || \
       ! grep -Fq -- '- **runtime_route:** `simulator`' "$r15_runbook" 2>/dev/null || \
       ! grep -Fq -- '- **driver:** `sim-review`' "$r15_runbook" 2>/dev/null || \
       ! grep -Fq 'SKTestSession' "$r15_runbook" 2>/dev/null || \
       ! grep -Eq '^\| local-storekit \|[^|]*\| 可用 \|' "$profile" 2>/dev/null; then
        fail "R15 local StoreKit 啟動契約不符"
    fi
    if ! grep -Fq '| `extended` | `partial-blocked` | R10、R11、R12 | 照常執行 |' "$run_index" 2>/dev/null; then
        fail "extended tier 缺部分阻斷展開"
    fi
    local relaunch_runbook relaunch_csv expected_relaunches actual_relaunches
    local relaunch_token_count relaunch_icon_count
    for relaunch_runbook in "$r01_runbook" "$r02_runbook" "$r08_runbook"; do
        if ! grep -Fq 'simulator 的完全關閉後重開由 sim-review terminate 並沿用同 token 產生新 `open-app-` requestId' \
            "$relaunch_runbook" 2>/dev/null || \
           ! grep -Eq '(使用者|任何操作者)不得直接點無 launch arguments 的 app icon' "$relaunch_runbook" 2>/dev/null; then
            fail "R01/R02/R08 runbook 缺 sim-review token-bound reopen 契約"
        fi
    done
    for relaunch_csv in "$r01_csv" "$r02_csv" "$r08_csv"; do
        case "$relaunch_csv" in
            *no3_r01_*) expected_relaunches=2 ;;
            *) expected_relaunches=1 ;;
        esac
        actual_relaunches=$(grep -Fc 'simulator route 由 sim-review terminate app' "$relaunch_csv" 2>/dev/null || true)
        relaunch_token_count=$(grep -Fc '沿用同一 token 產生未重複的 open-app- 加三十二字元小寫十六進位 requestId' "$relaunch_csv" 2>/dev/null || true)
        relaunch_icon_count=$(grep -Fc '不得使用無 launch arguments 的 icon 重開' "$relaunch_csv" 2>/dev/null || true)
        actual_relaunches=${actual_relaunches:-0}
        relaunch_token_count=${relaunch_token_count:-0}
        relaunch_icon_count=${relaunch_icon_count:-0}
        if [ "$actual_relaunches" -ne "$expected_relaunches" ] || \
           [ "$relaunch_token_count" -ne "$expected_relaunches" ] || \
           [ "$relaunch_icon_count" -ne "$expected_relaunches" ]; then
            fail "R01/R02/R08 CSV sim-review reopen 未鎖同 token、新 requestId 與禁 icon"
        fi
    done
    if ! grep -Fq '沿用 READY identityHash 綁定的同一 users path，provider 為 anonymous、email 為空值且 createdAt 不變；lastLoginAt 與 updatedAt 可依規格推進且不納入 identity digest' \
        "$auth_plan" "$r01_csv" 2>/dev/null || \
       ! grep -Fq '偏好不屬 AU-03 比較面' "$r01_csv" 2>/dev/null; then
        fail "AU-03 未鎖身分不變式與可推進時間欄位"
    fi
    local r01_baseline_action r01_final_expected
    r01_baseline_action=$(awk -F',' '$1 == "11" {print $4; exit}' "$r01_csv" 2>/dev/null)
    r01_final_expected=$(awk -F',' '$1 == "15" {print $5; exit}' "$r01_csv" 2>/dev/null)
    if [[ "$r01_baseline_action" != *'createdAt、lastLoginAt、updatedAt baseline 只保存於 session shell memory'* ]] || \
       [[ "$r01_final_expected" != *'lastLoginAt 與 updatedAt 欄位存在且皆不早於序 11 private baseline'* ]] || \
       ! grep -Fq 'metadata timestamp 不納入 identity digest' "$r01_runbook" 2>/dev/null; then
        fail "R01 metadata baseline 未私有捕獲或誤納 identity digest"
    fi

    local r08_language_capture_sequence r08_language_change_sequence
    local r08_updated_capture_sequence r08_first_cs01_change_sequence
    r08_language_capture_sequence=$(awk -F',' '$7 == "sqlite-local" && $4 ~ /QA_R08_ORIGINAL_LANGUAGE/ {print $1; exit}' "$r08_csv" 2>/dev/null)
    r08_language_change_sequence=$(awk -F',' '$3 == "操作" && $2 ~ /AS-04/ && $4 ~ /選日本語/ {print $1; exit}' "$r08_csv" 2>/dev/null)
    r08_updated_capture_sequence=$(awk -F',' '$7 == "firestore-read" && $4 ~ /QA_R08_CS01_BASELINE_UPDATED_AT/ {print $1; exit}' "$r08_csv" 2>/dev/null)
    r08_first_cs01_change_sequence=$(awk -F',' '$2 == "CS-01" && $3 == "操作" {print $1; exit}' "$r08_csv" 2>/dev/null)
    if [ "$r08_language_capture_sequence" != "8" ] || \
       [ "$r08_language_change_sequence" != "9" ] || \
       [ "$r08_updated_capture_sequence" != "15" ] || \
       [ "$r08_first_cs01_change_sequence" != "16" ] || \
       ! grep -Fq 'profile r08_original_language' "$r08_csv" 2>/dev/null || \
       ! grep -Fq -- '--session-uid-stdin' "$r08_csv" 2>/dev/null || \
       ! grep -Fq 'deleted tombstone 不納入' "$r08_csv" 2>/dev/null || \
       ! grep -Fq 'baseline 只留 session shell memory' "$r08_csv" 2>/dev/null || \
       ! grep -Fq '根層 updatedAt 存在且嚴格晚於序 15 private baseline' "$r08_csv" 2>/dev/null; then
        fail "R08 原語系或 updatedAt private baseline 順序不符"
    fi
    local r03_cleanup_sequence r03_prepare_sequence r03_inspect_sequence r03_open_sequence
    r03_cleanup_sequence=$(awk -F',' '$7 == "qa-cleanup" {print $1; exit}' "$r03_csv" 2>/dev/null)
    r03_prepare_sequence=$(awk -F',' '$7 == "qa-command" && $4 ~ /prepare r02_end/ {print $1; exit}' "$r03_csv" 2>/dev/null)
    r03_inspect_sequence=$(awk -F',' '$7 == "qa-probe" && $4 ~ /accounting.fixture-summary/ {print $1; exit}' "$r03_csv" 2>/dev/null)
    r03_open_sequence=$(awk -F',' '$7 == "qa-markers" && $4 ~ /open-app-/ {print $1; exit}' "$r03_csv" 2>/dev/null)
    if [ -z "$r03_cleanup_sequence" ] || \
       [ -z "$r03_prepare_sequence" ] || \
       [ -z "$r03_inspect_sequence" ] || \
       [ -z "$r03_open_sequence" ]; then
        fail "R03 未鎖 cleanup→prepare→inspect→open-app 順序"
    elif [ "$r03_cleanup_sequence" -ge "$r03_prepare_sequence" ] || \
         [ "$r03_prepare_sequence" -ge "$r03_inspect_sequence" ] || \
         [ "$r03_inspect_sequence" -ge "$r03_open_sequence" ]; then
        fail "R03 未鎖 cleanup→prepare→inspect→open-app 順序"
    fi
    if ! grep -Fq 'no1_fixture_golden.json' "$r03_runbook" "$r03_csv" 2>/dev/null || \
       ! grep -Fq '候選 RESULT 的 `verdict=pass` 不得作為唯一通過證據' "$r03_runbook" 2>/dev/null || \
       ! grep -Fq 'post-delete absent probes' "$r03_runbook" "$r03_csv" 2>/dev/null || \
       ! grep -Fq 'device cooldown' "$r03_runbook" "$r03_csv" 2>/dev/null; then
        fail "R03 缺 golden、post-delete absent 或 cooldown fail-closed 契約"
    fi
    if ! grep -Fq 'transactions 10 筆、transfers 2 筆' "$r03_csv" 2>/dev/null || \
       ! grep -Fq '2000→2000 與 1000→4500' "$r03_csv" "$r03_runbook" 2>/dev/null || \
       ! grep -Fq '兩路皆零額外 live row' "$r03_csv" 2>/dev/null || \
       ! grep -Fq 'transactions 與 transfers 都不得出現 golden 以外的 live row' "$r03_runbook" 2>/dev/null; then
        fail "R03 incremental profile 未鎖兩路 exact count、transfer pair 與零額外 live row"
    fi
    local r13_auth_sequence r13_bind_sequence r13_cleanup_sequence r13_prepare_sequence r13_inspect_sequence
    r13_auth_sequence=$(awk -F',' '$7 == "firebase-auth-control" && $4 ~ /QA_SESSION_UID/ {print $1; exit}' "$r13_csv" 2>/dev/null)
    r13_bind_sequence=$(awk -F',' '$7 == "sqlite-local" && $4 ~ /QA_SESSION_UID/ {print $1; exit}' "$r13_csv" 2>/dev/null)
    r13_cleanup_sequence=$(awk -F',' '$7 == "qa-cleanup" {print $1; exit}' "$r13_csv" 2>/dev/null)
    r13_prepare_sequence=$(awk -F',' '$7 == "qa-command" && $4 ~ /prepare r09_stale_schedule/ {print $1; exit}' "$r13_csv" 2>/dev/null)
    r13_inspect_sequence=$(awk -F',' '$7 == "qa-probe" && $4 ~ /accounting.schedule-backfill/ {print $1; exit}' "$r13_csv" 2>/dev/null)
    if [ -z "$r13_auth_sequence" ] || \
       [ -z "$r13_bind_sequence" ] || \
       [ -z "$r13_cleanup_sequence" ] || \
       [ -z "$r13_prepare_sequence" ] || \
       [ -z "$r13_inspect_sequence" ]; then
        fail "R13 未鎖 Auth bind→cleanup→prepare→SQLite bind→inspect 順序"
    elif [ "$r13_auth_sequence" -ge "$r13_cleanup_sequence" ] || \
         [ "$r13_cleanup_sequence" -ge "$r13_prepare_sequence" ] || \
         [ "$r13_prepare_sequence" -ge "$r13_bind_sequence" ] || \
         [ "$r13_bind_sequence" -ge "$r13_inspect_sequence" ]; then
        fail "R13 未鎖 Auth bind→cleanup→prepare→SQLite bind→inspect 順序"
    fi
    if [ -n "$r13_prepare_sequence" ] && awk -F',' -v prepare="$r13_prepare_sequence" '
        NR > 1 && $1 + 0 < prepare + 0 && ($7 == "sqlite-local" || $4 ~ /open-app-/) { forbidden = 1 }
        END { exit forbidden ? 0 : 1 }
    ' "$r13_csv"; then
        fail "R13 未鎖 Auth bind→cleanup→prepare→SQLite bind→inspect 順序"
    fi
    if [ "$(awk -F',' '$7 == "sqlite-local" {count++} END {print count + 0}' "$r13_csv" 2>/dev/null)" -ne 2 ] || \
       ! grep -Fq 'r13_schedule_backfill 聚合 profile' "$r13_csv" 2>/dev/null || \
       ! grep -Fq 'RESULT facts 與 sqlite-local 聚合都要各自符合 golden，再彼此對帳' "$r13_runbook" 2>/dev/null || \
       ! grep -Fq '候選 RESULT 的 `result.value.verdict=pass` 不得作為唯一通過證據' "$r13_runbook" 2>/dev/null || \
       ! grep -Fq 'global session `QA_SESSION_UID` exact-one binding' "$r13_runbook" 2>/dev/null || \
       ! grep -Fq 'exact UID fixture 子樹必須在 prepare 前通過 post-delete absent probes' "$r13_runbook" 2>/dev/null; then
        fail "R13 缺獨立 SQLite golden 對帳或 global cleanup binding"
    fi
    if ! grep -Fq 'requestId 必須以 `prepare-` 開頭' "$r13_runbook" 2>/dev/null || \
       ! grep -Fq 'requestId 必須以 `inspect-` 開頭' "$r13_runbook" 2>/dev/null || \
       [ "$(grep -Fc 'requestId 後綴必須為三十二字元小寫十六進位' "$r13_runbook" 2>/dev/null || true)" -ne 2 ] || \
       ! grep -Fq 'requestId 不得與本 session 任何既有 requestId 重複' "$r13_runbook" 2>/dev/null || \
       rg -q 'r13-(prepare|backfill)' "$r13_runbook" 2>/dev/null; then
        fail "R13 runbook requestId 未使用 operation prefix 加 32-lowerhex"
    fi
    local r13_prepare_action r13_inspect_action r13_marker_note
    r13_prepare_action=$(awk -F',' '$7 == "qa-command" {print $4; exit}' "$r13_csv" 2>/dev/null)
    r13_inspect_action=$(awk -F',' '$7 == "qa-probe" {print $4; exit}' "$r13_csv" 2>/dev/null)
    r13_marker_note=$(awk -F',' '$7 == "qa-markers" && $4 ~ /QA SCHED/ {print $9; exit}' "$r13_csv" 2>/dev/null)
    if [[ "$r13_prepare_action" != *'執行器產生 prepare-'* ]] || \
       [[ "$r13_prepare_action" != *'三十二字元小寫十六進位 requestId'* ]] || \
       [[ "$r13_inspect_action" != *'執行器產生未重複的 inspect-'* ]] || \
       [[ "$r13_inspect_action" != *'三十二字元小寫十六進位 requestId'* ]] || \
       [[ "$r13_marker_note" != *'inspect launch 動態產生的 inspect-'* ]] || \
       [[ "$r13_marker_note" != *'三十二字元小寫十六進位 requestId'* ]] || \
       rg -q 'r13-(prepare|backfill)' "$r13_csv" 2>/dev/null; then
        fail "R13 CSV requestId 未使用 operation prefix 加 32-lowerhex"
    fi
    local blocked_case blocked_runbook
    for blocked_case in R10 R11 R12; do
        case "$blocked_case" in
            R10) blocked_runbook="$r10_runbook" ;;
            R11) blocked_runbook="$r11_runbook" ;;
            R12) blocked_runbook="$r12_runbook" ;;
        esac
        if ! grep -Fq -- "- **caseId:** \`$blocked_case\`" "$blocked_runbook" 2>/dev/null || \
           ! grep -Fq -- '- **status:** `blocked`' "$blocked_runbook" 2>/dev/null || \
           ! grep -Fq -- '- **blockPhase:** `first-operation`' "$blocked_runbook" 2>/dev/null || \
           ! grep -Fq -- '- **reason:** `qa-app-check-isolation-unavailable`' "$blocked_runbook" 2>/dev/null || \
           ! grep -Fq '不提供 physical-device、simulator 或 manual route' "$blocked_runbook" 2>/dev/null; then
            fail "$blocked_case structured block 欄位不符"
        fi
        grep -Fq "| \`$blocked_case\` | \`blocked\` | \`first-operation\` | \`qa-app-check-isolation-unavailable\` |" \
            "$run_index" 2>/dev/null || fail "R10–R12 場次索引 structured block 不完整"
    done
    if rg -Fq 'qa-terminal-latch-rebirth-isolation-unavailable' \
        "$profile" "$run_index" "$r10_runbook" "$r11_runbook" "$r12_runbook" 2>/dev/null; then
        fail "R10–R12 structured block 使用過時 reason token"
    fi
    if rg -q '實機加 Metro 執行中|只准由 isolated sim-review|R10 至 R11 固定需要實機|\| `extended` \| `physical-device`' \
        "$run_index" "$r10_runbook" "$r11_runbook" "$r12_runbook" 2>/dev/null; then
        fail "R10–R12 仍宣稱可執行 route"
    fi
    if rg -qi '自 Metro[^,]*(uid|UID)|(?:uid|UID)[[:space:]]*前八碼' "$r12_csv" 2>/dev/null; then
        fail "場次 CSV 不得從 Metro 或可見證據擷取 raw UID"
    fi
    if ! rg -Fq '候選只由 command substitution 捕獲並以本機 SHA-256 與 READY identityHash exact-one 綁定 QA_SESSION_UID' "$r12_csv" 2>/dev/null || \
       ! rg -Fq '只在 shell memory 比較新舊 identityHash' "$r12_csv" 2>/dev/null || \
       ! rg -Fq '可見證據只記 verdict 且不含 raw uid' "$r12_csv" 2>/dev/null; then
        fail "R12 身分比對未鎖 shell-memory identityHash verdict"
    fi
    if ! rg -Fq 'users/${QA_SESSION_UID}、users/${QA_SESSION_UID}/accounts' "$r12_csv" 2>/dev/null || \
       ! rg -Fq 'accountDeletions/${QA_SESSION_UID} 與 entitlements/${QA_SESSION_UID}' "$r12_csv" 2>/dev/null || \
       ! rg -Fq 'run_qa_txn_index_exact_doc_probe 驗 canonical exact-document not-found' "$r12_csv" 2>/dev/null; then
        fail "R12 teardown firestore paths 未綁定 session identity"
    fi
    if rg -q 'result[.]evidence' "$profile" "$script" 2>/dev/null; then
        fail "RESULT 文件仍使用已廢棄的 evidence sibling 欄位"
    fi

    local quality_contract
    for quality_contract in \
        '支出交易固定一萬筆' \
        '每筆支出固定一百' \
        '收入交易固定一萬筆' \
        '每筆收入固定一百' \
        '轉出固定兩百筆' \
        '轉入固定兩百筆' \
        '每筆轉帳固定五十' \
        '轉帳帳戶必須同幣別' \
        '支出金標固定一百零一萬' \
        '收入金標固定一百零一萬' \
        '紀錄數金標固定二萬零四百' \
        '期間餘額金標固定零' \
        '`accounting.large-history-overlay` 驗完整 shape' \
        'shape drift 不得命中 fast path' \
        'currency drift 不得命中 fast path'; do
        grep -Fq "$quality_contract" "$profile" || fail "能力側寫缺 R06 契約：$quality_contract"
    done
    grep -Fq 'exact marker 為 `__SUSUGIGI_QA_R06_LARGE_HISTORY_V1__`' "$script/no1_fixtures.md" || \
        fail "fixture 缺 R06 exact marker"
    grep -Fq '`accounting.large-history-overlay` 驗完整 shape 與金標' "$script/no1_fixtures.md" || \
        fail "fixture 缺 full-shape probe 契約"
    grep -Fq '完整 shape 全數 pass' "$script/no8_r06_dashboard.csv" || \
        fail "R06 場次缺 full-shape probe 成功條件"
    for quality_contract in \
        'Load 寫入前先暫停同步' \
        'Load 等待既有 in-flight sync 完成' \
        'sync snapshot 排除 exact marker' \
        'sync push 排除 exact marker' \
        'marker 前綴或後綴不得被排除' \
        'Load 失敗先清 marker rows' \
        'Load 失敗於 marker 歸零後釋放同步' \
        'cleanup 成功於 marker 歸零後釋放同步' \
        'cleanup 失敗時保持同步暫停'; do
        grep -Fq "$quality_contract" "$profile" || fail "能力側寫缺 R06 sync 契約：$quality_contract"
    done
    grep -Fq 'marker 歸零後同步才釋放' "$script/no8_r06_dashboard.csv" || \
        fail "R06 場次缺 cleanup 後 release 契約"

    local overlay_id
    for overlay_id in r06_large_history r06_large_history_cleanup accounting.large-history-overlay; do
        rg -Fq "'$overlay_id'" "$interface" 2>/dev/null || fail "QA interface 缺 overlay id：$overlay_id"
        rg -Fq "$overlay_id" "$harness" 2>/dev/null || fail "Accounting QA harness 缺 overlay mapping：$overlay_id"
    done
    rg -Fq 'QA_R06_OFFLINE_REQUIRED' "$overlay" "$overlay_test" 2>/dev/null || fail "overlay 缺 offline fail-closed error"
    rg -Fq 'await requireOffline();' "$overlay" 2>/dev/null || fail "overlay Load 缺離線 gate"
    rg -Fq "it('在線時 fail-closed，資料與 writer 都不變'" "$overlay_test" 2>/dev/null || fail "overlay 測試未鎖在線 fail-closed"
    rg -Fq 'expect(mockDatabase.write).not.toHaveBeenCalled()' "$overlay_test" 2>/dev/null || fail "overlay 測試未鎖在線零寫入"
    rg -Fq 'export const LARGE_HISTORY_TRANSACTION_COUNT = 20_000;' "$overlay" 2>/dev/null || fail "overlay 交易 count 不是 20,000"
    rg -Fq 'export const LARGE_HISTORY_TRANSFER_COUNT = 400;' "$overlay" 2>/dev/null || fail "overlay 轉帳 count 不是 400"
    rg -Fq 'export const LARGE_HISTORY_DATE_SPAN_DAYS = 1_825;' "$overlay" 2>/dev/null || fail "overlay 日期跨度不是 1,825 天"
    rg -Fq 'expect(LARGE_HISTORY_DATE_SPAN_DAYS).toBe(1_825)' "$overlay_test" 2>/dev/null || fail "overlay 測試未鎖 1,825 天日期跨度"
    rg -Fq 'const TRANSACTIONS_PER_KIND = 10_000;' "$overlay" 2>/dev/null || fail "overlay 未鎖每種交易 10,000 筆"
    rg -Fq 'const TRANSFERS_PER_DIRECTION = 200;' "$overlay" 2>/dev/null || fail "overlay 未鎖每種轉帳方向 200 筆"
    rg -Fq 'const TRANSACTION_AMOUNT = toStorageAmount(100);' "$overlay" 2>/dev/null || fail "overlay 交易金額不是 100"
    rg -Fq 'const TRANSFER_AMOUNT = toStorageAmount(50);' "$overlay" 2>/dev/null || fail "overlay 轉帳金額不是 50"
    rg -Fq 'const GOLD_TOTAL = 1_010_000;' "$overlay" 2>/dev/null || fail "overlay 收支金標不是 1.01m"
    local shape_fact
    for shape_fact in \
        expenseTransactionCount incomeTransactionCount \
        transactionAmountShapeValid transactionCategoryShapeValid transactionAccountShapeValid \
        outgoingTransferCount incomingTransferCount \
        transferAmountShapeValid transferDirectionShapeValid sameCurrencyAccountPair \
        expenseTotal incomeTotal recordCount periodBalance \
        transactionDateShapeValid transferDateShapeValid; do
        rg -Fq "'$shape_fact'" "$overlay" 2>/dev/null || fail "overlay probe 缺 shape fact：$shape_fact"
    done
    rg -Fq 'expect(expenseTransactions).toHaveLength(10_000)' "$overlay_test" 2>/dev/null || fail "overlay 測試未鎖 10,000 筆支出"
    rg -Fq 'expect(incomeTransactions).toHaveLength(10_000)' "$overlay_test" 2>/dev/null || fail "overlay 測試未鎖 10,000 筆收入"
    rg -Fq 'row.amount === -1_000_000' "$overlay_test" 2>/dev/null || fail "overlay 測試未鎖支出每筆 100"
    rg -Fq 'row.amount === 1_000_000' "$overlay_test" 2>/dev/null || fail "overlay 測試未鎖收入每筆 100"
    rg -Fq 'expect(outgoingTransfers).toHaveLength(200)' "$overlay_test" 2>/dev/null || fail "overlay 測試未鎖 200 筆轉出"
    rg -Fq 'expect(incomingTransfers).toHaveLength(200)' "$overlay_test" 2>/dev/null || fail "overlay 測試未鎖 200 筆轉入"
    rg -Fq 'row.amountFrom === 500_000 && row.amountTo === 500_000' "$overlay_test" 2>/dev/null || fail "overlay 測試未鎖轉帳每筆 50"
    rg -Fq 'accountCurrencies.get(row.accountFromId) ===' "$overlay_test" 2>/dev/null || fail "overlay 測試未鎖同幣別轉帳"
    rg -Fq 'drift 不得命中 idempotent fast path，Load 會重建' "$overlay_test" 2>/dev/null || fail "overlay 測試未鎖 shape drift fast path"
    rg -Fq '帳戶幣別漂移不得命中 idempotent fast path' "$overlay_test" 2>/dev/null || fail "overlay 測試未鎖 currency drift fast path"
    rg -Fq 'expect(fromStorageAmount(storageAmount(expenseTotal))).toBe(1_010_000)' "$overlay_real_db_test" 2>/dev/null || fail "real DB 測試未鎖支出金標 1.01m"
    rg -Fq 'expect(fromStorageAmount(storageAmount(incomeTotal))).toBe(1_010_000)' "$overlay_real_db_test" 2>/dev/null || fail "real DB 測試未鎖收入金標 1.01m"
    rg -Fq 'expect(recordCount).toBe(20_400)' "$overlay_real_db_test" 2>/dev/null || fail "real DB 測試未鎖 20,400 筆"
    rg -Fq "fact('periodBalance', snapshot.periodBalance, 0)" "$overlay" 2>/dev/null || fail "overlay probe 未鎖期間餘額零"
    rg -Uq 'incomeTotal - expenseTotal\)\),\r?\n[[:space:]]*\)\.toBe\(0\);' "$overlay_real_db_test" 2>/dev/null || fail "real DB 測試未鎖期間餘額零"
    rg -Fq 'QA_R06_LOAD_VERIFICATION_FAILED' "$overlay" "$overlay_test" 2>/dev/null || fail "overlay Load 缺成功驗證"
    rg -Fq 'QA_R06_CLEANUP_VERIFICATION_FAILED' "$overlay" "$overlay_test" 2>/dev/null || fail "overlay cleanup 缺歸零驗證"
    rg -Fq 'R06_LARGE_HISTORY_SYNC_SUSPEND_REASON,' "$overlay" 2>/dev/null || fail "overlay 未引用穩定 sync suspend reason"
    rg -Fq "import { syncEngine } from '../services/syncEngine';" "$overlay" 2>/dev/null || fail "overlay 未引用 syncEngine"
    rg -Uq '(?s)export async function loadLargeHistoryOverlay\(.*?await syncEngine\.suspend\(R06_LARGE_HISTORY_SYNC_SUSPEND_REASON\);.*?const existingEvidence = verifySnapshot\(.*?await database\.write' "$overlay" 2>/dev/null || \
        fail "overlay Load 未先取得 sync barrier 再讀取或寫入"
    rg -Uq "(?s)const existingEvidence = verifySnapshot\\(.*?if \\(existingEvidence\\.verdict === 'pass'\\)" "$overlay" 2>/dev/null || \
        fail "overlay idempotent fast path 未以完整 probe 判定"
    rg -Uq '(?s)\} catch \(error\) \{.*?await removeMarkerRowsAndVerify\(userId\);[[:space:]]*await syncEngine\.resume\(R06_LARGE_HISTORY_SYNC_SUSPEND_REASON\);' "$overlay" 2>/dev/null || \
        fail "overlay Load failure 未在 marker 歸零後 release"
    rg -Uq '(?s)export async function removeLargeHistoryOverlay\(.*?const evidence = await removeMarkerRowsAndVerify\(userId\);[[:space:]]*await syncEngine\.resume\(R06_LARGE_HISTORY_SYNC_SUSPEND_REASON\);' "$overlay" 2>/dev/null || \
        fail "overlay cleanup 未在 marker 歸零後 release"
    test_block_has "$overlay_test" \
        'Load 等待 sync barrier 完成前不讀 DB，成功後持續 suspend' \
        'expect(mockDatabase.get).not.toHaveBeenCalled()' || \
        fail "overlay race test 未鎖 barrier 前零 DB 讀取"
    test_block_has "$overlay_test" \
        'Load 等待 sync barrier 完成前不讀 DB，成功後持續 suspend' \
        'expect(mockSyncResume).not.toHaveBeenCalled()' || \
        fail "overlay race test 未鎖成功 Load 持續 suspend"
    test_block_has "$overlay_test" \
        '分批寫入失敗時保留原始錯誤並清掉已寫 marker，不碰原資料' \
        'expect(mockSyncResume).toHaveBeenCalledTimes(1)' || \
        fail "overlay Load failure test 未鎖 cleanup 後 release"
    test_block_has "$overlay_test" \
        '分批寫入失敗時保留原始錯誤並清掉已寫 marker，不碰原資料' \
        'R06_LARGE_HISTORY_SYNC_SUSPEND_REASON' || \
        fail "overlay Load failure test 未鎖穩定 suspend reason"
    test_block_has "$overlay_test" \
        'cleanup 失敗時保留 suspend，重試清到零後才解除' \
        'expect(mockSyncResume).not.toHaveBeenCalled()' || \
        fail "overlay cleanup failure test 未鎖失敗時保持 suspend"
    test_block_has "$overlay_test" \
        'cleanup 失敗時保留 suspend，重試清到零後才解除' \
        'expect(mockSyncResume).toHaveBeenCalledTimes(1)' || \
        fail "overlay cleanup retry test 未鎖歸零後 release"
    rg -Fq "export const R06_LARGE_HISTORY_LOCAL_ONLY_MARKER =" "$local_only_policy" 2>/dev/null || fail "local-only policy 缺 R06 marker export"
    rg -Fq "'__SUSUGIGI_QA_R06_LARGE_HISTORY_V1__'" "$local_only_policy" 2>/dev/null || fail "local-only policy marker 不符 Quality fixture"
    rg -Fq "export const R06_LARGE_HISTORY_SYNC_SUSPEND_REASON =" "$local_only_policy" 2>/dev/null || fail "local-only policy 缺 sync suspend reason"
    rg -Fq "'qa-r06-large-history-overlay'" "$local_only_policy" 2>/dev/null || fail "R06 sync suspend reason 不穩定"
    rg -Uq '(?s)\.note ===[[:space:]]*R06_LARGE_HISTORY_LOCAL_ONLY_MARKER' "$local_only_policy" 2>/dev/null || fail "local-only policy 不是 exact-note 比對"
    rg -Fq "import { isLocalOnlyBackupRow } from './localOnlyBackupPolicy';" "$sync_engine" 2>/dev/null || fail "syncEngine 未引用 local-only policy"
    local local_only_filter_count
    local_only_filter_count=$(rg -c '\.filter\(row => !isLocalOnlyBackupRow\(row\)\);' "$sync_engine" 2>/dev/null)
    [ "${local_only_filter_count:-0}" -eq 2 ] || fail "syncEngine 必須只在交易與轉帳套用 exact marker 排除"
    rg -Fq 'suspend: async (reason: string): Promise<void> =>' "$sync_engine" 2>/dev/null || fail "syncEngine 缺 suspend API"
    rg -Fq 'syncState.suspendedReasons.add(reason);' "$sync_engine" 2>/dev/null || fail "sync suspend 未先記憶體設閘"
    rg -Fq "const STORAGE_KEY_SUSPENDED_REASONS = 'sync_suspended_reasons';" "$sync_engine" 2>/dev/null || fail "sync suspend 缺穩定 persisted key"
    rg -Fq 'await persistSyncSuspensions();' "$sync_engine" 2>/dev/null || fail "sync suspend 未持久化"
    rg -Fq 'const inFlight = syncState.inFlight;' "$sync_engine" 2>/dev/null || fail "sync suspend 未取得既有 inFlight"
    rg -Fq 'await inFlight.catch(() => {});' "$sync_engine" 2>/dev/null || fail "sync suspend 未等待既有 inFlight"
    rg -Fq 'await hydrateSyncSuspensions();' "$sync_engine" 2>/dev/null || fail "sync restart 未 hydrate suspension"
    rg -Fq 'if (syncState.suspendedReasons.size > 0)' "$sync_engine" 2>/dev/null || fail "sync 未在 suspension 下 skip"
    rg -Fq 'R06 suspend 先擋新 sync 並等待已在途 sync' "$sync_engine_test" 2>/dev/null || fail "sync race test 未鎖 suspend 與 in-flight"
    test_block_has_in_order "$sync_engine_test" \
        'restart hydrate 保留 fixture suspension，authorized open-app 只精確解除後才走 InitialBackup' \
        'await restarted.syncEngine.sync();' \
        "'sync_suspended_reasons'," \
        'expect(restarted.netInfo.default.fetch).not.toHaveBeenCalled();' \
        'expect(restarted.db.__get).not.toHaveBeenCalled();' \
        'expect(restarted.quota.quotaService.checkQuota).not.toHaveBeenCalled();' \
        'expect(restarted.firestore.__getDocs).not.toHaveBeenCalled();' \
        'expect(restarted.firestore.__batchSet).not.toHaveBeenCalled();' \
        'await openAppBarrier();' \
        ').toEqual([R06_SYNC_SUSPEND_REASON]);' \
        'await restarted.syncEngine.sync();' \
        'expect(restarted.netInfo.default.fetch).not.toHaveBeenCalled();' \
        'expect(restarted.db.__get).not.toHaveBeenCalled();' \
        'expect(restarted.firestore.__getDocs).not.toHaveBeenCalled();' \
        'await restarted.syncEngine.resume(R06_SYNC_SUSPEND_REASON);' \
        'await restarted.syncEngine.sync();' \
        'expect(restarted.netInfo.default.fetch).toHaveBeenCalledTimes(1);' \
        'expect(restarted.firestore.__getDocs).toHaveBeenCalledTimes(1);' \
        ').toBe(NOW);' || \
        fail "sync race test 未鎖 restart hydrate 與 open-app resume 序列"
    rg -Fq '即使未 suspend，push snapshot 仍只排除 exact R06 marker' "$sync_engine_test" 2>/dev/null || fail "sync test 未鎖 exact marker snapshot"
    rg -Fq 'loadLargeHistoryOverlay(requestedUserId' "$debug_ui" 2>/dev/null || fail "QA Debug UI 缺 Load overlay wiring"
    rg -Fq 'removeLargeHistoryOverlay(requestedUserId)' "$debug_ui" 2>/dev/null || fail "QA Debug UI 缺 Remove overlay wiring"
    rg -Fq 'Load R06 large history' "$debug_ui" 2>/dev/null || fail "QA Debug UI 缺 Load 按鈕文案"
    rg -Fq 'Remove R06 large history' "$debug_ui" 2>/dev/null || fail "QA Debug UI 缺 Remove 按鈕文案"
    rg -Fq "from '../../qa/largeHistoryOverlay'" "$r06_ui_isolation" 2>/dev/null || fail "R06 UI isolation 未鎖 overlay import"
    rg -Fq 'Production roots 不靜態匯入 overlay 或 Debug UI' "$r06_ui_isolation" 2>/dev/null || fail "R06 UI isolation 未鎖 Production graph"
    rg -Fq 'hasForbiddenQaModuleReference' "$r06_ui_isolation" 2>/dev/null || fail "Production guard 缺統一 QA module detector"
    rg -Fq 'multiline static import' "$r06_ui_isolation" 2>/dev/null || fail "Production guard 未涵蓋 multiline import"
    rg -Fq 'CommonJS require' "$r06_ui_isolation" 2>/dev/null || fail "Production guard 未涵蓋 require"
    rg -Fq 'dynamic import' "$r06_ui_isolation" 2>/dev/null || fail "Production guard 未涵蓋 dynamic import"
    rg -Fq 'loadLargeHistoryOverlay,\n} from' "$r06_ui_isolation" 2>/dev/null || fail "Production guard 缺 multiline import 攻擊樣本"
    rg -Fq "const screen = require('./screens/Settings/MockDataSettingsScreen');" "$r06_ui_isolation" 2>/dev/null || fail "Production guard 缺 require 攻擊樣本"
    rg -Fq "const overlay = await import('./qa/largeHistoryOverlay');" "$r06_ui_isolation" 2>/dev/null || fail "Production guard 缺 dynamic import 攻擊樣本"
    rg -Fq 'MockDataSettingsScreen' "$qa_app" 2>/dev/null || fail "QA App graph 未注入 Debug UI"
    rg -Fq 'Production module graph isolation' "$production_isolation" 2>/dev/null || fail "Production graph isolation 測試缺契約"
    rg -Fq 'symlink 別名指向 src/qa 時仍回報 canonical 違規' "$production_isolation" 2>/dev/null || \
        fail "Production graph 缺 canonical symlink isolation 測試"
    rg -Fq 'src/qa 內 symlink 逃逸到外部時仍回報 lexical 違規' "$production_isolation" 2>/dev/null || \
        fail "Production graph 缺 lexical src/qa escape 測試"
    rg -Fq 'canonical.startsWith(`${forbiddenCanonicalRoot}${path.sep}`)' "$production_graph" 2>/dev/null || \
        fail "Production graph scanner 未攔 canonical symlink alias"
    rg -Fq 'lexical.startsWith(`${forbiddenLexicalRoot}${path.sep}`)' "$production_graph" 2>/dev/null || \
        fail "Production graph scanner 未攔 lexical src/qa escape"
    rg -Fq 'isQaToolingEnabled: false' "$overlay_production_test" 2>/dev/null || fail "overlay Production 測試未關閉 QA tooling"
    rg -Fq 'QA_DISABLED' "$overlay_production_test" 2>/dev/null || fail "overlay Production 測試未驗 fail-closed"
    if rg -q 'import .*QaApp|import .*MockDataSettingsScreen|import .*largeHistoryOverlay' "$production_entry" "$impl/App.tsx" 2>/dev/null; then
        fail "Production entry 或 App 靜態匯入 QA overlay"
    fi

    grep -Fq "bash no2_qa_tools/query_local_db.sh --bundle-id $qa_bundle_id path" "$profile" 2>/dev/null || \
        fail "sqlite readiness 未顯式傳入 profile qaBundleId"
    if [ -f "$db_probe" ]; then
        grep -Fq 'QA_BUNDLE_ID="com.almightyken0425.susugigiapp.qa"' "$db_probe" || \
            fail "QA SQLite probe 缺 canonical QA bundle"
        grep -Fq 'PRODUCTION_BUNDLE_ID="com.almightyken0425.susugigiapp"' "$db_probe" || \
            fail "QA SQLite probe 缺 Production bundle deny value"
        grep -Fq '[ -n "$BUNDLE_ID" ] ||' "$db_probe" || \
            fail "QA SQLite probe 未要求顯式 bundle id"
        grep -Fq '[ "$BUNDLE_ID" != "$PRODUCTION_BUNDLE_ID" ] ||' "$db_probe" || \
            fail "QA SQLite probe 未拒絕 Production bundle"
        grep -Fq '[ "$BUNDLE_ID" = "$QA_BUNDLE_ID" ] ||' "$db_probe" || \
            fail "QA SQLite probe 未限制 canonical QA bundle"
        if rg -q -- '^[[:space:]]*--db[)]|DB_OVERRIDE' "$db_probe" 2>/dev/null; then
            fail "QA SQLite probe 正式介面不得接受任意 DB override"
        fi
        local db_override_output
        db_override_output=$(bash "$db_probe" \
            --bundle-id "$qa_bundle_id" \
            --db /tmp/production-watermelon.db path 2>&1 || true)
        if ! grep -Fq '未知參數：--db' <<< "$db_override_output"; then
            fail "QA SQLite probe 未 fail-closed 拒絕 Production DB override"
        fi
        if ! grep -Fq 'canonical_root=$(canonical_directory "$data_root")' "$db_probe" || \
           ! grep -Fq 'canonical_parent=$(canonical_directory "$(dirname "$db_path")")' "$db_probe" || \
           ! grep -Fq 'expected_db="$canonical_root/Documents/watermelon.db"' "$db_probe" || \
           ! grep -Fq '[ "$canonical_db" = "$expected_db" ] ||' "$db_probe"; then
            fail "QA SQLite probe 缺 canonical container confinement"
        fi
        if ! grep -Fq 'for candidate in "$db_path" "$db_path-wal" "$db_path-shm"; do' "$db_probe" || \
           ! grep -Fq '[ ! -L "$candidate" ] ||' "$db_probe"; then
            fail "QA SQLite probe 未拒絕 DB/WAL/SHM symlink"
        fi
        if ! grep -Fq 'cp -P "$src" "$DB"' "$db_probe" || \
           ! grep -Fq '[ ! -L "$DB" ]' "$db_probe" || \
           ! grep -Fq 'cp -P "$src-wal" "$DB-wal"' "$db_probe" || \
           ! grep -Fq 'cp -P "$src-shm" "$DB-shm"' "$db_probe"; then
            fail "QA SQLite snapshot 缺 cp -P 與 copied symlink fail-closed"
        fi
        if ! grep -Fq 'ln -s "$PRODUCTION_ROOT/Documents/watermelon.db"' "$db_probe" || \
           ! grep -Fq 'QA container 內的 Production DB symlink fail-closed 且不輸出內容' "$db_probe" || \
           ! grep -Fq "grep -q '123.45'" "$db_probe"; then
            fail "QA SQLite probe 缺 Production symlink escape 負向 selftest"
        fi
        if rg -Fq 'DB=$(snapshot "$SRC")' "$db_probe" 2>/dev/null || \
           ! grep -Fq 'DB="$SNAP_DIR/snap.db"' "$db_probe" || \
           { ! grep -Fq 'snapshot "$SRC" ||' "$db_probe" && \
             ! grep -Fq 'if ! snapshot "$SRC"; then' "$db_probe"; }; then
            fail "QA SQLite snapshot ownership 不得落入 command substitution"
        fi
        if ! grep -Fq 'rm -rf "$SNAP_DIR"' "$db_probe" || \
           ! grep -Fq 'DB=""' "$db_probe" || \
           ! grep -Fq 'SNAP_DIR=""' "$db_probe"; then
            fail "QA SQLite snapshot cleanup 未清除目錄與狀態"
        fi
        if ! grep -Fq 'current-shell snapshot 保存 ownership 並可完整 cleanup' "$db_probe" || \
           ! grep -Fq 'EXIT trap 完整刪除 snapshot DB、WAL 與 SHM' "$db_probe" || \
           ! grep -Fq '[ -e "$EXPLICIT_SNAPSHOT_DIR" ]' "$db_probe" || \
           ! grep -Fq '[ -e "$TRAP_SNAPSHOT_DIR" ]' "$db_probe"; then
            fail "QA SQLite probe 缺 snapshot cleanup 負向 selftest"
        fi
        if ! grep -Fq 'cmd_r08_original_language_profile()' "$db_probe" || \
           ! grep -Fq "AND _status != 'deleted'" "$db_probe" || \
           ! grep -Fq 'profile=r08_original_language language=$language' "$db_probe" || \
           ! grep -Fq 'R08 original language 只由 canonical snapshot exact-one Settings row 產生' "$db_probe" || \
           ! grep -Fq 'candidate facts 無法遮蔽 R08 duplicate Settings row' "$db_probe"; then
            fail "R08 SQLite original language profile 未鎖 live exact-one 與 candidate independence"
        fi
    fi
    local sqlite_symlink_profile_contract
    for sqlite_symlink_profile_contract in \
        'sqlite-local 必須同時 canonicalize QA data root 與 database parent，並只接受 exact `Documents/watermelon.db`' \
        'sqlite-local 必須拒絕 database、WAL 或 SHM 任一來源檔為 symlink' \
        'sqlite-local snapshot 必須使用 `cp -P`，並在查詢前拒絕複製後仍為 symlink 的 database、WAL 或 SHM' \
        'QA container 內指向 Production database 的 symlink escape 必須 fail-closed，且不得輸出資料內容' \
        'sqlite-local snapshot 必須在 current shell 設定 `SNAP_DIR` 與 `DB`，不得以 command substitution 呼叫 snapshot' \
        'sqlite-local cleanup 必須刪除 snapshot directory，並將 `SNAP_DIR` 與 `DB` 歸零' \
        'sqlite-local selftest 必須證明 explicit cleanup 與 EXIT trap 都刪除 snapshot database、WAL 與 SHM'; do
        grep -Fq "$sqlite_symlink_profile_contract" "$profile" 2>/dev/null || \
            fail "能力側寫缺 SQLite symlink containment 契約"
    done
    local probe_command
    while IFS= read -r probe_command; do
        case "$probe_command" in
            *--selftest*) ;;
            *"--bundle-id $qa_bundle_id"*) ;;
            *) fail "QA SQLite probe 指令未明確傳入 profile qaBundleId" ;;
        esac
    done < <(grep -Rh --include='*.md' --include='*.csv' \
        'bash no2_qa_tools/query_local_db.sh' "$profile" "$run_docs" 2>/dev/null)

    local prod_project="" prod_bundle=""
    if [ -f "$prod_firebase" ]; then
        prod_project=$(plist_value "$prod_firebase" PROJECT_ID)
        prod_bundle=$(plist_value "$prod_firebase" BUNDLE_ID)
        [ "$prod_project" = "$production_firebase_project_id" ] || \
            fail "Production Firebase PROJECT_ID 與 productionFirebaseProjectId 不符"
        [ "$prod_bundle" = "$production_bundle_id" ] || \
            fail "Production Firebase BUNDLE_ID 與 productionBundleId 不符"
    else
        note "  － Production Firebase config 缺少，略過本機值核對"
    fi

    if [ -f "$firebase" ]; then
        local qa_project qa_bundle qa_google_app
        qa_project=$(plist_value "$firebase" PROJECT_ID)
        qa_bundle=$(plist_value "$firebase" BUNDLE_ID)
        qa_google_app=$(plist_value "$firebase" GOOGLE_APP_ID)
        [ -n "$qa_project" ] || fail "QA Firebase PROJECT_ID 為空"
        [ "$qa_project" = "$qa_firebase_project_id" ] || fail "QA Firebase PROJECT_ID 與 qaFirebaseProjectId 不符"
        [ "$qa_google_app" = "$qa_google_app_id" ] || fail "QA Firebase GOOGLE_APP_ID 與 qaGoogleAppId 不符"
        printf '%s' "$qa_bundle" | grep -Eq '\.qa$' || fail "QA Firebase BUNDLE_ID 不是 .qa bundle"
        [ "$qa_bundle" = "$qa_bundle_id" ] || fail "QA Firebase BUNDLE_ID 與 qaBundleId 不符"
        [ -z "$prod_project" ] || [ "$qa_project" != "$prod_project" ] || fail "QA Firebase project 不得等於 Production project"
        check_qa_firebase_config_digest "$firebase" "$qa_firebase_config_sha256" "QA Firebase config"
        for id in qa-command qa-probe; do
            status=$(awk -F'|' -v target="$id" '$2 ~ target {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $4); print $4; exit}' "$profile")
            if [ "$status" != "受阻" ]; then
                fail "$id 持久狀態必須維持受阻，runtime 解鎖只限 session"
            fi
        done
    else
        local blocked_ok=1
        for id in qa-command qa-probe; do
            status=$(awk -F'|' -v target="$id" '$2 ~ target {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $4); print $4; exit}' "$profile")
            if [ "$status" != "受阻" ]; then
                fail "$id 必須因缺 QA Firebase config 標為受阻"
                blocked_ok=0
            fi
        done
        [ "$blocked_ok" -eq 1 ] && pass "QA Firebase config 缺少，qa-command 與 qa-probe 已正確標為受阻"
    fi
}

run_checks() {
    local plan="$1" script="$2" impl="$3" profile="$4"

    extract_verified "$script" > "${CHECK_TMP_PREFIX}_verified.txt"
    extract_assertions "$plan" > "${CHECK_TMP_PREFIX}_all.txt"
    extract_exceptions "$script" > "${CHECK_TMP_PREFIX}_exc.txt"

    local n_v n_a n_e
    n_v=$(wc -l < "${CHECK_TMP_PREFIX}_verified.txt")
    n_a=$(wc -l < "${CHECK_TMP_PREFIX}_all.txt")
    n_e=$(wc -l < "${CHECK_TMP_PREFIX}_exc.txt")

    note "[1] 抽取"
    if [ "$n_a" -eq 0 ]; then fail "分冊抽不到任何斷言，路徑或格式有問題"; return; fi
    if [ "$n_v" -eq 0 ]; then fail "腳本抽不到任何已驗引句，路徑或格式有問題"; return; fi
    pass "分冊 $n_a 條斷言、腳本 $n_v 條已驗、例外表 $n_e 條"

    note "[2] 正向：分冊有、腳本無，應逐條等於覆蓋例外表"
    grep -vxF -f "${CHECK_TMP_PREFIX}_verified.txt" "${CHECK_TMP_PREFIX}_all.txt" | sort -u > "${CHECK_TMP_PREFIX}_gap.txt"
    if diff -q "${CHECK_TMP_PREFIX}_gap.txt" "${CHECK_TMP_PREFIX}_exc.txt" >/dev/null 2>&1; then
        pass "缺口 $(wc -l < "${CHECK_TMP_PREFIX}_gap.txt") 條，與例外表逐條相符"
    else
        fail "缺口與例外表不符"
        comm -23 "${CHECK_TMP_PREFIX}_gap.txt" "${CHECK_TMP_PREFIX}_exc.txt" | sed 's/^/      未收下且未列例外： /'
        comm -13 "${CHECK_TMP_PREFIX}_gap.txt" "${CHECK_TMP_PREFIX}_exc.txt" | sed 's/^/      列了例外但其實已收下： /'
    fi

    note "[3] 反向：腳本有、分冊無，必須零失配"
    grep -vxF -f "${CHECK_TMP_PREFIX}_all.txt" "${CHECK_TMP_PREFIX}_verified.txt" > "${CHECK_TMP_PREFIX}_orphan.txt"
    if [ ! -s "${CHECK_TMP_PREFIX}_orphan.txt" ]; then
        pass "零失配"
    else
        fail "$(wc -l < "${CHECK_TMP_PREFIX}_orphan.txt") 條引句在分冊找不到逐字對應"
        sed 's/^/      /' "${CHECK_TMP_PREFIX}_orphan.txt"
    fi

    note "[4] 計數：已驗去重加例外等於分冊總數"
    if [ $((n_v + n_e)) -eq "$n_a" ]; then
        pass "$n_v 加 $n_e 對 $n_a"
    else
        fail "$n_v 加 $n_e 等於 $((n_v + n_e))，分冊為 $n_a"
    fi

    note "[5] marker 對帳：腳本引用的 QA 命名空間都在 impl 的 src 命中"
    if [ -z "$impl" ] || [ ! -d "$impl/src" ]; then
        note "  － 略過，未提供可用的 impl 路徑（--impl）"
    else
        grep -rho "QA [A-Z]\+" "$script"/*.csv 2>/dev/null | sort -u > "${CHECK_TMP_PREFIX}_mk_s.txt"
        grep -rho "QA [A-Z]\+" "$impl/src" --include=*.ts --include=*.tsx 2>/dev/null | sort -u > "${CHECK_TMP_PREFIX}_mk_i.txt"
        local miss; miss=$(grep -vxF -f "${CHECK_TMP_PREFIX}_mk_i.txt" "${CHECK_TMP_PREFIX}_mk_s.txt")
        if [ -z "$miss" ]; then
            pass "$(wc -l < "${CHECK_TMP_PREFIX}_mk_s.txt") 個命名空間全數命中"
        else
            fail "以下命名空間在 impl 不存在，執行當場會搜不到"
            printf '%s\n' "$miss" | sed 's/^/      /'
        fi
    fi

    note "[6] R00 核對列引用的測試檔路徑，每條樣式至少命中一個實際檔"
    # R00 同時點名 app 與後端兩側的測試檔，兩邊路徑都是 src/ 開頭、看字串分不出來，
    # 故任一側命中即算過。只掃單側會把另一側的七支後端測試全誤報成零命中。
    local r00="$script/no2_r00_static_verification.csv"
    if [ ! -f "$r00" ] || [ -z "$impl" ] || [ ! -d "$impl/src" ]; then
        note "  － 略過，缺 R00 檔或 impl 路徑"
    else
        local n_pat=0 n_miss=0
        while read -r p; do
            [ -z "$p" ] && continue
            n_pat=$((n_pat + 1))
            # shellcheck disable=SC2086
            local hits; hits=$( (eval ls $impl/$p 2>/dev/null; [ -n "$BACKEND" ] && eval ls $BACKEND/$p 2>/dev/null) | wc -l )
            if [ "$hits" -eq 0 ]; then
                fail "零命中：$p"; n_miss=$((n_miss + 1))
            fi
        done < <(grep -o "src/[a-zA-Z0-9/.*_-]*\.test\.tsx\?" "$r00" | sort -u)
        if [ "$n_miss" -eq 0 ]; then
            if [ -n "$BACKEND" ]; then pass "$n_pat 條樣式全數命中（app 與後端兩側合計）"
            else pass "$n_pat 條樣式全數命中（僅 app 側，後端未提供路徑）"; fi
        fi
    fi

    note "[7] 狀態鏈：每個前置場次都指向存在的場次"
    local bad=0
    for f in "$script"/no*_r*.md; do
        [ -f "$f" ] || continue
        local prev; prev=$(grep -o '前置場次:\*\* .*' "$f" | sed 's/前置場次:\*\* //' | sed 's/ .*//')
        [ -z "$prev" ] && continue
        [ "$prev" = "無" ] && continue
        if ! ls "$script"/no*_"$(printf '%s' "$prev" | tr 'A-Z' 'a-z')"_*.md >/dev/null 2>&1; then
            fail "$(basename "$f") 的前置場次 $prev 找不到對應檔"; bad=1
        fi
    done
    [ "$bad" -eq 0 ] && pass "全部前置場次都指得到"

    note "[8] schema：能力表、基線與九欄 QA metadata"
    local before
    before=$fail_count
    check_profile_and_baseline "$profile" "$plan"
    check_readiness_provider_contract "$plan" "$script"
    check_metadata_schema_fast "$plan"
    check_direct_case_mapping "$plan"
    if [ "$fail_count" -eq "$before" ]; then
        pass "能力表、基線與直接測項合法，$(awk -F'|' '$4 == "__block__" {print $3}' "${CHECK_TMP_PREFIX}_meta.txt" | sort -u | wc -l) 個 metadata 案例合法"
    fi

    note "[9] 手段引用與取證要求：本次操作者由 session 分配"
    before=$fail_count
    check_method_compatibility "$plan" "$script"
    if [ "$fail_count" -eq "$before" ]; then
        pass "分冊與腳本手段全數配對"
    fi

    note "[10] CSV type：九欄與合法 enum"
    before=$fail_count
    check_csv_schema "$script"
    if [ "$fail_count" -eq "$before" ]; then
        pass "$(wc -l < "${CHECK_TMP_PREFIX}_csv_rows.txt") 列 CSV schema 全數合法"
    fi

    note "[11] QA runtime：App QA 身分、RESULT identity 與 Firebase 阻斷"
    before=$fail_count
    check_fixture_golden_contract "$script" "$impl"
    check_qa_runtime_readiness "$impl" "$profile"
    if [ "$fail_count" -eq "$before" ]; then
        pass "QA runtime 靜態契約一致"
    fi

    note "[12] 場次 route：flexible session 解析與全程裝置不變式"
    before=$fail_count
    check_run_route_contract "$script"
    if [ "$fail_count" -eq "$before" ]; then
        pass "測項與場次 route 全數一致"
    fi
}

resolve_impl_path() {
    local quality_path="$1"
    local topic candidate main

    case "$quality_path" in
        */ai-company-worktrees/*)
            topic=$(dirname "$quality_path")
            for candidate in "$topic/impl-no2-accounting-app" "$topic/impl-no2_accounting_app"; do
                [ -d "$candidate/src" ] && printf '%s\n' "$candidate" && return
            done
            ;;
    esac

    main=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print substr($0,10); exit}')
    [ -n "$main" ] && printf '%s\n' "$main" | sed 's#no6_product_quality#no5_product_development#'
}

normalize_impl_path() {
    printf '%s\n' "${1%/}"
}

derive_backend_path() {
    local impl_path
    impl_path=$(normalize_impl_path "$1")

    case "$impl_path" in
        */ai-company-worktrees/*/impl-no2-accounting-app) printf '%s\n' "$impl_path" | sed 's#impl-no2-accounting-app$#impl-no3-cloud-functions/functions#' ;;
        */ai-company-worktrees/*/impl-no2_accounting_app) printf '%s\n' "$impl_path" | sed 's#impl-no2_accounting_app$#impl-no3_cloud_functions/functions#' ;;
        *) printf '%s\n' "$impl_path" | sed 's#no2_accounting_app$#no3_cloud_functions/functions#' ;;
    esac
}

# ── selftest：造多種已知壞資料，確認檢核器抓得到 ──
# 沒有這段，一支永遠印綠燈的檢核器跟沒有一樣。
check_execution_schema_selftest() (
    SCHEMA_WORK="$CHECK_TMP_ROOT/execution-schema"
    mkdir -p "$SCHEMA_WORK/plan" "$SCHEMA_WORK/runs"
    CHECK_TMP_PREFIX="$SCHEMA_WORK/check"
    FAIL_LOG=""
    schema_scenarios=0

    reset_schema_fixture() {
        cat > "$SCHEMA_WORK/profile.md" <<'CAP'
## 手段表
| 手段 id | 說明 | 狀態 | 操作需求 | 環境前提 | 限制 |
| --- | --- | --- | --- | --- | --- |
| manual-ui | 畫面 | 可用 | ui | 目標畫面 | 無 |
| manual-device | 裝置 | 可用 | device-ui | 目標裝置 | 無 |
| qa-command | 準備 | 受阻 | tool | QA session | bootstrap |
| qa-probe | 證據 | 受阻 | tool | QA session | bootstrap |
CAP
        cat > "$SCHEMA_WORK/plan/no0_index.md" <<'BASE'
## 生成基線表
| 上游 repo | commit | tree | 同步日期 |
| --- | --- | --- | --- |
| `sample` | `1111111111111111111111111111111111111111` | `2222222222222222222222222222222222222222` | 2026-09-30 |
BASE
        cat > "$SCHEMA_WORK/plan/no1_case.md" <<'PLAN'
## AA-01 測項
    - **取消後維持免費**
        - 層: UI ／ 手段: manual-ui
        - 取證時點: 取消後
PLAN
        printf '%s\n' \
            '序,測項,類型,動作,預期,取證時點,手段,已驗,說明' \
            '1,AA-01,操作,取消,免費,取消後,manual-ui,AA-01 取消後維持免費,' \
            '2,AA-01,取證,讀取證據,符合,取消後,qa-probe,,' \
            > "$SCHEMA_WORK/runs/no1_r01_case.csv"
    }

    assert_schema() {
        local label="$1" expected="${2:-}" schema_log="$SCHEMA_WORK/result.log"
        fail_count=0
        {
            check_profile_and_baseline "$SCHEMA_WORK/profile.md" "$SCHEMA_WORK/plan"
            check_method_compatibility "$SCHEMA_WORK/plan" "$SCHEMA_WORK/runs"
            check_csv_schema "$SCHEMA_WORK/runs"
        } > "$schema_log"
        if { [ -z "$expected" ] && [ "$fail_count" -ne 0 ]; } || \
            { [ -n "$expected" ] && ! grep -qF "$expected" "$schema_log"; }; then
            cat "$schema_log"
            printf 'execution schema selftest FAIL: %s\n' "$label"
            exit 1
        fi
        schema_scenarios=$((schema_scenarios + 1))
    }

    reset_schema_fixture
    assert_schema '中性格式包含受阻手段，定義有效但不代表可執行'

    printf '\357\273\277%s\r\n' '序,測項,類型,動作,預期,取證時點,手段,已驗,說明' > "$SCHEMA_WORK/runs/no1_r01_case.csv"
    printf '%s\r\n' '1,AA-01,操作,取消,免費,取消後,manual-ui,AA-01 取消後維持免費,' >> "$SCHEMA_WORK/runs/no1_r01_case.csv"
    assert_schema '中性格式保留 BOM 與 CRLF 仍可讀取'

    # 舊格式角色不同於能力表亦能讀取，不再綁死 UI 操作者。
    reset_schema_fixture
    sed 's/層: UI ／ 手段:/層: UI ／ 驗證者: Claude ／ 手段:/' \
        "$SCHEMA_WORK/plan/no1_case.md" > "$SCHEMA_WORK/changed"
    mv "$SCHEMA_WORK/changed" "$SCHEMA_WORK/plan/no1_case.md"
    printf '\357\273\277%s\r\n' '序,測項,類型,動作,預期,驗證者,手段,已驗,說明' > "$SCHEMA_WORK/runs/no1_r01_case.csv"
    printf '%s\r\n' '1,AA-01,操作,取消,免費,Claude,manual-ui,AA-01 取消後維持免費,' \
        '2,AA-01,Claude節點,讀證據,符合,使用者,qa-probe,,' >> "$SCHEMA_WORK/runs/no1_r01_case.csv"
    assert_schema '新側寫與舊測項混用，支援 BOM 與 CRLF'
    sed 's/操作需求/執行者/; s/| ui |/| 使用者 |/; s/| device-ui |/| 使用者 |/; s/| tool |/| Claude |/' \
        "$SCHEMA_WORK/profile.md" > "$SCHEMA_WORK/changed"
    mv "$SCHEMA_WORK/changed" "$SCHEMA_WORK/profile.md"
    assert_schema '完整舊格式相容，角色註記不分配工作'

    reset_schema_fixture
    sed 's/manual-ui/missing-method/g' "$SCHEMA_WORK/plan/no1_case.md" > "$SCHEMA_WORK/changed"
    mv "$SCHEMA_WORK/changed" "$SCHEMA_WORK/plan/no1_case.md"
    assert_schema '中性測項未知手段仍拒絕' '引用未知手段'

    reset_schema_fixture
    sed 's/manual-ui/missing-method/g' "$SCHEMA_WORK/runs/no1_r01_case.csv" > "$SCHEMA_WORK/changed"
    mv "$SCHEMA_WORK/changed" "$SCHEMA_WORK/runs/no1_r01_case.csv"
    assert_schema '中性 CSV 未知手段仍拒絕' '引用未知手段'

    reset_schema_fixture
    sed '/取證時點:/d' "$SCHEMA_WORK/plan/no1_case.md" > "$SCHEMA_WORK/changed"
    mv "$SCHEMA_WORK/changed" "$SCHEMA_WORK/plan/no1_case.md"
    assert_schema '中性測項缺取證時點' '缺少有效取證時點'
    cat >> "$SCHEMA_WORK/plan/no1_case.md" <<'PLAN'
    - **返回設定頁**
        - 層: UI ／ 手段: manual-ui
        - 取證時點: 返回設定後
PLAN
    assert_schema '後一檢查點的取證時點不能補前一項缺漏' '缺少有效取證時點'

    reset_schema_fixture
    sed 's/,取消後,/,使用者,/' "$SCHEMA_WORK/runs/no1_r01_case.csv" > "$SCHEMA_WORK/changed"
    mv "$SCHEMA_WORK/changed" "$SCHEMA_WORK/runs/no1_r01_case.csv"
    assert_schema '新欄位不能繼續填人名' '缺少有效取證時點'

    reset_schema_fixture
    sed 's/,取消後,/,  ,/' "$SCHEMA_WORK/runs/no1_r01_case.csv" > "$SCHEMA_WORK/changed"
    mv "$SCHEMA_WORK/changed" "$SCHEMA_WORK/runs/no1_r01_case.csv"
    assert_schema '取證時點不能只含空白' '缺少有效取證時點'

    reset_schema_fixture
    sed 's/,取證,/,Claude節點,/' "$SCHEMA_WORK/runs/no1_r01_case.csv" > "$SCHEMA_WORK/changed"
    mv "$SCHEMA_WORK/changed" "$SCHEMA_WORK/runs/no1_r01_case.csv"
    assert_schema '新表頭不能混用舊節點' '新格式不得使用 Claude節點'

    reset_schema_fixture
    sed 's/,取證,/,未知節點,/' "$SCHEMA_WORK/runs/no1_r01_case.csv" > "$SCHEMA_WORK/changed"
    mv "$SCHEMA_WORK/changed" "$SCHEMA_WORK/runs/no1_r01_case.csv"
    assert_schema '未知節點拒絕' '使用非法 type'

    reset_schema_fixture
    sed 's/取證時點/分工/' "$SCHEMA_WORK/runs/no1_r01_case.csv" > "$SCHEMA_WORK/changed"
    mv "$SCHEMA_WORK/changed" "$SCHEMA_WORK/runs/no1_r01_case.csv"
    assert_schema '不推測未知表頭的意義' 'CSV 表頭非法'

    reset_schema_fixture
    printf '%s\n' '3,AA-01,操作,取消,免費,取消後,manual-ui,AA-01 取消後維持免費,,多一欄' >> "$SCHEMA_WORK/runs/no1_r01_case.csv"
    assert_schema '欄數限制維持' '欄數為 10'

    reset_schema_fixture
    sed 's/| ui |/| Claude |/' "$SCHEMA_WORK/profile.md" > "$SCHEMA_WORK/changed"
    mv "$SCHEMA_WORK/changed" "$SCHEMA_WORK/profile.md"
    assert_schema '新能力需求不能填人名' '能力表操作需求非法'

    reset_schema_fixture
    sed 's/| ui |/| unavailable |/' "$SCHEMA_WORK/profile.md" > "$SCHEMA_WORK/changed"
    mv "$SCHEMA_WORK/changed" "$SCHEMA_WORK/profile.md"
    assert_schema '無路徑不能宣告可用' '無可用路徑的能力不得宣告可用'

    reset_schema_fixture
    sed 's/| device-ui |/| ui |/' "$SCHEMA_WORK/profile.md" > "$SCHEMA_WORK/changed"
    mv "$SCHEMA_WORK/changed" "$SCHEMA_WORK/profile.md"
    assert_schema '實機需求不能降成一般 UI' 'manual-device 操作需求必須為 device-ui'

    printf 'execution definition schema selftest PASS: %s scenarios\n' "$schema_scenarios"
)

if [ "$SELFTEST" -eq 1 ]; then
    check_execution_schema_selftest || exit 1
    check_qa_oauth_routes --selftest || exit 1
    TMP="$CHECK_TMP_ROOT/selftest"
    mkdir -p "$TMP"
    PARALLEL_DIR="$TMP/parallel"
    mkdir -p "$PARALLEL_DIR"
    SCRIPT_PATH=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
    SELFTEST_QUALITY_ROOT=$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)
    bash "$SCRIPT_PATH" --selftest-worker alpha "$PARALLEL_DIR" > "$TMP/alpha.log" 2>&1 &
    alpha_pid=$!
    bash "$SCRIPT_PATH" --selftest-worker beta "$PARALLEL_DIR" > "$TMP/beta.log" 2>&1 &
    beta_pid=$!
    alpha_status=0
    beta_status=0
    wait "$alpha_pid" || alpha_status=$?
    wait "$beta_pid" || beta_status=$?
    if [ "$alpha_status" -ne 0 ] || [ "$beta_status" -ne 0 ]; then
        sed -n '1,5p' "$TMP/alpha.log"
        sed -n '1,5p' "$TMP/beta.log"
        echo "selftest FAIL：平行執行共用了 scratch file。"
        exit 1
    fi
    echo "selftest parallel scratch PASS"
    mkdir -p "$TMP/$PLAN_DIR" "$TMP/$SCRIPT_DIR" "$TMP/no2_qa_tools/tests"
    cp "$SELFTEST_QUALITY_ROOT/no2_qa_tools/check_fixture_golden.py" \
        "$TMP/no2_qa_tools/check_fixture_golden.py"
    sed 's/r02_end:a3:c7:t9:f0:s0:v1/r02_end:a3:c7:t10:f0:s0:v1/g' \
        "$SELFTEST_QUALITY_ROOT/no3_run_scripts/no1_fixture_golden.json" \
        > "$TMP/$SCRIPT_DIR/no1_fixture_golden.json"
    cp "$SELFTEST_QUALITY_ROOT/no3_run_scripts/no1_fixtures.md" \
        "$TMP/$SCRIPT_DIR/no1_fixtures.md"

    check_derived_path() {
        [ "$1" = "$2" ] || { echo "selftest FAIL：$3"; exit 1; }
    }

    SELFTEST_CANONICAL="$TMP/ai-company-worktrees/canonical"
    mkdir -p "$SELFTEST_CANONICAL/impl-no2-accounting-app/src" "$SELFTEST_CANONICAL/impl-no2_accounting_app/src"
    check_derived_path "$(resolve_impl_path "$SELFTEST_CANONICAL/quality-no2-accounting-app")" "$SELFTEST_CANONICAL/impl-no2-accounting-app" "canonical sibling impl 推導失敗"
    check_derived_path "$(derive_backend_path "$SELFTEST_CANONICAL/impl-no2-accounting-app")" "$SELFTEST_CANONICAL/impl-no3-cloud-functions/functions" "canonical sibling backend 推導失敗"
    check_derived_path "$(normalize_impl_path "$SELFTEST_CANONICAL/impl-no2-accounting-app/")" "$SELFTEST_CANONICAL/impl-no2-accounting-app" "canonical impl 尾斜線正規化失敗"
    check_derived_path "$(derive_backend_path "$SELFTEST_CANONICAL/impl-no2-accounting-app/")" "$SELFTEST_CANONICAL/impl-no3-cloud-functions/functions" "canonical backend 尾斜線正規化失敗"
    SELFTEST_LEGACY="$TMP/ai-company-worktrees/legacy"
    mkdir -p "$SELFTEST_LEGACY/impl-no2_accounting_app/src"
    check_derived_path "$(resolve_impl_path "$SELFTEST_LEGACY/quality-no2_accounting_app")" "$SELFTEST_LEGACY/impl-no2_accounting_app" "legacy sibling impl 推導失敗"
    check_derived_path "$(derive_backend_path "$SELFTEST_LEGACY/impl-no2_accounting_app")" "$SELFTEST_LEGACY/impl-no3_cloud_functions/functions" "legacy sibling backend 推導失敗"
    check_derived_path "$(normalize_impl_path "$SELFTEST_LEGACY/impl-no2_accounting_app/")" "$SELFTEST_LEGACY/impl-no2_accounting_app" "legacy impl 尾斜線正規化失敗"
    check_derived_path "$(derive_backend_path "$SELFTEST_LEGACY/impl-no2_accounting_app/")" "$SELFTEST_LEGACY/impl-no3_cloud_functions/functions" "legacy backend 尾斜線正規化失敗"
    SELFTEST_MAIN_QUALITY=$(git worktree list --porcelain | awk '/^worktree /{print substr($0,10); exit}')
    SELFTEST_MAIN_IMPL=$(printf '%s' "$SELFTEST_MAIN_QUALITY" | sed 's#no6_product_quality#no5_product_development#')
    check_derived_path "$(resolve_impl_path "$TMP/no-sibling")" "$SELFTEST_MAIN_IMPL" "main git impl fallback 推導失敗"
    check_derived_path "$(derive_backend_path "$SELFTEST_MAIN_IMPL")" "$(printf '%s' "$SELFTEST_MAIN_IMPL" | sed 's#no2_accounting_app$#no3_cloud_functions/functions#')" "main git snake_case fallback 推導失敗"
    check_derived_path "$(normalize_impl_path "$SELFTEST_MAIN_IMPL/")" "$SELFTEST_MAIN_IMPL" "main git impl 尾斜線正規化失敗"
    check_derived_path "$(derive_backend_path "$SELFTEST_MAIN_IMPL/")" "$(printf '%s' "$SELFTEST_MAIN_IMPL" | sed 's#no2_accounting_app$#no3_cloud_functions/functions#')" "main git backend 尾斜線正規化失敗"
    pass "canonical、legacy 與 main git fallback 推導正確"

    cat > "$TMP/no1_capability_profile.md" <<'CAP'
## App QA 身分

- `qaScheme=Wrong-QA`
- `qaMode=Wrong-QA`
- `qaBundleId=com.example.wrong.qa`
- `qaFirebaseProjectId=susugigi-qa`
- `qaGoogleAppId=1:352034825841:ios:40c5c3bcfa630b4a6a1dd0`
- `qaFirebaseConfigSha256=0000000000000000000000000000000000000000000000000000000000000000`
- `qaIdentityMode=disposable-anonymous`
- `productionFirebaseProjectId=susugigi-c4fb1`
- `productionBundleId=com.almightyken0425.susugigiapp`

## 手段表

| 手段 id | 說明 | 狀態 | 執行者 | 環境前提 | 限制 |
| --- | --- | --- | --- | --- | --- |
| manual-ui | 手動 | 可用 | 使用者 | 無 | 無 |
| manual-device | 實機 | 可用 | 使用者 | 無 | 無 |
| qa-markers | 標記 | 可用 | Claude | 無 | 無 |
| qa-command | 命令 | 可用 | Claude | 無 | 無 |
| qa-probe | 探針 | 可用 | Claude | 無 | 無 |
CAP

    cat > "$TMP/$PLAN_DIR/no1_x.md" <<'PLAN'
## AA-01 測項一

- **QA metadata:**
    - feature_links: `app/test`
    - risk_tags: `selftest`
    - capabilities: `qa-markers`
    - tier: `core`
    - runtime_route: `simulator-or-physical-device`
    - driver: `sim-review`
    - seed: `r99_unknown`
    - inspect: `accounting.fixture-summary`
    - evidence: `qa-markers`

- **前置:**
    - firestore-read 與 cloud-logging 條件為 Firebase CLI 或 gcloud 已登入

- **檢查點:**
    - **甲斷言，含全形逗號**
        - 層: 日誌 ／ 驗證者: 使用者 ／ 手段: qa-markers
    - **乙斷言；分號後半段**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **丙斷言沒人收**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui

## AA-02 測項二

- **QA metadata:**
    - feature_links: `app/test`
    - risk_tags: `selftest`
    - capabilities: `qa-markers`
    - tier: `extended`
    - runtime_route: `physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `qa-markers`
PLAN

    printf '\xef\xbb\xbf序,測項,類型,動作,預期,驗證者,手段,已驗,說明\n' > "$TMP/$SCRIPT_DIR/no2_r00_x.csv"
    echo '1,AA-01,操作,做甲,好,使用者,manual-ui,AA-01 甲斷言，含全形逗號；AA-01 乙斷言,QA BOGUS 這個命名空間不存在' >> "$TMP/$SCRIPT_DIR/no2_r00_x.csv"
    # 孤兒引句：分冊沒有這條，反向那項應咬到
    echo '2,AA-01,Codex節點,做丁,好,使用者,qa-markers,AA-01 分冊裡查無此斷言,' >> "$TMP/$SCRIPT_DIR/no2_r00_x.csv"


    cat > "$TMP/$PLAN_DIR/no0_index.md" <<'BASE'
## 生成基線表

| 上游 repo | commit | tree | 同步日期 |
| --- | --- | --- | --- |
| `selftest` | `abc1234` | `deadbeef` | 2026-08-26 |

## 路徑映射表

| impl 路徑前綴 | 區碼 | 直接測項 |
| --- | --- | --- |
| `src/database/helpers/createInitialUserData.ts`、`src/database/helpers/createInitialUserData.test.ts` | QA | `AU-01`、`AU-03`、`CS-02` |
| `src/services/userService.ts`、`src/services/userService.test.ts` | QA | `AU-01`、`AU-03`、`CS-01`、`CS-02` |
| `src/services/recurringLogic*` | RC | |
| `src/services/recurringLogic.ts`、`src/services/recurringLogic.test.ts` | QA | `AU-01`、`AU-03`、`CS-02` |
| `src/services/syncEngine.ts`、`src/services/syncEngine.test.ts` | QA | `CS-02` |
| `src/services/runBackup.ts`、`src/services/runBackup.test.ts` | QA | `CS-02` |
| `src/contexts/PremiumContext.tsx`、`src/contexts/PremiumContext.storeKit.test.tsx` | QA | `CS-03`、`PM-02`、`PM-03` |
| `src/qa/` | QA | `AA-01` |
| `ios/scripts/select-firebase-config.sh`、`ios/SuSuGiGiApp.xcodeproj/project.pbxproj`、`ios/SuSuGiGiApp/AppDelegate.swift` | QA | `AA-01`、`ZZ-99`、`bogus` |
BASE

    cat > "$TMP/$SCRIPT_DIR/no0_index.md" <<'IDX'
## 場次總表

| 場次 | 檔 | 涵蓋測項 | 前置場次 | 步驟數 | 預估時長 |
| --- | --- | --- | --- | --- | --- |
| R13 補產生驗證 | `no15_r13.md` | AA-01、AA-02 | 無 | 1 | 1 分 |

## 覆蓋例外表

| 檢查點 | 理由 |
| --- | --- |
| AA-01 這條根本不在分冊裡 | 故意寫錯供 selftest 用 |

---
IDX

    cat > "$TMP/$SCRIPT_DIR/no15_r13.md" <<'RUN'
# R13 故意錯誤場次

- **前置環境:**
    - Mac 加 simulator
    - qa-command 已解除阻斷
RUN

    cat > "$TMP/$SCRIPT_DIR/no15_r13_backfill_verification.csv" <<'R13_CSV'
序,測項,類型,動作,預期,驗證者,手段,已驗,說明
1,,Claude節點,以 requestId r13-prepare 啟動 prepare,失敗樣本,Claude,qa-command,,
2,,Claude節點,以 requestId r13-backfill 啟動 inspect,失敗樣本,Claude,qa-probe,,
3,RC-06,Claude節點,對帳 log,失敗樣本,Claude,qa-markers,,requestId 必須為 r13-backfill
R13_CSV

    cat > "$TMP/$SCRIPT_DIR/no5_r03_backup_export.md" <<'RUN'
# R03 故意錯誤場次

- 讀取最新一筆 Firestore 文件，不綁定 READY 身分。
RUN

    cat > "$TMP/$SCRIPT_DIR/no5_r03_backup_export.csv" <<'R03'
序,測項,類型,動作,預期,驗證者,手段,已驗,說明
4,CS-02,Claude節點,Claude 以 firestore-read 查該 uid 下六個資料 collections,故意模糊,Claude,firestore-read,,
16,CS-03,Claude節點,Claude 以 firestore-read 查 transactions 集合,故意模糊,Claude,firestore-read,,
R03

    cat > "$TMP/$SCRIPT_DIR/no14_r12_teardown_rebirth.md" <<'R12_RUNBOOK'
# R12 故意錯誤場次

- 從 Metro 讀取 raw uid 後直接重生。
R12_RUNBOOK

    cat > "$TMP/$SCRIPT_DIR/no14_r12_teardown_rebirth.csv" <<'R12_CSV'
序,測項,類型,動作,預期,驗證者,手段,已驗,說明
2,AS-07,操作,自 Metro 輸出記下清除前 uid 前八碼,故意洩漏,使用者,manual-ui,,
11,AS-07、CF-03,Claude節點,Claude 以 firestore-read collection-wide 查舊 uid 與 txnIndex 集合,故意模糊,Claude,firestore-read,,
R12_CSV

    cat > "$TMP/no2_qa_tools/query_local_db.sh" <<'DB_PROBE'
#!/usr/bin/env bash
set -euo pipefail

DB_OVERRIDE="unsafe-production-path"
# 同步漂移改跟隨假 Impl seeder，不得跟隨 Quality 字面值。
# name = '卡片'
# name = '娛樂'
# type = 'expense'
# target_schedule.template_amount = -9900000
# target_schedule.template_note = '午餐'
# date('now', 'localtime', 'start of month', '-2 months', '+7 days')
# OR amount != -9900000
# OR note IS NOT '午餐'
echo "unsafe implicit bundle probe"
DB_PROBE

    cat > "$TMP/no2_qa_tools/cleanup_qa_fixtures.sh" <<'FIXTURE_CLEANUP'
#!/usr/bin/env bash
set -euo pipefail

read -r session_uid
firebase firestore:delete "users/${session_uid}" --recursive --force --project susugigi-qa
FIXTURE_CLEANUP

    cat > "$TMP/no2_qa_tools/tests/cleanup_qa_fixtures_test.sh" <<'FIXTURE_CLEANUP_TEST'
#!/usr/bin/env bash
for override_name in FIRESTORE_EMULATOR_HOST FIRESTORE_URL FIREBASE_EMULATOR_HUB; do
    printf '%s\n' "$override_name" >/dev/null
done
FIXTURE_CLEANUP_TEST

    cat > "$TMP/$SCRIPT_DIR/no8_r06_dashboard.csv" <<'R06'
序,測項,類型,動作,預期,驗證者,手段,已驗,說明
19,,建置,先執行 Load overlay 才檢查離線,錯誤順序,使用者,manual-ui,,故意缺 offline-first
20,,還原,恢復 session 鎖定裝置的網路,錯誤順序,使用者,manual-ui,,故意早於 cleanup
21,,還原,prepare r06_large_history_cleanup,歸零,Claude,qa-command,,故意晚於恢復網路
R06

    printf '%s%s\n' '- RESULT 誤用 `result.' 'evidence`' >> "$TMP/$SCRIPT_DIR/no15_r13.md"

    note "=== selftest：預期抓到覆蓋、runtime、schema、手段與 CSV type 失配 ==="
    IMPL_SELF="$TMP/fakeimpl"
    mkdir -p \
        "$IMPL_SELF/ios/scripts" \
        "$IMPL_SELF/ios/SuSuGiGiApp" \
        "$IMPL_SELF/ios/SuSuGiGiApp.xcodeproj" \
        "$IMPL_SELF/src/contexts" \
        "$IMPL_SELF/src/database/helpers" \
        "$IMPL_SELF/src/qa" \
        "$IMPL_SELF/src/services"
    echo "console.log('QA REAL x')" > "$IMPL_SELF/src/a.ts"
    cat > "$IMPL_SELF/index.qa.js" <<'QA_ENTRY'
const { initializeAppCheck } = require('./src/services/appCheck');
initializeAppCheck();
QA_ENTRY
    cat > "$IMPL_SELF/ios/SuSuGiGiApp/BuildEnvironmentModule.m" <<'NATIVE_PROOF'
[proof setObject:token forKey:@"token"];
[proof setObject:uid forKey:@"uid"];
NATIVE_PROOF
    cat > "$IMPL_SELF/ios/GoogleService-Info-QA.plist" <<'QA_FIREBASE'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>PROJECT_ID</key>
    <string>susugigi-c4fb1</string>
    <key>BUNDLE_ID</key>
    <string>com.almightyken0425.susugigiapp</string>
    <key>GOOGLE_APP_ID</key>
    <string>wrong-google-app-id</string>
</dict>
</plist>
QA_FIREBASE
    cat > "$IMPL_SELF/ios/GoogleService-Info.plist" <<'PRODUCTION_FIREBASE'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>PROJECT_ID</key>
    <string>susugigi-c4fb1</string>
    <key>BUNDLE_ID</key>
    <string>com.almightyken0425.susugigiapp</string>
</dict>
</plist>
PRODUCTION_FIREBASE
    cat > "$IMPL_SELF/ios/GoogleService-Info-QA-mixed-api-key.plist" <<'MIXED_QA_FIREBASE'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>PROJECT_ID</key>
    <string>susugigi-qa</string>
    <key>BUNDLE_ID</key>
    <string>com.almightyken0425.susugigiapp.qa</string>
    <key>GOOGLE_APP_ID</key>
    <string>1:352034825841:ios:40c5c3bcfa630b4a6a1dd0</string>
    <key>API_KEY</key>
    <string>wrong-route-key</string>
</dict>
</plist>
MIXED_QA_FIREBASE
    cat > "$IMPL_SELF/ios/scripts/select-firebase-config.sh" <<'FIREBASE_SELECTOR'
source_plist="$project_dir/SuSuGiGiApp/GoogleService-Info-QA.plist"
source_plist="$project_dir/GoogleService-Info.plist"
FIREBASE_SELECTOR
    cat > "$IMPL_SELF/ios/SuSuGiGiApp.xcodeproj/project.pbxproj" <<'XCODE_PROJECT'
buildPhases = (
    A60000000000000000000005 /* Select Firebase Configuration */,
    13B07F8E1A680F5B00A75B9A /* Resources */,
    2E3B770117BB3642B101F87F /* [CP-User] [RNFB] Core Configuration */,
);
/* GoogleService-Info.plist in Resources */
XCODE_PROJECT
    cat > "$IMPL_SELF/src/qa/registerQaRuntime.ts" <<'QA_RUNTIME'
export function registerQaRuntime(identityHash: string): void {
    (globalThis as any).__SUSUGIGI_QA__ = {prepare: () => undefined};
    console.log(`QA READY ${JSON.stringify({
        schema: 'qa.runtime/v1',
        requestId: 'prepare-00000000000000000000000000000000',
        state: 'ready',
        isAnonymous: true,
        identityMode: 'disposable-anonymous',
        identityHash,
        debugUid: 'raw-uid-must-not-appear',
    })}`);
}
QA_RUNTIME
    cat > "$IMPL_SELF/src/qa/registerQaRuntime.test.ts" <<'QA_RUNTIME_TEST'
it('identity hash test placeholder', () => {
    expect(true).toBe(true);
});
QA_RUNTIME_TEST
    cat > "$IMPL_SELF/src/qa/QaRuntimeBridge.tsx" <<'QA_RUNTIME_BRIDGE'
export default function QaRuntimeBridge(): null {
    registerQaRuntime('stale-user');
    return null;
}
QA_RUNTIME_BRIDGE
    cat > "$IMPL_SELF/src/qa/QaRuntimeBridge.test.ts" <<'QA_RUNTIME_BRIDGE_TEST'
it('loading placeholder', () => {
    expect(true).toBe(true);
});
QA_RUNTIME_BRIDGE_TEST
    cat > "$IMPL_SELF/src/qa/interface.ts" <<'QA_INTERFACE'
export type QaResult<T> = {
    readonly ok: boolean;
    readonly value: T;
    readonly error?: string;
};
export type QaPrepared = {
    readonly sceneId: string;
    readonly fingerprint: string;
    readonly debug: string;
};
export type QaEvidence = {
    readonly schema: string;
    readonly checkId: string;
    readonly verdict: string;
    readonly facts: ReadonlyArray<{
        readonly key: string;
        readonly actual: unknown;
        readonly nested?: object;
    }>;
};
QA_INTERFACE
    cat > "$IMPL_SELF/src/qa/enabledQaHarness.ts" <<'ENABLED_HARNESS'
export const failure = (error: Error) => ({
    ok: false,
    error: error.message,
});
ENABLED_HARNESS
    cat > "$IMPL_SELF/src/qa/enabledQaHarness.test.ts" <<'ENABLED_HARNESS_TEST'
it('nested result placeholder', () => {
    expect(true).toBe(true);
});
ENABLED_HARNESS_TEST
    cat > "$IMPL_SELF/src/qa/appQaHarness.test.ts" <<'APP_HARNESS_TEST'
expect(result).toEqual({
    error: 'QA fixture verification failed',
});
APP_HARNESS_TEST
    cat > "$IMPL_SELF/src/qa/appQaHarness.ts" <<'APP_HARNESS'
export const sceneFingerprints = {
    r02_end: 'r02_end:a3:c7:t10:f0:s0:v1',
    r09_stale_schedule: 'r09_stale_schedule:a3:c7:t9:f2:s1:v1',
};
APP_HARNESS
    cat > "$IMPL_SELF/src/services/regressionFixture.ts" <<'REGRESSION_FIXTURE'
export const FIXTURE_STALE_SCHEDULE = {
    note: '午餐',
    category: '娛樂',
    account: '卡片',
    amount: 990,
    frequency: 'DAILY',
    interval: 1,
    startMonthOffset: -2,
    startDay: 8,
};
REGRESSION_FIXTURE
    cat > "$IMPL_SELF/src/qa/qaLaunchPlan.ts" <<'QA_LAUNCH_PLAN'
const requestIdPattern = /^[A-Za-z0-9._-]{1,64}$/;

export function parseQaLaunchPlan(input: {
    requestId?: string;
    sessionToken?: string;
}): unknown {
    return input.requestId && requestIdPattern.test(input.requestId)
        ? input
        : null;
}
QA_LAUNCH_PLAN
    cat > "$IMPL_SELF/src/qa/qaLaunchPlan.test.ts" <<'QA_LAUNCH_PLAN_TEST'
it('accepts a generic request id', () => {
    expect(parseQaLaunchPlan({requestId: 'generic.request'})).not.toBeNull();
});
QA_LAUNCH_PLAN_TEST
    cat > "$IMPL_SELF/src/qa/anonymousIdentityBootstrap.ts" <<'QA_BOOTSTRAP'
export async function bootstrapDisposableAnonymousIdentity(
    persistedUser: {delete(): Promise<void>} | null,
    createAnonymous: () => Promise<unknown>,
): Promise<void> {
    if (persistedUser) {
        await persistedUser.delete();
    }
    await createAnonymous();
    console.log('QA READY');
}
QA_BOOTSTRAP
    cat > "$IMPL_SELF/src/qa/anonymousIdentityBootstrap.test.ts" <<'QA_BOOTSTRAP_TEST'
it('persisted anonymous user 刪除失敗時不得建立新身分或產出 READY', async () => {
    expect('QA_STALE_ANONYMOUS_DISPOSAL_FAILED').toBeTruthy();
    expect(createAnonymous).not.toHaveBeenCalled();
});
QA_BOOTSTRAP_TEST
    cat > "$IMPL_SELF/src/qa/nativeQaBuildIsolation.test.ts" <<'NATIVE_ISOLATION_TEST'
it('session proof 限制 TTL 與 consumed binding replay set', () => {
    expect(nativeModule).toContain('@"expiresAt"');
});
NATIVE_ISOLATION_TEST
    cat > "$IMPL_SELF/src/contexts/AuthContext.tsx" <<'AUTH_CONTEXT'
export function AuthProvider(): null {
    const qaAuthGuardTerminalBlocked = { current: false };
    return null;
}
AUTH_CONTEXT
    cat > "$IMPL_SELF/src/contexts/AuthContext.anonymousBootstrap.test.tsx" <<'AUTH_CONTEXT_TEST'
it('QA strict guard mismatch 後即使 expected UID 到達也永久 blocked', () => {
    expect(mockHandlePostAuth).not.toHaveBeenCalled();
});
AUTH_CONTEXT_TEST
    cat > "$IMPL_SELF/src/database/helpers/createInitialUserData.ts" <<'INITIAL_DATA'
export async function createInitialUserData(): Promise<void> {
    await database.write(async () => {});
}
INITIAL_DATA
    cat > "$IMPL_SELF/src/database/helpers/createInitialUserData.test.ts" <<'INITIAL_DATA_TEST'
it('stale identity placeholder', () => {
    expect(true).toBe(true);
});
INITIAL_DATA_TEST
    cat > "$IMPL_SELF/src/services/recurringLogic.ts" <<'RECURRING_LOGIC'
const inFlightByUser = new Map<string, Promise<void>>();
export function generateMissingInstances(userId: string): Promise<void> {
    const run = database.get('schedules').query(userId).fetch();
    inFlightByUser.set(userId, run);
    return run;
}
RECURRING_LOGIC
    cat > "$IMPL_SELF/src/services/recurringLogic.test.ts" <<'RECURRING_LOGIC_TEST'
it('identity guard placeholder', () => {
    expect(true).toBe(true);
});
RECURRING_LOGIC_TEST
    cat > "$IMPL_SELF/src/services/userService.ts" <<'USER_SERVICE'
export function uploadPreferences(uid: string): void {
    console.log('unsafe uid', uid);
}
USER_SERVICE
    cat > "$IMPL_SELF/src/services/userService.test.ts" <<'USER_SERVICE_TEST'
it('raw uid log placeholder', () => {
    expect(true).toBe(true);
});
USER_SERVICE_TEST
    cat > "$IMPL_SELF/src/services/syncEngine.ts" <<'SYNC_ENGINE'
export function sync(user: { uid: string }): void {
    console.log(`unsafe uid=${user.uid}`);
}
SYNC_ENGINE
    cat > "$IMPL_SELF/src/services/syncEngine.test.ts" <<'SYNC_ENGINE_TEST'
it('raw uid log placeholder', () => {
    expect(true).toBe(true);
});
SYNC_ENGINE_TEST
    cat > "$IMPL_SELF/src/services/runBackup.ts" <<'RUN_BACKUP'
export function runBackup(): void {
    import('./syncEngine').then(({ syncEngine }) => syncEngine.sync());
}
RUN_BACKUP
    cat > "$IMPL_SELF/src/services/runBackup.test.ts" <<'RUN_BACKUP_TEST'
it('identity guard placeholder', () => {
    expect(true).toBe(true);
});
RUN_BACKUP_TEST
    cat > "$IMPL_SELF/src/contexts/PremiumContext.tsx" <<'PREMIUM_CONTEXT'
export function PremiumProvider(): null {
    runBackup();
    return null;
}
PREMIUM_CONTEXT
    cat > "$IMPL_SELF/src/contexts/PremiumContext.storeKit.test.tsx" <<'PREMIUM_CONTEXT_TEST'
it('foreground backup placeholder', () => {
    expect(true).toBe(true);
});
PREMIUM_CONTEXT_TEST
    cat > "$IMPL_SELF/src/services/localOnlyBackupPolicy.ts" <<'POLICY'
export const R06_LARGE_HISTORY_LOCAL_ONLY_MARKER =
    '__SUSUGIGI_QA_R06_LARGE_HISTORY_V1__';
export const R06_LARGE_HISTORY_SYNC_SUSPEND_REASON =
    'qa-r06-large-history-overlay';
export function isLocalOnlyBackupRow(row: { note?: unknown }): boolean {
    return typeof row.note === 'string' &&
        row.note.startsWith(R06_LARGE_HISTORY_LOCAL_ONLY_MARKER);
}
POLICY
    FAIL_LOG="$TMP/failures.log"
    run_checks "$TMP/$PLAN_DIR" "$TMP/$SCRIPT_DIR" "$IMPL_SELF" "$TMP/no1_capability_profile.md"
    check_qa_firebase_config_digest \
        "$IMPL_SELF/ios/GoogleService-Info-QA-mixed-api-key.plist" \
        "$CANONICAL_QA_FIREBASE_CONFIG_SHA256" \
        "QA Firebase mixed API key config"
    local_expected_failures=(
        '直接測項格式非法：bogus'
        '直接測項不存在：ZZ-99'
        'App.tsx 的 direct-priority 測項集合不符'
        'src/contexts/AuthContext* 的 direct-priority 測項集合不符'
        'recurringLogic implementation 的 direct-priority 測項集合不符'
        'recurringLogic test 的 direct-priority 測項集合不符'
        'localDbService QA reset overlap 被 coarse mapping shadow'
        'createInitialUserData implementation 的 direct-priority 測項集合不符'
        'createInitialUserData test 的 direct-priority 測項集合不符'
        'userService implementation 的 direct-priority 測項集合不符'
        'userService test 的 direct-priority 測項集合不符'
        'syncEngine implementation 的 direct-priority 測項集合不符'
        'syncEngine test 的 direct-priority 測項集合不符'
        'runBackup implementation 的 direct-priority 測項集合不符'
        'runBackup test 的 direct-priority 測項集合不符'
        'PremiumContext implementation 的 direct-priority 測項集合不符'
        'PremiumContext storeKit test 的 direct-priority 測項集合不符'
        'src/qa/ broad mapping 必須維持 coarse-only'
        'QA bootstrap implementation 的 direct-priority 測項集合不符'
        'QA bootstrap test 的 direct-priority 測項集合不符'
        'QA disposal implementation 的 direct-priority 測項集合不符'
        'QA disposal test 的 direct-priority 測項集合不符'
        'QA session proof implementation 的 direct-priority 測項集合不符'
        'QA session proof test 的 direct-priority 測項集合不符'
        'QA native proof test 的 direct-priority 測項集合不符'
        'QA native proof implementation 的 direct-priority 測項集合不符'
        '.gitignore 的 direct-priority 測項集合不符'
        'src/qa/registerQaRuntime.ts 的 direct-priority 測項集合不符'
        'src/qa/QaRuntimeBridge.tsx 的 direct-priority 測項集合不符'
        'src/qa/QaRuntimeBridge.test.ts 的 direct-priority 測項集合不符'
        'src/qa/interface.ts 的 direct-priority 測項集合不符'
        'src/qa/qaLaunchPlan.ts 的 direct-priority 測項集合不符'
        'src/qa/qaLaunchPlan.test.ts 的 direct-priority 測項集合不符'
        'src/qa/enabledQaHarness.ts 的 direct-priority 測項集合不符'
        'src/qa/appQaHarness.test.ts 的 direct-priority 測項集合不符'
        'src/utils/buildEnvironment.ts 的 direct-priority 測項集合不符'
        'QA session token 未限制為 64-hex secret'
        'QA session token 未使用 process environment secret seam'
        'QA requestId 未限制為 operation prefix 加 32-lowerhex'
        'QA requestId prefix 未與 launch kind 綁定'
        'QA launch plan 未拒絕多 operation'
        'QA requestId malformed 與 prefix mismatch 負向測試不完整'
        'native session proof 缺契約：@"tokenHash"'
        'native session proof 缺契約：@"uidHash"'
        'native session proof 缺契約：QaSessionProofTTL = 8.0 * 60.0 * 60.0'
        'native session proof 缺契約：!isfinite(expiresAt.doubleValue)'
        'native session proof 缺契約：expiresAt.doubleValue <= 0.0'
        'native session proof 缺契約：expiresAt.doubleValue > NSDate.date.timeIntervalSince1970 + QaSessionProofTTL'
        'native session proof 缺契約：QaBindingHash(operationBinding)'
        'native session proof persisted key set 不等於 exact 六 keys'
        'native session proof 未在欄位讀取前拒絕額外 key'
        'native session proof exact-key 負向 source test 不完整'
        'native session proof persisted hash 缺 64-lowerhex 共用 shape gate'
        'native session proof persisted hash shape 負向 source test 不完整'
        'native session proof 非有限或非正 expiry 測試不存在'
        'native session proof 不得保存 raw token 或 uid'
        'QA operation 未消耗 session proof'
        'QA operation authorization 未拒絕多 operation'
        'open-app 未綁定 exact operation value'
        'QA runtime 不得發布 global adapter'
        'open-app global absence 與零 operation 測試不完整'
        'operation root A→B 或 replay 防護測試不完整'
        'AuthProvider 缺 QA terminal latch'
        'AuthProvider 缺同步 identity epoch invalidation'
        'AuthProvider 未將 identity guard 傳入 post-auth'
        'AuthProvider auth race 負向測試未鎖 stale setUser、排程與備份'
        'AuthProvider 未將 identity guard 傳入 recurring backfill'
        'recurringLogic 缺 optional stale identity guard 與 dynamic in-flight aggregation'
        'recurringLogic 未在每個 await 後與 transaction/transfer create 前後重驗 identity'
        'recurringLogic identity flip 負向測試未鎖零後續本地寫入'
        'AuthProvider recurring identity flip 負向測試不完整'
        'post-auth 未將 isCurrent guard 傳過本地 seed 與 Firestore write stage'
        'createInitialUserData 缺 stale identity write guard'
        'createInitialUserData stale identity 負向測試不完整'
        'post-auth stale identity 負向測試未鎖 local 或 Firestore orphan prevention'
        'AuthProvider 未把當輪 UID 與 epoch guard 綁入 background backup'
        'AuthProvider background backup guard 測試不存在'
        'runBackup 未在 dynamic import settle 後驗 UID、匿名狀態與 epoch guard'
        'runBackup identity-bound delegation 負向測試不完整'
        'syncEngine 未在 await 與 Firestore batch 邊界重驗 expected UID guard'
        'syncEngine identity flip 負向測試未鎖 Firestore batch 零寫入'
        'Premium foreground backup 未沿用 AuthProvider session guard'
        'QA runtime bridge 未以 AuthProvider isLoading 阻擋 READY binding'
        'post-auth settled-by-construction 測試或 isLoading 收斂順序不完整'
        'QaResult producer exact schema 欄位不符'
        'QaPrepared producer exact schema 欄位不符'
        'QaEvidence producer exact schema 欄位不符'
        'QA producer exact schema 允許 exception 或任意 nested evidence'
        'prepare 與 inspect exact failure schema 負向測試不完整'
        'QA operation READY identityHash 未驗 64-lowerhex'
        'QA operation READY invalid identityHash 測試未拒絕 runtime 與 READY'
        'QA operation READY producer exact keys 不符'
        'QA bootstrap READY producer exact keys 不符'
        'QA operation READY exact-object 測試未鎖六 keys 與 raw uid 隔離'
        'prepare 與 inspect error exact allowlist 不符'
        'launch error exact allowlist 不符'
        'QA RESULT error allowlist 未依 operation exact 分流'
        'QA RESULT error fallback 未拒絕跨 operation 或未登錄 QA code'
        'QA nested RESULT 不得回傳 exception message'
        'QA nested RESULT raw uid 隔離測試不存在'
        'QA app harness 測試仍期待 raw exception message'
        'userService console 不得直接輸出 raw uid 或 user.uid'
        'syncEngine console 不得直接輸出 raw uid 或 user.uid'
        'userService raw uid log 隔離測試不存在'
        'syncEngine raw uid log 隔離測試不存在'
        'QA READY 缺 identityHash'
        'QA READY identityHash 未取自 native session proof'
        'QA READY identityHash 未驗 native proof 64-lowerhex'
        'QA READY identityHash 未直接採用 native proof expectedUidHash'
        'QA READY invalid identityHash 測試未保留清理權限並拒絕 READY'
        'QA bootstrap log 未鎖 secret token 隔離'
        'QA bootstrap stale delete 未確認 Auth current user 已收斂為 null'
        'QA bootstrap stale delete resolve 但 current remains 負向測試不存在'
        'QA entry 不得載入 AppCheck'
        'QA build 不得註冊 RNFBAppCheck provider'
        'disposal 未以 token 與 uid begin proof'
        'disposal 未確認 Firebase Auth current user 為 null'
        'disposal log 未鎖 secret token 隔離'
        'Production graph 缺 canonical symlink isolation 測試'
        'Production graph 缺 lexical src/qa escape 測試'
        'sqlite readiness 未顯式傳入 profile qaBundleId'
        'QA SQLite probe 未要求顯式 bundle id'
        'QA SQLite probe 未拒絕 Production bundle'
        'QA SQLite probe 未限制 canonical QA bundle'
        'QA SQLite probe 正式介面不得接受任意 DB override'
        'QA SQLite probe 未 fail-closed 拒絕 Production DB override'
        'QA SQLite probe 缺 canonical container confinement'
        'QA SQLite probe 未拒絕 DB/WAL/SHM symlink'
        'QA SQLite snapshot 缺 cp -P 與 copied symlink fail-closed'
        'QA SQLite probe 缺 Production symlink escape 負向 selftest'
        'QA SQLite snapshot ownership 不得落入 command substitution'
        'QA SQLite snapshot cleanup 未清除目錄與狀態'
        'QA SQLite probe 缺 snapshot cleanup 負向 selftest'
        'Quality golden 與固定 scene fingerprint 不一致'
        'Impl R13 fixture semantics 與 Quality golden 不一致'
        'R13 SQLite profile 未鎖 Quality fixture semantics'
        'readiness 契約不得把 Firebase CLI 與 gcloud OAuth 寫成替代關係'
        'QA fixture cleanup 未完整拒絕並移除 endpoint、proxy、CA、loader、shell 與 Python overrides'
        'QA fixture delete transport 不存在'
        'QA fixture delete transport test 不存在'
        'QA fixture cleanup override test 未鎖零 CLI、固定錯誤與 UID 隔離'
        '能力側寫缺 cleanup 聚合契約：malicious `BASH_ENV` sentinel 整合測試必須證明 sentinel 零執行、helper 零呼叫與 UID 零洩漏'
        '能力側寫缺 cleanup 聚合契約：transport 每次 response 最多讀四 MiB 加一 byte，超過四 MiB 必須 fail-closed'
        '能力側寫缺 SQLite symlink containment 契約'
        '場次文件不得宣稱永久解除 qa-command 或 qa-probe 阻斷'
        '能力側寫缺 open-app global 隔離契約'
        '能力側寫缺 operation exact-binding anti-replay 契約'
        '能力側寫缺 recurring stale identity write guard 契約'
        '能力側寫缺 READY exact 六 keys 契約'
        '能力側寫缺 RESULT error operation exact allowlist 契約'
        '能力側寫缺 READY identityHash 契約'
        '能力側寫缺 process environment secret seam'
        '能力側寫缺 launch operation exclusivity'
        '能力側寫缺 requestId exact grammar 與 launch kind 綁定'
        '能力側寫缺 bootstrap stale delete current-null confirmation'
        '能力側寫缺 disposal token uid state 契約'
        '能力側寫缺 persisted proof exact-key 契約'
        '能力側寫缺 persisted proof unknown-key fail-closed 契約'
        '能力側寫缺 proof future-expiry upper bound'
        '能力側寫缺 Firestore 身分綁定：候選 hash 必須與 `identityHash` exact-one match'
        '能力側寫缺 Firestore 身分綁定：命中的 raw uid 只准留在 shell memory 的 `QA_SESSION_UID`'
        '能力側寫缺 Firestore 身分綁定：所有 firestore-read resource path 必須由 `QA_SESSION_UID` 衍生'
        '能力側寫缺 Firestore 身分綁定：bootstrap READY 只保存 `identityHash`，不得在 isolated bootstrap lifecycle 查 SQLite'
        '能力側寫缺 Firestore 身分綁定：cleanup 或首次手動變更前，可先以 Firebase CLI Auth export 將 exact-one uid hash 綁定 READY `identityHash`'
        '能力側寫缺 Firestore 身分綁定：需要執行 App 資料後，必須再以 canonical QA SQLite `users.id` exact-one 交叉驗證同一 `QA_SESSION_UID`'
        '能力側寫缺 Firestore 身分綁定：沒有 seed 或 inspect 時必須先執行 token-bound open-app'
        '能力側寫缺 Firestore 身分綁定：Firestore REST 原始回應必須以 bounded Python process memory parse 讀取'
        '能力側寫缺 Firestore 身分綁定：可見證據中的 uid 一律遮罩為固定字串 `[QA_SESSION_UID]`'
        'R03 缺 Firestore 身分綁定：候選 hash 必須與 READY `identityHash` exact-one match'
        'R03 缺 Firestore 身分綁定：R03 的 Firestore resource path 全由 `QA_SESSION_UID` 衍生'
        'R03 缺 Firestore 身分綁定：cleanup 或首次手動變更前，可先以 Firebase CLI Auth export 將 exact-one uid hash 綁定 READY `identityHash`'
        'R03 缺 Firestore 身分綁定：禁止輸出或回報 raw uid'
        'R03 缺 Firestore 身分綁定：disposal 不代表 Firestore 孤兒資料已清除'
        'R03 CSV 初次備份 probe 未綁定 QA_SESSION_UID 六個 resource path'
        'R03 CSV 增量備份 probe 未綁定 QA_SESSION_UID transactions 與 transfers path'
        'R03 CSV firestore-read 未由 QA_SESSION_UID 衍生 resource path'
        'R03 CSV firestore-read 原始回應未隔離於 bounded process memory'
        'R03 CSV firestore-read 可見證據未遮罩 uid'
        '場次 CSV firestore-read 未綁定 /${QA_SESSION_UID} exact path'
        '場次 CSV firestore-read 使用 collection-wide、newest 或模糊 uid'
        '場次 CSV firestore-read 未依場次隔離 raw response 或遮罩 uid'
        'R08 original language checkpoint 缺唯一 SQLite golden profile'
        'R08 SQLite original language profile 未鎖 live exact-one 與 candidate independence'
        '場次 CSV txnIndex probe 未由 session entitlement 衍生 exact path'
        '能力側寫缺 txnIndex typed exact-doc 契約'
        'R10 txnIndex probe 未鎖 typed provenance 與 owner hash'
        'R12 txnIndex absent probe 未鎖 typed not-found'
        '能力側寫缺 R10–R12 App Check isolation structured block'
        'R10 structured block 欄位不符'
        'R11 structured block 欄位不符'
        'R12 structured block 欄位不符'
        'R10–R12 場次索引 structured block 不完整'
        '場次 CSV 不得從 Metro 或可見證據擷取 raw UID'
        'R12 身分比對未鎖 shell-memory identityHash verdict'
        'R12 teardown firestore paths 未綁定 session identity'
        '缺少 R10–R12 first-operation structured block route'
        '缺少 extended App Check isolation block route'
        'R13 runbook requestId 未使用 operation prefix 加 32-lowerhex'
        'R13 CSV requestId 未使用 operation prefix 加 32-lowerhex'
        'R03 未鎖 cleanup→prepare→inspect→open-app 順序'
        'R03 缺 golden、post-delete absent 或 cooldown fail-closed 契約'
        'R13 未鎖 Auth bind→cleanup→prepare→SQLite bind→inspect 順序'
        'R13 缺獨立 SQLite golden 對帳或 global cleanup binding'
        'CS-02 metadata 與 R03 runbook seed 不一致'
        'CS-02 metadata 與 R03 runbook inspect 不一致'
        'RESULT 頂層 exact key set 契約不完整'
        'bootstrap RESULT error allowlist 契約不完整'
        'dispose RESULT error allowlist 契約不完整'
        'core tier 缺部分阻斷展開'
        'standard tier 缺部分阻斷展開'
        'extended tier 缺部分阻斷展開'
        'R14 first-launch 清理接手契約不符'
        'R15 local StoreKit 啟動契約不符'
        'QA Firebase config SHA-256 不符'
        'QA Firebase mixed API key config SHA-256 不符'
    )
    missing_expected=0
    for expected_failure in "${local_expected_failures[@]}"; do
        if ! grep -qxF "$expected_failure" "$FAIL_LOG"; then
            echo "selftest 缺預期失敗：$expected_failure"
            missing_expected=$((missing_expected + 1))
        fi
    done
    echo
    if [ "$missing_expected" -ne 0 ]; then
        echo "selftest FAIL：缺 $missing_expected 個安全契約失敗訊號。"
        exit 1
    fi
    if [ "$fail_count" -ge 7 ]; then
        echo "selftest PASS：檢核器抓到 $fail_count 個已知問題"
        exit 0
    fi
    echo "selftest FAIL：只抓到 $fail_count 個，應至少 7 個。檢核器本身壞了。"
    exit 1
fi

# ── 正式執行 ──
[ -d "$PLAN_DIR" ] && [ -d "$SCRIPT_DIR" ] || {
    echo "✗ 請在 quality git 根目錄執行（需有 $PLAN_DIR/ 與 $SCRIPT_DIR/）"; exit 2; }

if [ -z "$IMPL" ]; then
    # 對側 impl 的推導順序：同 topic 的 sibling worktree 優先，其次主 git。
    # 順序不能反——在 worktree 內開發時，新測試檔只存在於 impl worktree、
    # 主 git 還看不到，先比主 git 會把新加的測試全誤報成零命中。
    IMPL=$(resolve_impl_path "$(pwd)")
fi
[ -n "$IMPL" ] && IMPL=$(normalize_impl_path "$IMPL")
if [ -z "$BACKEND" ] && [ -n "$IMPL" ]; then
    # 同層容器下的後端 module。R00 的 jest-backend 核對列指的是這裡。
    # worktree 命名慣例是 impl-no3-cloud-functions，主 git 則是 no3_cloud_functions/functions。
    BACKEND=$(derive_backend_path "$IMPL")
    # worktree 側可能沒開後端那層，退回主 git 找
    [ -d "$BACKEND/src" ] || BACKEND=$(printf '%s' "$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print substr($0,10); exit}')" | sed 's#no6_product_quality/no2_accounting_app#no5_product_development/no3_cloud_functions/functions#')
fi

note "計劃對帳 — $(pwd)"
[ -n "$IMPL" ] && note "對側 app impl — $IMPL"
[ -n "$BACKEND" ] && [ -d "$BACKEND/src" ] && note "對側後端 impl — $BACKEND" || BACKEND=""
note ""
run_checks "$PLAN_DIR" "$SCRIPT_DIR" "$IMPL" "$PROFILE"
if [ -n "$RUNTIME_CONTROL" ]; then
    if python3 -I no2_qa_tools/check_runtime_entrypoints.py \
        --control "$RUNTIME_CONTROL" --impl "$IMPL"; then
        pass 'Control 與原生 QA 執行入口行為驗證'
    else
        fail 'Control 或原生 QA 執行入口行為驗證失敗'
    fi
else
    note '  － 未執行跨層 runtime 行為驗證，game-test 必須提供 --runtime-control'
fi
note ""
if [ "$fail_count" -eq 0 ]; then
    note "✓ 全部對帳通過"
    exit 0
fi
note "✗ $fail_count 項失配"
exit 1
