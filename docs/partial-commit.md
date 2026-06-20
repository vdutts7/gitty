# Partial commit and push

`gitty` tries to commit and push **as much as possible**. Paths that would block the remote are held back locally; everything else goes through.

This is built into `gitty` itself — not repo pre-commit/pre-push hooks.

## Flow

```
git add -A
  → scan staged paths for offenders
  → unstage offenders (held back locally)
  → git commit
  → git push -f
  → if push rejects a file → unstage it, recommit, retry
```

## What gets held back

| Offender | When | Reason shown |
|----------|------|----------------|
| Submodule gitlink (`160000`) | Pre-commit scan | `submodule (use gittyembedded)` |
| File over size limit | Pre-commit scan | `exceeds push size limit (N bytes)` |
| Push-rejected path | After failed push | `push rejected` |

Default size limit: **100 MiB** (GitHub hard limit). Override with `GITTY_MAX_FILE_BYTES`.

## Example

Four files modified; one is a 150 MiB blob and one is a submodule pointer:

```text
🟡 - Staging changes in /path/to/repo...
🔴 - huge.bin — held back (exceeds push size limit (500 bytes))
🟡 - 1 path(s) held back; proceeding with the rest
🟡 - Committing changes...
🟡 - Force pushing to remote...
── partial: commit/push ──
🟢 - ok.txt — committed and pushed
🟢 - fine.txt — committed and pushed
🔴 - huge.bin — not pushed (exceeds push size limit (500 bytes))
🟢 - partial success — 2 pushed, 1 held back
🟢 - Partial commit/push from /path/to/repo
```

The other two files commit and push normally. Held-back paths stay in your working tree unstaged.

## Push retry

If a file slips past pre-scan (or the host rejects it for another size-related reason), `gitty` parses the push error, holds that path back, soft-resets the last commit, recommits without it, and retries.

Retries: `GITTY_PUSH_RETRIES` (default `8`).

## Canonical test

Operator SSOT: `$CURTOOLS/test/gitty-partial-commit.smoke.sh`  
Downstream (this repo): `tests/partial-commit.smoke.sh`

```bash
npm run test:partial
# or
tests/partial-commit.smoke.sh
```

Expects: `huge.bin` held back (🔴), `ok.txt` + `fine.txt` pushed (🟢), partial success dashboard.

## Disable partial mode

Old all-or-nothing behavior:

```bash
GITTY_PARTIAL=0 gitty "message" /path/to/repo
```

## Submodule changes

`gitty` does **not** recurse into submodules. Submodule pointer changes in the parent are held back so the parent push is not blocked.

Use `gittyembedded` when you intend to commit submodule work first, then the parent.

## Large files with LFS

`gitty` does not configure Git LFS. For LFS-tracked patterns, use `gittylfs`.
