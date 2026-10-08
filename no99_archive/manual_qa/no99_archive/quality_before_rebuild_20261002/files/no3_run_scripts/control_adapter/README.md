# SuSuGiGi Quality 執行適配

本包由 `SuSuGiGi/no2_accounting_app` 的 Quality repo 維護。
`ios_runbook.md` 與 `ios_runtime/` 持有產品環境操作。
`handoff_contract.md` 與 `identity_contract.md` 持有交接及身分契約。
`programs/` 持有固定 QA project、場次、golden 語意與清理程序。
`runtime_manifest.json` 記錄全部執行來源的 SHA-256。

## 與控制系統的交接

Control 的 `manifests/qa_adapters.json` 只登錄 owner、repository、相對位置與 manifest 雜湊。
呼叫者必須明確提供本次 Quality 根目錄。
控制系統不從正式 checkout 偷換候選來源。
先核對 Control 與 Quality identity。再建立私有唯讀快照。
產品程式只從該次 Quality 快照執行。
共用快照驗證、輸入限制及子程序環境檢查留在 Control。

## 支援範圍

只支援 `susugigi-accounting-ios-v1`。
現有 driver 協定值 `sim-review` 對應 `test-ios`。
未知 profile 與不符的 repository 直接拒絕。
R10、R11、R12 與 R14 的既有阻斷條件保留。
執行結果與缺陷證據留在 session。不寫回本 repo。

## 維護與測試

產品程式測試位於 `tests/`。
Control 的跨來源整合測試使用 `QA_QUALITY_TEST_ROOT` 明確指定這個 Quality 工作區。
修改來源後更新本包 manifest。再更新 Control locator 的 manifest 雜湊。
兩個 Git 使用同一主題分支配對審閱。
來源原件可追查 Control 的重構 baseline 與提交歷史。
