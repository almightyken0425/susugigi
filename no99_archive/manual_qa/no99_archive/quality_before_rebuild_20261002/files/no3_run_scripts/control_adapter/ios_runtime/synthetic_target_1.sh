ORIGINAL_HEAD=$(/usr/bin/git -C "$IMPL_WORKTREE" rev-parse HEAD)
ORIGINAL_INDEX_TREE=$(/usr/bin/git -C "$IMPL_WORKTREE" write-tree)
SYNTHETIC_TMP="$(/usr/bin/mktemp -d)"
SYNTHETIC_INDEX="$SYNTHETIC_TMP/index"

if ! /usr/bin/git -C "$IMPL_WORKTREE" diff --cached --quiet; then
  echo staged changes exist
  exit 1
fi

GIT_INDEX_FILE="$SYNTHETIC_INDEX" /usr/bin/git -C "$IMPL_WORKTREE" read-tree "$ORIGINAL_HEAD"
GIT_INDEX_FILE="$SYNTHETIC_INDEX" /usr/bin/git -C "$IMPL_WORKTREE" add -A -- .

if GIT_INDEX_FILE="$SYNTHETIC_INDEX" /usr/bin/git -C "$IMPL_WORKTREE" \
  ls-files --error-unmatch ios/GoogleService-Info-QA.plist >/dev/null 2>&1; then
  echo QA Firebase private plist entered synthetic tree
  exit 1
fi

TARGET_TREE=$(
  GIT_INDEX_FILE="$SYNTHETIC_INDEX" /usr/bin/git -C "$IMPL_WORKTREE" write-tree
)
TARGET_COMMIT=$(
  printf '%s\n' "sim-review synthetic target" \
    | /usr/bin/git -C "$IMPL_WORKTREE" commit-tree "$TARGET_TREE" -p "$ORIGINAL_HEAD"
)

test "$(/usr/bin/git -C "$IMPL_WORKTREE" rev-parse HEAD)" = "$ORIGINAL_HEAD"
test "$(/usr/bin/git -C "$IMPL_WORKTREE" write-tree)" = "$ORIGINAL_INDEX_TREE"
