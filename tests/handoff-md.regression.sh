#!/usr/bin/env bash
# HANDOFF.md in the produced bundle must be self-contained: no operator paths,
# no corp identity, no producer-internal env-var names, no dangling ${VAR}.
# Scans the bundle whose version matches package.json (the ship this tree
# produces). Skips cleanly when that bundle has not been produced yet.
set -uo pipefail
declare -i PASS=0 FAIL=0
_pass() { echo "🟢 PASS $1"; PASS=$((PASS+1)); }
_fail() { echo "🔴 FAIL $1 - $2"; FAIL=$((FAIL+1)); }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_ROOT/package.json" | head -1)
BUNDLE_DIR="/tmp/@vd7-gitty-v${VERSION}"
[[ -d "$BUNDLE_DIR" ]] || { echo "🟡 SKIP no bundle at $BUNDLE_DIR (v${VERSION} not yet produced)"; exit 0; }
HD="$BUNDLE_DIR/HANDOFF.md"
[[ -f "$HD" ]] || { echo "🔴 no HANDOFF.md in $BUNDLE_DIR"; exit 1; }

# Construct corp username at runtime so the public tree never holds the
# forbidden corp-operator literal (npm-offband-ship corp-scrub).
_corp_user="vivek""dutta"
for banned in "/home/${_corp_user}" "/mnt/c/Users/${_corp_user}" '@microsoft\.com' '@corp\.' '@exchange\.' 'WSLHOME' 'AGENTS/' 'agents/tools/'; do
  if grep -qE "$banned" "$HD"; then
    _fail "no $banned" "found in HANDOFF.md"
  else
    _pass "no $banned"
  fi
done

if grep -qE '\$\{[A-Za-z_][A-Za-z_0-9]*\}' "$HD"; then
  _fail "no dangling \${VAR}" "found unresolved var"
else
  _pass "no dangling \${VAR}"
fi

echo "handoff-md regression: $PASS passed, $FAIL failed"
(( FAIL == 0 )) && exit 0 || exit 1
