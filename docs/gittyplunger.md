# gittyplunger

Retroactive repair for oversized blobs buried in **unpushed** Git history.

## Vocabulary

- **clog**: an oversized blob reachable from local `HEAD` but not upstream
- **plunge**: rebuild the local-only range while holding clog paths at their
  upstream state
- **trap**: a durable local ref retaining the original tip and every removed
  object
- **drain**: the normal remote branch, which receives only pushable history

## Commands

```bash
gittyplunger scan [repo]
gittyplunger plunge [repo] --yes
```

`scan` reads tree metadata only. `plunge` never pushes.

Plain `gitty` invokes `plunge` automatically after fetch and before push when
the tracked upstream is an ancestor of `HEAD`.

## V1 boundary

Supported:

- one checked-out branch
- one linear `upstream..HEAD` range
- oversized blobs above `GITTY_MAX_FILE_BYTES` (default 100 MiB)
- clean worktree, or dirty paths limited to the detected clog paths
- unsigned local-only commits

Fail closed:

- published-history repair
- merge commits in the outgoing range
- signed commits
- staged or unmerged paths
- dirty paths unrelated to the clogs
- upstream not being an ancestor of `HEAD`

## Safety

Before moving the branch, `plunge` writes:

```text
refs/gitty/plunger/traps/<branch>/<utc>-<old-tip>
```

The rebuilt tip may differ from the old tip only at detected clog paths. Clog
bytes remain in the worktree as held-back local changes. A JSON receipt is
stored under `.git/gitty/plunger/`.

## Future legs

The v1 interfaces intentionally leave room for:

- merge-aware replay
- signed-commit resigning
- optional trap bundles and trap reaping
- LFS/chunk transformations
- alternate-remote drains
- remote-host size-policy adapters

Those are separate legs; they do not widen v1 implicitly.
