# 帳戶與類別分冊

- 區碼 `EN`，對應整合層 Product Map 的 AppSetting 之 CategoryCRUD 與 AccountCRUD
- 涵蓋類別與帳戶的清單與編輯器 CRUD、拖拉排序、停用與軟刪除呈現
- 合併流程屬 RC 分冊；刪除後的 Undo 復原流程屬 RC 分冊；新增入口的付費牆分流屬 PM 分冊，此處只註記

---

## EN-01 新增類別並於分區清單呈現

- **QA metadata:**
    - feature_links: `app/app_setting`
    - risk_tags: `category`、`local-data`
    - capabilities: `manual-ui`、`jest-app`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 從類別列表點新增進編輯器，建立收入類別後回列表分區呈現
- **規格依據:**
    - `no9_category_list_screen.md`
    - `no10_category_editor_screen.md`
    - `no14_category_logic.md ## createCategory`
- **前置:**
    - 使用者可新增類別，付費牆分流屬 PM 分冊
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 從設定的資料管理進類別列表，點新增按鈕
    - 於類型選擇器切換為收入
    - 輸入類別名稱、點選圖示
    - 點完成回列表
- **檢查點:**
    - **新增模式標題為新增類別，類型預設選中支出**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no10_category_editor_screen.md ## 佈局`
    - **切換類型保留已輸入名稱與已選圖示**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no10_category_editor_screen.md ## 互動`
    - **名稱未填妥時完成鈕不可點按**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **名稱前後空白去除，超過長度上限回驗證失敗**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no14_category_logic.md ## createCategory`
        - 實作錨: `src/services/categoryLogic.ts`
    - **新類別出現在收入分區列表**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no9_category_list_screen.md ## 佈局`

---

## EN-02 編輯類別與類型鎖定

- **QA metadata:**
    - feature_links: `app/app_setting`
    - risk_tags: `category`、`editing`
    - capabilities: `manual-ui`、`jest-app`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 從列表點既有類別進編輯器，改名換圖示後回列表反映
- **規格依據:**
    - `no10_category_editor_screen.md`
    - `no14_category_logic.md ## updateCategory`
- **前置:**
    - 已有至少一個支出類別
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 進類別列表，點按既有類別
    - 點按類型選擇器
    - 修改名稱、改選圖示
    - 點完成回列表
- **檢查點:**
    - **編輯模式標題為編輯類別，類型選擇器停用樣式且點按無反應**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no10_category_editor_screen.md ## 佈局`
    - **updateCategory 可更新 name、iconId、disabledOn，不更新 type**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no14_category_logic.md ## updateCategory`
        - 實作錨: `src/services/categoryLogic.ts`
    - **改名與換圖示後列表即時反映**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no9_category_list_screen.md ## 佈局`
    - **允許與既有類別同名並存，不做查重**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no10_category_editor_screen.md ## 佈局`

---

## EN-03 新增帳戶與幣別鎖定

- **QA metadata:**
    - feature_links: `app/app_setting`
    - risk_tags: `account`、`currency`
    - capabilities: `manual-ui`、`jest-app`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 從帳戶列表點新增建立外幣帳戶，重進編輯器確認幣別鎖定
- **規格依據:**
    - `no11_account_list_screen.md`
    - `no12_account_editor_screen.md`
    - `no15_account_logic.md ## createAccount`
- **前置:**
    - 已完成主要貨幣設定
    - 使用者可新增帳戶，付費牆分流屬 PM 分冊
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 進帳戶列表，點新增按鈕
    - 展開幣別選擇器，輸入搜尋文字，選一個外幣
    - 輸入帳戶名稱、點選圖示，點完成
    - 回列表點按該帳戶再次進編輯器
- **檢查點:**
    - **新增模式幣別初始為主要貨幣，項目顯示 alphabeticCode 與 name**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no12_account_editor_screen.md ## 佈局`
    - **搜尋文字即時篩選幣別列表**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **名稱前後空白去除，超過長度上限回驗證失敗**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no15_account_logic.md ## createAccount`
        - 實作錨: `src/services/accountLogic.ts`
    - **編輯模式幣別不可展開、不可修改**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no12_account_editor_screen.md ## 佈局`
    - **新帳戶出現在帳戶列表**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no11_account_list_screen.md ## 佈局`

---

## EN-04 停用與刪除的軟刪呈現

- **QA metadata:**
    - feature_links: `app/app_setting`
    - risk_tags: `destructive`、`soft-delete`
    - capabilities: `manual-ui`、`jest-app`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 停用類別後檢視列表樣式，刪除帳戶經確認對話框完成軟刪除
- **規格依據:**
    - `no10_category_editor_screen.md`
    - `no12_account_editor_screen.md`
    - `delete_button_policy.md`
    - `no14_category_logic.md ## deleteCategory`
    - `no15_account_logic.md ## deleteAccount`
- **前置:**
    - 已有帶交易的類別、帶交易與轉帳紀錄的帳戶
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 編輯既有類別，開啟停用開關後完成
    - 回列表檢視該類別樣式
    - 編輯既有帳戶，點刪除按鈕
    - 於確認對話框確認刪除，回列表
- **檢查點:**
    - **停用類別於列表以停用樣式呈現、仍在列**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no9_category_list_screen.md ## 佈局`
    - **刪除按鈕標籤一律為刪除，不帶實體名稱**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `delete_button_policy.md ## 標籤詞庫`
    - **刪除經確認對話框，確認後返回且該帳戶自列表消失**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no12_account_editor_screen.md ## 互動`
    - **deleteCategory 軟刪除並串聯軟刪除所屬交易**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no14_category_logic.md ## deleteCategory`
        - 實作錨: `src/services/categoryLogic.ts`
    - **deleteAccount 軟刪除並串聯軟刪除交易與轉出轉入轉帳**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no15_account_logic.md ## deleteAccount`
        - 實作錨: `src/services/accountLogic.ts`
---

## EN-05 拖拉排序與持久化

- **QA metadata:**
    - feature_links: `app/app_setting`
    - risk_tags: `ordering`、`persistence`
    - capabilities: `manual-ui`、`jest-app`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 於類別與帳戶列表拖拉排序，離開重進確認順序保留
- **規格依據:**
    - `no9_category_list_screen.md ## 互動`
    - `no11_account_list_screen.md ## 互動`
    - `no14_category_logic.md ## reorderCategories`
    - `no15_account_logic.md ## reorderAccounts`
- **前置:**
    - 支出類別至少三個、帳戶至少三個
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 進類別列表，拖拉支出區項目改變順序
    - 離開列表再重進
    - 進帳戶列表，拖拉項目改變順序
    - 離開列表再重進
- **檢查點:**
    - **拖拉後列表順序即時更新**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **重進列表後順序保留**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **reorderCategories 依有序清單批次更新排序欄位**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no14_category_logic.md ## reorderCategories`
        - 實作錨: `src/services/categoryLogic.ts`
    - **reorderAccounts 批次更新排序欄位**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no15_account_logic.md ## reorderAccounts`
        - 實作錨: `src/services/accountLogic.ts`
