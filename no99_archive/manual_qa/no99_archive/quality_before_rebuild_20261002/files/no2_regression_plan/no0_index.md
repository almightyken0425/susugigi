# 回歸測試計劃索引

- 本檔為計劃入口，格式權威為 `test_plan_writer` skill
- 分冊依整合層 Product Map 的 app module 分組
- 排除 LogicEngine 與非 app 平台，前者未實作
- 場次腳本層在 `no3_run_scripts/`，入口為該目錄索引

---

## 測項總表

| 分冊 | 區碼 | 測項數 |
| --- | --- | --- |
| `no1_auth_bootstrap.md` 啟動與身分 | AU | 3 |
| `no2_recording_core.md` 記錄核心 | RC | 7 |
| `no3_home_dashboard.md` 首頁報表與搜尋 | HD | 7 |
| `no4_entity_management.md` 帳戶與類別 | EN | 5 |
| `no5_currency.md` 幣別與匯率 | CU | 5 |
| `no6_app_setting.md` 設定偏好與資料 | AS | 8 |
| `no7_cloud_sync.md` 雲端同步 | CS | 4 |
| `no8_payment.md` 付費 | PM | 9 |
| `no9_local_database.md` 本地資料庫 | LD | 3 |
| `no10_cloud_functions.md` 後端 | CF | 4 |
| 合計 | 十冊 | 55 |

---

## 生成基線表

- 基線代表計劃反映上游到該 commit
- refresh 全部完成才整批上推，流程見 `test_plan_writer` 的維護流程
- PM-06 至 PM-09 為本機 StoreKit 的局部增補。R15 與 RC-02 依六項寫法試改。本次未完成全計劃 refresh，保留既有生成基線。

| 上游 repo | commit | tree | 同步日期 |
| --- | --- | --- | --- |
| `no3_product_specs/no2_accounting_app` | `11936d1b7f887c2e9eb58b12ebb066e51758bd80` | `a63e15312a00ca6aafd15432ee2e0b11e4408910` | 2026-08-30 |
| `no3_product_specs/no3_cloud_functions` | `f25080520ffa08ffefe565ad828a490ea520d194` | `8cf7c60cae870a722f83adb42152c6ac1039cf24` | 2026-08-25 |
| `no5_product_development/no2_accounting_app` | `4b58e646a727d57b4e730a6d6b878656531026be` | `ec4ea1af5f0fc07e34b4d5a58103fb1824a58da9` | 2026-08-30 |
| `no5_product_development/no3_cloud_functions` | `98c202b8f90d7d5711fb835803b6fb5e4e06dfd5` | `3190279d596a7ffe5b55d083fe42f88fa8f62b49` | 2026-08-25 |

---

## 測項 QA metadata

- metadata 是計劃宣告
- metadata 不存執行結果
- 全部五十五案都必須宣告
- 九個欄位都必須填寫

| 欄位 | 規則 |
| --- | --- |
| `feature_links` | 至少一個 Product Map 功能鍵 |
| `risk_tags` | 至少一個風險標籤 |
| `capabilities` | 只准引用能力側寫手段 id |
| `tier` | 只准為 `core`、`standard`、`extended` |
| `runtime_route` | 只准為 `none`、`simulator`、`physical-device`、`simulator-or-physical-device` |
| `driver` | 只准為 `none`、`sim-review`、`game-test` |
| `seed` | `none` 或 qa-command 場景 id |
| `inspect` | `none` 或 qa-probe 檢查 id |
| `evidence` | 至少一個能力側寫手段 id，可加證據鍵 |

- core 是最短高風險信心集
- standard 固定選 `tier: core` 加 `tier: standard`
- extended 是高成本或特殊環境回歸
- 測項定義可以引用受阻 capability
- game-test 開跑前必須 fail-closed
- `none` 只准配 `none`
- `simulator` 只准配 `sim-review`
- `physical-device` 只准配 `game-test`
- `simulator-or-physical-device` 只准配 `game-test`
- `physical-device` 必須含 `manual-device`
- flexible route 由 game-test 解析
- 解析發生在 session 開始前
- seed 非 `none` 時須含 qa-command
- inspect 非 `none` 時須含 qa-probe
- evidence 的冒號前段是手段 id

---

## 規格覆蓋登記表

- 每份 spec 檔列出引用測項編號，六十二份全數覆蓋
- 後端 spec 以 cf 前綴標示，屬 `no3_product_specs/no3_cloud_functions`

| spec 檔 | 引用測項 |
| --- | --- |
| `no1_data_models/no1_data_models.md` | LD-01、LD-02、LD-03、AS-08 |
| `no2_screens/no2_home_screen.md` | HD-01、HD-03、HD-04、HD-05、HD-07、AS-04 |
| `no2_screens/no3_home_filter_screen.md` | HD-02 |
| `no2_screens/no4_search_screen.md` | HD-06、AS-04 |
| `no2_screens/no5_transaction_editor_screen.md` | RC-01、RC-02、RC-05、AS-08 |
| `no2_screens/no6_transfer_editor_screen.md` | RC-03、AS-08 |
| `no2_screens/no7_recurring_setting_screen.md` | RC-04 |
| `no2_screens/no8_settings_screen.md` | AS-01 |
| `no2_screens/no9_category_list_screen.md` | EN-01、EN-02、EN-04、EN-05 |
| `no2_screens/no10_category_editor_screen.md` | EN-01、EN-02、EN-04 |
| `no2_screens/no11_account_list_screen.md` | EN-03、EN-05 |
| `no2_screens/no12_account_editor_screen.md` | EN-03、EN-04 |
| `no2_screens/no13_merge_editor_screen.md` | RC-07 |
| `no2_screens/no14_data_management_screen.md` | AS-06、AS-07 |
| `no2_screens/no15_import_wizard_screen.md` | AS-05 |
| `no2_screens/no16_preference_screen.md` | AS-04、AS-08 |
| `no2_screens/no17_theme_settings_screen.md` | AS-02 |
| `no2_screens/no18_launch_mode_setting_screen.md` | AS-03 |
| `no2_screens/no19_base_currency_setting_screen.md` | CU-01 |
| `no2_screens/no20_currency_list_screen.md` | CU-02 |
| `no2_screens/no21_currency_detail_config_screen.md` | CU-02 |
| `no2_screens/no22_currency_rate_list_screen.md` | CU-03、CU-04 |
| `no2_screens/no23_currency_rate_editor_screen.md` | CU-04 |
| `no2_screens/no24_language_setting_screen.md` | AS-04 |
| `no2_screens/no25_time_zone_setting_screen.md` | AS-04 |
| `no2_screens/no26_paywall_screen.md` | PM-01、PM-02、PM-03、PM-06、PM-07、PM-08、AS-08 |
| `no2_screens/no27_week_start_setting_screen.md` | AS-04 |
| `no2_screens/no28_offline_retry_screen.md` | AU-02 |
| `no2_screens/no29_usage_analytics_consent_prompt.md` | AS-08 |
| `shared_ui_policies/date_picker_policy.md` | RC-04、AS-04 |
| `shared_ui_policies/delete_button_policy.md` | EN-04 |
| `shared_ui_policies/header_policy.md` | HD-02 |
| `shared_ui_policies/input_field_policy.md` | RC-01 |
| `shared_ui_policies/list_policy.md` | HD-04、HD-06 |
| `shared_ui_policies/search_policy.md` | HD-06 |
| `shared_ui_policies/undo_bar_policy.md` | RC-07 |
| `no3_logics/no1_app_bootstrap_logic.md` | AU-01、AU-03、AS-03、AS-08、CS-03 |
| `no3_logics/no2_anonymous_bootstrap_logic.md` | AU-01、AU-02、AU-03 |
| `no3_logics/no3_post_auth_logic.md` | AU-01 |
| `no3_logics/no5_settings_management.md` | AS-02、AS-03、AS-04、AS-08 |
| `no3_logics/no6_premium_logic.md` | PM-02、PM-03、PM-05、PM-06、PM-07、PM-08、PM-09 |
| `no3_logics/no7_currency_conversion_logic.md` | CU-01、CU-02、CU-03、CU-04、CU-05 |
| `no3_logics/no8_transfer_logic.md` | RC-03 |
| `no3_logics/no9_transaction_logic.md` | RC-01、RC-02 |
| `no3_logics/no10_recurring_transactions_logic.md` | RC-04、RC-05、RC-06 |
| `no3_logics/no11_undo_logic.md` | RC-02 |
| `no3_logics/no12_quota_management_logic.md` | CS-02、CS-04 |
| `no3_logics/no13_home_report_logic.md` | HD-03、HD-04、HD-07 |
| `no3_logics/no14_category_logic.md` | EN-01、EN-02、EN-04、EN-05 |
| `no3_logics/no15_account_logic.md` | EN-03、EN-04、EN-05 |
| `no3_logics/no16_merge_logic.md` | RC-07 |
| `no3_logics/no17_subscription_gate_logic.md` | PM-04、PM-09 |
| `no3_logics/no18_preference_upload_logic.md` | CS-01、AS-08 |
| `no3_logics/no19_transaction_backup_logic.md` | CS-02、CS-03、CS-04 |
| `no3_logics/no21_data_transfer_logic.md` | AS-05、AS-06、AS-08 |
| `no3_logics/no22_home_period_state_logic.md` | HD-01、HD-02、HD-04、HD-05、HD-07 |
| `no3_logics/no23_local_database_logic.md` | LD-02、LD-03、HD-07 |
| `no3_logics/no24_delete_user_account_logic.md` | AS-07 |
| `no3_logics/no25_usage_analytics_logic.md` | AS-08 |
| cf `no1_data_models/no1_data_models.md` | CF-01、CF-02、CF-03 |
| cf `no3_logics/no1_iap_verification_logic.md` | CF-01、CF-02、CF-03 |
| cf `no3_logics/no2_account_deletion_logic.md` | CF-03 |

---

## 路徑映射表

- impl 路徑前綴對應分冊區碼
- 區碼是版本差異選集的粗篩鍵
- 直接測項存在時以測項編號精確選集
- 一檔可服務多冊時映射取主責冊
- 共用 QA runtime 與 Firebase wiring 固定對應 `CS-02`、`HD-07`、`RC-06`
- `src/qa/` 只作 coarse mapping，身分 bootstrap、proof、operation、auth guard 與 disposal 由窄路徑列決定直接測項
- 映射不到的路徑升級人工判讀

| impl 路徑前綴 | 區碼 | 直接測項 |
| --- | --- | --- |
| `src/database/helpers/createInitialUserData*`、`src/constants/seedDefaults*`、`assets/definitions/InitialDataDefinition.json` | AU | |
| `App.tsx`、`__tests__/App.test*`、`src/utils/releaseQaTrace*` | AS | |
| `src/contexts/AuthContext*`、`src/services/firebase.ts`、`src/navigation/` | AU | |
| `src/services/transactionLogic*`、`src/services/transferLogic*`、`src/services/recurringLogic*`、`src/services/mergeService*`、`src/contexts/UndoContext*`、`src/hooks/useCalculator*`、`src/screens/Transactions/`、`src/screens/Merge/`、`src/components/RecurringOptions*` | RC | |
| `src/screens/Home/`、`src/screens/Search/`、`src/contexts/HomeFilterContext*`、`src/contexts/homeFilterPersistence*`、`src/contexts/reconcileAccountSelection*`、`src/services/homeReportLogic*`、`src/services/homeReportRepository*`、`src/services/homeLargeHistoryRegression*`、`src/stores/PeriodDataStore*`、`src/components/DonutChart*` | HD | |
| `src/services/categoryLogic*`、`src/services/accountLogic*`、`src/screens/Categories/`、`src/screens/Accounts/` | EN | |
| `src/services/currencyService*`、`src/services/transferDisplayLogic*`、`src/contexts/CurrencyContext*`、`src/utils/formatters*` | CU | |
| `src/utils/formatters*` | CU | `CU-01`、`CU-02`、`CU-03`、`CU-04`、`CU-05`、`AS-04` |
| `src/components/CalendarDialog*`、`src/utils/zonedDateTime*` | AS | `AS-04`、`RC-04` |
| `src/screens/Settings/`、`src/components/UsageAnalyticsConsentPrompt*`、`src/locales/usageAnalyticsConsentTranslations*`、`src/services/importService*`、`src/services/exportService*`、`src/services/templateService*`、`src/services/usageAnalytics*`、`src/contexts/PreferenceContext*` | AS | |
| `firebase.json`、`ios/Podfile`、`ios/SuSuGiGiApp/PrivacyInfo.xcprivacy` | AS | |
| `src/services/syncEngine*`、`src/services/runBackup*`、`src/services/quotaService*`、`src/services/userService*` | CS | |
| `src/screens/Paywall/`、`src/constants/legal*`、`src/contexts/PremiumContext*`、`src/services/subscriptionGateLogic*`、`src/services/storeKitTier*`、`src/services/entitlementService*` | PM | |
| `src/services/iapService*`、`src/constants/entitlements*` | PM | |
| `ios/SwishLocal.storekit`、`ios/STOREKIT_TESTING.md`、`ios/SuSuGiGiApp.xcodeproj/xcshareddata/xcschemes/SuSuGiGiApp-QA-StoreKit.xcscheme` | PM | `PM-06`、`PM-07`、`PM-08`、`PM-09` |
| `ios/SuSuGiGiApp.xcodeproj/project.pbxproj` | PM | `PM-06`、`PM-07`、`PM-08`、`PM-09` |
| `ios/scripts/select-storekit-config.sh`、`src/qa/qaLocalStoreKitMenu*`、`src/qa/QaApp.tsx`、`ios/SuSuGiGiApp/AppDelegate.swift`、`ios/SuSuGiGiApp/BuildEnvironmentModule.m` | PM | `PM-06`、`PM-07`、`PM-08`、`PM-09` |
| `src/database/`、`src/services/localDbService*` | LD | |
| 後端 impl 的 `functions/src/` | CF | |
| `App.tsx` | QA | `AU-01`、`AU-02`、`AU-03`、`AS-03`、`AS-08`、`CS-02`、`CS-03`、`HD-07`、`RC-06` |
| `src/contexts/AuthContext*` | QA | `AU-01`、`AU-02`、`AU-03`、`AS-03`、`AS-08`、`CS-02`、`CS-03`、`HD-07`、`RC-06` |
| `src/services/recurringLogic.ts`、`src/services/recurringLogic.test.ts` | QA | `AU-01`、`AU-03`、`CS-02`、`RC-06` |
| `src/database/helpers/createInitialUserData.ts`、`src/database/helpers/createInitialUserData.test.ts` | QA | `AU-01`、`AU-03`、`CS-02`、`CS-03` |
| `src/services/userService.ts`、`src/services/userService.test.ts` | QA | `AU-01`、`AU-03`、`CS-01`、`CS-02`、`CS-03` |
| `src/services/syncEngine.ts`、`src/services/syncEngine.test.ts` | QA | `CS-02`、`CS-03` |
| `src/services/runBackup.ts`、`src/services/runBackup.test.ts` | QA | `CS-02`、`CS-03` |
| `src/contexts/PremiumContext.tsx`、`src/contexts/PremiumContext.storeKit.test.tsx` | QA | `CS-03`、`PM-02`、`PM-03`、`PM-05` |
| `src/qa/` | QA | |
| `src/qa/qaCloudNetworkMenu*` | QA | `CS-03` |
| `src/qa/QaFirstLaunchApp*`、`src/qa/qaFirstLaunchSession*`、`ios/SuSuGiGiApp/QaAuthNetworkFault.h`、`src/qa/nativeProofHarness/auth_network_test.m` | QA | `AU-02` |
| `src/qa/accountingQaHarness*`、`src/qa/fixtureEvidence*` | QA | `CS-02`、`RC-06` |
| `src/qa/anonymousIdentityBootstrap*`、`src/services/firebase.ts` | QA | `AU-01`、`AU-03`、`CS-02` |
| `src/qa/anonymousIdentityDisposal*` | QA | `AS-07`、`CF-03` |
| `src/qa/qaSessionProof*`、`src/qa/nativeProofHarness/*`、`src/qa/nativeQaBuildIsolation.test.ts`、`ios/SuSuGiGiApp/BuildEnvironmentModule.m` | QA | `AU-01`、`AU-03`、`AS-07`、`CF-03`、`CS-02`、`HD-07`、`RC-06` |
| `src/qa/QaApp*`、`src/qa/QaRuntimeBridge*`、`src/qa/appQaHarness*`、`src/qa/enabledQaHarness*`、`src/qa/interface*`、`src/qa/QaOperationGateApp*`、`src/qa/qaOperationAuthorization*`、`src/qa/qaAuthGuard*`、`src/qa/registerQaRuntime*` | QA | `CS-02`、`HD-07`、`RC-06` |
| `index.qa.js`、`src/qa/qaLaunchPlan*`、`src/qa/nativeQaLaunchPlan*`、`src/qa/qaEntrySelection*`、`src/qa/invalidQaLaunch*`、`src/qa/qaNativeMarkerForwarding*`、`src/qa/buildEntryIsolation.test.ts`、`src/qa/firebaseConfigSelection.test.ts`、`src/qa/productionModuleGraph*` | QA | `AU-01`、`AU-03`、`AS-07`、`CF-03`、`CS-02`、`HD-07`、`RC-06` |
| `.gitignore`、`src/utils/buildEnvironment*`、`src/services/appCheck.ts`、`src/services/localDbService.qaReset.test.ts`、`ios/scripts/select-firebase-config.sh`、`ios/SuSuGiGiApp.xcodeproj/project.pbxproj`、`ios/SuSuGiGiApp/AppDelegate.swift`、`ios/SuSuGiGiApp/Info.plist` | QA | `CS-02`、`HD-07`、`RC-06` |
