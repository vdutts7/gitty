# Environment variables

Process env only by default. Optional: set `GITTY_ENV` to a file path to `source` before knobs apply. No implicit home/Cursor path.

## gitty

| Variable | Default | Effect |
|----------|---------|--------|
| `GITTY_PARTIAL` | `1` | `0` = disable partial holdback (all-or-nothing) |
| `GITTY_MAX_FILE_BYTES` | `104857600` (100 MiB) | Pre-commit size threshold for holdback |
| `GITTY_PUSH_RETRIES` | `8` | Max push→holdback→recommit cycles |
| `README_CACHE_BUST` | unset | `1` = force-bump `?v=` on all README `<img src>` |
| `GITTY_ENV` | unset | If set to an existing file, `source` it (opt-in only) |

## Repo extension

| Path | When |
|------|------|
| `scripts/pre-gitty.sh` | Runs before staging if executable |

## README cache bust

Before `git add`, bumps cache-bust query param on README images when README differs from HEAD.

```bash
README_CACHE_BUST=1 gitty "README: cache-bust" /path/to/repo
```

Bundled: `bin/readme-cache-bust.sh` (+ `.py`).

## Partial commit examples

```bash
# Stricter size gate (50 MiB)
GITTY_MAX_FILE_BYTES=$((50 * 1024 * 1024)) gitty "assets" /path/to/repo

# Legacy: fail whole run if anything would be held back
GITTY_PARTIAL=0 gitty "all or nothing" /path/to/repo
```
