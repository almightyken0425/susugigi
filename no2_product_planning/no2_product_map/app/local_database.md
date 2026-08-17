## LocalDatabase — 本機資料層

App 平台的基礎設施節點，全 module 共用的 Local-First 本機持久化層。所有 App 資料先落本地，再由 CloudSync 背景單向上傳。

- **技術：**
    - WatermelonDB
- **功能：**
    - 所有 App 資料的本機持久化儲存
    - 支援響應式查詢，資料變動自動觸發 UI 更新
    - 透過 WatermelonDB adapter 執行原生聚合
    - 提供有上限的分頁讀取
    - 提供 Sync Adapter 介面，將本機變動批次單向上傳至 Firestore
- **目的：**
    - 實現 Local-First 架構，確保 App 在離線狀態下完整運作
- **排除：**
    - 另開 SQLite 直連
    - 繞過 WatermelonDB 存取資料
    - 使用 AsyncStorage 儲存主要資料
