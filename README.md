# gitty

Git add, commit, and force push in one command. Prompts for commit message and repo root when omitted.

## Install

```bash
npm i -g @vd7/gitty
```

## Usage

```bash
gitty [commit_mssg] [root_dir]
```

- **commit_mssg** — Commit message (prompted if omitted; default `..`).
- **root_dir** — Absolute path to git repo (prompted if omitted; default `$PWD`).

### Examples

```bash
gitty "fix bug" /path/to/repo
gitty                    # prompts for both
gitty "wip"              # message only; root defaults to $PWD
```

## Requirements

- **zsh**
- **git**

## Publish (maintainers)

Uses the same flow as other @vd7 npm tools. After committing and pushing:

```bash
npm-publish $GITTY
# or: npm-publish $GITTY --minor
```

See `@registry/npm-publish.json` and `/npm-publish` command.
