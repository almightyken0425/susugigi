# SuSuGiGi 產品指令

- 本 repo 是頂層 Product git。
- 本 repo 承載提案與規劃。
- 本 repo 也承載 Roadmap。
- 專案管理位於工作區根層。

## 多層 git 邊界

- 各 module 層皆為獨立 git。
- 層級與配對以產品註冊表為準。
- 不在本 repo 追蹤 module 內容。
- 跨層分支必須逐字一致。
- 配對 commit 使用相同內容。
- 合併一律等待使用者明示。

## 命名規則

- 對外產品顯示名稱為 `Swish`，所有語系一致。
- `SuSuGiGi` 維持內部產品識別，改名依據見 `no1_product_initiation/no4_brand_name.md`。
- GitHub repository 與正式 checkout 資料夾使用 `susugigi`。
- 自建資料夾與檔名使用 `snake_case`。
- 前後關係使用不補零的 `noN_` 前綴。
- `no0_` 保留給入口與總覽。
- `no99_` 保留給封存內容。
- 原始匯入資料保留來源檔名，避免失去稽核依據。

## 動工路由

- 改動前必須使用 `product-scope`。
- 先回答上游 review 四問。
- 設定遷移不改產品語意。
- 所有 Markdown 必須使用 `doc-markdown`。
- Spec 路徑另使用 `code-spec`。
- Quality 路徑另使用 `test-define`。

## 產品術語

- 付費等級只用以下形式。
  - `LEVEL_0`
  - `LEVEL_1`
  - `LEVEL_2`
  - `LEVEL_3`
  - `LEVEL_B`
- 商業定義由提案層仲裁。
- module 能力由對應規格承載。

## Product Map 讀取

- Product Map 依平台拆分。
- 先讀 `structure.md`。
- 再讀目標平台索引。
- 只讀任務需要的 module。
- 禁止一次載入整個目錄。

## 指令檔維護

- `AGENTS.md` 是規則單一真相。
- `CLAUDE.md` 僅保留相容入口。
- 不在相容入口複製規則。
- 規則變動只修改原生入口。
