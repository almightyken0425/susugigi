# SuSuGiGi 測試交接契約

本契約由 Quality owner 維護。協調者與環境接收者讀取同一份。
現有 driver 協定值 `sim-review` 對應 test-ios，`game-test` 對應 test-run。

## 候選版本鎖定

- 每次都鎖定：
    - target kind
    - target ref
    - Control Plane root
    - Control Plane identity
    - trusted Control Plane root
    - trusted Control Plane identity
    - Quality root
    - Quality identity
    - Quality definition digest
    - case-set digest
- `feature` 可使用 worktree snapshot。
- worktree snapshot 必須鎖定：
    - base HEAD full commit
    - base HEAD full tree SHA
    - worktree snapshot digest
- `feature` 可使用 dirty Quality worktree。
- dirty Quality 必須鎖定：
    - base HEAD full commit
    - base HEAD full tree SHA
    - Quality worktree snapshot digest
- clean Quality 必須鎖定：
    - full commit
    - full tree SHA
    - Quality digest
- Impl staged changes 存在時停止。
- Impl unstaged 與 untracked 可納入 snapshot。
- Quality tracked 與 untracked 可納入 snapshot。
- `regression` 使用 release candidate。
- release candidate 必須鎖定：
    - target full commit
    - target full tree SHA
    - Release candidate manifest
- release candidate working tree 必須乾淨。
- regression 的 Quality working tree 必須乾淨。
- SHA 必須使用完整值。
- manifest 必須匹配 target。
- manifest 必須匹配 Quality。
- digest 依品質定義重算。
- case-set digest 綁定目前 Quality。
- 任一身分不一致時停止。
- `controlPlaneWorktreeOrRepo` 必須是啟動本次流程的 Control Plane root。
- `controlPlaneIdentity` 必須綁定該 root 的完整 commit、tree 與 snapshot digest。
- `trustedControlPlaneRoot` 必須是與候選 Control Plane root 分離的乾淨 Control Plane root。
- `trustedControlPlaneIdentity` 必須綁定 trusted root 的完整 commit 與 tree。
- `qualityWorktreeOrRepo` 必須是產生 Quality identity 的 repo 或 worktree。
- root 必須解析為實體目錄。
- root 不得為 symlink。
- 委派後由 `test-ios` 建立 session-owned immutable private snapshot。
- trusted verifier 從 payload 鎖定 commit blob 物化。
- candidate Control 與 Quality 依 source-pre、private snapshot、source-post 三段匹配。
- 後續 helper、Quality executable 與 golden 只從私有唯讀副本執行。
- 每次 helper 前後重算私有 tree manifest，後驗失敗時丟棄成功輸出。

---

## 身分契約

兩個接收者必讀 [身分與 Digest 契約](identity_contract.md)。
Control、Impl、Quality、selector 與 case-set 使用同版欄位與排序。
重算失敗只停止相依場次，不能使用舊版摘要補成通過。

## 結構化阻斷閘門

- 展開選集與前置鏈後，先讀取 Quality `no3_run_scripts/no0_index.md` 的 `結構化阻斷場次`。
- 結構化阻斷場次只接受 `caseId`、`status`、`blockPhase` 與 `reason` 四個欄位。
- 每個 selected QA case 必須收集所有承載它的 Rxx 場次。
- 任一 selected QA case 找不到承載場次時停止。
- 每個承載場次都展開完整場次前置閉包，再取所有閉包的精確聯集。
- 不得只選第一個、最新或最小的承載場次。
- `caseId` 比對承載場次聯集與前置閉包聯集的 Rxx ID，不直接比對功能測項 ID。
- `status` 為 `blocked` 且 `blockPhase` 為 `first-operation` 時，保留該 case 的 blocked 結果與固定 reason。
- 阻斷閘門在 App session 路由解析前執行。
- 命中 `first-operation` 時只記錄該場次與相依者的 `blocked` 結果。
- 未依賴阻斷場次的安全場次繼續執行。
- 阻斷場次不得進入 QA build 後的執行佇列。
- 阻斷場次不得進入 `test-ios` payload。
- 全部 App 場次都受阻時才省略 App session。
- 靜態檢查仍涵蓋 blocked 與安全場次。
- 阻斷場次不得因 `physical-device`、`simulator-or-physical-device` 或 regression depth 轉為可執行。
- `manual-device`、直接呼叫後端與重用 Production App Check 都不得繞過阻斷。
- `qa-app-check-isolation-unavailable` 表示 QA build 沒有可用的非 Production App Check attestation。
- R10、R11 與 R12 固定使用 `qa-app-check-isolation-unavailable`。
- R10、R11 與 R12 只記 blocked 並永不執行。
- R14 命中結構化阻斷時只記 blocked 並永不執行。
- Quality 缺少結構化阻斷表、欄位不完整或鏡射值不一致時停止。

---

## App session 路由

- 每個 selected case 都要有 route metadata。
- `runtime_route` 與 `driver` 必須合法配對。
- 配對不合法時停止。
- 先展開選集與前置鏈。
- 再解析 App session 路由。
- `regression extended` 固定全程實機。
- 鏈內含 `physical-device` 時：
    - session 解析為 `physical-device`。
    - `R01` 至 `R13` 全程使用同一 QA iPhone。
- 實機鏈只接受：
    - `physical-device`
    - `simulator-or-physical-device`
- 實機鏈含 `simulator` 時停止。
- 未選實機時：
    - `simulator-or-physical-device` 解析為 `simulator`。
    - simulator case 維持 `simulator`。
- `none` case 不啟動 App 環境。
- `simulator-or-physical-device` 不要求 `manual-device`。
- 解析結果只留 session。

---

## 能力閘門

- App session 路由必須先解析。
- 收集所有 selected capabilities。
- 實機 session 加入 `manual-device`。
- 每個能力必須存在於側寫。
- 定義狀態為 `可用` 時執行就緒探測。
- 受阻能力例外只接受 `qa-command` 與 `qa-probe`。
- 例外原因只能是匿名 READY runtime 證據缺少。
- `qa-app-check-isolation-unavailable` 不適用受阻能力例外。
- 其他受阻能力仍立即停止。
- 每個能力都執行就緒探測。
- 任一探測未通過時停止。
- QA build 身分必須確認。
- QA Firebase project 必須非 Production。
- QA Firebase App 必須匹配 `.qa` bundle。
- QA Firebase 必須使用拋棄式匿名帳號。
- Production project 裡另一個 Firebase App 不算隔離。
- 隔離不成立時停止破壞性 App case。
- Production 隔離必須確認。
- 閘門在第一個 case 前完成。
- 手動操作不得替代能力缺口。

---

## R14 首次啟動入口

R14／AU-02 使用 [首次離線啟動場次](../no16_r14_pre_identity_offline_launch.md) 的專用入口。以下一般 bootstrap 條件不替代此入口。

- build 前先設定場次與測項，核對鎖定 payload 的 `--qa-first-launch true`。
- 重新安裝只限 QA bundle，既有 proof 尚未回收時停止。
- 第一次 launch 使用 first-launch，冷啟動使用既有 open-app。
- AuthProvider 可在無身分時呈現實際離線與重試畫面。post-auth 資料寫入仍等待 native proof 與清理接手回條。
- READY 前只額外允許固定 `QA BOOT anonymous signIn start`，且必須先觀察到原生空身分 marker。
- 空資料與預設資料由 `qa-first-launch.py` 核對 canonical QA container。一般 SQLite path 探測延至 DB 建立後。
- READY 上限 600 秒。首頁完成上限 30 秒。其他場次維持既有上限。

## No-write capability bootstrap

- 每個 App session 的第一次 launch 固定為身分 bootstrap。
- 每次 launch 恰好屬於 bootstrap、open-app、prepare、inspect 或 dispose 其中一種。
- bootstrap 是唯一不帶 operation flag 的 launch。
- prepare 與 inspect 不得在同一次 launch 傳入。
- 匿名身分閘門適用所有 App session。
- capability session 提升只處理 `qa-command` 與 `qa-probe`。
- selected cases 使用 qa-command 或 qa-probe 時，兩者的靜態探測必須全數通過。
- QA build 與 Firebase 身分閘門必須先通過。
- 身分 bootstrap launch 必須路由 `QaIdentityBootstrapApp`。
- `QaIdentityBootstrapApp` 先刪除 stale anonymous Auth，再建立新的匿名 Firebase Auth。
- bootstrap 不得恢復或重用舊匿名身分。
- bootstrap、每個後續 operation 與 disposal 使用同一個 session token。
- session token 由 `test-ios` 以 64 字元十六進位高熵值建立。
- session token 只由 `test-ios` 保存於當次程序記憶體。
- session token 不進委派 payload、checkpoint、log、完成回報或 crash artifact。
- READY 前只允許匿名 Firebase Auth 身分寫入。
- READY 前不得 mount `QaApp` 或 `AuthProvider`。
- READY 前不得執行 App 資料 seed、資料庫寫入或同步。
- bootstrap launch 不得執行 prepare、inspect 或 dispose。
- bootstrap launch 使用唯一 requestId。
- 每個後續 operation 使用高熵且不重用的 requestId。
- READY 必須匹配同一 requestId。
- READY 必須通過拋棄式匿名身分閘門。
- READY identityHash 必須為六十四字元小寫十六進位。
- READY identityHash 必須逐字等於 native session proof 的 uid hash。
- READY 不得包含 raw Firebase uid。
- bootstrap requestId 不得產生 RESULT。
- READY 通過後只提升當次 session 的 qa-command 與 qa-probe。
- 未被 selected cases 使用的能力不得提升。
- Quality 的持久能力狀態維持受阻。
- operation launch 只能在 READY 通過後 mount `QaApp`。
- operation gate 必須在 mount `QaApp` 前原子驗證並 consume native session proof。
- 一般 `qaLaunchArguments` allowlist 只接受 prepare、inspect 與 `--qa-open-app true`。R14／AU-02 另接受互斥的 `--qa-first-launch true`。
- seed 與 inspect 都為 none 且 case 需要開 App 時，必須使用 open-app operation。
- manual-only App case 的 `qaLaunchArguments` 固定為 `--qa-open-app true`。
- manual-only App launch 不得使用 requestId-only 或無 flag launch。
- open-app operation 使用同一個 session token 與高熵且不重用的 requestId。
- open-app operation 通過 proof gate 後才能提示手動操作。
- bootstrap 失敗時停止所有 operation。

---

## QA Firebase 身分綁定

- `qaFirebaseProjectId` 由鎖定 target 的 QA plist 派生。
- `qaGoogleAppId` 由同一份 QA plist 派生。
- `qaFirebaseConfigSha256` 由同一份 QA plist 派生。
- `qaIdentityMode` 固定為 `disposable-anonymous`。
- QA plist 使用 `GoogleService-Info-QA.plist`。
- SuSuGiGi Accounting 固定使用 `susugigi-qa`。
- SuSuGiGi Accounting 固定使用 `1:352034825841:ios:40c5c3bcfa630b4a6a1dd0`。
- SuSuGiGi Accounting 固定使用 `8a349abb287abc45a2e4ad868d1fd93b373f4f878fe03aa4e805e97c31ac489f`。
- `susugigi-c4fb1` 為明確拒絕值。
- plist 的 `BUNDLE_ID` 必須等於 `qaBundleId`。
- plist 的 `GOOGLE_APP_ID` 必須等於 `qaGoogleAppId`。
- resolver 不讀取 Production plist。
- QA worktree 不需要 Production plist。
- resolver 失敗時停止。
- `.firebaserc` 不參與 project 選擇。
- Firebase project alias 不參與 project 選擇。
- Firebase active project 不參與 project 選擇。

委派者用原生唯讀工具從鎖定 target 的 QA plist 提取交接值。委派後的 resolver 只由 [QA build 程式](ios_runtime/build_1.sh) 與 [建置核對程式](ios_runtime/build_2.sh) 在私有快照內執行。

- `TARGET_ROOT` 取自鎖定 target 的 `implWorktreeOrRepo`。
- `CONTROL_PLANE_ROOT` 只取自鎖定的 `controlPlaneWorktreeOrRepo`。
- resolver 只從已驗證的私有 Quality 快照執行。
- `qaFirebaseProjectId` 使用 resolver 的完整輸出。
- `qaGoogleAppId` 使用 QA plist 的完整值。
- `qaFirebaseConfigSha256` 使用 QA plist 的 SHA-256。
- `qaIdentityMode` 不接受其他值。
- 每個 Firebase probe 顯式使用此 project id。
- Firebase CLI probe 必須帶 `--project "$QA_FIREBASE_PROJECT_ID"`。
- Firestore REST probe 必須在資源路徑帶入此 project id。
- Firestore document read 只接受受支援的 OAuth provider。
- 目前受支援的 Firestore OAuth provider 為已登入且可非互動執行的 `gcloud auth print-access-token`。
- Firebase CLI 沒有 Firestore document read 指令，不得以 delete、export 或 emulator 指令替代。
- 缺少受支援 provider 時只回 `QA_FIRESTORE_AUTH_PROVIDER_UNAVAILABLE` 並 fail-closed。
- Auth absence probe 使用 `firebase auth:export`、顯式 QA project 與 non-interactive mode。
- Firebase、Auth、Firestore、gcloud endpoint override 與 proxy 必須拒絕並從 child environment 移除。
- 所有 Python runtime helper 使用 isolated mode。
- 啟動 Bash、Firebase CLI 或 gcloud 前，Control 父層 wrapper 必須先拒絕 `BASH_ENV`、`ENV`、Node preload、TLS key log 與動態連結器注入。
- `SHELLOPTS` 與 `BASHOPTS` 只從 child environment 移除，不得因目前 shell 的正常非空值拒絕 session。
- probe 無法顯式指定 project 時停止。
- `firestore-read` 與 `cloud-logging` 保存 project id 證據。

---

## SQLite-local bundle binding

- QA_BUNDLE_ID 只取自 payload 的 `qaBundleId`。
- sqlite-local readiness 與每次 probe 都必須使用 payload 鎖定的 `qaBundleId`。
- Production bundle id `com.almightyken0425.susugigiapp` 為明確拒絕值。
- `QA_BUNDLE_ID` 不以預設值或已安裝 App 推導。
- `query_local_db.sh` 未顯式帶 bundle id 時停止。
- `QUALITY_ROOT` 必須匹配已鎖定的 Quality identity。
- `QUALITY_ROOT` 只取自鎖定的 `qualityWorktreeOrRepo`。
- sqlite-local readiness 必須執行 `run_qa_sqlite_local_probe path`。
- 每次 sqlite-local probe 都必須經過 `run_qa_sqlite_local_probe`。
- wrapper 只接受 `path`、`tables`、`assert` 與帶單一 query 的 `sql`。
- R08 profile 只接受 `r08_original_language`，raw UID 只經 stdin。
- R13 profile 只接受 `r13_schedule_backfill`，raw UID 只經 stdin。
- R13 final pass 必須對 candidate RESULT、獨立 SQLite aggregate 與 `QA SCHED` generated count 三方一致。

執行程式只由 [SQLite 綁定程式](ios_runtime/sqlite_binding_1.sh) 維護。先核對私有快照，再透過 run_session_snapshot_command 執行。協調者不另持一份可執行 wrapper。

---

## Firestore probe 身分綁定

- READY identityHash 必須為六十四字元小寫十六進位。
- READY identityHash 必須逐字等於 native session proof 的 uid hash。
- READY 不得包含 raw Firebase uid。
- 首次 firestore-read 前必須列舉 canonical QA SQLite 的 `users.id`。
- bootstrap READY 後不得立即 bind SQLite。
- 首次 firestore-read bind 必須晚於首個 authorized operation READY 與 AuthProvider post-auth 收斂。
- firestore-read 前沒有 prepare、inspect 或 open-app 時必須先執行 token-bound open-app operation。
- SQLite 列舉必須使用 payload 鎖定的 `qaBundleId`。
- SQLite candidates 必須以 command substitution 捕獲，不得直接輸出。
- SQLite candidates 的 stdout 與 stderr 必須完整捕獲。
- 每個候選 uid 只在本機計算 SHA-256。
- 候選 hash 必須與 READY identityHash exact-one match。
- 零筆 match 必須 fail-closed。
- 多筆 match 必須 fail-closed。
- zero 或 multi match 不得列出候選 uid。
- 命中的 raw uid 只准留在 shell memory 的 `QA_SESSION_UID`。
- R03 pre-seed cleanup 可先用 QA Auth export 對 READY identityHash 做 anonymous UID exact-one bind。
- Auth export 的 raw UID 只准由 command substitution 收進 `QA_SESSION_UID`。
- Auth export 的零筆或多筆 match 必須 fail-closed，且不得輸出候選 UID。
- 所有可能遠端寫入的 fixture prepare 前必須清除該 QA UID 的既有 subtree。
- 每次 prepare 都重新 cleanup 並確認 users 文件與六個子集合 absent。
- R13 在 cleanup 前先以 Auth export exact-one 對應 READY identityHash。
- R13 必須在 cleanup 與 post-delete absent probes 成功後 prepare。
- R13 prepare 必須早於 open-app、resume 與舊 SQLite 查詢。
- R13 prepare 完成後才以 SQLite exact-one 交叉驗證相同身分。
- R08 第一個語系變更前先用 Auth export exact-one 綁定 READY identity，再私下保存原語系。
- R08 CS-01 開始前才另行保存 updatedAt baseline。
- R01:11 identity invariant 只含 uid、provider、email 與 createdAt。
- R01:11 另私下保存 lastLoginAt 與 updatedAt，R01:15 只接受兩值不倒退。
- R03 CS-03 新增與修改後核對十筆 live transaction、兩筆 transfer 與零額外 live row。
- 刪除後核對九筆 live transaction 與一筆具有有效刪除時間的 tombstone。兩筆 transfer 保持不變。
- 兩筆 transfer 固定為 2000 對 2000 與 1000 對 4500。
- pre-seed cleanup 失敗時不得 launch prepare。
- 首個 authorized operation READY 後仍須以 SQLite exact-one bind 做第二次一致性確認。
- 所有 firestore-read resource path 必須由 `QA_SESSION_UID` 衍生。
- R10 至 R12 永久受阻，因此 runtime 不得建立、解析或讀取 transaction index path。
- 禁止依 newest 文件推定身分。
- 禁止依任意文件推定身分。
- Firestore driver 的 stdout 與 stderr 必須完整捕獲。
- 不得直接 echo Firestore probe 原始輸出。
- Firestore probe 判讀只在 shell memory 或本次 temporary file 執行。
- 可見輸出只包含 allowlisted facts。
- 可見 log 與報告必須先以 `[QA_SESSION_UID]` 取代 raw uid。
- Firestore probe 失敗只回固定安全碼。
- 不得回傳 Firestore driver 原始錯誤或 command line。
- Firestore probe 使用 temporary file 時 cleanup 必須刪除。
- log、session 報告與持久工件不得包含 raw uid。
- disposal 只銷毀 Firebase Auth 身分。
- disposal 不代表 Firestore 測試資料已清除。
- 正常與 cleanup disposal 嘗試後都必須清除 `QA_SESSION_UID`。

---

## 拋棄式匿名身分閘門

- App READY 必須回傳 QA 身分證據。
- READY identityMode 必須為 `disposable-anonymous`。
- READY isAnonymous 必須為 `true`。
- 缺欄位時停止。
- 任一值不符時停止。
- 第一個 seed 或 write 前必須通過 READY 身分閘門。
- 任何可能遠端寫入 fixture 的 operation 前必須先綁定 cleanup UID。
- prepare 與 inspect 期間 fixture sync 維持 suspended，不等待 backup marker。
- 合法 open-app 才恢復 fixture sync 並觸發 backup。
- 匿名帳號只供目前 QA session。
- 所有 case 與 fixture cleanup 完成後刪除匿名帳號。
- fixture cleanup 失敗時仍必須嘗試匿名帳號 disposal。
- fixture cleanup 與 disposal 失敗各自記錄，任一失敗都使 session 失敗。
- dispose RESULT operation 必須為 `dispose`。
- dispose RESULT value 必須為 `identity`。
- dispose RESULT identityMode 必須為 `disposable-anonymous`。
- dispose RESULT authDeleted 必須為 `true`。
- dispose RESULT 不得包含 `uid`。
- dispose 失敗時整體結果判定 `fail`。
- dispose 失敗後仍執行環境還原。

---


## Simulator 委派

- 只委派已解析的 simulator case。
- `simulator-or-physical-device` 委派時轉為：
    - `runtimeRoute` 為 `simulator`
    - `driver` 為 `sim-review`
- 委派 payload 必填：
    - `confirmedTestType`
    - `confirmedRegressionDepth`
    - `targetKind`
    - `targetRef`
    - `targetIdentity`
    - `controlPlaneWorktreeOrRepo`
    - `controlPlaneIdentity`
    - `trustedControlPlaneRoot`
    - `trustedControlPlaneIdentity`
    - `qualityWorktreeOrRepo`
    - `qualityIdentity`
    - `qualityDefinitionDigest`
    - `caseSetDigest`
    - `firestoreCheckpointMap`
    - `sqliteCheckpointMap`
    - `implWorktreeOrRepo`
    - `buildProfile`
    - `qaScheme`
    - `qaMode`
    - `qaBundleId`
    - `qaFirebaseProjectId`
    - `qaGoogleAppId`
    - `qaFirebaseConfigSha256`
    - `qaIdentityMode`
    - `runtimeRoute`
    - `driver`
    - `caseIds`
    - `sceneIds`
    - `manualSteps`
    - `expectedEvidence`
    - `logMarkers`
    - `qaLaunchArguments`
- `buildProfile` 必須為 `QA`。
- `runtimeRoute` 必須為 `simulator`。
- `driver` 必須為 `sim-review`。
- `qaIdentityMode` 必須為 `disposable-anonymous`。
- 實機路由一律拒絕。缺少必填欄位時停止。
- Git SHA 必須使用完整值。回傳的 identity 與 digest 必須逐字一致。
- clean `trustedControlPlaneIdentity` 使用 `kind`、`repository`、`commit` 與 `tree`。
- clean case-set domain 只接受 `susugigi.case-set-digest/v1`。
- dirty case-set domain 只接受 `susugigi.case-set-snapshot-digest/v1`。
- dirty identity 只接受 feature。regression 收到 dirty identity 時停止。
- dirty identity 不得回寫 manifest。
- `qaFirebaseProjectId` 必須完整保留。
- `qaGoogleAppId` 必須完整保留。
- `qaFirebaseConfigSha256` 必須完整保留。
- `qaIdentityMode` 必須完整保留。
- `controlPlaneWorktreeOrRepo` 必須完整保留。
- `controlPlaneIdentity` 必須完整保留。
- `trustedControlPlaneRoot` 必須完整保留。
- `trustedControlPlaneIdentity` 必須完整保留。
- `qualityWorktreeOrRepo` 必須完整保留。
- `firestoreCheckpointMap` 必須完整保留。
- `sqliteCheckpointMap` 必須完整保留。
- `firestoreCheckpointMap` 只包含已選且可執行的固定 mapping：
    - `R01:AU-01` 對 `R01:11` 與 `r01_anonymous_user`
    - `R01:AU-03` 對 `R01:15` 與 `r01_user_unchanged`
    - `R03:CS-02` 對 `R03:9` 與 `r03_initial_backup`
    - `R03:CS-03` 對 `R03:21` 與 `r03_incremental_backup`
    - `R03:CS-03` 修改後對 `R03:24` 與 `r03_updated_backup`
    - `R03:CS-03` 刪除後對 `R03:27` 與 `r03_deleted_backup`
    - `R08:CS-01` baseline 對 `R08:15` 與 `r08_preferences_baseline`
    - `R08:CS-01` final 對 `R08:21` 與 `r08_preferences`
- R10 至 R12 不得出現在 `firestoreCheckpointMap`。
- `sqliteCheckpointMap` 只包含以下固定 mapping：
    - `R08:AS-04` 對 `R08:8` 與 `r08_original_language`
    - `R13:RC-06` 對 `R13:6` 與 `r13_schedule_backfill`
    - `R14:AU-02` 對 `R14:4`、`R14:5` 與 `r14_defaults`
- feature depth 使用 `none`。
- worktree target identity 包含：
    - base commit
    - base tree SHA
    - worktree snapshot digest
- release target identity 包含：
    - target full commit
    - target full tree SHA
- `test-ios` 不重問已確認範圍。
- `sceneIds` 只包含未受阻的場次。
- `caseIds` 不得包含只由受阻場次承載的 case。
- 環境就緒後才提示手動操作。

---
