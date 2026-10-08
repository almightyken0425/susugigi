MAIN_REPO=$(/usr/bin/git -C "$IMPL_WORKTREE" worktree list --porcelain | /usr/bin/awk '/^worktree /{print $2; exit}')

test "$(/usr/bin/git -C "$MAIN_REPO" branch --show-current)" = main
test -z "$(/usr/bin/git -C "$MAIN_REPO" status --porcelain)"
MAIN_START_HEAD="$(/usr/bin/git -C "$MAIN_REPO" rev-parse HEAD)"
test "$MAIN_START_HEAD" = "$(/usr/bin/git -C "$MAIN_REPO" rev-parse main)"

RESOLVED_COMMIT=$(/usr/bin/git -C "$MAIN_REPO" rev-parse "$TARGET_COMMIT^{commit}")
RESOLVED_TREE=$(/usr/bin/git -C "$MAIN_REPO" rev-parse "$RESOLVED_COMMIT^{tree}")

test "$RESOLVED_COMMIT" = "$TARGET_COMMIT"
test "$RESOLVED_TREE" = "$TARGET_TREE"

MAIN_RESTORE_REQUIRED=1
/usr/bin/git -C "$MAIN_REPO" checkout --detach "$TARGET_COMMIT"
MAIN_DETACHED=1
