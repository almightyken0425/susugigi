# 啟動與身分分冊

- 區碼 `AU`，對應整合層 Product Map 的 Auth 與 AppClient
- 涵蓋匿名 bootstrap、離線重試、熱啟動身分沿用

---

## AU-01 首開連網匿名 bootstrap 與初始化

- **QA metadata:**
    - feature_links: `app/auth`、`app/app_client`
    - risk_tags: `bootstrap`、`identity`
    - capabilities: `manual-ui`、`jest-app`、`firestore-read`
    - tier: `core`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`、`firestore-read`

- **範圍:** 全新安裝連網首開，自動領匿名身分、建立預設記帳資料並落地主畫面
- **規格依據:**
    - `no2_anonymous_bootstrap_logic.md`
    - `no3_post_auth_logic.md`
    - `no1_app_bootstrap_logic.md ## bootstrapApp`
- **前置:**
    - 全新安裝、未曾開啟
    - 裝置連網
    - firestore-read 條件為 gcloud Firestore OAuth 可取得 access token
- **步驟:**
    - 移除既有 app 後重新安裝
    - 連網狀態下首次開啟
    - 等待載入完成落地
    - 檢視帳戶、類別與首頁清單
- **檢查點:**
    - **全程無帳號 UI 與登入畫面，直接落地**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **預設啟動模式下落點為 HomeScreen**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no1_app_bootstrap_logic.md ## resolveLaunchDestination`
    - **本機初始化預設值依裝置 Locale，主題 theme1、啟動模式 home**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no3_post_auth_logic.md ## initializeLocalUser`
        - 實作錨: `src/contexts/AuthContext.tsx`
    - **首次初始化建立兩個主要貨幣帳戶與五個本機語系類別，且不建立交易、轉帳或排程**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no3_post_auth_logic.md ## initializeDefaultEntities`
        - 實作錨: `src/database/helpers/createInitialUserData.ts`
    - **任一帳戶或類別含已刪除紀錄存在時不補種預設資料，重跑初始化亦不重複建立**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no3_post_auth_logic.md ## initializeDefaultEntities`
        - 實作錨: `src/database/helpers/createInitialUserData.test.ts`
    - **雲端 users 文件建立，provider 為 anonymous、email 為空值**
        - 層: 雲端資料 ／ 驗證者: Claude ／ 手段: firestore-read
        - 依據: `no3_post_auth_logic.md ## initializeCloudUser`
    - **uid 不曝露於任何畫面**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no2_anonymous_bootstrap_logic.md ## 目的`

---

## AU-02 離線首開與重試復原

- **QA metadata:**
    - feature_links: `app/auth`、`app/app_client`
    - risk_tags: `offline`、`bootstrap`
    - capabilities: `manual-ui`、`qa-markers`、`sqlite-local`
    - tier: `extended`
    - runtime_route: `simulator`
    - driver: `sim-review`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`qa-markers`、`sqlite-local`

- **範圍:** 離線首開停在重試畫面，連網重試後續走 bootstrap 落地
- **規格依據:**
    - `no28_offline_retry_screen.md`
    - `no2_anonymous_bootstrap_logic.md ## ensureAnonymousUser`
    - `no2_anonymous_bootstrap_logic.md ## retryBootstrap`
- **前置:**
    - 全新安裝、未曾開啟
    - 可控網路開關
    - qa-markers 條件為 Mac 上 Metro 執行中
- **步驟:**
    - 斷網後首次開啟
    - 停在離線重試畫面後，維持斷網點重試
    - 恢復連網再點重試
- **檢查點:**
    - **首開離線顯示重試畫面，文案為首開離線型態**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **斷網重試失敗回到本畫面，不閃退、不自動迴圈重試**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no2_anonymous_bootstrap_logic.md ## ensureAnonymousUser`
    - **連網重試成功進入主畫面**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **恢復連線後只建立一組預設帳戶與分類**
        - 層: 本機資料 ／ 驗證者: Claude ／ 手段: sqlite-local
        - 依據: `no3_post_auth_logic.md ## initializeDefaultEntities`
    - **完全關閉後重開不重複建立預設資料**
        - 層: 本機資料 ／ 驗證者: Claude ／ 手段: sqlite-local
        - 依據: `no3_post_auth_logic.md ## initializeDefaultEntities`
    - **重試經 handleAuthEvent 收斂，兩次離線失敗後恢復成功，首頁落點解析一次**
        - 層: 日誌 ／ 驗證者: Claude ／ 手段: qa-markers
        - 依據: `no2_anonymous_bootstrap_logic.md ## handleAuthEvent`
        - 實作錨: `src/contexts/AuthContext.tsx`
---

## AU-03 熱啟動身分沿用

- **QA metadata:**
    - feature_links: `app/auth`、`app/app_client`
    - risk_tags: `identity`、`persistence`
    - capabilities: `manual-ui`、`firestore-read`、`qa-markers`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`firestore-read`、`qa-markers`

- **範圍:** 已初始化的裝置殺掉 app 重開，沿用既有匿名身分
- **規格依據:**
    - `no2_anonymous_bootstrap_logic.md ## handleAuthEvent`
    - `no1_app_bootstrap_logic.md ## bootstrapApp`
- **前置:**
    - AU-01 已完成的裝置
    - firestore-read 條件為 gcloud Firestore OAuth 可取得 access token
- **步驟:**
    - 完全關閉 app
    - 重新開啟並落地
- **檢查點:**
    - **不出現重試畫面，直接落地主畫面路線**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **沿用 READY identityHash 綁定的同一 users path，provider 為 anonymous、email 為空值且 createdAt 不變；lastLoginAt 與 updatedAt 可依規格推進且不納入 identity digest**
        - 層: 雲端資料 ／ 驗證者: Claude ／ 手段: firestore-read
    - **身分事件去重，冷啟動工作不重跑**
        - 層: 日誌 ／ 驗證者: Claude ／ 手段: qa-markers
        - 依據: `no2_anonymous_bootstrap_logic.md ## handleAuthEvent`
        - 實作錨: `src/contexts/AuthContext.tsx`
