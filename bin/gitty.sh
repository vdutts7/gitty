#!/usr/bin/env zsh
# One command: git add, commit, force push. Run from any directory
# Part of @vd7/gitty - https://github.com/vdutts7/gitty

setopt errexit pipefail

# ---------- Load environment (optional; no-op if absent) ----------
ENV_FILE="${GITTY_ENV:-$HOME/scripts/.env}"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

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

    if echo "$output" | grep -q 'BLOCKED - staged changes add em dashes'; then
      echo "🔴 - check-em-dashes — em dashes in staged diff"
    elif echo "$output" | grep -q 'em-dash check skipped'; then
      echo "🟢 - check-em-dashes — skipped (EM_DASH_APPROVE)"
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

# ---------- Help ----------
show_help() {
  cat << EOF
Usage: gitty [commit_mssg] [root_dir]

Git add, commit, and force push in one command.

Arguments:
  commit_mssg  Commit message (prompts if not provided)
  root_dir     Absolute path to git repo (prompts if not provided, defaults to \$PWD)

Examples:
  gitty "fix bug" /path/to/repo
  gitty  # Will prompt for both parameters

EOF
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) show_help ;;
  esac
done

commit_mssg="$1"
root_dir="$2"

[[ -z "$commit_mssg" ]] && {
  echo -n "Enter commit message [default: ..]: "
  read commit_mssg
  [[ -z "$commit_mssg" ]] && commit_mssg=".."
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
  [[ -x "$bust" ]] || bust="${CURTOOLS:-$HOME/.cursor/tools}/git/readme-cache-bust.sh"
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

echo "🟡 - Staging all changes in $root_dir..."
git add . || {
  echo "🔴 - Failed to stage changes" >&2
  cd "$original_dir"
  exit 1
}

committed=false
nothing_to_commit=false

echo "🟡 - Committing changes..."
unsetopt errexit
commit_output=$(git commit -m "$commit_mssg" 2>&1)
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

push_up_to_date=false

echo "🟡 - Force pushing to remote..."
unsetopt errexit
push_output=$(git push -f 2>&1)
push_status=$?
setopt errexit

if [[ $push_status -eq 0 ]]; then
  if echo "$push_output" | grep -qiE 'everything up-to-date|up to date'; then
    push_up_to_date=true
    echo "🟢 - Nothing to push (remote up-to-date)"
  else
    echo "$push_output"
  fi
  gitty_report_hooks pre-push "$push_output" 0
else
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

cd "$original_dir"

if [[ "$nothing_to_commit" == true && "$push_up_to_date" == true ]]; then
  echo "🟢 - Nothing to commit or push — remote synced"
elif [[ "$committed" == true ]]; then
  echo "🟢 - Successfully committed and force pushed from $root_dir"
elif [[ "$nothing_to_commit" == true ]]; then
  echo "🟢 - Force pushed pending commits from $root_dir"
else
  echo "🟢 - Successfully added, committed, and pushed from $root_dir"
fi
