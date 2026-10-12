#!/usr/bin/env bash
# Unit tests for bin/init-hooks.sh argument parsing and guardrails.
set -uo pipefail
declare -i PASS=0 FAIL=0
_pass() { echo "🟢 PASS $1"; PASS=$((PASS+1)); }
_fail() { echo "🔴 FAIL $1 — $2"; FAIL=$((FAIL+1)); }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SCRIPT="$REPO_ROOT/bin/init-hooks.sh"

out=$("$SCRIPT" --help 2>&1)
[[ "$out" == *"install-hooks"* ]] && _pass "--help prints usage" || _fail "--help" "no usage"

"$SCRIPT" --unknown-flag >/dev/null 2>&1; rc=$?
[[ "$rc" == "2" ]] && _pass "unknown flag exits 2" || _fail "unknown flag rc" "got=$rc"

"$SCRIPT" --repo /tmp/nonexistent-repo-$$ >/dev/null 2>&1; rc=$?
[[ "$rc" == "1" ]] && _pass "non-repo exits 1" || _fail "non-repo rc" "got=$rc"

# need a real repo for --with parsing after repo check
FX=$(mktemp -d /tmp/gitty-ih-unit.XXXXXX)
git init -q -b main "$FX" >/dev/null
"$SCRIPT" --repo "$FX" --with clearmeta >/dev/null 2>&1; rc=$?
[[ "$rc" != "0" ]] && _pass "clearmeta --with refused" || _fail "clearmeta --with refused" "rc=$rc"
rm -rf "$FX" 2>/dev/null || true

echo "install-hooks unit: $PASS passed, $FAIL failed"
(( FAIL == 0 )) && exit 0 || exit 1
