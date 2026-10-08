# 記錄核心分冊

- 區碼 `RC`，對應整合層 Product Map 的 RecordingCore
- 涵蓋交易 CRUD 與復原、轉帳 CRUD、計算機輸入、定期排程建立與實例補產生與撤銷、合併流程與其復原

---

## RC-01 以計算機輸入新增支出交易

- **QA metadata:**
    - feature_links: `app/recording_core`
    - risk_tags: `local-data`、`data-integrity`
    - capabilities: `manual-ui`、`jest-app`
    - tier: `core`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 從首頁進入交易編輯器，以計算機鍵盤輸入金額建立支出，回列表確認
- **規格依據:**
    - `no5_transaction_editor_screen.md`
    - `no9_transaction_logic.md ## createTransaction`
    - `input_field_policy.md`
- **前置:** 已有至少一個帳戶與一個支出類別，未觸發付費閘，閘流程屬 PM 分冊，jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 於首頁點新增並選支出
    - 以計算機鍵盤輸入含加減乘除的算式並按等號
    - 選帳戶與類別後點完成
- **檢查點:**
    - **必填欄位未妥時完成按鈕不可點按**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **計算機按鍵結果即時顯示於金額輸入框，等號得出運算結果**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 實作錨: `src/hooks/useCalculator.ts`
    - **支出金額正規化為負整數落庫，達位數上限即時阻擋**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no9_transaction_logic.md ## normalizeTransactionAmount`
        - 實作錨: `src/services/transactionLogic.ts`
    - **完成後返回上一頁並顯示復原列，列表出現新交易**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui

---

## RC-02 編輯與刪除交易並以復原列還原

- **QA metadata:**
    - feature_links: `app/recording_core`
    - risk_tags: `undo`、`data-integrity`
    - capabilities: `manual-ui`、`jest-app`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 分開驗證已儲存交易的編輯，以及刪除後在倒數內復原。
- **規格依據:**
    - `no5_transaction_editor_screen.md`
    - `no9_transaction_logic.md ## updateTransaction`
    - `no11_undo_logic.md`
- **前置狀態:**
    - 首頁已儲存一般支出早餐，金額 123、帳戶錢包、類別餐飲、日期本月 5 日，未設為定期。
    - 由 R02 的 RC-01 流程建立。單獨執行時依 [交易組](../no3_run_scripts/no1_fixtures.md#交易組)重建相同起點。
    - 本機 node_modules 完整，可取得 R00 對應的單元測試證據。
- **操作步驟:**
    - 依[第 1 項](../no3_run_scripts/no4_r02_user_steps.md#1-編輯已儲存的交易)重新打開已儲存的早餐，把 123 改為 150，備註改為前後各一個半形空白的早餐改過。儲存後再次開啟核對。
    - 依[第 2 項](../no3_run_scripts/no4_r02_user_steps.md#2-刪除後在倒數內復原)刪除該筆，在倒數內點復原，核對刪除前後的各欄位。
    - 更新落庫與倒數機制依 R00 第 5 列的交易邏輯及 UndoContext 測試取得證據。
- **檢查點:**
    - **編輯模式依當前內容帶入各欄位，備註寫入時去除前後空白**
        - 層: UI ／ 手段: manual-ui
        - 取證時點: 修改前開啟早餐，以及修改儲存後再次開啟早餐改過
    - **更新落庫，排程連結欄位未帶不改寫**
        - 層: 單元測試 ／ 手段: jest-app
        - 取證時點: R00 第 5 列核對交易邏輯測試結果時
        - 實作錨: `src/services/transactionLogic.ts`
    - **刪除為軟刪除，復原後該筆回到列表**
        - 層: UI ／ 手段: manual-ui
        - 取證時點: 刪除後紀錄消失及復原後重新開啟該筆時
        - 依據: `no9_transaction_logic.md ## deleteTransaction`
    - **復原列倒數歸零自動關閉，後一次操作取代前一次等待**
        - 層: 單元測試 ／ 手段: jest-app
        - 取證時點: R00 第 5 列核對 UndoContext 測試結果時
        - 實作錨: `src/contexts/UndoContext.tsx`
- **結束狀態與清理:**
    - 返回首頁，早餐改過 150 保留，備註前後無空白，其餘欄位不變。
    - 可繼續 R02 建立其餘八筆交易，不刪除此筆。
    - 若本輪只驗本項，依本次 QA 環境收尾流程清理。功能判定與清理結果分開。

---

## RC-03 轉帳建立更新刪除與隱含匯率補錄

- **QA metadata:**
    - feature_links: `app/recording_core`
    - risk_tags: `transfer`、`currency-rate`
    - capabilities: `manual-ui`、`jest-app`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 建立同幣別與跨幣別轉帳，更新金額後刪除並復原，全程驗匯率連動
- **規格依據:**
    - `no6_transfer_editor_screen.md`
    - `no8_transfer_logic.md`
- **前置:** 已有兩個同幣別帳戶與一個不同幣別帳戶，jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 建立同幣別轉帳，輸入轉出金額並選兩帳戶後完成
    - 建立跨幣別轉帳，分別輸入轉出與轉入金額後完成
    - 編輯跨幣別該筆改轉入金額後完成，再刪除並於復原列點復原
- **檢查點:**
    - **同幣別時轉入金額停用並跟隨轉出金額，跨幣別時可獨立輸入**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 實作錨: `src/screens/Transactions/TransferEditorScreen.tsx`
    - **同幣別 impliedRate 為空值，跨幣別為轉入除以轉出並正反兩筆補錄 CurrencyRates**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/services/transferLogic.ts`
    - **更新金額後以新隱含匯率再補錄，生效時點為轉帳日期**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no8_transfer_logic.md ## updateTransfer`
    - **刪除為軟刪除且不刪已產生的匯率記錄，復原後回到列表**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no8_transfer_logic.md ## deleteTransfer`

---

## RC-04 建立定期排程與撤銷建立

- **QA metadata:**
    - feature_links: `app/recording_core`
    - risk_tags: `scheduling`、`undo`
    - capabilities: `manual-ui`、`jest-app`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 於編輯器展開定期設定建立排程與首筆實例並撤銷，另驗單筆轉排程
- **規格依據:**
    - `no7_recurring_setting_screen.md`
    - `no10_recurring_transactions_logic.md ## createSchedule`
- **前置:** 已有至少一個帳戶與類別及一筆一般交易，jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 新增支出並點定期切換按鈕展開定期設定區
    - 開啟啟用開關，設定頻率、間隔與結束日期後點完成
    - 於復原列點復原
    - 開啟既有一般交易，設定定期後點完成
- **檢查點:**
    - **啟用開關控制設定內容區可操作性，間隔輸入僅接受數字且開頭為 0 不更新**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 實作錨: `src/components/RecurringOptions.tsx`
    - **結束日期選擇器為 Date-only 模式，點永不清除結束日期**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `date_picker_policy.md`
    - **排程與首筆實例建立，撤銷後本體與實例一併軟刪除**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no10_recurring_transactions_logic.md ## revertScheduleCreation`
        - 實作錨: `src/services/recurringLogic.ts`
    - **單筆轉排程先建後刪，建立失敗時原紀錄保持完好**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no10_recurring_transactions_logic.md ## convertToSchedule`

---

## RC-05 定期實例編輯與刪除的範圍選擇與撤銷

- **QA metadata:**
    - feature_links: `app/recording_core`
    - risk_tags: `scheduling`、`data-integrity`
    - capabilities: `manual-ui`、`jest-app`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 編輯與刪除排程實例，分別驗僅此一筆與此筆及未來，並撤銷截斷
- **規格依據:**
    - `no5_transaction_editor_screen.md ## 互動`
    - `no10_recurring_transactions_logic.md ## updateSchedule`
    - `no10_recurring_transactions_logic.md ## deleteSchedule`
- **前置:** 已有排程且存在多筆實例，jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 開啟某筆實例改金額後完成，於對話框選僅此一筆
    - 再開啟並修改定期規則後完成，於對話框選此筆及未來，隨即點復原
    - 開啟另一筆點刪除，於對話框選此筆及未來，隨即點復原
- **檢查點:**
    - **定期規則有改動時對話框僅提供此筆及未來**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 實作錨: `src/screens/Transactions/showRecurringModeDialog.ts`
    - **僅此一筆只更新該筆，不影響排程本體**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
    - **此筆及未來把原排程 endOn 截至前一週期，依新規則建新排程並補實例**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/services/recurringLogic.ts`
    - **撤銷更新寫回 endOn 並軟刪新排程，快照復原不復活使用者先前自行刪除的實例**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no10_recurring_transactions_logic.md ## revertScheduleUpdate`
    - **刪除此筆及未來截斷排程，撤銷後 endOn 與實例依快照復原**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no10_recurring_transactions_logic.md ## restoreScheduleInstances`

---

## RC-06 啟動補產生遺漏實例

- **QA metadata:**
    - feature_links: `app/recording_core`
    - risk_tags: `scheduling`、`backfill`
    - capabilities: `manual-ui`、`jest-app`、`qa-markers`、`qa-command`、`qa-probe`
    - tier: `core`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `r09_stale_schedule`
    - inspect: `accounting.schedule-backfill`
    - evidence: `qa-probe:accounting.schedule-backfill`、`qa-markers:QA SCHED`

- **範圍:** 排程存在且跨過多期未開 app，重啟後自動補齊遺漏實例
- **規格依據:**
    - `no10_recurring_transactions_logic.md ## generateMissingInstances`
- **前置:**
    - 已有進行中的排程且跨過至少一個週期，jest-app 條件為本機 node_modules 完整
    - qa-markers 條件為 Mac 上 Metro 執行中
- **步驟:**
    - 保持 app 完全關閉跨過排程週期
    - 重新開啟 app 並落地列表
- **檢查點:**
    - **列表出現遺漏期的實例，補至當前時間為止**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **backfill 標記輸出排程識別碼與產生筆數**
        - 層: 日誌 ／ 驗證者: Claude ／ 手段: qa-markers
        - 實作錨: `src/services/recurringLogic.ts`
    - **同排程同 instanceDate 至多一筆，已軟刪除實例視為已存在不重生**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
    - **每月與每年推算錨定 startOn 原始日號，目標月天數不足夾到月底且不固化**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
    - **instanceDate 晚於當前時間或 endOn 即停止產生**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app

---

## RC-07 帳戶與類別合併與復原

- **QA metadata:**
    - feature_links: `app/recording_core`
    - risk_tags: `merge`、`undo`
    - capabilities: `manual-ui`、`jest-app`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 依序執行帳戶合併與類別合併，各自以復原列還原
- **規格依據:**
    - `no13_merge_editor_screen.md`
    - `no16_merge_logic.md`
- **前置:** 已有掛交易與轉帳的兩個同幣別帳戶、掛交易的兩個同型別類別，jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 進入合併編輯器帳戶模式，選來源與目標後點完成
    - 於復原列點復原
    - 以類別模式重複上述操作
- **檢查點:**
    - **目標選擇器僅列相容項目，帳戶限同幣別、類別限同型別**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 實作錨: `src/screens/Merge/MergeEditorScreen.tsx`
    - **來源與目標相同時完成按鈕不可點按，外框以錯誤色標示衝突**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **合併把關聯交易與轉帳轉移至目標並軟刪除來源，轉移後自我轉帳一併軟刪除**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/services/mergeService.ts`
    - **復原依合併前快照移回，含冗餘轉帳與來源本體**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no16_merge_logic.md ## revertMerge`
    - **復原後列表來源重新出現，記錄歸屬還原**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `undo_bar_policy.md`
