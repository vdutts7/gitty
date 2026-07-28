# gittysnap

Snapshot-first sync for one dev on two machines. Content off-machine before any merge.

```bash
gittysnap              # sync (default)
gittysnap snap         # panic: snapshot + push only
gittysnap list
gittysnap reap         # drop snapshots already ancestors of HEAD
```

## Flow

1. commit local (durable; stash is a gamble)
2. push timestamped `snap/…` branch **before** integrate
3. `merge --no-ff` (never rebase)
4. conflict → abort → clean worktree (`rc=2`)

## Why not rebase

| | `pull --rebase --autostash` | `gittysnap` |
|---|---|---|
| exit | `0` (false success) | `2` on conflict |
| worktree | dirty / mid-op | clean |
| remote | often nothing new | both sides' work |

## Env

| Var | Default | Effect |
|---|---|---|
| `GITTYSNAP_PREFIX` | `snap` | branch namespace |
| `GITTYSNAP_REMOTE` | `origin` | remote |
| `GITTYSNAP_NO_PUSH=1` | unset | local snap only |
| `GITTYSNAP_KEEP` | `10` | retain on `reap` |

Plain `gitty` does not call this.
