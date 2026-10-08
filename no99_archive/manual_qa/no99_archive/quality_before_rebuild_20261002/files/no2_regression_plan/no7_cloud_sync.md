# 雲端同步分冊

- 區碼 `CS`，對應整合層 Product Map 的 CloudSync
- 涵蓋偏好上傳、初次備份、增量備份與前景恢復觸發、寫入配額閘控與耗盡

---

## CS-01 偏好變更單向上傳

- **QA metadata:**
    - feature_links: `app/cloud_sync`
    - risk_tags: `preference-sync`、`cloud-data`
    - capabilities: `manual-ui`、`jest-app`、`firestore-read`、`qa-markers`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`、`firestore-read`、`qa-markers`

- **範圍:** 使用者於設定變更偏好後，欄位單向上傳至雲端 preferences，本機為唯一真相
- **規格依據:**
    - `no18_preference_upload_logic.md ## uploadPreferences`
    - `no18_preference_upload_logic.md ## getUploadedPreferenceFields`
- **前置:**
    - 已完成 bootstrap 的裝置且連網
    - firestore-read 條件為 gcloud Firestore OAuth 可取得 access token
    - qa-markers 條件為 Mac 上 Metro 執行中
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 開啟設定變更主題與語言
    - 變更主貨幣
    - 停留片刻讓背景上傳完成
- **檢查點:**
    - **設定畫面即時反映變更，雲端值永不回套本機**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no18_preference_upload_logic.md ## 目的`
    - **主貨幣轉 ISO 4217 代碼寫入遠端 currency，無法解析則略過**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/services/userService.ts`
    - **launchMode 與 weekStart 集外值正規化後上傳**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/services/userService.ts`
    - **偏好僅上傳不下載，雲端值不回寫套用本機**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no18_preference_upload_logic.md ## 目的`
        - 實作錨: `src/services/userService.ts`
    - **雲端 preferences 逐欄更新，文件根層 updatedAt 同步更新**
        - 層: 雲端資料 ／ 驗證者: Claude ／ 手段: firestore-read
    - **QA PREF 標記列出上傳欄位，lastSyncedAt 不受偏好上傳影響**
        - 層: 日誌 ／ 驗證者: Claude ／ 手段: qa-markers
        - 實作錨: `src/services/userService.ts`
---

## CS-02 首次備份全量上傳

- **QA metadata:**
    - feature_links: `app/cloud_sync`
    - risk_tags: `backup`、`cloud-data`
    - capabilities: `manual-ui`、`jest-app`、`firestore-read`、`qa-markers`、`qa-command`、`qa-probe`
    - tier: `core`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `r02_end`
    - inspect: `accounting.fixture-summary`
    - evidence: `qa-probe:accounting.fixture-summary`、`qa-markers:QA BACKUP`、`firestore-read:transactions`

- **範圍:** 遠端無資料的帳號落地後觸發備份，走 runInitialBackup 全量上傳六個 collections
- **規格依據:**
    - `no19_transaction_backup_logic.md ## runBackup`
    - `no19_transaction_backup_logic.md ## runInitialBackup`
- **前置:**
    - 本機已有交易、帳戶與類別資料
    - 遠端 transactions 集合為空
    - firestore-read 條件為 gcloud Firestore OAuth 可取得 access token
    - qa-markers 條件為 Mac 上 Metro 執行中
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 冷啟動 app 並落地主畫面
    - 正常操作，等待背景備份完成
- **檢查點:**
    - **備份全程無 UI 阻塞、無進度提示，使用者無感**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no19_transaction_backup_logic.md ## 目的`
    - **探測遠端無資料後進入 initial 模式**
        - 層: 日誌 ／ 驗證者: Claude ／ 手段: qa-markers
        - 實作錨: `src/services/syncEngine.ts`
    - **雲端六個 collections 出現與本機一致的資料**
        - 層: 雲端資料 ／ 驗證者: Claude ／ 手段: firestore-read
        - 依據: `no19_transaction_backup_logic.md ## runInitialBackup`
    - **寫入完成後 lastSyncedAt 更新為當下時間**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/services/syncEngine.ts`
    - **上傳筆數累加至當日寫入配額**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no12_quota_management_logic.md ## incrementQuota`
        - 實作錨: `src/services/quotaService.ts`

---

## CS-03 增量備份與前景恢復觸發

- **QA metadata:**
    - feature_links: `app/cloud_sync`
    - risk_tags: `incremental-backup`、`foreground`
    - capabilities: `jest-app`、`firestore-read`、`qa-markers`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `jest-app`、`firestore-read`、`qa-markers`

- **範圍:** 已完成初次備份的裝置新增交易，app 自背景回前景重新觸發備份，只傳變更
- **斷線變體:** [R03 雲端連線中斷與恢復](../no3_run_scripts/no5_r03_backup_export.md#雲端連線中斷與恢復)沿用同組資料。暫停 Firestore 真實連線，核對失敗時雲端仍保留舊值，恢復後再核對新值
- **規格依據:**
    - `no19_transaction_backup_logic.md ## runDeltaBackup`
    - `no19_transaction_backup_logic.md ## runBackup`
    - `no1_app_bootstrap_logic.md ## handleForegroundResume`
- **前置:**
    - CS-02 已完成的裝置
    - 距上次備份起始已滿 5 分鐘冷卻
    - firestore-read 條件為 gcloud Firestore OAuth 可取得 access token
    - qa-markers 條件為 Mac 上 Metro 執行中
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 新增一筆交易
    - 將 app 退至背景
    - 冷卻期滿後回前景，等待備份完成
    - 開啟增量備份交易。金額改為 275，備註改為增量備份已修改
    - 退到背景滿五分鐘後返回，核對雲端已更新金額與備註
    - 刪除這筆交易並確認刪除，不點復原
    - 退到背景滿五分鐘後返回，核對雲端刪除紀錄
- **檢查點:**
    - **前景恢復委派備份，觸發標記為 foreground**
        - 層: 日誌 ／ 驗證者: Claude ／ 手段: qa-markers
        - 依據: `no1_app_bootstrap_logic.md ## handleForegroundResume`
        - 實作錨: `src/contexts/PremiumContext.tsx`
    - **冷卻未滿的觸發被跳過，不重複上傳**
        - 層: 日誌 ／ 驗證者: Claude ／ 手段: qa-markers
        - 依據: `no19_transaction_backup_logic.md ## runBackup`
        - 實作錨: `src/services/syncEngine.ts`
    - **進入 incremental 模式，僅上傳 lastSyncedAt 之後的變更**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/services/syncEngine.ts`
    - **雲端 transactions 出現該筆新交易，transfers 精確保留兩組轉帳且兩路無額外 live row**
        - 層: 雲端資料 ／ 驗證者: Claude ／ 手段: firestore-read
    - **無變更時跳過上傳，lastSyncedAt 不更新**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no19_transaction_backup_logic.md ## runDeltaBackup`
        - 實作錨: `src/services/syncEngine.ts`
    - **交易修改後雲端保留新金額與備註，既有交易與轉帳不變**
        - 層: 雲端資料 ／ 驗證者: Claude ／ 手段: firestore-read
    - **交易刪除後雲端留有刪除時間，live 交易減一且其他交易與轉帳不變**
        - 層: 雲端資料 ／ 驗證者: Claude ／ 手段: firestore-read

---

## CS-04 寫入配額耗盡與跨日重置

- **QA metadata:**
    - feature_links: `app/cloud_sync`
    - risk_tags: `quota`、`time-boundary`
    - capabilities: `jest-app`、`qa-markers`
    - tier: `extended`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `jest-app`、`qa-markers`

- **範圍:** 當日寫入達 2000 上限時備份暫停，UTC+0 跨日重置後恢復
- **規格依據:**
    - `no12_quota_management_logic.md ## checkQuota`
    - `no12_quota_management_logic.md ## resetQuota`
    - `no19_transaction_backup_logic.md ## runBackup`
- **前置:**
    - 準備超過 2000 筆的匯入資料檔
    - qa-markers 條件為 Mac 上 Metro 執行中
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 匯入大量資料，使備份寫入計數達當日上限
    - 再次觸發備份，確認被閘控
    - 跨過 UTC+0 日界後重開 app，再觸發備份
- **檢查點:**
    - **計數達上限時 checkQuota 回禁止**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/services/quotaService.ts`
    - **寫入禁止時備份跳過，等待跨日重置**
        - 層: 日誌 ／ 驗證者: Claude ／ 手段: qa-markers
        - 依據: `no19_transaction_backup_logic.md ## runBackup`
        - 實作錨: `src/services/syncEngine.ts`
    - **跨日後計數歸零，備份恢復允許**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no12_quota_management_logic.md ## resetQuota`
        - 實作錨: `src/services/quotaService.ts`
    - **偏好上傳與遠端探測 read 不計入寫入計數**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no12_quota_management_logic.md ## 目的`
        - 實作錨: `src/services/userService.ts`
