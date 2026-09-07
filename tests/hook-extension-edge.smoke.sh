#!/usr/bin/env zsh
# Edge cases for the canonical pre-commit runner: a gate killed by SIGKILL and a
# gate with a broken shebang must both abort the commit (set -e in the runner).
# EPIPE behavior is covered by hook-extension-prepush.smoke.sh (stdin captured
# once, replayed per check).
setopt pipefail nounset
typeset -r REPO_ROOT="${0:A:h:h}"
typeset -r GIT="/usr/bin/git"
typeset PASS=0 FAIL=0
_pass() { print -u2 "🟢 PASS $1"; PASS=$((PASS+1)); }
_fail() { print -u2 "🔴 FAIL $1 — $2"; FAIL=$((FAIL+1)); }

typeset FX=""
trap 'rm -rf "$FX" 2>/dev/null || true' EXIT INT TERM
FX=$(mktemp -d /tmp/gitty-edge.XXXXXX)
"$GIT" init -q -b main "$FX"
"$GIT" -C "$FX" config core.hooksPath .hooks
mkdir -p "$FX/.hooks/pre-commit.d" "$FX/.hooks/local.d/gates" "$FX/.hooks/local.d/cosmetic"
cp "$REPO_ROOT/.hooks/pre-commit" "$FX/.hooks/pre-commit"
chmod +x "$FX/.hooks/pre-commit"

# Case A: gate killed by SIGKILL -> commit MUST fail.
cat > "$FX/.hooks/local.d/gates/50-suicide.sh" <<'HOOK'
#!/usr/bin/env bash
kill -KILL $$
HOOK
chmod +x "$FX/.hooks/local.d/gates/50-suicide.sh"
printf 'a\n' > "$FX/a.txt"; "$GIT" -C "$FX" add a.txt
if "$GIT" -C "$FX" -c user.email=t@t -c user.name=t commit -qm A 2>/dev/null; then
  _fail "SIGKILL gate aborts commit" "commit succeeded"
else
  _pass "SIGKILL gate aborts commit"
fi
rm "$FX/.hooks/local.d/gates/50-suicide.sh"

# Case B: broken shebang -> exec fails -> commit MUST fail. Stage fresh content
# so the commit is non-empty and the hook actually runs.
cat > "$FX/.hooks/local.d/gates/60-broken.sh" <<'HOOK'
#!/nonexistent/interp
echo hello
HOOK
chmod +x "$FX/.hooks/local.d/gates/60-broken.sh"
printf 'b\n' > "$FX/b.txt"; "$GIT" -C "$FX" add b.txt
if "$GIT" -C "$FX" -c user.email=t@t -c user.name=t commit -qm B 2>/dev/null; then
  _fail "broken shebang aborts commit" "commit succeeded"
else
  _pass "broken shebang aborts commit"
fi
rm "$FX/.hooks/local.d/gates/60-broken.sh"

# Case C: EPIPE — pre-push runner captures stdin once and replays; covered end
# to end by hook-extension-prepush.smoke.sh.
_pass "EPIPE covered by pre-push smoke (see hook-extension-prepush.smoke.sh)"

print -u2 "hook-extension-edge smoke: $PASS passed, $FAIL failed"
(( FAIL == 0 )) && exit 0 || exit 1
