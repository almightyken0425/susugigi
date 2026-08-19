# Product Map

## Structure

```
Platform: App — 行動端 React Native
├── Auth / AppClient
│   ├── BootstrapFlow
│   └── PostAuthSetup
├── RecordingCore
│   ├── TransactionEditor
│   ├── TransferEditor
│   ├── RecurringTransactions
│   ├── MergeOperation
│   └── UndoSystem
├── HomeDashboard
│   ├── PeriodView
│   ├── FilterSystem
│   ├── FocusFilter
│   ├── ChartView
│   ├── TransactionList
│   └── SearchFunction
├── AppSetting
│   ├── DataManagement
│   │   ├── CategoryCRUD
│   │   ├── AccountCRUD
│   │   ├── DataOperations
│   │   │   ├── DataImport
│   │   │   │   ├── ImportTransactions
│   │   │   │   └── ImportTransfers
│   │   │   └── DataExport
│   │   │       ├── ExportTransactions
│   │   │       └── ExportTransfers
│   │   └── DataErase
│   ├── Preference
│   │   ├── Appearance
│   │   │   ├── ThemeSystem
│   │   │   └── LaunchModeSetting
│   │   ├── CurrencyAndFinance
│   │   │   ├── BaseCurrencySetting
│   │   │   ├── CurrencyDisplayConfig
│   │   │   │   └── CurrencyDetailConfig
│   │   │   └── ExchangeRateManagement
│   │   │       └── CurrencyRateEditor
│   │   ├── RegionAndLanguage
│   │   │   ├── LanguageSetting
│   │   │   └── TimeZoneSetting
│   │   └── AnalyticsConsent
│   └── Plan
│       └── PlanUpgradeEntry
├── CloudSync / AppClient
│   ├── PreferenceUpload
│   └── TransactionBackup
│       ├── BackupEngine
│       ├── InitialBackup
│       └── QuotaManagement
├── LogicEngine
│   ├── RuleEngine
│   │   ├── RuleCenter
│   │   └── RuleEditor
│   └── TimeMachine
│       └── RecalculationEngine
├── Payment / AppClient
│   ├── PaywallScreen
│   ├── IAPService
│   ├── PremiumContext
│   └── PremiumFeatureGate
└── LocalDatabase

Platform: Web Console
├── SupportSite
│   ├── ContactFAQ
│   ├── WebConsole
│   │   ├── QueryEngine
│   │   │   ├── JQLInterface
│   │   │   └── SavedViews
│   │   └── ReportBuilder
│   │       ├── CustomDimensions
│   │       └── ExportFunction
│   └── Blog
└── AIAdvisor / WebClient
    ├── FinancialInsightsUI
    └── ConversationInterface

Platform: Firebase
├── Authentication
├── Storage（待定義）
├── Firestore
│   ├── DataCollections
│   ├── SecurityRules
│   └── QuotaBaseline
└── CloudFunctions
    ├── IAPReceiptValidation
    ├── AppStoreServerNotifications
    ├── EntitlementWriter
    └── AccountDeletion

Platform: Cloud Service
├── AIAdvisor / Backend
│   ├── LLMProxy
│   ├── CashFlowForecastEngine
│   ├── HealthScoreEngine
│   └── NaturalLanguageQAEngine
├── AnalyticsPipeline
│   ├── FirestoreToBigQueryMirror
│   ├── ActivationTrigger
│   ├── AnalyticsAPI
│   └── ConsentSync
└── MacroData
    ├── DataPipeline
    ├── MarketIntelligence
    │   ├── TrendDashboard
    │   └── CompetitiveAnalysis
    └── EnterpriseDataService
        ├── MacroAPI
        └── PrivacyCompliance

外部服務
└── LLM Provider

ExcludedModule
├── SharedLedger
└── RedeemCodeScreen
```

---

## 索引

| Module                | 平台     | 說明                                           | 詳細                       |
| --------------------- | -------- | ---------------------------------------------- | -------------------------- |
| Auth / AppClient      | App      | 匿名身分 bootstrap、首次啟動初始化             | [app/auth.md](app/auth.md)           |
| RecordingCore         | App      | 交易、轉帳、定期交易、合併、Undo | [app/recording_core.md](app/recording_core.md)           |
| HomeDashboard         | App      | 期間檢視、篩選、圓餅圖、交易清單、搜尋         | [app/home_dashboard.md](app/home_dashboard.md) |
| AppSetting            | App      | 資料管理含 CategoryCRUD、AccountCRUD、匯入匯出、清除所有資料，偏好設定含外觀、貨幣、語言時區，方案 | [app/app_setting.md](app/app_setting.md) |
| CloudSync / AppClient | App      | Preference 單向上傳、交易 silent backup 兩軌 | [app/cloud_sync.md](app/cloud_sync.md)           |
| LogicEngine           | App      | 規則引擎與時光機，LEVEL_2，未實作               | [app/logic_engine.md](app/logic_engine.md)           |
| Payment / AppClient   | App      | Paywall、原生 IAP 訂閱狀態         | [app/payment.md](app/payment.md)           |
| LocalDatabase         | App      | WatermelonDB 本機資料層，Local-First 基礎設施   | [app/local_database.md](app/local_database.md) |
| ContactFAQ            | Web      | 支援官網的聯絡信箱與 FAQ                        | [contact_faq.md](web_console/contact_faq.md) |
| WebConsole            | Web      | 桌面版進階查詢與報表，LEVEL_2，MVP 實作中          | [web_console.md](web_console/web_console.md) |
| Blog                  | Web      | 支援官網的 SEO 內容部落格                       | [blog.md](web_console/blog.md) |
| AIAdvisor / WebClient | Web      | AI 財務顧問前端，LEVEL_3，未實作                | [ai_advisor_web_client.md](web_console/ai_advisor_web_client.md) |
| Authentication        | Firebase | Firebase 身份驗證服務                          | [authentication.md](firebase/authentication.md) |
| Storage               | Firebase | Firebase 資料備份儲存，待定義                          | [storage.md](firebase/storage.md) |
| Firestore             | Firebase | 雲端資料庫，Delta batch sync 後端              | [firestore.md](firebase/firestore.md) |
| CloudFunctions        | Firebase | IAP 交易登記、App Store Server Notifications、寫 entitlement、資料清除 | [cloud_functions.md](firebase/cloud_functions.md) |
| AIAdvisor / Backend   | Cloud    | AI 財務顧問後端，LEVEL_3，架構待定              | [ai_advisor_backend.md](cloud_service/ai_advisor_backend.md) |
| MacroData             | Cloud    | 總體資料服務，LEVEL_B，未實作                   | [macro_data.md](cloud_service/macro_data.md) |
| AnalyticsPipeline     | Cloud    | 分析資料管道，R1 拍板、未啟動                   | [analytics_pipeline.md](cloud_service/analytics_pipeline.md) |
| LLM Provider          | 外部服務 | AI 推理 API 服務                               | [llm_provider.md](external_service/llm_provider.md) |
