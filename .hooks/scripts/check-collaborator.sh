#!/usr/bin/env bash
# .hooks/scripts/check-collaborator.sh
# git-platform-agnostic collaborator check- auto-detects GitHub/GitLab/Codeberg/Gitea/Bitbucket from remote URL.
# exit: 0=authorized, 1=blocked, 2=indeterminate (caller decides)

lc() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

USERNAME=$(git config user.name 2>/dev/null)
[[ -z "$USERNAME" ]] && exit 2

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"

# Load owner: .env → repo.config.json → remote URL
if [[ -z "$REPO_OWNER" && -f "$ROOT/.env" ]]; then
    REPO_OWNER=$(grep -E '^(REPO_OWNER|GITHUB_OWNER)=' "$ROOT/.env" | head -1 | cut -d'"' -f2)
    [[ -z "$REPO_TOKEN" ]] && REPO_TOKEN=$(grep -E '^(REPO_TOKEN|GITHUB_TOKEN)=' "$ROOT/.env" | head -1 | cut -d'"' -f2)
fi
if [[ -z "$REPO_OWNER" && -f "$ROOT/repo.config.json" ]] && command -v jq &>/dev/null; then
    REPO_OWNER=$(jq -r '.owner.username // .owner.github_username // empty' "$ROOT/repo.config.json" 2>/dev/null)
fi

# Owner match → pass
[[ -n "$REPO_OWNER" && "$(lc "$USERNAME")" == "$(lc "$REPO_OWNER")" ]] && exit 0

# Parse remote URL → forge host + owner/repo
REMOTE=$(git config --get remote.origin.url 2>/dev/null)
[[ -z "$REMOTE" ]] && exit 2

HOST="" SLUG=""
if [[ "$REMOTE" =~ ^git@([^:]+):(.+)$ ]]; then
    HOST="${BASH_REMATCH[1]}" SLUG="${BASH_REMATCH[2]%.git}"
elif [[ "$REMOTE" =~ ^https?://([^/]+)/(.+)$ ]]; then
    HOST="${BASH_REMATCH[1]}" SLUG="${BASH_REMATCH[2]%.git}"
fi
[[ -z "$HOST" || -z "$SLUG" ]] && exit 2

# Fallback: owner from URL
if [[ -z "$REPO_OWNER" ]]; then
    REPO_OWNER="${SLUG%%/*}"
    [[ "$(lc "$USERNAME")" == "$(lc "$REPO_OWNER")" ]] && exit 0
fi

command -v curl &>/dev/null || exit 2

AUTH=""
[[ -n "$REPO_TOKEN" ]] && AUTH="Authorization: token $REPO_TOKEN"

case "$HOST" in
    github.com)
        COLLABS=$(curl -sf -H "Accept: application/vnd.github+json" ${AUTH:+-H "$AUTH"} \
            "https://api.github.com/repos/$SLUG/collaborators" 2>/dev/null | jq -r '.[].login // empty' 2>/dev/null) ;;
    gitlab.com)
        [[ -n "$REPO_TOKEN" ]] && AUTH="PRIVATE-TOKEN: $REPO_TOKEN"
        COLLABS=$(curl -sf ${AUTH:+-H "$AUTH"} \
            "https://gitlab.com/api/v4/projects/$(echo "$SLUG" | sed 's|/|%2F|g')/members/all" 2>/dev/null | jq -r '.[].username // empty' 2>/dev/null) ;;
    codeberg.org|gitea.com|*.gitea.*)
        COLLABS=$(curl -sf ${AUTH:+-H "$AUTH"} \
            "https://$HOST/api/v1/repos/$SLUG/collaborators" 2>/dev/null | jq -r '.[].login // empty' 2>/dev/null) ;;
    bitbucket.org)
        [[ -n "$REPO_TOKEN" ]] && AUTH="Authorization: Bearer $REPO_TOKEN"
        COLLABS=$(curl -sf ${AUTH:+-H "$AUTH"} \
            "https://api.bitbucket.org/2.0/repositories/$SLUG/permissions-config/users" 2>/dev/null | jq -r '.values[].user.display_name // empty' 2>/dev/null) ;;
    *)
        COLLABS=$(curl -sf ${AUTH:+-H "$AUTH"} \
            "https://$HOST/api/v1/repos/$SLUG/collaborators" 2>/dev/null | jq -r '.[].login // empty' 2>/dev/null) ;;
esac

[[ -z "$COLLABS" ]] && exit 2
echo "$COLLABS" | grep -qix "$USERNAME" && exit 0
exit 1
