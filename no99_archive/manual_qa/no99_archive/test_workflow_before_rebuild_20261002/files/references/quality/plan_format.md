# 計劃格式

## 檔案佈局

```text
no1_capability_profile.md
no2_regression_plan/
  no0_index.md
  no1_<area>.md
no3_run_scripts/
  no0_index.md
  no1_fixtures.md
  no2_r01_<topic>.md
  no2_r01_<topic>.csv
```

- 分冊依 Product Map module 聚類。
- 流程不得依技術層拆分。
- 每冊使用固定兩碼區碼。
- case 編號發出後不回收。

---

## 索引

- 索引承載測項總表。
- 索引承載生成基線。
- 索引承載規格覆蓋。
- 索引承載路徑映射。
- 索引承載覆蓋例外。
- 每個上游基線包含：
    - repo 識別
    - 完整 commit
    - 完整 tree SHA
    - 同步日期

### 路徑映射表

- 路徑映射表固定包含三欄。
- 欄位依序為 impl 路徑前綴、區碼、直接測項。
- 直接測項只接受既有 case ID 的完整值。
- case ID 不得使用前綴、範圍或萬用字元。
- 多個直接測項使用頓號分隔。
- 多個直接測項依 case ID 排序去重。
- 每個直接測項都必須存在於測項總表。
- 同一路徑可命中多個路徑映射列。
- 多個命中列的直接測項取精確聯集並排序去重。
- 任一命中列有直接測項時，忽略所有命中列的區碼粗篩。
- 全部命中列的直接測項皆為空時使用區碼粗篩。

| impl 路徑前綴 | 區碼 | 直接測項 |
| --- | --- | --- |
| `src/qa/` | QA | `CS-02`、`HD-07`、`RC-06` |
| `src/services/syncEngine*` | CS | |

---

## Case metadata

- 每個 case 都有 `QA metadata`。
- metadata 必填：
    - `feature_links`
    - `risk_tags`
    - `capabilities`
    - `runtime_route`
    - `driver`
    - `tier`
    - `seed`
    - `inspect`
    - `evidence`
- 無需 seed 時填 `none`。
- 無需 inspect 時填 `none`。
- `runtime_route` 只允許：
    - `none`
    - `simulator`
    - `physical-device`
    - `simulator-or-physical-device`
- `driver` 只允許：
    - `none`
    - `sim-review`
    - `game-test`
- 合法路由配對只有：
    - `none` 配 `none`
    - `simulator` 配 `sim-review`
    - `physical-device` 配 `game-test`
    - `simulator-or-physical-device` 配 `game-test`
- `simulator-or-physical-device` 由 `test-run` 解析。
- `simulator-or-physical-device` 不要求 `manual-device`。
- 多值欄位需固定排序。
- 多值不可用散文替代。

---

## 結構化阻斷場次

- 權威表位於 `no3_run_scripts/no0_index.md` 的 `結構化阻斷場次`。
- 欄位固定為 `caseId`、`status`、`blockPhase` 與 `reason`。
- `caseId` 必須逐字匹配場次索引的 Rxx ID。
- `status` 只接受 `blocked`。
- `blockPhase` 只接受 `first-operation`。
- `reason` 使用小寫連字的固定 token。
- 每個阻斷場次的 runbook 檔頭必須逐字鏡射四個欄位。
- 索引與 runbook 鏡射不一致時檢核失敗。
- `test-run` 必須在 QA build、App launch、裝置 checkpoint 或手動操作前套用阻斷。
- `test-run` 必須收集 selected QA case 的所有承載場次與各自完整前置閉包，再比對結構化阻斷。
- 場次承載關係同時讀取 CSV 的 `測項` 與 `已驗` 欄。
- 承載比對只接受完整 case ID。
- 測項沒有承載場次時必須停止。
- selected QA case 沒有承載場次時必須停止。
- 多個承載場次與前置閉包必須取精確聯集，不得依順序擇一。
- 承載聯集必須分為安全場次與阻斷場次。
- 阻斷場次只記錄 `blocked`，不得阻斷同一選集的安全場次。
- 安全場次仍依 runtime route 執行。
- 同時含安全與阻斷場次時狀態為 `partial-blocked`。
- 阻斷場次不得因 runtime route 或 regression depth 轉為可執行。

---

## Tier 語意

- 任一 tier 可同時展開安全場次與阻斷場次。
- tier 只決定 selected case 範圍。
- tier 不得將個別場次的阻斷擴大為整批停止。

- `core`
    - 登入與啟動健康度。
    - 核心資料安全。
    - 主要寫入與還原。
- `standard`
    - 一般功能流程。
    - 常見跨模組整合。
- `extended`
    - 低頻邊界。
    - 高成本環境情境。

---

## Case 主體

- 每個 case 另外承載：
    - 標題
    - 範圍
    - 規格依據
    - 前置狀態
    - 操作步驟
    - 檢查點
    - 結束狀態與清理需求
- 每個檢查點承載：
    - 可判定的預期
    - 驗證層
    - 手段 id
    - 取證時點
    - 規格依據
    - 實作錨

內容依[六項撰寫要求](test_step_authoring.md)。準備可由場次共用，case 要有明確引用。
檢查點以 `層: ... ／ 手段: ...` 表達證據來源。本次取證者另由 session 指定。
舊 `使用者步驟` 及 `驗證者` 欄仍可讀取，但不代表固定工作分配。

---

## Case 模板

```markdown
## RC-01 建立交易並驗證落庫

- **QA metadata:**
    - feature_links: `RecordingCore.create`
    - risk_tags: `local-write`、`undo`
    - capabilities: `manual-ui`、`qa-probe`
    - runtime_route: `simulator-or-physical-device`
    - driver: `game-test`
    - tier: `core`
    - seed: `none`
    - inspect: `accounting.fixture-summary`
    - evidence: `manual-ui`、`qa-probe:fixture-summary`
- **範圍:**
    - 建立交易並復原刪除。
- **規格依據:**
    - `RecordingCore.create`
- **前置狀態:**
    - 已有帳戶與支出類別。
- **操作步驟:**
    - 開啟交易編輯器。
    - 輸入金額與分類。
    - 儲存後刪除交易。
    - 執行 Undo。
- **檢查點:**
    - **交易寫入正確**
        - 層: 本地資料 ／ 手段: qa-probe
        - 取證時點: 交易復原後
        - 實作錨: `src/services/transactionLogic.ts`
```

上述節錄示範 metadata 與檢查點語法。可照做的完整內容使用[內容範本](test_step_template.md)及[改寫範例](test_step_examples.md)。

---

## 格式約束

- feature link 使用穩定功能鍵。
- risk tag 使用小寫連字。
- capability 必須存在於側寫。
- seed scene 必須存在於 QA allowlist。
- inspect check 必須存在於 QA allowlist。
- expected evidence 必須可取得。
- case 可引用 `受阻` 手段。
- `test-run` 必須在執行前停止。
- 結構化阻斷場次必須在 first operation 前停止。
- 測試定義不得混入執行結果。
