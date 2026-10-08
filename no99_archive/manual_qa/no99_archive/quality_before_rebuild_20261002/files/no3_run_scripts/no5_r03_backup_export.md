# R03 備份啟動與匯出底線

- **涵蓋測項:** CS-02、AS-06、RC-03、CS-03
- **前置場次:** R02
- **起點狀態:** 同 R02 終點
- **終點狀態:** 連網、雲端與本機一致、轉帳兩筆在案且跨幣轉入已改 4500、匯出重匯的重複列已清、增量備份臨時交易已刪除、無排程
- **前置環境:**
    - Mac 加 session 鎖定裝置
    - qa-markers 由 Metro 或實機 Debug console 擷取
    - Firebase CLI Auth control 與 gcloud Firestore OAuth 各自就緒，兩者 readiness 不互推
    - app impl 主 checkout node_modules 完整
    - READY identityHash 已通過六十四字元小寫十六進位檢查
    - bootstrap READY 的 identityHash 已保存，本場不在 isolated bootstrap lifecycle 查 SQLite
    - 本場先綁定 `QA_SESSION_UID` 並清除 exact UID fixture 子樹
    - post-delete absent probes 成立後執行 `prepare r02_end`
    - 本場接著執行 `inspect accounting.fixture-summary`
    - prepare 與 inspect facts 逐項對帳 `no1_fixture_golden.json`
    - 首個 authorized operation READY 與 post-auth 已收斂
    - canonical QA SQLite probe 已通過 `qaBundleId` gate
    - Firebase CLI Auth 只供 Auth export、exact UID 與 absence control
    - gcloud Firestore OAuth 可供 Firestore REST read 與 QA cleanup transport 取 token
- **fixture 引用:** `r02_end`、帳戶清單、類別清單、交易組、轉帳組
- **預估時長:** 45 分鐘
- **步驟表:** `no5_r03_backup_export.csv`

本場另有 8 個單元測試層檢查點由 R00 靜態驗證涵蓋、不在本表。

---

## Golden 與同步隔離

- prepare RESULT 與 inspect RESULT 都必須符合 operation-specific exact schema
- runner 必須逐項比對 `no1_fixture_golden.json` 的 required fact keys、計數、signature id 與關係
- 候選 RESULT 的 `verdict=pass` 不得作為唯一通過證據
- candidate signature 只證明 RESULT 內部一致，不得單獨決定場次通過
- R03 final 通過必須另由 `r03_initial_backup` 或 `r03_incremental_backup` 的獨立 Firestore profile 成立
- `prepare r02_end` 以 `qa-fixture-reset` 暫停 sync
- `inspect accounting.fixture-summary` 完成後仍保持同一個 suspend reason
- prepare 與 inspect 期間不得執行 initial backup 或增量 backup
- fixture seed 在第一筆 fixture row 前把本 session 使用者的 `Settings.lastSyncedAt` 重設為 null
- watermark 重設失敗時立即停止，不得接受 initial marker
- remote fixture prepare 前以同一個 `QA_SESSION_UID` 清除既有 QA Firestore subtree
- helper delete exit 0 後，Control 仍須以同一 UID 完成 users root、六個子集合與 root collection ids 的 post-delete absent probes
- gcloud Firestore OAuth 缺少、delete 失敗或任一 absent probe 失敗時不得執行 prepare
- post-delete absent probes 未全數成立時立即停止
- exact UID fixture 子樹未確認乾淨時不得執行 prepare
- 只有合法 token-bound open-app launch 可以解除 `qa-fixture-reset`
- open-app 使用同一個 session token 與新的 `open-app-` 加三十二字元小寫十六進位 requestId
- open-app 後 initial backup 不得因 device cooldown 被 skip
- open-app READY 後等待 `QA BACKUP mode mode=initial`，再執行 Firestore initial profile 對帳
- incremental profile 必須同時查 transactions 與 transfers
- incremental 只允許十筆 live transactions 與兩筆 live transfers
- 兩筆 transfer 金額必須分別為 2000→2000 與 1000→4500
- transactions 與 transfers 都不得出現 golden 以外的 live row
- 修改增量備份交易後，使用 `r03_updated_backup` 核對金額 275 與備註增量備份已修改
- 刪除後使用 `r03_deleted_backup` 核對九筆 live 交易及一筆有效刪除時間的 tombstone
- 修改與刪除兩個檢查點都保留九筆原始交易及兩筆轉帳
- 每次變更後退到背景滿五分鐘再返回，等待背景備份完成
- 清單消失只能證明畫面更新。雲端刪除必須通過獨立 Firestore 核對

---

## 雲端連線中斷與恢復

- 此變體由助手操作 Simulator，沿用 CS-03 的交易、身分及三個獨立 Firestore 檢查點
- 準備至步驟 21，先確認雲端已有增量備份 200 與兩筆轉帳
- 開啟開發者選單，點 QA：暫停雲端連線。等畫面明確顯示已暫停後才繼續
- 依步驟 22 將交易改成 275，備註改為增量備份已修改
- 退至背景滿五分鐘後返回。等待備份逾時或網路失敗標記，核對主畫面仍可操作
- 此時再次執行 `probe R03:21`。雲端必須仍是修改前的 200 與原備註
- 開啟開發者選單，點 QA：恢復雲端連線。等畫面明確顯示已恢復
- 等待失敗後三十秒退避期結束，退至背景再返回。等 `QA BACKUP done` 後執行 `probe R03:24`
- 雲端必須變成 275 與修改後備註。交易仍只有十筆，不因重試多出副本
- 接著依步驟 25 至 27 完成交易刪除與雲端核對
- 場次結束前保持雲端連線已恢復，等待備份完成後才進入清理
- 控制按鈕呼叫 Firestore SDK 的 `disableNetwork` 與 `enableNetwork`。不替換備份程式、不回傳假的成功結果
- 此變體只涵蓋 Firestore 連線中斷。Firebase Auth 與 Mac 其他連線不受影響，不能代替 R14 首次身分建立前的離線驗證
- 控制只存在於 QA 入口。每次操作核對 QA Firebase App 與本場匿名身分，正式 App 不載入此模組
- 連線行為依據：[Firebase 離線資料說明](https://firebase.google.com/docs/firestore/manage-data/enable-offline)

---

## Firestore 身分綁定

- bootstrap READY 只保存 `identityHash`
- cleanup 或首次手動變更前，可先以 Firebase CLI Auth export 將 exact-one uid hash 綁定 READY `identityHash`
- 需要執行 App 資料後，必須再以 canonical QA SQLite `users.id` exact-one 交叉驗證同一 `QA_SESSION_UID`
- `prepare r02_end` 建立 CS-02 metadata 指定的本機 seed
- `inspect accounting.fixture-summary` 對齊 CS-02 metadata 指定的唯讀證據
- prepare 與 inspect 都使用同一 session proof
- 首次 firestore-read 前列舉 canonical QA SQLite 的 `users.id`
- 列舉查詢為 `SELECT id FROM users WHERE _status != 'deleted' ORDER BY id;`
- SQLite 候選只由 command substitution 捕獲
- SQLite 候選不得輸出、寫入 log 或寫入 session 報告
- 每個候選 uid 只在本機計算 SHA-256
- 候選 hash 必須與 READY `identityHash` exact-one match
- 零筆 match 立即停止
- 多筆 match 立即停止
- 零筆 match 不重試或改用猜測
- raw uid 只留在 shell memory 的 `QA_SESSION_UID`
- R03 的 Firestore resource path 全由 `QA_SESSION_UID` 衍生
- 禁止選 newest 文件
- 禁止選任意文件
- 禁止輸出或回報 raw uid
- Firestore REST 原始回應以 bounded Python process memory parse 讀取
- Firestore REST 原始回應不得進 shell memory 或落盤
- shell 只接收 allowlisted profile verdict
- 不直接輸出 Firestore REST 原始回應
- 可見證據中的 uid 固定遮罩為 `[QA_SESSION_UID]`
- disposal 只刪除 Firebase Auth 身分
- disposal 不代表 Firestore 孤兒資料已清除

執行指引三句。照步驟表列序走、一列一步。已驗欄是該步收下的檢查點、多條以全形分號分隔。類型為 Claude節點 的列停下等 Claude 或依說明貼回輸出。
