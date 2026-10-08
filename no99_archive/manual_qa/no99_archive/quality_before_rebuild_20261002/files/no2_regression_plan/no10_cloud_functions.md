# 後端分冊

- 區碼 `CF`，對應整合層 Product Map 的 CloudFunctions
- 涵蓋 IAP 驗證登記 entitlements 與 txnIndex、storeNotification 通知更新、帳號刪除後端契約、capBilling 斷計費
- 後端無 UI，觸發面靠 app 操作或 Apple 伺服器；onCall 入口掛 App Check，不直呼 API，副作用以 firestore-read 加 cloud-logging 驗證

---

## CF-01 購買登記寫入 entitlements 與 txnIndex

- **QA metadata:**
    - feature_links: `firebase/cloud_functions`
    - risk_tags: `billing`、`backend`、`entitlement`
    - capabilities: `jest-backend`、`firestore-read`、`cloud-logging`、`manual-device`
    - tier: `core`
    - runtime_route: `none`
    - driver: `none`
    - seed: `none`
    - inspect: `none`
    - evidence: `firestore-read:entitlements`、`cloud-logging:verifyTransaction`、`jest-backend`

- **範圍:** app 端 sandbox 購買觸發 verifyTransaction，伺服器對帳通過後歸戶並寫入授權
- **規格依據:**
    - `no1_iap_verification_logic.md ## verifyTransaction`
    - `no1_data_models.md`
- **前置:**
    - 已完成付費分冊 PM-02 的 sandbox 購買，作為觸發面
    - firestore-read 條件為 gcloud Firestore OAuth 可取得 access token
    - cloud-logging 條件為 gcloud OAuth 可讀 QA project logs
    - jest-backend 條件為 functions 內 node_modules 裝妥
- **步驟:**
    - 於 app 以 sandbox 帳號完成一筆 Premium 購買
    - 等待 client 背景送出登記呼叫
- **檢查點:**
    - **entitlements/${QA_SESSION_UID} 寫入，tier、status、environment、original_transaction_id 符合資料模型**
        - 層: 雲端資料 ／ 驗證者: Claude ／ 手段: firestore-read
        - 實作錨: `functions/src/services/entitlementStore.ts`
    - **txnIndex/${QA_ORIGINAL_TRANSACTION_ID} 的 uid hash 符合 READY identityHash**
        - 層: 雲端資料 ／ 驗證者: Claude ／ 手段: firestore-read
    - **verifyTransaction 執行成功，log 無未捕捉錯誤**
        - 層: 日誌 ／ 驗證者: Claude ／ 手段: cloud-logging
        - 實作錨: `functions/src/handlers/verifyTransaction.ts`
    - **拒絕分支齊備：未登入、缺原始交易編號、墓碑在場、查無訂閱狀態皆不寫入**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-backend
        - 實作錨: `functions/src/handlers/verifyTransaction.test.ts`

---

## CF-02 storeNotification 通知更新授權

- **QA metadata:**
    - feature_links: `firebase/cloud_functions`
    - risk_tags: `notification`、`entitlement`
    - capabilities: `jest-backend`、`firestore-read`、`cloud-logging`、`manual-device`
    - tier: `extended`
    - runtime_route: `none`
    - driver: `none`
    - seed: `none`
    - inspect: `none`
    - evidence: `jest-backend`、`firestore-read`、`cloud-logging`

- **範圍:** Apple 推送訂閱通知，簽章驗證後以 txnIndex 歸戶並重算授權寫回 entitlements
- **規格依據:**
    - `no1_iap_verification_logic.md ## handleStoreNotification`
    - `no1_iap_verification_logic.md ## deriveEntitlement`
    - `no1_iap_verification_logic.md ## writeEntitlement`
- **前置:**
    - CF-01 已完成、txnIndex 歸戶在案
    - sandbox 訂閱週期壓縮，放置即自然產生續訂與到期通知
    - firestore-read 條件為 gcloud Firestore OAuth 可取得 access token
    - cloud-logging 條件為 gcloud OAuth 可讀 QA project logs
    - jest-backend 條件為 functions 內 node_modules 裝妥
- **步驟:**
    - 完成 sandbox 購買後放置裝置，等待自動續訂與到期
    - 依 log 確認通知到達後比對授權文件
- **檢查點:**
    - **通知簽章驗證通過並處理成功，log 無未捕捉錯誤**
        - 層: 日誌 ／ 驗證者: Claude ／ 手段: cloud-logging
        - 實作錨: `functions/src/handlers/storeNotification.ts`
    - **entitlements/${QA_SESSION_UID} 的 status、expires_date、apple_signed_date 隨通知更新**
        - 層: 雲端資料 ／ 驗證者: Claude ／ 手段: firestore-read
        - 依據: `no1_data_models.md`
    - **授權推定正確：有效與寬限期維持等級、退款與撤銷降 LEVEL_0、過期回 LEVEL_0**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-backend
        - 實作錨: `functions/src/logic/deriveEntitlement.test.ts`
    - **亂序防護：簽章時間較舊的事件不覆寫較新授權**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-backend
        - 實作錨: `functions/src/services/entitlementStore.test.ts`
    - **查無歸戶時墓碑在場確認收訖、否則回報重試待補歸戶**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-backend
        - 實作錨: `functions/src/handlers/storeNotification.test.ts`

---

## CF-03 帳號刪除後端契約

- **QA metadata:**
    - feature_links: `firebase/cloud_functions`
    - risk_tags: `destructive`、`backend`
    - capabilities: `jest-backend`、`firestore-read`、`manual-device`
    - tier: `standard`
    - runtime_route: `none`
    - driver: `none`
    - seed: `none`
    - inspect: `none`
    - evidence: `jest-backend`、`firestore-read`

- **範圍:** app 資料清除觸發 deleteUserAccount 的後端契約；使用者可見流程、users 滅團、墓碑與執行 log 由設定分冊 AS-07 承載
- **規格依據:**
    - `no2_account_deletion_logic.md ## deleteUserAccount`
    - `no1_data_models.md`
- **前置:**
    - 測試身分已有雲端資料，且曾完成 sandbox 購買、授權在案
    - 觸發面與 AS-07 同場，本項只驗 AS-07 未覆蓋的後端斷言
    - firestore-read 條件為 gcloud Firestore OAuth 可取得 access token
    - jest-backend 條件為 functions 內 node_modules 裝妥
- **步驟:**
    - 於 app 執行資料清除的最終確認，觸發後端刪除
    - 待回報完成後比對雲端集合
- **檢查點:**
    - **entitlements/${QA_SESSION_UID} 與 txnIndex/${QA_ORIGINAL_TRANSACTION_ID} 全數刪除**
        - 層: 雲端資料 ／ 驗證者: Claude ／ 手段: firestore-read
        - 實作錨: `functions/src/services/userDeletionStore.ts`
    - **契約分支齊備：撤銷失敗不擋刪除、歸戶他人條目不刪、重試冪等**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-backend
        - 實作錨: `functions/src/handlers/deleteUserAccount.test.ts`
    - **清除窗競態防護：墓碑在場時授權寫入被拒**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-backend
        - 依據: `no1_iap_verification_logic.md ## writeEntitlement`
        - 實作錨: `functions/src/services/entitlementStore.test.ts`

---

## CF-04 capBilling 預算超標斷計費

- **QA metadata:**
    - feature_links: `firebase/cloud_functions`
    - risk_tags: `billing-control`、`irreversible`
    - capabilities: `jest-backend`、`cloud-logging`、`manual-device`
    - tier: `extended`
    - runtime_route: `none`
    - driver: `none`
    - seed: `none`
    - inspect: `none`
    - evidence: `jest-backend`、`cloud-logging`

- **範圍:** 預算警報訊息進 billing-alerts topic，成本達標時解除專案計費綁定
- **規格依據:**
    - 無規格
- **前置:**
    - 超標路徑不主動實測，斷計費為不可逆營運動作；回歸只驗未超標路徑與程式分支
    - 未超標訊息由使用者於 GCP console 對 billing-alerts topic 發布，成本值低於預算值
    - cloud-logging 條件為 gcloud OAuth 可讀 QA project logs
    - jest-backend 條件為 functions 內 node_modules 裝妥；capBilling 現無對應測試檔，補測前該點標記本次未驗
- **步驟:**
    - 對 billing-alerts topic 發布一則成本低於預算的測試訊息
    - 比對函式執行 log 與計費狀態
- **檢查點:**
    - **未超標訊息觸發函式執行後直接結束，無錯誤、不斷計費**
        - 層: 日誌 ／ 驗證者: Claude ／ 手段: cloud-logging
        - 實作錨: `functions/src/handlers/capBilling.ts`
    - **分支防護：訊息缺欄位不動作、未超標不動作、已停用冪等不重複**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-backend
        - 實作錨: `functions/src/handlers/capBilling.ts`
