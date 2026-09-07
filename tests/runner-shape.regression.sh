#!/usr/bin/env zsh
setopt errexit pipefail nounset
typeset PASS=0 FAIL=0
_pass() { print -u2 "🟢 PASS $1"; PASS=$((PASS+1)); }
_fail() { print -u2 "🔴 FAIL $1 — $2"; FAIL=$((FAIL+1)); }
_extract() { awk '/^exit[[:space:]]*0[[:space:]]*$/{print; exit} {print}' <<<"$1"; }
_has_all() { local body="$1"; shift; for t in "$@"; do printf '%s' "$body" | grep -qF -- "$t" || return 1; done; }
T1=$'#!/usr/bin/env bash\nset -e\nfor s in "$ROOT"/.hooks/pre-commit.d/*; do :; done\nfor s in "$ROOT"/.hooks/local.d/cosmetic/*; do :; done\nfor s in "$ROOT"/.hooks/local.d/gates/*; do :; done\nexit 0'
_has_all "$(_extract "$T1")" ".hooks/pre-commit.d/" ".hooks/local.d/cosmetic/" ".hooks/local.d/gates/" && _pass "T1 literal-exit-0" || _fail "T1" "missing"
T2=$'#!/usr/bin/env bash\nrc=0\nfor s in "$ROOT"/.hooks/pre-commit.d/*; do :; done\nfor s in "$ROOT"/.hooks/local.d/gates/*; do :; done\nexit $rc'
_has_all "$(_extract "$T2")" ".hooks/pre-commit.d/" ".hooks/local.d/gates/" && _pass "T2 variable-exit" || _fail "T2" "missing"
T3=$'#!/usr/bin/env bash\nfor s in "$ROOT"/.hooks/pre-commit.d/*; do :; done\nfor s in "$ROOT"/.hooks/local.d/gates/*; do :; done\n  exit 0'
_has_all "$(_extract "$T3")" ".hooks/pre-commit.d/" ".hooks/local.d/gates/" && _pass "T3 indented exit 0" || _fail "T3" "missing"
T4=$'#!/usr/bin/env bash\nfor s in "$ROOT"/.hooks/pre-commit.d/*; do :; done\nfor s in "$ROOT"/.hooks/local.d/gates/*; do :; done'
_has_all "$(_extract "$T4")" ".hooks/pre-commit.d/" ".hooks/local.d/gates/" && _pass "T4 missing exit 0" || _fail "T4" "missing"
print -u2 "runner-shape regression: $PASS passed, $FAIL failed"
(( FAIL == 0 )) && exit 0 || exit 1
