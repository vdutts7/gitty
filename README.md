<p align="center">
  <img src="https://raw.githubusercontent.com/vdutts7/squircle/main/webp/gitty.webp" alt="gitty icon" width="80" height="80" />
</p>

<div align="center">

<h1 align="center">gitty</h1>
<p align="center"><i><b>git add, commit, and push in one command</b></i></p>
<p align="center"><i><b>from any dir, for any repo</b></i></p>

[![GitHub][github-badge]][github-url]
[![npm][npm]][npm-url]

</div>

<br/>

## ToC

<ol>
    <a href="#about">About</a><br/>
    <a href="#install">Install</a><br/>
    <a href="#usage">Usage</a><br/>
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
- runs normal `git` commands- **does not bypass hooks**
- repo **pre-commit**/**commit-msg**/**pre-push** gates still fire
- if a repo enforces security hooks, **`gitty`** is subject to them

### Demo

- make a change
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

## Contact

<a href="https://vd7.io"><img src="https://res.cloudinary.com/ddyc1es5v/image/upload/v1773910810/readme-badges/readme-badge-vd7.png" alt="vd7.io" height="40" /></a> &nbsp; <a href="https://x.com/vdutts7"><img src="https://res.cloudinary.com/ddyc1es5v/image/upload/v1773910817/readme-badges/readme-badge-x.png" alt="/vdutts7" height="40" /></a>


[github-badge]: https://img.shields.io/badge/gitty-000000?style=for-the-badge&logo=github&logoColor=white
[github-url]: https://github.com/vdutts7/gitty
[npm]: https://img.shields.io/badge/npm-@vd7/gitty-CB3837?style=for-the-badge&logo=npm
[npm-url]: https://www.npmjs.com/package/@vd7/gitty