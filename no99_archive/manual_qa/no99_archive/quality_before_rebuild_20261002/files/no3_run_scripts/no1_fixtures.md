# Fixture 資料集

## 定位

- 本檔為場次腳本字面值的唯一權威
- 腳本 inline 寫死字面值，改值先改本檔、再 grep 舊值同批更新腳本
- 日期一律相對日期，如本月 5 日；CSV 檔因格式必須為絕對日期，腳本只斷言筆數不斷言期間
- 帳密不落檔，sandbox 帳號一律使用者自填
- 格式與政策由 `test_plan_writer` 的場次腳本格式承載

---

## Machine-readable golden

- `no1_fixture_golden.json` 是 runner 獨立對帳的機器可讀權威
- 頂層 exact keys 固定為 `schema`、`scenes`、`firestoreProfiles` 與 `sqliteProfiles`
- `scenes` 只登記 `r02_end` 與 `r09_stale_schedule`
- 每個 scene 固定 fingerprint、必要 fact keys、計數、signature id、獨立 profile 與關係
- `signatureIds` 以 exact fact key 對應固定 rule id，只作 candidate consistency evidence
- candidate signature 不得單獨決定場次通過
- `r02_end` final 必須通過獨立 `r03_initial_backup` Firestore profile
- `r09_stale_schedule` final 必須通過獨立 `r13_schedule_backfill` SQLite profile
- 每個會進入 remote 對帳的 scene 都要求 global session UID 在 prepare 前完成綁定，且 exact UID subtree 已通過 post-delete absent probes
- `firestoreProfiles` 只登記安全場次的六個可執行 checkpoint
- R10、R11 與 R12 永久受阻，不得登記 executable Firestore profile
- `sqliteProfiles` 登記 R08 的原語系 private baseline 與 R13 的獨立本機聚合規則
- runner 必須逐項比對 golden，不接受候選 RESULT 的 `verdict=pass` 作為唯一證據
- open-app 後的 initial backup 不得因 device cooldown 被跳過
- golden 不得包含 raw uid、OS 絕對路徑、隨機 requestId、shell 指令或 SQL
- JSON schema 封閉，未知 key、未知 profile、缺欄或型別不符一律 fail-closed

---

## 計數紀律

- 購買前全程 LEVEL_0：活躍帳戶壓 3 內、類別總數壓 7 內
- 軟刪除排除計數、停用仍計數
- 名額調度：R07 刪除銀行釋放帳戶名額、刪除醫療釋放類別名額
- R10 補建實體湊滿閘控計數、購買解鎖後再建超額實體

---

## 帳戶清單

| 名稱 | 幣別 | 建立場次 | 命運 | 服務測項 |
| --- | --- | --- | --- | --- |
| 錢包 | TWD | R01 預設現金，R02 改名 | 全程存活 | RC-01、RC-03、RC-07、HD 各項 |
| 銀行 | TWD | R01 預設信用卡，R02 改名 | R07 停用後刪除 | RC-03、RC-07、LD-03、EN-04、HD-06 |
| 日幣帳戶 | JPY | R02 | 全程存活 | EN-03、RC-03、CU-03、CU-04、CU-05 |
| 現金備用 | TWD | R10 | 湊滿閘控計數 | PM-04 |
| 投資 | TWD | R10 | 解鎖後建立 | PM-04 |
| 悠遊卡 | TWD | R10 | 匯入新建 | AS-05 |

---

## 類別清單

| 名稱 | 類型 | 建立場次 | 命運 | 服務測項 |
| --- | --- | --- | --- | --- |
| 餐飲 | 支出 | R01 預設 | 全程存活 | RC-01、HD-03、CS-04 |
| 交通 | 支出 | R01 預設 | 全程存活 | HD 各項 |
| 娛樂 | 支出 | R02 | R07 併入購物後復原、EN-04 停用 | RC-07、EN-04 |
| 購物 | 支出 | R01 預設 | 全程存活 | RC-07、HD-06 |
| 醫療 | 支出 | R02 | R07 刪除 | LD-03、HD-05 |
| 薪資 | 收入 | R01 預設 | 全程存活 | HD-03 |
| 獎金 | 收入 | R01 預設刪除，R02 重建 | 全程存活 | EN-01、HD-01 |
| 訂閱費 | 支出 | R10 | 湊滿閘控計數 | PM-04 |
| 禮金 | 收入 | R10 | 解鎖後第 8 類別 | PM-04 |
| 教育 | 支出 | R10 | 匯入新建 | AS-05 |

---

## 交易組

| 名稱與備註 | 類別 | 帳戶 | 金額 | 日期 | 服務測項 |
| --- | --- | --- | --- | --- | --- |
| 早餐 | 餐飲 | 錢包 | 123 | 本月 5 日 | RC-01、RC-02 |
| 薪資入帳 | 薪資 | 銀行 | 50000 | 本月 1 日 | HD-03 |
| 獎金入帳 | 獎金 | 銀行 | 5000 | 上月 25 日 | HD-01、HD-03 |
| 計程車 | 交通 | 錢包 | 350 | 本月 3 日 | HD-03、HD-04 |
| 電影 | 娛樂 | 錢包 | 300 | 本月 8 日 | RC-07 |
| 網購 | 購物 | 錢包 | 1500 | 上月 12 日 | RC-07、HD-01 |
| 診所 | 醫療 | 錢包 | 500 | 前月 20 日 | LD-03、HD-05 |
| 露營裝備 | 購物 | 錢包 | 3500 | 本月 10 日 | HD-06 |
| 露營餐費 | 餐飲 | 銀行 | 800 | 本月 11 日 | HD-06 |

- 錢包使用 TWD 預設零位小數。RC-01 先選錢包，再以計算機輸入 100 加 23 按等號得 123 並儲存早餐
- RC-02 重新打開已儲存的早餐。確認帶入 123 後改為 150。備註改為前後各帶一個空白的早餐改過，再儲存並確認空白已去除
- 儲存前把 123 改成 150 不算完成 RC-02 的已存交易編輯驗證
- 露營兩筆備註皆含關鍵字露營，銀行側供停用後排除驗證

---

## 轉帳組

| 來源 | 目標 | 轉出 | 轉入 | 日期 | 服務測項 |
| --- | --- | --- | --- | --- | --- |
| 錢包 | 銀行 | 2000 | 2000 | 本月 6 日 | RC-03 |
| 錢包 | 日幣帳戶 | 1000 | 4400 | 本月 7 日 | RC-03、CU-05 |

- 跨幣轉帳隱含匯率 4.4，RC-03 改轉入為 4500
- R03 incremental golden 固定驗 2000→2000 與 1000→4500 兩組 live transfers
- R03 incremental golden 固定驗十筆 live transactions、兩筆 live transfers 與兩路零額外 live row

---

## 匯率

- 日幣帳戶建立後 JPY 對即 CU-03 的佔位匯率對
- CU-04 編輯為 1 TWD 兌 4.6 JPY

---

## 偏好值組

| 項 | 值 | 服務測項 |
| --- | --- | --- |
| 主題 | theme2 套用、theme3 取消 | AS-02 |
| 啟動模式 | 支出，驗畢還原首頁 | AS-03 |
| 語系 | 日本語，驗畢還原 | AS-04 |
| 時區 | Asia/Tokyo，驗畢還原 | AS-04 |
| 週起始日 | 週一，驗畢還原 | AS-04 |
| 主要貨幣 | USD，驗畢還原 TWD | CU-01、CS-01 |

---

## CSV assets

| 檔 | 列數含表頭 | 特徵 | 服務測項 |
| --- | --- | --- | --- |
| `assets/import_small.csv` | 11 | 既有與新帳戶類別、一列金額 99999999999 超上限 | AS-05 |
| `assets/import_bad.csv` | 4 | 一列金額空值，驗欄位對應阻擋 | AS-05 |
| `assets/import_quota.csv` | 2101 | 全掛錢包餐飲，耗盡當日寫入配額 | CS-04 |

- 欄位序照匯入範本：transaction_datetime、category、account、amount、currency、note
- import_quota.csv 產生配方

```python
out = ["transaction_datetime,category,account,amount,currency,note"]
for i in range(2100):
    day = (i % 28) + 1
    out.append(f"2026-07-{day:02d} {i%24:02d}:{i%60:02d}:00,餐飲,錢包,{(i%500)+1},TWD,配額列{i+1}")
```

---

## 大型歷史資料組

- exact marker 為 `__SUSUGIGI_QA_R06_LARGE_HISTORY_V1__`
- overlay 只新增當前 QA user 的 marker rows
- overlay 不刪除或改寫原狀態鏈資料
- Load 未確認離線時立即失敗
- Load 寫 marker 前先暫停同步
- Load 等待既有 in-flight sync 完成
- 暫停狀態需持久化
- restart hydrate 後禁止啟動 sync
- sync snapshot 排除 exact marker
- sync push 排除 exact marker
- marker 前綴或後綴不得被排除
- Remove 不受網路狀態限制
- Remove 只清除 overlay marker rows
- Remove 完成前驗 marker rows 歸零
- marker 歸零後才釋放同步
- Load 失敗清理完成後釋放同步
- Remove 失敗時保持同步暫停
- cleanup 成功後才恢復網路
- 固定生成二萬筆交易
- 固定生成四百筆轉帳
- 全部資料皆為測試假資料
- 不引用個人匯入資料
- 支出交易共一萬筆
- 每筆支出金額為一百
- 收入交易共一萬筆
- 每筆收入金額為一百
- 轉出與轉入各兩百筆
- 每筆轉帳金額為五十
- 轉帳來源與目標帳戶同幣別
- 支出金標為一百零一萬
- 收入金標為一百零一萬
- 紀錄數金標為二萬零四百
- 期間餘額金標為零
- 日期跨度固定一千八百二十五天
- 日期分布依生成索引決定
- inspect probe 驗完整 shape
- inspect probe 驗全部金標
- shape drift 不得命中 idempotent fast path
- currency drift 不得命中 idempotent fast path
- 測試粒度使用全部
- 頁面筆數由測試輸入
- 服務測項為 HD-07

---

## 場內臨時值

- 為驗某檢查點而建、當場或次場即還原的產物
- 不進帳戶清單與交易組，但值同受本檔管轄

| 對帳鍵 | 值 | 場次 | 用途 | 命運 |
| --- | --- | --- | --- | --- |
| 增量備份 | 交易 餐飲 錢包 200 | R03 | CS-03 的增量變更來源 | 留庫至 R12 |
| 排程測試 | 排程 早餐 餐飲 錢包 100 | R04 | RC-04 建立後即撤銷 | 當場撤銷 |
| 閘控探針 | 交易 餐飲 錢包 100 與 轉帳 錢包 轉 現金備用 100 | R10 | PM-04 觸頂仍可新增 | 隨 R11 重裝清空 |

- 定期實例金額於 R04 改 200 驗範圍編輯、當場還原 150
- 類別 獎金 於 R01 預設建立，R02 先刪除再由 EN-01 正式流程重建
- 類別 交通 於 R02 暫改名為 餐飲 驗同名並存、當場還原
- 對帳鍵為 grep 用的唯一字串，值欄為人讀敘述

---

## QA seed 場景

- `r02_end` 建置 R02 終點
- 主要貨幣為 TWD 901
- JPY 對 TWD 有佔位匯率
- 佔位匯率為一
- 佔位日期為一
- fixture-summary 驗完整內容
- fixture-summary 驗引用與 tombstone

- `r09_stale_schedule` 建置過期排程
- 排程頻率為 DAILY
- 排程起始日為上月 5 日
- 排程備註為早餐
- 排程類別為餐飲
- 排程帳戶為錢包
- 排程金額為 150
- seed 當下只有起始實例
- 缺口保留給冷啟 bootstrap
- 匯率含佔位、4.4 與 4.5
- 正向與反向匯率成對
- 4.5 的 updatedOn 較晚
- schedule-backfill 驗連續 due sequence
- schedule-backfill 驗唯一 instanceDate
- schedule-backfill 驗零 tombstone
- schedule-backfill 驗固定 fixture 語意
- schedule-backfill 不以排程列作唯一 template 權威
- schedule-backfill 驗 generated count

- `r06_large_history` 載入 additive overlay
- overlay 交易為二萬筆
- overlay 轉帳為四百筆
- overlay 日期跨度固定一千八百二十五天
- `accounting.large-history-overlay` 驗完整 shape 與金標

- `r06_large_history_cleanup` 清除 overlay
- cleanup 只刪 marker rows
- cleanup 驗交易 marker 歸零
- cleanup 驗轉帳 marker 歸零

---

## sandbox 帳號

- 帳密不落檔，執行當場由使用者自備登入
- **sandbox-buyer:** 購買與恢復成功路徑，帳號與密碼為使用者自填
- **sandbox-empty:** 查無購買路徑，帳號與密碼為使用者自填
- **方案:** 月度；sandbox 週期壓縮，約三十五分鐘走完六次續訂至到期

---

## R15 本機商店資料

R15 為獨立場次，不承接前面 R02 至 R08 的資料鏈。以下全部是本場假資料。App 使用繁體中文，三個基準帳戶均為 TWD，初始餘額為 0，時區在本場保持不變。

日期的「本日」以準備時的 App 日期固定下來，跨日續做仍沿用該日期。資料比對時把首頁期間設為「全」。

| 類型 | 名稱或內容 | 數量與用途 |
| --- | --- | --- |
| 基準帳戶 | 錢包、銀行、備用 | 3 個，均為 TWD。由本場預設帳戶改名及新增。 |
| 基準支出類別 | 餐飲、交通、購物、娛樂、醫療 | 5 個，均啟用。 |
| 基準收入類別 | 薪資、獎金 | 2 個，均啟用。加上支出類別共 7 個。 |
| 暫用帳戶 | 測試帳戶 4 | TWD，餘額 0，不掛任何交易或轉帳，供新增及刪除檢查。 |
| 暫用類別 | 測試類別 8 | 支出類別，不掛任何交易，供新增、停用與刪除檢查。 |

| 建立時點 | 紀錄 | 具體欄位 | 應否儲存 |
| --- | --- | --- | --- |
| 第 5 項準備 | 基準支出 | 金額 100、錢包、餐飲、備註 R15 原有支出、本日 12:00 | 是，保留到整場收尾。 |
| 第 5 項準備 | 基準轉帳 | 錢包轉銀行、轉出及轉入均 200、本日 12:05 | 是，保留到整場收尾。 |
| 第 8 項 | R15 等於上限支出 | 金額 10、錢包、餐飲、備註 R15 等於上限、本日 12:10 | 是，保留到整場收尾。 |
| 第 8 項 | R15 等於上限轉帳 | 錢包轉銀行、轉出及轉入均 20、本日 12:15 | 是，保留到整場收尾。 |
| 第 9 至 12 項的超額狀態 | 超額嘗試支出 | 金額 5、錢包、餐飲、備註 R15 超額嘗試、本日 12:30 | 否，升級頁關閉後放棄這次編輯。 |
| 第 9 至 12 項的超額狀態 | 超額嘗試轉帳 | 錢包轉銀行、轉出及轉入均 5、本日 12:35 | 否，升級頁關閉後放棄這次編輯。 |
| 第 12 項刪除類別後 | R15 刪除後支出 | 金額 15、錢包、餐飲、備註 R15 刪除後、本日 12:20 | 是，保留到整場收尾。 |
| 第 12 項刪除類別後 | R15 刪除後轉帳 | 錢包轉銀行、轉出及轉入均 30、本日 12:25 | 是，保留到整場收尾。 |

| 比對基準 | 支出筆數 | 轉帳筆數 | 錢包餘額 | 銀行餘額 | 備用餘額 |
| --- | --- | --- | --- | --- | --- |
| 月年購買前基準 | 1 | 1 | -300 | 200 | 0 |
| 第 8 項完成基準 | 2 | 2 | -330 | 220 | 0 |
| 第 12 項完成基準 | 3 | 3 | -375 | 250 | 0 |

- 編輯器輸入正的金額大小。餘額使用上表的帶正負號結果。
- 測試帳戶 4 存在時餘額始終為 0。新增或刪除它不影響其他帳戶。
- 商店重設、購買、還原及到期不應改寫帳目或餘額。
- 第 8 項與第 12 項成功新增會改變餘額。後續以新的基準比對，不要求維持最初金額。
- 停用測試類別 8 後仍計入總數，刪除後才從總數排除。
- 只在步驟指定時刪除未使用的測試帳戶 4 或測試類別 8。原有紀錄保留至本場收尾。
