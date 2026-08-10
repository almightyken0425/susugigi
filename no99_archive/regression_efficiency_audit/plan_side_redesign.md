# 場次腳本層改造方案

## 這份方案的四條鐵律

動工前先把約束講死，後面每一項都受這四條管。

- **引句一個字都不改。** 已驗欄的引句只做整條搬移，不改寫、不截斷、不合併字面。要改字的一律改分冊那側的非引句欄位，`check_plan.sh` 的 `extract_assertions` 只抓 `    - **` 開頭的粗體行，層欄、驗證者欄、手段欄、前置欄、步驟欄全都抓不到，改它們不動對帳。
- **一條檢查點只掛一個手段。** 手段欄全 228 列皆單值，本方案維持這個不變式。要換手段就整條換掉、分冊同批換；要加第二個手段就另開一列佐證列、該列已驗留空，不把兩個手段塞進同一格。
- **合併儲存格禁用半形逗號。** 現行每列恰 9 個半形逗號分欄，`awk -F,` 取第 8 欄靠的就是這個。合併動作欄與預期欄一律用全形頓號與全形逗號串接，多值已驗欄一律用全形分號。
- **可證偽優先於省時。** 併列與延後只准發生在不改變斷言強度的地方。凡是併了會讓某個判準變模糊的，寧可多留一列。

---

## 逐場的新步驟表設計

### R00 靜態驗證 — 不動

18 列全為 Claude節點，零使用者步驟、零往返、零 manual-ui。步驟表本體一列不改。唯一變動在 `no0_index.md` 的場次總表，時長欄自單一值拆成人手與機器兩欄，見時長重估一節。

### R01 起始與身分 — 14 列降為 11 列

合併與刪除：原序 9 與 10 刪除、內容併入場尾；原序 11 與 12 併為一列；場尾新增一列承接 R03 搬來的 initial 模式觀測。

| 新序 | 對應原序 | 動作欄新內容 | 預期欄新內容 | 手段 | 驗證者 |
| --- | --- | --- | --- | --- | --- |
| 1 | 1 | 安裝舊版 build 並開啟、建立 TWD 帳戶測試帳戶、建立支出類別測試類別、再新增一筆金額 100 掛測試帳戶與測試類別的支出 | 帳戶列表出現測試帳戶、類別列表出現測試類別、首頁清單出現該筆 100 支出 | manual-ui | 使用者 |
| 3 | 3 | 不變 | 開啟不閃退、測試帳戶、測試類別與 100 支出完整可見 | manual-ui | 使用者 |
| 9 | 11 加 12 | 完全關閉 app、重新開啟並落地 | 不出現重試畫面、直接落地主畫面 | manual-ui | 使用者 |
| 10 | 9 加 13 | Claude 於 sim-review 導出的 Metro log 依序 grep QA BOOT anonymous signIn start、QA BOOT delegate、QA BACKUP probe、QA BACKUP mode、QA RCACHE lookup 五組列 | signIn start 恰三行、對應序 5 與序 6 與序 7 三次觸發、冷啟後無第四行；bootstrap delegate 每次落地各一組、無重跑；probe 列 remoteHasData=false 且 reads=1；全場 mode 列僅一行且為 mode=initial；兩段 QA RCACHE lookup 的 uid 值相同 | qa-markers | Claude |
| 11 | 10 加 14 | Claude 以 firestore-read 查 users 集合 | 恰一份文件、id 為新 uid、provider 為 anonymous、email 為空值、冷啟後仍恰一份且 id 不變 | firestore-read | Claude |

- 新序 10 的已驗欄以全形分號串接三條原引句，順序為 AU-02 重試收斂、AU-03 身分事件去重、CS-02 探測遠端無資料後進入 initial 模式
- 新序 11 的已驗欄以全形分號串接 AU-01 雲端 users 文件建立與 AU-03 沿用同 uid 兩條原引句
- 序 2、4、5、6、7、8 原文不動，序號順延為 2、4、5、6、7、8
- uid 一律取 `QA RCACHE lookup ... uid=` 或 `QA BACKUP start uid=`，QA BOOT 六個落點無一帶 uid，動作欄不得再寫 grep QA BOOT 比對 uid
- 序 10 不寫 signIn 單次發起。`ensureAnonymousUser` 的單飛守衛在 finally 清空，語意是每次觸發只發一顆，不是全場只印一行
- 手抄 uid 前八碼的動作全數刪除

### R02 實體與交易建置 — 22 列降為 18 列

合併與刪除：原序 1、8、18、19 由 seeder 一列取代；原序 12 與 13 併列；原序 21 與 22 併列；原序 20 改為只建一筆；場尾新增 sqlite-local 終點對賬列。

| 新序 | 對應原序 | 動作欄新內容 | 預期欄新內容 | 手段 | 驗證者 |
| --- | --- | --- | --- | --- | --- |
| 1 | 1 加 8 加 18 加 19 | 進設定頁點 Mock Data Settings、於 Regression Fixtures 區塊點 Seed R02 base、於確認對話框點 Seed | 顯示 Seeded R02 base 成功提示、類別列表出現餐飲、交通、娛樂、購物、醫療、薪資六類別、帳戶列表出現錢包與銀行、首頁出現七筆交易 | manual-ui | 使用者 |
| 11 | 12 加 13 | 回首頁點新增並選支出、以計算機鍵盤輸入 100 加 23.45 按等號 | 進入交易編輯器、必填欄位未妥時完成按鈕不可點按、按鍵結果即時顯示於金額輸入框、等號後顯示 123.45 | manual-ui | 使用者 |
| 16 | 20 | 新增收入、備註獎金入帳、金額 5000、類別獎金、帳戶銀行、日期上月 25 日 | 列表出現該筆、全場交易共九筆在案 | manual-ui | 使用者 |
| 17 | 21 加 22 | 完全關閉 app、斷網、重新開啟並逐一檢視首頁清單與帳戶管理 | 開啟不閃退、錢包、銀行、日幣帳戶三帳戶與九筆交易完整呈現、早餐金額 150、離線不影響讀取 | manual-ui | 使用者 |
| 18 | 新增 | Claude 以 query_local_db.sh 跑 scene R02-end 對賬 | 帳戶三筆為錢包 TWD、銀行 TWD、日幣帳戶 JPY；類別七筆；交易九筆且備註早餐改過金額為 150 的縮放整數；轉帳零筆；排程零筆；currency_rates 一筆為 TWD 對 JPY 的佔位列 | sqlite-local | Claude |

- 新序 11 的已驗欄以全形分號串接原序 12 與 13 兩條 RC-01 引句
- 新序 18 已驗留空，它不收檢查點，只把終點狀態的內容等價自人眼移到機器
- 序 2 至 7 原文不動、序號順延為 2 至 7；序 9、10、11 順延為 8、9、10；序 14 至 17 順延為 12 至 15
- 日幣帳戶必須留在 EN-03 的正式流程建立、不進 seeder。seeder 走 `collection.create` 直寫，繞過 `accountLogic` 的 `ensureRateForNewAccount`，不種佔位匯率，R05 的 CU-03 幣別對會查無
- 獎金必須留在 EN-01 的正式流程建立。seeder 一次鋪滿七類別會讓 EN-01 的新增被閘控擋下
- 本場相依 impl 新增 `r02_base` 場景，見手段改掛表的相依欄

### R03 備份啟動與匯出底線 — 16 列降為 11 列

合併與刪除：原序 3 與 4 刪除、內容分別搬到 R01 與本場場尾；原序 5、6、7 整段搬到 R12；原序 8 刪除。

| 新序 | 對應原序 | 動作欄新內容 | 預期欄新內容 | 手段 | 驗證者 |
| --- | --- | --- | --- | --- | --- |
| 2 | 2 | 不變 | 畫面不出現進度圈、進度條或同步中字樣；期間首頁可持續捲動、篩選 modal 可開可關、每次點擊都有畫面回應、無畫面凍住 | manual-ui | 使用者 |
| 7 | 13 | 將 app 退至背景、停留滿 5 分鐘後回前景並停留片刻 | 回前景後首頁自行重繪完成、期間標題仍為本月、無 Alert、無紅屏 | manual-ui | 使用者 |
| 8 | 14 | 不變 | 回前景後首頁照常顯示、無 Alert、無紅屏 | manual-ui | 使用者 |
| 9 | 15 | Claude 於同一份 Metro log 依序 grep QA BOOT delegate、QA BACKUP mode、QA BACKUP skip 三組列、涵蓋前兩步的兩次觸發 | 第一次見 delegate task=runBackup trigger=foreground 與其後的 mode 列 mode=incremental；第二次見 skip reason=cooldown；全場無 mode=initial 列 | qa-markers | Claude |
| 10 | 16 | Claude 以 firestore-read 查該 uid 下六個 collections | accounts 3 筆、categories 7 筆、transactions 10 筆且含備註早餐改過金額 150 那筆與備註增量備份金額 200 那筆、transfers 2 筆含轉入 4500、schedules 0 筆、currencyRates 含 TWD 對 JPY 的佔位列與跨幣轉帳補錄的正反匯率列；六個 collections 逐一與新序 11 印出的本機筆數相同 | firestore-read | Claude |
| 11 | 新增 | Claude 以 query_local_db.sh 跑 scene R03-end 對賬 | 六張表存活列數逐一印出、供新序 10 逐項比對；transactions 10 筆、transfers 2 筆、schedules 0 筆 | sqlite-local | Claude |

- 新序 9 的已驗欄沿用原序 15 的兩條 CS-03 引句，不加不減。initial 模式那條引句已搬到 R01 新序 10
- 新序 10 的已驗欄沿用原序 16 的 CS-03 引句，並在其前以全形分號接上原序 4 的 CS-02 雲端六個 collections 引句
- 新序 11 已驗留空
- 序 1 不變；原序 9、10、11、12 順延為新序 3、4、5、6
- transactions 為 10 筆不是 19 筆，因為 AS-06 重匯段已整段搬到 R12。若不採搬移，此格改為 19 筆並註明其中 9 筆為帶 `deletedOn` 的墓碑列，`getLocalChanges` 不濾 `deletedOn`，墓碑照樣上雲

### R04 定期排程 — 11 列升為 12 列

合併與新增：原序 3 與 4 併列、原序 7 與 8 併列；場末新增兩列還原、一列 sqlite-local 對賬。這是全案唯一淨增列的場次，換到的是 R05 至 R08 四場的定值斷言。

| 新序 | 對應原序 | 動作欄新內容 | 預期欄新內容 | 手段 | 驗證者 |
| --- | --- | --- | --- | --- | --- |
| 3 | 3 加 4 | 點完成、待復原列出現後於倒數內點復原 | 返回列表並顯示復原列、列表出現排程測試該筆、點復原後該筆自列表消失、無排程殘留 | manual-ui | 使用者 |
| 5 | 6 | 完全關閉 app、重新開啟 | 實例已於序 4 建立當下補齊、冷啟後不再新增、列表自本月 5 日起每日一筆早餐改過在列、筆數等於本月 5 日至今日的天數且不少於三筆 | manual-ui | 使用者 |
| 6 | 7 加 8 | 點開本月 5 日早餐實例、金額改為 200、點完成、於對話框選僅此一筆、確認其他實例維持 150 後再點開該筆改回 150、點完成、於對話框選僅此一筆 | 對話框提供僅此一筆與此筆及未來、改動時僅該筆金額變 200、其他實例維持 150、還原後該筆金額回 150 | manual-ui | 使用者 |
| 10 | 新增 | 點開最早一筆早餐實例、點刪除、於對話框選此筆及未來、不點復原 | 全部早餐實例自列表消失、排程不再產生新實例 | manual-ui | 使用者 |
| 11 | 新增 | 手動新增支出、備註早餐改過、金額 150、類別餐飲、帳戶錢包、日期本月 5 日、點完成 | 列表出現該筆、餐飲組回到定值 | manual-ui | 使用者 |
| 12 | 新增 | Claude 以 query_local_db.sh 跑 scene R04-end 對賬 | schedules 一筆且 end_on 早於 start_on；schedule_id 非空的存活交易零筆；本月 5 日備註早餐改過金額 150 的一般交易恰一筆 | sqlite-local | Claude |

- 新序 6 的類型欄取 操作，還原意圖寫進說明欄
- 新序 10 與 11 已驗留空，兩列類型皆為 還原
- 序 1、2 不變；原序 5 順延為新序 4；原序 9、10、11 順延為新序 7、8、9
- `deleteSchedule` 的此筆及未來分支只把 `endOn` 截到前一週期並軟刪該日起的實例，排程本體留庫。新序 10 的預期不得寫成排程消失
- RC-06 的補產生驗證由 R13 以 seeder 收下，本場刪掉排程實例不損任何斷言

### R05 幣別與匯率 — 21 列降為 14 列

合併與刪除：原序 1 刪除、交給 R04 場尾對賬；原序 2 與 3 併列、原序 5 與 6 併列、原序 13 至 15 併列；原序 19、20、21 整段移入 R06。

| 新序 | 對應原序 | 動作欄新內容 | 預期欄新內容 | 手段 | 驗證者 |
| --- | --- | --- | --- | --- | --- |
| 1 | 2 加 3 | 於貨幣與財務點匯率列表、逐字檢視該幣別對的單行文字 | 列表出現一組 TWD 對 JPY 單行、文字為 1 TWD = 4.5 JPY 型態、數值取自 R03 跨幣轉帳 1000 對 4500 的隱含匯率、小數補滿至少四位有效數字 | manual-ui | 使用者 |
| 3 | 5 加 6 | 點該 TWD 對 JPY 幣別對進匯率編輯器、嘗試點按來源欄與目標幣別欄、檢視目標金額欄預填值 | 來源固定為 TWD、目標幣別 JPY、兩欄皆不可展開不可修改、目標金額預填 4.5 | manual-ui | 使用者 |
| 10 | 13 加 14 加 15 | 返回貨幣與財務、點主要貨幣進畫面、於搜尋框輸入 USD、清空改輸入該項顯示名稱前三個字元、清空後點選 USD、觀察列表排序後點完成回上一頁 | 進入時 TWD 置頂並帶選取標記、兩次搜尋皆即時篩出 USD 項其餘項消失、改選後 TWD 仍置頂不重排、USD 帶選取標記、返回後主要貨幣欄顯示 USD | manual-ui | 使用者 |
| 13 | 18 | 不變 | 不變 | manual-ui | 使用者 |
| 14 | 新增 | Claude 以 query_local_db.sh 跑 scene R05-end 對賬 | settings 的 base_currency_id 為 901；currency_rates 含 TWD 對 JPY 的 4.6 生效列、另有兩筆對 USD 的 1.0 佔位列 | sqlite-local | Claude |

- 新序 1 的已驗欄以全形分號串接原序 2 與 3 兩條 CU-03 引句；新序 3 串接原序 5 與 6 兩條 CU-04 引句；新序 10 串接原序 13 與 14 兩條 CU-01 引句，原序 15 已驗本為空
- 新序 14 已驗留空
- 原序 4 順延為新序 2；原序 7、8 順延為 4、5；原序 9 至 12 順延為 6 至 9；原序 16、17 順延為 11、12
- CU-05 的引句隨原序 20 移入 R06，本場涵蓋測項刪去 CU-05

### R06 儀表板 — 19 列維持 19 列

合併與新增：原序 5 與 6 併列、原序 16 與 17 併列；CU-05 引句掛進原序 14；場尾新增 qa-markers 與 sqlite-local 兩列。列數持平，換到的是三條斷言自反推改為直證。

| 新序 | 對應原序 | 動作欄新內容 | 預期欄新內容 | 手段 | 驗證者 |
| --- | --- | --- | --- | --- | --- |
| 1 | 1 | 不變 | 三帳戶皆選取、期間標題為本月、清單依類別分組 | manual-ui | 使用者 |
| 5 | 5 加 6 | 點首頁 header 篩選按鈕開啟 modal、檢視摘要條兩卡、點時間粒度卡切到週、再點分組方式卡切到日期、每點一次都看 modal 後方的 HomeScreen | 左卡顯示全部、右卡顯示類別、與當前首頁狀態一致；兩卡值改為週與日期、後方報表即時改為本週區間並改依日期分組 | manual-ui | 使用者 |
| 12 | 13 | 不變 | 購物組 3500 為露營裝備單筆、交通組 350 為計程車單筆、娛樂組 300 為電影單筆、餐飲組 1150 為露營餐費 800 加早餐改過 150 加增量備份 200 | manual-ui | 使用者 |
| 13 | 14 | 不變 | 清單改依日期分組、日期由新到舊排列、該列金額 4500 JPY、下方帶 ≈ 起頭的換算副文字 978 TWD | manual-ui | 使用者 |
| 15 | 16 加 17 | 自本月向過去滑動至前月、再多滑兩期後一路滑回前月 | 逐頁標題連續往前遞減、前月之前各頁皆為空期間、全程無白畫面無閃退、回到前月頁支出 500、收入 0、中心餘額為負 500、清單僅醫療組的診所 500 一筆 | manual-ui | 使用者 |
| 16 | 18 | 不變 | 前月支出合計改為 600、中心餘額改為負 600、醫療組顯示 600 | manual-ui | 使用者 |
| 18 | 新增 | Claude 於 sim-review 導出的 Metro log grep QA RCACHE clear 列 | 見一行 reason=tx_write，時點落在新序 16 的金額改動之後 | qa-markers | Claude |
| 19 | 新增 | Claude 以 query_local_db.sh 跑 scene R06-end 對賬 | settings 的 home_time_granularity 為 month、home_group_mode 為 category、home_selected_account_ids 含三個帳戶 id；交易與轉帳筆數與 R05 終點相同 | sqlite-local | Claude |

- 新序 13 的已驗欄以全形分號串接原序 14 的 HD-04 引句與自 R05 移入的 CU-05 引句
- 新序 16 的已驗欄改為空白，HD-05 快取清空那條引句整條移到新序 18
- 新序 15 已驗留空，說明欄寫明快取淘汰斷言由 R00 序 9 的 jest 收下、本列只留連續切期的穩定性煙霧測
- 新序 19 已驗留空
- 序 1 說明欄刪掉餐飲組非定值的免責註記。R04 場末已把排程實例還原成單筆，餐飲組回到 1150 定值
- 原序 2、3、4 順延為 2、3、4；原序 7 至 12 順延為 6 至 11；原序 15 順延為 14；原序 19 順延為 17
- 本場前置環境必須補 Metro 以 `--client-logs` 啟動，否則新序 18 抓不到標記

### R07 清單治理 — 25 列降為 23 列

合併與刪除：原序 1 刪除、交給 R06 場尾對賬；原序 20 併入原序 8、原序 18 併入原序 9、原序 19 與 21 併列；場尾新增 qa-markers 與 sqlite-local 兩列。

| 新序 | 對應原序 | 測項欄 | 動作欄新內容 | 預期欄新內容 | 手段 | 驗證者 |
| --- | --- | --- | --- | --- | --- | --- |
| 7 | 8 加 20 | LD-03、EN-05 | 進帳戶列表點銀行進編輯器、開啟停用開關、點完成、返回列表後長按日幣帳戶拖到錢包之前放開 | 銀行仍在列並呈停用樣式、帳戶順序即時更新為日幣帳戶、錢包、銀行 | manual-ui | 使用者 |
| 8 | 9 加 18 | LD-03、EN-05 | 進類別列表點醫療進編輯器、點刪除並於確認對話框確認、返回列表後長按支出區的購物拖到餐飲之前放開 | 醫療自類別清單消失、類別作用中剩六個、支出區順序即時更新為購物、餐飲、交通、娛樂 | manual-ui | 使用者 |
| 12 | 13 | HD-06 | 逐列核對結果內是否有掛銀行的露營餐費 800 | 露營餐費 800 不在結果內、其帳戶銀行已於本場停用 | manual-ui | 使用者 |
| 17 | 19 加 21 | EN-05 | 返回設定頁後依序重進類別列表與帳戶列表 | 類別支出區仍為購物、餐飲、交通、娛樂；帳戶仍為日幣帳戶、錢包、銀行 | manual-ui | 使用者 |
| 21 | 25 | EN-04 | 不變 | 不變 | manual-ui | 使用者 |
| 22 | 新增 | HD-06 | Claude 於 Metro log grep QA DBQ search 列 | search 列的 raw 大於 filtered、excludedAccounts 為 1 | qa-markers | Claude |
| 23 | 新增 | — | Claude 以 query_local_db.sh 跑 scene R07-end 對賬 | accounts 存活兩筆為錢包與日幣帳戶、categories 存活六筆且娛樂帶 disabled_on、醫療與銀行皆為軟刪列、transfers 存活一筆 | sqlite-local | Claude |

- 新序 7 已驗留空，原序 8 與 20 兩列的已驗本就皆空
- 新序 8 的已驗欄以全形分號串接原序 9 的 LD-03 引句與原序 18 的 EN-05 引句
- 新序 17 的已驗欄沿用原序 21 的 EN-05 引句
- 新序 12 的已驗欄改為空白，HD-06 停用排除那條引句整條移到新序 22
- 新序 23 已驗留空。手段欄單值的不變式在此體現：兩個手段兩列，不塞同一格
- 若不採 impl 補 marker，新序 22 刪除、HD-06 引句留在新序 12、本場列數為 22
- 多測項欄有先例，R08 原序 10 為三測項、R12 原序 11 為兩測項
- 原序 2 至 7 順延為 1 至 6；原序 10 至 17 順延為 9 至 16；原序 22、23、24 順延為 18、19、20

### R08 偏好與同步 — 23 列降為 20 列

合併與刪除：原序 1 刪除、交給 R07 場尾對賬；原序 2 改為 Claude節點；原序 11 併入場尾；原序 16 與 23 併為場尾一列；原序 21 改為 Debug 工具。

| 新序 | 對應原序 | 動作欄新內容 | 預期欄新內容 | 手段 | 驗證者 |
| --- | --- | --- | --- | --- | --- |
| 1 | 2 | Claude 以 query_local_db.sh 查 settings 的 theme、language、time_zone、week_start、analytics_consent、base_currency_id 六欄、把輸出原樣貼進本列說明欄 | 六個原值已記錄、供新序 15 至 17 的還原列引用 | sqlite-local | Claude |
| 4 | 5 | 於設定頁 Debug 區點 Theme 開主題設定 Modal、點選 theme2 卡片確認右上出現勾選 overlay 後點完成 | 不變 | manual-ui | 使用者 |
| 5 | 6 | 於設定頁 Debug 區點 Theme 再開主題設定 Modal、點選 theme3 卡片、點關閉 | 不變 | manual-ui | 使用者 |
| 10 | 12 | 於設定頁 Debug 區點 Theme 開主題設定 Modal、點選 theme3 卡片、點完成 | 不變 | manual-ui | 使用者 |
| 14 | 17 | 不變 | 不變 | firestore-read | Claude |
| 16 | 19 | 於設定頁 Debug 區點 Theme 開主題設定 Modal、選回新序 1 記下的原主題卡片、點完成 | 不變 | manual-ui | 使用者 |
| 18 | 21 | 進設定頁點 Mock Data Settings、於 Regression Fixtures 區塊點 Fill write quota | 顯示配額已填至上限的提示 | manual-ui | 使用者 |
| 19 | 22 | 停留前景等背景備份跑完、再將 app 退至背景滿 5 分鐘後回前景 | 兩次回前景都重繪完成、無 Alert、無紅屏 | manual-ui | 使用者 |
| 20 | 11 加 16 加 23 | Claude 於 sim-review 導出的 Metro log 依序 grep QA BOOT resolve、QA PREF、QA QUOTA gate、QA BACKUP skip 四組列 | resolve 列 landing 值為支出模式；QA PREF 列出本次上傳欄位含 theme、language 與 currency、lastSyncedAt 未因偏好上傳而更新；gate 列 allowed=false 且 todayTotal 達 2000 上限；skip 列 reason=quota | qa-markers | Claude |

- 新序 1 的說明欄註明本列為非阻斷節點，Claude 可在使用者走新序 2 與 3 時並行執行，六個原值只有新序 15 至 17 要用；已驗留空
- 新序 20 的已驗欄以全形分號串接三條原引句，順序為 AS-03 啟動落點解析、CS-01 QA PREF 標記、CS-04 寫入禁止時備份跳過
- 新序 14 是全場唯一不可延後的節點。新序 15 至 17 的還原列會逐欄覆寫雲端 preferences，說明欄要寫死這句
- 原序 3、4 順延為 2、3；原序 7、8、9、10 順延為 6、7、8、9；原序 13、14、15 順延為 11、12、13；原序 18、20 順延為 15、17
- 本場前置環境刪 CSV assets 引用、加 dev build 與 Debug 區可見的前提
- 本場相依 impl 新增 `fillWriteQuotaForTesting` 與對應按鈕，見手段改掛表

### R10 付費與後端登記 — 27 列降為 23 列

合併與刪除：原序 1、3、4 由 seeder 一列取代；原序 16 與 17 整列下移至場尾；原序 20 與 21 併列、原序 26 與 27 併列。

| 新序 | 對應原序 | 動作欄新內容 | 預期欄新內容 | 手段 | 驗證者 |
| --- | --- | --- | --- | --- | --- |
| 1 | 1 加 3 加 4 | 於實機開啟 app、確認設定內 Apple ID 為 sandbox-buyer、進設定頁點 Mock Data Settings、於 Regression Fixtures 區塊點 Seed R02 end state、於確認對話框點 Seed | 顯示 Seeded R02 end state 成功提示、帳戶管理列三個活躍帳戶、類別管理列七個活躍類別、首頁出現九筆交易 | manual-ui | 使用者 |
| 9 | 11 | 首頁點新增並選轉帳、轉出帳戶選錢包、轉入帳戶選銀行、轉出金額輸入 100 後點完成 | 轉帳新增成功、列表出現該筆、全程不出現付費牆 | manual-ui | 使用者 |
| 16 | 20 加 21 | 進設定頁點資料管理、點匯入收入支出、於首步點下載範本並於分享面板儲存、再點下載說明檔並於分享面板儲存 | 系統分享面板開啟、範本檔與說明檔皆儲存成功、範本表頭欄位序為 transaction_datetime、category、account、amount、currency、note；說明檔檔名為 $wish_transaction_guide.txt、開檔後所列欄位依序與範本表頭逐字相同 | manual-ui | 使用者 |
| 20 | 25 | 不變 | 僅列當前使用者活躍紀錄、錢包與餐飲與交通與薪資標為既有、悠遊卡與教育標為新、CSV 未出現的帳戶與類別不在列 | manual-ui | 使用者 |
| 21 | 26 加 27 | 為悠遊卡與教育各選新建後前進、核對預覽摘要後點送出、於結果對話框點確認、回首頁後開 header 篩選把時間粒度切為全部、再進帳戶管理與類別管理檢視 | 預覽摘要列 10 筆待匯入、送出後顯示已匯入 9 筆與略過 1 筆、Modal 關閉、粒度為全部時清單出現匯入早餐 120 等 9 筆、帳戶管理出現悠遊卡共五個帳戶、類別管理出現教育共九個類別、匯入超額列不在清單 | manual-ui | 使用者 |
| 22 | 16 | Claude 以 firestore-read 一併查 entitlements 集合與 txnIndex 集合、並記下該 uid 前八碼供 R11 與 R12 引用 | 不變、另加該 uid 前八碼已記錄 | firestore-read | Claude |
| 23 | 17 | 不變 | 不變 | cloud-logging | Claude |

- 新序 16 的已驗欄沿用原序 21 的 AS-05 引句；新序 21 的已驗欄沿用原序 26 的 AS-05 引句，原序 27 已驗本為空
- 原序 2 順延為新序 2；原序 5 至 15 順延為 3 至 13；原序 18、19 順延為 14、15；原序 22、23、24 順延為 17、18、19
- 全場六處點儲存一律改點完成，與其餘八個 csv 的 40 處對齊
- 序 3、8、14 的幣別選 TWD 一律改幣別維持預設，說明欄註明預設即主要貨幣、該預設已由 R02 的 EN-03 引句驗過
- 原序 3、4 的湊滿兩列可刪，因為 `r02_end` 鋪出的三帳戶七類別正等於 `MAX_FREE_ACCOUNTS` 與 `MAX_FREE_CATEGORIES`
- 新序 9 的轉入帳戶自現金備用改為銀行。`r02_end` 沒有現金備用，銀行同為 TWD、`createTransfer` 走小於等於上限、放行成立
- 新序 22 額外承擔 uid 記錄，該列本就要用 uid 查 entitlements

### R11 訂閱生命週期 — 14 列降為 13 列

合併：原序 8 與 9 併列。其餘只改預期與動作文字。

| 新序 | 對應原序 | 動作欄新內容 | 預期欄新內容 | 手段 | 驗證者 |
| --- | --- | --- | --- | --- | --- |
| 2 | 2 | 長按 app 圖示刪除 app、重新安裝 dev build 後開啟、落地主畫面、自 Metro log 的 QA BACKUP start uid= 列記下 uid 前八碼 | app 正常落地、全程無登入畫面、首頁無交易資料、uid 前八碼與 R10 新序 22 記錄一致 | manual-ui | 使用者 |
| 4 | 4 | 不變 | 顯示恢復成功對話框、設定頁升級入口消失、等級呈現為付費 | manual-ui | 使用者 |
| 8 | 8 加 9 | 進設定頁點資料管理、點匯入收入支出、來源時區維持預設、選 assets 的 import_small.csv 後前進、於內容比對為所有標為新的帳戶與類別選新建後前進、核對預覽後送出、於結果對話框點確認、回首頁後開 header 篩選把時間粒度切為全部 | 六欄自動對應無缺、顯示已匯入 9 筆與略過 1 筆、粒度為全部時清單出現匯入早餐 120 等 9 筆 | manual-ui | 使用者 |
| 13 | 14 | Claude 於 Metro log 一併 grep QA BOOT delegate 與 QA PREMIUM resolve 兩組列 | 見一條 delegate task=refreshStatus trigger=foreground；其後的 QA PREMIUM resolve source=storekit 的 tier 由 LEVEL_1 轉為 LEVEL_0 | qa-markers | Claude |

- 新序 4 的已驗欄引句逐字不動，說明欄補一句解鎖上限那半由 R10 的解鎖後新增列承載、本場序 2 重裝後計數歸零故不重驗
- 新序 2 的說明欄註明 uid 若不一致即停場、不進新序 3。重裝不清 keychain、身分應沿用
- 原序 1、3 順延為 1、3；原序 5、6、7 順延為 5、6、7；原序 10 至 13 順延為 9 至 12
- 新序 11 對應原序 12，時點敏感、不可延後，說明欄維持原字

### R12 毀滅與重生 — 15 列升為 18 列後降為 12 列

合併與搬入：R03 的 AS-06 三列搬進本場開場之後；原序 1 與 2 併列、原序 3 至 6 併列、原序 7 與 8 併列；原序 13 與 15 上移讓 GCP console 一次進出；原序 12 與 14 併為場尾一列。

| 新序 | 對應原序 | 動作欄新內容 | 預期欄新內容 | 手段 | 驗證者 |
| --- | --- | --- | --- | --- | --- |
| 1 | 1 加 2 | 確認裝置連網、開啟 app 落地主畫面、開 header 篩選把時間粒度切為全部、檢視首頁清單與帳戶管理、自 Metro log 的 QA BACKUP start uid= 列記下清除前 uid 前八碼 | 粒度為全部時首頁列出匯入的交易、帳戶管理列出錢包與悠遊卡帳戶、清除前 uid 前八碼在案且與 R10 新序 22 記錄一致 | manual-ui | 使用者 |
| 2 | R03 序 5 | 進設定頁點資料管理、點匯出轉帳確認顯示無資料對話框後關閉、點匯出收入支出、於分享面板儲存至檔案 | 不變 | manual-ui | 使用者 |
| 3 | R03 序 6 | 不變 | 不變 | manual-ui | 使用者 |
| 4 | R03 序 7 | 不變 | 顯示已匯入 9 筆、略過 0 筆、清單每筆各出現第二份含匯入早餐 120 | manual-ui | 使用者 |
| 5 | 3 加 4 加 5 加 6 | 進設定頁點資料管理、點清除所有資料、於說明對話框讀畢說明段後點繼續、於最終確認對話框點破壞性樣式確認鈕、清除進行中試點資料管理各入口 | 清除入口可點、說明段預告雲端與本機資料及身分全滅不可復原、最終確認鈕為破壞性樣式、清除進度顯示中、各入口停用不可點 | manual-ui | 使用者 |
| 6 | 7 加 8 | 等待清除完成、自 Metro log 的 QA BACKUP start uid= 列記下重生後 uid 前八碼 | 自動落回主畫面、全程無登入畫面與帳號欄位、新 uid 前八碼與清除前不同 | manual-ui | 使用者 |
| 9 | 13 | 不變 | 不變 | manual-ui | 使用者 |
| 10 | 15 | 不變 | 不變 | manual-ui | 使用者 |
| 11 | 11 | Claude 以 firestore-read 一次查 R10 新序 22 記下的那顆 uid 的 users 文件與其子集合、accountDeletions 內該 uid 的墓碑文件、以該 uid 為 id 的 entitlements 文件、以及 txnIndex 歸戶該 uid 的條目 | 不變 | firestore-read | Claude |
| 12 | 12 加 14 | Claude 以 cloud-logging 一併查 deleteUserAccount 與 capBilling 兩支 functions log | deleteUserAccount 有執行完成訊息、無刪除未完成錯誤；capBilling 受訊息觸發執行後直接結束、無錯誤、無解除計費綁定動作 | cloud-logging | Claude |

- 新序 4 的已驗欄沿用 R03 原序 7 的 AS-06 引句、逐字不動
- 新序 5 的已驗欄沿用原序 6 的 AS-07 引句；新序 12 的已驗欄以全形分號串接原序 12 與 14 兩條引句
- 新序 2 的已驗欄沿用 R03 原序 5 的 AS-06 引句
- 原 R03 序 8 的九筆重複列手工清理整列刪除。R12 隨即清空全部資料，重複列不必清
- 原序 9、10 順延為新序 7、8
- uid 記錄留給使用者、不搬給 Claude。R12 跑實機，sqlite-local 不成立；改由動作欄指名去 `QA BACKUP start uid=` 那一行找，前置環境同批補 Metro 帶 `--client-logs`

### R13 補產生驗證 — 3 列升為 4 列

新增一列 sqlite-local，換掉跨一個月的逐日目視。

| 新序 | 對應原序 | 動作欄新內容 | 預期欄新內容 | 手段 | 驗證者 |
| --- | --- | --- | --- | --- | --- |
| 1 | 1 | 進設定頁點 Mock Data Settings、於 Regression Fixtures 區塊點 Seed stale schedule、於確認對話框點 Seed、返回首頁後開 header 篩選把時間粒度切為全部 | 顯示 Seeded stale schedule 成功提示、粒度為全部時首頁出現八筆一般交易、一筆上月 5 日備註早餐的排程實例、兩筆轉帳為錢包轉銀行 2000 與錢包轉日幣帳戶 1000 對 4500 | manual-ui | 使用者 |
| 2 | 2 | 完全關閉 app、重新開啟、落地交易清單並確認時間粒度仍為全部 | 清單出現遺漏期的實例、自上月 5 日起每日一筆早餐、補至今日為止 | manual-ui | 使用者 |
| 3 | 3 | 不變 | 不變 | qa-markers | Claude |
| 4 | 新增 | Claude 以 query_local_db.sh 跑 scene R13-backfill 對賬 | 依 schedule_instance_date 逐日分組，自上月 5 日至今日每日恰一筆、無缺日、無重複 | sqlite-local | Claude |

- 新序 2 的已驗欄改為空白，RC-06 那條引句整條移到新序 4；逐日核對的要求自動作欄刪除
- 新序 3 的預期欄把筆數對照對象自序 2 的人工計數改為新序 4 的分組列數
- 新序 1 的說明欄補一句 Mock Data 的按鈕標籤為 `Seed stale schedule (R09)`，其中 R09 為已移除的舊場次編號、即本場的 seeder
- 本場改列在 A 鏈末、跑 simulator，sqlite-local 才成立。若沿用實機跑，新序 4 標本次未驗、RC-06 引句退回新序 3 的 qa-markers 承載

---

## 往返重排後的節點分佈

停等區塊的定義是相鄰的一段 Claude節點。使用者在區塊處停下等 Claude，區塊內幾列不影響等幾次。

| 場次 | 現行 Claude節點數 | 現行停等區塊 | 現行場中停等 | 改造後節點數 | 改造後區塊 | 改造後場中停等 | 節點落點 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| R00 | 15 | 1 | 0 | 15 | 1 | 0 | 全場 |
| R01 | 4 | 2 | 1 | 2 | 1 | 0 | 場尾 |
| R02 | 0 | 0 | 0 | 1 | 1 | 0 | 場尾 |
| R03 | 4 | 2 | 1 | 3 | 1 | 0 | 場尾 |
| R04 | 0 | 0 | 0 | 1 | 1 | 0 | 場尾 |
| R05 | 0 | 0 | 0 | 1 | 1 | 0 | 場尾 |
| R06 | 0 | 0 | 0 | 2 | 1 | 0 | 場尾 |
| R07 | 0 | 0 | 0 | 2 | 1 | 0 | 場尾 |
| R08 | 4 | 3 | 2 | 3 | 3 | 1 | 場首非阻斷、場中一次、場尾 |
| R10 | 2 | 1 | 1 | 2 | 1 | 0 | 場尾 |
| R11 | 3 | 2 | 1 | 3 | 2 | 1 | 場中一次、場尾 |
| R12 | 3 | 2 | 2 | 2 | 1 | 0 | 場尾 |
| R13 | 1 | 1 | 0 | 2 | 1 | 0 | 場尾 |
| 合計 | 36 | 14 | 8 | 39 | 15 | 2 | — |

- 場中停等自 8 次降為 2 次。剩下兩次都經過個別確認、無法延後
    - R08 新序 14 讀雲端 preferences。新序 15 至 17 的還原列逐欄覆寫該筆文件，延後即讀到還原後的值
    - R11 新序 11 讀 entitlements 到期狀態。作者已標時點敏感、到期剛發生時比對、時點錯過即失真
- 可推到場尾的六次全是 grep log 或查落庫。Metro log 隨 Metro 啟動建立、整場累積，場尾照樣抓得到前段的列；sqlite 查的是當下快照，只要中間步驟不覆寫該欄就成立
- R08 場首那次是新增的非阻斷節點。它讀六個偏好原值供還原列引用，Claude 可與使用者的新序 2 至 3 並行，不佔使用者時間
- 節點總數自 36 升為 39，但區塊只自 14 升為 15。節點變多不等於停等變多，同一區塊內多列是同一次等待
- 場尾節點的代價要寫進說明欄。R10 新序 22 與 23 延後後，若後端登記失敗，訊號延到場尾才出現，中間十步的解鎖行為靠 client 端 StoreKit 仍會通過

---

## 手段改掛的逐條對照表

換手段一律兩側同批改，分冊那條檢查點的層欄、驗證者欄、手段欄與腳本該列的驗證者欄、手段欄要一起動。加佐證列則兩側都不動、只在腳本多一列已驗留空的列。

| 檢查點引句 | 分冊位置 | 原手段 | 新手段 | 查證指令或命名空間 | 相依 |
| --- | --- | --- | --- | --- | --- |
| HD-05 交易異動後快取清空，返回首頁報表反映修改 | `no3_home_dashboard.md:160` | manual-ui | qa-markers | grep `QA RCACHE clear reason=tx_write cleared=`，marker 在 `PeriodDataStore.ts:236`、reason 由同檔 `deriveClearReason` 依變更表推導 | R06 前置環境補 Metro 帶 `--client-logs`。impl 無須改動 |
| HD-06 停用帳戶或停用分類的紀錄不列入結果 | `no3_home_dashboard.md:193` | manual-ui | qa-markers | grep `QA DBQ search raw= filtered= excludedAccounts=` | 相依 impl 於 `SearchScreen.tsx:116` 的過濾處補該 marker、加 `__DEV__` 閘。未補則本條維持 manual-ui 不動 |
| RC-06 列表出現遺漏期的實例，補至當前時間為止 | `no2_recording_core.md:160` | manual-ui | sqlite-local | `query_local_db.sh scene R13-backfill`，底層依 `schedule_instance_date` 逐日分組計數 | R13 須跑 simulator。跑實機時本條退回 qa-markers 的 `QA SCHED backfill ... generated=` |
| AU-02 重試經 handleAuthEvent 收斂，全程只產生一顆 uid | `no1_auth_bootstrap.md:66` | qa-markers | qa-markers 不變 | grep 對象自 QA BOOT 改為 `QA RCACHE lookup ... uid=` 加 `QA BOOT anonymous signIn start` 計次 | 無。QA BOOT 六個落點無一帶 uid，只改 grep 對象 |
| AU-03 身分事件去重，冷啟動工作不重跑 | `no1_auth_bootstrap.md:90` | qa-markers | qa-markers 不變 | grep `QA BOOT delegate` 計組數、冷啟後無第二條 `anonymous signIn start` | 無 |
| CS-02 探測遠端無資料後進入 initial 模式 | `no7_cloud_sync.md:64` | qa-markers | qa-markers 不變 | grep `QA BACKUP probe remoteHasData=` 與 `QA BACKUP mode mode=initial`；收下場次自 R03 改 R01 | 無。`runInitialBackup` 無條件 `markSynced`，R01 落地後 `lastSyncedAt` 已非 null，R03 走不到 initial |
| PM-05 QA PREMIUM 標記可見 reconcile 觸發與等級解析結果 | `no8_payment.md:152` | qa-markers | qa-markers 不變 | grep 對象加 `QA BOOT delegate task=refreshStatus trigger=foreground`。QA PREMIUM 兩條 reconcile 皆為 `triggered=false`、無 true | 無 |
| AS-03 啟動落點解析輸出 QA BOOT resolve 標記，landing 值為所設模式 | `no6_app_setting.md:66` | qa-markers | qa-markers 不變 | grep `QA BOOT resolve premiumLoaded= landing=`；收下位置自場中移到場尾 | 無 |
| CS-04 寫入禁止時備份跳過，等待跨日重置 | `no7_cloud_sync.md:99` | qa-markers | qa-markers 不變 | grep `QA QUOTA gate allowed=false todayTotal=` 與 `QA BACKUP skip reason=quota` | 相依 impl 新增 `fillWriteQuotaForTesting`。分冊步驟欄同批改，匯入大量資料改為以 Debug 工具填滿配額 |

新增的佐證列一律已驗留空、分冊不動。清單如下。

| 佐證列位置 | 手段 | 查證內容 | 佐證對象 |
| --- | --- | --- | --- |
| R02 新序 18 | sqlite-local | `scene R02-end` | 該場終點狀態的內容等價 |
| R03 新序 11 | sqlite-local | `scene R03-end` | 該場終點狀態與新序 10 的雲端筆數比對基準 |
| R04 新序 12 | sqlite-local | `scene R04-end` | 排程截斷與早餐回復單筆 |
| R05 新序 14 | sqlite-local | `scene R05-end` | CU-01 主要貨幣落庫與 USD 佔位匯率 |
| R06 新序 19 | sqlite-local | `scene R06-end` | HD-02 三值持久化落庫 |
| R07 新序 23 | sqlite-local | `scene R07-end` | LD-03 軟刪與停用的落庫形狀 |
| R08 新序 1 | sqlite-local | 六個偏好欄原值 | 取代手抄、供還原列引用 |

實機場次不掛 sqlite-local。`query_local_db.sh` 以 `xcrun simctl get_app_container` 定位，實機無路徑，R10 至 R12 的落庫性質斷言維持現狀、不改掛。

需要先補的 impl 改動集中三項，全部走 impl git 的獨立 branch、不與計劃層混批。

- `regressionFixture.ts` 新增 `r02_base` 場景。帳戶取 `FIXTURE_ACCOUNTS` 濾掉日幣帳戶為兩筆、類別取 `FIXTURE_CATEGORIES` 濾掉獎金為六筆、交易取 `FIXTURE_TRANSACTIONS` 濾掉早餐改過與獎金入帳為七筆；`MockDataSettingsScreen` 加 Seed R02 base 按鈕；`regressionFixture.test.ts` 同批更新筆數對帳
- `quotaService.ts` 新增 `fillWriteQuotaForTesting`，形狀比照 `resetWriteQuotaForTesting`、production 同樣 no-op。寫入必須是 `AsyncStorage.multiSet`，日期鍵用與 `resetIfNewDay` 完全相同的 UTC 取法，否則下次 `checkQuota` 判成跨日直接歸零；`MockDataSettingsScreen` 加 Fill write quota 按鈕
- `SearchScreen.tsx:116` 的記憶體過濾處補 `QA DBQ search` marker、加 `__DEV__` 閘。命名空間 QA DBQ 已在能力側寫清單、`localDbService.ts:22` 已在用，不必動能力側寫

---

## 狀態鏈修正

### 終點狀態與起點狀態的改寫

| 場次 | 欄位 | 新內容 |
| --- | --- | --- |
| R02 | 終點狀態 | 帳戶錢包、銀行、日幣帳戶三個，類別餐飲、交通、娛樂、購物、醫療、薪資、獎金七個，fixture 交易組九筆已錄且早餐已改 150 並改備註為早餐改過、日幣帳戶建立時已種入 JPY 對 TWD 的 1.0 佔位匯率、無轉帳、無排程、裝置斷網且 app 已重啟 |
| R03 | 終點狀態 | 連網、雲端與本機一致、轉帳兩筆在案且跨幣轉入已改 4500、臨時交易增量備份 200 留庫至 R12、無排程 |
| R04 | 終點狀態 | 早餐由單筆轉為每日排程後於場末以此筆及未來刪除、排程本體留庫但 endOn 早於 startOn 且不再產生實例、無排程實例、早餐已回復為單筆備註早餐改過金額 150 掛本月 5 日、序 1 建立的排程測試該筆已撤銷、資料其餘不變 |
| R05 | 終點狀態 | 主要貨幣 TWD、JPY 匯率 4.6、幣別顯示格式已重置、記帳資料不變、另留兩筆對 USD 的 1.0 佔位匯率且切回 TWD 後不顯示於匯率列表、首頁篩選不動、沿用 R04 狀態 |
| R06 | 終點狀態 | 首頁篩選已還原為帳戶三卡全選、時間粒度月、分組方式類別；無資料變動 |
| R08 | 終點狀態 | 偏好與主題語系主貨幣全還原、啟動模式還原首頁、當日寫入配額已以 Debug 工具填至上限 |
| R10 | 起點狀態 | 以 Seed R02 end state 鋪起點，三帳戶、七類別、fixture 交易組九筆；實機、sandbox-buyer 已登入。不吃 R08 狀態 |
| R13 | 起點狀態 | 不吃任何前場狀態，seeder 自足清空重鋪 |

- R06 終點與 R07 起點的全類別字樣一律刪除。首頁篩選只有時間粒度、分組方式、選取帳戶三個維度，沒有類別篩選
- R04 終點的含未來實例字樣刪除。backfill 迴圈上界是 `nowTs`，產不出未來實例
- R07 序 1 的交易九筆清點整列刪除，改由 R06 場尾對賬承擔。沿鏈推到 R07 起點時存活交易多於九筆

### 場次順序與切鏈

現行是十三場一條單鏈，R10 中途失敗要回頭補前面八場。逐場推導後，R10 對前鏈的實質依賴只有活躍帳戶三個與活躍類別七個兩個計數，兩者 seeder 秒級鋪得出來。切成兩鏈後裝置矛盾一併消失。

| 鏈 | 場次 | 裝置 | 前置場次 | 說明 |
| --- | --- | --- | --- | --- |
| 鏈外 | R00 | 無 | 無 | 排最前為快速失敗 |
| A 鏈 | R01 至 R08 | simulator 或實機擇一、全鏈同一台 | 逐場相接 | 資料、報表、同步 |
| A 鏈末 | R13 | 必須 simulator，sqlite-local 才成立 | 無 | seeder 自足、不吃前場 |
| B 鏈 | R10 至 R12 | 實機 | R10 為無、R11 接 R10、R12 接 R11 | 購買、生命週期、滅盡 |

- 各場 md 的前置環境欄裝置別一律改成 R01 現行的寫法，裝置別見場次索引的執行環境，單一真相收回索引
- 索引的執行環境節改寫：A 鏈全程單一裝置、資料逐場累積不得跨裝置接續；B 鏈自 seeder 重建起點、不接 A 鏈；兩鏈可分日分裝置跑
- 索引新增失敗重進點一節：A 鏈 R03 至 R08 任一場失敗，修完以 Seed R02 end state 鋪起點、自 R03 重入。同節要寫清 seeder 鋪不出來的東西——它以 `collection.create` 直寫，繞過 `ensureRateForNewAccount`，不種 JPY 對 TWD 佔位匯率，R05 新序 1 的前提在重入路徑不成立；但 R03 的跨幣轉帳會補上正反兩筆真匯率，CU-03 兩條斷言仍成立
- 重進點需要可見 Debug 工具的 build，與 R10 前置同一個前提

### 前置環境補列

| 場次 | 補列內容 |
| --- | --- |
| R01、R03、R06、R07、R08、R11、R12、R13 | Metro 以 `--client-logs` 啟動並執行中；未帶該選項時 QA 標記整批不進 log 檔，須重啟 Metro 補上再重跑本場 |
| R01、R02 | 可控網路開關：simulator 走 Mac 端關 Wi-Fi 或 Network Link Conditioner，實機走飛航模式 |
| R03 | 可控網路開關，本場序 1 需自 R02 的斷網狀態恢復連網 |
| R02、R04、R05、R06、R07 | sqlite-local 的環境前提逐字沿用能力側寫，Mac 加 booted simulator、app 已跑過 bootstrap |
| R04 | 執行日須為本月 8 日以後。早餐排程自本月 5 日起每日補產生，新序 8 的中間日期實例需要至少三筆；當日實例是否已產生取決於原交易的時分秒，故不取 7 日為界 |
| R08、R10、R11、R12、R13 | dev build，設定頁 Debug 區與 Mock Data Settings 入口可見；TestFlight build 須先連點版本號七下解鎖、解鎖不持久，App Store 正式版永不可見、不可用於本場 |
| R10、R11 | `assets/import_small.csv` 與 `assets/import_bad.csv` 已置入實機的檔案 app、選檔器選得到；檔案來自 quality git 的 `no3_run_scripts/assets/` |
| R01、R02 | 刪掉 node_modules 完整那列。兩場步驟表無 jest-app 列，屬照抄的死條件 |

---

## 改造後的時長重估

現行十三個估值全是 5 的倍數、35 分出現六次，每步平均最大差三倍且方向與工作量相反，查無實測依據。本方案不沿用那組數字，改以逐列成本模型重估，並把等待自人手拆開。

估算依據：一般 manual-ui 操作列每列 1.5 分，含讀步驟、操作、核對預期；多筆連續輸入的建置列以每筆交易 1 分計；冷啟列 1.5 分；重裝 app 或安裝 build 3 至 4 分；清空裝置 5 分；系統購買對話框往返 2 分；Claude節點依手段計 wall-clock，qa-markers 與 sqlite-local 各 1 分、firestore-read 與 cloud-logging 各 2 分；純等待列的人手另計 0.5 至 1 分、等待本身進等待欄。

| 場次 | 新列數 | 人手分鐘 | 等待分鐘 | 現行估值 | 依據 |
| --- | --- | --- | --- | --- | --- |
| R00 | 18 | 0 | 15 | 15 | 兩次 npm test 的機器時間，使用者不參與；能力側寫已記 97 檔 846 斷言與 11 檔 89 斷言 |
| R01 | 11 | 20 | 0 | 35 | 含安裝舊版 4、安裝新版 2、清空裝置 5、安裝 dev build 3、Claude 節點 3 |
| R02 | 18 | 20 | 0 | 45 | seeder 取代十五個實體手建，省下的是 15 筆逐筆輸入 |
| R03 | 11 | 13 | 5 | 35 | 轉帳三列 4、增量備份 1.5、Claude 三列 4；退背景 5 分入等待欄 |
| R04 | 12 | 17 | 0 | 35 | RC-04 五列 5、RC-05 四列 6、新增還原兩列 3 |
| R05 | 14 | 18 | 0 | 25 | 三組併列各省 1.5、CU-05 三列移出省 4 |
| R06 | 19 | 24 | 0 | 35 | HD-01 滑動 3、HD-04 五列 5、HD-05 併列後 2 |
| R07 | 23 | 28 | 0 | 35 | RC-07 六列 8、HD-06 七列 8、EN-04 四列 5，清單進出自八次收斂為六次 |
| R08 | 20 | 24 | 5 | 35 | 匯入 2100 筆改 Debug 按鈕省 6；場首節點非阻斷不計人手 |
| R10 | 23 | 34 | 0 | 40 | seeder 開場省 3、AS-05 六列 10、PM-02 四列 6 |
| R11 | 13 | 24 | 35 | 50 | 重裝 4、切帳號 5、匯入 3；放置 35 分入等待欄 |
| R12 | 12 | 20 | 0 | 30 | 併入 AS-06 三列 6、清除鏈併列後 2、Claude 兩列 4 |
| R13 | 4 | 5 | 0 | 10 | 逐日目視改機器對賬，省 5 |
| 合計 | 198 | 247 | 60 | 425 | — |

- 現行 425 分裡有 45 分是純等待，人手約 380 分。改造後人手 247 分、等待 45 分、R00 機器時間 15 分
- 人手差額為省 133 分、約 2 小時 13 分、約三成五。以 wall-clock 計自 425 分降為 307 分、省 118 分
- A 鏈人手 169 分加等待 10 分；B 鏈人手 78 分加等待 35 分。兩鏈可分日跑
- 切鏈另省的是重跑成本、不是單輪成本。B 鏈失敗時免掉的 A 鏈重跑為 169 分，這筆不計入上表
- 場次總表的預估時長欄拆成人手分鐘、等待分鐘、依據三欄。依據欄先全填估值、未實測；第一輪真正跑完時逐場記起訖、把人手欄換成實測值並標日期與機器，格式比照能力側寫的探針紀錄
- 選集政策表全量回歸那格的約 7 小時改為同一口徑，人手約 4 小時、等待約 1 小時
- R11 序 9 說明欄那句放置期可與其他事並行上抬進索引的執行環境節，讓 wall-clock 與人手時間的分野在總表旁邊就看得到

---

## 對帳影響

### 七項逐項的失配風險

| 項 | 判準 | 本方案的影響 | 處置 |
| --- | --- | --- | --- |
| 1 抽取 | 兩側都抽得到 | 無影響，csv 仍為 9 欄、已驗仍在第 8 欄 | 合併儲存格一律用全形頓號與全形逗號。跑一次 `awk -F, 'FNR>1 && NF>0 && NF!=9'` 確認零列 |
| 2 正向 | 分冊有腳本無等於例外表 | 無影響。刪掉的列已驗全為空白，搬移的引句字串未變 | 例外表維持空表 |
| 3 反向 | 腳本有分冊無須零失配 | 無影響。本方案零引句改字 | 改完跑 `bash no2_qa_tools/check_plan.sh` 確認第三項仍零失配 |
| 4 計數 | 已驗去重加例外等於分冊總數 | 無影響。引句只搬不刪不增，仍為 212 加 0 對 212 | 不拆分任何既有檢查點。HD-02 三值那條只改層欄、不拆成兩條，拆了會讓分冊斷言數變 213 |
| 5 marker | 腳本引用的命名空間存在於 impl 的 src | 新增引用 QA RCACHE 與 QA DBQ，兩者皆已存在於 impl，第五項會綠 | 這是假綠。QA DBQ 的 search marker 尚未存在、第五項只驗命名空間不驗訊息，必須靠 impl 那批一起做，不能只看綠燈 |
| 6 R00 路徑 | 核對列的測試檔樣式至少一命中 | 無影響。R00 一列不改 | 無 |
| 7 狀態鏈 | 每個前置場次指得到 | R10 前置改無、R13 前置改無，第七項對無直接 skip | 改完重跑確認 |

### 需要同批改的檔清單

腳本層。

- `no3_run_scripts/no0_index.md`：場次總表的步驟數、時長三欄、涵蓋測項、前置場次；選集政策表的全量那格；執行環境節改雙鏈；新增失敗重進點一節
- `no3_run_scripts/no1_fixtures.md`：交易組第一列名稱與備註欄改早餐指向早餐改過並在註記說明 impl 以此字串識別；匯率節補 4.5 與 978 兩個推導值與其斷言落點；轉帳組註記補隱含匯率 4.5；場內臨時值表的排程測試列值欄改為排程 備註排程測試 餐飲 錢包 100 每週間隔 2；CSV assets 表把 import_quota 標為備用並補一句三檔日期固定在 2026 年 7 月、凡斷言匯入結果入清單的步驟一律先切粒度為全部；定位節補一句無下游依賴的一次性關鍵字不入本檔
- 十三對 md 與 csv 全數改動，逐場內容見前一節

計劃層。分冊改的全是非引句欄位，`extract_assertions` 抓不到，改它們不影響對帳。

- `no2_regression_plan/no3_home_dashboard.md`：HD-02 三值那條的層欄自本地資料改為 UI 加本地資料兩值、手段維持 manual-ui；HD-05 的步驟欄自連續向過去滑動超過十五個期間改為連續向過去滑動至最早期間再滑回；HD-05 快取清空那條的層改日誌、驗證者改 Claude、手段改 qa-markers；HD-06 停用排除那條同批改為日誌與 Claude 與 qa-markers
- `no2_regression_plan/no2_recording_core.md`：RC-06 列表出現遺漏期那條的層改本地資料、驗證者改 Claude、手段改 sqlite-local；`:163` 的 qa-markers 驗證者自使用者改 Claude
- `no2_regression_plan/no7_cloud_sync.md`：CS-02 的前置刪掉本機已有交易帳戶類別資料那條、因為 R01 落地那次是零筆；CS-04 的前置自準備超過 2000 筆的匯入資料檔改為以 Debug 工具填滿當日寫入配額、步驟的匯入大量資料同批改；四處 qa-markers 驗證者改 Claude；五處 qa-markers 條件自 Mac 上 Metro 執行中改為 Metro 以 `--client-logs` 啟動並執行中
- `no2_regression_plan/no1_auth_bootstrap.md`、`no6_app_setting.md`、`no8_payment.md`：qa-markers 驗證者改 Claude、qa-markers 條件補 `--client-logs`
- `no2_regression_plan/no10_cloud_functions.md`：CF-04 前置刪掉 capBilling 現無對應測試檔那句；`:122` 的實作錨自 `capBilling.ts` 改 `capBilling.test.ts`，日誌層那條的實作錨維持 `capBilling.ts` 不動

工具層。

- `no1_capability_profile.md`：sqlite-local 的限制欄補一句僅 simulator、實機場次無定位路徑；就緒探測表同列補註
- `no2_qa_tools/query_local_db.sh`：新增 `scene` 子指令，把各場起點與終點的期望形狀寫成具名斷言組，沿用現有 note 與 pass 與 fail 版型與 `fail_count` 退出碼、與 `cmd_assert` 同構。期望形狀的唯一真相取自各場 md 的終點狀態欄加 `no1_fixtures.md`，不另立一份。`--selftest` 同批擴充，造一份缺一個帳戶、多一筆 `_status='deleted'` 隱形列的 db，確認 scene 斷言咬得到
- `no2_qa_tools/check_plan.sh`：新增第八項手段與驗證者一致性。對每個引句，比對分冊檢查點的手段欄與腳本該列手段欄一致、且驗證者欄與能力側寫手段表的執行者欄一致，manual-ui 對使用者、其餘全對 Claude。`--selftest` 造一筆兩側手段不同、一筆驗證者與執行者不符的資料驗它咬得到

impl 層，獨立 branch。

- `regressionFixture.ts` 加 `r02_base` 場景與 `MockDataSettingsScreen` 的 Seed R02 base 按鈕，`regressionFixture.test.ts` 同批更新筆數對帳
- `quotaService.ts` 加 `fillWriteQuotaForTesting` 與 Fill write quota 按鈕
- `SearchScreen.tsx` 補 `QA DBQ search` marker

### 動工順序

第八項一上線就會紅十筆。分冊那十處日誌層檢查點現在寫的是驗證者使用者、手段 qa-markers，而能力側寫的 qa-markers 執行者是 Claude、對應 csv 那些列也全是 Claude節點。這十筆誰勝出要先決定，否則第八項一上線就被當成雜訊關掉。

- 第一步 決定日誌層那十筆的勝出方，建議以能力側寫為準、改分冊驗證者為 Claude
- 第二步 補 `check_plan.sh` 第八項與 `query_local_db.sh` 的 `scene` 子指令，兩者各自過 `--selftest`
- 第三步 impl 三項改動，各自附測試、獨立 branch
- 第四步 腳本層與計劃層的內容改動，逐場改、每場改完跑一次 `check_plan.sh`
- 第五步 全綠後跑第一輪，逐場記起訖、把時長表的人手欄換成實測值

先做前兩步的理由是把關比收益重要。沒有第八項那道機械把關，本方案十餘條手段改動的兩側失配沒有東西擋得住，風險高於它們的收益。
