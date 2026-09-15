#!/usr/bin/env zsh
setopt errexit pipefail nounset

typeset -r REPO_ROOT="${0:A:h:h}"
typeset -r GITTY_SCRIPT="${GITTY_SCRIPT:-$REPO_ROOT/bin/gitty.sh}"
typeset -r GIT="$(command -v git)"
command -v git-crypt >/dev/null || { print -u2 "git-crypt is required for this regression suite"; exit 1; }
typeset -r FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/gitty-additive.XXXXXX")"
cleanup() {
  if [[ "${GITTY_TEST_KEEP_FIXTURES:-0}" == 1 ]]; then
    print -u2 -- "Fixtures retained: $FIXTURE"
  else
    rm -rf -- "$FIXTURE"
  fi
}
trap cleanup EXIT

export HOME="$FIXTURE/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0
export GIT_AUTHOR_NAME="Gitty Test" GIT_AUTHOR_EMAIL="gitty@example.invalid"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
export GIT_TERMINAL_PROMPT=0 GIT_PAGER=cat LC_ALL=C
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
typeset CASE WORK PEER BARE LOCAL_TIP REMOTE_TIP OUTPUT=""
typeset -i RC=0 PASS=0

_assert() {
  local label="$1"
  shift
  if ! "$@"; then
    print -u2 -- "FAIL: $label"
    print -u2 -r -- "$OUTPUT"
    exit 1
  fi
}

_pass() {
  PASS=$((PASS + 1))
  print -- "PASS: $1"
}

_new_case() {
  CASE="$FIXTURE/$1"
  WORK="$CASE/local"
  PEER="$CASE/peer"
  BARE="$CASE/remote.git"
  OUTPUT=""
  mkdir -p "$CASE"
  "$GIT" init -q --bare -b main "$BARE"
  "$GIT" init -q -b main "$WORK"
  "$GIT" -C "$WORK" remote add origin "$BARE"
  mkdir -p "$WORK/host-a" "$WORK/host-b"
  printf 'base\n' > "$WORK/host-a/live.txt"
  printf 'base\n' > "$WORK/shared.txt"
  : > "$WORK/host-b/empty.txt"
  if [[ "${2:-plain}" == encrypted ]]; then
    printf '* filter=git-crypt diff=git-crypt\n.gitattributes !filter !diff\n' > "$WORK/.gitattributes"
    (cd "$WORK" && git-crypt init && git-crypt export-key "$CASE/key")
  fi
  "$GIT" -C "$WORK" add -A
  "$GIT" -C "$WORK" commit -qm seed
  "$GIT" -C "$WORK" push -qu origin main
  "$GIT" clone -q "$BARE" "$PEER"
  if [[ "${2:-plain}" == encrypted ]]; then
    (cd "$PEER" && git-crypt unlock "$CASE/key")
    _assert "empty plaintext is encrypted in Git" test "$("$GIT" -C "$WORK" cat-file -s HEAD:host-b/empty.txt)" -eq 22
  fi
  LOCAL_TIP=$("$GIT" -C "$WORK" rev-parse HEAD)
  REMOTE_TIP="$LOCAL_TIP"
}

_remote_update() {
  local file="${1:-host-b/empty.txt}"
  printf 'remote\n' > "$PEER/$file"
  "$GIT" -C "$PEER" add "$file"
  "$GIT" -C "$PEER" commit -qm remote
  "$GIT" -C "$PEER" push -q origin main
  REMOTE_TIP=$("$GIT" -C "$PEER" rev-parse HEAD)
}

_remote_delete() {
  local file="${1:-host-b/empty.txt}"
  "$GIT" -C "$PEER" rm -q -f "$file"
  "$GIT" -C "$PEER" commit -qm remote-delete
  "$GIT" -C "$PEER" push -q origin main
  REMOTE_TIP=$("$GIT" -C "$PEER" rev-parse HEAD)
}

_local_update() {
  local file="${1:-host-a/live.txt}"
  printf 'local\n' > "$WORK/$file"
  "$GIT" -C "$WORK" add "$file"
  "$GIT" -C "$WORK" commit -qm local
  LOCAL_TIP=$("$GIT" -C "$WORK" rev-parse HEAD)
}

_run_gitty() {
  RC=0
  OUTPUT=$(cd "$WORK" && GITTY_ENV="" GITTY_FORCE=0 GITTY_PARTIAL="${1:-0}" \
    GITTY_NO_STALE_BASE_HEAL=0 GITTY_PUSH_RETRIES=0 \
    zsh "$GITTY_SCRIPT" "additive integration regression" "$WORK" 2>&1) || RC=$?
}

_assert_synced() {
  local incoming="${1:-host-b/empty.txt}" expected="${2:-remote}"
  _assert "gitty succeeds" test "$RC" -eq 0
  _assert "local tip remains reachable" "$GIT" -C "$WORK" merge-base --is-ancestor "$LOCAL_TIP" HEAD
  _assert "remote tip was integrated" "$GIT" -C "$WORK" merge-base --is-ancestor "$REMOTE_TIP" HEAD
  _assert "remote main matches local HEAD" test "$("$GIT" -C "$WORK" rev-parse HEAD)" = "$("$GIT" --git-dir="$BARE" rev-parse main)"
  _assert "no unresolved index entries" test -z "$("$GIT" -C "$WORK" ls-files -u)"
  _assert "merge state cleared" test ! -e "$WORK/.git/MERGE_HEAD"
  _assert "integrated worktree content is correct" test "$(cat "$WORK/$incoming")" = "$expected"
}

_assert_failed_not_parked() {
  _assert "merge execution failure exits 2" test "$RC" -eq 2
  _assert "Git diagnostic is preserved" grep -q 'does not have a GPG signature' <<< "$OUTPUT"
  _assert "execution failure is identified" grep -q 'Additive integrate failed' <<< "$OUTPUT"
  _assert "failure was not called a parked conflict" test "${OUTPUT#*Conflict parked}" = "$OUTPUT"
  _assert "no pending-conflict ref created" test -z "$("$GIT" -C "$WORK" for-each-ref --format='%(refname)' refs/heads/bak/pending-merge refs/heads/remote-snapshot)"
  _assert "local HEAD preserved" test "$("$GIT" -C "$WORK" rev-parse HEAD)" = "$LOCAL_TIP"
  _assert "remote main preserved" test "$("$GIT" --git-dir="$BARE" rev-parse main)" = "$REMOTE_TIP"
}

_new_case encrypted-ff encrypted
_remote_update
cp "$WORK/.git/config" "$CASE/config.before"
_run_gitty
_assert_synced
_assert "fast-forward reaches the exact remote tip" test "$("$GIT" -C "$WORK" rev-parse HEAD)" = "$REMOTE_TIP"
_assert "encryption configuration unchanged" cmp "$CASE/config.before" "$WORK/.git/config"
_assert "incoming blob remains encrypted" test "$("$GIT" -C "$WORK" cat-file -s HEAD:host-b/empty.txt)" -eq 29
_pass "encrypted empty file fast-forward"

_new_case encrypted-diverged encrypted
_remote_update
_local_update
cp "$WORK/.git/config" "$CASE/config.before"
_run_gitty
_assert_synced
_assert "merge retains both exact parents" test "$("$GIT" -C "$WORK" log -1 --format=%P)" = "$LOCAL_TIP $REMOTE_TIP"
_assert "remote ciphertext is preserved byte-for-byte" test "$("$GIT" -C "$WORK" rev-parse HEAD:host-b/empty.txt)" = "$("$GIT" -C "$PEER" rev-parse HEAD:host-b/empty.txt)"
_assert "encryption configuration unchanged" cmp "$CASE/config.before" "$WORK/.git/config"
_pass "encrypted disjoint two-parent merge"

_new_case encrypted-delete encrypted
_remote_delete
_local_update
_run_gitty
_assert "encrypted deletion integration succeeds" test "$RC" -eq 0
_assert "encrypted deletion retains local tip" "$GIT" -C "$WORK" merge-base --is-ancestor "$LOCAL_TIP" HEAD
_assert "encrypted deletion integrates remote tip" "$GIT" -C "$WORK" merge-base --is-ancestor "$REMOTE_TIP" HEAD
_assert "encrypted incoming deletion reaches worktree" test ! -e "$WORK/host-b/empty.txt"
_assert "encrypted deletion merge retains both parents" test "$("$GIT" -C "$WORK" log -1 --format=%P)" = "$LOCAL_TIP $REMOTE_TIP"
_pass "encrypted incoming deletions survive fallback"

_new_case encrypted-live-writer encrypted
_remote_update
printf 'snapshot\n' > "$WORK/host-a/live.txt"
cat > "$WORK/.git/hooks/post-commit" <<'HOOK'
#!/usr/bin/env zsh
printf 'concurrent\n' >> host-a/live.txt
HOOK
chmod +x "$WORK/.git/hooks/post-commit"
_run_gitty
_assert_synced
printf 'snapshot\nconcurrent\n' | _assert "concurrent appends stay in the worktree" cmp - "$WORK/host-a/live.txt"
"$GIT" -C "$WORK" show HEAD:host-a/live.txt | (cd "$WORK" && git-crypt smudge) > "$CASE/committed"
printf 'snapshot\n' | _assert "dirty appends did not enter the merge commit" cmp - "$CASE/committed"
_pass "encrypted merge preserves dirty non-overlapping writes"

_new_case plain-diverged
_remote_update
_local_update
_run_gitty
_assert_synced
_assert "ordinary merge retains both parents" test "$("$GIT" -C "$WORK" log -1 --format=%P)" = "$LOCAL_TIP $REMOTE_TIP"
_pass "ordinary disjoint merge"

_new_case real-conflict
_remote_update shared.txt
_local_update shared.txt
_run_gitty
_assert "real conflicts retain non-fatal park behavior" test "$RC" -eq 0
_assert "real conflict is reported" grep -q 'Conflict parked' <<< "$OUTPUT"
_assert "park preserves local tip" test "$("$GIT" -C "$WORK" rev-parse HEAD)" = "$LOCAL_TIP"
_assert "park preserves remote main" test "$("$GIT" --git-dir="$BARE" rev-parse main)" = "$REMOTE_TIP"
_assert "local snapshot ref retains its tip" test "$("$GIT" -C "$WORK" for-each-ref --format='%(objectname)' 'refs/heads/bak/pending-merge-*')" = "$LOCAL_TIP"
_assert "remote snapshot ref retains its tip" test "$("$GIT" -C "$WORK" for-each-ref --format='%(objectname)' refs/heads/remote-snapshot)" = "$REMOTE_TIP"
_assert "local conflict content preserved" test "$(cat "$WORK/shared.txt")" = local
_assert "park clears merge state" test ! -e "$WORK/.git/MERGE_HEAD"
_assert "park clears unresolved index entries" test -z "$("$GIT" -C "$WORK" ls-files -u)"
_pass "genuine conflicts still park on durable refs"

_new_case partial-conflict
_remote_update shared.txt
_local_update shared.txt
_run_gitty 1
_assert_synced shared.txt local
_assert "partial integration retains both parents" test "$("$GIT" -C "$WORK" log -1 --format=%P)" = "$LOCAL_TIP $REMOTE_TIP"
_assert "partial integration is reported" grep -q 'Additive integrate (partial)' <<< "$OUTPUT"
_pass "partial conflict handling remains additive"

_new_case pre-merge-error
_remote_update
_local_update
"$GIT" -C "$WORK" config merge.verifySignatures true
_run_gitty
_assert_failed_not_parked
_assert "pre-merge error did not create merge state" test ! -e "$WORK/.git/MERGE_HEAD"
_pass "pre-merge errors stop with the original Git diagnostic"

_new_case stale-base-error
_remote_update
_local_update
"$GIT" -C "$WORK" config merge.verifySignatures true
cat > "$WORK/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env zsh
print -u2 'Stale-base guard'
exit 1
HOOK
chmod +x "$WORK/.git/hooks/pre-commit"
printf 'draft\n' > "$WORK/draft.txt"
_run_gitty 1
_assert_failed_not_parked
_assert "stale-base path preserves staged work" test "$("$GIT" -C "$WORK" show :draft.txt)" = draft
_assert "failed integration does not enter elimination retries" test "${OUTPUT#*trying without}" = "$OUTPUT"
_pass "stale-base autoheal propagates integration errors"

_new_case push-retry-error
_local_update
export TEST_PEER="$PEER"
cat > "$WORK/.git/hooks/pre-push" <<'HOOK'
#!/usr/bin/env zsh
setopt errexit pipefail nounset
[[ -e .git/retry-injected ]] && exit 0
touch .git/retry-injected
printf 'remote\n' > "$TEST_PEER/host-b/empty.txt"
git -C "$TEST_PEER" add host-b/empty.txt
git -C "$TEST_PEER" commit -qm concurrent-remote
git -C "$TEST_PEER" push -q origin main
git config merge.verifySignatures true
print -u2 'injected concurrent push rejection'
exit 1
HOOK
chmod +x "$WORK/.git/hooks/pre-push"
_run_gitty
REMOTE_TIP=$("$GIT" -C "$PEER" rev-parse HEAD)
_assert_failed_not_parked
_assert "push retry path was exercised" grep -q 'Push rejected; re-integrating and retrying' <<< "$OUTPUT"
_pass "push retry propagates integration errors"

_new_case merge-hook-error
_remote_update
_local_update
cat > "$WORK/.git/hooks/pre-merge-commit" <<'HOOK'
#!/usr/bin/env zsh
print -u2 'merge hook declined'
exit 1
HOOK
chmod +x "$WORK/.git/hooks/pre-merge-commit"
_run_gitty
_assert "merge-hook failure exits 2" test "$RC" -eq 2
_assert "merge-hook diagnostic is preserved" grep -q 'merge hook declined' <<< "$OUTPUT"
_assert "merge-hook failure is not parked" test "${OUTPUT#*Conflict parked}" = "$OUTPUT"
_assert "unfinished merge remains available to resolve" test -e "$WORK/.git/MERGE_HEAD"
_assert "merge-hook failure preserves HEAD" test "$("$GIT" -C "$WORK" rev-parse HEAD)" = "$LOCAL_TIP"
_assert "merge-hook failure preserves remote main" test "$("$GIT" --git-dir="$BARE" rev-parse main)" = "$REMOTE_TIP"
_pass "merge-hook failures preserve in-progress state"

_new_case encrypted-merge-hook-error encrypted
_remote_update
_local_update
cat > "$WORK/.git/hooks/pre-merge-commit" <<'HOOK'
#!/usr/bin/env zsh
print -u2 'encrypted merge hook declined'
exit 1
HOOK
chmod +x "$WORK/.git/hooks/pre-merge-commit"
_run_gitty
_assert "encrypted fallback hook failure exits 2" test "$RC" -eq 2
_assert "encrypted fallback hook diagnostic is preserved" grep -q 'encrypted merge hook declined' <<< "$OUTPUT"
_assert "encrypted fallback hook failure is not parked" test "${OUTPUT#*Conflict parked}" = "$OUTPUT"
_assert "encrypted fallback hook failure preserves HEAD" test "$("$GIT" -C "$WORK" rev-parse HEAD)" = "$LOCAL_TIP"
_pass "encrypted fallback hook failures remain execution errors"

for resolution in configured partial; do
  _new_case "$resolution-hook-error"
  _remote_update shared.txt
  if [[ "$resolution" == configured ]]; then
    mkdir "$WORK/.gitty"
    printf 'per_host:\n  paths:\n    - shared.txt\n' > "$WORK/.gitty/additive-resolvers.yaml"
    "$GIT" -C "$WORK" add .gitty/additive-resolvers.yaml
    "$GIT" -C "$WORK" commit -qm resolver-config
  fi
  _local_update shared.txt
  cat > "$WORK/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env zsh
if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
  print -u2 'resolved merge hook declined'
  exit 1
fi
exit 0
HOOK
  chmod +x "$WORK/.git/hooks/pre-commit"
  if [[ "$resolution" == configured ]]; then _run_gitty 0; else _run_gitty 1; fi
  _assert "resolved merge commit failure exits 2" test "$RC" -eq 2
  _assert "resolved merge hook diagnostic is preserved" grep -q 'resolved merge hook declined' <<< "$OUTPUT"
  _assert "resolved merge failure is not parked" test "${OUTPUT#*Conflict parked}" = "$OUTPUT"
  _assert "resolved merge state remains available" test -e "$WORK/.git/MERGE_HEAD"
  _assert "resolved merge has no unmerged entries" test -z "$("$GIT" -C "$WORK" ls-files -u)"
  _assert "resolved merge preserves HEAD" test "$("$GIT" -C "$WORK" rev-parse HEAD)" = "$LOCAL_TIP"
  _assert "resolved merge preserves remote main" test "$("$GIT" --git-dir="$BARE" rev-parse main)" = "$REMOTE_TIP"
  _pass "$resolution resolver commit errors preserve in-progress state"
done

# ---------------------------------------------------------------------------
# Regression: gitty_merge_without_internal_stash must feed pathspecs to
# `git restore` via NUL stdin, not argv. A large integrate (tens of thousands
# of changed paths) overflows ARG_MAX and aborts the fallback with E2BIG
# ("argument list too long: git"). A `git` shim simulates the kernel argument
# limit at small N so the guard stays deterministic without materializing a
# 50k-file fixture: it rejects a `restore` that carries pathspecs in argv but
# lets the NUL-stdin form (--pathspec-from-file) through.
# ---------------------------------------------------------------------------
_new_case fallback-arg-max encrypted
mkdir -p "$PEER/host-b/bulk"
typeset -i _i
for _i in {1..120}; do
  printf 'remote-%d\n' "$_i" > "$PEER/host-b/bulk/file-$(printf '%04d' "$_i").txt"
done
"$GIT" -C "$PEER" add -A
"$GIT" -C "$PEER" commit -qm remote-bulk
"$GIT" -C "$PEER" push -q origin main
REMOTE_TIP=$("$GIT" -C "$PEER" rev-parse HEAD)
_local_update   # disjoint local commit -> forces the two-parent fallback

typeset _shimdir="$CASE/shim"
mkdir -p "$_shimdir"
cat > "$_shimdir/git" <<SHIM
#!/usr/bin/env zsh
_real="$GIT"
# Police only the restore verb; simulate execve E2BIG when pathspecs ride in
# argv over the cap. The NUL-stdin form keeps argv tiny and is exempt.
if [[ " \$* " == *" restore "* && " \$* " != *"--pathspec-from-file"* ]]; then
  typeset _all="\$*"
  (( \${#_all} > 512 )) && { print -u2 "argument list too long: git"; exit 1; }
fi
exec "\$_real" "\$@"
SHIM
chmod +x "$_shimdir/git"

RC=0
OUTPUT=$(cd "$WORK" && PATH="$_shimdir:$PATH" GITTY_ENV="" GITTY_FORCE=0 GITTY_PARTIAL=0 \
  GITTY_NO_STALE_BASE_HEAL=0 GITTY_PUSH_RETRIES=0 \
  zsh "$GITTY_SCRIPT" "additive integration regression" "$WORK" 2>&1) || RC=$?
_assert_synced "host-b/bulk/file-0001.txt" "remote-1"
_assert "fallback used the NUL-stdin restore" grep -q 'without Git internal stash' <<< "$OUTPUT"
_assert "every bulk path integrated" \
  test "$("$GIT" -C "$WORK" ls-files 'host-b/bulk' | wc -l | tr -d ' ')" -eq 120
_pass "fallback restores large changed set without ARG_MAX overflow"

print -- "additive integration smoke: $PASS passed"
