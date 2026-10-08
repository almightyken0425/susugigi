# 能力側寫

## 定位

- 本檔為 SuSuGiGi 產品的驗證手段真相
- 涵蓋 module `no2_accounting_app` 與 `no3_cloud_functions`
- schema 與引用規則由 `test_plan_writer` skill 承載
- 檢查點的手段欄只准引用本表手段 id

---

## App QA 身分

- `qaScheme=SuSuGiGiApp-QA`
- `qaMode=Debug-QA`
- `qaBundleId=com.almightyken0425.susugigiapp.qa`
- `qaFirebaseProjectId=susugigi-qa`
- `qaGoogleAppId=1:352034825841:ios:40c5c3bcfa630b4a6a1dd0`
- `qaFirebaseConfigSha256=8a349abb287abc45a2e4ad868d1fd93b373f4f878fe03aa4e805e97c31ac489f`
- `qaIdentityMode=disposable-anonymous`
- `productionFirebaseProjectId=susugigi-c4fb1`
- `productionBundleId=com.almightyken0425.susugigiapp`
- sim-review payload 必須逐字沿用
- game-test 不得自行改寫

---

## Session runtime 路由

- `runtime_route` 可為 `none`
- `runtime_route` 可為 `simulator`
- `runtime_route` 可為 `physical-device`
- `runtime_route` 可為 `simulator-or-physical-device`
- flexible route 只准配 `game-test`
- game-test 先鎖定選集與前置鏈
- 選集含實機需求時全程實機
- 前置鏈含實機需求時全程實機
- 實機 session 的 R01–R13 使用同一支 QA iPhone
- extended 固定全程使用 QA iPhone
- session 開始後禁止切換裝置類型
- 無實機需求時 flexible 解析為 simulator
- simulator 解析結果委派 sim-review
- 實機解析結果建立 manual-device checkpoint

---

## 手段表

狀態欄只分可用與受阻，屬機器無關的判定。受阻代表任何機器上都沒有路徑，不是本機缺套件。逐台機的就緒與否見下一節。

| 手段 id | 說明 | 狀態 | 操作需求 | 環境前提 | 限制 |
| --- | --- | --- | --- | --- | --- |
| manual-ui | 於 simulator 或連接 iPhone 操作 App 與觀察畫面 | 可用 | ui | Mac 加 simulator 或已信任 iPhone。Sandbox 購買與續訂通知場次需實機。 | simulator 走 /sim-review。iPhone 由 Xcode 啟動。操作者依本次能力與偏好分配。 |
| manual-device | 通過 game-test 的實機檢查點 | 可用 | device-ui | Mac 加已信任的專用 QA iPhone。場次指定的 log、DB 唯讀通道及 Sandbox 身分成立。 | 不交給 sim-review。任一通道未就緒時不得開始 physical-device 測項。 |
| jest-app | 於 app impl 主 checkout 跑 `npm test` | 可用 | tool | 本機 node_modules 完整 | 依賴不完整時先 `npm ci --legacy-peer-deps` |
| jest-backend | 於後端 impl 的 `functions/` 跑 `npm test` | 可用 | tool | functions 內 node_modules 裝妥 | 依賴不完整時先 npm ci |
| firebase-auth-control | 匯出 QA Auth 身分並驗 exact UID 與 absence | 可用 | tool | Firebase CLI Auth 已登入 | 不得據此推定 Firestore REST 或 gcloud OAuth 已就緒 |
| firestore-read | 以 REST 讀 Firestore 文件驗後端副作用 | 可用 | tool | gcloud Firestore OAuth 可取得 access token | 只准使用 READY identityHash 綁定的 `QA_SESSION_UID`。raw response 只准 bounded Python process memory。 |
| qa-cleanup | 清除本 session 的 QA Firestore fixture | 可用 | tool | gcloud Firestore OAuth 可取得 access token | 只准 canonical QA project 與 stdin UID。Control 必須同 UID 執行 post-delete absent probes。 |
| cloud-logging | 讀 Cloud Logging 的 functions log | 可用 | tool | gcloud OAuth 可讀 QA project logs | log 非結構化，只承諾子字串比對 |
| callable-api | 直呼 healthCheck、verifyTransaction、deleteUserAccount | 受阻 | unavailable | 無 | 三支 onCall 全掛 App Check，外呼被拒。解除靠 debug token 或 emulator。以 firestore-read 加 cloud-logging 間接驗證替代。 |
| sqlite-local | 直查 app 本地 SQLite，走 `no2_qa_tools/query_local_db.sh` | 可用 | tool | Mac 加 booted simulator，app 已跑過 bootstrap | 查的是容器內資料庫的快照副本。app 寫入當下取樣會落在中途狀態。對 app 資料唯讀。 |
| qa-markers | 讀 dev build 的 QA console 標記 | 可用 | tool | Mac 加 Debug build。simulator 由 Metro 轉發，iPhone 由 Xcode 或 devicectl console 擷取。 | Release build 因 `__DEV__` 為 false 不輸出。QA RELEASE 與 QA ANALYTICS 不含 uid 或帳目內容。其他命名空間的測試識別碼不進報告。 |
| qa-command | 由 QA build 接收 `prepare` 啟動請求 | 受阻 | tool | app impl 的 QA build，harness mode 為 `qa` | 只准依 session capability promotion 契約暫時解鎖 |
| qa-probe | 由 QA build 接收 `inspect` 啟動請求 | 受阻 | tool | QA 場景已建立，harness mode 為 `qa` | 只准依 session capability promotion 契約暫時解鎖 |
| local-storekit | 以 SKTestSession 啟用本機商店並測試原生購買 | 可用 | tool | Mac、iOS Simulator、Debug-QA 與 token-bound QA session | 開跑前核對設定雜湊及原生啟用標記。不得替代 Apple Sandbox、簽章與伺服器通知 |

操作需求依共同能力契約定義。`manual-ui` 與 `manual-device` 沿用既有 id，不固定指定人。
準備、操作、取證及觀看安排只記於 session。舊測項的驗證者註記不決定本次分工。
Xcode 或裝置存在只證明環境條件。AI 操作前另核對目前工具能讀取目標畫面與完成所需手勢。
使用者選擇親自操作或觀看時沿用該偏好。換人不能略過本檔的身分、證據與清理條件。

---

## Session capability promotion

- `local-storekit` 使用 R15 獨立 Simulator 場次，開跑前核對本機就緒。
- 本機商品設定與專用 scheme 見 Impl 的 `ios/STOREKIT_TESTING.md`。
- 執行器傳入候選商店雜湊。QA App 消耗有效 proof 後以 SKTestSession 啟用，原生 READY 是必要證據。
- test-ios 同時保持 session proof、QA 身分、商店設定與冷啟動綁定。disposal 清理交易並獨立核對完成標記。
- 本機購買不得解除 R10、R11 或 R12 的 App Check 阻斷。

- `qa-command` 與 `qa-probe` 是唯一可 bootstrap 的受阻手段
- 其他受阻手段仍在開跑前 fail-closed
- QA runtime 靜態 readiness 與 canonical QA config 全數成立後，sim-review 才可進行零寫入 bootstrap launch
- 每個 session 產生一組六十四字元小寫十六進位 secret token
- secret token 只留本機 session
- secret token 不得進入 log、READY、RESULT 或 Quality
- secret token 只從 process environment 的 `SUSUGIGI_QA_SESSION_TOKEN` 載入
- secret token 不得出現在 process arguments
- bootstrap launch 只傳 requestId 與 secret token
- bootstrap launch 不得傳 open-app、prepare、inspect 或 dispose flag
- bootstrap launch 必須直接啟動 isolated identity lifecycle，不得等待 React root、Production App 或 AuthProvider
- bootstrap 開始時確認沒有待回收 proof
- 既有 proof 必須由持有相同 token 的 cleanup 清除，不得直接覆寫
- READY 前只允許檢查並銷毀殘留匿名 Firebase Auth 身分，再建立本 session 新身分
- 殘留身分若非匿名，或匿名身分刪除失敗，必須輸出固定安全 RESULT 並停止
- 殘留匿名身分刪除 resolve 後，必須確認 Auth current user 為 null，才可建立本 session 新身分
- bootstrap 不得沿用前一場 persisted anonymous user
- proof 只保存 token hash 與 Firebase uid hash
- proof 不得保存 raw token 或 raw Firebase uid
- persisted proof 的 key set 必須恰為 `tokenHash`、`uidHash`、`expiresAt`、`state`、`consumedBindings`、`consumedRequestHashes`
- persisted proof 必須在讀取任何欄位前拒絕 raw token、raw uid、未知 key 或舊版額外 key
- 新身分先保存 `staged` 清理憑證，再啟用 `active` 測試憑證
- `staged` 不授權 App mount，只允許同 token 與 uid 的清理
- 啟用寫入失敗保留清理憑證，不輸出 READY
- 清理第一次刪帳失敗保留 `disposing`，同 token 可重試
- 清理憑證本身無法寫入且刪帳失敗時，必須明報可能殘留並停止
- active proof 寫入成功後才可輸出 READY
- proof 初始有效期為八小時
- persisted proof 的 `expiresAt` 不得晚於目前時間加八小時
- 每次成功 operation consume 將有效期滑動八小時
- operation consume 原子綁定 requestId 與 operation payload
- 相同 requestId 或相同 binding 不得重放
- launch-driven runtime 不得發布 `globalThis.__SUSUGIGI_QA__`
- open-app 只可輸出 READY，不得暴露或執行 prepare、inspect
- operation root 只可執行已消耗 proof 綁定的 exact operation 與 value
- operation root 不得以 global adapter 執行第二種 operation 或重放已消耗 operation
- READY 前不得啟動本機 seed、Firestore sync、排程補產生或 backup
- bootstrap launch 不得 seed、寫入或讀取測項資料
- 同一 requestId 的 READY 必須符合匿名身分契約
- READY 成立後，只在當次 session 暫時提升 `qa-command` 與 `qa-probe`
- session promotion 不得改寫本檔的持久狀態
- READY 前不得執行 prepare、inspect 或任何 QA 測項資料寫入
- operation root 必須先消耗 proof 才可掛載 QA App
- AuthProvider 必須核對目前匿名身分的 uid hash
- AuthProvider 遇到 null 或 uid hash 不符時永久鎖住該 root
- terminal latch 後不得匿名重生或執行 post-auth
- AuthProvider 必須將當輪 `isCurrent` 傳入 QA recurring backfill
- Production 未提供 `isCurrent` 時必須維持既有 recurring backfill 行為
- recurring backfill 入口已失效時必須零副作用返回
- recurring backfill 必須在每個 await 後重驗 `isCurrent`
- recurring backfill 必須在 transaction 與 transfer create 前後重驗 `isCurrent`
- guarded caller 加入既有 unguarded in-flight 時必須動態合併 guard
- recurring backfill pending 期間遇到 null 或不同 uid 時不得再產生本地寫入
- READY 逾時、requestId 不符或匿名契約失敗時立即停止
- session 結束前必須執行 QA identity disposal
- disposal 可接受已過期 proof
- disposal 仍須符合相同 token、uid 與 proof state
- disposal begin 只接受 staged、active 或 disposing state
- READY 前失敗時可唯讀取得同 token 的清理 uid hash
- 清理 uid hash 不得提升 READY，不得進入報告或 checkpoint
- Auth delete 後必須確認 current user 為 null
- disposal complete 只清除相同 token 與 uid 的 disposing proof
- disposal 失敗時整場失敗，不得以 simulator erase 或人工刪除冒充成功

---

## Firestore probe 身分綁定

- READY 必須提供 `identityHash`
- `identityHash` 必須為六十四字元小寫十六進位
- READY 不得提供 raw Firebase uid
- bootstrap READY 只保存 `identityHash`，不得在 isolated bootstrap lifecycle 查 SQLite
- cleanup 或首次手動變更前，可先以 Firebase CLI Auth export 將 exact-one uid hash 綁定 READY `identityHash`
- 需要執行 App 資料後，必須再以 canonical QA SQLite `users.id` exact-one 交叉驗證同一 `QA_SESSION_UID`
- Auth export、READY 與 SQLite 任一身分不符時必須 fail-closed
- 沒有 seed 或 inspect 時必須先執行 token-bound open-app
- 首次 firestore-read 前必須完成 Auth export exact-one bind；App 資料已建立時還必須完成 SQLite exact-one 交叉驗證
- SQLite 列舉必須使用 `qaBundleId`
- SQLite 候選只准由 command substitution 捕獲
- SQLite 候選不得直接輸出、寫入 log 或寫入 session 報告
- 每個候選 uid 只在本機計算 SHA-256
- 候選 hash 必須與 `identityHash` exact-one match
- 零筆 match 必須 fail-closed
- 多筆 match 必須 fail-closed
- 零筆 match 不得重試或改用猜測
- 命中的 raw uid 只准留在 shell memory 的 `QA_SESSION_UID`
- 所有 firestore-read resource path 必須由 `QA_SESSION_UID` 衍生
- 場次腳本的每個 firestore-read 動作必須明列 exact resource path
- `txnIndex` exact-doc 是唯一可不直接含 `QA_SESSION_UID` 的 firestore-read path
- `QA_ORIGINAL_TRANSACTION_ID` 只能由 `entitlements/${QA_SESSION_UID}` 的 exact-doc response 擷取
- `QA_ORIGINAL_TRANSACTION_ID` 與 provenance 只准留在 shell memory
- `QA_ORIGINAL_TRANSACTION_ID` 必須符合 `^[0-9]{5,32}$`
- `QA_ORIGINAL_TRANSACTION_ID_PROVENANCE` 必須為 `session-entitlement-exact-doc`
- capture 完成時 `QA_ORIGINAL_TRANSACTION_OWNER_HASH` 必須等於 READY identityHash
- txnIndex probe 只准呼叫 `run_qa_txn_index_exact_doc_probe`
- txnIndex wrapper 只接受單一 `present` 或 `absent` mode
- txnIndex wrapper 不接受 caller 提供 resource path
- `present` 必須讓 owner uid SHA-256 同時等於 READY identityHash 與 `QA_ORIGINAL_TRANSACTION_OWNER_HASH`
- `absent` 只接受 canonical exact-document not-found，且不得宣稱 owner uid 已驗
- txnIndex document id、owner raw uid 與 provenance 不得進入 log、可見證據或持久工件
- 禁止依 newest 文件推定身分
- 禁止依任意文件推定身分
- 禁止 collection-wide probe 推定或搜尋本 session 文件
- log、session 報告與持久工件不得包含 raw uid
- Firestore REST 原始回應必須以 bounded Python process memory parse 讀取
- Firestore REST 原始回應不得進 shell memory 或落盤
- shell 只准接收 allowlisted scalar、baseline 或 profile verdict
- 不得直接輸出 Firestore REST 原始回應
- 可見證據中的 uid 一律遮罩為固定字串 `[QA_SESSION_UID]`
- R01 與 R08 的 metadata baseline 只准留在 session shell memory
- baseline 不得進 argv、log、可見證據或獨立暫存值
- disposal 只銷毀 Firebase Auth 身分
- disposal 不代表 Firestore 測試資料已清除

---

## Session cleanup 聚合

- Firestore fixture cleanup 與 Firebase Auth disposal 是兩個獨立結果
- `cleanup_qa_fixtures.sh` 只接受 `--project susugigi-qa --session-uid-stdin`
- 最外層 shell 必須是 Control 提供的 trusted launcher
- Control 必須在 spawn bash 前拒絕並清除 `BASH_ENV` 與 `ENV`
- Control 必須在 spawn bash 前清除 `SHELLOPTS`、`BASHOPTS`、`BASH_XTRACEFD` 與 `PS4`
- malicious `BASH_ENV` sentinel 整合測試必須證明 sentinel 零執行、helper 零呼叫與 UID 零洩漏
- helper 進入後必須再次拒絕 Production project、`BASH_ENV`、`ENV` 與任何非空 emulator、endpoint、proxy、CA 或 loader override
- helper 必須移除 child environment 的 emulator、endpoint、proxy、CA、loader 與 shell startup override
- helper 內部檢查不是 shell startup injection 的安全邊界
- Python transport 必須以 isolated mode 啟動，並拒絕與移除 Python path、home、SSL key log 或 dynamic loader 注入
- helper 只准把 raw uid 經 stdin 傳給 checked-in OAuth REST transport
- raw uid 不得進 argv、log、可見輸出或持久檔
- REST host 固定為 `https://firestore.googleapis.com`
- transport 必須拒絕 redirect 並停用 proxy handler
- transport 每次 response 最多讀四 MiB 加一 byte，超過四 MiB 必須 fail-closed
- 取得 token 前必須直接檢查 active gcloud config，proxy、API endpoint 或 custom CA 設定一律 fail-closed
- root collection ids 只准 accounts、categories、transactions、transfers、currency_rates 與 schedules
- root collection ids 可為六個固定 id 的子集，支援冪等與 partial cleanup，不要求六者同時存在
- 出現未知第七 collection 或任一 nested collection 時必須在刪除前 fail-closed
- transport 必須分頁列舉六個 allowlisted collection
- pagination 必須有固定頁數上限，重複 page token、collection id 或 document name 一律 fail-closed
- transport 必須逐筆驗證 delete status，全部 child 成功後才可刪 users root
- helper 不得輸出 raw uid 或 REST 原始回應
- transport exit 0 只代表受控刪除請求完成，不代表 cleanup 成功
- Control 必須以同一個 shell-memory `QA_SESSION_UID` 執行 users 文件、六個子集合與 root collection ids 的 post-delete absent probes
- post-delete absent probes 未全數成立時 Firestore cleanup 為失敗
- gcloud Firestore OAuth provider 缺少時整體 cleanup 狀態固定失敗
- gcloud Firestore OAuth provider 缺少或 Firestore cleanup 失敗時仍必須繼續 Firebase Auth disposal
- session 最終結果必須聚合 Firestore cleanup 與 Auth disposal
- 任一結果失敗時 session cleanup 整體 fail-closed
- cleanup 聚合只輸出固定狀態，不得輸出 raw uid、token 或 REST 原始回應

---

## 永久隔離阻斷

- QA App 不載入或註冊 App Check
- R10 的 verifyTransaction 與 txnIndex route、R11 的 subscription route、R12 的 deleteUserAccount 都要求 App Check
- R10、R11 與 R12 的結構化狀態固定為 `blocked`
- R10、R11 與 R12 的固定阻斷代碼為 `qa-app-check-isolation-unavailable`
- R10、R11 與 R12 不提供 physical-device、simulator 或 manual 執行 route
- game-test 必須在各阻斷場次的第一個 operation 前記錄 `blocked`
- 阻斷場次不得中止同一選集的安全場次
- 同時含兩類場次時結果為 `partial-blocked`
- QA AuthProvider 的 terminal latch 另外使 R12 同一 root 無法在刪除身分後匿名重生
- 清除前的 raw uid 只准以 `QA_SESSION_UID` 留在 session shell memory
- 清除後只准在 shell memory 比較新舊 READY `identityHash`
- 可見證據只記錄 identityHash 比對 verdict，不得記錄 raw uid
- 不得以 Production Firebase 設定、Production build、dev log 或 Metro raw uid 繞過阻斷

---

## 就緒探測表

R14 的身分建立前入口與清理接手契約見 [首次離線啟動](no3_run_scripts/no16_r14_pre_identity_offline_launch.md)。
它只允許初始 null 觸發實際匿名登入。匿名身分建立後先保存原有 proof，執行器取得同身分清理責任後才放行資料寫入。
已觀察身分後的 null、非匿名及身分切換仍套用 terminal latch。
離線由 QA 專用 Auth transport 故障注入提供，恢復後連真正的 QA Firebase。

同一份計劃在兩台機上可跑的手段不同。就緒指令為零副作用的本地探測，開跑前逐項實測，不憑印象。

| 手段 id | 就緒指令 | Windows | Mac |
| --- | --- | --- | --- |
| manual-ui | `xcodebuild -version` 成功；實機另需 `xcrun devicectl list devices` 看得到已信任 iPhone | 不成立 | Xcode 成立，iPhone 待連接，2026-08-25 |
| manual-device | `xcrun devicectl list devices` 看得到專用 QA iPhone；場次的 log 與 DB 唯讀探測成功 | 不成立 | iPhone 與兩條通道待實測，2026-08-25 |
| jest-app | 於 app impl 跑 `node -e "require.resolve('jest/package.json')"` | 成立 | 成立，2026-08-17 |
| jest-backend | 於 functions 跑 `node -e "require.resolve('jest/package.json')"` | 成立 | 成立，2026-08-07 |
| firebase-auth-control | `command -v firebase` 加 `firebase login:list` 有有效 Firebase CLI Auth | 不成立 | 成立，2026-08-07 |
| firestore-read | `gcloud auth print-access-token` 可取得 Firestore REST OAuth token | 不成立 | 每場實測 |
| qa-cleanup | cleanup shell 與 Python transport tests 全綠，且 `gcloud auth print-access-token` 可取得 Firestore OAuth token | 不成立 | helper stub 成立，gcloud OAuth 每場實測 |
| cloud-logging | `gcloud auth print-access-token` 可取得 QA project log 所需 OAuth token | 不成立 | 每場實測 |
| qa-markers | simulator log 或 iPhone console 內含 `QA ` 前綴列 | 不成立 | simulator 成立，iPhone 待連接，2026-08-25 |
| sqlite-local | 於 quality git 跑 `bash no2_qa_tools/query_local_db.sh --bundle-id com.almightyken0425.susugigiapp.qa path` 印得出路徑 | 不成立 | 成立，2026-08-07 |
| local-storekit | 核對候選商店雜湊、SKU 與週期，並在本次 QA session 取得原生 READY 及交易狀態。清理入口須能核對 CLEANED | 不成立 | 每場核對。設定存在不能單獨證明就緒 |

- Windows 側不裝 firebase CLI，屬既定決議、不是待補項
- Firebase CLI Auth 只供 Auth export、exact UID 與 absence control
- gcloud Firestore OAuth 供 Firestore REST read 與 fixture cleanup
- Firebase CLI Auth 與 gcloud Firestore OAuth 的 readiness 不得互相推定
- Windows 側無 iOS 執行環境，manual-ui、qa-markers 與 sqlite-local 永不成立
- 表內日期只代表歷史探測。本次工具、裝置與操作者就緒結果只留 session，不從歷史日期推定可執行。
- qa-markers 的就緒指令只驗擷取結果，不驗 Metro 啟動參數。Metro 未帶 `--client-logs` 時該指令回不成立，處置是重啟 Metro 補上選項，不是判該手段失效
- sqlite-local 的 path、tables、assert、sql 與 profile 都必須明確傳入 `qaBundleId`
- `r08_original_language` profile 只接受 stdin UID，並從 canonical snapshot 取 exact-one live `settings.language`
- `r08_original_language` profile 排除 `_status='deleted'` tombstone
- `r08_original_language` profile 只輸出 `profile=r08_original_language language=<code>`
- sqlite-local 必須拒絕 `productionBundleId`
- sqlite-local 正式介面不得接受 `--db` 或任意資料庫路徑 override
- sqlite-local 的資料庫來源只准由 canonical QA bundle 的 simulator data container 定位
- 以 QA bundle 搭配 Production 資料庫路徑的 override 必須 fail-closed
- sqlite-local 必須同時 canonicalize QA data root 與 database parent，並只接受 exact `Documents/watermelon.db`
- sqlite-local 必須拒絕 database、WAL 或 SHM 任一來源檔為 symlink
- sqlite-local snapshot 必須使用 `cp -P`，並在查詢前拒絕複製後仍為 symlink 的 database、WAL 或 SHM
- QA container 內指向 Production database 的 symlink escape 必須 fail-closed，且不得輸出資料內容
- sqlite-local snapshot 必須在 current shell 設定 `SNAP_DIR` 與 `DB`，不得以 command substitution 呼叫 snapshot
- sqlite-local cleanup 必須刪除 snapshot directory，並將 `SNAP_DIR` 與 `DB` 歸零
- sqlite-local selftest 必須證明 explicit cleanup 與 EXIT trap 都刪除 snapshot database、WAL 與 SHM

---

## QA harness 契約

| 手段 id | operation | 允許 id | 回傳 |
| --- | --- | --- | --- |
| qa-command | `prepare` | `r02_end`、`r06_large_history`、`r06_large_history_cleanup`、`r09_stale_schedule` | `QA RESULT` 的 `result.value` 為 `QaPrepared` |
| qa-probe | `inspect` | `accounting.fixture-summary`、`accounting.large-history-overlay`、`accounting.schedule-backfill` | `QA RESULT` 的 `result.value.schema` 為 `qa.evidence/v1` |

- `prepare` 只改 QA 本機資料
- 相同場景可重複建立
- `inspect` 不得改任何資料
- `accounting.fixture-summary` 驗 fixture 全貌
- `r06_large_history` 只新增當前 QA user 的 marker rows
- `r06_large_history` 新增二萬筆交易與四百筆轉帳
- 支出交易固定一萬筆
- 每筆支出固定一百
- 收入交易固定一萬筆
- 每筆收入固定一百
- 轉出固定兩百筆
- 轉入固定兩百筆
- 每筆轉帳固定五十
- 轉帳帳戶必須同幣別
- 支出金標固定一百零一萬
- 收入金標固定一百零一萬
- 紀錄數金標固定二萬零四百
- 期間餘額金標固定零
- `r06_large_history` 未確認離線時立即失敗
- `accounting.large-history-overlay` 驗完整 shape
- 完整 shape 包含交易方向與金額
- 完整 shape 包含類別型別與帳戶
- 完整 shape 包含轉帳方向與金額
- 完整 shape 包含同幣別帳戶
- 完整 shape 包含四個金標
- 完整 shape 包含一千八百二十五天日期分布
- idempotent fast path 只接受完整 shape
- shape drift 不得命中 fast path
- currency drift 不得命中 fast path
- `r06_large_history_cleanup` 只清當前 QA user 的 marker rows
- `r06_large_history_cleanup` 完成前驗 marker rows 歸零
- cleanup 不受網路狀態限制
- R06 固定在 cleanup 成功後恢復網路
- `accounting.schedule-backfill` 驗補產生結果
- mode 非 `qa` 時立即停測
- Production 不暴露 `prepare` 與 `inspect`
- Production 不暴露 QA Debug UI
- 遠端資料仍走 firestore-read
- 遠端日誌仍走 cloud-logging

---

## QA fixture 同步隔離契約

- `prepare` 與 `inspect` 都以 `qa-fixture-reset` reason 暫停 sync
- suspend reason 同時保存在記憶體與持久層
- `prepare`、完全關閉後的 `inspect` 與 post-delete absent probes 全程保持 suspend
- fixture seed 在第一筆 fixture row 前把 exact user 的 `Settings.lastSyncedAt` 重設為 null
- watermark 重設失敗時不得建立任何 fixture row
- golden 登記的每個 remote fixture scene 都必須在 prepare 前完成 global session UID 綁定，且 exact UID fixture 子樹已通過 post-delete absent probes
- prepare RESULT 與 inspect RESULT 的 facts 必須依 `no1_fixture_golden.json` 獨立比對
- 候選 RESULT 的 `verdict=pass` 不得作為唯一通過依據
- 只有 token-bound `open-app` launch 可解除 `qa-fixture-reset`
- open-app resume 前不得啟動 remote probe、initial backup 或增量 backup
- open-app 後 initial backup 不得因 device cooldown 被 skip
- open-app resume 後必須等待 `QA BACKUP mode mode=initial` 再對帳 Firestore

---

## R06 同步隔離契約

- Load 寫入前先暫停同步
- 暫停狀態先寫入記憶體
- 暫停狀態同步寫入持久層
- Load 等待既有 in-flight sync 完成
- restart hydrate 後先套用暫停狀態
- sync snapshot 排除 exact marker
- sync push 排除 exact marker
- 排除範圍只含交易與轉帳
- marker 前綴或後綴不得被排除
- Load 失敗先清 marker rows
- Load 失敗於 marker 歸零後釋放同步
- cleanup 成功於 marker 歸零後釋放同步
- cleanup 失敗時保持同步暫停
- race tests 鎖定暫停與釋放順序

---

## QA Debug UI 契約

- QA Debug UI 只存在於 QA App graph
- `Load R06 large history` 按鈕執行 `r06_large_history`
- `Remove R06 large history` 按鈕執行 `r06_large_history_cleanup`
- Load 未確認離線時立即失敗
- Load 成功前核對完整 shape 與金標
- Remove 成功前核對 marker rows 歸零
- Load 與 Remove 套用同步隔離契約
- Load 與 Remove 都限制當前 QA user
- simulator 由 game-test 委派 sim-review command
- 實機由 manual-device checkpoint 操作按鈕
- Production App graph 不得匯入 Debug UI

---

## Native launch 契約

| 用途 | 輸入 | 值 |
| --- | --- | --- |
| 對帳鍵 | `--qa-request-id` | 符合 `(?:bootstrap|dispose|first-launch|inspect|open-app|prepare)-[0-9a-f]{32}` 的 requestId |
| Session 密鑰 | `SUSUGIGI_QA_SESSION_TOKEN` environment | 六十四字元小寫十六進位 secret token |
| 手動開啟 | `--qa-open-app` | 固定為 `true` |
| 建置場景 | `--qa-prepare` | 已登記場景 id |
| 讀取證據 | `--qa-inspect` | 已登記檢查 id |
| 銷毀身分 | `--qa-dispose-identity` | 固定為 `true` |
| 首次離線啟動 | `--qa-first-launch` | 固定為 `true`。僅 R14 使用。 |

- requestId 必須符合 `(?:bootstrap|dispose|first-launch|inspect|open-app|prepare)-[0-9a-f]{32}`
- requestId 的 operation prefix 必須與本次 launch kind 完全相同
- 每次 launch 必須傳 requestId 與 session token
- 每次 launch 恰為 bootstrap、first-launch、open-app、prepare、inspect 或 dispose
- bootstrap 不帶任何 operation flag
- open-app 只供 manual-ui 場次
- simulator route 的完全關閉後重開一律由 sim-review terminate 後重新 launch
- simulator 重開必須沿用同一個 session token
- simulator 重開必須產生新的 `open-app-` 加三十二字元小寫十六進位 requestId
- 使用者不得直接點沒有 launch arguments 的 app icon
- 相同 requestId 在同一 session 不得重用
- prepare 與 inspect 不得同次 launch
- 冷啟動探測只傳 inspect
- bootstrap launch 只傳 requestId 與 session token
- disposal launch 只傳 requestId、session token 與 `--qa-dispose-identity true`
- disposal launch 不得掛載 Production App 或 AuthProvider
- malformed、mixed 或未知 flag 值必須切到 immediate fail-closed lifecycle
- invalid lifecycle 不得掛載 Production App 或 AuthProvider
- invalid lifecycle 必須輸出固定安全 error RESULT 後停止

---

## Runtime log 契約

- READY 前綴為 `QA READY `
- READY JSON schema 為 `qa.runtime/v1`
- READY 頂層必須且只能含 `schema`、`requestId`、`state`、`isAnonymous`、`identityMode` 與 `identityHash`
- READY 必含 requestId 與 state
- READY 的 state 必須為 `ready`
- READY 必含 `isAnonymous`
- READY 的 `isAnonymous` 必須為 `true`
- READY 必含 `identityMode`
- READY 的 `identityMode` 必須為 `disposable-anonymous`
- READY 必含 `identityHash`
- READY 的 `identityHash` 必須為六十四字元小寫十六進位
- READY 不得包含 Firebase uid
- RESULT 前綴為 `QA RESULT `
- RESULT JSON schema 為 `qa.runtime/v1`
- RESULT 套用 operation-specific exact schema
- RESULT 頂層的四個 base keys 為 `schema`、`requestId`、`operation` 與 `value`
- 成功 RESULT 頂層必須且只能含四個 base keys 與 `result`
- 失敗 RESULT 頂層必須且只能含四個 base keys 與 `error`
- RESULT 頂層必須且只能含 `result` 或 `error` 其中一項
- RESULT 頂層不得出現額外欄位
- RESULT 必含 requestId、operation 與 value
- prepare 與 inspect 的 top-level value 必須等於 requested scene 或 check
- 成功 RESULT 必含 result
- 失敗 RESULT 必含 error
- prepare 與 inspect 的外層 error allowlist 固定為 `QA_AUTH_REQUIRED`、`QA_DISABLED`、`QA_DISPOSABLE_ANONYMOUS_REQUIRED`、`QA_INVALID_LAUNCH_REQUEST`、`QA_OPERATION_FAILED`、`QA_SESSION_STALE`
- launch 的外層 error allowlist 固定為 `QA_AUTH_REQUIRED`、`QA_INVALID_LAUNCH_PLAN`、`QA_INVALID_OPERATION_PLAN`、`QA_LAUNCH_FAILED`、`QA_OPERATION_AUTH_GUARD_FAILED`、`QA_OPERATION_AUTH_REQUIRED`、`QA_OPERATION_AUTH_RESTORE_TIMEOUT`、`QA_OPERATION_GATE_FAILED`、`QA_OPERATION_IDENTITY_MISMATCH`、`QA_OPERATION_SESSION_PROOF_REJECTED`
- bootstrap 的外層 error allowlist 固定為 `QA_ANONYMOUS_BOOTSTRAP_FAILED`、`QA_ANONYMOUS_PROVIDER_DISABLED`、`QA_AUTH_RESTORE_FAILED`、`QA_AUTH_RESTORE_TIMEOUT`、`QA_BOOTSTRAP_ENTRY_LOAD_FAILED`、`QA_BOOTSTRAP_ENTRY_SELECTION_LOAD_FAILED`、`QA_BOOTSTRAP_ENVIRONMENT_LOAD_FAILED`、`QA_BOOTSTRAP_IDENTITY_MODULE_LOAD_FAILED`、`QA_BOOTSTRAP_LAUNCH_PLAN_LOAD_FAILED`、`QA_BOOTSTRAP_LAUNCH_PLAN_RESOLUTION_FAILED`、`QA_DISPOSABLE_ANONYMOUS_REQUIRED`、`QA_FIREBASE_AUTH_CONFIG_REJECTED`、`QA_FIREBASE_AUTH_NETWORK_FAILED`、`QA_SESSION_PROOF_CLEAR_FAILED`、`QA_SESSION_PROOF_WRITE_FAILED`、`QA_SESSION_PROOF_WRITE_FAILED_IDENTITY_REMAINS`、`QA_STALE_ANONYMOUS_DISPOSAL_FAILED`
- dispose 的外層 error allowlist 固定為 `QA_AUTH_RESTORE_TIMEOUT`、`QA_DISPOSABLE_ANONYMOUS_REQUIRED`、`QA_DISPOSAL_PROOF_CLEAR_FAILED`、`QA_DISPOSAL_PROOF_STATE_FAILED`、`QA_DISPOSAL_SESSION_PROOF_REJECTED`、`QA_IDENTITY_DELETE_FAILED`、`QA_IDENTITY_DELETE_NOT_CONFIRMED`
- prepare 與 inspect 遇到其他 code 時固定回傳 `QA_OPERATION_FAILED`
- launch 遇到其他 code 時固定回傳 `QA_LAUNCH_FAILED`
- 任一 operation 不得接收其他 operation 的專屬 code
- prepare 成功 result 只准 `ok`、`runId` 與 `value`
- prepare 成功 value 只准 `sceneId` 與 `fingerprint`
- inspect 成功 result 只准 `ok`、`runId` 與 `value`
- inspect 成功 value 只准 `schema`、`checkId`、`verdict` 與 `facts`
- prepare 與 inspect 的內層失敗只准 `ok`、`runId`、`code` 與 `recoverable`
- 內層失敗不得包含 exception message
- evidence fact 只准 `key`、`actual`、`expected` 與 `pass`
- evidence fact 的 actual 只准字串、數字、布林或 null
- evidence fact 的 expected 只准字串、數字、布林或 null
- evidence fact 不得包含任意巢狀物件
- disk 前 marker filter 必須先驗 operation-specific exact schema
- evidence 的字串 actual 與 expected 必須在 disk 前轉為 deterministic SHA-256 digest
- evidence 的 bare Firebase uid 不得進入可見 log 或持久工件
- prepare 成功以 result 的 `ok: true` 判定
- prepare 成功時 `result.value` 為 `QaPrepared`
- prepare 的 `result.value.sceneId` 必須等於 requested scene
- inspect 成功以 result 的 `ok: true` 判定
- inspect 的 `result.value.schema` 必須為 `qa.evidence/v1`
- inspect 的 `result.value.checkId` 必須等於 requested check
- inspect 的 `result.value.verdict` 須為 `pass`
- signature facts 只作 candidate consistency evidence
- golden 的 `signatureIds` 必須以 exact fact key 對應固定 rule id
- signature facts 不得單獨決定 final 通過
- final 通過必須另有 scene 對應的獨立 Firestore 或 SQLite profile
- disposal RESULT 的 operation 必須為 `dispose`
- disposal RESULT 的 top-level value 必須為 `identity`
- disposal RESULT 的 `result.ok` 必須為 `true`
- disposal RESULT 的 `result.value.identityMode` 必須為 `disposable-anonymous`
- disposal RESULT 的 `result.value.authDeleted` 必須為 `true`
- disposal RESULT 不得包含 Firebase uid
- invalid launch RESULT 的 requestId 必須為 `invalid`
- invalid launch RESULT 的 operation 必須為 `launch`
- invalid launch RESULT 的 value 必須為 `null`
- invalid launch RESULT 的 error 必須為 `QA_INVALID_LAUNCH_PLAN`
- invalid launch RESULT 不得包含 Firebase uid、token 或 API key
- READY 等待上限為三十秒
- RESULT 等待上限為一百二十秒
- 逾時、schema 錯誤或 requestId 不符即停測
- prepare 失敗時不得繼續 inspect

---

## QA runtime 靜態 readiness

- game-test 必須以 `check_plan.sh --runtime-control` 指定已選定 Control 版本
- 跨層行為檢核執行 `check_runtime_entrypoints.py`
- 檢核必須執行 READY window、原生 proof reader 與長駐流程的負向測試
- 原生回收測試必須編譯實際 native module，以隔離 Auth 與儲存替身模擬失敗
- READY 重複、憑證不符、逾時、輸入中斷與清理失敗都必須拒絕成功
- 原生測試必須覆蓋啟用寫入失敗後的刪帳失敗與同 token 重試
- 缺少 checked-in 入口或只具備文字契約時不得開跑
- 此檢核不啟動 App，不代表線上測項已通過

| 元件 | 零副作用探測 | 目前狀態 |
| --- | --- | --- |
| QA scheme | `test -f ios/SuSuGiGiApp.xcodeproj/xcshareddata/xcschemes/SuSuGiGiApp-QA.xcscheme` | 成立 |
| native inputs | `rg -q -- '--qa-request-id|--qa-open-app|--qa-prepare|--qa-inspect' ios/SuSuGiGiApp/BuildEnvironmentModule.m` 與 `rg -q 'SUSUGIGI_QA_SESSION_TOKEN' ios/SuSuGiGiApp/BuildEnvironmentModule.m` | 成立 |
| runtime bridge | `rg -q 'QA READY|QA RESULT|qa.runtime/v1' src/qa/registerQaRuntime.ts src/qa/QaRuntimeBridge.tsx` | 成立 |
| large history overlay | `rg -q 'r06_large_history|r06_large_history_cleanup|accounting.large-history-overlay' src/services/regressionFixture.ts src/qa/` | 成立 |
| QA Debug UI | `rg -q 'r06_large_history|r06_large_history_cleanup' src/screens/Settings/MockDataSettingsScreen.tsx` | 成立 |
| R06 sync isolation | `rg -q 'suspend|resume|inFlight|localOnly' src/qa/ src/services/` | 成立 |
| Production isolation | Production graph 同時通過 canonical symlink 與 lexical `src/qa` symlink escape 測試 | 成立 |
| QA anonymous runtime guard | `rg -q 'isAnonymous|disposable-anonymous|QA_DISPOSABLE_ANONYMOUS_REQUIRED' src/qa/registerQaRuntime.ts src/qa/registerQaRuntime.test.ts` | 成立 |
| QA session proof | native store 只保存 SHA-256，TTL 為八小時，operation 成功後滑動 | 成立 |
| QA operation gate | 每次 requestId 與 operation binding 只可 consume 一次 | 成立 |
| QA Auth terminal latch | null 或 uid hash 不符後不得重生或 post-auth | 成立 |
| QA recurring identity guard | AuthProvider 傳入 optional `isCurrent`，所有 await 與 create 邊界 fail-closed | 成立 |
| Firebase selector | `test -f ios/scripts/select-firebase-config.sh` | 成立 |
| Xcode Firebase phase | 順序為 `Resources` → `Select Firebase Configuration` → `[CP-User] [RNFB] Core Configuration` | 成立 |
| Production resource isolation | Xcode Resources 不含固定的 `GoogleService-Info.plist` | 成立 |
| QA Firebase config | `test -f ios/GoogleService-Info-QA.plist` | 依本機私密設定 |
| QA config project binding | config 的 `PROJECT_ID` 等於 `susugigi-qa` | 依本機私密設定 |
| QA config App binding | config 的 `GOOGLE_APP_ID` 等於已登記 QA App | 依本機私密設定 |
| QA config bundle binding | config 的 `BUNDLE_ID` 等於 `com.almightyken0425.susugigiapp.qa` | 依本機私密設定 |
| QA config digest binding | config 的 SHA-256 等於 `qaFirebaseConfigSha256` | 依本機私密設定 |
| QA stale identity disposal | bootstrap 先刪除 persisted anonymous user，再建立本 session 新身分 | 成立 |
| QA entry App Check isolation | `index.qa.js` 不匯入或初始化 AppCheck | 成立 |
| QA native App Check isolation | AppDelegate 的 provider registration 只編入非 QA build | 成立 |
| QA OAuth route isolation | QA config 使用 QA URL scheme，且 QA build 不編入 GoogleSignIn handler | 成立 |
| QA SQLite bundle gate | 所有 probe 明確傳入 `qaBundleId`，Production bundle 必須拒絕 | 成立 |
| Production Firebase config | `test -f ios/GoogleService-Info.plist` | 依本機私密設定 |
| Production Firebase project | config 存在時 `PROJECT_ID` 等於 `susugigi-c4fb1` | 依本機私密設定 |
| Production bundle | config 存在時 `BUNDLE_ID` 等於 `com.almightyken0425.susugigiapp` | 依本機私密設定 |
| QA 身分 | 同 requestId 的 READY JSON 含 `isAnonymous=true`，且 `identityMode` 符合 `qaIdentityMode` | 待 runtime 證據 |
| QA 身分銷毀 | proof begin 後刪除 Auth，確認 null，再完成 proof 清除 | 待 runtime 證據 |

- qa-command 與 qa-probe 整體狀態為受阻
- 阻斷原因含匿名 READY runtime 證據尚未取得
- 匿名 READY runtime 證據由 game-test preflight 機械核對
- 文字聲明不得取代匿名 READY runtime 證據
- QA plist 固定放在 iOS 根目錄
- QA plist 不得放在 App source 目錄
- QA 與 Production plist 必須同層分檔
- Firebase selector 遇到未知 configuration 時必須失敗
- Firebase selector 遇到配對 config 缺少時必須失敗
- Production plist 不得供 QA bundle 使用
- Production Firebase project 不得供 QA build 使用
- Production guard 必須攔截 multiline static import
- Production guard 必須攔截 CommonJS require
- Production guard 必須攔截 dynamic import
- Production guard 必須攔截指向 `src/qa` 的 canonical symlink alias
- Production guard 必須攔截從 lexical `src/qa` symlink 逃逸
- config 到位不代表能力已可用
- PROJECT_ID、GOOGLE_APP_ID 與 BUNDLE_ID 相符仍不足以取代 SHA-256 對帳
- QA plist 的任何欄位漂移都必須 fail-closed
- bootstrap 不得以 timeout race 包裝匿名身分建立
- bootstrap 刪除殘留匿名身分失敗時不得建立替代帳號或輸出 READY
- READY 只代表本 session 新建立的匿名身分，不得接受前一場殘留帳號
- 同 requestId 與 session proof 的匿名 READY 成立後，只提升當次 session；持久狀態維持受阻
- session 收尾必須銷毀當次匿名 Firebase Auth 帳號
- 身分銷毀只刪匿名 Auth 帳號，不宣稱清除 Firestore 測試資料
- reset 只能作用於當次 QA user
- 狀態變更需重跑所有靜態探測

---

## QA 標記命名空間

腳本的 qa-markers 檢查點只准引用本清單，且每個命名空間必須在 app impl 的 `src/` 命中。對帳配方見 `test_plan_writer` 的場次腳本格式。

`QA BOOT`、`QA BACKUP`、`QA QUOTA`、`QA PREF`、`QA PREMIUM`、`QA SCHED`、`QA SEED`、`QA UNDO`、`QA DBQ`、`QA PAYWALL`、`QA RCACHE`、`QA FOCUS`、`QA VALID`、`QA FINDING`、`QA RELEASE`、`QA ANALYTICS`

---

## 總則

- 測項定義可引用受阻手段
- 受阻引用只宣告能力需求
- game-test 執行前逐項查 readiness
- 除 `qa-command` 與 `qa-probe` 的 session bootstrap 例外外，任一必要能力受阻即 fail-closed
- 受阻時不得啟動測項 operation runtime
- `qa-command` 與 `qa-probe` 受阻時只准依 session capability promotion 啟動 isolated bootstrap lifecycle
- 就緒探測不成立時標記本次未驗
- 場次前置逐字沿用環境前提

---

## 探針紀錄

每筆標明在哪台機測的。跨機不可推論。

- 2026-08-25 探針，Mac
    - Xcode 26.2 與 devicectl 506.6 可用
    - ios-deploy 可用
    - iPhone 尚未連接，manual-ui 實機分支與 qa-markers 實機分支待實測
    - 實機 Debug 記錄由 Xcode console 或 devicectl `--console` 擷取

- 2026-08-17 探針，Mac
    - 記帳 App impl 可解析 Jest
    - 本次不需安裝依賴
    - 大型歷史測試使用生成資料
    - 個人匯入資料不進測試工件
- 2026-08-07 探針，Mac
    - app impl 與後端 functions 的 node_modules 都已完整，未重跑 `npm ci`。改以實跑驗收：app 側 97 個測試檔全過、846 條斷言通過，後端側 11 個測試檔全過、89 條斷言通過
    - app 側全量跑需帶 `--forceExit`。LokiJS adapter 不自行收 worker，不帶會留 hung process
    - firebase CLI 已裝且登入只證明當時 Auth control 可用，不推定 Firestore REST 與 cloud-logging 就緒
    - QA 標記通道成立，但成立條件與原先假設不同。RN 0.79 起 JS log 預設改進 React Native DevTools、不進 Metro stdout，log 檔只會留一行提示說 log 已搬家。Metro 啟動帶 `--client-logs` 才會轉發，該選項在 RN 0.79.6 預設為關、且已標記為 deprecated
    - 帶該選項冷啟一次，log 檔命中 `QA BOOT`、`QA RCACHE`、`QA PREMIUM`、`QA BACKUP` 四個命名空間 → qa-markers 就緒
    - sqlite-local 解阻。`xcrun simctl get_app_container` 定位得到容器，資料庫檔落在容器的 Documents 下，查詢器 `no2_qa_tools/query_local_db.sh` 已落地並通過自驗
    - 命名空間對帳的已知誤命中：impl 的 `src` 側以 `QA [A-Z]+` 抓取時會多出一個 `QA A`，來源是兩支測試檔註解裡的手動場次編號，不是 console 標記。腳本側對 impl 側的單向對帳不受影響，反向對帳會誤報
- 2026-08-06 探針，Windows
    - app impl 的 node_modules 缺 `@babel/core`、`@jest/core`、`@nozbe/watermelondb`，`.bin` 目錄不存在
    - `npm ci` 因 `@types/react-native` 的 peer 衝突失敗；lockfile 本身完整、1151 個套件齊備
    - 改跑 `npm ci --legacy-peer-deps` 修復成功，`jest --listTests` 列出 91 支 → jest-app 就緒
    - 後端 `functions/` 跑 `npm ci` 裝妥 670 個套件 → jest-backend 就緒
    - firebase CLI 依決議不裝 → firebase-auth-control 在本機永不成立；Firestore REST 與 cloud-logging 另看 gcloud OAuth
- 2026-08-05 探針，Windows
    - 已由上一筆取代，保留供追溯
