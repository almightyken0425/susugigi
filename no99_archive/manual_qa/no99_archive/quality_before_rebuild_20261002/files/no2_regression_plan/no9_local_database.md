# 本地資料庫分冊

- 區碼 `LD`，對應整合層 Product Map 的 LocalDatabase
- 涵蓋 schema migration、跨重啟持久化、軟刪除不變式

---

## LD-01 版本升級 schema migration

- **QA metadata:**
    - feature_links: `app/local_database`
    - risk_tags: `migration`、`data-integrity`
    - capabilities: `manual-ui`、`jest-app`
    - tier: `extended`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 帶既有資料的舊版 app 覆蓋升級新版，migration 完成後資料完整可用
- **規格依據:**
    - `no1_data_models.md ## 使用者自訂資料結構`
- **前置:**
    - 裝置已安裝舊版 build，且有交易、帳戶與類別資料
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 於舊版建立資料後關閉 app
    - 安裝新版 build 覆蓋升級
    - 開啟 app 檢視各清單
- **檢查點:**
    - **升級後開啟不閃退，既有資料完整呈現**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **migration 鏈自初版起連續無缺口**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: 無規格
        - 實作錨: `src/database/migrations.ts`
    - **schema 欄位定義與資料模型規格一致**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/database/schema.ts`
    - **新增欄位依規格預設值補齊，如 weekStart 預設 auto**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/database/migrations.ts`

---

## LD-02 跨重啟資料持久化

- **QA metadata:**
    - feature_links: `app/local_database`
    - risk_tags: `persistence`、`offline`
    - capabilities: `manual-ui`、`jest-app`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 建立資料後完全關閉 app 重開，資料仍在且離線可讀
- **規格依據:**
    - `no23_local_database_logic.md ## 目的`
    - `no1_data_models.md ## 金額數值標準`
    - `no1_data_models.md ## 時間格式標準`
- **前置:**
    - 已完成 bootstrap 的裝置
    - 已有至少一個帳戶與一個類別
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 新增一個帳戶與一筆交易
    - 完全關閉 app
    - 斷網後重新開啟，檢視清單
- **檢查點:**
    - **重啟後帳戶與交易完整呈現，離線不影響讀取**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **清單查詢一律以 userId 限定範圍**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no23_local_database_logic.md ## 目的`
        - 實作錨: `src/services/localDbService.ts`
    - **金額以固定倍率縮放整數落庫**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no1_data_models.md ## 金額數值標準`
        - 實作錨: `src/database/models/Transaction.ts`
    - **時間欄位以 UTC Unix Timestamp 毫秒存放**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no1_data_models.md ## 時間格式標準`
        - 實作錨: `src/database/models/SoftDeletableModel.ts`

---

## LD-03 軟刪除與停用不變式

- **QA metadata:**
    - feature_links: `app/local_database`
    - risk_tags: `soft-delete`、`query-scope`
    - capabilities: `manual-ui`、`jest-app`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 刪除與停用帳戶或類別後，清單與選擇器正確排除、記錄仍留庫
- **規格依據:**
    - `no23_local_database_logic.md ## getAccounts`
    - `no23_local_database_logic.md ## getAccountsForSelector`
    - `no1_data_models.md ## 使用者自訂資料結構`
- **前置:**
    - 已有可刪除與可停用的帳戶與類別
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 停用一個帳戶
    - 刪除一個類別
    - 檢視管理清單與編輯時的選擇器
- **檢查點:**
    - **刪除的類別自管理清單消失**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no23_local_database_logic.md ## getCategories`
    - **停用的帳戶留在管理清單、自選擇器排除**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no23_local_database_logic.md ## getAccountsForSelector`
    - **軟刪記錄 deletedOn 寫入時間戳，實體仍留庫**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no1_data_models.md ## 使用者自訂資料結構`
        - 實作錨: `src/database/models/SoftDeletableModel.ts`
    - **清單查詢排除 deletedOn 非 Null 記錄**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no23_local_database_logic.md ## getAccounts`
        - 實作錨: `src/services/localDbService.ts`
