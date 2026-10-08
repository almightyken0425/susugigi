# Refresh 與 Digest

## 基線語意

- 基線表示定義已反映上游。
- 每個 repo 記完整 commit。
- 每個 repo 記完整 tree SHA。
- 基線只在索引保存一次。
- refresh 完成後整批推進。
- refresh 中斷時維持舊基線。

---

## Refresh

- 比對基線 commit 與 HEAD。
- Spec 異動反查規格依據。
- Impl 異動反查實作錨。
- 新規格零引用列為缺口。
- 消失依據列為孤兒候選。
- 能力改動反查 capability。
- scene 改動反查 seed scene。
- check 改動反查 inspect check。
- 先產影響表。
- 確認後更新定義。
- 完整檢核後推進基線。

---

## 身分與 Digest

依已解析 Quality owner 選取同一份產品契約。
SuSuGiGi 的欄位、排序、版本與拒絕條件只由 `<已鎖定 Quality 根目錄>/no3_run_scripts/control_adapter/identity_contract.md` 維護。
既有授權已涵蓋 refresh 時，確認影響表後直接更新。內容矛盾回原主人。

## 基線失效

- commit 不可達時停止 refresh。
- 該 repo 改為全面重驗。
- 原因必須回報。
- 有上游異動但零 case 時停止。
- 停止時列出所有異動路徑。
