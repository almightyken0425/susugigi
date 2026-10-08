# R08 偏好與同步

- **涵蓋測項:** AS-01、AS-02、AS-03、AS-04、AS-08、CS-01、CS-04 前段
- **前置場次:** R07
- **起點狀態:** 同 R07 終點
- **終點狀態:** 偏好與主題語系主貨幣全還原、使用行為分析關閉、啟動模式還原首頁、當日寫入配額已耗盡、import_quota 的 2100 筆交易在庫
- **前置環境:**
    - session 鎖定裝置為 simulator 或專用 QA iPhone
    - simulator 加 Metro；實機加 Xcode Debug console
    - Firebase CLI Auth control 與 gcloud Firestore OAuth 各自就緒，兩者 readiness 不互推
    - 本機 node_modules 完整
    - CS-01 與 CS-04 需裝置全程連網
    - simulator 的完全關閉後重開由 sim-review terminate 並沿用同 token 產生新 `open-app-` requestId
    - 使用者不得直接點無 launch arguments 的 app icon
    - 首次手動改語系前，以 `r08_original_language` SQLite profile 取得 exact-one live `settings.language`
    - profile UID 只由 stdin 傳入，完整 stdout 只由 command substitution 私下捕獲於 session shell memory
    - CS-01 首次偏好變更前，以 gcloud Firestore OAuth 經 firestore-read 將根層 `updatedAt` 私下保存於 session shell memory
    - R08 的 Firestore REST raw response 只做 bounded Python process memory parse，禁止進 shell 或落盤
    - shell 只接收 allowlisted baseline scalar 或 profile verdict
    - 兩個 baseline 都不得進 argv、log、可見輸出或獨立檔案
- **fixture 引用:** 偏好值組、CSV assets、帳戶清單、類別清單
- **預估時長:** 40 分鐘
- **步驟表:** `no10_r08_preference_sync.csv`

本場另有 13 個單元測試層檢查點由 R00 靜態驗證涵蓋、不在本表。

執行指引三句。照步驟表列序走、一列一步。已驗欄是該步收下的檢查點、多條以全形分號分隔。類型為 Claude節點 的列停下等 Claude 或依說明貼回輸出。
