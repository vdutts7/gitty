#!/usr/bin/env zsh
# hook-extension smoke: pre-commit + pre-push runners must dispatch three/two
# lanes in order and honor advisory vs blocking semantics. Regression guard for
# v0.6.18 extension-point contract.
setopt errexit pipefail nounset

typeset -r REPO_ROOT="${0:A:h:h}"
typeset -r GIT="/usr/bin/git"
typeset PASS=0 FAIL=0
_pass() { print -u2 "🟢 PASS $1"; PASS=$((PASS + 1)) }
_fail() { print -u2 "🔴 FAIL $1 - $2"; FAIL=$((FAIL + 1)) }

typeset FX=""
trap 'rm -rf "$FX" 2>/dev/null || true' EXIT INT TERM
FX="$(mktemp -d /tmp/gitty-hook-ext.XXXXXX)"

# Fixture repo with configured hooksPath
"$GIT" init -q -b main "$FX"
"$GIT" -C "$FX" config core.hooksPath .hooks
mkdir -p "$FX/.hooks/pre-commit.d" "$FX/.hooks/local.d/cosmetic" \
         "$FX/.hooks/local.d/gates"   "$FX/.hooks/local.d/pre-push" \
         "$FX/.hooks/pre-push.d"
cp "$REPO_ROOT/.hooks/pre-commit" "$FX/.hooks/pre-commit"
cp "$REPO_ROOT/.hooks/pre-push"   "$FX/.hooks/pre-push"
chmod +x "$FX/.hooks/pre-commit" "$FX/.hooks/pre-push"

# --- test 1: empty local.d/ subdirs are no-op (backward compat) --------------
touch "$FX/a.txt"
"$GIT" -C "$FX" add a.txt
"$GIT" -C "$FX" -c user.email=t@t -c user.name=t commit -qm empty-hooks \
  && _pass "empty local.d/ subdirs are no-op" \
  || _fail "empty local.d/ subdirs" "commit failed on empty local.d/"

# --- test 2: local.d/gates/ blocking hook aborts commit ----------------------
cat > "$FX/.hooks/local.d/gates/50-block.sh" <<'HOOK'
#!/usr/bin/env bash
exit 42
HOOK
chmod +x "$FX/.hooks/local.d/gates/50-block.sh"
touch "$FX/b.txt"; "$GIT" -C "$FX" add b.txt
if "$GIT" -C "$FX" -c user.email=t@t -c user.name=t commit -qm 'should-fail' 2>/dev/null; then
  _fail "local.d/gates blocks commit" "commit succeeded despite exit 42"
else
  _pass "local.d/gates blocks commit"
fi
rm "$FX/.hooks/local.d/gates/50-block.sh"
"$GIT" -C "$FX" restore --staged b.txt 2>/dev/null || true

# --- test 3: local.d/cosmetic/ failing hook does NOT block (advisory) --------
cat > "$FX/.hooks/local.d/cosmetic/40-advisory.sh" <<'HOOK'
#!/usr/bin/env bash
exit 99
HOOK
chmod +x "$FX/.hooks/local.d/cosmetic/40-advisory.sh"
"$GIT" -C "$FX" add b.txt
"$GIT" -C "$FX" -c user.email=t@t -c user.name=t commit -qm advisory-should-pass \
  && _pass "local.d/cosmetic advisory does not block" \
  || _fail "local.d/cosmetic advisory" "commit blocked despite advisory wrapping"
rm "$FX/.hooks/local.d/cosmetic/40-advisory.sh"

# --- test 4: execution order is pre-commit.d/ -> cosmetic/ -> gates/ ---------
: > "$FX/order.log"
for lane in pre-commit.d local.d/cosmetic local.d/gates; do
  name="${lane//\//-}"
  cat > "$FX/.hooks/$lane/10-log.sh" <<HOOK
#!/usr/bin/env bash
echo "$name" >> "$FX/order.log"
HOOK
  chmod +x "$FX/.hooks/$lane/10-log.sh"
done
touch "$FX/c.txt"; "$GIT" -C "$FX" add c.txt
"$GIT" -C "$FX" -c user.email=t@t -c user.name=t commit -qm order-test
expected=$'pre-commit.d\nlocal.d-cosmetic\nlocal.d-gates'
actual="$(cat "$FX/order.log")"
if [[ "$actual" == "$expected" ]]; then
  _pass "execution order: pre-commit.d -> cosmetic -> gates"
else
  _fail "execution order" "expected [$expected] got [$actual]"
fi

print -u2 "smoke: $PASS passed, $FAIL failed"
(( FAIL == 0 )) && { print -u2 "🟢 hook-extension smoke OK"; exit 0 }
print -u2 "🔴 hook-extension smoke FAIL"; exit 1
