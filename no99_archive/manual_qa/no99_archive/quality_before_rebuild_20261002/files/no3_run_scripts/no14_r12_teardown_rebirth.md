# R12 毀滅與重生

- **涵蓋測項:** AS-07、CF-03、CF-04
- **前置場次:** R11
- **caseId:** `R12`
- **status:** `blocked`
- **blockPhase:** `first-operation`
- **reason:** `qa-app-check-isolation-unavailable`
- **起點狀態:** 同 R11 終點
- **終點狀態:** 全資料已清除、新匿名身分重生、`[QA_SESSION_UID]` 對應的雲端資料滅盡、回歸完成
- **前置環境:**
    - 目前受阻。QA App 不載入或註冊 App Check，deleteUserAccount 無可用 QA 呼叫路徑
    - QA AuthProvider terminal latch 另外不允許同一 root 在刪除身分後匿名重生
    - 不提供 physical-device、simulator 或 manual route。game-test 必須在第一個 operation 前 fail-closed
    - 不得改用 Production Firebase 設定、Production build、dev log 或 Metro raw uid 繞過阻斷
    - 清除前 raw uid 只以 `QA_SESSION_UID` 留在 shell memory
    - 清除後只在 shell memory 比較新舊 READY identityHash；可見證據只記 verdict
    - Firebase CLI Auth control 可執行 Auth export、exact UID 與 absence
    - gcloud Firestore OAuth 可執行 Firestore read 與 cleanup
    - gcloud OAuth 可讀 QA project 的 Cloud Logging
    - 三項 readiness 不得互相推定
    - app impl 主 checkout node_modules 完整
    - functions 內 node_modules 裝妥
    - 測試身分已有雲端資料，且曾完成 sandbox 購買、授權在案
    - CF-04 需可於 GCP console 對 billing-alerts topic 發布測試訊息
- **fixture 引用:** CSV assets 的 import_small 重建產物，清除後驗其滅盡
- **預估時長:** 30 分鐘
- **步驟表:** `no14_r12_teardown_rebirth.csv`

本場另有 4 個單元測試層檢查點由 R00 靜態驗證涵蓋、不在本表。

執行指引三句。照步驟表列序走、一列一步。已驗欄是該步收下的檢查點、多條以全形分號分隔。類型為 Claude節點 的列停下等 Claude 或依說明貼回輸出。
