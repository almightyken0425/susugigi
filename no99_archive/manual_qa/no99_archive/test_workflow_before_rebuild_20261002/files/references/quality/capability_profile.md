# 能力側寫

## 定位

- Quality 保存能力契約。
- session 保存就緒結果。
- 能力 id 是 case 引用鍵。
- 一個 owner 維護一份側寫。
- 跨 module 共用 owner 側寫。

---

## 能力契約

- 每個能力必填：
    - 手段 id
    - 說明
    - 定義狀態
    - 操作需求
    - 環境前提
    - 零副作用探測
    - 成功條件
    - 限制
- 定義狀態只有：
    - `可用`
    - `受阻`
- `受阻` 必須寫解除條件。
- 探測結果不得寫回 Quality。

操作需求使用 `ui`、`device-ui`、`tool` 或 `unavailable`。
它們分別代表畫面操作、實體裝置操作、工具或命令，以及尚無可用路徑。
`unavailable` 只能搭配 `受阻`。受阻能力仍可宣告已知的操作需求。
能力表不保存固定操作者。當次誰執行與能否執行，依[執行分工](execution_assignment.md)記在 session。

舊能力表的 `執行者` 欄只供格式相容讀取，不作本次分配依據。
遷移時改為 `操作需求`，並保留環境、成功條件與限制。

---

## 必備能力

- `manual-ui`
    - 操作需求為 `ui`。沿用既有 id，不表示限定使用者操作。
    - 依本次分工完成手勢與畫面觀察。
- `manual-device`
    - 操作需求為 `device-ui`。須核對當次實機操作能力。
    - 環境前提包含 log 通道。
    - 環境前提包含 DB 通道。
    - 實機 session preflight 必須取得。
    - `simulator-or-physical-device` 不必引用。
- `jest-app`
    - 操作需求為 `tool`。
    - 執行 App 自動測試。
- `jest-backend`
    - 操作需求為 `tool`。
    - 執行後端自動測試。
- `qa-command`
    - 操作需求為 `tool`。
    - 呼叫 QA allowlist 指令。
    - 只允許 QA build。
- `qa-probe`
    - 操作需求為 `tool`。
    - 讀取 QA 證據。
    - probe 必須唯讀。
- `qa-markers`
    - 操作需求為 `tool`。
    - 從 Metro log 讀標記。
- `firestore-read`
    - 操作需求為 `tool`。
    - 讀取隔離 QA 資料。
- 不適用能力可省略。

---

## QA command 契約

- 契約必須列出：
    - command id
    - 允許的 scene
    - 身分隔離條件
    - 寫入範圍
    - 成功 marker
    - 失敗 marker
- command 不在 allowlist 時拒絕。
- 使用者身分空白時拒絕。
- Production build 必須無命令入口。
- Firebase 隔離未確認時拒絕。

---

## QA probe 契約

- 契約必須列出：
    - check id
    - 可用 scene
    - 查詢範圍
    - expected evidence
    - 成功 marker
    - 失敗 marker
- probe 只能讀取。
- 每個查詢必須限制使用者。
- probe 不在 allowlist 時拒絕。
- scene 與 check 不相容時拒絕。

---

## Production 隔離契約

- 側寫必須定義隔離探測。
- 探測至少驗證：
    - Production 無 QA command。
    - Production 無 QA probe。
    - Production 無 Debug UI。
    - QA bundle id 已隔離。
    - QA Firebase 設定已隔離。
- 任一項不成立即 `受阻`。
- Production 隔離能力是硬閘門。

---

## 執行規則

- `test-run` 先收集選案能力。
- Quality case 可引用 `受阻`。
- 選案引用 `受阻` 時停止。
- 選案缺能力定義時停止。
- 每個能力都要執行探測。
- 探測未通過時停止。
- 停止發生在第一個 case 前。
- 改派操作者不得替代缺失能力或必要證據。
- 環境可用與操作者可用分開查核。Xcode 存在不代表 AI 可操作畫面。
- 就緒證據只留 session。

---

## 維護規則

- 能力介面改變時更新側寫。
- command allowlist 改變時更新。
- probe allowlist 改變時更新。
- Production 隔離改變時更新。
- 同 branch 更新受影響 case。
- 機器狀態變化不修改側寫。
