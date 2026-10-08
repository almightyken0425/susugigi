# iOS 驗證環境

test-ios 承接已授權的 iOS simulator 工作。只持有環境、觀測、清理與還原。
case 判定回 test-run。沒有 App 操作需求時略過本入口。

## 前置與支援範圍

讀 [共同交接](../workflow_requirements.md)、已確認的產品和 Quality owner。
沿用目標版本、測項、場次、預期證據及已知授權。
定義存在不代表已執行。缺少 simulator 或必要能力時回報 blocked。
只阻擋受影響測項，保留可獨立執行的驗證。

候選只支援 `susugigi-accounting-ios-v1` 的既有功能測試操作。
它的 driver 協定值仍是 `sim-review`。該值由轉接器解讀為 test-ios，不是另一份 Skill。
回歸協調可產生選案，但此 runner 尚未通過 release candidate 的實際模擬器驗證。
未知產品、場次、平台或 profile 不套用 SuSuGiGi 的參數。

## 執行

讀 `<已鎖定 Quality 根目錄>/no3_run_scripts/control_adapter/ios_runbook.md`。
先執行 `python3 ~/.codex/scripts/qa_adapter.py check --profile susugigi-accounting-ios-v1 --quality-root <已鎖定 Quality 根目錄>` 核對程式與區塊。
來源由 `~/.codex/manifests/qa_adapters.json` 定位。核對 repository 與 manifest 雜湊。
只使用本次 Quality identity 鎖定的適配包。Control 與 Quality 都建立私有唯讀副本。
程序區塊需在同一個長存 runner shell 依 runbook 載入，不能拆成各自 shell。
不把 Markdown 展開結果當成可執行腳本。
qa-runtime-input 只收有限公開指令。session token 留在程序記憶體。

QA Metro 使用場次私有暫存登記，不修改公司主目錄的 `.codex/launch.json`。
鎖定的 Control helper 核對 SuSuGiGi 主 checkout、detached commit、tree 與乾淨狀態。
確認 `8081` 空閒後，在本場次 mode `0700` 暫存目錄建立 mode `0600` 的 `launch.json`。
登記只接受主 checkout 的相對路徑與固定 `8081`，並使用鎖定的產品資料核對 server policy。
既有 port owner 未結束時停止啟動，不終止其他程序。
正常結束及失敗清理都移除本場次登記，還原為 Metro 未啟動的狀態。
這項例外只適用已鎖定的 test-ios runner。一般 server 沿用公司登記與主目錄保護。

外部 QA helper 在專用私有暫存工作目錄執行，輸入檔案必須明確指定完整路徑。
工具產生的診斷檔隨該目錄清除，避免污染目前 checkout。

UI 操作依[執行分工](execution_assignment.md)承接。每次接手先核對目前 App、裝置、畫面與待辦步驟。
AI 需有目前平台可用的觀察與操作工具。讀得到 log 或已安裝 Xcode 不代表能點選畫面。
使用者選擇自行操作時交出 UI 控制，環境 owner 仍管理 launch、冷啟、Metro 及清理。
前景恢復與完全關閉後重開需區分。冷啟仍走鎖定 runner，不能改由點 App 圖示取代。
需要使用者觀看時保留指定畫面，再按本次約定續做。切換 UI 操作者不改變 candidate、裝置與證據要求。

## 交付與失敗

交付目標與版本、觀測結果、證據位置、未完成測項及清理狀態。
身分不符、來源變更、EOF、timeout 或 signal 必須停下相依操作。
清理失敗保留 session 證據，不回報成功。
資料不存在證據與 Auth 身分刪除各自驗證。不能只依程序結束碼判定。
還原前核對原 checkout、Metro owner 與既有差異。保留其他任務成果。
