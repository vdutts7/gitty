#!/usr/bin/env zsh
# gittysnap snapshot-first sync smoke test
setopt pipefail nounset

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"

typeset -r REPO_ROOT="${0:A:h:h}"
typeset -r SNAP="${SNAP_SCRIPT:-$REPO_ROOT/bin/gittysnap.sh}"
typeset -r GIT="/usr/bin/git"

[[ -x "$SNAP" ]] || { print -u2 "🔴 missing $SNAP"; exit 1 }

typeset -r WORK="$(mktemp -d /tmp/gitty-snap-fixture.XXXXXX)"
trap 'trash -- "$WORK" 2>/dev/null || rm -rf "$WORK" 2>/dev/null || true' EXIT INT TERM

typeset -i PASS=0 FAIL=0
_pass() { print -u2 "🟢 PASS $1"; PASS=$((PASS + 1)) }
_fail() { print -u2 "🔴 FAIL $1 - $2"; FAIL=$((FAIL + 1)) }

# Two clones of one remote = one dev, two machines.
cd "$WORK" || exit 1
"$GIT" init -q --bare remote.git
"$GIT" clone -q remote.git mac
"$GIT" clone -q remote.git wsl
for d in mac wsl; do
  "$GIT" -C "$d" config user.email smoke@test.local
  "$GIT" -C "$d" config user.name smoke
done

cd "$WORK/mac" || exit 1
print -r -- "line1" > code.sh
"$GIT" add -A && "$GIT" commit -qm init
"$GIT" push -q origin HEAD:refs/heads/main
"$GIT" branch -M main 2>/dev/null
"$GIT" branch --set-upstream-to=origin/main main >/dev/null 2>&1
cd "$WORK/wsl" || exit 1
"$GIT" fetch -q origin && "$GIT" checkout -q -B main origin/main
"$GIT" branch --set-upstream-to=origin/main main >/dev/null 2>&1

# ---------- 1. clean sync ----------
cd "$WORK/wsl" || exit 1
print -r -- "WSL EDIT" >> code.sh
"$SNAP" sync "$WORK/wsl" >/dev/null 2>&1
if (( $? == 0 )); then
  _pass "sync: clean path returns 0"
else
  _fail "sync: clean path returns 0" "non-zero exit"
fi
if [[ -n "$("$GIT" ls-remote --heads origin 'refs/heads/snap/*' 2>/dev/null)" ]]; then
  _pass "sync: snapshot branch pushed to remote"
else
  _fail "sync: snapshot branch pushed to remote" "no snap ref on remote"
fi

# ---------- 2. conflicting sync must NOT strand ----------
cd "$WORK/mac" || exit 1
print -r -- "MAC EDIT" >> code.sh
"$SNAP" sync "$WORK/mac" >/dev/null 2>&1
typeset -i rc=$?
if (( rc == 2 )); then
  _pass "conflict: signals rc=2 instead of a false success"
else
  _fail "conflict: signals rc=2 instead of a false success" "got rc=$rc"
fi
if [[ -z "$("$GIT" status --porcelain)" ]]; then
  _pass "conflict: worktree left clean"
else
  _fail "conflict: worktree left clean" "worktree dirty"
fi
if [[ ! -f "$("$GIT" rev-parse --git-dir)/MERGE_HEAD" ]]; then
  _pass "conflict: no merge left in progress"
else
  _fail "conflict: no merge left in progress" "MERGE_HEAD present"
fi
if ! grep -q '<<<<<<<' code.sh; then
  _pass "conflict: no conflict markers written into the file"
else
  _fail "conflict: no conflict markers written into the file" "markers present"
fi
if [[ "$("$GIT" rev-parse --abbrev-ref HEAD)" != "HEAD" ]]; then
  _pass "conflict: HEAD still attached to a branch"
else
  _fail "conflict: HEAD still attached to a branch" "detached HEAD"
fi
# The core guarantee: both machines' work survives on the remote regardless.
typeset -i snapcount
snapcount=$("$GIT" ls-remote --heads origin 'refs/heads/snap/*' 2>/dev/null | wc -l | tr -d ' ')
if (( snapcount >= 2 )); then
  _pass "conflict: both machines' work is on the remote"
else
  _fail "conflict: both machines' work is on the remote" "only $snapcount snapshot(s)"
fi

# ---------- 3. refuses to stack on an in-progress operation ----------
"$GIT" merge --no-ff origin/main >/dev/null 2>&1
"$SNAP" sync "$WORK/mac" >/dev/null 2>&1
if (( $? == 1 )); then
  _pass "guard: refuses to run during an in-progress merge"
else
  _fail "guard: refuses to run during an in-progress merge" "did not refuse"
fi
"$GIT" merge --abort 2>/dev/null

# ---------- 4. snap works offline ----------
print -r -- "offline work" >> code.sh
GITTYSNAP_NO_PUSH=1 "$SNAP" snap "$WORK/mac" >/dev/null 2>&1
if (( $? == 0 )) && [[ -z "$("$GIT" status --porcelain)" ]]; then
  _pass "snap: commits offline without a remote"
else
  _fail "snap: commits offline without a remote" "left uncommitted work"
fi

# ---------- 5. reap never eats unmerged work ----------
"$GIT" merge --no-ff -X ours origin/main -m resolve >/dev/null 2>&1
"$GIT" branch -f snap/main/local/MERGED HEAD
"$GIT" checkout -qb orphan
print -r -- "unmerged" > only-here.txt
"$GIT" add -A && "$GIT" commit -qm unmerged >/dev/null 2>&1
"$GIT" branch -f snap/main/local/UNMERGED HEAD
"$GIT" checkout -q main
GITTYSNAP_KEEP=0 GITTYSNAP_NO_PUSH=1 "$SNAP" reap "$WORK/mac" >/dev/null 2>&1
if ! "$GIT" show-ref --verify -q refs/heads/snap/main/local/MERGED; then
  _pass "reap: deletes snapshots already merged"
else
  _fail "reap: deletes snapshots already merged" "merged snapshot survived"
fi
if "$GIT" show-ref --verify -q refs/heads/snap/main/local/UNMERGED; then
  _pass "reap: refuses to delete unmerged snapshots"
else
  _fail "reap: refuses to delete unmerged snapshots" "UNMERGED WAS DELETED (data loss)"
fi

print -u2 ""
print -u2 "🟢 $PASS passed, 🔴 $FAIL failed"
(( FAIL == 0 )) || exit 1
