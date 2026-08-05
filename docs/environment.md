# Environment variables

Process env only by default. Optional: set `GITTY_ENV` to a file path to `source` before knobs apply. No implicit home/Cursor path.

## gitty

| Variable | Default | Effect |
|---|---|---|
| `GITTY_PARTIAL` | `1` | `0` = disable partial holdback (all-or-nothing) |
| `GITTY_MAX_FILE_BYTES` | `104857600` (100 MiB) | pre-commit size threshold for holdback |
| `GITTY_PUSH_RETRIES` | `8` | max push→holdback→recommit cycles |
| `GITTY_FORCE` | unset | `1` = bulldoze `push -f` (solo escape hatch) |
| `GITTY_NO_STALE_BASE_HEAL` | unset | `1` = skip stale-base autoheal |
| `GITTY_NO_UNION_AUTOINSTALL` | unset | `1` = skip ndjson-union auto-register |
| `README_CACHE_BUST` | unset | `1` = force-bump `?v=` on all README `<img src>` |
| `GITTY_ENV` | unset | if set to an existing file, `source` it (opt-in only) |

## gittysnap

| Variable | Default | Effect |
|---|---|---|
| `GITTYSNAP_PREFIX` | `snap` | snapshot branch namespace |
| `GITTYSNAP_REMOTE` | `origin` | remote name |
| `GITTYSNAP_NO_PUSH` | unset | `1` = local snapshots only |
| `GITTYSNAP_KEEP` | `10` | snapshots retained per branch on `reap` |

## Repo extension

| Path | When |
|---|---|
| `scripts/pre-gitty.sh` | runs before staging if executable |

## README cache bust

```bash
README_CACHE_BUST=1 gitty "README: cache-bust" /path/to/repo
```

Bundled: `bin/readme-cache-bust.sh` (+ `.py`).

## Partial commit examples

```bash
GITTY_MAX_FILE_BYTES=$((50 * 1024 * 1024)) gitty "assets" /path/to/repo
GITTY_PARTIAL=0 gitty "all or nothing" /path/to/repo
```

## Rebase snapshots

Before rebase (stale-base autoheal + additive sync), `gitty` wip-commits dirty state and creates `bak/<kind>-<utc>` so conflict recovery is a first-class ref. Never `--autostash`.
