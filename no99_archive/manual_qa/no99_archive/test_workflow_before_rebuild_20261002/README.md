# 舊資料封存

本目錄保存重做前的原始資料。新版 Quality 與測試 Skills 完成驗收前，只能核對清單與完整性，不閱讀內容作為新方法的依據，也不執行舊版程式。

- `manifest.json` 記錄來源版本、原路徑、封存路徑、檔案模式與 SHA-256。
- `files/` 保存原始位元組。指令檔與 Git 設定改用 `.snapshot` 副檔名。
- `verify_archive.py` 只核對封存，不執行舊工具，也不修改檔案。
- `snapshot_retained` 與 `shared_snapshot_retained` 表示原件仍保留。
- `replace_notice` 表示原位置已由停用告示取代。
- `remove_after_verified` 表示核對成功後移出原位置。

## 完整性核對

在本目錄執行：

```bash
python3 -B verify_archive.py
```

## 還原方式

先通過完整性核對，再建立獨立還原目錄。依 `manifest.json` 的 `source_path` 還原每個檔案，並保留記錄的模式與連結種類。還原後再次比對雜湊、數量與子目錄。

不要直接覆蓋已有的新成果。需要正式回復時，先比較差異與現有工作，再依當次授權處理。
