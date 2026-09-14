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
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gitty-pack.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
if ! npm pack --dry-run --json > "$TMP/dry-run.json" 2> "$TMP/dry-run.err"; then
  _fail "npm pack --dry-run" "$(cat "$TMP/dry-run.err")"
  echo "npm-tarball smoke: $PASS passed, $FAIL failed"
  exit 1
fi

_has() { jq -e --arg path "$1" '.[0].files | any(.path == $path)' "$TMP/dry-run.json" >/dev/null; }

_has 'bin/init-hooks.sh'                && _pass "ships bin/init-hooks.sh"          || _fail "bin/init-hooks.sh" "missing"
_has 'bin/gitty-dispatch.sh'            && _pass "ships bin/gitty-dispatch.sh"      || _fail "bin/gitty-dispatch.sh" "missing"
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
  if jq -r '.[0].files[].path' "$TMP/dry-run.json" | grep -qE "$banned"; then
    _fail "must NOT ship $banned" "leaks into tarball"
  else
    _pass "excludes $banned"
  fi
done

if npm pack --json --pack-destination "$TMP" > "$TMP/pack.json" 2> "$TMP/pack.err"; then
  TARBALL="$TMP/$(jq -er '.[0].filename' "$TMP/pack.json")"
  if [[ -f "$TARBALL" ]]; then
    _pass "creates actual tarball"
    mkdir -p "$TMP/extracted"
    tar -xzf "$TARBALL" -C "$TMP/extracted"
    if [[ -x "$TMP/extracted/package/bin/gitty-dispatch.sh" ]]; then
      _pass "packed dispatcher executable"
    else
      _fail "packed dispatcher executable" "mode is not executable"
    fi
    if zsh "$TMP/extracted/package/bin/gitty-dispatch.sh" --help >/dev/null; then
      _pass "packed dispatcher runs"
    else
      _fail "packed dispatcher runs" "help invocation failed"
    fi
  else
    _fail "creates actual tarball" "reported tarball missing"
  fi
else
  _fail "npm pack" "$(cat "$TMP/pack.err")"
fi

echo "npm-tarball smoke: $PASS passed, $FAIL failed"
(( FAIL == 0 )) && exit 0 || exit 1
