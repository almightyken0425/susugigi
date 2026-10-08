# R11 訂閱生命週期

- **涵蓋測項:** PM-03、CF-02、PM-05
- **前置場次:** R10
- **caseId:** `R11`
- **status:** `blocked`
- **blockPhase:** `first-operation`
- **reason:** `qa-app-check-isolation-unavailable`
- **起點狀態:** 同 R10 終點
- **終點狀態:** 訂閱已自然到期、等級回 LEVEL_0、entitlements 留存到期狀態、app 內有 import_small 重建的小資料集且已候備份
- **前置環境:**
    - 目前受阻。QA App 不載入或註冊 App Check，subscription route 無可用 QA 呼叫路徑
    - 不提供 physical-device、simulator 或 manual route。game-test 必須在第一個 operation 前 fail-closed
    - 不得改用 Production Firebase 設定或 Production build 繞過阻斷
- **fixture 引用:** sandbox 帳號、CSV assets
- **預估時長:** 50 分鐘
- **步驟表:** `no13_r11_subscription_lifecycle.csv`

本場另有 5 個單元測試層檢查點由 R00 靜態驗證涵蓋、不在本表。

執行指引三句。照步驟表列序走、一列一步。已驗欄是該步收下的檢查點、多條以全形分號分隔。類型為 Claude節點 的列停下等 Claude 或依說明貼回輸出。
