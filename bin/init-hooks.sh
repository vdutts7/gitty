#!/usr/bin/env bash
# gitty install-hooks - install canonical extension-aware runners in the target
# repo. Idempotent, no clobber. Optional --with copies consumer-safe scripts
# from bin/hooks-lib/ into .hooks lanes.
# file-flags always-on: pre-commit sync + post-checkout/post-merge apply.
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
  --with <names>    opt-in hooks-lib scripts (em-dashes,python-venv,
                    drop-eof-newline,health-check)
  --force           overwrite existing runners / file-flags wrappers
  note: file-flags always installs (1:1 uchg sync); no --with
HELP
      exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

[[ -d "$REPO/.git" || -f "$REPO/.git" ]] || { echo "not a git repo: $REPO" >&2; exit 1; }

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
lib_dir="$script_dir/hooks-lib"

mkdir -p "$REPO/.hooks/pre-commit.d" \
         "$REPO/.hooks/pre-push.d" \
         "$REPO/.hooks/post-checkout.d" \
         "$REPO/.hooks/post-merge.d" \
         "$REPO/.hooks/lib" \
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

_write_post_checkout() {
  cat > "$REPO/.hooks/post-checkout" <<'POST_CHECKOUT_EOF'
#!/usr/bin/env bash
# Canonical post-checkout runner (installed by gitty install-hooks).
set -e
ROOT="$(git rev-parse --show-toplevel)"; export ROOT
for s in "$ROOT"/.hooks/post-checkout.d/*; do [[ -x "$s" ]] && "$s" "$@"; done
exit 0
POST_CHECKOUT_EOF
  chmod +x "$REPO/.hooks/post-checkout"
}

_write_post_merge() {
  cat > "$REPO/.hooks/post-merge" <<'POST_MERGE_EOF'
#!/usr/bin/env bash
# Canonical post-merge runner (installed by gitty install-hooks).
set -e
ROOT="$(git rev-parse --show-toplevel)"; export ROOT
for s in "$ROOT"/.hooks/post-merge.d/*; do [[ -x "$s" ]] && "$s" "$@"; done
exit 0
POST_MERGE_EOF
  chmod +x "$REPO/.hooks/post-merge"
}

_write_if_allowed() {
  # $1=path $2=label; body on stdin
  local path="$1" label="$2"
  if [[ -f "$path" && "$FORCE" != "1" ]]; then
    echo "🟡 $label already exists; pass --force to overwrite" >&2
    return 0
  fi
  cat > "$path"
  chmod +x "$path"
  echo "🟢 wrote $label"
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

if [[ -f "$REPO/.hooks/post-checkout" && "$FORCE" != "1" ]]; then
  echo "🟡 .hooks/post-checkout already exists; pass --force to overwrite" >&2
else
  _write_post_checkout; echo "🟢 wrote .hooks/post-checkout"
fi

if [[ -f "$REPO/.hooks/post-merge" && "$FORCE" != "1" ]]; then
  echo "🟡 .hooks/post-merge already exists; pass --force to overwrite" >&2
else
  _write_post_merge; echo "🟢 wrote .hooks/post-merge"
fi

git -C "$REPO" config core.hooksPath .hooks
echo "🟢 git config core.hooksPath = .hooks"

[[ -d "$lib_dir" ]] || { echo "🔴 bin/hooks-lib/ not found" >&2; exit 1; }
_ff_src="$lib_dir/apply-file-flags.sh"
_ff_lib="$REPO/.hooks/lib/apply-file-flags.sh"

if [[ -f "$_ff_lib" && "$FORCE" != "1" ]]; then
  echo "🟡 ${_ff_lib#$REPO/} already exists; pass --force to overwrite" >&2
else
  cp "$_ff_src" "$_ff_lib" && chmod +x "$_ff_lib"
  echo "🟢 installed ${_ff_lib#$REPO/}"
fi

_ff_sync="$REPO/.hooks/pre-commit.d/05-file-flags-sync.sh"
_ff_co="$REPO/.hooks/post-checkout.d/10-file-flags.sh"
_ff_mg="$REPO/.hooks/post-merge.d/10-file-flags.sh"

_install_wrapper() {
  local path="$1" mode="$2" extra="${3:-}"
  if [[ -f "$path" && "$FORCE" != "1" ]]; then
    echo "🟡 ${path#$REPO/} already exists; pass --force to overwrite" >&2
    return 0
  fi
  cat > "$path" <<EOF
#!/usr/bin/env bash
# generated by gitty install-hooks (file-flags $mode)
set -euo pipefail
ROOT="\$(git rev-parse --show-toplevel)"
exec bash "\$ROOT/.hooks/lib/apply-file-flags.sh" --repo "\$ROOT" --$mode $extra "\$@"
EOF
  chmod +x "$path"
  echo "🟢 installed ${path#$REPO/}"
}

_install_wrapper "$_ff_sync" sync "--stage"
_install_wrapper "$_ff_co" apply
_install_wrapper "$_ff_mg" apply

# Clone chicken-egg: reconcile once (no-op without inventory).
bash "$_ff_src" --repo "$REPO" --apply --quiet || true

if [[ -n "$WITH" ]]; then
  IFS=',' read -ra items <<< "$WITH"
  n=20
  for name in "${items[@]}"; do
    case "$name" in
      file-flags)
        echo "🟡 file-flags already default; ignore --with file-flags" >&2
        continue
        ;;
      em-dashes)        src="$lib_dir/check-em-dashes.sh"     ; dst="$REPO/.hooks/pre-commit.d/$(printf '%02d' $n)-em-dashes.sh" ;;
      python-venv)      src="$lib_dir/check-python-venv.sh"   ; dst="$REPO/.hooks/pre-commit.d/$(printf '%02d' $n)-python-venv.sh" ;;
      clearmeta)
        echo "🔴 clearmeta removed: conflicts with uchg/file-flags; was not a valid staged-file hook" >&2
        exit 1
        ;;
      drop-eof-newline) src="$lib_dir/drop-eof-newline-only.sh"; dst="$REPO/.hooks/pre-commit.d/$(printf '%02d' $n)-drop-eof-newline.sh" ;;
      health-check)     src="$lib_dir/health-check.sh"        ; dst="$REPO/.hooks/pre-push.d/$(printf '%02d' $n)-health-check.sh" ;;
      *) echo "🔴 unknown --with name: $name (available: em-dashes,python-venv,drop-eof-newline,health-check)" >&2; exit 1 ;;
    esac
    cp "$src" "$dst" && chmod +x "$dst"
    echo "🟢 installed $name -> ${dst#$REPO/}"
    n=$((n + 10))
  done
fi

echo "🟢 install-hooks complete"
