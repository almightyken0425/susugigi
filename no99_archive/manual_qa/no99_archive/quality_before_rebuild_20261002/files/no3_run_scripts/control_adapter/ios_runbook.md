# iOS 執行與還原

## 職責

- 管理單一 iOS simulator。
- 管理主 git 的候選 checkout。
- 管理 QA build 與 Metro。
- 擷取 allowlisted QA markers。
- 承接本次 UI 操作及取證分工。
- 結束後還原 git 與 Metro。
- 測試判定仍由 `test-run` 負責。

---

## 啟動來源

- 使用者直接呼叫 `test-ios`。
- 使用者指定某個場次。
- `test-run` 提交確認 payload。
- test-run 委派已代表執行授權。
- 委派流程不重問類型與深度。
- 直接呼叫只確認 target 身分。

---

## 委派核對

讀 [產品交接契約](handoff_contract.md)。先核對必要欄位、候選、選集與場次閉包。
Driver 協定仍接受 sim-review。它映射到 test-ios，並未保留另一份 Skill。

## 執行模式

- `delegated-candidate`
    - 使用 clean release commit。
    - 不修改 Impl worktree。
- `topic-review`
    - 使用 worktree snapshot。
    - 使用 synthetic commit。
- 兩種模式都從主 git執行。
- worktree 內不啟 Metro。
- worktree 內不執行 build。

---

## 阻斷場次邊界

- payload 只接受未受阻的 simulator cases。
- structured blocked scenes 不得出現在 `caseIds`。
- structured blocked scenes 不得出現在 `sceneIds`。
- R10、R11 與 R12 永不執行。
- R14 命中 structured block 時永不執行。
- 收到受阻場次時停止委派。
- `test-run` 保留該場次的 blocked result。
- 安全場次使用獨立 payload 繼續。

[執行區塊](ios_runtime/blocked_scenes_1.sh)。
在同一個已鎖定且持續存活的 runner shell 內載入。不可拆成獨立 shell。

---

## Trusted verifier staged bootstrap

- verifier 必須先由獨立 Control 主題交付。
- bootstrap 變更只包含最小 verifier 與專用測試。
- bootstrap 變更須經獨立 review。
- bootstrap 變更須先合併至乾淨 Control main。
- trusted main 尚未包含 verifier 時停止 session。
- candidate verifier 不得驗證或物化自身。
- candidate runtime 只鎖定已含 verifier 的 main commit。
- 第二階段才物化 candidate 與 Quality snapshot。
- 第二階段仍須執行 source-pre 與 source-post identity 比對。

---

## Target 驗證

- 取得主 git 路徑。
- 確認主 git 位於 main。
- 確認主 git working tree 乾淨。
- release target 解析 commit 與 tree。
- worktree target 重算 snapshot digest。
- `CONTROL_PLANE_ROOT` 只取自 payload 的 `controlPlaneWorktreeOrRepo`。
- `TRUSTED_CONTROL_PLANE_ROOT` 只取自 payload 的 `trustedControlPlaneRoot`。
- `QUALITY_ROOT` 只取自 payload 的 `qualityWorktreeOrRepo`。
- trusted root 必須與候選 Control root 分離。
- trusted root 只接受乾淨且 identity 鎖定的 Control Plane checkout。
- 兩個 root 必須解析為實體目錄。
- 兩個 root 都不得為 symlink。
- identity 驗證完成後建立 session-owned immutable private snapshot。
- trusted verifier 從鎖定 trusted commit 的 Git object 擷取，不從 mutable checkout 執行。
- candidate Control 與 Quality snapshot 必須在私有副本重算並匹配 payload identity。
- session 建立後所有 Control helper、Quality executable 與 golden 只從私有副本使用。
- 每次 helper 前後重算私有 tree manifest，後驗失敗時丟棄成功輸出。
- mutable Control 或 Quality worktree 後續變更不得改寫本次 runtime。
- Control snapshot 必須匹配 `controlPlaneIdentity`。
- Quality snapshot 必須匹配 `qualityIdentity`。
- 比對 payload 的 target identity。
- 鎖定 payload 的 `qualityIdentity`。
- 鎖定 payload 的 `qualityDefinitionDigest`。
- 鎖定 payload 的 `caseSetDigest`。
- 任一值不同時停止。
- main checkout 使用 detached target。
- feat branch 保持 worktree 所有權。

[執行區塊](ios_runtime/target_1.sh)。
在同一個已鎖定且持續存活的 runner shell 內載入。不可拆成獨立 shell。

---

## Session temporary cleanup

- cleanup trap 在建立任何 temporary resource 前啟用。
- cleanup 可重複執行。
- `run_and_validate_qa_identity_disposal` 必須在 trap 註冊前定義。
- cleanup 先處理可能存在的 QA fixture。
- fixture cleanup 失敗時仍必須嘗試匿名帳號 disposal。
- fixture cleanup 與 disposal 必須分別彙總失敗。
- cleanup helper exit 0 後仍須獨立確認 users document 與六個 fixture 子集合全數 absent。
- post-delete absence probe 缺 OAuth provider 或任一資料仍存在時，fixture cleanup 判定失敗。
- cleanup 完成 disposal 後才停止 App 與 Metro。
- cleanup 停止 Metro 與 disk 前 filter。
- cleanup 停止 filter 後必須重驗整個 session marker window。
- cleanup 移除 private FIFO、場次 launch.json 與 temporary directory。
- cleanup 移除 Control、Quality 與 trusted verifier 的 session 私有副本。
- cleanup 停止 Metro 後刪除 transient READY marker log。
- main QA 私密副本存在時刪除。
- main QA 私密副本刪除失敗時保留 ownership。
- QA 私密副本 cleanup 失敗時不得 checkout main。
- main 位於 detached target 時 checkout 回 main。
- checkout 前必須先刪除 QA 私密副本。
- 刪除自有副本後必須檢查 main dirty 狀態。
- main dirty 時保留 detached 狀態。
- main dirty 時要求人工恢復。
- temporary index 與目錄存在時刪除。
- cleanup 不改動 feat HEAD、index 或 working tree。
- cleanup disposal 失敗時仍完成環境還原。
- cleanup disposal 失敗時整體 session 維持失敗。
- cleanup 不得重複或遞迴執行 disposal。

[執行區塊](ios_runtime/session_cleanup_1.sh)。
在同一個已鎖定且持續存活的 runner shell 內載入。不可拆成獨立 shell。

---

## Topic synthetic target

- 只適用 `topic-review`。
- `IMPL_WORKTREE` 必須取自 payload。
- 先記錄 `ORIGINAL_HEAD`。
- 先記錄目前 index tree。
- staged changes 存在時停止。
- 停止時保留原狀。
- 使用 temporary index 收入 unstaged 與 untracked。
- temporary index 不取代 feat index。
- synthetic commit 不移動 feat HEAD。
- synthetic commit 不建立 branch ref。
- QA 私密 plist 必須維持 ignored。
- QA 私密 plist 不得進入 synthetic tree。
- synthetic commit 不 push。
- synthetic commit 不寫入 manifest。
- synthetic commit 不成為 release truth。

[執行區塊](ios_runtime/synthetic_target_1.sh)。
在同一個已鎖定且持續存活的 runner shell 內載入。不可拆成獨立 shell。

---

## Main checkout

[執行區塊](ios_runtime/main_checkout_1.sh)。
在同一個已鎖定且持續存活的 runner shell 內載入。不可拆成獨立 shell。

- checkout 後再次核對 commit。
- checkout 後再次核對 tree。
- checkout 前先取得 main restore responsibility。
- cleanup 依實際 branch 與 HEAD 判斷中斷位置。
- 不使用 branch 名替代 SHA。

---

## QA build

- QA App 使用獨立 bundle id。
- QA Firebase project 必須非 Production。
- QA Firebase App 必須匹配 `.qa` bundle。
- QA Firebase 必須使用拋棄式匿名帳號。
- 同 Production project 的 App 不算隔離。
- QA 隔離未成立時停止。
- 下列情況必須 build：
    - 候選含原生異動
    - QA App 尚未安裝
    - 已安裝原生身分未知
- 已確認同一原生身分時：
    - JS 異動可只切 Metro。
- SuSuGiGi Accounting 使用：

- `qaScheme` 為 `SuSuGiGiApp-QA`。
- `qaMode` 為 `Debug-QA`。
- `qaBundleId` 必須以 `.qa` 結尾。
- `qaFirebaseProjectId` 必須為 `susugigi-qa`。
- `qaGoogleAppId` 必須為 `1:352034825841:ios:40c5c3bcfa630b4a6a1dd0`。
- `qaFirebaseConfigSha256` 必須為 `8a349abb287abc45a2e4ad868d1fd93b373f4f878fe03aa4e805e97c31ac489f`。
- `qaIdentityMode` 必須為 `disposable-anonymous`。
- `susugigi-c4fb1` 為明確拒絕值。
- `QA_SCHEME` 取自 `qaScheme`。
- `QA_MODE` 取自 `qaMode`。
- `QA_BUNDLE_ID` 取自 `qaBundleId`。
- `QA_FIREBASE_PROJECT_ID` 取自 `qaFirebaseProjectId`。
- QA_GOOGLE_APP_ID 取自 `qaGoogleAppId`。
- QA_FIREBASE_CONFIG_SHA256 取自 `qaFirebaseConfigSha256`。
- `.firebaserc` 不參與 project 選擇。
- Firebase project alias 不參與 project 選擇。
- resolver 不讀取 Production plist。
- 不得讀取或複製 Production plist。
- 不得輸出 `API_KEY`。
- QA plist 來源鎖定 payload 的 Impl target。
- QA plist 來源維持私密 ignored 檔案。
- main 副本只存在於 detached target build 期間。
- detached target 必須先套用 feature `.gitignore`。
- ignore 規則未生效時停止。
- main 同名檔已存在時停止。
- QA plist 不得 commit。

[執行區塊](ios_runtime/build_1.sh)。
在同一個已鎖定且持續存活的 runner shell 內載入。不可拆成獨立 shell。

- main 副本只在 detached target 上建立。
- 確認 main 副本不是一般檔案或 symlink 後立即預約 cleanup ownership。
- 複製開始前必須完成 cleanup ownership 預約。
- 複製失敗或中斷時 cleanup 仍刪除目標路徑。
- 只有刪除成功且路徑不是一般檔案或 symlink 時才能釋放 cleanup ownership。
- 刪除失敗時 `MAIN_QA_FIREBASE_CREATED` 保持 `1`。
- source 與 main 副本都必須通過 resolver。
- resolver 必須同時驗證 project、bundle 與 app id。
- resolver 結果必須逐字符合 payload project id。
- resolver 失敗時停止 build。
- 任一檔案不一致時停止 build。
- cleanup trap 必須在 build 錯誤後刪除 main 副本。
- build 只產生 App artifact。
- 安裝動作不得自動 launch App。
- 安裝後第一次 launch 必須是 token-bound 身分 bootstrap。
- build 與 installed artifact 只接受 QA URL route。
- QA URL route 不得包含 Production OAuth scheme。
- QA target 的 AppDelegate source 必須以 `#if !QA` 排除 Production GoogleSignIn import 與 URL handler。
- 不得以整顆 QA executable 是否連入 GIDSignIn SDK 作隔離判定。
- QA build settings 必須包含 `QA` compilation condition。

[執行區塊](ios_runtime/build_2.sh)。
在同一個已鎖定且持續存活的 runner shell 內載入。不可拆成獨立 shell。

- build 必須從主 git 執行。
- build log 必須保留路徑。
- 成功 marker 缺失時停止。
- build artifact 必須先通過 Firebase 身分核對。
- build artifact 通過後才安裝。
- 已安裝 App 必須重新解析完整 Firebase 身分。
- 來源 plist 與 App 產物必須逐字一致。
- main 私密副本在 build 驗證後立即刪除。
- 任一身分不一致時停止測項。

---

## SQLite-local bundle binding

R15 在 QA build 與安裝核對完成後，先載入 [本機 StoreKit 設定](ios_runtime/storekit_1.sh)。
此場只含 R15，使用 SKTestSession 啟用候選商店，不依賴 `simctl` 讀取 Xcode scheme。
設定檔須與候選、建置產物及已安裝 App 完全一致。雜湊透過 process environment 傳入。
R15 啟動時也傳入目前 Xcode 的 Simulator 測試框架與函式庫搜尋位置，讓 StoreKitTest 能載入 XCTest。位置由 `xcode-select` 推導，不沿用外部傳入值。
App 只在消耗有效 QA proof 後啟用本機商店。每次 open-app 必須同時取得 READY 與 `QA NATIVE LOCAL_STOREKIT_READY`。
Simulator 的開發選單提供 StoreKit 操作，原生端每次重驗同一匿名身分與 active proof。
到期動作保留十秒讓 App 進入背景。必須觀察到 `QA NATIVE LOCAL_STOREKIT_EXPIRED` 並核對交易到期時間。
disposal 同時清理 StoreKit，執行器獨立核對 `QA NATIVE LOCAL_STOREKIT_CLEANED`。缺少時整場失敗，仍嘗試 Auth 與 Firestore 清理。

- QA_BUNDLE_ID 只取自 payload 的 `qaBundleId`。
- sqlite-local readiness 與每次 probe 都必須使用 payload 鎖定的 `qaBundleId`。
- Production bundle id `com.almightyken0425.susugigiapp` 為明確拒絕值。
- `QA_BUNDLE_ID` 不以預設值或已安裝 App 推導。
- `query_local_db.sh` 未顯式帶 bundle id 時停止。
- `QUALITY_ROOT` 必須匹配已鎖定的 Quality identity。
- sqlite-local readiness 必須執行 `run_qa_sqlite_local_probe path`。
- 每次 sqlite-local probe 都必須經過 `run_qa_sqlite_local_probe`。
- wrapper 只接受 `path`、`tables`、`assert` 與帶單一 query 的 `sql`。

[執行區塊](ios_runtime/sqlite_binding_1.sh)。
在同一個已鎖定且持續存活的 runner shell 內載入。不可拆成獨立 shell。

---

## Metro

- simulator 共用 port `8081`。
- 同一時間只允許一個 owner。
- Metro 從主 git 啟動。
- 啟動前以鎖定的 Control `qa-launch-registry.py` 核對主 checkout 的 detached commit、tree、乾淨狀態與 `8081` 空閒。
- helper 使用鎖定 Control 的產品 registry 與 server policy，不讀取可變的正式產品設定。
- 場次登記只建立於本次 mode `0700` 的 `sim-review-stream.*` 暫存目錄。
- `launch.json` 使用 mode `0600`，只登記主 checkout 的相對路徑與 `metroPort: 8081`。
- 既有檔案、symlink、身分不符或 port 佔用時停止，不覆寫或終止既有 owner。
- 不修改公司主目錄的 `.codex/launch.json`，一般主目錄寫入保護保持有效。
- Metro 不得加 `--client-logs`，避免 runtime marker 重複送達。
- QA App 必須由 `simctl launch --console` 啟動。
- QA App stdout、stderr 與 Metro stdout、stderr 必須先通過 disk 前 marker filter。
- 原生生命週期診斷只接受固定 `QA NATIVE` allowlist，不得帶 URL、身分或 payload。
- bootstrap 失敗時只回報 allowlisted 原生分類或 `QA NATIVE NONE_OBSERVED`。
- 每次 App launch 只允許一個 `QA_APP_CONSOLE_PID`。
- App 終止後必須停止 console capture，再檢查 quiet window。
- unfiltered App 或 Metro stream 不得寫檔或輸出到可見通道。
- 不得使用 `tee` 複製 unfiltered stream。
- filter 固定接受通過完整 schema 驗證的 `QA READY` 與 `QA RESULT`。
- schema 驗證失敗的 runtime marker 必須輸出固定無 payload sentinel `QA RUNTIME MARKER REJECTED`。
- sentinel 不得包含原始行、requestId 或 payload。
- 單一實體行只能包含一個 runtime marker prefix。
- 混合 READY 與 RESULT prefix 時必須輸出 sentinel。
- 重複同類 prefix 時必須輸出 sentinel。
- 每個 READY 與 RESULT validator 必須先檢查自身 offset window 不含 sentinel。
- offset window 含 sentinel 時即使另有合法 pass 也停止。
- session taint 一旦成立不得在本次 lifecycle 清除。
- 後續 validator 必須拒絕已 taint 的 session。
- terminal candidate 不等於 validation success。
- terminal candidate 後必須等待十次連續穩定取樣。
- 穩定取樣間隔固定為一百毫秒。
- bounded drain quiet window 上限固定為五秒。
- `QA RESULT` 必須依 bootstrap、launch、prepare、inspect 或 dispose 套用 operation-specific exact schema。
- prepare sceneId、inspect checkId、runId 與 fingerprint 必須符合固定 allowlist 或 grammar。
- inspect evidence 的 fact key 必須符合 check-specific allowlist。
- inspect evidence 的 actual 與 expected 為字串時，filter 必須在寫檔前改為 deterministic SHA-256 digest。
- identityHash 只允許存在於通過驗證的 `QA READY`。
- 第一筆 valid READY 前，所有成功 prepare／inspect RESULT 與 selected golden marker 必須輸出 sentinel。
- 第一筆 valid READY 前只允許 fixed-schema bootstrap／launch／dispose failure RESULT。
- `QA RESULT` 與 golden marker 含身分欄位時必須丟棄。
- selected cases 需要的 golden marker family 才能加入 filter。
- golden marker family 必須匹配 Quality 的 QA 標記命名空間。
- golden marker 必須依 family 套用 event 與 field allowlist。
- golden marker 的自由字串 field value 必須在寫檔前改為 deterministic SHA-256 digest。
- filter 記住第一筆通過驗證的 READY identityHash。
- 後續 READY identityHash 不同時輸出 sentinel。
- 任何 RESULT 或 golden marker 正規化 digest 等於 READY identityHash 時輸出 sentinel。
- selected expected marker 必須使用相同 filter seam 正規化。
- selected expected marker 的 digest 等於 READY identityHash 時停止。
- family 或 event-only expected marker 使用 token-bound prefix compare。
- 含 field 的 expected marker 使用 normalized exact compare。
- expected marker 含 unknown field 時停止。
- selected golden markers 在通過身分字串檢查後保留。
- candidate source 的所有 console call 都必須拒絕 UID 或 session token 參數，即使 marker 由變數傳入。
- 固定 string literal 的 uid 字樣不視為身分值。
- console argument expression 與 template interpolation 仍必須掃描身分值。
- static scan 或 runtime filter 失敗時 marker 通道判定失敗。
- filter output 才能寫入本次 session 的 transient READY marker log。
- transient READY marker log 使用不可重用且已解析 symlink 的私密 temporary path。
- transient READY marker log 必須在每個 exit path 由 cleanup 刪除。
- 此 runner 只承接 Metro 已空閒的環境。既有 owner 尚未結束時保留現況。

[執行區塊](ios_runtime/metro_1.sh)。
在同一個已鎖定且持續存活的 runner shell 內載入。不可拆成獨立 shell。

- `/status` 成功不代表 bundle 成功。
- 必須再請求 iOS bundle。
- bundle 編譯失敗時停止。
- bootstrap launch 後先驗證 QA READY marker。
- marker 通道失敗時停止測項。

---

## QA session proof

- session token 在 payload、Quality、Release 與 checkpoint 之外管理。
- `test-ios` 在第一個身分 bootstrap 前產生 session token。
- bootstrap、每個 operation 與 disposal 都使用同一個 session token。
- QA session token 不得輸出到 stdout、stderr 或 log。
- QA session token 不得寫入完成回報。
- QA session token 不得寫入 crash artifact。
- session token 只保留於當次 shell 程序記憶體。
- session token 只透過 `SIMCTL_CHILD_SUSUGIGI_QA_SESSION_TOKEN` 注入 App process environment。
- session token process environment 不得寫入 payload、log 或 checkpoint。
- session token 不得出現在 App launch arguments。
- 整個 stateful lifecycle 必須在同一個 long-lived shell process 與 session 執行。
- 長駐入口固定使用已鎖定的 `no3_run_scripts/control_adapter/programs/qa-session-runtime.sh`。
- READY 與原生憑證驗證固定使用 `no3_run_scripts/control_adapter/programs/qa-runtime-phase.py`。
- 私有 runner 只組裝已鎖定的參數與既有環境步驟。
- 私有 runner 不得另寫啟動驗證或命令派送邏輯。
- 命令迴圈只接受列明的指令，不執行任意 shell 輸入。
- 輸入中斷、閒置逾時或 signal 都執行完整 cleanup。
- 執行及等待期間都持續監測 marker filter 與 session taint。
- session token、identityHash 與 `QA_SESSION_UID` 不得拆到獨立 exec。
- session token、raw Firebase uid 與 `QA_SESSION_UID` 永不得寫入任何檔案。
- identityHash 只允許出現在本次 session 的 transient READY marker log。
- identityHash 不得進入 payload、checkpoint、完成回報、crash artifact 或 persistent artifact。
- identityHash 不得 export 或重建。
- stateful shell 必須停用 xtrace。
- 文件與命令範例只引用 shell 變數。
- native session proof 必須綁定 token hash。
- native session proof 必須綁定 uid hash。
- native session proof 必須包含 TTL。
- native session proof 必須保存 consumed request 與 operation hash。
- bootstrap 先保存 `staged` 清理憑證，再啟用 `active` 測試憑證。
- `staged` 不授權 App mount。
- 啟用失敗時保留 `staged`，交給 session cleanup 處理。
- 新 bootstrap 不得清除尚待回收的憑證。
- proof 不得保存原始 session token 或 Firebase uid。
- operation gate 必須在 mount `QaApp` 前原子 consume proof。
- operation proof 缺失、過期、身分不符或重放時必須 fail-closed。
- operation proof 過期時不得 mount `QaApp`。
- disposal 必須驗證同一 session token，再先轉為 disposing。
- 每個 operation 使用高熵且不重用的 requestId。
- bootstrap 與 disposal 也各自使用高熵且不重用的 requestId。

[執行區塊](ios_runtime/session_proof_1.sh)。
在同一個已鎖定且持續存活的 runner shell 內載入。不可拆成獨立 shell。

---

## No-write capability bootstrap

R14／AU-02 改用 [交接契約的首次啟動入口](handoff_contract.md#r14-首次啟動入口)。
build 前設定 `QA_CURRENT_SCENE_ID=R14` 與 `QA_CURRENT_CASE_ID=AU-02`，由 bootstrap 執行區塊路由。
此入口先掛離線重試畫面，身分成功後先保存 proof，再取得清理接手回條，最後放行 post-auth 資料寫入。
第一筆 READY 前只准固定匿名登入嘗試 marker，其他成功結果仍拒絕。
一般 SQLite path 探測延至首次建立 DB。空資料及預設資料核對使用鎖定的 `qa-first-launch.py`。
下列一般 bootstrap 條件適用其他場次。

- 每個 App session 的第一次 launch 固定為身分 bootstrap。
- 每次 launch 恰好屬於 bootstrap、open-app、prepare、inspect 或 dispose 其中一種。
- bootstrap 是唯一不帶 operation flag 的 launch。
- prepare 與 inspect 不得在同一次 launch 傳入。
- 匿名身分閘門適用所有 App session。
- capability session 提升只在 selected cases 需要 `qa-command` 或 `qa-probe` 時執行。
- selected cases 使用 qa-command 或 qa-probe 時，兩者的靜態探測必須全數通過。
- 其他受阻能力不得由 bootstrap 提升。
- 身分 bootstrap launch 必須路由 `QaIdentityBootstrapApp`。
- `QaIdentityBootstrapApp` 先刪除 stale anonymous Auth，再建立新的匿名 Firebase Auth。
- bootstrap 不得恢復或重用舊匿名身分。
- READY 前只允許匿名 Firebase Auth 身分寫入。
- READY 前不得 mount `QaApp` 或 `AuthProvider`。
- READY 前不得執行 App 資料 seed、資料庫寫入或同步。
- bootstrap launch 只傳 requestId argument。
- session token 由 process environment 注入。
- bootstrap launch 不傳 prepare、inspect 或 dispose flag。
- `BOOTSTRAP_REQUEST_ID` 每次唯一。
- bootstrap 必須先建立 token-bound native session proof，再輸出 READY。
- 記錄 bootstrap launch 當下 log offset。
- 只讀取 offset 後的新 log。
- bootstrap READY deadline 為三十秒。
- bootstrap READY requestId 必須等於 `BOOTSTRAP_REQUEST_ID`。
- bootstrap READY 必須通過匿名身分閘門。
- READY identityHash 必須為六十四字元小寫十六進位。
- READY identityHash 必須逐字等於 native session proof 的 uid hash。
- READY 不得包含 raw Firebase uid。
- bootstrap requestId 出現任何 RESULT 判定 `fail`。
- bootstrap READY validator 在接受成功前必須對 offset window 執行 `require_runtime_marker_window_clean`。
- bootstrap READY candidate 出現後必須終止 App 並等待 bounded drain quiet window。
- bootstrap quiet window 完成後必須重讀相同 offset window。
- bootstrap READY 通過 exact-one 重驗後才能接受成功。
- session 提升只適用 `qa-command` 與 `qa-probe`。
- session 提升不修改 Quality 持久狀態。
- operation launch 只能在 READY 通過後 mount `QaApp`。
- bootstrap launch 前取得匿名帳號 teardown 責任。
- READY timeout 或 mismatch 不得清除 teardown 責任。
- READY 全部驗證通過後標記匿名帳號已確認。
- bootstrap 失敗時不執行 operation launch。

[執行區塊](ios_runtime/bootstrap_1.sh)。
在同一個已鎖定且持續存活的 runner shell 內載入。不可拆成獨立 shell。

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
- `FIRESTORE_READ_REQUIRED` 只由 selected capabilities 派生。
- `qa_firestore_read_driver` 只接受 checked-in 唯讀 transport。
- `render_qa_firestore_allowlisted_facts_in_memory` 只輸出 case 所需 facts。
- 禁止在 wrapper 外直接呼叫 `qa_firestore_read_driver`。
- checked-in transport 固定綁定 `susugigi-qa`。
- Firestore document read 只接受受支援的 OAuth provider。
- 目前受支援的 Firestore OAuth provider 為已登入且可非互動執行的 `gcloud auth print-access-token`。
- Firebase CLI 沒有 Firestore document read 指令，不得以 delete、export 或 emulator 指令替代。
- 缺少受支援 provider 時只回 `QA_FIRESTORE_AUTH_PROVIDER_UNAVAILABLE` 並 fail-closed。
- Auth absence probe 使用 `firebase auth:export`、顯式 QA project 與 non-interactive mode。
- fixture UID bind 使用同一份私有 Auth export，逐筆計算 SHA-256 後只接受 exact-one anonymous match。
- fixture UID bind 的 raw UID 只准由 command substitution 收進 shell memory，不得進 argv、stderr、log 或報告。
- raw UID 只透過 stdin 傳入 checked-in transport。
- Firebase、Auth、Firestore 與 gcloud endpoint override 必須在父層拒絕。
- child environment 必須移除所有盤點過的 endpoint override 名稱。
- 所有 Python runtime helper 使用 isolated mode。
- `run_session_snapshot_command` 必須先經 checked-in child environment guard，再啟動 Bash、Firebase CLI、gcloud 或 Quality helper。
- child environment guard 將 helper 的工作目錄設為專用私有暫存目錄，輸入檔案使用完整路徑。
- Firebase 等工具產生的診斷檔隨該目錄清除，不留在 caller checkout。
- Control 父層 wrapper 必須在新 Bash 啟動前拒絕 `BASH_ENV`、`ENV`、`BASH_XTRACEFD`、`PS4`、Node preload、TLS key log 與動態連結器注入。
- `SHELLOPTS` 與 `BASHOPTS` 在目前 Bash 通常非空，只從 child environment 移除。
- shell helper 無法防止自身啟動前的 `BASH_ENV` 注入。此邊界由 trusted launcher 與 Control 父層 wrapper 承擔。
- checked-in transport 只輸出 allowlisted verdict。
- Auth export 只寫入 mode `0700` 的私密 temporary directory，檔案使用 mode `0600`。
- Auth export 在正常、錯誤與中斷路徑都刪除。
- Firestore response 必須在 bounded memory 中解析，不得寫入檔案。
- `QA_FIRESTORE_PROFILE` 只能由 scene 與 case 的封閉 mapping 派生。
- `QA_CURRENT_CHECKPOINT_KEY` 必須是 Quality CSV 的固定 `場次:序`。
- `QA_QUALITY_FIRESTORE_PROFILE_KEY` 必須是 Quality golden 的固定 profile key。
- 執行 Firestore transport 前必須重算 Quality snapshot，並用 checked-in Quality evaluator 驗證鎖定 golden。
- golden evaluator 只接受 `susugigi.qa.fixture-golden/v1`、exact top-level keys 與六個固定 Firestore profiles。
- golden 缺漏、schema 漂移、checkpoint 漂移、額外欄位或 symlink 一律 fail-closed。
- executable mapping 只有 R01 AU-01、R01 AU-03、R03 CS-02、R03 CS-03 與 R08 CS-01。
- R10 至 R12 的 Firestore checkpoint 永不執行。
- R01 unchanged 只對 same UID、provider、email 與 createdAt identity invariant 計算 session SHA-256。
- R01 unchanged 排除 lastLoginAt、updatedAt 與 preferences，不使用預存隨機 id 或 timestamp digest。
- R01:11 私下保存 lastLoginAt 與 updatedAt baseline，兩值不得輸出或寫入 log。
- R01:15 要求 lastLoginAt 與 updatedAt 存在且不得早於各自 baseline。
- R03 initial profile 核對六個集合、3/7/9 筆數、早餐 150 與固定 fixture 業務欄位。
- R03 incremental profile 核對完整十筆 live transactions、唯一增量備份 200、唯一早餐 150 與兩筆 live transfers。
- R03 incremental 的兩筆 transfer 必須為 2000 對 2000 與 1000 對 4500。
- R08 profile 核對 theme3、原語系代碼、USD 與根層 updatedAt。
- mapping 缺失或重複時 fail-closed。

[執行區塊](ios_runtime/firestore_binding_1.sh)。
在同一個已鎖定且持續存活的 runner shell 內載入。不可拆成獨立 shell。

---

## 自動 QA command

- 本節只處理非空 `qaLaunchArguments`。
- 無自動 command 時跳過本節。
- 依 payload 原樣傳入 QA arguments。
- 一般 qaLaunchArguments allowlist 只接受 prepare、inspect 與 `--qa-open-app true`。R14／AU-02 的 first-launch 由前節處理。
- prepare 或 inspect 不得與 open-app 同時傳入。
- `QA_REMOTE_FIXTURE_WRITE_POSSIBLE` 與 `QA_FIXTURE_RESEED_REQUIRED` 只由 checked-in 封閉 mapping 派生。
- R03 r02_end 與 R13 r09_stale_schedule 的 canonical prepare 固定為一。
- R06 large-history overlay 與 cleanup 固定為零。
- 未映射 prepare 必須 fail-closed。
- 可能寫入 QA Firestore 時必須在 launch 前取得 fixture cleanup 責任。
- 所有可能遠端寫入的 fixture prepare 都必須在 launch 前清除同 UID 的既有 subtree。
- 每次符合條件的 prepare 都重新執行 cleanup 與 post-delete absence probe，不得沿用前次確認。
- R03 的 `prepare r02_end` 必須先以 Auth export 對 READY identityHash 做 exact-one UID bind。
- R03 seed 前必須用 QA-only cleanup helper 清除該 UID 的既有 fixture subtree。
- pre-seed cleanup 只接受 QA project、合法 fixture 場次與已綁定 UID。
- pre-seed cleanup 失敗時停止，不得 launch prepare。
- pre-seed cleanup exit 0 後仍須通過同 UID 的 fixture subtree absence profile。
- prepare 與 inspect 保持 fixture sync suspended，不得等待 backup marker。
- 每個 prepare 或 inspect 都是獨立 operation launch。
- 每個 operation launch 使用高熵且不重用的 requestId。
- 每個 operation launch 由 process environment 注入本次 session token。
- operation launch 前驗證 native session proof 的 token hash、uid hash 與 TTL。
- operation gate 在 mount `QaApp` 前原子保存 consumed request 與 operation hash。
- proof 已 consumed 同一 request 或 operation 時停止。
- 記錄 launch 當下 log offset。
- 只讀取 offset 後的新 log。
- launch 後等待 `QA READY`。
- READY deadline 固定 30 秒。
- deadline 從 launch 成功起算。
- READY payload 必須是 JSON。
- READY schema 必須為 `qa.runtime/v1`。
- READY requestId 必須相同。
- READY state 必須為 `ready`。
- READY identityMode 必須為 `disposable-anonymous`。
- READY isAnonymous 必須為 `true`。
- READY 身分欄位缺失判定 `fail`。
- READY 身分不符判定 `fail`。
- READY timeout 判定 `fail`。
- READY mismatch 判定 `fail`。
- operation READY identityHash 缺失判定 `fail`。
- operation READY identityHash 必須等於 `READY_IDENTITY_HASH`。
- operation READY 不得包含 raw Firebase uid。
- operation READY 後必須等待 AuthProvider post-auth 收斂。
- QaRuntimeBridge 只在 AuthContext post-auth 完成並關閉 isLoading 後輸出 operation READY。
- `AUTH_PROVIDER_POST_AUTH_SETTLED=1` 只可由 exact validated operation READY 推導。
- READY 與 post-auth 都通過後才標記 authorized operation。
- operation READY candidate 只允許繼續等待 RESULT，不得提前提升 session。
- operation launch 前取得匿名帳號 teardown 責任。
- READY 全部驗證通過後標記匿名帳號已確認。
- READY 通過後等待所有 RESULT。
- RESULT deadline 固定 120 秒。
- deadline 從 READY 通過起算。
- RESULT payload 必須是 JSON。
- RESULT schema 必須為 `qa.runtime/v1`。
- RESULT requestId 必須相同。
- RESULT operation 必須符合請求。
- prepare top-level `value` 必須等於所請求 `sceneId`。
- inspect top-level `value` 必須等於所請求 `checkId`。
- RESULT 不得含 error。
- `result` 必須是 object。
- `result.ok` 必須為 true。
- prepare `result.value.sceneId` 必須等於所請求 `sceneId`。
- inspect `result.value.schema` 必須為 `qa.evidence/v1`。
- inspect `result.value.checkId` 必須等於所請求 `checkId`。
- inspect `result.value.verdict` 必須為 `pass`。
- 候選 App 的 `verdict=pass` 不足以通過 inspect。
- r02_end 與 r09_stale_schedule 的 prepare fingerprint 必須交由 checked-in Quality evaluator 對鎖定 Quality golden 比對。
- accounting.fixture-summary 的完整 filtered facts 必須交由同一 evaluator 核對 exact keys、counts、布林關係與 pass 狀態。
- accounting.schedule-backfill 的 candidate facts 只產生 candidate count，不得冒充 SQLite aggregate。
- R13 prepare 前只可用 Auth export 綁定 READY identity，不得先 open-app、resume sync 或以舊 SQLite 綁定。
- prepare 與 inspect launch 前都必須由 Auth export exact-bind。
- 每次 QaApp mount 前都必須取得 fixture cleanup ownership。
- cleanup ownership 不依賴 remote 或 reseed policy。
- R13 remote cleanup 與 absence probe 通過後才可 launch prepare。
- R13 prepare RESULT 通過後，才以 SQLite exact-one UID 作獨立身分交叉驗證。
- R13:6 必須以 UID stdin 呼叫鎖定 Quality query helper，取得獨立 allowlisted aggregate。
- R13 final pass 必須對 candidate RESULT、SQLite aggregate 與 inspect launch 後的 `QA SCHED` generated count 三方 exact compare。
- operation-specific parser 只在 exact schema 通過後回傳 result value。
- result value 只留函式記憶體，大小上限 256 KiB，不得寫入 checkpoint 或報告。
- 預期 operation 必須各有一筆 RESULT。
- 重複 operation RESULT 判定 fail。
- RESULT timeout 判定 `fail`。
- RESULT mismatch 判定 `fail`。
- operation READY 與 RESULT validator 在接受成功前必須對各自 offset window 執行 `require_runtime_marker_window_clean`。
- prepare 或 inspect 的 RESULT candidate 出現後必須終止 App 並等待 bounded drain quiet window。
- operation quiet window 完成後必須重讀共同 offset window。
- operation READY 與 RESULT 必須在重讀後各自 exact-one。
- operation session 只在重讀驗證全數通過後提升。
- 任一 fail 都停止目前 case。
- fail 證據回傳 `test-run`。

[執行區塊](ios_runtime/operation_1.sh)。
在同一個已鎖定且持續存活的 runner shell 內載入。不可拆成獨立 shell。

- 空白 argument 不傳入。
- feature 無 seed 時省略 prepare。
- feature 無 probe 時省略 inspect。
- prepare 與 inspect 都存在時分成兩次 launch。
- 第二次 launch 使用新的 requestId。
- prepare fail 後不執行 inspect launch。

---

## Manual-only App operation

本節沿用既有名稱，指沒有 seed 或 inspect 的 App 操作入口。UI 操作者依本次分工決定。

- seed 與 inspect 都為 none 且 case 需要開 App 時，必須使用 open-app operation。
- manual-only App launch 不得使用 requestId-only 或無 flag launch。
- payload 的 `qaLaunchArguments` 必須逐字等於 `--qa-open-app true`。
- open-app operation 使用高熵且不重用的 requestId。
- 每次冷啟 open-app 必須產生新的 requestId，禁止重用前次 requestId。
- open-app operation 由 process environment 注入本次 session token。
- open-app flag 不得與 prepare、inspect 或 dispose 同時傳入。
- open-app launch 只能在 bootstrap READY 通過後執行。
- native proof gate 必須在 mount `QaApp` 前原子 consume request 與 open-app operation hash。
- open-app READY 必須匹配 `OPEN_APP_REQUEST_ID`。
- open-app READY 必須通過相同的匿名身分閘門。
- open-app READY identityHash 缺失判定 `fail`。
- open-app READY identityHash 必須等於 `READY_IDENTITY_HASH`。
- open-app READY 不得包含 raw Firebase uid。
- open-app READY 後必須等待 AuthProvider post-auth 收斂。
- open-app READY validator 在接受成功前必須對 offset window 執行 `require_runtime_marker_window_clean`。
- open-app READY candidate 必須經 bounded quiet window 後才可開始 UI 操作。
- open-app quiet window 期間不得終止 App。
- open-app quiet window 完成後必須重讀相同 offset window。
- open-app READY 必須在重讀後 exact-one。
- open-app stabilization 後出現 sentinel 時永久 taint session。
- open-app READY 通過後才開始 UI 操作。
- open-app operation 不要求 RESULT。
- open-app 必須先由 Auth export exact-bind。
- open-app 必須在 launch 前取得 fixture cleanup ownership。
- open-app 中途失敗時 trap 仍必須清除 Firestore fixture。

[執行區塊](ios_runtime/manual_operation_1.sh)。
在同一個已鎖定且持續存活的 runner shell 內載入。不可拆成獨立 shell。

---

## Firestore probe 啟用

- 本節只在首個 firestore-read checkpoint 執行。
- bootstrap READY 不足以啟用 SQLite bind。
- prepare、inspect 或 open-app 皆可提供 authorized operation READY。
- authorized operation READY 後仍須等待 AuthProvider post-auth 收斂。
- 選集尚無 authorized operation 時先執行 token-bound open-app operation。
- open-app 使用相同 session token。
- open-app 使用新的高熵 requestId。
- exact-one bind 通過後才能執行第一個 Firestore wrapper call。
- 後續 Firestore path 仍逐次經過相同 wrapper。
- R03 CS-02 的 final open-app window 必須各有一筆 remoteHasData=false probe 與 initial mode。
- R03 initial window 出現 incremental 或 full_delta mode 時停止。

[執行區塊](ios_runtime/firestore_probe_1.sh)。
在同一個已鎖定且持續存活的 runner shell 內載入。不可拆成獨立 shell。

[執行區塊](ios_runtime/firestore_probe_2.sh)。
在同一個已鎖定且持續存活的 runner shell 內載入。不可拆成獨立 shell。

---

## 伴跑

- 依鎖定 Control 的 `references/quality/execution_assignment.md` 承接本次分工與使用者偏好。
- AI 操作前核對當次 UI 工具可用。使用者操作時交出 UI 控制。
- 接手先核對畫面、已完成步驟及資料狀態，同一時間只有一個 UI 操作者。
- UI 接手不轉移 test-ios 的環境與清理責任。
- 保留已指定的觀看停點，不因 AI 可以操作就跳過。
- 使用 payload 的 case 順序。
- R01、R02 與 R08 的 simulator cold reopen 必須由 test-ios 自動 terminate 後 launch。
- simulator cold reopen 不得要求使用者點 App icon，避免遺失 QA launch arguments。
- 每次 cold reopen 都呼叫 `run_and_validate_qa_open_app_operation`，使用新的 requestId 並重驗 READY。
- 環境檢查完成後才開始 UI 操作。
- 使用者操作時一次只提示一組步驟。AI 操作時依序執行已安排的步驟。
- bootstrap 成功後以 `qa_session_command_loop` 維持同一個 shell。
- `QA_SESSION_PAYLOAD` 指向已鎖定的公開 payload。
- `QA_SESSION_PAYLOAD_SHA256` 保存該檔原始 bytes 的 SHA-256。
- 兩個值在啟動命令迴圈前設為 readonly。
- `case Rxx XX-00` 透過 `qa-runtime-selection.py` 核對選集與場次歸屬。
- `prepare` 與 `inspect` 只使用已選 case 的 payload arguments。
- `probe Rxx:N` 只執行 payload 已登記的同 case 檢查點。
- `r13-final` 只執行 R13 的候選結果、SQLite 與 marker 三方對帳。
- `open-app` 與 `cold-reopen` 只呼叫既有 token-bound 開啟流程。
- `status` 與 `continue` 只核對 session 健康度，不代表 case 通過。
- `finish` 執行清理後結束，`abort` 以失敗狀態清理。

[執行區塊](ios_runtime/accompany_1.sh)。
在同一個已鎖定且持續存活的 runner shell 內載入。不可拆成獨立 shell。
- 依測項指定時點讀取 log。使用者操作時先取得具體完成訊號，AI 操作時由工具結果確認。
- `test-run` 再讀 probe 與 DB。
- `test-ios` 回傳環境證據。
- case pass 或 fail 由 test-run 判定。
- R08 場次第一個語系變更前，先從 canonical QA SQLite 私下 capture original language。
- R08 original language capture 前必須先由 Auth export exact-one 綁定 READY identity。
- R08 original language 不得由可能落後的 Firestore preference 取代。
- R08 CS-01 的 UI 操作前，另行 capture updatedAt baseline。
- original language 與 CS-01 updatedAt 使用兩個獨立 shell-memory 變數。
- 兩個 baseline 都不得輸出或寫入 session log。
- R08 profile 必須回到場次原語系，且 updatedAt 嚴格晚於 CS-01 baseline。
- 執行證據不得寫回 Quality。
- 每個 case 操作前記錄 marker log offset。
- `QA_LOG_MARKERS` 只包含目前 case 的 expected markers。
- 每個 marker occurrence 只能消耗一次。
- 舊 case 的 marker 不得滿足新 case。

[執行區塊](ios_runtime/accompany_2.sh)。
在同一個已鎖定且持續存活的 runner shell 內載入。不可拆成獨立 shell。

---

## QA identity disposal

- 正常路徑在所有 case 與 fixture cleanup 後執行。
- error 路徑在停止 App 與 Metro 前執行。
- error 路徑在還原 git 前執行。
- `run_and_validate_qa_identity_disposal` 依本節契約執行。
- bootstrap 與 operation launch 前設定 teardown 可能性。
- 尚未執行任何 QA launch 時不得嘗試 disposal。
- READY timeout 後仍必須嘗試 disposal。
- teardown 成功後才清除 teardown 可能性。
- disposal 失敗不得證明匿名帳號不存在。
- disposal 失敗必須明報帳號未清除或未證實不存在。
- 不得以 simulator erase 取代帳號 disposal。
- dispose launch 只允許 QA build。
- dispose launch 使用唯一 `DISPOSE_REQUEST_ID`。
- dispose launch 由 process environment 注入本次 session token。
- disposal 必須忽略 proof expiry，避免過期 proof 阻斷帳號清理。
- disposal 仍必須驗證 token hash、uid hash 與 proof state。
- bootstrap 尚未產生 READY 時，清理可唯讀擷取原生 proof 的 uid hash。
- 擷取只接受 canonical QA container 與相同 token hash。
- 擷取不得重建或提升 READY 狀態。
- uid hash 只留清理函式記憶體，供獨立 Auth absence probe 對帳。
- 缺少可驗證的清理憑證時維持 fail-closed，不得以 UID-only 刪除替代。
- token hash、uid hash 或 proof state 不符時 disposal fail-closed。
- disposal 身分驗證通過後先原子轉為 disposing。
- 進入 disposing 後才刪除匿名 Firebase Auth。
- dispose flag 不得與 prepare 或 inspect 同時傳入。
- 記錄 dispose launch 當下 log offset。
- 只讀取 offset 後的新 log。
- dispose RESULT deadline 為一百二十秒。
- dispose RESULT schema 必須為 `qa.runtime/v1`。
- dispose RESULT requestId 必須等於 `DISPOSE_REQUEST_ID`。
- dispose RESULT operation 必須為 `dispose`。
- dispose RESULT value 必須為 `identity`。
- dispose RESULT 不得含 error。
- dispose RESULT 的 result.ok 必須為 `true`。
- dispose RESULT identityMode 必須為 `disposable-anonymous`。
- dispose RESULT authDeleted 必須為 `true`。
- dispose RESULT 不得包含 `uid`。
- 重複 dispose RESULT 判定 `fail`。
- dispose RESULT validator 在接受成功前必須對 offset window 執行 `require_runtime_marker_window_clean`。
- dispose RESULT candidate 出現後必須終止 App 並等待 bounded drain quiet window。
- dispose quiet window 完成後必須重讀相同 offset window。
- dispose RESULT 必須在重讀後 exact-one。
- dispose timeout 判定 `fail`。
- dispose 失敗時整體結果判定 `fail`。
- dispose 失敗後仍執行環境還原。
- dispose 重入或重複呼叫不得再次 launch。
- disposal 不要求手動操作。
- disposal 只銷毀 Firebase Auth 身分。
- disposal 不代表 Firestore 測試資料已清除。
- dispose RESULT 通過後必須執行獨立 QA Auth absence probe。
- Auth probe 只接受鎖定的 QA project。
- Auth probe 只接收 READY identityHash。
- Auth probe 不得輸出 raw UID。
- 候選 App 自報成功不得取代獨立 Auth probe。

[執行區塊](ios_runtime/disposal_1.sh)。
在同一個已鎖定且持續存活的 runner shell 內載入。不可拆成獨立 shell。

---

## 還原

- 本輪操作、取證及已安排的檢視完成後執行。沒有檢視停點時直接收尾。
- 先處理可能存在的 QA fixture。
- fixture cleanup 失敗時仍必須嘗試匿名帳號 disposal。
- fixture cleanup 與 disposal 必須分別彙總失敗。
- 清理錯誤只回報固定的階段與原因代碼。
- 不回報憑證、UID、身分雜湊、遠端回應或原始例外。
- 只有資料盤點或刪除的暫時性連線錯誤可以重試。
- 同次退出最多清理三次。兩次重試前分別等待一秒與兩秒。
- 每次重試重新核對同一個記憶體內 QA 身分及不可變執行快照。
- 身分、快照、設定、權限與未分類錯誤不得重試。
- 刪除後仍須獨立確認資料不存在。確認失敗不得視為成功或自動重試刪除。
- `QA_FIXTURE_CLEANUP_VERIFIED` 才表示資料清理已獨立核對。
- `QA_IDENTITY_DISPOSAL_VERIFIED` 才表示帳號刪除及獨立核對皆通過。
- 彙總旗標未報錯不代表已取得上述成功證據。
- `QA_FIXTURE_RECOVERY_BLOCKED` 表示舊資料仍未確認清除。不得直接開新場次蓋過失敗。
- 流程退出後不保留 UID 或 token。不得重用過期場次憑證或延長八小時上限。
- 無法確認舊身分時停止恢復。先取得可核對的精確清理對象及授權。
- 不從舊 DB、過期證明或最新建立的 Firebase 帳號猜測清理對象。
- disposal 完成嘗試後才終止 QA App。
- 只終止本次 Metro PID。
- 停止 disk 前 marker filter。
- 移除 private FIFO、場次 launch.json 與 temporary directory。
- 停止 Metro 後刪除 transient READY marker log。
- 先刪除 main QA 私密副本。
- QA 私密副本刪除失敗時保留 ownership 並阻止 checkout。
- 刪除自有副本後檢查 main dirty 狀態。
- main dirty 時不 checkout。
- main dirty 時保留 detached target。
- main dirty 時明確要求人工恢復。
- 主 git checkout 回 main。
- 驗證主 git 乾淨。
- `topic-review` 驗證 feat HEAD 未改變。
- `topic-review` 驗證 feat index 未改變。
- `topic-review` 重算 worktree snapshot digest。
- snapshot digest 必須匹配原值。
- temporary index 完成核對後刪除。
- 還原啟動前 Metro 未執行的狀態，不自動建立新的 main Metro。
- 還原失敗必須明確回報。
- disposal 失敗時還原完成後仍回傳失敗。

[執行區塊](ios_runtime/restore_1.sh)。
在同一個已鎖定且持續存活的 runner shell 內載入。不可拆成獨立 shell。

- synthetic commit 沒有改動 feat ref。
- `MAIN_DETACHED` 歸零後才算 main 還原完成。
- 使用者檔案維持原 working tree。
- feat index 維持原內容。
- snapshot digest 不同時回報失敗。

---

## 錯誤處理

- 任一身分核對失敗即停止。
- 任一 build 失敗即停止。
- 任一 Metro 失敗即停止。
- 任一 marker 通道失敗即停止。
- QA launch 後任一錯誤都先嘗試匿名帳號 disposal。
- READY timeout 仍屬必須嘗試 disposal 的 error path。
- disposal 失敗時明報帳號未清除或未證實不存在。
- 停止後仍嘗試安全還原。
- 還原每個項目分別回報。
- detached main dirty 時不得 checkout。
- detached main dirty 時回報人工恢復需求。
- worktree HEAD 被推進時：
    - 不修改 feat branch。
    - 回報人工處理需求。
- 主 git 不乾淨時：
    - 不切換 checkout。
    - 回報污染檔案。

---

## 完成回報

- 回報 target ref。
- 回報 target kind 與 identity。
- 回報 transient commit 與 tree。
- 回報 build profile。
- 回報 `qaScheme` 與 `qaMode`。
- 回報 `qaBundleId`。
- 回報 `qaFirebaseProjectId`。
- 回報 `qaGoogleAppId`。
- 回報 `qaFirebaseConfigSha256`。
- 回報 `qaIdentityMode`。
- 回報 `qualityIdentity`。
- 回報 `qualityDefinitionDigest`。
- 回報 `caseSetDigest`。
- 回報 build 身分與結果。
- 回報 Metro source 與 port。
- 回報 transient READY marker log 已刪除。
- 回報 launch request id。
- 回報 READY 耗時與驗證結果。
- 回報 RESULT 耗時與驗證結果。
- 不回報 session token 或其展開值。
- 不回報 identityHash。
- 不回報 raw Firebase uid 或 `QA_SESSION_UID`。
- 回報 teardown 可能性與確認狀態。
- 回報 teardown 嘗試與成功狀態。
- 帳號未清除或未證實不存在時明確回報。
- 回報 dispose request id 與 RESULT 驗證。
- 回報擷取到的 markers。
- 回報主 git restore。
- 回報 worktree restore。
- 回報 Metro restore。
- transient 身分不得當作 release truth。
- 不代替 test-run 宣告 case pass。

---

## 邊界

- 本技能只處理 iOS simulator。
- Android 使用另一套流程。
- simulator 與 Metro 採單一 owner。
- 同時有其他 review 時排隊。
- Production build 不載入 QA 工具。
- QA bundle 不覆蓋 Production bundle。
- 直接呼叫也使用相同安全閘門。
