#!/usr/bin/env zsh
# file-attrs smoke: 1:1 uchg <-> .gitty/file-attrs.json via real git hooks.
# Covers install-hooks wiring, pre-commit sync add/drop, post-checkout apply,
# and a second-clone restore (the new-machine path).
setopt errexit pipefail nounset
typeset -r REPO_ROOT="${0:A:h:h}"
typeset -r GIT="/usr/bin/git"
typeset -r GITTY="$REPO_ROOT/bin/gitty.sh"
typeset PASS=0 FAIL=0
_pass() { print -u2 "🟢 PASS $1"; PASS=$((PASS+1)); }
_fail() { print -u2 "🔴 FAIL $1 — $2"; FAIL=$((FAIL+1)); }

[[ "$(uname -s)" == "Darwin" ]] || {
  print -u2 "🟡 SKIP file-attrs smoke (non-Darwin)"
  exit 0
}

typeset FX="" CLONE=""
trap '[[ -n "$FX" ]] && { chflags -R nouchg "$FX" 2>/dev/null || true; rm -rf "$FX" 2>/dev/null || true; }
      [[ -n "$CLONE" ]] && { chflags -R nouchg "$CLONE" 2>/dev/null || true; rm -rf "$CLONE" 2>/dev/null || true; }' EXIT INT TERM

FX=$(mktemp -d /tmp/gitty-file-attrs.XXXXXX)
"$GIT" init -q -b main "$FX"
"$GIT" -C "$FX" config user.email t@t
"$GIT" -C "$FX" config user.name t
print -r -- 'a' > "$FX/a.txt"
print -r -- 'b' > "$FX/b.txt"
"$GIT" -C "$FX" add a.txt b.txt
"$GIT" -C "$FX" commit -q -m seed

# --- install-hooks always-on wiring ---
zsh "$GITTY" install-hooks --repo "$FX" --force >/dev/null 2>&1
[[ -x "$FX/.hooks/lib/apply-file-attrs.sh" ]] \
  && _pass "lib installed" || _fail "lib installed" "missing"
[[ -x "$FX/.hooks/pre-commit.d/05-file-attrs-sync.sh" ]] \
  && _pass "pre-commit sync wrapper" || _fail "pre-commit sync" "missing"
[[ -x "$FX/.hooks/post-checkout.d/10-file-attrs.sh" ]] \
  && _pass "post-checkout apply wrapper" || _fail "post-checkout wrapper" "missing"
[[ -x "$FX/.hooks/post-merge.d/10-file-attrs.sh" ]] \
  && _pass "post-merge apply wrapper" || _fail "post-merge wrapper" "missing"
[[ "$("$GIT" -C "$FX" config --get core.hooksPath)" == ".hooks" ]] \
  && _pass "core.hooksPath=.hooks" || _fail "hooksPath" "wrong"

# --- pre-commit: uchg add -> inventory staged+committed ---
chflags uchg "$FX/a.txt"
print -r -- 'note' > "$FX/note.txt"
"$GIT" -C "$FX" add note.txt
"$GIT" -C "$FX" commit -q -m 'uchg a via hook'
jq -e '.entries|map(.path)|index("a.txt")' "$FX/.gitty/file-attrs.json" >/dev/null \
  && _pass "hook sync adds a.txt" || _fail "hook sync add" "$(cat "$FX/.gitty/file-attrs.json" 2>/dev/null)"
"$GIT" -C "$FX" show --name-only --pretty=format: HEAD | grep -q 'file-attrs.json' \
  && _pass "inventory committed" || _fail "inventory committed" "not in HEAD"
/bin/ls -lO "$FX/a.txt" | grep -q uchg \
  && _pass "a.txt still uchg after commit" || _fail "a.txt uchg" "lost"

# --- pre-commit: nouchg -> dropped from inventory ---
chflags nouchg "$FX/a.txt"
print -r -- 'drop' > "$FX/drop.txt"
"$GIT" -C "$FX" add drop.txt
"$GIT" -C "$FX" commit -q -m 'nouchg a via hook'
jq -e '(.entries|map(.path)|index("a.txt")) == null' "$FX/.gitty/file-attrs.json" >/dev/null \
  && _pass "hook sync drops a.txt" || _fail "hook sync drop" "$(cat "$FX/.gitty/file-attrs.json")"

# --- mark b, commit, then second clone restores ---
chflags uchg "$FX/b.txt"
print -r -- 'keep' > "$FX/keep.txt"
"$GIT" -C "$FX" add keep.txt
"$GIT" -C "$FX" commit -q -m 'uchg b via hook'
jq -e '.entries|map(.path)|index("b.txt")' "$FX/.gitty/file-attrs.json" >/dev/null \
  && _pass "hook sync adds b.txt" || _fail "hook sync b" "$(cat "$FX/.gitty/file-attrs.json")"

CLONE=$(mktemp -d /tmp/gitty-file-attrs-clone.XXXXXX)
"$GIT" clone -q "$FX" "$CLONE"
# clone has no hooksPath until install-hooks (chicken-egg)
zsh "$GITTY" install-hooks --repo "$CLONE" --force >/dev/null 2>&1
/bin/ls -lO "$CLONE/b.txt" | grep -q uchg \
  && _pass "clone+install-hooks applies b.txt uchg" || _fail "clone apply" "$(/bin/ls -lO "$CLONE/b.txt")"
/bin/ls -lO "$CLONE/a.txt" | grep -q uchg \
  && _fail "clone leaves a.txt unlocked" "a.txt has uchg" || _pass "clone leaves a.txt unlocked"

# --- post-checkout re-apply after unlock + checkout ---
bash "$CLONE/.hooks/lib/apply-file-attrs.sh" --repo "$CLONE" --unlock --quiet
/bin/ls -lO "$CLONE/b.txt" | grep -q uchg \
  && _fail "unlock cleared b" "still uchg" || _pass "unlock cleared b"
"$GIT" -C "$CLONE" checkout -q HEAD
/bin/ls -lO "$CLONE/b.txt" | grep -q uchg \
  && _pass "post-checkout re-applies b" || _fail "post-checkout re-apply" "$(/bin/ls -lO "$CLONE/b.txt")"

# --- gitty apply-flags CLI (package path) ---
bash "$CLONE/.hooks/lib/apply-file-attrs.sh" --repo "$CLONE" --unlock --quiet
zsh "$GITTY" apply-flags --repo "$CLONE" --quiet
/bin/ls -lO "$CLONE/b.txt" | grep -q uchg \
  && _pass "gitty apply-flags CLI" || _fail "apply-flags CLI" "$(/bin/ls -lO "$CLONE/b.txt")"

# --- reconcile clears stray uchg not in inventory ---
chflags uchg "$CLONE/a.txt"
zsh "$GITTY" apply-flags --repo "$CLONE" --quiet
/bin/ls -lO "$CLONE/a.txt" | grep -q uchg \
  && _fail "reconcile clears stray" "a.txt still uchg" || _pass "reconcile clears stray"

print -u2 "file-attrs smoke: $PASS passed, $FAIL failed"
(( FAIL == 0 )) && exit 0 || exit 1
