#!/usr/bin/env zsh
# Quick health check for a git repo. Run from any directory
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
Usage: gittyhealth [root_dir]

Quick health check for a git repository. Reports branch, remote, status, stashes, recent commits, repo size, and potential issues.

Arguments:
  root_dir  Absolute path to git repo (prompts if not provided, defaults to \$PWD)

Examples:
  gittyhealth /path/to/repo
  gittyhealth  # Will prompt or default to \$PWD

EOF
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) show_help ;;
  esac
done

root_dir="$1"

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

issues=0

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  gittyhealth — $root_dir"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ---------- Branch ----------
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "DETACHED")
echo "📌 Branch:  $branch"
[[ "$branch" == "DETACHED" ]] && { echo "   ⚠️  HEAD is detached"; issues=$((issues + 1)); }

# ---------- Remote ----------
remote_url=$(git remote get-url origin 2>/dev/null || echo "none")
echo "🔗 Remote:  $remote_url"
[[ "$remote_url" == "none" ]] && { echo "   ⚠️  No remote 'origin' configured"; issues=$((issues + 1)); }

# ---------- Upstream tracking ----------
tracking=$(git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null || echo "none")
echo "📡 Tracks:  $tracking"
[[ "$tracking" == "none" ]] && { echo "   ⚠️  No upstream tracking branch set"; issues=$((issues + 1)); }

# ---------- Ahead / behind ----------
if [[ "$tracking" != "none" ]]; then
  ahead=$(git rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)
  behind=$(git rev-list --count "HEAD..@{u}" 2>/dev/null || echo 0)
  echo "📊 Ahead:   $ahead  |  Behind: $behind"
  [[ $behind -gt 0 ]] && { echo "   ⚠️  Branch is behind upstream by $behind commit(s)"; issues=$((issues + 1)); }
fi

echo ""

# ---------- Working tree status ----------
staged=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
modified=$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')
untracked=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

echo "📂 Staged:     $staged file(s)"
echo "   Modified:   $modified file(s)"
echo "   Untracked:  $untracked file(s)"
[[ $((staged + modified + untracked)) -gt 0 ]] && { echo "   ⚠️  Working tree is dirty"; issues=$((issues + 1)); }

# ---------- Stashes ----------
stash_count=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
echo "📦 Stashes:    $stash_count"
[[ $stash_count -gt 0 ]] && echo "   ℹ️  You have stashed changes"

echo ""

# ---------- Recent commits ----------
echo "🕒 Last 5 commits:"
git log --oneline -5 2>/dev/null | while IFS= read -r line; do
  echo "   $line"
done

echo ""

# ---------- Repo size ----------
git_dir=$(git rev-parse --git-dir 2>/dev/null)
if [[ -d "$git_dir" ]]; then
  repo_size=$(du -sh "$git_dir" 2>/dev/null | cut -f1 | tr -d ' ')
  echo "💾 .git size:  $repo_size"
fi

# ---------- Large files in history ----------
large_file_count=$(git rev-list --objects --all 2>/dev/null | git cat-file --batch-check='%(objecttype) %(objectsize) %(rest)' 2>/dev/null | awk '/^blob/ && $2 > 10485760 { count++ } END { print count+0 }')
[[ $large_file_count -gt 0 ]] && {
  echo "   ⚠️  $large_file_count blob(s) > 10 MB in history (consider git-lfs)"
  issues=$((issues + 1))
}

# ---------- Submodules ----------
if [[ -f ".gitmodules" ]]; then
  sub_count=$(git submodule status 2>/dev/null | wc -l | tr -d ' ')
  echo "🔩 Submodules: $sub_count"
  dirty_subs=$(git submodule status 2>/dev/null | grep '^+' | wc -l | tr -d ' ')
  [[ $dirty_subs -gt 0 ]] && { echo "   ⚠️  $dirty_subs submodule(s) out of sync"; issues=$((issues + 1)); }
fi

# ---------- LFS ----------
if command -v git-lfs &>/dev/null && git lfs env &>/dev/null; then
  lfs_tracked=$(git lfs ls-files 2>/dev/null | wc -l | tr -d ' ')
  echo "📎 LFS files:  $lfs_tracked"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $issues -eq 0 ]]; then
  echo "  🟢 Healthy — no issues found"
else
  echo "  🟡 $issues issue(s) detected"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd "$original_dir"
exit 0
