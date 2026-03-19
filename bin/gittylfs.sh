#!/usr/bin/env zsh
# One command: git add, commit, force push — with LFS tracking. Run from any directory
# Part of @vd7/gitty - https://github.com/vdutts7/gitty

setopt pipefail 2>/dev/null || true
set -eo pipefail

# ---------- Load environment (optional; for local dev / scripts/.env) ----------
ENV_FILE="${GITTY_ENV:-$HOME/scripts/.env}"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

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
Usage: gittylfs [commit_mssg] [root_dir] [lfs_patterns...]

One command: git add, commit, force push — with LFS tracking.
Ensures git-lfs is installed, tracks specified patterns (or common defaults), then adds, commits, and force pushes.

Arguments:
  commit_mssg   Commit message (prompts if not provided)
  root_dir      Absolute path to git repo (prompts if not provided, defaults to \$PWD)
  lfs_patterns  File patterns to track with LFS (e.g. "*.psd" "*.zip")
                Defaults: *.psd *.sketch *.ai *.zip *.tar.gz *.7z *.mp4 *.mov *.wav *.mp3 *.bin *.pkl *.h5 *.onnx *.pt

Examples:
  gittylfs "add assets" /path/to/repo "*.psd" "*.zip"
  gittylfs "models" /path/to/repo "*.bin" "*.onnx"
  gittylfs  # Will prompt for message & dir, track default patterns

EOF
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) show_help ;;
  esac
done

DEFAULT_LFS_PATTERNS=(
  "*.psd" "*.sketch" "*.ai"
  "*.zip" "*.tar.gz" "*.7z"
  "*.mp4" "*.mov" "*.wav" "*.mp3"
  "*.bin" "*.pkl" "*.h5" "*.onnx" "*.pt"
)

commit_mssg="$1"
root_dir="$2"
shift 2 2>/dev/null || true
lfs_patterns=("$@")
[[ ${#lfs_patterns[@]} -eq 0 ]] && lfs_patterns=("${DEFAULT_LFS_PATTERNS[@]}")

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

# ---------- Verify git-lfs ----------
if ! command -v git-lfs &>/dev/null; then
  echo "🔴 - git-lfs is not installed. Install it first: https://git-lfs.com" >&2
  exit 1
fi

original_dir="$PWD"

cd "$root_dir" || {
  echo "🔴 - Failed to change to directory: $root_dir" >&2
  exit 1
}

# ---------- Init LFS + track patterns ----------
echo "🟡 - Initializing git-lfs in $root_dir..."
git lfs install --local || {
  echo "🔴 - Failed to initialize git-lfs" >&2
  cd "$original_dir"
  exit 1
}

for pattern in "${lfs_patterns[@]}"; do
  echo "🟡 - Tracking LFS pattern: $pattern"
  git lfs track "$pattern" 2>/dev/null || true
done

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
echo "🟢 - Successfully added, committed, and pushed changes (with LFS) from $root_dir"
