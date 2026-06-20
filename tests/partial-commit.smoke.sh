#!/usr/bin/env zsh
# Partial-commit smoke (downstream) — SSOT: $CURTOOLS/test/gitty-partial-commit.smoke.sh
setopt errexit pipefail nounset

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"

typeset -r REPO_ROOT="${0:A:h:h}"
typeset -r GITTY_SCRIPT="${GITTY_SCRIPT:-$REPO_ROOT/bin/gitty.sh}"
typeset -r GIT="/usr/bin/git"
typeset -r PYTHON3="${PYTHON3:-$(command -v python3)}"
typeset -r CUR="${CUR:-$HOME/.cursor}"
typeset -r GENESIS_LIB="$CUR/tools/lib/smoke-genesis.sh"

[[ -x "$GITTY_SCRIPT" ]] || { print -u2 "🔴 missing $GITTY_SCRIPT"; exit 1 }
[[ -n "$PYTHON3" && -x "$PYTHON3" ]] || { print -u2 "🔴 missing python3"; exit 1 }

if [[ -f "$GENESIS_LIB" ]]; then
  # shellcheck source=/dev/null
  source "$GENESIS_LIB"
  SMOKE_NAMESPACE="gitty-partial"
  smoke_genesis_init "$SMOKE_NAMESPACE" $$
  export SMOKE_RUN_DIR
  trap '_smoke_genesis_dispose_all' EXIT INT TERM
  smoke_genesis_fixture_dir partial || exit 1
  typeset -r FIXTURE="$SMOKE_LAST_FIXTURE_DIR"
  trap 'smoke_genesis_cleanup_fixture partial' EXIT INT TERM
  typeset -r BARE="$SMOKE_RUN_DIR/remote.git"
else
  typeset -r FIXTURE="$(mktemp -d /tmp/gitty-partial-fixture.XXXXXX)"
  typeset -r BARE="$(mktemp -d /tmp/gitty-partial-bare.XXXXXX)"
  trap 'trash -- "$FIXTURE" "$BARE" 2>/dev/null || true' EXIT INT TERM
fi

typeset -i PASS=0 FAIL=0
_pass() { print -u2 "🟢 PASS $1"; PASS=$((PASS + 1)) }
_fail() { print -u2 "🔴 FAIL $1 — $2"; FAIL=$((FAIL + 1)) }

"$GIT" init --bare -b main -q "$BARE"
cd "$FIXTURE" || exit 1
"$GIT" init -b main -q
"$GIT" commit --allow-empty -m "init" -q
"$GIT" remote add origin "$BARE"

"$PYTHON3" -c "open('huge.bin','wb').write(b'x'*500)"
print -r -- "ok" > ok.txt
print -r -- "fine" > fine.txt

typeset -a out=()
out=("${(@f)$(
  GITTY_MAX_FILE_BYTES=100 GITTY_PARTIAL=1 "$GITTY_SCRIPT" "smoke partial" "$FIXTURE" 2>&1
)}")
typeset -i rc=$?
joined="${(j:\n:)out}"

(( rc == 0 )) && _pass "exit 0" || _fail "exit 0" "got rc=$rc"
print -r -- "$joined" | grep -q '🔴 - huge\.bin — held back' && _pass "holdback line" || _fail "holdback line" "missing"
print -r -- "$joined" | grep -q 'partial success' && _pass "partial dashboard" || _fail "partial dashboard" "missing"

typeset -a committed=("${(@f)$("$GIT" show --name-only --pretty=format: HEAD 2>/dev/null)}")
(( ${committed[(Ie)fine.txt]} && ${committed[(Ie)ok.txt]} )) \
  && _pass "fine+ok committed" || _fail "fine+ok committed" "got: ${committed[*]}"
print -r -- "${(j:\n:)committed}" | grep -q 'huge\.bin' \
  && _fail "huge.bin excluded" "was committed" || _pass "huge.bin excluded"

print -u2 "smoke: $PASS passed, $FAIL failed"
(( FAIL == 0 )) && { print -u2 "🟢 smoke OK"; exit 0 }
print -u2 "🔴 smoke FAIL"; exit 1
