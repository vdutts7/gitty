#!/usr/bin/env zsh
# NDJSON union merge-driver smoke test
setopt pipefail nounset

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"

typeset -r REPO_ROOT="${0:A:h:h}"
typeset -r UNION_SCRIPT="${UNION_SCRIPT:-$REPO_ROOT/bin/gittyunion.sh}"
typeset -r GIT="/usr/bin/git"
typeset -r PYTHON3="${PYTHON3:-$(command -v python3)}"

[[ -x "$UNION_SCRIPT" ]] || { print -u2 "🔴 missing $UNION_SCRIPT"; exit 1 }
[[ -n "$PYTHON3" && -x "$PYTHON3" ]] || { print -u2 "🔴 missing python3"; exit 1 }

typeset -r FIXTURE="$(mktemp -d /tmp/gitty-union-fixture.XXXXXX)"
trap 'trash -- "$FIXTURE" 2>/dev/null || rm -rf "$FIXTURE" 2>/dev/null || true' EXIT INT TERM

typeset -i PASS=0 FAIL=0
_pass() { print -u2 "🟢 PASS $1"; PASS=$((PASS + 1)) }
_fail() { print -u2 "🔴 FAIL $1 - $2"; FAIL=$((FAIL + 1)) }

# ---------- 1. install registers driver + attributes ----------
cd "$FIXTURE" || exit 1
"$GIT" init -b main -q
"$GIT" config user.email smoke@test.local
"$GIT" config user.name "smoke"
print -r -- '{"id":"a","ts":"2026-01-01T00:00:00Z"}' > log.ndjson
"$GIT" add -A && "$GIT" commit -qm base

"$UNION_SCRIPT" install "$FIXTURE" >/dev/null 2>&1
if [[ -n "$("$GIT" config --get merge.ndjson-union.driver)" ]]; then
  _pass "install registers merge.ndjson-union.driver"
else
  _fail "install registers merge.ndjson-union.driver" "config missing"
fi

if [[ "$("$GIT" check-attr merge -- log.ndjson)" == *ndjson-union* ]]; then
  _pass "install declares merge=ndjson-union in .gitattributes"
else
  _fail "install declares merge=ndjson-union in .gitattributes" "attr unset"
fi

"$GIT" add -A && "$GIT" commit -qm attrs

# ---------- 2. concurrent appends auto-merge (the core case) ----------
"$GIT" checkout -qb other
print -r -- '{"id":"c","ts":"2026-01-03T00:00:00Z"}' >> log.ndjson
"$GIT" commit -qam "append c"
"$GIT" checkout -q main
print -r -- '{"id":"b","ts":"2026-01-02T00:00:00Z"}' >> log.ndjson
"$GIT" commit -qam "append b"

if "$GIT" merge --no-ff other -m merge >/dev/null 2>&1; then
  _pass "merge: concurrent appends resolve without conflict"
else
  _fail "merge: concurrent appends resolve without conflict" "merge returned non-zero"
fi

typeset -i n_records
n_records=$(grep -c . log.ndjson)
if (( n_records == 3 )); then
  _pass "merge: all 3 records preserved (lossless)"
else
  _fail "merge: all 3 records preserved (lossless)" "got $n_records"
fi

if [[ "$(sed -n 2p log.ndjson)" == *'"id":"b"'* && "$(sed -n 3p log.ndjson)" == *'"id":"c"'* ]]; then
  _pass "merge: new records ordered by timestamp"
else
  _fail "merge: new records ordered by timestamp" "$(tr '\n' ' ' < log.ndjson)"
fi

if ! grep -q '^<<<<<<<\|^>>>>>>>' log.ndjson; then
  _pass "merge: no conflict markers written"
else
  _fail "merge: no conflict markers written" "markers present"
fi

# ---------- 3. rebase container also resolves ----------
"$GIT" checkout -qb rebasetest other
print -r -- '{"id":"d","ts":"2026-01-04T00:00:00Z"}' >> log.ndjson
"$GIT" commit -qam "append d"
if "$GIT" rebase main >/dev/null 2>&1; then
  _pass "rebase: resolves without stranding the worktree"
else
  "$GIT" rebase --abort 2>/dev/null
  _fail "rebase: resolves without stranding the worktree" "rebase stalled"
fi
if (( $("$GIT" diff --name-only --diff-filter=U | wc -l) == 0 )); then
  _pass "rebase: no unmerged paths left behind"
else
  _fail "rebase: no unmerged paths left behind" "unmerged paths remain"
fi
"$GIT" checkout -q main

# ---------- 4. malformed input fails closed ----------
print -r -- '{"id":"a","ts":"1"}' > "$FIXTURE/o.ndjson"
print -rl -- '{"id":"a","ts":"1"}' '{"id":"b","ts":"2"}' > "$FIXTURE/a.ndjson"
print -rl -- '{"id":"a","ts":"1"}' 'NOT JSON' > "$FIXTURE/b.ndjson"
"$UNION_SCRIPT" merge "$FIXTURE/o.ndjson" "$FIXTURE/a.ndjson" "$FIXTURE/b.ndjson" bad.ndjson >/dev/null 2>&1
if (( $? != 0 )); then
  _pass "malformed JSON leaves conflict for human (fails closed)"
else
  _fail "malformed JSON leaves conflict for human (fails closed)" "silently unioned"
fi
if [[ "$(grep -c . "$FIXTURE/a.ndjson")" == 2 ]]; then
  _pass "malformed JSON leaves ours untouched"
else
  _fail "malformed JSON leaves ours untouched" "ours was mutated"
fi

# ---------- 5. verify reports a healthy repo ----------
if "$UNION_SCRIPT" verify "$FIXTURE" >/dev/null 2>&1; then
  _pass "verify: passes on a configured repo"
else
  _fail "verify: passes on a configured repo" "verify returned non-zero"
fi

# ---------- 6. gitty self-heals an unregistered clone ----------
# .gitattributes clones but .git/config does not, so a fresh clone names a driver
# that does not exist and git falls back to the CONFLICTING default merge.
typeset -r HEALDIR="$(mktemp -d /tmp/gitty-union-heal.XXXXXX)"
cd "$HEALDIR" || exit 1
"$GIT" init -b main -q
"$GIT" config user.email smoke@test.local
"$GIT" config user.name "smoke"
print -r -- '*.ndjson merge=ndjson-union' > .gitattributes
print -r -- '{"id":"a","ts":"1"}' > l.ndjson
"$GIT" add -A && "$GIT" commit -qm base
"${REPO_ROOT}/bin/gitty.sh" "heal" "$HEALDIR" >/dev/null 2>&1
if [[ -n "$("$GIT" config --get merge.ndjson-union.driver)" ]]; then
  _pass "gitty auto-registers a declared-but-missing driver"
else
  _fail "gitty auto-registers a declared-but-missing driver" "still unregistered"
fi
cd "$FIXTURE" || exit 1
trash -- "$HEALDIR" 2>/dev/null || rm -rf "$HEALDIR" 2>/dev/null || true

print -u2 ""
print -u2 "🟢 $PASS passed, 🔴 $FAIL failed"
(( FAIL == 0 )) || exit 1
