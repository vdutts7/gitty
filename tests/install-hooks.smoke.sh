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
for d in .hooks/pre-commit.d .hooks/pre-push.d .hooks/local.d/cosmetic .hooks/local.d/gates .hooks/local.d/pre-push; do
  [[ -d "$FX/$d" ]] && _pass "dir $d" || _fail "dir $d" "missing"
done
got=$("$GIT" -C "$FX" config --get core.hooksPath)
[[ "$got" == ".hooks" ]] && _pass "core.hooksPath set" || _fail "core.hooksPath" "got=$got"

# Idempotency: second run must not change the .hooks tree.
sha1=$(find "$FX/.hooks" -type f | sort | xargs sha256sum | sha256sum)
zsh "$GITTY" install-hooks --repo "$FX" >/dev/null 2>&1
sha2=$(find "$FX/.hooks" -type f | sort | xargs sha256sum | sha256sum)
[[ "$sha1" == "$sha2" ]] && _pass "idempotent second run" || _fail "idempotent" "sha drift"

# --with selective install: exactly the two named scripts land in pre-commit.d/.
find "$FX/.hooks/pre-commit.d" -type f -delete 2>/dev/null || true
zsh "$GITTY" install-hooks --repo "$FX" --with em-dashes,clearmeta >/dev/null 2>&1
n=$(ls "$FX/.hooks/pre-commit.d/" 2>/dev/null | wc -l | tr -d ' ')
[[ "$n" == "2" ]] && _pass "--with installs exactly 2" || _fail "--with count" "got=$n"

print -u2 "install-hooks smoke: $PASS passed, $FAIL failed"
(( FAIL == 0 )) && exit 0 || exit 1
