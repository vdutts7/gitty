#!/usr/bin/env zsh
# One command: git add, commit, force push. Run from any directory
# Part of @vd7/gitty - https://github.com/vdutts7/gitty

setopt errexit pipefail

typeset -r _GITTY_ROOT="${0:A:h:h}"

# Preserve CLI env overrides across optional GITTY_ENV source
_gitty_partial_cli=${GITTY_PARTIAL-}
_gitty_max_cli=${GITTY_MAX_FILE_BYTES-}

# ---------- Load environment (opt-in via GITTY_ENV only) ----------
if [[ -n "${GITTY_ENV:-}" && -f "$GITTY_ENV" ]]; then
  # shellcheck source=/dev/null
  source "$GITTY_ENV"
fi

[[ -n "$_gitty_partial_cli" ]] && GITTY_PARTIAL="$_gitty_partial_cli"
[[ -n "$_gitty_max_cli" ]] && GITTY_MAX_FILE_BYTES="$_gitty_max_cli"
GITTY_PARTIAL=${GITTY_PARTIAL:-1}

# ---------- Cleanup handler ----------
cleanup() {
  local exit_code=$?
  mkdir -p /tmp/_deleteme
  setopt localoptions nullglob
  local tmp_files=(/tmp/script_$$_*)
  [[ ${#tmp_files[@]} -gt 0 ]] && mv "${tmp_files[@]}" /tmp/_deleteme/ 2>/dev/null || true
  exit $exit_code
}
trap cleanup EXIT SIGTERM SIGINT SIGHUP

# ---------- Partial commit/push: hold back offenders, proceed with the rest ----------
typeset -a gitty_held_paths=()
typeset -a gitty_held_reasons=()
typeset -a _gitty_staged_snapshot=()
typeset -a GITTY_GIT=(git -c core.quotePath=false)

gitty_read_staged_paths() {
  _gitty_staged_snapshot=()
  local p
  while IFS= read -r -d '' p; do
    [[ -n "$p" ]] && _gitty_staged_snapshot+=("$p")
  done < <("${GITTY_GIT[@]}" diff --cached --name-only -z 2>/dev/null || true)
}

gitty_refresh_staged_snapshot() { gitty_read_staged_paths; }

gitty_path_canonical() {
  local p="$1"
  command -v python3 >/dev/null 2>&1 || { print -r -- "$p"; return 0 }
  python3 -c 'import sys, unicodedata; print(unicodedata.normalize("NFKC", sys.argv[1]))' "$p"
}

gitty_path_from_display() {
  local p="$1"
  p="${p#\"}"; p="${p%\"}"
  print -r -- "$p"
}

gitty_path_match_staged() {
  local hint="$1" raw canon staged base
  raw=$(gitty_path_from_display "$hint")
  canon=$(gitty_path_canonical "$raw")
  for staged in "${_gitty_staged_snapshot[@]}"; do
    [[ "$(gitty_path_canonical "$staged")" == "$canon" ]] && { print -r -- "$staged"; return 0 }
  done
  base="${raw:t}"
  for staged in "${_gitty_staged_snapshot[@]}"; do
    [[ "${staged:t}" == "$base" ]] && { print -r -- "$staged"; return 0 }
  done
  [[ -n "$raw" ]] && { print -r -- "$raw"; return 0 }
  return 1
}

gitty_resolve_push_offender() {
  local output="$1" hint resolved
  hint=$(gitty_parse_push_offender "$output" 2>/dev/null || true)
  [[ -z "$hint" ]] && return 1
  gitty_refresh_staged_snapshot
  resolved=$(gitty_path_match_staged "$hint" 2>/dev/null || true)
  [[ -n "$resolved" ]] && { print -r -- "$resolved"; return 0 }
  return 1
}

gitty_record_held() {
  local path="$1" reason="$2"
  local existing
  for existing in "${gitty_held_paths[@]}"; do
    [[ "$existing" == "$path" ]] && return 0
  done
  gitty_held_paths+=("$path")
  gitty_held_reasons+=("$reason")
  echo "🔴 - $path — held back ($reason)"
}

gitty_file_size() {
  local file="$1"
  local size=0
  [[ -f "$file" ]] || { echo 0; return 0 }
  if [[ -x /usr/bin/stat ]]; then
    /usr/bin/stat -f%z "$file" 2>/dev/null && return 0
    /usr/bin/stat -c%s "$file" 2>/dev/null && return 0
  fi
  if command -v stat >/dev/null 2>&1; then
    stat -f%z "$file" 2>/dev/null && return 0
    stat -c%s "$file" 2>/dev/null && return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import os, sys; print(os.path.getsize(sys.argv[1]))' "$file" 2>/dev/null && return 0
  fi
  echo 0
}

gitty_holdback_offenders() {
  [[ "${GITTY_PARTIAL:-1}" == 0 ]] && return 0

  setopt localoptions
  unsetopt errexit

  local -a held=()
  local -a reasons=()
  local path mode size max_bytes reason entry

  max_bytes=${GITTY_MAX_FILE_BYTES:-$((100 * 1024 * 1024))}

  [[ -n "${GITTY_DEBUG:-}" ]] && echo "🟡 - holdback scan (max=${max_bytes} bytes)" >&2

  local -a staged_paths=("${_gitty_staged_snapshot[@]}")
  [[ -n "${GITTY_DEBUG:-}" ]] && echo "🟡 - holdback staged: ${staged_paths[*]:-none}" >&2

  for path in "${staged_paths[@]}"; do
    [[ -z "$path" ]] && continue
    reason=""

    entry=$("${GITTY_GIT[@]}" ls-files -s -- "$path" 2>/dev/null || true)
    mode=${entry%% *}
    if [[ "$mode" == "160000" ]]; then
      reason="submodule (use gittyembedded)"
    elif [[ -f "$path" ]]; then
      size=$(gitty_file_size "$path")
      [[ -n "${GITTY_DEBUG:-}" ]] && echo "🟡 - holdback check $path size=$size" >&2
      if (( size > max_bytes )); then
        reason="exceeds push size limit (${size} bytes)"
      fi
    fi

    if [[ -n "$reason" ]]; then
      "${GITTY_GIT[@]}" reset HEAD -- "$path" 2>/dev/null || true
      held+=("$path")
      reasons+=("$reason")
    fi
  done

  if [[ ${#held[@]} -gt 0 ]]; then
    local i
    for i in {1..${#held[@]}}; do
      gitty_record_held "${held[$i]}" "${reasons[$i]}"
    done
    echo "🟡 - ${#held[@]} path(s) held back; proceeding with the rest"
    gitty_refresh_staged_snapshot
  fi
}

gitty_parse_push_offender() {
  local output="$1"
  local path

  path=$(printf '%s\n' "$output" | grep -oiE 'File [^[:space:]]+ is [0-9.]+ MB' | head -1 | awk '{print $2}')
  [[ -n "$path" ]] && { echo "$path"; return 0 }

  path=$(printf '%s\n' "$output" | grep -oiE 'remote: error: File [^[:space:]]+ is' | head -1 | awk '{print $4}')
  [[ -n "$path" ]] && { echo "$path"; return 0 }

  return 1
}

gitty_unstage_held_paths() {
  local p
  for p in "${gitty_held_paths[@]}"; do
    "${GITTY_GIT[@]}" reset HEAD -- "$p" 2>/dev/null || true
  done
}

gitty_commit_safe() {
  local msg="$1"
  gitty_unstage_held_paths
  git commit -m "$msg" 2>&1
}

gitty_holdback_path() {
  local path="$1" reason="$2"
  "${GITTY_GIT[@]}" reset HEAD -- "$path" 2>/dev/null || true
  gitty_record_held "$path" "$reason"
}

gitty_report_partial() {
  local -a committed_paths=()
  local pushed_count=0
  local held_count=${#gitty_held_paths[@]}
  local i p

  if [[ "$committed" == true ]]; then
    while IFS= read -r -d '' p; do
      [[ -z "$p" ]] && continue
      committed_paths+=("$p")
    done < <("${GITTY_GIT[@]}" show --name-only --pretty=format: -z HEAD 2>/dev/null || true)
    pushed_count=${#committed_paths[@]}
  fi

  echo "── partial: commit/push ──"

  if [[ $pushed_count -gt 0 ]]; then
    for p in "${committed_paths[@]}"; do
      local is_held=false held_path
      for held_path in "${gitty_held_paths[@]}"; do
        [[ "$p" == "$held_path" ]] && is_held=true && break
      done
      [[ "$is_held" == true ]] && continue
      echo "🟢 - $p — committed and pushed"
    done
  elif [[ "$committed" == true ]]; then
    echo "🟢 - commit — committed and pushed"
    pushed_count=1
  elif [[ "$nothing_to_commit" == true && "$push_up_to_date" == true ]]; then
    echo "🟢 - remote — already up to date"
  elif [[ "$nothing_to_commit" == true ]]; then
    echo "🟢 - push — pending commits synced"
  fi

  if [[ $held_count -gt 0 ]]; then
    for i in {1..$held_count}; do
      echo "🔴 - ${gitty_held_paths[$i]} — not pushed (${gitty_held_reasons[$i]})"
    done
  fi

  if [[ $held_count -eq 0 && $pushed_count -gt 0 ]]; then
    echo "🟢 - all staged paths committed and pushed"
  elif [[ $held_count -gt 0 && $pushed_count -gt 0 ]]; then
    local pushed_ok=0 p is_held=false held_path
    for p in "${committed_paths[@]}"; do
      is_held=false
      for held_path in "${gitty_held_paths[@]}"; do
        [[ "$p" == "$held_path" ]] && is_held=true && break
      done
      [[ "$is_held" == false ]] && pushed_ok=$((pushed_ok + 1))
    done
    echo "🟢 - partial success — ${pushed_ok} pushed, ${held_count} held back"
  elif [[ $held_count -gt 0 && $pushed_count -eq 0 && "$nothing_to_commit" != true ]]; then
    echo "🔴 - nothing pushed — ${held_count} path(s) held back"
  fi
}

# ---------- Hook dashboard (logmoji) ----------
gitty_report_hooks() {
  local event="$1"
  local output="$2"
  local hook_rc="${3:-0}"

  echo "── hooks: ${event} ──"

  if [[ "$event" == "pre-commit" ]]; then
    if echo "$output" | grep -q '\[enforce-git-identity\] BLOCKED'; then
      echo "🔴 - enforce-git-identity — blocked"
    elif echo "$output" | grep -q '\[enforce-git-identity\] OK'; then
      echo "🟢 - enforce-git-identity — OK"
    elif [[ "$hook_rc" -eq 0 ]]; then
      echo "🟢 - enforce-git-identity — passed"
    fi

    if echo "$output" | grep -q 'em dashes replaced with hyphens'; then
      echo "🟢 - check-em-dashes — fixed (em dash -> hyphen)"
    elif [[ "$hook_rc" -eq 0 ]]; then
      echo "🟢 - check-em-dashes — passed"
    fi

    if echo "$output" | grep -q 'BLOCKED - staged files under a Python venv'; then
      echo "🔴 - check-python-venv — venv paths staged"
    elif [[ "$hook_rc" -eq 0 ]]; then
      echo "🟢 - check-python-venv — passed"
    fi

    if echo "$output" | grep -q 'metadata stripped'; then
      echo "🟢 - clearmeta — metadata stripped"
    elif [[ "$hook_rc" -eq 0 ]]; then
      echo "🟢 - clearmeta — passed"
    fi

    if echo "$output" | grep -q '\[readme-cache-bust\] bumped'; then
      echo "🟢 - readme-cache-bust — img v= bumped"
    elif echo "$output" | grep -q '\[readme-cache-bust\] skip'; then
      echo "🟢 - readme-cache-bust — skipped"
    fi

    if [[ "$hook_rc" -eq 0 ]]; then
      echo "🟢 - drop-eof-newline-only — passed"
    fi

    if echo "$output" | grep -q 'COMMIT BLOCKED — not a repo collaborator'; then
      echo "🔴 - check-collaborator — not a repo collaborator"
    elif echo "$output" | grep -q '\[pre-commit\] git user.name not set'; then
      echo "🔴 - check-collaborator — git user.name not set"
    elif [[ "$hook_rc" -eq 0 ]]; then
      echo "🟢 - check-collaborator — passed"
    fi

    return
  fi

  if [[ "$event" == "pre-push" ]]; then
    if echo "$output" | grep -qiE 'Touch ID denied|pre-push: BLOCKED'; then
      echo "🔴 - shelllock — Touch ID denied"
    elif [[ "$hook_rc" -eq 0 ]]; then
      echo "🟢 - shelllock — passed"
    fi

    if echo "$output" | grep -q 'Issues found - fix before pushing'; then
      echo "🔴 - health-check — issues found"
    elif echo "$output" | grep -q 'All checks passed'; then
      echo "🟢 - health-check — all checks passed"
    elif [[ "$hook_rc" -eq 0 ]]; then
      echo "🟢 - health-check — passed"
    fi
  fi
}

# ---------- Help / version ----------
gitty_version() {
  local pkg="${_GITTY_ROOT}/package.json"
  local ver="unknown"
  if [[ -f "$pkg" ]]; then
    ver=$(grep -m1 '"version"' "$pkg" | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
    [[ -z "$ver" ]] && ver="unknown"
  fi
  echo "gitty ${ver}"
  exit 0
}

gitty_usage_error() {
  echo "🔴 - $1" >&2
  echo "usage: gitty [-h|--help] [-V|--version] [commit_mssg] [root_dir]" >&2
  exit 1
}

typeset -r _GITTY_DEFAULT_MSG='-------[gitty] snapshotting repo state-------'

show_help() {
  cat << EOF
Usage: gitty [-h|--help] [-V|--version] [commit_mssg] [root_dir]

Git add, commit, and force push in one command.

Options:
  -h, --help      Show this help
  -V, --version   Show version

Arguments:
  commit_mssg  Commit message (prompts if omitted; default ${_GITTY_DEFAULT_MSG})
  root_dir     Absolute repo root (prompts if omitted; default \$PWD)

Examples:
  gitty "fix bug" /path/to/repo
  gitty

EOF
  exit 0
}

typeset -a gitty_positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) show_help ;;
    -V|--version) gitty_version ;;
    --)
      shift
      gitty_positional+=("$@")
      break
      ;;
    -*) gitty_usage_error "unknown flag: $1" ;;
    *) gitty_positional+=("$1"); shift ;;
  esac
done

(( ${#gitty_positional[@]} > 2 )) && gitty_usage_error "too many arguments"

commit_mssg="${gitty_positional[1]:-}"
root_dir="${gitty_positional[2]:-}"

[[ -z "$commit_mssg" ]] && {
  echo -n "Enter commit message [default: ${_GITTY_DEFAULT_MSG}]: "
  read commit_mssg
  [[ -z "$commit_mssg" ]] && commit_mssg="${_GITTY_DEFAULT_MSG}"
}

[[ -z "$root_dir" ]] && {
  echo -n "Enter root directory (absolute path) [default: $PWD]: "
  read root_dir
  [[ -z "$root_dir" ]] && root_dir="$PWD"
}

root_dir=$(echo "$root_dir" | sed "s/^[\"']//; s/[\"']$//")
root_dir=$(eval "echo $root_dir")

case "$root_dir" in
  /*) ;;
  *)
    echo "🔴 - Root directory must be an absolute path: $root_dir" >&2
    exit 1
    ;;
esac

[[ ! -d "$root_dir" ]] && {
  echo "🔴 - Directory does not exist: $root_dir" >&2
  exit 1
}

[[ ! -d "$root_dir/.git" && ! -f "$root_dir/.git" ]] && {
  echo "🔴 - Not a git repository: $root_dir" >&2
  exit 1
}

original_dir="$PWD"

cd "$root_dir" || {
  echo "🔴 - Failed to change to directory: $root_dir" >&2
  exit 1
}

if [[ -x "$root_dir/scripts/pre-gitty.sh" ]]; then
  "$root_dir/scripts/pre-gitty.sh"
fi

gitty_bust_readme() {
  local bust="${0:A:h}/readme-cache-bust.sh"
  [[ -x "$bust" && -f "$root_dir/README.md" ]] || return 0
  local -a bust_args=(--repo "$root_dir")
  if [[ "${README_CACHE_BUST:-}" == 1 ]]; then
    bust_args+=(--force)
  else
    bust_args+=(--if-dirty)
  fi
  "$bust" "${bust_args[@]}" 2>&1 || true
}

gitty_bust_readme

echo "🟡 - Staging changes in $root_dir..."

git add -A || {
  echo "🔴 - Failed to stage changes" >&2
  cd "$original_dir"
  exit 1
}
gitty_refresh_staged_snapshot
[[ -n "${GITTY_DEBUG:-}" ]] && echo "🟡 - post-add staged: ${_gitty_staged_snapshot[*]:-none}" >&2
gitty_holdback_offenders

if ! git diff --cached --quiet 2>/dev/null; then
  :
elif [[ ${#gitty_held_paths[@]} -gt 0 ]]; then
  echo "🟡 - Nothing committable after holdback; held back ${#gitty_held_paths[@]} path(s)"
else
  echo "🟡 - No staged changes"
fi

committed=false
nothing_to_commit=false

echo "🟡 - Committing changes..."
unsetopt errexit
commit_output=$(gitty_commit_safe "$commit_mssg")
commit_status=$?
setopt errexit

if [[ $commit_status -eq 0 ]]; then
  committed=true
  echo "$commit_output"
  gitty_report_hooks pre-commit "$commit_output" 0
elif echo "$commit_output" | grep -qiE 'nothing to commit|no changes added to commit'; then
  nothing_to_commit=true
  if [[ "${README_CACHE_BUST:-}" == 1 && -f "$root_dir/README.md" ]]; then
    echo "🟡 - README_CACHE_BUST=1: force-bump img v= on push-only path..."
    gitty_bust_readme
    git add README.md 2>/dev/null || true
    unsetopt errexit
    commit_output=$(git commit -m "README: cache-bust image URLs" 2>&1)
    commit_status=$?
    setopt errexit
    if [[ $commit_status -eq 0 ]]; then
      committed=true
      nothing_to_commit=false
      echo "$commit_output"
    fi
  fi
  if [[ "$nothing_to_commit" == true ]]; then
    echo "🟢 - Nothing to commit (working tree clean)"
    echo "── hooks: pre-commit ──"
    echo "🟢 - skipped (nothing to commit)"
  fi
else
  if [[ "${GITTY_NO_STALE_BASE_HEAL:-0}" != "1" ]] \
     && [[ "${_gitty_stale_base_healed:-0}" != "1" ]] \
     && echo "$commit_output" | grep -qE 'Stale-base guard'; then
    _gitty_stale_base_healed=1
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    echo "🟡 - Stale-base guard fired; fetching + rebasing onto origin/$branch (additive autoheal)..."
    git fetch origin "$branch" 2>/dev/null || git fetch origin 2>/dev/null || true
    if git rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
      unsetopt errexit
      git rebase --autostash "origin/$branch"
      rebase_rc=$?
      setopt errexit
      if [[ $rebase_rc -eq 0 ]]; then
        echo "🟢 - Rebase clean; re-staging and retrying commit..."
        git add -A || true
        gitty_refresh_staged_snapshot
        gitty_holdback_offenders
        unsetopt errexit
        commit_output=$(gitty_commit_safe "$commit_mssg")
        commit_status=$?
        setopt errexit
        if [[ $commit_status -eq 0 ]]; then
          committed=true
          echo "$commit_output"
          gitty_report_hooks pre-commit "$commit_output" 0
          echo "🟢 - Autohealed stale-base: rebased onto origin/$branch"
        fi
      else
        git rebase --abort 2>/dev/null || true
        echo "🔴 - Rebase conflicted during stale-base autoheal — real ledger collision." >&2
        echo "     Resolve manually per additive-git; do not auto-pick sides on shared JSON ledgers." >&2
      fi
    fi
  fi

  if [[ "$committed" != true ]]; then
    if echo "$commit_output" | grep -qiE 'hook declined|BLOCKED|failed'; then
      echo "🔴 - Commit blocked by hook" >&2
      gitty_report_hooks pre-commit "$commit_output" 1
    else
      echo "🔴 - Failed to commit changes" >&2
    fi
    echo "$commit_output" >&2
    cd "$original_dir"
    exit 1
  fi
fi

push_up_to_date=false
push_attempt=0
push_max=${GITTY_PUSH_RETRIES:-8}

# ---------- Safe additive sync (multi-host aware) ----------
# Escape hatch: GITTY_FORCE=1 restores the old bulldoze behavior for solo repos.
while true; do
  unsetopt errexit

  if [[ "${GITTY_FORCE:-0}" == "1" ]]; then
    echo "🟡 - Force pushing to remote (GITTY_FORCE=1)..."
    if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
      push_output=$(git push -f 2>&1)
    else
      push_output=$(git push -f -u origin HEAD 2>&1)
    fi
    push_status=$?
  else
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

    echo "🟡 - Fetching remote..."
    git fetch origin "$branch" 2>/dev/null || git fetch origin 2>/dev/null || true

    rebase_conflict=false
    if git rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
      echo "🟡 - Rebasing onto origin/$branch (additive sync)..."
      if ! git rebase --autostash "origin/$branch"; then
        git rebase --abort 2>/dev/null || true
        echo "🔴 - Real conflict with remote. Resolve manually, then re-run gitty." >&2
        echo "     Refusing to force-push over the other host's commits." >&2
        push_output="rebase conflict"
        push_status=1
        rebase_conflict=true
      fi
    fi

    if [[ "$rebase_conflict" != true ]]; then
      echo "🟡 - Pushing to remote..."
      if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
        push_output=$(git push origin "$branch" 2>&1)
      else
        push_output=$(git push -u origin HEAD 2>&1)
      fi
      push_status=$?

      if [[ $push_status -ne 0 ]]; then
        echo "🟡 - Push rejected; re-syncing and retrying with lease guard..."
        git fetch origin "$branch" 2>/dev/null || true
        if ! git rebase --autostash "origin/$branch"; then
          git rebase --abort 2>/dev/null || true
          echo "🔴 - Real conflict with remote. Resolve manually, then re-run gitty." >&2
          echo "     Refusing to force-push over the other host's commits." >&2
          push_output="rebase conflict"
          push_status=1
          rebase_conflict=true
        else
          push_output=$(git push --force-with-lease origin "$branch" 2>&1)
          push_status=$?
        fi
      fi
    fi
  fi

  setopt errexit

  if [[ "${rebase_conflict:-false}" == true ]]; then
    cd "$original_dir"
    exit 1
  fi

  if [[ $push_status -eq 0 ]]; then
    if echo "$push_output" | grep -qiE 'everything up-to-date|up to date'; then
      push_up_to_date=true
      echo "🟢 - Nothing to push (remote up-to-date)"
    else
      echo "$push_output"
    fi
    gitty_report_hooks pre-push "$push_output" 0
    break
  fi

  offender=""
  offender=$(gitty_resolve_push_offender "$push_output" 2>/dev/null || true)
  if [[ -z "$offender" || $push_attempt -ge $push_max ]]; then
    if echo "$push_output" | grep -qiE 'hook declined|BLOCKED|failed'; then
      echo "🔴 - Push blocked by hook" >&2
      gitty_report_hooks pre-push "$push_output" 1
    else
      echo "🔴 - Failed to push changes" >&2
    fi
    echo "$push_output" >&2
    cd "$original_dir"
    exit 1
  fi

  echo "🟡 - Push rejected $offender; holding back and retrying..."
  if [[ "$committed" == true ]]; then
    unsetopt errexit
    git reset --soft HEAD~1 2>/dev/null
    setopt errexit
    committed=false
  fi
  gitty_holdback_path "$offender" "push rejected"
  gitty_holdback_offenders

  if git diff --cached --quiet 2>/dev/null; then
    echo "🔴 - Nothing left to push after holdback" >&2
    echo "$push_output" >&2
    cd "$original_dir"
    exit 1
  fi

  echo "🟡 - Recommitting without held-back paths..."
  unsetopt errexit
  commit_output=$(gitty_commit_safe "$commit_mssg")
  commit_status=$?
  setopt errexit
  if [[ $commit_status -ne 0 ]]; then
    echo "🔴 - Failed to recommit after holdback" >&2
    echo "$commit_output" >&2
    cd "$original_dir"
    exit 1
  fi
  committed=true
  echo "$commit_output"
  ((push_attempt++))
done

cd "$original_dir"

gitty_report_partial

if [[ "$nothing_to_commit" == true && "$push_up_to_date" == true ]]; then
  if [[ ${#gitty_held_paths[@]} -gt 0 ]]; then
    echo "🟢 - Remote synced (${#gitty_held_paths[@]} path(s) still held back locally)"
  else
    echo "🟢 - Nothing to commit or push — remote synced"
  fi
elif [[ "$committed" == true ]]; then
  if [[ ${#gitty_held_paths[@]} -gt 0 ]]; then
    echo "🟢 - Partial commit/push from $root_dir"
  else
    echo "🟢 - Successfully synced (additive) from $root_dir"
  fi
elif [[ "$nothing_to_commit" == true ]]; then
  echo "🟢 - Synced pending commits from $root_dir"
else
  echo "🟢 - Successfully added, committed, and pushed from $root_dir"
fi
