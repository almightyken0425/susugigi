# 產出與 Selector

## 前提

- 先解析 `quality_owner`。
- Quality 不存在時停止。
- 能力側寫不存在時先建立。
- Product Map 決定功能全貌。
- Spec 決定行為契約。
- Impl 只供錨點與能力查核。

---

## 計劃產出

- 依 Product Map 聚類分冊。
- 先產一冊作格式驗證。
- 確認格式後完成其餘分冊。
- 跨冊流程只保留一份。
- 編號必須全域唯一。
- 每個 case metadata 必須齊全。
- 每個規格都要有覆蓋狀態。
- 每個 impl 錨點必須可達。

---

## 場次產出

- case 定稿後才產場次。
- fixture 先定義資料契約。
- 場次依狀態累積排序。
- 破壞性場次排在鏈末。
- 無法安全提供必要能力時建立結構化阻斷場次。
- 結構化阻斷場次在索引與各自 runbook 檔頭逐字鏡射。
- 結構化阻斷只使用 `caseId`、`status`、`blockPhase` 與 `reason` 四個欄位。
- `caseId` 使用場次索引的 Rxx ID，不使用功能測項 ID。
- 同一功能測項可由多個 Rxx 場次承載，selector 必須保留所有承載關係。
- 場次承載同時來自 CSV 的 `測項` 與 `已驗` 欄。
- 承載關係只使用完整 case ID 比對。
- selected case 零承載時立即停止。
- 每個承載場次的完整前置閉包都必須納入阻斷比對。
- `status` 固定為 `blocked`，`blockPhase` 固定為 `first-operation`。
- 靜態驗證可獨立執行。
- 每個檢查點至少被引用一次。
- 覆蓋例外必須寫明原因。

---

## branch-diff Selector

- 輸入必須包含：
    - target kind
    - base commit
    - base tree SHA
- clean target 另含：
    - target commit
    - target tree SHA
- worktree target 另含：
    - worktree snapshot digest
- worktree 差異包含 tracked 與 untracked 路徑。
- 取得兩端完整路徑差異。
- 每個差異路徑必須收集所有命中的映射列。
- 路徑映射命中直接測項時優先精確選案。
- 多個命中列的直接測項取精確聯集並排序去重。
- 每個直接測項必須先驗證 case ID 存在。
- 任一直接測項不存在時 selector 停止。
- 任一命中列有直接測項時，忽略所有命中列的區碼粗篩。
- 精確選案後展開必要前置鏈。
- 只有全部命中列的直接測項皆為空時，才使用區碼粗篩。
- 粗篩使用全部命中列的區碼與實作錨。
- 粗篩選案後展開必要前置鏈。
- 規格異動依規格依據選案。
- 資料模型異動擴張相依流程。
- 共用層異動擴張相關 module。
- 映射不到的路徑列為缺口。
- 有缺口時 selector 不得宣告完整。

---

## core-regression Selector

- 選取 tier 為 `core` 的 case。
- 排除候選版本不適用 case。
- 排除必須附穩定規則。
- 不得依執行方便排除。

---

## impacted-plus-core Selector

- 先執行 `branch-diff`。
- 再執行 `core-regression`。
- 合併後依 case ID 去重。
- 保留所有風險標籤。
- 任何缺口沿用為阻塞。
- 本 selector 不代表回歸深度。

---

## 直接選案

- `feature` 由 `test-run` 執行。
- feature 選案順序：
    - 取得 branch diff
    - 解析 Product Map feature links
    - 解析 Product Map risk tags
    - 正規化 selector 陣列
    - 比對 case metadata
- selector 陣列各自排序去重。
- 兩個陣列聯集至少非空。
- `featureLinks` 比對 `feature_links`。
- `riskTags` 比對 `risk_tags`。
- 任一交集即選取 case。
- 命中時保留完整 case。
- 選案後展開必要前置鏈。
- 新功能無對應 case 時停止。
- `full-regression` 由 `test-run` 執行。
- 選取全部適用 case。
- regression `core` 選 core tier。
- regression `standard` 選：
    - core tier
    - standard tier
- regression `extended` 選全部 tier。
- 直接選案仍需計算 digest。

---

## 場次展開

- 選完 case 後展開每個 case 的全部承載場次。
- 承載場次取精確聯集。
- 任一 selected case 沒有承載場次時停止。
- 每個承載場次展開完整前置閉包。
- 承載場次與前置閉包取精確聯集。
- 聯集依結構化阻斷表分流。
- 安全場次繼續進入 runtime route。
- 阻斷場次只產生 `blocked` 結果。
- 阻斷場次不啟動 build 或 App。
- 同時含兩類場次時輸出 `partial-blocked`。
- `core` 與 `standard` 仍套用相同分流。
- 回歸深度不得改寫場次阻斷狀態。

---

## Selector 輸出

- 輸出每個 case 的完整 metadata。
- 輸出選案理由。
- 輸出未映射差異。
- 輸出覆蓋缺口。
- 輸出使用的 Quality 身分。
- 輸出只留 session。
- 完成後計算 case-set digest。

---

## 完整性檢查

- case ID 無重複。
- metadata 欄位無缺漏。
- `runtime_route` 與 `driver` 配對合法。
- capability 引用均存在。
- scene 與 check 定義均存在。
- case 可引用受阻 capability。
- 受阻狀態必須保留。
- 結構化阻斷索引與 runbook 鏡射必須一致。
- 規格覆蓋已更新。
- 基線 commit 與 tree 齊全。
- Markdown 全部通過 linter。
- 唯讀檢核器通過。
