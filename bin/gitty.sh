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

# ---------- Banned operations gate (godelify: gitty-destructive-op-ban, exit 96) ----------
# Runtime interception, not prose. shim-as-a-log on violation.
gitty_assert_no_banned_op() {
  local cmd="$1"
  case "$cmd" in
    *stash*)
      printf '🔴 gitty: git stash is banned (exit 96)\n  run: git reset HEAD -- <path>  (unstage) or gitty_safe_snapshot (backup)\n' >&2
      return 96 ;;
    *rebase*)
      printf '🔴 gitty: git rebase is banned (exit 96)\n  run: gitty uses merge-only sync via gitty_additive_integrate\n' >&2
      return 96 ;;
    *reset*--hard*)
      printf '🔴 gitty: git reset --hard is banned (exit 96)\n  run: git checkout -- <path>  (per-file) or gitty_safe_snapshot + manual fix\n' >&2
      return 96 ;;
  esac
  return 0
}

# ---------- Additive sync (merge-only integrate) ----------
# Sync := additive_git_integrate(origin/$branch). One primitive replaces the
# prior rebase + drip + autoheal + WIP-snapshot machinery. Conflicts route through
# permitted_additive_resolvers (config-driven) or park on a first-class ref.

# 0 = clean, 1 = conflict/unmerged markers present
gitty_working_tree_has_conflict() {
  local unmerged
  unmerged=$(git ls-files -u 2>/dev/null | head -c1)
  [[ -n "$unmerged" ]] && return 0
  # `git diff --check` reports leftover conflict markers (rc=2) and whitespace
  # errors (rc=1). Only conflict markers should trip this guard, so scan output
  # rather than trust rc alone. Do NOT combine with --quiet: --quiet short-
  # circuits on the first diff regardless of --check.
  local check_out
  check_out=$(git -c color.ui=never diff --check 2>/dev/null; git -c color.ui=never diff --cached --check 2>/dev/null)
  [[ "$check_out" == *"conflict marker"* ]] && return 0
  return 1
}

# 0 = a merge/rebase/cherry-pick is mid-flight, 1 = none
gitty_rebase_in_progress() {
  local gd
  gd=$(git rev-parse --git-dir 2>/dev/null) || return 1
  [[ -d "$gd/rebase-merge" ]] && return 0
  [[ -d "$gd/rebase-apply" ]] && return 0
  [[ -f "$gd/MERGE_HEAD" ]]  && return 0
  [[ -f "$gd/CHERRY_PICK_HEAD" ]] && return 0
  return 1
}

# Merge-state commit: structurally proves MERGE_HEAD exists before bypassing
# stale-base guard. Gate is filesystem state (outside agent decision plane),
# not an env var the agent can set. shim-as-a-log on violation.
gitty_merge_commit() {
  local gd
  gd=$(git rev-parse --git-dir 2>/dev/null) || return 1
  if [[ ! -f "$gd/MERGE_HEAD" ]]; then
    printf '🔴 gitty: merge commit attempted outside merge state (exit 95)\n  run: use gitty_additive_integrate, not manual merge commit\n' >&2
    return 1
  fi
  SKIP_STALE_BASE=1 git commit "$@"
}

# Snapshot HEAD onto a first-class ref (safe_snapshot). Durable,
# pushable, gc-safe. NEVER git stash.
gitty_safe_snapshot() {
  local kind="${1:-integrate}"
  local snap="bak/${kind}-$(date -u +%Y%m%dT%H%M%SZ)"
  git branch "$snap" HEAD 2>/dev/null || true
  git push origin "$snap" 2>/dev/null || echo "🔴 - Failed to push snapshot $snap to remote" >&2
  echo "🟡 - Safe snapshot: $snap"
}

# Load $ROOT/.gitty/additive-resolvers.yaml (tolerant, zsh-native line parser).
typeset -a _gitty_resolver_per_host_paths=()
typeset -a _gitty_resolver_per_host_globs=()
typeset -a _gitty_resolver_union_globs=()
typeset _gitty_resolver_union_key="ts"

gitty_load_additive_resolvers() {
  _gitty_resolver_per_host_paths=()
  _gitty_resolver_per_host_globs=()
  _gitty_resolver_union_globs=()
  _gitty_resolver_union_key="ts"
  local cfg="${1:-.gitty/additive-resolvers.yaml}"
  [[ -f "$cfg" ]] || return 0
  local section="" sublist="" line val
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    if [[ "$line" == per_host:* ]]; then section="per_host"; sublist=""; continue; fi
    if [[ "$line" == semantic_union:* ]]; then section="union"; sublist=""; continue; fi
    if [[ "$line" =~ ^[[:space:]]+paths:[[:space:]]*$ ]]; then sublist="paths"; continue; fi
    if [[ "$line" =~ ^[[:space:]]+globs:[[:space:]]*$ ]]; then sublist="globs"; continue; fi
    if [[ "$line" =~ ^[[:space:]]+key_field:[[:space:]]* ]]; then
      val="${line#*key_field:}"; val="${val//[[:space:]]/}"; val="${val//\"/}"; val="${val//\'/}"
      _gitty_resolver_union_key="$val"
      continue
    fi
    if [[ "$line" == *-\ * ]]; then
      val="${line#*- }"; val="${val## }"; val="${val%% }"; val="${val//\"/}"; val="${val//\'/}"
      case "$section:$sublist" in
        per_host:paths) _gitty_resolver_per_host_paths+=("$val") ;;
        per_host:globs) _gitty_resolver_per_host_globs+=("$val") ;;
        union:globs)    _gitty_resolver_union_globs+=("$val") ;;
      esac
    fi
  done < "$cfg"
}

gitty_match_per_host() {
  local p="$1" entry
  for entry in "${_gitty_resolver_per_host_paths[@]}"; do
    [[ "$p" == "$entry" ]] && return 0
  done
  for entry in "${_gitty_resolver_per_host_globs[@]}"; do
    [[ "$p" == ${~entry} ]] && return 0
  done
  return 1
}

gitty_match_union() {
  local p="$1" entry
  for entry in "${_gitty_resolver_union_globs[@]}"; do
    [[ "$p" == ${~entry} ]] && return 0
  done
  return 1
}

# Apply permitted_additive_resolvers to unmerged paths in an in-flight merge.
# per_host_byte_authoritative -> checkout --ours + add
# semantic_union -> union + dedupe + stable-sort by key_field
# Returns 0 iff every unmerged path resolved (index fully staged).
gitty_apply_additive_resolvers() {
  local audit=/tmp/gitty-resolver-audit-$$.log; : >"$audit"
  local -a unmerged=()
  local p ours theirs
  while IFS= read -r p; do [[ -n "$p" ]] && unmerged+=("$p"); done \
    < <(git diff --name-only --diff-filter=U 2>/dev/null)
  (( ${#unmerged[@]} == 0 )) && return 0
  local -a unresolved=()
  for p in "${unmerged[@]}"; do
    ours=$(git rev-parse ":2:$p" 2>/dev/null || echo -)
    theirs=$(git rev-parse ":3:$p" 2>/dev/null || echo -)
    if gitty_match_per_host "$p"; then
      if git checkout --ours -- "$p" 2>/dev/null && git add -- "$p" 2>/dev/null; then
        print -r -- "per_host_byte_authoritative $p ours=$ours theirs=$theirs" >>"$audit"
        continue
      fi
      unresolved+=("$p"); continue
    fi
    if gitty_match_union "$p" && command -v python3 >/dev/null 2>&1; then
      local out_blob=/tmp/gitty-out-$$.$RANDOM ours_blob=/tmp/gitty-ours-$$.$RANDOM theirs_blob=/tmp/gitty-theirs-$$.$RANDOM
      git show ":2:$p" >"$ours_blob" 2>/dev/null || : >"$ours_blob"
      git show ":3:$p" >"$theirs_blob" 2>/dev/null || : >"$theirs_blob"
      if python3 - "$_gitty_resolver_union_key" "$ours_blob" "$theirs_blob" "$out_blob" <<'PYEOF'
import json, sys
key, ours, theirs, out = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
seen=set(); rows=[]
for src in (ours, theirs):
    try: fh=open(src)
    except OSError: continue
    for line in fh:
        if not line.strip() or line in seen: continue
        seen.add(line)
        try: k=json.loads(line).get(key)
        except Exception: k=None
        rows.append((k if k is not None else "", len(rows), line))
rows.sort(key=lambda r:(str(r[0]), r[1]))
with open(out,"w") as f:
    for _,_,line in rows: f.write(line if line.endswith("\n") else line+"\n")
PYEOF
      then
        mv "$out_blob" "$p" 2>/dev/null && git add -- "$p" 2>/dev/null
        rm -f "$ours_blob" "$theirs_blob"
        print -r -- "semantic_union $p ours=$ours theirs=$theirs key=$_gitty_resolver_union_key" >>"$audit"
        continue
      fi
      rm -f "$out_blob" "$ours_blob" "$theirs_blob"
    fi
    unresolved+=("$p")
  done
  if (( ${#unresolved[@]} > 0 )); then
    for p in "${unresolved[@]}"; do
      gitty_record_held "$p" "unresolved conflict (no matching additive resolver)"
    done
    return 1
  fi
  return 0
}

# Park an unresolvable conflict on first-class refs, abort the merge, and
# return the branch untouched. NEVER stash. Zero data loss, non-fatal.
gitty_park_conflict() {
  local target_sha="$1"
  git merge --abort 2>/dev/null || true
  local ts snap_local snap_remote
  ts=$(date -u +%Y%m%dT%H%M%SZ)
  snap_local="bak/pending-merge-$ts"
  snap_remote="remote-snapshot/$ts"
  git branch "$snap_local" HEAD 2>/dev/null || true
  git branch "$snap_remote" "$target_sha" 2>/dev/null || true
  git push origin "$snap_local" "$snap_remote" 2>/dev/null || true
  echo "🟡 - Conflict parked: $snap_local (local HEAD) + $snap_remote ($target_sha)"
  echo "     Resolve manually; local branch untouched; nothing lost."
}

# git-crypt merge bypass: merge's internal stash runs the clean filter on every
# dirty file. If any filter invocation fails (phantom-dirty from cross-host
# decrypt), git aborts with "fatal: stash failed". Use git -c per-invocation
# overrides so .git/config is never mutated (SIGKILL-safe).
_gitty_crypt_merge() {
  local _crypt_clean
  _crypt_clean=$(git config --get filter.git-crypt.clean 2>/dev/null) || true
  if [[ -n "$_crypt_clean" && "$_crypt_clean" != "cat" ]]; then
    git -c filter.git-crypt.clean=cat -c filter.git-crypt.required=false "$@"
  else
    git "$@"
  fi
}

# additive_git_integrate: doctrinal sync of origin/$branch into HEAD.
# Returns 0 = merged (or already present), 1 = parked/stopped.
gitty_additive_integrate() {
  local branch="$1" msg="$2"
  local target_ref="origin/$branch"
  local target_sha head_before head_after base
  target_sha=$(git rev-parse --verify "${target_ref}^{commit}" 2>/dev/null) || return 0
  head_before=$(git rev-parse HEAD 2>/dev/null)
  if git merge-base --is-ancestor "$target_sha" HEAD 2>/dev/null; then
    return 0
  fi
  # Prefer ff-only: no merge commit, preserves dirty index (disjoint files),
  # and matches the stale-base hook's own prescribed fix.
  # Use _gitty_crypt_merge to bypass git-crypt filter if needed (SIGKILL-safe).
  if _gitty_crypt_merge merge --ff-only --no-edit "$target_sha" >/dev/null 2>&1; then
    head_after=$(git rev-parse HEAD 2>/dev/null)
    echo "🟢 - Additive integrate (ff): $target_ref ($target_sha) [$head_before -> $head_after]"
    return 0
  fi
  gitty_load_additive_resolvers "$root_dir/.gitty/additive-resolvers.yaml"
  gitty_safe_snapshot "pre-integrate"
  local merge_rc
  _gitty_crypt_merge merge --no-ff --no-edit "$target_sha" >/dev/null 2>&1
  merge_rc=$?
  if (( merge_rc == 0 )); then
    head_after=$(git rev-parse HEAD 2>/dev/null)
    echo "🟢 - Additive integrate: merged $target_ref ($target_sha) [$head_before -> $head_after]"
    return 0
  fi
  local resolver_rc
  gitty_apply_additive_resolvers
  resolver_rc=$?
  local audit_body
  audit_body=$(cat /tmp/gitty-resolver-audit-$$.log 2>/dev/null || true)

  if (( resolver_rc == 0 )); then
    # All conflicts resolved - commit the merge
    if gitty_merge_commit --no-edit -m "$msg

additive-git: permitted_additive_resolvers
$audit_body" >/dev/null 2>&1; then
      head_after=$(git rev-parse HEAD 2>/dev/null)
      echo "🟢 - Additive integrate: merged via resolvers [$head_before -> $head_after]"
      rm -f /tmp/gitty-resolver-audit-$$.log
      return 0
    fi
  elif [[ "${GITTY_PARTIAL:-1}" == "1" ]]; then
    # Partial resolution: some paths resolved, others held back.
    # Check if any staged (resolved) paths exist beyond the unresolved ones.
    local -a still_unmerged=()
    local p
    while IFS= read -r p; do [[ -n "$p" ]] && still_unmerged+=("$p"); done \
      < <(git diff --name-only --diff-filter=U 2>/dev/null)
    if (( ${#still_unmerged[@]} > 0 )); then
      # Unstage unresolved conflict paths, checkout --ours to clear markers,
      # then re-add as-is so the merge can commit the resolved subset.
      for p in "${still_unmerged[@]}"; do
        git checkout --ours -- "$p" 2>/dev/null || true
        git add -- "$p" 2>/dev/null || true
      done
      if gitty_merge_commit --no-edit -m "$msg

additive-git: partial drip-through (${#still_unmerged[@]} path(s) held back)
$audit_body" >/dev/null 2>&1; then
        head_after=$(git rev-parse HEAD 2>/dev/null)
        echo "🟢 - Additive integrate (partial): merged resolved subset [$head_before -> $head_after]"
        echo "🟡 - ${#still_unmerged[@]} path(s) held back - resolve manually on next commit"
        rm -f /tmp/gitty-resolver-audit-$$.log
        return 0
      fi
    fi
  fi

  rm -f /tmp/gitty-resolver-audit-$$.log
  gitty_park_conflict "$target_sha"
  return 1
}

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
  echo "🔴 - $path - held back ($reason)"
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
  local off_path

  off_path=$(printf '%s\n' "$output" | grep -oiE 'File [^[:space:]]+ is [0-9.]+ MB' | head -1 | awk '{print $2}')
  [[ -n "$off_path" ]] && { echo "$off_path"; return 0 }

  off_path=$(printf '%s\n' "$output" | grep -oiE 'remote: error: File [^[:space:]]+ is' | head -1 | awk '{print $4}')
  [[ -n "$off_path" ]] && { echo "$off_path"; return 0 }

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

# Canonicalize a pre-commit hook rejection into a specific, stable holdback
# reason instead of the mute constant "pre-commit hook rejection".
# Catalog (optional): $GITTY_HOLDBACK_CATALOG or <repo>/.gitty/holdback-reasons.json.
#   rules[].match (regex) vs the raw hook stderr -> "[code] reason" with $1..$9
#   = capture groups (+ optional fix hint). No catalog / no match -> the most
#   specific offender stderr line + exit code (never a bare constant).
gitty_holdback_reason() {
  setopt localoptions
  unsetopt errexit
  local hb_path="$1" reject="$2"
  local catalog="${GITTY_HOLDBACK_CATALOG:-${root_dir:-$PWD}/.gitty/holdback-reasons.json}"
  local canon="" line ec

  if [[ -f "$catalog" ]] && command -v python3 >/dev/null 2>&1; then
    canon=$(GITTY_HB_PATH="$hb_path" GITTY_HB_REJECT="$reject" python3 - "$catalog" <<'PY' 2>/dev/null
import json, os, re, sys
try:
    cat = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
path = os.environ.get("GITTY_HB_PATH", "")
reject = os.environ.get("GITTY_HB_REJECT", "")
for rule in cat.get("rules", []):
    pat = rule.get("match")
    if not pat:
        continue
    try:
        m = re.search(pat, reject)
    except re.error:
        continue
    if not m:
        continue
    def _sub(mm):
        try:
            return m.group(int(mm.group(1))) or ""
        except Exception:
            return ""
    reason = re.sub(r"\$([1-9])", _sub, rule.get("reason", ""))
    out = f"[{rule.get('code', 'HOLD')}] {reason}".rstrip()
    fix = rule.get("fix", "")
    if fix:
        out += f" - {fix}"
    print(out)
    break
PY
)
    if [[ -n "$canon" ]]; then
      print -r -- "$canon"
      return 0
    fi
  fi

  # Fallback: the most specific stderr line we can find for this path.
  line=$(printf '%s\n' "$reject" | grep -F -- "$hb_path" 2>/dev/null | grep -iE 'error|exit|blocked|pollution|:[0-9]+' | head -1)
  [[ -z "$line" ]] && line=$(printf '%s\n' "$reject" | grep -iE 'exit [0-9]+|error|blocked' | head -1)
  line=$(printf '%s' "$line" | sed -E 's/^[^A-Za-z0-9]+//; s/[[:space:]]+/ /g; s/[[:space:]]*$//')
  ec=$(printf '%s\n' "$reject" | grep -oiE 'exit [0-9]+' | head -1 | grep -oE '[0-9]+')
  if [[ -n "$line" ]]; then
    [[ -n "$ec" && "$line" != *"$ec"* ]] && line="$line (exit $ec)"
    print -r -- "pre-commit: $line"
  elif [[ -n "$ec" ]]; then
    print -r -- "pre-commit hook rejection (exit $ec)"
  else
    print -r -- "pre-commit hook rejection"
  fi
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
      echo "🟢 - $p - committed and pushed"
    done
  elif [[ "$committed" == true ]]; then
    echo "🟢 - commit - committed and pushed"
    pushed_count=1
  elif [[ "$nothing_to_commit" == true && "$push_up_to_date" == true ]]; then
    echo "🟢 - remote - already up to date"
  elif [[ "$nothing_to_commit" == true ]]; then
    echo "🟢 - push - pending commits synced"
  fi

  if [[ $held_count -gt 0 ]]; then
    for i in {1..$held_count}; do
      echo "🔴 - ${gitty_held_paths[$i]} - not pushed (${gitty_held_reasons[$i]})"
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
    echo "🟢 - partial success - ${pushed_ok} pushed, ${held_count} held back"
  elif [[ $held_count -gt 0 && $pushed_count -eq 0 && "$nothing_to_commit" != true ]]; then
    echo "🔴 - nothing pushed - ${held_count} path(s) held back"
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
      echo "🔴 - enforce-git-identity - blocked"
    elif echo "$output" | grep -q '\[enforce-git-identity\] OK'; then
      echo "🟢 - enforce-git-identity - OK"
    elif [[ "$hook_rc" -eq 0 ]]; then
      echo "🟢 - enforce-git-identity - passed"
    fi

    if echo "$output" | grep -q 'em dashes replaced with hyphens'; then
      echo "🟢 - check-em-dashes - fixed (em dash -> hyphen)"
    elif [[ "$hook_rc" -eq 0 ]]; then
      echo "🟢 - check-em-dashes - passed"
    fi

    if echo "$output" | grep -q 'BLOCKED - staged files under a Python venv'; then
      echo "🔴 - check-python-venv - venv paths staged"
    elif [[ "$hook_rc" -eq 0 ]]; then
      echo "🟢 - check-python-venv - passed"
    fi

    if echo "$output" | grep -q 'metadata stripped'; then
      echo "🟢 - clearmeta - metadata stripped"
    elif [[ "$hook_rc" -eq 0 ]]; then
      echo "🟢 - clearmeta - passed"
    fi

    if echo "$output" | grep -q '\[readme-cache-bust\] bumped'; then
      echo "🟢 - readme-cache-bust - img v= bumped"
    elif echo "$output" | grep -q '\[readme-cache-bust\] skip'; then
      echo "🟢 - readme-cache-bust - skipped"
    fi

    if [[ "$hook_rc" -eq 0 ]]; then
      echo "🟢 - drop-eof-newline-only - passed"
    fi

    if echo "$output" | grep -q 'COMMIT BLOCKED - not a repo collaborator'; then
      echo "🔴 - check-collaborator - not a repo collaborator"
    elif echo "$output" | grep -q '\[pre-commit\] git user.name not set'; then
      echo "🔴 - check-collaborator - git user.name not set"
    elif [[ "$hook_rc" -eq 0 ]]; then
      echo "🟢 - check-collaborator - passed"
    fi

    # Surface local.d gate failures (check-tilde, scope-proof, stale-base, ...)
    # that the fixed-hook dashboard above has no branch for.
    if [[ "$hook_rc" -ne 0 ]]; then
      local _gl
      while IFS= read -r _gl; do
        _gl=$(printf '%s' "$_gl" | sed -E 's/^[^A-Za-z0-9]+//; s/[[:space:]]+/ /g; s/[[:space:]]*$//')
        [[ -n "$_gl" ]] && echo "🔴 - gate - $_gl"
      done < <(printf '%s\n' "$output" | grep -E '\(exit [0-9]+\)' || true)
    fi

    return
  fi

  if [[ "$event" == "pre-push" ]]; then
    if echo "$output" | grep -q 'Issues found - fix before pushing'; then
      echo "🔴 - health-check - issues found"
    elif echo "$output" | grep -q 'All checks passed'; then
      echo "🟢 - health-check - all checks passed"
    elif [[ "$hook_rc" -eq 0 ]]; then
      echo "🟢 - health-check - passed"
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
  echo "usage: gitty [-h|--help] [-v|-V|--version] [commit_mssg] [root_dir]" >&2
  exit 1
}

typeset -r _GITTY_DEFAULT_MSG='-------[gitty] snapshotting repo state-------'

show_help() {
  cat << EOF
Usage: gitty [-h|--help] [-v|-V|--version] [commit_mssg] [root_dir]

Git add, commit, and force push in one command.

Options:
  -h, --help      Show this help
  -v, -V, --version   Show version

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
    -v|-V|--version) gitty_version ;;
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

# Banner is ALWAYS the subject line. If caller provided a message, it becomes
# the body beneath the banner. Agent cannot opt out - structural, not optional.
if [[ "$commit_mssg" != "$_GITTY_DEFAULT_MSG" ]]; then
  commit_mssg="${_GITTY_DEFAULT_MSG}

${commit_mssg}"
fi

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

# Fail fast on foreign-owned .git (usually root from past `sudo git`).
# Cannot auto-chown without elevating; print heal command and exit.
gitty_perm_check() {
  [[ "${GITTY_SKIP_PERM_CHECK:-0}" == "1" ]] && return 0
  local gd bad
  gd=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 0
  bad=$(find "$gd" -not -user "$(whoami)" 2>/dev/null | head -8)
  if [[ -n "$bad" ]]; then
    echo "🔴 - Foreign-owned paths under $gd (often root from sudo git)." >&2
    echo "$bad" | while IFS= read -r line; do
      [[ -n "$line" ]] && echo "     $line" >&2
    done
    echo "     heal: sudo chown -R \"\$(whoami)\" \"$gd\"" >&2
    echo "     then re-run gitty. (opt out: GITTY_SKIP_PERM_CHECK=1)" >&2
    return 1
  fi
  return 0
}

if ! gitty_perm_check; then
  cd "$original_dir"
  exit 1
fi

# Refuse to proceed if a rebase/merge/cherry-pick is mid-flight - otherwise the
# stale-base autoheal path would layer a new rebase on top of an in-progress one
# and produce genuinely unrecoverable state. Opt out with GITTY_ALLOW_INPROGRESS=1
# only if you know what you're doing (e.g. re-entering after resolving markers).
if [[ "${GITTY_ALLOW_INPROGRESS:-0}" != "1" ]] && gitty_rebase_in_progress; then
  echo "🔴 - A rebase/merge/cherry-pick is in progress in $root_dir." >&2
  echo "     Finish it (git rebase --continue / --abort, git merge --abort, etc.) or set" >&2
  echo "     GITTY_ALLOW_INPROGRESS=1 to force. Refusing to run - would compound the state." >&2
  cd "$original_dir"
  exit 1
fi

# Same for pre-existing unresolved conflict markers in the working tree.
if [[ "${GITTY_ALLOW_CONFLICTS:-0}" != "1" ]] && gitty_working_tree_has_conflict; then
  echo "🔴 - Working tree has conflict markers or unmerged paths in $root_dir." >&2
  echo "     Run 'git status', 'git diff --check', resolve, then re-run gitty." >&2
  echo "     Set GITTY_ALLOW_CONFLICTS=1 to override (not recommended - the pre-commit" >&2
  echo "     hooks may still reject the commit, and force-pushing conflict markers is" >&2
  echo "     the exact failure mode this guard exists to prevent)." >&2
  cd "$original_dir"
  exit 1
fi

# A repo can declare `merge=ndjson-union` in .gitattributes, but the driver itself
# lives in .git/config, which is NOT cloned. In a fresh clone the name resolves to
# nothing and git silently falls back to the conflicting default merge -- worse than
# having declared nothing at all. Re-register it here so the declaration is honored.
# Derivable, idempotent, and non-destructive. Opt out with GITTY_NO_UNION_AUTOINSTALL=1.
gitty_ensure_union_driver() {
  [[ "${GITTY_NO_UNION_AUTOINSTALL:-}" == 1 ]] && return 0
  [[ -f "$root_dir/.gitattributes" ]] || return 0
  grep -q 'merge=ndjson-union' "$root_dir/.gitattributes" 2>/dev/null || return 0
  [[ -z "$(git config --get merge.ndjson-union.driver 2>/dev/null)" ]] || return 0
  local union="${${(%):-%x}:A:h}/gittyunion.sh"
  [[ -x "$union" ]] || return 0
  git config merge.ndjson-union.name "union merge for append-only NDJSON ledgers" 2>/dev/null || return 0
  git config merge.ndjson-union.driver "'$union' merge %O %A %B %P" 2>/dev/null || return 0
  git config merge.ndjson-union.recursive binary 2>/dev/null || true
  echo "🟢 - Registered ndjson-union merge driver (declared in .gitattributes, missing in this clone)"
}

gitty_ensure_union_driver

gitty_bust_readme() {
  local bust="${${(%):-%x}:A:h}/readme-cache-bust.sh"
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
    echo "🟡 - Stale-base guard fired; additive-integrating origin/$branch..."
    git fetch origin "$branch" 2>/dev/null || git fetch origin 2>/dev/null || true
    unsetopt errexit
    gitty_additive_integrate "$branch" "$commit_mssg"
    ai_rc=$?
    setopt errexit
    if (( ai_rc == 0 )); then
      echo "🟢 - Autoheal integrate clean; re-staging and retrying commit..."
      git add -A || true
      if gitty_working_tree_has_conflict; then
        echo "🔴 - Conflict markers appeared during re-stage; aborting autoheal." >&2
        git reset -q HEAD -- . 2>/dev/null || true
        committed=false
      else
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
          echo "🟢 - Autohealed stale-base via additive integrate"
        fi
      fi
    else
      echo "🔴 - Additive integrate parked; local branch untouched." >&2
      echo "     See bak/pending-merge-*  +  remote-snapshot/*  for both sides." >&2
    fi
  fi

  if [[ "$committed" != true && "${GITTY_PARTIAL:-1}" == "1" ]]; then
    local -a _elim_staged=("${(@f)$(git diff --cached --name-only 2>/dev/null)}")
    if (( ${#_elim_staged} > 1 )); then
      local _reject_output="$commit_output"
      echo "🟡 - Hook rejected commit; elimination scan (${#_elim_staged} paths)" >&2
      gitty_report_hooks pre-commit "$commit_output" 1
      for _elim in "${_elim_staged[@]}"; do
        [[ -z "$_elim" ]] && continue
        git restore --staged -- "$_elim" 2>/dev/null || continue
        if git diff --cached --quiet 2>/dev/null; then
          git add -- "$_elim" 2>/dev/null
          continue
        fi
        unsetopt errexit
        commit_output=$(gitty_commit_safe "$commit_mssg")
        commit_status=$?
        setopt errexit
        if [[ $commit_status -eq 0 ]]; then
          committed=true
          echo "$commit_output"
          gitty_holdback_path "$_elim" "$(gitty_holdback_reason "$_elim" "$_reject_output")"
          gitty_report_hooks pre-commit "$commit_output" 0
          echo "🟢 - Partial commit (drip-additive): held back $_elim"
          break
        fi
        git add -- "$_elim" 2>/dev/null
      done
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
# Sync = additive_git_integrate(origin/$branch) + push. Merge-only; never rebase.
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

    integrate_parked=false
    if git rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
      echo "🟡 - Additive-integrating origin/$branch..."
      gitty_additive_integrate "$branch" "$commit_mssg"
      if (( $? != 0 )); then
        push_output="integrate parked"
        push_status=1
        integrate_parked=true
      fi
    fi

    if [[ "$integrate_parked" != true ]]; then
      echo "🟡 - Pushing to remote..."
      if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
        push_output=$(git push origin "$branch" 2>&1)
      else
        push_output=$(git push -u origin HEAD 2>&1)
      fi
      push_status=$?

      if [[ $push_status -ne 0 ]]; then
        echo "🟡 - Push rejected; re-integrating and retrying..."
        git fetch origin "$branch" 2>/dev/null || true
        gitty_additive_integrate "$branch" "$commit_mssg"
        if (( $? != 0 )); then
          push_output="integrate parked"
          push_status=1
          integrate_parked=true
        else
          push_output=$(git push origin "$branch" 2>&1)
          push_status=$?
        fi
      fi
    fi
  fi

  setopt errexit

  if [[ "${integrate_parked:-false}" == true ]]; then
    cd "$original_dir"
    exit 0   # parked = non-fatal; branch untouched; nothing lost
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
    echo "🟢 - Nothing to commit or push - remote synced"
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
