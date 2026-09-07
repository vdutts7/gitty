#!/usr/bin/env zsh
setopt errexit pipefail nounset
typeset -r REPO_ROOT="${0:A:h:h}"
typeset -r GIT="/usr/bin/git"
typeset -r GITTY="$REPO_ROOT/bin/gitty.sh"
typeset PASS=0 FAIL=0
_pass() { print -u2 "🟢 PASS $1"; PASS=$((PASS+1)); }
_fail() { print -u2 "🔴 FAIL $1 — $2"; FAIL=$((FAIL+1)); }
typeset FX="" BARE=""
trap 'rm -rf "$FX" "$BARE" 2>/dev/null || true' EXIT INT TERM
FX=$(mktemp -d /tmp/gitty-drip.XXXXXX)
BARE=$(mktemp -d /tmp/gitty-drip-bare.XXXXXX)
"$GIT" init -q -b main "$FX"
"$GIT" init -q --bare -b main "$BARE"
"$GIT" -C "$FX" remote add origin "$BARE"
"$GIT" -C "$FX" config core.hooksPath .hooks
# seed-initial-commit: real repos have history; git restore --staged needs HEAD
printf "seed\n" > "$FX/.seed"; "$GIT" -C "$FX" add .seed
"$GIT" -C "$FX" -c user.email=t@t -c user.name=t commit -qm seed --no-verify
mkdir -p "$FX/.hooks"
cat > "$FX/.hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
staged=$(git diff --cached --name-only)
if grep -q '^tools/bad.sh$' <<<"$staged"; then
  printf 'clearmeta noise: /home/nobody/x.yaml stripped\n' >&2
  printf 'clearmeta noise: /home/nobody/y.json stripped\n' >&2
  printf 'context-pollution: tools/bad.sh:12 contains bare token (exit 93)\n' >&2
  exit 93
fi
exit 0
HOOK
chmod +x "$FX/.hooks/pre-commit"
mkdir -p "$FX/tools" "$FX/docs"
printf 'a\n' > "$FX/tools/bad.sh"; printf 'b\n' > "$FX/tools/good.sh"; printf 'c\n' > "$FX/docs/notes.md"
"$GIT" -C "$FX" add -A
out=$(cd "$FX" && GITTY_PARTIAL=1 zsh "$GITTY" "targeted-retry-smoke" "$FX" 2>&1) || true
grep -q 'parsed offender from stderr: tools/bad.sh' <<<"$out" && _pass "parser identified offender" || _fail "parser identified offender" "no parsed-offender line"
grep -q '(1 attempt)' <<<"$out" && _pass "1-attempt fast-path" || _fail "1-attempt" "no (1 attempt)"
if grep -q '\[[0-9]\+/[0-9]\+\] trying without' <<<"$out"; then _fail "no brute-force lines" "scan present"; else _pass "no brute-force lines"; fi
print -u2 "drip-targeted-retry smoke: $PASS passed, $FAIL failed"
(( FAIL == 0 )) && exit 0 || exit 1
