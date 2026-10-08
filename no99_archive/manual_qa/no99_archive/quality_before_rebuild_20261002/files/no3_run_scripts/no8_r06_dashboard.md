# R06 儀表板

- **涵蓋測項:** HD-01、HD-02、HD-03、HD-04、HD-05、HD-07
- **前置場次:** R05
- **起點狀態:** 同 R05 終點
- **終點狀態:** 首頁篩選已還原全帳戶全類別、overlay 已清除、原資料不變、網路已恢復
- **前置環境:**
    - Mac 加 session 鎖定裝置
    - 本機 node_modules 完整
    - qa-markers 由 Metro 或實機 Debug console 擷取
    - HD-07 需 qa-command 與 qa-probe 的同 session promotion
    - qa-command 與 qa-probe 的持久狀態維持受阻
    - 每次 operation 帶同 session 的 secret token
    - 實機需 QA Debug UI 與 manual-device checkpoint
    - Load 前必須完成離線探測
    - Load 前必須暫停同步並等待 in-flight sync
- **fixture 引用:** 帳戶清單、類別清單、交易組、轉帳組、匯率、大型歷史資料組
- **預估時長:** 50 分鐘
- **步驟表:** `no8_r06_dashboard.csv`

本場另有 25 個單元測試層檢查點由 R00 靜態驗證涵蓋、不在本表。

- HD-07 overlay 只新增當前 QA user 的 marker rows
- HD-07 overlay 含二萬筆交易與四百筆轉帳
- HD-07 overlay 的交易分為一萬筆支出與一萬筆收入
- HD-07 overlay 的交易金額固定一百
- HD-07 overlay 的轉帳分為兩百筆轉出與兩百筆轉入
- HD-07 overlay 的轉帳金額固定五十
- HD-07 overlay 的轉帳帳戶同幣別
- HD-07 overlay 的金標為一百零一萬與一百零一萬
- HD-07 overlay 的紀錄數為二萬零四百
- HD-07 overlay 的期間餘額為零
- HD-07 Load 前先確認離線
- HD-07 Load 寫入前暫停同步
- HD-07 Load 等待既有 in-flight sync
- exact marker 不得進入 sync snapshot 或 push
- marker 前綴或後綴仍須同步
- simulator route 由 game-test 委派 sim-review command
- simulator route 使用 `r06_large_history`
- simulator cleanup 使用 `r06_large_history_cleanup`
- physical-device route 使用 QA Debug UI Load 與 Remove
- physical-device route 由 manual-device checkpoint 承接
- simulator route 使用 `accounting.large-history-overlay`
- inspect probe 核對完整 shape 與全部金標
- shape drift 不得命中 idempotent fast path
- currency drift 不得命中 idempotent fast path
- physical-device Load 成功前由 overlay service 核對完整 shape 與全部金標
- physical-device Remove 成功前由 overlay service 核對 marker rows 歸零
- route 分支列只執行符合 session 的一列
- cleanup 成功後確認原狀態鏈仍在
- cleanup 於 marker 歸零後釋放同步
- cleanup 失敗時保持同步暫停
- cleanup 完成後才恢復網路

執行指引三句。照步驟表列序走、一列一步。已驗欄是該步收下的檢查點、多條以全形分號分隔。類型為 Claude節點 的列停下等 Claude 或依說明貼回輸出。
