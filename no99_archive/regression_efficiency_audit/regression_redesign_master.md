# 回歸計劃改造總大綱

本檔統整兩份方案：場次腳本層方案處理 13 場 228 步的重排與手段改掛，impl 與機制層方案處理 marker 補齊、測試假綠、兩支工具強化與原生機制修正。以下是合併後的全局判斷、施工批次、完成判準、效益估算、風險取捨與否決清單。

路徑一律以 `~/` 為錨。impl 指 `~/Doc/ai-company/product/susugigi/no5_product_development/no2_accounting_app`，後端 impl 指同層的 `no3_cloud_functions`，quality 指 `~/Doc/ai-company/product/susugigi/no6_product_quality/no2_accounting_app`，設定 repo 指 `~/.claude`。

---

## 全局判斷

最大的效率損失不是步驟太多，是人眼在做機器的事。228 列裡 135 列掛檢查點，其中大量斷言的內容是筆數、金額、欄位值、日期序列這種可查詢的東西，卻一律掛 manual-ui 由使用者逐筆目視。最露骨的三處：R02 開場手建兩帳戶六類別七筆交易共 15 個實體，R08 為了填滿當日寫入配額去匯入 2100 筆資料，R13 為了驗補產生要跨一個月逐日核對實例。sqlite-local 這個手段在 2026-08-07 才解阻，解阻之後沒有任何一條檢查點被改掛，它在分冊與 13 支 csv 裡的出現次數是零。能力側寫變了，212 個檢查點的手段欄沒有跟著重掛，這是第一個根因。

第二個損失是停等結構。13 場一條單鏈，36 個 Claude 節點就地嵌在使用者的操作序列中間，造成 8 次場中停等。逐節點檢查後，其中六次讀的是整場累積的 Metro log 或當下的 sqlite 快照，資料來源根本不會因為延後而消失，本來就可以推到場尾。真正不能延後的只有兩次：R08 讀雲端 preferences，因為後續三列還原會逐欄覆寫那份文件；R11 讀到期 entitlements，因為時點錯過即失真。節點落位規則只分兩類，狀態相依就地內嵌與零依賴集中 R00，沒有第三類只讀快照可延後，於是所有節點被一律就地嵌入。這是第二個根因。

第三個損失是假綠，它不吃時間但吃可信度，最終還是會變成時間。宣告了卻做不出來的手段有四條：R01 兩列點名 grep QA BOOT 比對 uid，而 QA BOOT 六個落點無一帶 uid；後端 deleteUserAccount、capBilling、verifyTransaction 三支的 cloud-logging 檢查點在應用層沒有對應輸出，Pub/Sub 沒接上與接上且正確不動作在 log 上同形。測試側同型：recurringLogic 的三支正向函式全 repo 零測試呼叫卻被 R00 序 7 收下，deleteTransfer 零測試卻被序 6 宣稱已收，searchTransactions 那個 it 標題承諾排序、body 零排序斷言，findWhere 只比對 type 與 left 不看 comparison，把 notDeleted 改成語意完全相反的寫法五個站點一條都不會紅。check_plan 七項只驗引句兩側對得上，不驗手段是否真的成立，也就攔不住這一類。這是第三個根因：計劃層與 impl 層之間缺一道手段可行性的機械把關。

第四個損失散在機制層，單次都小、乘上 7 小時流程就不小。redirect guard 把命令裡任何一個大於符號當寫檔訊號，第一個被擋的正是對帳配方自己；伴跑判定全活在對話裡，auto-compact 或換 session 等於整場重跑；brevity 每輪注入的 15 字上限與 QA 操作指引的格式鐵律直接打架；12 個雲端節點與 sqlite 查詢沒進 allowlist，使用者正拿著裝置操作時逐次卡權限；main-on-clean-main 在回歸模式下每輪發一次它自己承認是假的警報。

改造後的樣貌是這樣：13 場切成兩鏈，A 鏈 R01 至 R08 加 R13 走 simulator、B 鏈 R10 至 R12 走實機以 seeder 鋪起點，裝置矛盾消失、B 鏈失敗不必回頭重跑 A 鏈。列數自 228 降為 198，場中停等自 8 次降為 2 次。人眼只做人眼才做得到的事，也就是視覺樣式、互動回饋、系統對話框往返；筆數與落庫形狀交給 query_local_db 的 scene 子指令，行為分支交給 Metro log 的 QA 標記。check_plan 自七項擴到九項，手段值域、跨層一致、受阻手段零出現全部機械把關。伴跑狀態落到 `~/.claude/game/regression-runs/` 下的 tsv，中斷可續跑。人手自約 380 分降為 247 分，wall-clock 自 425 分降為 307 分。

---

## 施工批次編排

八個批次，相依關係標在每批的排序理由裡。可平行的批次另行標明。

### 第一批 hook 解阻

- **branch**：`feat/qa-hook-unblock`
- **涵蓋**：`hooks/lib/guards/redirect.sh` 的誤擋修法，把大於符號自字串出現判定改成語法位置判定；同支 guard 的漏擋補齊，補 `cp`、`mv`、`install`、`patch` 的最後位置參數抽取，補 `sed -i` 的檔案參數檢查，補 `python3 -c` 與 `node -e` 的保守 ask；`hooks/tests/windows-enforcement-test.sh` 補兩條 should-pass 與三條 should-block 案例。
- **動哪些 git**：設定 repo `~/.claude`。
- **為什麼排在這裡**：這是全案唯一必須絕對最先的一批。現行 guard 把 `awk 'FNR>1'` 與 `grep '=>'` 判成寫檔並 exit 2，而這兩式正是後續每一批驗收要跑的對帳配方。不先修，後面每批都在半盲狀態下驗收。
- **完成後可以驗到什麼**：主 git 路徑下跑對帳配方不再被擋；`cp` 與 `sed -i` 寫進主 git 的 `no[34567]_` 開始被擋；`windows-enforcement-test.sh` 全綠。

### 第二批 既有矛盾收斂

- **涵蓋**：驗證者歸屬拍板，分冊 10 條 qa-markers 檢查點的驗證者自使用者改為 Claude，與能力側寫執行者欄及 csv 的 9 列對齊；`no1_capability_profile.md` 刪 `QA FINDING`，它從來不是 marker、只出現在 `cleanupScheduleStamps.ts` 的一句註解裡；`no2_r00_static_verification.md` 第 21 行的覆蓋例外表散文改成與索引一致；`no2_regression_plan/no0_index.md` 路徑映射表的 CF 列前綴欄改成純路徑、散文移到表下的註；能力側寫的 sqlite-local 限制欄補一句僅 simulator、實機場次無定位路徑。
- **動哪些 git**：Quality git。
- **為什麼排在這裡**：check_plan 新增的第 8 項第四子判一上線就會紅十筆，紅的正是這批要修的資料。動工順序必須是先修資料再加閘，顛倒過來會讓人把真訊號當雜訊關掉。CF 列前綴欄同理，它是第七批 multi-tier-sync 後端場次點名的前提。
- **與第三批可平行**：不同 git、不同檔，無雙向相依。
- **完成後可以驗到什麼**：分冊、能力側寫、csv 三面對驗證者欄的說法一致；索引與 R00 md 對覆蓋例外表的說法一致；check_plan 現有七項仍全綠。

### 第三批 marker 補齊與 impl 鋪路

- **branch**：`feat/qa-marker-backfill`，三個 git 同名。
- **涵蓋**：修好斷掉手段的四條 marker，也就是 MRK-01 加 MRK-02 讓 QA BOOT 帶 uid 與去重分支、MRK-04 後端 deleteUserAccount 成功路徑與墓碑收尾、MRK-05 capBilling 進入點與四個提前 return、MRK-06 verifyTransaction 成功登記與六個拒絕分支；新增日誌層檢查點的四條，也就是 MRK-08 訂閱閘門、MRK-09 QA RATE convert、MRK-11 匯入略過七條分支統一、MRK-14 schema migration 事件；純診斷鋪路的三條，也就是 MRK-03 資料清除五分支、MRK-07 writeEntitlement 兩道閘、MRK-10 QA SCHED split 與 truncate；場次腳本層點名要的三項 impl 改動，也就是 `regressionFixture.ts` 新增 `r02_base` 場景與對應 seed 按鈕、`quotaService.ts` 新增 `fillWriteQuotaForTesting` 與 Fill write quota 按鈕、`SearchScreen.tsx` 補 `QA DBQ search` marker；`__DEV__` 閘 30 餘條；`QA RATE` 寫進能力側寫命名空間清單。
- **動哪些 git**：impl app module、impl 後端 module、Quality git。三個同名 feat branch、配對 commit。
- **為什麼排在這裡**：marker 必須先進 impl，手段才改掛得成 qa-markers；seeder 與 Fill write quota 必須先存在，第五批的 R02 與 R08 開場才刪得掉那 21 分鐘的手工鋪設。這批是第五批的硬前提。
- **完成後可以驗到什麼**：Metro 帶 `--client-logs` 啟動後 grep 得到 `QA BOOT authEvent uid=` 與 `dedup=`；後端三支 function 在 Cloud Logging 印得出帶 uid 與 reason 的行；設定頁 Debug 區出現 Seed R02 base 與 Fill write quota 兩個按鈕；release bundle 掃不到新增的 QA 字串。

### 第四批 兩支工具強化

- **涵蓋**：`check_plan.sh` 的第 5 項抽取修正，改成只認 `console` 呼叫的引數位置、消掉 `QA A` 誤命中與 `QA FINDING` 註解殘留；第 6 項 glob 強度改為 csv 側逐檔列出、41 條樣式展開後共 64 支檔；新增第 8 項手段值域與跨層一致，四個子判分別管手段欄是能力側寫手段表 id 的子集、類型欄只准四值、驗證者欄只准兩值、每條引句在分冊與 csv 的手段一致且驗證者與執行者欄相符；新增第 9 項受阻手段零出現，現況只有 `callable-api`；新增覆蓋例外表與散文一致的廉價子判；19 處 `/tmp/cp_*.txt` 改 mktemp、兩個 trap 併成一個；第 92 至 93 行的 comm 換成 `grep -vxF -f`；selftest 自單一數字門檻改成集合比對，補第 6、7、8、9 項的壞資料。`query_local_db.sh` 新增 `scene` 子指令，把各場起點與終點的期望形狀寫成具名斷言組，唯一真相取自各場 md 的終點狀態欄加 `no1_fixtures.md`；新增 `--impl` 參數與九類落庫不變式，也就是金額縮放整數擴到全部六欄、時間毫秒擴到全部時間欄並帶 OBS-03 佔位哨兵白名單、schema 版本、串聯軟刪完整性、孤兒外鍵、跨身分汙染、RC-06 實例唯一、RC-01 金額正負號、AS-04 settings 值域；selftest 補 WAL 快照、首動詞白名單、tables 存活分欄三段。
- **動哪些 git**：Quality git。
- **為什麼排在這裡**：`scene` 子指令是第五批七個場尾對賬列的執行體，沒有它那七列寫得出來也跑不出來。第 8 項與第 9 項是第五批十餘條手段改動的護欄，方案作者的原話是把關比收益重要——沒有這道機械把關，兩側失配沒有東西擋得住。第 5 項抽取修正必須在第三批之後，否則新加的命名空間會被舊抽取誤判。
- **完成後可以驗到什麼**：`check_plan.sh --selftest` 的失配項集合恰等於預期集合，而不只是數量湊得上；`query_local_db.sh --selftest` 對每一條新不變式各咬到一筆違例；兩支腳本並行跑不再互相覆寫中間檔。

### 第五批 場次腳本重排

- **涵蓋**：13 場的逐場改寫，列數自 228 降為 198；手段改掛九條，其中三條真正換手段，也就是 HD-05 快取清空改 qa-markers、HD-06 停用排除改 qa-markers、RC-06 補產生改 sqlite-local，另六條只改 grep 對象或收下場次；新增七條佐證列，全部已驗留空、分冊不動；場中停等自 8 次降為 2 次；單鏈切成 A 鏈與 B 鏈；終點狀態與起點狀態八處改寫；前置環境補列，含 Metro 以 `--client-logs` 啟動、可控網路開關、sqlite-local 環境前提、dev build 與 Debug 區可見、R04 執行日須為本月 8 日以後；索引的場次總表時長欄拆成人手、等待、依據三欄，選集政策表全量那格改口徑，新增失敗重進點一節；`no1_fixtures.md` 六處補正。
- **動哪些 git**：Quality git，分冊與腳本兩層同批。
- **為什麼排在這裡**：這批同時吃第三批的 marker 與 seeder、第四批的 scene 子指令與第 8 項護欄，是全案相依最深的一批，只能排在兩者之後。逐場改、每場改完跑一次 check_plan。
- **完成後可以驗到什麼**：`awk -F, 'FNR>1 && NF>0 && NF!=9'` 對 13 支 csv 回零列，證明合併儲存格沒有混入半形逗號；check_plan 七項加新增兩項全綠；引句零改字，反向逐字對帳仍零失配；計數仍為 212 加 0 對 212。

### 第六批 測試補齊與 R00 加強

- **branch**：`feat/qa-assertion-hardening`，兩個 git 同名。
- **涵蓋**：impl 側新增 `recurringLogic.forwardPaths.test.ts` 覆蓋四支正向函式；`transferLogic.test.ts` 補 `deleteTransfer` describe；`localDbService.test.ts` 的 searchTransactions 改寫成涵蓋兩張表的 `it.each` 並補排序與 take 斷言；同檔新增 `expectExcludesDeleted` 並替換五處 `deleted_on` 與兩處 `disabled_on` 的弱斷言；`PremiumContext.storeKit.test.tsx` 補首次解析完成前的視窗斷言；`exportService.test.ts` 補 header describe 收欄序、UTC 偏移、儲存精度，`templateService.ts` 的兩個 header 抽成 exported 常數；`regressionFixture.test.ts` 誠實化，describe 名與 docblock 改成鎖 seeder 側；`PeriodDataStore.test.ts` 補排序 describe；`HomeFilterContext.selectionPersist.test.tsx` 補第二個 describe 收非法持久值回退與讀取失敗不寫回；`realDb.spike.test.ts` 補逐表時間欄毫秒斷言。Quality 側改 `no2_r00_static_verification.csv` 的序 2 預期欄寫死已知數字、序 4 動作欄刪兩條不承載檢查點的樣式、序 5 的 LD-02 毫秒引句剪貼到序 4、序 6 說明欄改掉已過時的敘述、序 7 的 glob 展開五支、序 9 動作欄補三支檔。
- **動哪些 git**：impl app module、Quality git。
- **為什麼排在這裡**：這批只動 R00 那一場與 impl 測試，與第四、五批無雙向相依。排在後面是因為它不擋任何人，不是因為它不重要。
- **可與第四批與第五批平行**：同一個 Quality git 但不同檔，注意 merge 順序即可。
- **完成後可以驗到什麼**：`npm test` 兩批全綠且 skipped 恰為 1；刪掉 `recurringLogic` 任一支測試檔，check_plan 第 6 項會紅；把 `notDeleted` 改成 `Q.notEq(null)`，五個站點的測試會紅。

### 第七批 機制衛生

- **branch**：`feat/qa-mechanism-hygiene`，走正式 plan mode 與 acceptEdits，commit 加 `self-modification` 標籤。
- **涵蓋**：`verification-report.sh` 排除後端 module 並收斂 UI 路徑，與 `design-impl-alignment.sh` 的判定抽成 `lib/common.sh` 的 `hook_is_ui_path`；`multi-tier-sync.sh` 加後端 module 別名對照與 rel 抽取自 `functions/src/` 起算，並補一條後端案例進 `impl-scene-hint-test.sh`；`capability-probe.sh` 掃描面收斂到有回歸計劃的 module，補 qa-markers、sqlite-local、firestore-read 三個零副作用探測；`main-on-clean-main-guard.sh` 認 sim-review 的 active marker 並刪掉那句自承假警報的話；`brevity-refresh.sh` 與 `brevity-meter.sh` 加 session 級 QA 模式旗標；伴跑狀態檔落 `~/.claude/game/regression-runs/`，三處措辭自不落任何檔改回不入 Quality git；`sim-review/SKILL.md` 補伴跑 cwd 前提與場次號用 glob 定位；全域 CLAUDE.md 的 Compaction 復原規範第 2 步補回歸狀態檔；`~/Doc/ai-company/.claude/settings.local.json` 補六條唯讀 allowlist 並清一次性項；memory 的 `project_susugigi_manual_qa_plan.md` 本文重寫，舊結構另開已封存條目。
- **動哪些 git**：設定 repo，加上不在 git 內的 allowlist 與 memory。
- **為什麼排在這裡**：與 Quality 和 impl 無相依，可全程平行。唯一的序列點是伴跑狀態檔與 QA 語體旗標必須在第八批實跑之前落地，否則第一輪跑完仍然沒有可續跑的紀錄。
- **可與第三批至第六批全程平行**。
- **完成後可以驗到什麼**：改一支後端 handler 不再被索討 design canvas port；改後端 impl 拿得到場次點名；開新 session 不再被 LiquidGlassHeaderTemplate 的假缺口洗版；`/sim-review` 期間主 git detached 不再每輪跳提醒；伴跑中斷後重開能印出已完成到第幾列。

### 第八批 第一輪實跑與實測回填

- **涵蓋**：跑一次全量回歸，A 鏈與 B 鏈可分日；逐場記起訖時間；把時長表的人手欄自估值換成實測值並標日期與機器，格式比照能力側寫的探針紀錄；驗證伴跑狀態檔的中斷續跑真的可用；把第一輪撞到的定位不足回頭補成鋪路列。
- **動哪些 git**：Quality git，只改索引的時長表與依據欄。
- **為什麼排在這裡**：所有省時數字目前都是逐列成本模型的推算，現行那組 13 個估值全是 5 的倍數、35 分出現六次、每步平均最大差三倍且方向與工作量相反，查無實測依據。沒有這一批，效益那節的數字永遠是紙上的。
- **完成後可以驗到什麼**：時長表的依據欄自估值改為實測；選集政策表的全量那格對得上實測；伴跑狀態檔在真實中斷情境下復原成功。

---

## 每批的完成判準

### 第一批的判準

- 在主 git 路徑下執行 `awk 'FNR>1' <任一 csv>` 與 `grep '=>' <任一 ts>`，兩者皆放行、exit code 為 0。
- 在主 git 路徑下嘗試 `cp` 一個檔案進 `no[34567]_` 目錄、`sed -i` 改該目錄下的檔，兩者皆 exit 2。
- `python3 -c` 內文同時出現該路徑與寫入意圖時回 ask、不硬擋。
- `hooks/tests/windows-enforcement-test.sh` 全綠，且新增的兩條 should-pass 與三條 should-block 各自單獨驗過。

### 第二批的判準

- 對分冊全文 grep qa-markers 的檢查點，驗證者欄零筆寫使用者。
- 能力側寫命名空間清單不含 `QA FINDING`。
- 索引與 R00 md 對覆蓋例外表的描述互不矛盾，兩處皆為空表。
- `check_plan.sh` 現有七項全綠，尤其第 3 項反向逐字對帳仍零失配，證明只動了非引句欄位。

### 第三批的判準

- Metro 帶 `--client-logs` 啟動、跑一次冷啟動，grep 得到帶 uid 前八碼的 `QA BOOT authEvent` 行，且能分辨 `dedup=true` 與 `dedup=false`。
- 觸發一次刪帳號，Cloud Logging 查得到 `deleteUserAccount 完成 uid=` 與 `appleRevokeFailed=` 欄位。
- 送一則未超標訊息給 capBilling，log 出現 `reason=under_budget` 而非只有沒有錯誤。
- 設定頁 Debug 區點 Seed R02 base 後，帳戶兩筆、類別六筆、交易七筆；點 Fill write quota 後下一次 `checkQuota` 判為不允許，且不會因為日期鍵取法不同被判成跨日歸零。
- 對 release bundle 掃新增的 QA 字串與 30 餘條被套閘的 log 字串，命中數為零。
- `regressionFixture.test.ts` 的筆數對帳同批更新後仍綠。

### 第四批的判準

- `check_plan.sh --selftest` 的失配項集合恰等於第 2、3、4、5、6、7、8、9 項各至少一筆，數量對得上但抓錯項的情況會被偵測出來。
- 對真實資料跑 `check_plan.sh`，第 8 項第四子判在第二批修完後回零筆；若刻意把某條 csv 手段改成 `callable-api`，第 9 項立刻紅。
- `query_local_db.sh --selftest` 對每一條新增不變式各造一筆違例列並全部咬到，含帶小數的 `amount_from`、秒級的 `date`、`user_version` 與宣告不符、串聯半套、孤兒外鍵、跨身分引用、同排程同日期兩筆、支出金額為正、`week_start` 集外值。
- 佔位哨兵白名單生效，`currency_rates.date` 等於 1 的那筆不被誤報。
- 兩支腳本同時在兩個 worktree 跑，中間檔不互相覆寫。

### 第五批的判準

- 13 支 csv 跑 `awk -F, 'FNR>1 && NF>0 && NF!=9'` 回零列。
- `check_plan.sh` 九項全綠。第 4 項計數仍為 212 加 0 對 212，證明引句只搬不刪不增。
- 逐場對照新步驟表，場中停等恰為 2 次，分別是 R08 讀雲端 preferences 與 R11 讀到期 entitlements。
- 索引的執行環境節寫得出兩鏈與失敗重進點，重進點明寫 seeder 鋪不出佔位匯率這件事。
- 每一條 sqlite-local 佐證列都已驗留空，手段欄全 198 列皆單值。

### 第六批的判準

- impl 兩批 `npm test` 全綠，skipped 恰為 1 且該筆為 App.test.tsx 的佔位。
- 反向驗證四則：刪掉 `recurringLogic` 任一支測試檔，check_plan 第 6 項紅；把 `notDeleted` 改成 `Q.notEq(null)`，`localDbService.test.ts` 紅；把 `searchTransactions` 的排序改成 asc，該測試紅；把 `templateService` 的 header 欄序調換，`exportService.test.ts` 紅。
- R00 csv 序 2 的預期欄寫死的數字與實跑一致。
- 序 5 剪走的 LD-02 引句在序 4 逐字存在，check_plan 第 3 項不受影響。

### 第七批的判準

- 改一支後端 handler，verification-report guard 不索討 port 與畫面差異；改一支 impl screen，仍索討。
- 改後端 impl 拿得到場次點名，`impl-scene-hint-test.sh` 原 19 條加新增後端案例全綠。
- 開新 session，capability-probe 對沒有 Quality git 的 module 零輸出，且三個新探測各自在 5 秒內回應。
- `/sim-review` 期間 touch 出 active marker，主 git detached 時 Stop hook 不再對該 repo 發提醒；還原步驟移除 marker 後恢復發。
- 伴跑模式下 brevity 不再注入 15 字上限，退出伴跑後恢復注入。
- 12 個雲端節點與 sqlite 查詢在一輪流程內零權限提示。
- memory 索引那一列與本文都指向現行三層結構，舊結構在另一條標題帶已封存的條目裡。

### 第八批的判準

- 時長表的依據欄全部自估值改為實測值，並標日期與機器。
- 實測人手總數與模型推算的 247 分差距在可解釋範圍內；差距大的場次逐場寫出原因。
- 至少製造一次人為中斷，自狀態檔續跑成功，不需重跑已完成場次。

---

## 預估效益

先講估算依據，數字才有意義。新模型是逐列成本推算：一般 manual-ui 操作列每列 1.5 分，含讀步驟、操作、核對預期；多筆連續輸入的建置列以每筆 1 分計；冷啟列 1.5 分；重裝或安裝 build 3 至 4 分；清空裝置 5 分；系統購買對話框往返 2 分；Claude 節點依手段計 wall-clock，qa-markers 與 sqlite-local 各 1 分、firestore-read 與 cloud-logging 各 2 分；純等待列的人手另計 0.5 至 1 分、等待本身進等待欄。

被拿來比較的現行 425 分是舊估值，它本身查無實測依據，13 個值全是 5 的倍數、35 分出現六次。所以下表的省時是新模型與舊估值的差，不是兩次實測的差，這一點在第八批之前都必須誠實掛著。

| 批次 | 省下的人手分鐘 | 估算依據 |
| --- | --- | --- |
| 第一批 hook 解阻 | 0 | 不動場次，省的是施工期間每次對帳被擋後的重試與繞道 |
| 第二批 矛盾收斂 | 0 | 純資料一致性，省的是第 8 項上線後不被當雜訊關掉的機率 |
| 第三批 marker 與 seeder | 約 24 | R02 開場 seeder 取代 15 個實體手建省 15；R08 填配額自匯入 2100 筆改按鈕省 6；R10 開場 seeder 省 3 |
| 第四批 工具強化 | 約 18 | R13 逐日目視改 scene 對賬省 5；R02、R03、R05、R06、R07 五場的終點或起點逐筆清點各省 2 至 3，合計約 11；R08 手抄六個偏好原值改機器查省 2 |
| 第五批 場次重排 | 約 67 | 淨減 30 列，每列 1.5 分約 45；R07 清單進出自八次收斂為六次省 8；R12 併入 AS-06 後併列省 6；R05 的 CU-05 三列移出省 4；R01 手抄 uid 全數刪除省 2；R11 併列省 2 |
| 第六批 測試補齊 | 0 | 只動 R00 與 impl 測試，R00 是機器時間、使用者不參與 |
| 第七批 機制衛生 | 約 5 | allowlist 補齊消掉約 20 次權限提示、每次約 15 秒 |
| 第八批 實跑回填 | 0 | 這批是把上面所有估值換成實測 |
| 口徑歸正 | 約 19 | R00 的 15 分自人手移入機器等待欄；R11 的放置期自人手移入等待欄後對應的口徑差。這一段是帳面歸正、不是真的省 |
| **合計** | **約 133** | — |

總計：人手自約 380 分降為 247 分，省 133 分、約三成五。wall-clock 自 425 分降為 307 分，省 118 分。以時數講，現行的約 7 小時變成人手約 4 小時 7 分、加上等待與機器時間的 wall-clock 約 5 小時 7 分。索引裡選集政策表的全量回歸那格要改成同一口徑，寫人手約 4 小時、等待約 1 小時。

還有一筆不計入單輪的效益：切鏈之後 B 鏈失敗不必回頭重跑 A 鏈，一次免掉 169 分。以現行單鏈結構，R10 到 R12 任一場出問題就要從 R01 重來，這筆重跑成本在真實使用中出現的機率不低。伴跑狀態檔同理，auto-compact 或換 session 一次的重跑成本按已跑進度計，最壞情況是整場 380 分。這兩筆都不寫進上表，因為它們是機率性的。

---

## 風險與取捨

- **場尾節點延後是拿失敗定位精度換停等次數。** R10 的後端登記與 cloud-logging 兩列延到場尾之後，若後端登記失敗，訊號要到場尾才出現，中間十步的解鎖行為靠 client 端 StoreKit 仍會照常通過。這個代價必須寫進該列的說明欄，讓現場的人知道場尾紅了要往回追十步。
- **併列讓失敗定位變粗。** 一列含四個子動作時，紅了要回頭拆才知道是哪一步。方案的鐵律已把併列限制在不改變斷言強度的地方，但定位粒度確實降了。R12 的清除鏈把四列併成一列是這批裡最粗的一處。
- **切鏈使 A 鏈到 B 鏈的真實資料延續性不再被驗。** R10 改以 seeder 鋪起點、不吃 A 鏈狀態，換到的是重跑成本歸零與裝置矛盾消失。取捨方向是明確的，但要記住現在沒有任何一場在驗跨鏈的資料延續。
- **seeder 繞過 accountLogic 是永久性限制。** 它以 `collection.create` 直寫，不走 `ensureRateForNewAccount`、不種佔位匯率，所以 R05 的 CU-03 前提在 seeder 重入路徑不成立。方案已把這件事寫進失敗重進點一節，但這是 seeder 這條路的固有代價，不是可以修掉的 bug。同理，日幣帳戶與獎金類別必須留在正式流程建立、不能進 seeder。
- **check_plan 第 8 項一上線就紅十筆。** 那是它該有的第一個訊號、不是誤報。動工順序寫成第二批在第四批之前就是為了這件事，順序顛倒的後果是有人把它關掉、然後整套護欄形同不存在。
- **`__DEV__` 閘 30 餘條是正式版行為改動。** 少掉的 log 若有人在靠它排查線上問題，會失去線索。判準已記錄下來供後續沿用，`console.error` 與 `console.warn` 若記的是真異常且不含使用者實際值一律不套閘。`iapService` 那兩條落在 mock 分支、執行期到不了，風險低。
- **拿正確性換速度的只有一處。** R06 新序 15 的快取淘汰斷言改由 R00 的 jest 收下，現場只留連續切期的穩定性煙霧測。這是把端到端證據降級成單元證據，是全案唯一一筆真正的強度讓步。其餘的併列與延後都不改變斷言強度。
- **QA PAYWALL 的四份 log 有漂移風險。** `accCount` 與 `catCount` 是各 case 區塊內的區域變數，不能共用單一 log 行，只能各 case 各印一條。四份複製貼上的格式一旦漂掉，grep 就抓不齊。
- **QA RATE 的去重 Set 是 module 級。** 同一組幣別與倍率在同一個進程只印一次。若某場需要驗同一幣別對的兩次不同匯率，第二次會漏印。R05 的用法目前不會撞到，但改場次時要記得這個限制。
- **建議先不做的第一組：三條純診斷 marker。** MRK-03 資料清除五分支、MRK-07 writeEntitlement 兩道閘、MRK-10 QA SCHED split 與 truncate，三者都不改分冊、不省時、不修任何斷掉的手段，價值只在出事時定位。建議留到第一輪實跑真的撞到才補，避免把第三批撐大成一個難 review 的巨包。
- **建議先不做的第二組：query_local_db 的九類不變式一次全上。** `scene` 子指令是第五批七個對賬列的執行體、屬必要；九類不變式屬額外把關、與省時無關。建議第四批只做 `scene` 加金額與時間兩類，其餘七類另開一期。
- **建議先不做的第三組：multi-tier-sync 的三刀 fork 收斂。** 那是純效能整理、不修任何錯，而動的是每輪都跑的 hook，改壞的代價高於省下的毫秒。後端 module 別名與 rel 抽取兩項要做，fork 收斂緩。

---

## 不建議做的事

以下是盤查過程中看起來像機會、實際上不值得做的。列出來是為了避免以後有人重複提。

- **不要為了讓零引用的命名空間有人用，就去補列收 HD-05 與 RC-07 的檢查點。** `QA DBQ`、`QA PAYWALL`、`QA RCACHE`、`QA UNDO`、`QA VALID` 五個命名空間目前零 csv 引用看起來像浪費，但那幾條檢查點的手段是 jest-app、已由 R00 序 9 與序 10 收下。再收一次是重複登載，而且與分冊手段欄直接矛盾。要用那些 marker 的正確做法是加已驗欄留空的鋪路列。
- **不要把 UI 層的 manual-ui 檢查點硬改掛 qa-markers。** 分冊檢查點帶層欄位，硬改會讓層與手段互相矛盾。13 條 marker 裡真正修好斷掉手段的只有四條，其餘是新增日誌層檢查點或純診斷鋪路，這個誠實分類要守住。
- **不要拿 R01 序 1 的舊版與序 3 的新版兩次 log 做 migration 對照。** 序 1 跑的是舊 build，不含新加的 marker，這條路走不通。要驗 schema 版本走 `PRAGMA user_version`。
- **不要把 `regressionFixture.test.ts` 改成跨 repo 讀 quality 的 fixtures 檔。** impl 有 worktree 慣例，從 impl 相對路徑推 quality git 在主 git 成立、在 worktree 內整條斷掉，寫成 skip 又等於沒驗。正確落點是 quality 側的 check_plan 反向去讀 impl 的常數表，該方向的路徑推導 check_plan 已經有現成的。
- **不要在 query_local_db 加金額上界判準。** `MAX_STORAGE_AMOUNT` 就是 `Number.MAX_SAFE_INTEGER`，對 REAL 欄近乎恆真；而且這支 shell 讀不到 TS 常數，真要判上界得先加參數與解析器，成本遠高於收益。
- **不要在實機場次掛 sqlite-local。** `query_local_db.sh` 以 `xcrun simctl get_app_container` 定位，實機沒有這條路徑。R10 至 R12 的落庫性質斷言維持現狀、不改掛，這是手段的物理邊界。
- **不要把 R00 的 15 分算進省時。** 那是兩次 npm test 的機器時間、使用者不參與。現行估值把它計進人手是口徑錯，改正它是帳面歸正，不是可以拿去報的節省。
- **不要把兩個手段塞進同一格手段欄。** 198 列皆單值是硬不變式，`awk -F,` 取第 8 欄靠的是每列恰 9 個半形逗號。要加第二個手段就另開一列佐證列、該列已驗留空。同理，合併儲存格一律用全形頓號與全形逗號串接，多值已驗欄一律用全形分號。
- **不要用 comm 比對兩份清單。** 多位元組下 sort 定序不保證一致，一律 `grep -vxF`。check_plan 現存那兩處 comm 出現在唯一會被人逐條讀的失敗分支上，必須換掉。
- **不要把 HD-02 三值那條拆成兩條檢查點。** 拆了分冊斷言總數變 213，check_plan 第 4 項的計數立刻失配。只改層欄、不拆條。
- **不要為 R11 的 35 分放置期想辦法加速。** 那是 sandbox 訂閱自然到期的物理時間，不可壓縮。正確做法是移進等待欄、在索引的執行環境節寫明可與其他事並行，讓 wall-clock 與人手時間的分野在總表旁邊就看得到。
- **不要改 `hooks/lib/common.sh` 把 CR 與 LF 壓成空白那段。** 改完 redirect 正則後風險已經降下來，而動它會牽動所有 guard 的輸入形狀，是典型的高風險低收益。
- **不要清 allowlist 裡 `bash -n ~/.claude/hooks/*-guard.sh` 那幾筆。** 那些 wrapper 檔仍在，不是一次性垃圾。該清的是兩筆寫死 pid 的 kill、兩筆 `/tmp` 測試腳本、兩筆一次性 cp、一行寫死路徑的 simctl screenshot。
- **不要在 allowlist 加 gcloud。** 能力側寫的 cloud-logging 環境前提逐字寫同 firestore-read，走的是 firebase CLI，加 gcloud 是擴大授權面換零收益。
- **不要沿用 memory 裡舊 QA 結構那條的內容。** 它描述的是上一代六份文件、1112 條 R-ID、32 場 1064 步與三支已不存在的工具，而 Quality git 的 CLAUDE.md 明令不引用不沿用舊內容。新 session 讀 memory 會先被帶去死結構、再自己撞上禁令。重寫本文、另開一條標題帶已封存的條目收追溯價值，不要兩者混在同一條。
