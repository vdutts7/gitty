#!/usr/bin/env bash
# npm tarball composition: `npm pack --dry-run` must ship the consumer plane
# (bin/gitty.sh, bin/init-hooks.sh, bin/hooks-lib/*) and must NOT ship the
# maintainer plane (.hooks/scripts/*, identity/Cloudinary/README-badge scripts),
# tests, or docs. Identity-boundary per npm-portability doctrine.
set -uo pipefail
declare -i PASS=0 FAIL=0
_pass() { echo "🟢 PASS $1"; PASS=$((PASS+1)); }
_fail() { echo "🔴 FAIL $1 — $2"; FAIL=$((FAIL+1)); }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$REPO_ROOT"
out=$(npm pack --dry-run --json 2>&1)

_has() { grep -q -- "$1" <<<"$out"; }

_has 'bin/init-hooks.sh'                && _pass "ships bin/init-hooks.sh"          || _fail "bin/init-hooks.sh" "missing"
_has 'bin/hooks-lib/clearmeta.sh'       && _pass "ships bin/hooks-lib/clearmeta.sh" || _fail "clearmeta.sh" "missing"
_has 'bin/hooks-lib/check-em-dashes.sh' && _pass "ships check-em-dashes.sh"         || _fail "check-em-dashes.sh" "missing"
_has 'bin/hooks-lib/README.md'          && _pass "ships hooks-lib README"           || _fail "hooks-lib README" "missing"

for banned in \
  '\.hooks/scripts/' \
  'enforce-git-identity' \
  'check-collaborator' \
  'upload-cloudinary' \
  'set-remote' \
  'gen-social' \
  'verify-commit-authors' \
  'check-readme-images' \
  'tests/' \
  'docs/'; do
  if grep -qE "$banned" <<<"$out"; then
    _fail "must NOT ship $banned" "leaks into tarball"
  else
    _pass "excludes $banned"
  fi
done

echo "npm-tarball smoke: $PASS passed, $FAIL failed"
(( FAIL == 0 )) && exit 0 || exit 1
