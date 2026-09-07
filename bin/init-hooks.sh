#!/usr/bin/env bash
# gitty install-hooks - install canonical extension-aware runners in the target
# repo. Idempotent, no clobber. Optional --with copies consumer-safe scripts
# from bin/hooks-lib/ into .hooks/pre-commit.d/.
set -euo pipefail

REPO="${PWD}"
WITH=""
FORCE=0
while (( $# )); do
  case "$1" in
    --repo)  REPO="$2"; shift 2 ;;
    --with)  WITH="$2"; shift 2 ;;
    --force) FORCE=1;   shift ;;
    -h|--help)
      cat >&2 <<'HELP'
usage: gitty install-hooks [--repo <path>] [--with <name,name,...>] [--force]
  --repo <path>     target repo root (default: PWD)
  --with <names>    comma-separated hooks-lib scripts to install into
                    .hooks/pre-commit.d/ (e.g. em-dashes,clearmeta,python-venv,
                    drop-eof-newline,health-check)
  --force           overwrite existing .hooks/pre-commit or .hooks/pre-push
HELP
      exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

[[ -d "$REPO/.git" || -f "$REPO/.git" ]] || { echo "not a git repo: $REPO" >&2; exit 1; }

mkdir -p "$REPO/.hooks/pre-commit.d" \
         "$REPO/.hooks/pre-push.d" \
         "$REPO/.hooks/local.d/cosmetic" \
         "$REPO/.hooks/local.d/gates" \
         "$REPO/.hooks/local.d/pre-push"

_write_pre_commit() {
  cat > "$REPO/.hooks/pre-commit" <<'PRE_COMMIT_EOF'
#!/usr/bin/env bash
# Canonical extension-aware runner (installed by gitty install-hooks).
set -e
ROOT="$(git rev-parse --show-toplevel)"; export ROOT
for s in "$ROOT"/.hooks/pre-commit.d/*;     do [[ -x "$s" ]] && "$s" "$@"; done
for s in "$ROOT"/.hooks/local.d/cosmetic/*; do [[ -x "$s" ]] && { "$s" "$@" || true; }; done
for s in "$ROOT"/.hooks/local.d/gates/*;    do [[ -x "$s" ]] && "$s" "$@"; done
exit 0
PRE_COMMIT_EOF
  chmod +x "$REPO/.hooks/pre-commit"
}

_write_pre_push() {
  cat > "$REPO/.hooks/pre-push" <<'PRE_PUSH_EOF'
#!/usr/bin/env bash
# Canonical extension-aware runner (installed by gitty install-hooks).
set -e
ROOT="$(git rev-parse --show-toplevel)"; export ROOT
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
cat > "$tmp"
for s in "$ROOT"/.hooks/pre-push.d/*;       do [[ -x "$s" ]] && "$s" "$@" < "$tmp"; done
for s in "$ROOT"/.hooks/local.d/pre-push/*; do [[ -x "$s" ]] && "$s" "$@" < "$tmp"; done
exit 0
PRE_PUSH_EOF
  chmod +x "$REPO/.hooks/pre-push"
}

if [[ -f "$REPO/.hooks/pre-commit" && "$FORCE" != "1" ]]; then
  echo "🟡 .hooks/pre-commit already exists; pass --force to overwrite" >&2
else
  _write_pre_commit; echo "🟢 wrote .hooks/pre-commit"
fi

if [[ -f "$REPO/.hooks/pre-push" && "$FORCE" != "1" ]]; then
  echo "🟡 .hooks/pre-push already exists; pass --force to overwrite" >&2
else
  _write_pre_push; echo "🟢 wrote .hooks/pre-push"
fi

git -C "$REPO" config core.hooksPath .hooks
echo "🟢 git config core.hooksPath = .hooks"

if [[ -n "$WITH" ]]; then
  script_dir="$(cd "$(dirname "$0")" && pwd -P)"
  lib_dir="$script_dir/hooks-lib"
  [[ -d "$lib_dir" ]] || { echo "🔴 bin/hooks-lib/ not found" >&2; exit 1; }
  IFS=',' read -ra items <<< "$WITH"
  n=10
  for name in "${items[@]}"; do
    case "$name" in
      em-dashes)        src="$lib_dir/check-em-dashes.sh"     ; dst="$REPO/.hooks/pre-commit.d/$(printf '%02d' $n)-em-dashes.sh" ;;
      python-venv)      src="$lib_dir/check-python-venv.sh"   ; dst="$REPO/.hooks/pre-commit.d/$(printf '%02d' $n)-python-venv.sh" ;;
      clearmeta)        src="$lib_dir/clearmeta.sh"           ; dst="$REPO/.hooks/pre-commit.d/$(printf '%02d' $n)-clearmeta.sh" ;;
      drop-eof-newline) src="$lib_dir/drop-eof-newline-only.sh"; dst="$REPO/.hooks/pre-commit.d/$(printf '%02d' $n)-drop-eof-newline.sh" ;;
      health-check)     src="$lib_dir/health-check.sh"        ; dst="$REPO/.hooks/pre-push.d/$(printf '%02d' $n)-health-check.sh" ;;
      *) echo "🔴 unknown --with name: $name (available: em-dashes,python-venv,clearmeta,drop-eof-newline,health-check)" >&2; exit 1 ;;
    esac
    cp "$src" "$dst" && chmod +x "$dst"
    echo "🟢 installed $name -> ${dst#$REPO/}"
    n=$((n + 10))
  done
fi

echo "🟢 install-hooks complete"
