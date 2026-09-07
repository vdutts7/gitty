#!/usr/bin/env zsh
setopt errexit pipefail nounset
typeset -r REPO_ROOT="${0:A:h:h}"
typeset -r GIT="/usr/bin/git"
typeset PASS=0 FAIL=0
_pass() { print -u2 "🟢 PASS $1"; PASS=$((PASS+1)); }
_fail() { print -u2 "🔴 FAIL $1 — $2"; FAIL=$((FAIL+1)); }
typeset FX="" BARE=""
trap 'rm -rf "$FX" "$BARE" 2>/dev/null || true' EXIT INT TERM
FX=$(mktemp -d /tmp/gitty-prepush.XXXXXX)
BARE=$(mktemp -d /tmp/gitty-prepush-bare.XXXXXX)
"$GIT" init -q -b main "$FX"
"$GIT" init -q --bare -b main "$BARE"
"$GIT" -C "$FX" config core.hooksPath .hooks
mkdir -p "$FX/.hooks/pre-push.d" "$FX/.hooks/local.d/pre-push"
cp "$REPO_ROOT/.hooks/pre-push" "$FX/.hooks/pre-push"
chmod +x "$FX/.hooks/pre-push"
"$GIT" -C "$FX" remote add origin "$BARE"
touch "$FX/a.txt"; "$GIT" -C "$FX" add a.txt
"$GIT" -C "$FX" -c user.email=t@t -c user.name=t commit -qm init
"$GIT" -C "$FX" push -q origin main 2>/dev/null && _pass "empty local.d/pre-push no-op" || _fail "empty local.d/pre-push" "push blocked"
cat > "$FX/.hooks/local.d/pre-push/50-block.sh" <<'HOOK'
#!/usr/bin/env bash
exit 42
HOOK
chmod +x "$FX/.hooks/local.d/pre-push/50-block.sh"
touch "$FX/b.txt"; "$GIT" -C "$FX" add b.txt
"$GIT" -C "$FX" -c user.email=t@t -c user.name=t commit -qm second
if "$GIT" -C "$FX" push -q origin main 2>/dev/null; then _fail "local.d/pre-push blocks push" "push succeeded"; else _pass "local.d/pre-push blocks push"; fi
print -u2 "hook-extension-prepush smoke: $PASS passed, $FAIL failed"
(( FAIL == 0 )) && exit 0 || exit 1
