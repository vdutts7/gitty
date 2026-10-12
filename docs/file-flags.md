# File flags (uchg 1:1 sync)

Git tracks content + the executable bit only. macOS `chflags uchg` does not
survive clone/checkout. gitty keeps a tracked inventory and reconciles both ways.

## Model

| direction | when | behavior |
|-----------|------|----------|
| worktree -> inventory | `pre-commit` (`--sync --stage`) | scan tracked `uchg` files; rewrite `.gitty/file-flags.json`; stage it |
| inventory -> worktree | `post-checkout` / `post-merge` / `gitty` sync (`--apply`) | set `uchg` on listed paths; clear `uchg` on tracked paths not listed |

1:1: add `uchg` locally -> next commit updates the list. Drop `uchg` locally ->
next commit removes it from the list. Pull/checkout on another machine restores
exactly that set.

## Always-on with `gitty install-hooks`

No `--with`. Installs:

- `.hooks/lib/apply-file-flags.sh`
- `pre-commit.d/05-file-flags-sync.sh` (`--sync --stage`)
- `post-checkout.d/10-file-flags.sh` + `post-merge.d/10-file-flags.sh` (`--apply`)

Missing inventory + no local `uchg` -> no-op. Non-Darwin -> no-op.

## Commands

```sh
gitty install-hooks                 # once per clone
gitty apply-flags                   # reconcile now (--apply)
gitty apply-flags --sync --stage    # scan uchg -> inventory + git add
gitty apply-flags --unlock          # clear inventory paths (gitty sync prelude)
chflags uchg path/to/file           # mark; next commit syncs into inventory
chflags nouchg path/to/file         # unmark; next commit drops from inventory
```

## Mid-repo / new machine

Commit count irrelevant. No history rewrite.

1. `npm i -g @vd7/gitty` + `gitty install-hooks` in the repo
2. `chflags uchg` on paths you care about (or they already have it)
3. next `git commit` / `gitty` commit runs sync and lands `.gitty/file-flags.json`
4. other clones: `gitty install-hooks` (or pull + hooks already present) -> apply reconciles

## Not stub-telemetry

Stub-telemetry bulldozes `$HOME` cache paths into empty uchg stubs from its own
`targets.json` and self-heals on login. gitty only syncs **tracked repo paths**.

## vs clearmeta

`clearmeta` (xattr strip / byte-rewrite) is removed from `@vd7/gitty` hooks-lib.
Under `uchg`, `xattr -c` and `mv` return Operation not permitted, so strip could
not run on locked paths anyway. Keep file-flags; do metadata scrub outside the
immutable set if needed.
