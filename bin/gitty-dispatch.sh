#!/usr/bin/env zsh
# Config-driven Git operation dispatcher. Policy lives in the caller's JSON.

[[ -n "${ZSH_VERSION:-}" ]] || exec /usr/bin/env zsh "$0" "$@"
setopt errexit pipefail nounset

typeset -r GITTY_DISPATCH_EXIT_CONFIG=93
typeset _config=""
typeset -i _require_match=0

gitty_dispatch_usage() {
  cat <<'EOF'
usage: gitty-dispatch --config <path> [--require-match] -- <git-args...>

Dispatch configured Git operations to a canonical driver. Unmatched repositories
pass through unless --require-match is set.
EOF
}

gitty_dispatch_fail() {
  print -u2 -r -- "gitty-dispatch: $1 (exit $GITTY_DISPATCH_EXIT_CONFIG)"
  exit "$GITTY_DISPATCH_EXIT_CONFIG"
}

while (( $# > 0 )); do
  case "$1" in
    --config)
      (( $# >= 2 )) || gitty_dispatch_fail '--config requires a path'
      _config="$2"
      shift 2
      ;;
    --require-match)
      _require_match=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -h|--help)
      gitty_dispatch_usage
      exit 0
      ;;
    *)
      gitty_dispatch_fail "unknown option: $1"
      ;;
  esac
done

[[ -n "$_config" ]] || gitty_dispatch_fail '--config is required'
[[ "$_config" == /* && -f "$_config" ]] || gitty_dispatch_fail 'config must be an existing absolute path'
(( $# > 0 )) || gitty_dispatch_fail 'Git arguments are required after --'
command -v jq >/dev/null 2>&1 || gitty_dispatch_fail 'jq is required'
typeset -r _config_path="${_config:A}"
typeset -r _config_dir="${_config_path:h}"
typeset -r _config_json="$(<"$_config_path")"
jq -e '
  type == "object" and
  .dispatch.version == 1 and
  (.dispatch.real_git | type == "string" and length > 0 and (contains("\u0000") | not) and (test("[\r\n]") | not)) and
  (.guarded_repos | type == "array") and
  (.guarded_repos | all(
    type == "object" and
    (.match | type == "object") and
    (.match.remote_urls | type == "array" and length > 0) and
    (.match.remote_urls | all(type == "string" and length > 0 and (contains("\u0000") | not))) and
    (.dispatch | type == "object") and
    (.dispatch.mode == "redirect") and
    (.dispatch.intercept_ops | type == "array" and length > 0) and
    (.dispatch.intercept_ops | all(type == "string" and length > 0 and (contains("\u0000") | not))) and
    (.dispatch.passthrough_ops | type == "array") and
    (.dispatch.passthrough_ops | all(type == "string" and length > 0 and (contains("\u0000") | not))) and
    ([.dispatch.intercept_ops[], .dispatch.passthrough_ops[]] | length == (unique | length)) and
    (.dispatch.driver_argv | type == "array" and length > 0) and
    (.dispatch.driver_argv | all(type == "string" and (contains("\u0000") | not))) and
    ([.dispatch.driver_argv[] | select(. == "{git_args}")] | length <= 1) and
    (.dispatch.authorized_ancestor | type == "string" and length > 0 and (contains("\u0000") | not) and (test("[\r\n]") | not))
  ))
' <<<"$_config_json" >/dev/null 2>&1 || gitty_dispatch_fail 'invalid config root'

typeset -r _real_git_raw="$(jq -er '.dispatch.real_git' <<<"$_config_json")"
[[ "$_real_git_raw" == /* && -x "$_real_git_raw" ]] || gitty_dispatch_fail 'dispatch.real_git must be an executable absolute path'
typeset -r _real_git="${_real_git_raw:A}"

typeset -a _git_argv=("$@")
typeset -a _repo_args=()
typeset -a _config_overrides=()
typeset -i _has_config_env=0
typeset -i _command_index=1
typeset _argument
while (( _command_index <= ${#_git_argv[@]} )); do
  _argument="${_git_argv[$_command_index]}"
  case "$_argument" in
    -c|-C|--git-dir|--work-tree|--namespace)
      (( _command_index < ${#_git_argv[@]} )) || gitty_dispatch_fail "missing value for $_argument"
      if [[ "$_argument" == -c ]]; then
        _config_overrides+=("${_git_argv[$(( _command_index + 1 ))]}")
      else
        _repo_args+=("$_argument" "${_git_argv[$(( _command_index + 1 ))]}")
      fi
      (( _command_index += 2 ))
      ;;
    --config-env)
      (( _command_index < ${#_git_argv[@]} )) || gitty_dispatch_fail '--config-env requires a name'
      _has_config_env=1
      (( _command_index += 2 ))
      ;;
    --config-env=*)
      _has_config_env=1
      (( _command_index += 1 ))
      ;;
    -c*)
      _config_overrides+=("${_argument#-c}")
      (( _command_index += 1 ))
      ;;
    --git-dir=*|--work-tree=*|--namespace=*|--bare)
      _repo_args+=("$_argument")
      (( _command_index += 1 ))
      ;;
    --no-pager|--paginate|-P|-p|--no-optional-locks|--no-replace-objects|--literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs|--no-lazy-fetch)
      (( _command_index += 1 ))
      ;;
    --version|-v|--help|-h|--exec-path|--html-path|--man-path|--info-path)
      exec "$_real_git" "${_git_argv[@]}"
      ;;
    --exec-path=*)
      (( _command_index += 1 ))
      ;;
    -*)
      gitty_dispatch_fail "unsupported Git global option: $_argument"
      ;;
    *)
      break
      ;;
  esac
done

typeset -r _operation="${_git_argv[$_command_index]:-}"
[[ -n "$_operation" ]] || exec "$_real_git" "${_git_argv[@]}"

gitty_dispatch_policy_git() {
  /usr/bin/env -i HOME="$_config_dir" PATH=/usr/bin:/bin LC_ALL=C \
    "$_real_git" "$@"
}

typeset _repo_root _repo_git_dir _remote_url
if ! _repo_git_dir=$(gitty_dispatch_policy_git "${_repo_args[@]}" rev-parse --absolute-git-dir 2>/dev/null); then
  (( _require_match == 0 )) || gitty_dispatch_fail 'repository discovery failed'
  exec "$_real_git" "${_git_argv[@]}"
fi
if ! _repo_root=$(gitty_dispatch_policy_git "${_repo_args[@]}" rev-parse --show-toplevel 2>/dev/null); then
  _repo_root="$_repo_git_dir"
fi
if ! _remote_url=$(gitty_dispatch_policy_git "${_repo_args[@]}" config --local --get remote.origin.url 2>/dev/null); then
  (( _require_match == 0 )) || gitty_dispatch_fail 'repository has no local origin URL'
  exec "$_real_git" "${_git_argv[@]}"
fi

typeset -a _matches=()
while IFS= read -r _match; do
  [[ -n "$_match" ]] && _matches+=("$_match")
done < <(jq -c --arg remote "$_remote_url" '
  .guarded_repos[] | select(.match.remote_urls | index($remote) != null)
' <<<"$_config_json")

if (( ${#_matches[@]} == 0 )); then
  (( _require_match == 0 )) || gitty_dispatch_fail 'no repository rule matched'
  exec "$_real_git" "${_git_argv[@]}"
fi
(( ${#_matches[@]} == 1 )) || gitty_dispatch_fail 'multiple repository rules matched'

typeset -r _rule="${_matches[1]}"
(( _has_config_env == 0 )) || gitty_dispatch_fail '--config-env is not accepted for matched repositories'
for _argument in "${_config_overrides[@]}"; do
  [[ "$_argument" != alias.* ]] || gitty_dispatch_fail 'caller-defined Git aliases are not accepted for matched repositories'
done

if ! jq -e --arg operation "$_operation" '.dispatch.intercept_ops | index($operation) != null' <<<"$_rule" >/dev/null; then
  if ! jq -e --arg operation "$_operation" '.dispatch.passthrough_ops | index($operation) != null' <<<"$_rule" >/dev/null; then
    gitty_dispatch_fail "operation is neither intercepted nor permitted: $_operation"
  fi
  exec "$_real_git" "${_git_argv[@]}"
fi

gitty_dispatch_expand_control_path() {
  local path_spec="$1"
  case "$path_spec" in
    /*) print -r -- "$path_spec" ;;
    '{config_dir}') print -r -- "$_config_dir" ;;
    '{config_dir}/'*) print -r -- "$_config_dir/${path_spec#\{config_dir\}/}" ;;
    *) return 1 ;;
  esac
}

typeset -r _authorized_spec="$(jq -er '.dispatch.authorized_ancestor' <<<"$_rule")"
typeset -r _authorized_raw="$(gitty_dispatch_expand_control_path "$_authorized_spec")" || gitty_dispatch_fail 'authorized_ancestor must be absolute or config-relative'
[[ -e "$_authorized_raw" ]] || gitty_dispatch_fail 'authorized_ancestor does not exist'
typeset -r _authorized="${_authorized_raw:A}"

typeset -a _driver_argv=()
while IFS= read -r -d '' _argument; do
  _driver_argv+=("$_argument")
done < <(jq -j '.dispatch.driver_argv[] | ., "\u0000"' <<<"$_rule")
(( ${#_driver_argv[@]} > 0 )) || gitty_dispatch_fail 'driver_argv cannot be empty'
_driver_argv[1]="$(gitty_dispatch_expand_control_path "${_driver_argv[1]}")" || gitty_dispatch_fail 'driver_argv[0] must be absolute or config-relative'
[[ -x "${_driver_argv[1]}" ]] || gitty_dispatch_fail 'driver_argv[0] must be executable'
[[ "${_driver_argv[1]:A}" == "$_authorized" ]] || gitty_dispatch_fail 'driver and authorized ancestor must resolve to the same path'
_driver_argv[1]="$_authorized"
[[ "$_authorized" != "${0:A}" ]] || gitty_dispatch_fail 'dispatcher cannot be its own driver'

gitty_dispatch_script_identity_matches() {
  local authorized="$1" executable="$2"
  shift 2
  local -a process_argv=("$@")
  local candidate
  [[ -e "$executable" && "${executable:A}" == "$authorized" ]] && return 0
  (( ${#process_argv[@]} >= 2 )) || return 1
  case "${executable:t}" in
    zsh|bash|sh|dash|ksh|python|python[0-9]*|node|ruby|perl) ;;
    *) return 1 ;;
  esac
  candidate="${process_argv[2]}"
  [[ "$candidate" == /* && -e "$candidate" && "${candidate:A}" == "$authorized" ]]
}

gitty_dispatch_ancestor_matches() {
  local authorized="$1" platform="$(uname -s)"
  local pid="$PPID" parent executable command_line process_stat process_tail
  local -a process_argv=()
  local -i depth=0
  while (( pid > 1 && depth < 64 )); do
    process_argv=()
    if [[ "$platform" == Linux ]]; then
      [[ -r "/proc/$pid/cmdline" && -r "/proc/$pid/stat" ]] || return 2
      executable=$(readlink "/proc/$pid/exe" 2>/dev/null || true)
      while IFS= read -r -d '' token; do process_argv+=("$token"); done < "/proc/$pid/cmdline"
      gitty_dispatch_script_identity_matches "$authorized" "$executable" "${process_argv[@]}" && return 0
      process_stat=$(<"/proc/$pid/stat") || return 2
      process_tail="${process_stat##*) }"
      process_argv=("${(z)process_tail}")
      (( ${#process_argv[@]} >= 2 )) || return 2
      parent="${process_argv[2]}"
    elif [[ "$platform" == Darwin ]]; then
      [[ "$authorized" != *[[:space:]]* ]] || return 2
      executable=$(/bin/ps -ww -p "$pid" -o comm= 2>/dev/null) || return 2
      command_line=$(/bin/ps -ww -p "$pid" -o command= 2>/dev/null) || return 2
      process_argv=("${(z)command_line}")
      gitty_dispatch_script_identity_matches "$authorized" "$executable" "${process_argv[@]}" && return 0
      parent=$(/bin/ps -p "$pid" -o ppid= 2>/dev/null | tr -d '[:space:]') || return 2
    else
      return 2
    fi
    [[ "$parent" == <-> ]] || return 2
    pid="$parent"
    (( depth += 1 ))
  done
  (( pid <= 1 )) && return 1
  return 2
}

typeset _ancestry_status
if gitty_dispatch_ancestor_matches "$_authorized"; then
  exec "$_real_git" "${_git_argv[@]}"
else
  _ancestry_status=$?
fi
(( _ancestry_status == 1 )) || gitty_dispatch_fail 'process ancestry could not be verified'

typeset -a _expanded_driver_argv=()
for ((_command_index = 1; _command_index <= ${#_driver_argv[@]}; _command_index++)); do
  case "${_driver_argv[$_command_index]}" in
    '{repo_root}') _expanded_driver_argv+=("$_repo_root") ;;
    '{operation}') _expanded_driver_argv+=("$_operation") ;;
    '{git_args}') _expanded_driver_argv+=("${_git_argv[@]}") ;;
    *) _expanded_driver_argv+=("${_driver_argv[$_command_index]}") ;;
  esac
done
exec "${_expanded_driver_argv[@]}"
