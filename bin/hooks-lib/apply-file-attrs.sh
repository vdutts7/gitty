#!/usr/bin/env bash
# apply-file-attrs — 1:1 sync: Darwin chflags (flags[]) + owner/group ↔ .gitty/file-attrs.json
#
# Inventory (v2): path + flags (uchg) + optional owner/group.
# Stolen pattern (etckeeper / metastore / git-store-meta): sidecar + pre-commit
# sync + post-checkout apply. No external binary. Darwin only for chflags.
#
#   --sync    worktree -> inventory (pre-commit)
#   --apply   inventory -> worktree (post-checkout/post-merge)
#   --unlock  clear uchg on inventory paths (gitty sync prelude)
#
# usage: apply-file-attrs.sh [--repo <path>] [--sync|--apply|--unlock] [--stage] [--quiet]
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
usage: apply-file-attrs [--repo <path>] [--sync|--apply|--unlock] [--stage] [--quiet]
  --sync    scan tracked uchg (+ live owner/group) -> .gitty/file-attrs.json
  --stage   with --sync: git add the inventory when it changed
  --apply   reconcile worktree to inventory 1:1 (chown then chflags)
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
[[ -n "$REPO" && -d "$REPO" ]] || { echo "🔴 apply-file-attrs: not a git repo" >&2; exit 1; }
REPO="$(cd "$REPO" && pwd -P)"

INVENTORY="$REPO/.gitty/file-attrs.json"
LEGACY_INVENTORY="$REPO/.gitty/file-flags.json"
# migrate legacy inventory name (uchg-only era)
if [[ ! -f "$INVENTORY" && -f "$LEGACY_INVENTORY" ]]; then
  mkdir -p "$REPO/.gitty"
  mv "$LEGACY_INVENTORY" "$INVENTORY"
fi
_log() { (( QUIET )) || echo "$1" >&2; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  _log "🟡 apply-file-attrs: non-Darwin; skip"
  exit 0
fi
command -v jq >/dev/null 2>&1 || { echo "🔴 apply-file-attrs: jq required" >&2; exit 1; }
command -v chflags >/dev/null 2>&1 || { echo "🔴 apply-file-attrs: chflags missing" >&2; exit 1; }

# --- helpers ---

_list_tracked_uchg() {
  local f rel
  while IFS= read -r -d '' f; do
    rel="${f#"$REPO"/}"
    [[ "$rel" == "$f" ]] && continue
    [[ "$rel" == ".gitty/file-attrs.json" ]] && continue
    case "$rel" in
      .git|/*|.|..|../*|*/..|*/../*) continue ;;
    esac
    if git -C "$REPO" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
      printf '%s\n' "$rel"
    fi
  done < <(find "$REPO" \( -path "$REPO/.git" -o -path "$REPO/.git/*" \) -prune -o \
    -flags +uchg \( -type f -o -type l \) -print0 2>/dev/null)
}

_list_inventory_paths() {
  [[ -f "$INVENTORY" ]] || return 0
  jq -r '(.entries // [])[] | select((.path|type)=="string" and (.path|length)>0) | .path' "$INVENTORY"
}

# stdout: one JSON object per line {path,flags,owner,group}
_entry_from_live() {
  local rel="$1" target="$REPO/$rel" owner group sf flags_json
  [[ -e "$target" || -L "$target" ]] || return 1
  owner="$(stat -f '%Su' "$target" 2>/dev/null || true)"
  group="$(stat -f '%Sg' "$target" 2>/dev/null || true)"
  sf="$(stat -f '%Sf' "$target" 2>/dev/null || true)"
  if [[ "$sf" == *uchg* ]]; then
    flags_json='["uchg"]'
  else
    flags_json='[]'
  fi
  jq -nc --arg p "$rel" --arg o "$owner" --arg g "$group" --argjson f "$flags_json" \
    '{path:$p, flags:$f, owner:$o, group:$g}'
}

_write_inventory_from_ndjson() {
  # stdin: NDJSON entries
  local tmp
  tmp="$(mktemp)"
  mkdir -p "$REPO/.gitty"
  jq -s '
    {
      version: 2,
      entries: (
        map(select((.path|type)=="string" and (.path|length)>0))
        | unique_by(.path)
        | sort_by(.path)
        | map(
            if ((.flags // []) | length) == 0 and ((.owner // "") | length) == 0 then
              empty
            else
              {
                path: .path,
                flags: (if ((.flags // []) | index("uchg")) then ["uchg"] else [] end),
                owner: (.owner // ""),
                group: (.group // "")
              }
              | if .owner == "" then del(.owner) else . end
              | if .group == "" then del(.group) else . end
              | if (.flags | length) == 0 then del(.flags) else . end
            end
          )
      )
    }
  ' > "$tmp"
  if [[ -f "$INVENTORY" ]] && cmp -s "$tmp" "$INVENTORY"; then
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$INVENTORY"
  return 0
}

_safe_target() {
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

# chown with escalate-if-needed (no new binary; sudo -n then sudo)
_chown_apply() {
  local target="$1" owner="$2" group="$3" spec
  [[ -n "$owner" ]] || return 0
  if [[ -n "$group" ]]; then
    spec="${owner}:${group}"
  else
    spec="$owner"
  fi
  local cur_o cur_g
  cur_o="$(stat -f '%Su' "$target")"
  cur_g="$(stat -f '%Sg' "$target")"
  if [[ -n "$group" ]]; then
    [[ "$cur_o" == "$owner" && "$cur_g" == "$group" ]] && return 0
  else
    [[ "$cur_o" == "$owner" ]] && return 0
  fi
  if chown "$spec" "$target" 2>/dev/null; then
    return 0
  fi
  if command -v sudo >/dev/null 2>&1; then
    if sudo -n chown "$spec" "$target" 2>/dev/null; then
      return 0
    fi
    if sudo chown "$spec" "$target" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

_nouchg() {
  chflags nouchg "$1" 2>/dev/null || sudo -n chflags nouchg "$1" 2>/dev/null || sudo chflags nouchg "$1" 2>/dev/null
}

_uchg() {
  chflags uchg "$1" 2>/dev/null || sudo -n chflags uchg "$1" 2>/dev/null || sudo chflags uchg "$1" 2>/dev/null
}

# --- modes ---

if [[ "$MODE" == "sync" ]]; then
  paths_file="$(mktemp)"
  ndjson="$(mktemp)"
  {
    _list_tracked_uchg
    _list_inventory_paths
  } | sort -u > "$paths_file"

  if [[ ! -s "$paths_file" && ! -f "$INVENTORY" ]]; then
    rm -f "$paths_file" "$ndjson"
    _log "🟡 file-attrs sync: no uchg tracked files; no inventory"
    exit 0
  fi

  : > "$ndjson"
  login_user="$(id -un)"
  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    entry="$(_entry_from_live "$rel" || true)"
    [[ -z "$entry" ]] && continue
    # Drop noise: no Darwin flags and owner is the login user (not a stub lock).
    # Keep if uchg OR owner differs from login (root stubs etc).
    keep="$(jq -r --arg u "$login_user"       '((.flags // []) | index("uchg") != null) or ((.owner // "") != "" and (.owner != $u))' <<<"$entry")"
    [[ "$keep" == "true" ]] || continue
    printf '%s
' "$entry" >> "$ndjson"
  done < "$paths_file"

  if [[ ! -s "$ndjson" && ! -f "$INVENTORY" ]]; then
    rm -f "$paths_file" "$ndjson"
    _log "🟡 file-attrs sync: nothing to inventory"
    exit 0
  fi

  if _write_inventory_from_ndjson < "$ndjson"; then
    n="$(jq '.entries|length' "$INVENTORY")"
    _log "🟢 file-attrs sync: inventory -> $n path(s)"
    if (( STAGE )); then
      git -C "$REPO" add -- ".gitty/file-attrs.json"
      _log "🟢 file-attrs sync: staged .gitty/file-attrs.json"
    fi
  else
    _log "🟡 file-attrs sync: inventory unchanged"
  fi
  rm -f "$paths_file" "$ndjson"
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
      if _nouchg "$TARGET"; then
        _log "🟢 unlock $rel"; ok=$((ok+1))
      else
        _log "🔴 unlock failed $rel"; fail=$((fail+1))
      fi
    done < <(_list_inventory_paths)
  else
    while IFS= read -r rel; do
      TARGET=""
      _safe_target "$rel" || continue
      _nouchg "$TARGET" && ok=$((ok+1)) || fail=$((fail+1))
    done < <(_list_tracked_uchg)
  fi
  _log "── file-attrs: mode=unlock ok=$ok fail=$fail ──"
  (( fail == 0 )) || exit 1
  exit 0
fi

# MODE=apply
if [[ ! -f "$INVENTORY" ]]; then
  _log "🟡 apply-file-attrs: no inventory; skip"
  exit 0
fi

ok=0; cleared=0; fail=0
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
  if _nouchg "$TARGET"; then
    _log "🟢 nouchg (not in inventory) $rel"
    cleared=$((cleared+1))
  else
    _log "🔴 nouchg failed $rel"
    fail=$((fail+1))
  fi
done < <(_list_tracked_uchg)

# apply each inventory entry: nouchg -> chown -> uchg
while IFS= read -r row; do
  [[ -z "$row" ]] && continue
  rel="$(jq -r '.path' <<<"$row")"
  owner="$(jq -r '.owner // empty' <<<"$row")"
  group="$(jq -r '.group // empty' <<<"$row")"
  want_uchg="$(jq -r '(.flags // []) | index("uchg") != null' <<<"$row")"

  TARGET=""
  if ! _safe_target "$rel"; then
    _log "🟡 apply missing $rel"
    continue
  fi

  entry_ok=1
  # unlock first so chown can proceed on immutable stubs
  if [[ "$want_uchg" == "true" ]] || [[ -n "$owner" ]]; then
    _nouchg "$TARGET" || true
  fi

  if [[ -n "$owner" ]]; then
    if _chown_apply "$TARGET" "$owner" "$group"; then
      _log "🟢 chown ${owner}${group:+:$group} $rel"
    else
      _log "🔴 chown failed $rel"
      entry_ok=0
    fi
  fi

  if [[ "$want_uchg" == "true" ]]; then
    if _uchg "$TARGET"; then
      _log "🟢 uchg $rel"
    else
      _log "🔴 uchg failed $rel"
      entry_ok=0
    fi
  fi

  if (( entry_ok )); then
    ok=$((ok+1))
  else
    fail=$((fail+1))
  fi
done < <(jq -c '(.entries // [])[]' "$INVENTORY")

rm -f "$desired_file"
_log "── file-attrs: mode=apply ok=$ok cleared=$cleared fail=$fail ──"
(( fail == 0 )) || exit 1
exit 0
