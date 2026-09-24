#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
PLUNGER="$ROOT/bin/gittyplunger.py"
GITTY="$ROOT/bin/gitty.sh"
HEALTH="$ROOT/bin/gittyhealth.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gittyplunger.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0

pass() { echo "🟢 PASS $1"; PASS=$((PASS + 1)); }
fail() { echo "🔴 FAIL $1 — $2"; FAIL=$((FAIL + 1)); }

export GIT_AUTHOR_NAME="Plunger Test"
export GIT_AUTHOR_EMAIL="plunger@example.invalid"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

make_repo() {
  local name="$1"
  local remote="$TMP/$name.git"
  local repo="$TMP/$name"
  git init -q --bare --initial-branch=main "$remote"
  git init -q --initial-branch=main "$repo"
  git -C "$repo" remote add origin "$remote"
  printf 'base\n' > "$repo/base.txt"
  git -C "$repo" add base.txt
  git -C "$repo" commit -qm base
  git -C "$repo" push -q -u origin main
  printf '%s\n' "$repo"
}

REPO="$(make_repo direct)"
python3 -c "open('$REPO/clog.bin','wb').write(b'x'*2048)"
printf 'one\n' > "$REPO/clean-one.txt"
git -C "$REPO" add .
git -C "$REPO" commit -qm 'local one'
python3 -c "open('$REPO/clog.bin','wb').write(b'y'*3072)"
printf 'two\n' > "$REPO/clean-two.txt"
git -C "$REPO" add .
git -C "$REPO" commit -qm 'local two'
OLD_HEAD="$(git -C "$REPO" rev-parse HEAD)"

SCAN="$(python3 "$PLUNGER" scan "$REPO" --max-bytes 1000 --json)"
[[ "$(jq -r '.clog_path_count' <<<"$SCAN")" == 1 ]] \
  && [[ "$(jq -r '.clog_paths[0]' <<<"$SCAN")" == clog.bin ]] \
  && pass "scan finds one buried clog path" \
  || fail "scan finds one buried clog path" "$SCAN"
HEALTH_OUTPUT="$(GITTY_MAX_FILE_BYTES=1000 zsh "$HEALTH" "$REPO")"
grep -q 'buried oversized path(s) block the outgoing pipe' <<<"$HEALTH_OUTPUT" \
  && pass "gittyhealth surfaces the buried clog" \
  || fail "gittyhealth surfaces the buried clog" "$HEALTH_OUTPUT"

PLUNGED="$(python3 "$PLUNGER" plunge "$REPO" --max-bytes 1000 --yes --json)"
NEW_HEAD="$(git -C "$REPO" rev-parse HEAD)"
TRAP_REF="$(jq -r '.trap_ref' <<<"$PLUNGED")"
[[ "$NEW_HEAD" != "$OLD_HEAD" ]] \
  && [[ "$(git -C "$REPO" rev-parse "$TRAP_REF")" == "$OLD_HEAD" ]] \
  && pass "plunge rewrites main and traps original tip" \
  || fail "plunge rewrites main and traps original tip" "$PLUNGED"
git -C "$REPO" cat-file -e "$NEW_HEAD:clean-one.txt" \
  && git -C "$REPO" cat-file -e "$NEW_HEAD:clean-two.txt" \
  && ! git -C "$REPO" cat-file -e "$NEW_HEAD:clog.bin" 2>/dev/null \
  && [[ -f "$REPO/clog.bin" ]] \
  && pass "clean paths survive and clog stays local" \
  || fail "clean paths survive and clog stays local" "tree mismatch"
AFTER_SCAN="$(python3 "$PLUNGER" scan "$REPO" --max-bytes 1000 --json)"
[[ "$(jq -r '.clear' <<<"$AFTER_SCAN")" == true ]] \
  && pass "rewritten outgoing range is clear" \
  || fail "rewritten outgoing range is clear" "$AFTER_SCAN"

AUTO="$(make_repo automatic)"
python3 -c "open('$AUTO/clog.bin','wb').write(b'z'*2048)"
printf 'clean\n' > "$AUTO/clean.txt"
git -C "$AUTO" add .
git -C "$AUTO" commit -qm 'buried clog'
printf 'later\n' > "$AUTO/later.txt"
OUTPUT="$(
  GITTY_ENV="" \
  GITTY_PARTIAL=1 \
  GITTY_PLUNGER=1 \
  GITTY_MAX_FILE_BYTES=1000 \
    zsh "$GITTY" "later clean change" "$AUTO" 2>&1
)"
REMOTE_HEAD="$(git --git-dir "$TMP/automatic.git" rev-parse main)"
git --git-dir "$TMP/automatic.git" cat-file -e "$REMOTE_HEAD:clean.txt" \
  && git --git-dir "$TMP/automatic.git" cat-file -e "$REMOTE_HEAD:later.txt" \
  && ! git --git-dir "$TMP/automatic.git" cat-file -e "$REMOTE_HEAD:clog.bin" 2>/dev/null \
  && grep -q 'gittyplunger' <<<"$OUTPUT" \
  && pass "plain gitty auto-plunges before push" \
  || fail "plain gitty auto-plunges before push" "$OUTPUT"

echo "gittyplunger smoke: $PASS passed, $FAIL failed"
(( FAIL == 0 ))
