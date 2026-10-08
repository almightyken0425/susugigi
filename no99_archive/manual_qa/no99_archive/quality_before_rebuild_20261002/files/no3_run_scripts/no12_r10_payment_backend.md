# R10 付費與後端登記

- **涵蓋測項:** PM-01、PM-04、PM-02、AS-05、CF-01
- **前置場次:** R08
- **caseId:** `R10`
- **status:** `blocked`
- **blockPhase:** `first-operation`
- **reason:** `qa-app-check-isolation-unavailable`
- **起點狀態:** 同 R08 終點
- **終點狀態:** LEVEL 已升、帳戶五個含投資與悠遊卡、類別九個含禮金與教育、import_small 已入庫且超額列略過、entitlements 與 txnIndex 在案、閘控探針兩筆留庫至 R11 重裝
- **前置環境:**
    - 目前受阻。QA App 不載入或註冊 App Check，verifyTransaction 與 txnIndex route 無可用 QA 呼叫路徑
    - 不提供 physical-device、simulator 或 manual route。game-test 必須在第一個 operation 前 fail-closed
    - 不得改用 Production Firebase 設定或 Production build 繞過阻斷
- **fixture 引用:** 計數紀律、帳戶清單、類別清單、CSV assets、sandbox 帳號
- **預估時長:** 40 分鐘
- **步驟表:** `no12_r10_payment_backend.csv`

本場另有 7 個單元測試層檢查點由 R00 靜態驗證涵蓋、不在本表。

執行指引三句。照步驟表列序走、一列一步。已驗欄是該步收下的檢查點、多條以全形分號分隔。類型為 Claude節點 的列停下等 Claude 或依說明貼回輸出。
