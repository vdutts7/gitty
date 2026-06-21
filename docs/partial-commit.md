# Partial commit (+ push)

- `gitty` tries to commit + push **as much as possible**
  - paths that would block remote are held back locally; everything else goes through.
- built into `gitty` itself- not repo `pre-commit`/`pre-push` hooks

## Flow

```bash
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

Default size limit: **100 MiB** (GitHub hard limit)
- Override with `GITTY_MAX_FILE_BYTES`

## Ex

4 files modified
- file1 is a 150 MiB blob
- file2 is a submodule pointer
- file3, file4 commit + push normally
  - held-back paths stay in your working tree unstaged

```bash
🟡 - Staging changes in /path/to/repo...
🔴 - huge.bin- held back (exceeds push size limit (500 bytes))
🟡 - 1 path(s) held back; proceeding with the rest
🟡 - Committing changes...
🟡 - Force pushing to remote...
── partial: commit/push ──
🟢 - ok.txt- committed and pushed
🟢 - fine.txt- committed and pushed
🔴 - huge.bin- not pushed (exceeds push size limit (500 bytes))
🟢 - partial success- 2 pushed, 1 held back
🟢 - Partial commit/push from /path/to/repo
```

## Push retry

- if a file slips past pre-scan (or the host rejects it for another size-related reason):
  - `gitty` parses push error → holds that path back → soft-resets the last commit → recommits without it → retries

Retries: `GITTY_PUSH_RETRIES` (default `8`).

## Canonical test

- run: `tests/partial-commit.smoke.sh`

```bash
npm run test:partial
# or
tests/partial-commit.smoke.sh
```

Expects: `huge.bin` held back (🔴), `ok.txt` + `fine.txt` pushed (🟢), partial success dashboard

## Disable partial mode

Old all-or-nothing behavior:

```bash
GITTY_PARTIAL=0 gitty "message" /path/to/repo
```

## Submodule changes

- `gitty` does **not** recurse into submodules
- submodule pointer changes in parent are held back so parent push is not blocked
- use `gittyembedded` when you intend to commit submodule work first → *then* parent

## Large files with LFS

- `gitty` does not configure Git LFS. For LFS-tracked patterns, use `gittylfs`
