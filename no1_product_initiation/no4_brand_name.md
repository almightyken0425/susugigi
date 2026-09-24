# 對外品牌名稱

2026-09-16 依使用者決議，對外品牌由 `$wish` 統一改為 `Swish`。所有語系採相同拼法。產品定位與功能維持既有定義。

## 適用範圍

- App 名稱、首頁品牌、輔助使用標籤與系統權限說明。
- 匯入範本與欄位說明的下載檔名及品牌標題。CSV 欄位與既有匯入相容性維持原契約。
- 設計字標、支援網站、隱私頁與商店發布文案。

## 延續既有身分

內部產品識別 `SuSuGiGi` 與 repository slug `susugigi` 沿用。Bundle ID、Android application ID、Firebase 專案 ID、資料庫、URL scheme 與訂閱商品 ID 沿用，讓現有安裝、資料與購買紀錄延續。無文字的品牌圖示維持原設計。

## 影響對應

- HomeDashboard 與 Auth / AppClient 跟進顯示名稱。
- AppSetting 的 DataImport 跟進下載檔名。
- ContactFAQ 跟進公開品牌與隱私頁。
- Cloud Functions 無品牌顯示文案，不需改動。
- Quality owner 為 `SuSuGiGi/no2_accounting_app`。只更新受影響測項與場次，不推進完整基線。
- QA 身分、除錯標記與環境隔離契約維持原值。

品牌呈現由 Design 跟進，匯入檔名由 Spec 跟進，發布操作由 Release 的 `no6_swish_rebrand.md` 承載。
