<p align="center">
  <img src="https://raw.githubusercontent.com/vdutts7/squircle/main/webp/gitty.webp" alt="gitty icon" width="80" height="80" />
</p>

<div align="center">

<h1 align="center">gitty</h1>
<p align="center"><i><b>git add, commit, and push in one command</b></i></p>
<p align="center"><i><b>from any dir, for any repo</b></i></p>

[![GitHub][github-badge]][github-url]

</div>

<br/>

## ToC

<ol>
    <a href="#about">About</a><br/>
    <a href="#install">Install</a><br/>
    <a href="#usage">Usage</a><br/>
    <a href="#requirements">Requirements</a><br/>
    <a href="#contact">Contact</a>
</ol>

<br/>

## About

**Problem**

- agents often edit **lots of repos** on my machine **at once**
- I often bounce across multiple repos in a singular work session:
    - adding little features here and there (mini-tasks for agent to do in background unattended)
    - remembering todos, editing READMEs, other chores
    - brilliant ideas
    - tangents
- want **frequent checkpoints** because agents go rogue and overwrite important stuff- devastating if you had a brilliant idea (or agent nukes something that isn't already protected by [shelllock](https://github.com/vdutts7/shelllock-macos))
- need **several mini-rollbacks/snapshots**
but `cd`-ing into each repo and then running `git add` / `commit` / `push` over and over is **friction**

**Solution**

- **`gitty`** is one command: stage all → commit → **force-push**
- run from **any directory** for **any repo**- pass **repo root** or get prompted
    - no `cd` 
    - no `&&` chaining
- checkpoint **repo B** while in **repo A**
    - drop a quick save before/after an agent run- always have a rollback

**Summary**

- one command: `git add`, `git commit -m <msg>`, `git push -f`
- from any dir, for any repo (pass `path/to/repo/root` or get prompted)
- built for **agent-heavy** workflows- **fast checkpoints across many repos**

<br/>

## Install

```bash
npm i -g @vd7/gitty
```

<br/>

## Usage

```bash
gitty [commit_mssg] [root_dir]
```

| Arg | Description |
|-----|-------------|
| `commit_mssg` | **Commit message** (prompted if omitted; default `..`) |
| `root_dir` | **Repo root** to operate on (prompted if omitted; default `$PWD`)- checkpoint a repo without leaving your current dir |

### Examples

```bash
gitty "fix bug" /path/to/repo
gitty "checkpoint" $HOME/projects/other-repo   # save other-repo while elsewhere
gitty "wip"                                 # message only; root = $PWD
gitty                                      # prompts for both
```

- uses `git push -f`- overwrites remote
- use when you want a **checkpoint**, not shared history

### Demo

- make a tiny change
- run **`gitty`** with no args- answer prompts
- watch it stage, commit, and push

```bash
# make a change
touch "$HOME/projects/example-repo/test.txt"
```

```bash
# run (no args -> prompts)
gitty
Enter commit message [default: ..]: added XYZ feature
Enter root directory (absolute path) [default: /Users/you/projects/example-repo]:

# output (abbreviated)
Detecting changed files..
Staging changes...
[main b309cba] added XYZ feature
 create mode 100644 test.txt
- Force pushing to remote...
To github.com:vdutts7/example-repo.git
🟢 Successfully added, committed, and pushed changes from /Users/you/projects/example-repo
```

<br/>

## Requirements

- **zsh**
- **git**

<br/>

## Contact

<a href="https://vd7.io"><img src="data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSI5NyIgaGVpZ2h0PSI0MCIgdmlld0JveD0iMCAwIDk3IDQwIj48ZGVmcz48bGluZWFyR3JhZGllbnQgaWQ9ImNpcmNsZSIgeDE9IjAlIiB5MT0iMCUiIHgyPSIxMDAlIiB5Mj0iMCUiPjxzdG9wIG9mZnNldD0iMCUiIHN0eWxlPSJzdG9wLWNvbG9yOiM1ZGQzZmYiLz48c3RvcCBvZmZzZXQ9IjEwMCUiIHN0eWxlPSJzdG9wLWNvbG9yOiMyMmE4YzkiLz48L2xpbmVhckdyYWRpZW50PjwvZGVmcz48cmVjdCB4PSIwIiB5PSIwIiB3aWR0aD0iOTciIGhlaWdodD0iNDAiIHJ4PSIyMCIgcnk9IjIwIiBmaWxsPSIjMDAwIiBzdHJva2U9InJnYmEoMjU1LDI1NSwyNTUsMC4yKSIgc3Ryb2tlLXdpZHRoPSIxIi8+PGcgdHJhbnNmb3JtPSJ0cmFuc2xhdGUoMTMsIDApIj48Y2lyY2xlIGN4PSI5IiBjeT0iMjAiIHI9IjkiIGZpbGw9InVybCgjY2lyY2xlKSIvPjx0ZXh0IHg9IjI2IiB5PSIyNSIgZmlsbD0iI2ZmZiIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsJ1NGIE1vbm8nLCdGaXJhIENvZGUnLG1vbm9zcGFjZSIgZm9udC1zaXplPSIxMyIgZm9udC13ZWlnaHQ9IjUwMCI+dmQ3LmlvPC90ZXh0PjwvZz48L3N2Zz4=" alt="vd7.io" height="40" /></a> &nbsp; <a href="https://x.com/vdutts7"><img src="data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxMTgiIGhlaWdodD0iNDAiIHZpZXdCb3g9IjAgMCAxMTggNDAiPjxyZWN0IHg9IjAiIHk9IjAiIHdpZHRoPSIxMTgiIGhlaWdodD0iNDAiIHJ4PSIyMCIgcnk9IjIwIiBmaWxsPSIjMDAwIiBzdHJva2U9InJnYmEoMjU1LDI1NSwyNTUsMC4yKSIgc3Ryb2tlLXdpZHRoPSIxIi8+PGcgdHJhbnNmb3JtPSJ0cmFuc2xhdGUoMTMsIDApIj48ZyB0cmFuc2Zvcm09InRyYW5zbGF0ZSg5LCAyMCkgc2NhbGUoMC41NSkgdHJhbnNsYXRlKC0xMiwgLTEyKSI+PHBhdGggZD0iTTE4LjI0NCAyLjI1aDMuMzA4bC03LjIyNyA4LjI2IDguNTAyIDExLjI0SDE2LjE3bC01LjIxNC02LjgxN0w0Ljk5IDIxLjc1SDEuNjhsNy43My04LjgzNUwxLjI1NCAyLjI1SDguMDhsNC43MTMgNi4yMzF6bS0xLjE2MSAxNy41MmgxLjgzM0w3LjA4NCA0LjEyNkg1LjExN3oiIGZpbGw9IiNmZmYiLz48L2c+PHRleHQgeD0iMjYiIHk9IjI1IiBmaWxsPSIjZmZmIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJywnU0YgTW9ubycsJ0ZpcmEgQ29kZScsbW9ub3NwYWNlIiBmb250LXNpemU9IjEzIiBmb250LXdlaWdodD0iNTAwIj4vdmR1dHRzNzwvdGV4dD48L2c+PC9zdmc+" alt="/vdutts7" height="40" /></a>


[github-badge]: https://img.shields.io/badge/gitty-000000?style=for-the-badge&logo=github&logoColor=white
[github-url]: https://github.com/vdutts7/gitty
