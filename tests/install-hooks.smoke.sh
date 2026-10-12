#!/usr/bin/env zsh
# End-to-end: fresh repo -> `gitty install-hooks` -> verify canonical tree,
# idempotency, and --with selective install.
setopt errexit pipefail nounset
typeset -r REPO_ROOT="${0:A:h:h}"
typeset -r GIT="/usr/bin/git"
typeset -r GITTY="$REPO_ROOT/bin/gitty.sh"
typeset PASS=0 FAIL=0
_pass() { print -u2 "🟢 PASS $1"; PASS=$((PASS+1)); }
_fail() { print -u2 "🔴 FAIL $1 — $2"; FAIL=$((FAIL+1)); }

typeset FX=""
trap 'rm -rf "$FX" 2>/dev/null || true' EXIT INT TERM
FX=$(mktemp -d /tmp/gitty-install-hooks.XXXXXX)
"$GIT" init -q -b main "$FX"

zsh "$GITTY" install-hooks --repo "$FX" >/dev/null 2>&1

[[ -f "$FX/.hooks/pre-commit" ]] && _pass "pre-commit written" || _fail "pre-commit written" "missing"
[[ -f "$FX/.hooks/pre-push"   ]] && _pass "pre-push written"   || _fail "pre-push written"   "missing"
[[ -f "$FX/.hooks/post-checkout" ]] && _pass "post-checkout written" || _fail "post-checkout written" "missing"
[[ -f "$FX/.hooks/post-merge" ]] && _pass "post-merge written" || _fail "post-merge written" "missing"
for d in .hooks/pre-commit.d .hooks/pre-push.d .hooks/post-checkout.d .hooks/post-merge.d .hooks/local.d/cosmetic .hooks/local.d/gates .hooks/local.d/pre-push; do
  [[ -d "$FX/$d" ]] && _pass "dir $d" || _fail "dir $d" "missing"
done
got=$("$GIT" -C "$FX" config --get core.hooksPath)
[[ "$got" == ".hooks" ]] && _pass "core.hooksPath set" || _fail "core.hooksPath" "got=$got"
[[ -x "$FX/.hooks/lib/apply-file-flags.sh" ]] \
  && _pass "file-flags lib" || _fail "file-flags lib" "missing"
[[ -x "$FX/.hooks/pre-commit.d/05-file-flags-sync.sh" ]] \
  && _pass "file-flags always-on pre-commit sync" || _fail "file-flags pre-commit" "missing"
[[ -x "$FX/.hooks/post-checkout.d/10-file-flags.sh" ]] \
  && _pass "file-flags always-on post-checkout" || _fail "file-flags post-checkout" "missing"
[[ -x "$FX/.hooks/post-merge.d/10-file-flags.sh" ]] \
  && _pass "file-flags always-on post-merge" || _fail "file-flags post-merge" "missing"

# Idempotency: second run must not change the .hooks tree.
sha1=$(find "$FX/.hooks" -type f | sort | xargs sha256sum | sha256sum)
zsh "$GITTY" install-hooks --repo "$FX" >/dev/null 2>&1
sha2=$(find "$FX/.hooks" -type f | sort | xargs sha256sum | sha256sum)
[[ "$sha1" == "$sha2" ]] && _pass "idempotent second run" || _fail "idempotent" "sha drift"

# --with selective install: named scripts land beside always-on file-flags sync.
find "$FX/.hooks/pre-commit.d" -type f -delete 2>/dev/null || true
zsh "$GITTY" install-hooks --repo "$FX" --force --with em-dashes,health-check >/dev/null 2>&1
[[ -x "$FX/.hooks/pre-commit.d/05-file-flags-sync.sh" ]] \
  && _pass "file-flags sync restored with --force" || _fail "file-flags sync restore" "missing"
[[ -f "$FX/.hooks/pre-commit.d/20-em-dashes.sh" ]] \
  && _pass "--with em-dashes" || _fail "--with em-dashes" "missing $(ls "$FX/.hooks/pre-commit.d" 2>/dev/null)"
[[ -f "$FX/.hooks/pre-push.d/30-health-check.sh" ]] \
  && _pass "--with health-check" || _fail "--with health-check" "missing $(ls "$FX/.hooks/pre-push.d" 2>/dev/null)"
# clearmeta removed: must refuse
rc=0
zsh "$GITTY" install-hooks --repo "$FX" --with clearmeta >/dev/null 2>&1 || rc=$?
[[ "$rc" != "0" ]] && _pass "--with clearmeta refused" || _fail "--with clearmeta refused" "rc=$rc"

print -u2 "install-hooks smoke: $PASS passed, $FAIL failed"
(( FAIL == 0 )) && exit 0 || exit 1
