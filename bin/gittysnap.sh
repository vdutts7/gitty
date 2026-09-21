#!/usr/bin/env zsh
# gittysnap - snapshot-first sync. Never strands a worktree, never loses work.
# Part of @vd7/gitty - https://github.com/vdutts7/gitty
#
# Problem it solves:
#   A solo dev with two machines (laptop + desktop, mac + WSL) edits the same
#   repo from both. The usual sync is `git pull --rebase` then push. When both
#   sides touched the same file, that rebase stops mid-flight: HEAD detached,
#   worktree half-applied, work sitting in an autostash that may itself fail to
#   reapply. The machine is now stuck, and the *other* machine's work is still
#   only on the other machine. One conflicted file blocks everything.
#
#   The failure is structural, not bad luck. Rebase rewrites your commits onto
#   a new base, so it must stop and ask on every textual disagreement, and while
#   stopped your work exists only as loose objects and index state.
#
#   gittysnap inverts the order: SNAPSHOT FIRST, resolve second.
#     1. commit everything local (a commit is durable; a stash is a gamble)
#     2. push that commit to a timestamped snapshot branch on the remote
#        -> local work is off-machine and recoverable BEFORE any merge is tried
#     3. only then integrate, via `merge --no-ff` (never rebase: --no-ff keeps
#        both sides reachable as commit parents, so nothing can be orphaned)
#     4. if the merge conflicts, ABORT it cleanly and stop with a clean worktree
#        -> you are never left mid-merge, and the snapshot is already pushed
#
#   Net effect: a conflict costs you a resolution, not a stranded machine. Both
#   machines' work is always on the remote regardless of whether it merged.
#
# Subcommands:
#   sync   [repo]   snapshot -> push snapshot -> merge -> push (default)
#   snap   [repo]   snapshot + push snapshot only; no integration attempted
#   list   [repo]   list snapshot branches, local and remote
#   reap   [repo]   delete snapshot branches already merged into the current branch
#
# Environment:
#   GITTYSNAP_PREFIX     snapshot branch namespace (default: snap)
#   GITTYSNAP_REMOTE     remote name (default: origin)
#   GITTYSNAP_NO_PUSH=1  local snapshots only; skip all network operations
#   GITTYSNAP_KEEP=N     keep N most recent snapshots per branch on reap (default: 10)

setopt pipefail 2>/dev/null || true

typeset -g PREFIX="${GITTYSNAP_PREFIX:-snap}"
typeset -g REMOTE="${GITTYSNAP_REMOTE:-origin}"
typeset -g KEEP="${GITTYSNAP_KEEP:-10}"

# ---------- Help ----------
show_help() {
  cat << EOF
Usage: gittysnap [command] [root_dir]

Snapshot-first sync for solo devs working across multiple machines. Commits and
pushes a timestamped snapshot BEFORE attempting any integration, so a conflict
never strands the worktree and never traps work on one machine.

Commands:
  sync   [root_dir]  snapshot, push snapshot, merge remote, push (default)
  snap   [root_dir]  snapshot and push snapshot only; no merge attempted
  list   [root_dir]  list snapshot branches (local + remote)
  reap   [root_dir]  delete snapshots already merged into the current branch

Arguments:
  root_dir  Absolute path to git repo (defaults to \$PWD)

Environment:
  GITTYSNAP_PREFIX     snapshot branch namespace (default: snap)
  GITTYSNAP_REMOTE     remote name (default: origin)
  GITTYSNAP_NO_PUSH=1  local snapshots only, no network
  GITTYSNAP_KEEP=N     snapshots to retain per branch on reap (default: 10)

Examples:
  gittysnap                      # sync \$PWD
  gittysnap sync /path/to/repo
  gittysnap snap                 # panic button: get my work off this machine
  gittysnap list
  gittysnap reap

Why not rebase:
  Rebase rewrites commits onto a new base, so it must stop on every textual
  disagreement, leaving a detached HEAD and a half-applied worktree. gittysnap
  uses merge --no-ff, which keeps both sides reachable as parents, and aborts
  cleanly on conflict rather than leaving you mid-operation.

EOF
  exit 0
}

# ---------- Arg parsing ----------
typeset -a positional=()
for arg in "$@"; do
  case "$arg" in
    -h|--help) show_help ;;
    *) positional+=("$arg") ;;
  esac
done

typeset CMD="${positional[1]:-sync}"
typeset ROOT="${positional[2]:-}"

# Allow `gittysnap /path/to/repo` with the command omitted.
case "$CMD" in
  sync|snap|list|reap) ;;
  *)
    if [[ -d "$CMD" ]]; then
      ROOT="$CMD"
      CMD="sync"
    else
      echo "🔴 - Unknown command: $CMD (expected sync, snap, list, or reap)" >&2
      exit 1
    fi
    ;;
esac

ROOT="${ROOT:-$PWD}"
[[ -d "$ROOT" ]] || { echo "🔴 - Not a directory: $ROOT" >&2; exit 1 }
cd "$ROOT" || { echo "🔴 - Failed to cd to $ROOT" >&2; exit 1 }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "🔴 - Not a git repo: $ROOT" >&2; exit 1 }

# Refuse to run on top of an operation already in progress. Doing so is how a
# half-finished rebase gets buried under a second one.
typeset GITDIR
GITDIR="$(git rev-parse --git-dir)"
if [[ -d "$GITDIR/rebase-merge" || -d "$GITDIR/rebase-apply" ]]; then
  echo "🔴 - A rebase is already in progress in this repo." >&2
  echo "     Finish or abort it first:  git rebase --abort" >&2
  exit 1
fi
if [[ -f "$GITDIR/MERGE_HEAD" ]]; then
  echo "🔴 - A merge is already in progress in this repo." >&2
  echo "     Finish or abort it first:  git merge --abort" >&2
  exit 1
fi
if [[ -f "$GITDIR/CHERRY_PICK_HEAD" ]]; then
  echo "🔴 - A cherry-pick is already in progress in this repo." >&2
  echo "     Finish or abort it first:  git cherry-pick --abort" >&2
  exit 1
fi

typeset BRANCH
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
if [[ "$BRANCH" == "HEAD" ]]; then
  echo "🔴 - Detached HEAD; refusing to act. Check out a branch first." >&2
  exit 1
fi

typeset TS
TS="$(date -u +%Y%m%dT%H%M%SZ)"
typeset HOSTTAG
HOSTTAG="$(hostname -s 2>/dev/null || echo unknown)"
HOSTTAG="${HOSTTAG//[^a-zA-Z0-9._-]/-}"
# Deliberately NOT final yet. A name built only from host+timestamp collides when
# two syncs land in the same second, and second-granularity collisions are common
# in scripted or back-to-back runs. The short SHA is appended once the snapshot
# commit exists, which makes the ref content-addressed and collision-free.
typeset SNAPBRANCH="${PREFIX}/${BRANCH}/${HOSTTAG}/${TS}"

finalize_snapbranch() {
  SNAPBRANCH="${PREFIX}/${BRANCH}/${HOSTTAG}/${TS}-$(git rev-parse --short HEAD 2>/dev/null)"
}

typeset -i HAS_REMOTE=0
if [[ "${GITTYSNAP_NO_PUSH:-}" != 1 ]] && git remote get-url "$REMOTE" >/dev/null 2>&1; then
  HAS_REMOTE=1
fi

# ---------- snapshot ----------
# A commit is durable and pushable. A stash is local-only, unnamed, and easy to
# lose, which is exactly why doctrine treats it as a gamble rather than a backup.
snapshot_local() {
  if [[ -z "$(git status --porcelain)" ]]; then
    echo "ℹ️  - Worktree clean; nothing to snapshot"
    return 0
  fi

  echo "🟡 - Snapshotting working tree..."
  git add -A || { echo "🔴 - Failed to stage" >&2; return 1 }

  git commit -q -m "-------[gittysnap] snapshot ${HOSTTAG} ${TS}-------" || {
    echo "🔴 - Failed to commit snapshot" >&2
    return 1
  }
  echo "🟢 - Snapshot committed: $(git rev-parse --short HEAD)"
  return 0
}

# Push the snapshot ref BEFORE integrating. This is the whole point: after this
# succeeds, local work exists on the remote no matter what the merge does.
push_snapshot() {
  finalize_snapbranch
  (( HAS_REMOTE )) || { echo "ℹ️  - No remote/push disabled; snapshot is local only"; return 0 }

  echo "🟡 - Pushing snapshot branch..."
  # Never force. The ref is content-addressed and new every run, so a rejection
  # means something genuinely unexpected and should surface, not be overwritten.
  # Skip entirely when HEAD is already on the remote: the work is off-machine by
  # definition, and a snapshot would be pure ref clutter.
  if git rev-parse --verify -q "$REMOTE/$BRANCH" >/dev/null 2>&1 && \
     git merge-base --is-ancestor HEAD "$REMOTE/$BRANCH" 2>/dev/null; then
    echo "ℹ️  - HEAD already on $REMOTE; no snapshot needed"
    return 0
  fi

  if git push -q "$REMOTE" "HEAD:refs/heads/$SNAPBRANCH" 2>/dev/null; then
    echo "🟢 - Snapshot pushed: $SNAPBRANCH"
    echo "     work is now off this machine and recoverable"
    return 0
  fi

  echo "⚠️  - Could not push snapshot (offline or remote rejected)" >&2
  git branch -f "$SNAPBRANCH" HEAD 2>/dev/null && \
    echo "🟡 - Kept local snapshot branch: $SNAPBRANCH"
  return 0
}

# ---------- integrate ----------
integrate() {
  (( HAS_REMOTE )) || { echo "ℹ️  - No remote; skipping integration"; return 0 }

  echo "🟡 - Fetching $REMOTE..."
  git fetch -q "$REMOTE" 2>/dev/null || {
    echo "⚠️  - Fetch failed (offline?); snapshot is safe, integration skipped" >&2
    return 0
  }

  git rev-parse --verify -q "$REMOTE/$BRANCH" >/dev/null 2>&1 || {
    echo "ℹ️  - $REMOTE/$BRANCH does not exist yet; nothing to integrate"
    return 0
  }

  typeset -i behind
  behind=$(git rev-list --count "HEAD..$REMOTE/$BRANCH" 2>/dev/null || echo 0)
  if (( behind == 0 )); then
    echo "🟢 - Already up to date with $REMOTE/$BRANCH"
    return 0
  fi

  echo "🟡 - Merging $REMOTE/$BRANCH ($behind commit(s) behind)..."
  # --no-ff, never rebase: both sides stay reachable through commit parents, so
  # no commit can be orphaned by the integration itself.
  if git merge --no-ff --no-edit "$REMOTE/$BRANCH" -m "merge: integrate $REMOTE/$BRANCH via gittysnap" >/dev/null 2>&1; then
    echo "🟢 - Merged cleanly"
    return 0
  fi

  # Conflict. Abort rather than leave a half-merged worktree, and verify the
  # abort actually worked instead of assuming it. A silently failed abort is
  # precisely how a machine ends up stranded while being told it is fine.
  echo "⚠️  - Merge conflict; aborting to keep the worktree clean" >&2
  if ! git merge --abort 2>/dev/null; then
    echo "🔴 - merge --abort FAILED. The worktree is mid-merge." >&2
    echo "     Your snapshot is safe at: $SNAPBRANCH" >&2
    echo "     Recover with:  git merge --abort   (or)  git reset --merge" >&2
    return 2
  fi

  typeset -a conflicted
  conflicted=("${(@f)$(git diff --name-only --diff-filter=U 2>/dev/null)}")

  echo "🟡 - Worktree restored; nothing is stranded"
  echo ""
  echo "   Both sides are safe:"
  echo "     yours:  $SNAPBRANCH"
  echo "     theirs: $REMOTE/$BRANCH"
  echo ""
  echo "   Resolve when convenient:"
  echo "     git merge --no-ff $REMOTE/$BRANCH"
  echo ""
  echo "   Ledger conflicts (.ndjson/.jsonl) can auto-resolve: gittyunion install"
  return 2
}

push_branch() {
  (( HAS_REMOTE )) || return 0
  typeset -i ahead
  ahead=$(git rev-list --count "$REMOTE/$BRANCH..HEAD" 2>/dev/null || echo 0)
  (( ahead == 0 )) && { echo "ℹ️  - Nothing to push"; return 0 }

  echo "🟡 - Pushing $BRANCH ($ahead commit(s) ahead)..."
  # No --force-with-lease. After a --no-ff merge the push is a fast-forward; if
  # it is rejected the remote moved again, and re-syncing is correct, not forcing.
  if git push -q "$REMOTE" "$BRANCH" 2>/dev/null; then
    echo "🟢 - Pushed $BRANCH"
    return 0
  fi
  echo "⚠️  - Push rejected; remote moved again. Re-run gittysnap." >&2
  echo "     Your work is safe at: $SNAPBRANCH" >&2
  return 1
}

# ---------- commands ----------
cmd_snap() {
  snapshot_local || return 1
  push_snapshot
  echo "🟢 - Snapshot complete"
  return 0
}

cmd_sync() {
  snapshot_local || return 1
  push_snapshot
  integrate
  typeset -i rc=$?
  (( rc == 2 )) && return 2
  push_branch || return 1
  echo "🟢 - Sync complete"
  return 0
}

cmd_list() {
  echo "📸 Local snapshots:"
  git for-each-ref --format='   %(refname:short)  %(committerdate:relative)' \
    "refs/heads/$PREFIX/**" 2>/dev/null || true
  if (( HAS_REMOTE )); then
    echo "📸 Remote snapshots:"
    git for-each-ref --format='   %(refname:short)  %(committerdate:relative)' \
      "refs/remotes/$REMOTE/$PREFIX/**" 2>/dev/null || true
  fi
  return 0
}

# Reaping removes branch names, never recoverability. Every distinct local or
# remote tip is retained under a pushed, verified annotated tag before deletion.
ensure_recovery_tag() {
  typeset tag_name="$1" tip_sha="$2" source_kind="$3" source_ref="$4" timestamp="$5"
  typeset message existing_tip local_tag_object remote_tag_object
  message="gittysnap-retire/1
branch: $source_ref
source: $source_kind
tip: $tip_sha
retired_at_utc: $timestamp
head_at_retirement: $(git rev-parse HEAD)
restore: git branch '$source_ref' '$tag_name^{}'"

  if git show-ref --verify --quiet "refs/tags/$tag_name"; then
    existing_tip=$(git rev-parse "$tag_name^{}")
    [[ "$existing_tip" == "$tip_sha" ]] || {
      echo "🔴 - Recovery tag collision: $tag_name" >&2
      return 1
    }
  else
    git tag -a "$tag_name" "$tip_sha" -m "$message" || return 1
  fi

  if (( HAS_REMOTE )); then
    git push -q "$REMOTE" "refs/tags/${tag_name}:refs/tags/${tag_name}" || return 1
    local_tag_object=$(git rev-parse "refs/tags/$tag_name")
    remote_tag_object=$(git ls-remote "$REMOTE" "refs/tags/$tag_name" | awk 'NR == 1 { print $1 }')
    [[ "$remote_tag_object" == "$local_tag_object" ]] || {
      echo "🔴 - Remote recovery tag verification failed: $tag_name" >&2
      return 1
    }
  fi
}

retire_snapshot_ref() {
  typeset ref="$1" local_tip remote_tip="" timestamp local_tag remote_tag
  local_tip=$(git rev-parse --verify "refs/heads/$ref^{commit}") || return 1
  timestamp=$(date -u +%Y%m%dT%H%M%SZ)
  local_tag="recovery/deleted-branches/$ref/${timestamp}-local-${local_tip[1,12]}"
  ensure_recovery_tag "$local_tag" "$local_tip" "local" "$ref" "$timestamp" || return 1

  if (( HAS_REMOTE )); then
    remote_tip=$(git ls-remote --heads "$REMOTE" "refs/heads/$ref" 2>/dev/null | awk 'NR == 1 { print $1 }')
    if [[ -n "$remote_tip" && "$remote_tip" != "$local_tip" ]]; then
      if ! git cat-file -e "$remote_tip^{commit}" 2>/dev/null; then
        git fetch -q --no-tags "$REMOTE" "refs/heads/$ref" || return 1
        [[ "$(git rev-parse FETCH_HEAD)" == "$remote_tip" ]] || {
          echo "🔴 - Remote tip changed while archiving $REMOTE/$ref" >&2
          return 1
        }
      fi
      remote_tag="recovery/deleted-branches/$ref/${timestamp}-remote-${remote_tip[1,12]}"
      ensure_recovery_tag "$remote_tag" "$remote_tip" "remote:$REMOTE" "$ref" "$timestamp" || return 1
    fi
  fi

  git branch -D -- "$ref" >/dev/null || return 1
  if [[ -n "$remote_tip" ]]; then
    if ! git push -q --force-with-lease="refs/heads/$ref:$remote_tip" "$REMOTE" ":refs/heads/$ref"; then
      git branch "$ref" "$local_tip" >/dev/null 2>&1 || true
      echo "🔴 - Remote deletion raced or failed; restored local branch: $ref" >&2
      return 1
    fi
  fi

  echo "   🗑️  $ref"
  echo "   🛟  $local_tag"
  [[ -n "$remote_tag" ]] && echo "   🛟  $remote_tag"
}

# Only retire refs proven to be ancestors of HEAD and beyond the keep window.
cmd_reap() {
  typeset -a merged=()
  typeset ref
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    git merge-base --is-ancestor "$ref" HEAD 2>/dev/null && merged+=("$ref")
  done < <(git for-each-ref --format='%(refname:short)' --sort=-committerdate "refs/heads/$PREFIX/**" 2>/dev/null)

  if (( ${#merged[@]} <= KEEP )); then
    echo "ℹ️  - ${#merged[@]} merged snapshot(s), keeping $KEEP; nothing to reap"
    return 0
  fi

  typeset -a doomed=("${merged[@]:$KEEP}")
  echo "🟡 - Reaping ${#doomed[@]} merged snapshot(s) (keeping $KEEP most recent)..."
  for ref in "${doomed[@]}"; do
    retire_snapshot_ref "$ref" || {
      echo "🔴 - Reap stopped; branch remains recoverable: $ref" >&2
      return 1
    }
  done
  echo "🟢 - Reap complete"
  return 0
}

case "$CMD" in
  sync) cmd_sync ;;
  snap) cmd_snap ;;
  list) cmd_list ;;
  reap) cmd_reap ;;
esac
exit $?
