# SuSuGiGi 身分與 Digest 契約

此格式由產品 Quality owner 維護。test-define、test-run 與 test-ios 共用同一份。
候選快照與乾淨版本分開。兩種 binding 不得同時存在。

## Control Plane 與 Quality identity

- clean `controlPlaneIdentity` 欄位：
    - `kind` 為 `clean`
    - `repository`
    - `commit`
    - `tree`
- dirty `controlPlaneIdentity` 欄位：
    - `kind` 為 `snapshot`
    - `repository`
    - `baseCommit`
    - `baseTree`
    - `controlPlaneSnapshotDigest`
- Control snapshot schema 為 `control-plane-snapshot/v1`。
- Control snapshot 使用 Quality snapshot 的 canonical 欄位規則。
- Control helper 使用前必須重算 `controlPlaneSnapshotDigest`。
- clean Control root 使用前必須確認 working tree 乾淨。
- clean Control root 必須匹配完整 commit 與 tree。

- clean `qualityIdentity` 欄位：
    - `kind` 為 `clean`
    - `repository`
    - `commit`
    - `tree`
    - `qualityDigest`
- dirty `qualityIdentity` 欄位：
    - `kind` 為 `snapshot`
    - `repository`
    - `baseCommit`
    - `baseTree`
    - `qualitySnapshotDigest`
- `qualityDefinitionDigest` 必須等於：
    - clean 的 `qualityDigest`
    - dirty 的 `qualitySnapshotDigest`
- `caseSetDigest` 欄位：
    - `domain`
    - `value`
- clean domain 使用 clean case-set domain。
- dirty domain 使用 snapshot case-set domain。
- `qualityIdentity.repository` 取自 Quality root 的 origin remote，且重算時必須逐字一致。

---

## Impl worktree snapshot

- domain 為 `susugigi.worktree-snapshot/v1`。
- snapshot 內容包含：
    - base commit
    - base tree SHA
    - tracked binary diff digest
    - untracked paths 與內容 digest
- untracked paths 依 UTF-16 升冪。
- payload 使用 canonical JSON。
- canonical bytes 計算 SHA-256。
- test-ios 前後必須重算。
- snapshot 改變時舊證據失效。
- transient commit 只供 simulator。
- transient 身分不得進 Release manifest。

---

## Quality digest

- 本節 digest 只供 clean Quality 與 Release manifest。
- dirty feature 使用 Quality snapshot。
- Quality snapshot 不寫入 Release manifest。
- domain 為 `susugigi.quality-digest/v1`。
- input 欄位只有：
    - repository
    - commit
    - tree
- payload 欄位只有：
    - domain
    - repository
    - commit
    - tree
- commit 與 tree 必須完整。
- payload 使用 canonical JSON。
- canonical bytes 計算 SHA-256。

---

## Quality snapshot

- schema 為 `quality-snapshot/v1`。
- 只供 dirty feature session。
- payload 欄位只有：
    - schema
    - repository
    - baseCommit
    - baseTree
    - trackedPatchDigest
    - untrackedEntries
- base commit 與 tree 必須完整。
- tracked patch 命令固定為：

```bash
git diff --binary --full-index --no-color --no-ext-diff --no-textconv HEAD --
```

- tracked patch 使用原始 stdout bytes。
- tracked patch 計算 SHA-256。
- untracked entry 欄位只有：
    - path
    - contentDigest
- untracked 清單命令固定為：

```bash
git ls-files --others --exclude-standard -z
```

- path 使用 repo 相對路徑。
- contentDigest 雜湊 raw file bytes。
- untracked paths 依 UTF-16 升冪。
- payload 使用 canonical JSON。
- canonical bytes 計算 SHA-256。
- 結果名稱為 `qualitySnapshotDigest`。
- staged 與 unstaged tracked diff 都納入。
- snapshot 不得進 Release manifest。

---

## Clean case-set digest

- domain 為 `susugigi.case-set-digest/v1`。
- input 欄位只有：
    - `qualityDigest`
    - `selector`
    - `caseIds`
- case IDs 依 UTF-16 升冪。
- `selector` 使用完整 canonical form。
- payload 欄位只有：
    - domain
    - `qualityDigest`
    - `selector`
    - 排序後 `caseIds`
- payload 使用 canonical JSON。
- canonical bytes 計算 SHA-256。
- Release 只接受本 domain。

---

## Dirty case-set digest

- domain 為 `susugigi.case-set-snapshot-digest/v1`。
- input 欄位只有：
    - `qualitySnapshotDigest`
    - `selector`
    - `caseIds`
- payload 欄位只有：
    - domain
    - `qualitySnapshotDigest`
    - `selector`
    - 排序後 `caseIds`
- 欄位名稱為 `qualitySnapshotDigest`。
- `selector` 使用完整 canonical form。
- payload 使用 canonical JSON。
- canonical bytes 計算 SHA-256。
- 只允許 feature selector。
- digest 只留 session。
- digest 不得進 Release manifest。

---

## Selector canonical form

- regression selector 只有：
    - `mode` 為 `regression`
    - `depth` 為確認深度
- depth 值只有：
    - `core`
    - `standard`
    - `extended`
- feature selector 只有：
    - `mode` 為 `feature`
    - `strategy` 為 `branch-diff`
    - `featureLinks` 為功能鍵陣列
    - `riskTags` 為風險標籤陣列
- `featureLinks` 依 UTF-16 升冪。
- `riskTags` 依 UTF-16 升冪。
- 兩個陣列各自去重。
- 兩個陣列聯集至少非空。
- selector 不得加入結果摘要。
- selector 不得加入 session 時間。

---

## Canonical JSON

- id 為 `canonical-json-utf8-no-newline/v1`。
- object keys 依 UTF-16 升冪。
- array 保留既定順序。
- case IDs 先獨立排序。
- feature selector 陣列先正規化。
- string 使用 JSON encoding。
- number 必須是有限值。
- 結構不含額外空白。
- bytes 使用 UTF-8。
- bytes 不含結尾換行。
- manifest 保存 input 與 value。
- validator 必須可重新計算。

---

## Digest 閘門

- `test-run` 開跑前重算 digest。
- regression 的 Release manifest 必須一致。
- Production gate 只接受 regression selector。
- feature session 不得通過 Production gate。
- clean feature 可核對 clean digest。
- dirty feature 核對 snapshot digest。
- Quality tree 不一致時停止。
- case-set 不一致時停止。
- session 續跑前再次核對。
- 任一 digest 改變即失效。

---
