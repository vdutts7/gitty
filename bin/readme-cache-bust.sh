#!/usr/bin/env bash
# readme-cache-bust.sh — bump ?v= on README.md <img src> for GitHub render cache bust
# SSOT: $CURREGISTRY/git/readme-cache-bust/manifest.json
set -euo pipefail

REPO=""
README="README.md"
FORCE=0
IF_DIRTY=0
DRY_RUN=0
QUIET=0

usage() {
  cat >&2 <<'EOF'
usage: readme-cache-bust.sh [--repo DIR] [--readme FILE] [--force|--if-dirty] [--dry-run] [-q]

GitHub has no README render purge API. Bumping ?v= on <img src> forces a new camo fetch.

  --force      always rewrite v= (use when UI still shows stale images)
  --if-dirty   bump only if README.md differs from HEAD (default)
  --dry-run    print counts; do not write
  -q           quiet (exit 0; no stdout unless changed)

env:
  README_CACHE_BUST=1   same as --force
  README_CACHE_BUST=0   no-op exit 0

gitty: runs --if-dirty before git add; README_CACHE_BUST=1 → --force
hooks: opt-in gitty-family pre-commit (see githooks manifest)
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --readme) README="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --if-dirty) IF_DIRTY=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -q|--quiet) QUIET=1; shift ;;
    -h|--help) usage ;;
    *) REPO="$1"; shift ;;
  esac
done

[[ "${README_CACHE_BUST:-}" == 0 ]] && exit 0
[[ "${README_CACHE_BUST:-}" == 1 ]] && FORCE=1
[[ "$FORCE" -eq 0 && "$IF_DIRTY" -eq 0 ]] && IF_DIRTY=1

if [[ -z "$REPO" ]]; then
  REPO="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -n "$REPO" && -d "$REPO" ]] || { echo "[readme-cache-bust] skip (not a repo)" >&2; exit 0; }

TARGET="$REPO/$README"
[[ -f "$TARGET" ]] || { echo "[readme-cache-bust] skip (no $README)" >&2; exit 0; }

if [[ "$IF_DIRTY" -eq 1 && "$FORCE" -eq 0 ]]; then
  if git -C "$REPO" rev-parse --verify HEAD >/dev/null 2>&1; then
    if git -C "$REPO" diff --quiet HEAD -- "$README" 2>/dev/null; then
      echo "[readme-cache-bust] skip (README unchanged vs HEAD)" >&2
      exit 0
    fi
  fi
fi

V="$(date +%s)"
export TARGET V DRY_RUN
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT="$(python3 "$SCRIPT_DIR/readme-cache-bust.py")"

ACTION="${RESULT%%$'\t'*}"
N="${RESULT#*$'\t'}"

if [[ "$ACTION" == "unchanged" ]]; then
  echo "[readme-cache-bust] skip (no <img src> URLs to bump)" >&2
  exit 0
fi

TAG="[readme-cache-bust] bumped ${N} img src (v=${V})"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "${TAG} [dry-run]" >&2
else
  echo "$TAG" >&2
fi
[[ "$QUIET" -eq 0 ]] && echo "$TAG"
exit 0
