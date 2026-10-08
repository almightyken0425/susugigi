# R14 首次離線啟動與重試

- **涵蓋測項:** AU-02
- **前置場次:** 無
- **caseId:** `R14`
- **runtime_route:** `simulator`
- **driver:** `sim-review`
- **起點狀態:** 重新安裝的 QA App。匿名身分、session proof 與使用者資料皆不存在。
- **終點狀態:** 進入首頁。冷啟動後仍只有一組預設資料。
- **預估時長:** 15 分
- **步驟表:** `no16_r14_pre_identity_offline_launch.csv`

## 操作步驟

- 執行器重新安裝 QA App，先確認沒有待回收的 proof。
- 第一次開啟時維持身分服務斷線，看到離線重試畫面。
- 點一次重試。仍回到離線畫面，等待 20 秒確認沒有自行重試。
- 打開 Simulator 的 Device → Shake，再選 QA：恢復首次啟動連線。
- 關閉提示，點 App 的重試。進入首頁，帳目為空。
- 核對帳戶只有現金與信用卡。支出分類有餐飲、交通、購物，收入分類有薪資、獎金。
- 由執行器完全關閉後重開，再核對相同資料與識別碼，沒有重複建立。

## 執行與證據

- 使用繁體中文、TWD 與本場專用匿名身分。
- 首開使用 `--qa-first-launch true` 與 `first-launch-` requestId。
- 此入口只接受 QA simulator。既有 bootstrap 與 open-app 的 proof 條件維持原契約。
- 身分建立前只允許原有匿名登入與重試流程。觀察到身分後，null、非匿名或身分改變仍永久阻斷該 root。
- 使用 Firebase Auth 底層 GTMSessionFetcher 提供的測試入口，只對 QA API key 的 Auth 請求回報離線錯誤。SDK、重試畫面與恢復後的 QA Firebase 連線均使用實際實作。
- 此變體驗證身分服務斷線，不代表切斷整台 Simulator、Mac 或 Firestore 網路。
- 原生 `FIRST_LAUNCH_EMPTY_IDENTITY`、`AUTH_NETWORK_BLOCKED` 與 `AUTH_NETWORK_RESTORED` 是必要證據。
- 離線時以 `qa-first-launch.py --action empty` 唯讀核對本機零資料及無 proof。
- 成功建立匿名身分後先持久保存 staged 與 active proof，再輸出 READY。
- 執行器以 Auth export 綁定相同身分並取得 fixture 清理責任，才原子寫入清理接手回條。
- App 驗證回條並消耗 `first-launch:true` proof 後，才允許 post-auth 寫入資料。
- 首開 READY 等待上限 600 秒。取得清理責任後，首頁等待上限 30 秒。
- SQLite 獨立核對一筆 user、一筆 settings、兩個帳戶與五個分類。交易、轉帳、排程與匯率皆為零。
- 冷啟動前後的資料識別碼摘要必須相同。raw uid 不輸出。
- 首開視窗有三次匿名登入嘗試，包含兩次離線失敗及恢復後一次成功。首頁落點只解析一次。
- 冷啟動由 sim-review 沿用同 token 與新 open-app requestId，不直接點無參數的 App 圖示。
- 正常及失敗均沿用 proof-backed 身分回收。尚無 proof 的中斷不得推定 Auth 已清除。
- 雲端 fixture 與匿名身分分開清理，分開驗證。

## 方法來源

- [Google GTMSessionFetcher 測試入口](https://github.com/google/gtm-session-fetcher/blob/main/Sources/Core/Public/GTMSessionFetcher/GTMSessionFetcher.h)
- [Firebase 匿名登入](https://firebase.google.com/docs/auth/ios/anonymous-auth)
