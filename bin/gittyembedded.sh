#!/usr/bin/env zsh
# One command: git add, commit, force push — including submodules. Run from any directory
# Part of @vd7/gitty - https://github.com/vdutts7/gitty

setopt pipefail 2>/dev/null || true
set -eo pipefail

# ---------- Cleanup handler ----------
cleanup() {
  local exit_code=$?
  mkdir -p /tmp/_deleteme
  setopt localoptions nullglob 2>/dev/null || true
  local tmp_files=(/tmp/script_$$_*)
  [[ ${#tmp_files[@]} -gt 0 ]] && mv "${tmp_files[@]}" /tmp/_deleteme/ 2>/dev/null || true
  exit $exit_code
}
trap cleanup EXIT ERR INT TERM

# ---------- Help ----------
show_help() {
  cat << EOF
Usage: gittyembedded [commit_mssg] [root_dir]

One command: git add, commit, force push — recursing into submodules first.
Commits each dirty submodule, then commits and pushes the parent repo.

Arguments:
  commit_mssg  Commit message (prompts if not provided; used for both submodules and parent)
  root_dir     Absolute path to git repo (prompts if not provided, defaults to \$PWD)

Examples:
  gittyembedded "sync all" /path/to/repo
  gittyembedded  # Will prompt for both parameters

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

[ -z "$commit_mssg" ] && {
  echo -n "Enter commit message [default: ..]: "
  read commit_mssg
  [ -z "$commit_mssg" ] && commit_mssg=".."
}

[ -z "$root_dir" ] && {
  echo -n "Enter root directory (absolute path) [default: $PWD]: "
  read root_dir
  [ -z "$root_dir" ] && root_dir="$PWD"
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

[ ! -d "$root_dir" ] && {
  echo "🔴 - Directory does not exist: $root_dir" >&2
  exit 1
}

[ ! -d "$root_dir/.git" ] && [ ! -f "$root_dir/.git" ] && {
  echo "🔴 - Not a git repository: $root_dir" >&2
  exit 1
}

original_dir="$PWD"

cd "$root_dir" || {
  echo "🔴 - Failed to change to directory: $root_dir" >&2
  exit 1
}

# ---------- Init / update submodules ----------
if [[ -f ".gitmodules" ]]; then
  echo "🟡 - Initializing and updating submodules..."
  git submodule update --init --recursive || {
    echo "🔴 - Failed to initialize submodules" >&2
    cd "$original_dir"
    exit 1
  }

  # ---------- Commit each dirty submodule ----------
  echo "🟡 - Processing submodules..."
  git submodule foreach --recursive '
    if [ -n "$(git status --porcelain)" ]; then
      echo "🟡 - Staging changes in submodule: $name"
      git add .
      git commit -m "'"$commit_mssg"'" || true
      git push -f || echo "⚠️  - Push failed for submodule $name (may not have remote)"
    else
      echo "🟢 - Submodule clean: $name"
    fi
  ' || true
else
  echo "🟡 - No .gitmodules found — treating as normal repo"
fi

# ---------- Parent repo ----------
echo "🟡 - Staging all changes in $root_dir..."
git add . || {
  echo "🔴 - Failed to stage changes" >&2
  cd "$original_dir"
  exit 1
}

echo "🟡 - Committing changes..."
commit_output=$(git commit -m "$commit_mssg" 2>&1) || {
  if echo "$commit_output" | grep -q "nothing to commit"; then
    echo "🟢 - Nothing to commit, working tree clean"
    cd "$original_dir"
    exit 0
  fi
  echo "🔴 - Failed to commit changes" >&2
  echo "$commit_output" >&2
  cd "$original_dir"
  exit 1
}
echo "$commit_output"

echo "🟡 - Force pushing to remote..."
git push -f || {
  echo "🔴 - Failed to push changes" >&2
  cd "$original_dir"
  exit 1
}

cd "$original_dir"
echo "🟢 - Successfully added, committed, and pushed changes (with submodules) from $root_dir"
