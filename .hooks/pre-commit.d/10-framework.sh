#!/usr/bin/env bash
# gitty-owned framework checks (one unit; repos add their own drop-ins alongside).
set -eo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[[ "$(git config core.hooksPath 2>/dev/null)" != ".hooks" ]] && git config --local include.path ../.gitconfig
ENFORCE_CONFIG="$ROOT/.hooks/scripts/enforce-git-config.sh"
CHECK_EM_DASHES="$ROOT/.hooks/scripts/check-em-dashes.sh"
CHECK_PYTHON_VENV="$ROOT/.hooks/scripts/check-python-venv.sh"
DROP_EOF_NEWLINE="$ROOT/.hooks/scripts/drop-eof-newline-only.sh"
CHECK_README_IMAGES="$ROOT/.hooks/scripts/check-readme-images.sh"
staged_names=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)
if [[ -n "$staged_names" ]]; then
  hits=$(printf '%s\n' "$staged_names" | grep -E -- '-[0-9]{8}-[0-9]{6}' || true)
  if [[ -n "$hits" ]]; then
    echo "COMMIT BLOCKED - timestamped sibling backups (git already versions these)"
    printf '%s\n' "$hits"
    exit 1
  fi
fi
if [[ -x "$ENFORCE_CONFIG" ]]; then "$ENFORCE_CONFIG" "$ROOT" --quiet; fi
if [[ -x "$CHECK_EM_DASHES" ]]; then "$CHECK_EM_DASHES"; fi
if [[ -x "$CHECK_PYTHON_VENV" ]]; then "$CHECK_PYTHON_VENV"; fi
# clearmeta removed: conflicts with uchg/file-flags; xattr/mv fail under uchg
if [[ -x "$DROP_EOF_NEWLINE" ]]; then "$DROP_EOF_NEWLINE" || true; fi
if [[ -x "$CHECK_README_IMAGES" ]]; then "$CHECK_README_IMAGES"; fi
exit 0
