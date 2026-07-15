<p align="center">
  <img src="https://raw.githubusercontent.com/vdutts7/squircle/main/webp/gitty.webp?v=1782018495" alt="gitty icon" width="80" height="80" />
</p>

<div align="center">

<h1 align="center">gitty</h1>
<p align="center"><i><b>git add, commit, force push- one command</b></i></p>
<p align="center"><i><b>any dir, any repo</b></i></p>

[![GitHub][github-badge]][github-url]
[![npm][npm]][npm-url]

</div>

<br/>

## ToC

<ol>
    <a href="#about">About</a><br/>
    <a href="#install">Install</a><br/>
    <a href="#commands">Commands</a><br/>
    <a href="#usage">Usage</a><br/>
    <a href="#partial-commit">Partial commit</a><br/>
    <a href="#behavior">Behavior</a><br/>
    <a href="#docs">Docs</a><br/>
    <a href="#demo">Demo</a><br/>
    <a href="#contact">Contact</a>
</ol>

<br/>

## About

### Problem

1. Agents touch many repos per session- mini tasks, README chores, tangents, ideas
2. Need fast checkpoints before/after agent runs- rollback when something gets nuked
3. `cd` + `git add` + `commit` + `push` per repo = friction
4. One bad file (too large, submodule) blocks the whole checkpoint

### Solution

1. `gitty`: stage → commit → always `git push -f`
2. **Partial mode**: hold back offenders; push everything else
3. Any cwd- pass repo root or get prompted
4. Logmoji: 🟡 in progress, 🟢 success, 🔴 failure
5. Hook pass/fail dashboard when repo has `.hooks/`

### Summary

One chain: `git add -A` → hold back blockers → `git commit` → `git push -f`. Agent-heavy multi-repo checkpointing. npm tarball = `bin/` + README only.

<br/>

## Install

```bash
npm i -g @vd7/gitty
```

<br/>

## Commands

| Bin | Purpose |
|-----|---------|
| `gitty` | add, partial holdback, commit, force push |
| `gittylfs` | same + LFS track/install |
| `gittyembedded` | recurse submodules, then parent |
| `gittyhealth` | repo health report only |

Details: [docs/commands.md](docs/commands.md)

<br/>

## Usage

```bash
gitty [commit_mssg] [root_dir]
```

| Arg | Description |
|-----|-------------|
| `commit_mssg` | Commit message- prompted if omitted; default `-------[gitty] snapshotting repo state-------` |
| `root_dir` | Absolute repo root- prompted if omitted; default `$PWD` |

```bash
gitty "fix bug" /path/to/repo
gitty "checkpoint" $HOME/projects/other-repo
gitty "wip"          # root = $PWD
gitty                # prompts for both
```

<br/>

## Partial commit

When some paths cannot be pushed (oversized file, submodule pointer, remote rejection), `gitty` **holds them back locally** and commits/pushes the rest.

```text
🟡 - Held back: assets/huge.bin (exceeds push size limit)
🟡 - 1 path(s) held back locally; proceeding with the rest
...
🟢 - Committed and force pushed (1 path(s) held back)
```

- Default on (`GITTY_PARTIAL=1`)
- Submodules → use `gittyembedded`
- Large binaries → use `gittylfs` or fix paths manually

Full reference: [docs/partial-commit.md](docs/partial-commit.md)

<br/>

## Behavior

### Force push

Always `git push -f`. Checkpoint workflow- overwrites remote branch. Use when you own the remote.

### Clean tree

Nothing to commit → still force-pushes pending commits. Remote up to date → says so explicitly.

### Env

| Variable | Default | Effect |
|----------|---------|--------|
| `GITTY_PARTIAL` | `1` | `0` disables holdback |
| `GITTY_MAX_FILE_BYTES` | 100 MiB | Pre-commit size gate |
| `README_CACHE_BUST` | - | `1` bumps README img `?v=` |

More: [`docs/environment.md`](docs/environment.md) · Hooks: [`docs/hooks.md`](docs/hooks.md)

<br/>

## Docs

| Doc | Topic |
|-----|-------|
| [`docs/README.md`](docs/README.md) | Index |
| [`docs/partial-commit.md`](docs/partial-commit.md) | Holdback logic |
| [`docs/commands.md`](docs/commands.md) | All bins |
| [docs/environment.md](docs/environment.md) | Env vars |
| [docs/hooks.md](docs/hooks.md) | Repo hooks |

<br/>

## Demo

```bash
touch "$HOME/projects/example-repo/test.txt"
gitty "added test" "$HOME/projects/example-repo"
```

```text
🟡 - Staging changes in /Users/you/projects/example-repo...
🟡 - Committing changes...
[main abc1234] added test
🟡 - Force pushing to remote...
🟢 - Successfully committed and force pushed from /Users/you/projects/example-repo
```

<br/>

## Contact

<a href="https://vd7.io"><img src="https://res.cloudinary.com/ddyc1es5v/image/upload/v1773910810/readme-badges/readme-badge-vd7.png?v=1782018495" alt="vd7.io" height="40" /></a> &nbsp; <a href="https://x.com/vdutts7"><img src="https://res.cloudinary.com/ddyc1es5v/image/upload/v1773910817/readme-badges/readme-badge-x.png?v=1782018495" alt="/vdutts7" height="40" /></a>

[github-badge]: https://img.shields.io/badge/gitty-000000?style=for-the-badge&logo=github&logoColor=white
[github-url]: https://github.com/vdutts7/gitty
[npm]: https://img.shields.io/badge/npm-@vd7/gitty-CB3837?style=for-the-badge&logo=npm
[npm-url]: https://www.npmjs.com/package/@vd7/gitty
