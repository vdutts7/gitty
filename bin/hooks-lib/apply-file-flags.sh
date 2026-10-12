#!/usr/bin/env bash
# apply-file-flags — 1:1 sync between worktree uchg and .gitty/file-flags.json
#
#   --sync    worktree -> inventory (pre-commit): scan tracked uchg; rewrite json; optional --stage
#   --apply   inventory -> worktree (post-checkout/post-merge): reconcile 1:1
#   --unlock  clear uchg on inventory paths (or all tracked uchg if no inventory)
#
# usage: apply-file-flags.sh [--repo <path>] [--sync|--apply|--unlock] [--stage] [--quiet]
set -euo pipefail

REPO=""
MODE="apply"
QUIET=0
STAGE=0

while (( $# )); do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --apply) MODE="apply"; shift ;;
    --sync) MODE="sync"; shift ;;
    --unlock) MODE="unlock"; shift ;;
    --stage) STAGE=1; shift ;;
    --quiet|-q) QUIET=1; shift ;;
    -h|--help)
      cat >&2 <<'HELP'
usage: apply-file-flags [--repo <path>] [--sync|--apply|--unlock] [--stage] [--quiet]
  --sync    scan tracked uchg files -> rewrite .gitty/file-flags.json (pre-commit)
  --stage   with --sync: git add the inventory when it changed
  --apply   reconcile worktree to inventory 1:1 (post-checkout / post-merge); default
  --unlock  clear uchg on inventory paths (gitty sync prelude)
HELP
      exit 0 ;;
    *)
      if [[ "$1" =~ ^[0-9a-f]{7,40}$ || "$1" == "0" || "$1" == "1" ]]; then
        shift
        continue
      fi
      echo "unknown flag: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$REPO" ]]; then
  REPO="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -n "$REPO" && -d "$REPO" ]] || { echo "🔴 apply-file-flags: not a git repo" >&2; exit 1; }
REPO="$(cd "$REPO" && pwd -P)"

INVENTORY="$REPO/.gitty/file-flags.json"
_log() { (( QUIET )) || echo "$1" >&2; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  _log "🟡 apply-file-flags: non-Darwin; skip"
  exit 0
fi
command -v jq >/dev/null 2>&1 || { echo "🔴 apply-file-flags: jq required" >&2; exit 1; }
command -v chflags >/dev/null 2>&1 || { echo "🔴 apply-file-flags: chflags missing" >&2; exit 1; }

# --- helpers ---

# print relative tracked paths that currently have uchg (NUL-safe via lines; paths unlikely to have newline)
_list_tracked_uchg() {
  local f rel
  # macOS find: -flags uchg
  while IFS= read -r -d '' f; do
    rel="${f#"$REPO"/}"
    [[ "$rel" == "$f" ]] && continue
    [[ "$rel" == ".gitty/file-flags.json" ]] && continue
    case "$rel" in
      .git|/*|.|..|../*|*/..|*/../*) continue ;;
    esac
    if git -C "$REPO" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
      printf '%s\n' "$rel"
    fi
  done < <(find "$REPO" \( -path "$REPO/.git" -o -path "$REPO/.git/*" \) -prune -o \
    -flags uchg \( -type f -o -type l \) -print0 2>/dev/null)
}

_list_inventory_paths() {
  [[ -f "$INVENTORY" ]] || return 0
  jq -r '(.entries // [])[] | select((.path|type)=="string" and (.path|length)>0) | .path' "$INVENTORY"
}

_write_inventory() {
  # stdin: relative paths, one per line
  local tmp sorted
  tmp="$(mktemp)"
  sorted="$(mktemp)"
  sort -u > "$sorted"
  mkdir -p "$REPO/.gitty"
  jq -n --rawfile paths "$sorted" '
    {
      version: 1,
      entries: (
        ($paths | split("\n") | map(select(length > 0)) | unique | sort)
        | map({ path: ., flags: ["uchg"] })
      )
    }
  ' > "$tmp"
  if [[ -f "$INVENTORY" ]] && cmp -s "$tmp" "$INVENTORY"; then
    rm -f "$tmp" "$sorted"
    return 1
  fi
  mv "$tmp" "$INVENTORY"
  rm -f "$sorted"
  return 0
}

_safe_target() {
  # $1=rel -> sets TARGET global or returns 1
  local rel="$1"
  case "$rel" in
    /*|.|..|../*|*/..|*/../*) return 1 ;;
  esac
  TARGET="$REPO/$rel"
  [[ -e "$TARGET" || -L "$TARGET" ]] || return 1
  local resolved
  resolved="$(cd "$(dirname "$TARGET")" && pwd -P)/$(basename "$TARGET")"
  case "$resolved" in
    "$REPO"|"$REPO"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- modes ---

if [[ "$MODE" == "sync" ]]; then
  paths_file="$(mktemp)"
  _list_tracked_uchg | sort -u > "$paths_file"
  if [[ ! -s "$paths_file" && ! -f "$INVENTORY" ]]; then
    rm -f "$paths_file"
    _log "🟡 file-flags sync: no uchg tracked files; no inventory"
    exit 0
  fi
  if _write_inventory < "$paths_file"; then
    n="$(jq '.entries|length' "$INVENTORY")"
    _log "🟢 file-flags sync: inventory -> $n path(s)"
    if (( STAGE )); then
      git -C "$REPO" add -- ".gitty/file-flags.json"
      _log "🟢 file-flags sync: staged .gitty/file-flags.json"
    fi
  else
    _log "🟡 file-flags sync: inventory unchanged"
  fi
  rm -f "$paths_file"
  exit 0
fi

if [[ "$MODE" == "unlock" ]]; then
  ok=0; fail=0
  if [[ -f "$INVENTORY" ]]; then
    while IFS= read -r rel; do
      [[ -z "$rel" ]] && continue
      TARGET=""
      if ! _safe_target "$rel"; then
        _log "🟡 unlock skip $rel"
        continue
      fi
      if chflags nouchg "$TARGET" 2>/dev/null; then
        _log "🟢 unlock $rel"; ok=$((ok+1))
      else
        _log "🔴 unlock failed $rel"; fail=$((fail+1))
      fi
    done < <(_list_inventory_paths)
  else
    while IFS= read -r rel; do
      TARGET=""
      _safe_target "$rel" || continue
      chflags nouchg "$TARGET" 2>/dev/null && ok=$((ok+1)) || fail=$((fail+1))
    done < <(_list_tracked_uchg)
  fi
  _log "── file-flags: mode=unlock ok=$ok fail=$fail ──"
  (( fail == 0 )) || exit 1
  exit 0
fi

# MODE=apply : reconcile inventory <-> worktree 1:1
if [[ ! -f "$INVENTORY" ]]; then
  _log "🟡 apply-file-flags: no inventory; skip"
  exit 0
fi

ok=0; cleared=0; fail=0
# desired set
desired_file="$(mktemp)"
_list_inventory_paths | sort -u > "$desired_file"

# clear tracked uchg not in inventory
while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  if grep -Fxq -- "$rel" "$desired_file"; then
    continue
  fi
  TARGET=""
  _safe_target "$rel" || continue
  if chflags nouchg "$TARGET" 2>/dev/null; then
    _log "🟢 nouchg (not in inventory) $rel"
    cleared=$((cleared+1))
  else
    _log "🔴 nouchg failed $rel"
    fail=$((fail+1))
  fi
done < <(_list_tracked_uchg)

# apply inventory
while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  TARGET=""
  if ! _safe_target "$rel"; then
    _log "🟡 apply missing $rel"
    continue
  fi
  if chflags uchg "$TARGET" 2>/dev/null; then
    _log "🟢 uchg $rel"
    ok=$((ok+1))
  else
    _log "🔴 uchg failed $rel"
    fail=$((fail+1))
  fi
done < "$desired_file"

rm -f "$desired_file"
_log "── file-flags: mode=apply ok=$ok cleared=$cleared fail=$fail ──"
(( fail == 0 )) || exit 1
exit 0
