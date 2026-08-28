# SuSuGiGi 匯入功能驗證測項

在 iOS simulator 手動驗 SuSuGiGi 的匯入功能，測資為 2026-06-03 從 Monefy 匯出的 `.db` + `.csv`，經 `monefy_export.py` 轉成 `transactions.csv` + `transfers.csv`。對帳基準是 Monefy app 的截圖——SuSuGiGi 匯入後對得上 Monefy 才算通過。

測的是 `feat/datamgmt-currency-fidelity`（branch 1）修正後的匯入，屬 JS-only，用 `/sim-review` 切到該 worktree 的 Metro 再驗。

## 範圍

- 驗交易匯入 + 轉帳匯入。
- 不在內：排程匯入（Monefy 無排程資料）、匯出、reset。
- 通過標準：匯入後 SuSuGiGi 每帳戶 native 餘額、抽查記錄、筆數、幣別，與 Monefy 截圖一致。

## 測資快照（2026-06-03 匯出，已抽出）

- 來源：`original_db_data/monefy-2026-06-03_11-11-06.csv` + `monefy_database-2026-06-03_23-11-49.db`
- 交易 17,206 筆、可匯入轉帳 282 筆（DB 共 317；其中 35 筆是已刪除帳戶之間的轉帳、不匯入，對現役帳戶零影響）、日期 2015-12-31 → 2026-06-03
- 資料保真已驗：export 腳本經 Smart Match 從 raw CSV 撈跨幣別轉帳的實際轉入金額（不再用匯率估算），`diff_check.py` 對六月資料 zero-discrepancy（17,770＝17,770）；每帳戶餘額算出來與 Monefy 全對、0 帳戶有差
- 8 幣別全在 `Currency.json`：TWD / USD / IDR / PEN / THB 為 2 位小數；JPY / KRW 為 0 位小數；MYR 2 位、僅 馬幣 帳戶在轉帳用
- 17 帳戶（初始餘額 `InitialBalanceCents` 皆 0）、33 類別

## 每帳戶餘額對帳基準

native 幣別。因初始餘額皆 0，此表等於 Monefy 顯示餘額，也是 SuSuGiGi 匯入後應有的餘額。

| 帳戶 | 幣別 | 應有餘額 |
|---|---|---|
| One | TWD | 201,628 |
| Two | TWD | −124,297 |
| 借錢 | TWD | −528,467 |
| 台股 | TWD | 18,053 |
| 寶包 | TWD | −1,940 |
| SuGi | TWD | −4,186 |
| 婚禮 | TWD | 0 |
| 虛幣 | TWD | 0 |
| 日円 | JPY | 25,946 |
| 韓元 | KRW | 30,200 |
| 美股 | USD | 91,323 |
| 美幣 | USD | 344 |
| 鎂薪 | USD | 0 |
| 印鈔 | IDR | 0（浮點 ≈0.01） |
| 泰錢 | THB | 211 |
| 馬幣 | MYR | 300 |
| 魯幣 | PEN | 0 |

## 前置

- **P1（已完成）**：跑 `monefy_export.py` 產生 `export_data/transactions.csv`（17,206）、`transfers.csv`（282）。
- **P2**：`/sim-review` 切 Metro 到 `feat/datamgmt-currency-fidelity` worktree（約 30 秒），讓 simulator 跑修正後匯入。
- **P3**：把 `transactions.csv` 與 `transfers.csv` 拖進 simulator 視窗，選 Save to Files → On My iPhone。
- **P4**：SuSuGiGi → 設定 → 資料管理 → 清除資料庫 → 重啟 app，得到乾淨起點。注意重啟後 `createInitialUserData` 會自動建 1 個預設現金帳戶 + 標準類別；對帳時略過該預設帳戶。
- **P5**：在 Monefy 截圖（見下）。

## Monefy 要截的圖

- **M-1**：Monefy 帳戶列表，每個帳戶餘額看得到——主對帳依據。
- **M-2**：抽查記錄明細（TC-5～TC-7 那幾筆），每筆含日期、金額、類別、帳戶、幣別、備註。
- **M-3（選）**：某月類別報表，做類別小計抽查。
- 不要拿 Monefy 總餘額對 SuSuGiGi 總額，原因見「已知不對帳項」。

## 測項

### 功能類：精靈走通

**TC-1 交易匯入精靈** — 資料管理 → 匯入收入支出 → 選 `transactions.csv`

- 步驟 2 自動把 `transaction_datetime` / `category` / `account` / `amount` / `currency` / `note` 對到正確欄，多出的 `is_virtual`、`is_ignored` 被忽略，首列預覽正確。
- 步驟 3 列出 16 帳戶、33 類別，新項預設 Create。
- 步驟 4 與成功對話框：**added = 17,205、skipped = 1**。
- 那 1 筆 skip 是資料瑕疵 `2023-11-01 日円 補給 0.005 JPY`——0.005 在 0 位小數幣別 round 成 0、被「金額不可為 0」規則擋掉，屬預期、非 bug。
- 通過：added = 17,205、skipped = 1。

**TC-2 轉帳匯入精靈** — 匯入轉帳 → 選 `transfers.csv`

- 步驟 2 自動對 `transfer_datetime` / `from_account` / `from_currency` / `from_amount` / `to_account` / `to_currency` / `to_amount` / `note`，忽略 `exchange_rate`、`rate_type`。
- 步驟 3 帳戶清單含只在轉帳出現的 馬幣。
- 成功：**added = 282、skipped = 0**。
- 通過：added = 282、skipped = 0、馬幣 帳戶被建立。

### 資料類：對帳

**TC-3 帳戶與幣別** — 匯入後看帳戶列表

- 17 個 Monefy 帳戶都在（外加 1 個預設現金帳戶），幣別符合上表：日円=JPY、韓元=KRW、印鈔=IDR、魯幣=PEN、泰錢=THB、美股/美幣/鎂薪=USD、馬幣=MYR、其餘 TWD。
- 對 M-1。通過：帳戶 17 個 + 幣別全中。

**TC-4 每帳戶餘額對帳（核心）** — 逐帳戶比對 SuSuGiGi vs Monefy（M-1）vs 上表

- 通過：17 帳戶 native 餘額全相符，容許 ±0.01 浮點。

**TC-5 JPY/KRW 非 100 倍（branch 1 修正重點）**

- 日円 帳戶餘額 = ¥25,946，不是 ¥2,594,600；韓元 = ₩30,200，不是 ₩3,020,000。
- 抽查 日円 `2023-11-05 一起 −¥1,700 特急車車` → 顯示 −¥1,700，非 −¥170,000。
- 抽查 韓元 `2024-06-13 五金 −₩115,000 棉被` → 顯示 −₩115,000，非 −₩11,500,000。
- 對 M-1 + M-2。通過：JPY/KRW 餘額與抽查皆非 100 倍。

**TC-6 跨幣別轉帳**

- 抽查 `2026-05-07 美幣 250.00 USD → 泰錢(THB)`、`2026-01-14 美股 5,706.00 USD → One(TWD)`。
- 對 M-2。通過：兩腿金額與幣別與 Monefy 一致，轉入金額不會被退回成等於轉出。

**TC-7 個別記錄抽查**

- 在 Monefy 任選 3 筆不同帳戶/幣別交易，含最近 2026-06-03 一筆，在 SuSuGiGi 搜尋同筆，比對日期、金額、類別、帳戶、幣別、備註六欄。
- 對 M-2。通過：每筆六欄全中。

**TC-8 日期（注意時區）**

- 抽查記錄日期是否落在 Monefy 同一天。
- 時區自選功能尚未做（後續 branch）；目前匯入用裝置時區解析 date-only 午夜。若 simulator 裝置時區與資料時區一致應對得上；若少數午夜記錄差一天且集中在時區差，記為時區待修、不算匯入失敗。

## 已知不對帳項（先說清楚、不算失敗）

- **總餘額別對**：Monefy 多數帳戶 `IsIncludedInTotalBalance=0`、不列入總額，SuSuGiGi 匯入不帶此旗標、全列入；加上多幣別換算（reset 已清匯率，外幣吃 1:1 佔位或被轉帳隱含匯率填）。所以只對「每帳戶 native 餘額」，不對「換算後總額」。
- **預設現金帳戶**：reset 重啟自動生、餘額 0、與 Monefy 無關，略過。
- **類別小計**：Monefy 類別名若與標準預設同名會併入同類，可能讓類別小計偏差；以每帳戶餘額為準。

## 通過判定

TC-1～TC-8 全過、且所有差異都落在「已知不對帳項」→ 匯入驗證通過。
