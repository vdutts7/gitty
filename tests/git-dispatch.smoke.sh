#!/usr/bin/env zsh
setopt errexit pipefail nounset

typeset -r DISPATCH="${0:A:h:h}/bin/gitty-dispatch.sh"
typeset -r REAL_GIT="/usr/bin/git"
[[ -x "$REAL_GIT" ]] || { print -u2 "FAIL missing $REAL_GIT"; exit 1; }
typeset -r FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/gitty-dispatch.XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT

typeset -r REMOTE="$FIXTURE/remote.git"
typeset -r REPO="$FIXTURE/work tree"
# macOS ancestry verification cannot safely parse whitespace in authorized
# driver paths (see README). Keep repo path spaced; keep driver path portable.
typeset -r DRIVER="$FIXTURE/canonical-driver.sh"
typeset -r SPOOF="$FIXTURE/canonical-driver.sh-spoof"
typeset -r CONFIG="$FIXTURE/config.json"
typeset -r LOG="$FIXTURE/events.log"

"$REAL_GIT" init --bare --initial-branch=main "$REMOTE" >/dev/null
"$REAL_GIT" init --initial-branch=main "$REPO" >/dev/null
"$REAL_GIT" -C "$REPO" config user.name fixture
"$REAL_GIT" -C "$REPO" config user.email fixture@example.invalid
"$REAL_GIT" -C "$REPO" remote add origin "$REMOTE"
print -r -- seed > "$REPO/file.txt"
"$REAL_GIT" -C "$REPO" add file.txt
"$REAL_GIT" -C "$REPO" commit -m seed >/dev/null

cat > "$DRIVER" <<'DRIVER_EOF'
#!/usr/bin/env zsh
print -r -- "driver:$2:$1" >> "$GITTY_DISPATCH_TEST_LOG"
"$GITTY_DISPATCH_TEST_BIN" --config "$GITTY_DISPATCH_TEST_CONFIG" --require-match -- -C "$1" "$2" origin main
DRIVER_EOF
chmod +x "$DRIVER"

cat > "$SPOOF" <<'SPOOF_EOF'
#!/usr/bin/env zsh
print -r -- spoof >> "$GITTY_DISPATCH_TEST_LOG"
"$GITTY_DISPATCH_TEST_BIN" --config "$GITTY_DISPATCH_TEST_CONFIG" --require-match -- -C "$1" push origin main
SPOOF_EOF
chmod +x "$SPOOF"

jq -n \
  --arg git "$REAL_GIT" \
  --arg match "$REMOTE" \
  --arg driver '{config_dir}/canonical-driver.sh' \
  '{
    dispatch: {version: 1, real_git: $git},
    guarded_repos: [{
      match: {remote_urls: [$match]},
      dispatch: {
        mode: "redirect",
        intercept_ops: ["push", "fetch"],
        passthrough_ops: ["status"],
        driver_argv: [$driver, "{repo_root}", "{operation}"],
        authorized_ancestor: $driver
      }
    }]
  }' > "$CONFIG"

typeset -x GITTY_DISPATCH_TEST_LOG="$LOG"
typeset -x GITTY_DISPATCH_TEST_BIN="$DISPATCH"
typeset -x GITTY_DISPATCH_TEST_CONFIG="$CONFIG"

typeset -i PASS=0
pass() { PASS=$(( PASS + 1 )); print -r -- "PASS $1"; }
expect_rc() {
  local expected="$1"; shift
  set +e
  "$@" >/dev/null 2>&1
  local actual=$?
  set -e
  [[ "$actual" == "$expected" ]] || { print -u2 -r -- "FAIL expected rc=$expected actual=$actual: $*"; exit 1; }
}

"$DISPATCH" --help >/dev/null
pass help

"$DISPATCH" --config "$CONFIG" --require-match -- -C "$REPO" status --short >/dev/null
[[ ! -e "$LOG" ]] || { print -u2 'FAIL read operation invoked driver'; exit 1; }
pass passthrough

__GITTY_ACTIVE=1 __DOTSYNC_ACTIVE=1 "$DISPATCH" --config "$CONFIG" --require-match -- -C "$REPO" push origin main >/dev/null
[[ "$(grep -c '^driver:push:' "$LOG")" == 1 ]]
[[ "$($REAL_GIT --git-dir="$REMOTE" rev-parse main)" == "$($REAL_GIT -C "$REPO" rev-parse HEAD)" ]]
pass redirect_and_exact_ancestor
pass forged_environment_ignored

GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.url GIT_CONFIG_VALUE_0=hidden.invalid \
  "$DISPATCH" --config "$CONFIG" --require-match -- -C "$REPO" fetch >/dev/null
[[ "$(grep -c '^driver:fetch:' "$LOG")" == 1 ]]
pass caller_config_cannot_hide_remote

print -r -- change >> "$REPO/file.txt"
"$REAL_GIT" -C "$REPO" add file.txt
"$REAL_GIT" -C "$REPO" commit -m change >/dev/null
"$SPOOF" "$REPO" "$DRIVER" >/dev/null
[[ "$(grep -c '^spoof$' "$LOG")" == 1 ]]
[[ "$(grep -c '^driver:push:' "$LOG")" == 2 ]]
pass later_argument_does_not_authorize

typeset -r BEFORE_SPOOF="$(grep -c '^driver:push:' "$LOG")"
/bin/bash -c '"$GITTY_DISPATCH_TEST_BIN" --config "$GITTY_DISPATCH_TEST_CONFIG" --require-match -- -C "$1" push origin main' "$DRIVER" "$REPO" >/dev/null
[[ "$(grep -c '^driver:push:' "$LOG")" == $(( BEFORE_SPOOF + 1 )) ]]
pass forged_argv_zero_does_not_authorize

jq '.guarded_repos += [.guarded_repos[0]]' "$CONFIG" > "$FIXTURE/ambiguous.json"
expect_rc 93 "$DISPATCH" --config "$FIXTURE/ambiguous.json" --require-match -- -C "$REPO" push
pass ambiguous_match_fails

jq '.dispatch.version = 2' "$CONFIG" > "$FIXTURE/version.json"
expect_rc 93 "$DISPATCH" --config "$FIXTURE/version.json" --require-match -- -C "$REPO" push
pass schema_version_fails

jq '.guarded_repos[0] = "invalid"' "$CONFIG" > "$FIXTURE/malformed.json"
expect_rc 93 "$DISPATCH" --config "$FIXTURE/malformed.json" --require-match -- -C "$REPO" push
pass malformed_rule_fails

expect_rc 93 "$DISPATCH" --config "$CONFIG" --require-match -- -c alias.publish=push -C "$REPO" publish origin main
expect_rc 93 "$DISPATCH" --config "$CONFIG" --require-match -- -C "$REPO" publish origin main
pass alias_and_unknown_operation_fail

jq '.guarded_repos = []' "$CONFIG" > "$FIXTURE/unmatched.json"
expect_rc 93 "$DISPATCH" --config "$FIXTURE/unmatched.json" --require-match -- -C "$REPO" push
"$DISPATCH" --config "$FIXTURE/unmatched.json" -- -C "$REPO" status --short >/dev/null
pass require_match_and_default_passthrough

cat > "$FIXTURE/exit37.sh" <<'EXIT_EOF'
#!/bin/sh
exit 37
EXIT_EOF
chmod +x "$FIXTURE/exit37.sh"
jq --arg driver "$FIXTURE/exit37.sh" \
  '.guarded_repos[0].dispatch.driver_argv = [$driver] | .guarded_repos[0].dispatch.authorized_ancestor = $driver' \
  "$CONFIG" > "$FIXTURE/exit37.json"
expect_rc 37 "$DISPATCH" --config "$FIXTURE/exit37.json" --require-match -- -C "$REPO" fetch
pass driver_status_propagates

cat > "$FIXTURE/capture.sh" <<'CAPTURE_EOF'
#!/usr/bin/env zsh
printf '%s\0' "$@" > "$GITTY_DISPATCH_CAPTURE"
CAPTURE_EOF
chmod +x "$FIXTURE/capture.sh"
jq --arg driver "$FIXTURE/capture.sh" '
  .guarded_repos[0].dispatch.driver_argv = [$driver, "{git_args}"]
  | .guarded_repos[0].dispatch.authorized_ancestor = $driver
' "$CONFIG" > "$FIXTURE/capture.json"
typeset -x GITTY_DISPATCH_CAPTURE="$FIXTURE/capture.bin"
"$DISPATCH" --config "$FIXTURE/capture.json" --require-match -- -C "$REPO" push --dry-run 'ref with spaces' >/dev/null
typeset -a CAPTURED=()
while IFS= read -r -d '' _captured; do CAPTURED+=("$_captured"); done < "$GITTY_DISPATCH_CAPTURE"
[[ "${(j:|:)CAPTURED}" == "-C|$REPO|push|--dry-run|ref with spaces" ]]
pass original_argv_preserved

# Ancestry that cannot be verified must fail closed (exit 93), never redirect.
# Force the unknown-platform branch of the ancestry walk via a fake uname.
mkdir -p "$FIXTURE/fakebin"
cat > "$FIXTURE/fakebin/uname" <<'UNAME_EOF'
#!/bin/sh
echo TestOS
UNAME_EOF
chmod +x "$FIXTURE/fakebin/uname"
expect_rc 93 env PATH="$FIXTURE/fakebin:$PATH" \
  "$DISPATCH" --config "$CONFIG" --require-match -- -C "$REPO" push origin main
pass ancestry_unverifiable_fails_closed

# Control characters in trust-boundary config fields must be rejected.
jq '.dispatch.real_git = "/usr/bin/git\nevil"' "$CONFIG" > "$FIXTURE/newline-git.json"
expect_rc 93 "$DISPATCH" --config "$FIXTURE/newline-git.json" --require-match -- -C "$REPO" push
jq '.guarded_repos[0].dispatch.authorized_ancestor = "/tmp/driver\nspoof"' "$CONFIG" > "$FIXTURE/newline-anc.json"
expect_rc 93 "$DISPATCH" --config "$FIXTURE/newline-anc.json" --require-match -- -C "$REPO" push
pass control_char_config_field_rejected

# Caller-supplied --config-env cannot be smuggled into a matched repository.
expect_rc 93 "$DISPATCH" --config "$CONFIG" --require-match -- --config-env FOO=BAR -C "$REPO" push origin main
pass config_env_rejected_for_matched_repo

# The dispatcher must refuse to authorize itself as the driver (no self-redirect loop).
jq --arg d "$DISPATCH" '
  .guarded_repos[0].dispatch.driver_argv = [$d, "{repo_root}", "{operation}"]
  | .guarded_repos[0].dispatch.authorized_ancestor = $d
' "$CONFIG" > "$FIXTURE/selfdriver.json"
expect_rc 93 "$DISPATCH" --config "$FIXTURE/selfdriver.json" --require-match -- -C "$REPO" push origin main
pass dispatcher_cannot_be_own_driver

print -r -- "git-dispatch smoke: $PASS passed"
