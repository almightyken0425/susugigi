# R01 起始與身分

- **涵蓋測項:** LD-01、AU-01、AU-03、AS-08 前段
- **前置場次:** 無
- **起點狀態:** 舊版覆蓋段可為任意舊狀態，正常驗證段已完成 token-bound 匿名 READY
- **終點狀態:** 新匿名身分在案、連網、預設兩帳戶五類別在案、無交易轉帳排程、使用分析已拒絕
- **前置環境:**
    - session 鎖定裝置為 simulator 或專用 QA iPhone
    - simulator 加 Metro；實機加 Xcode Debug console
    - Firebase CLI Auth control 與 gcloud Firestore OAuth 各自就緒，兩者 readiness 不互推
    - app impl 主 checkout node_modules 完整
    - LD-01 需舊版 build 可得
    - token-bound READY 的 `identityHash` 已通過格式與 QA Firebase 綁定
    - 正常驗證段的本機資料庫為空
    - 裝置使用繁體中文與 TWD 地區預設
    - simulator 的完全關閉後重開由 sim-review terminate 並沿用同 token 產生新 `open-app-` requestId
    - 使用者不得直接點無 launch arguments 的 app icon
    - R01:11 私下保存 `createdAt`、`lastLoginAt` 與 `updatedAt` baseline，值只留 session shell memory
    - R01:11 與 R01:15 的 Firestore REST raw response 只做 bounded Python process memory parse，禁止進 shell 或落盤
    - shell 只接收 allowlisted 欄位、baseline 或 profile verdict
    - identity digest 只涵蓋 users path、identityHash、provider、email 與 `createdAt`
    - `lastLoginAt` 與 `updatedAt` 必須存在且不得倒退，但可依冷啟流程推進
    - metadata timestamp 不納入 identity digest
- **fixture 引用:** 無，僅本場臨時資料
- **預估時長:** 35 分鐘
- **步驟表:** `no3_r01_bootstrap_identity.csv`

本場另有 5 個單元測試層檢查點由 R00 靜態驗證涵蓋、不在本表。

執行指引三句。照步驟表列序走、一列一步。已驗欄是該步收下的檢查點、多條以全形分號分隔。類型為 Claude節點 的列停下等 Claude 或依說明貼回輸出。
