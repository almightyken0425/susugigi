# Swish 改名進度與待辦

更新時間：2026-09-24 17:55，Asia/Taipei。

核心改名已合併，商店名稱與發布文案已儲存。新版截圖正在製作，完整裝置驗證與 1.0.2 正式發布尚未完成。

本檔記錄跨任務進度快照。程式、素材及發布文案仍由各層 Git 持有。外部狀態依相關任務的操作與讀回紀錄判定，本次盤點未重新登入核對全部欄位。

## 已完成

| 項目 | 結果 |
| --- | --- |
| 程式與跨層改名 | Product、Spec、Design、App、Support Site、Quality、Release 共七個 Git 已合併並推送 main。涵蓋 iOS／Android 顯示名稱、App 品牌文字、匯入範本、設計字標與發布文件 |
| iOS 版本 | 四個建置設定的 `MARKETING_VERSION` 已改為 `1.0.2` |
| 商店名稱 | 20 語系 Name 已逐一儲存。英文為 `Swish - Expense Tracker`，其他語系使用在地化功能後綴。App 內與桌面維持 `Swish` |
| 審查備註與更新說明 | 審查備註已改為 Swish 並加入更名說明。1.0.2 的 20 語系更新說明已儲存，重新載入後逐語系核對 |
| Firebase 對外名稱 | 正式環境 Public-facing name 已核對為 `Swish`。Project ID 與 Bundle ID 保留正確 |
| 支援網站 | [支援首頁](https://swish-support.web.app/)與[隱私頁](https://swish-support.web.app/privacy/)已部署。部署任務透過 HTTPS 確認內容與來源一致，沒有 `$wish`。瀏覽器語系切換尚未驗證 |
| 基本品牌驗證 | 先前 QA build 已確認桌面為 `Swish QA`、首頁為 `Swish`。這不代表正式版升級與完整回歸已通過 |

## 進行中與待辦

### 1. 商店截圖

- 狀態：進行中，由 `rename - app screenshot` 負責。
- 五張主題：打開直接記錄、常用自己排序、收支一眼看清、帳戶清楚掌握、時區自由切換。
- 最新進度：截圖用的 1.0.2 已編譯成功，正在準備繁中示範資料。標題與版面已設計好，尚待填入實際畫面。
- 待辦：完成繁中五張樣稿與總覽，審閱後延伸其他語系，再依語系及裝置尺寸上傳。
- 完成判準：App 畫面、品牌與文案一致。逐語系預覽後台，確認新圖已儲存。
- App Preview 影片目前只是後續建議，未定為本次發布必要項目。

### 2. 1.0.2 裝置回歸

- 狀態：尚未開始完整裝置回歸，由 `1.0.2 regression` 負責。
- 比較基準：1.0.1 為 `2396a1b03955fc314cbc0d4ba6e07efe4f8bc85f`，1.0.2 主線為 `43834ba83df640e382e3425d438ec15a7ee37e55`。
- 已完成：App 自動測試 1,274 項通過、1 項略過，後端 89 項通過。QA Firebase 設定檔已核對並放入工作區，靜態對帳通過。
- 保留問題：App 測試程序未自行退出。付款、清除資料與離線首開仍有既定執行限制。
- 當前待確認：可使用的 iPhone，該任務已提出裝置問題。
- 待驗：既有安裝升級後的資料、偏好與訂閱，以及啟動、備份、定期交易和正式版環境設定。
- 改名待驗：離線重試頁、相簿權限提示、四種範本下載檔名，以及安裝後的 1.0.2 版本顯示。
- 完成判準：證據對應實際送審候選。未執行與受限項目明列，不以自動測試代替完整裝置驗證。

### 3. Build、送審與發布

- 狀態：最新後台紀錄為 1.0.2 `Prepare for Submission`，尚未選入 Build，未送審、未發布。
- 截圖用 QA 編譯成功不代表正式 Build 已上傳 TestFlight。
- 待辦：準備正式 Build、上傳 TestFlight、完成驗證，再選入原 App 的 1.0.2 版本。
- 發布前確認：截圖、各語系文案與審查資訊完整。發布後再核對商店及安裝後的名稱。

### 4. 外部文案與素材核對

- 尚未逐項核對：其他語系的 Description、Promotional Text、TestFlight 說明，以及月訂與年訂的審查截圖。
- 已確認：英文 Description 使用 Swish。訂閱群組 App Name 已顯示新商店名稱，`Premium Monthly`、`Premium Yearly` 與其商品說明沒有舊品牌。
- 待辦：替換仍含舊品牌的文案或圖片，核對實際使用的預覽影片、自訂產品頁及產品頁測試素材。
- Subtitle 與 Keywords 可再檢查重複詞及母語自然度。這屬搜尋優化，不是改名必填項目。

### 5. Release 定稿與保存

- 狀態：`codex/swish-store-name` 的 Release 工作區有五個未提交修改檔。
- 涉及檔案：`app_store_localizations_v1.0.1.json`、`no0_dashboard.md`、`no2_screenshots.md`、`no4_app_info.md`、`no6_swish_rebrand.md`。
- 已知落差：發布總表與操作清單仍寫其他後台欄位未修改，但審查備註與 20 語系更新說明已完成。
- 已知落差：本機語系 JSON 的 `whatsNew` 仍是舊版增加語言的內容。審查文件也尚未保存這次新增的更名說明。
- 待辦：保存 1.0.2 的實際發布定稿，更新完成狀態與截圖清單，避免之後把舊稿回填後台。
- 完成判準：Release 文件與後台內容一致。依後續收尾授權完成提交、合併與工作區整理。

## 可稍後或依使用情況整理

| 項目 | 現況與後續 |
| --- | --- |
| Firebase 內部標籤 | 正式 Project name 為 `SuSuGiGi`，QA 為 `SuSuGiGi QA`。iOS nickname 仍為 `susugigiios` 與 `SuSuGiGi QA iOS`，可整理為 Swish 對應名稱。QA Public-facing name 尚未確認 |
| 產品註冊表 | 支援站備註仍有 `$wish`。該檔屬控制設定，需依控制維護流程更新說明 |
| Analytics 與外部渠道 | Analytics 資源名稱、社群、客服與其他使用中的行銷素材，尚無完整核對紀錄 |
| 條件式項目 | OAuth、Auth 郵件、Google Play 僅在實際使用時處理。Apple Developer 的內部 App ID 描述可按需要整理 |

## 刻意保留的技術身分

內部產品識別 `SuSuGiGi`、repository slug `susugigi`、Bundle ID、Android application ID、Firebase Project ID、訂閱商品 ID、資料庫與簽章設定均保留。原生專案名與 JS 註冊名沿用 `SuSuGiGiApp`。這些不算漏改。

歷史送審紀錄保留當時名稱。品牌決議見 [對外品牌名稱](../no1_product_initiation/no4_brand_name.md)。外部操作依據位於 Release 的 `no6_swish_rebrand.md`，其 main 尚未包含本次 Release 工作區的全部更新。

## 追溯來源

| 任務 | task ID |
| --- | --- |
| 將 susugigi 名稱改為 Swish | `01a0a9a3-5a12-7761-bc1e-81c0cf55ea00` |
| rename - app store connect | `01a0d245-3782-7973-8261-dec758714175` |
| rename - app screenshot | `01a0d2ab-01e2-7812-a39c-cf5e552ba7fb` |
| rename - firebase | `01a0d2ab-994b-71d1-8495-7ed13378750a` |
| rename - support site | `01a0d2ae-d1df-7ad0-a92b-5356eb86b0e4` |
| 1.0.2 regression | `01a0d27c-f2fa-7063-a06f-a8386d6b5b80` |

七個改名合併提交：Product `17142f9`、Spec `85f5216`、Design `5c98be5`、App `43834ba`、Support Site `d012ccb`、Quality `a94e3ff`、Release `028a689`。

建議順序：完成截圖與裝置回歸，同步保存 Release 定稿，再處理正式 Build、送審及發布。
