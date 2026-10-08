# 場次腳本索引

- 本檔為場次腳本層入口，格式權威為 `test_plan_writer` 的場次腳本格式
- 一場次兩檔成對：md 檔頭引導、同名 csv 步驟表
- fixture 人讀權威在 `no1_fixtures.md`，runner golden 在 `no1_fixture_golden.json`，匯入用 CSV 實體在 `assets/`
- 這次該跑哪個檔位見下節；跑起來怎麼排見場次總表

---

## 選集政策

- game-test 先依改動風險推薦檔位
- 使用者確認後才鎖定執行範圍
- 選集以測項 tier 與版本差異組成

| 檔位 | 成本 | 內容 | 什麼時候跑 |
| --- | --- | --- | --- |
| 單元測試 | 5 分 | app 與後端各跑一次 `npm test` | 改完 impl 當下 |
| R00 靜態驗證 | 15 分 | 單元測試加版本綁定 | 開任何一輪之前 |
| core | 部分受阻 | 八個最高風險測項 | 功能完成後與 release 前 |
| standard | 部分受阻 | 全部 core 加 standard | 跨功能或中風險改動 |
| extended | 部分受阻 | 全部五十五案 | 上架前或大改版 |

- core 取 `tier: core`
- standard 固定選 `tier: core` 加 `tier: standard`
- standard 不等於 `impacted-plus-core`
- extended 取全部三種 tier
- 場次承載同時讀取 `測項` 與 `已驗` 欄
- 阻斷場次只記錄 blocked
- 安全場次仍繼續執行
- 同時含兩類場次時狀態為 `partial-blocked`
- core 案例共八案
- RC-06 需要獨立 R13 場次
- 版本差異可再擴張推薦選集
- seed 與 inspect 依最短場次排序
- 裝置限制仍依各案例前置
- 個別場次的必要 capability 受阻時不得開跑
- 阻斷場次必須由 game-test 在第一個 operation 前 fail-closed

---

## 場次總表

| 場次 | 檔 | 涵蓋測項 | 前置場次 | 步驟數 | 預估時長 |
| --- | --- | --- | --- | --- | --- |
| R00 靜態驗證 | `no2_r00_static_verification.md` | 十三場的單元測試層檢查點 | 無 | 21 | 15 分 |
| R01 起始與身分 | `no3_r01_bootstrap_identity.md` | LD-01、AU-01、AU-03、AS-08 前段 | 無 | 15 | 35 分 |
| R02 實體與交易建置 | `no4_r02_entity_recording.md` | EN-01、EN-02、EN-03、RC-01、RC-02、LD-02 | R01 | 30 | 45 分 |
| R03 備份啟動與匯出底線 | `no5_r03_backup_export.md` | CS-02、AS-06、RC-03、CS-03 | R02 | 27 | 45 分 |
| R04 定期排程 | `no6_r04_recurring.md` | RC-04、RC-05 | R03 | 11 | 35 分 |
| R05 幣別與匯率 | `no7_r05_currency.md` | CU-03、CU-04、CU-02、CU-01、CU-05 | R04 | 21 | 25 分 |
| R06 儀表板 | `no8_r06_dashboard.md` | HD-01、HD-02、HD-03、HD-04、HD-05、HD-07 | R05 | 29 | 50 分 |
| R07 清單治理 | `no9_r07_list_governance.md` | RC-07、LD-03、HD-06、EN-05、EN-04 | R06 | 25 | 35 分 |
| R08 偏好與同步 | `no10_r08_preference_sync.md` | AS-01、AS-02、AS-03、AS-04、AS-08、CS-01、CS-04 前段 | R07 | 28 | 40 分 |
| R10 付費與後端登記 | `no12_r10_payment_backend.md` | PM-01、PM-04、PM-02、AS-05、CF-01 | R08 | 27 | 受阻 |
| R11 訂閱生命週期 | `no13_r11_subscription_lifecycle.md` | PM-03、CF-02、PM-05 | R10 | 14 | 受阻 |
| R12 毀滅與重生 | `no14_r12_teardown_rebirth.md` | AS-07、CF-03、CF-04 | R11 | 16 | 受阻 |
| R13 補產生驗證 | `no15_r13_backfill_verification.md` | RC-06 | 無 | 8 | 10 分 |
| R14 身分建立前離線首開 | `no16_r14_pre_identity_offline_launch.md` | AU-02 | 無 | 6 | 15 分 |
| R15 本機 StoreKit 購買與到期 | `no17_r15_local_storekit.md` | PM-06、PM-07、PM-08、PM-09 | 無 | 202 | 60 分 |
| 合計 | 十五場 | 55 測項、263 檢查點 | — | 480 | 安全場次約 6 小時 15 分。三場受阻 |

## 結構化阻斷場次

| caseId | status | blockPhase | reason |
| --- | --- | --- | --- |
| `R10` | `blocked` | `first-operation` | `qa-app-check-isolation-unavailable` |
| `R11` | `blocked` | `first-operation` | `qa-app-check-isolation-unavailable` |
| `R12` | `blocked` | `first-operation` | `qa-app-check-isolation-unavailable` |

## Tier 阻斷展開

| tier | status | 阻斷場次 | 安全場次 |
| --- | --- | --- | --- |
| `core` | `partial-blocked` | R10、R12 | 照常執行 |
| `standard` | `partial-blocked` | R10、R12 | 照常執行 |
| `extended` | `partial-blocked` | R10、R11、R12 | 照常執行 |

- R00、R13、R14 與 R15 為鏈外場次
- R15 為獨立本機商店場次，不承接 R10 或 R11。由 test-ios 啟用 SKTestSession，操作說明見 [白話測試步驟](no17_r15_user_steps.md)。
- R13 以三次 launch 依序完成身分綁定、fixture prepare 與冷啟補產生
- R13 只要求使用者檢視結果
- R14 使用專用 first-launch 入口驗證身分服務離線與恢復。
- R14 不得繞過 proof 執行
- R00 排最前為快速失敗
- R13 排在可執行場次最後，因為它會清空重鋪，放鏈中會破壞閘控計數
- R14 先取得 proof 與同身分清理責任，再開放資料建立。
- **單日走完，不跨夜。** 原設計靠跨夜製造兩件事，兩件都已改由 Debug 工具取代
    - 排程缺口 → R13 以 seeder 直接寫庫，繞開建立當下的自動補產生
    - UTC 零時配額重置 → R10 序 2 以 Reset write quota 抹掉當日計數
- 檔名編號留有 `no11` 空號，該檔為已移除的舊 R09 隔夜場；不回收編號，避免既有 grep 與歷史對不上

---

## 單元測試層的集中

- 102 個檢查點的手段為 jest，與 app 執行狀態零相依
- 全數集中 R00，整輪只跑兩次測試，一次 app 一次後端
- 全數有對應測試檔並由 R00 收下，覆蓋例外表已清空
- LD-01 由兩支測試夾擊：`schema.test.ts` 驗宣告面的鏈連續與欄位齊備，`realDb.spike.test.ts` 以真 LokiJS 引擎起一個資料庫、驗那份 schema 建得起表且九張表可讀寫。前者證明宣告連續，後者證明真的跑得起來
- 手動場次不再各跑一次全套，各場 md 註明本場幾點由 R00 涵蓋
- R00 的說明欄標對應手動場次，僅供追溯、不代表執行順序相依
- 核對列寫測試檔路徑而非群名，路徑取自 `npx jest --listTests`，測試檔改名時 grep 得出失配

---

## Session runtime 解析

| session 條件鍵 | 解析結果 | driver | delegate | 裝置不變式 |
| --- | --- | --- | --- | --- |
| `no-physical-requirement` | `simulator` | `game-test` | `sim-review` | 單一 simulator |
| `physical-in-selection-or-prerequisite` | `physical-device` | `game-test` | `none` | R01–R08 與 R13 同一支專用 QA iPhone |
| `selection-contains-blocked-scenes` | `partial-blocked` | `game-test` | `per-safe-scene` | 阻斷場次不取得裝置 |
| `extended` | `partial-blocked` | `game-test` | `per-safe-scene` | 安全場次沿用單一裝置 |

- game-test 先合併選集與前置鏈
- game-test 先分出安全場次與阻斷場次
- 只對安全場次解析 session route
- 安全場次的 session route 只解析一次
- session 開始後禁止切換裝置類型
- flexible 只有無實機需求時走 simulator
- simulator 解析結果委派 sim-review
- physical-device 建立 manual-device checkpoint

---

## 執行環境

- R01 至 R08 與 R13 沿用 session 鎖定裝置
- R01、R02 與 R08 的 simulator 完全關閉後重開都由 sim-review terminate 並以同 token、新 `open-app-` requestId launch
- 使用者不得直接點無 launch arguments 的 app icon
- 資料狀態逐場累積
- R01 舊版覆蓋段須另開 session
- 乾淨首開只用未曾安裝 app 的專用 QA iPhone 或已清除的 simulator
- 個人 iPhone 不清除整機內容，只跑版本差異的安全升級選集
- R10 至 R12 固定為 `blocked`，不提供 physical-device、simulator 或 manual route
- R10 至 R12 不得用 Production Firebase 設定、Production build、dev log 或 Metro raw uid 繞過阻斷
- R14 使用重新安裝的 QA simulator App。既有 proof 未完成回收時不得重裝。
- R14 不得清除有效 proof 以繞過身分綁定。
- sandbox 購買無法由 simulator 完成
- Xcode 本機 StoreKit 可模擬購買。R15 使用 QA proof 後啟用的 SKTestSession，不能以本機結果代替 Sandbox。
- Apple 續訂通知無法由 simulator 完成
- extended 選集只為阻斷場次記錄 blocked
- extended 的安全場次仍解析裝置
- R00 不需裝置，任何環境皆可先跑
- R13 不吃前場狀態
- 非 extended 的 R13 可獨立走 simulator
- R10 至 R12 的步驟表只保留測試定義，不得執行

---

## 本次試改範圍

- R15 的 12 項情境及 RC-02 採用六項寫法，操作說明與系統取證分開。
- R02 與 R15 的 CSV 使用取證時點欄及取證類型。其他場次暫時沿用舊格式，舊角色註記不分配本次工作。
- 本次只整理上述測項，不推進完整生成基線，不登記執行結果。

## 覆蓋例外表

- 每個檢查點須被至少一個已驗節點引用，例外列此附理由
- **現況無例外。** 261 條全數有腳本引用。引用不代表測試已執行。
- 例外不是永久豁免。補上測試檔即回收進 R00 對應核對列，同批把該列自本表移除
- 清空歷程：2026-08-06 以 `npx jest --listTests` 實測認定九條無對應測試檔；2026-08-07 分兩批補齊
    - 第一批八條——新增 `schema.test.ts`、`preferenceNormalize.test.ts`、`UndoContext.test.tsx`、`quotaService.test.ts` 與後端 `capBilling.test.ts`，另於 `syncEngine.test.ts` 與 `userService.test.ts` 補配額豁免斷言
    - 第二批一條——AS-04 卡在 `PreferenceProvider` 的 effect 有 lazy `import()`、jest 掛不起來；改把 `updateSetting` 的落庫與上傳兩段抽成純函式，由 `preferenceNormalize.test.ts` 直接驗

| 檢查點 | 理由 |
| --- | --- |

---

## 覆蓋對帳

- 在 quality git 根目錄執行 `bash no2_qa_tools/check_plan.sh`
- 十二項一次跑完
- 退出碼非零代表失配

檢核器唯讀，不改任何計劃檔。它自己的正確性由 `--selftest` 把關：造四種已知壞資料，抓不到就報自己壞了。

| # | 項 | 判準 |
| --- | --- | --- |
| 1 | 抽取 | 兩側清單都抽得到東西，抽不到即格式或路徑有問題 |
| 2 | 正向 | 分冊有、腳本無的缺口，逐條等於覆蓋例外表 |
| 3 | 反向 | 腳本有、分冊無，須零失配 |
| 4 | 計數 | 已驗去重加例外等於分冊總數，現為 261 加 0 對 261 |
| 5 | marker | 腳本引用的每個 QA 命名空間存在於 impl 的 `src/` |
| 6 | R00 路徑 | 核對列引用的測試檔樣式，app 與後端兩側合計至少一命中 |
| 7 | 狀態鏈 | 每個前置場次都指向存在的場次 |
| 8 | schema | 基線含 full commit 與 tree，metadata 與能力表欄位合法 |
| 9 | 手段與取證 | 引用手段存在，新格式具備取證時點。本次操作者由 session 分配 |
| 10 | CSV type | 九欄齊備，類型只准合法 enum |
| 11 | QA runtime | App QA 身分、RESULT identity、runtime bridge 與 Firebase 阻斷一致 |
| 12 | 場次 route | R01–R08 與 R13 為 flexible。R10–R12 與 R14 結構化受阻。R15 固定 Simulator。安全場次仍執行 |

- 兩側比對前皆切在第一個全形分號前，與引句取法一致
- fixture 對帳仍為手工：fixture 表名稱與對帳鍵於腳本至少一命中
- 狀態鏈內容等價仍需人眼
- 每場起點應等於前場終點
- 檢核器只驗指向存在
- 對帳於收攏階段與 refresh 時執行
