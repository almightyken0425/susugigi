#!/bin/bash
# query_local_db.sh — 直查 simulator 上 app 本地 SQLite 的唯讀查詢器。
#
# 只讀不寫。它查的是 WatermelonDB 落在 simulator 容器裡的 watermelon.db，
# 回報落庫事實；不改資料、不改計劃檔，也不推導任何內容。
#
# 為什麼需要：LD-02 與 LD-03 的落庫斷言講的是「值以什麼形狀進到庫裡」——
# 金額是不是整數、時間戳是不是毫秒、軟刪的列是不是還在。這類斷言原本只能靠
# manual-ui 加 jest-app 夾擊：UI 看得到清單對不對，jest 驗得到函式行為對不對，
# 但兩者都不是「庫裡真的長這樣」。中間那段落差在真機上一直沒人看過。
#
# 為什麼查的是快照而不是原檔：WatermelonDB 開 WAL。直接以 immutable 模式讀原檔
# 會跳過 -wal，讀到 checkpoint 之前的舊值——資料明明寫進去了卻查不到，是最難察覺的
# 失效樣態。改成把 db 與 -wal、-shm 三個檔一起複製到暫存目錄再查，sqlite 會自行
# replay WAL，既拿得到最新值，也一個 byte 都不會寫回 app 的容器。
#
# 用法：
#   bash no2_qa_tools/query_local_db.sh --bundle-id com.almightyken0425.susugigiapp.qa path
#   bash no2_qa_tools/query_local_db.sh --bundle-id com.almightyken0425.susugigiapp.qa tables
#   bash no2_qa_tools/query_local_db.sh --bundle-id com.almightyken0425.susugigiapp.qa assert
#   bash no2_qa_tools/query_local_db.sh --bundle-id com.almightyken0425.susugigiapp.qa sql '<query>'
#   printf '%s\n' "$QA_SESSION_UID" | bash no2_qa_tools/query_local_db.sh --bundle-id com.almightyken0425.susugigiapp.qa --session-uid-stdin profile r08_original_language
#   printf '%s\n' "$QA_SESSION_UID" | bash no2_qa_tools/query_local_db.sh --bundle-id com.almightyken0425.susugigiapp.qa --session-uid-stdin profile r13_schedule_backfill
#   bash no2_qa_tools/query_local_db.sh --selftest        # 驗這支腳本自己咬不咬得到
#
# 選項：
#   --bundle-id <id>   必填，且只接受 canonical QA bundle id
#   --device <udid>    覆寫裝置，預設 booted
#
# 退出碼：0 全過；1 斷言失敗或查詢失敗；2 用法或環境錯誤。

set -u

QA_BUNDLE_ID="com.almightyken0425.susugigiapp.qa"
PRODUCTION_BUNDLE_ID="com.almightyken0425.susugigiapp"
BUNDLE_ID=""
DEVICE="booted"
SELFTEST=0
CMD=""
SQL_ARG=""
PROFILE_ARG=""
READ_SESSION_UID=0
SESSION_UID=""

while [ $# -gt 0 ]; do
    case "$1" in
        --bundle-id)
            [ $# -ge 2 ] && [ -n "$2" ] || { echo "✗ --bundle-id 缺值"; exit 2; }
            BUNDLE_ID="$2"
            shift 2
            ;;
        --device)    DEVICE="${2:-}"; shift 2 ;;
        --session-uid-stdin)
            [ "$READ_SESSION_UID" -eq 0 ] || { echo "✗ --session-uid-stdin 重複"; exit 2; }
            READ_SESSION_UID=1
            shift
            ;;
        --selftest)  SELFTEST=1; shift ;;
        path|tables|assert) CMD="$1"; shift ;;
        sql)         CMD="sql"; SQL_ARG="${2:-}"; shift 2 ;;
        profile)
            [ -z "$CMD" ] || { echo "✗ 子指令重複"; exit 2; }
            CMD="profile"
            PROFILE_ARG="${2:-}"
            shift 2
            ;;
        *) echo "未知參數：$1"; exit 2 ;;
    esac
done

fail_count=0
note() { printf '%s\n' "$*"; }
pass() { printf '  ✓ %s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*"; fail_count=$((fail_count + 1)); }

profile_reject() {
    printf '%s\n' 'QA_LOCAL_DB_PROFILE_REJECTED' >&2
    exit 2
}

profile_fail() {
    printf '%s\n' 'QA_LOCAL_DB_PROFILE_FAILED' >&2
    exit 1
}

if ! command -v sqlite3 >/dev/null 2>&1; then
    [ "$CMD" = "profile" ] && profile_fail
    echo "✗ 找不到 sqlite3"
    exit 2
fi

canonical_directory() {
    (cd -P "$1" 2>/dev/null && pwd -P)
}

validate_qa_db_path() {
    local data_root="$1"
    local db_path="$2"
    local candidate

    [ -d "$data_root" ] || { echo "✗ QA app 資料容器不存在" >&2; return 2; }
    for candidate in "$db_path" "$db_path-wal" "$db_path-shm"; do
        [ ! -L "$candidate" ] || {
            echo "✗ QA database 與 WAL companion 不得為 symlink" >&2
            return 2
        }
    done
    [ -f "$db_path" ] || {
        echo "✗ 容器裡找不到 watermelon.db" >&2
        echo "  app 尚未跑過 bootstrap 時資料庫還不存在" >&2
        return 2
    }

    local canonical_root canonical_parent canonical_db expected_db
    canonical_root=$(canonical_directory "$data_root") || {
        echo "✗ QA app 資料容器無法 canonicalize" >&2
        return 2
    }
    canonical_parent=$(canonical_directory "$(dirname "$db_path")") || {
        echo "✗ QA database 目錄無法 canonicalize" >&2
        return 2
    }
    canonical_db="$canonical_parent/$(basename "$db_path")"
    expected_db="$canonical_root/Documents/watermelon.db"
    [ "$canonical_db" = "$expected_db" ] || {
        echo "✗ QA database realpath 逃出 canonical QA container" >&2
        return 2
    }
    printf '%s' "$canonical_db"
}

# ── 定位：simulator 容器裡的 watermelon.db ──
# 路徑含隨機 UUID、每次重裝都變，一律現查、不入 config、不寫死。
locate_db() {
    command -v xcrun >/dev/null 2>&1 || { echo "✗ 找不到 xcrun，本手段只在 Mac 成立" >&2; return 2; }

    local booted_count
    booted_count=$(xcrun simctl list devices booted 2>/dev/null | grep -c "(Booted)")
    if [ "$DEVICE" = "booted" ] && [ "$booted_count" -gt 1 ]; then
        echo "✗ 有 $booted_count 台裝置開著，booted 指代不明，請帶 --device <udid>" >&2
        return 2
    fi

    local data
    data=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data 2>&1) || {
        echo "✗ 抓不到 app 資料容器：$data" >&2
        echo "  裝置沒開機、或這個 bundle id 的 app 沒裝在上面" >&2
        return 2
    }

    validate_qa_db_path "$data" "$data/Documents/watermelon.db"
}

# ── 快照：連 -wal、-shm 一起複製，查副本 ──
# 直接查原檔就算是唯讀也可能拿到 checkpoint 前的舊值，見檔頭說明。
SNAP_DIR=""
DB=""
snapshot() {
    local src="$1"
    SNAP_DIR=$(mktemp -d)
    DB="$SNAP_DIR/snap.db"
    cp -P "$src" "$DB" || return 1
    [ ! -L "$DB" ] && [ -f "$DB" ] || return 1
    if [ -f "$src-wal" ]; then
        cp -P "$src-wal" "$DB-wal" || return 1
        [ ! -L "$DB-wal" ] || return 1
    fi
    if [ -f "$src-shm" ]; then
        cp -P "$src-shm" "$DB-shm" || return 1
        [ ! -L "$DB-shm" ] || return 1
    fi
}
cleanup() {
    if [ -n "$SNAP_DIR" ]; then
        rm -rf "$SNAP_DIR"
    fi
    DB=""
    SNAP_DIR=""
}
trap cleanup EXIT

q() { sqlite3 "$1" "$2" 2>&1; }

# 表清單一律從 sqlite_master 現取。寫死表名的清單會在 migration 加表時安靜漏掉。
list_tables() {
    q "$1" "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;"
}
has_column() {
    q "$1" "SELECT COUNT(*) FROM pragma_table_info('$2') WHERE name='$3';"
}

# ── tables：每張表的總列數與存活列數 ──
# 兩個數要分開看。WatermelonDB 的 _status='deleted' 是待同步的刪除標記，
# 那些列在 app 眼裡已經不存在，但 raw dump 照樣撈得到——只看總數會誤判成撞號。
cmd_tables() {
    local db="$1"
    printf '%-20s %8s %8s %8s\n' "表" "總列數" "存活" "軟刪"
    printf '%-20s %8s %8s %8s\n' "---" "---" "---" "---"
    local t total live softdel
    while read -r t; do
        [ -z "$t" ] && continue
        total=$(q "$db" "SELECT COUNT(*) FROM \"$t\";")
        if [ "$(has_column "$db" "$t" "_status")" = "1" ]; then
            live=$(q "$db" "SELECT COUNT(*) FROM \"$t\" WHERE _status!='deleted';")
        else
            live="－"
        fi
        if [ "$(has_column "$db" "$t" "deleted_on")" = "1" ]; then
            softdel=$(q "$db" "SELECT COUNT(*) FROM \"$t\" WHERE deleted_on IS NOT NULL;")
        else
            softdel="－"
        fi
        printf '%-20s %8s %8s %8s\n' "$t" "$total" "$live" "$softdel"
    done <<EOF
$(list_tables "$db")
EOF
}

# ── assert：落庫不變式 ──
# 對應 LD-02 的金額與時間格式、LD-03 的軟刪留庫與 userId 限定。
# 每項都寫成「違例列數應為 0」，空表時自然為 0——空表代表沒驗到，不代表通過，
# 故另外把樣本數印出來，讓讀的人自己判斷這輪有沒有料。
cmd_assert() {
    local db="$1" n bad

    note "[1] LD-02 金額以固定倍率縮放整數落庫"
    # 判的是「值是不是整數」，不是「SQLite 型別是不是 INTEGER」。WatermelonDB 經 JS
    # number 落庫，欄位一律存成 REAL，dump 出來長 -38000000.0 這樣——帶 .0 是常態、
    # 不是縮放壞掉。真正要咬的是帶小數部分的值，那才代表倍率沒套上去。
    n=$(q "$db" "SELECT COUNT(*) FROM transactions WHERE amount IS NOT NULL;")
    bad=$(q "$db" "SELECT COUNT(*) FROM transactions WHERE amount IS NOT NULL AND CAST(amount AS INTEGER) != amount;")
    if [ "$bad" = "0" ]; then pass "$n 筆交易金額全為整數"
    else fail "${bad} 筆交易金額非整數（樣本 ${n}）"
         q "$db" "SELECT id, amount FROM transactions WHERE CAST(amount AS INTEGER) != amount LIMIT 5;" | sed 's/^/      /'
    fi

    note "[2] LD-02 時間欄位以 UTC Unix Timestamp 毫秒存放"
    # 秒級誤存的判準是位數：毫秒級在 2001 年之後一律 >= 1e12，秒級同期只有 1e9 量級。
    local tables_with_created
    tables_with_created=$(q "$db" "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';")
    local t any=0
    while read -r t; do
        [ -z "$t" ] && continue
        [ "$(has_column "$db" "$t" "created_at")" = "1" ] || continue
        n=$(q "$db" "SELECT COUNT(*) FROM \"$t\" WHERE created_at IS NOT NULL;")
        [ "$n" = "0" ] && continue
        any=1
        bad=$(q "$db" "SELECT COUNT(*) FROM \"$t\" WHERE created_at IS NOT NULL AND created_at > 0 AND created_at < 1000000000000;")
        if [ "$bad" = "0" ]; then pass "${t}：${n} 筆 created_at 全為毫秒級"
        else fail "${t}：${bad} 筆 created_at 疑為秒級（樣本 ${n}）"; fi
    done <<EOF
$tables_with_created
EOF
    [ "$any" = "0" ] && note "  － 略過，所有表的 created_at 都是空的"

    note "[3] LD-03 軟刪記錄 deletedOn 寫入時間戳，實體仍留庫"
    local total_soft=0 checked=0 before=$fail_count
    while read -r t; do
        [ -z "$t" ] && continue
        [ "$(has_column "$db" "$t" "deleted_on")" = "1" ] || continue
        checked=1
        n=$(q "$db" "SELECT COUNT(*) FROM \"$t\" WHERE deleted_on IS NOT NULL;")
        total_soft=$((total_soft + n))
        # 有 deleted_on 卻不是正整數時間戳，等於軟刪標記本身壞了
        bad=$(q "$db" "SELECT COUNT(*) FROM \"$t\" WHERE deleted_on IS NOT NULL AND (CAST(deleted_on AS INTEGER) != deleted_on OR deleted_on <= 0);")
        [ "$bad" = "0" ] || fail "${t}：${bad} 筆 deleted_on 不是正整數時間戳"
    done <<EOF
$(list_tables "$db")
EOF
    if [ "$checked" = "0" ]; then note "  － 略過，沒有帶 deleted_on 欄的表"
    elif [ "$fail_count" -ne "$before" ]; then :   # 已在迴圈內報過失配，不再補一句通過
    elif [ "$total_soft" = "0" ]; then note "  － 無樣本，這輪庫裡沒有任何軟刪列（不等於通過）"
    else pass "$total_soft 筆軟刪列仍留庫、時間戳格式正確"; fi

    note "[4] LD-02 清單查詢一律以 userId 限定範圍（資料面：user_id 不得為空）"
    checked=0
    while read -r t; do
        [ -z "$t" ] && continue
        [ "$(has_column "$db" "$t" "user_id")" = "1" ] || continue
        n=$(q "$db" "SELECT COUNT(*) FROM \"$t\" WHERE _status!='deleted';")
        [ "$n" = "0" ] && continue
        checked=1
        bad=$(q "$db" "SELECT COUNT(*) FROM \"$t\" WHERE _status!='deleted' AND (user_id IS NULL OR user_id='');")
        if [ "$bad" = "0" ]; then pass "${t}：${n} 筆存活列 user_id 全非空"
        else fail "${t}：${bad} 筆存活列 user_id 為空（樣本 ${n}）"; fi
    done <<EOF
$(list_tables "$db")
EOF
    [ "$checked" = "0" ] && note "  － 略過，帶 user_id 的表都沒有存活列"
}

cmd_r13_schedule_backfill_profile() {
    local db="$1"
    local raw
    raw=$(sqlite3 -batch -noheader "file:$db?mode=ro" 2>/dev/null <<SQL
WITH
live_schedules AS (
    SELECT *
    FROM schedules
    WHERE user_id = '$SESSION_UID'
      AND _status != 'deleted'
      AND deleted_on IS NULL
),
expected_accounts AS (
    SELECT id
    FROM accounts
    WHERE user_id = '$SESSION_UID'
      AND _status != 'deleted'
      AND deleted_on IS NULL
      AND name = '錢包'
),
expected_categories AS (
    SELECT id
    FROM categories
    WHERE user_id = '$SESSION_UID'
      AND _status != 'deleted'
      AND deleted_on IS NULL
      AND name = '餐飲'
      AND type = 'expense'
),
target_schedule AS (
    SELECT *
    FROM live_schedules
    ORDER BY id
    LIMIT 1
),
linked_instances AS (
    SELECT transactions.*
    FROM transactions
    JOIN target_schedule
      ON transactions.schedule_id = target_schedule.id
    WHERE transactions.user_id = '$SESSION_UID'
),
live_instances AS (
    SELECT *
    FROM linked_instances
    WHERE _status != 'deleted'
      AND deleted_on IS NULL
),
ordered_instances AS (
    SELECT
        schedule_instance_date,
        LAG(schedule_instance_date) OVER (
            ORDER BY schedule_instance_date
        ) AS previous_instance_date,
        ROW_NUMBER() OVER (
            ORDER BY schedule_instance_date
        ) AS sequence_number
    FROM live_instances
),
counts AS (
    SELECT
        (SELECT COUNT(*) FROM live_schedules) AS schedule_count,
        (SELECT COUNT(*) FROM live_instances) AS live_instance_count,
        (SELECT COUNT(DISTINCT schedule_instance_date) FROM live_instances) AS distinct_instance_date_count,
        (SELECT COUNT(*) FROM linked_instances WHERE _status = 'deleted' OR deleted_on IS NOT NULL) AS tombstone_count
),
relations AS (
    SELECT
        CASE WHEN
            counts.schedule_count = 1
            AND target_schedule.frequency = 'DAILY'
            AND target_schedule.interval = 1
            AND date(target_schedule.start_on / 1000.0, 'unixepoch', 'localtime') =
                date('now', 'localtime', 'start of month', '-1 month', '+4 days')
            AND target_schedule.end_on IS NULL
            AND target_schedule.is_transfer = 0
            AND target_schedule.template_amount = -1500000
            AND target_schedule.template_note = '早餐'
            AND (SELECT COUNT(*) FROM expected_accounts) = 1
            AND (SELECT COUNT(*) FROM expected_categories) = 1
            AND target_schedule.template_account_id = (SELECT id FROM expected_accounts)
            AND target_schedule.template_category_id = (SELECT id FROM expected_categories)
            AND target_schedule.template_amount_from IS NULL
            AND target_schedule.template_account_from_id IS NULL
            AND target_schedule.template_amount_to IS NULL
            AND target_schedule.template_account_to_id IS NULL
        THEN 1 ELSE 0 END AS schedule_contract,
        CASE WHEN
            counts.schedule_count = 1
            AND counts.live_instance_count = counts.distinct_instance_date_count
            AND counts.live_instance_count = MAX(
                0,
                CAST(
                    julianday(date('now', 'localtime')) -
                    julianday(date(target_schedule.start_on / 1000.0, 'unixepoch', 'localtime'))
                    AS INTEGER
                ) + CASE WHEN
                    time('now', 'localtime') >= time(target_schedule.start_on / 1000.0, 'unixepoch', 'localtime')
                THEN 1 ELSE 0 END
            )
            AND NOT EXISTS (
                SELECT 1
                FROM ordered_instances
                WHERE schedule_instance_date IS NULL
                   OR schedule_instance_date > CAST(strftime('%s', 'now') AS INTEGER) * 1000
                   OR time(schedule_instance_date / 1000.0, 'unixepoch', 'localtime') !=
                      time(target_schedule.start_on / 1000.0, 'unixepoch', 'localtime')
                   OR CASE
                        WHEN sequence_number = 1
                        THEN schedule_instance_date != target_schedule.start_on
                        ELSE CAST(
                            julianday(date(schedule_instance_date / 1000.0, 'unixepoch', 'localtime')) -
                            julianday(date(previous_instance_date / 1000.0, 'unixepoch', 'localtime'))
                            AS INTEGER
                        ) != 1
                      END
            )
        THEN 1 ELSE 0 END AS due_sequence_valid,
        CASE WHEN
            counts.schedule_count = 1
            AND (SELECT COUNT(*) FROM expected_accounts) = 1
            AND (SELECT COUNT(*) FROM expected_categories) = 1
            AND NOT EXISTS (
                SELECT 1
                FROM live_instances
                WHERE user_id != target_schedule.user_id
                   OR account_id != (SELECT id FROM expected_accounts)
                   OR category_id != (SELECT id FROM expected_categories)
                   OR amount != -1500000
                   OR note IS NOT '早餐'
                   OR schedule_instance_date IS NULL
                   OR date != schedule_instance_date
            )
        THEN 1 ELSE 0 END AS template_match
    FROM counts
    LEFT JOIN target_schedule ON 1 = 1
)
SELECT
    counts.schedule_count || '|' ||
    counts.live_instance_count || '|' ||
    MAX(counts.live_instance_count - 1, 0) || '|' ||
    counts.distinct_instance_date_count || '|' ||
    counts.tombstone_count || '|' ||
    relations.schedule_contract || '|' ||
    relations.due_sequence_valid || '|' ||
    relations.template_match
FROM counts
JOIN relations ON 1 = 1;
SQL
    ) || profile_fail

    local schedule_count live_instance_count generated_count
    local distinct_instance_date_count tombstone_count
    local schedule_contract due_sequence_valid template_match extra
    IFS='|' read -r \
        schedule_count \
        live_instance_count \
        generated_count \
        distinct_instance_date_count \
        tombstone_count \
        schedule_contract \
        due_sequence_valid \
        template_match \
        extra <<EOF
$raw
EOF
    for value in \
        "$schedule_count" \
        "$live_instance_count" \
        "$generated_count" \
        "$distinct_instance_date_count" \
        "$tombstone_count"; do
        [[ "$value" =~ ^[0-9]+$ ]] || profile_fail
    done
    [ -z "$extra" ] || profile_fail
    case "$schedule_contract$due_sequence_valid$template_match" in
        [01][01][01]) ;;
        *) profile_fail ;;
    esac

    [ "$schedule_contract" = "1" ] && schedule_contract=true || schedule_contract=false
    [ "$due_sequence_valid" = "1" ] && due_sequence_valid=true || due_sequence_valid=false
    [ "$template_match" = "1" ] && template_match=true || template_match=false
    SESSION_UID=''
    printf '%s\n' \
        "profile=r13_schedule_backfill scheduleCount=$schedule_count liveInstanceCount=$live_instance_count generatedCount=$generated_count distinctInstanceDateCount=$distinct_instance_date_count tombstoneCount=$tombstone_count scheduleContract=$schedule_contract dueSequenceValid=$due_sequence_valid templateMatch=$template_match"
}

cmd_r08_original_language_profile() {
    local db="$1"
    local raw count language extra
    raw=$(sqlite3 -batch -noheader "file:$db?mode=ro" 2>/dev/null <<SQL
SELECT COUNT(*) || '|' || COALESCE(MIN(language), '')
FROM settings
WHERE user_id = '$SESSION_UID'
  AND _status != 'deleted';
SQL
    ) || profile_fail

    IFS='|' read -r count language extra <<EOF
$raw
EOF
    [ "$count" = "1" ] || profile_fail
    [ -z "$extra" ] || profile_fail
    [[ "$language" =~ ^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$ ]] || profile_fail

    SESSION_UID=''
    printf '%s\n' "profile=r08_original_language language=$language"
}

# ── selftest：造一份違反每條不變式的 db，確認上面四項真的咬得到 ──
# 沒有這段，一支永遠印綠燈的查詢器跟沒有一樣。
if [ "$SELFTEST" -eq 1 ]; then
    TMP=$(mktemp -d)
    selftest_cleanup() {
        cleanup
        rm -rf "$TMP"
    }
    trap selftest_cleanup EXIT
    BAD="$TMP/bad.db"
    sqlite3 "$BAD" <<'SQL'
CREATE TABLE transactions ("id" primary key, "_status", "user_id", "amount", "created_at", "deleted_on");
CREATE TABLE accounts ("id" primary key, "_status", "user_id", "created_at", "deleted_on");
-- 金額帶小數：第一項應咬到
INSERT INTO transactions VALUES ('t1','created','u1',123.45,1786000000000,NULL);
-- created_at 是秒級：第二項應咬到
INSERT INTO transactions VALUES ('t2','created','u1',100,1786000000,NULL);
-- deleted_on 是 0：第三項應咬到（0 不是有效時間戳，@date setter 會把 falsy 吞成 null）
INSERT INTO accounts VALUES ('a1','created','u1',1786000000000,0);
-- user_id 空字串：第四項應咬到
INSERT INTO accounts VALUES ('a2','created','',1786000000000,NULL);
SQL

    note "=== selftest：預期四項全數咬到 ==="
    cmd_assert "$BAD"
    echo
    override_output=$(bash "$0" \
        --bundle-id "$QA_BUNDLE_ID" \
        --db "$BAD" \
        assert 2>&1)
    override_status=$?
    if [ "$override_status" -ne 2 ] ||
       [ "$override_output" != "未知參數：--db" ]; then
        echo "selftest FAIL：正式介面仍可接受 DB path override。"
        exit 1
    fi
    pass "正式介面拒絕 Production／任意 DB path override"

    QA_ROOT="$TMP/qa-container"
    PRODUCTION_ROOT="$TMP/production-container"
    mkdir -p "$QA_ROOT/Documents" "$PRODUCTION_ROOT/Documents"
    cp "$BAD" "$PRODUCTION_ROOT/Documents/watermelon.db"
    ln -s "$PRODUCTION_ROOT/Documents/watermelon.db" \
        "$QA_ROOT/Documents/watermelon.db"
    symlink_output=$(validate_qa_db_path \
        "$QA_ROOT" \
        "$QA_ROOT/Documents/watermelon.db" 2>&1)
    symlink_status=$?
    if [ "$symlink_status" -ne 2 ] ||
       [ "$symlink_output" != "✗ QA database 與 WAL companion 不得為 symlink" ] ||
       printf '%s' "$symlink_output" | grep -q '123.45'; then
        echo "selftest FAIL：QA container symlink 可逃逸到 Production DB。"
        exit 1
    fi
    pass "QA container 內的 Production DB symlink fail-closed 且不輸出內容"

    if ! snapshot "$BAD"; then
        echo "selftest FAIL：current-shell snapshot 建立失敗。"
        exit 1
    fi
    EXPLICIT_SNAPSHOT_DIR="$SNAP_DIR"
    if [ ! -d "$EXPLICIT_SNAPSHOT_DIR" ] ||
       [ "$DB" != "$EXPLICIT_SNAPSHOT_DIR/snap.db" ] ||
       [ ! -f "$DB" ]; then
        echo "selftest FAIL：snapshot 沒有在 parent shell 保存 cleanup ownership。"
        exit 1
    fi
    cleanup
    if [ -e "$EXPLICIT_SNAPSHOT_DIR" ] ||
       [ -n "$SNAP_DIR" ] ||
       [ -n "$DB" ]; then
        echo "selftest FAIL：explicit snapshot cleanup 留下暫存資料。"
        exit 1
    fi
    pass "current-shell snapshot 保存 ownership 並可完整 cleanup"

    TRAP_SNAPSHOT_PATH_FILE="$TMP/trap-snapshot-path"
    if ! (
        SNAP_DIR=""
        DB=""
        trap cleanup EXIT
        snapshot "$BAD"
        [ -d "$SNAP_DIR" ]
        [ -f "$DB" ]
        printf '%s' "$SNAP_DIR" > "$TRAP_SNAPSHOT_PATH_FILE"
    ); then
        echo "selftest FAIL：trap-compatible snapshot setup 失敗。"
        exit 1
    fi
    TRAP_SNAPSHOT_DIR=$(cat "$TRAP_SNAPSHOT_PATH_FILE")
    if [ -z "$TRAP_SNAPSHOT_DIR" ] || [ -e "$TRAP_SNAPSHOT_DIR" ]; then
        echo "selftest FAIL：EXIT trap 留下 snapshot 暫存資料。"
        exit 1
    fi
    pass "EXIT trap 完整刪除 snapshot DB、WAL 與 SHM"

    PROFILE_STUB_BIN="$TMP/profile-bin"
    PROFILE_STUB_LOG="$TMP/profile-xcrun-args.log"
    PROFILE_STDERR="$TMP/profile-stderr.log"
    PROFILE_GOOD_ROOT="$TMP/profile-good-container"
    PROFILE_BAD_ROOT="$TMP/profile-bad-container"
    PROFILE_COUPLED_ROOT="$TMP/profile-coupled-container"
    PROFILE_UID='qaProfileSessionUid0123456789'
    mkdir -p \
        "$PROFILE_STUB_BIN" \
        "$PROFILE_GOOD_ROOT/Documents" \
        "$PROFILE_BAD_ROOT/Documents" \
        "$PROFILE_COUPLED_ROOT/Documents"
    cat > "$PROFILE_STUB_BIN/xcrun" <<'XCRUN_STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$QA_QUERY_STUB_LOG"
if [ "$1 $2 $3 $4" = 'simctl list devices booted' ]; then
    printf '%s\n' 'iPhone QA (00000000-0000-0000-0000-000000000000) (Booted)'
    exit 0
fi
if [ "$1 $2" = 'simctl get_app_container' ]; then
    printf '%s\n' "$QA_QUERY_STUB_CONTAINER"
    exit 0
fi
exit 1
XCRUN_STUB
    chmod +x "$PROFILE_STUB_BIN/xcrun"
    PROFILE_START_MS="$(date -v1d -v-1m -v5d -v12H -v0M -v0S +%s)000"
    sqlite3 "$PROFILE_GOOD_ROOT/Documents/watermelon.db" <<SQL
CREATE TABLE schedules (
    id TEXT PRIMARY KEY,
    _status TEXT,
    user_id TEXT,
    frequency TEXT,
    interval INTEGER,
    start_on INTEGER,
    end_on INTEGER,
    is_transfer INTEGER,
    template_amount INTEGER,
    template_category_id TEXT,
    template_account_id TEXT,
    template_amount_from INTEGER,
    template_account_from_id TEXT,
    template_amount_to INTEGER,
    template_account_to_id TEXT,
    template_note TEXT,
    deleted_on INTEGER
);
CREATE TABLE transactions (
    id TEXT PRIMARY KEY,
    _status TEXT,
    user_id TEXT,
    account_id TEXT,
    category_id TEXT,
    amount INTEGER,
    date INTEGER,
    note TEXT,
    schedule_id TEXT,
    schedule_instance_date INTEGER,
    deleted_on INTEGER
);
CREATE TABLE settings (
    id TEXT PRIMARY KEY,
    _status TEXT,
    user_id TEXT,
    language TEXT
);
CREATE TABLE accounts (
    id TEXT PRIMARY KEY,
    _status TEXT,
    user_id TEXT,
    name TEXT,
    deleted_on INTEGER
);
CREATE TABLE categories (
    id TEXT PRIMARY KEY,
    _status TEXT,
    user_id TEXT,
    name TEXT,
    type TEXT,
    deleted_on INTEGER
);
INSERT INTO settings VALUES ('settings-good','synced','$PROFILE_UID','zh-Hant');
INSERT INTO settings VALUES ('settings-tombstone','deleted','$PROFILE_UID','en');
INSERT INTO accounts VALUES ('account-wallet','synced','$PROFILE_UID','錢包',NULL);
INSERT INTO categories VALUES ('category-food','synced','$PROFILE_UID','餐飲','expense',NULL);
INSERT INTO schedules VALUES ('schedule-good','synced','$PROFILE_UID','DAILY',1,$PROFILE_START_MS,NULL,0,-1500000,'category-food','account-wallet',NULL,NULL,NULL,NULL,'早餐',NULL);
WITH RECURSIVE due(instance_date, sequence_number) AS (
    SELECT $PROFILE_START_MS, 0
    UNION ALL
    SELECT instance_date + 86400000, sequence_number + 1
    FROM due
    WHERE date((instance_date + 86400000) / 1000.0, 'unixepoch', 'localtime') < date('now', 'localtime')
       OR (
            date((instance_date + 86400000) / 1000.0, 'unixepoch', 'localtime') = date('now', 'localtime')
            AND time('now', 'localtime') >= time($PROFILE_START_MS / 1000.0, 'unixepoch', 'localtime')
       )
)
INSERT INTO transactions
SELECT
    printf('instance-%04d', sequence_number),
    'synced',
    '$PROFILE_UID',
    'account-wallet',
    'category-food',
    -1500000,
    instance_date,
    '早餐',
    'schedule-good',
    instance_date,
    NULL
FROM due;
SQL
    PROFILE_LIVE_COUNT=$(sqlite3 "$PROFILE_GOOD_ROOT/Documents/watermelon.db" \
        "SELECT COUNT(*) FROM transactions WHERE _status != 'deleted';")
    PROFILE_GENERATED_COUNT=$((PROFILE_LIVE_COUNT - 1))
    PROFILE_LAST_MS=$(sqlite3 "$PROFILE_GOOD_ROOT/Documents/watermelon.db" \
        "SELECT MAX(schedule_instance_date) FROM transactions WHERE _status != 'deleted';")
    cp "$PROFILE_GOOD_ROOT/Documents/watermelon.db" \
        "$PROFILE_BAD_ROOT/Documents/watermelon.db"
    cp "$PROFILE_GOOD_ROOT/Documents/watermelon.db" \
        "$PROFILE_COUPLED_ROOT/Documents/watermelon.db"
    sqlite3 "$PROFILE_BAD_ROOT/Documents/watermelon.db" <<SQL
UPDATE transactions SET amount=-999000 WHERE id='instance-0001';
UPDATE transactions SET schedule_instance_date=$PROFILE_START_MS WHERE id='instance-0001';
INSERT INTO transactions VALUES ('instance-deleted','deleted','$PROFILE_UID','account-wallet','category-food',-1500000,$PROFILE_LAST_MS,'早餐','schedule-good',$PROFILE_LAST_MS,1);
INSERT INTO settings VALUES ('settings-duplicate','synced','$PROFILE_UID','en');
SQL
    sqlite3 "$PROFILE_COUPLED_ROOT/Documents/watermelon.db" <<SQL
UPDATE accounts SET name='卡片' WHERE id='account-wallet';
UPDATE categories SET name='娛樂' WHERE id='category-food';
UPDATE schedules SET template_amount=-9900000, template_note='午餐' WHERE id='schedule-good';
UPDATE transactions SET amount=-9900000, note='午餐' WHERE schedule_id='schedule-good';
SQL

    run_profile_selftest() {
        local container="$1"
        local profile_name="${2:-r13_schedule_backfill}"
        : > "$PROFILE_STUB_LOG"
        : > "$PROFILE_STDERR"
        printf '%s\n' "$PROFILE_UID" | \
            env PATH="$PROFILE_STUB_BIN:$PATH" \
                QA_QUERY_STUB_CONTAINER="$container" \
                QA_QUERY_STUB_LOG="$PROFILE_STUB_LOG" \
                QA_CANDIDATE_RESULT='verdict=pass generatedCount=999999' \
                QA_RESULT_FACTS='schedule-backfill.generated-count=999999' \
                bash "$0" \
                    --bundle-id "$QA_BUNDLE_ID" \
                    --session-uid-stdin \
                    profile "$profile_name" \
                    2> "$PROFILE_STDERR"
    }

    : > "$PROFILE_STUB_LOG"
    : > "$PROFILE_STDERR"
    PROFILE_TRAILING_OUTPUT=$(
        printf '%s\ntrailing-bytes' "$PROFILE_UID" | \
            env PATH="$PROFILE_STUB_BIN:$PATH" \
                QA_QUERY_STUB_CONTAINER="$PROFILE_GOOD_ROOT" \
                QA_QUERY_STUB_LOG="$PROFILE_STUB_LOG" \
                bash "$0" \
                    --bundle-id "$QA_BUNDLE_ID" \
                    --session-uid-stdin \
                    profile r13_schedule_backfill \
                    2> "$PROFILE_STDERR"
    )
    PROFILE_TRAILING_STATUS=$?
    if [ "$PROFILE_TRAILING_STATUS" -ne 2 ] || \
       [ -n "$PROFILE_TRAILING_OUTPUT" ] || \
       [ "$(cat "$PROFILE_STDERR")" != 'QA_LOCAL_DB_PROFILE_REJECTED' ]; then
        echo "selftest FAIL：profile 未拒絕無結尾換行的 trailing stdin bytes。"
        exit 1
    fi
    if grep -Fq "$PROFILE_UID" "$PROFILE_STUB_LOG" "$PROFILE_STDERR"; then
        echo "selftest FAIL：profile trailing stdin 拒絕路徑洩漏 session UID。"
        exit 1
    fi
    pass "profile 拒絕無結尾換行的 trailing stdin bytes"

    PROFILE_GOOD_OUTPUT=$(run_profile_selftest "$PROFILE_GOOD_ROOT")
    PROFILE_GOOD_STATUS=$?
    PROFILE_EXPECTED_GOOD="profile=r13_schedule_backfill scheduleCount=1 liveInstanceCount=$PROFILE_LIVE_COUNT generatedCount=$PROFILE_GENERATED_COUNT distinctInstanceDateCount=$PROFILE_LIVE_COUNT tombstoneCount=0 scheduleContract=true dueSequenceValid=true templateMatch=true"
    if [ "$PROFILE_GOOD_STATUS" -ne 0 ] || \
       [ "$PROFILE_GOOD_OUTPUT" != "$PROFILE_EXPECTED_GOOD" ]; then
        echo "selftest FAIL：R13 profile good DB aggregate 不符固定 schema。"
        exit 1
    fi
    if grep -Fq "$PROFILE_UID" "$PROFILE_STUB_LOG" "$PROFILE_STDERR"; then
        echo "selftest FAIL：R13 profile 將 session UID 寫入 argv 或錯誤輸出。"
        exit 1
    fi
    pass "R13 profile 只由 canonical snapshot 產生固定單行 aggregate"

    PROFILE_BAD_OUTPUT=$(run_profile_selftest "$PROFILE_BAD_ROOT")
    PROFILE_BAD_STATUS=$?
    PROFILE_EXPECTED_BAD="profile=r13_schedule_backfill scheduleCount=1 liveInstanceCount=$PROFILE_LIVE_COUNT generatedCount=$PROFILE_GENERATED_COUNT distinctInstanceDateCount=$((PROFILE_LIVE_COUNT - 1)) tombstoneCount=1 scheduleContract=true dueSequenceValid=false templateMatch=false"
    if [ "$PROFILE_BAD_STATUS" -ne 0 ] || \
       [ "$PROFILE_BAD_OUTPUT" != "$PROFILE_EXPECTED_BAD" ]; then
        echo "selftest FAIL：R13 profile bad DB 未呈現獨立失配。"
        exit 1
    fi
    pass "candidate verdict 與 facts 無法改寫 R13 SQLite aggregate"

    PROFILE_COUPLED_OUTPUT=$(run_profile_selftest "$PROFILE_COUPLED_ROOT")
    PROFILE_COUPLED_STATUS=$?
    PROFILE_EXPECTED_COUPLED="profile=r13_schedule_backfill scheduleCount=1 liveInstanceCount=$PROFILE_LIVE_COUNT generatedCount=$PROFILE_GENERATED_COUNT distinctInstanceDateCount=$PROFILE_LIVE_COUNT tombstoneCount=0 scheduleContract=false dueSequenceValid=true templateMatch=false"
    if [ "$PROFILE_COUPLED_STATUS" -ne 0 ] || \
       [ "$PROFILE_COUPLED_OUTPUT" != "$PROFILE_EXPECTED_COUPLED" ]; then
        echo "selftest FAIL：R13 profile 未抓到 seeder 與 candidate 同步漂移。"
        exit 1
    fi
    pass "R13 profile 以 Quality literals 抓到 seeder 與 candidate 同步漂移"

    R08_GOOD_OUTPUT=$(run_profile_selftest "$PROFILE_GOOD_ROOT" r08_original_language)
    R08_GOOD_STATUS=$?
    R08_EXPECTED_GOOD='profile=r08_original_language language=zh-Hant'
    if [ "$R08_GOOD_STATUS" -ne 0 ] || \
       [ "$R08_GOOD_OUTPUT" != "$R08_EXPECTED_GOOD" ]; then
        echo "selftest FAIL：R08 profile good DB 不符固定 schema。"
        exit 1
    fi
    if grep -Fq "$PROFILE_UID" "$PROFILE_STUB_LOG" "$PROFILE_STDERR"; then
        echo "selftest FAIL：R08 profile 將 session UID 寫入 argv 或錯誤輸出。"
        exit 1
    fi
    pass "R08 original language 只由 canonical snapshot exact-one Settings row 產生"

    R08_BAD_OUTPUT=$(run_profile_selftest "$PROFILE_BAD_ROOT" r08_original_language)
    R08_BAD_STATUS=$?
    if [ "$R08_BAD_STATUS" -eq 0 ] || \
       [ -n "$R08_BAD_OUTPUT" ] || \
       [ "$(cat "$PROFILE_STDERR")" != 'QA_LOCAL_DB_PROFILE_FAILED' ]; then
        echo "selftest FAIL：R08 profile 未對 duplicate Settings row fail-closed。"
        exit 1
    fi
    pass "candidate facts 無法遮蔽 R08 duplicate Settings row"

    if [ "$fail_count" -ge 4 ]; then
        echo "selftest PASS：查詢器抓到 $fail_count 個已知問題，且 DB override、symlink escape 與 snapshot cleanup 已受阻"
        exit 0
    fi
    echo "selftest FAIL：只抓到 $fail_count 個，應至少 4 個。查詢器本身壞了。"
    exit 1
fi

# ── 正式執行 ──
[ -n "$CMD" ] || { echo "✗ 需指定子指令：path / tables / assert / sql，或 --selftest"; exit 2; }
if [ "$CMD" = "profile" ]; then
    case "$PROFILE_ARG" in
        r08_original_language|r13_schedule_backfill) ;;
        *) profile_reject ;;
    esac
    [ "$READ_SESSION_UID" -eq 1 ] || profile_reject
    [ -n "$BUNDLE_ID" ] || profile_reject
    [ "$BUNDLE_ID" = "$QA_BUNDLE_ID" ] || profile_reject
    IFS= read -r SESSION_UID || profile_reject
    extra_input=""
    if IFS= read -r extra_input; then
        profile_reject
    fi
    [ -z "$extra_input" ] || profile_reject
    [[ "$SESSION_UID" =~ ^[A-Za-z0-9._-]{1,128}$ ]] || profile_reject
else
    [ "$READ_SESSION_UID" -eq 0 ] || { echo "✗ --session-uid-stdin 只供 profile"; exit 2; }
    [ -n "$BUNDLE_ID" ] || { echo "✗ 必須明確傳入 canonical QA --bundle-id"; exit 2; }
    [ "$BUNDLE_ID" != "$PRODUCTION_BUNDLE_ID" ] || { echo "✗ Production bundle id 禁止用於 QA DB probe"; exit 2; }
    [ "$BUNDLE_ID" = "$QA_BUNDLE_ID" ] || { echo "✗ --bundle-id 不符合 canonical QA bundle id"; exit 2; }
fi

if [ "$CMD" = "profile" ]; then
    SRC=$(locate_db 2>/dev/null) || profile_fail
else
    SRC=$(locate_db) || exit 2
fi

if [ "$CMD" = "path" ]; then printf '%s\n' "$SRC"; exit 0; fi

if ! snapshot "$SRC"; then
    [ "$CMD" = "profile" ] && profile_fail
    echo "✗ 快照失敗"
    exit 2
fi

case "$CMD" in
    tables)
        note "本地資料庫 — $SRC"
        note ""
        cmd_tables "$DB"
        ;;
    sql)
        [ -n "$SQL_ARG" ] || { echo "✗ sql 需帶查詢字串"; exit 2; }
        # 守門走白名單首動詞，不走關鍵字黑名單。黑名單擋的是子字串，
        # `WHERE _status!='deleted'` 裡的 delete 會讓一句正當的 SELECT 被誤殺。
        # 首動詞用 awk 取，不用 tr——tr 逐 byte 處理，查詢裡的全形字會被切爛。
        verb=$(printf '%s' "$SQL_ARG" | awk '{print tolower($1); exit}')
        case "$verb" in
            select|with|pragma|explain) ;;
            *) echo "✗ 只接受 select / with / pragma / explain 起頭的讀取查詢，收到：$verb"; exit 2 ;;
        esac
        # 第二道是機制層：唯讀連線。字串比對擋不掉 `SELECT 1; DELETE FROM x`
        # 這種夾帶，mode=ro 讓 sqlite 自己拒絕任何寫入。
        sqlite3 -header -column "file:$DB?mode=ro" "$SQL_ARG"
        ;;
    assert)
        note "落庫不變式對帳 — $SRC"
        note ""
        cmd_assert "$DB"
        note ""
        if [ "$fail_count" -eq 0 ]; then note "✓ 全部斷言通過"; exit 0; fi
        note "✗ $fail_count 項失配"
        exit 1
        ;;
    profile)
        case "$PROFILE_ARG" in
            r08_original_language) cmd_r08_original_language_profile "$DB" ;;
            r13_schedule_backfill) cmd_r13_schedule_backfill_profile "$DB" ;;
        esac
        ;;
esac
