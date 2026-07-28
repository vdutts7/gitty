# gittyunion

Lossless union merge driver for append-only `.ndjson` / `.jsonl` ledgers.

```bash
gittyunion install [root_dir]
gittyunion verify [root_dir]
```

## Why a driver

Hooks cannot fix mid-merge conflicts. Driver runs during 3-way merge (also rebase / cherry-pick / stash pop).

## Guarantees

- keep every line from both sides; dedupe exact line identity
- base records keep order; new records sort by first of `ts` / `timestamp` / `issued_utc` / `created_at` / `seq` / `lamport`
- no order key → ours then theirs (still lossless)
- invalid JSON → refuse; leave conflict markers
- hash-chain re-link only when checksum excludes chain field

## Per clone

`.gitattributes` travels with the repo. `merge.ndjson-union.driver` lives in `.git/config` and is **not** cloned. Fresh clone without `install` falls back to conflicting default.

`gitty` auto-registers when `.gitattributes` already asks and the clone lacks the driver. Opt out: `GITTY_NO_UNION_AUTOINSTALL=1`.

Interim without driver:

```gitattributes
registry/**/*.ndjson merge=union
```
