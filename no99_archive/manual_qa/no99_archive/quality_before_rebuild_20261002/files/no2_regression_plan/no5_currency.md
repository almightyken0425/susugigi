# 幣別與匯率分冊

- 區碼 `CU`，對應整合層 Product Map 的 AppSetting 之 CurrencyAndFinance
- 涵蓋主要貨幣設定、幣別顯示格式配置、匯率列表與編輯、換算與金額顯示

---

## CU-01 變更主要貨幣

- **QA metadata:**
    - feature_links: `app/app_setting`
    - risk_tags: `base-currency`、`persistence`
    - capabilities: `manual-ui`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`

- **範圍:** 從偏好設定進主要貨幣畫面，搜尋改選新貨幣後全 App 沿用
- **規格依據:**
    - `no19_base_currency_setting_screen.md`
- **前置:**
    - 已有至少一個外幣帳戶，供匯率列表對照
- **步驟:**
    - 進主要貨幣畫面
    - 輸入搜尋文字後點選另一貨幣
    - 點完成回上一頁
    - 進匯率列表檢視幣別對
- **檢查點:**
    - **進入時目前選取貨幣置頂帶選取標記，其後改選不重排**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no19_base_currency_setting_screen.md ## 佈局`
    - **搜尋依貨幣代碼或名稱即時篩選**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **完成呼叫 setBaseCurrency，重開 app 沿用新主要貨幣**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no19_base_currency_setting_screen.md ## 互動`
        - 實作錨: `src/contexts/PreferenceContext.tsx`
    - **匯率列表幣別對改以新主要貨幣為來源配對**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no7_currency_conversion_logic.md ## getCurrencyPairs`
        - 實作錨: `src/services/currencyService.ts`

---

## CU-02 幣別顯示格式配置與重置

- **QA metadata:**
    - feature_links: `app/app_setting`
    - risk_tags: `formatting`、`persistence`
    - capabilities: `manual-ui`、`jest-app`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 從貨幣格式列表進單一貨幣，配置千分位與小數位後全 App 套用
- **規格依據:**
    - `no20_currency_list_screen.md`
    - `no21_currency_detail_config_screen.md`
    - `no7_currency_conversion_logic.md ## getCurrencyConfig`
- **前置:**
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 進貨幣格式列表，輸入搜尋文字
    - 點選目標貨幣進顯示格式畫面
    - 開啟千分位開關、改選小數位數，點完成
    - 重進該貨幣，點重置為預設值後完成
- **檢查點:**
    - **列表搜尋即時篩選，無結果顯示找不到結果**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no20_currency_list_screen.md ## 互動`
    - **千分位開關兩態各自顯示對應說明文字**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no21_currency_detail_config_screen.md ## 佈局`
    - **完成後金額顯示套用新設定，重置回該貨幣預設位數**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no21_currency_detail_config_screen.md ## 互動`
        - 實作錨: `src/services/settingsLogic.ts`
    - **getCurrencyConfig 優先序為使用者設定、TWD 例外 0、minorUnits**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no7_currency_conversion_logic.md ## getCurrencyConfig`
        - 實作錨: `src/contexts/CurrencyContext.tsx`
---

## CU-03 外幣帳戶佔位匯率入列表

- **QA metadata:**
    - feature_links: `app/app_setting`
    - risk_tags: `currency-rate`、`placeholder`
    - capabilities: `manual-ui`、`jest-app`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 建立外幣帳戶後於匯率列表看到佔位匯率幣別對
- **規格依據:**
    - `no7_currency_conversion_logic.md ## createInitialCurrencyRate`
    - `no22_currency_rate_list_screen.md`
- **前置:**
    - 帳戶建立流程本體屬 EN 分冊，此處僅作前置操作
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 建立一個幣別非主要貨幣的帳戶
    - 進匯率列表
    - 輸入搜尋文字篩選
- **檢查點:**
    - **列表出現該外幣對主要貨幣的幣別對**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no7_currency_conversion_logic.md ## getCurrencyPairs`
        - 實作錨: `src/services/currencyService.ts`
    - **佔位匯率值為 1，date 為極早佔位時點，不重複種入**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no7_currency_conversion_logic.md ## createInitialCurrencyRate`
        - 實作錨: `src/services/currencyService.ts`
    - **匯率單行格式為 `1 主要貨幣代碼 = 數值 外幣代碼`，至少四位有效數字**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no22_currency_rate_list_screen.md ## 佈局`
    - **搜尋依外幣或主要貨幣代碼即時篩選，無結果顯示找不到結果**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no22_currency_rate_list_screen.md ## 互動`

---

## CU-04 編輯匯率並回列表反映

- **QA metadata:**
    - feature_links: `app/app_setting`
    - risk_tags: `currency-rate`、`editing`
    - capabilities: `manual-ui`、`jest-app`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 從匯率列表點幣別對進編輯器，更新匯率後回列表看到新值
- **規格依據:**
    - `no23_currency_rate_editor_screen.md`
    - `no7_currency_conversion_logic.md ## createCurrencyRate`
    - `no7_currency_conversion_logic.md ## resolveCurrencyRate`
- **前置:**
    - 匯率列表已有至少一個幣別對
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 進匯率列表，點按幣別對進編輯器
    - 修改目標金額
    - 點完成返回列表
- **檢查點:**
    - **來源鎖定主要貨幣，目標幣別不可修改**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no23_currency_rate_editor_screen.md ## 佈局`
    - **目標金額預填 1 單位主要貨幣對應的外幣數量**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no23_currency_rate_editor_screen.md ## 佈局`
    - **金額欄即時只接受數字與單一小數點，達上限阻擋**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no23_currency_rate_editor_screen.md ## 佈局`
    - **createCurrencyRate 守門，非有限正值回驗證失敗**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no7_currency_conversion_logic.md ## createCurrencyRate`
        - 實作錨: `src/services/currencyService.ts`
    - **返回列表重新載入，顯示最新匯率**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no22_currency_rate_list_screen.md ## 互動`
    - **resolveCurrencyRate 取最新已生效記錄，反向取倒數，未來時點不生效**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no7_currency_conversion_logic.md ## resolveCurrencyRate`
        - 實作錨: `src/services/currencyService.ts`

---

## CU-05 跨幣別金額換算顯示

- **QA metadata:**
    - feature_links: `app/app_setting`
    - risk_tags: `conversion`、`reporting`
    - capabilities: `manual-ui`、`jest-app`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 帶匯率的外幣資料於報表與清單以主要貨幣換算呈現
- **規格依據:**
    - `no7_currency_conversion_logic.md ## formatCurrency`
    - `no7_currency_conversion_logic.md ## resolveTransferDisplay`
    - `no7_currency_conversion_logic.md ## getMinorUnits`
- **前置:**
    - 已有外幣帳戶、已設定該幣別對匯率
    - 已有跨幣別轉帳與外幣交易資料
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 於首頁選取部分帳戶檢視清單與報表
    - 切換帳戶選取範圍，觀察轉帳顯示變化
- **檢查點:**
    - **外幣金額依已生效匯率換算為主要貨幣呈現**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no7_currency_conversion_logic.md ## resolveCurrencyRate`
    - **轉帳依所選帳戶範圍分流，兩端皆選或皆不選不顯示**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no7_currency_conversion_logic.md ## resolveTransferDisplay`
        - 實作錨: `src/services/transferDisplayLogic.ts`
    - **formatCurrency 依縮放倍率還原主單位，千分位啟用進 K 顯示模式**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no7_currency_conversion_logic.md ## formatCurrency`
        - 實作錨: `src/utils/formatters.ts`
    - **未知貨幣 minorUnits fallback 為 2**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no7_currency_conversion_logic.md ## getMinorUnits`
        - 實作錨: `src/contexts/CurrencyContext.tsx`
