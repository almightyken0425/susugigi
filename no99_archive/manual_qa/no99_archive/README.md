# Quality 與測試 Skill 集中封存

本目錄保存 SuSuGiGi Quality Git、`test-define` 與 `test-run` 的歷史內容。封存日期為 2026-10-08。資料供查考與還原，不是使用中的測試方法。

Quality repository 保留 Git 歷史，工作檔案清空。兩個 Skill 的使用中入口及舊名稱路由撤下。`test-ios` 入口保留，但原 SuSuGiGi QA 適配包已撤下，不能啟動依賴該包的場次。

## 內容位置

| 內容 | 位置 |
| --- | --- |
| Quality 來源索引、最小契約與代表案例 | `sources.yaml`、`contracts/`、`representative_cases.yaml` |
| 上述成果原有說明 | `README.md.snapshot` |
| 原來源檢查程式 | `scripts/check_sources.py` |
| 2026-10-02 以前的 Quality 舊資料 | `quality_before_rebuild_20261002/` |
| 控制層舊測試流程與原 Skill 方法 | `test_workflow_before_rebuild_20261002/` |
| 撤下前的 Codex、Claude 入口與能力登記 | `skill_entrypoints_before_archive_20261008/` |
| Quality 清空前的規則與 Git 設定 | `quality_checkout_before_clear/` |

原始檔案保留位元組與模式。入口和設定快照使用 `.snapshot` 副檔名，避免被當作有效指令。`AGENTS.local.md.snapshot` 保留搬移時已清空的本機版本，`AGENTS.md.snapshot` 保留 Git 中的原版本。

## 完整性與還原

`archive_manifest.json` 記錄來源 repository、來源版本、原路徑、封存路徑、大小、模式與 SHA-256。同一檔案可能有多筆來源紀錄，表示本機搬移副本與 Git 原件相同。

在本目錄執行下列唯讀檢查：

```bash
python3 -B verify_archive.py
```

檢查器只驗證封存，不執行舊測試工具。需要還原時，先通過檢查，再依清單在獨立目錄還原。不要覆蓋後續的新成果。兩個舊封存包各自的原始清單與驗證程式也保留。

## 本機憑證

`no2_qa_tools/serviceAccountKey.json` 保留於正式目的地的本機目錄，內容不進 Git，也不複製到審閱工作區。本目錄的 `.gitignore` 排除 service account key 與 `*.key.json`。Git 同步不會傳送這些憑證。
