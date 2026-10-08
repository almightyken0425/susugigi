# Test Plan Writer

## 適用範圍

- 只處理 ai-company 產品的 Quality 定義與選案工作。
- 測試計劃、回歸等一般用語不單獨構成啟動條件。
- 目前目錄不能代替任務的實際目標。
- 沿用本次任務已確認的產品與模組範圍。
- 身分未確認時依產品決策路由的目標解析處理。
- 解析來源為 `~/.agents/skills/product-scope/SKILL.md`。
- 唯讀選案不進入產品修改前檢查。
- 範圍外的任務退出本技能並續做原任務。
- 不要求外部專案補 Product Map 或 Quality。
- 技能維護與一般測試討論不執行產品路由。

---

## 職責

- 維護 Quality 的測試定義。
- 建立與更新測試計劃。
- 維護能力契約與場次腳本。
- 執行 refresh 與 selector。
- 實際測試交給 `test-run`。
- 執行證據只留 session。

---

## 路由

- 完成範圍確認後才讀產品註冊表與解析品質責任。
- 固定使用 Quality owner resolver。

    ```bash
    python3 ~/.codex/scripts/quality_owner_resolver.py --product <Product> --module <module> --json
    ```

- resolver context 提供 `owner`。
- resolver context 提供 `quality_path`。
- resolver context 提供 `source_modules`。
- `quality_path` 是唯一 Quality 承載位置。
- `source_modules` 是共享 owner 的完整輸入範圍。
- 產品註冊表是 owner 唯一真相。
- 完整 owner 指向 Quality 承載位置。
- 同產品跨 module 使用解析後的位置。
- 跨產品 owner 一律 fail-closed。
- 共享 owner 的 plan 必須涵蓋全部 `source_modules`。
- 共享 owner 的 refresh 必須涵蓋全部 `source_modules`。
- 禁止只取本次呼叫的單一 module。
- 禁止猜測同名 module 的 Quality repo。
- 禁止搜尋鄰近 Quality repo 代替解析。
- `quality_owner` 為 `none` 時停止本技能的 Quality 流程。
- 停止時回報 `QUALITY_NOT_APPLICABLE`。
- 不因此阻止原專案可獨立執行的測試。
- 缺少 `quality_owner` 時 fail-closed。
- owner 懸空時 fail-closed。
- owner 無有效 Quality 層時 fail-closed。
- owner 無 Quality repo 時 fail-closed。
- 解析失敗時回報 `QUALITY_OWNER_INVALID`。
- 只有定義變更才開 Quality worktree。
- 純選案不修改 Quality。

---

## 執行分界

- `test-define` 定義測什麼。
- `test-define` 定義如何選案。
- `test-run` 決定本次類型。
- `test-run` 決定本次深度。
- `test-run` 解析 App session 路由。
- `test-run` 執行選中的測項。
- `test-ios` 管理已解析 simulator。
- `test-run` 管理已解析實機。
- 測試結果不寫回 Quality。
- 缺陷紀錄不寫回 Quality。

---

## Selector

- `branch-diff`
    - 依候選差異選出影響測項。
    - 無映射差異必須回報。
- `core-regression`
    - 選取 `core` tier 測項。
- `impacted-plus-core`
    - 合併差異與核心測項。
    - 重複 case 只保留一次。
    - 不代表 `standard` 深度。
- `feature`
    - 由 `test-run` 直接選案。
    - 先取得 branch diff。
    - 再解析 Product Map mapping。
    - 依 metadata 任一交集選案。
- `full-regression`
    - 由 `test-run` 直接選案。
    - 選取全部適用測項。
- selector 結果只留 session。

---

## Tier

- `core`
    - 核心健康度必驗。
- `standard`
    - 一般功能與整合風險。
- `extended`
    - 低頻或高成本邊界。
- 每個 case 只能有一個 tier。
- regression `core` 只選 core。
- regression `standard` 選：
    - core
    - standard
- regression `extended` 選全部。

---

## 基線

- 每個上游都記完整 commit。
- 每個上游都記完整 tree SHA。
- Quality 也記完整 commit。
- Quality 也記完整 tree SHA。
- SHA 必須是完整 Git object id。
- refresh 完成後才推進基線。
- 部分更新不得推進基線。

---

## 完成條件

- 每個 case metadata 齊全。
- 每個手段都有能力契約。
- 新增或改寫的內容符合六項撰寫要求。
- 操作、取證需求與本次分工分開。舊角色欄不作執行限制。
- 每個 selector 可重現結果。
- Quality digest 可重算。
- case-set digest 可重算。
- 全部 Markdown 通過 linter。
- 唯讀檢核器通過 selftest。

---

## 參考主題

- [測試步驟撰寫方法](test_step_authoring.md)。新增或改寫操作內容時使用，包含六項要求、內容範本與改寫範例。
- [計劃格式](plan_format.md)
- [能力側寫](capability_profile.md)
- [場次腳本](run_script_format.md)
- [產出與 selector](generation_procedure.md)
- [refresh 與 digest](maintenance_procedure.md)

---

## 硬邊界

- 上游只做唯讀查詢。
- 計劃檔維持手工可讀。
- 唯讀檢核器可以落地。
- 檢核器不得改寫計劃。
- fixture 不得含帳密。
- Production 資料不可寫入。
- Quality 不承載 session evidence。
