#!/usr/bin/env zsh
# Holdback-reason smoke: a pre-commit hook rejection must be held back with a
# SPECIFIC, canonical reason (catalog code or offender stderr), never the mute
# constant "pre-commit hook rejection".
setopt errexit pipefail nounset

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"

typeset -r REPO_ROOT="${0:A:h:h}"
typeset -r GITTY_SCRIPT="${GITTY_SCRIPT:-$REPO_ROOT/bin/gitty.sh}"
typeset -r GIT="/usr/bin/git"

[[ -x "$GITTY_SCRIPT" ]] || { print -u2 "🔴 missing $GITTY_SCRIPT"; exit 1 }

typeset -i PASS=0 FAIL=0
_pass() { print -u2 "🟢 PASS $1"; PASS=$((PASS + 1)) }
_fail() { print -u2 "🔴 FAIL $1 - $2"; FAIL=$((FAIL + 1)) }

typeset FX1="" BARE1="" FX2="" BARE2=""
trap 'rm -rf "$FX1" "$BARE1" "$FX2" "$BARE2" 2>/dev/null || true' EXIT INT TERM

# Build a fixture repo whose pre-commit hook rejects any *.md containing HOLDME,
# emitting the exact check-tilde-style stderr the catalog matches.
_make_fixture() {
  local fx="$1" bare="$2" with_catalog="$3"
  "$GIT" init --bare -b main -q "$bare"
  "$GIT" init -b main -q "$fx"
  "$GIT" -C "$fx" commit --allow-empty -m init -q
  "$GIT" -C "$fx" remote add origin "$bare"
  mkdir -p "$fx/.githooks"
  cat > "$fx/.githooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
staged=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.md$' || true)
for f in $staged; do
  if git show ":$f" 2>/dev/null | grep -q 'HOLDME'; then
    line=$(git show ":$f" | grep -n 'HOLDME' | head -1 | cut -d: -f1)
    printf '\xf0\x9f\x94\xb4 context-pollution: %s:%s contains bare ~/ (exit 93)\n' "$f" "$line" >&2
    exit 93
  fi
done
exit 0
HOOK
  chmod +x "$fx/.githooks/pre-commit"
  "$GIT" -C "$fx" config core.hooksPath .githooks
  if [[ "$with_catalog" == "1" ]]; then
    mkdir -p "$fx/.gitty"
    cat > "$fx/.gitty/holdback-reasons.json" <<'CAT'
{ "rules": [ { "code": "HOLD-TILDE-93", "match": "context-pollution: (\\S+):(\\d+) contains bare ~/", "reason": "bare tilde-slash at $1:$2", "fix": "use \$HOME" } ] }
CAT
  fi
  print -r -- "fine" > "$fx/clean.txt"
  print -r -- "line with HOLDME token" > "$fx/bad.md"
}

# --- case 1: catalog present -> canonical [HOLD-TILDE-93] code ---------------
FX1="$(mktemp -d /tmp/gitty-hb1.XXXXXX)"; BARE1="$(mktemp -d /tmp/gitty-hb1b.XXXXXX)"
_make_fixture "$FX1" "$BARE1" 1
typeset -a out1
out1=("${(@f)$(GITTY_PARTIAL=1 "$GITTY_SCRIPT" "smoke holdback" "$FX1" 2>&1)}")
typeset -i rc1=$?
typeset joined1="${(j:\n:)out1}"

(( rc1 == 0 )) && _pass "case1 exit 0" || _fail "case1 exit 0" "rc=$rc1"
print -r -- "$joined1" | grep -q '\[HOLD-TILDE-93\]' \
  && _pass "case1 canonical code" || _fail "case1 canonical code" "no [HOLD-TILDE-93] in output"
print -r -- "$joined1" | grep -qE 'held back \(pre-commit hook rejection\)$' \
  && _fail "case1 no mute constant" "mute constant still emitted" || _pass "case1 no mute constant"
"$GIT" -C "$FX1" show --name-only --pretty=format: HEAD | grep -q 'clean.txt' \
  && _pass "case1 clean.txt committed" || _fail "case1 clean.txt committed" "missing"
"$GIT" -C "$FX1" show --name-only --pretty=format: HEAD | grep -q 'bad.md' \
  && _fail "case1 bad.md excluded" "was committed" || _pass "case1 bad.md excluded"

# --- case 2: no catalog -> fallback = specific offender stderr, not mute ------
FX2="$(mktemp -d /tmp/gitty-hb2.XXXXXX)"; BARE2="$(mktemp -d /tmp/gitty-hb2b.XXXXXX)"
_make_fixture "$FX2" "$BARE2" 0
typeset -a out2
out2=("${(@f)$(GITTY_HOLDBACK_CATALOG=/nonexistent GITTY_PARTIAL=1 "$GITTY_SCRIPT" "smoke holdback" "$FX2" 2>&1)}")
typeset joined2="${(j:\n:)out2}"
print -r -- "$joined2" | grep -q 'context-pollution' \
  && _pass "case2 fallback keeps offender stderr" || _fail "case2 fallback keeps offender stderr" "lost the specific line"
print -r -- "$joined2" | grep -qE 'held back \(pre-commit hook rejection\)$' \
  && _fail "case2 no mute constant" "mute constant still emitted" || _pass "case2 no mute constant"

print -u2 "smoke: $PASS passed, $FAIL failed"
(( FAIL == 0 )) && { print -u2 "🟢 smoke OK"; exit 0 }
print -u2 "🔴 smoke FAIL"; exit 1
