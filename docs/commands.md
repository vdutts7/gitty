# Commands

All bins ship in the `@vd7/gitty` npm package under `bin/`.

## gitty

```bash
gitty [commit_message] [root_dir]
```

| Arg | Default | Notes |
|-----|---------|-------|
| `commit_message` | prompted; `-------[gitty] snapshotting repo state-------` if empty | Used for every commit in the chain |
| `root_dir` | prompted; `$PWD` if empty | **Must be absolute** |

### Chain

1. Optional `scripts/pre-gitty.sh` in repo root
2. README cache-bust (if README changed vs HEAD)
3. `git add -A` + partial holdback — see [partial-commit.md](partial-commit.md)
4. `git commit -m <msg>`
5. `git push -f` (or `-u origin HEAD` if no upstream)
6. Push retry loop on recoverable rejections

### Examples

```bash
gitty "fix bug" /Users/you/projects/my-repo
gitty "wip"                    # root = $PWD
gitty                          # prompts for message + root
```

## gittylfs

Same as `gitty`, plus local `git lfs install` and `git lfs track` for given patterns.

```bash
gittylfs [commit_message] [root_dir] [lfs_patterns...]
```

Default LFS patterns when none given:

`*.psd`, `*.sketch`, `*.ai`, `*.zip`, `*.tar.gz`, `*.7z`, `*.mp4`, `*.mov`, `*.wav`, `*.mp3`, `*.bin`, `*.pkl`, `*.h5`, `*.onnx`, `*.pt`

Requires `git-lfs` on PATH.

## gittyembedded

Commits dirty submodules first (recursive), then parent repo.

```bash
gittyembedded [commit_message] [root_dir]
```

Submodule push failures are warned but do not abort the parent chain.

## gittyhealth

Read-only repo report: branch, remote, status, stashes, recent commits, size, common issues.

```bash
gittyhealth [root_dir]
```

No commit or push.
