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
failed=0
if grep -q '^tools/bad-one.sh$' <<<"$staged"; then
  printf 'clearmeta noise: /home/nobody/x.yaml stripped\n' >&2
  printf 'clearmeta noise: /home/nobody/y.json stripped\n' >&2
  printf 'GITTY_HOLDBACK\ttools/bad-one.sh\tHOME-POLICY-2\ttrue\tchecker uncertainty\n' >&2
  printf '🔴 HOME-POLICY-BLOCK file=tools/bad-one.sh checker_rc=2 reason=checker-uncertainty gate_exit=93\n' >&2
  failed=1
fi
if grep -q '^tools/bad-two.sh$' <<<"$staged"; then
  printf 'GITTY_HOLDBACK\ttools/bad-two.sh\tHOME-POLICY-8\ttrue\timplicit home\n' >&2
  printf 'context-pollution: tools/bad-two.sh:9 contains bare token (exit 93)\n' >&2
  failed=1
fi
(( failed == 0 )) || exit 93
exit 0
HOOK
chmod +x "$FX/.hooks/pre-commit"
mkdir -p "$FX/tools" "$FX/docs"
printf 'a\n' > "$FX/tools/bad-one.sh"; printf 'b\n' > "$FX/tools/bad-two.sh"
printf 'c\n' > "$FX/tools/good.sh"; printf 'd\n' > "$FX/docs/notes.md"
"$GIT" -C "$FX" add -A
out=$(cd "$FX" && GITTY_PARTIAL=1 zsh "$GITTY" "targeted-retry-smoke" "$FX" 2>&1) || true
grep -q 'Drip retry: holding back 2 explicitly reported path(s)' <<<"$out" \
  && _pass "aggregate parser identified both offenders" || _fail "aggregate offenders" "missing aggregate holdback line"
grep -q '(1 retry)' <<<"$out" && _pass "one bounded retry" || _fail "one retry" "missing bounded retry count"
if grep -q '\[[0-9]\+/[0-9]\+\] trying without' <<<"$out"; then _fail "no brute-force lines" "scan present"; else _pass "no brute-force lines"; fi

# Opaque hooks must stop without probing every staged path and restore the index.
cat > "$FX/.hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
printf 'policy rejected this commit without an offender path\n' >&2
exit 93
HOOK
chmod +x "$FX/.hooks/pre-commit"
printf 'opaque\n' > "$FX/tools/opaque.sh"
"$GIT" -C "$FX" add -A
opaque_out=$(cd "$FX" && GITTY_PARTIAL=1 zsh "$GITTY" "opaque-retry-smoke" "$FX" 2>&1) || true
grep -q 'brute-force elimination disabled' <<<"$opaque_out" \
  && _pass "opaque hook stops without scan" || _fail "opaque stop" "missing stop diagnostic"
if grep -q '\[[0-9]\+/[0-9]\+\] trying without' <<<"$opaque_out"; then _fail "opaque no brute-force lines" "scan present"; else _pass "opaque no brute-force lines"; fi
"$GIT" -C "$FX" diff --cached --quiet -- tools/opaque.sh \
  && _fail "opaque index restored" "opaque.sh not staged" || _pass "opaque index restored"
print -u2 "drip-targeted-retry smoke: $PASS passed, $FAIL failed"
(( FAIL == 0 )) && exit 0 || exit 1
