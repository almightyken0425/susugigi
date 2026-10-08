# 測試協調與判定

## 適用範圍

- 只協調 ai-company 產品的 Quality 測試流程。
- 一般測試用語與最少手動操作要求不單獨構成啟動條件。
- 沿用任務已確認的產品與模組範圍。
- 身分未確認時依產品決策路由的目標解析處理。
- 解析來源為 `~/.agents/skills/product-scope/SKILL.md`。
- 範圍外的任務退出本技能並依原專案方式測試。
- 不要求外部專案建立 Product Map、Quality 或 Release。
- 維護技能與討論測試方法不執行本流程。
- 明確呼叫技能但目標不清時只釐清必要的目標。
- 不把不適用本技能回報成整個測試任務受阻。

---

## 職責

- 協調實際測試執行。
- 使用 Quality 的測試定義。
- 使用 Release 的候選 manifest。
- 自動蒐集 log、DB 與 Jest。
- 依本次能力與使用者偏好分配操作。
- Simulator App 委派 `test-ios`。
- 實機 App 由本技能伴跑。
- 執行證據只留 session。

---

## 啟動決策

- 先依 `test-define` 的路由解析品質責任。
- 該路由定義於 `~/.agents/skills/test-define/SKILL.md`。
- 保留解析結果的 `owner`、`quality_path` 與 `source_modules`。
- 品質流程不適用時回報原因並改用原專案可用的測試方式。
- 替代驗證不得宣稱通過本流程的 Quality 或 Release 閘門。
- 品質責任解析失敗時停止依賴該資料的測試。
- 既有選案與測試授權不因入口解析而重問。
- 先讀 branch diff。
- 先讀 Product Map 影響。
- 先讀 Quality 定義。
- 提出測試類型建議。
- 提出建議的原因與風險。
- 沿用使用者已確認的類型。尚未選定且會改變驗證範圍時，先提出具體建議。
- 類型只有：
    - `feature`
    - `regression`
- `feature` 不詢問回歸深度。
- `regression` 才建議深度。
- 沿用已確認深度。缺少深度且影響驗證範圍時才請使用者選定。
- 深度只有：
    - `core`
    - `standard`
    - `extended`

---

## 建議規則

- 單一新功能優先 `feature`。
- 發布前健康檢查建議 `core`。
- 一般候選版本建議 `standard`。
- 資料模型異動建議 `extended`。
- 跨 module 契約異動建議 `extended`。
- 安全或付款異動建議 `extended`。
- 使用者明示差異選案時：
    - 使用 `branch-diff` override。
    - override 不改回歸深度語意。

---

## 選案路由

- `feature`
    - 先執行 branch diff。
    - 再解析 Product Map mapping。
    - 依功能鍵或風險標籤選案。
    - 加入必要相依 case。
- `regression core`
    - 選取 `core` tier。
- `regression standard`
    - 選取 `core` tier。
    - 選取 `standard` tier。
- `regression extended`
    - 直接選取全部適用 case。
- `branch-diff` selector override
    - 呼叫 `branch-diff` selector。
- `impacted-plus-core` selector override
    - 呼叫 `impacted-plus-core` selector。
- selector override 不代表回歸深度。
- override 必須由使用者明確選擇。
- `standard` 不等同差異選案。
- selector 由 `test-define` 定義。
- 缺少 feature mapping 時停止。
- 缺少 selector mapping 時停止。

---

## Selector 身分

依已確認 owner 的身分契約正規化 selector。SuSuGiGi 使用 `<已鎖定 Quality 根目錄>/no3_run_scripts/control_adapter/identity_contract.md`。
不另存 selector 欄位定義。

## 候選與環境交接

先核對 [iOS 環境入口](ios_execution.md) 的受支援 profile。
SuSuGiGi 功能測試交接只讀 `<已鎖定 Quality 根目錄>/no3_run_scripts/control_adapter/handoff_contract.md`。
候選、Quality 與 Control 來源都要鎖定。由接收者重算並建立私有副本。
未知 profile 不套用這份產品契約，未支援 runner 的測項保留 blocked。
只讀測試計畫不能產生執行證據。定義不足回 test-define，環境缺口回 test-ios。

## 執行順序

- 先執行靜態檢查。
- 靜態檢查必須執行 Quality 的 `check_plan.sh --runtime-control <已選定 Control 根目錄>`。
- 同次提供 `--impl` 與 `--backend`，涵蓋 Quality owner 的全部 source modules。
- 跨層 runtime 行為驗證必須通過，缺少實際入口時不得以文字契約代替。
- 再執行 Jest。
- 再準備 QA App 環境。
- 依[執行分工](execution_assignment.md)核對操作者與取證能力。
- 再執行 no-write capability bootstrap。
- 再準備 QA fixture。
- 再執行 App 測項。
- 再讀 inspect 與 DB。
- 再核對 log marker。
- 破壞性測項排在最後。
- 每個 case 完成才進下一個。
- 必要證據不足時不得判定 pass。

---

## 授權邊界

- 執行授權包含：
    - 讀取 log
    - 讀取隔離 QA DB
    - 執行 Jest
    - 呼叫唯讀 probe
    - 核對 commit 與 digest
- QA seed 需通過能力閘門。
- QA seed 只寫隔離 QA 身分。
- Production 僅允許唯讀身分查核。
- 測試 session 不修改 code。
- 測試 session 不修改 Quality。
- 測試 session 不修改 Release。
- `test-run` 不建立持久 commit。
- `test-ios` 可建立 transient commit。
- transient commit 必須在同次委派還原。
- 測試 session 不 merge。
- 測試 session 不 push。

---

## Simulator 委派

把已核對候選、選集及所需證據交 test-ios。
一併交出目前分工、使用者要看的停點與接手位置。
Payload 欄位、阻斷場次與執行順序依同一份產品交接契約。
不重問已有答案，不把未通過身分核對的場次交給 runner。

## 實機 App case

- 已解析的實機 session 不委派。
- 實機 session 由 `test-run` 伴跑。
- preflight 必須取得 `manual-device`。
- `manual-device` 受阻時停止。
- 建立 `manual-device` checkpoint。
- checkpoint 必填：
    - device identity
    - installed build identity
    - target identity
    - Quality identity
    - case IDs
    - manual steps
    - log channel
    - DB evidence channel
- 沿用本次實機操作者。使用者操作時一次只提示一組動作。
- 每組操作前核對同一 QA iPhone。
- 操作完成後自動讀 log。
- 操作完成後自動讀 DB。
- 必要能力缺失時標 `blocked`。
- blocked case 不可假裝完成。
- 實機結果不得套用 simulator 證據。

---

## 操作、取證與檢視

依[執行分工](execution_assignment.md)處理 AI 操作、使用者操作及中途接手。
既有使用者偏好持續有效。可自動取得的值不要求抄寫。
UI 結果使用當次可用的畫面觀察，不能用資料庫結果代替必要 UI 證據。
使用者主觀評價與客觀通過結果分開記錄。

---

## 證據判定

- 結果值只有：
    - `pass`
    - `fail`
    - `blocked`
    - `inconclusive`
- 每筆結果保留：
    - case ID
    - target kind
    - target identity
    - transient commit 與 tree
    - `qaFirebaseProjectId`
    - `qaGoogleAppId`
    - `qaFirebaseConfigSha256`
    - `qaIdentityMode`
    - Quality identity
    - Quality definition digest
    - case-set digest
    - evidence channel
    - expected value
    - observed value
    - result
    - blocker
    - 實際操作者與取證者
    - 使用者檢視或主觀評價，若本次有要求
    - dispose identity evidence
- 必要證據全符合才可 pass。
- 證據衝突時判定 fail。
- 執行中能力失效時判定 blocked。
- 證據不足時判定 inconclusive。

---

## Checkpoint

- 每輪保存：
    - test type
    - regression depth
    - selector override
    - resolved runtime route
    - target kind
    - target ref
    - target identity
    - transient commit 與 tree
    - `qaFirebaseProjectId`
    - `qaGoogleAppId`
    - `qaFirebaseConfigSha256`
    - `qaIdentityMode`
    - Quality identity
    - Quality definition digest
    - case-set digest
    - passed cases
    - failed cases
    - blocked cases
    - pending cases
    - next action
    - 本次分工與有效的使用者偏好
    - UI 操作者、畫面停點與接手位置
    - simulator state
    - device checkpoint
    - Metro source
    - restore state
- 續跑前重算全部身分。
- 任一身分改變即失效。
- 失效後重新執行前檢查。

---

## 完成回報

- 先回報整體結論。
- 回報類型與深度。
- 回報 resolved runtime route。
- 回報 target kind 與 identity。
- feature 回報 snapshot digest。
- release 回報 commit 與 tree。
- transient 身分只列 simulator 證據。
- 回報 `qaFirebaseProjectId`。
- 回報 `qaGoogleAppId`。
- 回報 `qaFirebaseConfigSha256`。
- 回報 `qaIdentityMode`。
- 回報 Quality 身分與 digest。
- 回報 case-set digest。
- 回報各結果數量。
- 回報失敗與阻塞 case。
- 回報使用的證據通道。
- 回報未覆蓋風險。
- 回報 simulator 與 Metro 狀態。
- 回報 git restore 狀態。
- 全部必要 case 通過後：
    - 才能建議候選版本可發布。
- Production gate 只接受 regression selector。
- feature session 不得通過 Production gate。
- session evidence 不寫回 Quality。
- 未完成結果不寫成 release truth。
