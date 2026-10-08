# R13 補產生驗證

- **涵蓋測項:** RC-06
- **前置場次:** 無
- **起點狀態:** 可丟棄的 QA 身分
- **終點狀態:** 不傳遞
- **前置環境:**
    - Mac 加 session 鎖定裝置
    - qa-markers 由 Metro 或實機 Debug console 擷取
    - app impl QA build
    - harness mode 為 `qa`
    - qa-command 與 qa-probe 已取得同 session promotion
    - qa-command 與 qa-probe 的持久狀態維持受阻
    - 每次 operation 帶同 session 的 secret token
    - canonical QA SQLite probe 已通過 `qaBundleId` gate
    - Firebase CLI 可執行 exact-one Auth export
    - gcloud Firestore OAuth 可執行 post-delete Firestore read
    - gcloud Firestore OAuth 可供 QA cleanup REST transport 取 token
    - `no1_fixture_golden.json` 可讀且通過 schema 檢查
- **fixture 引用:** `r09_stale_schedule`
- **預估時長:** 十分鐘
- **步驟表:** `no15_r13_backfill_verification.csv`

- 三個單元測試檢查點由 R00 涵蓋
- 本場為鏈外場次
- 本場會清空 QA 身分資料
- 使用者只需檢視補產生結果
- prepare 前必須先完成 global session `QA_SESSION_UID` exact-one binding
- session cleanup 必須沿用同一個 shell-memory UID

---

## 身分綁定與 cleanup 前置

- Control 先以 Firebase CLI Auth export 完成 READY identityHash exact-one binding
- 綁定身分必須是本 session 新建立的匿名帳號
- prepare 前不得 open-app、resume sync 或查詢舊 SQLite
- 命中的 raw uid 只保存於 global session shell memory 的 `QA_SESSION_UID`
- Control 以同一 UID 執行 `cleanup_qa_fixtures.sh` 與 users root、六個子集合、root collection ids 的 post-delete absent probes
- gcloud Firestore OAuth 缺少、delete 失敗或任一 absent probe 失敗時不得執行 prepare
- cleanup 失敗時仍繼續 Firebase Auth disposal，最終 cleanup 結果維持 fail-closed

---

## Prepare launch

- requestId 由執行器當次產生
- requestId 必須以 `prepare-` 開頭
- requestId 後綴必須為三十二字元小寫十六進位
- 以 process environment 的 `SUSUGIGI_QA_SESSION_TOKEN` 傳入同 session token
- 傳入 `--qa-prepare r09_stale_schedule`
- READY 等待上限為三十秒
- RESULT 等待上限為一百二十秒
- READY 與 RESULT 必須對上 requestId
- RESULT 的 top-level value 必須為 `r09_stale_schedule`
- prepare 的 `result.ok` 必須為 true
- prepare 的 `result.value.sceneId` 必須為 `r09_stale_schedule`
- prepare fingerprint 必須逐字符合 `no1_fixture_golden.json`
- prepare 內部 fixture 驗證通過不取代 runner golden 對帳
- prepare 期間 sync 以 `qa-fixture-reset` 保持 suspend
- exact UID fixture 子樹必須在 prepare 前通過 post-delete absent probes
- fixture seed 必須在第一筆 row 前把本 session 使用者的 `Settings.lastSyncedAt` 重設為 null
- global session binding 或 remote cleanup 未成立時不得開始 prepare
- prepare RESULT 通過後，才以 canonical QA SQLite 完成 identityHash exact-one 交叉驗證
- SQLite 必須對上 Auth export 綁定的同一 `QA_SESSION_UID`
- SQLite 身分不符時停止，不得改綁其他身分

---

## Inspect 冷啟 launch

- 首次 launch 完成後完全關閉 app
- requestId 由執行器當次產生
- requestId 必須以 `inspect-` 開頭
- requestId 後綴必須為三十二字元小寫十六進位
- requestId 不得與本 session 任何既有 requestId 重複
- 不得再次傳入 prepare
- 以 process environment 的 `SUSUGIGI_QA_SESSION_TOKEN` 傳入同 session token
- 傳入 `--qa-inspect accounting.schedule-backfill`
- bootstrap 負責補產生
- inspect 只讀取補產生結果
- READY 與 RESULT 必須對上 requestId
- RESULT 的 top-level value 必須為 `accounting.schedule-backfill`
- inspect 的 `result.value.schema` 必須為 `qa.evidence/v1`
- inspect 的 `result.value.checkId` 必須為 `accounting.schedule-backfill`
- runner 必須逐項比對 `no1_fixture_golden.json` 的 required fact keys 與關係
- 候選 RESULT 的 `result.value.verdict=pass` 不得作為唯一通過證據
- candidate signature 只證明 RESULT 內部一致，不得單獨決定場次通過
- R13 final 通過必須另由 `r13_schedule_backfill` 的獨立 sqlite-local profile 成立
- inspect 完成後 sync 仍以 `qa-fixture-reset` 保持 suspend

---

## 獨立 SQLite 聚合

- inspect RESULT 完成後，以 sqlite-local 查 canonical QA bundle 的 snapshot
- probe 只回傳聚合數字與布林關係，不輸出 schedule id、transaction id 或 raw uid
- schedule live count 固定為一
- schedule 頻率固定為 DAILY、interval 固定為一、endOn 為 null、isTransfer 為 false
- schedule 起始日固定為上月 5 日
- schedule 備註固定為早餐
- schedule 類別固定為餐飲
- schedule 帳戶固定為錢包
- schedule 金額固定為 150
- linked transaction tombstone count 固定為零
- distinct instanceDate count 必須等於 live instance count
- generated count 必須等於 live instance count 減一筆 seed
- due sequence 必須自起始日逐日連續並包含目前到期日
- 每筆 live instance 必須符合 Quality fixture 字面值
- schedule row 與 instance 同步漂移仍須失敗
- RESULT facts 與 sqlite-local 聚合都要各自符合 golden，再彼此對帳
- 任一聚合或關係失配即停測

---

## 成功判準

- 排程頻率為 DAILY
- due sequence 連續至當前時間
- instanceDate 不重複
- 實例沒有 tombstone
- 每筆實例符合 template
- generated count 與新增筆數相同
- `QA SCHED` 的產生筆數相同
- sqlite-local generated count 與 RESULT fact、`QA SCHED` 產生筆數三者相同
- 任一對帳失配即停測
