# Commands

All bins ship in `@vd7/gitty` under `bin/`.

## gitty

```bash
gitty [commit_message] [root_dir]
```

| Arg | Default | Notes |
|---|---|---|
| `commit_message` | prompted; `-------[gitty] snapshotting repo state-------` if empty | every commit in the chain |
| `root_dir` | prompted; `$PWD` if empty | must be absolute |

### Chain

1. optional `scripts/pre-gitty.sh`
2. auto-register `ndjson-union` if `.gitattributes` asks and clone lacks driver
3. README cache-bust (when README differs from HEAD)
4. `git add -A` + partial holdback — [partial-commit.md](partial-commit.md)
5. `git commit`
6. additive sync (fetch + rebase/`--force-with-lease`); `GITTY_FORCE=1` → `push -f`

### Examples

```bash
gitty "fix bug" /Users/you/projects/my-repo
gitty "wip"                    # root = $PWD
gitty                          # prompts
```

## gittylfs

Same as `gitty`, plus local `git lfs install` / `git lfs track`.

```bash
gittylfs [commit_message] [root_dir] [lfs_patterns...]
```

Default patterns when none given: `*.psd`, `*.sketch`, `*.ai`, `*.zip`, `*.tar.gz`, `*.7z`, `*.mp4`, `*.mov`, `*.wav`, `*.mp3`, `*.bin`, `*.pkl`, `*.h5`, `*.onnx`, `*.pt`

Requires `git-lfs` on PATH.

## gittyembedded

Dirty submodules first (recursive), then parent.

```bash
gittyembedded [commit_message] [root_dir]
```

Submodule push failures warn; parent chain continues.

## gittyhealth

Read-only report: branch, remote, status, stashes (promote-to-`bak/` hint when non-empty), size, mid-rebase/merge, unpushed-only-local, ledger merge attrs.

```bash
gittyhealth [root_dir]
```

No commit or push.

## gittysnap

Snapshot-first sync. See [gittysnap.md](gittysnap.md).

```bash
gittysnap [sync|snap|list|reap] [root_dir]
```

Not invoked by plain `gitty`.

## gittyunion

NDJSON/JSONL union merge driver. See [gittyunion.md](gittyunion.md).

```bash
gittyunion install [root_dir]
gittyunion verify [root_dir]
```

`.gitattributes` is cloned; `merge.*.driver` in `.git/config` is not — run `install` per clone.
