# 設定偏好與資料分冊

- 區碼 `AS`，對應整合層 Product Map 的 AppSetting
- 涵蓋設定入口、主題、啟動模式、語系時區週起始日、偏好持久化、使用行為分析、匯入匯出、清除所有資料端到端
- 貨幣設定與匯率流程屬 CU 分冊，付費牆內行為屬 PM 分冊，本冊觸及僅一句帶過

---

## AS-01 設定主頁入口導覽與升級入口

- **QA metadata:**
    - feature_links: `app/app_setting`
    - risk_tags: `navigation`、`version-identity`
    - capabilities: `manual-ui`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`

- **範圍:** 從主畫面進入設定頁，逐一導航各入口並確認免費版升級入口與版本號
- **規格依據:** `no8_settings_screen.md`
- **前置:** 已完成初始化的裝置，目前為免費版 LEVEL_0
- **步驟:**
    - 進入設定頁，逐一點入類別管理、帳戶管理、資料管理、偏好設定後返回，捲動查看底部版本號
- **檢查點:**
    - **各入口導航至對應畫面並可返回，App 版本號錨定底部且符合待驗版 Marketing Version**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 實作錨: `src/screens/Settings/SettingsScreen.tsx`
    - **免費版顯示升級入口並導向付費牆，牆內行為屬 PM 分冊**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui

---

## AS-02 主題切換即時套用與重啟沿用

- **QA metadata:**
    - feature_links: `app/app_setting`
    - risk_tags: `theme`、`persistence`
    - capabilities: `manual-ui`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`

- **範圍:** 於主題設定選新主題套用全 App，重啟後沿用
- **規格依據:**
    - `no17_theme_settings_screen.md`
    - `no5_settings_management.md ## switchTheme`
- **前置:** 主題切換為內部功能，以內部入口開啟 Modal
- **步驟:**
    - 開啟主題設定 Modal，點選另一主題卡片後點完成
    - 再開 Modal 點選第三個主題後點關閉，殺掉 app 重開
- **檢查點:**
    - **點選卡片右上出現勾選 overlay，完成後全 App 即時換色**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 實作錨: `src/screens/Settings/ThemeSettingsScreen.tsx`
    - **點關閉不套用選取中的變更**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **重開後沿用所選主題**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui

---

## AS-03 啟動模式設定與 editor 落點

- **QA metadata:**
    - feature_links: `app/app_setting`
    - risk_tags: `launch-mode`、`bootstrap`
    - capabilities: `manual-ui`、`qa-markers`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`qa-markers`

- **範圍:** 設定啟動模式為支出，重啟落地交易編輯器；付費等級對落點的攔截屬 PM 分冊
- **規格依據:**
    - `no18_launch_mode_setting_screen.md`
    - `no5_settings_management.md ## setLaunchMode`
    - `no1_app_bootstrap_logic.md ## resolveLaunchDestination`
- **前置:**
    - 已完成初始化的裝置
    - qa-markers 條件為 Mac 加 Debug build console
- **步驟:**
    - 偏好設定進啟動模式，選支出後點完成
    - 殺掉 app 重開落地，驗畢回設為首頁
- **檢查點:**
    - **選項顯示選取標記，偏好設定列顯示當前模式**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **重開落點為支出模式的交易編輯器，關閉後回主畫面**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no1_app_bootstrap_logic.md ## resolveLaunchDestination`
    - **啟動落點解析輸出 QA BOOT resolve 標記，landing 值為所設模式**
        - 層: 日誌 ／ 驗證者: Claude ／ 手段: qa-markers
        - 實作錨: `src/navigation/AppNavigator.tsx`

---

## AS-04 語系時區週起始日切換與偏好持久化

- **QA metadata:**
    - feature_links: `app/app_setting`
    - risk_tags: `preference`、`localization`、`timezone`、`date-integrity`
    - capabilities: `manual-ui`、`jest-app`
    - tier: `standard`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 切換語系、時區與週起始日，重開確認沿用。核對日期顯示與日期選擇使用同一 App 時區。上傳落庫與不回寫契約由 CS-01 承載。
- **規格依據:**
    - `no16_preference_screen.md`
    - `no24_language_setting_screen.md`
    - `no25_time_zone_setting_screen.md`
    - `no27_week_start_setting_screen.md`
    - `no5_settings_management.md`
    - `shared_ui_policies/date_picker_policy.md`
    - `no2_home_screen.md`
    - `no4_search_screen.md`
- **前置:**
    - 已依 AS-02 與 AS-03 設定主題與啟動模式
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 進語系設定，以搜尋篩選後選日本語，點完成
    - 進時區選 Tokyo、週起始日選週一，各點完成
    - 殺掉 app 重開，回偏好設定逐列查看
    - 執行跨日時區與日期選擇器測試，核對台北、洛杉磯及夏令時間邊界
- **檢查點:**
    - **語系列表目前選取置頂，搜尋依代碼或原生名稱即時篩選，無結果顯示空狀態**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **完成後介面立即切為所選語系，時區與週起始日列顯示新值**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **重開後主題、啟動模式、語系、時區與週起始日全數沿用**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **theme、launchMode、language、timeZone 與 weekStart 寫入 Settings 表**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/contexts/PreferenceContext.tsx`
    - **報表標題、紀錄列、搜尋日期與編輯器使用 App 時區，切換時區不改寫原時刻**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/utils/formatters.timezone.test.ts`、`src/contexts/PreferenceContext.usageAnalyticsConsent.test.tsx`、`src/screens/Home/components/TxDateBadge.timezone.test.tsx`、`src/components/CalendarDialog.timezone.test.tsx`
    - **選日、選月與編輯時分依 App 時區回傳時刻，跨日與夏令時間保持一致**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/components/CalendarDialog.timezone.test.tsx`、`src/utils/zonedDateTime.test.ts`

---

## AS-05 匯入精靈四步匯入交易

- **QA metadata:**
    - feature_links: `app/app_setting`
    - risk_tags: `import`、`data-integrity`
    - capabilities: `manual-ui`、`jest-app`、`manual-device`
    - tier: `extended`
    - runtime_route: `none`
    - driver: `none`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 從資料管理進匯入精靈，走完選檔、欄位對應、內容比對、預覽後送出入帳
- **規格依據:**
    - `no15_import_wizard_screen.md`
    - `no21_data_transfer_logic.md`
- **前置:**
    - 備妥合法交易 CSV，內容含既有與新的帳戶類別
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 資料管理點匯入收入支出，下載範本與說明檔各一次
    - 選來源時區與 CSV 檔後前進，確認欄位對應後前進
    - 於內容比對為新帳戶與新類別選新建後前進，核對預覽摘要後送出
- **檢查點:**
    - **選非 CSV 檔顯示僅支援 CSV 格式對話框**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **範本與說明經系統分享面板產出，欄位與匯入接受格式同源**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 實作錨: `src/services/templateService.ts`
    - **交易與轉帳的範本與說明使用 `Swish_transaction_template.csv`、`Swish_transfer_template.csv`、`Swish_transaction_guide.txt`、`Swish_transfer_guide.txt`**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no21_data_transfer_logic.md ## shareTemplate`、`no21_data_transfer_logic.md ## shareInstructions`
        - 實作錨: `src/services/templateService.test.ts`
    - **必填欄位含空值或非法值時整欄不入候選，擋於欄位對應**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no21_data_transfer_logic.md ## suggestColumnMapping`
        - 實作錨: `src/services/importService.ts`
    - **內容比對僅列當前使用者活躍紀錄，同名不同幣別帳戶各自一列**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **送出成功顯示已匯入與略過筆數，確認後關閉 Modal、交易入清單**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **金額超出可儲存範圍的列於執行時略過並計入略過數**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/services/importService.ts`

---

## AS-06 匯出 CSV 與原樣重匯

- **QA metadata:**
    - feature_links: `app/app_setting`
    - risk_tags: `export`、`round-trip`
    - capabilities: `manual-ui`、`jest-app`
    - tier: `extended`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `manual-ui`、`jest-app`

- **範圍:** 匯出交易 CSV 經分享面板保存，原檔重匯確認新增為獨立紀錄
- **規格依據:**
    - `no14_data_management_screen.md`
    - `no21_data_transfer_logic.md ## exportToCsv`
- **前置:**
    - 至少一筆交易、無任何轉帳
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 資料管理點匯出轉帳
    - 點匯出收入支出，於分享面板存檔
    - 以剛匯出的交易檔重走匯入精靈送出
- **檢查點:**
    - **無轉帳資料時顯示無資料對話框，匯出交易觸發分享面板、檔名依類型附時間戳**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **匯出欄位順序與範本同源，時間帶 UTC 偏移、金額以儲存精度輸出**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/services/exportService.ts`
    - **原樣重匯每列配新主鍵新增為獨立紀錄，不被靜默略過**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no21_data_transfer_logic.md ## executeImport`

---

## AS-07 清除所有資料端到端

- **QA metadata:**
    - feature_links: `app/app_setting`
    - risk_tags: `destructive`、`identity`、`cloud-data`
    - capabilities: `manual-ui`、`jest-app`、`firestore-read`、`cloud-logging`、`manual-device`
    - tier: `core`
    - runtime_route: `none`
    - driver: `none`
    - seed: `none`
    - inspect: `none`
    - evidence: `firestore-read:users`、`cloud-logging:deleteUserAccount`

- **範圍:** 從資料管理發起清除，兩段確認後雲端本機身分全滅，自動重生新匿名身分續用
- **規格依據:**
    - `no14_data_management_screen.md`
    - `no24_delete_user_account_logic.md`
- **前置:**
    - 裝置連網，已有記帳資料且已備份上雲；以 READY identityHash 綁定清除前 `QA_SESSION_UID`，兩者只留 shell memory
    - firestore-read 條件為 gcloud Firestore OAuth 可取得 access token
    - cloud-logging 條件為 gcloud OAuth 可讀 QA project logs
    - jest-app 條件為本機 node_modules 完整
- **步驟:**
    - 資料管理點清除所有資料，說明對話框確認繼續
    - 最終確認對話框點破壞性樣式確認，等待完成落回主畫面
- **檢查點:**
    - **說明段預告雲端本機身分全滅不可復原，清除中入口停用並顯示進度**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **完成後回主畫面路線，新匿名身分直接續用，本機舊資料清空**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
    - **雲端 users/${QA_SESSION_UID} 文件與 session-scoped 子集合全滅**
        - 層: 雲端資料 ／ 驗證者: Claude ／ 手段: firestore-read
        - 依據: `no2_account_deletion_logic.md ## deleteUserAccount`
        - 實作錨: `functions/src/handlers/deleteUserAccount.ts`
    - **accountDeletions/${QA_SESSION_UID} 留存墓碑並標記刪除完成**
        - 層: 雲端資料 ／ 驗證者: Claude ／ 手段: firestore-read
        - 依據: `no2_account_deletion_logic.md ## deleteUserAccount`
        - 實作錨: `functions/src/services/deletionTombstone.ts`
    - **Cloud Logging 有 deleteUserAccount 執行完成訊息，無刪除未完成錯誤**
        - 層: 日誌 ／ 驗證者: Claude ／ 手段: cloud-logging
        - 實作錨: `functions/src/handlers/deleteUserAccount.ts`
    - **本機硬刪僅動被刪身分的資料列，歷史身分殘留保留**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no24_delete_user_account_logic.md ## destroyUserData`
        - 實作錨: `src/services/localDbService.ts`

---

## AS-08 使用行為分析同意與事件保護

- **QA metadata:**
    - feature_links: `app/app_setting`
    - risk_tags: `privacy`、`analytics`
    - capabilities: `manual-ui`、`jest-app`、`qa-markers`
    - tier: `core`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - seed: `none`
    - inspect: `none`
    - evidence: `qa-markers:QA ANALYTICS`、`jest-app`

- **範圍:** 驗證首次啟動同意提示、偏好控制與五個自訂事件的資料邊界
- **規格依據:**
    - `no29_usage_analytics_consent_prompt.md`
    - `no16_preference_screen.md`
    - `no1_app_bootstrap_logic.md ## bootstrapApp`
    - `no25_usage_analytics_logic.md ## resolveUsageAnalyticsConsent`
    - `no5_settings_management.md ## setUsageAnalyticsConsent`
    - `no18_preference_upload_logic.md`
- **前置:**
    - 備妥尚未決定使用分析的乾淨安裝
    - 備妥第二個乾淨安裝驗同意分支
    - jest-app 條件為本機 node_modules 完整
    - qa-markers 條件為 Mac 加 Debug build
- **步驟:**
    - 啟動 app 並等待首頁可用
    - 核對標題為協助改善
    - 核對首行為分享功能使用情況
    - 核對次行為不含記帳內容
    - 核對不要分享與同意並繼續按鈕
    - 點不要分享後重啟 app
    - 進偏好設定核對使用分析開關
    - 以第二個乾淨安裝重新啟動
    - 點同意並繼續後重啟 app
    - 回偏好設定關閉使用分析
- **檢查點:**
    - **偏好頁只留使用分析開關且無說明，財務分析開關不顯示，切換與重啟沿用**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 實作錨: `src/screens/Settings/PreferenceScreen.tsx`
    - **尚未決定時首頁就緒後顯示同意提示，拒絕後重啟不再顯示且偏好開關為關**
        - 層: UI ／ 驗證者: 使用者 ／ 手段: manual-ui
        - 依據: `no29_usage_analytics_consent_prompt.md`
        - 實作錨: `src/components/UsageAnalyticsConsentPrompt.tsx`
    - **QA ANALYTICS 依序記錄提示、決定、蒐集狀態與事件結果，且不含 uid 或帳目內容**
        - 層: 日誌 ／ 驗證者: Claude ／ 手段: qa-markers
        - 依據: `no25_usage_analytics_logic.md`
        - 實作錨: `src/utils/releaseQaTrace.ts`、`src/services/usageAnalytics.ts`
    - **首次可用啟動只顯示一次提示，標題、兩行訊息與兩個按鈕符合指定文案，二十種支援語系皆有完整文案，偏好載入取消時不顯示**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/components/UsageAnalyticsConsentPrompt.test.tsx`、`src/contexts/PreferenceContext.usageAnalyticsConsent.test.tsx`、`src/locales/usageAnalyticsConsentTranslations.test.ts`
    - **決定前與拒絕後分析蒐集停用，同意後啟用，快速切換取最後結果，跨使用者舊請求不得啟用分析**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/components/UsageAnalyticsConsentPrompt.test.tsx`、`src/contexts/PreferenceContext.usageAnalyticsConsent.test.tsx`、`src/contexts/preferenceNormalize.test.ts`
    - **未同意與關閉後不送事件，同意時只允許分析儲存，廣告用途保持拒絕**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 實作錨: `src/services/usageAnalytics.test.ts`、`src/services/usageAnalytics.nativeConfig.test.ts`
    - **同意決定只存本機，migration 關閉財務分析，五個自訂事件不帶參數，首次記帳事件只在零筆與一筆邊界送出**
        - 層: 單元測試 ／ 驗證者: Claude ／ 手段: jest-app
        - 依據: `no18_preference_upload_logic.md`
        - 實作錨: `src/contexts/preferenceNormalize.test.ts`、`src/database/schema.test.ts`、`src/services/usageAnalytics.test.ts`
