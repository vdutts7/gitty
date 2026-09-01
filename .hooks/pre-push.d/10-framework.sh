#!/usr/bin/env bash
# gitty-owned framework checks for pre-push.
set -eo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[[ "$(git config core.hooksPath 2>/dev/null)" != ".hooks" ]] && git config --local include.path ../.gitconfig
ENFORCE="$ROOT/.hooks/scripts/enforce-git-config.sh"
[[ -x "$ENFORCE" ]] && "$ENFORCE" "$ROOT" --quiet
VERIFY_AUTHORS="$ROOT/.hooks/scripts/verify-commit-authors.sh"
[[ -x "$VERIFY_AUTHORS" ]] && "$VERIFY_AUTHORS" "$ROOT"
HEALTH="$ROOT/.hooks/scripts/health-check.sh"
[[ -x "$HEALTH" ]] && "$HEALTH"
exit 0
