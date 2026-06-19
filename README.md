<p align="center">
  <img src="https://raw.githubusercontent.com/vdutts7/squircle/main/webp/gitty.webp" alt="gitty icon" width="80" height="80" />
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
    <a href="#behavior">Behavior</a><br/>
    <a href="#hooks">Hooks</a><br/>
    <a href="#demo">Demo</a><br/>
    <a href="#contact">Contact</a>
</ol>

<br/>

## About

### Problem

1. agents touch many repos per session- mini tasks, README chores, tangents, ideas
2. need fast checkpoints before/after agent runs- rollback when something gets nuked
3. `cd` + `git add` + `commit` + `push` per repo = friction
4. offline push fail -> retry on clean tree -> remote never got last commit

### Solution

1. `gitty`: stage all -> commit -> always `git push -f`
2. any cwd- pass repo root or get prompted
3. checkpoint repo B while sitting in repo A
4. logmoji: 🟡 in progress, 🟢 success, 🔴 failure
5. hook pass/fail dashboard per step
6. clean tree -> still force pushes
7. remote up to date -> says so explicitly

### Summary

1. one chain: `git add .` -> `git commit -m <msg>` -> `git push -f`
2. agent-heavy multi-repo checkpointing
3. npm tarball = `bin/` + README only- no hooks bundled

<br/>

## Install

```bash
npm i -g @vd7/gitty
```

<br/>

## Commands

| Bin | Purpose |
|-----|---------|
| `gitty` | add, commit, force push |
| `gittylfs` | same + LFS-aware staging |
| `gittyembedded` | same + recurse into submodules first |
| `gittyhealth` | pre-push health check only |

<br/>

## Usage

```bash
gitty [commit_mssg] [root_dir]
```

| Arg | Description |
|-----|-------------|
| `commit_mssg` | commit message- prompted if omitted; default `..` |
| `root_dir` | absolute repo root- prompted if omitted; default `$PWD` |

### Examples

```bash
gitty "fix bug" /path/to/repo
gitty "checkpoint" $HOME/projects/other-repo
gitty "wip"          # root = $PWD
gitty                # prompts for both
```

<br/>

## Behavior

### Force push

1. always `git push -f`
2. checkpoint workflow- overwrites remote branch
3. use when you own remote and want snapshots

### Clean tree / retry

1. nothing to commit -> `🟢 - Nothing to commit (working tree clean)`
2. still force pushes after that
3. remote already synced -> `🟢 - Nothing to push (remote up-to-date)`
4. both -> `🟢 - Nothing to commit or push - remote synced`

### Status output

```text
🟡 - Staging all changes in /path/to/repo...
🟡 - Committing changes...
🟢 - Nothing to commit (working tree clean)
── hooks: pre-commit ──
🟢 - skipped (nothing to commit)
🟡 - Force pushing to remote...
🟢 - Nothing to push (remote up-to-date)
── hooks: pre-push ──
🟢 - shelllock - passed
🟢 - health-check - passed
🟢 - Nothing to commit or push - remote synced
```

1. hook dashboard lists each gate 🟢/🔴 when hooks run
2. hook blocks -> 🔴 names which hook failed
3. commit/push stops on hook fail

### Optional env

1. `GITTY_ENV` or `$HOME/scripts/.env` loaded if present
2. no-op for most users
3. repo `scripts/pre-gitty.sh` runs before `git add` if executable

<br/>

## Hooks

### Npm install only

1. plain `git` commands- no hooks ship in package
2. no shelllock
3. no health-check unless you add them

### Repo with `.hooks/`

1. e.g. [gh-template](https://github.com/vdutts7/gh-template)
2. `gitty` does not bypass hooks- no `--no-verify`
3. pre-commit on commit
4. pre-push on push
5. [shelllock](https://github.com/vdutts7/shelllock-macos) opt-in only
6. needs `shelllock` on PATH
7. needs repo pre-push hook wired
8. not default for npm-only users

<br/>

## Demo

```bash
touch "$HOME/projects/example-repo/test.txt"
gitty "added test" "$HOME/projects/example-repo"
```

```text
🟡 - Staging all changes in /Users/you/projects/example-repo...
🟡 - Committing changes...
[main abc1234] added test
 1 file changed, 0 insertions(+), 0 deletions(-)
 create mode 100644 test.txt
── hooks: pre-commit ──
🟢 - clearmeta - passed
🟢 - check-collaborator - passed
🟡 - Force pushing to remote...
To github.com:you/example-repo.git
   def5678..abc1234  main -> main
── hooks: pre-push ──
🟢 - health-check - all checks passed
🟢 - Successfully committed and force pushed from /Users/you/projects/example-repo
```

<br/>

## Contact

1. [vd7.io](https://vd7.io)
2. [@vdutts7 on X](https://x.com/vdutts7)


[github-badge]: https://img.shields.io/badge/gitty-000000?style=for-the-badge&logo=github&logoColor=white
[github-url]: https://github.com/vdutts7/gitty
[npm]: https://img.shields.io/badge/npm-@vd7/gitty-CB3837?style=for-the-badge&logo=npm
[npm-url]: https://www.npmjs.com/package/@vd7/gitty
