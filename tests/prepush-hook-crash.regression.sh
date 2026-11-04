#!/usr/bin/env zsh
# Regression: pre-push hook *script* crash drip.
# When a hook script in HEAD crashes (bash "path: line N:"), gitty holds that
# path back, restores the prior live copy, and pushes the rest.
setopt errexit pipefail nounset

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"

typeset -r REPO_ROOT="${0:A:h:h}"
typeset -r GITTY_SCRIPT="${GITTY_SCRIPT:-$REPO_ROOT/bin/gitty.sh}"
typeset -r GIT="/usr/bin/git"

[[ -x "$GITTY_SCRIPT" ]] || { print -u2 "🔴 missing $GITTY_SCRIPT"; exit 1 }

typeset -i PASS=0 FAIL=0
_pass() { print -u2 "🟢 PASS $1"; PASS=$((PASS + 1)) }
_fail() { print -u2 "🔴 FAIL $1 - $2"; FAIL=$((FAIL + 1)) }

# Mirror of gitty_parse_hook_script_offender (keep in lockstep with bin/gitty.sh).
_parse_hook_script_offender() {
  local output="$1" root="$2" raw rel
  raw=$(printf '%s\n' "$output" \
    | grep -oE '[^[:space:]"'"'"']+\.(sh|zsh|bash):[[:space:]]+line[[:space:]]+[0-9]+' \
    | head -1 \
    | sed -E 's/:[[:space:]]+line[[:space:]]+[0-9]+$//' ) || true
  if [[ -z "$raw" ]]; then
    raw=$(printf '%s\n' "$output" \
      | grep -oE '[^[:space:]"'"'"']+\.(sh|zsh|bash):[0-9]+:' \
      | head -1 \
      | sed -E 's/:[0-9]+:$//' ) || true
  fi
  [[ -z "$raw" ]] && return 1
  if [[ "$raw" == /* ]]; then
    case "$raw" in
      "$root"/*) rel="${raw#$root/}" ;;
      *) return 1 ;;
    esac
  else
    rel="${raw#./}"
  fi
  [[ -n "$rel" ]] || return 1
  print -r -- "$rel"
  return 0
}

# ---- R1-R4: parser unit surface ----
typeset -r FAKE_ROOT="/tmp/gitty-hook-crash-root"
got=$(_parse_hook_script_offender \
  $'/tmp/gitty-hook-crash-root/.hooks/scripts/health-check.sh: line 193: unexpected EOF while looking for matching quote\nerror: failed to push' \
  "$FAKE_ROOT" || echo NONE)
[[ "$got" == ".hooks/scripts/health-check.sh" ]] \
  && _pass "R1 abs bash line-N path" || _fail "R1" "got=$got"

got=$(_parse_hook_script_offender \
  $'.hooks/scripts/health-check.sh: line 10: syntax error' \
  "$FAKE_ROOT" || echo NONE)
[[ "$got" == ".hooks/scripts/health-check.sh" ]] \
  && _pass "R2 relative bash line-N path" || _fail "R2" "got=$got"

got=$(_parse_hook_script_offender \
  $'.hooks/scripts/health-check.sh:42: parse error near end\n' \
  "$FAKE_ROOT" || echo NONE)
[[ "$got" == ".hooks/scripts/health-check.sh" ]] \
  && _pass "R3 zsh path:N: form" || _fail "R3" "got=$got"

got=$(_parse_hook_script_offender \
  $'/outside/repo/evil.sh: line 1: boom\nremote: rejected' \
  "$FAKE_ROOT" || echo NONE)
[[ "$got" == "NONE" ]] \
  && _pass "R4 outside-repo path rejected" || _fail "R4" "got=$got"

# ---- R5: end-to-end drip ----
typeset FX="" BARE=""
trap 'rm -rf "$FX" "$BARE" 2>/dev/null || true' EXIT INT TERM
FX=$(mktemp -d /tmp/gitty-prepush-crash.XXXXXX)
BARE=$(mktemp -d /tmp/gitty-prepush-crash-bare.XXXXXX)

"$GIT" init -q -b main "$FX"
"$GIT" init -q --bare -b main "$BARE"
"$GIT" -C "$FX" remote add origin "$BARE"
"$GIT" -C "$FX" config core.hooksPath .hooks
"$GIT" -C "$FX" config user.email t@t
"$GIT" -C "$FX" config user.name t

mkdir -p "$FX/.hooks/pre-push.d" "$FX/.hooks/scripts"
cp "$REPO_ROOT/.hooks/pre-push" "$FX/.hooks/pre-push"
chmod +x "$FX/.hooks/pre-push"

# Good health-check (seed) — invoked by pre-push.d
cat > "$FX/.hooks/scripts/health-check.sh" <<'GOOD'
#!/usr/bin/env bash
exit 0
GOOD
chmod +x "$FX/.hooks/scripts/health-check.sh"
cat > "$FX/.hooks/pre-push.d/10-health-check.sh" <<'RUN'
#!/usr/bin/env bash
ROOT="$(git rev-parse --show-toplevel)"
exec "$ROOT/.hooks/scripts/health-check.sh"
RUN
chmod +x "$FX/.hooks/pre-push.d/10-health-check.sh"

print -r -- "seed" > "$FX/seed.txt"
"$GIT" -C "$FX" add -A
"$GIT" -C "$FX" commit -qm seed
"$GIT" -C "$FX" push -q origin main

# Break health-check + add a good sibling in one commit intent via gitty
# Unmatched quote (syntax crash); generic name — no operator path tokens.
cat > "$FX/.hooks/scripts/health-check.sh" <<'BAD'
#!/usr/bin/env bash
PLACEHOLDER="${PLACEHOLDER:-"
exit 0
BAD
chmod +x "$FX/.hooks/scripts/health-check.sh"
print -r -- "ok" > "$FX/ok.txt"

typeset -a out=()
typeset -i rc=0
{
  setopt localoptions noerrexit
  out=("${(@f)$(
    GITTY_PARTIAL=1 GITTY_PLUNGER=0 "$GITTY_SCRIPT" "smoke prepush crash drip" "$FX" 2>&1
  )}")
  rc=$?
}
joined="${(j:\n:)out}"

(( rc == 0 )) && _pass "R5 exit 0" || _fail "R5 exit 0" "rc=$rc"
print -r -- "$joined" | grep -q 'pre-push hook script failure' \
  && _pass "R5 holdback reason" || _fail "R5 holdback reason" "missing"
print -r -- "$joined" | grep -qE 'health-check\.sh.*held back|held back.*health-check\.sh' \
  && _pass "R5 held path named" || _fail "R5 held path named" "missing in: $joined"
print -r -- "$joined" | grep -q 'partial success\|Partial commit/push' \
  && _pass "R5 partial dashboard" || _fail "R5 partial dashboard" "missing"

# Remote got ok.txt; broken health-check not on remote tip
typeset -a remote_files=("${(@f)$("$GIT" --git-dir="$BARE" ls-tree -r --name-only HEAD 2>/dev/null)}")
(( ${remote_files[(Ie)ok.txt]} )) && _pass "R5 ok.txt on remote" || _fail "R5 ok.txt on remote" "got: ${remote_files[*]}"
if print -r -- "${(j:\n:)remote_files}" | grep -q 'health-check\.sh'; then
  # Prior good copy may still be on remote from seed — content must still exit 0
  tip_blob=$("$GIT" --git-dir="$BARE" show "HEAD:.hooks/scripts/health-check.sh" 2>/dev/null || true)
  print -r -- "$tip_blob" | grep -q 'PLACEHOLDER="\${PLACEHOLDER:-"' \
    && _fail "R5 remote not broken" "broken script reached remote" \
    || _pass "R5 remote health-check still good"
else
  _pass "R5 remote has no health-check path (dropped)"
fi

# Broken bytes preserved under .git/gitty-holdback
[[ -f "$FX/.git/gitty-holdback/.hooks/scripts/health-check.sh" ]] \
  && _pass "R5 broken copy preserved" || _fail "R5 broken copy preserved" "missing holdback file"

# Live worktree hook must be runnable again
bash -n "$FX/.hooks/scripts/health-check.sh" \
  && _pass "R5 live hook syntax ok" || _fail "R5 live hook syntax ok" "still broken"

print -u2 "prepush-hook-crash regression: $PASS passed, $FAIL failed"
(( FAIL == 0 )) && { print -u2 "🟢 regression OK"; exit 0 }
print -u2 "🔴 regression FAIL"; exit 1
